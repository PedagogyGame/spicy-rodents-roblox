--!strict
-- tools/bake/skylift/Summit: the sky lift's summit station inside the Lookout's lift hall (venue f3_hilltop,
-- local X -50..-20, D -25..25; the hall's floor, canopy and walls are the Lookout's own, tools/bake/lookout).
-- Model f4_lift_summit (Atomic, attributes VenueId = "f3_hilltop", Family = "F4"), in the Lookout's frame:
--   the down-boarding platform (X -50..-43.6, anchor board_down) and the arrival platform (X -26.4..-20, anchor
--     alight), both at floor + 1.5 and joined behind the bullwheel by a walkway (D 20.6..25); the arrival
--     platform's front end steps down to the hall floor by the terrace (D -25..-22), the only way on or off;
--   the self-service gate across the boarding platform (BoardGate: Gate = "board", Station = "summit";
--     BoardGateArm; NextCabinBoard with a TextLabel "Next"), "DOWN TO TOWN" and "WELCOME TO THE LOOKOUT" signs;
--   the bullwheel (its underside clear of the grips), hub and gearbox on two steel gantries that stand on the
--     platforms (the hall canopy carries nothing of the lift), guide rails along both strands, the haul rope
--     round the bullwheel and out to the lip, pendant lamps, rails on the open side, yellow edge lines;
--   Anchors: alight, board_down, cable_in (the F4 anchors of f3_hilltop).
-- Everything stays below Y 16.4 (local) so the Lookout's canopy can close over it.
-- Interface: build(kit, parent, venue) -> Model; BUDGET; TOP

local AlleyLayout = require("../../../src/shared/Attractions/AlleyLayout")
local Common = require("./Common")
local Kit = require("../alley/Kit")
local SkyLift = require("../../../src/shared/Rides/SkyLift")

local Summit = {}

Summit.BUDGET = 120
Summit.TOP = 16.4

local PLAT = SkyLift.PLATFORM_HEIGHT

function Summit.build(kit: Kit.Kit, parent: any, v: any): any
	local roblox = kit.roblox
	local m = kit:model(parent, "f4_lift_summit")
	m.ModelStreamingMode = roblox.Enum.ModelStreamingMode.Atomic
	m:SetAttribute("VenueId", v.id)
	m:SetAttribute("Family", Common.FAMILY)
	m:SetAttribute("Type", "skylift_summit")
	m:SetAttribute("FloorY", v.floorY)
	m:SetAttribute("Yaw", v.yaw)
	m:SetAttribute("PartBudget", Summit.BUDGET)
	local st = SkyLift.stations().summit
	local wx, _, wd = AlleyLayout.toLocal(kit.place, st.wheel.x, 0, st.wheel.z) -- (-35, 12)
	local cableY = st.wheel.y - v.floorY -- 12
	local S = SkyLift.STRAND
	local downX, upX = wx - S, wx + S -- the boarding (down) strand and the arriving (up) strand
	local X0, X1 = -50, -20 -- the hall
	local FRONT, BACK = -25, 25
	local BOARD_EDGE, ALIGHT_EDGE, WALK_EDGE = -43.6, -26.4, 21.3
	local PLAT_FRONT = -22
	local deck = Common.TERRAZZO
	local shell = kit:folder(m, "Platforms")
	local liftF = kit:folder(m, "Lift")
	local fit = kit:folder(m, "Fittings")

	-- platforms, walkway, the steps down at the arrival platform's front end
	kit:box(shell, "PlatformBoard", X0, BOARD_EDGE, 0, PLAT, PLAT_FRONT, WALK_EDGE, deck, "Slate")
	kit:box(shell, "PlatformAlight", ALIGHT_EDGE, X1, 0, PLAT, PLAT_FRONT, WALK_EDGE, deck, "Slate")
	kit:box(shell, "Walkway", X0, X1, 0, PLAT, WALK_EDGE, BACK, deck, "Slate")
	kit:box(shell, "Step", ALIGHT_EDGE, X1, 0, PLAT - 0.5, PLAT_FRONT - 1.1, PLAT_FRONT, deck, "Slate")
	kit:box(shell, "Step", ALIGHT_EDGE, X1, 0, PLAT - 1.0, PLAT_FRONT - 2.2, PLAT_FRONT - 1.1, deck, "Slate")
	local line = { collide = false, query = false, shadow = false }
	kit:box(
		fit,
		"EdgeBoard",
		BOARD_EDGE - 0.5,
		BOARD_EDGE,
		PLAT,
		PLAT + 0.03,
		PLAT_FRONT,
		WALK_EDGE,
		Common.YELLOW,
		"SmoothPlastic",
		line
	)
	kit:box(
		fit,
		"EdgeAlight",
		ALIGHT_EDGE,
		ALIGHT_EDGE + 0.5,
		PLAT,
		PLAT + 0.03,
		PLAT_FRONT,
		WALK_EDGE,
		Common.YELLOW,
		"SmoothPlastic",
		line
	)
	kit:box(
		fit,
		"EdgeWalk",
		BOARD_EDGE,
		ALIGHT_EDGE,
		PLAT,
		PLAT + 0.03,
		WALK_EDGE,
		WALK_EDGE + 0.5,
		Common.YELLOW,
		"SmoothPlastic",
		line
	)

	-- rails along the hall's open side and across the boarding platform's front end
	local railH = 3.4
	local function rail(name: string, x0: number, x1: number, d0: number, d1: number, posts: number)
		kit:box(fit, name .. "Top", x0, x1, PLAT + railH - 0.2, PLAT + railH, d0, d1, Common.FRAME, "Metal")
		kit:box(
			fit,
			name .. "Mid",
			x0,
			x1,
			PLAT + railH / 2 - 0.1,
			PLAT + railH / 2 + 0.1,
			d0,
			d1,
			Common.FRAME,
			"Metal",
			{
				collide = false,
			}
		)
		for i = 0, posts - 1 do
			local f = if posts == 1 then 0.5 else i / (posts - 1)
			local x = x0 + (x1 - x0) * f
			local d = d0 + (d1 - d0) * f
			local hx, hd = math.min(0.12, (x1 - x0) / 2), math.min(0.12, (d1 - d0) / 2)
			kit:box(fit, name .. "Post", x - hx, x + hx, PLAT, PLAT + railH, d - hd, d + hd, Common.FRAME, "Metal")
		end
	end
	rail("RailSide", X0, X0 + 0.24, PLAT_FRONT, BACK - 0.3, 6)
	rail("RailFront", X0, BOARD_EDGE - 0.6, PLAT_FRONT, PLAT_FRONT + 0.24, 2)

	-- gantries on the platforms: the bullwheel's at the wheel, one more toward the front for the rails
	local BEAM0, BEAM1 = 14.0, 14.6
	local cols = { X0 + 0.4, X1 - 1.2 } -- column west faces
	for _, d in { wd, -10 } do
		for _, x in cols do
			kit:box(liftF, "GantryColumn", x, x + 0.8, PLAT, BEAM1, d - 0.4, d + 0.4, Common.STEEL, "Metal")
		end
		kit:box(liftF, "GantryBeam", cols[1], cols[2] + 0.8, BEAM0, BEAM1, d - 0.45, d + 0.45, Common.STEEL, "Metal")
	end
	-- the bullwheel, hub and gearbox
	local discY0 = cableY + SkyLift.GRIP_ABOVE + 0.15
	kit:cyl(liftF, "Bullwheel", wx, discY0 + 0.3, wd, 0.6, 2 * S + 0.8, "Y", Common.STEEL_DARK, "Metal")
	kit:cyl(liftF, "BullwheelRim", wx, discY0 + 0.65, wd, 0.1, 2 * S + 0.4, "Y", Common.RED, "Metal", {
		collide = false,
		query = false,
	})
	kit:cyl(liftF, "Hub", wx, (discY0 + 0.6 + BEAM0) / 2, wd, BEAM0 - discY0 - 0.6, 2.2, "Y", Common.STEEL, "Metal")
	kit:box(liftF, "Gearbox", wx - 2.2, wx + 2.2, BEAM1, BEAM1 + 1.6, wd - 1.4, wd + 1.4, Common.RED_DARK, "Metal")
	kit:box(liftF, "Tensioner", wx - 0.6, wx + 0.6, BEAM1, BEAM1 + 1.1, wd + 1.4, wd + 4.4, Common.STEEL_DARK, "Metal")
	-- guide rails along both strands, from the front to the bullwheel, hung from the gantry beams
	local railY0 = cableY + SkyLift.GRIP_ABOVE + 0.2
	local railEnd = wd - math.sqrt((S + 0.4) ^ 2 - S ^ 2) - 0.6
	for _, x in { downX, upX } do
		kit:box(
			liftF,
			"GuideRail",
			x - 0.3,
			x + 0.3,
			railY0,
			railY0 + 0.5,
			FRONT + 0.4,
			railEnd,
			Common.STEEL_DARK,
			"Metal"
		)
		kit:box(liftF, "RailHanger", x - 0.12, x + 0.12, railY0 + 0.5, BEAM0, -10.12, -9.88, Common.STEEL, "Metal")
	end
	-- the haul rope: round the bullwheel, along the hall and out through the lip's fillet
	local kit0 = Common.worldKit(roblox)
	for i, seg in Common.ropeSegments().summit do
		Common.rodW(
			kit0,
			liftF,
			`Rope{i}`,
			seg[1],
			seg[2],
			0.34,
			Common.ROPE,
			"Metal",
			{ collide = false, query = false }
		)
	end

	-- the self-service gate across the boarding platform, and the next-cabin board over it
	local GATE_D = 14.6
	local pillar = kit:box(
		fit,
		"BoardGate",
		X0 + 0.3,
		X0 + 0.9,
		PLAT,
		PLAT + 3.9,
		GATE_D - 0.4,
		GATE_D + 0.4,
		Common.RED,
		"SmoothPlastic"
	)
	pillar:SetAttribute("Gate", "board")
	pillar:SetAttribute("Station", "summit")
	local pg = kit:gui(pillar, "Front", 40)
	kit:label(pg, { Text = "SKY LIFT\nPRESS E", TextColor = Common.CREAM, Size = { 0.9, 0.3 }, Pos = { 0.05, 0.08 } })
	kit:box(
		fit,
		"BoardGatePost",
		BOARD_EDGE - 1.1,
		BOARD_EDGE - 0.5,
		PLAT,
		PLAT + 3.9,
		GATE_D - 0.4,
		GATE_D + 0.4,
		Common.RED,
		"SmoothPlastic"
	)
	local arm = kit:box(
		fit,
		"BoardGateArm",
		X0 + 0.9,
		BOARD_EDGE - 1.1,
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
	arm:SetAttribute("HingeX", X0 + 0.9)
	local nb = kit:box(
		fit,
		"NextCabinBoard",
		X0 + 1.4,
		BOARD_EDGE - 0.8,
		PLAT + 4.6,
		PLAT + 6.0,
		wd - 0.1,
		wd + 0.1,
		Common.FRAME,
		"SmoothPlastic",
		{
			collide = false,
			query = false,
		}
	)
	kit:box(fit, "BoardHanger", X0 + 1.8, X0 + 1.95, PLAT + 6.0, BEAM0, wd - 0.05, wd + 0.05, Common.STEEL, "Metal", {
		collide = false,
		query = false,
	})
	for _, face in { "Front", "Back" } do
		local ng = kit:gui(nb, face, 40)
		ng.LightInfluence = 0
		local t = kit:label(ng, { Text = "NEXT CABIN", TextColor = { 255, 196, 90 }, Font = "Code" })
		t.Name = "Next"
	end
	-- signs hung from the front gantry: down to town over the boarding side, welcome over the arrival side
	-- (both faces read; a SurfaceLight under each lights the platform's front end)
	local function sign(name: string, x0: number, x1: number, d: number, text: string)
		local p = kit:box(fit, name, x0, x1, 10.2, 11.8, d - 0.1, d + 0.1, Common.RED, "SmoothPlastic", {
			collide = false,
			query = false,
		})
		for _, face in { "Front", "Back" } do
			local sg = kit:gui(p, face, 40)
			sg.LightInfluence = 0
			kit:label(
				sg,
				{
					Text = text,
					TextColor = Common.CREAM,
					Font = "GothamBlack",
					Size = { 0.92, 0.7 },
					Pos = { 0.04, 0.15 },
				}
			)
		end
		kit:light(
			p,
			"SurfaceLight",
			{ Face = "Bottom", Range = 12, Brightness = 1.2, Angle = 80, Color = Common.WARM_LIGHT }
		)
		for _, x in { x0 + 0.5, x1 - 0.65 } do
			kit:box(fit, name .. "Hanger", x, x + 0.15, 11.8, BEAM0, d - 0.05, d + 0.05, Common.STEEL, "Metal", {
				collide = false,
				query = false,
			})
		end
	end
	sign("SignDown", X0 + 1.4, BOARD_EDGE - 0.2, -10, "DOWN TO TOWN")
	sign("SignWelcome", ALIGHT_EDGE + 0.2, X1 - 1.4, -10, "WELCOME TO THE LOOKOUT")

	-- pendant lamps from the bullwheel's gantry over both platforms
	for _, l in { { BOARD_EDGE - 1.4, wd }, { X1 - 3.2, wd } } do
		local x, d = l[1], l[2]
		kit:box(fit, "LampCord", x - 0.05, x + 0.05, 11.3, BEAM0, d - 0.05, d + 0.05, Common.FRAME, "Metal", {
			collide = false,
			query = false,
			shadow = false,
		})
		kit:cyl(
			fit,
			"LampShade",
			x,
			11.05,
			d,
			0.5,
			1.6,
			"Y",
			Common.RED_DARK,
			"Metal",
			{ collide = false, query = false }
		)
		local bulb = kit:cyl(fit, "Lamp", x, 10.75, d, 0.12, 1.2, "Y", Common.WARM_LIGHT, "Neon", {
			collide = false,
			query = false,
			shadow = false,
		})
		kit:light(bulb, "PointLight", { Range = 18, Brightness = 1.3, Color = Common.WARM_LIGHT, Shadows = false })
	end

	Common.anchors(kit, m, v, Common.FAMILY)
	return m
end

return Summit
