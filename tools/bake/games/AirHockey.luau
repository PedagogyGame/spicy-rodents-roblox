--!strict
-- tools/bake/games/AirHockey: the owner's AER / 01 air hockey table, rebuilt in parts in the bowling alley's
-- games room (along the back wall, beyond the bumper pool), once per station through the bake registry
-- (tools/bake/GameBakes). Every dimension and colour is his Blender source's
-- (docs/reference/air_hockey/build_arena.py: boxes as (centre, size), metres, X across, Y along, Z up; his
-- material colours are linear RGB), and every one goes through Shared/Minigames/AirHockey/Layout, the same
-- module the server and the client place the puck and the mallets with: one metre is the pool tables' 10.8 / 2.54
-- studs, the cabinet below the bed is shortened to this town's table height, and the table lies with Glacier's
-- end to the west.
-- What is built: the midnight ceramic cabinet on its two sleds with the champagne reveal and the aluminium
-- tray; the pale bed with its centre line, centre circle, face-off ring, the two defensive arcs (glacier and
-- ember), service hashes, the A E R logotype and the 01 / 02 team numbers; the dark side and end rails with
-- their titanium tops and cushions; the side LEDs split glacier blue / ember orange; each goal's dark mouth,
-- bridge, lit lintel, rounded posts and puck return; the cooling fins and side badges; the two mallets (base,
-- light seam, crown, stem, cap) and the puck (carbon disc, lit equator, brass crown) as small Models that the
-- game slides about; a score panel on the wall behind, two lamps in the ceiling and a mat at each end where a
-- player stands (the Ember end's is that prompt's own: GamesRoom.AirHockeyEmberEnd). The recessed rail
-- fasteners are there; his 1,500 air jets and the bevels are left to the mesh
-- (docs/reference/air_hockey/AER_AirHockey.glb).
-- Names the game relies on (Layout): GamesRoom.AirHockey.{Puck, MalletGlacier, MalletEmber, ScoreBoard} and the
-- TextLabel "Score" on the board.
-- Interface: { build(kit, parent, station, venue) }; PARTS (how many parts one table is, after a build)

local AlleyLayout = require("../../../src/shared/Attractions/AlleyLayout")
local Layout = require("../../../src/shared/Minigames/AirHockey/Layout")
local Sim = require("../../../src/shared/Minigames/AirHockey/Sim")

local Bake = {}
Bake.PARTS = 0

-- his materials (build_arena.py), as sRGB
local function col(r: number, g: number, b: number): { number }
	return { Layout.srgb(r), Layout.srgb(g), Layout.srgb(b) }
end
local SHELL = col(0.018, 0.033, 0.050) -- 01 midnight ceramic
local BLACK = col(0.008, 0.013, 0.020) -- 02 soft black rubber
local METAL = col(0.29, 0.38, 0.43) -- 03 satin titanium
local ICE = col(0.67, 0.82, 0.85) -- 04 porcelain ice
local CYAN = col(0.015, 0.66, 0.82) -- 05 glacier cyan
local CORAL = col(0.95, 0.12, 0.09) -- 06 ember coral
local LED_CYAN = col(0.015, 0.70, 1) -- 07 cyan light
local LED_CORAL = col(1, 0.10, 0.055) -- 08 coral light
local WHITE = col(0.85, 0.95, 1) -- 09 warm white light
local INK = col(0.075, 0.19, 0.25) -- 10 printed slate
local BRASS = col(0.52, 0.35, 0.16) -- 12 champagne alloy
local PUCK = col(0.021, 0.027, 0.035) -- 13 puck carbon

local SOFT = { collide = false }
-- The printed bed is built up in layers a millimetre apart, the topmost exactly at the playing surface (the
-- puck and the mallets ride two millimetres over it): the bed itself, the defensive arcs, the centre circle, the
-- face-off ring, the lines, then the spot and the lettering.
local LAYER = 0.001
local function layer(i: number): number
	return Layout.BED_Z - (8 - i) * LAYER
end

-- Where an end's player stands: a rubber mat on the floor behind the end rail, edged in the end's colour.
local function mat(kit: any, into: any, side: number)
	local r = Layout.standing(side)
	local led = if side == 0 then LED_CYAN else LED_CORAL
	-- (the lit edge is the mat's own, on the side nearest the table)
	local e0, e1 = r.x0, r.x0 + 0.12
	if side == 0 then
		e0, e1 = r.x1 - 0.12, r.x1
	end
	kit:box(into, "Mat", r.x0, r.x1, 0, 0.03, r.d0 + 0.5, r.d1 - 0.5, { 20, 24, 30 }, "Fabric", SOFT)
	kit:box(into, "MatEdge", e0, e1, 0, 0.035, r.d0 + 0.5, r.d1 - 0.5, led, "Neon", SOFT)
end

function Bake.build(kit: any, parent: any, station: any, _venue: any?)
	if station.joins ~= nil then
		-- the Ember end's prompt: the same table. Its own furniture is the mat its player stands on
		mat(kit, kit:model(parent, Layout.MODEL .. "EmberEnd"), 1)
		return
	end
	local before = kit.count
	local m = kit:model(parent, Layout.MODEL)
	mat(kit, m, 0)
	local K = Layout.SCALE
	local CFrame = kit.roblox.CFrame

	-- one of his boxes: centre (x, y, z) and size (sx, sy, sz) in metres
	local function box(
		into: any,
		name: string,
		x: number,
		y: number,
		z: number,
		sx: number,
		sy: number,
		sz: number,
		color: { number },
		material: string,
		opts: any?
	): any
		local X0, _, D0 = Layout.toLocal(x + sx / 2, y - sy / 2)
		local X1, _, D1 = Layout.toLocal(x - sx / 2, y + sy / 2)
		return kit:box(
			into,
			name,
			X0,
			X1,
			Layout.height(z - sz / 2),
			Layout.height(z + sz / 2),
			D0,
			D1,
			color,
			material,
			opts
		)
	end
	-- one of his upright cylinders: centre, radius, depth
	local function disc(
		into: any,
		name: string,
		x: number,
		y: number,
		z: number,
		r: number,
		depth: number,
		color: { number },
		material: string,
		opts: any?
	): any
		local X, _, D = Layout.toLocal(x, y)
		local y0, y1 = Layout.height(z - depth / 2), Layout.height(z + depth / 2)
		return kit:cyl(into, name, X, (y0 + y1) / 2, D, math.max(y1 - y0, 0.004), 2 * r * K, "Y", color, material, opts)
	end
	-- a ring printed on the bed: a disc of the line's colour (its top at layer i) with a disc of the bed's
	-- colour on it (layer i + 1)
	local function ring(name: string, y: number, i: number, r: number, width: number, color: { number })
		disc(m, name, 0, y, layer(i) - LAYER / 2, r, LAYER, color, "SmoothPlastic", SOFT)
		disc(m, name .. "Fill", 0, y, layer(i + 1) - LAYER / 2, r - width, LAYER, ICE, "SmoothPlastic", SOFT)
	end
	-- a printed line: one of his boxes laid with its top at the lines' layer
	local function line(name: string, x: number, y: number, sx: number, sy: number)
		box(m, name, x, y, layer(7) - LAYER / 2, sx, sy, LAYER, INK, "SmoothPlastic", SOFT)
	end
	-- lettering printed on the bed: a hair-thin clear plate with the words on its top face, read from Glacier's
	-- end (turn = -1) or from Ember's (turn = 1)
	local function print_(
		name: string,
		text: string,
		x: number,
		y: number,
		w: number,
		h: number,
		color: { number },
		turn: number
	)
		local X, Y, D = Layout.toLocal(x, y, layer(8) - LAYER / 2)
		local plate = kit:at(m, name, X, Y, D, w * K, LAYER * K, h * K, ICE, "SmoothPlastic", {
			collide = false,
			transparency = 1,
			shadow = false,
			rot = CFrame.Angles(0, turn * math.pi / 2, 0),
		})
		kit:label(kit:gui(plate, "Top", 120), { Text = text, TextColor = color, Font = "GothamBold" })
	end

	-- A broad sculpted chassis over two architectural sled supports.
	box(m, "Cabinet", 0, 0, 0.731, 1.49, 2.62, 0.254, SHELL, "SmoothPlastic", { reflectance = 0.12 })
	box(m, "ShadowSeam", 0, 0, 0.610, 1.40, 2.50, 0.045, BLACK, "SmoothPlastic", SOFT)
	box(m, "Reveal", 0, 0, 0.846, 1.455, 2.585, 0.018, BRASS, "Metal", SOFT)
	box(m, "Tray", 0, 0, 0.870, 1.39, 2.49, 0.040, METAL, "Metal", SOFT)
	box(m, "Bed", 0, 0, layer(0) - 0.012, 1.24, 2.34, 0.024, ICE, "SmoothPlastic", { reflectance = 0.08 })
	for _, y in { -0.84, 0.84 } do
		for _, x in { -0.50, 0.50 } do
			local X, _, D = Layout.toLocal(x, y)
			local y0, y1 = Layout.height(0.344 - 0.2675), Layout.height(0.344 + 0.2675)
			kit:at(m, "Support", X, (y0 + y1) / 2, D, 0.19 * K, y1 - y0, 0.12 * K, SHELL, "SmoothPlastic", {
				rot = CFrame.Angles(if x < 0 then -0.12 else 0.12, 0, 0),
			})
			box(
				m,
				"SupportCollar",
				x + (if x < 0 then 0.024 else -0.024),
				y,
				0.15,
				0.125,
				0.20,
				0.095,
				METAL,
				"Metal",
				SOFT
			)
		end
		box(m, "Sled", 0, y, 0.080, 1.25, 0.27, 0.12, SHELL, "SmoothPlastic")
		for _, x in { -0.49, 0.49 } do
			box(m, "Foot", x, y, 0.019, 0.23, 0.23, 0.038, BLACK, "SmoothPlastic", SOFT)
			box(
				m,
				"FootAccent",
				x,
				y - 0.138,
				0.079,
				0.18,
				0.007,
				0.017,
				if y < 0 then LED_CYAN else LED_CORAL,
				"Neon",
				SOFT
			)
		end
	end

	-- Rails, inset bumpers and real openings for both goals.
	for _, sx in { -1, 1 } do
		local x = sx * 0.685
		box(m, "SideRail", x, 0, 0.932, 0.13, 2.57, 0.115, SHELL, "SmoothPlastic", { reflectance = 0.12 })
		box(m, "SideRailTop", x, 0, 0.991, 0.105, 2.51, 0.009, METAL, "Metal", SOFT)
		box(m, "SideCushion", sx * 0.628, 0, 0.925, 0.016, 2.34, 0.036, BLACK, "SmoothPlastic", SOFT)
		for _, s in { -1, 1 } do
			box(
				m,
				"SideLed",
				x,
				s * 0.609,
				0.981,
				0.011,
				1.184,
				0.012,
				if s < 0 then LED_CYAN else LED_CORAL,
				"Neon",
				SOFT
			)
		end
		for _, y in { -1.12, -0.93, 0.93, 1.12 } do
			disc(m, "RailFastener", x, y, 0.9965, 0.010, 0.003, BLACK, "SmoothPlastic", SOFT)
		end
		box(m, "UnderLight", sx * 0.739, 0, 0.645, 0.008, 2.34, 0.012, LED_CYAN, "Neon", SOFT)
		for j = 0, 12, 2 do
			box(m, "CoolingFin", sx * 0.746, -0.48 + j * 0.08, 0.749, 0.004, 0.042, 0.065, BLACK, "SmoothPlastic", SOFT)
		end
		-- the side badge: A E R / 0 1 in titanium on the cabinet's flank
		local X, Y, D = Layout.toLocal(sx * 0.7465, 0, 0.775)
		local badge = kit:at(m, "SideBadge", X, Y, D, 0.62 * K, 0.07 * K, 0.004, SHELL, "SmoothPlastic", {
			collide = false,
			transparency = 1,
			shadow = false,
		})
		kit:label(kit:gui(badge, if sx > 0 then "Back" else "Front", 120), {
			Text = "A E R   /   0 1",
			TextColor = METAL,
			Font = "GothamBold",
		})
	end
	for _, s in { -1, 1 } do
		local led = if s < 0 then LED_CYAN else LED_CORAL
		for _, x in { -0.485, 0.485 } do
			box(m, "EndRail", x, s * 1.235, 0.932, 0.53, 0.13, 0.115, SHELL, "SmoothPlastic", { reflectance = 0.12 })
			box(m, "EndRailTop", x, s * 1.235, 0.991, 0.49, 0.105, 0.009, METAL, "Metal", SOFT)
			box(m, "EndLed", x, s * 1.235, 0.981, 0.45, 0.011, 0.012, led, "Neon", SOFT)
			box(m, "EndCushion", x, s * 1.178, 0.925, 0.53, 0.016, 0.036, BLACK, "SmoothPlastic", SOFT)
		end
		-- (the mouth's floor stands just over the printed arc, which must not show in the goal)
		box(m, "GoalMouth", 0, s * 1.219, layer(2.5) - 0.006, 0.432, 0.10, 0.012, BLACK, "SmoothPlastic", SOFT)
		box(m, "GoalBridge", 0, s * 1.247, 0.980, 0.454, 0.09, 0.035, SHELL, "SmoothPlastic", SOFT)
		local lintel = box(m, "GoalLintel", 0, s * 1.199, 0.973, 0.405, 0.007, 0.009, led, "Neon", SOFT)
		kit:light(lintel, "PointLight", { Range = 7, Brightness = 0.7, Color = led, Shadows = false })
		box(m, "GoalReturn", 0, s * 1.312, 0.739, 0.48, 0.012, 0.102, BLACK, "SmoothPlastic", SOFT)
		box(m, "GoalReturnLip", 0, s * 1.326, 0.694, 0.46, 0.035, 0.012, METAL, "Metal", SOFT)
		for _, x in { -Sim.GOAL, Sim.GOAL } do
			disc(m, "GoalPost", x, s * Sim.HALF_LENGTH, 0.925, Sim.POST_RADIUS, 0.055, METAL, "Metal", SOFT)
		end
	end

	-- Inlaid sport graphics. Nothing floats above the mallet/puck contact plane.
	for _, x in { -0.596, 0.596 } do
		line("Touchline", x, 0, 0.003, 2.29)
	end
	line("CentreLine", 0, 0, 1.19, 0.004)
	for _, s in { -1, 1 } do
		-- the defensive circle is cut off by the end rail; the goal's mouth covers the rest
		ring(if s < 0 then "ArcGlacier" else "ArcEmber", s * 1.05, 1, 0.29, 0.004, if s < 0 then CYAN else CORAL)
		for _, x in { -0.46, 0.46 } do
			line("ServiceHash", x, s * 0.76, 0.042, 0.003)
		end
		print_(
			"TeamIndex",
			if s < 0 then "01" else "02",
			-0.49,
			s * 1.02,
			0.11,
			0.075,
			if s < 0 then CYAN else CORAL,
			s
		)
	end
	ring("CentreCircle", 0, 3, 0.205, 0.004, INK)
	ring("FaceoffRing", 0, 5, 0.066, 0.003, INK)
	disc(m, "FaceoffSpot", 0, 0, layer(8) - LAYER / 2, 0.009, LAYER, CYAN, "SmoothPlastic", SOFT)
	print_("Logotype", "A E R", 0, -0.405, 0.30, 0.075, INK, -1)
	print_("FinePrint", "PRECISION AIR SYSTEM   /   01", 0, 0.405, 0.36, 0.018, INK, 1)

	-- The pieces the game slides about: each a Model standing where a match starts it.
	local function mallet(name: string, y: number, color: { number }, led: { number })
		local piece = kit:model(m, name)
		local base = disc(
			piece,
			"Base",
			0,
			y,
			0.915,
			0.064,
			0.030,
			color,
			"SmoothPlastic",
			{ collide = false, reflectance = 0.1 }
		)
		disc(piece, "Seam", 0, y, 0.9305, 0.059, 0.003, led, "Neon", SOFT)
		disc(piece, "Crown", 0, y, 0.934, 0.048, 0.010, SHELL, "SmoothPlastic", SOFT)
		disc(piece, "Stem", 0, y, 0.957, 0.022, 0.049, color, "SmoothPlastic", SOFT)
		disc(piece, "Cap", 0, y, 0.986, 0.030, 0.016, color, "SmoothPlastic", SOFT)
		piece.PrimaryPart = base
	end
	mallet(Layout.MALLETS[0], Layout.HOME_MALLET[0][2], CYAN, LED_CYAN)
	mallet(Layout.MALLETS[1], Layout.HOME_MALLET[1][2], CORAL, LED_CORAL)
	local puck = kit:model(m, Layout.PUCK)
	local body = disc(
		puck,
		"Disc",
		0,
		0,
		0.912,
		Sim.PUCK_RADIUS,
		0.020,
		PUCK,
		"SmoothPlastic",
		{ collide = false, reflectance = 0.15 }
	)
	disc(puck, "Equator", 0, 0, 0.913, Sim.PUCK_RADIUS + 0.0012, 0.004, WHITE, "Neon", SOFT)
	disc(puck, "Crown", 0, 0, 0.9225, 0.025, 0.002, BRASS, "Metal", SOFT)
	puck.PrimaryPart = body

	-- The score, on the wall behind the table for the whole room to read; and two lamps let into the ceiling.
	local c = Layout.CENTRE
	local wallD = AlleyLayout.GAME_ROOM_D1 - 0.06
	local board = kit:box(
		m,
		Layout.SCORE,
		c.x - 3.6,
		c.x + 3.6,
		6.9,
		8.3,
		wallD - 0.14,
		wallD,
		{ 14, 20, 28 },
		"SmoothPlastic",
		SOFT
	)
	kit:label(kit:gui(board, "Back", 60), {
		Name = "Score",
		Text = "AIR HOCKEY  ·  FIRST TO 7",
		TextColor = { 214, 244, 255 },
		Font = "GothamBold",
		Size = { 0.94, 0.7 },
		Pos = { 0.03, 0.15 },
	})
	kit:box(m, "ScoreTrimGlacier", c.x - 3.6, c.x, 6.8, 6.9, wallD - 0.16, wallD, LED_CYAN, "Neon", SOFT)
	kit:box(m, "ScoreTrimEmber", c.x, c.x + 3.6, 6.8, 6.9, wallD - 0.16, wallD, LED_CORAL, "Neon", SOFT)
	for _, dx in { -2.6, 2.6 } do
		local lamp = kit:box(
			m,
			"Lamp",
			c.x + dx - 0.65,
			c.x + dx + 0.65,
			AlleyLayout.CEILING_Y - 0.1,
			AlleyLayout.CEILING_Y,
			c.d - 0.65,
			c.d + 0.65,
			{ 236, 246, 255 },
			"Neon",
			SOFT
		)
		kit:light(
			lamp,
			"SpotLight",
			{ Face = "Bottom", Range = 16, Angle = 80, Brightness = 2.4, Color = { 226, 240, 255 } }
		)
	end
	Bake.PARTS = kit.count - before
end

return Bake
