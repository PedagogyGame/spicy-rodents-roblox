--!strict
-- ServerScriptService.Server.WorldGen.Builders.Props
-- Dressing for the single-block lots (review 2026-11-09, "make it a believable small town"): the block
-- Plan made stays the lot's PrimaryPart (same collision role), and this adds the pieces that make it
-- read as the thing it is: columns under the fuel canopy and the hospital porte-cochere (roofs need
-- supports), pilings under the Quay docks, a round trampoline on legs, and small street and yard
-- details (hydrants, benches, bins, stop signs, mailbox-sized yard props) instead of 3-stud boxes; the kids' bikes,
-- wheelbarrows, hose reels, the ride-on mower and the park shed's roof and door (owner playtest 2026-11-19: "bikes and
-- things that were basic colors"), each drawn over its old box, which stays the lot's unseen PrimaryPart.
-- The v5.4 `streetlight` details become invisible markers: street lamps are LampPlan's job (one row
-- per street), and the 13 x 3 boxes read as fallen lamp posts.
-- Interface: dress(lot, kit, body, list, seat) (body = the lot's block PartSpec, edited in place).
-- Pure.

local Geometry = require("../Geometry")
local Import = require("../Import")
local Spec = require("../Spec")
local Height = Import.shared("World/Height") :: typeof(require("../../shared/World/Height"))
local RidePuppet = Import.shared("Vehicles/RidePuppet") :: typeof(require("../../shared/Vehicles/RidePuppet"))

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

-- A part at a frame-local position p = { x, y, z } (y above the frame's height), size s; never solid.
local function add3(list: Spec.PartList, f: Geometry.Frame, name: string, p: { number }, s: { number }, o: Spec.Opts)
	o.canCollide = false
	o.role = o.role or "Trim"
	if o.castShadow == nil then
		o.castShadow = false
	end
	list:add(f, name, p[1], p[2], p[3], s[1], s[2], s[3], o)
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
		attrs = { Embedded = true } :: Spec.Attrs,
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
			attrs = { Embedded = true } :: Spec.Attrs,
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
			post(
				list,
				`Piling{i}`,
				x0 + (x1 - x0) * fx,
				z0 + (z1 - z0) * fz,
				bed - 1,
				bottom + 2.2,
				0.7,
				{ 92, 76, 60 },
				"Wood",
				true
			)
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

-- Parts drawn the PartBuilder way (Shared/Vehicles/RidePuppet: positions above the ground, local yaw, pitch and roll)
-- put down in a frame on the lot; none collides (the box they replace never did), small ones cast no shadow.
local function drawn(list: Spec.PartList, prefix: string, parts: { any }, f: Geometry.Frame)
	for _, p in parts do
		local c = p.color
		add3(list, f, prefix .. p.name, p.pos, p.size, {
			yaw = p.yaw,
			pitch = p.pitch,
			roll = p.roll,
			shape = if p.shape == "Block" then nil else p.shape,
			color = { math.floor(c.r * 255 + 0.5), math.floor(c.g * 255 + 0.5), math.floor(c.b * 255 + 0.5) },
			material = p.material or "SmoothPlastic",
			castShadow = p.castShadow == true,
		})
	end
end

-- The box a drawn prop replaces stays the lot's PrimaryPart, unseen: no shadow, nothing to stand on.
local function hide(body: Spec.PartSpec)
	body.transparency = 1
	body.canQuery = false
	body.castShadow = false
end

-- A kid's bicycle on its stand (RidePuppet's, at a kid's 0.82, one bar of spokes a wheel), in the old box's colour.
local function kidsBike(body: Spec.PartSpec, list: Spec.PartList, seat: number)
	hide(body)
	local k = RidePuppet.newKit(0)
	RidePuppet.drawBicycle(k, { scale = 0.82, frame = "#3c78aa", basket = true, spokes = 1 })
	local f = Geometry.frame(body.cx, seat, body.cz, body.yaw)
	drawn(list, "Bike", k.parts, f)
	add3(
		list,
		f,
		"BikeStand",
		{ 0.32, 0.36, 0.75 },
		{ 0.06, 0.8, 0.06 },
		{ roll = 0.45, color = METAL, material = "Metal" }
	)
end

-- A garden wheelbarrow: the red tray with its sloped front, the wheel, two wooden handles and two legs (7 parts).
local function wheelbarrow(body: Spec.PartSpec, list: Spec.PartList, seat: number)
	hide(body)
	local f = Geometry.frame(body.cx, seat, body.cz, body.yaw)
	local red, dark = { 150, 60, 50 }, { 30, 31, 33 }
	add3(list, f, "Tray", { 0, 1.25, 0.35 }, { 1.9, 0.75, 1.5 }, { color = red, material = "Metal", castShadow = true })
	add3(
		list,
		f,
		"TrayNose",
		{ 0, 1.25, -0.75 },
		{ 1.9, 0.75, 0.7 },
		{ shape = "Wedge", color = red, material = "Metal" }
	)
	add3(list, f, "Wheel", { 0, 0.5, -1.35 }, { 0.3, 1.0, 1.0 }, { shape = "Cylinder", color = dark })
	for i, sx in { -1, 1 } do
		add3(
			list,
			f,
			`Handle{i}`,
			{ sx * 0.62, 1.0, 0.25 },
			{ 0.14, 0.14, 3.4 },
			{ pitch = 0.12, color = WOOD, material = "Wood" }
		)
		add3(list, f, `Leg{i}`, { sx * 0.55, 0.45, 0.95 }, { 0.12, 0.9, 0.12 }, { color = METAL, material = "Metal" })
	end
end

-- A garden hose reel: the green hose wound on a drum between two discs on a metal frame with a handle (6 parts).
local function hoseReel(body: Spec.PartSpec, list: Spec.PartList, seat: number)
	hide(body)
	local f = Geometry.frame(body.cx, seat, body.cz, body.yaw)
	add3(
		list,
		f,
		"Hose",
		{ 0, 1.0, 0 },
		{ 1.0, 1.25, 1.25 },
		{ shape = "Cylinder", color = { 70, 130, 70 }, castShadow = true }
	)
	for i, sx in { -1, 1 } do
		add3(
			list,
			f,
			`Disc{i}`,
			{ sx * 0.56, 1.0, 0 },
			{ 0.1, 1.7, 1.7 },
			{ shape = "Cylinder", color = { 196, 160, 60 } }
		)
	end
	add3(list, f, "Crank", { 0.75, 1.0, 0 }, { 0.3, 0.3, 0.3 }, { shape = "Ball", color = METAL, material = "Metal" })
	add3(list, f, "Frame", { 0, 0.12, 0.2 }, { 1.4, 0.24, 1.9 }, { color = METAL, material = "Metal" })
	add3(list, f, "Handle", { 0, 1.9, 0.75 }, { 1.4, 0.14, 0.14 }, { color = METAL, material = "Metal" })
end

-- The ride-on mower behind house 3 (v5.4 #d1ae44): the cutting deck, the yellow bonnet and body, the seat and its back,
-- the steering column and wheel, small front and big back wheels (12 parts), along the old box.
local function mower(body: Spec.PartSpec, list: Spec.PartList, seat: number)
	hide(body)
	local long = body.sz >= body.sx
	local f = Geometry.frame(body.cx, seat, body.cz, body.yaw + (if long then 0 else math.pi / 2))
	local yellow, dark, black = { 209, 174, 68 }, { 58, 60, 62 }, { 30, 31, 33 }
	add3(list, f, "Deck", { 0, 0.6, 0.2 }, { 4.4, 0.45, 3.6 }, { color = dark, material = "Metal" })
	add3(list, f, "Bonnet", { 0, 1.55, -2.3 }, { 2.6, 1.3, 2.6 }, { color = yellow, castShadow = true })
	add3(list, f, "Grille", { 0, 1.45, -3.62 }, { 1.8, 0.8, 0.06 }, { color = black })
	add3(list, f, "Chassis", { 0, 1.3, 1.1 }, { 3.0, 0.9, 3.6 }, { color = yellow, castShadow = true })
	add3(list, f, "Seat", { 0, 1.95, 1.6 }, { 1.6, 0.35, 1.4 }, { color = black })
	add3(list, f, "SeatBack", { 0, 2.6, 2.35 }, { 1.6, 1.2, 0.3 }, { pitch = -0.2, color = black })
	add3(list, f, "Column", { 0, 2.2, -0.6 }, { 0.14, 1.4, 0.14 }, { pitch = -0.45, color = black })
	add3(
		list,
		f,
		"SteeringWheel",
		{ 0, 2.85, -0.3 },
		{ 0.1, 0.9, 0.9 },
		{ shape = "Cylinder", roll = math.pi / 2 - 0.45, color = black }
	)
	for i, w in { { -1.45, -2.4, 0.55 }, { 1.45, -2.4, 0.55 }, { -1.55, 2.5, 0.85 }, { 1.55, 2.5, 0.85 } } do
		add3(
			list,
			f,
			`Wheel{i}`,
			{ w[1], w[3], w[2] },
			{ 0.55, w[3] * 2, w[3] * 2 },
			{ shape = "Cylinder", color = black }
		)
	end
end

-- The park shed: the walls stay the body (the same solid box); a flat slate roof sits on it with eaves all round (solid,
-- like every roof in town: nothing can slip between it and the walls), a door and a window on the front, a fascia
-- board under the front eave (4 parts).
local function shed(body: Spec.PartSpec, list: Spec.PartList)
	local W, D, H = body.sx, body.sz, body.sy
	local f = Geometry.frame(body.cx, body.cy - H / 2, body.cz, body.yaw)
	body.material = "WoodPlanks"
	list:add(f, "Roof", 0, H + 0.2, 0, W + 2.4, 0.4, D + 2.4, {
		color = { 95, 93, 86 },
		material = "Slate",
		canCollide = true,
		castShadow = true,
		role = "Roof",
	})
	add3(
		list,
		f,
		"Fascia",
		{ 0, H - 0.1, -D / 2 - 1.05 },
		{ W + 2.4, 0.6, 0.25 },
		{ color = { 120, 92, 66 }, material = "Wood" }
	)
	add3(
		list,
		f,
		"Door",
		{ -W * 0.18, 3.0, -D / 2 - 0.08 },
		{ 4.2, 6.0, 0.2 },
		{ color = { 96, 70, 50 }, material = "WoodPlanks" }
	)
	add3(
		list,
		f,
		"Window",
		{ W * 0.24, 4.2, -D / 2 - 0.08 },
		{ 4.0, 2.4, 0.2 },
		{ color = { 31, 44, 53 }, material = "Glass" }
	)
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
		add(
			list,
			"Cap",
			x,
			seat + 2.7,
			z,
			1.3,
			1.3,
			1.3,
			{ shape = "Ball", color = { 196, 52, 44 }, material = "Metal", canCollide = false, role = "Trim" }
		)
		add(list, "Nozzle", x, seat + 1.8, z, 2.2, 0.6, 0.6, {
			roll = 0,
			shape = "Cylinder",
			color = { 170, 44, 38 },
			material = "Metal",
			canCollide = false,
			role = "Trim",
		})
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
			add(
				list,
				`Leg{k}`,
				x + lx,
				seat + 0.75,
				z + lz,
				if along then 0.35 else 2.2,
				1.5,
				if along then 2.2 else 0.35,
				{
					color = METAL,
					material = "Metal",
					canCollide = false,
					role = "Trim",
				}
			)
		end
	elseif kind == "trash_can" then
		reshape(2.4, 3.2, 2.4, { 52, 78, 62 }, "Metal", "Cylinder")
		add(list, "Lid", x, seat + 3.3, z, 0.25, 2.7, 2.7, {
			roll = math.pi / 2,
			shape = "Cylinder",
			color = { 40, 60, 48 },
			material = "Metal",
			canCollide = false,
			role = "Trim",
		})
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
		add(
			list,
			"Board",
			x,
			seat + 10.5,
			z,
			4,
			2.8,
			0.25,
			{ color = { 236, 236, 232 }, canCollide = false, role = "Trim" }
		)
		add(list, "Rim", x, seat + 9.4, z - 1.0, 0.15, 1.8, 1.8, {
			roll = math.pi / 2,
			shape = "Cylinder",
			color = { 214, 96, 40 },
			material = "Metal",
			canCollide = false,
			role = "Trim",
		})
	elseif kind == "bird_feeder" or kind == "porch_light" or kind == "wind_chime" then
		reshape(0.3, 5, 0.3, WOOD, "Wood", "Cylinder")
		add(
			list,
			"Top",
			x,
			seat + 5.3,
			z,
			1.4,
			1.0,
			1.4,
			{ color = { 150, 120, 84 }, material = "WoodPlanks", canCollide = false, role = "Trim" }
		)
	elseif kind == "rain_barrel" or kind == "compost_bin" then
		reshape(
			2.6,
			3.2,
			2.6,
			if kind == "rain_barrel" then { 74, 96, 120 } else { 70, 86, 58 },
			"SmoothPlastic",
			"Cylinder"
		)
	elseif kind == "lawn_flamingo" then
		reshape(0.15, 2.2, 0.15, { 225, 120, 160 }, "SmoothPlastic", "Cylinder")
		add(
			list,
			"Bird",
			x,
			seat + 2.5,
			z,
			0.9,
			0.9,
			0.9,
			{ shape = "Ball", color = { 232, 128, 168 }, canCollide = false, role = "Trim" }
		)
	elseif kind == "garden_gnome" then
		reshape(0.8, 1.0, 0.8, { 70, 100, 160 }, "SmoothPlastic", "Cylinder")
		add(
			list,
			"Hat",
			x,
			seat + 1.35,
			z,
			0.7,
			0.7,
			0.7,
			{ shape = "Ball", color = { 196, 50, 44 }, canCollide = false, role = "Trim" }
		)
	elseif kind == "sprinkler_head" then
		reshape(0.5, 0.4, 0.5, { 90, 90, 90 }, "Metal", "Cylinder")
	elseif kind == "kids_bike" or kind == "wheelbarrow" or kind == "garden_hose_reel" then
		-- the old box stays (unseen) at its old size; the thing itself is drawn in its place
		body.sx, body.sz = math.min(body.sx, 3.2), math.min(body.sz, 5.5)
		body.sy, body.cy = 1.8, seat + 0.9
		body.color = if kind == "kids_bike"
			then { 60, 120, 170 }
			elseif kind == "wheelbarrow" then { 150, 60, 50 }
			else { 70, 130, 70 }
		if kind == "kids_bike" then
			kidsBike(body, list, seat)
		elseif kind == "wheelbarrow" then
			wheelbarrow(body, list, seat)
		else
			hoseReel(body, list, seat)
		end
	elseif kind == "porch_swing" then
		-- a garden swing: the seat hangs from a top bar on two posts
		body.sy, body.cy = 0.5, seat + 1.6
		body.color, body.material = WOOD, "WoodPlanks"
		local along = body.sx >= body.sz
		local L = math.max(body.sx, body.sz)
		for k, s in { -1, 1 } do
			local px = if along then x + s * (L / 2 + 0.3) else x
			local pz = if along then z else z + s * (L / 2 + 0.3)
			post(list, `SwingPost{k}`, px, pz, seat - 0.3, seat + 6, 0.25, WOOD, "Wood", false)
		end
		add(list, "SwingBar", x, seat + 6, z, if along then L + 1 else 0.4, 0.4, if along then 0.4 else L + 1, {
			color = WOOD,
			material = "Wood",
			canCollide = false,
			role = "Trim",
		})
	elseif kind == "window_box" then
		-- a planter box on the ground with flowers
		body.sy, body.cy = 1.2, seat + 0.6
		body.color, body.material = WOOD, "WoodPlanks"
		add(list, "Flowers", x, seat + 1.5, z, body.sx * 0.9, 0.8, body.sz * 0.9, {
			color = { 196, 84, 104 },
			material = "LeafyGrass",
			canCollide = false,
			role = "Trim",
		})
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
	elseif t == "backyard_prop" and string.find(lot.style or "", "mower", 1, true) then
		mower(body, list, seat)
	elseif t == "shed" then
		shed(body, list)
	end
end

return Props
