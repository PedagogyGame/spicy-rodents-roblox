--!strict
-- tools/bake/alley/Roof: the lane hall's raised roof (BRIEF_ADDENDUM D9, D10: "crawling into the top rafters of the
-- bowling alley"; owner question Q2's default: a taller roof over the lanes with steel trusses you can see from the
-- lanes). It is the model AlleyLayout.HALL_ROOF.model ("HallRoof"), everything that belongs to the roof over the hall,
-- built from Shared/Attractions/AlleyRoof's numbers in the alley's local frame:
--   the strip of the old flat roof from the concourse's back edge to the north clerestory wall, with its hung ceiling
--     (CeilingLanes) and the troffers over the settees;
--   brick clerestory walls north, east (with the vent duct's sleeve hole) and west standing on the old roof line, a
--     south wall on the machine wall, parapets with a coping, and a masking header from the masking units up to the
--     deck (the pinsetters' attic behind it is the backstage's);
--   the deck (Roof: corrugated steel underneath, slate on top) and the four rooftop units re-seated on it;
--   nine steel box trusses (AlleyRoof.TRUSS_D): a 2.4-wide bottom plate (the rafter routes 9120..9127 run on its
--     top), two Warren lattice planes either side of the body's path with a node at every lane pair's edge and
--     middle, two top chords, end posts at the walls; purlins between the top chords and the deck;
--   the two aisle braces across the plates (routes 9139, 9140) with the aisle troffers under them;
--   nine light rails over the lane pairs (routes 9130..9138), each hung from three trusses by a yoke and two rods
--     outside the body's path, and under them the lane lights (LaneLights: cans and washes at AlleyRoof.lamps(), the
--     pendant troffers over the approaches).
-- Only the plates, the braces, the rails, the walls, the deck, the strip and the units collide; the lattice, the top
-- chords, the purlins, the hangers and the lights neither collide nor take queries, and stand clear of every
-- rafter route's body (tests/unit/alley_roof_bake.spec.luau sweeps them).
-- No meshes: the owner's roof and rafter kit (docs/reference/store_roofs/roof_rafter_kit) is a timber gable bay
-- 11.1 m wide and 3.9 m tall; a flat-decked steel hall 127 studs across does not take it at one scale.
-- Interface: build(kit, root) -> Model; C (the palette); trussNodes() -> { { X, Y } } (one lattice plane's nodes,
--   west to east)

local AlleyLayout = require("../../../src/shared/Attractions/AlleyLayout")
local AlleyRoof = require("../../../src/shared/Attractions/AlleyRoof")

local Roof = {}

local L = AlleyLayout
local R = AlleyRoof
local HR = R.HALL_ROOF
local CH = R.CHORD
local RAIL = R.LIGHT_RAIL

local C = {
	brick = { 146, 70, 50 },
	trim = { 232, 222, 198 },
	roof = { 58, 60, 64 },
	deck = { 120, 124, 130 },
	steel = { 74, 80, 92 },
	lattice = { 92, 98, 110 },
	rail = { 52, 54, 58 },
	ceiling = { 176, 180, 196 },
	unit = { 176, 178, 176 },
	fan = { 90, 92, 92 },
	lamp = { 250, 248, 238 },
	can = { 200, 210, 255 },
	housing = { 40, 42, 46 },
	mask = { 26, 30, 60 },
}
Roof.C = C

local VISUAL = { collide = false, query = false }
local LIGHT = { collide = false, query = false, shadow = false }

-- One lattice plane's nodes, west to east: the top at the west wall, then a bottom node at every lane pair's edge and
-- a top node over every pair's middle, and the top at the east wall.
function Roof.trussNodes(): { { number } }
	local nodes = { { HR.x0, CH.topY0 } }
	local edge0 = L.LANE_BLOCK_X0
	for p = 1, L.PAIRS do
		table.insert(nodes, { edge0 + (p - 1) * 2 * L.PITCH, CH.y1 })
		table.insert(nodes, { L.pairX(p), CH.topY0 })
	end
	table.insert(nodes, { L.LANE_BLOCK_X1, CH.y1 })
	table.insert(nodes, { HR.x1, CH.topY0 })
	return nodes
end

local function walls(kit: any, m: any)
	local w = kit:model(m, "Clerestory")
	local top = HR.parapetY - 0.2
	-- north, on the strip's edge; west and east on the old roof line; south on the machine wall
	kit:box(w, "WallNorth", HR.outerX0, HR.outerX1, L.CEILING_Y, top, HR.northD0, HR.d0, C.brick, "Brick")
	kit:box(w, "WallWest", HR.outerX0, HR.x0, HR.clerestoryY0, top, HR.d0, HR.d1, C.brick, "Brick")
	kit:box(w, "WallSouth", HR.x0, HR.x1, L.CEILING_Y, top, HR.southD0, HR.d1, C.brick, "Brick")
	-- the east wall with the duct's sleeve through it (AlleyRoof.DUCT)
	local du = R.DUCT
	local y0 = HR.clerestoryY0
	kit:box(w, "WallEast", HR.x1, HR.outerX1, y0, du.y0, HR.d0, HR.d1, C.brick, "Brick")
	kit:box(w, "WallEast", HR.x1, HR.outerX1, du.y1, top, HR.d0, HR.d1, C.brick, "Brick")
	kit:box(w, "WallEast", HR.x1, HR.outerX1, du.y0, du.y1, HR.d0, du.d0, C.brick, "Brick")
	kit:box(w, "WallEast", HR.x1, HR.outerX1, du.y0, du.y1, du.d1, HR.d1, C.brick, "Brick")
	-- the coping round the top
	local function coping(name: string, x0: number, x1: number, d0: number, d1: number)
		kit:box(w, name, x0 - 0.1, x1 + 0.1, top, HR.parapetY, d0 - 0.1, d1 + 0.1, C.trim, "Concrete")
	end
	coping("CopingNorth", HR.outerX0, HR.outerX1, HR.northD0, HR.d0)
	coping("CopingWest", HR.outerX0, HR.x0, HR.d0, HR.d1)
	coping("CopingEast", HR.x1, HR.outerX1, HR.d0, HR.d1)
	coping("CopingSouth", HR.x0, HR.x1, HR.southD0, HR.d1)
	-- the masking header: the masking units' face carried up to the deck
	local mf = L.MACHINE_D0
	kit:box(
		w,
		"MaskHeader",
		L.LANE_BLOCK_X0 - 0.3,
		L.LANE_BLOCK_X1 + 0.3,
		L.CEILING_Y,
		HR.deckY0,
		mf - 0.4,
		mf,
		C.mask,
		"SmoothPlastic"
	)
end

local function deck(kit: any, m: any)
	kit:box(m, "RoofDeckSteel", HR.x0, HR.x1, HR.deckY0, HR.deckY0 + 0.15, HR.d0, HR.southD0, C.deck, "Metal")
	kit:box(m, "Roof", HR.x0, HR.x1, HR.deckY0 + 0.15, HR.deckY1, HR.d0, HR.southD0, C.roof, "Slate")
	-- the old flat roof over the settees, with its hung ceiling
	local CEIL = L.CEILING_Y
	kit:box(m, "RoofStrip", HR.x0, HR.x1, CEIL, HR.clerestoryY0, HR.stripD0, HR.northD0, C.roof, "Slate")
	kit:box(m, "CeilingLanes", HR.x0, HR.x1, CEIL - 0.04, CEIL, HR.stripD0, HR.northD0, C.ceiling, "SmoothPlastic", {
		collide = false,
		shadow = false,
	})
	-- the rooftop units, re-seated on the raised deck
	local H = HR.deckY1
	for i, hx in { -10, 20, 50, 80 } do
		local hd = 13
		kit:box(m, `RoofUnit{i}`, hx - 2.5, hx + 2.5, H, H + 2.6, hd - 3, hd + 3, C.unit, "Metal")
		kit:box(m, `RoofUnitFan{i}`, hx - 1.4, hx + 1.4, H + 2.6, H + 2.8, hd - 1.4, hd + 1.4, C.fan, "Metal")
	end
end

local function truss(kit: any, parent: any, i: number, d: number)
	local m = kit:model(parent, `Truss{i}`)
	m:SetAttribute("D", d)
	local half = CH.width / 2
	kit:box(m, "Plate", HR.x0, HR.x1, CH.y0, CH.y1, d - half, d + half, C.steel, "Metal")
	local nodes = Roof.trussNodes()
	for _, side in { -1, 1 } do
		local wd = d + side * CH.web
		kit:box(
			m,
			"TopChord",
			HR.x0,
			HR.x1,
			CH.topY0,
			CH.topY1,
			wd - CH.topW / 2,
			wd + CH.topW / 2,
			C.steel,
			"Metal",
			VISUAL
		)
		for _, x in { HR.x0 + CH.webT / 2, HR.x1 - CH.webT / 2 } do
			kit:box(
				m,
				"EndPost",
				x - CH.webT / 2,
				x + CH.webT / 2,
				CH.y1,
				CH.topY0,
				wd - CH.webT / 2,
				wd + CH.webT / 2,
				C.steel,
				"Metal",
				VISUAL
			)
		end
		for k = 1, #nodes - 1 do
			local a, b = nodes[k], nodes[k + 1]
			kit:rod(m, "Web", a[1], a[2], wd, b[1], b[2], wd, CH.webT, C.lattice, "Metal", VISUAL)
		end
	end
end

local function purlins(kit: any, m: any)
	local f = kit:model(m, "Purlins")
	for p = 0, L.PAIRS + 1 do
		local x = if p == 0 then HR.x0 + 2 elseif p == L.PAIRS + 1 then HR.x1 - 2 else L.pairX(p)
		kit:box(f, "Purlin", x - 0.15, x + 0.15, CH.topY1, HR.deckY0, HR.d0, HR.southD0, C.steel, "Metal", VISUAL)
	end
end

local function braces(kit: any, m: any)
	local f = kit:model(m, "Braces")
	local aisles = kit:model(m, "AisleLights")
	for i, x in R.BRACE_X do
		kit:box(f, `Brace{i}`, x - 0.25, x + 0.25, CH.y0, CH.y1, R.BRACE_D.d0, R.BRACE_D.d1, C.steel, "Metal")
		-- the aisle's troffers, fixed under the brace
		for _, d in { 2, 26, 50 } do
			local t = kit:box(
				aisles,
				"AisleTroffer",
				x - 1,
				x + 1,
				CH.y0 - 0.16,
				CH.y0 - 0.04,
				d - 3,
				d + 3,
				C.lamp,
				"Neon",
				LIGHT
			)
			kit:light(t, "PointLight", { Range = 22, Brightness = 0.9, Color = { 255, 244, 226 }, Shadows = false })
		end
	end
end

local function lights(kit: any, m: any)
	local rails = kit:model(m, "LightRails")
	local lanes = kit:model(m, "LaneLights")
	local hw = RAIL.width / 2
	for p = 1, L.PAIRS do
		local x = L.pairX(p)
		local r = kit:model(rails, `Rail{p}`)
		kit:box(r, "Rail", x - hw, x + hw, RAIL.y - 0.3, RAIL.y, RAIL.d0, L.MACHINE_D0 - 0.4, C.rail, "Metal")
		-- hung from the trusses: a yoke under the rail and a rod each side, outside the body's path (0.8)
		for _, d in RAIL.hangD do
			kit:box(r, "Yoke", x - 1.0, x + 1.0, RAIL.y - 0.45, RAIL.y - 0.3, d - 0.1, d + 0.1, C.rail, "Metal", VISUAL)
			for _, side in { -1, 1 } do
				local rx = x + side * 0.95
				kit:box(
					r,
					"Hanger",
					rx - 0.05,
					rx + 0.05,
					RAIL.y - 0.45,
					CH.y0,
					d - 0.05,
					d + 0.05,
					C.rail,
					"Metal",
					VISUAL
				)
			end
		end
	end
	-- the lamps where AlleyRoof.lamps() puts them: cans and washes under the rails, troffers over the approaches
	for _, lp in R.lamps() do
		local x, y, d = lp[1], lp[2], lp[3]
		if d < 0 then
			-- a pendant troffer on two rods to the deck
			local f = kit:box(lanes, "Troffer", x - 3.6, x + 3.6, y - 0.12, y, d - 0.5, d + 0.5, C.lamp, "Neon", LIGHT)
			if d == -13 then
				kit:light(
					f,
					"PointLight",
					{ Range = 22, Brightness = 1.15, Color = { 255, 244, 226 }, Shadows = false }
				)
			end
			for _, side in { -1, 1 } do
				local rx = x + side * 3.2
				kit:box(
					lanes,
					"TrofferRod",
					rx - 0.04,
					rx + 0.04,
					y,
					HR.deckY0,
					d - 0.04,
					d + 0.04,
					C.rail,
					"Metal",
					VISUAL
				)
			end
		elseif d == 12 or d == 30 then
			local wash = kit:cyl(lanes, "LaneWash", x, y - 0.25, d, 0.5, 1.4, "Y", C.can, "Neon", LIGHT)
			kit:light(wash, "PointLight", { Range = 20, Brightness = 0.85, Color = { 214, 222, 255 }, Shadows = false })
		else
			kit:cyl(lanes, "Can", x, y - 0.3, d, 0.6, 0.9, "Y", C.can, "Neon", LIGHT)
		end
	end
	-- the settee row's troffers in the strip's hung ceiling
	for p = 1, L.PAIRS do
		local x = L.pairX(p)
		kit:box(
			lanes,
			"Troffer",
			x - 3.6,
			x + 3.6,
			L.CEILING_Y - 0.12,
			L.CEILING_Y,
			-20.5,
			-19.5,
			C.lamp,
			"Neon",
			LIGHT
		)
	end
end

-- build(kit, root): the model HallRoof under root.
function Roof.build(kit: any, root: any): any
	local m = kit:model(root, L.HALL_ROOF.model)
	walls(kit, m)
	deck(kit, m)
	local trusses = kit:model(m, "Trusses")
	for i, d in R.TRUSS_D do
		truss(kit, trusses, i, d)
	end
	purlins(kit, m)
	braces(kit, m)
	lights(kit, m)
	return m
end

return Roof
