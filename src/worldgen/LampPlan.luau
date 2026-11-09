--!strict
-- ServerScriptService.Server.WorldGen.LampPlan
-- Street-lamp placement (BUILD_PLAN §3.19, §4.4 #7; brief v2 §15): greybox posts (no lights in W1)
-- along both sides of every town road, at least `perBlockSide` per side and no further apart than
-- `spacingMaxU`, set back from the kerb, nudged along the road off solid lots and other roads.
-- A seeded `flicker.fraction` of the posts carries Flicker = true. The emissive heads are Skyline
-- parts (Skyline.luau). Data: generated/Lighting (HTML units).
-- Interface: plan(roads, roadPlans, solids, lighting, lampKit, heightAt) -> (BuildPlan[], Lamp[], report)
-- Pure.

local Geometry = require("./Geometry")
local Spec = require("./Spec")

local LampPlan = {}

local KINDS = { asphalt = true, concrete = true, cobble = true }
local POST_R = 0.375 -- studs (0.15 u)
local ARM = 3 -- studs: the arm reaches over the kerb (v5.4 streetlight arm 3.3 u at a 9 u pole, scaled)
local ORIGIN = Geometry.frame(0, 0, 0, 0)

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

local function endpoints(road: any): (number, number, number, number)
	if road.axis == "x" then
		return road.start, road.coord, road["end"], road.coord
	elseif road.axis == "z" then
		return road.coord, road.start, road.coord, road["end"]
	end
	return road.start[1], road.start[2], road["end"][1], road["end"][2]
end

function LampPlan.plan(
	roads: { any },
	roadPlans: { Spec.BuildPlan },
	solids: { Geometry.Box },
	lighting: any,
	lampKit: { heightU: number, lod: string, streaming: string },
	heightAt: (number, number) -> number
): ({ Spec.BuildPlan }, { Lamp }, { [string]: number })
	local spu = Spec.SPU
	local L = lighting.lamps
	local spacing, setback = L.spacingMaxU * spu, L.setbackU * spu
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
			if Geometry.containsXZ(b, x, z, 0.8) then
				return true
			end
		end
		for _, b in roadBoxes do
			if Geometry.containsXZ(b, x, z, 0.3) then
				return true
			end
		end
		return false
	end
	local lamps: { Lamp } = {}
	local report = { roads = 0, sides = 0, sidesShort = 0, skipped = 0, placed = 0 }
	for _, road in roads do
		local x0, z0, x1, z1 = endpoints(road)
		local dx, dz = x1 - x0, z1 - z0
		local len = math.sqrt(dx * dx + dz * dz)
		if KINDS[road.kind] and len >= L.minRoadLengthU * spu then
			report.roads += 1
			local ux, uz = dx / len, dz / len
			local nx, nz = -uz, ux
			local count = math.max(L.perBlockSide, math.ceil(len / spacing))
			for side = -1, 1, 2 do
				report.sides += 1
				local placed = 0
				for i = 1, count do
					local t = (i - 0.5) / count * len
					local off = road.width / 2 + setback
					local ok = false
					local px, pz = 0, 0
					for k = 0, 12 do
						local shift = (if k % 2 == 0 then 1 else -1) * math.ceil(k / 2) * 4
						local tt = math.clamp(t + shift, 0, len)
						px, pz = x0 + ux * tt + nx * side * off, z0 + uz * tt + nz * side * off
						if not blocked(px, pz) then
							ok = true
							break
						end
					end
					if ok then
						placed += 1
						local y = heightAt(px, pz)
						local ax, az = -nx * side * ARM, -nz * side * ARM
						table.insert(lamps, {
							id = `{road.id}_{if side < 0 then "L" else "R"}{i}`,
							road = road.id,
							side = side,
							x = px,
							z = pz,
							y = y,
							top = y + height,
							hx = px + ax,
							hz = pz + az,
							flicker = false,
						})
					else
						report.skipped += 1
					end
				end
				if placed < L.perBlockSide then
					report.sidesShort += 1
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
	-- one Model per road
	local byRoad: { [string]: Spec.PartList } = {}
	local roadOrder: { string } = {}
	for _, l in lamps do
		local list = byRoad[l.road]
		if not list then
			list = Spec.list()
			byRoad[l.road] = list
			table.insert(roadOrder, l.road)
		end
		list:add(ORIGIN, "Post_" .. l.id, l.x, l.y + height / 2, l.z, height, POST_R * 2, POST_R * 2, {
			roll = math.pi / 2,
			shape = "Cylinder",
			color = { 60, 62, 64 },
			material = "Metal",
			role = "Post",
			attrs = { Lamp = l.id, Flicker = l.flicker },
		})
	end
	local plans: { Spec.BuildPlan } = {}
	for _, rid in roadOrder do
		local list = byRoad[rid]
		table.insert(plans, {
			kind = "lamps",
			id = "Lamps_" .. rid,
			category = "lamp",
			lod = lampKit.lod,
			streaming = lampKit.streaming,
			attributes = { Road = rid, Count = #list.parts },
			parts = list.parts,
			extras = list.extras,
		})
	end
	return plans, lamps, report
end

return LampPlan
