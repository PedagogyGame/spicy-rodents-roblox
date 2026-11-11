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
--     seconds with every lamp flashing, then the meter falls back into RABID.
--   * S-P-I-C-Y lights the bite; the bite then pays its jackpot and a big bite of heat.
--   * Every third wire in one ball lights the extra ball at the bite (once a game).
--   * A drain costs half the heat.
--   * End of ball: 1,000 for every wire and target of that ball, times the heat level reached.
-- Geometry is in studs in Layout's playfield frame. Pure data and pure functions; Lune-tested
-- (tests/unit/pinball_tables.spec.luau, pinball_rules.spec.luau).
-- Interface: a Machine.Table (id, title, def, ix, c, sheet) plus POINTS, SAY, HEAT, LEVEL_MULT, level(t)

local Layout = require("./Layout")
local Machine = require("./Machine")
local Physics = require("./Physics")

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
		mouth = 0.17,
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
	-- S and P stand one above the other on a bump in the left rail, both in reach of the left flipper's backhand
	standup("spicy_s", 0.1, 2.13, 0.16, 2.24, 0.26, 2.11)
	standup("spicy_p", 0.16, 2.26, 0.22, 2.37, 0.32, 2.24)
	Layout.wall(def, "wood", { 0.0, 2.1, 0.1, 2.13 })
	Layout.wall(def, "wood", { 0.22, 2.37, 0.0, 2.62 })
	standup("spicy_i", 1.02, 2.86, 1.26, 2.86, 1.14, 2.74)
	-- its back comes to a point, so a ball from above rolls off it
	Layout.wall(def, "plastic", { 1.02, 2.86, 1.02, 2.9, 1.14, 3.0, 1.26, 2.9, 1.26, 2.86 })
	standup("spicy_c", X1 - 0.22, 2.37, X1 - 0.16, 2.26, X1 - 0.32, 2.24)
	standup("spicy_y", X1 - 0.16, 2.24, X1 - 0.1, 2.13, X1 - 0.26, 2.11)
	Layout.wall(def, "wood", { X1, 2.1, X1 - 0.1, 2.13 })
	-- the bump's upper side is steep: a ball dribbling down the hot lane slides off it onto the right flipper
	Layout.wall(def, "wood", { X1 - 0.22, 2.37, X1 - 0.02, 2.8, X1, 2.9 })
end

-- the hot lane up the right side; a ball that comes down it rolls off the bump above C and Y into the table
Layout.wall(def, "metal", { X1 - 0.22, 2.8, X1 - 0.22, 3.4 })
Layout.post(def, X1 - 0.22, 3.4)
Layout.post(def, X1 - 0.22, 2.8)
table.insert(def.sensors, { id = "hot_lane", kind = "rollover", x1 = X1 - 0.22, y1 = 3.0, x2 = X1, y2 = 3.0 })
Layout.lamp(def, "hot_lane", X1 - 0.11, 2.8, "red")

-- the bite: a kick-out hole in a horseshoe; it drops the ball back onto the right flipper, to be caught
table.insert(def.saucers, {
	id = "bite",
	x = 1.58,
	y = 3.52,
	r = 0.1,
	maxSpeed = 7,
	vx = -0.19,
	vy = -1.5,
	holdTicks = 300,
})
Layout.cup(def, 1.58, 3.52, 0.16, 250, 130)
Layout.lamp(def, "bite", 1.5, 3.28, "red")
Layout.lamp(def, "extra_ball", 1.42, 3.12, "red")

-- the nest: three pop bumpers top left, where a hard plunge comes down off the arch; a rebound rubber on the
-- left rail turns a ball running down the rail into them
Layout.wall(def, "rubber", { 0.0, 4.05, 0.17, 3.97 })
Layout.post(def, 0.17, 3.97)
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

-- ---------------------------------------------------------------------------------------------------------
-- The rule sheet
-- ---------------------------------------------------------------------------------------------------------
local CUE, EV = Machine.CUE, Physics.EV

local SAY = {
	HOT_SHOT = 101,
	FERAL = 102,
	RABID = 103,
	SUPER = 104,
	BITE_LIT = 105,
	BITE = 106,
	WIRE = 107,
	SUPER_OVER = 108,
	BITTEN = 109,
}
local POINTS = {
	wire = 5000,
	letter = 1000,
	letterAgain = 250,
	bite = 2500,
	biteJackpot = 25000,
	bumper = 500,
	sling = 110,
	hotLane = 1000,
	hotShot = 10000,
	inlane = 500,
	outlane = 2500,
	bonusEach = 1000,
}
local HEAT = {
	wire = 14,
	letter = 5,
	letterAgain = 1,
	bite = 8,
	biteJackpot = 30,
	bumper = 1.5,
	sling = 0.5,
	hotLane = 3,
	hotShot = 20,
	full = 100,
	feral = 100 / 3,
	rabid = 200 / 3,
	coolPerTick = 1.6 / 240, -- the meter cools by this all the time a ball is in play
	superTicks = 4800, -- twenty seconds
	afterSuper = 75, -- where the meter stands when SUPER ends: in RABID, five seconds from cooling out of it
}
local LEVEL_MULT = { 1, 2, 3, 5 } -- calm, FERAL, RABID, SUPER
local WIRES_FOR_EXTRA = 3

local LETTERS = { ix.target.spicy_s, ix.target.spicy_p, ix.target.spicy_i, ix.target.spicy_c, ix.target.spicy_y }
local LETTER_NAMES = { "s", "p", "i", "c", "y" }

local function bit(n: number, i: number): boolean
	return bit32.band(n, bit32.lshift(1, i - 1)) ~= 0
end

-- level(t): 1 calm, 2 FERAL, 3 RABID, 4 SUPER
local function level(t: Machine.Numbers): number
	if t.super > 0 then
		return 4
	elseif t.heat >= HEAT.rabid then
		return 3
	elseif t.heat >= HEAT.feral then
		return 2
	end
	return 1
end

local function score(m: Machine.State, t: Machine.Numbers, points: number)
	Machine.add(m, points * LEVEL_MULT[level(t)])
end

local function warm(m: Machine.State, t: Machine.Numbers, out: { number }, by: number)
	if t.super > 0 then
		return
	end
	local before = level(t)
	t.heat += by
	if t.heat >= HEAT.full then
		t.heat = HEAT.full
		t.super = HEAT.superTicks
		t.supers += 1
		Machine.callout(m, out, SAY.SUPER, 0)
		Machine.cue(out, CUE.JINGLE, 4, 0)
	else
		local now = level(t)
		if now > before then
			Machine.callout(m, out, if now == 3 then SAY.RABID else SAY.FERAL, LEVEL_MULT[now])
			Machine.cue(out, CUE.JINGLE, now, 0)
		end
	end
	local now = level(t)
	if now > t.peak then
		t.peak = now
	end
end

local sheet: Machine.Sheet = {
	saveTicks = 1920, -- eight seconds: the hungry one
	maxScorePerSec = 150000,
	scoreScale = "a good game is 300,000; a million is a great one",
	text = {
		[101] = "HOT SHOT",
		[102] = "FERAL! ALL SCORES 2X",
		[103] = "RABID! ALL SCORES 3X",
		[104] = "SUPER! ALL SCORES 5X",
		[105] = "S-P-I-C-Y! THE BITE IS LIT",
		[106] = "THE BITE",
		[107] = "UP THE WIRE",
		[108] = "SUPER IS OVER",
		[109] = "A BIG BITE",
	},
	init = function(): Machine.Numbers
		return {
			heat = 0, -- 0..100
			super = 0, -- ticks of SUPER left
			supers = 0,
			peak = 1, -- the highest level reached on this ball
			letters = 0, -- bits: S-P-I-C-Y lit
			biteLit = 0,
			wires = 0, -- on this ball
			made = 0, -- wires and targets on this ball
			extraLit = 0,
		}
	end,
	ballStart = function(_m, t, _tbl, _out)
		t.wires = 0
		t.made = 0
		t.peak = level(t)
	end,
	flip = function(_m, _t, _left) end,
	event = function(m, t, _tbl, out, code, ref, value, _ball)
		if code == EV.BUMPER then
			if value == 1 then
				score(m, t, POINTS.bumper)
				warm(m, t, out, HEAT.bumper)
			end
		elseif code == EV.SLING then
			score(m, t, POINTS.sling)
			warm(m, t, out, HEAT.sling)
		elseif code == EV.RAIL_OUT then
			if value == 1 then
				score(m, t, POINTS.wire)
				t.wires += 1
				t.made += 1
				Machine.callout(m, out, SAY.WIRE, t.wires)
				warm(m, t, out, HEAT.wire)
				if t.wires % WIRES_FOR_EXTRA == 0 and m.extras[m.up] == 0 and t.extraLit == 0 then
					t.extraLit = 1
					Machine.callout(m, out, Machine.SAY.EXTRA_BALL_LIT, 0)
				end
			end
		elseif code == EV.STANDUP then
			for i = 1, 5 do
				if ref == LETTERS[i] then
					if bit(t.letters, i) then
						score(m, t, POINTS.letterAgain)
						warm(m, t, out, HEAT.letterAgain)
					else
						t.letters += bit32.lshift(1, i - 1)
						t.made += 1
						score(m, t, POINTS.letter)
						warm(m, t, out, HEAT.letter)
						if t.letters == 31 then
							t.letters = 0
							t.biteLit = 1
							Machine.callout(m, out, SAY.BITE_LIT, 0)
							Machine.cue(out, CUE.JINGLE, 5, 0)
						end
					end
					return
				end
			end
		elseif code == EV.SAUCER then
			if t.biteLit == 1 then
				t.biteLit = 0
				score(m, t, POINTS.biteJackpot)
				Machine.callout(m, out, SAY.BITTEN, POINTS.biteJackpot * LEVEL_MULT[level(t)])
				Machine.cue(out, CUE.JINGLE, 6, 0)
				warm(m, t, out, HEAT.biteJackpot)
			else
				score(m, t, POINTS.bite)
				Machine.callout(m, out, SAY.BITE, POINTS.bite * LEVEL_MULT[level(t)])
				warm(m, t, out, HEAT.bite)
			end
			if t.extraLit == 1 then
				t.extraLit = 0
				Machine.extraBall(m, out)
			end
		elseif code == EV.ROLLOVER then
			if ref == ix.sensor.hot_lane then
				if m.skillLeft > 0 then
					m.skillLeft = 0
					score(m, t, POINTS.hotShot)
					Machine.callout(m, out, SAY.HOT_SHOT, POINTS.hotShot)
					Machine.cue(out, CUE.JINGLE, 1, 0)
					warm(m, t, out, HEAT.hotShot)
				else
					score(m, t, POINTS.hotLane)
					warm(m, t, out, HEAT.hotLane)
				end
			elseif ref == ix.sensor.inlane_l or ref == ix.sensor.inlane_r then
				score(m, t, POINTS.inlane)
			elseif ref == ix.sensor.outlane_l or ref == ix.sensor.outlane_r then
				score(m, t, POINTS.outlane)
			end
		end
	end,
	tick = function(m, t, _tbl, out)
		if not m.launched then
			return
		end
		if t.super > 0 then
			t.super -= 1
			if t.super == 0 then
				t.heat = HEAT.afterSuper
				Machine.callout(m, out, SAY.SUPER_OVER, 0)
			end
		elseif t.heat > 0 then
			t.heat -= HEAT.coolPerTick
			if t.heat < 0 then
				t.heat = 0
			end
		end
	end,
	drained = function(_m, t, _tbl, _out, saved)
		if not saved then
			-- a drain costs half the heat (and SUPER with it)
			t.super = 0
			t.heat /= 2
		end
	end,
	bonus = function(_m, t)
		return POINTS.bonusEach * t.made, LEVEL_MULT[t.peak]
	end,
	lamps = function(m, t, _tbl, lamp)
		local L = ix.lamp
		local lv = level(t)
		local flash = if lv == 4 then 2 else 1
		lamp[L.wire] = if t.extraLit == 0 and t.wires % WIRES_FOR_EXTRA == WIRES_FOR_EXTRA - 1 then 2 else flash
		for i = 1, 5 do
			if bit(t.letters, i) then
				lamp[L[`spicy_{LETTER_NAMES[i]}`]] = flash
			end
		end
		lamp[L.hot_lane] = if m.skillLeft > 0 or not m.launched then 2 else flash
		if t.biteLit == 1 then
			lamp[L.bite] = 2
		end
		if t.extraLit == 1 then
			lamp[L.extra_ball] = 2
		end
		for i = 1, 3 do
			lamp[L[`bumper_{i}`]] = flash
		end
		local lit = math.floor(t.heat / HEAT.full * 9 + 1e-9)
		for i = 1, 9 do
			if i <= lit then
				lamp[L[`heat_{i}`]] = flash
			end
		end
		if lv >= 2 then
			lamp[L.feral] = flash
		end
		if lv >= 3 then
			lamp[L.rabid] = flash
		end
		if lv >= 4 then
			lamp[L.super] = 2
		end
	end,
	status = function(_m, t)
		local lv = level(t)
		if lv == 4 then
			return `SUPER! EVERYTHING SCORES 5X FOR {math.ceil(t.super / 240)} MORE SECONDS`
		end
		if t.extraLit == 1 then
			return "EXTRA BALL IS LIT AT THE BITE"
		end
		if t.biteLit == 1 then
			return "THE BITE IS LIT: SHOOT THE HOLE FOR THE JACKPOT"
		end
		local name = if lv == 3 then "RABID 3X" elseif lv == 2 then "FERAL 2X" else "CALM"
		return `HEAT {math.floor(t.heat)}% ({name}): SHOOT THE WIRE TO FEED THE RODENT`
	end,
	wants = function(_m, t)
		local list: { number } = {}
		local bite = Machine.key(EV.SAUCER, ix.saucer.bite)
		if t.extraLit == 1 or t.biteLit == 1 then
			table.insert(list, bite)
		end
		-- the wire feeds the rodent best; then the letters still dark, the bite, the hot lane, the nest
		table.insert(list, Machine.key(EV.RAIL_OUT, ix.rail.wire))
		for i = 1, 5 do
			if not bit(t.letters, i) then
				table.insert(list, Machine.key(EV.STANDUP, LETTERS[i]))
			end
		end
		table.insert(list, bite)
		table.insert(list, Machine.key(EV.ROLLOVER, ix.sensor.hot_lane))
		for i = 1, 3 do
			table.insert(list, Machine.key(EV.BUMPER, i))
		end
		return list
	end,
}

local TableSpicy = {
	id = def.id,
	title = def.title,
	def = def,
	ix = ix,
	c = Layout.compile(def),
	sheet = sheet,
	POINTS = POINTS,
	SAY = SAY,
	HEAT = HEAT,
	LEVEL_MULT = LEVEL_MULT,
	level = level,
}

return TableSpicy
