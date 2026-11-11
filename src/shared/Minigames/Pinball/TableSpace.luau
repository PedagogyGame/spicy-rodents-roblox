--!strict
-- ReplicatedStorage.Shared.Minigames.Pinball.TableSpace
-- SPACE SQUIRREL: the third machine (checklist PIN-R6), the flow table. Two ramps that feed each other (the
-- left ramp, shot from the right flipper, drops the ball in the left inlane; the right ramp, shot from the
-- left flipper, in the right inlane), an orbit right round the top of the table, two lock pods and a
-- three-ball multiball. Scores run to the millions.
-- The playfield: the orbit lane inside both rails and under the arch; inside it the asteroid field of three
-- pop bumpers, reached up the middle or through the docking gap top right (a soft plunge falls through it:
-- the skill shot); the two ramps; a lock pod beside each ramp; F-U and E-L standup targets on the rails.
-- The rule sheet (one goal: LIFTOFF):
--   * F-U-E-L lights the locks. A ball shot into a lit pod stays there and a new ball comes to the plunger.
--   * With both pods full, either ramp starts the countdown: 3, 2, 1, LIFTOFF, both pods fire and three balls
--     are in play. During multiball every ramp and every orbit is a jackpot; it ends when one ball is left.
--   * Ramps and orbits made within four seconds of each other are a combo: each one in the chain is worth
--     one more times its value (up to 5x).
--   * Three orbits in one ball light the extra ball at the left pod (once a game).
--   * End of ball: 10,000 for every ramp and orbit of that ball, times one more for every ball locked.
-- Geometry is in studs in Layout's playfield frame. Pure data and pure functions; Lune-tested
-- (tests/unit/pinball_tables.spec.luau, pinball_rules.spec.luau).
-- Interface: def (Layout.TableDef), sheet (Sheet.Rules), ix (Layout.Index)

local Layout = require("./Layout")

local def = Layout.new("pinball_space", "SPACE SQUIRREL")
def.slopeDeg = 6.5
def.gravity = Layout.gravityFor(6.5)
def.plunger.vMin = 4.7
def.plunger.vMax = 9.2

Layout.addShell(def)
Layout.addBottom(def, { gap = 0.22, outlane = 0.17, inlane = 0.17, pivotY = 0.62 })

local XC = Layout.XC
local X1 = Layout.FIELD_X1
local function mx(x: number): number
	return 2 * XC - x
end

-- the orbit's inner guide: up the left, round under the arch, down the right, with the docking gap top right
local OR, OY = 0.885, 3.7
do
	local left = { XC - OR, 2.6 }
	for _, v in Layout.arc(XC, OY, OR, 180, 66, 20) do
		table.insert(left, v)
	end
	Layout.wall(def, "metal", left)
	local right = Layout.arc(XC, OY, OR, 34, 0, 6)
	table.insert(right, XC + OR)
	table.insert(right, 2.6)
	Layout.wall(def, "metal", right)
	Layout.post(def, XC - OR, 2.6)
	Layout.post(def, XC + OR, 2.6)
	local g1 = Layout.arc(XC, OY, OR, 66, 66, 1)
	local g2 = Layout.arc(XC, OY, OR, 34, 34, 1)
	Layout.post(def, g1[1], g1[2])
	Layout.post(def, g2[1], g2[2])
	table.insert(def.sensors, { id = "dock", kind = "rollover", x1 = g1[1], y1 = g1[2], x2 = g2[1], y2 = g2[2] })
	Layout.lamp(def, "dock", (g1[1] + g2[1]) / 2 - 0.1, (g1[2] + g2[2]) / 2 - 0.1, "blue")
end
table.insert(def.sensors, { id = "orbit_l", kind = "rollover", x1 = 0, y1 = 3.0, x2 = XC - OR, y2 = 3.0 })
table.insert(def.sensors, { id = "orbit_r", kind = "rollover", x1 = XC + OR, y1 = 3.0, x2 = X1, y2 = 3.0 })
table.insert(def.sensors, { id = "orbit_top", kind = "rollover", x1 = XC, y1 = OY + OR, x2 = XC, y2 = 4.9 })
Layout.lamp(def, "orbit_l", 0.11, 2.45, "blue")
Layout.lamp(def, "orbit_r", X1 - 0.11, 2.45, "blue")

-- the asteroid field
table.insert(def.bumpers, { id = "bumper_1", x = 0.84, y = 3.98, r = 0.11 })
table.insert(def.bumpers, { id = "bumper_2", x = 1.375, y = 3.98, r = 0.11 })
table.insert(def.bumpers, { id = "bumper_3", x = XC, y = 3.56, r = 0.11 })
for i, b in def.bumpers do
	Layout.lamp(def, `bumper_{i}`, b.x, b.y, "blue")
end

-- the two ramps
do
	local lx, ly = Layout.inlaneDrop(def, "left")
	local pts = { 0.75, 2.62, 0, 0.58, 3.32, 0.25, 0.44, 3.62, 0.3, 0.24, 3.66, 0.3, 0.1, 3.3, 0.3, 0.085, 2.3, 0.24, 0.1, 1.8, 0.16, lx, ly, 0 }
	Layout.addRamp(def, { id = "ramp_l", pts = pts, mouth = 0.11, minSpeed = 0.6, exitSpeed = 1.2, drag = 0.2 })
	local mirrored: { number } = {}
	for i = 1, #pts, 3 do
		table.insert(mirrored, mx(pts[i]))
		table.insert(mirrored, pts[i + 1])
		table.insert(mirrored, pts[i + 2])
	end
	Layout.addRamp(def, { id = "ramp_r", pts = mirrored, mouth = 0.11, minSpeed = 0.6, exitSpeed = 1.2, drag = 0.2 })
	Layout.lamp(def, "ramp_l", 0.82, 2.4, "white")
	Layout.lamp(def, "ramp_r", mx(0.82), 2.4, "white")
end

-- the lock pods, each a kick-out hole in a horseshoe open toward the far flipper
table.insert(def.saucers, { id = "pod_1", x = 0.44, y = 2.86, r = 0.075, maxSpeed = 7, vx = 1.1, vy = -3.0, holdTicks = 240 })
Layout.cup(def, 0.44, 2.86, 0.125, 290, 130)
table.insert(def.saucers, { id = "pod_2", x = mx(0.44), y = 2.86, r = 0.075, maxSpeed = 7, vx = -1.1, vy = -3.0, holdTicks = 240 })
Layout.cup(def, mx(0.44), 2.86, 0.125, 250, 130)
Layout.lamp(def, "pod_1", 0.52, 2.62, "green")
Layout.lamp(def, "pod_2", mx(0.52), 2.62, "green")
Layout.lamp(def, "extra_ball", 0.58, 2.48, "red")

-- F-U on the left rail, E-L on the right
do
	local function standup(id: string, x1: number, y1: number, x2: number, y2: number, lx: number, ly: number)
		table.insert(def.targets, { id = id, kind = "standup", x1 = x1, y1 = y1, x2 = x2, y2 = y2 })
		Layout.lamp(def, id, lx, ly, "yellow")
	end
	standup("fuel_f", 0.04, 2.02, 0.09, 2.13, 0.2, 2.0)
	standup("fuel_u", 0.09, 2.15, 0.14, 2.26, 0.25, 2.13)
	Layout.wall(def, "wood", { 0.0, 2.0, 0.04, 2.02 })
	Layout.wall(def, "wood", { 0.14, 2.26, 0.0, 2.5 })
	standup("fuel_e", X1 - 0.14, 2.26, X1 - 0.09, 2.15, X1 - 0.25, 2.13)
	standup("fuel_l", X1 - 0.09, 2.13, X1 - 0.04, 2.02, X1 - 0.2, 2.0)
	Layout.wall(def, "wood", { X1, 2.0, X1 - 0.04, 2.02 })
	Layout.wall(def, "wood", { X1 - 0.14, 2.26, X1, 2.5 })
end

-- a kink in each rail above the outlanes leans a ball coming down out of the orbit toward the inlane
Layout.wall(def, "wood", { 0.0, 1.92, 0.15, 1.66 })
Layout.wall(def, "wood", { X1, 1.92, X1 - 0.15, 1.66 })
Layout.post(def, 0.15, 1.66)
Layout.post(def, X1 - 0.15, 1.66)

for i = 1, 3 do
	Layout.lamp(def, `count_{i}`, XC - 0.4 + 0.2 * i, 2.1, "red")
end
for i = 1, 5 do
	Layout.lamp(def, `combo_{i}`, XC - 0.36 + 0.12 * i, 1.6, "white")
end
Layout.lamp(def, "jackpot", XC, 2.6, "red")
Layout.lamp(def, "shoot_again", XC, 0.35, "red")

local ix = Layout.index(def)

local TableSpace = {}
TableSpace.def = def
TableSpace.ix = ix

return TableSpace
