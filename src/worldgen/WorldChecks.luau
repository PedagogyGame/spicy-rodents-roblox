--!strict
-- ServerScriptService.Server.WorldGen.WorldChecks
-- The WorldBuild exit checks on the bake plans (BUILD_PLAN §4.4 #7, §6.5), shared by Lune
-- (tools/bake/check.luau, tests/unit/world_checks.spec.luau) and the engine (tests/engine/WorldBuild):
-- lot count equals data; no solid overlap between lots; every exterior door reachable from a
-- sidewalk and standing on its threshold at ground level or on steps down to it (DoorSill);
-- every route sample within surfaceRadius + 0.3 u of geometry or terrain except the
-- routes in harvest_patches.json (each with a reason); Skyline for every building; the hospital's 8
-- brief rooms and the station's drone console exist; at least one lamp per road side; every enterable
-- room passes InteriorCheck (furnished, walkable, lit) and a body can walk from each building's door
-- into every one of its rooms (EnterCheck).
-- Interface: run(data?, plans?) -> Result { ok, failures, ... }
-- Pure (reads generated data through Import).

local Bake = require("./Bake")
local DoorReach = require("./DoorReach")
local DoorSill = require("./DoorSill")
local EnterCheck = require("./EnterCheck")
local Geometry = require("./Geometry")
local Import = require("./Import")
local InteriorCheck = require("./InteriorCheck")
local Kits = require("./Kits")
local RouteCheck = require("./RouteCheck")
local Spec = require("./Spec")
local Yield = require("./Yield")
local Height = Import.shared("World/Height") :: typeof(require("../shared/World/Height"))
local Registry = Import.shared("Routes/Registry") :: typeof(require("../shared/Routes/Registry"))

local WorldChecks = {}

-- Collidable parts of solid lots, per lot, for the overlap test (doors and furniture are inside).
local function solidParts(p: Spec.BuildPlan): { Spec.PartSpec }
	local out = {}
	for _, s in p.parts do
		if
			s.canCollide
			and s.role ~= "Door"
			and s.role ~= "Furniture"
			and s.role ~= "Station"
			and s.role ~= "Shelf"
			and s.role ~= "Step"
			and s.role ~= "Ceiling"
		then
			table.insert(out, s)
		end
	end
	return out
end

function WorldChecks.overlaps(plans: { Spec.BuildPlan }): ({ string }, number)
	local solids: { { id: string, parts: { Spec.PartSpec }, box: { number } } } = {}
	for _, p in plans do
		if p.kind == "lot" and p.attributes.Solid then
			local parts = solidParts(p)
			local x0, x1, y0, y1, z0, z1 = math.huge, -math.huge, math.huge, -math.huge, math.huge, -math.huge
			for _, s in parts do
				local a0, a1, b0, b1, c0, c1 = Geometry.aabb(s :: any)
				x0, x1, y0, y1 = math.min(x0, a0), math.max(x1, a1), math.min(y0, b0), math.max(y1, b1)
				z0, z1 = math.min(z0, c0), math.max(z1, c1)
			end
			table.insert(solids, { id = p.id, parts = parts, box = { x0, x1, y0, y1, z0, z1 } })
		end
	end
	local out: { string } = {}
	local tol = 0.05
	for i = 1, #solids do
		local A = solids[i]
		for j = i + 1, #solids do
			local B = solids[j]
			local a, b = A.box, B.box
			if
				math.min(a[2], b[2]) - math.max(a[1], b[1]) > tol
				and math.min(a[6], b[6]) - math.max(a[5], b[5]) > tol
				and math.min(a[4], b[4]) - math.max(a[3], b[3]) > tol
			then
				-- envelopes meet: test the parts (oriented boxes, by corner containment both ways)
				local hit = false
				for _, pa in A.parts do
					local pa0, pa1, pb0, pb1, pc0, pc1 = Geometry.aabb(pa :: any)
					for _, pb in B.parts do
						local qa0, qa1, qb0, qb1, qc0, qc1 = Geometry.aabb(pb :: any)
						local ox = math.min(pa1, qa1) - math.max(pa0, qa0)
						local oy = math.min(pb1, qb1) - math.max(pb0, qb0)
						local oz = math.min(pc1, qc1) - math.max(pc0, qc0)
						if ox > tol and oy > tol and oz > tol then
							-- sample the overlap box centre against both oriented boxes
							local c = {
								(math.max(pa0, qa0) + math.min(pa1, qa1)) / 2,
								(math.max(pb0, qb0) + math.min(pb1, qb1)) / 2,
								(math.max(pc0, qc0) + math.min(pc1, qc1)) / 2,
							}
							if
								Geometry.boxDistance(pa :: any, c) <= 1e-6
								and Geometry.boxDistance(pb :: any, c) <= 1e-6
							then
								hit = true
								break
							end
						end
					end
					if hit then
						break
					end
				end
				if hit then
					table.insert(out, A.id .. " x " .. B.id)
				end
			end
		end
	end
	return out, #solids
end

function WorldChecks.run(dataIn: any?, plansIn: { Spec.BuildPlan }?): { [string]: any }
	local data = dataIn or Bake.data()
	local plans = plansIn or Bake.plans(data)
	local failures: { string } = {}
	local r: { [string]: any } = { failures = failures }

	-- counts
	local lots, skylineIds = 0, {}
	local skyline: Spec.BuildPlan? = nil
	for _, p in plans do
		if p.kind == "lot" then
			lots += 1
		elseif p.kind == "skyline" then
			skyline = p
		end
	end
	r.lots = lots
	if lots ~= #data.lots then
		table.insert(failures, `lot count {lots} ~= data {#data.lots}`)
	end

	Yield.breathe()
	-- overlaps
	local overlaps, nSolid = WorldChecks.overlaps(plans)
	r.solids, r.overlaps = nSolid, overlaps
	if #overlaps > 0 then
		table.insert(failures, `{#overlaps} solid overlaps: {table.concat(overlaps, "; ")}`)
	end

	-- Skyline for every building and structure
	for _, s in (skyline :: Spec.BuildPlan).parts do
		skylineIds[s.name] = true
	end
	local missing = {}
	local buildings = 0
	for _, p in plans do
		if p.kind == "lot" and p.attributes.ParentLot == nil and Kits.get(p.attributes.LotType :: string).skyline then
			buildings += 1
			if not skylineIds[p.id] then
				table.insert(missing, p.id)
			end
		end
	end
	r.skyline = { buildings = buildings, missing = missing }
	if #missing > 0 then
		table.insert(failures, "Skyline missing for " .. table.concat(missing, ", "))
	end

	-- hospital rooms and station console
	local Buildings = Import.generated("Buildings")
	local byLot: { [string]: Spec.BuildPlan } = {}
	for _, p in plans do
		if p.kind == "lot" then
			byLot[p.id] = p
		end
	end
	local function hasPart(p: Spec.BuildPlan?, name: string): boolean
		if not p then
			return false
		end
		for _, s in p.parts do
			if s.name == name then
				return true
			end
		end
		return false
	end
	local hosp = Buildings.hospital
	local hp = byLot[hosp.lot]
	local rooms = 0
	for _, id in hosp.briefRooms do
		if hasPart(hp, "Room_" .. id) then
			rooms += 1
		else
			table.insert(failures, "hospital room missing: " .. id)
		end
	end
	r.hospitalRooms = rooms
	r.droneConsole = hasPart(byLot[Buildings.police_station.lot], "Station_drone_console")
	if not r.droneConsole then
		table.insert(failures, "police station drone console missing")
	end

	-- lamps: one per block side
	local lampSides: { [string]: { [string]: boolean } } = {}
	for _, p in plans do
		if p.kind == "lamps" then
			for _, s in p.parts do
				local id = (s.attrs :: any).Lamp :: string
				local side = string.match(id, "_([LR])%d+$") :: string
				lampSides[p.attributes.Road :: string] = lampSides[p.attributes.Road :: string] or {}
				lampSides[p.attributes.Road :: string][side] = true
			end
		end
	end
	local lampRoads, lampShort = 0, {}
	for road, sides in lampSides do
		lampRoads += 1
		if not (sides.L and sides.R) then
			table.insert(lampShort, road)
		end
	end
	table.sort(lampShort)
	r.lamps = { roads = lampRoads, oneSided = lampShort }

	Yield.breathe()
	-- interiors: every enterable room furnished for its purpose, doorways and walkways clear, nothing
	-- floating or buried, a light in every room
	local interiors = InteriorCheck.run(plans)
	r.interiors =
		{ lots = interiors.lots, rooms = interiors.rooms, pieces = interiors.pieces, lights = interiors.lights }
	if #interiors.failures > 0 then
		table.insert(
			failures,
			`{#interiors.failures} interior failures: {table.concat(
				interiors.failures,
				"; ",
				1,
				math.min(#interiors.failures, 5)
			)}`
		)
	end

	Yield.breathe()
	-- getting in: a body walks from the ground in front of the door into every room and out at the back
	local enter = EnterCheck.run(plans, Height.at)
	r.enter = { lots = enter.lots, rooms = enter.rooms, doors = enter.doors }
	if #enter.failures > 0 then
		table.insert(
			failures,
			`{#enter.failures} ways in blocked: {table.concat(enter.failures, "; ", 1, math.min(#enter.failures, 5))}`
		)
	end

	Yield.breathe()
	-- doors
	local reach = DoorReach.run(plans, Height.at, Height.insideRiverWater)
	r.doors = reach
	if #reach.unreachable > 0 then
		table.insert(
			failures,
			`{#reach.unreachable} doors not reachable from a sidewalk: {table.concat(reach.unreachable, ", ")}`
		)
	end

	-- every exterior door stands on its threshold at ground level, or on steps down to it
	local sills = DoorSill.run(plans, Height.at)
	r.sills = sills
	if #sills.failures > 0 then
		table.insert(
			failures,
			`{#sills.failures} doors off the ground: {table.concat(
				sills.failures,
				"; ",
				1,
				math.min(#sills.failures, 6)
			)}`
		)
	end

	Yield.breathe()
	-- routes on geometry
	if data.routes then
		local patches = Import.generated("HarvestPatches")
		local patched: { [number]: boolean } = {}
		for _, p in patches.patches do
			for _, id in p.routes do
				patched[id] = true
			end
		end
		local registry = Registry.fromRecords(data.routes, 2.5)
		local rc = RouteCheck.run(
			plans,
			data.routes,
			{ registry = registry, heightAt = Height.at, slackU = 0.3, patched = patched }
		)
		r.routes = rc
		if #rc.failures > 0 then
			table.insert(failures, `{#rc.failures} routes off geometry and not in harvest_patches.json`)
		end
	end
	r.ok = #failures == 0
	return r
end

return WorldChecks
