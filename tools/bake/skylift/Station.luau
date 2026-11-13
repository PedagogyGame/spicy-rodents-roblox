--!strict
-- tools/bake/skylift/Station: the sky lift's base station on Lift Road (venue f4_lift_base, "SKY LIFT"; BATCH2
-- item 36: bullwheel, boarding platform, gate, operator post; "Interiors ... must hold up at eye level").
-- In the venue's frame (X along the station, Y up from floorY, D from the front face D = -15 to the back D = 15).
-- The cabins (Shared/Rides/SkyLift) creep round the bullwheel at X -12, D 2, their floors level with the
-- platforms (floor + 1.5): they sweep X -20.5..25, D -6.5..10.5 and leave through the open +X end.
--   Platforms (Y 1.5): the front one (D -15..-6.4) where people board (anchor board, X -5), the back one
--     (D 10.4..15) where they get out (alight_down), joined round the bullwheel's end by a walkway (X -25..-21.3: the cabins swing 8.9 out round the bullwheel);
--     between them the pit the cabins pass over (floor Y 0). Yellow edge lines. Platform screens: full-height
--     collidable glass along all three pit edges, one OPENING at the board point closed by two sliding leaves
--     ("ScreenDoor1/2": attributes ScreenDoor = "base", Slide = open offset; the server slides them).
--   The front door (X -9..-1) is at platform height; outside, steps down to the ground and the front walk.
--   A glass fence across the front platform (D -10.5) with the self-service gate: "BoardGate" (the pillar that
--     carries the prompt: attributes Gate = "board", Station = "base"), "BoardGateArm" (the swing bar, hinged at
--     its pillar end; CanCollide false: the server decides who passes), and "NextCabinBoard" (a TextLabel
--     "Next" the server or client can write the wait into). The exit is the walkway round the bullwheel end.
--   Bullwheel (a disc just over the grips' reach), hub, gearbox and motor under the roof trusses; guide rails
--     along both strands from the bullwheel to the mouth; the haul rope round the bullwheel and out.
--   Shell: concrete plinth to ground.min - 2, low walls, a glass band, a cream upper band with the lit "SKY LIFT"
--     sign on the front (anchor sign), a shallow gable roof, exposed trusses, pendant lamps (PointLights), benches,
--     planters, a free-ride notice and a line map.
-- Interface: build(kit, parent, venue) -> Model (f4_lift_base); BUDGET

local AlleyLayout = require("../../../src/shared/Attractions/AlleyLayout")
local Common = require("./Common")
local Kit = require("../alley/Kit")
local SkyLift = require("../../../src/shared/Rides/SkyLift")

local Station = {}

Station.BUDGET = 500
Station.OPENING = 4 -- the platform screen's opening at the board point (a cabin's doorway is 3.4)

local PLAT = SkyLift.PLATFORM_HEIGHT -- 1.5
local EAVE, RIDGE = 15, 18
local SILL, HEAD = 4, 11 -- the glass band

function Station.build(kit: Kit.Kit, parent: any, v: any): any
	local roblox = kit.roblox
	local CFrame = roblox.CFrame
	local m = Common.venueModel(kit, parent, v.id, v, Station.BUDGET, "Atomic")
	local shell = kit:folder(m, "Shell")
	local interior = kit:folder(m, "Interior")
	local lift = kit:folder(m, "Lift")
	local props = kit:folder(m, "Props")
	local hw, hd = v.footprint.w / 2, v.footprint.d / 2 -- 25, 15
	local base = v.ground.min - 2 - v.floorY -- plinth bottom (local Y)
	local C, CD = Common.CONCRETE, Common.CONCRETE_DARK

	-- plinth, pit floor and the three platforms
	kit:box(shell, "Plinth", -hw, hw, base, -0.3, -hd, hd, CD, "Concrete")
	local FRONT_EDGE, BACK_EDGE, WEST_EDGE = -6.4, 10.4, -21.3
	kit:box(shell, "PitFloor", WEST_EDGE, hw, -0.3, 0, FRONT_EDGE, BACK_EDGE, { 92, 94, 96 }, "Concrete")
	kit:box(shell, "PlatformFront", -hw, hw, -0.3, PLAT, -hd, FRONT_EDGE, Common.TERRAZZO, "Slate")
	kit:box(shell, "PlatformBack", -hw, hw, -0.3, PLAT, BACK_EDGE, hd, Common.TERRAZZO, "Slate")
	kit:box(shell, "Walkway", -hw, WEST_EDGE, -0.3, PLAT, FRONT_EDGE, BACK_EDGE, Common.TERRAZZO, "Slate")
	local line = { collide = false, query = false, shadow = false }
	kit:box(
		interior,
		"EdgeFront",
		WEST_EDGE,
		hw - 0.4,
		PLAT,
		PLAT + 0.03,
		FRONT_EDGE - 0.5,
		FRONT_EDGE,
		Common.YELLOW,
		"SmoothPlastic",
		line
	)
	kit:box(
		interior,
		"EdgeBack",
		WEST_EDGE,
		hw - 0.4,
		PLAT,
		PLAT + 0.03,
		BACK_EDGE,
		BACK_EDGE + 0.5,
		Common.YELLOW,
		"SmoothPlastic",
		line
	)
	kit:box(
		interior,
		"EdgeWest",
		WEST_EDGE - 0.5,
		WEST_EDGE,
		PLAT,
		PLAT + 0.03,
		FRONT_EDGE - 0.5,
		BACK_EDGE + 0.5,
		Common.YELLOW,
		"SmoothPlastic",
		line
	)

	-- the platform screens (review: a child walked into an open cabin and dropped through its floor into the pit):
	-- collidable glass along all three pit edges, just clear of the cabins' swept volume, full height so nobody
	-- jumps over, with one opening at the board point. Two sliding leaves close it; the server slides them open
	-- only while a cabin stands at that opening (attribute ScreenDoor = station, Slide = the leaf's open offset in
	-- world studs) and seats whoever steps into it.
	local SCREEN_TOP = PLAT + 7.2
	local SF0, SF1 = FRONT_EDGE - 0.6, FRONT_EDGE - 0.45 -- the front screen's faces (the swept volume ends at -6.5)
	local SB0, SB1 = BACK_EDGE + 0.45, BACK_EDGE + 0.6
	local SW0, SW1 = WEST_EDGE - 0.15, WEST_EDGE - 0.03
	local glassScreen = { transparency = 0.7, reflectance = 0.15 }
	local boardAnchor = nil
	for _, a in v.anchors do
		if a.id == "board" then
			boardAnchor = a
		end
	end
	local ox = if boardAnchor then boardAnchor.at[1] else -5
	local OPEN = Station.OPENING
	local o0, o1 = ox - OPEN / 2, ox + OPEN / 2
	local screenEnd = hw - 0.5 -- the mouth pier
	for _, seg in { { SW0, o0 - 0.15 }, { o1 + 0.15, screenEnd } } do
		kit:box(interior, "ScreenFront", seg[1], seg[2], PLAT, SCREEN_TOP, SF0, SF1, Common.GLASS, "Glass", glassScreen)
	end
	kit:box(interior, "ScreenBack", SW0, screenEnd, PLAT, SCREEN_TOP, SB0, SB1, Common.GLASS, "Glass", glassScreen)
	kit:box(interior, "ScreenWest", SW0, SW1, PLAT, SCREEN_TOP, SF0, SB1, Common.GLASS, "Glass", glassScreen)
	for _, r in
		{
			{ SW0, screenEnd, SF0 - 0.05, SF1 + 0.05 },
			{ SW0, screenEnd, SB0 - 0.05, SB1 + 0.05 },
			{ SW0 - 0.05, SW1 + 0.05, SF0, SB1 },
		}
	do
		kit:box(interior, "ScreenHead", r[1], r[2], SCREEN_TOP, SCREEN_TOP + 0.3, r[3], r[4], Common.FRAME, "Metal")
	end
	for _, x in { o0 - 0.15, o1 } do
		kit:box(interior, "ScreenJamb", x, x + 0.15, PLAT, SCREEN_TOP, SF0 - 0.08, SF1 + 0.02, Common.RED, "Metal")
	end
	-- the two leaves, on the platform side of the screen line, sliding apart along it
	for i, l in { { o0, ox, -1 }, { ox, o1, 1 } } do
		local leaf = kit:box(
			interior,
			`ScreenDoor{i}`,
			l[1],
			l[2],
			PLAT,
			SCREEN_TOP - 0.1,
			SF0 - 0.17,
			SF0 - 0.05,
			Common.GLASS,
			"Glass",
			{ transparency = 0.5, reflectance = 0.15 }
		)
		local open = (kit:cf(l[3] * (OPEN / 2 - 0.1), 0, 0).Position - kit:cf(0, 0, 0).Position)
		leaf:SetAttribute("ScreenDoor", "base")
		leaf:SetAttribute("Slide", open)
	end

	-- walls: low wall, glass band, upper band; the front has the door, the +X end the cabins' mouth
	local T = 0.5
	local glass = { transparency = 0.6, reflectance = 0.1 }
	local function wallRun(name: string, x0: number, x1: number, d0: number, d1: number, mullions: number)
		kit:box(shell, name .. "Low", x0, x1, PLAT, SILL, d0, d1, Common.CREAM, "SmoothPlastic")
		kit:box(shell, name .. "Glass", x0, x1, SILL, HEAD, d0 + 0.15, d1 - 0.15, Common.GLASS, "Glass", glass)
		for i = 1, mullions do
			local x = x0 + (x1 - x0) * i / (mullions + 1)
			kit:box(
				shell,
				name .. "Mullion",
				x - 0.15,
				x + 0.15,
				SILL,
				HEAD,
				d0 - 0.02,
				d1 + 0.02,
				Common.FRAME,
				"Metal"
			)
		end
		kit:box(shell, name .. "Sill", x0, x1, SILL - 0.1, SILL + 0.15, d0 - 0.15, d1 + 0.15, Common.FRAME, "Metal")
	end
	local DOOR0, DOOR1, DOOR_TOP = -9, -1, 8.5
	-- front (D -15): low wall and glass either side of the door, the upper band over all
	wallRun("FrontW", -hw, DOOR0, -hd, -hd + T, 3)
	wallRun("FrontE", DOOR1, hw - T, -hd, -hd + T, 5)
	kit:box(shell, "FrontUpper", -hw, hw, HEAD, EAVE, -hd, -hd + T, Common.CREAM, "SmoothPlastic")
	kit:box(shell, "DoorHeader", DOOR0, DOOR1, DOOR_TOP, HEAD, -hd, -hd + T, Common.RED, "SmoothPlastic")
	kit:box(shell, "DoorJambW", DOOR0 - 0.35, DOOR0, PLAT, DOOR_TOP, -hd - 0.1, -hd + T + 0.1, Common.FRAME, "Metal")
	kit:box(shell, "DoorJambE", DOOR1, DOOR1 + 0.35, PLAT, DOOR_TOP, -hd - 0.1, -hd + T + 0.1, Common.FRAME, "Metal")
	-- back (D 15)
	wallRun("Back", -hw, hw - T, hd - T, hd, 8)
	kit:box(shell, "BackUpper", -hw, hw, HEAD, EAVE, hd - T, hd, Common.CREAM, "SmoothPlastic")
	-- west end (X -25), with a round window over the walkway
	kit:box(shell, "WestLow", -hw, -hw + T, PLAT, SILL, -hd + T, hd - T, Common.CREAM, "SmoothPlastic")
	kit:box(shell, "WestUpper", -hw, -hw + T, SILL, EAVE, -hd + T, -3, Common.CREAM, "SmoothPlastic")
	kit:box(shell, "WestUpper", -hw, -hw + T, SILL, EAVE, 7, hd - T, Common.CREAM, "SmoothPlastic")
	kit:box(shell, "WestUpper", -hw, -hw + T, SILL, 6, -3, 7, Common.CREAM, "SmoothPlastic")
	kit:box(shell, "WestUpper", -hw, -hw + T, 11, EAVE, -3, 7, Common.CREAM, "SmoothPlastic")
	kit:box(shell, "WestWindow", -hw + 0.1, -hw + 0.4, 6, 11, -3, 7, Common.GLASS, "Glass", glass)
	-- east end (X 25): the mouth (open over the pit) between two pier walls, a lintel over it
	kit:box(shell, "MouthPierFront", hw - T, hw, PLAT, EAVE, -hd + T, FRONT_EDGE, Common.CREAM, "SmoothPlastic")
	kit:box(shell, "MouthPierBack", hw - T, hw, PLAT, EAVE, BACK_EDGE, hd - T, Common.CREAM, "SmoothPlastic")
	kit:box(shell, "MouthLintel", hw - T, hw, 14.2, EAVE, FRONT_EDGE, BACK_EDGE, Common.RED, "SmoothPlastic")
	-- the mouth's sill: as high as the passing cabins' undersides allow (they clear it by 0.3), so nobody strolls
	-- into the pit from outside
	kit:box(shell, "MouthSill", hw - T, hw + 0.2, -0.3, PLAT - 0.5 - 0.3, FRONT_EDGE, BACK_EDGE, CD, "Concrete")
	-- the red trim band at the eaves all round
	kit:box(shell, "EaveTrimFront", -hw - 0.1, hw + 0.1, EAVE - 0.7, EAVE, -hd - 0.12, -hd, Common.RED, "SmoothPlastic")
	kit:box(shell, "EaveTrimBack", -hw - 0.1, hw + 0.1, EAVE - 0.7, EAVE, hd, hd + 0.12, Common.RED, "SmoothPlastic")

	-- the roof: a shallow gable along X, overhanging, with gable-end wedges and a ridge cap
	local over = 0.8
	local rise = RIDGE - EAVE
	local run = hd + over
	local slope = math.atan2(rise, run)
	local slab = math.sqrt(run * run + rise * rise)
	for _, side in { -1, 1 } do
		-- side -1: the front slope (D < 0)
		kit:at(
			shell,
			"Roof",
			0,
			EAVE + rise / 2 + 0.2,
			side * run / 2,
			2 * hw + 2 * over,
			0.4,
			slab,
			{ 84, 88, 92 },
			"Slate",
			{
				rot = CFrame.Angles(-side * slope, 0, 0),
			}
		)
	end
	kit:box(shell, "RidgeCap", -hw - over, hw + over, RIDGE + 0.15, RIDGE + 0.55, -0.5, 0.5, Common.RED_DARK, "Metal")
	for _, sx in { -1, 1 } do
		for _, side in { -1, 1 } do
			-- gable end: a wedge per half, slope rising toward the ridge
			kit:wedge(
				shell,
				"Gable",
				sx * (hw - T / 2),
				EAVE + rise / 2,
				side * hd / 2,
				T,
				rise,
				hd,
				Common.CREAM,
				"SmoothPlastic",
				{
					rot = CFrame.Angles(0, if side < 0 then math.pi else 0, 0),
				}
			)
		end
	end
	-- ceiling: the trusses (they also carry the guide rails and the lamps)
	local TRUSS_Y0, TRUSS_Y1 = 14.3, 14.9
	local function roofUnder(d: number): number
		return EAVE + (run - math.abs(d)) * rise / run - 0.1
	end
	local trussX = { -18, -2, 14 }
	for _, x in trussX do
		kit:box(shell, "Truss", x - 0.3, x + 0.3, TRUSS_Y0, TRUSS_Y1, -hd + T, hd - T, Common.STEEL_DARK, "Metal")
		kit:box(shell, "TrussKing", x - 0.2, x + 0.2, TRUSS_Y1, RIDGE - 0.3, -0.2, 0.2, Common.STEEL_DARK, "Metal")
	end

	-- the bullwheel: a disc whose underside clears the grips (they reach GRIP_ABOVE over the rope), the hub,
	-- the gearbox and motor above it
	local st = SkyLift.stations().base
	local wheelX, _, wheelD = AlleyLayout.toLocal(kit.place, st.wheel.x, 0, st.wheel.z)
	local cableY = st.wheel.y - v.floorY -- 12
	local discY0 = cableY + SkyLift.GRIP_ABOVE + 0.35
	kit:cyl(
		lift,
		"Bullwheel",
		wheelX,
		discY0 + 0.3,
		wheelD,
		0.6,
		2 * SkyLift.STRAND + 0.8,
		"Y",
		Common.STEEL_DARK,
		"Metal"
	)
	kit:cyl(
		lift,
		"BullwheelRim",
		wheelX,
		discY0 + 0.65,
		wheelD,
		0.1,
		2 * SkyLift.STRAND + 0.4,
		"Y",
		Common.RED,
		"Metal",
		{
			collide = false,
			query = false,
		}
	)
	local discTop = discY0 + 0.6
	kit:cyl(lift, "Hub", wheelX, (discTop + TRUSS_Y0) / 2, wheelD, TRUSS_Y0 - discTop, 2.2, "Y", Common.STEEL, "Metal")
	kit:box(
		lift,
		"GearboxBeam",
		wheelX - 0.3,
		wheelX + 0.3,
		TRUSS_Y0,
		TRUSS_Y1,
		-hd + T,
		hd - T,
		Common.STEEL_DARK,
		"Metal"
	)
	kit:box(
		lift,
		"Gearbox",
		wheelX - 2.2,
		wheelX + 2.2,
		TRUSS_Y1,
		TRUSS_Y1 + 1.7,
		wheelD - 1.6,
		wheelD + 1.6,
		Common.RED_DARK,
		"Metal"
	)
	kit:box(
		lift,
		"Motor",
		wheelX + 2.2,
		wheelX + 5.4,
		TRUSS_Y1 + 0.1,
		TRUSS_Y1 + 1.5,
		wheelD - 0.8,
		wheelD + 0.8,
		Common.STEEL_DARK,
		"Metal"
	)
	kit:cyl(lift, "MotorFins", wheelX + 3.8, TRUSS_Y1 + 0.8, wheelD, 2.6, 1.8, "X", Common.STEEL, "Metal")
	-- guide rails along both strands from the bullwheel to the mouth, hung from the trusses
	local railY0 = cableY + SkyLift.GRIP_ABOVE + 0.35
	for _, strandD in { wheelD - SkyLift.STRAND, wheelD + SkyLift.STRAND } do
		kit:box(
			lift,
			"GuideRail",
			wheelX + SkyLift.STRAND + 0.8,
			hw - 0.6,
			railY0,
			railY0 + 0.5,
			strandD - 0.3,
			strandD + 0.3,
			Common.STEEL_DARK,
			"Metal"
		)
		for _, x in trussX do
			if x > wheelX + 1 then
				kit:box(
					lift,
					"RailHanger",
					x - 0.12,
					x + 0.12,
					railY0 + 0.5,
					TRUSS_Y0,
					strandD - 0.12,
					strandD + 0.12,
					Common.STEEL,
					"Metal"
				)
			end
		end
	end
	-- the haul rope inside the station (round the bullwheel and along the runs)
	local kit0 = Common.worldKit(roblox)
	for i, seg in Common.ropeSegments().base do
		Common.rodW(
			kit0,
			lift,
			`Rope{i}`,
			seg[1],
			seg[2],
			0.34,
			Common.ROPE,
			"Metal",
			{ collide = false, query = false }
		)
	end

	-- the gate line across the front platform: a glass fence with the self-service gate at the board point
	local GATE_D = -10.5
	local board = nil
	for _, a in v.anchors do
		if a.id == "board" then
			board = a
		end
	end
	local gx = if board then board.at[1] else -5
	local g0, g1 = gx - 2.5, gx + 2.5
	local fence = { transparency = 0.55 }
	for _, seg in { { WEST_EDGE, g0 }, { g1, hw - T } } do
		kit:box(
			interior,
			"Fence",
			seg[1],
			seg[2],
			PLAT + 0.2,
			PLAT + 3.4,
			GATE_D - 0.06,
			GATE_D + 0.06,
			Common.GLASS,
			"Glass",
			fence
		)
		kit:box(
			interior,
			"FenceRail",
			seg[1],
			seg[2],
			PLAT + 3.4,
			PLAT + 3.6,
			GATE_D - 0.12,
			GATE_D + 0.12,
			Common.FRAME,
			"Metal"
		)
		kit:box(
			interior,
			"FenceFoot",
			seg[1],
			seg[2],
			PLAT,
			PLAT + 0.2,
			GATE_D - 0.12,
			GATE_D + 0.12,
			Common.FRAME,
			"Metal"
		)
	end
	local pillar = kit:box(
		interior,
		"BoardGate",
		g1 - 0.6,
		g1,
		PLAT,
		PLAT + 3.9,
		GATE_D - 0.4,
		GATE_D + 0.4,
		Common.RED,
		"SmoothPlastic"
	)
	pillar:SetAttribute("Gate", "board")
	pillar:SetAttribute("Station", "base")
	local pg = kit:gui(pillar, "Back", 40)
	kit:label(pg, { Text = "SKY LIFT\nPRESS E", TextColor = Common.CREAM, Size = { 0.9, 0.3 }, Pos = { 0.05, 0.08 } })
	kit:box(
		interior,
		"BoardGatePost",
		g0,
		g0 + 0.6,
		PLAT,
		PLAT + 3.9,
		GATE_D - 0.4,
		GATE_D + 0.4,
		Common.RED,
		"SmoothPlastic"
	)
	local arm = kit:box(
		interior,
		"BoardGateArm",
		g0 + 0.6,
		g1 - 0.6,
		PLAT + 2.6,
		PLAT + 2.85,
		GATE_D - 0.08,
		GATE_D + 0.08,
		Common.YELLOW,
		"Metal",
		{
			collide = false,
			query = false,
		}
	)
	arm:SetAttribute("HingeX", g1 - 0.6)
	-- the next-cabin board over the gate
	local nb = kit:box(
		interior,
		"NextCabinBoard",
		g0,
		g1,
		PLAT + 4.6,
		PLAT + 6.0,
		GATE_D - 0.1,
		GATE_D + 0.1,
		Common.FRAME,
		"SmoothPlastic",
		{
			collide = false,
			query = false,
		}
	)
	kit:box(
		interior,
		"BoardHangerW",
		g0 + 0.4,
		g0 + 0.55,
		PLAT + 6.0,
		roofUnder(GATE_D),
		GATE_D - 0.05,
		GATE_D + 0.05,
		Common.STEEL,
		"Metal",
		{
			collide = false,
			query = false,
		}
	)
	kit:box(
		interior,
		"BoardHangerE",
		g1 - 0.55,
		g1 - 0.4,
		PLAT + 6.0,
		roofUnder(GATE_D),
		GATE_D - 0.05,
		GATE_D + 0.05,
		Common.STEEL,
		"Metal",
		{
			collide = false,
			query = false,
		}
	)
	for _, face in { "Front", "Back" } do
		local ng = kit:gui(nb, face, 40)
		ng.LightInfluence = 0
		local t = kit:label(ng, { Text = "NEXT CABIN", TextColor = { 255, 196, 90 }, Font = "Code" })
		t.Name = "Next"
	end
	-- the operator's desk (self-service: no staff) at the operator post
	kit:box(
		interior,
		"OperatorDesk",
		-14,
		-10,
		PLAT,
		PLAT + 2.6,
		GATE_D + 0.15,
		GATE_D + 1.3,
		Common.WOOD_DARK,
		"WoodPlanks"
	)
	kit:box(
		interior,
		"OperatorPanel",
		-13.6,
		-10.4,
		PLAT + 2.6,
		PLAT + 2.75,
		GATE_D + 0.25,
		GATE_D + 1.2,
		{ 30, 34, 38 },
		"SmoothPlastic",
		{
			collide = false,
			query = false,
		}
	)
	kit:box(
		interior,
		"OperatorLamp",
		-11.2,
		-10.8,
		PLAT + 2.75,
		PLAT + 2.95,
		GATE_D + 0.5,
		GATE_D + 0.9,
		{ 90, 220, 120 },
		"Neon",
		{
			collide = false,
			query = false,
			shadow = false,
		}
	)
	-- notices on the fence's lobby side: free rides, and the line map
	local notice = kit:box(
		interior,
		"FreeNotice",
		g1 + 1.5,
		g1 + 5.5,
		PLAT + 0.9,
		PLAT + 3.1,
		GATE_D - 0.22,
		GATE_D - 0.12,
		Common.CREAM,
		"SmoothPlastic",
		{
			collide = false,
			query = false,
		}
	)
	local ngui = kit:gui(notice, "Back", 40)
	kit:label(ngui, {
		Text = "FREE RIDES\nBoth ways, all day\nUp to The Lookout in about a minute",
		TextColor = Common.RED_DARK,
		Font = "GothamBold",
		Size = { 0.9, 0.8 },
		Pos = { 0.05, 0.1 },
	})
	local map = kit:box(
		interior,
		"LineMap",
		g1 + 6.5,
		g1 + 12.5,
		PLAT + 0.9,
		PLAT + 3.1,
		GATE_D - 0.22,
		GATE_D - 0.12,
		{ 226, 232, 222 },
		"SmoothPlastic",
		{
			collide = false,
			query = false,
		}
	)
	local mgui = kit:gui(map, "Back", 40)
	kit:label(mgui, {
		Text = "LIFT ROAD  ·  9 TOWERS  ·  THE LOOKOUT",
		TextColor = Common.FRAME,
		Font = "GothamBold",
		Size = { 0.9, 0.2 },
		Pos = { 0.05, 0.05 },
	})
	kit:label(mgui, { Text = "", Bg = Common.RED, Size = { 0.8, 0.04 }, Pos = { 0.1, 0.55 } })
	-- the exit sign over the walkway
	local exit = kit:box(
		interior,
		"ExitSign",
		-hw + 0.6,
		WEST_EDGE - 0.3,
		9,
		10.2,
		GATE_D - 0.1,
		GATE_D + 0.1,
		{ 30, 110, 60 },
		"SmoothPlastic",
		{
			collide = false,
			query = false,
		}
	)
	local eg = kit:gui(exit, "Front", 40)
	kit:label(eg, { Text = "EXIT", TextColor = { 240, 255, 240 } })
	for _, x in { -hw + 1.2, WEST_EDGE - 0.9 } do
		kit:box(
			interior,
			"ExitHanger",
			x,
			x + 0.15,
			10.2,
			roofUnder(GATE_D),
			GATE_D - 0.05,
			GATE_D + 0.05,
			Common.STEEL,
			"Metal",
			{
				collide = false,
				query = false,
			}
		)
	end
	-- benches: in the lobby against the front wall, and on the back platform by the wall
	local function bench(name: string, x0: number, x1: number, d0: number, d1: number, backD: number)
		kit:box(props, name .. "Seat", x0, x1, PLAT + 1.25, PLAT + 1.5, d0, d1, Common.WOOD, "WoodPlanks")
		kit:box(
			props,
			name .. "Back",
			x0,
			x1,
			PLAT + 1.5,
			PLAT + 3.2,
			backD - 0.12,
			backD + 0.12,
			Common.WOOD,
			"WoodPlanks"
		)
		for _, x in { x0 + 0.4, x1 - 0.6 } do
			kit:box(
				props,
				name .. "Leg",
				x,
				x + 0.2,
				PLAT,
				PLAT + 1.25,
				math.min(d0, d1) + 0.1,
				math.max(d0, d1) - 0.1,
				Common.FRAME,
				"Metal"
			)
		end
	end
	bench("BenchLobbyW", -22, -16.5, -14.4, -12.9, -14.35)
	bench("BenchLobbyE", 8, 13.5, -14.4, -12.9, -14.35)
	bench("BenchBack", -16, -10.5, 13.4, 14.4, 14.35)
	-- pendant lamps over both platforms, from the trusses
	local lights = kit:folder(m, "Lights")
	for _, x in trussX do
		for _, d in { -12.5, 12.7 } do
			kit:box(lights, "LampCord", x - 0.05, x + 0.05, 11.6, TRUSS_Y0, d - 0.05, d + 0.05, Common.FRAME, "Metal", {
				collide = false,
				query = false,
				shadow = false,
			})
			kit:cyl(lights, "LampShade", x, 11.35, d, 0.5, 1.6, "Y", Common.RED_DARK, "Metal", {
				collide = false,
				query = false,
			})
			local bulb = kit:cyl(lights, "Lamp", x, 11.05, d, 0.12, 1.2, "Y", Common.WARM_LIGHT, "Neon", {
				collide = false,
				query = false,
				shadow = false,
			})
			kit:light(bulb, "PointLight", { Range = 18, Brightness = 1.3, Color = Common.WARM_LIGHT, Shadows = false })
		end
	end

	-- outside: the lit sign over the door (anchor sign), the steps down to the walk, planters
	local signY = 10
	for _, a in v.anchors do
		if a.id == "sign" then
			signY = a.at[2]
		end
	end
	local sign = kit:box(
		shell,
		"Sign",
		DOOR0 - 3,
		DOOR1 + 3,
		signY - 1.2,
		signY + 1.2,
		-hd - 0.35,
		-hd - 0.05,
		Common.RED,
		"SmoothPlastic",
		{
			collide = false,
		}
	)
	local sg = kit:gui(sign, "Back", 40)
	sg.LightInfluence = 0
	sg.Brightness = 2.5
	kit:label(
		sg,
		{ Text = "SKY LIFT", TextColor = Common.CREAM, Font = "GothamBlack", Size = { 0.9, 0.8 }, Pos = { 0.05, 0.1 } }
	)
	kit:light(
		sign,
		"SurfaceLight",
		{ Face = "Back", Range = 10, Brightness = 1.4, Angle = 70, Color = { 255, 220, 200 } }
	)
	-- steps from the door (platform height) down to the ground in front, with cheek walls
	local sx0, sx1 = DOOR0 - 0.5, DOOR1 + 0.5
	local gMin = math.huge
	for _, x in { sx0, (sx0 + sx1) / 2, sx1 } do
		for _, d in { -hd - 1, -hd - 4 } do
			local w = kit:cf(x, 0, d).Position
			gMin = math.min(gMin, Common.ground(w.X, w.Z) - v.floorY)
		end
	end
	-- risers of at most 0.5: `steps` of them, so steps - 1 treads between the door sill and the ground; each
	-- step is a block from the plinth's bottom up to its tread
	local steps = math.max(2, math.ceil((PLAT - gMin) / 0.5 - 0.01))
	local riser = (PLAT - gMin) / steps
	for i = 1, steps - 1 do
		kit:box(shell, "Step", sx0, sx1, base, PLAT - riser * i, -hd - i * 1.1, -hd - (i - 1) * 1.1, C, "Concrete")
	end
	for _, x in { sx0 - 0.6, sx1 } do
		kit:box(shell, "StepCheek", x, x + 0.6, base, PLAT + 0.4, -hd - steps * 1.1, -hd, CD, "Concrete")
	end
	m:SetAttribute("FrontSteps", steps)
	m:SetAttribute("StepsFootD", -hd - steps * 1.1)
	for _, x in { sx0 - 4.2, sx1 + 1.2 } do
		kit:box(
			props,
			"Planter",
			x,
			x + 3,
			PLAT - 0.6,
			PLAT + 0.6,
			-hd - 2.6,
			-hd - 0.4,
			Common.CONCRETE_DARK,
			"Concrete"
		)
		kit:ball(props, "Shrub", x + 1.5, PLAT + 1.2, -hd - 1.5, 2.4, Common.SHRUB, "Grass", { collide = false })
	end

	Common.anchors(kit, m, v, Common.FAMILY)
	return m
end

return Station
