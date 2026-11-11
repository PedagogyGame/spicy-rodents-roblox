--!strict
-- ReplicatedStorage.Shared.Minigames.Pinball.TableSpicy
-- SPICY RODENT: the second machine (checklist PIN-R6), the fast one. A steeper table, a wide gap between the
-- flippers, wide outlanes and a short ball save: it is hungry. Scores run to the hundreds of thousands.
-- The playfield: the ramp "the wire" up the middle left for the right flipper (it carries the ball round the
-- top of the table and drops it in the right inlane, so the shot can be repeated), the S-P-I-C-Y standup
-- targets (two left, one centre, two right), the kick-out hole "the bite" in a horseshoe top right for the
-- left flipper, the hot lane up the right side (a soft plunge dribbles down it: the skill shot), three pop
-- bumpers in the nest top left.
-- The rule sheet (one goal: feed the rodent to SUPER):
--   * Everything feeds the HEAT meter: the wire most, then the bite, targets, bumpers. The meter cools all the
--     time. At a third it is FERAL (all scores 2x), at two thirds RABID (3x), full is SUPER: 5x for twenty
--     seconds with every lamp flashing, then the meter falls back to RABID's line.
--   * S-P-I-C-Y lights the bite; the bite then pays its jackpot and a big bite of heat.
--   * Every third wire in one ball lights the extra ball at the bite (once a game).
--   * A drain costs half the heat.
--   * End of ball: 1,000 for every wire and target of that ball, times the heat level reached.
-- Geometry is in studs in Layout's playfield frame. Pure data and pure functions; Lune-tested
-- (tests/unit/pinball_tables.spec.luau, pinball_rules.spec.luau).
-- Interface: def (Layout.TableDef), sheet (Sheet.Rules), ix (Layout.Index)

local Layout = require("./Layout")

local def = Layout.new("pinball_rodent", "SPICY RODENT")
def.slopeDeg = 7
def.gravity = Layout.gravityFor(7)
def.plunger.vMin = 4.8
def.plunger.vMax = 8.6

Layout.addShell(def)
Layout.addBottom(def, { gap = 0.26, outlane = 0.2, inlane = 0.16, pivotY = 0.62 })

local XC = Layout.XC
local X1 = Layout.FIELD_X1

-- the wire: up from the middle left, round the top above the playfield, down the right side to the right inlane
do
	local dropX, dropY = Layout.inlaneDrop(def, "right")
	Layout.addRamp(def, {
		id = "wire",
		pts = {
			0.8,
			2.45,
			0,
			0.6,
			3.2,
			0.24,
			0.52,
			3.7,
			0.3,
			0.66,
			4.2,
			0.3,
			1.05,
			4.5,
			0.3,
			1.5,
			4.46,
			0.3,
			1.88,
			4.12,
			0.3,
			2.08,
			3.5,
			0.28,
			2.1,
			2.4,
			0.24,
			2.08,
			1.8,
			0.16,
			dropX,
			dropY,
			0,
		},
		mouth = 0.11,
		minSpeed = 0.6,
		exitSpeed = 1.2,
		drag = 0.25,
	})
	Layout.lamp(def, "wire", 0.86, 2.2, "red")
end

-- S-P-I-C-Y: two standups on the left, one in the centre, two on the right
do
	local function standup(id: string, x1: number, y1: number, x2: number, y2: number, lx: number, ly: number)
		table.insert(def.targets, { id = id, kind = "standup", x1 = x1, y1 = y1, x2 = x2, y2 = y2 })
		Layout.lamp(def, id, lx, ly, "orange")
	end
	standup("spicy_s", 0.04, 2.0, 0.1, 2.11, 0.2, 1.98)
	standup("spicy_p", 0.1, 2.13, 0.16, 2.24, 0.26, 2.11)
	Layout.wall(def, "wood", { 0.0, 1.98, 0.04, 2.0 })
	Layout.wall(def, "wood", { 0.16, 2.24, 0.0, 2.5 })
	standup("spicy_i", 1.12, 2.86, 1.24, 2.86, 1.18, 2.74)
	Layout.wall(def, "plastic", { 1.12, 2.86, 1.12, 2.92, 1.24, 2.92, 1.24, 2.86 })
	Layout.post(def, 1.12, 2.86, 0.02, "rubber")
	Layout.post(def, 1.24, 2.86, 0.02, "rubber")
	standup("spicy_c", X1 - 0.16, 2.24, X1 - 0.1, 2.13, X1 - 0.26, 2.11)
	standup("spicy_y", X1 - 0.1, 2.11, X1 - 0.04, 2.0, X1 - 0.2, 1.98)
	Layout.wall(def, "wood", { X1, 1.98, X1 - 0.04, 2.0 })
	Layout.wall(def, "wood", { X1 - 0.16, 2.24, X1 - 0.22, 2.4 })
end

-- the hot lane up the right side (above S-P-I-C-Y's C and Y)
Layout.wall(def, "metal", { X1 - 0.22, 2.4, X1 - 0.22, 3.4 })
Layout.post(def, X1 - 0.22, 3.4)
table.insert(def.sensors, { id = "hot_lane", kind = "rollover", x1 = X1 - 0.22, y1 = 3.0, x2 = X1, y2 = 3.0 })
Layout.lamp(def, "hot_lane", X1 - 0.11, 2.8, "red")

-- the bite: a kick-out hole in a horseshoe, open toward the left flipper
table.insert(def.saucers, {
	id = "bite",
	x = 1.58,
	y = 3.52,
	r = 0.075,
	maxSpeed = 7,
	vx = -1.25,
	vy = -3.4,
	holdTicks = 300,
})
Layout.cup(def, 1.58, 3.52, 0.125, 250, 130)
Layout.lamp(def, "bite", 1.5, 3.28, "red")
Layout.lamp(def, "extra_ball", 1.42, 3.12, "red")

-- the nest: three pop bumpers top left, where a hard plunge comes down off the arch
table.insert(def.bumpers, { id = "bumper_1", x = 0.3, y = 3.72, r = 0.115 })
table.insert(def.bumpers, { id = "bumper_2", x = 0.72, y = 3.86, r = 0.115 })
table.insert(def.bumpers, { id = "bumper_3", x = 0.36, y = 3.28, r = 0.115 })
for i, b in def.bumpers do
	Layout.lamp(def, `bumper_{i}`, b.x, b.y, "red")
end

-- heat lamps up the middle
for i = 1, 9 do
	Layout.lamp(def, `heat_{i}`, XC, 1.1 + 0.12 * i, if i <= 3 then "yellow" elseif i <= 6 then "orange" else "red")
end
Layout.lamp(def, "feral", XC - 0.2, 1.5, "yellow")
Layout.lamp(def, "rabid", XC - 0.2, 1.86, "orange")
Layout.lamp(def, "super", XC - 0.2, 2.22, "red")
Layout.lamp(def, "shoot_again", XC, 0.35, "red")

local ix = Layout.index(def)

local TableSpicy = {}
TableSpicy.def = def
TableSpicy.ix = ix

return TableSpicy
