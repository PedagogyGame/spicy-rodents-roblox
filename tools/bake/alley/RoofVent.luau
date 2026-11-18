--!strict
-- tools/bake/alley/RoofVent: the elaborate rooftop vent (BRIEF_ADDENDUM D9: "an elaborate roof based vent the squirrel
-- can get to from the roof of the bowling alley"), built round route 9107 (Shared/Attractions/AlleyRoof: AHU, MOUTH,
-- DUCT, ELBOW, BOOT) as the model "RoofVent":
--   the air-handling unit on the games wing's roof: a curb (cut at the mouth so the sill is the roof), the housing in
--     riveted panels, a bank of louvres on its east face with one slat bent open over a gap where the squirrel goes
--     in, two access doors and the "AHU-3" plate on its north face, conduit to the hall's wall, the exhaust stack on
--     top with a guard and a five-bladed fan (the model "Fan": attribute SpinRpm, Client/World/Spinners turns it);
--   inside, the filter rack, the coil and the blower over a sheet-metal channel the squirrel runs through, up the
--     plenum's ramp and step to the duct, with one dim light;
--   the duct on two stands across the roof, flanged, through its sleeve in the hall's raised east wall; inside the
--     hall the drop (elbow) standing on the D 16.5 truss's plate between the truss's lattice planes, and the boot at
--     its foot, open onto the plate (route 9120) under a grille swung up on its hinge.
-- Everything round the squirrel's way collides (it is the enclosed run's wall: Shared/Routes/Enclosure); the dressing
-- does not, and nothing stands in the body's section along 9107 (tests/unit/alley_roofvent_bake.spec.luau sweeps it).
-- Interface: build(kit, root) -> Model; C (the palette); FAN_RPM

local AlleyRoof = require("../../../src/shared/Attractions/AlleyRoof")

local RoofVent = {}

local R = AlleyRoof
local A = R.AHU
local M = R.MOUTH
local DU = R.DUCT
local EL = R.ELBOW
local BO = R.BOOT

local C = {
	curb = { 150, 148, 142 },
	panel = { 182, 186, 184 },
	seam = { 150, 154, 152 },
	louvre = { 128, 132, 132 },
	inner = { 96, 100, 100 },
	duct = { 170, 174, 176 },
	flange = { 128, 132, 136 },
	stand = { 70, 74, 80 },
	filter = { 214, 206, 168 },
	coil = { 160, 100, 70 },
	blower = { 74, 78, 84 },
	stack = { 140, 144, 146 },
	fan = { 60, 62, 66 },
	door = { 170, 174, 172 },
	handle = { 40, 40, 44 },
	plate = { 30, 60, 120 },
	conduit = { 120, 120, 116 },
	grille = { 80, 84, 88 },
}
RoofVent.C = C
RoofVent.FAN_RPM = 90

local VISUAL = { collide = false, query = false }

local function housing(kit: any, m: any)
	local h, c, sk = A.housing, A.curb, A.skin
	local s = M.slat
	-- the curb, cut at the mouth
	kit:box(m, "Curb", c.x0, c.x1, c.y0, c.y1, c.d0, h.d0, C.curb, "Concrete")
	kit:box(m, "Curb", c.x0, c.x1, c.y0, c.y1, h.d1, c.d1, C.curb, "Concrete")
	kit:box(m, "Curb", c.x0, h.x0, c.y0, c.y1, h.d0, h.d1, C.curb, "Concrete")
	kit:box(m, "Curb", h.x1, c.x1, c.y0, c.y1, h.d0, s.d0, C.curb, "Concrete")
	kit:box(m, "Curb", h.x1, c.x1, c.y0, c.y1, s.d1, h.d1, C.curb, "Concrete")
	-- the panels: north (doors), south, the roof, the west face round the duct
	kit:box(m, "PanelNorth", h.x0, h.x1, h.y0, h.y1, h.d0, h.d0 + sk, C.panel, "DiamondPlate")
	kit:box(m, "PanelSouth", h.x0, h.x1, h.y0, h.y1, h.d1 - sk, h.d1, C.panel, "DiamondPlate")
	kit:box(m, "PanelTop", h.x0, h.x1, h.y1 - sk, h.y1, h.d0, h.d1, C.panel, "Metal")
	kit:box(m, "PanelWest", h.x0, h.x0 + sk, h.y0, DU.y0, h.d0, h.d1, C.panel, "Metal")
	kit:box(m, "PanelWest", h.x0, h.x0 + sk, DU.y1, h.y1, h.d0, h.d1, C.panel, "Metal")
	kit:box(m, "PanelWest", h.x0, h.x0 + sk, DU.y0, DU.y1, h.d0, DU.d0, C.panel, "Metal")
	kit:box(m, "PanelWest", h.x0, h.x0 + sk, DU.y0, DU.y1, DU.d1, h.d1, C.panel, "Metal")
	-- the east face round the louvre bank
	local lv = A.louvre
	kit:box(m, "PanelEast", h.x1 - sk, h.x1, h.y0, h.y1, h.d0, lv.d0, C.panel, "Metal")
	kit:box(m, "PanelEast", h.x1 - sk, h.x1, h.y0, h.y1, lv.d1, h.d1, C.panel, "Metal")
	kit:box(m, "PanelEast", h.x1 - sk, h.x1, lv.y1, h.y1, lv.d0, lv.d1, C.panel, "Metal")
	-- rivet strips on the seams (north and south faces, every 3 studs), a rail round the top
	for x = h.x0 + 3, h.x1 - 2, 3 do
		kit:box(m, "Seam", x - 0.06, x + 0.06, h.y0, h.y1, h.d0 - 0.04, h.d0, C.seam, "Metal", VISUAL)
		kit:box(m, "Seam", x - 0.06, x + 0.06, h.y0, h.y1, h.d1, h.d1 + 0.04, C.seam, "Metal", VISUAL)
	end
	kit:box(
		m,
		"TopRail",
		h.x0 - 0.05,
		h.x1 + 0.05,
		h.y1 - 0.25,
		h.y1,
		h.d0 - 0.05,
		h.d1 + 0.05,
		C.seam,
		"Metal",
		VISUAL
	)
	-- the access doors and the plate on the north face
	for i, x in { 106.5, 111.5 } do
		kit:box(m, `Door{i}`, x - 1.6, x + 1.6, h.y0 + 0.4, h.y1 - 0.6, h.d0 - 0.08, h.d0, C.door, "Metal", VISUAL)
		kit:box(m, "Handle", x + 1.0, x + 1.2, 16.2, 16.9, h.d0 - 0.2, h.d0 - 0.08, C.handle, "Metal", VISUAL)
	end
	local plate =
		kit:box(m, "UnitPlate", 108.6, 109.4, 17.6, 18.1, h.d0 - 0.1, h.d0 - 0.08, C.plate, "SmoothPlastic", VISUAL)
	kit:label(kit:gui(plate, "Back", 60), { Text = "AHU-3", TextColor = { 240, 240, 240 }, Font = "GothamBold" })
	-- conduit from the north face to the hall's wall
	kit:box(
		m,
		"Conduit",
		R.HALL_ROOF.outerX1,
		106.1,
		17.85,
		18.05,
		h.d0 - 0.35,
		h.d0 - 0.15,
		C.conduit,
		"Metal",
		VISUAL
	)
	kit:box(m, "Conduit", 105.9, 106.1, 17.85, 18.05, h.d0 - 0.35, h.d0, C.conduit, "Metal", VISUAL)
end

-- The louvre bank: slats angled down and out, the frame; across the mouth the lowest slats are gone and the one above
-- the gap is bent up and out.
local function louvres(kit: any, m: any)
	local lv, s, h = A.louvre, M.slat, A.housing
	local CFrame = kit.roblox.CFrame
	local tilt = CFrame.Angles(0, 0, math.rad(-40)) -- the slat's face turned down toward the outside (+X)
	local pitch = (lv.y1 - lv.y0) / lv.slats
	local x = h.x1 - 0.1
	for k = 0, lv.slats - 1 do
		local y = lv.y0 + (k + 0.5) * pitch
		if y - 0.2 < s.y1 then
			-- across the mouth: gone, and the first one above the gap bent open
			kit:at(m, "Slat", x, y, (lv.d0 + s.d0) / 2, 0.36, 0.05, s.d0 - lv.d0, C.louvre, "Metal", { rot = tilt })
			kit:at(m, "Slat", x, y, (s.d1 + lv.d1) / 2, 0.36, 0.05, lv.d1 - s.d1, C.louvre, "Metal", { rot = tilt })
		else
			kit:at(m, "Slat", x, y, (lv.d0 + lv.d1) / 2, 0.36, 0.05, lv.d1 - lv.d0, C.louvre, "Metal", { rot = tilt })
		end
	end
	-- the bent slat: torn at one end, pried up and out over the gap
	kit:at(
		m,
		"BentSlat",
		x + 0.35,
		s.y1 + 0.32,
		(s.d0 + s.d1) / 2 + 0.1,
		0.36,
		0.05,
		s.d1 - s.d0 - 0.1,
		C.louvre,
		"Metal",
		{
			rot = CFrame.Angles(math.rad(8), 0, math.rad(35)),
			collide = false,
			query = false,
		}
	)
	-- the frame round the bank
	local f = { collide = false, query = false }
	kit:box(m, "LouvreFrame", h.x1, h.x1 + 0.1, lv.y0 - 0.1, lv.y1, lv.d0, lv.d0 + 0.15, C.seam, "Metal", f)
	kit:box(m, "LouvreFrame", h.x1, h.x1 + 0.1, lv.y0 - 0.1, lv.y1, lv.d1 - 0.15, lv.d1, C.seam, "Metal", f)
	kit:box(m, "LouvreFrame", h.x1, h.x1 + 0.1, lv.y1 - 0.12, lv.y1, lv.d0, lv.d1, C.seam, "Metal", f)
end

-- Inside: the channel the squirrel runs in, the plenum's ramp and step up to the duct, and the plant over and beside it.
local function inside(kit: any, m: any)
	local h, sk = A.housing, A.skin
	local s = M.slat
	local x0, x1 = h.x0 + sk, h.x1 - sk
	local top = A.channelY1
	local CFrame = kit.roblox.CFrame
	kit:box(m, "ChannelWall", x0, x1, R.WING_ROOF.y, top, s.d0 - 0.1, s.d0, C.inner, "Metal")
	kit:box(m, "ChannelWall", x0, x1, R.WING_ROOF.y, top, s.d1, s.d1 + 0.1, C.inner, "Metal")
	kit:box(m, "CoilDeck", x0, x1, top, top + 0.1, s.d0 - 0.1, s.d1 + 0.1, C.inner, "Metal")
	-- the floor the route climbs: the ramp (from the louvre's sill up to the plenum's step), the step, the riser and
	-- the lip at the duct (AlleyRoof.route(9107)'s points)
	local p = R.route(R.VENT).points
	local rampX0, rampX1, stepY = p[3][1], p[2][1], p[3][2]
	local riseX0, riseX1, ductY = p[6][1], p[5][1], p[6][2]
	local width = s.d1 - s.d0
	local up = CFrame.Angles(0, -math.pi / 2, 0) -- a wedge rising toward -X
	local roofY = R.WING_ROOF.y
	kit:wedge(
		m,
		"PlenumRamp",
		(rampX0 + rampX1) / 2,
		(roofY + stepY) / 2,
		M.d,
		width,
		stepY - roofY,
		rampX1 - rampX0,
		C.inner,
		"Metal",
		{ rot = up }
	)
	kit:box(m, "PlenumStep", x0, rampX0, roofY, stepY, s.d0, s.d1, C.inner, "Metal")
	kit:wedge(
		m,
		"PlenumRiser",
		(riseX0 + riseX1) / 2,
		(stepY + ductY) / 2,
		M.d,
		width,
		ductY - stepY,
		riseX1 - riseX0,
		C.inner,
		"Metal",
		{ rot = up }
	)
	kit:box(m, "PlenumLip", x0, riseX0, stepY, ductY, s.d0, s.d1, C.inner, "Metal")
	-- the plant: the filter rack behind the louvres, the coil, the blower in its scroll (north) and its motor (south)
	for _, side in { { h.d0 + sk, s.d0 - 0.1 }, { s.d1 + 0.1, h.d1 - sk } } do
		kit:box(m, "FilterRack", 114.3, 114.6, h.y0, h.y1 - sk, side[1], side[2], C.filter, "Fabric", VISUAL)
	end
	kit:box(m, "FilterRack", 114.3, 114.6, top + 0.1, h.y1 - sk, s.d0 - 0.1, s.d1 + 0.1, C.filter, "Fabric", VISUAL)
	kit:box(m, "Coil", 112.6, 113.2, top + 0.1, h.y1 - sk, h.d0 + sk, h.d1 - sk, C.coil, "Metal", VISUAL)
	kit:cyl(m, "BlowerScroll", 108.5, 16.2, 13.3, 3.4, 3.6, "D", C.blower, "Metal", VISUAL)
	kit:cyl(m, "BlowerWheel", 108.5, 16.2, 13.3, 3.5, 2.4, "D", { 110, 114, 120 }, "Metal", VISUAL)
	kit:cyl(m, "Motor", 108.5, 15.4, 19.6, 2.0, 1.4, "D", C.blower, "Metal", VISUAL)
	local lamp = kit:box(
		m,
		"ChannelLamp",
		109.6,
		110.4,
		top - 0.06,
		top,
		M.d - 0.2,
		M.d + 0.2,
		{ 255, 214, 150 },
		"Neon",
		{
			collide = false,
			query = false,
			shadow = false,
		}
	)
	kit:light(lamp, "PointLight", { Range = 3.5, Brightness = 0.6, Color = { 255, 200, 140 }, Shadows = false })
end

-- The exhaust stack on the roof, its guard, and the fan the client turns.
local function stack(kit: any, m: any)
	local st = A.stack
	local CFrame = kit.roblox.CFrame
	local cy = (st.y0 + st.y1) / 2
	kit:cyl(m, "Stack", st.x, cy, st.d, st.y1 - st.y0, st.r * 2, "Y", C.stack, "Metal")
	kit:cyl(m, "StackRim", st.x, st.y1 + 0.05, st.d, 0.1, st.r * 2 + 0.3, "Y", C.seam, "Metal", VISUAL)
	kit:cyl(
		m,
		"StackThroat",
		st.x,
		st.y1 + 0.11,
		st.d,
		0.02,
		st.r * 2 - 0.3,
		"Y",
		{ 18, 18, 20 },
		"SmoothPlastic",
		VISUAL
	)
	local fan = kit:model(m, "Fan")
	fan:SetAttribute("SpinRpm", RoofVent.FAN_RPM)
	fan.PrimaryPart = kit:cyl(fan, "Hub", st.x, st.y1 + 0.3, st.d, 0.3, 0.7, "Y", C.fan, "Metal", VISUAL)
	for k = 0, 4 do
		local a = k * 2 * math.pi / 5
		local rx, rd = math.cos(a) * 1.0, math.sin(a) * 1.0
		kit:at(fan, "Blade", st.x + rx, st.y1 + 0.3, st.d + rd, 1.5, 0.05, 0.6, C.fan, "Metal", {
			collide = false,
			query = false,
			rot = CFrame.Angles(0, -a, 0) * CFrame.Angles(math.rad(25), 0, 0),
		})
	end
	-- the guard: two crossed bars over the fan
	for _, a in { math.pi / 4, -math.pi / 4 } do
		kit:at(m, "FanGuard", st.x, st.y1 + 0.6, st.d, st.r * 2 + 0.2, 0.08, 0.12, C.seam, "Metal", {
			collide = false,
			query = false,
			rot = CFrame.Angles(0, a, 0),
		})
	end
end

-- The duct across the roof and through the wall; the drop inside the hall and the boot onto the plate.
local function duct(kit: any, m: any)
	local s = M.slat
	local t = 0.1
	local x1 = DU.x1
	kit:box(m, "DuctFloor", DU.x0, x1, DU.y0, DU.y0 + t + 0.02, DU.d0, DU.d1, C.duct, "Metal")
	kit:box(m, "DuctTop", DU.x0, x1, DU.y1 - t, DU.y1, DU.d0, DU.d1, C.duct, "Metal")
	kit:box(m, "DuctSide", DU.x0, x1, DU.y0, DU.y1, DU.d0, DU.d0 + t, C.duct, "Metal")
	kit:box(m, "DuctSide", DU.x0, x1, DU.y0, DU.y1, DU.d1 - t, DU.d1, C.duct, "Metal")
	-- flanges where it leaves the unit and where it meets the wall, the stands under it
	for _, x in { x1 - 0.2, R.HALL_ROOF.outerX1 + 0.15 } do
		local a, b, e = x - 0.08, x + 0.08, 0.12
		kit:box(m, "Flange", a, b, DU.y1, DU.y1 + e, DU.d0 - e, DU.d1 + e, C.flange, "Metal", VISUAL)
		kit:box(m, "Flange", a, b, DU.y0 - e, DU.y0, DU.d0 - e, DU.d1 + e, C.flange, "Metal", VISUAL)
		kit:box(m, "Flange", a, b, DU.y0, DU.y1, DU.d0 - e, DU.d0, C.flange, "Metal", VISUAL)
		kit:box(m, "Flange", a, b, DU.y0, DU.y1, DU.d1, DU.d1 + e, C.flange, "Metal", VISUAL)
	end
	kit:box(m, "DuctStand", 102.6, 103.0, R.WING_ROOF.y, DU.y0, DU.d0 + 0.2, DU.d1 - 0.2, C.stand, "Metal")
	kit:box(
		m,
		"DuctStandFoot",
		102.3,
		103.3,
		R.WING_ROOF.y,
		R.WING_ROOF.y + 0.1,
		DU.d0,
		DU.d1,
		C.stand,
		"Metal",
		VISUAL
	)
	-- the drop: a box from the plate to over the duct, the duct coming in high on its east face
	local d0, d1 = EL.d0, EL.d1
	kit:box(m, "DropSide", EL.x0, EL.x1, EL.y0, EL.y1, d0, s.d0, C.duct, "Metal")
	kit:box(m, "DropSide", EL.x0, EL.x1, EL.y0, EL.y1, s.d1, d1, C.duct, "Metal")
	kit:box(m, "DropTop", EL.x0, EL.x1, EL.y1 - t, EL.y1, d0, d1, C.duct, "Metal")
	kit:box(m, "DropEast", EL.x1 - t, EL.x1, EL.y0, DU.y0 + t + 0.02, s.d0, s.d1, C.duct, "Metal")
	kit:box(m, "DropEast", EL.x1 - t, EL.x1, DU.y1 - t, EL.y1, s.d0, s.d1, C.duct, "Metal")
	kit:box(m, "DropWest", EL.x0, EL.x0 + t, BO.y1, EL.y1, s.d0, s.d1, C.duct, "Metal")
	-- the boot's grille, hung from the lintel and swung up and out
	local CFrame = kit.roblox.CFrame
	local hingeX, hingeY = EL.x0, BO.y1
	-- (swung past level, so its free edge stands over the plate's path: a body leaving the boot passes under it)
	local open = math.rad(110)
	local len = BO.y1 - BO.y0 - 0.1
	local cx = hingeX - math.sin(open) * len / 2
	local cy = hingeY - math.cos(open) * len / 2
	local rot = CFrame.Angles(0, 0, -open)
	kit:at(m, "BootGrille", cx, cy, M.d, 0.06, len, s.d1 - s.d0, C.grille, "Metal", {
		collide = false,
		query = false,
		rot = rot,
		transparency = 0.35,
	})
	kit:at(
		m,
		"BootGrilleFrame",
		cx,
		cy,
		M.d,
		0.1,
		len,
		0.1,
		C.grille,
		"Metal",
		{ collide = false, query = false, rot = rot }
	)
end

-- build(kit, root): the model RoofVent under root.
function RoofVent.build(kit: any, root: any): any
	local m = kit:model(root, "RoofVent")
	housing(kit, m)
	louvres(kit, m)
	inside(kit, m)
	stack(kit, m)
	duct(kit, m)
	return m
end

return RoofVent
