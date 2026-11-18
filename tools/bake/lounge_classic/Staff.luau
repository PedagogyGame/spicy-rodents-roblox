--!strict
-- tools/bake/lounge_classic/Staff: THE GILDED ACORN's three people, built of parts like the game's puppets: the
-- two doormen-guards on the forecourt (broad, in claret greatcoats with brass buttons and peaked caps) and the
-- bartender behind the bar (white jacket, black bow tie, black trousers, hair combed back). Each is a Model with
-- an invisible, non-colliding Root as its PrimaryPart (Server/Attractions/LoungeService turns and moves them by
-- it) and attribute Staff = "guard" | "bartender". They face the street (-D), the bartender faces the bar.
-- Interface: build(kit, root) -> Model "Staff"; FIGURES (name, kind, X, D). No side effects on require.

local Kit = require("../alley/Kit")
local Style = require("./Style")

local Staff = {}

Staff.FIGURES = {
	{ name = "Guard1", kind = "guard", x = -6, d = -31 }, -- data/expansion.json guard_1
	{ name = "Guard2", kind = "guard", x = 6, d = -31 }, -- guard_2
	{ name = "Bartender", kind = "bartender", x = Style.BARTENDER[1], d = Style.BARTENDER[2] },
}

local GHOST = { collide = false, query = false }
local SKIN = { { 196, 150, 118 }, { 132, 92, 64 }, { 220, 182, 150 } }

local LOOKS = {
	guard = { coat = { 92, 28, 34 }, legs = { 30, 28, 32 }, trim = Style.GOLD, wide = 1.0, tall = 1.08 },
	bartender = { coat = { 238, 232, 220 }, legs = { 26, 24, 26 }, trim = Style.BLACK, wide = 0.82, tall = 1.0 },
}

-- One figure, feet on the ground at (x, y0, d), facing -D.
local function figure(
	kit: Kit.Kit,
	parent: any,
	name: string,
	kind: string,
	x: number,
	y0: number,
	d: number,
	skin: { number }
): any
	local look = LOOKS[kind]
	local m = kit:model(parent, name)
	m:SetAttribute("Staff", kind)
	local w, t = look.wide, look.tall
	local function box(
		part: string,
		cx: number,
		y: number,
		cd: number,
		sx: number,
		sy: number,
		sd: number,
		c: { number },
		mat: string
	)
		return kit:at(m, part, x + cx * w, y0 + y * t, d + cd, sx * w, sy * t, sd, c, mat, GHOST)
	end
	local root = kit:at(
		m,
		"Root",
		x,
		y0 + 2.9 * t,
		d,
		2 * w,
		5.8 * t,
		1.1,
		skin,
		"SmoothPlastic",
		{ collide = false, query = false, transparency = 1, shadow = false }
	)
	m.PrimaryPart = root
	for _, s in { -1, 1 } do
		box(`Shoe{s}`, s * 0.38, 0.17, -0.12, 0.62, 0.34, 0.95, Style.BLACK, "SmoothPlastic")
		box(`Leg{s}`, s * 0.38, 1.45, 0, 0.6, 2.22, 0.62, look.legs, "Fabric")
		box(`Arm{s}`, s * 1.24, 3.55, 0, 0.56, 1.95, 0.62, look.coat, "Fabric")
		box(`Hand{s}`, s * 1.24, 2.42, 0, 0.46, 0.34, 0.5, skin, "SmoothPlastic")
	end
	box("Body", 0, 3.65, 0, 1.95, 2.3, 1.0, look.coat, "Fabric")
	box("Front", 0, 3.7, -0.52, 0.14, 1.8, 0.06, look.trim, if kind == "guard" then "Metal" else "Fabric")
	box("Neck", 0, 4.9, 0, 0.5, 0.25, 0.5, skin, "SmoothPlastic")
	kit:ball(m, "Head", x, y0 + 5.5 * t, d, 1.15, skin, "SmoothPlastic", GHOST)
	if kind == "guard" then
		kit:cyl(m, "Cap", x, y0 + 6.05 * t, d, 0.38, 1.25, "Y", look.coat, "Fabric", GHOST)
		kit:box(
			m,
			"Peak",
			x - 0.45,
			x + 0.45,
			y0 + 5.88 * t,
			y0 + 5.94 * t,
			d - 0.95,
			d - 0.45,
			Style.BLACK,
			"SmoothPlastic",
			GHOST
		)
		kit:box(
			m,
			"Belt",
			x - 1.0,
			x + 1.0,
			y0 + 2.75 * t,
			y0 + 2.95 * t,
			d - 0.53,
			d + 0.53,
			Style.BLACK,
			"Leather",
			GHOST
		)
	else
		kit:cyl(m, "Hair", x, y0 + 5.82 * t, d + 0.08, 0.5, 1.18, "Y", { 40, 30, 24 }, "SmoothPlastic", GHOST)
		kit:box(m, "BowTie", x - 0.3, x + 0.3, y0 + 4.62, y0 + 4.82, d - 0.6, d - 0.5, Style.BLACK, "Fabric", GHOST)
		kit:box(
			m,
			"Apron",
			x - 0.75,
			x + 0.75,
			y0 + 1.3,
			y0 + 2.7,
			d - 0.36,
			d - 0.32,
			{ 250, 248, 244 },
			"Fabric",
			GHOST
		)
	end
	return m
end

function Staff.build(kit: Kit.Kit, root: any): any
	local m = kit:model(root, "Staff")
	for i, f in Staff.FIGURES do
		-- the guards stand on the forecourt, the bartender on the floor
		local y0 = if f.kind == "guard" then Style.FORECOURT_Y else 0
		figure(kit, m, f.name, f.kind, f.x, y0, f.d, SKIN[(i - 1) % #SKIN + 1])
	end
	return m
end

return Staff
