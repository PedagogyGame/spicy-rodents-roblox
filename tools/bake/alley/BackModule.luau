--!strict
-- tools/bake/alley/BackModule: THE INTERIM BACK OF THE HOUSE, everything behind the pinsetters of the
-- eighteen-lane alley (brief v2 §13a "realistic back of house: steel push-bar exit doors to an alley with big
-- round dark-blue used trash cans and a push broom leaning by the door"; addendum D4, D5). The owner's authored
-- backstage (docs/reference/bowling_backstage) goes here when its meshes arrive, placed from the anchor part
-- "ServiceFrontCenter" this file leaves under the alley's root (AlleyLayout.BACKSTAGE: anchor, scale, the volume
-- kept for it). Until then this is a plain service corridor built to be thrown away whole: delete the model
-- "BackModule" and the folder "Doors" and nothing in front of AlleyLayout.BACKSTAGE.interimFrom is touched.
--   BackModule.Structure   foundation (the nine ducts run on under it to their vents), floor, the rear wall and
--                          the two side walls, roof, parapet, the inside paint, tube lights
--   BackModule.Machines    Machine<lane>: the stand-in pinsetter behind each masking unit (tools/bake/alley/Lanes)
--   BackModule.BackOfHouse the mechanic's bench, spare pins, the pin cart, the ball cleaner, lockers, cartons
--   BackModule.RearAlley   the paving, kerb, fence, the stoop and its steps, a ramp down to the grass at each end
--   BackModule.AlleyProps  three big round dark-blue trash cans by the first vents, the push broom leaning by the
--                          door, a dumpster, crates
--   Doors (under the root: Server/Attractions/AttractionService swings them) the steel push-bar exit doors
-- Interface: build(kit, root) -> nothing

local AlleyLayout = require("../../../src/shared/Attractions/AlleyLayout")
local Lanes = require("./Lanes")
local Shell = require("./Shell")

local BackModule = {}
local L = AlleyLayout
local C = Shell.C
local BLACK = { 24, 24, 26 }
local STEEL = { 70, 74, 80 }
local CREAM = { 226, 214, 184 }
local TEAL = { 62, 124, 122 }

local T = L.PARTITION_T
local H = L.ROOF_Y
local CEIL = L.CEILING_Y
local HX1 = L.HALL_X1
local OX0 = L.X0 - L.WALL_T
local OHX1 = HX1 + L.WALL_T
local BACK = L.BACKSTAGE.interimFrom
local R = L.REAR_WALL_D
local D1 = R + L.WALL_T
local HIDDEN = { collide = false, query = false, transparency = 1, shadow = false }

local function structure(kit: any, m: any)
	local s = kit:model(m, "Structure")
	-- foundation, the ducts left open
	local holes = {}
	for p = 1, L.PAIRS do
		local a, b = Shell.ductX(p)
		table.insert(holes, { a, b, BACK, D1 })
	end
	for i, r in kit:holes(OX0, OHX1, BACK, D1, holes) do
		kit:box(s, `Subfloor{i}`, r[1], r[2], Shell.FLOOR_BOTTOM, L.DUCT_CEIL, r[3], r[4], C.foundation, "Concrete")
	end
	-- sealed concrete floor (and the strip under the machines, behind the pits)
	kit:box(s, "BackFloor", L.X0, HX1, L.DUCT_CEIL, 0, BACK, R, C.bohFloor, "Concrete")
	kit:box(
		s,
		"MachineFloor",
		L.LANE_BLOCK_X0,
		L.LANE_BLOCK_X1,
		L.DUCT_CEIL,
		0,
		L.PIT_END + 0.3,
		BACK,
		C.bohFloor,
		"Concrete"
	)
	-- the rear wall with the exit, and the side walls
	local exit = L.opening("exit_doors")
	Shell.wallX(kit, s, "RearWall", OX0, OHX1, R, D1, H, { { exit.a, exit.b, exit.head } }, C.brick, "Brick")
	kit:box(s, "WestWall", OX0, L.X0, 0, H, BACK, R, C.brick, "Brick")
	kit:box(s, "EastWall", HX1, OHX1, 0, H, BACK, R, C.brick, "Brick")
	-- roof, ceiling, parapet and coping
	kit:box(s, "Roof", L.X0, HX1, CEIL, H, BACK, R, C.roof, "Slate")
	kit:box(s, "Ceiling", L.X0, HX1, CEIL - 0.04, CEIL, BACK, R, { 196, 196, 188 }, "SmoothPlastic", {
		collide = false,
		shadow = false,
	})
	local function parapet(name: string, x0: number, x1: number, d0: number, d1: number)
		kit:box(s, "Parapet" .. name, x0, x1, H, H + 1.2, d0, d1, C.brick, "Brick")
		kit:box(s, "Coping" .. name, x0 - 0.1, x1 + 0.1, H + 1.2, H + 1.4, d0 - 0.1, d1 + 0.1, C.trim, "Concrete")
	end
	parapet("Rear", OX0, OHX1, R, D1)
	parapet("West", OX0, L.X0, BACK, R)
	parapet("East", HX1, OHX1, BACK, R)
	-- paint on the inside of the brick: cream above a teal dado, on the rear wall and both ends
	local soft = { collide = false }
	kit:box(s, "PaintRear", L.X0, HX1, 3.2, CEIL, R - 0.06, R, CREAM, "Plaster", soft)
	kit:box(s, "DadoRear", L.X0, HX1, 0, 3.2, R - 0.08, R, TEAL, "Plaster", soft)
	for _, side in { { L.X0, 1 }, { HX1, -1 } } do
		local x, into = side[1], side[2]
		kit:box(
			s,
			"PaintEnd",
			math.min(x, x + into * 0.06),
			math.max(x, x + into * 0.06),
			3.2,
			CEIL,
			BACK,
			R,
			CREAM,
			"Plaster",
			soft
		)
		kit:box(
			s,
			"DadoEnd",
			math.min(x, x + into * 0.08),
			math.max(x, x + into * 0.08),
			0,
			3.2,
			BACK,
			R,
			TEAL,
			"Plaster",
			soft
		)
	end
	-- a yellow safety line along the machines, fluorescent tubes down the corridor (every other one a real light)
	kit:box(
		s,
		"SafetyLine",
		L.X0 + 0.5,
		HX1 - 0.5,
		0,
		0.004,
		BACK + 1.2,
		BACK + 1.4,
		{ 240, 200, 40 },
		"SmoothPlastic",
		{
			collide = false,
			query = false,
		}
	)
	local k = 0
	for x = L.X0 + 8, HX1 - 6, 11 do
		k += 1
		local tube = kit:box(
			s,
			"Tube",
			x - 3,
			x + 3,
			CEIL - 0.5,
			CEIL - 0.35,
			(BACK + R) / 2 - 0.15,
			(BACK + R) / 2 + 0.15,
			{ 240, 250, 255 },
			"Neon",
			{ collide = false, shadow = false }
		)
		if k % 2 == 1 then
			kit:light(tube, "PointLight", { Range = 22, Brightness = 1.1, Color = { 236, 246, 255 }, Shadows = false })
		end
	end
	-- EMPLOYEES ONLY over each aisle's machine-room door, on the hall side
	for _, id in { "machine_door_west", "machine_door_east" } do
		local o = L.opening(id)
		local mid = (o.a + o.b) / 2
		local sign = kit:box(
			s,
			"EmployeesOnly",
			mid - 2.5,
			mid + 2.5,
			o.head + 0.2,
			o.head + 1.2,
			BACK - T - 0.06,
			BACK - T - 0.02,
			{ 200, 30, 30 },
			"SmoothPlastic",
			soft
		)
		kit:label(
			kit:gui(sign, "Back", 40),
			{ Text = "EMPLOYEES ONLY", TextColor = { 255, 255, 255 }, Font = "GothamBlack" }
		)
	end
end

-- The rear exit: steel push-bar double doors (hinged; Server/Attractions/AttractionService swings them on E).
local function doors(kit: any, root: any)
	local folder = kit:folder(root, "Doors")
	local exit = L.opening("exit_doors")
	local doorX0, doorX1 = exit.a, exit.b
	for side = -1, 1, 2 do
		local hinge = if side < 0 then doorX0 else doorX1
		local leaf = kit:model(folder, if side < 0 then "ExitDoorL" else "ExitDoorR")
		local cx = hinge - side * 1.1
		local panel = kit:at(leaf, "Leaf", cx, 3.6, R + 0.4, 2.15, 7.2, 0.22, { 116, 122, 128 }, "DiamondPlate")
		kit:at(leaf, "PushBar", cx, 3.4, R + 0.05, 1.8, 0.22, 0.25, { 200, 200, 196 }, "Metal", { collide = false })
		kit:at(leaf, "PushBarCap", cx - side * 0.95, 3.4, R + 0.05, 0.25, 0.4, 0.3, { 60, 60, 60 }, "Metal", {
			collide = false,
		})
		kit:at(leaf, "Kickplate", cx, 0.45, R + 0.27, 2.1, 0.9, 0.04, { 160, 164, 168 }, "Metal", { collide = false })
		leaf.PrimaryPart = panel
		leaf:SetAttribute("HingeX", hinge)
		leaf:SetAttribute("Side", side)
		leaf:SetAttribute("Door", "push_bar")
	end
	local exitSign = kit:box(
		folder,
		"ExitSign",
		doorX0 + 1.2,
		doorX1 - 1.2,
		7.7,
		8.4,
		R - 0.25,
		R,
		{ 30, 10, 10 },
		"SmoothPlastic",
		{ collide = false }
	)
	kit:label(kit:gui(exitSign, "Back", 60), { Text = "EXIT", TextColor = { 255, 60, 50 }, Font = "GothamBlack" })
	kit:box(
		folder,
		"ExitSignGlow",
		doorX0 + 1.25,
		doorX1 - 1.25,
		7.68,
		7.72,
		R - 0.24,
		R - 0.02,
		{ 255, 50, 40 },
		"Neon",
		{
			collide = false,
		}
	)
	kit:box(folder, "Threshold", doorX0, doorX1, -0.05, 0.02, R, D1, { 130, 130, 130 }, "Metal")
end

local function backOfHouse(kit: any, m: any)
	local b = kit:model(m, "BackOfHouse")
	local d0, d1 = BACK, R
	-- the mechanic's workbench against the rear wall with a vice, tools on a pegboard (AlleyLayout post "bench")
	kit:box(b, "Bench", -12, -2, 0, 3.0, d1 - 2.2, d1, { 90, 70, 50 }, "Wood")
	kit:box(b, "BenchTop", -12.1, -1.9, 3.0, 3.2, d1 - 2.3, d1, { 120, 96, 70 }, "Wood")
	kit:box(
		b,
		"Pegboard",
		-12,
		-2,
		3.8,
		7.6,
		d1 - 0.18,
		d1 - 0.08,
		{ 190, 160, 120 },
		"WoodPlanks",
		{ collide = false }
	)
	for k = 0, 6 do
		kit:box(
			b,
			"Tool",
			-11 + k * 1.3,
			-10.7 + k * 1.3,
			4.6 + (k % 2) * 1.2,
			6.2 + (k % 3) * 0.4,
			d1 - 0.3,
			d1 - 0.2,
			{ 60 + k * 20, 60, 70 },
			"Metal",
			{ collide = false }
		)
	end
	kit:box(b, "Vice", -4.2, -3.2, 3.2, 3.8, d1 - 1.6, d1 - 0.8, { 40, 70, 120 }, "Metal", { collide = false })
	-- spare pins on steel shelving (post "pin_shelf"), and a second bay of it further along
	for _, sx0 in { 4, 58 } do
		kit:box(b, "Shelf", sx0, sx0 + 10, 0, 0.2, d1 - 1.6, d1 - 0.1, { 120, 120, 124 }, "Metal")
		for level = 0, 2 do
			local y = 1.4 + level * 2.0
			kit:box(b, "ShelfBoard", sx0, sx0 + 10, y - 0.1, y, d1 - 1.6, d1 - 0.1, { 120, 120, 124 }, "Metal")
			for k = 0, 7 do
				kit:cyl(
					b,
					"SparePin",
					sx0 + 0.6 + k * 1.2,
					y + 0.73,
					d1 - 0.8,
					1.45,
					0.42,
					"Y",
					{ 245, 245, 240 },
					"SmoothPlastic",
					{ collide = false }
				)
			end
		end
		for _, sx in { sx0, sx0 + 10 } do
			kit:box(b, "ShelfPost", sx - 0.1, sx + 0.1, 0, 6, d1 - 1.6, d1 - 0.1, { 90, 90, 94 }, "Metal")
		end
	end
	-- the pin cart, parked clear of the walk along the machines
	local cd0 = d0 + 6.6
	kit:box(b, "PinCart", 18, 21, 0.6, 2.2, cd0, cd0 + 2, { 200, 120, 30 }, "Metal")
	for _, w in { { 18.4, cd0 + 0.3 }, { 20.6, cd0 + 0.3 }, { 18.4, cd0 + 1.7 }, { 20.6, cd0 + 1.7 } } do
		kit:cyl(b, "CartWheel", w[1], 0.3, w[2], 0.2, 0.6, "X", BLACK, "Rubber" :: any, { collide = false })
	end
	for k = 0, 3 do
		kit:at(b, "CartPin", 18.6 + k * 0.6, 2.5, cd0 + 1, 0.42, 1.45, 0.42, { 245, 245, 240 }, "SmoothPlastic", {
			collide = false,
			shape = "Cylinder",
			rot = kit.roblox.CFrame.Angles(0, 0, 1.2),
		})
	end
	kit:box(b, "BallCleaner", 30, 33, 0, 3.6, d1 - 3, d1 - 0.1, { 60, 120, 160 }, "Metal")
	-- cartons of shoes and paper towels, a mop bucket with its mop
	for k = 0, 5 do
		local bx = 38 + (k % 3) * 2.4
		local by = math.floor(k / 3) * 1.8
		kit:box(b, "Carton", bx, bx + 2.2, by, by + 1.8, d1 - 2.4, d1 - 0.2, { 180, 150, 110 }, "Cardboard" :: any)
	end
	kit:cyl(b, "MopBucket", 49, 0.8, d1 - 1.4, 1.5, 1.7, "Y", { 230, 200, 40 }, "SmoothPlastic")
	kit:cyl(b, "MopHandle", 49.4, 3.2, d1 - 1.4, 4.4, 0.12, "Y", { 170, 130, 80 }, "Wood", {
		collide = false,
		rot = kit.roblox.CFrame.Angles(0.25, 0, 0),
	})
	-- the lane-oiling machine and a row of staff lockers toward the east door
	kit:box(b, "LaneMachine", 73, 77.4, 0.3, 1.9, d1 - 2.6, d1 - 0.4, { 196, 60, 44 }, "Metal")
	kit:box(b, "LaneMachineHandle", 73.3, 77.1, 1.9, 3.3, d1 - 0.7, d1 - 0.5, { 60, 62, 66 }, "Metal", {
		collide = false,
	})
	for k = 0, 4 do
		local lx = 82 + k * 1.7
		kit:box(
			b,
			"Locker",
			lx,
			lx + 1.6,
			0,
			6.4,
			d1 - 1.6,
			d1 - 0.1,
			if k % 2 == 0 then TEAL else { 70, 104, 110 },
			"Metal"
		)
		kit:box(b, "LockerVent", lx + 0.3, lx + 1.3, 5.2, 5.8, d1 - 1.63, d1 - 1.6, { 40, 44, 48 }, "Metal", {
			collide = false,
		})
	end
end

local function rearAlley(kit: any, root: any, m: any)
	local o = kit:model(m, "RearAlley")
	local carve = root:FindFirstChild("TerrainCarve") or kit:folder(root, "TerrainCarve")
	local zone = L.zone("rear_alley")
	local ax0, ax1 = zone.x0, zone.x1
	local ay = L.ALLEY_Y
	-- asphalt paving at ALLEY_Y, thick enough to meet the ground on the low side
	kit:box(o, "AlleyPaving", ax0, ax1, ay - 4.6, ay, D1, L.ALLEY_D1, C.asphalt, "Asphalt")
	kit:box(o, "AlleyKerb", ax0, ax1, ay - 4.6, ay + 0.35, L.ALLEY_D1, L.ALLEY_D1 + 0.6, C.concrete, "Concrete")
	kit:box(o, "Puddle", 4, 8.5, ay, ay + 0.012, 92, 95.5, { 40, 44, 50 }, "Glass", {
		collide = false,
		reflectance = 0.25,
		shadow = false,
	})
	for _, dx in { 20, 70 } do
		kit:box(o, "Drain", dx, dx + 1.2, ay, ay + 0.02, 94, 95.2, { 50, 50, 52 }, "DiamondPlate", { collide = false })
	end
	-- the terrain is cut well below the paving (the voxel ground stands up to a stud above its computed height)
	kit:box(carve, "Alley", ax0, ax1, ay - 2.2, ay + 10, D1, L.ALLEY_D1 + 0.6, { 255, 0, 0 }, "SmoothPlastic", HIDDEN)
	-- each end runs down to the grass on a ramp (the ground is 3 studs below the paving at the west end, 1 at the
	-- east), so the alley is a way round the building and not a dead-end shelf
	local depth = L.ALLEY_D1 - D1
	local midD = (D1 + L.ALLEY_D1) / 2
	local CFrame = kit.roblox.CFrame
	kit:wedge(o, "RampWest", ax0 - 6, ay - 2.3, midD, depth, 4.6, 12, C.asphalt, "Asphalt", {
		rot = CFrame.Angles(0, math.pi / 2, 0),
	})
	kit:wedge(o, "RampEast", ax1 + 4, ay - 2.3, midD, depth, 4.6, 8, C.asphalt, "Asphalt", {
		rot = CFrame.Angles(0, -math.pi / 2, 0),
	})
	-- a wooden privacy fence across the far side of the alley
	local fx = ax0
	while fx < ax1 do
		local fx1 = math.min(fx + 8, ax1)
		kit:box(
			o,
			"FenceBoards",
			fx,
			fx1,
			ay + 0.35,
			ay + 6.2,
			L.ALLEY_D1 + 0.15,
			L.ALLEY_D1 + 0.4,
			C.fence,
			"WoodPlanks"
		)
		kit:box(
			o,
			"FencePost",
			fx,
			fx + 0.45,
			ay - 1,
			ay + 6.5,
			L.ALLEY_D1 + 0.4,
			L.ALLEY_D1 + 0.85,
			{ 100, 78, 56 },
			"Wood"
		)
		kit:box(
			o,
			"FenceRail",
			fx,
			fx1,
			ay + 5.6,
			ay + 5.9,
			L.ALLEY_D1 + 0.4,
			L.ALLEY_D1 + 0.6,
			{ 100, 78, 56 },
			"Wood",
			{
				collide = false,
			}
		)
		fx = fx1
	end
	-- the stoop at the exit doors: landing, steps down to the alley, pipe railings
	local st = L.STOOP
	local sx0, sx1 = st.x0, st.x1
	kit:box(o, "Stoop", sx0, sx1, ay - 1, 0, D1, D1 + st.depth, C.concrete, "Concrete")
	local rise = -ay / st.steps
	for k = 1, st.steps do
		local top = -k * rise
		local sd = D1 + st.depth + (k - 1) * st.tread
		kit:box(o, "StoopStep", sx0, sx1, ay - 1, top, sd, sd + st.tread, C.concrete, "Concrete")
	end
	for _, rx in { sx0 + 0.15, sx1 - 0.15 } do
		local p0d, p1d = D1 + 0.4, D1 + st.depth + st.steps * st.tread - 0.3
		kit:cyl(o, "RailPost", rx, 1.6, p0d, 3.2, 0.14, "Y", STEEL, "Metal", { collide = false })
		kit:cyl(o, "RailPost", rx, 1.6 + ay + 0.4, p1d, 3.2, 0.14, "Y", STEEL, "Metal", { collide = false })
		kit:cyl(o, "RailTop", rx, 3.2, (p0d + D1 + st.depth) / 2, D1 + st.depth - p0d, 0.12, "D", STEEL, "Metal", {
			collide = false,
		})
		kit:rod(o, "RailSlope", rx, 3.2, D1 + st.depth, rx, 3.2 + ay + 0.4, p1d, 0.12, STEEL, "Metal")
	end
	-- wall pack light over the door, and two more down the long wall
	local exit = L.opening("exit_doors")
	for i, wx in { (exit.a + exit.b) / 2, 30, 80 } do
		kit:box(o, "WallPack", wx - 0.7, wx + 0.7, 8.2, 8.9, D1, D1 + 0.5, { 60, 60, 62 }, "Metal")
		local lens = kit:box(
			o,
			"WallPackLens",
			wx - 0.5,
			wx + 0.5,
			8.15,
			8.25,
			D1 + 0.05,
			D1 + 0.45,
			{ 255, 236, 200 },
			"Neon",
			{
				collide = false,
			}
		)
		kit:light(lens, "SpotLight", {
			Range = 22,
			Brightness = 2.2,
			Angle = 110,
			Face = "Bottom",
			Color = { 255, 228, 190 },
			Shadows = i == 1,
		})
	end
end

-- The alley: three big round dark-blue trash cans by the vents, the push broom leaning by the door, a dumpster,
-- a couple of crates and an old lane board.
local function alleyProps(kit: any, m: any)
	local a = kit:model(m, "AlleyProps")
	local ay = L.ALLEY_Y
	local d = D1 + 1.6
	local blue = { 26, 46, 98 }
	local cans = { { -15.6, 0.04 }, { -9.0, -0.06 }, { -3.0, 0.03 } }
	for i, c in cans do
		local cx = c[1]
		local tilt = kit.roblox.CFrame.Angles(c[2], 0, c[2] * 0.6)
		local can = kit:model(a, `TrashCan{i}`)
		kit:cyl(can, "Body", cx, ay + 1.75, d, 3.5, 2.5, "Y", blue, "SmoothPlastic", { rot = tilt })
		for k = 0, 2 do
			kit:cyl(can, "Rib", cx, ay + 0.6 + k * 1.15, d, 0.12, 2.6, "Y", { 22, 40, 86 }, "SmoothPlastic", {
				collide = false,
				rot = tilt,
			})
		end
		kit:cyl(can, "Lid", cx + 0.05, ay + 3.6, d, 0.25, 2.75, "Y", { 30, 52, 108 }, "SmoothPlastic", {
			rot = tilt * kit.roblox.CFrame.Angles(0.06 * i, 0, 0),
		})
		kit:box(
			can,
			"Handle",
			cx - 0.5,
			cx + 0.5,
			ay + 3.75,
			ay + 3.95,
			d - 0.12,
			d + 0.12,
			{ 22, 40, 86 },
			"SmoothPlastic",
			{
				collide = false,
			}
		)
		can:SetAttribute("Forage", "trash_can")
	end
	-- a bag that did not make it in
	kit:ball(a, "TrashBag", -6.3, ay + 0.6, d + 1.4, 1.3, { 30, 30, 32 }, "SmoothPlastic")
	-- the push broom leaning on the wall by the exit door
	local bx, bd = -18.7, D1 + 0.35
	local lean = kit.roblox.CFrame.Angles(0.22, 0, 0.05)
	kit:cyl(
		a,
		"BroomHandle",
		bx,
		2.35,
		bd + 0.55,
		4.8,
		0.13,
		"Y",
		{ 176, 130, 76 },
		"Wood",
		{ collide = false, rot = lean }
	)
	kit:at(a, "BroomHead", bx, 0.18, bd + 1.08, 2.2, 0.32, 0.4, { 90, 64, 40 }, "Wood", { collide = false, rot = lean })
	kit:at(a, "Bristles", bx, 0.05, bd + 1.1, 2.15, 0.12, 0.34, BLACK, "Fabric", { collide = false })
	-- crates and an old lane board leaning on the fence
	kit:box(a, "Crate", 30, 33, ay, ay + 2.4, 97, 100, { 160, 120, 70 }, "WoodPlanks")
	kit:box(a, "Crate", 30.4, 32.6, ay + 2.4, ay + 4.2, 97.5, 99.6, { 150, 112, 64 }, "WoodPlanks")
	kit:at(a, "OldLaneBoard", 40, ay + 3, 100.4, 6, 0.3, 0.7, { 210, 180, 130 }, "Wood", {
		rot = kit.roblox.CFrame.Angles(0.15, 0, 1.2),
	})
	-- a dumpster against the fence, half way along
	local dump = kit:model(a, "Dumpster")
	kit:box(dump, "Body", 56, 64, ay, ay + 3.8, 96.6, 100.6, { 38, 84, 62 }, "Metal")
	kit:at(dump, "Lid", 60, ay + 4.0, 98.6, 8.2, 0.2, 4.2, { 30, 30, 34 }, "SmoothPlastic", {
		rot = kit.roblox.CFrame.Angles(-0.08, 0, 0),
	})
	for _, sx in { 56.2, 63.8 } do
		kit:box(dump, "Pocket", sx - 0.25, sx + 0.25, ay + 1.6, ay + 2.4, 96.4, 96.6, { 30, 66, 50 }, "Metal", {
			collide = false,
		})
	end
	dump:SetAttribute("Forage", "dumpster")
end

function BackModule.build(kit: any, root: any)
	local m = kit:model(root, "BackModule")
	m:SetAttribute("Interim", true)
	m:SetAttribute("ReplacedBy", L.BACKSTAGE.anchorName)
	structure(kit, m)
	local machines = kit:folder(m, "Machines")
	for lane = 1, L.LANES do
		Lanes.machine(kit, machines, lane)
	end
	backOfHouse(kit, m)
	rearAlley(kit, root, m)
	alleyProps(kit, m)
	doors(kit, root)
	-- the anchor the owner's backstage is placed from (its package frame: +X to lane 18, +Y up, +Z to the
	-- customer lanes), with the uniform scale to apply about it
	local bs = L.BACKSTAGE
	local anchor = kit:at(
		root,
		bs.anchorName,
		bs.anchor.x,
		bs.anchor.y,
		bs.anchor.d,
		1,
		0.2,
		1,
		{ 255, 0, 255 },
		"SmoothPlastic",
		HIDDEN
	)
	anchor:SetAttribute("Scale", bs.scale)
	anchor:SetAttribute("AuthoredPitch", bs.authoredPitch)
	anchor:SetAttribute("Bays", bs.bays)
end

return BackModule
