--!strict
-- tools/bake/alley/Shell: the bowling alley's structure (brief v2 §13a): the foundation with the three ball-return
-- ducts left open under the lane pairs (the squirrel tunnels), the finished floors, brick walls with the
-- storefront, the roof and parapet, the entrance steps, the alley behind with its paving, retaining edge and
-- fence, the tunnel vents in the foundation, the pylon sign by the parking, and the terrain carve boxes the
-- server applies at boot (Workspace terrain is written over the whole map; the ducts must be air).
-- Interface: build(kit, root, data) -> nothing (adds to root)

local AlleyLayout = require("../../../src/shared/Attractions/AlleyLayout")

local Shell = {}

local L = AlleyLayout
local C = {
	concrete = { 168, 166, 160 },
	foundation = { 150, 147, 140 },
	brick = { 146, 70, 50 },
	brickDark = { 112, 52, 40 },
	trim = { 232, 222, 198 },
	roof = { 58, 60, 64 },
	carpet = { 30, 36, 74 },
	carpetGames = { 70, 30, 46 },
	woodFloor = { 150, 98, 58 },
	bohFloor = { 132, 132, 128 },
	ceiling = { 44, 44, 54 },
	wallLow = { 40, 46, 78 },
	wallHigh = { 96, 118, 150 },
	orange = { 232, 118, 40 },
	teal = { 36, 150, 150 },
	mustard = { 236, 196, 64 },
	glass = { 150, 190, 205 },
	frame = { 60, 62, 66 },
	asphalt = { 66, 68, 70 },
	fence = { 122, 96, 70 },
	ductMetal = { 120, 124, 128 },
	duct = { 84, 86, 90 },
}
Shell.C = C

local FLOOR_BOTTOM = -6.8
local X0, X1 = L.X0 - L.WALL_T, L.X1 + L.WALL_T -- outer faces
local D0, D1 = L.FRONT_D - L.WALL_T, L.REAR_WALL_D + L.WALL_T

local function ductX(p: number): (number, number)
	local x = L.pairX(p)
	return x - L.DUCT_W / 2, x + L.DUCT_W / 2
end

local function foundation(kit: any, root: any)
	local f = kit:model(root, "Foundation")
	-- solid subfloor everywhere except the ducts and the pit zone
	local holes = {}
	for p = 1, 3 do
		local a, b = ductX(p)
		table.insert(holes, { a, b, L.SHAFT_D0, D1 })
	end
	local pitX0, pitX1 = -L.LANE_BLOCK_X, L.LANE_BLOCK_X
	table.insert(holes, { pitX0, pitX1, L.DECK_END, L.PIT_END })
	for i, r in kit:holes(X0, X1, D0, D1, holes) do
		kit:box(f, `Subfloor{i}`, r[1], r[2], FLOOR_BOTTOM, L.DUCT_CEIL, r[3], r[4], C.foundation, "Concrete")
	end
	-- the pit zone: subfloor lower (the pits sit in it), ducts still open
	local pitHoles = {}
	for p = 1, 3 do
		local a, b = ductX(p)
		table.insert(pitHoles, { a, b, L.DECK_END, L.PIT_END })
	end
	for i, r in kit:holes(pitX0, pitX1, L.DECK_END, L.PIT_END, pitHoles) do
		kit:box(f, `PitBase{i}`, r[1], r[2], FLOOR_BOTTOM, L.PIT_Y - 0.15, r[3], r[4], C.foundation, "Concrete")
	end
end

-- The ball-return duct under each pair: floor, the return track, ribbed walls, a ceiling of lane-bed joists,
-- the riser into the hood and the vent through the rear foundation. The squirrel's camera lives in here, so it
-- gets the most care of anything underground.
local function ducts(kit: any, root: any)
	local folder = kit:folder(root, "Tunnels")
	for p = 1, 3 do
		local m = kit:model(folder, `Tunnel{p}`)
		m:SetAttribute("Pair", p)
		local x = L.pairX(p)
		local a, b = ductX(p)
		local floorTop = L.DUCT_FLOOR
		-- floor (a long steel trough on concrete) from the riser to just inside the rear wall
		kit:box(m, "Floor", a, b, FLOOR_BOTTOM, floorTop, L.SHAFT_D0, L.REAR_WALL_D - 1.6, C.duct, "Concrete")
		-- the ramp up from the alley vent (the vent sill is at alley level)
		kit:box(m, "VentSill", a, b, FLOOR_BOTTOM, L.ALLEY_Y, L.REAR_WALL_D + 0.4, D1, C.foundation, "Concrete")
		kit:wedge(
			m,
			"VentRamp",
			x,
			(L.ALLEY_Y + floorTop) / 2 - 0.02,
			L.REAR_WALL_D - 0.6,
			L.DUCT_W,
			floorTop - L.ALLEY_Y + 0.04,
			2.0,
			C.duct,
			"Concrete",
			{ rot = kit.roblox.CFrame.Angles(0, math.pi, 0) }
		)
		kit:box(m, "RampFill", a, b, FLOOR_BOTTOM, L.ALLEY_Y, L.REAR_WALL_D - 1.6, L.REAR_WALL_D + 0.4, C.foundation, "Concrete")
		-- the foundation above the vent opening
		kit:box(m, "VentLintel", a, b, L.ALLEY_Y + 1.55, L.DUCT_CEIL, L.REAR_WALL_D, D1, C.foundation, "Concrete")
		-- return track: two rails the ball rolls on, the length of the duct
		for side = -1, 1, 2 do
			kit:box(
				m,
				"Rail",
				x + side * 0.24 - 0.04,
				x + side * 0.24 + 0.04,
				floorTop,
				floorTop + 0.14,
				L.SHAFT_D1 + 0.2,
				L.REAR_WALL_D - 1.8,
				C.ductMetal,
				"Metal",
				{ collide = false }
			)
		end
		-- walls (sheet steel with ribs every 4 studs); under the pits the ceiling is lower
		local segs = {
			{ L.SHAFT_D0, L.DECK_END, L.DUCT_CEIL },
			{ L.DECK_END, L.PIT_END, L.PIT_Y - 0.15 },
			{ L.PIT_END, L.REAR_WALL_D + 0.4, L.DUCT_CEIL },
		}
		for i, s in segs do
			kit:box(m, `Ceiling{i}`, a - 0.2, b + 0.2, s[3] - 0.08, s[3], s[1], s[2], { 70, 52, 36 }, "WoodPlanks")
		end
		local d = L.SHAFT_D1 + 2
		local n = 0
		while d < L.REAR_WALL_D - 1 do
			n += 1
			local ceil = if d > L.DECK_END and d < L.PIT_END then L.PIT_Y - 0.15 else L.DUCT_CEIL
			for side = -1, 1, 2 do
				kit:box(
					m,
					"Rib",
					x + side * (L.DUCT_W / 2 - 0.06),
					x + side * (L.DUCT_W / 2),
					floorTop,
					ceil,
					d - 0.08,
					d + 0.08,
					C.ductMetal,
					"Metal",
					{ collide = false }
				)
			end
			-- a joist across the ceiling
			kit:box(m, "Joist", a, b, ceil - 0.22, ceil - 0.08, d - 0.1, d + 0.1, { 96, 70, 46 }, "Wood", { collide = false })
			d += 4
		end
		-- small amber maintenance lamps every 16 studs (the run is dark otherwise) and a cool glow at the riser
		local lampD = 6
		while lampD < L.REAR_WALL_D - 4 do
			local ceil = if lampD > L.DECK_END and lampD < L.PIT_END then L.PIT_Y - 0.15 else L.DUCT_CEIL
			local lamp = kit:box(
				m,
				"Lamp",
				b - 0.18,
				b - 0.06,
				ceil - 0.5,
				ceil - 0.3,
				lampD - 0.15,
				lampD + 0.15,
				{ 255, 170, 70 },
				"Neon",
				{ collide = false }
			)
			kit:light(lamp, "PointLight", { Range = 9, Brightness = 0.9, Color = { 255, 176, 96 }, Shadows = false })
			lampD += 16
		end
		-- odds and ends a squirrel would notice: a lost sock, popcorn, a gum wrapper, a spare pin on its side
		kit:box(m, "LostSock", x - 0.5, x - 0.1, floorTop, floorTop + 0.06, 30, 30.6, { 236, 236, 230 }, "Fabric", { collide = false })
		for k = 0, 4 do
			kit:ball(m, "Popcorn", x + 0.45 - k * 0.07, floorTop + 0.05, 22 + k * 0.23, 0.12, { 250, 236, 180 }, "SmoothPlastic", { collide = false })
		end
		kit:box(m, "Wrapper", x + 0.2, x + 0.5, floorTop, floorTop + 0.01, 47, 47.2, { 210, 40, 50 }, "SmoothPlastic", { collide = false })
		kit:cyl(m, "SparePin", x - 0.45, floorTop + 0.2, 70, 1.4, 0.36, "D", { 245, 245, 240 }, "SmoothPlastic", { collide = false })
		-- the riser: a vertical chute from the duct up into the hood
		kit:box(m, "RiserBack", a, b, floorTop, 0, L.SHAFT_D0 - 0.15, L.SHAFT_D0, C.ductMetal, "Metal")
		for side = -1, 1, 2 do
			local wx = if side < 0 then a else b
			kit:box(m, "RiserWall", wx - 0.1, wx + 0.1, floorTop, 0, L.SHAFT_D0, L.SHAFT_D1 + 0.4, C.ductMetal, "Metal", { collide = false })
		end
		local glow = kit:box(m, "RiserGlow", a + 0.1, b - 0.1, -0.6, -0.5, L.SHAFT_D0, L.SHAFT_D0 + 0.12, { 150, 210, 255 }, "Neon", { collide = false })
		kit:light(glow, "PointLight", { Range = 7, Brightness = 1.2, Color = { 170, 210, 255 }, Shadows = false })
		-- the bent vent grille outside, leaning against the foundation beside the opening
		local ventD = D1 + 0.12
		kit:box(m, "VentFrameTop", a - 0.2, b + 0.2, L.ALLEY_Y + 1.35, L.ALLEY_Y + 1.55, D1 - 0.05, ventD, { 90, 92, 96 }, "Metal")
		for side = -1, 1, 2 do
			local wx = if side < 0 then a - 0.1 else b + 0.1
			kit:box(m, "VentFrameSide", wx - 0.1, wx + 0.1, L.ALLEY_Y, L.ALLEY_Y + 1.55, D1 - 0.05, ventD, { 90, 92, 96 }, "Metal")
		end
		local grille = kit:model(m, "Grille")
		local gcf = kit.roblox.CFrame.Angles(-0.35, 0.5, 0.12)
		for k = 0, 5 do
			kit:at(
				grille,
				"Slat",
				b + 1.1,
				L.ALLEY_Y + 0.62,
				D1 + 0.55 + k * 0.001,
				1.5,
				0.06,
				0.06,
				{ 104, 106, 110 },
				"Metal",
				{ collide = false, rot = gcf * kit.roblox.CFrame.new(0, -0.55 + k * 0.22, 0) }
			)
		end
		-- the terrain carve box for this duct (Server/Attractions/AttractionService applies it at boot)
		kit:box(
			root:FindFirstChild("TerrainCarve") or kit:folder(root, "TerrainCarve"),
			`Duct{p}`,
			a - 0.3,
			b + 0.3,
			L.DUCT_FLOOR - 0.05,
			-0.05,
			L.SHAFT_D0 - 0.5,
			D1 + 1.5,
			{ 255, 0, 0 },
			"SmoothPlastic",
			{ collide = false, query = false, transparency = 1, shadow = false }
		)
	end
end

local function floors(kit: any, root: any)
	local f = kit:model(root, "Floors")
	local top, bottom = 0, L.DUCT_CEIL
	-- carpet: settees and concourse (front of the approaches), both aisles
	kit:box(f, "CarpetFront", L.X0, L.GAME_ROOM_X0, bottom, top, L.FRONT_D, L.APPROACH_D, C.carpet, "Fabric")
	kit:box(f, "CarpetLeftAisle", L.X0, -L.LANE_BLOCK_X - 0.4, bottom, top, L.APPROACH_D, L.MACHINE_D1, C.carpet, "Fabric")
	kit:box(f, "CarpetRightAisle", L.LANE_BLOCK_X + 0.4, L.GAME_ROOM_X0, bottom, top, L.APPROACH_D, L.GAME_ROOM_D1, C.carpet, "Fabric")
	-- games room: warm boards
	kit:box(f, "GamesFloor", L.GAME_ROOM_X0, L.X1, bottom, top, L.FRONT_D, L.GAME_ROOM_D1, C.woodFloor, "WoodPlanks")
	-- back of house: sealed concrete behind the machines and in the storeroom wing
	kit:box(f, "BackFloor", L.X0, L.X1, bottom, top, L.MACHINE_D1, L.REAR_WALL_D, C.bohFloor, "Concrete")
	kit:box(f, "StoreFloor", L.LANE_BLOCK_X + 0.4, L.X1, bottom, top, L.GAME_ROOM_D1, L.MACHINE_D1, C.bohFloor, "Concrete")
end

local function walls(kit: any, root: any, data: any)
	local w = kit:model(root, "Walls")
	local H = L.ROOF_Y
	local t = L.WALL_T
	-- rear wall (with the push-bar doors at x -22.5) and side walls
	local doorX0, doorX1 = -24.7, -20.3
	kit:box(w, "RearWallA", X0, doorX0, 0, H, L.REAR_WALL_D, D1, C.brick, "Brick")
	kit:box(w, "RearWallB", doorX1, X1, 0, H, L.REAR_WALL_D, D1, C.brick, "Brick")
	kit:box(w, "RearWallOverDoor", doorX0, doorX1, 7.4, H, L.REAR_WALL_D, D1, C.brick, "Brick")
	kit:box(w, "LeftWall", X0, L.X0, 0, H, L.FRONT_D, L.REAR_WALL_D, C.brick, "Brick")
	kit:box(w, "RightWall", L.X1, X1, 0, H, L.FRONT_D, L.REAR_WALL_D, C.brick, "Brick")
	-- front: storefront glass either side of the entrance, brick piers and a sign band
	local entX0, entX1 = -3.5, 3.5
	kit:box(w, "FrontBaseL", X0, entX0 - 0.8, 0, 1.2, D0, L.FRONT_D, C.brickDark, "Brick")
	kit:box(w, "FrontBaseR", entX1 + 0.8, X1, 0, 1.2, D0, L.FRONT_D, C.brickDark, "Brick")
	kit:box(w, "FrontBand", X0, X1, 7.6, H, D0, L.FRONT_D, C.brick, "Brick")
	local piers = { X0, -18, -10, entX0 - 0.8, entX1, 10, 18, 26, 34, 42, 50 }
	for i, px in piers do
		local w0 = if i == 1 then X0 else px
		local w1 = if i == 1 then L.X0 + 0.6 else px + 0.8
		kit:box(w, "Pier", w0, w1, 1.2, 7.6, D0, L.FRONT_D, C.brick, "Brick")
	end
	kit:box(w, "PierEnd", L.X1 - 0.6, X1, 1.2, 7.6, D0, L.FRONT_D, C.brick, "Brick")
	-- glazing between the piers (not across the entrance)
	local bays = { { L.X0 + 0.6, -18 }, { -17.2, -10 }, { -9.2, entX0 - 0.8 }, { entX1 + 0.8, 10 }, { 10.8, 18 }, { 18.8, 26 }, { 26.8, 34 }, { 34.8, 42 }, { 42.8, 50 }, { 50.8, L.X1 - 0.6 } }
	for _, bay in bays do
		kit:box(w, "Glass", bay[1], bay[2], 1.2, 7.6, D0 + 0.3, L.FRONT_D - 0.3, C.glass, "Glass", { transparency = 0.55, reflectance = 0.15, shadow = false })
		kit:box(w, "Mullion", (bay[1] + bay[2]) / 2 - 0.08, (bay[1] + bay[2]) / 2 + 0.08, 1.2, 7.6, D0 + 0.2, L.FRONT_D - 0.2, C.frame, "Metal")
		kit:box(w, "Transom", bay[1], bay[2], 5.6, 5.75, D0 + 0.2, L.FRONT_D - 0.2, C.frame, "Metal")
	end
	-- the entrance: glass doors propped open, a canopy and the name in lights
	for side = -1, 1, 2 do
		local hingeX = if side < 0 then entX0 else entX1
		kit:at(w, "EntranceDoor", hingeX - side * 0.1, 3.6, L.FRONT_D + 0.3 + 1.6, 0.1, 7.0, 3.2, C.glass, "Glass", {
			collide = false,
			transparency = 0.5,
			reflectance = 0.2,
		})
		kit:at(w, "DoorPull", hingeX - side * 0.25, 3.6, L.FRONT_D + 0.3 + 2.8, 0.1, 2.2, 0.12, { 200, 200, 205 }, "Metal", { collide = false })
	end
	kit:box(w, "DoorHead", entX0, entX1, 7.2, 7.6, D0, L.FRONT_D, C.frame, "Metal")
	kit:box(w, "Canopy", entX0 - 3, entX1 + 3, 7.6, 8.1, D0 - 6, D0, C.trim, "SmoothPlastic")
	kit:box(w, "CanopyFascia", entX0 - 3, entX1 + 3, 7.2, 8.3, D0 - 6.2, D0 - 6, C.orange, "SmoothPlastic")
	local signBand = kit:box(w, "SignBoard", -20, 26, 8.4, 12.4, D0 - 0.35, D0, { 34, 40, 80 }, "SmoothPlastic")
	local g = kit:gui(signBand, "Back", 20)
	kit:label(g, { Text = data.name, TextColor = { 255, 214, 92 }, Font = "FredokaOne", Size = { 0.96, 0.8 }, Pos = { 0.02, 0.1 } })
	for k = 0, 1 do
		kit:box(w, "SignNeon", -20, 26, 8.4 + k * 3.85, 8.55 + k * 3.85, D0 - 0.45, D0 - 0.35, C.teal, "Neon", { collide = false })
	end
	-- parapet and coping
	kit:box(w, "ParapetF", X0, X1, H, H + 1.2, D0, L.FRONT_D, C.brick, "Brick")
	kit:box(w, "ParapetB", X0, X1, H, H + 1.2, L.REAR_WALL_D, D1, C.brick, "Brick")
	kit:box(w, "ParapetL", X0, L.X0, H, H + 1.2, L.FRONT_D, L.REAR_WALL_D, C.brick, "Brick")
	kit:box(w, "ParapetR", L.X1, X1, H, H + 1.2, L.FRONT_D, L.REAR_WALL_D, C.brick, "Brick")
	kit:box(w, "CopingF", X0 - 0.1, X1 + 0.1, H + 1.2, H + 1.4, D0 - 0.1, L.FRONT_D + 0.1, C.trim, "Concrete")
	kit:box(w, "CopingB", X0 - 0.1, X1 + 0.1, H + 1.2, H + 1.4, L.REAR_WALL_D - 0.1, D1 + 0.1, C.trim, "Concrete")
	kit:box(w, "CopingL", X0 - 0.1, L.X0 + 0.1, H + 1.2, H + 1.4, L.FRONT_D, L.REAR_WALL_D, C.trim, "Concrete")
	kit:box(w, "CopingR", L.X1 - 0.1, X1 + 0.1, H + 1.2, H + 1.4, L.FRONT_D, L.REAR_WALL_D, C.trim, "Concrete")
	-- roof deck and ceiling
	kit:box(w, "Roof", L.X0, L.X1, L.CEILING_Y, H, L.FRONT_D, L.REAR_WALL_D, C.roof, "Slate")
	for i, hx in { -10, 20, 44 } do
		kit:box(w, `RoofUnit{i}`, hx - 2.5, hx + 2.5, H, H + 2.6, 10, 16, { 176, 178, 176 }, "Metal")
		kit:box(w, `RoofUnitFan{i}`, hx - 1.4, hx + 1.4, H + 2.6, H + 2.8, 11.6, 14.4, { 90, 92, 92 }, "Metal")
	end
	-- interior partitions: games room (two wide openings), its back wall, the machine room line
	local px0, px1 = L.GAME_ROOM_X0 - 0.3, L.GAME_ROOM_X0 + 0.3
	kit:box(w, "GamesWallA", px0, px1, 0, L.CEILING_Y, L.FRONT_D, -24, C.wallLow, "Plaster")
	kit:box(w, "GamesWallB", px0, px1, 0, L.CEILING_Y, -14, -2, C.wallLow, "Plaster")
	kit:box(w, "GamesWallC", px0, px1, 0, L.CEILING_Y, 8, L.GAME_ROOM_D1, C.wallLow, "Plaster")
	for _, span in { { -24, -14 }, { -2, 8 } } do
		kit:box(w, "GamesHeader", px0, px1, 8.4, L.CEILING_Y, span[1], span[2], C.wallLow, "Plaster")
		kit:box(w, "GamesHeaderTrim", px0 - 0.05, px1 + 0.05, 8.2, 8.4, span[1], span[2], C.orange, "SmoothPlastic", { collide = false })
	end
	kit:box(w, "GamesBackWall", L.GAME_ROOM_X0, L.X1, 0, L.CEILING_Y, L.GAME_ROOM_D1, L.GAME_ROOM_D1 + 0.6, C.wallLow, "Plaster")
	-- the right aisle ends at a wall (storeroom beyond), with a staff door
	local sx0 = L.LANE_BLOCK_X + 0.4
	kit:box(w, "StoreWallA", sx0, sx0 + 2.2, 0, L.CEILING_Y, L.GAME_ROOM_D1, L.GAME_ROOM_D1 + 0.6, C.wallLow, "Plaster")
	kit:box(w, "StoreWallB", sx0 + 5.6, L.GAME_ROOM_X0, 0, L.CEILING_Y, L.GAME_ROOM_D1, L.GAME_ROOM_D1 + 0.6, C.wallLow, "Plaster")
	kit:box(w, "StoreDoorHead", sx0 + 2.2, sx0 + 5.6, 7.2, L.CEILING_Y, L.GAME_ROOM_D1, L.GAME_ROOM_D1 + 0.6, C.wallLow, "Plaster")
	kit:box(w, "StoreSideWall", L.LANE_BLOCK_X + 0.4, L.LANE_BLOCK_X + 1.0, 0, L.CEILING_Y, L.GAME_ROOM_D1, L.MACHINE_D1, C.wallLow, "Plaster")
	-- left aisle: the machine room door at the end (open doorway, a sign over it)
	kit:box(w, "MachineWallL", L.X0, -24.2, 0, L.CEILING_Y, L.MACHINE_D1 - 0.6, L.MACHINE_D1, C.wallLow, "Plaster")
	kit:box(w, "MachineWallR", -20.8, -L.LANE_BLOCK_X - 0.4, 0, L.CEILING_Y, L.MACHINE_D1 - 0.6, L.MACHINE_D1, C.wallLow, "Plaster")
	kit:box(w, "MachineDoorHead", -24.2, -20.8, 7.2, L.CEILING_Y, L.MACHINE_D1 - 0.6, L.MACHINE_D1, C.wallLow, "Plaster")
	-- interior finish on the long walls (dado and band), only where people see them
	kit:box(w, "LeftDado", L.X0, L.X0 + 0.08, 0, 3.4, L.FRONT_D, L.MACHINE_D1 - 0.6, C.wallLow, "Plaster", { collide = false })
	kit:box(w, "LeftUpper", L.X0, L.X0 + 0.06, 3.4, L.CEILING_Y, L.FRONT_D, L.MACHINE_D1 - 0.6, C.wallHigh, "Plaster", { collide = false })
	for k, col in { C.orange, C.mustard, C.teal } do
		kit:box(w, "LeftStripe", L.X0, L.X0 + 0.1, 3.4 + (k - 1) * 0.35, 3.7 + (k - 1) * 0.35, L.FRONT_D, L.MACHINE_D1 - 0.6, col, "SmoothPlastic", { collide = false })
		kit:box(w, "RightStripe", L.X1 - 0.1, L.X1, 3.4 + (k - 1) * 0.35, 3.7 + (k - 1) * 0.35, L.FRONT_D, L.GAME_ROOM_D1, col, "SmoothPlastic", { collide = false })
	end
	-- the rear exit: steel push-bar double doors (hinged; Server/Attractions swings them on E)
	local doors = kit:folder(root, "Doors")
	for side = -1, 1, 2 do
		local hinge = if side < 0 then doorX0 else doorX1
		local leaf = kit:model(doors, if side < 0 then "ExitDoorL" else "ExitDoorR")
		local cx = hinge - side * 1.1
		local panel = kit:at(leaf, "Leaf", cx, 3.6, L.REAR_WALL_D + 0.4, 2.15, 7.2, 0.22, { 116, 122, 128 }, "DiamondPlate")
		kit:at(leaf, "PushBar", cx, 3.4, L.REAR_WALL_D + 0.05, 1.8, 0.22, 0.25, { 200, 200, 196 }, "Metal", { collide = false })
		kit:at(leaf, "PushBarCap", cx - side * 0.95, 3.4, L.REAR_WALL_D + 0.05, 0.25, 0.4, 0.3, { 60, 60, 60 }, "Metal", { collide = false })
		kit:at(leaf, "Kickplate", cx, 0.45, L.REAR_WALL_D + 0.27, 2.1, 0.9, 0.04, { 160, 164, 168 }, "Metal", { collide = false })
		leaf.PrimaryPart = panel
		leaf:SetAttribute("HingeX", hinge)
		leaf:SetAttribute("Side", side)
		leaf:SetAttribute("Door", "push_bar")
	end
	local exitSign = kit:box(doors, "ExitSign", doorX0 + 1.2, doorX1 - 1.2, 7.7, 8.4, L.REAR_WALL_D - 0.25, L.REAR_WALL_D, { 30, 10, 10 }, "SmoothPlastic", { collide = false })
	local eg = kit:gui(exitSign, "Back", 60)
	kit:label(eg, { Text = "EXIT", TextColor = { 255, 60, 50 }, Font = "GothamBlack" })
	kit:box(doors, "ExitSignGlow", doorX0 + 1.25, doorX1 - 1.25, 7.68, 7.72, L.REAR_WALL_D - 0.24, L.REAR_WALL_D - 0.02, { 255, 50, 40 }, "Neon", { collide = false })
	kit:box(doors, "Threshold", doorX0, doorX1, -0.05, 0.02, L.REAR_WALL_D, D1, { 130, 130, 130 }, "Metal")
end

-- Outside: entrance steps, the walk to the bays, the alley behind with its paving, stoop, fence and the
-- retaining edge, and the pylon sign with a giant pin.
local function outside(kit: any, root: any, data: any)
	local o = kit:model(root, "Outside")
	local carve = root:FindFirstChild("TerrainCarve") or kit:folder(root, "TerrainCarve")
	-- entrance landing and steps
	kit:box(o, "Landing", -9, 9, -3.5, 0, D0 - 6.2, D0, C.concrete, "Concrete")
	kit:box(o, "Step", -9, 9, -3.5, -0.35, D0 - 7.3, D0 - 6.2, C.concrete, "Concrete")
	kit:box(o, "Walk", -3, 3, -3.5, -0.72, D0 - 30, D0 - 7.3, C.concrete, "Concrete")
	for _, x in { -8, 8 } do
		kit:box(o, "Planter", x - 1, x + 1, 0, 0.9, D0 - 5.5, D0 - 1.5, C.brickDark, "Brick")
		kit:box(o, "PlanterSoil", x - 0.85, x + 0.85, 0.85, 0.92, D0 - 5.35, D0 - 1.65, { 70, 52, 36 }, "Ground", { collide = false })
		for k = 0, 2 do
			kit:ball(o, "Shrub", x + (k - 1) * 0.5, 1.4, D0 - 2.4 - k * 1.1, 1.3, { 64, 112, 52 }, "Grass", { collide = false })
		end
	end
	kit:box(carve, "Entrance", -9.5, 9.5, -0.8, 6, D0 - 31, D0 + 0.1, { 255, 0, 0 }, "SmoothPlastic", { collide = false, query = false, transparency = 1 })
	-- the alley: asphalt paving at ALLEY_Y, thick enough to meet the ground on the low side
	local ay = L.ALLEY_Y
	kit:box(o, "AlleyPaving", X0 - 2, X1 + 14, ay - 4, ay, D1, L.ALLEY_D1, C.asphalt, "Asphalt")
	kit:box(o, "AlleyKerb", X0 - 2, X1 + 14, ay - 4, ay + 0.35, L.ALLEY_D1, L.ALLEY_D1 + 0.6, C.concrete, "Concrete")
	kit:box(o, "Puddle", 4, 8.5, ay, ay + 0.012, 92, 95.5, { 40, 44, 50 }, "Glass", { collide = false, reflectance = 0.25, shadow = false })
	kit:box(o, "Drain", 20, 21.2, ay, ay + 0.02, 94, 95.2, { 50, 50, 52 }, "DiamondPlate", { collide = false })
	kit:box(carve, "Alley", X0 - 2, X1 + 14, ay - 0.05, ay + 10, D1, L.ALLEY_D1 + 0.6, { 255, 0, 0 }, "SmoothPlastic", { collide = false, query = false, transparency = 1 })
	-- a wooden privacy fence across the far side of the alley
	local fx = X0 - 2
	while fx < X1 + 14 do
		local fx1 = math.min(fx + 8, X1 + 14)
		kit:box(o, "FenceBoards", fx, fx1, ay + 0.35, ay + 6.2, L.ALLEY_D1 + 0.15, L.ALLEY_D1 + 0.4, C.fence, "WoodPlanks")
		kit:box(o, "FencePost", fx, fx + 0.45, ay - 1, ay + 6.5, L.ALLEY_D1 + 0.4, L.ALLEY_D1 + 0.85, { 100, 78, 56 }, "Wood")
		kit:box(o, "FenceRail", fx, fx1, ay + 5.6, ay + 5.9, L.ALLEY_D1 + 0.4, L.ALLEY_D1 + 0.6, { 100, 78, 56 }, "Wood", { collide = false })
		fx = fx1
	end
	-- the stoop at the exit doors: landing, steps down to the alley, pipe railings
	local sx0, sx1 = -27.4, -17.6
	kit:box(o, "Stoop", sx0, sx1, ay - 1, 0, D1, D1 + 3.4, C.concrete, "Concrete")
	local steps = 6
	local rise = -ay / steps
	for k = 1, steps do
		local top = -k * rise
		kit:box(o, "StoopStep", sx0, sx1, ay - 1, top, D1 + 3.4 + (k - 1) * 0.72, D1 + 3.4 + k * 0.72, C.concrete, "Concrete")
	end
	for _, rx in { sx0 + 0.15, sx1 - 0.15 } do
		local p0d, p1d = D1 + 0.4, D1 + 3.4 + steps * 0.72 - 0.3
		kit:cyl(o, "RailPost", rx, 1.6, p0d, 3.2, 0.14, "Y", { 70, 74, 80 }, "Metal", { collide = false })
		kit:cyl(o, "RailPost", rx, 1.6 + ay + 0.4, p1d, 3.2, 0.14, "Y", { 70, 74, 80 }, "Metal", { collide = false })
		kit:cyl(o, "RailTop", rx, 3.2, (p0d + D1 + 3.4) / 2, D1 + 3.4 - p0d, 0.12, "D", { 70, 74, 80 }, "Metal", { collide = false })
		local run = p1d - (D1 + 3.4)
		local drop = 3.2 - (3.2 + ay + 0.4)
		local len = math.sqrt(run * run + drop * drop)
		kit:cyl(o, "RailSlope", rx, 3.2 - drop / 2, D1 + 3.4 + run / 2, len, 0.12, "D", { 70, 74, 80 }, "Metal", {
			collide = false,
			rot = kit.roblox.CFrame.Angles(math.atan2(drop, run), 0, 0),
		})
	end
	-- wall pack light over the door
	local wallPack = kit:box(o, "WallPack", -23.2, -21.8, 8.2, 8.9, D1, D1 + 0.5, { 60, 60, 62 }, "Metal")
	local lens = kit:box(o, "WallPackLens", -23.0, -22.0, 8.15, 8.25, D1 + 0.05, D1 + 0.45, { 255, 236, 200 }, "Neon", { collide = false })
	kit:light(lens, "SpotLight", { Range = 22, Brightness = 2.2, Angle = 110, Face = "Bottom", Color = { 255, 228, 190 } })
	local _ = wallPack
	-- pylon sign by the parking with a giant pin on top
	local pyD, pyX = D0 - 26, 18
	kit:box(o, "PylonFooting", pyX - 1.5, pyX + 1.5, -3.5, -0.4, pyD - 1.5, pyD + 1.5, C.concrete, "Concrete")
	kit:cyl(o, "PylonPole", pyX, 9, pyD, 18.8, 0.9, "Y", { 70, 74, 80 }, "Metal")
	local board = kit:box(o, "PylonBoard", pyX - 6, pyX + 6, 12, 16, pyD - 0.4, pyD + 0.4, { 30, 36, 78 }, "SmoothPlastic")
	for _, face in { "Front", "Back" } do
		local pg = kit:gui(board, face, 12)
		kit:label(pg, { Text = "BOWL", TextColor = { 255, 210, 80 }, Font = "FredokaOne", Size = { 1, 0.62 } })
		kit:label(pg, { Text = "6 LANES - DARTS - POOL", TextColor = { 120, 230, 230 }, Font = "GothamBold", Size = { 1, 0.3 }, Pos = { 0, 0.66 } })
	end
	kit:box(o, "PylonTrim", pyX - 6.2, pyX + 6.2, 11.8, 12.0, pyD - 0.5, pyD + 0.5, C.orange, "Neon", { collide = false })
	kit:box(o, "PylonTrim", pyX - 6.2, pyX + 6.2, 16.0, 16.2, pyD - 0.5, pyD + 0.5, C.orange, "Neon", { collide = false })
	-- the giant pin (x 5 of a lane pin)
	local s = 5
	local base = 16.2
	local profile = { { 0, 0.12, 0.30 }, { 0.10, 0.30, 0.42 }, { 0.28, 0.62, 0.46 }, { 0.60, 0.82, 0.36 }, { 0.80, 1.15, 0.20 } }
	for i, pr in profile do
		kit:cyl(o, `GiantPin{i}`, pyX, base + (pr[1] + pr[2]) / 2 * s, pyD, (pr[2] - pr[1]) * s, pr[3] * s, "Y", { 246, 246, 240 }, "SmoothPlastic")
	end
	kit:ball(o, "GiantPinHead", pyX, base + 1.28 * s, pyD, 0.27 * s, { 246, 246, 240 }, "SmoothPlastic")
	for k = 0, 1 do
		kit:cyl(o, "GiantPinStripe", pyX, base + (0.96 + k * 0.08) * s, pyD, 0.04 * s, 0.205 * s, "Y", { 200, 30, 40 }, "SmoothPlastic")
	end
	local _ = data
end

function Shell.build(kit: any, root: any, data: any)
	kit:folder(root, "TerrainCarve")
	foundation(kit, root)
	ducts(kit, root)
	floors(kit, root)
	walls(kit, root, data)
	outside(kit, root, data)
end

return Shell
