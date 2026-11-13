--!strict
-- tools/bake/alley/Shell: the eighteen-lane bowling alley's structure (brief v2 §13a; addendum D5), everything in
-- front of the back module: the foundation with the nine ball-return ducts left open under the lane pairs (the
-- squirrel tunnels), the finished floors room by room, the brick outer walls with the storefront and the main
-- doors, the partitions with every opening of Shared/Attractions/AlleyLayout.OPENINGS, the ceilings, the roof and
-- parapet, the house lights, and the terrain carve boxes the server applies at boot (Workspace terrain is
-- written over the whole map: the ducts must be air, and the front-west corner is cut a little into the slope).
-- The plan is AlleyLayout's: no room, wall line or opening is a number here.
-- What stands behind the pinsetters (the back corridor, the rear wall and exit, the rear alley) is
-- tools/bake/alley/BackModule; the way in from the street is tools/bake/alley/Forecourt.
-- Interface: build(kit, root, data) -> nothing (adds to root); C (the palette); FLOOR_BOTTOM; ductX(p) -> (a, b);
--   wallX(kit, parent, name, xa, xb, d0, d1, y1, openings, color, material) and wallD(...) (a wall with
--   openings { { a, b, head } }: solid between them, a header over each)

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
	ceiling = { 214, 210, 196 },
	ceilingLanes = { 176, 180, 196 },
	ceilingGames = { 206, 192, 164 },
	wallLow = { 40, 46, 78 },
	wallHigh = { 96, 118, 150 },
	plaster = { 218, 208, 186 },
	orange = { 232, 118, 40 },
	teal = { 36, 150, 150 },
	mustard = { 236, 196, 64 },
	glass = { 150, 190, 205 },
	frame = { 60, 62, 66 },
	asphalt = { 66, 68, 70 },
	fence = { 122, 96, 70 },
	ductMetal = { 120, 124, 128 },
	duct = { 84, 86, 90 },
	terrazzo = { 196, 188, 170 },
	lino = { 58, 96, 104 },
	tile = { 204, 198, 188 },
}
Shell.C = C

local FLOOR_BOTTOM = -8
Shell.FLOOR_BOTTOM = FLOOR_BOTTOM
local T = L.PARTITION_T
local H = L.ROOF_Y
local CEIL = L.CEILING_Y
local HX1 = L.HALL_X1
local OX0, OX1 = L.X0 - L.WALL_T, L.X1 + L.WALL_T -- outer faces
local OHX1 = HX1 + L.WALL_T -- the hall's outer east face behind the wing
local OD0 = L.FRONT_D - L.WALL_T
local GD1 = L.GAME_ROOM_D1
local BACK = L.BACKSTAGE.interimFrom -- the back module starts here
local CD = L.CONCOURSE_D0

function Shell.ductX(p: number): (number, number)
	local x = L.pairX(p)
	return x - L.DUCT_W / 2, x + L.DUCT_W / 2
end
local ductX = Shell.ductX

-- A wall across the building (thickness d0 .. d1) from xa to xb, floor to y1, with openings { { a, b, head } }.
function Shell.wallX(
	kit: any,
	parent: any,
	name: string,
	xa: number,
	xb: number,
	d0: number,
	d1: number,
	y1: number,
	openings: { { number } },
	color: { number },
	material: string
)
	table.sort(openings, function(p, q)
		return p[1] < q[1]
	end)
	local x = xa
	for _, o in openings do
		if o[1] > x + 1e-6 then
			kit:box(parent, name, x, o[1], 0, y1, d0, d1, color, material)
		end
		if o[3] < y1 - 1e-6 then
			kit:box(parent, name .. "Head", o[1], o[2], o[3], y1, d0, d1, color, material)
		end
		x = o[2]
	end
	if xb > x + 1e-6 then
		kit:box(parent, name, x, xb, 0, y1, d0, d1, color, material)
	end
end

-- A wall down the building (thickness x0 .. x1) from da to db, with openings { { a, b, head } }.
function Shell.wallD(
	kit: any,
	parent: any,
	name: string,
	x0: number,
	x1: number,
	da: number,
	db: number,
	y1: number,
	openings: { { number } },
	color: { number },
	material: string
)
	table.sort(openings, function(p, q)
		return p[1] < q[1]
	end)
	local d = da
	for _, o in openings do
		if o[1] > d + 1e-6 then
			kit:box(parent, name, x0, x1, 0, y1, d, o[1], color, material)
		end
		if o[3] < y1 - 1e-6 then
			kit:box(parent, name .. "Head", x0, x1, o[3], y1, o[1], o[2], color, material)
		end
		d = o[2]
	end
	if db > d + 1e-6 then
		kit:box(parent, name, x0, x1, 0, y1, d, db, color, material)
	end
end

-- The openings of AlleyLayout on one wall line: { { a, b, head } }.
local function openingsOn(axis: string, at: number): { { number } }
	local out = {}
	for _, o in L.OPENINGS do
		if o.axis == axis and math.abs(o.at - at) < 1e-6 then
			table.insert(out, { o.a, o.b, o.head })
		end
	end
	return out
end
Shell.openingsOn = openingsOn

local function foundation(kit: any, root: any)
	local f = kit:model(root, "Foundation")
	-- solid subfloor under the hall and the front rooms, except the ducts and the pit zone
	local holes = {}
	for p = 1, L.PAIRS do
		local a, b = ductX(p)
		table.insert(holes, { a, b, L.SHAFT_D0, BACK })
	end
	table.insert(holes, { L.LANE_BLOCK_X0, L.LANE_BLOCK_X1, L.DECK_END, L.PIT_END })
	for i, r in kit:holes(OX0, OHX1, OD0, BACK, holes) do
		kit:box(f, `Subfloor{i}`, r[1], r[2], FLOOR_BOTTOM, L.DUCT_CEIL, r[3], r[4], C.foundation, "Concrete")
	end
	-- the pit zone: subfloor lower (the pits sit in it), ducts still open
	local pitHoles = {}
	for p = 1, L.PAIRS do
		local a, b = ductX(p)
		table.insert(pitHoles, { a, b, L.DECK_END, L.PIT_END })
	end
	for i, r in kit:holes(L.LANE_BLOCK_X0, L.LANE_BLOCK_X1, L.DECK_END, L.PIT_END, pitHoles) do
		kit:box(f, `PitBase{i}`, r[1], r[2], FLOOR_BOTTOM, L.PIT_Y - 0.15, r[3], r[4], C.foundation, "Concrete")
	end
	-- the games wing stands on its own plinth (the ground falls away to the east: up to 7 studs of it shows)
	kit:box(f, "WingBase", OHX1, OX1, FLOOR_BOTTOM - 2, L.DUCT_CEIL, OD0, GD1 + L.WALL_T, C.foundation, "Concrete")
end

-- The ball-return duct under each pair: floor, the return track, ribbed walls, a ceiling of lane-bed joists,
-- the riser into the hood and the vent through the rear foundation. The squirrel's camera lives in here, so it
-- gets the most care of anything underground. (A tunnel runs on under the back module to its vent in the rear
-- foundation: the one thing behind the pinsetters that is not the back module's.)
local function ducts(kit: any, root: any)
	local folder = kit:folder(root, "Tunnels")
	local D1 = L.REAR_WALL_D + L.WALL_T
	for p = 1, L.PAIRS do
		local m = kit:model(folder, `Tunnel{p}`)
		m:SetAttribute("Pair", p)
		local x = L.pairX(p)
		local a, b = ductX(p)
		local floorTop = L.DUCT_FLOOR
		-- floor (a long steel trough on concrete) from the riser to just inside the rear wall
		kit:box(m, "Floor", a, b, FLOOR_BOTTOM, floorTop, L.SHAFT_D0, L.REAR_WALL_D - 1.6, C.duct, "Concrete")
		-- the ramp up from the alley vent (the vent sill is at alley level): low at the vent, high at the duct
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
			"Concrete"
		)
		kit:box(
			m,
			"RampFill",
			a,
			b,
			FLOOR_BOTTOM,
			L.ALLEY_Y,
			L.REAR_WALL_D - 1.6,
			L.REAR_WALL_D + 0.4,
			C.foundation,
			"Concrete"
		)
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
		local ribN = 0
		while d < L.REAR_WALL_D - 1 do
			local ceil = if d > L.DECK_END and d < L.PIT_END then L.PIT_Y - 0.15 else L.DUCT_CEIL
			ribN += 1
			for side = -1, if ribN % 2 == 1 then 1 else -2, 2 do
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
			kit:box(
				m,
				"Joist",
				a,
				b,
				ceil - 0.22,
				ceil - 0.08,
				d - 0.1,
				d + 0.1,
				{ 96, 70, 46 },
				"Wood",
				{ collide = false }
			)
			d += 4
		end
		-- small amber maintenance lamps every 10 studs, alternating walls (the run is dark otherwise): every lamp
		-- glows, every other one is a real light (nine tunnels: the lights are counted), and a cool glow at the
		-- riser where the light at the end of the tunnel comes from
		local lampD = 4
		local lampSide = 1
		local lampN = 0
		while lampD < L.REAR_WALL_D - 3 do
			lampN += 1
			local ceil = if lampD > L.DECK_END and lampD < L.PIT_END then L.PIT_Y - 0.15 else L.DUCT_CEIL
			local lx0 = if lampSide > 0 then b - 0.18 else a + 0.06
			local lamp = kit:box(
				m,
				"Lamp",
				lx0,
				lx0 + 0.12,
				ceil - 0.5,
				ceil - 0.3,
				lampD - 0.15,
				lampD + 0.15,
				{ 255, 170, 70 },
				"Neon",
				{ collide = false }
			)
			if lampN % 2 == 1 then
				kit:light(
					lamp,
					"PointLight",
					{ Range = 15, Brightness = 1.4, Color = { 255, 176, 96 }, Shadows = false }
				)
			end
			lampD += 10
			lampSide = -lampSide
		end
		-- odds and ends a squirrel would notice: a lost sock, popcorn, a gum wrapper, a spare pin on its side
		kit:box(
			m,
			"LostSock",
			x - 0.5,
			x - 0.1,
			floorTop,
			floorTop + 0.06,
			30,
			30.6,
			{ 236, 236, 230 },
			"Fabric",
			{ collide = false }
		)
		for k = 0, 4 do
			kit:ball(
				m,
				"Popcorn",
				x + 0.45 - k * 0.07,
				floorTop + 0.05,
				22 + k * 0.23,
				0.12,
				{ 250, 236, 180 },
				"SmoothPlastic",
				{ collide = false }
			)
		end
		kit:box(
			m,
			"Wrapper",
			x + 0.2,
			x + 0.5,
			floorTop,
			floorTop + 0.01,
			47,
			47.2,
			{ 210, 40, 50 },
			"SmoothPlastic",
			{ collide = false }
		)
		kit:cyl(
			m,
			"SparePin",
			x - 0.45,
			floorTop + 0.2,
			70,
			1.4,
			0.36,
			"D",
			{ 245, 245, 240 },
			"SmoothPlastic",
			{ collide = false }
		)
		-- the riser: a vertical chute from the duct up into the hood
		kit:box(m, "RiserBack", a, b, floorTop, 0, L.SHAFT_D0 - 0.15, L.SHAFT_D0, C.ductMetal, "Metal")
		for side = -1, 1, 2 do
			local wx = if side < 0 then a else b
			kit:box(
				m,
				"RiserWall",
				wx - 0.1,
				wx + 0.1,
				floorTop,
				0,
				L.SHAFT_D0,
				L.SHAFT_D1 + 0.4,
				C.ductMetal,
				"Metal",
				{ collide = false }
			)
		end
		local glow = kit:box(
			m,
			"RiserGlow",
			a + 0.1,
			b - 0.1,
			-0.6,
			-0.5,
			L.SHAFT_D0,
			L.SHAFT_D0 + 0.12,
			{ 150, 210, 255 },
			"Neon",
			{ collide = false }
		)
		kit:light(glow, "PointLight", { Range = 7, Brightness = 1.2, Color = { 170, 210, 255 }, Shadows = false })
		-- the bent vent grille outside, leaning against the foundation beside the opening
		local ventD = D1 + 0.12
		kit:box(
			m,
			"VentFrameTop",
			a - 0.2,
			b + 0.2,
			L.ALLEY_Y + 1.35,
			L.ALLEY_Y + 1.55,
			D1 - 0.05,
			ventD,
			{ 90, 92, 96 },
			"Metal"
		)
		for side = -1, 1, 2 do
			local wx = if side < 0 then a - 0.1 else b + 0.1
			kit:box(
				m,
				"VentFrameSide",
				wx - 0.1,
				wx + 0.1,
				L.ALLEY_Y,
				L.ALLEY_Y + 1.55,
				D1 - 0.05,
				ventD,
				{ 90, 92, 96 },
				"Metal"
			)
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
			L.DUCT_FLOOR - 1.0, -- below the duct floor part too: voxels are 4 studs, the floor slab hides the rest
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
	-- carpet: the concourse and the settees (front of the approaches), both aisles
	kit:box(f, "CarpetConcourse", L.X0, HX1, bottom, top, CD, L.APPROACH_D, C.carpet, "Fabric")
	kit:box(f, "CarpetLeftAisle", L.X0, L.LANE_BLOCK_X0, bottom, top, L.APPROACH_D, BACK, C.carpet, "Fabric")
	kit:box(f, "CarpetRightAisle", L.LANE_BLOCK_X1, HX1, bottom, top, L.APPROACH_D, BACK, C.carpet, "Fabric")
	-- the front rooms, each with its own floor (between the cross walls' centre lines)
	local finish: { [string]: { any } } = {
		ball_shop = { C.lino, "SmoothPlastic" },
		shoe_rental = { C.carpet, "Fabric" },
		lobby = { C.terrazzo, "Marble" },
		gift_shop = { C.woodFloor, "WoodPlanks" },
		snack_bar = { C.tile, "Marble" },
		lockers = { C.carpet, "Fabric" },
	}
	local lines = { L.X0 }
	for _, x in L.FRONT_WALLS_X do
		table.insert(lines, x)
	end
	table.insert(lines, HX1)
	for i, id in { "ball_shop", "shoe_rental", "lobby", "gift_shop", "snack_bar", "lockers" } do
		local fin = finish[id]
		kit:box(f, `Floor_{id}`, lines[i], lines[i + 1], bottom, top, L.FRONT_D, CD, fin[1], fin[2])
	end
	-- games room: warm boards
	kit:box(f, "GamesFloor", HX1, L.X1, bottom, top, L.GAME_ROOM_D0, GD1, C.woodFloor, "WoodPlanks")
end

-- The storefront between xa and xb: a brick base course, piers about every 8 studs, glass between them with a
-- mullion and a transom, and the brick band above.
local function glazedFront(kit: any, w: any, xa: number, xb: number)
	local n = math.max(1, math.floor((xb - xa) / 8 + 0.5))
	local bay = (xb - xa) / n
	kit:box(w, "FrontBase", xa, xb, 0, 1.2, OD0, L.FRONT_D, C.brickDark, "Brick")
	kit:box(w, "FrontBand", xa, xb, 7.6, H, OD0, L.FRONT_D, C.brick, "Brick")
	for i = 1, n + 1 do
		local c = xa + (i - 1) * bay
		local p0, p1 = math.max(xa, c - 0.4), math.min(xb, c + 0.4)
		kit:box(w, "Pier", p0, p1, 1.2, 7.6, OD0, L.FRONT_D, C.brick, "Brick")
		if i <= n then
			local g0, g1 = p1, math.min(xb, c + bay - 0.4)
			kit:box(
				w,
				"Glass",
				g0,
				g1,
				1.2,
				7.6,
				OD0 + 0.3,
				L.FRONT_D - 0.3,
				C.glass,
				"Glass",
				{ transparency = 0.55, reflectance = 0.15, shadow = false }
			)
			kit:box(
				w,
				"Mullion",
				(g0 + g1) / 2 - 0.08,
				(g0 + g1) / 2 + 0.08,
				1.2,
				7.6,
				OD0 + 0.2,
				L.FRONT_D - 0.2,
				C.frame,
				"Metal"
			)
			kit:box(w, "Transom", g0, g1, 5.6, 5.75, OD0 + 0.2, L.FRONT_D - 0.2, C.frame, "Metal")
		end
	end
end

local function sign(kit: any, parent: any, name: string, x0: number, x1: number, y0: number, y1: number, text: string)
	local board = kit:box(parent, name, x0, x1, y0, y1, OD0 - 0.3, OD0, { 34, 40, 80 }, "SmoothPlastic")
	kit:label(kit:gui(board, "Back", 20), {
		Text = text,
		TextColor = { 255, 214, 92 },
		Font = "FredokaOne",
		Size = { 0.94, 0.8 },
		Pos = { 0.03, 0.1 },
	})
	return board
end

local function walls(kit: any, root: any, data: any)
	local w = kit:model(root, "Walls")
	-- side walls: the west wall, the games wing's east wall and back wall, the hall's east wall behind the wing
	kit:box(w, "WestWall", OX0, L.X0, 0, H, L.FRONT_D, BACK, C.brick, "Brick")
	kit:box(w, "WingEastWall", L.X1, OX1, 0, H, L.FRONT_D, GD1 + L.WALL_T, C.brick, "Brick")
	kit:box(w, "WingBackWall", HX1, L.X1, 0, H, GD1, GD1 + L.WALL_T, C.brick, "Brick")
	kit:box(w, "HallEastWall", HX1, OHX1, 0, H, GD1 + L.WALL_T, BACK, C.brick, "Brick")
	-- the front, west to east: the ball shop's windows, the shoe rental's blank wall, the lobby with the main
	-- doors, the gift shop's windows, the snack bar's and the lockers' blank wall, the games room (blank behind
	-- the pinball machines, windows beyond)
	local ent = L.ENTRANCE
	local fw = L.FRONT_WALLS_X
	glazedFront(kit, w, OX0, fw[1])
	kit:box(w, "FrontSolid", fw[1], fw[2], 0, H, OD0, L.FRONT_D, C.brick, "Brick")
	glazedFront(kit, w, fw[2], ent.x0 - 0.8)
	glazedFront(kit, w, ent.x1 + 0.8, fw[3])
	glazedFront(kit, w, fw[3], fw[4])
	local pinballEnd = L.PINBALLS[#L.PINBALLS].x + 6
	kit:box(w, "FrontSolid", fw[4], pinballEnd, 0, H, OD0, L.FRONT_D, C.brick, "Brick")
	glazedFront(kit, w, pinballEnd, OX1)
	kit:box(w, "FrontTrim", OX0 - 0.05, OX1 + 0.05, 7.6, 7.85, OD0 - 0.08, OD0, C.trim, "Concrete", {
		collide = false,
	})
	-- the main doors: brick jambs, glass leaves propped open, a canopy and the name in lights
	for side = -1, 1, 2 do
		local jamb = if side < 0 then ent.x0 - 0.8 else ent.x1
		kit:box(w, "DoorJamb", jamb, jamb + 0.8, 0, 7.6, OD0, L.FRONT_D, C.brick, "Brick")
		local hingeX = if side < 0 then ent.x0 else ent.x1
		kit:at(w, "EntranceDoor", hingeX - side * 0.1, 3.6, L.FRONT_D + 0.3 + 1.8, 0.1, 7.0, 3.6, C.glass, "Glass", {
			collide = false,
			transparency = 0.5,
			reflectance = 0.2,
		})
		kit:at(
			w,
			"DoorPull",
			hingeX - side * 0.25,
			3.6,
			L.FRONT_D + 0.3 + 3.2,
			0.1,
			2.2,
			0.12,
			{ 200, 200, 205 },
			"Metal",
			{ collide = false }
		)
	end
	kit:box(w, "DoorHead", ent.x0, ent.x1, 7.2, 7.6, OD0, L.FRONT_D, C.frame, "Metal")
	kit:box(w, "DoorBand", ent.x0 - 0.8, ent.x1 + 0.8, 7.6, H, OD0, L.FRONT_D, C.brick, "Brick")
	kit:box(w, "Canopy", ent.x0 - 4, ent.x1 + 4, 7.85, 8.35, OD0 - 7, OD0, C.trim, "SmoothPlastic")
	kit:box(w, "CanopyFascia", ent.x0 - 4, ent.x1 + 4, 7.45, 8.55, OD0 - 7.2, OD0 - 7, C.orange, "SmoothPlastic")
	for side = -1, 1, 2 do
		local px = (ent.x0 + ent.x1) / 2 + side * ((ent.x1 - ent.x0) / 2 + 3.4)
		kit:cyl(w, "CanopyPost", px, 3.9, OD0 - 6.4, 7.9, 0.5, "Y", C.frame, "Metal")
	end
	local mid = (ent.x0 + ent.x1) / 2
	sign(kit, w, "SignBoard", mid - 19, mid + 19, 8.8, 12.8, data.name)
	for k = 0, 1 do
		kit:box(
			w,
			"SignNeon",
			mid - 19,
			mid + 19,
			8.8 + k * 3.85,
			8.95 + k * 3.85,
			OD0 - 0.4,
			OD0 - 0.3,
			C.teal,
			"Neon",
			{ collide = false }
		)
	end
	-- what is behind each stretch of the front
	sign(kit, w, "SignBallShop", -23, -5, 9.2, 11.6, "PRO SHOP - BOWLING BALLS")
	sign(kit, w, "SignGifts", 44.5, 53.5, 9.2, 11.6, "GIFTS")
	sign(kit, w, "SignSnack", 61, 81, 9.2, 11.6, "SNACK BAR - NACHOS 5c")
	sign(kit, w, "SignGames", 106, 145, 9.2, 11.6, "GAMES ROOM - POOL - PINBALL - AIR HOCKEY - DARTS")
	-- parapet and coping round the roof (the rear's are the back module's)
	local function parapet(name: string, x0: number, x1: number, d0: number, d1: number)
		kit:box(w, "Parapet" .. name, x0, x1, H, H + 1.2, d0, d1, C.brick, "Brick")
		kit:box(w, "Coping" .. name, x0 - 0.1, x1 + 0.1, H + 1.2, H + 1.4, d0 - 0.1, d1 + 0.1, C.trim, "Concrete")
	end
	parapet("Front", OX0, OX1, OD0, L.FRONT_D)
	parapet("West", OX0, L.X0, L.FRONT_D, BACK)
	parapet("WingEast", L.X1, OX1, L.FRONT_D, GD1 + L.WALL_T)
	parapet("WingBack", OHX1, L.X1, GD1, GD1 + L.WALL_T)
	parapet("HallEast", HX1, OHX1, GD1, BACK)
	-- roof deck (the ceilings hang under it) and the plant on it
	kit:box(w, "Roof", L.X0, HX1, CEIL, H, L.FRONT_D, BACK, C.roof, "Slate")
	kit:box(w, "RoofWing", HX1, L.X1, CEIL, H, L.FRONT_D, GD1, C.roof, "Slate")
	for i, at in { { -10, 13 }, { 20, 13 }, { 50, 13 }, { 80, 13 }, { 36, -40 }, { 125, -20 } } do
		local hx, hd = at[1], at[2]
		kit:box(w, `RoofUnit{i}`, hx - 2.5, hx + 2.5, H, H + 2.6, hd - 3, hd + 3, { 176, 178, 176 }, "Metal")
		kit:box(w, `RoofUnitFan{i}`, hx - 1.4, hx + 1.4, H + 2.6, H + 2.8, hd - 1.4, hd + 1.4, { 90, 92, 92 }, "Metal")
	end
	-- the games-room partition with its two cased openings
	Shell.wallD(kit, w, "GamesWall", HX1, HX1 + T, L.FRONT_D, GD1, CEIL, openingsOn("d", HX1), C.wallHigh, "Plaster")
	for _, id in { "games_arch", "games_side" } do
		local o = L.opening(id)
		kit:box(
			w,
			"GamesHeaderTrim",
			HX1 - 0.05,
			HX1 + T + 0.05,
			o.head - 0.2,
			o.head,
			o.a,
			o.b,
			C.orange,
			"SmoothPlastic",
			{ collide = false }
		)
	end
	-- the wall between the front rooms and the concourse: doors, serving openings, the open lobby and lockers
	Shell.wallX(kit, w, "FrontRoomsWall", L.X0, HX1, CD - T, CD, CEIL, openingsOn("x", CD), C.wallHigh, "Plaster")
	for _, o in L.OPENINGS do
		if o.axis == "x" and o.at == CD then
			kit:box(
				w,
				"OpeningTrim",
				o.a,
				o.b,
				o.head - 0.2,
				o.head,
				CD - T - 0.05,
				CD + 0.05,
				if o.kind == "open" then C.mustard else C.orange,
				"SmoothPlastic",
				{ collide = false }
			)
		end
	end
	-- the front rooms' cross walls (the shoe desk's serving opening is in the one beside the lobby): light
	-- plaster, so the lobby a newcomer walks into and the shops are bright rooms, not navy boxes
	for _, x in fw do
		Shell.wallD(
			kit,
			w,
			"CrossWall",
			x - T / 2,
			x + T / 2,
			L.FRONT_D,
			CD - T,
			CEIL,
			openingsOn("d", x),
			C.plaster,
			"Plaster"
		)
	end
	-- each aisle ends at the machine-room wall (an open doorway; the back module is beyond)
	local md = L.MACHINE_D1
	Shell.wallX(kit, w, "MachineWall", L.X0, L.LANE_BLOCK_X0 - 0.3, md - T, md, CEIL, {
		{ L.opening("machine_door_west").a, L.opening("machine_door_west").b, L.opening("machine_door_west").head },
	}, C.wallLow, "Plaster")
	Shell.wallX(kit, w, "MachineWall", L.LANE_BLOCK_X1 + 0.3, HX1, md - T, md, CEIL, {
		{ L.opening("machine_door_east").a, L.opening("machine_door_east").b, L.opening("machine_door_east").head },
	}, C.wallLow, "Plaster")
	-- interior finish on the hall's long walls (dado, upper wall and three stripes), where people see them
	local function finishWall(name: string, x: number, into: number, d0: number, d1: number)
		local a0, a1 = math.min(x, x + into * 0.08), math.max(x, x + into * 0.08)
		kit:box(w, name .. "Dado", a0, a1, 0, 3.4, d0, d1, C.wallLow, "Plaster", { collide = false })
		local b0, b1 = math.min(x, x + into * 0.06), math.max(x, x + into * 0.06)
		kit:box(w, name .. "Upper", b0, b1, 3.4, CEIL, d0, d1, C.wallHigh, "Plaster", { collide = false })
		local s0, s1 = math.min(x, x + into * 0.1), math.max(x, x + into * 0.1)
		for k, col in { C.orange, C.mustard, C.teal } do
			kit:box(
				w,
				name .. "Stripe",
				s0,
				s1,
				3.4 + (k - 1) * 0.35,
				3.7 + (k - 1) * 0.35,
				d0,
				d1,
				col,
				"SmoothPlastic",
				{ collide = false }
			)
		end
	end
	finishWall("West", L.X0, 1, CD, md - T)
	finishWall("East", HX1, -1, L.opening("games_side").b, md - T)
	-- plaster on the inside of the brick front, above the glass and over the blank stretches
	kit:box(w, "FrontLinerHigh", L.X0, L.X1, 7.6, CEIL, L.FRONT_D, L.FRONT_D + 0.06, C.plaster, "Plaster", {
		collide = false,
	})
	kit:box(w, "FrontLiner", fw[1], fw[2], 0, 7.6, L.FRONT_D, L.FRONT_D + 0.06, C.plaster, "Plaster", {
		collide = false,
	})
	kit:box(w, "FrontLiner", fw[4], pinballEnd, 0, 7.6, L.FRONT_D, L.FRONT_D + 0.06, C.plaster, "Plaster", {
		collide = false,
	})
	kit:box(w, "WestLinerShop", L.X0, L.X0 + 0.06, 0, CEIL, L.FRONT_D, CD - T, C.plaster, "Plaster", {
		collide = false,
	})
end

-- Real ceilings under the roof deck: light acoustic tile over the front rooms and the concourse, a cooler tone
-- over the lanes, a warm one in the games room. (A lamp's housing hangs a little below them.)
local function ceilings(kit: any, root: any)
	local m = kit:model(root, "Ceilings")
	local opts = { collide = false, shadow = false }
	kit:box(m, "CeilingFront", L.X0, HX1, CEIL - 0.04, CEIL, L.FRONT_D, L.APPROACH_D, C.ceiling, "SmoothPlastic", opts)
	kit:box(m, "CeilingLanes", L.X0, HX1, CEIL - 0.04, CEIL, L.APPROACH_D, BACK, C.ceilingLanes, "SmoothPlastic", opts)
	kit:box(m, "CeilingGames", HX1 + T, L.X1, CEIL - 0.04, CEIL, L.FRONT_D, GD1, C.ceilingGames, "SmoothPlastic", opts)
	-- the grid of a hung ceiling over the concourse and the front rooms (lines every 8 studs across)
	for x = -18, HX1 - 2, 8 do
		kit:box(
			m,
			"CeilingGrid",
			x - 0.05,
			x + 0.05,
			CEIL - 0.06,
			CEIL - 0.04,
			L.FRONT_D,
			-24,
			{ 150, 148, 140 },
			"Metal",
			opts
		)
	end
end

-- The house lights that belong to no room's furniture: the concourse, the two aisles and one troffer in every
-- front room. None casts shadows (there are many, and the lanes' pin lights do).
local function lights(kit: any, root: any)
	local m = kit:model(root, "HouseLights")
	local function troffer(name: string, x: number, d: number, sx: number, sd: number, range: number, bright: number)
		local t = kit:box(
			m,
			name,
			x - sx / 2,
			x + sx / 2,
			CEIL - 0.14,
			CEIL - 0.04,
			d - sd / 2,
			d + sd / 2,
			{ 250, 248, 238 },
			"Neon",
			{ collide = false, shadow = false }
		)
		kit:light(t, "PointLight", { Range = range, Brightness = bright, Color = { 255, 244, 226 }, Shadows = false })
	end
	for x = -14, HX1 - 6, 22 do
		troffer("ConcourseTroffer", x, -36, 8, 2, 30, 1.0)
	end
	for _, d in { 2, 26, 50 } do
		troffer("AisleTroffer", (L.X0 + L.LANE_BLOCK_X0) / 2, d, 2, 6, 22, 0.9)
		troffer("AisleTroffer", (L.LANE_BLOCK_X1 + HX1) / 2, d, 2, 6, 22, 0.9)
	end
	for _, id in { "ball_shop", "shoe_rental", "lobby", "gift_shop", "snack_bar", "lockers" } do
		local z = L.zone(id)
		local wide = z.x1 - z.x0
		if wide > 26 then
			troffer("RoomTroffer_" .. id, z.x0 + wide * 0.28, (z.d0 + z.d1) / 2, 6, 2, 24, 1.0)
			troffer("RoomTroffer_" .. id, z.x0 + wide * 0.72, (z.d0 + z.d1) / 2, 6, 2, 24, 1.0)
		else
			troffer("RoomTroffer_" .. id, (z.x0 + z.x1) / 2, (z.d0 + z.d1) / 2, 6, 2, 26, 1.1)
		end
	end
end

-- Where the ground stands at or above the floor (AlleyLayout.SITE_CUTS: the front-west corner) the terrain is cut
-- back to just under the floor slab, inside the walls only.
local function siteCut(kit: any, root: any)
	local carve = root:FindFirstChild("TerrainCarve") or kit:folder(root, "TerrainCarve")
	for _, c in L.SITE_CUTS do
		kit:box(carve, c.id, c.x0, c.x1, c.y0, c.y1, c.d0, c.d1, { 255, 0, 0 }, "SmoothPlastic", {
			collide = false,
			query = false,
			transparency = 1,
			shadow = false,
		})
	end
end

function Shell.build(kit: any, root: any, data: any)
	kit:folder(root, "TerrainCarve")
	foundation(kit, root)
	ducts(kit, root)
	floors(kit, root)
	walls(kit, root, data)
	ceilings(kit, root)
	lights(kit, root)
	siteCut(kit, root)
end

return Shell
