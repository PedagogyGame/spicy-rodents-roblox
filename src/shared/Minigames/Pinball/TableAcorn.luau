--!strict
-- ReplicatedStorage.Shared.Minigames.Pinball.TableAcorn
-- ACORN ATTACK: the first of the alley's three machines (checklist PIN-R6), an old electro-mechanical table
-- and the gentlest of the three: a narrow gap between the flippers, a long ball save, small scores that
-- clack up on reels and ring chimes (tens, hundreds, thousands).
-- The playfield: three top lanes under the arch (the plunger's skill shot: the lit lane; the flipper buttons
-- move the light), three pop bumpers below them, the A-C-O-R-N bank of five drop targets on the left for the
-- right flipper, a spinner in the lane up the right side for the left flipper, two standup targets.
-- The rule sheet (one goal: fill the hoard before winter):
--   * Knock down A-C-O-R-N: an acorn goes into the hoard, the bank resets, the bonus multiplier steps up
--     (2x, 3x, 5x at most) and the spinner is lit for 100 a turn until the ball ends.
--   * All three top lanes: the bumpers are lit (100 a pop in place of 10) until the ball ends.
--   * Three acorns in the hoard light the extra ball at the right standup (once a game).
--   * Five acorns: WINTER IS COMING, 5,000 and the hoard starts again.
--   * End of ball: 100 for every target and lane made on that ball plus 500 an acorn in the hoard, times the
--     multiplier.
-- Geometry is in studs in Layout's playfield frame. Pure data and pure functions; Lune-tested
-- (tests/unit/pinball_tables.spec.luau, pinball_rules.spec.luau).
-- Interface: def (Layout.TableDef), sheet (Sheet.Rules), ix (Layout.Index)

local Layout = require("./Layout")

local def = Layout.new("pinball_acorn", "ACORN ATTACK")
def.slopeDeg = 6
def.gravity = Layout.gravityFor(6)
def.plunger.vMin = 4.6
def.plunger.vMax = 7.6

Layout.addShell(def)
Layout.addBottom(def, { gap = 0.2, outlane = 0.16, inlane = 0.17, pivotY = 0.62 })

local XC = Layout.XC
local X1 = Layout.FIELD_X1

-- a rebound rubber across the arch on the left turns a hard plunge back toward the top lanes
Layout.wall(def, "rubber", { 0.161, 4.3, 0.42, 4.15 })
Layout.post(def, 0.42, 4.15)

-- three top lanes between four wire guides
local LANE_X = { 0.72, 0.95, 1.18, 1.41 }
for _, x in LANE_X do
	Layout.wall(def, "metal", { x, 4.08, x, 4.34 })
	Layout.post(def, x, 4.34, 0.02, "rubber")
	Layout.post(def, x, 4.08, 0.02, "rubber")
end
for i = 1, 3 do
	local a, b = LANE_X[i], LANE_X[i + 1]
	table.insert(def.sensors, { id = `top_{i}`, kind = "rollover", x1 = a, y1 = 4.2, x2 = b, y2 = 4.2 })
	Layout.lamp(def, `top_{i}`, (a + b) / 2, 4.2, "amber")
end

-- three pop bumpers
table.insert(def.bumpers, { id = "bumper_1", x = 0.74, y = 3.62, r = 0.12 })
table.insert(def.bumpers, { id = "bumper_2", x = 1.4, y = 3.62, r = 0.12 })
table.insert(def.bumpers, { id = "bumper_3", x = 1.07, y = 3.16, r = 0.12 })
for i, b in def.bumpers do
	Layout.lamp(def, `bumper_{i}`, b.x, b.y, "white")
end

-- the A-C-O-R-N bank on the left, turned to face the right flipper, with a wall behind it
do
	local ax, ay, bx, by = 0.1, 2.22, 0.36, 2.72
	local letters = { "a", "c", "o", "r", "n" }
	for i = 1, 5 do
		local u0, u1 = (i - 1) / 5, i / 5
		table.insert(def.targets, {
			id = `acorn_{letters[i]}`,
			kind = "drop",
			x1 = ax + (bx - ax) * u0 + 0.004,
			y1 = ay + (by - ay) * u0 + 0.008,
			x2 = ax + (bx - ax) * u1 - 0.004,
			y2 = ay + (by - ay) * u1 - 0.008,
		})
		Layout.lamp(def, `acorn_{letters[i]}`, ax + (bx - ax) * (u0 + u1) / 2 + 0.09, ay + (by - ay) * (u0 + u1) / 2 - 0.05, "green")
	end
	Layout.wall(def, "wood", { 0.0, 2.2, ax, ay })
	Layout.wall(def, "rubber", { 0.0, 2.34, bx - 0.07, by + 0.035, bx, by })
	Layout.wall(def, "wood", { bx, by, 0.0, 3.02 })
	Layout.post(def, bx, by)
	Layout.post(def, ax, ay)
end

-- the spinner lane up the right side
Layout.wall(def, "metal", { 1.95, 2.25, 1.95, 3.42 })
Layout.post(def, 1.95, 2.25)
Layout.post(def, 1.95, 3.42)
table.insert(def.sensors, { id = "spinner", kind = "spinner", x1 = 1.95, y1 = 2.7, x2 = X1, y2 = 2.7 })
Layout.lamp(def, "spinner", 2.08, 2.45, "red")

-- two standup targets flanking the low bumper
table.insert(def.targets, { id = "oak_l", kind = "standup", x1 = 0.5, y1 = 3.02, x2 = 0.6, y2 = 2.92 })
Layout.wall(def, "wood", { 0.5, 3.02, 0.46, 3.08 })
table.insert(def.targets, { id = "oak_r", kind = "standup", x1 = 1.62, y1 = 2.92, x2 = 1.72, y2 = 3.02 })
Layout.wall(def, "wood", { 1.72, 3.02, 1.76, 3.08 })
Layout.post(def, 0.6, 2.92)
Layout.post(def, 1.62, 2.92)
Layout.lamp(def, "oak_l", 0.6, 2.84, "yellow")
Layout.lamp(def, "oak_r", 1.62, 2.84, "yellow")

-- a kink in each rail above the outlanes leans a ball rolling down the side toward the inlane
Layout.wall(def, "wood", { 0.0, 1.95, 0.13, 1.7 })
Layout.wall(def, "wood", { X1, 1.95, X1 - 0.13, 1.7 })
Layout.post(def, 0.13, 1.7)
Layout.post(def, X1 - 0.13, 1.7)

for i = 1, 5 do
	Layout.lamp(def, `hoard_{i}`, XC - 0.3 + 0.1 * i, 1.75, "orange")
end
Layout.lamp(def, "bonus_2x", XC - 0.14, 1.5, "white")
Layout.lamp(def, "bonus_3x", XC, 1.5, "white")
Layout.lamp(def, "bonus_5x", XC + 0.14, 1.5, "white")
Layout.lamp(def, "extra_ball", 1.67, 2.76, "red")
Layout.lamp(def, "shoot_again", XC, 0.35, "red")

local ix = Layout.index(def)

local TableAcorn = {}
TableAcorn.def = def
TableAcorn.ix = ix

return TableAcorn
