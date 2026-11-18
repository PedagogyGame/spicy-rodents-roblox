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
--     (2x, 3x, 5x at most) and the spinner is lit for 100 a turn until the ball ends. The letters a player
--     has down stay down for that player's next ball (the gentlest table: the hoard is filled over a game).
--   * All three top lanes: the bumpers are lit (100 a pop in place of 10) until the ball ends.
--   * Three acorns in the hoard light the extra ball at the right standup (once a game).
--   * Five acorns: WINTER IS COMING, 5,000 and the hoard starts again.
--   * End of ball: 100 for every target and lane made on that ball plus 500 an acorn in the hoard, times the
--     multiplier.
-- Geometry is in studs in Layout's playfield frame. Pure data and pure functions; Lune-tested
-- (tests/unit/pinball_layout.spec.luau, pinball_rules.spec.luau, pinball_shots.spec.luau).
-- Interface: a Machine.Table (id, title, def, ix, c, sheet) plus POINTS, SAY, MULTS

local Layout = require("./Layout")
local Machine = require("./Machine")
local Physics = require("./Physics")

local def = Layout.new("pinball_acorn", "ACORN ATTACK")
def.slopeDeg = 6
def.gravity = Layout.gravityFor(6)
def.kick = 0.75 -- old coils: its bumpers and slingshots are the softest of the three
def.plunger.vMin = 4.2
def.plunger.vMax = 7.6

Layout.addShell(def)
Layout.addBottom(def, { gap = 0.18, outlane = 0.19, inlane = 0.22, pivotY = 0.62, lead = 0.17 })

local XC = Layout.XC
local X1 = Layout.FIELD_X1

-- a rebound rubber across the arch on the left turns a hard plunge back toward the top lanes
Layout.wall(def, "rubber", { 0.161, 4.3, 0.42, 4.15 })
Layout.endPost(def, 0.42, 4.15, 0.161, 4.3)

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

-- the A-C-O-R-N bank on the left, turned to face down the table, with a wall behind it. It stands where the
-- left flipper's backhand goes (a ball flipped early, from near the pivot): the easiest shot on a flipper to
-- time, so the gentlest table's goal is its gentlest shot. N is the hardest hit and A the softest.
do
	local ax, ay, bx, by = 0.2, 2.25, 0.5, 2.7
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
		Layout.lamp(
			def,
			`acorn_{letters[i]}`,
			ax + (bx - ax) * (u0 + u1) / 2 + 0.09,
			ay + (by - ay) * (u0 + u1) / 2 - 0.05,
			"green"
		)
	end
	Layout.wall(def, "wood", { 0.0, 2.2, ax, ay })
	-- the rubber the targets fall back against stands close behind them, so no ball fits behind the bank
	Layout.wall(def, "rubber", { ax - 0.0266, ay + 0.0138, bx - 0.0266, by + 0.0138 })
	Layout.wall(def, "wood", { bx, by, 0.0, 3.02 })
	Layout.endPost(def, bx, by, 0.0, 3.02)
	Layout.post(def, ax, ay)
end

-- the spinner lane up the right side
-- (its guide leans out at the foot, so the lane's mouth is wide: the right flipper's backhand finds it)
Layout.wall(def, "metal", { 1.74, 2.3, 1.95, 2.95, 1.95, 3.42 })
Layout.post(def, 1.74, 2.3)
Layout.post(def, 1.95, 3.42)
table.insert(def.sensors, { id = "spinner", kind = "spinner", x1 = 1.95, y1 = 3.0, x2 = X1, y2 = 3.0 })
Layout.lamp(def, "spinner", 2.0, 2.5, "red")

-- two standup targets flanking the low bumper, each turned to face the flipper across the table (a late shot,
-- outside the low bumper); its back comes to a point, so a ball from above rolls off it
do
	local x1, y1, x2, y2 = 1.56, 2.99, 1.72, 2.93
	table.insert(def.targets, { id = "oak_r", kind = "standup", x1 = x1, y1 = y1, x2 = x2, y2 = y2 })
	table.insert(def.targets, { id = "oak_l", kind = "standup", x1 = X1 - x2, y1 = y2, x2 = X1 - x1, y2 = y1 })
	local back = { x1, y1, 1.66, 3.1, x2, y2 }
	Layout.wall(def, "wood", back)
	Layout.wall(def, "wood", Layout.mirror(back, X1 / 2))
	Layout.lamp(def, "oak_r", 1.6, 2.86, "yellow")
	Layout.lamp(def, "oak_l", X1 - 1.6, 2.86, "yellow")
end

-- a ball guide on each rail turns a ball rolling down the side into the inlane (the gentlest table)
Layout.railGuide(def, { 0.0, 2.16, 0.165, 1.68 })

for i = 1, 5 do
	Layout.lamp(def, `hoard_{i}`, XC - 0.3 + 0.1 * i, 1.75, "orange")
end
Layout.lamp(def, "bonus_2x", XC - 0.14, 1.5, "white")
Layout.lamp(def, "bonus_3x", XC, 1.5, "white")
Layout.lamp(def, "bonus_5x", XC + 0.14, 1.5, "white")
Layout.lamp(def, "extra_ball", 1.67, 2.76, "red")
Layout.lamp(def, "shoot_again", XC, 0.35, "red")

local ix = Layout.index(def)

-- ---------------------------------------------------------------------------------------------------------
-- The rule sheet
-- ---------------------------------------------------------------------------------------------------------
local CUE, EV = Machine.CUE, Physics.EV

local SAY = {
	SKILL = 101,
	ACORN = 102,
	BUMPERS_LIT = 103,
	WINTER = 104,
	SPINNER_LIT = 105,
	LANES = 106,
}
local MULTS = { 1, 2, 3, 5 }
local POINTS = {
	bumper = 10,
	bumperLit = 100,
	sling = 10,
	lane = 50,
	lanesAll = 300,
	skill = 500,
	drop = 100,
	bank = 1000,
	spin = 10,
	spinLit = 100,
	oak = 50,
	inlane = 50,
	outlane = 100,
	winter = 5000,
	bonusMade = 100,
	bonusAcorn = 500,
}
local HOARD_FULL = 5
local HOARD_EXTRA = 3
local RESET_TICKS = 150 -- the bank stands up again this long after its last target falls

local TOP = { ix.sensor.top_1, ix.sensor.top_2, ix.sensor.top_3 }
local BANK = { ix.target.acorn_a, ix.target.acorn_c, ix.target.acorn_o, ix.target.acorn_r, ix.target.acorn_n }
local BANK_NAMES = { "a", "c", "o", "r", "n" }

local function bit(n: number, i: number): boolean
	return bit32.band(n, bit32.lshift(1, i - 1)) ~= 0
end

local function bankDown(m: Machine.State): number
	local n = 0
	for _, i in BANK do
		if m.phys.drop[i] then
			n += 1
		end
	end
	return n
end

local sheet: Machine.Sheet = {
	saveTicks = 2400, -- ten seconds: the gentlest of the three
	maxScorePerSec = 4000,
	scoreScale = "a good game is 10,000; 30,000 is a great one",
	text = {
		[101] = "SKILL SHOT",
		[102] = "AN ACORN FOR THE HOARD",
		[103] = "BUMPERS ARE LIT",
		[104] = "WINTER IS COMING",
		[105] = "SPINNER IS LIT",
		[106] = "ALL THREE LANES",
	},
	init = function(): Machine.Numbers
		return {
			hoard = 0, -- acorns in the hoard, 0..4 (the fifth is WINTER and it starts again)
			winters = 0,
			mult = 1, -- index into MULTS
			lanes = 0, -- bits: top lanes made
			skillLane = 2,
			bumpersLit = 0,
			spinnerLit = 0,
			made = 0, -- targets and lanes made on this ball
			extraLit = 0,
			resetIn = 0,
			bank = 0, -- bits: the letters this player has knocked down (kept from ball to ball)
		}
	end,
	ballStart = function(m, t, tbl, out)
		t.lanes = 0
		t.skillLane = 2
		t.bumpersLit = 0
		t.spinnerLit = 0
		t.made = 0
		t.resetIn = 0
		-- the bank remembers: the letters this player has down stay down for their next ball (the machine
		-- stands the bank up and drops theirs again), so the hoard is filled over a whole game
		Machine.raiseDrops(m, tbl, out)
		for i, target in BANK do
			if bit(t.bank, i) then
				m.phys.drop[target] = true
			end
		end
	end,
	flip = function(_m, t, left)
		-- lane change: the flipper buttons walk the lit lanes (and the skill-shot lane) across
		local l = t.lanes
		if left then
			t.lanes = bit32.band(bit32.bor(bit32.rshift(l, 1), bit32.lshift(l, 2)), 7)
			t.skillLane = if t.skillLane == 1 then 3 else t.skillLane - 1
		else
			t.lanes = bit32.band(bit32.bor(bit32.lshift(l, 1), bit32.rshift(l, 2)), 7)
			t.skillLane = if t.skillLane == 3 then 1 else t.skillLane + 1
		end
	end,
	event = function(m, t, _tbl, out, code, ref, value, _ball)
		if code == EV.BUMPER then
			if value == 1 then
				Machine.add(m, if t.bumpersLit == 1 then POINTS.bumperLit else POINTS.bumper)
			end
		elseif code == EV.SLING then
			Machine.add(m, POINTS.sling)
		elseif code == EV.SPIN then
			Machine.add(m, if t.spinnerLit == 1 then POINTS.spinLit else POINTS.spin)
		elseif code == EV.ROLLOVER then
			for i = 1, 3 do
				if ref == TOP[i] then
					Machine.add(m, POINTS.lane)
					if m.skillLeft > 0 and t.skillLane == i then
						Machine.add(m, POINTS.skill)
						Machine.callout(m, out, SAY.SKILL, POINTS.skill)
						Machine.cue(out, CUE.JINGLE, 1, 0)
					end
					m.skillLeft = 0
					if not bit(t.lanes, i) then
						t.lanes += bit32.lshift(1, i - 1)
						t.made += 1
						if t.lanes == 7 then
							t.lanes = 0
							t.bumpersLit = 1
							Machine.add(m, POINTS.lanesAll)
							Machine.callout(m, out, SAY.BUMPERS_LIT, POINTS.lanesAll)
							Machine.cue(out, CUE.JINGLE, 2, 0)
						end
					end
					return
				end
			end
			if ref == ix.sensor.inlane_l or ref == ix.sensor.inlane_r then
				Machine.add(m, POINTS.inlane)
			elseif ref == ix.sensor.outlane_l or ref == ix.sensor.outlane_r then
				Machine.add(m, POINTS.outlane)
			end
		elseif code == EV.DROP then
			Machine.add(m, POINTS.drop)
			t.made += 1
			for i, target in BANK do
				if target == ref and not bit(t.bank, i) then
					t.bank += bit32.lshift(1, i - 1)
				end
			end
			if bankDown(m) == #BANK then
				t.bank = 0
				t.hoard += 1
				t.resetIn = RESET_TICKS
				t.spinnerLit = 1
				if t.mult < #MULTS then
					t.mult += 1
				end
				Machine.add(m, POINTS.bank)
				Machine.cue(out, CUE.JINGLE, 3, t.hoard)
				if t.hoard >= HOARD_FULL then
					t.hoard = 0
					t.winters += 1
					Machine.add(m, POINTS.winter)
					Machine.callout(m, out, SAY.WINTER, POINTS.winter)
					Machine.cue(out, CUE.JINGLE, 4, t.winters)
				else
					Machine.callout(m, out, SAY.ACORN, t.hoard)
					if t.hoard == HOARD_EXTRA and Machine.extraOpen(m) and t.extraLit == 0 then
						t.extraLit = 1
						Machine.callout(m, out, Machine.SAY.EXTRA_BALL_LIT, 0)
					end
				end
			end
		elseif code == EV.STANDUP then
			Machine.add(m, POINTS.oak)
			t.made += 1
			if ref == ix.target.oak_r and t.extraLit == 1 then
				t.extraLit = 0
				Machine.extraBall(m, out)
			end
		end
	end,
	tick = function(m, t, tbl, out)
		if t.resetIn > 0 then
			t.resetIn -= 1
			if t.resetIn == 0 then
				if Machine.dropsClear(m, tbl) then
					Machine.raiseDrops(m, tbl, out)
				else
					t.resetIn = 24
				end
			end
		end
	end,
	drained = function(_m, _t, _tbl, _out, _saved) end,
	tilted = function(_m, t, _tbl, _out)
		t.resetIn = 0
	end,
	bonus = function(_m, t)
		return POINTS.bonusMade * t.made + POINTS.bonusAcorn * t.hoard, MULTS[t.mult]
	end,
	lamps = function(m, t, _tbl, lamp)
		local L = ix.lamp
		for i = 1, 3 do
			if bit(t.lanes, i) then
				lamp[L[`top_{i}`]] = 1
			end
		end
		if m.skillLeft > 0 or not m.launched then
			lamp[L[`top_{t.skillLane}`]] = 2
		end
		for i = 1, 3 do
			lamp[L[`bumper_{i}`]] = if t.bumpersLit == 1 then 2 else 1
		end
		for i, target in BANK do
			if not m.phys.drop[target] then
				lamp[L[`acorn_{BANK_NAMES[i]}`]] = 1
			end
		end
		lamp[L.spinner] = t.spinnerLit
		lamp[L.oak_l] = 1
		lamp[L.oak_r] = 1
		for i = 1, HOARD_FULL do
			if i <= t.hoard then
				lamp[L[`hoard_{i}`]] = 1
			end
		end
		if t.mult >= 2 then
			lamp[L.bonus_2x] = 1
		end
		if t.mult >= 3 then
			lamp[L.bonus_3x] = 1
		end
		if t.mult >= 4 then
			lamp[L.bonus_5x] = 1
		end
		if t.extraLit == 1 then
			lamp[L.extra_ball] = 2
		end
	end,
	status = function(m, t)
		if t.extraLit == 1 then
			return "EXTRA BALL IS LIT AT THE RIGHT OAK TARGET"
		end
		local left = #BANK - bankDown(m)
		if left == 0 then
			return `ACORN {t.hoard} OF {HOARD_FULL} IS IN THE HOARD`
		end
		return `KNOCK DOWN A-C-O-R-N ({left} TO GO): {t.hoard} OF {HOARD_FULL} ACORNS IN THE HOARD`
	end,
	wants = function(m, t)
		local list: { number } = {}
		if t.extraLit == 1 then
			table.insert(list, Machine.key(EV.STANDUP, ix.target.oak_r))
		end
		-- the letters still standing, then the lit spinner, then anything that scores
		for _, i in BANK do
			if not m.phys.drop[i] then
				table.insert(list, Machine.key(EV.DROP, i))
			end
		end
		if t.spinnerLit == 1 then
			table.insert(list, Machine.key(EV.SPINNER, ix.sensor.spinner))
		end
		table.insert(list, Machine.key(EV.STANDUP, ix.target.oak_l))
		table.insert(list, Machine.key(EV.STANDUP, ix.target.oak_r))
		for i = 1, 3 do
			table.insert(list, Machine.key(EV.BUMPER, i))
		end
		return list
	end,
}

local TableAcorn = {
	id = def.id,
	title = def.title,
	def = def,
	ix = ix,
	c = Layout.compile(def),
	sheet = sheet,
	POINTS = POINTS,
	SAY = SAY,
	MULTS = MULTS,
	HOARD_FULL = HOARD_FULL,
	HOARD_EXTRA = HOARD_EXTRA,
}

return TableAcorn
