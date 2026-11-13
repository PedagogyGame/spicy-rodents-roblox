--!strict
-- The three rule sheets (checklist PIN-R6: each table has its own rule sheet with one clear goal) and the
-- Minigame contract the machines are played through (PIN-R5). The sheets are driven here by the switch events
-- the physics would send, so every line of each sheet is pinned without waiting for a ball to find the switch:
--   ACORN ATTACK   fill the hoard: the A-C-O-R-N bank, the lanes and lit bumpers, the spinner, the multiplier,
--                  the extra ball at three acorns, WINTER at five; small scores;
--   SPICY RODENT   feed the heat: FERAL 2x, RABID 3x, SUPER 5x for twenty seconds; S-P-I-C-Y lights the bite;
--                  the wire; a drain costs half the heat;
--   SPACE SQUIRREL F-U-E-L lights the locks, two locks and a ramp count down to a three-ball multiball with
--                  jackpots; ramps and orbits chain into combos.
local Layout = require("@shared/Minigames/Pinball/Layout")
local Machine = require("@shared/Minigames/Pinball/Machine")
local Minigame = require("@shared/Minigames/Minigame")
local Physics = require("@shared/Minigames/Pinball/Physics")
local Rules = require("@shared/Minigames/Pinball/Rules")
local TableAcorn = require("@shared/Minigames/Pinball/TableAcorn")
local TableSpace = require("@shared/Minigames/Pinball/TableSpace")
local TableSpicy = require("@shared/Minigames/Pinball/TableSpicy")
local Bot = require("@shared/Minigames/Pinball/Bot")
local Games = require("@shared/Minigames/Games")
local InputLog = require("@shared/Minigames/Pinball/InputLog")
local PinballSpec = require("@shared/Minigames/Pinball/Spec")
local Replay = require("@shared/Minigames/Pinball/Replay")
local Tables = require("@shared/Minigames/Pinball/Tables")
local Test = require("../lib/Test")

local EV, CUE, BTN, PHASE = Physics.EV, Machine.CUE, Machine.BTN, Machine.PHASE

-- a machine whose ball is out on the playfield (parked asleep in the open middle), ball save off
local function inPlay(tbl: Machine.Table, players: number?): (Machine.State, { number })
	local m = Machine.new(tbl, 1, players or 1)
	local out: { number } = {}
	local b = m.phys.balls[1]
	b.x, b.y, b.asleep = Layout.XC, 2.0, true
	Machine.step(tbl, m, 0, out)
	m.saveLeft, m.graceLeft, m.skillLeft = 0, 0, 0
	return m, out
end

local function fire(
	tbl: Machine.Table,
	m: Machine.State,
	out: { number },
	code: number,
	ref: number,
	value: number?,
	ball: number?
)
	tbl.sheet.event(m, m.sheets[m.up], tbl, out, code, ref, value or 1, ball or 1)
end

local function tick(tbl: Machine.Table, m: Machine.State, out: { number }, ticks: number)
	for _ = 1, ticks do
		for _, b in m.phys.balls do
			if b.mode == Physics.FREE and b.x < Layout.FIELD_X1 then
				b.x, b.y, b.vx, b.vy, b.asleep = Layout.XC, 2.0, 0, 0, true
			end
		end
		Machine.step(tbl, m, BTN.LEFT, out)
	end
end

-- shove the cabinet until it tilts (the ball held in the open middle meanwhile)
local function tiltNow(tbl: Machine.Table, m: Machine.State, out: { number })
	for _ = 1, 8 do
		if m.tilted then
			return
		end
		for k = 1, Machine.NUDGE_COOL + 2 do
			for _, b in m.phys.balls do
				if b.mode == Physics.FREE and b.x < Layout.FIELD_X1 then
					b.x, b.y, b.vx, b.vy, b.asleep = Layout.XC, 2.0, 0, 0, true
				end
			end
			Machine.step(tbl, m, if k == 1 then BTN.NUDGE_L else 0, out)
		end
	end
	assert(m.tilted, "the machine did not tilt")
end

local function jingles(out: { number }): number
	local n = 0
	for i = 1, #out, 3 do
		if out[i] == CUE.JINGLE then
			n += 1
		end
	end
	return n
end

local function said(out: { number }, say: number): number
	local n = 0
	for i = 1, #out, 3 do
		if out[i] == CUE.SAY and out[i + 1] == say then
			n += 1
		end
	end
	return n
end

return function(t: Test.T)
	-- ------------------------------------------------------------------------------------------------- ACORN
	local A, AP = TableAcorn, TableAcorn.POINTS
	local aix = A.ix

	t.test("ACORN ATTACK: small scores: bumpers 10, slings 10, lanes 50, targets 100 (the gentlest table)", function()
		local m, out = inPlay(A)
		fire(A, m, out, EV.BUMPER, 1, 1)
		t.eq(m.scores[1], 10)
		fire(A, m, out, EV.BUMPER, 1, 0)
		t.eq(m.scores[1], 10, "a bumper that did not fire scores nothing")
		fire(A, m, out, EV.SLING, 1)
		t.eq(m.scores[1], 20)
		fire(A, m, out, EV.ROLLOVER, aix.sensor.inlane_l)
		t.eq(m.scores[1], 70)
		fire(A, m, out, EV.ROLLOVER, aix.sensor.outlane_r)
		t.eq(m.scores[1], 170)
		fire(A, m, out, EV.STANDUP, aix.target.oak_l)
		t.eq(m.scores[1], 220)
		fire(A, m, out, EV.SPIN, aix.sensor.spinner)
		t.eq(m.scores[1], 230)
		t.eq(A.sheet.saveTicks, 2400, "and the longest ball save: ten seconds")
	end)

	t.test("ACORN ATTACK: all three top lanes light the bumpers (100 a pop) until the ball ends", function()
		local m, out = inPlay(A)
		local s = m.sheets[1]
		fire(A, m, out, EV.ROLLOVER, aix.sensor.top_1)
		fire(A, m, out, EV.ROLLOVER, aix.sensor.top_1)
		t.eq(m.scores[1], 100, "50 each time through")
		t.eq(s.made, 1, "but a lane is made once")
		t.eq(Machine.lamps(A, m, {})[aix.lamp.top_1], 1)
		fire(A, m, out, EV.ROLLOVER, aix.sensor.top_3)
		t.eq(s.bumpersLit, 0)
		fire(A, m, out, EV.ROLLOVER, aix.sensor.top_2)
		t.eq(s.bumpersLit, 1)
		t.eq(m.scores[1], 100 + 50 + 50 + AP.lanesAll)
		t.eq(said(out, A.SAY.BUMPERS_LIT), 1)
		t.eq(s.lanes, 0, "the lanes go out to be made again")
		local before = m.scores[1]
		fire(A, m, out, EV.BUMPER, 2, 1)
		t.eq(m.scores[1] - before, 100)
		t.eq(Machine.lamps(A, m, {})[aix.lamp.bumper_2], 2)
		-- next ball: unlit again
		A.sheet.ballStart(m, s, A, out)
		t.eq(s.bumpersLit, 0)
	end)

	t.test("ACORN ATTACK: the flipper buttons walk the lit lanes across (lane change)", function()
		local m, out = inPlay(A)
		local s = m.sheets[1]
		fire(A, m, out, EV.ROLLOVER, aix.sensor.top_1)
		t.eq(s.lanes, 1)
		Machine.step(A, m, BTN.RIGHT, out)
		t.eq(s.lanes, 2, "right flipper: the light moves right")
		Machine.step(A, m, 0, out)
		Machine.step(A, m, BTN.RIGHT, out)
		t.eq(s.lanes, 4)
		Machine.step(A, m, 0, out)
		Machine.step(A, m, BTN.RIGHT, out)
		t.eq(s.lanes, 1, "and round")
		Machine.step(A, m, 0, out)
		Machine.step(A, m, BTN.LEFT, out)
		t.eq(s.lanes, 4, "left flipper: the other way")
		-- holding a button is one step, not one a tick
		for _ = 1, 20 do
			Machine.step(A, m, BTN.LEFT, out)
		end
		t.eq(s.lanes, 4)
	end)

	t.test("PIN-R1 ACORN ATTACK: the skill shot is the lit top lane, straight from the plunger", function()
		local m, out = inPlay(A)
		local s = m.sheets[1]
		t.eq(s.skillLane, 2)
		m.skillLeft = 500
		t.eq(Machine.lamps(A, m, {})[aix.lamp.top_2], 2, "the skill lane flashes")
		fire(A, m, out, EV.ROLLOVER, aix.sensor.top_2)
		t.eq(m.scores[1], AP.lane + AP.skill)
		t.eq(said(out, A.SAY.SKILL), 1)
		t.eq(m.skillLeft, 0, "one chance")
		fire(A, m, out, EV.ROLLOVER, aix.sensor.top_2)
		t.eq(m.scores[1], AP.lane * 2 + AP.skill)
		-- the wrong lane is no skill shot and closes it
		local m2, out2 = inPlay(A)
		m2.skillLeft = 500
		fire(A, m2, out2, EV.ROLLOVER, aix.sensor.top_1)
		t.eq(m2.scores[1], AP.lane)
		t.eq(m2.skillLeft, 0)
		-- and the ball getting into the game first closes it too
		local m3, out3 = inPlay(A)
		m3.skillLeft = 500
		m3.phys.balls[1].asleep = false
		m3.phys.balls[1].x, m3.phys.balls[1].y = A.def.bumpers[1].x, A.def.bumpers[1].y + 0.19
		m3.phys.balls[1].vy = -2
		for _ = 1, 10 do
			Machine.step(A, m3, 0, out3)
		end
		t.truthy(m3.scores[1] >= AP.bumper, "it hit a bumper")
		t.eq(m3.skillLeft, 0)
	end)

	t.test(
		"ACORN ATTACK: A-C-O-R-N down puts an acorn in the hoard, resets the bank, steps the multiplier, lights the spinner",
		function()
			local m, out = inPlay(A)
			local s = m.sheets[1]
			local bank =
				{ aix.target.acorn_a, aix.target.acorn_c, aix.target.acorn_o, aix.target.acorn_r, aix.target.acorn_n }
			local function knock(n: number)
				for i = 1, n do
					m.phys.drop[bank[i]] = true
					fire(A, m, out, EV.DROP, bank[i])
				end
			end
			knock(4)
			t.eq(m.scores[1], 400)
			t.eq(s.hoard, 0)
			t.eq(Machine.lamps(A, m, {})[aix.lamp.acorn_n], 1, "the last one standing is lit")
			t.eq(Machine.lamps(A, m, {})[aix.lamp.acorn_a], 0)
			m.phys.drop[bank[5]] = true
			fire(A, m, out, EV.DROP, bank[5])
			t.eq(s.hoard, 1)
			t.eq(m.scores[1], 500 + AP.bank)
			t.eq(said(out, A.SAY.ACORN), 1)
			t.eq(s.mult, 2)
			t.eq(A.MULTS[s.mult], 2, "bonus 2x")
			t.eq(s.spinnerLit, 1)
			local before = m.scores[1]
			fire(A, m, out, EV.SPIN, aix.sensor.spinner)
			t.eq(m.scores[1] - before, AP.spinLit, "the lit spinner pays 100 a turn")
			-- the bank stands up again a moment later
			t.truthy(m.phys.drop[bank[1]])
			tick(A, m, out, 200)
			for i = 1, 5 do
				t.falsy(m.phys.drop[bank[i]], `target {i} is up again`)
			end
			-- the multiplier goes 2x, 3x, 5x and no higher
			for expect = 3, 6 do
				knock(5)
				tick(A, m, out, 200)
				t.eq(A.MULTS[s.mult], ({ 1, 2, 3, 5, 5, 5 })[math.min(expect, 6)])
			end
		end
	)

	t.test(
		"ACORN ATTACK: the bank remembers: a player's letters stay down for their next ball, each player their own",
		function()
			local m, out = inPlay(A, 2)
			local bank =
				{ aix.target.acorn_a, aix.target.acorn_c, aix.target.acorn_o, aix.target.acorn_r, aix.target.acorn_n }
			local function knock(i: number)
				m.phys.drop[bank[i]] = true
				fire(A, m, out, EV.DROP, bank[i])
			end
			local function standing(): string
				local word = ""
				for i = 1, 5 do
					word ..= if m.phys.drop[bank[i]] then "-" else string.sub("ACORN", i, i)
				end
				return word
			end
			-- lose the ball in play: straight down between the flippers, then on to the next ball
			local function nextBall()
				for _, b in m.phys.balls do
					b.x, b.y, b.vx, b.vy, b.asleep = Layout.XC, 0.3, 0, -2, false
				end
				for _ = 1, 4000 do
					Machine.step(A, m, 0, out)
					if m.phase == PHASE.PLAY and m.ballTicks == 0 then
						break
					end
				end
				local b = m.phys.balls[1]
				b.x, b.y, b.asleep = Layout.XC, 2.0, true
				Machine.step(A, m, 0, out)
				m.saveLeft, m.graceLeft = 0, 0
			end
			knock(1)
			knock(3)
			t.eq(standing(), "-C-RN")
			t.eq(m.sheets[1].bank, 5, "A and O, as bits")
			nextBall()
			t.eq(m.up, 2)
			t.eq(standing(), "ACORN", "the second player finds the whole bank standing")
			t.eq(m.sheets[2].bank, 0)
			knock(5)
			nextBall()
			t.eq(m.up, 1)
			t.eq(m.ball, 2)
			t.eq(standing(), "-C-RN", "the first player's letters are down again")
			t.eq(Machine.lamps(A, m, {})[aix.lamp.acorn_a], 0)
			t.eq(Machine.lamps(A, m, {})[aix.lamp.acorn_c], 1)
			-- the rest of the bank on this ball finishes the acorn begun on the last one
			knock(2)
			knock(4)
			t.eq(m.sheets[1].hoard, 0)
			knock(5)
			t.eq(m.sheets[1].hoard, 1, "five letters over two balls: an acorn")
			t.eq(m.sheets[1].bank, 0, "and the bank starts again")
			nextBall()
			t.eq(m.up, 2)
			t.eq(standing(), "ACOR-", "the second player's N is still down")
			-- knocking the same letter twice is not two letters
			fire(A, m, out, EV.DROP, bank[5])
			t.eq(m.sheets[2].bank, 16)
		end
	)

	t.test("ACORN ATTACK: the bank does not stand up under a ball that is still on it", function()
		local m, out = inPlay(A)
		local s = m.sheets[1]
		local tg = A.def.targets[aix.target.acorn_o]
		for _, i in A.c.dropTargets do
			m.phys.drop[i] = true
		end
		s.resetIn = 1
		local b = m.phys.balls[1]
		b.x, b.y, b.asleep = (tg.x1 + tg.x2) / 2 + 0.03, (tg.y1 + tg.y2) / 2 - 0.02, true
		t.falsy(Machine.dropsClear(m, A))
		A.sheet.tick(m, s, A, out)
		t.truthy(m.phys.drop[aix.target.acorn_o], "it waits")
		b.x, b.y = Layout.XC, 2.0
		t.truthy(Machine.dropsClear(m, A))
		s.resetIn = 1
		A.sheet.tick(m, s, A, out)
		t.falsy(m.phys.drop[aix.target.acorn_o])
	end)

	t.test("PIN-R4 ACORN ATTACK: three acorns light the extra ball at the right oak target, once a game", function()
		local m, out = inPlay(A)
		local s = m.sheets[1]
		local function acorn()
			for _, i in A.c.dropTargets do
				m.phys.drop[i] = true
			end
			fire(A, m, out, EV.DROP, A.c.dropTargets[1])
			Machine.raiseDrops(m, A, out)
		end
		acorn()
		acorn()
		t.eq(s.extraLit, 0)
		acorn()
		t.eq(s.hoard, A.HOARD_EXTRA)
		t.eq(s.extraLit, 1)
		t.eq(said(out, Machine.SAY.EXTRA_BALL_LIT), 1)
		t.eq(Machine.lamps(A, m, {})[aix.lamp.extra_ball], 2)
		t.truthy(string.find(A.sheet.status(m, s), "EXTRA BALL", 1, true))
		fire(A, m, out, EV.STANDUP, aix.target.oak_l)
		t.falsy(m.shootAgain, "the left oak is not it")
		fire(A, m, out, EV.STANDUP, aix.target.oak_r)
		t.truthy(m.shootAgain)
		t.eq(m.extras[1], 1)
		t.eq(s.extraLit, 0)
		-- WINTER at five; the hoard starts again; three more acorns do not light a second extra ball
		acorn()
		t.eq(said(out, A.SAY.WINTER), 0)
		local before = m.scores[1]
		acorn()
		t.eq(said(out, A.SAY.WINTER), 1)
		t.eq(m.scores[1] - before, AP.drop + AP.bank + AP.winter)
		t.eq(s.hoard, 0)
		t.eq(s.winters, 1)
		acorn()
		acorn()
		acorn()
		t.eq(s.extraLit, 0, "one extra ball a game")
	end)

	t.test(
		"ACORN ATTACK: the bonus is 100 a target or lane made on the ball plus 500 an acorn, times the multiplier",
		function()
			local m, out = inPlay(A)
			local s = m.sheets[1]
			fire(A, m, out, EV.STANDUP, aix.target.oak_l)
			fire(A, m, out, EV.ROLLOVER, aix.sensor.top_1)
			m.phys.drop[aix.target.acorn_a] = true
			fire(A, m, out, EV.DROP, aix.target.acorn_a)
			s.hoard, s.mult = 2, 3
			local base, mult = A.sheet.bonus(m, s)
			t.eq(base, 3 * 100 + 2 * 500)
			t.eq(mult, 3)
			t.truthy(string.find(A.sheet.status(m, s), "A-C-O-R-N", 1, true), "the status line names the goal")
			-- what was made is per ball; the hoard and the multiplier are the player's for the game
			A.sheet.ballStart(m, s, A, out)
			t.eq(s.made, 0)
			t.eq(s.hoard, 2)
			t.eq(s.mult, 3)
		end
	)

	-- ------------------------------------------------------------------------------------------------- SPICY
	local S, SP, HEAT = TableSpicy, TableSpicy.POINTS, TableSpicy.HEAT
	local six = S.ix

	t.test(
		"SPICY RODENT: everything feeds the heat, the wire most; the meter cools all the time a ball is in play",
		function()
			local m, out = inPlay(S)
			local s = m.sheets[1]
			t.eq(s.heat, 0)
			fire(S, m, out, EV.BUMPER, 1, 1)
			t.eq(s.heat, HEAT.bumper)
			t.eq(m.scores[1], SP.bumper)
			fire(S, m, out, EV.RAIL_OUT, six.rail.wire, 1)
			t.eq(s.heat, HEAT.bumper + HEAT.wire)
			t.eq(m.scores[1], SP.bumper + SP.wire)
			t.truthy(HEAT.wire > HEAT.bite and HEAT.bite > HEAT.letter and HEAT.letter > HEAT.bumper, "the wire most")
			fire(S, m, out, EV.RAIL_OUT, six.rail.wire, 0)
			t.eq(s.heat, HEAT.bumper + HEAT.wire, "a ball that rolled back out of the wire fed nothing")
			local hot = s.heat
			tick(S, m, out, 240)
			t.near(hot - s.heat, 1.6, 0.02, "it cools 1.6 a second")
			-- not while the ball waits on the plunger
			local idle = Machine.new(S, 1, 1)
			idle.sheets[1].heat = 50
			for _ = 1, 480 do
				Machine.step(S, idle, 0, out)
			end
			t.eq(idle.sheets[1].heat, 50)
		end
	)

	t.test("SPICY RODENT: the heat multiplies every score: FERAL 2x at a third, RABID 3x at two thirds", function()
		local m, out = inPlay(S)
		local s = m.sheets[1]
		t.eq(S.level(s), 1)
		s.heat = 30
		fire(S, m, out, EV.RAIL_OUT, six.rail.wire, 1)
		t.eq(m.scores[1], SP.wire, "scored at the level it was made at")
		t.eq(S.level(s), 2, "and now FERAL")
		t.eq(said(out, S.SAY.FERAL), 1)
		local before = m.scores[1]
		fire(S, m, out, EV.SLING, 1)
		t.eq(m.scores[1] - before, SP.sling * 2)
		s.heat = 65
		fire(S, m, out, EV.BUMPER, 1, 1)
		fire(S, m, out, EV.BUMPER, 1, 1)
		t.eq(S.level(s), 3)
		t.eq(said(out, S.SAY.RABID), 1)
		before = m.scores[1]
		fire(S, m, out, EV.ROLLOVER, six.sensor.inlane_l)
		t.eq(m.scores[1] - before, SP.inlane * 3)
		t.deepEq(S.LEVEL_MULT, { 1, 2, 3, 5 })
		t.truthy(string.find(S.sheet.status(m, s), "RABID", 1, true))
	end)

	t.test(
		"SPICY RODENT: a full meter is SUPER: 5x for twenty seconds with the lamps flashing, then back to RABID's line",
		function()
			local m, out = inPlay(S)
			local s = m.sheets[1]
			s.heat = 95
			fire(S, m, out, EV.RAIL_OUT, six.rail.wire, 1)
			t.eq(S.level(s), 4)
			t.eq(s.super, HEAT.superTicks)
			t.eq(HEAT.superTicks, 20 * 240)
			t.eq(said(out, S.SAY.SUPER), 1)
			local before = m.scores[1]
			fire(S, m, out, EV.BUMPER, 1, 1)
			t.eq(m.scores[1] - before, SP.bumper * 5)
			local lamps = Machine.lamps(S, m, {})
			t.eq(lamps[six.lamp.super], 2)
			t.eq(lamps[six.lamp.heat_9], 2, "every heat lamp flashes")
			t.eq(lamps[six.lamp.bumper_1], 2)
			tick(S, m, out, HEAT.superTicks - 1)
			t.eq(S.level(s), 4, "still SUPER at 19.99 s")
			t.eq(s.heat, HEAT.full, "the meter holds full while it lasts")
			tick(S, m, out, 2)
			t.eq(S.level(s), 3, "then RABID")
			t.near(s.heat, HEAT.afterSuper, 0.05)
			t.truthy(HEAT.afterSuper > HEAT.rabid)
			t.eq(said(out, S.SAY.SUPER_OVER), 1)
			t.eq(s.peak, 4, "the ball's bonus remembers the level reached")
		end
	)

	t.test("SPICY RODENT: S-P-I-C-Y lights the bite; the bite then pays its jackpot and a big bite of heat", function()
		local m, out = inPlay(S)
		local s = m.sheets[1]
		fire(S, m, out, EV.SAUCER, six.saucer.bite)
		t.eq(m.scores[1], SP.bite, "unlit, the bite is a small award")
		local names = { "spicy_s", "spicy_p", "spicy_i", "spicy_c", "spicy_y" }
		local score = m.scores[1]
		for i = 1, 4 do
			fire(S, m, out, EV.STANDUP, six.target[names[i]])
		end
		t.eq(m.scores[1] - score, 4 * SP.letter)
		fire(S, m, out, EV.STANDUP, six.target.spicy_s)
		t.eq(m.scores[1] - score, 4 * SP.letter + SP.letterAgain, "a letter already lit is a small award")
		t.eq(s.biteLit, 0)
		t.eq(Machine.lamps(S, m, {})[six.lamp.spicy_p], 1)
		t.eq(Machine.lamps(S, m, {})[six.lamp.spicy_y], 0)
		fire(S, m, out, EV.STANDUP, six.target.spicy_y)
		t.eq(s.biteLit, 1)
		t.eq(said(out, S.SAY.BITE_LIT), 1)
		t.eq(s.letters, 0, "the letters go out to be spelt again")
		t.eq(Machine.lamps(S, m, {})[six.lamp.bite], 2)
		s.heat = 0
		score = m.scores[1]
		fire(S, m, out, EV.SAUCER, six.saucer.bite)
		t.eq(m.scores[1] - score, SP.biteJackpot)
		t.eq(s.heat, HEAT.biteJackpot)
		t.eq(s.biteLit, 0)
		t.eq(said(out, S.SAY.BITTEN), 1)
	end)

	t.test(
		"PIN-R4 SPICY RODENT: every third wire in one ball lights the extra ball at the bite, once a game",
		function()
			local m, out = inPlay(S)
			local s = m.sheets[1]
			fire(S, m, out, EV.RAIL_OUT, six.rail.wire, 1)
			fire(S, m, out, EV.RAIL_OUT, six.rail.wire, 1)
			t.eq(s.extraLit, 0)
			t.eq(Machine.lamps(S, m, {})[six.lamp.wire], 2, "one more: the wire lamp flashes")
			fire(S, m, out, EV.RAIL_OUT, six.rail.wire, 1)
			t.eq(s.extraLit, 1)
			fire(S, m, out, EV.SAUCER, six.saucer.bite)
			t.truthy(m.shootAgain)
			t.eq(s.extraLit, 0)
			for _ = 1, 3 do
				fire(S, m, out, EV.RAIL_OUT, six.rail.wire, 1)
			end
			t.eq(s.extraLit, 0, "never a second one")
			-- the count is per ball
			local m2, out2 = inPlay(S)
			fire(S, m2, out2, EV.RAIL_OUT, six.rail.wire, 1)
			fire(S, m2, out2, EV.RAIL_OUT, six.rail.wire, 1)
			S.sheet.ballStart(m2, m2.sheets[1], S, out2)
			fire(S, m2, out2, EV.RAIL_OUT, six.rail.wire, 1)
			t.eq(m2.sheets[1].extraLit, 0)
		end
	)

	t.test(
		"SPICY RODENT: a drain costs half the heat (a saved ball costs nothing); the hot lane is the skill shot",
		function()
			local m, out = inPlay(S)
			local s = m.sheets[1]
			s.heat = 80
			S.sheet.drained(m, s, S, out, true)
			t.eq(s.heat, 80)
			S.sheet.drained(m, s, S, out, false)
			t.eq(s.heat, 40)
			s.heat, s.super = 100, 1000
			S.sheet.drained(m, s, S, out, false)
			t.eq(s.super, 0, "and SUPER with it")
			t.eq(s.heat, 50)
			-- the hot lane
			local m2, out2 = inPlay(S)
			m2.skillLeft = 400
			t.eq(Machine.lamps(S, m2, {})[six.lamp.hot_lane], 2)
			fire(S, m2, out2, EV.ROLLOVER, six.sensor.hot_lane)
			t.eq(m2.scores[1], SP.hotShot)
			t.eq(said(out2, S.SAY.HOT_SHOT), 1)
			t.eq(m2.sheets[1].heat, HEAT.hotShot)
			fire(S, m2, out2, EV.ROLLOVER, six.sensor.hot_lane)
			t.eq(m2.scores[1], SP.hotShot + SP.hotLane, "afterwards it is an ordinary lane")
		end
	)

	t.test("SPICY RODENT: the bonus is 1,000 a wire or target of the ball, times the heat level reached", function()
		local m, out = inPlay(S)
		local s = m.sheets[1]
		fire(S, m, out, EV.RAIL_OUT, six.rail.wire, 1)
		fire(S, m, out, EV.STANDUP, six.target.spicy_i)
		fire(S, m, out, EV.STANDUP, six.target.spicy_i)
		t.eq(s.made, 2, "a letter counts once")
		s.heat = 70
		fire(S, m, out, EV.SLING, 1)
		t.eq(s.peak, 3)
		s.heat = 0
		local base, mult = S.sheet.bonus(m, s)
		t.eq(base, 2 * SP.bonusEach)
		t.eq(mult, 3, "the level REACHED, though the meter has cooled since")
		-- the heat is the player's for the game; what was made is the ball's
		s.heat = 40
		S.sheet.ballStart(m, s, S, out)
		t.eq(s.made, 0)
		t.eq(s.heat, 40)
		t.eq(s.peak, 2)
	end)

	-- ------------------------------------------------------------------------------------------------- SPACE
	local P, PP = TableSpace, TableSpace.POINTS
	local pix = P.ix

	t.test(
		"SPACE SQUIRREL: an orbit is a side lane and then the top of the arch; the plunge alone is not one",
		function()
			local m, out = inPlay(P)
			local s = m.sheets[1]
			fire(P, m, out, EV.ROLLOVER, pix.sensor.orbit_top, 1)
			t.eq(m.scores[1], 0, "the plunge goes over the top without having come up a side lane")
			fire(P, m, out, EV.ROLLOVER, pix.sensor.orbit_l, -1)
			fire(P, m, out, EV.ROLLOVER, pix.sensor.orbit_top, 1)
			t.eq(m.scores[1], 0, "coming DOWN a side lane does not arm it")
			fire(P, m, out, EV.ROLLOVER, pix.sensor.orbit_l, 1)
			fire(P, m, out, EV.ROLLOVER, pix.sensor.orbit_top, -1)
			t.eq(m.scores[1], PP.orbit)
			t.eq(s.orbits, 1)
			t.eq(said(out, P.SAY.ORBIT), 1)
			fire(P, m, out, EV.ROLLOVER, pix.sensor.orbit_top, 1)
			t.eq(m.scores[1], PP.orbit, "one orbit, not two")
			-- too slow round is no orbit
			fire(P, m, out, EV.ROLLOVER, pix.sensor.orbit_r, 1)
			tick(P, m, out, 721)
			fire(P, m, out, EV.ROLLOVER, pix.sensor.orbit_top, 1)
			t.eq(s.orbits, 1)
		end
	)

	t.test("SPACE SQUIRREL: ramps and orbits within four seconds chain into a combo, up to 5x", function()
		local m, out = inPlay(P)
		local s = m.sheets[1]
		fire(P, m, out, EV.RAIL_OUT, pix.rail.ramp_l, 1)
		t.eq(m.scores[1], PP.ramp)
		t.eq(s.combo, 1)
		tick(P, m, out, 900)
		fire(P, m, out, EV.RAIL_OUT, pix.rail.ramp_r, 1)
		t.eq(m.scores[1], PP.ramp + PP.ramp * 2)
		t.eq(said(out, P.SAY.COMBO), 1)
		tick(P, m, out, 400)
		fire(P, m, out, EV.ROLLOVER, pix.sensor.orbit_r, 1)
		fire(P, m, out, EV.ROLLOVER, pix.sensor.orbit_top, 1)
		t.eq(m.scores[1], PP.ramp * 3 + PP.orbit * 3)
		t.eq(Machine.lamps(P, m, {})[pix.lamp.combo_3], 1)
		t.eq(Machine.lamps(P, m, {})[pix.lamp.combo_4], 0)
		for _ = 1, 5 do
			fire(P, m, out, EV.RAIL_OUT, pix.rail.ramp_l, 1)
		end
		t.eq(s.combo, 5, "no higher than 5x")
		-- four seconds without one and the chain is gone
		tick(P, m, out, P.COMBO_TICKS + 1)
		local before = m.scores[1]
		fire(P, m, out, EV.RAIL_OUT, pix.rail.ramp_l, 1)
		t.eq(m.scores[1] - before, PP.ramp)
		t.eq(s.flow, 9)
	end)

	t.test(
		"SPACE SQUIRREL: F-U-E-L lights the locks; a lit pod keeps the ball and a new one comes to the plunger",
		function()
			local m, out = inPlay(P)
			local s = m.sheets[1]
			local b = m.phys.balls[1]
			for _, name in { "fuel_f", "fuel_u", "fuel_e" } do
				fire(P, m, out, EV.STANDUP, pix.target[name])
			end
			t.eq(m.scores[1], 3 * PP.fuel)
			t.eq(s.locksLit, 0)
			t.truthy(string.find(P.sheet.status(m, s), "F-U-E-L", 1, true))
			-- an unlit pod just kicks the ball back out
			fire(P, m, out, EV.SAUCER, pix.saucer.pod_1)
			t.eq(m.scores[1], 3 * PP.fuel + PP.pod)
			t.eq(s.locked, 0)
			fire(P, m, out, EV.STANDUP, pix.target.fuel_l)
			t.eq(s.locksLit, 1)
			t.eq(said(out, P.SAY.LOCKS_LIT), 1)
			t.eq(Machine.lamps(P, m, {})[pix.lamp.pod_1], 2)
			-- the ball falls into pod 2
			local pod = P.def.saucers[pix.saucer.pod_2]
			b.mode, b.ref, b.timer, b.x, b.y, b.asleep =
				Physics.HELD, pix.saucer.pod_2, pod.holdTicks, pod.x, pod.y, false
			fire(P, m, out, EV.SAUCER, pix.saucer.pod_2, 0, 1)
			t.eq(s.locked, 1)
			t.eq(b.timer, -1, "the pod keeps it")
			t.eq(m.queue, 1, "and the machine owes the plunger a ball")
			t.eq(said(out, P.SAY.LOCKED), 1)
			tick(P, m, out, Machine.FEED_TICKS + 5)
			t.eq(#m.phys.balls, 2)
			t.eq(m.phase, PHASE.PLAY)
			t.eq(b.mode, Physics.HELD, "still locked")
			t.eq(Machine.live(m), 1, "a locked ball is not a ball in play")
		end
	)

	t.test(
		"SPACE SQUIRREL: both pods full, a ramp starts the countdown: 3, 2, 1, LIFTOFF, three balls in play",
		function()
			local m, out = inPlay(P)
			local s = m.sheets[1]
			s.locksLit = 1
			-- two balls into the two pods
			for i, name in { "pod_1", "pod_2" } do
				local pod = P.def.saucers[pix.saucer[name]]
				local b = m.phys.balls[i]
				b.mode, b.ref, b.timer, b.x, b.y, b.asleep =
					Physics.HELD, pix.saucer[name], pod.holdTicks, pod.x, pod.y, false
				fire(P, m, out, EV.SAUCER, pix.saucer[name], 0, i)
				tick(P, m, out, Machine.FEED_TICKS + 5)
			end
			t.eq(s.locked, 2)
			t.eq(s.locksLit, 0)
			t.eq(said(out, P.SAY.READY), 1)
			t.eq(#m.phys.balls, 3)
			t.truthy(string.find(P.sheet.status(m, s), "RAMP", 1, true))
			-- an orbit does not start it; a ramp does
			fire(P, m, out, EV.ROLLOVER, pix.sensor.orbit_l, 1)
			fire(P, m, out, EV.ROLLOVER, pix.sensor.orbit_top, 1)
			t.eq(s.count, 0)
			fire(P, m, out, EV.RAIL_OUT, pix.rail.ramp_r, 1)
			t.eq(s.count, P.COUNT_TICKS)
			t.eq(P.COUNT_TICKS, 3 * 240)
			local counts = said(out, P.SAY.COUNT)
			t.eq(counts, 1)
			tick(P, m, out, 240)
			t.eq(said(out, P.SAY.COUNT), 2)
			t.truthy(string.find(P.sheet.status(m, s), "LIFTOFF IN 2", 1, true))
			tick(P, m, out, 240)
			t.eq(said(out, P.SAY.COUNT), 3)
			t.eq(s.multi, 0)
			tick(P, m, out, 241)
			t.eq(said(out, P.SAY.LIFTOFF), 1)
			t.eq(s.multi, 1)
			t.eq(s.locked, 0)
			-- both pods fire: three balls loose
			tick(P, m, out, 60)
			local loose = 0
			for _, b in m.phys.balls do
				if b.mode == Physics.FREE then
					loose += 1
				end
			end
			t.eq(loose, 3)
			t.eq(Machine.live(m), 3)
			-- every ramp and orbit is a jackpot now
			local before = m.scores[1]
			tick(P, m, out, P.COMBO_TICKS)
			fire(P, m, out, EV.RAIL_OUT, pix.rail.ramp_l, 1)
			t.eq(m.scores[1] - before, PP.jackpot)
			t.eq(said(out, P.SAY.JACKPOT), 1)
			t.eq(Machine.lamps(P, m, {})[pix.lamp.jackpot], 2)
			-- it ends when one ball is left
			m.phys.balls[3] = nil
			tick(P, m, out, 2)
			t.eq(s.multi, 1, "two balls: still multiball")
			m.phys.balls[2] = nil
			tick(P, m, out, 2)
			t.eq(s.multi, 0)
			t.eq(said(out, P.SAY.MULTIBALL_OVER), 1)
			t.eq(s.multiballs, 1)
		end
	)

	t.test(
		"SPACE SQUIRREL: locks are the player's across balls; the pods are emptied between balls and the plunger makes the three up",
		function()
			local m, out = inPlay(P, 2)
			local s = m.sheets[1]
			s.locksLit = 1
			local pod = P.def.saucers[pix.saucer.pod_1]
			local b = m.phys.balls[1]
			b.mode, b.ref, b.timer, b.x, b.y, b.asleep =
				Physics.HELD, pix.saucer.pod_1, pod.holdTicks, pod.x, pod.y, false
			fire(P, m, out, EV.SAUCER, pix.saucer.pod_1, 0, 1)
			t.eq(s.locked, 1)
			-- the served ball is lost: the ball is over, though one sits in a pod
			tick(P, m, out, Machine.FEED_TICKS + Machine.AUTO_TICKS + 300)
			for _, x in m.phys.balls do
				if x.mode == Physics.FREE then
					x.x, x.y, x.vx, x.vy, x.asleep = Layout.XC, 0.3, 0, -2, false
				end
			end
			for _ = 1, 60 do
				Machine.step(P, m, 0, out)
			end
			t.eq(m.phase, PHASE.BONUS)
			local _, mult = P.sheet.bonus(m, s)
			t.eq(mult, 2, "the bonus is times one more for every ball locked")
			for _ = 1, 3000 do
				Machine.step(P, m, 0, out)
				if m.phase == PHASE.PLAY then
					break
				end
			end
			t.eq(m.up, 2)
			t.eq(#m.phys.balls, 1, "the pod was emptied: player 2 starts with a clean table")
			t.eq(m.sheets[2].locked, 0, "and no locks of their own")
			t.eq(s.locked, 1, "player 1 keeps theirs")
			-- with two locks and the pods empty, LIFTOFF serves both from the plunger
			local m2, out2 = inPlay(P)
			local s2 = m2.sheets[1]
			s2.locked = 2
			fire(P, m2, out2, EV.RAIL_OUT, pix.rail.ramp_l, 1)
			tick(P, m2, out2, P.COUNT_TICKS + 1)
			t.eq(s2.multi, 1)
			t.eq(m2.queue, 2)
			t.eq(Machine.live(m2), 3)
		end
	)

	t.test(
		"PIN-R4 SPACE SQUIRREL: three orbits in one ball light the extra ball at the left pod; the dock is the skill shot",
		function()
			local m, out = inPlay(P)
			local s = m.sheets[1]
			for _ = 1, 3 do
				fire(P, m, out, EV.ROLLOVER, pix.sensor.orbit_l, 1)
				fire(P, m, out, EV.ROLLOVER, pix.sensor.orbit_top, 1)
			end
			t.eq(s.extraLit, 1)
			fire(P, m, out, EV.SAUCER, pix.saucer.pod_2)
			t.falsy(m.shootAgain, "the right pod is not it")
			fire(P, m, out, EV.SAUCER, pix.saucer.pod_1)
			t.truthy(m.shootAgain)
			local base, mult = P.sheet.bonus(m, s)
			t.eq(base, 3 * PP.bonusEach)
			t.eq(mult, 1)
			-- the dock
			local m2, out2 = inPlay(P)
			m2.skillLeft = 300
			t.eq(Machine.lamps(P, m2, {})[pix.lamp.dock], 2)
			fire(P, m2, out2, EV.ROLLOVER, pix.sensor.dock)
			t.eq(m2.scores[1], PP.docked)
			t.eq(said(out2, P.SAY.DOCKED), 1)
			fire(P, m2, out2, EV.ROLLOVER, pix.sensor.dock)
			t.eq(m2.scores[1], PP.docked + PP.dock)
		end
	)

	t.test(
		"SPACE SQUIRREL: the ball lost inside the countdown does not take the prize back: LIFTOFF at once",
		function()
			local m, out = inPlay(P)
			local s = m.sheets[1]
			s.locksLit = 1
			for i, name in { "pod_1", "pod_2" } do
				local pod = P.def.saucers[pix.saucer[name]]
				local b = m.phys.balls[i]
				b.mode, b.ref, b.timer, b.x, b.y, b.asleep =
					Physics.HELD, pix.saucer[name], pod.holdTicks, pod.x, pod.y, false
				fire(P, m, out, EV.SAUCER, pix.saucer[name], 0, i)
				tick(P, m, out, Machine.FEED_TICKS + 5)
			end
			t.eq(s.locked, 2)
			m.saveLeft, m.graceLeft = 0, 0
			fire(P, m, out, EV.RAIL_OUT, pix.rail.ramp_r, 1)
			t.eq(s.count, P.COUNT_TICKS)
			tick(P, m, out, 300)
			-- the one loose ball goes down the middle with the count at 2
			for _, b in m.phys.balls do
				if b.mode == Physics.FREE then
					b.x, b.y, b.vx, b.vy, b.asleep = Layout.XC, 0.3, 0, -2, false
				end
			end
			for _ = 1, 40 do
				Machine.step(P, m, 0, out)
			end
			t.eq(m.phase, PHASE.PLAY, "the ball is not over")
			t.eq(said(out, P.SAY.LIFTOFF), 1, "the rocket goes at once")
			t.eq(s.count, 0)
			t.eq(s.multi, 1)
			t.eq(s.multiballs, 1)
			t.eq(Machine.live(m), 3, "both pods fire and the plunger makes the three up")
			t.eq(m.queue, 1)
			-- LIFTOFF starts a ball save of its own: a ball lost in its first seconds comes back
			t.truthy(m.saveLeft > 0, "a ball save runs from LIFTOFF")
			t.eq(P.LIFTOFF_SAVE, 5 * 240)
			t.near(m.saveLeft, P.LIFTOFF_SAVE, 40)
			for _ = 1, 120 do
				Machine.step(P, m, 0, out)
			end
			local saves = 0
			for _, b in m.phys.balls do
				if b.mode == Physics.FREE and b.x < Layout.FIELD_X1 then
					b.x, b.y, b.vx, b.vy, b.asleep = Layout.XC, 0.3, 0, -2, false
					saves += 1
					break
				end
			end
			t.eq(saves, 1)
			for _ = 1, 40 do
				Machine.step(P, m, 0, out)
			end
			t.eq(said(out, Machine.SAY.BALL_SAVED), 1)
			t.eq(Machine.live(m), 3, "it is given back")
			-- the ordinary countdown ends in the same LIFTOFF with the same save
			local m2, out2 = inPlay(P)
			local s2 = m2.sheets[1]
			s2.locked = 2
			fire(P, m2, out2, EV.RAIL_OUT, pix.rail.ramp_l, 1)
			tick(P, m2, out2, P.COUNT_TICKS + 1)
			t.eq(s2.multi, 1)
			t.near(m2.saveLeft, P.LIFTOFF_SAVE, 2)
			-- a ball saved by the ordinary ball save is not lost, so the count simply runs on
			local m3, out3 = inPlay(P)
			local s3 = m3.sheets[1]
			s3.locked = 2
			fire(P, m3, out3, EV.RAIL_OUT, pix.rail.ramp_l, 1)
			m3.saveLeft = 2000
			local b3 = m3.phys.balls[1]
			b3.x, b3.y, b3.vx, b3.vy, b3.asleep = Layout.XC, 0.3, 0, -2, false
			for _ = 1, 40 do
				Machine.step(P, m3, 0, out3)
			end
			t.eq(s3.multi, 0)
			t.truthy(s3.count > 0, "still counting")
			t.eq(said(out3, P.SAY.LIFTOFF), 0)
		end
	)

	t.test(
		"PIN-R3 SPACE SQUIRREL: a tilt stops the countdown, and a dead ball in a lit pod is kicked out, not locked",
		function()
			-- the countdown
			local m, out = inPlay(P)
			local s = m.sheets[1]
			s.locked = 2
			fire(P, m, out, EV.RAIL_OUT, pix.rail.ramp_l, 1)
			t.eq(s.count, P.COUNT_TICKS)
			tiltNow(P, m, out)
			t.eq(s.count, 0, "no countdown on a tilted machine")
			table.clear(out)
			tick(P, m, out, P.COUNT_TICKS + 10)
			t.eq(s.multi, 0, "and no LIFTOFF into a dead multiball")
			t.eq(said(out, P.SAY.COUNT), 0)
			t.eq(said(out, P.SAY.LIFTOFF), 0)
			t.eq(s.locked, 2, "the locks the player has are still theirs for the next ball")
			-- the lit pod
			local m2, out2 = inPlay(P)
			local s2 = m2.sheets[1]
			s2.locksLit = 1
			tiltNow(P, m2, out2)
			table.clear(out2)
			local pod = P.def.saucers[pix.saucer.pod_1]
			local b = m2.phys.balls[1]
			-- (a pod is a scoop: its mouth is toward the flippers, so the dead ball is rolled up into it)
			b.x, b.y, b.vx, b.vy, b.asleep = pod.x, pod.y - 0.25, 0, 3, false
			local fell = false
			for _ = 1, 200 do
				Machine.step(P, m2, 0, out2)
				if b.mode == Physics.HELD then
					fell = true
					break
				end
			end
			t.truthy(fell, "the dead ball rolled into the pod")
			t.truthy(b.timer > 0, "the pod will kick it out")
			t.eq(s2.locked, 0, "no lock")
			t.eq(m2.queue, 0, "no new ball is served")
			t.eq(said(out2, P.SAY.LOCKED), 0)
			t.eq(jingles(out2), 0)
			for _ = 1, pod.holdTicks + 5 do
				Machine.step(P, m2, 0, out2)
			end
			t.eq(b.mode, Physics.FREE, "kicked out")
			t.eq(#m2.phys.balls, 1)
		end
	)

	t.test(
		"PIN-R3: on a tilted machine a dead ball does not knock letters down for the bank or put a lit extra ball out",
		function()
			-- ACORN: a dead ball fired into the bank
			local m, out = inPlay(A)
			local s = m.sheets[1]
			s.extraLit = 1
			tiltNow(A, m, out)
			local b = m.phys.balls[1]
			local hits = 0
			for _, name in { "acorn_c", "acorn_o", "acorn_r" } do
				local target = A.def.targets[aix.target[name]]
				local mx, my = (target.x1 + target.x2) / 2, (target.y1 + target.y2) / 2
				b.x, b.y, b.vx, b.vy, b.asleep = mx + 0.2, my - 0.14, -4, 2.8, false
				for _ = 1, 40 do
					Machine.step(A, m, 0, out)
				end
				if m.phys.drop[aix.target[name]] then
					hits += 1
				end
			end
			t.truthy(hits >= 2, `the dead ball knocked {hits} targets over`)
			t.eq(s.made, 0, "nothing was made")
			t.eq(s.bank, 0, "no letter is remembered")
			-- the lit extra-ball target
			local oak = A.def.targets[aix.target.oak_r]
			b.x, b.y, b.vx, b.vy, b.asleep = (oak.x1 + oak.x2) / 2 - 0.1, (oak.y1 + oak.y2) / 2 - 0.1, 3, 3, false
			for _ = 1, 30 do
				Machine.step(A, m, 0, out)
			end
			t.eq(s.extraLit, 1, "the light is still there for the next ball")
			t.falsy(m.shootAgain)
			-- SPICY: the bite
			local m2, out2 = inPlay(S)
			local s2 = m2.sheets[1]
			s2.extraLit = 1
			s2.biteLit = 1
			tiltNow(S, m2, out2)
			local bite = S.def.saucers[six.saucer.bite]
			local b2 = m2.phys.balls[1]
			b2.x, b2.y, b2.vx, b2.vy, b2.asleep = bite.x, bite.y - 0.2, 0, 2, false
			local held = false
			for _ = 1, 120 do
				Machine.step(S, m2, 0, out2)
				held = held or b2.mode == Physics.HELD
			end
			t.truthy(held, "the dead ball went into the bite")
			t.eq(s2.extraLit, 1)
			t.eq(s2.biteLit, 1)
			t.falsy(m2.shootAgain)
		end
	)

	t.test(
		"PIN-R5, C13: a seat that leaves with an extra ball owed: the turn is the next seat still present",
		function()
			for _, when in { "in mid-ball", "during the bonus count" } do
				local rules = Rules.forTable("pinball_space")
				local g = Minigame.start(rules, 2, 5)
				local turn = rules.turn :: (any) -> number?
				local gone = rules.gone :: (any, number) -> ()
				local r = Rules.replay(g.state)
				assert(r, "a replay")
				t.truthy(Minigame.input(g, 1, "seg", { { 0, 600, 1, BTN.PLUNGE, 250, 0 } }))
				t.truthy(Machine.extraBall(r.m, {}), when)
				if when == "during the bonus count" then
					r.m.saveLeft, r.m.graceLeft = 0, 0
					for _, b in r.m.phys.balls do
						b.x, b.y, b.vx, b.vy, b.asleep = Layout.XC, 0.3, 0, -2, false
					end
					t.truthy(Minigame.input(g, 1, "seg", { { 600, 660 } }))
					t.eq(r.m.phase, PHASE.BONUS)
				end
				gone(g.state, 1)
				t.eq(turn(g.state), 2, when)
				t.eq(r.m.up, 2, when)
				t.falsy(r.m.forfeit, when)
				t.eq(r.m.ballTicks, 0, `{when}: seat 2's fresh ball stands on the plunger`)
				local ok, why = Minigame.input(g, 2, "seg", { { r.tick, r.tick + 24 } })
				t.truthy(ok, `{when}: seat 2's first segment is taken ({why})`)
			end
		end
	)

	t.test("PIN-R6: the three score scales are far apart: tens, thousands, tens of thousands", function()
		t.truthy(AP.bumper * 20 <= SP.bumper)
		t.truthy(SP.bumper < PP.bumper)
		t.truthy(AP.bank * 4 < SP.wire and SP.wire * 3 < PP.ramp)
		t.truthy(PP.jackpot >= 100000)
	end)

	-- -------------------------------------------------------------------------------------- the Minigame contract
	t.test("PIN-R5: each machine is a Minigame: free, four seats, the log in and the server's thump", function()
		t.deepEq(Rules.GAMES, { "pinball_acorn", "pinball_rodent", "pinball_space" })
		for _, id in Rules.GAMES do
			local rules = Rules.forTable(id)
			local ok, why = Minigame.check(rules)
			t.truthy(ok, why)
			t.eq(rules.def.game, id)
			t.eq(rules.def.money, "none")
			t.eq(rules.def.seats, 4)
			t.eq(rules.def.authority, "client_replay")
			t.truthy(rules.verbs.seg)
			t.truthy(rules.verbs.log, "the segment as the wire carries it")
			t.truthy(rules.serverVerbs and rules.serverVerbs.thump)
			t.eq(type(rules.gone), "function", "the Session's word for a seat that has left")
			t.eq(Rules.forTable(id), rules, "one rules table per machine")
		end
		t.eq(Rules.forTable("pinball_acorn").def.title, "ACORN ATTACK")
	end)

	t.test(
		'PIN-R5: the registry\'s one game: "pinball", switched on by its station as acorn, rodent or space',
		function()
			local game = Rules.game
			t.eq(Rules.GAME, "pinball")
			t.eq(game.def.game, "pinball")
			t.eq(game.def.money, "none")
			t.eq(game.def.seats, 4)
			t.eq(game.def.authority, "client_replay")
			-- it is what the registry asks of a built game (Minigames/Games.check), turn-based, four verbs deep
			local spec = table.clone(PinballSpec) :: any
			spec.soon = nil
			spec.rules = game
			spec.flow = "turns"
			spec.verbs = Rules.CLIENT_VERBS
			local ok, why = Games.check(spec)
			t.truthy(ok, why)
			t.deepEq(Rules.CLIENT_VERBS, { "log" })
			for _, verb in Rules.CLIENT_VERBS do
				t.truthy(game.verbs[verb])
				t.falsy(game.serverVerbs and game.serverVerbs[verb], "a client's verb is not a server's")
				t.truthy(#verb <= 24)
			end
			for _, verb in { "machine", "thump", "retire" } do
				t.truthy(game.serverVerbs and game.serverVerbs[verb], `{verb} is the server's`)
			end
			-- every station of the alley's games room names a machine there is
			local stations = PinballSpec.stations({ bowling_alley = { x = 0, z = 0, floorY = 0, yaw = 0 } })
			t.eq(#stations, 3)
			local titles = {}
			for _, st in stations do
				local id = Tables.forVariant(st.variant)
				assert(id, `no machine for variant {st.variant}`)
				table.insert(titles, Tables.need(id).title)
			end
			t.deepEq(titles, { "ACORN ATTACK", "SPICY RODENT", "SPACE SQUIRREL" })
			t.eq(Tables.forVariant("pinball_space"), "pinball_space", "a table id is taken as it is")
			t.eq(Tables.forVariant("riverside"), nil)
			t.eq(Tables.forVariant(nil), nil)

			-- switched off until the station says which machine it is
			local g = Minigame.start(game, 2, 5)
			local turn = game.turn :: (any) -> number?
			local view = game.view :: (any) -> { [string]: any }
			t.eq(turn(g.state), 1)
			t.eq(view(g.state).phase, "off")
			t.eq(Minigame.result(g), nil)
			t.eq(Rules.replay(g.state), nil)
			local refused, words = Minigame.input(g, 1, "log", { 0, 24, "" })
			t.falsy(refused)
			t.eq(words, "the machine is not switched on")
			t.falsy(Minigame.input(g, 1, "machine", { "riverside" }), "no such machine")
			t.truthy(Minigame.input(g, 1, "machine", { "rodent" }))
			t.falsy(Minigame.input(g, 1, "machine", { "space" }), "it is one machine for the whole game")
			local v = view(g.state)
			t.eq(v.game, "pinball")
			t.eq(v.table, "pinball_rodent")
			t.eq(v.variant, "rodent")
			t.eq(v.title, "SPICY RODENT")
			t.eq(v.phase, "play")
			t.eq(v.up, 1)
			local r = Rules.replay(g.state)
			assert(r, "the replay is there once the machine is on")
			t.eq(r.id, "pinball_rodent")
			local own = Rules.forTable("pinball_acorn").init(1, 1)
			t.eq(Rules.replay(own), own, "a machine's own state is its replay")

			-- a whole two-player game through the wire's three arguments, checked against a replay fed directly
			local tbl = Tables.need("pinball_rodent")
			local direct = Replay.new("pinball_rodent", 5, 2)
			local live = Replay.new("pinball_rodent", 5, 2)
			local rec = Replay.recorder(live)
			local bots = { Bot.new(1, 11), Bot.new(2, 12) }
			local guard = 0
			while not Replay.over(live) do
				local seat = live.m.up
				local seg = Replay.live(live, rec, Bot.step(bots[seat], tbl, live.m))
				if seg then
					t.eq(turn(g.state), seat, "the turn is the player whose ball is up")
					local from, to, packed = InputLog.pack(seg)
					local other = 3 - seat
					t.falsy(Minigame.input(g, other, "log", { from, to, packed }), "not their ball")
					local took, why2 = Minigame.input(g, seat, "log", { from, to, packed })
					t.truthy(took, why2)
					t.truthy(Replay.feed(direct, seat, seg))
				end
				guard += 1
				assert(guard < 240 * 3600, "the game did not end")
			end
			t.eq(turn(g.state), nil, "the game is over: nobody's turn")
			local result = Minigame.result(g)
			assert(result, "a finished game has a result")
			t.eq(result.scores[1], direct.m.scores[1])
			t.eq(result.scores[2], direct.m.scores[2])
			t.eq(result.scores[1], live.m.scores[1], "the score of record is the player's own game")
			t.eq(view(g.state).phase, "over")
			t.falsy(Minigame.input(g, 1, "log", { live.tick, live.tick + 24, "" }), "the game is over")
			-- what is not a segment is refused in words, never an error
			local g2 = Minigame.start(game, 1, 1)
			t.truthy(Minigame.input(g2, 1, "machine", { "pinball_acorn" }))
			t.falsy(Minigame.input(g2, 1, "log", { 0, 24 }))
			t.falsy(Minigame.input(g2, 1, "log", { 0, 24, 7 }))
			t.falsy(Minigame.input(g2, 1, "log", { 0, 24, "!!!!" }))
			t.falsy(Minigame.input(g2, 1, "log", { 3, 24, "" }), "out of order")
			t.falsy(Minigame.input(g2, 1, "log", {}))
			t.truthy(Minigame.input(g2, 1, "log", { 0, 24, "" }))
		end
	)

	t.test("PIN-R5, C13: a seat the Session says has gone is retired: the game goes on without it", function()
		local game = Rules.game
		local gone = game.gone :: (any, number) -> ()
		local turn = game.turn :: (any) -> number?
		local skip = game.skipTurn :: (any) -> ()
		-- before the machine is on, a seat going and a turn skipped are nothing to the rules (and no error)
		local off = Minigame.start(game, 2, 3)
		gone(off.state, 2)
		skip(off.state)
		t.eq(turn(off.state), 1)
		local g = Minigame.start(game, 3, 3)
		t.truthy(Minigame.input(g, 1, "machine", { "acorn" }))
		t.truthy(Minigame.input(g, 1, "log", { 0, 24, "" }))
		gone(g.state, 1)
		t.eq(turn(g.state), 2, "their ball was played out dead and the next player is up")
		local r = Rules.replay(g.state)
		assert(r, "the machine is on")
		t.truthy(r.m.gone[1])
		skip(g.state)
		t.eq(turn(g.state), 3, "a skipped turn is a ball played out dead")
		skip(g.state)
		t.eq(turn(g.state), 2, "seat 1 is passed over")
		-- the last two go as well: the game ends by itself, every score kept
		gone(g.state, 2)
		gone(g.state, 3)
		t.eq(turn(g.state), nil)
		local result = Minigame.result(g)
		assert(result, "a finished game has a result")
		t.eq(result.done, true)
		t.eq(#result.scores, 3)
	end)

	t.test(
		"PIN-R5: the turn is the player whose ball is up; only they may send a log; a skipped turn is a ball played out dead",
		function()
			local rules = Rules.forTable("pinball_rodent")
			local g = Minigame.start(rules, 2, 5)
			local turn = rules.turn :: (any) -> number?
			local skip = rules.skipTurn :: (any) -> ()
			local view = rules.view :: (any) -> { [string]: any }
			t.eq(turn(g.state), 1)
			t.eq(Minigame.result(g), nil)
			local ok, why = Minigame.input(g, 2, "seg", { { 0, 48 } })
			t.falsy(ok)
			t.eq(why, "not your ball")
			t.truthy(Minigame.input(g, 1, "seg", { { 0, 48 } }))
			ok, why = Minigame.input(g, 1, "seg", { { 0, 48 } })
			t.falsy(ok, "the same segment twice is refused")
			t.eq(why, "out of order")
			t.falsy(Minigame.input(g, 1, "seg", {}))
			t.falsy(Minigame.input(g, 1, "seg", { "nonsense" }))
			t.falsy(Minigame.input(g, 1, "flip", {}), "not a verb")
			local v = view(g.state)
			t.eq(v.game, "pinball_rodent")
			t.eq(v.title, "SPICY RODENT")
			t.eq(v.freePlay, true)
			t.eq(v.phase, "play")
			t.eq(v.up, 1)
			t.eq(v.ball, 1)
			t.eq(v.balls, 3)
			t.eq(#v.players, 2)
			t.eq(v.players[1].score, 0)
			t.truthy(#v.status > 0)
			t.eq(v.tick, 48)
			-- an idle turn is played out as the game's miss, six times over: the game ends, announced once
			local order = {}
			for _ = 1, 6 do
				table.insert(order, turn(g.state))
				skip(g.state)
			end
			t.deepEq(order, { 1, 2, 1, 2, 1, 2 })
			t.eq(turn(g.state), nil)
			local r = Minigame.result(g)
			assert(r, "a result")
			t.truthy(r.done)
			t.eq(#r.stats, 2)
			t.eq(r.stats[1].balls, 3)
			t.eq(r.suspect, false)
			v = view(g.state)
			t.eq(v.phase, "over")
			t.eq(v.up, nil)
			t.eq(v.status, "GAME OVER")
			t.eq(v.say, "GAME OVER")
			ok, why = Minigame.input(g, 1, "seg", { { v.tick, v.tick + 10 } })
			t.falsy(ok)
			skip(g.state)
			t.eq(view(g.state).tick, v.tick, "skipping a finished game does nothing")
		end
	)

	t.test("PIN-R5: the result has every score and the winner; a tie has no winner", function()
		local rules = Rules.forTable("pinball_acorn")
		local g = Minigame.start(rules, 3, 1)
		local skip = rules.skipTurn :: (any) -> ()
		g.state.m.scores[2] = 5000
		for _ = 1, 9 do
			skip(g.state)
		end
		local r = Minigame.result(g)
		assert(r, "a result")
		t.truthy(r.scores[2] >= 5000)
		t.eq(r.winner, 2)
		local g2 = Minigame.start(rules, 2, 1)
		for _ = 1, 6 do
			skip(g2.state)
		end
		g2.state.m.scores[1], g2.state.m.scores[2] = 700, 700
		local r2 = Minigame.result(g2)
		assert(r2, "a result")
		t.eq(r2.winner, nil)
	end)
end
