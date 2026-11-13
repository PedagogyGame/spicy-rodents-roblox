--!strict
-- tools/bake/lookout/Lookout: THE LOOKOUT (venue f3_hilltop), the hilltop restaurant and the sky lift's summit
-- hall on the crown of Lookout Hill (brief v2 line 250: "A sky lift up a slight hill to a hilltop restaurant
-- (second vantage over the town)"; BATCH2_SPEC item 35; the sky-lift plan's lane 3). Lune only.
-- Interface: build(kit, parent, venue) -> Model. kit = tools/bake/alley/Kit in the venue's frame
--   (Kit.new(roblox, venue.place)); parent = the F4 folder (Workspace.Expansion.F4: the lift's bake entry,
--   tools/bake/skylift.luau, calls this so one rbxm is written); venue = the f3_hilltop record of
--   generated/Expansion. Adds two Models to parent: `f3_hilltop` (Atomic) and `f3_hilltop_Skyline` (Persistent).
--   Also: Lookout.ROOF_TOP(D), Lookout.HALL_DOOR, Lookout.STEPS (numbers the spec and other lanes read).
--
-- Frame (BATCH2 §2.1): origin = footprint centre on the finished floor (y 116); X across the frontage, D into the
-- building, front (-D) toward the town. Footprint X -50..50, D -25..25; terrace D -47..-25.
--   * Lift hall X -50..-20 (inner faces X -48.8 and -20, back D 23.8): open on its front between X -47 and -23
--     where the cable leaves, roof at 18, steel beams at 15.6..16.4. Lane 2 (tools/bake/skylift/Summit) puts the
--     platforms, bullwheel and gates in it; this file builds the shell, floor, lamps and the sign.
--   * Dining room X -20..50: glass front with a window bar, four tables (table_1..4), the counter (anchor
--     `counter`, lane 4's prompt), a fireside corner at the back, the kitchen behind the counter (closed).
--     The door to the lift hall is in the wall X = -20 at D 15..23 (HALL_DOOR).
--   * Terrace X -24..50 (east of the cabins' sweep, which reaches X -27.5 at deck height), D -47..-25, on posts
--     over the slope, glass rail (the town-facing run frameless under a thin steel top at 2.8, the sides with an oak
--     cap at 3.3, both below a seated eye at 4.5), four tables (terrace_1..4) with
--     parasols, the free telescope (anchor `telescope`), a bench by the west rail to watch the cabins.
--   * Terrace steps (entrance terrace_steps, X 11..19 at D -47): straight down the slope to the trail head at
--     D -47 - STEPS.run; they stand on the trail's path (BATCH2 §2.2: pads and paths excepted from the site).
-- Doors: the terrace doors are sliding glass leaves parked open (no server swing needed).
-- Seats are Seat parts (sitting plays the stock sit clip); each looks at its table or the view.
-- Skyline: inset copies of the big opaque pieces (hidden inside the real parts when the venue is streamed in,
--   the silhouette on the crown when it is not) plus a warm window band baked invisible with FarOnly = true (the
--   client shows it while f3_hilltop is streamed out: lane 8). At most 40 parts.

local Height = require("../../../src/shared/World/Height")
local TerrainExtensions = require("../../../generated/TerrainExtensions")

local Lookout = {}

-- the dining roof: one mono-pitch slab rising toward the town, overhanging the terrace
local ROOF_FRONT_D, ROOF_FRONT_Y = -29.5, 14.6
local ROOF_BACK_D, ROOF_BACK_Y = 25, 12.2
local ROOF_THICK = 1.0
function Lookout.ROOF_TOP(D: number): number
	return ROOF_FRONT_Y + (D - ROOF_FRONT_D) * (ROOF_BACK_Y - ROOF_FRONT_Y) / (ROOF_BACK_D - ROOF_FRONT_D)
end
local function under(D: number): number
	return Lookout.ROOF_TOP(D) - ROOF_THICK
end

Lookout.HALL = { x0 = -50, x1 = -20, open0 = -47, open1 = -23, roof = 18, beamY = 15.6 }
Lookout.HALL_DOOR = { x = -20, d0 = 15, d1 = 23, height = 8.5 }
-- railTop: the side runs' oak cap; frontTop: the town-facing run, frameless glass under a thin steel top, low
-- enough to stay under the town from a seat (review: the oak cap at 3.3 lay on the town band from the tables)
Lookout.TERRACE = { x0 = -24, x1 = 49.7, d0 = -46.7, d1 = -25, railTop = 3.3, frontTop = 2.8 }
-- run (how far beyond D -47 the flight and its landing reach) and footY (the landing's top) are filled in by build
Lookout.STEPS = { x0 = 11, x1 = 19, rise = 0.75, tread = 1.0, run = 0, footY = 0 }
Lookout.SKIRT_BOTTOM = -9.4 -- local y: ground.min - 2 = 106.6
Lookout.SKY_MAX = 40 -- parts in f3_hilltop_Skyline (BATCH2 §2.2)

local C = {
	stone = { 132, 124, 112 },
	stoneDark = { 98, 92, 84 },
	stoneCap = { 160, 154, 142 },
	cedar = { 150, 102, 64 },
	cedarDark = { 104, 70, 46 },
	bronze = { 70, 60, 50 },
	glass = { 176, 204, 212 },
	roof = { 62, 68, 70 },
	fascia = { 84, 66, 50 },
	oak = { 178, 136, 94 },
	ceiling = { 198, 164, 124 },
	beam = { 160, 116, 72 },
	plaster = { 234, 226, 210 },
	concrete = { 170, 168, 162 },
	hallFloor = { 136, 136, 132 },
	deck = { 170, 130, 90 },
	larch = { 182, 146, 104 },
	steel = { 74, 76, 78 },
	steelLight = { 120, 124, 128 },
	safety = { 232, 186, 40 },
	leather = { 124, 72, 46 },
	fabric = { 78, 98, 84 },
	cushion = { 166, 64, 52 },
	canvas = { 236, 226, 200 },
	canvasStripe = { 178, 58, 46 },
	scope = { 46, 104, 78 },
	brass = { 196, 160, 84 },
	leaf = { 70, 112, 60 },
	leafDark = { 52, 88, 48 },
	soil = { 70, 52, 36 },
	warm = { 255, 214, 160 },
	fire = { 255, 140, 50 },
	dark = { 34, 30, 28 },
	white = { 246, 244, 238 },
}

local DECOR = { collide = false, query = false, shadow = false }
local GLASS = { transparency = 0.6, reflectance = 0.08 }

type Kit = any

local function opts(base: { [string]: any }, extra: { [string]: any }?): any
	local o = table.clone(base)
	if extra then
		for k, v in extra do
			o[k] = v
		end
	end
	return o
end

-- A slab whose length runs in the local D-Y plane from (d0, y0) to (d1, y1) at centre X: width along X,
-- thickness along its normal (roofs, sloped boards, stair stringers).
local function plank(
	kit: Kit,
	parent: any,
	name: string,
	X: number,
	d0: number,
	y0: number,
	d1: number,
	y1: number,
	width: number,
	thick: number,
	color: { number },
	material: string,
	o: any?
): any
	local CFrame = kit.roblox.CFrame
	local a = kit:cf(X, y0, d0).Position
	local b = kit:cf(X, y1, d1).Position
	local len = (b - a).Magnitude
	local vX = kit:cf(0, 0, 0).RightVector
	local vZ = (a - b).Unit
	local vY = vZ:Cross(vX)
	if vY.Y < 0 then
		vZ = -vZ
		vY = vZ:Cross(vX)
	end
	local p = kit:at(parent, name, 0, 0, 0, width, thick, len, color, material, o)
	p.CFrame = CFrame.fromMatrix((a + b) / 2, vX, vY, vZ)
	return p
end

-- A wall in the X-Y plane at depth band [d0, d1] (or the D-Y plane at [x0, x1]) with rectangular holes.
-- holes = { { u0, u1, y0, y1 } } along the wall's length axis u (X for "X" walls, D for "D" walls).
local function wall(
	kit: Kit,
	parent: any,
	name: string,
	axis: string,
	u0: number,
	u1: number,
	y0: number,
	y1: number,
	t0: number,
	t1: number,
	holes: { { number } },
	color: { number },
	material: string,
	o: any?
): { any }
	local out = {}
	for i, r in kit:holes(u0, u1, y0, y1, holes) do
		local part
		if axis == "X" then
			part = kit:box(parent, `{name}{i}`, r[1], r[2], r[3], r[4], t0, t1, color, material, o)
		else
			part = kit:box(parent, `{name}{i}`, t0, t1, r[3], r[4], r[1], r[2], color, material, o)
		end
		table.insert(out, part)
	end
	return out
end

-- Ground (local y) under a local point.
local function groundY(kit: Kit, X: number, D: number): number
	local p = kit:cf(X, 0, D).Position
	return Height.at(p.X, p.Z) - kit.place.floorY
end

-- The lowest and highest ground (local y) over a local rectangle (3 x 3 samples).
local function groundRange(kit: Kit, x0: number, x1: number, d0: number, d1: number): (number, number)
	local lo, hi = math.huge, -math.huge
	for _, X in { x0, (x0 + x1) / 2, x1 } do
		for _, D in { d0, (d0 + d1) / 2, d1 } do
			local g = groundY(kit, X, D)
			lo, hi = math.min(lo, g), math.max(hi, g)
		end
	end
	return lo, hi
end
local function minGround(kit: Kit, x0: number, x1: number, d0: number, d1: number): number
	return (groundRange(kit, x0, x1, d0, d1))
end

-- Inset copies for the far view (built after the real parts; see the header).
type SkyItem = { part: any, inset: number }
local function skyMark(list: { SkyItem }, part: any, inset: number?)
	table.insert(list, { part = part, inset = inset or 0.06 })
end

---------------------------------------------------------------------------------------------------------------
-- The plinth, the floors and the terrain carve
local function base(kit: Kit, root: any, sky: { SkyItem })
	local shell = root:FindFirstChild("Shell") or kit:model(root, "Shell")
	local SB = Lookout.SKIRT_BOTTOM
	-- the floors: polished concrete in the hall, oak in the restaurant; tops exactly at the floor
	kit:box(shell, "HallFloor", -50, -20, -1.2, 0, -25, 25, C.hallFloor, "Concrete")
	kit:box(shell, "DiningFloor", -20, 50, -1.2, 0, -25, 25, C.oak, "WoodPlanks")
	-- the stone skirt round the whole footprint, down to ground.min - 2, with a projecting cap course
	local walls = {
		{ "SkirtFront", -49.7, 49.7, -24.7, -23.5 },
		{ "SkirtBack", -49.7, 49.7, 23.5, 24.7 },
		{ "SkirtWest", -49.7, -48.5, -23.5, 23.5 },
		{ "SkirtEast", 48.5, 49.7, -23.5, 23.5 },
	}
	for _, w in walls do
		local p = kit:box(shell, w[1], w[2], w[3], SB, -1.2, w[4], w[5], C.stone, "Slate")
		skyMark(sky, p)
	end
	kit:box(shell, "SkirtCapFront", -50, 50, -1.6, -1.2, -25, -24.3, C.stoneCap, "Concrete")
	kit:box(shell, "SkirtCapBack", -50, 50, -1.6, -1.2, 24.3, 25, C.stoneCap, "Concrete")
	kit:box(shell, "SkirtCapWest", -50, -49.3, -1.6, -1.2, -24.3, 24.3, C.stoneCap, "Concrete")
	kit:box(shell, "SkirtCapEast", 49.3, 50, -1.6, -1.2, -24.3, 24.3, C.stoneCap, "Concrete")
	-- a darker plinth course at the foot (the part of the skirt above the ground on the falling sides)
	kit:box(shell, "PlinthEast", 49.7, 49.95, SB, -4, -24.7, 24.7, C.stoneDark, "Slate", DECOR)
	kit:box(shell, "PlinthWest", -49.95, -49.7, SB, -4, -24.7, 24.7, C.stoneDark, "Slate", DECOR)
	kit:box(shell, "PlinthBack", -49.7, 49.7, SB, -4, 24.7, 24.95, C.stoneDark, "Slate", DECOR)
	-- TerrainCarve: voxels sit up to a stud over the analytic ground (crown 115.41 under a floor at 116)
	local carve = kit:folder(root, "TerrainCarve")
	local hidden = { collide = false, query = false, transparency = 1, shadow = false }
	kit:box(carve, "UnderFloor", -50, 50, -2.5, -0.05, -25, 25, { 255, 0, 0 }, "SmoothPlastic", hidden)
	kit:box(carve, "UnderTerrace", -24, 49.7, -3, -0.6, -46.7, -25, { 255, 0, 0 }, "SmoothPlastic", hidden)
end

---------------------------------------------------------------------------------------------------------------
-- The lift hall shell (lane 2 fills it with the platforms, bullwheel and gates)
local function hall(kit: Kit, root: any, sky: { SkyItem })
	local m = kit:model(root, "LiftHall")
	local H = Lookout.HALL
	local top = H.roof
	-- west wall, a band of windows looking down the hill's west side
	local westHoles = {}
	for _, d in { -19, -9, 1, 11 } do
		table.insert(westHoles, { d, d + 7, 4, 10.5 })
	end
	for _, p in wall(kit, m, "WestWall", "D", -24.6, 24.6, 0, top - 1, -49.6, -48.8, westHoles, C.larch, "WoodPlanks") do
		skyMark(sky, p)
	end
	for i, h in westHoles do
		kit:box(m, `WestGlass{i}`, -49.35, -49.05, h[3], h[4], h[1], h[2], C.glass, "Glass", opts(GLASS, DECOR))
		kit:box(m, `WestSill{i}`, -49.9, -48.6, h[3] - 0.25, h[3], h[1] - 0.2, h[2] + 0.2, C.bronze, "Metal")
	end
	-- back wall with a service door
	local backHoles = { { -32, -28, 0, 8 } }
	for _, p in wall(kit, m, "BackWall", "X", -49.6, -20, 0, top - 1, 23.8, 24.6, backHoles, C.larch, "WoodPlanks") do
		skyMark(sky, p)
	end
	kit:box(m, "ServiceDoor", -32, -28, 0, 8, 24.05, 24.35, C.steel, "DiamondPlate")
	kit:box(m, "ServiceDoorHandle", -31.4, -31, 3.6, 3.8, 23.7, 24.05, C.steelLight, "Metal", DECOR)
	-- east wall (shared with the dining room): the door to the restaurant and a window onto the dining room
	local D = Lookout.HALL_DOOR
	local eastHoles = { { D.d0, D.d1, 0, D.height }, { -16, 6, 2.6, 8.6 } }
	for _, p in
		wall(kit, m, "EastWall", "D", -24.6, 23.8, 0, top - 1, -20, -19.2, eastHoles, C.plaster, "SmoothPlastic")
	do
		skyMark(sky, p)
	end
	kit:box(m, "HallWindow", -19.75, -19.45, 2.6, 8.6, -16, 6, C.glass, "Glass", opts(GLASS, DECOR))
	for _, d in { -16.2, 6.2 } do
		kit:box(m, "HallWindowJamb", -20.1, -19.1, 2.4, 8.8, d - 0.2, d + 0.2, C.bronze, "Metal", DECOR)
	end
	kit:box(m, "HallWindowSill", -20.15, -19.05, 2.4, 2.6, -16.2, 6.2, C.bronze, "Metal", DECOR)
	kit:box(m, "HallWindowHead", -20.15, -19.05, 8.6, 8.8, -16.2, 6.2, C.bronze, "Metal", DECOR)
	-- the door frame, seen from both rooms
	for _, d in { D.d0 - 0.25, D.d1 + 0.25 } do
		kit:box(m, "HallDoorJamb", -20.2, -19, 0, D.height + 0.3, d - 0.25, d + 0.25, C.bronze, "Metal")
	end
	kit:box(m, "HallDoorHead", -20.2, -19, D.height, D.height + 0.35, D.d0 - 0.5, D.d1 + 0.5, C.bronze, "Metal")
	-- way signs over the door, both sides, and a welcome board for those stepping off a cabin
	local over = kit:box(m, "DoorSign", -20.35, -18.85, 9.3, 10.7, D.d0, D.d1, C.dark, "SmoothPlastic", DECOR)
	kit:label(kit:gui(over, "Left", 40), { Text = "RESTAURANT  ·  TERRACE  ·  TRAIL TO TOWN", TextColor = C.white })
	kit:label(kit:gui(over, "Right", 40), { Text = "SKY LIFT  ·  CABINS DOWN TO TOWN", TextColor = C.white })
	local welcome = kit:box(m, "WelcomeBoard", -20.2, -20, 3.2, 8.2, -23, -17.5, { 40, 58, 52 }, "SmoothPlastic", DECOR)
	local wg = kit:gui(welcome, "Left", 40)
	kit:label(
		wg,
		{ Text = "WELCOME TO THE LOOKOUT", TextColor = { 255, 226, 170 }, Size = { 0.9, 0.2 }, Pos = { 0.05, 0.06 } }
	)
	kit:label(wg, {
		Text = "Lookout Hill: the highest ground for miles\n\nThe restaurant and the terrace: through the door at the back\nThe telescope on the terrace is free\nCabins down to town leave from the far platform",
		TextColor = C.white,
		Size = { 0.9, 0.62 },
		Pos = { 0.05, 0.32 },
		Font = "Gotham",
		TextXAlignment = kit.roblox.Enum.TextXAlignment.Left,
	})
	kit:box(m, "WelcomeFrame", -20.15, -20, 3.0, 8.4, -23.2, -17.3, C.bronze, "Metal", DECOR)
	-- front piers either side of the opening, the head beam over it (above every hanger: 12.6) and the sign
	for _, r in { { -50, H.open0 }, { H.open1, -19.2 } } do
		local p = kit:box(m, "FrontPier", r[1], r[2], 0, top - 1, -25.6, -24, C.stone, "Slate")
		skyMark(sky, p)
	end
	local head = kit:box(m, "OpeningHead", H.open0, H.open1, 13.6, top - 1, -25.6, -24, C.cedarDark, "WoodPlanks")
	skyMark(sky, head)
	kit:box(m, "OpeningSoffit", H.open0, H.open1, 13.4, 13.6, -25.4, -24.2, C.bronze, "Metal", DECOR)
	-- the roof: flat, oversailing the front as a canopy over the cabins' mouth
	-- two skylight bands light the platforms by day
	local lights = { { -44, -26, -14, -6 }, { -44, -26, 4, 12 } }
	for i, r in kit:holes(-49.7, -19.2, -27.5, 24.7, lights) do
		local roof = kit:box(m, `HallRoof{i}`, r[1], r[2], top - 1, top, r[3], r[4], C.roof, "Metal")
		skyMark(sky, roof)
	end
	for i, r in lights do
		kit:box(m, `Skylight{i}`, r[1], r[2], top - 0.6, top - 0.4, r[3], r[4], C.glass, "Glass", opts(GLASS, DECOR))
		for _, x in { -39.5, -35, -30.5 } do
			kit:box(m, `SkylightBar{i}`, x - 0.12, x + 0.12, top - 0.7, top - 0.3, r[3], r[4], C.bronze, "Metal", DECOR)
		end
	end
	kit:box(m, "HallFasciaFront", -50, -19.2, top - 1.6, top + 0.25, -27.8, -27.5, C.fascia, "Metal")
	kit:box(m, "HallFasciaWest", -50, -49.7, top - 1.6, top + 0.25, -27.8, 25, C.fascia, "Metal")
	kit:box(m, "HallFasciaBack", -49.7, -19.2, top - 1.6, top + 0.25, 24.7, 25, C.fascia, "Metal")
	for i, r in kit:holes(-48.8, -20, -24, 23.8, lights) do
		kit:box(m, `HallCeiling{i}`, r[1], r[2], top - 1.2, top - 1, r[3], r[4], C.ceiling, "WoodPlanks", DECOR)
	end
	-- steel beams across the hall (lane 2 may hang the bullwheel frame from them)
	for i, d in { -18, -8, 2, 12, 21 } do
		kit:box(m, `Beam{i}`, -48.8, -20, H.beamY, H.beamY + 0.8, d - 0.35, d + 0.35, C.steel, "Metal")
		kit:box(m, `BeamFlange{i}`, -48.8, -20, H.beamY - 0.12, H.beamY, d - 0.6, d + 0.6, C.steel, "Metal", DECOR)
	end
	-- industrial lamps over the two platforms (outside the cabins' sweep, X -44..-26.5)
	for _, x in { -47, -23 } do
		for _, d in { -14, -2, 10 } do
			kit:box(m, "LampCord", x - 0.05, x + 0.05, 10.6, H.beamY, d - 0.05, d + 0.05, C.dark, "Metal", DECOR)
			local shade =
				kit:cyl(m, "LampShade", x, 10.4, d, 0.5, 1.6, "Y", C.steel, "Metal", opts(DECOR, { shadow = false }))
			local bulb = kit:ball(m, "LampBulb", x, 10.0, d, 0.5, C.warm, "Neon", DECOR)
			kit:light(bulb, "PointLight", { Color = C.warm, Brightness = 2, Range = 22, Shadows = false })
			local _ = shade
		end
	end
	-- the floor's front edge: a yellow safety line and a nosing where the cabins leave
	kit:box(m, "EdgeLine", H.open0, H.open1, 0, 0.03, -24.9, -24.4, C.safety, "SmoothPlastic", DECOR)
	kit:box(m, "EdgeNosing", H.open0, H.open1, -1.2, 0, -25.3, -25, C.steel, "Metal")
	-- THE LOOKOUT on the head beam, facing the town and every arriving cabin; lit at night
	local board = kit:box(m, "SignBoard", -48.6, -21.4, 13.9, 16.8, -26.1, -25.6, C.dark, "SmoothPlastic")
	local g = kit:gui(board, "Back", 40)
	kit:label(g, { Text = "THE LOOKOUT", TextColor = { 255, 226, 170 }, Size = { 0.96, 0.62 }, Pos = { 0.02, 0.06 } })
	kit:label(g, {
		Text = "RESTAURANT  ·  TERRACE  ·  SKY LIFT",
		TextColor = { 220, 210, 190 },
		Size = { 0.9, 0.24 },
		Pos = { 0.05, 0.7 },
		Font = "Gotham",
	})
	kit:light(board, "SurfaceLight", { Face = "Back", Color = C.warm, Brightness = 1.2, Range = 10, Angle = 70 })
	skyMark(sky, board, 0.04)
	-- a frame round the sign
	kit:box(m, "SignFrameTop", -48.8, -21.2, 16.8, 17.0, -26.2, -25.6, C.bronze, "Metal", DECOR)
	kit:box(m, "SignFrameBottom", -48.8, -21.2, 13.7, 13.9, -26.2, -25.6, C.bronze, "Metal", DECOR)
end

---------------------------------------------------------------------------------------------------------------
-- The dining room shell: glass front, east wall, back wall, roof and ceiling
local function diningShell(kit: Kit, root: any, sky: { SkyItem })
	local m = kit:model(root, "Dining")
	local x0, x1 = -19.2, 49.6
	local dFront = -25
	local frontTop = under(dFront)
	-- the glass front: lower lights to the transom at 9.2, a clerestory band above to the roof
	local doorX0, doorX1 = 11, 19
	local TR = 9.2
	for _, r in { { x0, doorX0 }, { doorX1, x1 - 0.4 } } do
		kit:box(m, "FrontGlass", r[1], r[2], 0.5, TR, -24.95, -24.65, C.glass, "Glass", GLASS)
	end
	kit:box(m, "FrontClerestory", x0, x1 - 0.4, TR + 0.4, frontTop, -24.95, -24.65, C.glass, "Glass", GLASS)
	kit:box(m, "DoorGlassOver", doorX0, doorX1, TR + 0.4, frontTop, -24.95, -24.65, C.glass, "Glass", GLASS)
	for _, r in { { x0, doorX0 }, { doorX1, x1 } } do
		kit:box(m, "FrontSill", r[1], r[2], 0, 0.5, -25.3, -24.3, C.bronze, "Metal")
	end
	local transom = kit:box(m, "Transom", x0, x1, TR, TR + 0.4, -25.2, -24.4, C.bronze, "Metal")
	local _ = transom
	kit:box(m, "FrontHead", x0, x1, frontTop - 0.3, frontTop, -25.2, -24.4, C.bronze, "Metal")
	-- mullions: 12 bays, the door bay wider
	local mx = { -19.2, -13.2, -7.2, -1.2, 5, 11, 19, 25, 31, 37, 43, 49.2 }
	for i, x in mx do
		local lo = if x == doorX0 or x == doorX1 then 0 else 0.5
		kit:box(m, `Mullion{i}`, x - 0.22, x + 0.22, lo, frontTop, -25.25, -24.35, C.bronze, "Metal")
	end
	-- the terrace doors: two sliding glass leaves parked open behind the fixed glass, a threshold
	for _, r in { { 3.4, 11.2 }, { 18.8, 26.6 } } do
		kit:box(m, "SlidingLeaf", r[1], r[2], 0.1, TR - 0.1, -24.3, -24.1, C.glass, "Glass", opts(GLASS, DECOR))
		kit:box(m, "SlidingLeafFrame", r[1], r[2], TR - 0.3, TR - 0.1, -24.35, -24.05, C.bronze, "Metal", DECOR)
		kit:box(m, "SlidingLeafPull", r[1] + 0.3, r[1] + 0.5, 3, 5, -24.05, -23.85, C.steelLight, "Metal", DECOR)
	end
	kit:box(m, "DoorTrack", 3, 27, TR - 0.05, TR + 0.1, -24.4, -24.0, C.bronze, "Metal", DECOR)
	kit:box(m, "Threshold", doorX0, doorX1, 0, 0.06, -25.4, -24.1, C.steelLight, "Metal")
	-- east wall: glass in the front half (the corner wraps the view), cedar behind
	local eastSplit = 0
	kit:box(m, "EastGlass", 49.05, 49.35, 0.5, TR, -24.4, eastSplit - 0.4, C.glass, "Glass", GLASS)
	kit:box(
		m,
		"EastClerestory",
		49.05,
		49.35,
		TR + 0.4,
		under(eastSplit),
		-24.4,
		eastSplit - 0.4,
		C.glass,
		"Glass",
		GLASS
	)
	kit:wedge(
		m,
		"EastGlassGable",
		49.2,
		under(eastSplit) + (under(dFront) - under(eastSplit)) / 2,
		(dFront + eastSplit) / 2,
		0.8,
		under(dFront) - under(eastSplit),
		eastSplit - dFront,
		C.cedarDark,
		"WoodPlanks"
	)
	kit:box(m, "EastSill", 48.8, 49.9, 0, 0.5, -24.6, eastSplit, C.bronze, "Metal")
	kit:box(m, "EastTransom", 48.9, 49.8, TR, TR + 0.4, -24.6, eastSplit, C.bronze, "Metal")
	for i, d in { -24.6, -18.6, -12.6, -6.6, -0.4 } do
		kit:box(m, `EastMullion{i}`, 48.9, 49.8, 0.5, under(d), d - 0.22, d + 0.22, C.bronze, "Metal")
	end
	local eastHoles = { { 4, 11, 3, 8.5 } }
	for _, p in
		wall(kit, m, "EastWall", "D", eastSplit, 24.6, 0, under(24.6), 48.8, 49.6, eastHoles, C.cedar, "WoodPlanks")
	do
		skyMark(sky, p)
	end
	kit:box(m, "EastWindow", 49.05, 49.35, 3, 8.5, 4, 11, C.glass, "Glass", opts(GLASS, DECOR))
	local gable = kit:wedge(
		m,
		"EastGable",
		49.2,
		under(24.6) + (under(eastSplit) - under(24.6)) / 2,
		(eastSplit + 24.6) / 2,
		0.8,
		under(eastSplit) - under(24.6),
		24.6 - eastSplit,
		C.cedar,
		"WoodPlanks"
	)
	local _ = gable
	-- back wall (kitchen behind its east part) with the restrooms door
	local backHoles = { { -16.5, -12.5, 0, 7.6 } }
	for _, p in wall(kit, m, "BackWall", "X", -19.2, 49.6, 0, under(24.6), 23.8, 24.6, backHoles, C.cedar, "WoodPlanks") do
		skyMark(sky, p)
	end
	kit:box(m, "RestroomDoor", -16.5, -12.5, 0, 7.6, 24.05, 24.3, C.cedarDark, "Wood")
	kit:box(m, "RestroomDoorFrame", -16.9, -12.1, 7.6, 8.0, 23.6, 23.9, C.bronze, "Metal", DECOR)
	for _, x in { -16.9, -12.5 } do
		kit:box(m, "RestroomDoorJamb", x, x + 0.4, 0, 7.6, 23.6, 23.9, C.bronze, "Metal", DECOR)
	end
	kit:box(m, "RestroomKnob", -13.3, -13.0, 3.5, 3.8, 23.8, 24.05, C.brass, "Metal", DECOR)
	local rsign = kit:box(m, "RestroomSign", -16, -13, 8.3, 9.3, 23.65, 23.8, C.dark, "SmoothPlastic", DECOR)
	kit:label(kit:gui(rsign, "Front", 60), { Text = "RESTROOMS", TextColor = C.white, Font = "Gotham" })
	-- the roof: a mono-pitch slab rising to the town, overhanging the terrace; fascia; the interior ceiling
	local roof = plank(
		kit,
		m,
		"Roof",
		(x0 + 50) / 2,
		ROOF_FRONT_D,
		Lookout.ROOF_TOP(ROOF_FRONT_D) - ROOF_THICK / 2,
		ROOF_BACK_D,
		Lookout.ROOF_TOP(ROOF_BACK_D) - ROOF_THICK / 2,
		50 - x0,
		ROOF_THICK,
		C.roof,
		"Metal"
	)
	skyMark(sky, roof)
	-- standing seams down the slope
	for i = 0, 11 do
		local x = -16 + i * 5.7
		plank(
			kit,
			m,
			"RoofSeam",
			x,
			ROOF_FRONT_D,
			Lookout.ROOF_TOP(ROOF_FRONT_D) + 0.08,
			ROOF_BACK_D,
			Lookout.ROOF_TOP(ROOF_BACK_D) + 0.08,
			0.16,
			0.16,
			C.steel,
			"Metal",
			DECOR
		)
	end
	kit:box(
		m,
		"RoofFasciaFront",
		x0,
		50,
		Lookout.ROOF_TOP(ROOF_FRONT_D) - 1.5,
		Lookout.ROOF_TOP(ROOF_FRONT_D) + 0.2,
		ROOF_FRONT_D - 0.35,
		ROOF_FRONT_D,
		C.fascia,
		"Metal"
	)
	plank(
		kit,
		m,
		"RoofFasciaEast",
		49.85,
		ROOF_FRONT_D,
		Lookout.ROOF_TOP(ROOF_FRONT_D) - 0.65,
		ROOF_BACK_D,
		Lookout.ROOF_TOP(ROOF_BACK_D) - 0.65,
		0.35,
		1.7,
		C.fascia,
		"Metal"
	)
	kit:box(
		m,
		"RoofFasciaBack",
		x0,
		50,
		Lookout.ROOF_TOP(ROOF_BACK_D) - 1.5,
		Lookout.ROOF_TOP(ROOF_BACK_D) + 0.2,
		ROOF_BACK_D - 0.3,
		ROOF_BACK_D,
		C.fascia,
		"Metal"
	)
	-- the soffit under the overhang (timber, lit by downlights over the terrace)
	plank(
		kit,
		m,
		"Soffit",
		(x0 + 50) / 2,
		ROOF_FRONT_D,
		under(ROOF_FRONT_D) - 0.1,
		-25.3,
		under(-25.3) - 0.1,
		50 - x0,
		0.2,
		C.ceiling,
		"WoodPlanks",
		DECOR
	)
	for i, x in { -12, 4, 30, 44 } do
		local dl = kit:cyl(m, `Downlight{i}`, x, under(-27.5) - 0.25, -27.5, 0.12, 0.7, "Y", C.warm, "Neon", DECOR)
		kit:light(dl, "SpotLight", { Face = "Bottom", Color = C.warm, Brightness = 1.6, Range = 16, Angle = 80 })
	end
	-- ceiling downlights between the beams (the room's even fill; the pendants are the warm pools)
	for _, d in { -14, 4 } do
		for _, x in { -10.2, 5, 20.2, 35.4 } do
			local dl = kit:cyl(m, "CeilingLight", x, under(d) - 0.2, d, 0.1, 0.9, "Y", C.warm, "Neon", DECOR)
			kit:light(dl, "PointLight", { Color = C.warm, Brightness = 0.8, Range = 20, Shadows = false })
		end
	end
	-- the back of the room: a row over the fireside corner and the bar, sconces on the back wall
	for _, x in { -10.2, 5, 20.2 } do
		local dl = kit:cyl(m, "CeilingLight", x, under(17) - 0.2, 17, 0.1, 0.9, "Y", C.warm, "Neon", DECOR)
		kit:light(dl, "PointLight", { Color = C.warm, Brightness = 0.7, Range = 18, Shadows = false })
	end
	for _, x in { -9, 9, 17 } do
		kit:box(m, "SconcePlate", x - 0.3, x + 0.3, 5.6, 6.6, 23.6, 23.8, C.bronze, "Metal", DECOR)
		local sc = kit:cyl(m, "Sconce", x, 6.3, 23.2, 0.9, 0.7, "Y", C.warm, "Neon", DECOR)
		kit:light(sc, "PointLight", { Color = C.warm, Brightness = 0.8, Range = 12, Shadows = false })
	end
	-- interior ceiling and glulam beams
	plank(
		kit,
		m,
		"Ceiling",
		15.2,
		-24.4,
		under(-24.4) - 0.1,
		23.8,
		under(23.8) - 0.1,
		68,
		0.2,
		C.ceiling,
		"WoodPlanks",
		DECOR
	)
	for i = 0, 8 do
		local x = -14 + i * 7.6
		plank(
			kit,
			m,
			"Glulam",
			x,
			-24.4,
			under(-24.4) - 0.8,
			23.8,
			under(23.8) - 0.8,
			0.8,
			1.2,
			C.beam,
			"Wood",
			{ collide = false, query = false }
		)
	end
	-- skirting round the room
	kit:box(m, "SkirtingBack", -19.2, 48.8, 0, 0.4, 23.55, 23.8, C.cedarDark, "Wood", DECOR)
	kit:box(m, "SkirtingWest", -19.2, -18.95, 0, 0.4, -24.3, 23.8, C.cedarDark, "Wood", DECOR)
	kit:box(m, "SkirtingEast", 48.55, 48.8, 0, 0.4, eastSplit, 23.8, C.cedarDark, "Wood", DECOR)
	-- the chimney over the fireside corner
	local chim = kit:box(m, "Chimney", -3, 3, under(24) - 0.5, 17.4, 21.2, 24.6, C.stone, "Slate")
	skyMark(sky, chim)
	kit:box(m, "ChimneyCap", -3.4, 3.4, 17.4, 17.8, 20.8, 25, C.stoneCap, "Concrete")
	return m
end

---------------------------------------------------------------------------------------------------------------
-- Furniture
local function seat(kit: Kit, parent: any, X: number, Y: number, D: number, w: number, d: number, face: string, c)
	local a = if face == "+D"
		then 0
		elseif face == "-D" then math.pi
		elseif face == "+X" then -math.pi / 2
		else math.pi / 2
	-- w and d are the extents along local X and D: a quarter turn swaps the part's own axes
	if face == "+X" or face == "-X" then
		w, d = d, w
	end
	return kit:at(parent, "Seat", X, Y - 0.15, D, w, 0.3, d, c, "Fabric", {
		class = "Seat",
		rot = kit.roblox.CFrame.Angles(0, a, 0),
	})
end

-- A chair at (X, D) facing `face` ("+X", "-X", "+D", "-D").
local function chair(
	kit: Kit,
	parent: any,
	X: number,
	D: number,
	face: string,
	seatColor: { number },
	frame: { number }
)
	local m = kit:model(parent, "Chair")
	seat(kit, m, X, 1.5, D, 1.6, 1.6, face, seatColor)
	-- (u = across the sitter, v = toward the table) in local X and D
	local fx = if face == "+X" then 1 elseif face == "-X" then -1 else 0
	local fd = if face == "+D" then 1 elseif face == "-D" then -1 else 0
	local ux, ud = fd, fx -- perpendicular
	local function at(u: number, v: number): (number, number)
		return X + ux * u + fx * v, D + ud * u + fd * v
	end
	local function post(name: string, u: number, v: number, y0: number, y1: number, w: number)
		local px, pd = at(u, v)
		kit:box(m, name, px - w, px + w, y0, y1, pd - w, pd + w, frame, "Metal", DECOR)
	end
	-- four slim legs, the two at the back carried up as the back's posts
	for _, u in { -0.62, 0.62 } do
		post("Leg", u, 0.62, 0, 1.2, 0.07)
		post("BackPost", u, -0.68, 0, 3.4, 0.08)
	end
	-- the back: a curved-looking rail of two slats
	local bx, bd = at(0, -0.7)
	local hw = 0.7
	for _, y in { { 2.2, 2.6 }, { 2.9, 3.35 } } do
		if fx ~= 0 then
			kit:box(m, "BackSlat", bx - 0.06, bx + 0.06, y[1], y[2], bd - hw, bd + hw, seatColor, "Wood", DECOR)
		else
			kit:box(m, "BackSlat", bx - hw, bx + hw, y[1], y[2], bd - 0.06, bd + 0.06, seatColor, "Wood", DECOR)
		end
	end
	return m
end

-- A round table for four with its chairs. Returns the table model.
local function table4(
	kit: Kit,
	parent: any,
	name: string,
	X: number,
	D: number,
	top: { number },
	topMat: string,
	seatColor: { number },
	frame: { number }
): any
	local m = kit:model(parent, name)
	kit:cyl(m, "Top", X, 2.7, D, 0.2, 4.2, "Y", top, topMat)
	kit:cyl(m, "Pedestal", X, 1.3, D, 2.6, 0.35, "Y", frame, "Metal", DECOR)
	kit:cyl(m, "Foot", X, 0.06, D, 0.12, 1.8, "Y", frame, "Metal", DECOR)
	chair(kit, m, X - 2.7, D, "+X", seatColor, frame)
	chair(kit, m, X + 2.7, D, "-X", seatColor, frame)
	chair(kit, m, X, D - 2.7, "+D", seatColor, frame)
	chair(kit, m, X, D + 2.7, "-D", seatColor, frame)
	return m
end

local function pendant(kit: Kit, parent: any, X: number, D: number, bottom: number, color: { number }, bright: number)
	local topY = under(D) - 0.1
	kit:box(parent, "PendantCord", X - 0.04, X + 0.04, bottom + 0.6, topY, D - 0.04, D + 0.04, C.dark, "Metal", DECOR)
	kit:cyl(parent, "PendantShade", X, bottom + 0.35, D, 0.7, 1.3, "Y", color, "Metal", DECOR)
	local bulb = kit:ball(parent, "PendantBulb", X, bottom + 0.05, D, 0.45, C.warm, "Neon", DECOR)
	kit:light(bulb, "PointLight", { Color = C.warm, Brightness = bright, Range = 14, Shadows = true })
end

local function plant(kit: Kit, parent: any, X: number, D: number, h: number)
	local m = kit:model(parent, "Plant")
	kit:cyl(m, "Pot", X, 0.8, D, 1.6, 1.6, "Y", C.stoneDark, "Concrete")
	kit:ball(m, "Leaves", X, 1.6 + h * 0.35, D, 1.8 + h * 0.3, C.leaf, "Grass", DECOR)
	kit:ball(m, "LeavesTop", X + 0.3, 1.8 + h * 0.75, D - 0.2, 1.2 + h * 0.2, C.leafDark, "Grass", DECOR)
end

---------------------------------------------------------------------------------------------------------------
-- The dining room inside: window bar, tables, counter, fireside corner, the panorama on the wall
local function diningInside(kit: Kit, root: any, venue: any)
	local m = kit:model(root, "Interior")
	-- the window bar along the glass, stools facing the town
	for _, r in { { -18.4, 9.6 }, { 20.4, 48.4 } } do
		kit:box(m, "WindowBar", r[1], r[2], 3.3, 3.5, -24.3, -22.9, C.oak, "Wood")
		for x = r[1] + 2, r[2] - 1.5, 7 do
			kit:box(m, "WindowBarBracket", x - 0.1, x + 0.1, 2.4, 3.3, -24.25, -23.5, C.bronze, "Metal", DECOR)
		end
		for x = r[1] + 1.8, r[2] - 1.2, 3.6 do
			local s = kit:model(m, "Stool")
			seat(kit, s, x, 2.4, -21.6, 1.2, 1.2, "-D", C.leather)
			kit:cyl(s, "StoolPost", x, 1.15, -21.6, 2.1, 0.22, "Y", C.bronze, "Metal", DECOR)
			kit:cyl(s, "StoolFoot", x, 0.05, -21.6, 0.1, 1.1, "Y", C.bronze, "Metal", DECOR)
			kit:cyl(s, "StoolRing", x, 0.9, -21.6, 0.08, 0.9, "Y", C.bronze, "Metal", DECOR)
		end
	end
	-- the four tables (anchors table_1..4)
	local anchorAt: { [string]: { number } } = {}
	for _, a in venue.anchors do
		anchorAt[a.id] = a.at
	end
	for k = 1, 4 do
		local at = anchorAt[`table_{k}`]
		if at then
			local t = table4(kit, m, `Table{k}`, at[1], at[3], C.oak, "Wood", C.fabric, C.cedarDark)
			-- a small vase on each
			kit:cyl(t, "Vase", at[1] + 0.5, 3.15, at[3] - 0.3, 0.7, 0.35, "Y", C.white, "Glass", DECOR)
			kit:ball(t, "Flowers", at[1] + 0.5, 3.6, at[3] - 0.3, 0.55, { 214, 90, 70 }, "SmoothPlastic", DECOR)
			pendant(kit, m, at[1], at[3], 7.7, C.bronze, 0.9)
		end
	end
	-- the host's place by the door: a lectern beside the staff post
	local host = anchorAt.host or { 15, 0, -18 }
	local hx, hd = host[1] + 3.2, host[3]
	kit:box(m, "Lectern", hx - 0.8, hx + 0.8, 0, 3.6, hd - 0.6, hd + 0.6, C.cedarDark, "Wood")
	kit:box(m, "LecternTop", hx - 0.95, hx + 0.95, 3.6, 3.75, hd - 0.75, hd + 0.75, C.oak, "Wood", DECOR)
	local lsign =
		kit:box(m, "LecternSign", hx - 0.7, hx + 0.7, 1.4, 3.2, hd - 0.66, hd - 0.61, C.dark, "SmoothPlastic", DECOR)
	kit:label(kit:gui(lsign, "Back", 60), {
		Text = "PLEASE SEAT YOURSELF\nLunch at the counter",
		TextColor = C.white,
		Font = "Gotham",
	})
	-- the counter (anchor `counter`): stone front, oak top, a pastry case and the register
	local ca = anchorAt.counter or { 35, 0, 12 }
	local cx, cd = ca[1], ca[3]
	local cx0, cx1 = cx - 7, cx + 7
	kit:box(m, "CounterFront", cx0, cx1, 0, 3.4, cd - 1.2, cd + 1.2, C.stone, "Slate")
	kit:box(m, "CounterTop", cx0 - 0.2, cx1 + 0.2, 3.4, 3.65, cd - 1.4, cd + 1.3, C.oak, "Wood")
	kit:box(m, "CounterKick", cx0 + 0.1, cx1 - 0.1, 0, 0.35, cd - 1.35, cd - 1.2, C.dark, "Metal", DECOR)
	kit:box(m, "PastryCase", cx + 2, cx + 5.6, 3.65, 5.0, cd - 0.9, cd + 0.6, C.glass, "Glass", opts(GLASS, DECOR))
	kit:box(m, "PastryShelf", cx + 2.1, cx + 5.5, 4.2, 4.3, cd - 0.8, cd + 0.5, C.steelLight, "Metal", DECOR)
	for i = 0, 3 do
		kit:ball(m, "Pastry", cx + 2.5 + i * 0.85, 3.85, cd - 0.2, 0.55, { 214, 160, 90 }, "SmoothPlastic", DECOR)
		kit:ball(m, "Bun", cx + 2.5 + i * 0.85, 4.45, cd - 0.2, 0.45, { 190, 128, 70 }, "SmoothPlastic", DECOR)
	end
	kit:box(m, "Register", cx - 4.5, cx - 3, 3.65, 4.5, cd - 0.5, cd + 0.6, C.dark, "Metal", DECOR)
	kit:box(m, "RegisterScreen", cx - 4.3, cx - 3.2, 4.5, 5.2, cd + 0.2, cd + 0.35, { 40, 80, 70 }, "Neon", DECOR)
	local bell = kit:cyl(m, "CounterBell", cx - 1.5, 3.8, cd - 0.6, 0.3, 0.5, "Y", C.brass, "Metal", DECOR)
	local _ = bell
	local csign =
		kit:box(m, "CounterCard", cx - 1, cx + 1, 3.65, 4.9, cd - 1.05, cd - 0.95, C.white, "SmoothPlastic", DECOR)
	kit:label(kit:gui(csign, "Back", 60), { Text = "ORDER HERE", TextColor = C.dark, Font = "Gotham" })
	-- the back bar: the kitchen's front wall with shelves, the coffee machine, the pass and the menu board
	local kd = 15
	kit:box(m, "KitchenWall", 24, 48.8, 0, under(kd), kd, kd + 0.6, C.plaster, "SmoothPlastic")
	kit:box(m, "KitchenWallWest", 24, 24.6, 0, under(kd), kd + 0.6, 23.8, C.plaster, "SmoothPlastic")
	kit:box(m, "BackBarTile", cx0 - 1, cx1 + 1, 0, 3.8, kd - 0.15, kd, { 210, 196, 170 }, "Slate", DECOR)
	kit:box(m, "BackCounter", cx0 - 1, cx1 + 1, 0, 3.4, kd - 1.4, kd - 0.15, C.cedarDark, "Wood")
	kit:box(m, "BackCounterTop", cx0 - 1.1, cx1 + 1.1, 3.4, 3.6, kd - 1.5, kd - 0.1, C.stoneCap, "Concrete", DECOR)
	kit:box(m, "CoffeeMachine", cx - 6.5, cx - 3.7, 3.6, 5.4, kd - 1.3, kd - 0.3, C.steelLight, "Metal", DECOR)
	kit:box(m, "CoffeeTray", cx - 6.4, cx - 3.8, 3.6, 3.75, kd - 1.6, kd - 1.3, C.steel, "Metal", DECOR)
	for i = 0, 2 do
		kit:cyl(m, "Cup", cx - 6.1 + i * 0.9, 5.65, kd - 0.8, 0.5, 0.45, "Y", C.white, "SmoothPlastic", DECOR)
	end
	for _, y in { 5.8, 7.4 } do
		kit:box(m, "Shelf", cx0 - 0.5, cx0 + 4.5, y, y + 0.15, kd - 0.9, kd, C.oak, "Wood", DECOR)
		kit:box(m, "Shelf", cx1 - 4.5, cx1 + 0.5, y, y + 0.15, kd - 0.9, kd, C.oak, "Wood", DECOR)
		for i = 0, 3 do
			local jar = { { 180, 70, 50 }, { 220, 190, 120 }, { 120, 150, 90 }, { 90, 60, 40 } }
			kit:cyl(m, "Jar", cx0 + 0.3 + i * 1.1, y + 0.55, kd - 0.45, 0.8, 0.6, "Y", jar[i + 1], "Glass", DECOR)
			kit:cyl(m, "Jar", cx1 - 3.7 + i * 1.1, y + 0.55, kd - 0.45, 0.8, 0.6, "Y", jar[4 - i], "Glass", DECOR)
		end
	end
	-- the pass: a lit niche into the kitchen with a heat-lamp shelf
	kit:box(m, "PassBack", cx - 2, cx + 3, 3.6, 5.6, kd + 0.6, kd + 0.8, C.steelLight, "Metal", DECOR)
	kit:box(m, "PassShelf", cx - 2, cx + 3, 3.6, 3.7, kd - 0.3, kd + 0.6, C.steelLight, "Metal", DECOR)
	local lamp = kit:box(m, "PassLamp", cx - 1.8, cx + 2.8, 5.3, 5.6, kd - 0.2, kd + 0.5, C.steel, "Metal", DECOR)
	kit:light(
		lamp,
		"SurfaceLight",
		{ Face = "Bottom", Color = { 255, 190, 120 }, Brightness = 1, Range = 5, Angle = 90 }
	)
	kit:box(m, "PassFrameTop", cx - 2.2, cx + 3.2, 5.6, 5.8, kd - 0.05, kd + 0.6, C.bronze, "Metal", DECOR)
	-- the menu board (no price: the lunch is free until the wallet lands; lane 4 says so at the counter)
	local menu = kit:box(
		m,
		"MenuBoard",
		cx - 6,
		cx + 6,
		8.4,
		under(kd) - 0.6,
		kd - 0.25,
		kd - 0.05,
		C.dark,
		"SmoothPlastic",
		DECOR
	)
	local mg = kit:gui(menu, "Back", 40)
	kit:label(mg, { Text = "HILLTOP LUNCH", TextColor = { 255, 226, 170 }, Size = { 0.9, 0.36 }, Pos = { 0.05, 0.08 } })
	kit:label(mg, {
		Text = "Soup of the day, warm bread, apple tart\n- and the best view in town -",
		TextColor = { 230, 224, 210 },
		Size = { 0.9, 0.46 },
		Pos = { 0.05, 0.48 },
		Font = "Gotham",
	})
	kit:light(menu, "SurfaceLight", { Face = "Back", Color = C.warm, Brightness = 0.5, Range = 6, Angle = 60 })
	-- the kitchen door, round porthole
	kit:box(m, "KitchenDoor", 45, 48, 0, 7.4, kd - 0.25, kd + 0.1, C.steelLight, "DiamondPlate")
	kit:cyl(m, "Porthole", 46.5, 5.6, kd - 0.3, 0.1, 1.1, "D", C.glass, "Glass", DECOR)
	kit:box(m, "KitchenDoorFrame", 44.7, 48.3, 7.4, 7.8, kd - 0.3, kd + 0.1, C.bronze, "Metal", DECOR)
	-- three lamps over the counter
	for _, dx in { -4.5, 0, 4.5 } do
		pendant(kit, m, cx + dx, cd, 7.9, C.brass, 0.6)
	end
	-- the fireside corner: stone chimney breast, a glowing fire, a sofa and two armchairs on a rug
	kit:box(m, "ChimneyBreast", -4.5, 4.5, 0, under(23), 21.8, 23.8, C.stone, "Slate")
	kit:box(m, "Mantel", -5, 5, 4.6, 5.0, 21.4, 22.2, C.cedarDark, "Wood")
	kit:box(m, "Firebox", -2.6, 2.6, 0.6, 3.8, 21.7, 22.4, C.dark, "Slate", { collide = false })
	kit:box(m, "Hearth", -5, 5, 0, 0.4, 19.8, 21.8, C.stoneCap, "Concrete")
	local fire = kit:box(m, "FireGlow", -1.4, 1.4, 0.7, 1.6, 21.75, 21.85, C.fire, "Neon", DECOR)
	kit:light(fire, "PointLight", { Color = { 255, 150, 70 }, Brightness = 2, Range = 18, Shadows = true })
	for i = -1, 1 do
		kit:cyl(m, "Log", i * 0.8, 0.75, 22.6, 2.4, 0.4, "X", { 96, 64, 42 }, "Wood", DECOR)
	end
	kit:box(m, "Rug", -7, 7, 0, 0.05, 13.5, 19.6, { 150, 74, 56 }, "Fabric", DECOR)
	-- the sofa faces the fire
	local sofa = kit:model(m, "Sofa")
	kit:box(sofa, "Base", -3.6, 3.6, 0, 1.2, 14.3, 16.4, C.leather, "Fabric")
	kit:box(sofa, "Back", -3.6, 3.6, 1.2, 3.6, 13.6, 14.3, C.leather, "Fabric")
	for _, x in { -3.6, 3.6 } do
		kit:box(sofa, "Arm", x - 0.35, x + 0.35, 1.2, 2.3, 13.6, 16.4, C.leather, "Fabric")
	end
	for _, x in { -1.6, 1.6 } do
		seat(kit, sofa, x, 1.6, 15.4, 3, 2, "+D", C.cushion)
	end
	for _, x in { -6.6, 6.6 } do
		local ch = kit:model(m, "Armchair")
		seat(kit, ch, x, 1.6, 19.4, 2, 2, if x < 0 then "+X" else "-X", C.fabric)
		local bx = if x < 0 then x - 1.2 else x + 1.2
		kit:box(ch, "Back", bx - 0.3, bx + 0.3, 0, 3.4, 18.3, 20.5, C.fabric, "Fabric")
		kit:box(ch, "Base", x - 1, x + 1, 0, 1.3, 18.4, 20.4, C.fabric, "Fabric", DECOR)
	end
	kit:box(m, "CoffeeTable", -1.6, 1.6, 0, 1.4, 17.2, 18.6, C.oak, "Wood")
	-- the panorama on the wall to the lift hall: the town from the hill, painted
	local px, pd0, pd1, py0, py1 = -19.1, 8, 14, 2.8, 8.4
	kit:box(
		m,
		"PanoramaFrame",
		px - 0.05,
		px + 0.2,
		py0 - 0.25,
		py1 + 0.25,
		pd0 - 0.25,
		pd1 + 0.25,
		C.cedarDark,
		"Wood",
		DECOR
	)
	local bands = {
		{ 0.62, 1.0, { 132, 176, 214 } }, -- sky
		{ 0.5, 0.62, { 170, 196, 214 } }, -- haze
		{ 0.42, 0.5, { 92, 118, 132 } }, -- far ranges
		{ 0.36, 0.42, { 70, 120, 160 } }, -- sea
		{ 0.0, 0.36, { 104, 140, 80 } }, -- the plain
	}
	for _, b in bands do
		kit:box(
			m,
			"Panorama",
			px + 0.2,
			px + 0.25,
			py0 + b[1] * (py1 - py0),
			py0 + b[2] * (py1 - py0),
			pd0,
			pd1,
			b[3],
			"SmoothPlastic",
			DECOR
		)
	end
	local roofs = { { 200, 120, 90 }, { 230, 220, 200 }, { 150, 90, 70 }, { 210, 200, 170 }, { 180, 70, 60 } }
	for i = 0, 9 do
		local u = pd0 + 0.4 + i * 0.55
		local h = 0.3 + ((i * 37) % 5) * 0.12
		kit:box(
			m,
			"PanoramaHouse",
			px + 0.25,
			px + 0.3,
			py0 + 1.3,
			py0 + 1.3 + h,
			u,
			u + 0.4,
			roofs[i % 5 + 1],
			"SmoothPlastic",
			DECOR
		)
	end
	local cap = kit:box(
		m,
		"PanoramaCaption",
		px + 0.2,
		px + 0.25,
		py0 - 0.9,
		py0 - 0.35,
		pd0 + 1,
		pd1 - 1,
		C.dark,
		"SmoothPlastic",
		DECOR
	)
	kit:label(
		kit:gui(cap, "Right", 60),
		{ Text = "THE TOWN FROM LOOKOUT HILL", TextColor = { 230, 220, 190 }, Font = "Gotham" }
	)
	-- plants in the corners
	plant(kit, m, -17.5, -19, 3)
	plant(kit, m, 47.5, -19, 3)
	plant(kit, m, 47.5, 9, 2.5)
	plant(kit, m, -17.5, 12, 2.5)
	-- warm wall washers over the window bar for the evening glow seen from the town
	for i, x in { -12, 2, 28, 42 } do
		local w = kit:box(
			m,
			`Washer{i}`,
			x - 0.6,
			x + 0.6,
			under(-23) - 0.3,
			under(-23) - 0.1,
			-23.6,
			-22.8,
			C.bronze,
			"Metal",
			DECOR
		)
		kit:light(w, "SpotLight", { Face = "Bottom", Color = C.warm, Brightness = 1.1, Range = 14, Angle = 70 })
	end
	return m
end

---------------------------------------------------------------------------------------------------------------
-- The terrace: deck on posts, glass rail, tables with parasols, the telescope, lanterns, the bench, the steps
local function railRun(
	kit: Kit,
	parent: any,
	axis: string,
	fixed: number,
	a0: number,
	a1: number,
	top: number,
	slim: boolean?
)
	local n = math.max(1, math.ceil((a1 - a0) / (if slim then 8 else 5.5)))
	local step = (a1 - a0) / n
	local function box(name: string, u0: number, u1: number, y0: number, y1: number, t: number, c, mat: string, o: any?)
		if axis == "X" then
			return kit:box(parent, name, u0, u1, y0, y1, fixed - t, fixed + t, c, mat, o)
		end
		return kit:box(parent, name, fixed - t, fixed + t, y0, y1, u0, u1, c, mat, o)
	end
	local post = if slim then 0.08 else 0.15
	local capH = if slim then 0.1 else 0.2
	for i = 0, n do
		local u = a0 + i * step
		box("RailPost", u - post, u + post, 0, top - capH, post, C.steel, "Metal")
		if i < n then
			box(
				"RailGlass",
				u + post + 0.03,
				u + step - post - 0.03,
				0.3,
				top - capH - 0.05,
				0.06,
				C.glass,
				"Glass",
				{ transparency = if slim then 0.8 else 0.72, reflectance = 0.06 }
			)
		end
	end
	if slim then
		box("RailTop", a0 - 0.1, a1 + 0.1, top - capH, top, 0.06, C.steel, "Metal")
	else
		box("RailCap", a0 - 0.2, a1 + 0.2, top - capH, top, 0.25, C.oak, "Wood")
	end
end

local function telescope(kit: Kit, parent: any, X: number, D: number)
	local m = kit:model(parent, "Telescope")
	local CF = kit.roblox.CFrame
	kit:cyl(m, "Plate", X, 0.08, D, 0.16, 1.6, "Y", C.steel, "Metal")
	kit:cyl(m, "Column", X, 1.9, D, 3.6, 0.45, "Y", C.scope, "Metal")
	kit:box(m, "CoinBox", X - 0.3, X + 0.3, 2.6, 3.3, D + 0.2, D + 0.6, C.scope, "Metal", DECOR)
	kit:box(m, "CoinPlate", X - 0.18, X + 0.18, 2.95, 3.15, D + 0.6, D + 0.64, C.brass, "Metal", DECOR)
	kit:box(m, "Yoke", X - 0.55, X + 0.55, 3.7, 4.2, D - 0.25, D + 0.25, C.scope, "Metal")
	-- the head, tipped down 6 degrees toward the town
	local tilt = CF.Angles(math.rad(-6), 0, 0)
	kit:at(m, "Head", X, 4.75, D, 1.5, 0.95, 1.6, C.scope, "Metal", { rot = tilt })
	for _, dx in { -0.36, 0.36 } do
		kit:cyl(m, "Lens", X + dx, 4.68, D - 0.85, 0.2, 0.5, "D", C.brass, "Metal", opts(DECOR, { rot = tilt }))
		kit:cyl(m, "Eyepiece", X + dx, 4.86, D + 0.9, 0.3, 0.32, "D", C.dark, "Metal", opts(DECOR, { rot = tilt }))
	end
	kit:at(m, "Visor", X, 5.15, D + 0.75, 1.5, 0.12, 0.5, C.dark, "Metal", opts(DECOR, { rot = tilt }))
	kit:box(m, "Step", X - 0.8, X + 0.8, 0, 0.35, D + 0.9, D + 1.8, C.steel, "DiamondPlate")
	local card = kit:box(m, "Card", X - 0.35, X + 0.35, 2.1, 2.5, D - 0.26, D - 0.23, C.white, "SmoothPlastic", DECOR)
	kit:label(kit:gui(card, "Back", 80), { Text = "FREE", TextColor = C.dark })
	return m
end

local function lantern(kit: Kit, parent: any, X: number, D: number, y: number)
	kit:box(parent, "LanternArm", X - 0.08, X + 0.08, y - 0.4, y, D - 0.08, D + 0.08, C.steel, "Metal", DECOR)
	kit:box(parent, "LanternCap", X - 0.35, X + 0.35, y + 0.55, y + 0.7, D - 0.35, D + 0.35, C.steel, "Metal", DECOR)
	local glow =
		kit:box(parent, "LanternGlass", X - 0.25, X + 0.25, y, y + 0.55, D - 0.25, D + 0.25, C.warm, "Neon", DECOR)
	kit:light(glow, "PointLight", { Color = C.warm, Brightness = 1.1, Range = 13, Shadows = false })
end

local function terrace(kit: Kit, root: any, venue: any, sky: { SkyItem })
	local m = kit:model(root, "Terrace")
	local T = Lookout.TERRACE
	-- the deck: planks on two beams, posts on footings down the slope
	local deck = kit:box(m, "Deck", T.x0, T.x1, -0.5, 0, T.d0, T.d1, C.deck, "WoodPlanks")
	skyMark(sky, deck)
	kit:box(m, "DeckFasciaFront", T.x0 - 0.3, T.x1 + 0.3, -1.6, 0, T.d0 - 0.3, T.d0, C.cedarDark, "Wood")
	kit:box(m, "DeckFasciaWest", T.x0 - 0.3, T.x0, -1.6, 0, T.d0, T.d1, C.cedarDark, "Wood")
	kit:box(m, "DeckFasciaEast", T.x1, T.x1 + 0.3, -1.6, 0, T.d0, T.d1, C.cedarDark, "Wood")
	local postsX = { -23, -11, 1, 11, 19, 31, 41, 49 }
	for _, d in { -46, -35.5 } do
		kit:box(m, "DeckBeam", T.x0, T.x1, -1.7, -0.5, d - 0.4, d + 0.4, C.steel, "Metal")
		for _, x in postsX do
			local g = groundY(kit, x, d)
			kit:box(m, "DeckPost", x - 0.35, x + 0.35, g - 0.6, -1.7, d - 0.35, d + 0.35, C.steel, "Metal")
			kit:box(m, "Footing", x - 0.9, x + 0.9, g - 1.2, g + 0.35, d - 0.9, d + 0.9, C.concrete, "Concrete")
		end
	end
	-- diagonal braces under the front beam between alternate posts
	for i = 1, #postsX - 1, 2 do
		local xa, xb = postsX[i], postsX[i + 1]
		local ga = groundY(kit, xa, -46)
		kit:rod(m, "Brace", xa, math.max(ga + 0.6, -6), -46, xb, -1.8, -46, 0.25, C.steel, "Metal", DECOR)
	end
	-- the glass rail, broken at the steps
	local S = Lookout.STEPS
	railRun(kit, m, "X", T.d0 + 0.3, T.x0 + 0.3, S.x0, T.frontTop, true)
	railRun(kit, m, "X", T.d0 + 0.3, S.x1, T.x1 - 0.3, T.frontTop, true)
	railRun(kit, m, "D", T.x0 + 0.3, T.d0 + 0.3, T.d1, T.railTop)
	railRun(kit, m, "D", T.x1 - 0.3, T.d0 + 0.3, T.d1, T.railTop)
	-- tables with parasols (anchors terrace_1..4) and a candle jar each (lit at night)
	local anchorAt: { [string]: { number } } = {}
	for _, a in venue.anchors do
		anchorAt[a.id] = a.at
	end
	for k = 1, 4 do
		local at = anchorAt[`terrace_{k}`]
		if at then
			local x, d = at[1], at[3]
			local t = table4(kit, m, `TerraceTable{k}`, x, d, { 220, 218, 210 }, "Marble", C.canvas, C.steelLight)
			kit:cyl(t, "ParasolPole", x, 4.9, d, 4.3, 0.16, "Y", C.steelLight, "Metal", DECOR)
			kit:cyl(
				t,
				"Parasol",
				x,
				7.0,
				d,
				0.25,
				7.2,
				"Y",
				if k % 2 == 0 then C.canvasStripe else C.canvas,
				"Fabric",
				DECOR
			)
			kit:cyl(
				t,
				"ParasolCrown",
				x,
				7.3,
				d,
				0.35,
				3.6,
				"Y",
				if k % 2 == 0 then C.canvas else C.canvasStripe,
				"Fabric",
				DECOR
			)
			kit:cyl(t, "ParasolFinial", x, 7.6, d, 0.3, 0.3, "Y", C.steelLight, "Metal", DECOR)
			local jar = kit:cyl(t, "CandleJar", x + 0.9, 3.05, d + 0.4, 0.5, 0.35, "Y", C.warm, "Neon", DECOR)
			kit:light(jar, "PointLight", { Color = { 255, 190, 120 }, Brightness = 0.6, Range = 6, Shadows = false })
		end
	end
	-- the free telescope (anchor `telescope`) looking over the town
	local ta = anchorAt.telescope or { 15, 0, -44 }
	telescope(kit, m, ta[1], ta[3])
	-- lanterns on the side rails' posts (none on the town-facing run: they sat on the town band from a seat),
	-- planters at the corners, a bench by the west rail to watch the cabins
	for _, d in { -42.2, -35.6, -29 } do
		lantern(kit, m, T.x1 - 0.3, d, T.railTop + 0.5)
		lantern(kit, m, T.x0 + 0.3, d, T.railTop + 0.5)
	end
	for _, p in { { T.x0 + 1.8, T.d0 + 1.8 }, { T.x1 - 1.8, T.d0 + 1.8 }, { T.x1 - 1.8, T.d1 - 2 } } do
		local pl = kit:model(m, "Planter")
		kit:box(pl, "Box", p[1] - 1.2, p[1] + 1.2, 0, 1.8, p[2] - 1.2, p[2] + 1.2, C.cedarDark, "WoodPlanks")
		kit:box(pl, "Soil", p[1] - 1.05, p[1] + 1.05, 1.8, 1.85, p[2] - 1.05, p[2] + 1.05, C.soil, "Ground", DECOR)
		kit:ball(pl, "Shrub", p[1], 2.7, p[2], 2.4, C.leaf, "Grass", DECOR)
		kit:ball(pl, "Bloom", p[1] + 0.5, 3.4, p[2] - 0.3, 1.3, { 200, 120, 160 }, "Grass", DECOR)
	end
	local bench = kit:model(m, "Bench")
	local bx = T.x0 + 2.2
	seat(kit, bench, bx, 1.5, -36, 1.4, 8, "-X", C.deck)
	kit:box(bench, "Back", bx + 0.6, bx + 0.8, 1.5, 3.2, -40, -32, C.deck, "WoodPlanks", { collide = false })
	for _, d in { -39.4, -32.6 } do
		kit:box(bench, "Leg", bx - 0.65, bx + 0.75, 0, 1.2, d - 0.1, d + 0.1, C.steel, "Metal", DECOR)
	end
	return m
end

-- The terrace steps: from the deck edge (D -47) down the slope to the trail head, on the trail's path.
local function steps(kit: Kit, root: any)
	local m = kit:model(root, "TerraceSteps")
	local S = Lookout.STEPS
	local x0, x1 = S.x0, S.x1
	local d = Lookout.TERRACE.d0
	local y = 0
	local k = 0
	while true do
		k += 1
		local top = -k * S.rise
		local da, db = d - S.tread, d
		local g, gHigh = groundRange(kit, x0, x1, da, db)
		if top <= gHigh + 0.3 then
			-- the landing at the foot, on the ground (never above the last tread)
			local gl, glHigh = groundRange(kit, x0 - 1, x1 + 1, da - 2, db)
			local ly = math.min(y - 0.15, math.max(top, glHigh + 0.15))
			kit:box(m, "Landing", x0 - 1, x1 + 1, gl - 1.5, ly, da - 2, db, C.concrete, "Concrete")
			d = da - 2
			y = ly
			break
		end
		kit:box(m, `Step{k}`, x0, x1, g - 1.2, top, da, db, C.concrete, "Concrete")
		kit:box(m, `Nosing{k}`, x0, x1, top - 0.02, top + 0.02, db - 0.3, db, C.steel, "Metal", DECOR)
		d = da
		y = top
		if k > 30 then
			error("Lookout: the terrace steps never reach the ground")
		end
	end
	S.run = Lookout.TERRACE.d0 - d
	S.footY = y
	-- cheek walls and handrails both sides
	for _, x in { x0 - 0.35, x1 + 0.35 } do
		local g = minGround(kit, x - 0.35, x + 0.35, d, Lookout.TERRACE.d0)
		plank(kit, m, "Cheek", x, Lookout.TERRACE.d0, -0.4, d + 2, y - 0.4, 0.7, 0.8, C.stone, "Slate")
		kit:box(m, "CheekFoot", x - 0.35, x + 0.35, g - 1, y - 0.2, d, d + 2.2, C.stone, "Slate")
		kit:rod(m, "Handrail", x, 3.2, Lookout.TERRACE.d0 + 0.2, x, y + 3.2, d + 2.2, 0.22, C.steel, "Metal")
		for _, f in { 0.15, 0.55, 0.95 } do
			local pd = Lookout.TERRACE.d0 - f * (Lookout.TERRACE.d0 - (d + 2.2))
			local py = f * (y - 0) -- along the flight
			kit:box(
				m,
				"HandrailPost",
				x - 0.08,
				x + 0.08,
				py - 0.6,
				py + 3.2,
				pd - 0.08,
				pd + 0.08,
				C.steel,
				"Metal",
				DECOR
			)
		end
	end
	-- a fingerpost at the foot for those arriving on foot
	local sx = x1 + 2.6
	local sd = d + 1
	kit:box(m, "SignPost", sx - 0.15, sx + 0.15, y - 1, y + 6.2, sd - 0.15, sd + 0.15, C.cedarDark, "Wood")
	local arm = kit:box(
		m,
		"SignArm",
		sx - 2.4,
		sx + 0.2,
		y + 4.8,
		y + 5.8,
		sd - 0.12,
		sd + 0.12,
		{ 230, 220, 196 },
		"Wood",
		DECOR
	)
	kit:label(kit:gui(arm, "Back", 50), { Text = "THE LOOKOUT  ↑", TextColor = { 60, 44, 30 }, Font = "Gotham" })
	kit:label(kit:gui(arm, "Front", 50), { Text = "TOWN  ·  SKY LIFT", TextColor = { 60, 44, 30 }, Font = "Gotham" })
end

---------------------------------------------------------------------------------------------------------------
-- Anchors (F3-owned only; the lift's own, alight / board_down / cable_in, are lane 2's)
local function anchors(kit: Kit, root: any, venue: any)
	local f = kit:folder(root, "Anchors")
	for _, a in venue.anchors do
		if a.owner == "F3" then
			local at = a.at
			local p = kit:at(f, a.id, at[1], at[2], at[3], 0.2, 0.2, 0.2, { 255, 255, 0 }, "SmoothPlastic", {
				collide = false,
				query = false,
				transparency = 1,
				shadow = false,
				rot = kit.roblox.CFrame.Angles(0, math.rad(a.yaw or 0), 0),
				attrs = { Kind = a.kind, Owner = a.owner },
			})
			local _ = p
		end
	end
end

-- The far-view layer: inset copies of the marked parts (inside the real ones, so they never show up close) and
-- the window band, baked invisible with FarOnly for the client to show while the venue is streamed out.
local function skyline(kit: Kit, parent: any, venue: any, sky: { SkyItem }): any
	local roblox = kit.roblox
	local m = roblox.Instance.new("Model")
	m.Name = `{venue.id}_Skyline`
	m.ModelStreamingMode = roblox.Enum.ModelStreamingMode.Persistent
	m:SetAttribute("VenueId", venue.id)
	m:SetAttribute("SkylineOf", venue.id)
	local far = { collide = false, query = false, shadow = false }
	-- the biggest faces first; at most SKY_MAX - 2 copies (the window bands are the other two)
	local function face(it: SkyItem): number
		local s = it.part.Size
		local a = { s.X, s.Y, s.Z }
		table.sort(a)
		return a[2] * a[3]
	end
	table.sort(sky, function(a: SkyItem, b: SkyItem): boolean
		return face(a) > face(b)
	end)
	while #sky > Lookout.SKY_MAX - 2 do
		table.remove(sky)
	end
	for i, it in sky do
		local src = it.part
		local s = src.Size
		local g = it.inset * 2
		local p = roblox.Instance.new(src.ClassName == "Seat" and "Part" or src.ClassName)
		p.Size = roblox.Vector3.new(math.max(s.X - g, 0.05), math.max(s.Y - g, 0.05), math.max(s.Z - g, 0.05))
		p.CFrame = src.CFrame
		p.Name = `Far{i}_{src.Name}`
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Color = src.Color
		p.Material = src.Material
		p.TopSurface = roblox.Enum.SurfaceType.Smooth
		p.BottomSurface = roblox.Enum.SurfaceType.Smooth
		p.Parent = m
		kit.count += 1
	end
	-- the lit window band across the glass front (warm), shown only from far
	local band =
		kit:box(m, "FarWindowBand", -19, 49, 1, 12.8, -24.9, -24.7, C.warm, "Neon", opts(far, { transparency = 1 }))
	band:SetAttribute("FarOnly", true)
	band:SetAttribute("FarTransparency", 0.15)
	local bandE = kit:box(
		m,
		"FarWindowBandEast",
		49.1,
		49.3,
		1,
		11.6,
		-24.4,
		-0.4,
		C.warm,
		"Neon",
		opts(far, { transparency = 1 })
	)
	bandE:SetAttribute("FarOnly", true)
	bandE:SetAttribute("FarTransparency", 0.15)
	m.Parent = parent
	return m
end

---------------------------------------------------------------------------------------------------------------
function Lookout.build(kit: Kit, parent: any, venue: any): any
	-- the posts and steps stand on World/Height with the hill (D32 terrain extensions): configure it if the
	-- caller has not, and put it back as found
	local borrowed = Height.at(venue.place.x, venue.place.z) < venue.floorY - 20
	if borrowed then
		Height.configure(TerrainExtensions)
	end
	local roblox = kit.roblox
	local root = roblox.Instance.new("Model")
	root.Name = venue.id
	root.ModelStreamingMode = roblox.Enum.ModelStreamingMode.Atomic
	root:SetAttribute("VenueId", venue.id)
	root:SetAttribute("Family", venue.family)
	root:SetAttribute("Type", venue.type)
	root:SetAttribute("FloorY", venue.floorY)
	root:SetAttribute("Yaw", venue.yaw)
	root:SetAttribute("OriginX", venue.place.x)
	root:SetAttribute("OriginZ", venue.place.z)
	root:SetAttribute("PartBudget", venue.partBudget)
	local start = kit.count
	local sky: { SkyItem } = {}
	base(kit, root, sky)
	hall(kit, root, sky)
	diningShell(kit, root, sky)
	diningInside(kit, root, venue)
	terrace(kit, root, venue, sky)
	steps(kit, root)
	anchors(kit, root, venue)
	root.Parent = parent
	local skyStart = kit.count
	local sm = skyline(kit, parent, venue, sky)
	root:SetAttribute("Parts", skyStart - start)
	sm:SetAttribute("Parts", kit.count - skyStart)
	if borrowed then
		Height.configure(nil)
	end
	return root
end

return Lookout
