--!strict
-- tools/bake/games/CueParts: what the two cue-sport tables' bakes share (tools/bake/games/Pool, BumperPool): a
-- kit that works in a TABLE's own frame (x across, z along, y above the cloth: Shared/Minigames/Pool/Tables
-- and Furniture, so every dimension the bake draws is one the game plays on), the balls as Models the server
-- and the clients move by name, and the lamp over a table.
-- A ball is a Model whose PrimaryPart "Skin" is the sphere, with its pivot at the centre:
--   eight-ball's 1 to 8: the coloured sphere and a white number spot on each side (a thin disc, its face a
--     hair proud of the sphere, with the number on a SurfaceGui);
--   9 to 15: the sphere is the band's colour and two white spheres, a hair smaller and set a hair toward
--     each pole, cover everything outside the band (two nearly equal spheres cross on a circle: at 0.44 of
--     a radius from the middle, a real stripe's width), with the number spots on the band;
--   the cue ball: white, with six small red dots (a training ball), so its spin is seen;
--   bumper pool's: plain red and plain white, the marked one of each five with a spot of the other colour.
-- Every ball part is uncollidable (the game moves balls itself; a squirrel on the cloth walks through them).
-- Interface: on(kit, station) -> T (a kit in the table's frame): T:box(parent, name, x0, x1, y0, y1, z0, z1,
--   color, material, opts?), T:cyl(parent, name, x, y, z, length, diameter, axis "X" | "Y" | "Z", color,
--   material, opts?), T:ball(parent, name, x, y, z, diameter, color, material, opts?), T:slab(parent, name,
--   x1, z1, x2, z2, y0, y1, thick, side, color, material, opts?) (a wall along a line; side +1 puts its
--   thickness on the left of the direction, -1 on the right, 0 centres it), T:rod(parent, name, x0, y0, z0,
--   x1, y1, z1, diameter, color, material), T.kit, T.station; ball(T, parent, tableId, id, x, z) -> Model;
--   lamp(T, parent, halfL, shades) -> Model ("Lamp": the clients hide it for the top view); board(T, parent,
--   x, z, text) -> Model ("ScoreBoard": a chalkboard on a post, its TextLabels "Score" written by the server)

local AlleyLayout = require("../../../src/shared/Attractions/AlleyLayout")
local Furniture = require("../../../src/shared/Minigames/Pool/Furniture")
local Tables = require("../../../src/shared/Minigames/Pool/Tables")

local CueParts = {}

local T = {}
T.__index = T

function CueParts.on(kit: any, station: any): any
	return setmetatable({ kit = kit, station = station, cx = station.x, cd = station.d, y0 = Furniture.BED_Y }, T)
end

function T.box(
	self: any,
	parent: any,
	name: string,
	x0: number,
	x1: number,
	y0: number,
	y1: number,
	z0: number,
	z1: number,
	color: { number },
	material: string,
	opts: any?
): any
	return self.kit:box(
		parent,
		name,
		self.cx + x0,
		self.cx + x1,
		self.y0 + y0,
		self.y0 + y1,
		self.cd + z0,
		self.cd + z1,
		color,
		material,
		opts
	)
end

function T.cyl(
	self: any,
	parent: any,
	name: string,
	x: number,
	y: number,
	z: number,
	length: number,
	diameter: number,
	axis: string,
	color: { number },
	material: string,
	opts: any?
): any
	return self.kit:cyl(
		parent,
		name,
		self.cx + x,
		self.y0 + y,
		self.cd + z,
		length,
		diameter,
		if axis == "Z" then "D" else axis,
		color,
		material,
		opts
	)
end

function T.ball(
	self: any,
	parent: any,
	name: string,
	x: number,
	y: number,
	z: number,
	diameter: number,
	color: { number },
	material: string,
	opts: any?
): any
	return self.kit:ball(parent, name, self.cx + x, self.y0 + y, self.cd + z, diameter, color, material, opts)
end

-- A wall from (x1, z1) to (x2, z2), y0 to y1 high and `thick` wide. In the site's frame a part turned by
-- CFrame.Angles(0, a, 0) has its X axis along (cos a, sin a) in (X, D).
function T.slab(
	self: any,
	parent: any,
	name: string,
	x1: number,
	z1: number,
	x2: number,
	z2: number,
	y0: number,
	y1: number,
	thick: number,
	side: number,
	color: { number },
	material: string,
	opts: any?
): any
	local dx, dz = x2 - x1, z2 - z1
	local len = math.sqrt(dx * dx + dz * dz)
	local tx, tz = dx / len, dz / len
	-- the left of the direction (x right, z up the page) is (-tz, tx)
	local mx = (x1 + x2) / 2 - tz * side * thick / 2
	local mz = (z1 + z2) / 2 + tx * side * thick / 2
	local o: { [string]: any } = table.clone(opts or {})
	o.rot = self.kit.roblox.CFrame.Angles(0, math.atan2(tz, tx), 0)
	return self.kit:at(
		parent,
		name,
		self.cx + mx,
		self.y0 + (y0 + y1) / 2,
		self.cd + mz,
		len,
		math.abs(y1 - y0),
		thick,
		color,
		material,
		o
	)
end

function T.rod(
	self: any,
	parent: any,
	name: string,
	x0: number,
	y0: number,
	z0: number,
	x1: number,
	y1: number,
	z1: number,
	diameter: number,
	color: { number },
	material: string
): any
	return self.kit:rod(
		parent,
		name,
		self.cx + x0,
		self.y0 + y0,
		self.cd + z0,
		self.cx + x1,
		self.y0 + y1,
		self.cd + z1,
		diameter,
		color,
		material
	)
end

local LOOSE = { collide = false, query = false, shadow = false }
local SKIN = { collide = false, query = false, reflectance = 0.14 }
local INK = { 22, 22, 24 }
local DOT_RED = { 206, 36, 36 }

-- A number spot: a thin white disc on the ball's side (sx = +1 or -1 along the table's x), its face a hair
-- proud of the sphere, with the number on it.
local function numberSpot(t: any, m: any, x: number, y: number, z: number, r: number, sx: number, text: string)
	local rho = 0.33 * r -- the spot's radius
	local proud = 0.0025
	local depth = 0.03
	local disc = t:cyl(
		m,
		if sx > 0 then "SpotRight" else "SpotLeft",
		x + sx * (r + proud - depth / 2),
		y,
		z,
		depth,
		2 * rho,
		"X",
		Furniture.STRIPE_WHITE,
		"SmoothPlastic",
		LOOSE
	)
	if text ~= "" then
		local gui = t.kit:gui(disc, if sx > 0 then "Right" else "Left", 600)
		t.kit:label(gui, { Text = text, TextColor = INK, Font = "GothamBlack" })
	end
	return disc
end

-- One ball at (x, z) on the cloth of the table `tableId` ("eightball" | "bumper").
function CueParts.ball(t: any, parent: any, tableId: string, id: number, x: number, z: number): any
	local tb = Tables.byId(tableId)
	local r = tb.ballR
	local y = r
	local m = t.kit:model(parent, Furniture.ballName(id))
	local color, striped = Furniture.ballColor(tableId, id)
	local skin = t:ball(m, "Skin", x, y, z, 2 * r, color, "SmoothPlastic", SKIN)
	if tableId == "bumper" then
		-- the marked ball of each five carries a spot of the other colour on top and underneath
		if id == 1 or id == 6 then
			local other = if id == 1 then Furniture.BUMPER_WHITE else Furniture.BUMPER_RED
			for _, sy in { -1, 1 } do
				t:cyl(m, "Mark", x, y + sy * (r - 0.012), z, 0.03, 0.42 * r * 2, "Y", other, "SmoothPlastic", LOOSE)
			end
		end
	elseif id == 0 then
		-- six red dots: the spin shows
		local d, depth = 0.2 * r, 0.02
		local off = r + 0.002 - depth / 2
		for _, s in { -1, 1 } do
			t:cyl(m, "Dot", x + s * off, y, z, depth, d, "X", DOT_RED, "SmoothPlastic", LOOSE)
			t:cyl(m, "Dot", x, y + s * off, z, depth, d, "Y", DOT_RED, "SmoothPlastic", LOOSE)
			t:cyl(m, "Dot", x, y, z + s * off, depth, d, "Z", DOT_RED, "SmoothPlastic", LOOSE)
		end
	else
		if striped then
			-- two white spheres, a hair smaller and a hair toward each pole: they cross the skin at the band's edge
			local edge = 0.44 * r
			local bulge = 0.003
			local h = r - edge + bulge
			local capR = (r * r - edge * edge + h * h) / (2 * h)
			local lift = r + bulge - capR
			for _, sy in { -1, 1 } do
				t:ball(
					m,
					if sy > 0 then "CapTop" else "CapBottom",
					x,
					y + sy * lift,
					z,
					2 * capR,
					Furniture.STRIPE_WHITE,
					"SmoothPlastic",
					SKIN
				)
			end
		end
		numberSpot(t, m, x, y, z, r, 1, tostring(id))
		numberSpot(t, m, x, y, z, r, -1, tostring(id))
	end
	m.PrimaryPart = skin
	return m
end

local BRASS = { 196, 160, 80 }
local SHADE = { 22, 96, 56 }
local GLOW = { 255, 236, 190 }

-- The lamp over a table: a brass bar with `shades` green shades along the table, hung from the ceiling, with
-- real light under it. The clients hide the Model "Lamp" on their own screen for the top view.
function CueParts.lamp(t: any, parent: any, halfL: number, shades: number): any
	local m = t.kit:model(parent, "Lamp")
	local y = Furniture.LAMP_Y
	local span = halfL * 0.62
	local ceiling = AlleyLayout.CEILING_Y - Furniture.BED_Y
	t:box(m, "LampBar", -0.07, 0.07, y + 0.62, y + 0.74, -span - 0.5, span + 0.5, BRASS, "Metal", LOOSE)
	for _, sz in { -1, 1 } do
		t:cyl(
			m,
			"LampRod",
			0,
			(y + 0.74 + ceiling) / 2,
			sz * span * 0.6,
			ceiling - y - 0.74,
			0.06,
			"Y",
			BRASS,
			"Metal",
			LOOSE
		)
	end
	for k = 1, shades do
		local z = if shades == 1 then 0 else -span + (k - 1) * 2 * span / (shades - 1)
		-- a shade: a wide skirt under a narrow cap
		t:box(m, "Shade", -0.75, 0.75, y, y + 0.22, z - 0.75, z + 0.75, SHADE, "SmoothPlastic", LOOSE)
		t:box(m, "ShadeCap", -0.45, 0.45, y + 0.22, y + 0.5, z - 0.45, z + 0.45, SHADE, "SmoothPlastic", LOOSE)
		t:cyl(m, "ShadeStem", 0, y + 0.56, z, 0.14, 0.12, "Y", BRASS, "Metal", LOOSE)
		local bulb = t:box(m, "Bulb", -0.5, 0.5, y - 0.03, y, z - 0.5, z + 0.5, GLOW, "Neon", LOOSE)
		t.kit:light(
			bulb,
			"SurfaceLight",
			{ Face = "Bottom", Range = 11, Angle = 100, Brightness = 1.6, Color = { 255, 240, 206 } }
		)
	end
	local glow = t:box(m, "LampLight", -0.1, 0.1, y - 0.08, y - 0.03, -0.1, 0.1, GLOW, "Neon", LOOSE)
	t.kit:light(glow, "PointLight", { Range = 14, Brightness = 0.7, Color = { 255, 236, 200 }, Shadows = false })
	return m
end

local BOARD = { 34, 52, 40 }
local CHALK_WHITE = { 236, 236, 226 }

-- A little chalkboard on a post standing on the floor at (x, z) of the table's frame, its face across the
-- table's long axis (a label on each face, so it reads from either side): the server writes the score on it.
function CueParts.board(t: any, parent: any, x: number, z: number, text: string): any
	local m = t.kit:model(parent, "ScoreBoard")
	local floor = -Furniture.BED_Y
	local y0, y1 = floor + 3.3, floor + 4.5
	t:cyl(m, "BoardPost", x, (floor + y0) / 2, z, y0 - floor, 0.1, "Y", { 66, 40, 26 }, "Wood", LOOSE)
	t:cyl(m, "BoardFoot", x, floor + 0.05, z, 0.1, 0.6, "Y", { 66, 40, 26 }, "Wood", LOOSE)
	t:box(m, "BoardFrame", x - 0.98, x + 0.98, y0 - 0.06, y1 + 0.06, z - 0.05, z + 0.05, { 108, 68, 40 }, "Wood", LOOSE)
	local slate = t:box(m, "Board", x - 0.9, x + 0.9, y0, y1, z - 0.06, z + 0.06, BOARD, "Slate", LOOSE)
	for _, face in { "Front", "Back" } do
		local gui = t.kit:gui(slate, face, 80)
		t.kit:label(gui, {
			Name = "Score",
			Text = text,
			TextColor = CHALK_WHITE,
			Font = "GothamMedium",
			Size = { 0.92, 0.9 },
			Pos = { 0.04, 0.05 },
		})
	end
	return m
end

return CueParts
