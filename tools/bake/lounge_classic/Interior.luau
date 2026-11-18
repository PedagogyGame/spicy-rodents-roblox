--!strict
-- tools/bake/lounge_classic/Interior: THE GILDED ACORN's room. Walnut panelling to the chair rail, claret paper
-- above, a crown moulding and a beamed plaster ceiling; a rug with a gold border; the long polished bar with
-- its leather arm roll, brass foot rail and seven leather stools; the back bar with its mirror, cups, tea tins,
-- the coffee urn, the cocoa pot, the teapot and the snow-cone machine (hot drinks and snow cones only: no
-- bottles, taps or cocktail glasses anywhere); four leather booths; club chairs round four small tables; the
-- stage with velvet drapes, a grand piano, a ribbon microphone and the console radio; the fireplace with two
-- armchairs; two palms by the door. The lamps are in Lamps.
-- Interface: build(kit, root, venue) -> Model "Interior". No side effects on require.

local Kit = require("../alley/Kit")
local Style = require("./Style")

local Interior = {}

local GHOST = { collide = false, query = false, shadow = false }
local FLAT = { collide = false, query = false } -- casts a shadow, nobody stands on it

-- Panelling, chair rail, paper and crown on one stretch of wall (its inner face at `face`, facing `n`, along
-- the other axis from a to b). axis "X": the wall runs along X (a front or back wall); "D": along D.
local function lining(kit: Kit.Kit, m: any, name: string, axis: string, face: number, n: number, a: number, b: number)
	local function slab(part: string, y0: number, y1: number, depth: number, color: { number }, material: string)
		local f0, f1 = face, face + n * depth
		if axis == "X" then
			kit:box(m, `{name}{part}`, a, b, y0, y1, f0, f1, color, material, GHOST)
		else
			kit:box(m, `{name}{part}`, f0, f1, y0, y1, a, b, color, material, GHOST)
		end
	end
	slab("Panel", 0, Style.WAINSCOT, 0.25, Style.WALNUT, "Wood")
	slab("Rail", Style.WAINSCOT, Style.WAINSCOT + 0.3, 0.38, Style.MAHOGANY, "Wood")
	slab("Paper", Style.WAINSCOT + 0.3, Style.CROWN, 0.12, Style.PAPER, "Fabric")
	slab("Crown", Style.CROWN, Style.CEILING, 0.4, Style.WALNUT, "Wood")
end

local function walls(kit: Kit.Kit, m: any)
	local IX, F, IB = Style.INNER_X, Style.FRONT_D + Style.WALL, Style.INNER_BACK
	local AX, h = Style.ALCOVE_X + Style.WALL, Style.DOOR_HALF
	local DI = Style.DOOR_D + Style.WALL -- the door wall's inner face
	lining(kit, m, "West", "D", -IX, 1, F, IB)
	lining(kit, m, "East", "D", IX, -1, F, IB)
	lining(kit, m, "Back", "X", IB, -1, -IX, IX)
	lining(kit, m, "FrontW", "X", F, 1, -IX, -AX)
	lining(kit, m, "FrontE", "X", F, 1, AX, IX)
	lining(kit, m, "SideW", "D", -AX, -1, F, DI)
	lining(kit, m, "SideE", "D", AX, 1, F, DI)
	lining(kit, m, "DoorW", "X", DI, 1, -AX, -h - 0.35)
	lining(kit, m, "DoorE", "X", DI, 1, h + 0.35, AX)
	-- walnut pilasters on the side walls (the sconces hang on three of them)
	for _, s in { -1, 1 } do
		for _, d in { -24, -17, -3, 11, 24 } do
			if not (s > 0 and d == 24) then
				local x0 = s * IX
				kit:box(
					m,
					`Pilaster{s}{d}`,
					x0,
					x0 - s * 0.45,
					0,
					Style.CROWN,
					d - 0.35,
					d + 0.35,
					Style.WALNUT,
					"Wood",
					GHOST
				)
			end
		end
	end
	-- the beamed ceiling
	for _, d in { -20, -12, -4, 4, 12, 20 } do
		kit:box(m, `Beam{d}`, -IX, IX, Style.CROWN, Style.CEILING, d - 0.4, d + 0.4, Style.WALNUT, "Wood", GHOST)
	end
	for _, x in { -8, 8 } do
		kit:box(m, `Girder{x}`, x - 0.4, x + 0.4, Style.CROWN + 0.1, Style.CEILING, F, IB, Style.WALNUT, "Wood", GHOST)
	end
	-- the rug, its gold border and the runner from the door
	kit:box(m, "RugBorder", -9.6, 9.6, 0, 0.03, -17.6, 9.6, Style.RUG_BORDER, "Carpet", GHOST)
	kit:box(m, "Rug", -9, 9, 0, 0.05, -17, 9, Style.RUG, "Carpet", GHOST)
	kit:box(m, "Runner", -2, 2, 0, 0.04, DI, -17.6, Style.RUG, "Carpet", GHOST)
end

local function bar(kit: Kit.Kit, m: any)
	local X, D0, D1 = Style.BAR_X, Style.BAR_D0, Style.BAR_D1
	local top = Style.BAR_TOP
	kit:box(m, "BarKick", -X, X, 0, 0.5, D0 + 0.3, D1, Style.DARK_WOOD, "Wood")
	kit:box(m, "BarFront", -X, X, 0.5, top - 0.35, D0, D1, Style.MAHOGANY, "Wood")
	kit:box(
		m,
		"BarTop",
		-X - 0.5,
		X + 0.5,
		top - 0.35,
		top,
		D0 - 0.5,
		D1 + 0.6,
		Style.WALNUT,
		"Wood",
		{ reflectance = 0.12 }
	)
	kit:cyl(m, "ArmRoll", 0, top + 0.12, D0 - 0.3, 2 * X + 0.8, 0.36, "X", Style.LEATHER, "Leather", FLAT)
	for _, x in { -X, -X / 3, X / 3, X } do
		kit:box(m, `BarStrip{x}`, x - 0.18, x + 0.18, 0.5, top - 0.35, D0 - 0.08, D0, Style.BRASS, "Metal", GHOST)
	end
	for _, x in { -X / 1.5, 0, X / 1.5 } do
		kit:box(m, `BarPanel{x}`, x - 3, x + 3, 0.9, top - 0.75, D0 - 0.06, D0, Style.LEATHER, "Leather", GHOST)
	end
	-- the brass foot rail on its brackets
	kit:cyl(m, "FootRail", 0, 0.7, D0 - 0.8, 2 * X, 0.26, "X", Style.BRASS, "Metal", { collide = false, query = false })
	for _, x in { -X + 1, -X / 2, 0, X / 2, X - 1 } do
		kit:box(m, `RailBracket{x}`, x - 0.08, x + 0.08, 0.55, 0.85, D0 - 0.8, D0, Style.BRASS, "Metal", GHOST)
	end
	-- seven stools
	for i = -3, 3 do
		local x = i * Style.STOOL_GAP
		kit:cyl(m, `StoolFoot{i}`, x, 0.06, Style.STOOLS_D, 0.12, 1.1, "Y", Style.BRASS, "Metal", GHOST)
		kit:cyl(m, `StoolPost{i}`, x, 1.15, Style.STOOLS_D, 2.1, 0.24, "Y", Style.BRASS, "Metal", { collide = true })
		kit:cyl(m, `StoolSeat{i}`, x, 2.38, Style.STOOLS_D, 0.36, 1.3, "Y", Style.LEATHER, "Leather")
	end
end

local function backBar(kit: Kit.Kit, m: any)
	local D, IB = Style.BACKBAR_D, Style.INNER_BACK - 0.25
	kit:box(m, "Cabinet", -11, 11, 0, 3.2, D, IB, Style.MAHOGANY, "Wood")
	kit:box(m, "CabinetTop", -11.2, 11.2, 3.2, 3.45, D - 0.2, IB, Style.STONE, "Marble", { reflectance = 0.08 })
	for _, x in { -8, -3, 3, 8 } do
		kit:box(m, `CabinetDoor{x}`, x - 2, x + 2, 0.5, 2.8, D - 0.08, D, Style.DARK_WOOD, "Wood", GHOST)
	end
	kit:box(m, "MirrorFrame", -9.4, 9.4, 4.3, 10.3, IB - 0.12, IB, Style.GOLD, "Metal", GHOST)
	kit:box(
		m,
		"Mirror",
		-9,
		9,
		4.6,
		10,
		IB - 0.2,
		IB - 0.12,
		{ 120, 112, 104 },
		"Glass",
		{ collide = false, query = false, shadow = false, reflectance = 0.35 }
	)
	for i, y in { 6, 8.2 } do
		kit:box(m, `Shelf{i}`, -9, 9, y - 0.15, y, IB - 1.1, IB - 0.2, Style.WALNUT, "Wood", GHOST)
	end
	-- cups on the lower shelf, tea tins on the upper
	for i = 0, 7 do
		local x = -7.7 + i * 2.2
		kit:cyl(m, `Cup{i}`, x, 6.22, IB - 0.65, 0.44, 0.5, "Y", Style.CHINA, "SmoothPlastic", GHOST)
	end
	local tins = { Style.LEATHER, Style.GOLD, Style.COPPER }
	for i = 0, 5 do
		local x = -7.5 + i * 3
		kit:box(m, `Tin{i}`, x - 0.35, x + 0.35, 8.2, 9.1, IB - 0.95, IB - 0.35, tins[i % 3 + 1], "Metal", GHOST)
	end
	-- the menu over the mirror: the four things the bartender serves
	local menu = kit:box(m, "MenuBoard", -9.4, 9.4, 10.6, 12.0, IB - 0.12, IB, Style.BLACK, "Marble", GHOST)
	kit:label(kit:gui(menu, "Back", 40), {
		Text = Style.MENU,
		TextColor = Style.GOLD,
		Font = "Bodoni",
		Size = { 0.94, 0.62 },
		Pos = { 0.03, 0.19 },
	})
	-- on the counter: the coffee urn, the cocoa pot and its mugs, the teapot, the snow-cone machine
	local t = 3.45
	kit:cyl(m, "UrnBody", -7, t + 1.1, D + 1.1, 2.2, 1.4, "Y", Style.BRASS, "Metal", GHOST)
	kit:cyl(m, "UrnLid", -7, t + 2.35, D + 1.1, 0.3, 1.0, "Y", Style.BRASS, "Metal", GHOST)
	kit:ball(m, "UrnKnob", -7, t + 2.6, D + 1.1, 0.3, Style.DARK_WOOD, "Wood", GHOST)
	kit:box(m, "UrnTap", -7.1, -6.9, t + 0.5, t + 0.7, D + 0.1, D + 0.45, Style.BRASS, "Metal", GHOST)
	kit:cyl(m, "CocoaPot", -3.5, t + 0.6, D + 1.1, 1.2, 1.0, "Y", Style.COPPER, "Metal", GHOST)
	kit:rod(m, "CocoaSpout", -3.5, t + 0.8, D + 0.6, -3.5, t + 1.2, D + 0.15, 0.16, Style.COPPER, "Metal", GHOST)
	for i = 0, 2 do
		kit:cyl(m, `Mug{i}`, -1.8 + i * 0.7, t + 0.25, D + 1.0, 0.5, 0.48, "Y", Style.CHINA, "SmoothPlastic", GHOST)
	end
	kit:ball(m, "Teapot", 1.8, t + 0.45, D + 1.1, 0.9, Style.CHINA, "SmoothPlastic", GHOST)
	kit:rod(m, "TeaSpout", 1.8, t + 0.4, D + 0.75, 1.8, t + 0.7, D + 0.35, 0.14, Style.CHINA, "SmoothPlastic", GHOST)
	kit:box(m, "ConeBase", 4.2, 6.2, t, t + 0.9, D + 0.4, D + 1.8, Style.VELVET, "SmoothPlastic", GHOST)
	kit:box(
		m,
		"ConeGlass",
		4.3,
		6.1,
		t + 0.9,
		t + 2.5,
		D + 0.5,
		D + 1.7,
		{ 220, 236, 240 },
		"Glass",
		{ collide = false, query = false, shadow = false, transparency = 0.55 }
	)
	kit:box(m, "ConeIce", 4.5, 5.9, t + 0.9, t + 1.6, D + 0.7, D + 1.5, { 248, 250, 252 }, "Snow", GHOST)
	kit:box(m, "ConeCap", 4.2, 6.2, t + 2.5, t + 2.8, D + 0.4, D + 1.8, Style.VELVET, "SmoothPlastic", GHOST)
	kit:cyl(m, "ConeCups", 7.4, t + 0.6, D + 1.1, 1.2, 0.5, "Y", Style.IVORY, "SmoothPlastic", GHOST)
end

local function booths(kit: Kit.Kit, m: any)
	for i, b in Style.BOOTHS do
		local s, c = if b[1] < 0 then -1 else 1, b[2]
		local x0, x1 = s * Style.BOOTH_X0, s * Style.BOOTH_X1
		for _, side in { -1, 1 } do
			local d0, d1 = c + side * 2.4, c + side * 4
			local back = c + side * 3.4
			kit:box(m, `Booth{i}Plinth{side}`, x0, x1, 0, 0.9, d0, d1, Style.DARK_WOOD, "Wood")
			kit:box(m, `Booth{i}Seat{side}`, x0, x1, 0.9, 1.7, d0, d1, Style.LEATHER, "Leather")
			kit:box(m, `Booth{i}Back{side}`, x0, x1, 1.7, 4.6, back, d1, Style.LEATHER, "Leather")
			kit:box(m, `Booth{i}Cap{side}`, x0, x1, 4.6, 4.85, back - side * 0.1, d1 + side * 0.1, Style.WALNUT, "Wood")
		end
		local tx = s * (Style.BOOTH_X0 + Style.BOOTH_X1) / 2
		kit:box(
			m,
			`Booth{i}Table`,
			s * (Style.BOOTH_X0 + 1.4),
			x1,
			2.6,
			2.85,
			c - 1.5,
			c + 1.5,
			Style.WALNUT,
			"Wood",
			{ reflectance = 0.1 }
		)
		kit:cyl(m, `Booth{i}Pedestal`, tx, 1.3, c, 2.6, 0.5, "Y", Style.BRASS, "Metal")
	end
end

local function clubTables(kit: Kit.Kit, m: any)
	for i, tb in Style.TABLES do
		local x, d = tb[1], tb[2]
		kit:cyl(m, `Table{i}Top`, x, 2.4, d, 0.2, 2.6, "Y", Style.WALNUT, "Wood", { reflectance = 0.1 })
		kit:cyl(m, `Table{i}Post`, x, 1.15, d, 2.3, 0.35, "Y", Style.BRASS, "Metal")
		kit:cyl(m, `Table{i}Foot`, x, 0.05, d, 0.1, 1.2, "Y", Style.BRASS, "Metal", GHOST)
		kit:cyl(m, `Table{i}Candle`, x, 2.7, d, 0.4, 0.3, "Y", Style.AMBER, "Neon", GHOST)
		for _, s in { -1, 1 } do
			local cx = x + s * 2.6
			kit:box(m, `Chair{i}{s}Seat`, cx - 1.1, cx + 1.1, 0, 1.5, d - 1.1, d + 1.1, Style.TAN, "Leather")
			kit:box(m, `Chair{i}{s}Back`, cx + s * 0.5, cx + s * 1.1, 1.5, 3.3, d - 1.1, d + 1.1, Style.TAN, "Leather")
			for _, a in { -1, 1 } do
				kit:box(
					m,
					`Chair{i}{s}Arm{a}`,
					cx - 1.1,
					cx + 1.1,
					1.5,
					2.2,
					d + a * 0.75,
					d + a * 1.15,
					Style.TAN,
					"Leather"
				)
			end
		end
	end
end

local function stage(kit: Kit.Kit, m: any)
	local S = Style.STAGE
	local IX, IB = Style.INNER_X - 0.25, Style.INNER_BACK - 0.25
	kit:box(m, "Stage", S.x0 + 0.25, S.x1, 0, S.top, S.d0, IB, Style.WALNUT, "WoodPlanks")
	kit:box(
		m,
		"StageNosingFront",
		S.x0 + 0.25,
		S.x1 + 0.12,
		S.top - 0.2,
		S.top,
		S.d0 - 0.12,
		S.d0,
		Style.BRASS,
		"Metal",
		GHOST
	)
	kit:box(m, "StageNosingSide", S.x1, S.x1 + 0.12, S.top - 0.2, S.top, S.d0, IB, Style.BRASS, "Metal", GHOST)
	kit:box(m, "StageStep", -20, -16, 0, S.top / 2, S.d0 - 1, S.d0, Style.WALNUT, "Wood")
	kit:box(m, "DrapeBack", -IX, S.x1, S.top, Style.CROWN, IB - 0.45, IB, Style.VELVET, "Fabric", FLAT)
	kit:box(m, "DrapeSide", -IX, -IX + 0.45, S.top, Style.CROWN, S.d0, IB - 0.45, Style.VELVET, "Fabric", FLAT)
	-- a velvet valance with a gold fringe along the stage's open sides (the spots shine down between them)
	kit:box(
		m,
		"Valance",
		-IX,
		S.x1 + 0.3,
		Style.CROWN - 1.2,
		Style.CROWN,
		S.d0 - 0.3,
		S.d0 + 0.3,
		Style.VELVET,
		"Fabric",
		GHOST
	)
	kit:box(
		m,
		"ValanceSide",
		S.x1 - 0.3,
		S.x1 + 0.3,
		Style.CROWN - 1.2,
		Style.CROWN,
		S.d0 + 0.3,
		IB,
		Style.VELVET,
		"Fabric",
		GHOST
	)
	kit:box(
		m,
		"Fringe",
		-IX,
		S.x1 + 0.35,
		Style.CROWN - 1.4,
		Style.CROWN - 1.2,
		S.d0 - 0.35,
		S.d0 - 0.25,
		Style.GOLD,
		"Fabric",
		GHOST
	)
	kit:box(
		m,
		"FringeSide",
		S.x1 + 0.25,
		S.x1 + 0.35,
		Style.CROWN - 1.4,
		Style.CROWN - 1.2,
		S.d0 - 0.25,
		IB,
		Style.GOLD,
		"Fabric",
		GHOST
	)

	-- the grand piano: a black case rounded at the tail, its lid propped open, ivory keys, three legs, a bench
	local px, pd, y = Style.PIANO[1], Style.PIANO[2], S.top
	local CFrame = kit.roblox.CFrame
	local BLACK = { collide = true, reflectance = 0.15 }
	kit:box(m, "PianoCase", px - 2, px + 2, y + 0.9, y + 2.1, pd - 2, pd + 1.6, Style.BLACK, "SmoothPlastic", BLACK)
	kit:cyl(m, "PianoTail", px, y + 1.5, pd + 1.6, 1.2, 4, "Y", Style.BLACK, "SmoothPlastic", BLACK)
	kit:at(
		m,
		"PianoLid",
		px - 2 + 2 * math.cos(math.rad(28)),
		y + 2.15 + 2 * math.sin(math.rad(28)),
		pd + 0.6,
		4,
		0.08,
		5.2,
		Style.BLACK,
		"SmoothPlastic",
		{ collide = false, query = false, reflectance = 0.15, rot = CFrame.Angles(0, 0, math.rad(28)) }
	)
	kit:rod(m, "PianoProp", px + 1.4, y + 2.1, pd + 0.6, px + 1.4, y + 3.9, pd + 0.6, 0.08, Style.BLACK, "Metal", GHOST)
	kit:box(m, "PianoKeys", px - 2, px + 2, y + 1.6, y + 1.9, pd - 2.8, pd - 2, Style.IVORY, "SmoothPlastic", GHOST)
	kit:box(m, "PianoFall", px - 2, px + 2, y + 1.9, y + 2.3, pd - 2.1, pd - 1.95, Style.BLACK, "SmoothPlastic", GHOST)
	for i, l in { { px - 1.7, pd - 1.7 }, { px + 1.7, pd - 1.7 }, { px, pd + 2.9 } } do
		kit:cyl(m, `PianoLeg{i}`, l[1], y + 0.45, l[2], 0.9, 0.35, "Y", Style.BLACK, "SmoothPlastic", BLACK)
	end
	kit:box(m, "PianoBench", px - 1.2, px + 1.2, y, y + 1.4, pd - 4.6, pd - 3.6, Style.BLACK, "SmoothPlastic", BLACK)
	kit:box(
		m,
		"PianoBenchTop",
		px - 1.2,
		px + 1.2,
		y + 1.4,
		y + 1.6,
		pd - 4.6,
		pd - 3.6,
		Style.LEATHER,
		"Leather",
		GHOST
	)

	-- the ribbon microphone and the console radio (the jazz plays from the radio)
	kit:cyl(m, "MicFoot", -15.6, y + 0.05, 16, 0.1, 0.9, "Y", Style.BRASS, "Metal", GHOST)
	kit:cyl(m, "MicStand", -15.6, y + 2.3, 16, 4.5, 0.1, "Y", Style.BRASS, "Metal", GHOST)
	kit:box(m, "Mic", -15.85, -15.35, y + 4.5, y + 5.3, 15.85, 16.15, { 200, 200, 204 }, "Metal", GHOST)
	kit:box(m, "Radio", -23.4, -21.8, y, y + 3.2, S.d0 + 0.6, S.d0 + 2.4, Style.WALNUT, "Wood")
	kit:box(
		m,
		"RadioGrille",
		-21.82,
		-21.76,
		y + 1.4,
		y + 2.8,
		S.d0 + 0.9,
		S.d0 + 2.1,
		Style.RUG_BORDER,
		"Fabric",
		GHOST
	)
	kit:box(m, "RadioDial", -21.82, -21.74, y + 0.8, y + 1.1, S.d0 + 1.2, S.d0 + 1.8, Style.AMBER, "Neon", GHOST)
end

local function fireplace(kit: Kit.Kit, m: any)
	local IX, d = Style.INNER_X - 0.25, Style.FIRE_D
	kit:box(m, "Hearth", IX - 2.4, IX, 0, 0.3, d - 3.4, d + 3.4, Style.STONE, "Marble")
	kit:box(m, "Surround", IX - 1.1, IX, 0.3, 6.2, d - 3, d + 3, Style.STONE, "Marble")
	kit:box(m, "Firebox", IX - 1.16, IX - 1.1, 0.3, 3.4, d - 1.4, d + 1.4, Style.BLACK, "Slate", GHOST)
	kit:box(m, "Mantel", IX - 1.6, IX, 6.2, 6.6, d - 3.4, d + 3.4, Style.WALNUT, "Wood")
	for i, o in { -0.5, 0.5 } do
		kit:cyl(m, `Log{i}`, IX - 1.5, 0.5, d + o * 0.6, 0.35, 2.2, "D", Style.DARK_WOOD, "Wood", GHOST)
	end
	kit:box(
		m,
		"FireScreen",
		IX - 1.9,
		IX - 1.8,
		0.3,
		2.9,
		d - 1.6,
		d + 1.6,
		Style.BRASS,
		"Metal",
		{ collide = true, query = false, transparency = 0.6, shadow = false }
	)
	kit:box(m, "PictureFrame", IX - 0.12, IX, 7.4, 11.4, d - 2.4, d + 2.4, Style.GOLD, "Metal", GHOST)
	kit:box(m, "Picture", IX - 0.18, IX - 0.12, 7.7, 11.1, d - 2.1, d + 2.1, { 92, 64, 40 }, "Fabric", GHOST)
	-- two armchairs facing the fire
	for i, cd in { d - 4.2, d + 4.2 } do
		local cx = IX - 5.5
		kit:box(m, `Arm{i}Seat`, cx - 1.1, cx + 1.1, 0, 1.5, cd - 1.1, cd + 1.1, Style.LEATHER, "Leather")
		kit:box(m, `Arm{i}Back`, cx - 1.1, cx - 0.5, 1.5, 3.6, cd - 1.1, cd + 1.1, Style.LEATHER, "Leather")
		for _, a in { -1, 1 } do
			kit:box(
				m,
				`Arm{i}Arm{a}`,
				cx - 1.1,
				cx + 1.1,
				1.5,
				2.2,
				cd + a * 0.75,
				cd + a * 1.15,
				Style.LEATHER,
				"Leather"
			)
		end
	end
end

local function palms(kit: Kit.Kit, m: any)
	local CFrame = kit.roblox.CFrame
	for _, s in { -1, 1 } do
		local x, d = s * 21.8, -24.6
		kit:cyl(m, `Pot{s}`, x, 0.9, d, 1.8, 1.8, "Y", Style.BLACK, "Marble")
		kit:cyl(m, `PotRim{s}`, x, 1.85, d, 0.15, 1.95, "Y", Style.GOLD, "Metal", GHOST)
		kit:cyl(m, `Trunk{s}`, x, 3.6, d, 3.4, 0.35, "Y", { 104, 80, 56 }, "Wood", GHOST)
		for k = 0, 3 do
			local a = k * math.pi / 2 + math.pi / 4
			local lx, ld = x + math.cos(a) * 1.3, d + math.sin(a) * 1.3
			kit:at(m, `Frond{s}{k}`, lx, 5.4, ld, 0.15, 0.7, 3.2, { 62, 98, 52 }, "Grass", {
				collide = false,
				query = false,
				shadow = false,
				rot = CFrame.Angles(0, -a + math.pi / 2, 0) * CFrame.Angles(math.rad(-25), 0, 0),
			})
		end
	end
end

function Interior.build(kit: Kit.Kit, root: any, _venue: any): any
	local m = kit:model(root, "Interior")
	walls(kit, m)
	bar(kit, m)
	backBar(kit, m)
	booths(kit, m)
	clubTables(kit, m)
	stage(kit, m)
	fireplace(kit, m)
	palms(kit, m)
	return m
end

return Interior
