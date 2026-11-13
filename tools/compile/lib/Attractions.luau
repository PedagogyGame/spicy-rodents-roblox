--!strict
-- tools/compile: data/attractions.json -> generated/Attractions.luau (brief v2 §13a; BUILD_PLAN §3.17, W3c #15).
-- Attraction buildings that are baked on their own (tools/bake/attractions.luau -> build/Attractions.rbxm ->
-- Workspace.Attractions). The file is authored in STUDS. Each building's routes (the bowling alley's
-- ball-return vents and tunnels) are turned from the building's local frame into world route records the
-- Routes Registry reads (Shared/Data appends them after the harvested chunks): world points, the curve's arc
-- length, the sample count (max(20, ceil(3L)) + 1 on the length in HTML units, as for a harvested route),
-- origin "attraction" and explicit flags. A route of kind "tunnel" carries its `enclosure` record (Shared/Routes/
-- Enclosure: the enclosed-run contract); the compiler turns each mouth's `out` from the local frame into a world unit
-- vector and checks the record (Enclosure.validate) and the set (Enclosure.validateSet: links name real routes,
-- end links stay inside their enclosure, every enclosure has a way in; Motion.enclosureErrors: every link reaches
-- its route within a transfer). Invariants: ids unique and clear of the
-- harvest, at least two points, every point inside the footprint or one of the attraction's `annexes` (ground beside
-- the footprint it also bakes on: the bowling alley's yard, Shared/Attractions/AlleyRoof.ANNEX), every enclosure valid.
-- Interface: compile(ctx) -> Module? (nil when the file is absent)
local fs = require("@lune/fs")
local Json = require("./Json")
local Schema = require("./Schema")
local AlleyLayout = require("../../../src/shared/Attractions/AlleyLayout")
local Curve = require("../../../src/shared/Routes/Curve")
local Enclosure = require("../../../src/shared/Routes/Enclosure")
local Motion = require("../../../src/shared/Routes/Motion")
local Registry = require("../../../src/shared/Routes/Registry")

local Attractions = {}

local STUDS_PER_UNIT = 2.5

local function r4(n: number): number
	return math.floor(n * 1e4 + 0.5) / 1e4
end

local function r6(n: number): number
	return math.floor(n * 1e6 + 0.5) / 1e6
end

-- a direction from the building's local frame [X, Y, D] to a world unit vector
local function worldDir(place: any, v: { number }): { number }
	local x0, y0, z0 = AlleyLayout.toWorld(place, 0, 0, 0)
	local x1, y1, z1 = AlleyLayout.toWorld(place, v[1], v[2], v[3])
	local dx, dy, dz = x1 - x0, y1 - y0, z1 - z0
	local len = math.sqrt(dx * dx + dy * dy + dz * dz)
	return { r6(dx / len), r6(dy / len), r6(dz / len) }
end

-- the enclosure record in world terms (Shared/Routes/Enclosure): each mouth's `out`, the section's `up` and `upAt`,
-- and the `cavity` from the building's local frame [X, Y, D]
local function worldEnclosure(place: any, e: any): any
	local out: { [string]: any } = table.clone(e)
	if e.mouths then
		local mouths = {}
		for _, m in e.mouths do
			local wm: { [string]: any } = table.clone(m)
			if m.out then
				wm.out = worldDir(place, m.out)
			end
			table.insert(mouths, wm)
		end
		out.mouths = mouths
	end
	if e.up then
		out.up = worldDir(place, e.up)
	end
	if e.upAt then
		local keys = {}
		for _, k in e.upAt do
			local d = worldDir(place, { k[2], k[3], k[4] })
			table.insert(keys, { k[1], d[1], d[2], d[3] })
		end
		out.upAt = keys
	end
	if e.cavity then
		local c = e.cavity
		local x, _, z = AlleyLayout.toWorld(place, c.axis[1], 0, c.axis[2])
		local cav: { [string]: any } = { axis = { r4(x), r4(z) }, radius = c.radius }
		if c.bottom then
			local _, y = AlleyLayout.toWorld(place, c.axis[1], c.bottom, c.axis[2])
			cav.bottom = r4(y)
		end
		if c.top then
			local _, y = AlleyLayout.toWorld(place, c.axis[1], c.top, c.axis[2])
			cav.top = r4(y)
		end
		out.cavity = cav
	end
	return out
end
Attractions.worldEnclosure = worldEnclosure

function Attractions.compile(ctx: any): any?
	local rel = "data/attractions.json"
	local path = ctx.repo .. "/" .. rel
	if not fs.isFile(path) then
		return nil
	end
	local doc = Json.decodeFile(path)
	local schema = Json.decodeFile(ctx.repo .. "/tools/compile/schema/attractions.schema.json")
	local errs = Schema.validate(schema, doc)
	if #errs > 0 then
		ctx.schemaError(rel, errs)
	end
	doc["$schema"] = nil
	local routes = {}
	local seen: { [number]: boolean } = {}
	for _, a in doc.attractions do
		local place = a.place
		local grounds = { a.footprint }
		for _, an in a.annexes or {} do
			table.insert(grounds, an)
		end
		local function onGround(X: number, D: number): boolean
			for _, g in grounds do
				if X >= g.x0 and X <= g.x1 and D >= g.d0 and D <= g.d1 then
					return true
				end
			end
			return false
		end
		for _, r in a.routes do
			ctx.invariant("attraction route id unique: " .. r.id, not seen[r.id])
			ctx.invariant("attraction route id clear of the harvest: " .. r.id, not ctx.routeIds[r.id])
			seen[r.id] = true
			local pts = {}
			local vecs = {}
			for _, p in r.points do
				local X, Y, D = p[1], p[2], p[3]
				ctx.invariant(
					"attraction route point inside the footprint or an annex: " .. r.id,
					onGround(X, D),
					string.format("(%.2f, %.2f, %.2f)", X, Y, D)
				)
				local x, y, z = AlleyLayout.toWorld(place, X, Y, D)
				table.insert(pts, { r4(x), r4(y), r4(z) })
				table.insert(vecs, Curve.vec3(x, y, z))
			end
			local length = Curve.new(vecs):getLength()
			local rec: { [string]: any } = {
				id = r.id,
				name = r.name,
				kind = r.kind,
				speedMult = 1,
				surfaceRadius = r.surfaceRadius,
				length = r4(length),
				sampleCount = Curve.sampleSteps(length / STUDS_PER_UNIT) + 1,
				points = pts,
				origin = "attraction",
				generator = "attraction:" .. a.id,
				lotId = a.id,
			}
			if r.visualOffset ~= nil then
				rec.visualOffset = r.visualOffset
			end
			if r.enclosure ~= nil then
				rec.enclosure = worldEnclosure(place, r.enclosure)
			end
			local encErrs = Enclosure.validate(rec.enclosure, r.kind)
			ctx.invariant("attraction route enclosure valid: " .. r.id, #encErrs == 0, table.concat(encErrs, "; "))
			if r.flags then
				local f = r.flags
				rec.flags = {
					autoGrabExcluded = f.autoGrabExcluded == true,
					isPole = f.isPole == true,
					isGiant = f.isGiant == true,
					fixedSurfaceZ = f.fixedSurfaceZ == true,
					treeTravel = f.treeTravel == true,
				}
			end
			table.insert(routes, rec)
		end
	end
	local setErrs = Enclosure.validateSet(routes, ctx.routeIds)
	ctx.invariant("attraction enclosures consistent", #setErrs == 0, table.concat(setErrs, "; "))
	if #setErrs == 0 then
		-- what only the curves show: every link reaches its route within a transfer
		local linkErrs = Motion.enclosureErrors(Registry.fromRecords(routes :: any), ctx.routeIds)
		ctx.invariant("attraction enclosure links reach", #linkErrs == 0, table.concat(linkErrs, "; "))
	end
	ctx.compare("attraction routes (data/attractions.json)", #routes, #routes)
	return {
		name = "Attractions",
		value = { attractions = doc.attractions, routes = routes },
		records = #routes,
		map = true,
		source = rel,
		header = {
			"STUDS. attractions: placement and footprint per building (local frame: Shared/Attractions/AlleyLayout).",
			"routes: world-space route records (origin attraction) that Shared/Data appends to the Routes Registry.",
		},
	}
end

return Attractions
