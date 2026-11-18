--!strict
-- tools/bake/lounge_classic/Shell: THE GILDED ACORN's building. A sealed brick hall with a flat roof behind a
-- parapet; a black-marble and brass front with leaded amber windows (set on the wall, not through it), a recessed
-- entry up four steps to a solid double door, a canopy, the sign, a stepped crown with a brass acorn; the
-- forecourt in front where the guards stand, with brass stanchions and velvet ropes. The floor is walnut planks
-- on a stone plinth down to below the lowest ground.
-- Interface: build(kit, root, venue) -> Model "Shell". No side effects on require.

local Kit = require("../alley/Kit")
local Style = require("./Style")

local Shell = {}

local SOLID = nil
local GHOST = { collide = false, query = false, shadow = false }
local HIDDEN = { collide = false, query = false, transparency = 1, shadow = false }

function Shell.build(kit: Kit.Kit, root: any, venue: any): any
	local m = kit:model(root, "Shell")
	local OX, IX = Style.OUTER_X, Style.INNER_X
	local F, B, IB = Style.FRONT_D, Style.BACK_D, Style.INNER_BACK
	local W = Style.WALL
	local AX, DD = Style.ALCOVE_X, Style.DOOR_D
	local top = Style.PARAPET
	local base = venue.ground.min - venue.floorY - 1 -- below the lowest ground under the footprint

	-- the plinth (the alcove's steps stand in its notch) and the walnut floor
	for i, r in kit:holes(-OX, OX, F, B, { { -AX, AX, F, DD } }) do
		kit:box(m, `Plinth{i}`, r[1], r[2], base, -0.2, r[3], r[4], Style.STONE, "Limestone", SOLID)
	end
	for i, r in kit:holes(-IX, IX, F + W, IB, { { -AX - W, AX + W, F + W, DD + W } }) do
		kit:box(m, `Floor{i}`, r[1], r[2], -0.2, 0, r[3], r[4], Style.WALNUT, "WoodPlanks", SOLID)
	end

	-- brick walls to the parapet; the alcove's sides and the door wall
	kit:box(m, "WestWall", -OX, -IX, base, top, F, B, Style.BRICK, "Brick")
	kit:box(m, "EastWall", IX, OX, base, top, F, B, Style.BRICK, "Brick")
	kit:box(m, "BackWall", -IX, IX, base, top, IB, B, Style.BRICK, "Brick")
	kit:box(m, "FrontWallW", -IX, -AX - W, base, top, F, F + W, Style.BRICK, "Brick")
	kit:box(m, "FrontWallE", AX + W, IX, base, top, F, F + W, Style.BRICK, "Brick")
	kit:box(m, "FrontOverDoor", -AX - W, AX + W, Style.ALCOVE_TOP, top, F, F + W, Style.BRICK, "Brick")
	kit:box(m, "AlcoveW", -AX - W, -AX, base, Style.CEILING, F, DD + W, Style.BRICK, "Brick")
	kit:box(m, "AlcoveE", AX, AX + W, base, Style.CEILING, F, DD + W, Style.BRICK, "Brick")
	local h = Style.DOOR_HALF
	kit:box(m, "DoorWallW", -AX, -h, -0.2, Style.CEILING, DD, DD + W, Style.BLACK, "Marble")
	kit:box(m, "DoorWallE", h, AX, -0.2, Style.CEILING, DD, DD + W, Style.BLACK, "Marble")
	kit:box(m, "Transom", -h, h, Style.DOOR_TOP, Style.CEILING, DD, DD + W, Style.BLACK, "Marble")
	kit:box(m, "AlcoveCeiling", -AX, AX, Style.ALCOVE_TOP, Style.ALCOVE_TOP + 1, F + W, DD, Style.GOLD, "Metal")

	-- the ceiling (cream plaster underneath) and the roof deck; stone coping on the parapet
	kit:box(m, "Ceiling", -IX, IX, Style.CEILING, Style.ROOF_TOP - 0.2, F + W, IB, Style.PLASTER, "SmoothPlastic")
	kit:box(m, "RoofDeck", -IX, IX, Style.ROOF_TOP - 0.2, Style.ROOF_TOP, F + W, IB, { 70, 66, 64 }, "Slate")
	local cope = { 0.15, 0.15 }
	kit:box(m, "CopingW", -OX - cope[1], -IX, top, top + 0.3, F - cope[1], B + cope[1], Style.STONE, "Limestone")
	kit:box(m, "CopingE", IX, OX + cope[1], top, top + 0.3, F - cope[1], B + cope[1], Style.STONE, "Limestone")
	kit:box(m, "CopingBack", -IX, IX, top, top + 0.3, IB, B + cope[1], Style.STONE, "Limestone")
	kit:box(m, "CopingFront", -IX, IX, top, top + 0.3, F - cope[1], F + W, Style.STONE, "Limestone")

	-- the door: two solid leaves (they never open; the prompt takes a person through), brass portholes and
	-- push plates, a brass architrave
	local dd0 = DD + 0.25
	for _, s in { -1, 1 } do
		local side = if s < 0 then "W" else "E"
		kit:box(m, `Leaf{side}`, s * 0.02, s * h, 0, Style.DOOR_TOP, dd0, dd0 + 0.5, Style.MAHOGANY, "Wood")
		kit:cyl(m, `Porthole{side}`, s * h / 2, 5.3, dd0 - 0.02, 0.2, 1.3, "D", Style.BRASS, "Metal", GHOST)
		kit:cyl(m, `PortGlass{side}`, s * h / 2, 5.3, dd0 - 0.08, 0.1, 1.0, "D", Style.AMBER, "Glass", GHOST)
		kit:box(m, `PushPlate{side}`, s * 0.25, s * 0.55, 3.2, 4.6, dd0 - 0.06, dd0, Style.BRASS, "Metal", GHOST)
		kit:box(m, `Jamb{side}`, s * h, s * (h + 0.35), -0.2, Style.DOOR_TOP + 0.35, DD - 0.12, DD, Style.GOLD, "Metal")
	end
	kit:box(m, "Lintel", -h - 0.35, h + 0.35, Style.DOOR_TOP, Style.DOOR_TOP + 0.35, DD - 0.12, DD, Style.GOLD, "Metal")
	kit:box(m, "Threshold", -h, h, -0.2, 0.05, DD, DD + W, Style.BRASS, "Metal")

	-- the steps up from the forecourt and the landing (terrazzo)
	local steps = { -1.86, -1.24, -0.62 }
	for i, y in steps do
		kit:box(m, `Step{i}`, -AX, AX, base, y, F + (i - 1), F + i, Style.STONE, "Marble")
	end
	kit:box(m, "Landing", -AX, AX, base, 0, Style.LANDING_D, DD, Style.STONE, "Marble")

	-- the front: black marble with brass fins and a brass band, four leaded amber windows set on the wall
	local face = F - 0.3
	kit:box(m, "FrontFaceW", -OX, -AX - W, base + 0.5, top, face, F, Style.BLACK, "Marble")
	kit:box(m, "FrontFaceE", AX + W, OX, base + 0.5, top, face, F, Style.BLACK, "Marble")
	kit:box(m, "FaceOverDoor", -AX - W, AX + W, Style.ALCOVE_TOP + 0.6, top, face, F, Style.BLACK, "Marble")
	kit:box(m, "Band", -OX, OX, 10.6, 11.0, face - 0.12, face, Style.GOLD, "Metal", GHOST)
	for _, x in { -20, -14, -8, 8, 14, 20 } do
		kit:box(m, `Fin{x}`, x - 0.2, x + 0.2, 0.4, top - 0.4, face - 0.25, face, Style.GOLD, "Metal", GHOST)
	end
	for _, x in { -17, -11, 11, 17 } do
		kit:box(m, `WinFrame{x}`, x - 2.2, x + 2.2, 2.8, 9.2, face - 0.08, face, Style.BRASS, "Metal", GHOST)
		kit:box(m, `WinGlass{x}`, x - 1.9, x + 1.9, 3.1, 8.9, face - 0.14, face - 0.08, Style.AMBER, "Glass", GHOST)
		kit:box(m, `WinMullion{x}`, x - 0.07, x + 0.07, 3.1, 8.9, face - 0.2, face - 0.14, Style.BRASS, "Metal", GHOST)
	end
	-- three blind amber windows on each side wall
	for _, s in { -1, 1 } do
		for _, d in { -14, 0, 14 } do
			local n = `{if s < 0 then "W" else "E"}{d}`
			local x0 = s * OX
			kit:box(m, `SideFrame{n}`, x0, x0 + s * 0.1, 3.5, 9.5, d - 2, d + 2, Style.STONE, "Limestone", GHOST)
			kit:box(m, `SideGlass{n}`, x0, x0 + s * 0.16, 3.8, 9.2, d - 1.7, d + 1.7, Style.AMBER, "Glass", GHOST)
		end
	end

	-- the canopy over the entry
	local cy = Style.ALCOVE_TOP
	kit:box(m, "Canopy", -AX - 2, AX + 2, cy, cy + 0.6, F - 3, F - 0.3, Style.BLACK, "Marble")
	kit:box(m, "CanopyEdge", -AX - 2.05, AX + 2.05, cy - 0.05, cy + 0.65, F - 3.1, F - 3, Style.GOLD, "Metal", GHOST)

	-- the sign over the canopy: gold letters on black, lit on their own
	local board = kit:box(m, "SignBoard", -9.5, 9.5, 11.4, 14.4, F - 0.7, F - 0.3, Style.BLACK, "Marble", GHOST)
	kit:box(m, "SignBorder", -9.8, 9.8, 11.1, 14.7, F - 0.6, F - 0.3, Style.GOLD, "Metal", GHOST)
	local gui = kit:gui(board, "Back", 40)
	kit:label(
		gui,
		{ Text = Style.SIGN, TextColor = Style.GOLD, Font = "Bodoni", Size = { 0.94, 0.7 }, Pos = { 0.03, 0.15 } }
	)

	-- the crown: two steps of black marble on the parapet and a brass acorn
	kit:box(m, "Crown1", -6.5, 6.5, top, top + 1.8, F - 0.3, F + 3, Style.BLACK, "Marble")
	kit:box(m, "Crown2", -4, 4, top + 1.8, top + 3, F - 0.3, F + 2.2, Style.BLACK, "Marble")
	kit:box(m, "CrownBand", -6.6, 6.6, top + 1.6, top + 1.8, F - 0.4, F - 0.3, Style.GOLD, "Metal", GHOST)
	local acornY = top + 3 + 1.0
	kit:ball(m, "AcornNut", 0, acornY, F + 1, 2.0, Style.GOLD, "Metal")
	kit:cyl(m, "AcornCap", 0, acornY + 0.75, F + 1, 0.7, 2.3, "Y", Style.WALNUT, "Wood")
	kit:cyl(m, "AcornStem", 0, Style.CREST - 0.3, F + 1, 0.6, 0.3, "Y", Style.WALNUT, "Wood", GHOST)

	-- the forecourt: paved to Bowl Lane's planned sidewalk; stanchions and velvet ropes line the way in
	local FD, FX = Style.FORECOURT_D, Style.FORECOURT_X
	kit:box(m, "Forecourt", -FX, FX, base, Style.FORECOURT_Y, FD, F, Style.STONE, "Pavement")
	for _, s in { -1, 1 } do
		local x = s * 3.6
		for i, d in { FD + 0.6, F - 0.6 } do
			kit:cyl(m, `Stanchion{s}{i}`, x, Style.FORECOURT_Y + 1.6, d, 3.2, 0.22, "Y", Style.BRASS, "Metal", GHOST)
			kit:ball(m, `Finial{s}{i}`, x, Style.FORECOURT_Y + 3.3, d, 0.36, Style.BRASS, "Metal", GHOST)
		end
		local rope = kit:cyl(
			m,
			`Rope{s}`,
			x,
			Style.FORECOURT_Y + 2.7,
			(FD + F) / 2,
			F - FD - 1.2,
			0.16,
			"D",
			Style.VELVET,
			"Fabric",
			GHOST
		)
		rope.CastShadow = false
	end

	-- the ground in the entry and on the forecourt, carved to air at boot (the west ground stands above it)
	local carve = kit:folder(root, "TerrainCarve")
	kit:box(carve, "Forecourt", -FX, FX, Style.FORECOURT_Y, cy + 1, FD, F, { 255, 0, 0 }, "SmoothPlastic", HIDDEN)
	kit:box(carve, "Alcove", -AX, AX, -2, cy, F, DD, { 255, 0, 0 }, "SmoothPlastic", HIDDEN)
	return m
end

return Shell
