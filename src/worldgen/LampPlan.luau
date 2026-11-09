--!strict
-- ServerScriptService.Server.WorldGen.LampPlan
-- Street-lamp placement (BUILD_PLAN §3.19, §4.4 #7; brief v2 §15; review 2026-11-09): ONE row of
-- lamps per street (asphalt streets and the Quay bridge; never sidewalks, footpaths, drives or rails),
-- on the grass verge between the kerb and the sidewalk, alternating sides block by block (a block
-- ends at each crossing street), about `spacingU` apart (~105 studs), none inside an intersection
-- (`crossClearU` from the crossing street's kerb), none within `minGapU` (25 studs) of another lamp,
-- a utility pole or a tree trunk, and none on a solid lot, a drive or a walk (nudged along the street
-- instead). Posts are vertical dark-metal cylinders `lampKit.heightU` tall (15 studs) on a base, with a
-- finial; the curved arm, housing and lit head over the kerb are Skyline parts (Skyline.luau) so the
-- client can light the nearest ~40 (Client/Render/TownView). A seeded `flicker.fraction` carries
-- Flicker = true. Data: generated/Lighting (HTML units), lot_types.json `lamp`.
-- Why lamps looked LEANING (review): the v5.4 `streetlight` details were baked as 13 x 3 x 3 stud
-- boxes lying on the verge (Builders/Props now leaves them invisible), and lamps stood in rows of
-- three (street + both sidewalks), so posts and arms crossed in perspective.
-- Interface: plan(roads, roadPlans, solids, lighting, lampKit, baseAt, obstacles?)
--   -> (BuildPlan[], Lamp[], report); baseAt(x, z) is the ground (or deck) height; obstacles are
--   { x, z, r } circles lamps keep minGapU + r clear of. Pure.

local Geometry = require("./Geometry")
local Spec = require("./Spec")

local LampPlan = {}

local POST_R = 0.42
local ORIGIN = Geometry.frame(0, 0, 0, 0)
local METAL = { 44, 48, 50 }

export type Lamp = {
	id: string,
	road: string,
	side: number,
	x: number,
	z: number,
	y: number,
	top: number,
	hx: number, -- the lamp head at the arm's tip, over the road side of the post
	hz: number,
	ox: number, -- unit XZ direction from the post toward the road (the arm's reach)
	oz: number,
	flicker: boolean,
}

local function hash(s: string): number
	local h = 2166136261
	for i = 1, #s do
		h = bit32.bxor(h, string.byte(s, i))
		h = (bit32.lshift(h, 24) + h * 403) % 4294967296
	end
	return h
end

local function span(road: any): (number, number)
	return math.min(road.start, road["end"]), math.max(road.start, road["end"])
end

local function isStreet(road: any): boolean
	if road.axis ~= "x" and road.axis ~= "z" then
		return false
	end
	return road.kind == "asphalt" or (road.kind == "cobble" and string.find(road.id, "bridge", 1, true) ~= nil)
end

function LampPlan.plan(
	roads: { any },
	roadPlans: { Spec.BuildPlan },
	solids: { Geometry.Box },
	lighting: any,
	lampKit: { heightU: number, lod: string, streaming: string },
	baseAt: (number, number) -> number,
	obstacles: { { number } }?
): ({ Spec.BuildPlan }, { Lamp }, { [string]: number })
	local spu = Spec.SPU
	local L = lighting.lamps
	local spacing = (L.spacingU or 42) * spu
	local minGap = (L.minGapU or 10) * spu
	local crossClear = (L.crossClearU or 4.8) * spu
	local height = lampKit.heightU * spu
	local roadBoxes: { Geometry.Box } = {}
	for _, p in roadPlans do
		for _, part in p.parts do
			if part.role ~= "Paint" then -- lane paint and curbs ride on the segments
				table.insert(roadBoxes, part :: any)
			end
		end
	end
	local function blocked(x: number, z: number): boolean
		for _, b in solids do
			if Geometry.containsXZ(b, x, z, 1.5) then
				return true
			end
		end
		for _, b in roadBoxes do
			if Geometry.containsXZ(b, x, z, 0.6) then
				return true
			end
		end
		return false
	end
	local lamps: { Lamp } = {}
	local taken: { { number } } = {}
	for _, o in obstacles or {} do
		table.insert(taken, o)
	end
	local function crowded(x: number, z: number): boolean
		for _, t in taken do
			local r = minGap + (t[3] or 0)
			if (t[1] - x) ^ 2 + (t[2] - z) ^ 2 < r * r then
				return true
			end
		end
		return false
	end
	local streets: { any } = {}
	for _, r in roads do
		if isStreet(r) then
			table.insert(streets, r)
		end
	end
	-- the lateral offset of the verge on one side: between the kerb and the parallel sidewalk
	local function verge(road: any, side: number): number
		local c = road.coord :: number
		local a0, a1 = span(road)
		local best: number? = nil
		for _, o in roads do
			if o.kind == "concrete" and o.axis == road.axis and o ~= road then
				local o0, o1 = span(o)
				local oc = o.coord :: number
				local rel = (oc - c) * side
				local gap = rel - o.width / 2 - road.width / 2
				if rel > 0 and gap > -0.5 and gap < 10 and o0 < a1 and o1 > a0 then
					local off: number
					if gap >= 2.4 then
						off = road.width / 2 + gap / 2 -- centred on the grass verge
					else
						off = rel + o.width / 2 + 1.6 -- behind a sidewalk that meets the kerb
					end
					if best == nil or off < best then
						best = off
					end
				end
			end
		end
		return best or (road.width / 2 + 2.2)
	end
	local report = { streets = 0, blocks = 0, skipped = 0, placed = 0 }
	for si, road in streets do
		report.streets += 1
		local a0, a1 = span(road)
		local c = road.coord :: number
		-- crossings along this street (other streets that cross its line inside its span)
		local cuts: { { number } } = {}
		for _, o in streets do
			if o ~= road and o.axis ~= road.axis then
				local o0, o1 = span(o)
				local oc = o.coord :: number
				if oc > a0 - o.width and oc < a1 + o.width and c >= o0 - road.width and c <= o1 + road.width then
					table.insert(cuts, { oc - o.width / 2 - crossClear, oc + o.width / 2 + crossClear })
				end
			end
		end
		table.sort(cuts, function(p, q)
			return p[1] < q[1]
		end)
		-- blocks between the crossings
		local blocks: { { number } } = {}
		local cur = a0 + 6
		for _, cut in cuts do
			if cut[1] > cur then
				table.insert(blocks, { cur, cut[1] })
			end
			cur = math.max(cur, cut[2])
		end
		if a1 - 6 > cur then
			table.insert(blocks, { cur, a1 - 6 })
		end
		local side0 = if si % 2 == 0 then 1 else -1
		for bi, blk in blocks do
			report.blocks += 1
			local len = blk[2] - blk[1]
			if len >= 12 then
				local side = side0 * (if bi % 2 == 0 then -1 else 1)
				local n = math.max(1, math.floor(len / spacing + 0.5))
				local off = verge(road, side)
				for i = 1, n do
					local t = blk[1] + (i - 0.5) / n * len
					local placed = false
					for k = 0, 10 do
						local shift = (if k % 2 == 0 then 1 else -1) * math.ceil(k / 2) * 5
						local tt = t + shift
						if tt >= blk[1] and tt <= blk[2] then
							local px, pz
							if road.axis == "x" then
								px, pz = tt, c + side * off
							else
								px, pz = c + side * off, tt
							end
							if not blocked(px, pz) and not crowded(px, pz) then
								local y = baseAt(px, pz)
								-- toward the street: -side across the street's axis
								local ox, oz = 0, 0
								if road.axis == "x" then
									oz = -side
								else
									ox = -side
								end
								local id = `{road.id}_{if side < 0 then "L" else "R"}{bi}{i}`
								table.insert(lamps, {
									id = id,
									road = road.id,
									side = side,
									x = px,
									z = pz,
									y = y,
									top = y + height,
									hx = px + ox * 4.6,
									hz = pz + oz * 4.6,
									ox = ox,
									oz = oz,
									flicker = false,
								})
								table.insert(taken, { px, pz, 0 })
								placed = true
								break
							end
						end
					end
					if not placed then
						report.skipped += 1
					end
				end
			end
		end
	end
	-- seeded flicker set
	local order = table.clone(lamps)
	table.sort(order, function(a, b)
		local ha, hb = hash(lighting.flicker.seed .. a.id), hash(lighting.flicker.seed .. b.id)
		if ha == hb then
			return a.id < b.id
		end
		return ha < hb
	end)
	local nFlicker = math.floor(#lamps * lighting.flicker.fraction + 0.5)
	for i = 1, nFlicker do
		order[i].flicker = true
	end
	report.placed = #lamps
	report.flicker = nFlicker
	-- one Model per road: post, base and finial (the arm and head are Skyline parts)
	local byRoad: { [string]: Spec.PartList } = {}
	local roadOrder: { string } = {}
	for _, l in lamps do
		local list = byRoad[l.road]
		if not list then
			list = Spec.list()
			byRoad[l.road] = list
			table.insert(roadOrder, l.road)
		end
		local y0 = l.y - 0.8
		list:add(ORIGIN, "Post_" .. l.id, l.x, (y0 + l.top) / 2, l.z, l.top - y0, POST_R * 2, POST_R * 2, {
			roll = math.pi / 2,
			shape = "Cylinder",
			color = METAL,
			material = "Metal",
			role = "Post",
			attrs = { Lamp = l.id, Flicker = l.flicker },
		})
		list:add(ORIGIN, "Base_" .. l.id, l.x, l.y + 0.4, l.z, 1.6, 1.5, 1.5, {
			roll = math.pi / 2,
			shape = "Cylinder",
			color = METAL,
			material = "Metal",
			canCollide = false,
			role = "Trim",
			attrs = { Lamp = l.id },
		})
		list:add(ORIGIN, "Finial_" .. l.id, l.x, l.top + 0.15, l.z, 1.0, 1.0, 1.0, {
			shape = "Ball",
			color = METAL,
			material = "Metal",
			canCollide = false,
			castShadow = false,
			role = "Trim",
			attrs = { Lamp = l.id },
		})
	end
	local plans: { Spec.BuildPlan } = {}
	for _, rid in roadOrder do
		local list = byRoad[rid]
		local posts = 0
		for _, s in list.parts do
			if string.sub(s.name, 1, 5) == "Post_" then
				posts += 1
			end
		end
		table.insert(plans, {
			kind = "lamps",
			id = "Lamps_" .. rid,
			category = "lamp",
			lod = lampKit.lod,
			streaming = lampKit.streaming,
			attributes = { Road = rid, Count = posts },
			parts = list.parts,
			extras = list.extras,
		})
	end
	return plans, lamps, report
end

return LampPlan
