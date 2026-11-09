--!strict
-- ServerScriptService.Server.WorldGen.Builders.Props
-- Dressing for the single-block lots (review 2026-11-09, "make it a believable small town"): the block
-- Plan made stays the lot's PrimaryPart (same collision role), and this adds the pieces that make it
-- read as the thing it is: columns under the fuel canopy and the hospital porte-cochere (roofs need
-- supports), pilings under the Quay docks, a round trampoline on legs, and small street and yard
-- details (hydrants, benches, bins, stop signs, mailbox-sized yard props) instead of 3-stud boxes.
-- The v5.4 `streetlight` details become invisible markers: street lamps are LampPlan's job (one row
-- per street), and the 13 x 3 boxes read as fallen lamp posts.
-- Interface: dress(lot, kit, body, list, seat) (body = the lot's block PartSpec, edited in place).
-- Pure.

local Geometry = require("../Geometry")
local Import = require("../Import")
local Spec = require("../Spec")
local Height = Import.shared("World/Height") :: typeof(require("../../shared/World/Height"))

local Props = {}

local ORIGIN = Geometry.frame(0, 0, 0, 0)
local METAL = { 58, 60, 62 }
local CONCRETE = { 196, 192, 182 }
local WOOD = { 120, 92, 66 }

local function add(
	list: Spec.PartList,
	name: string,
	x: number,
	y: number,
	z: number,
	sx: number,
	sy: number,
	sz: number,
	o: Spec.Opts
)
	list:add(ORIGIN, name, x, y, z, sx, sy, sz, o)
end

-- A vertical cylinder from y0 to y1.
local function post(
	list: Spec.PartList,
	name: string,
	x: number,
	z: number,
	y0: number,
	y1: number,
	r: number,
	color: { number },
	material: string,
	collide: boolean
)
	add(list, name, x, (y0 + y1) / 2, z, y1 - y0, 2 * r, 2 * r, {
		roll = math.pi / 2,
		shape = "Cylinder",
		color = color,
		material = material,
		canCollide = collide,
		castShadow = true,
		role = "Post",
	})
end

-- World XZ extents of a block body (yaws are quarter turns).
local function box(b: Spec.PartSpec): (number, number, number, number)
	local q = math.floor(b.yaw / (math.pi / 2) + 0.5) % 2
	local wx, wz = b.sx, b.sz
	if q == 1 then
		wx, wz = b.sz, b.sx
	end
	return b.cx - wx / 2, b.cx + wx / 2, b.cz - wz / 2, b.cz + wz / 2
end

local function canopyColumns(lot: any, body: Spec.PartSpec, list: Spec.PartList)
	local x0, x1, z0, z1 = box(body)
	local bottom = body.cy - body.sy / 2
	local pts: { { number } } = {}
	if lot.type == "gas_canopy" then
		-- on the two pump-island lines, between the dispensers (v5.4 fuel canopy 810-865)
		for _, fx in { 0.34, 0.66 } do
			for _, fz in { 0.26, 0.74 } do
				table.insert(pts, { x0 + (x1 - x0) * fx, z0 + (z1 - z0) * fz })
			end
		end
	else
		-- porte-cochere: two columns along the drive-side (front) edge, v5.4 local x +-9 u
		local front = lot.facing or "-Z"
		local fz = if front == "-Z" then z0 + 1.6 elseif front == "+Z" then z1 - 1.6 else (z0 + z1) / 2
		local fx = if front == "-X" then x0 + 1.6 elseif front == "+X" then x1 - 1.6 else nil
		if fx then
			for _, t in { 0.12, 0.88 } do
				table.insert(pts, { fx, z0 + (z1 - z0) * t })
			end
		else
			for _, t in { 0.09, 0.91 } do
				table.insert(pts, { x0 + (x1 - x0) * t, fz })
			end
		end
	end
	for i, p in pts do
		local g = Height.at(p[1], p[2])
		post(list, `Column{i}`, p[1], p[2], g - 1, bottom + 0.05, 1.0, CONCRETE, "Concrete", true)
		add(list, `ColumnFoot{i}`, p[1], g + 0.4, p[2], 3.2, 1.2, 3.2, {
			color = CONCRETE,
			material = "Concrete",
			canCollide = false,
			castShadow = false,
			role = "Trim",
		})
	end
end

local function dockPilings(body: Spec.PartSpec, list: Spec.PartList)
	local x0, x1, z0, z1 = box(body)
	local bottom = body.cy - body.sy / 2
	local bed = Height.RIVER.bedY * Spec.SPU
	local i = 0
	for _, fx in { 0.08, 0.92 } do
		for _, fz in { 0.08, 0.5, 0.92 } do
			i += 1
			post(list, `Piling{i}`, x0 + (x1 - x0) * fx, z0 + (z1 - z0) * fz, bed - 1, bottom + 2.2, 0.7, { 92, 76, 60 }, "Wood", true)
		end
	end
end

local function trampoline(body: Spec.PartSpec, list: Spec.PartList, seat: number)
	local d = math.min(body.sx, body.sz)
	local top = body.cy + body.sy / 2
	-- the body becomes the round frame + mat (same footprint and top, still the collider)
	body.shape = "Cylinder"
	body.yaw, body.pitch, body.roll = 0, 0, math.pi / 2
	body.sx, body.sy, body.sz = 0.9, d, d
	body.cy = top - 0.45
	body.color = { 46, 70, 96 }
	add(list, "Mat", body.cx, top + 0.02, body.cz, 0.12, d - 2.4, d - 2.4, {
		roll = math.pi / 2,
		shape = "Cylinder",
		color = { 32, 33, 36 },
		material = "Fabric",
		canCollide = false,
		role = "Trim",
	})
	for k = 1, 6 do
		local a = (k - 0.5) / 6 * 2 * math.pi
		local x, z = body.cx + math.cos(a) * (d / 2 - 0.6), body.cz + math.sin(a) * (d / 2 - 0.6)
		post(list, `Leg{k}`, x, z, seat - 0.5, top - 0.6, 0.3, { 150, 152, 156 }, "Metal", false)
	end
end

-- Small details: the body (footprint x 3 st box) is replaced by a believable little object.
local function detail(lot: any, body: Spec.PartSpec, list: Spec.PartList, seat: number)
	local id: string = lot.id
	local kind = string.match(id, "^detail_%d+_(.+)$") or ""
	local x, z = body.cx, body.cz
	local function reshape(sx: number, sy: number, sz: number, color: { number }, material: string?, shape: string?)
		body.sx, body.sy, body.sz = sx, sy, sz
		body.color = color
		body.material = material or "SmoothPlastic"
		body.shape = shape
		body.cy = seat + sy / 2
		if shape == "Cylinder" then
			body.yaw, body.pitch, body.roll = 0, 0, math.pi / 2
			body.sx, body.sy, body.sz = sy, sx, sx
		elseif shape == "Ball" then
			body.cy = seat + sy / 2
		end
	end
	if kind == "streetlight" then
		body.transparency = 1
		body.canQuery = false
		body.castShadow = false
		return
	elseif kind == "fire_hydrant" then
		reshape(1.5, 2.6, 1.5, { 196, 52, 44 }, "Metal", "Cylinder")
		add(list, "Cap", x, seat + 2.7, z, 1.3, 1.3, 1.3, { shape = "Ball", color = { 196, 52, 44 }, material = "Metal", canCollide = false, role = "Trim" })
		add(list, "Nozzle", x, seat + 1.8, z, 2.2, 0.6, 0.6, { roll = 0, shape = "Cylinder", color = { 170, 44, 38 }, material = "Metal", canCollide = false, role = "Trim" })
	elseif kind == "park_bench" then
		local along = body.sx >= body.sz
		local L = math.max(body.sx, body.sz) * 0.7
		body.sx, body.sz = if along then L else 2.2, if along then 2.2 else L
		body.sy, body.cy = 0.45, seat + 1.7
		body.color, body.material = WOOD, "WoodPlanks"
		local bx, bz = if along then 0 else 1.0, if along then 1.0 else 0
		add(list, "Back", x + bx, seat + 2.9, z + bz, if along then L else 0.35, 1.6, if along then 0.35 else L, {
			color = WOOD,
			material = "WoodPlanks",
			canCollide = false,
			role = "Trim",
		})
		for k, s in { -1, 1 } do
			local lx, lz = if along then s * L * 0.4 else 0, if along then 0 else s * L * 0.4
			add(list, `Leg{k}`, x + lx, seat + 0.75, z + lz, if along then 0.35 else 2.2, 1.5, if along then 2.2 else 0.35, {
				color = METAL,
				material = "Metal",
				canCollide = false,
				role = "Trim",
			})
		end
	elseif kind == "trash_can" then
		reshape(2.4, 3.2, 2.4, { 52, 78, 62 }, "Metal", "Cylinder")
		add(list, "Lid", x, seat + 3.3, z, 0.25, 2.7, 2.7, { roll = math.pi / 2, shape = "Cylinder", color = { 40, 60, 48 }, material = "Metal", canCollide = false, role = "Trim" })
	elseif kind == "stop_sign" then
		reshape(0.35, 7, 0.35, { 150, 150, 152 }, "Metal", "Cylinder")
		add(list, "Sign", x, seat + 7.4, z, 0.15, 2.8, 2.8, {
			roll = 0,
			yaw = if math.abs(body.yaw % math.pi) < 0.1 then math.pi / 2 else 0,
			shape = "Cylinder",
			color = { 190, 36, 36 },
			material = "SmoothPlastic",
			canCollide = false,
			role = "Sign",
		})
	elseif kind == "driveway_basketball_hoop" then
		reshape(0.5, 10, 0.5, { 70, 72, 76 }, "Metal", "Cylinder")
		add(list, "Board", x, seat + 10.5, z, 4, 2.8, 0.25, { color = { 236, 236, 232 }, canCollide = false, role = "Trim" })
		add(list, "Rim", x, seat + 9.4, z - 1.0, 0.15, 1.8, 1.8, { roll = math.pi / 2, shape = "Cylinder", color = { 214, 96, 40 }, material = "Metal", canCollide = false, role = "Trim" })
	elseif kind == "bird_feeder" or kind == "porch_light" or kind == "wind_chime" then
		reshape(0.3, 5, 0.3, WOOD, "Wood", "Cylinder")
		add(list, "Top", x, seat + 5.3, z, 1.4, 1.0, 1.4, { color = { 150, 120, 84 }, material = "WoodPlanks", canCollide = false, role = "Trim" })
	elseif kind == "rain_barrel" or kind == "compost_bin" then
		reshape(2.6, 3.2, 2.6, if kind == "rain_barrel" then { 74, 96, 120 } else { 70, 86, 58 }, "SmoothPlastic", "Cylinder")
	elseif kind == "lawn_flamingo" then
		reshape(0.15, 2.2, 0.15, { 225, 120, 160 }, "SmoothPlastic", "Cylinder")
		add(list, "Bird", x, seat + 2.5, z, 0.9, 0.9, 0.9, { shape = "Ball", color = { 232, 128, 168 }, canCollide = false, role = "Trim" })
	elseif kind == "garden_gnome" then
		reshape(0.8, 1.0, 0.8, { 70, 100, 160 }, "SmoothPlastic", "Cylinder")
		add(list, "Hat", x, seat + 1.35, z, 0.7, 0.7, 0.7, { shape = "Ball", color = { 196, 50, 44 }, canCollide = false, role = "Trim" })
	elseif kind == "sprinkler_head" then
		reshape(0.5, 0.4, 0.5, { 90, 90, 90 }, "Metal", "Cylinder")
	elseif kind == "kids_bike" or kind == "wheelbarrow" or kind == "garden_hose_reel" then
		body.sx, body.sz = math.min(body.sx, 3.2), math.min(body.sz, 5.5)
		body.sy, body.cy = 1.8, seat + 0.9
		body.color = if kind == "kids_bike" then { 60, 120, 170 } elseif kind == "wheelbarrow" then { 150, 60, 50 } else { 70, 130, 70 }
	elseif kind == "porch_swing" or kind == "window_box" then
		body.sy, body.cy = 1.2, seat + 1.4
		body.color, body.material = WOOD, "WoodPlanks"
		if kind == "window_box" then
			add(list, "Flowers", x, seat + 2.3, z, body.sx * 0.9, 0.8, body.sz * 0.9, { color = { 196, 84, 104 }, material = "LeafyGrass", canCollide = false, role = "Trim" })
		end
	end
end

function Props.dress(lot: any, _kit: any, body: Spec.PartSpec, list: Spec.PartList, seat: number)
	local t = lot.type
	if t == "gas_canopy" or t == "porte_cochere" then
		canopyColumns(lot, body, list)
	elseif t == "dock" and Height.insideRiverWater(lot.x, lot.z) then
		dockPilings(body, list)
	elseif t == "backyard_trampoline" then
		trampoline(body, list, seat)
	elseif t == "detail" then
		detail(lot, body, list, seat)
	end
end

return Props
