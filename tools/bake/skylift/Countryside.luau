--!strict
-- tools/bake/skylift/Countryside: the farmland under the sky lift's line (review: "the ride is 65 s, and about the
-- first 35 s are 20 to 30 studs over bare grass"). Model xs_lift_country (streaming Default), laid out in the
-- line's own frame (u: studs along the centre line from the base station's mouth toward the summit; v: studs to
-- the right of a cabin going up, the side the trail and the town are on) and set on World/Height:
--   Fields: three fields of strips running across the line (wheat, green crop, ploughed, fallow), each strip in
--     ground-following pieces, with hedgerows along their edges and a few hedgerow oaks;
--   Farm: a red barn, a silo, the farmhouse with its chimney, a fenced paddock and hay bales, on the left of the
--     line where the plain rises toward the hill;
--   Orchard: twelve apple trees in rows beyond the trail;
--   Water: a brook from a spring on the left, under the line (the cabins cross it), under a timber footbridge
--     where it crosses the trail, into a pond in the low ground with reeds;
--   Lane: a gravel farm lane across the line under tower 3, to the trail, with the lift's maintenance hut;
--   Walls: two dry-stone walls across the line.
-- Nothing on the trail (except the footbridge's rails, either side of it), in either venue's site, on a tower's
-- footing, on Lift Road or the car park, or in the cabins' swept volume. Low parts that a walker meets collide;
-- the field strips, the water and the lane are surfaces (they collide; the brook does not).
-- Interface: build(roblox, parent) -> Model; frame() -> (bx, bz, ux, uz, rx, rz) (pure); BUDGET; FIELD_LIFT

local Approach = require("./Approach")
local Common = require("./Common")
local Kit = require("../alley/Kit")
local SkyLift = require("../../../src/shared/Rides/SkyLift")

local Countryside = {}

Countryside.BUDGET = 220
Countryside.FIELD_LIFT = 0.35 -- a field strip's top over the ground (terrain voxels sit up to a stud proud)
Countryside.PIECE = 30 -- ground-following pieces at most this long (the plain rolls gently)

-- colours
local WHEAT = { 202, 176, 98 }
local CROP = { 104, 134, 62 }
local PLOUGH = { 112, 86, 62 }
local FALLOW = { 142, 150, 92 }
local HEDGE = { 74, 102, 56 }
local OAK = { 70, 100, 56 }
local APPLE = { 92, 128, 64 }
local BARN = { 150, 50, 40 }
local ROOF = { 70, 72, 78 }
local WHITE = { 232, 226, 210 }
local STONE = { 140, 136, 126 }
local WATER = { 70, 104, 116 }
local GRAVEL = { 152, 140, 118 }
local TIMBER = { 120, 86, 56 }
local HAY = { 214, 182, 104 }
local REED = { 108, 128, 66 }

-- The line's frame: the base mouth, the unit direction toward the summit's mouth and its right.
function Countryside.frame(): (number, number, number, number, number, number)
	local st = SkyLift.stations()
	local bx, bz = st.base.mouth.x, st.base.mouth.z
	local dx, dz = st.summit.mouth.x - bx, st.summit.mouth.z - bz
	local l = math.sqrt(dx * dx + dz * dz)
	local ux, uz = dx / l, dz / l
	return bx, bz, ux, uz, -uz, ux
end

local function at(u: number, v: number): (number, number)
	local bx, bz, ux, uz, rx, rz = Countryside.frame()
	return bx + ux * u + rx * v, bz + uz * u + rz * v
end

local function ground(x: number, z: number): number
	return Common.ground(x, z)
end

function Countryside.build(roblox: any, parent: any): any
	local kit0 = Common.worldKit(roblox)
	local CFrame = roblox.CFrame
	local m = kit0:model(parent, "xs_lift_country")
	m.ModelStreamingMode = roblox.Enum.ModelStreamingMode.Default
	m:SetAttribute("Family", Common.FAMILY)
	m:SetAttribute("PartBudget", Countryside.BUDGET)
	local _, _, ux, uz = Countryside.frame()
	local lineYaw = math.atan2(-ux, -uz) -- Roblox yaw looking along the line toward the summit
	local seed = 41113
	local function rnd(): number
		seed = (seed * 1103515245 + 12345) % 2147483648
		return seed / 2147483648
	end

	-- a ground-following strip from (u0, v0) to (u1, v1): pieces at most PIECE long, `w` wide, `h` thick, their
	-- tops `lift` over the ground at both ends and the middle (the higher of them)
	local function strip(
		folder: any,
		name: string,
		u0: number,
		v0: number,
		u1: number,
		v1: number,
		w: number,
		h: number,
		lift: number,
		color: { number },
		material: string,
		o: Kit.Opts?
	): number
		local len = math.sqrt((u1 - u0) ^ 2 + (v1 - v0) ^ 2)
		local n = math.max(1, math.ceil(len / Countryside.PIECE))
		for i = 0, n - 1 do
			local fa, fb = i / n, (i + 1) / n
			local ax, az = at(u0 + (u1 - u0) * fa, v0 + (v1 - v0) * fa)
			local bx2, bz2 = at(u0 + (u1 - u0) * fb, v0 + (v1 - v0) * fb)
			local ga, gb = ground(ax, az), ground(bx2, bz2)
			local gm = ground((ax + bx2) / 2, (az + bz2) / 2)
			local over = math.max(0, gm - (ga + gb) / 2)
			local ya, yb = ga + lift + over - h / 2, gb + lift + over - h / 2
			Common.boxW(kit0, folder, name, { ax, ya, az }, { bx2, yb, bz2 }, w, h, color, material, o)
		end
		return n
	end
	-- a block standing on the ground at (u, v), turned `yaw` from the line, its base sunk to the lowest corner
	local function block(
		folder: any,
		name: string,
		u: number,
		v: number,
		yaw: number,
		w: number,
		hgt: number,
		d: number,
		color: { number },
		material: string,
		o: Kit.Opts?
	): (any, number)
		local x, z = at(u, v)
		local lo = math.huge
		for _, c in { { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 }, { 0, 0 } } do
			local cx, cz = at(u + c[1] * d / 2, v + c[2] * w / 2)
			lo = math.min(lo, ground(cx, cz))
		end
		local hi = ground(x, z)
		local base = lo - 0.6
		local top = math.max(hi, lo) + hgt
		local opts: Kit.Opts = table.clone(o or {})
		opts.rot = CFrame.Angles(0, lineYaw + yaw, 0)
		local p = kit0:at(folder, name, x, (base + top) / 2, -z, w, top - base, d, color, material, opts)
		return p, top
	end
	-- a pitched roof over a block: the ridge along the block's local X, two wedges facing it
	local function roof(
		folder: any,
		u: number,
		v: number,
		yaw: number,
		w: number,
		d: number,
		eaves: number,
		rise: number
	)
		local x, z = at(u, v)
		local by = lineYaw + yaw
		local ax, az = math.sin(by), math.cos(by) -- the block's local +Z in the world
		for _, side in { -1, 1 } do
			local half = d / 2 + 0.6
			local cx, cz = x + side * ax * half / 2, z + side * az * half / 2
			kit0:wedge(folder, "Roof", cx, eaves + rise / 2, -cz, w + 1, rise, half, ROOF, "Slate", {
				rot = CFrame.Angles(0, by + (if side > 0 then math.pi else 0), 0),
			})
		end
	end
	local function tree(folder: any, u: number, v: number, h: number, crown: number, color: { number })
		local x, z = at(u, v)
		local g = ground(x, z)
		kit0:cyl(
			folder,
			"Trunk",
			x,
			g + h * 0.3,
			-z,
			h * 0.6 + 0.6,
			math.max(0.6, crown * 0.12),
			"Y",
			Common.BARK,
			"Wood"
		)
		kit0:ball(folder, "Crown", x, g + h * 0.62, -z, crown, color, "Grass", { collide = false, query = false })
	end

	-- the fields: three blocks of strips across the line on its left (v < 0), ends kept off the cabins' way
	local fields = kit0:folder(m, "Fields")
	local palette = { WHEAT, CROP, PLOUGH, FALLOW }
	local strips = 0
	for f, block0 in { { 112, 190 }, { 196, 262 }, { 268, 336 } } do
		local width = (block0[2] - block0[1]) / 4
		for k = 0, 3 do
			local u = block0[1] + width * (k + 0.5)
			local col = palette[((k + f) % #palette) + 1]
			strips += strip(fields, "Strip", u, -38, u, -150, width - 0.6, 1.2, Countryside.FIELD_LIFT, col, "Ground")
		end
	end
	-- hedgerows round the fields (between them and the line, and at their two ends) and a few hedgerow oaks
	local hedges = kit0:folder(m, "Hedges")
	strip(hedges, "Hedge", 108, -32, 340, -32, 2.4, 3.2, 2.3, HEDGE, "Grass")
	strip(hedges, "Hedge", 108, -34, 108, -154, 2.6, 3.2, 2.6, HEDGE, "Grass")
	strip(hedges, "Hedge", 340, -34, 340, -154, 2.6, 3.2, 2.6, HEDGE, "Grass")
	for _, p in { { 108, -32 }, { 193, -32 }, { 265, -32 }, { 340, -96 }, { 108, -150 } } do
		tree(hedges, p[1], p[2], 18 + rnd() * 6, 12 + rnd() * 4, OAK)
	end

	-- the farm, on the left where the plain rises toward the hill
	local farm = kit0:folder(m, "Farm")
	local _, barnTop = block(farm, "Barn", 400, -120, 0, 26, 11, 15, BARN, "WoodPlanks")
	roof(farm, 400, -120, 0, 26, 15, barnTop, 6)
	block(farm, "BarnDoor", 400, -106.8, 0, 0.4, 8, 7, { 92, 34, 28 }, "WoodPlanks")
	local sx, sz = at(372, -128)
	local sg = ground(sx, sz)
	kit0:cyl(farm, "Silo", sx, sg + 11, -sz, 23, 7, "Y", { 176, 178, 172 }, "Metal")
	kit0:ball(farm, "SiloDome", sx, sg + 22.4, -sz, 7, { 150, 152, 148 }, "Metal")
	local _, houseTop = block(farm, "Farmhouse", 436, -150, math.pi / 2, 14, 8, 11, WHITE, "SmoothPlastic")
	roof(farm, 436, -150, math.pi / 2, 14, 11, houseTop, 5)
	block(farm, "Chimney", 432, -150, 0, 1.6, 15, 1.6, { 120, 70, 56 }, "Brick")
	-- the paddock: posts every 15 and two rails a side
	local px0, px1, pv0, pv1 = 412, 470, -78, -112
	local corners = { { px0, pv0 }, { px1, pv0 }, { px1, pv1 }, { px0, pv1 } }
	for i = 1, 4 do
		local a, b = corners[i], corners[i % 4 + 1]
		local len = math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2)
		local n = math.max(1, math.floor(len / 15))
		for k = 0, n - 1 do
			local f = k / n
			block(farm, "Post", a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f, 0, 0.4, 3.6, 0.4, TIMBER, "Wood")
		end
		for _, y in { 1.6, 3.0 } do
			strip(farm, "Rail", a[1], a[2], b[1], b[2], 0.25, 0.3, y, TIMBER, "Wood")
		end
	end
	for k = 0, 3 do
		local u, v = 420 + k * 9, -128 - (k % 2) * 4
		local hx, hz = at(u, v)
		local hg = ground(hx, hz)
		kit0:cyl(farm, "HayBale", hx, hg + 1.3, -hz, 3.2, 2.8, "X", HAY, "Fabric", {
			rot = CFrame.Angles(0, lineYaw + rnd(), 0),
		})
	end

	-- the orchard beyond the trail: three rows of four
	local orchard = kit0:folder(m, "Orchard")
	for i = 0, 3 do
		for j = 0, 2 do
			tree(orchard, 205 + i * 22 + (j % 2) * 8, 112 + j * 20, 9 + rnd() * 2, 7 + rnd() * 1.5, APPLE)
		end
	end

	-- the brook: from a spring on the left, under the line, under the footbridge on the trail, into the pond
	local water = kit0:folder(m, "Water")
	local course = {
		{ 348, -96 },
		{ 366, -60 },
		{ 392, -24 },
		{ 418, 4 },
		{ 440, 40 },
		{ 452, 66 },
		{ 458, 92 },
		{ 462, 128 },
	}
	local ghost: Kit.Opts = { collide = false, query = false, shadow = false }
	for i = 1, #course - 1 do
		local a, b = course[i], course[i + 1]
		strip(water, "Brook", a[1], a[2], b[1], b[2], 4 + i * 0.4, 0.8, 0.12, WATER, "Glass", ghost)
	end
	local pu, pv = 470, 150
	local qx, qz = at(pu, pv)
	local qg = ground(qx, qz)
	for _, dz in { -6, 6 } do
		local ox, oz = at(pu + dz, pv)
		qg = math.max(qg, ground(ox, oz))
	end
	kit0:cyl(water, "Pond", qx, qg + 0.12 - 0.4, -qz, 0.8, 38, "Y", WATER, "Glass", ghost)
	for k = 1, 6 do
		local a = k * math.pi / 3 + rnd() * 0.4
		local x, z = qx + math.cos(a) * 18.5, qz + math.sin(a) * 18.5
		kit0:cyl(water, "Reeds", x, ground(x, z) + 1, -z, 2.4, 2.2, "Y", REED, "Grass", ghost)
	end
	-- the footbridge where the brook crosses the trail: a plank deck on the trail's gravel and a rail each side
	local bu = 458
	local bvTrail = 79.4
	local bridge = kit0:folder(m, "Footbridge")
	local hw = Approach.TRAIL_WIDTH / 2
	for _, side in { -1, 1 } do
		strip(
			bridge,
			"BridgeRail",
			bu - 6,
			bvTrail + side * (hw + 0.4),
			bu + 6,
			bvTrail + side * (hw + 0.4),
			0.3,
			0.3,
			2.9,
			TIMBER,
			"Wood"
		)
		for _, du in { -5.5, 0, 5.5 } do
			block(bridge, "BridgePost", bu + du, bvTrail + side * (hw + 0.4), 0, 0.45, 3.2, 0.45, TIMBER, "Wood")
		end
	end

	-- the farm lane across the line under tower 3, up to the trail, and the lift's maintenance hut beside it
	local lane = kit0:folder(m, "Lane")
	local t3 = SkyLift.towers()[3]
	local bx, bz = Countryside.frame()
	local u3 = (t3.x - bx) * ux + (t3.z - bz) * uz
	strip(lane, "Lane", u3 + 14, -200, u3 + 14, 76, 6, 1.2, 0.3, GRAVEL, "Pebble")
	local _, hutTop = block(lane, "Hut", u3 + 27, -18, 0, 8, 6.5, 6, { 196, 188, 168 }, "Concrete")
	roof(lane, u3 + 27, -18, 0, 8, 6, hutTop, 2.2)
	block(lane, "HutDoor", u3 + 23.85, -18, math.pi / 2, 0.3, 5, 2.4, Common.RED, "Metal")

	-- dry-stone walls across the line
	local walls = kit0:folder(m, "Walls")
	strip(walls, "Wall", 92, -30, 92, 66, 1.3, 2.2, 1.5, STONE, "Slate")
	strip(walls, "Wall", 520, -96, 520, 50, 1.3, 2.2, 1.5, STONE, "Slate")

	m:SetAttribute("Strips", strips)
	return m
end

return Countryside
