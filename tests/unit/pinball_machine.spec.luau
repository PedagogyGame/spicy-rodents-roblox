--!strict
-- Minigames/Pinball/Machine: what a real machine's board does round the physics, line by line against the
-- checklist:
--   PIN-R1 three balls a game; PIN-P5 the plunger is analogue (hold to pull, the strength is the launch, too
--   soft comes back); PIN-R2 a ball save from the moment the ball enters the playfield, and the end-of-ball
--   bonus counted out; PIN-R3 nudge and tilt (two warnings, the third tilts: flippers dead, ball and bonus
--   lost) and the thump on the glass that can warn but never tilt; PIN-R4 one extra ball at most, no credits,
--   no replay, no match number; PIN-R5 one to four players alternate ball by ball; a still ball is found by a
--   ball search; an abandoned ball is played out dead; and the state is plain data with nothing hidden.
local Layout = require("@shared/Minigames/Pinball/Layout")
local Machine = require("@shared/Minigames/Pinball/Machine")
local Physics = require("@shared/Minigames/Pinball/Physics")
local Tables = require("@shared/Minigames/Pinball/Tables")
local Test = require("../lib/Test")

local BTN, CUE, SAY, PHASE = Machine.BTN, Machine.CUE, Machine.SAY, Machine.PHASE
local acorn = Tables.need("pinball_acorn")

local function run(tbl: Machine.Table, m: Machine.State, buttons: number, ticks: number, out: { number }?)
	local sink = out or {}
	for _ = 1, ticks do
		Machine.step(tbl, m, buttons, sink)
	end
end

local function count(out: { number }, cue: number, a: number?): number
	local n = 0
	for i = 1, #out, 3 do
		if out[i] == cue and (a == nil or out[i + 1] == a) then
			n += 1
		end
	end
	return n
end

-- hold the plunger for a share of its full pull, let go, and wait until the ball is out of the lane
local function launch(tbl: Machine.Table, m: Machine.State, pull: number, out: { number }?)
	run(tbl, m, BTN.PLUNGE, math.floor(pull * tbl.def.plunger.pullTicks + 0.5), out)
	for _ = 1, 720 do
		Machine.step(tbl, m, 0, out or {})
		if m.launched then
			return
		end
	end
end

-- put every loose ball where it is lost: between the flippers, on its way down
local function lose(m: Machine.State)
	for _, b in m.phys.balls do
		if b.mode == Physics.FREE then
			b.x, b.y, b.vx, b.vy = Layout.XC, 0.3, 0, -2
			b.asleep = false
		end
	end
end

-- hold every loose ball still in the open middle of the table while `ticks` go by with these buttons held
local function park(tbl: Machine.Table, m: Machine.State, buttons: number, ticks: number, out: { number }?)
	for _ = 1, ticks do
		for _, b in m.phys.balls do
			if b.mode == Physics.FREE and b.x < Layout.FIELD_X1 then
				b.x, b.y, b.vx, b.vy, b.asleep = Layout.XC, 2.0, 0, 0, true
			end
		end
		Machine.step(tbl, m, buttons, out or {})
	end
end

-- play a ball to its end without the ball save: returns when the next ball is up or the game is over
local function loseBall(tbl: Machine.Table, m: Machine.State, out: { number }?)
	launch(tbl, m, 0.9, out)
	m.saveLeft, m.graceLeft = 0, 0
	lose(m)
	for _ = 1, 4000 do
		Machine.step(tbl, m, 0, out or {})
		if m.phase == PHASE.OVER or (m.phase == PHASE.PLAY and m.ballTicks == 0) then
			return
		end
	end
	error("the ball did not end")
end

local function digest(v: any): string
	if type(v) ~= "table" then
		return if type(v) == "number" then string.format("%.17g", v) else tostring(v)
	end
	local keys = {}
	for k in v do
		table.insert(keys, k)
	end
	table.sort(keys, function(a, b)
		return tostring(a) < tostring(b)
	end)
	local parts = {}
	for _, k in keys do
		table.insert(parts, tostring(k) .. "=" .. digest(v[k]))
	end
	return "{" .. table.concat(parts, ",") .. "}"
end

return function(t: Test.T)
	t.test("PIN-R1: three balls a game; the game is over once, and then nothing moves", function()
		for _, id in Tables.IDS do
			local tbl = Tables.need(id)
			local m = Machine.new(tbl, 1, 1)
			local out: { number } = {}
			t.eq(Machine.BALLS, 3)
			t.eq(m.phase, PHASE.PLAY)
			t.eq(m.ball, 1)
			t.eq(#m.phys.balls, 1, "a ball is on the plunger")
			for ball = 1, 3 do
				t.eq(m.ball, ball)
				t.eq(m.phase, PHASE.PLAY)
				loseBall(tbl, m, out)
			end
			t.eq(m.phase, PHASE.OVER)
			t.eq(count(out, CUE.BALL_START), 2, "two more balls came up after the first")
			t.eq(count(out, CUE.BALL_END), 3)
			t.eq(count(out, CUE.GAME_OVER), 1, "the end is announced exactly once")
			t.eq(m.say, SAY.GAME_OVER)
			local before = digest(m)
			table.clear(out)
			run(tbl, m, BTN.LEFT + BTN.PLUNGE, 500, out)
			t.eq(#out, 0, "nothing more happens")
			t.eq(digest(m), before)
			t.eq(m.stats[1].balls, 3)
		end
	end)

	t.test("PIN-P5: the plunger is analogue: the longer the pull the harder the launch, up to the full pull", function()
		local p = acorn.def.plunger
		local function speedAfter(pullTicks: number): number
			local m = Machine.new(acorn, 1, 1)
			run(acorn, m, 0, 30)
			run(acorn, m, BTN.PLUNGE, pullTicks)
			t.near(m.pull, math.min(pullTicks, p.pullTicks), 0, "the pull is on the state for the drawer")
			Machine.step(acorn, m, 0, {})
			return m.phys.balls[1].vy
		end
		local soft, half, full, over =
			speedAfter(20), speedAfter(p.pullTicks // 2), speedAfter(p.pullTicks), speedAfter(p.pullTicks + 200)
		t.truthy(soft < half and half < full, `{soft} < {half} < {full}`)
		t.near(full, p.vMax, 0.05)
		t.near(over, p.vMax, 0.05, "holding longer than a full pull adds nothing")
		t.near(half, (p.vMin + p.vMax) / 2, 0.08)
		-- nothing happens until it is let go, and no pull is no launch
		local m = Machine.new(acorn, 1, 1)
		run(acorn, m, BTN.PLUNGE, 100)
		t.near(m.phys.balls[1].y, p.y, 0.01, "still on the plunger while held")
		local idle = Machine.new(acorn, 1, 1)
		run(acorn, idle, 0, 500)
		t.near(idle.phys.balls[1].y, p.y, 0.01, "an untouched ball waits on the plunger")
		t.falsy(idle.launched)
	end)

	t.test("PIN-P5: a plunge too soft to clear the lane comes back to the plunger and can be plunged again", function()
		for _, id in Tables.IDS do
			local tbl = Tables.need(id)
			local m = Machine.new(tbl, 1, 1)
			local out: { number } = {}
			run(tbl, m, 0, 20)
			run(tbl, m, BTN.PLUNGE, 2, out)
			run(tbl, m, 0, 1, out)
			t.eq(count(out, CUE.PLUNGE), 1)
			local top = 0
			for _ = 1, 240 * 6 do
				Machine.step(tbl, m, 0, out)
				top = math.max(top, m.phys.balls[1].y)
			end
			t.truthy(top > 2.5, `{id}: it went well up the lane ({top})`)
			t.falsy(m.launched, `{id}: but never reached the playfield`)
			t.near(m.phys.balls[1].y, tbl.def.plunger.y, 0.01, "back on the plunger")
			t.eq(m.saveLeft, 0, "the ball save has not started")
			launch(tbl, m, 1, out)
			t.truthy(m.launched, `{id}: a full plunge gets out`)
		end
	end)

	t.test(
		"PIN-R2: the ball save runs from the moment the ball enters the playfield, however long it waited",
		function()
			for _, id in Tables.IDS do
				local tbl = Tables.need(id)
				local m = Machine.new(tbl, 1, 1)
				run(tbl, m, 0, 240 * 20)
				t.eq(m.saveLeft, 0)
				launch(tbl, m, 0.9)
				t.truthy(m.saveLeft > tbl.sheet.saveTicks - 5, "it starts as the ball leaves the lane")
				local seconds = tbl.sheet.saveTicks / 240
				t.truthy(seconds >= 8 and seconds <= 10, `{id}: {seconds} s`)
				local lamps = Machine.lamps(tbl, m, {})
				t.eq(lamps[tbl.ix.lamp.shoot_again], 2, "the shoot-again lamp flashes while it runs")
			end
		end
	)

	t.test(
		"PIN-R2: a ball lost inside the ball save comes back: said on the display, launched by the machine",
		function()
			local m = Machine.new(acorn, 1, 1)
			local out: { number } = {}
			launch(acorn, m, 0.9, out)
			run(acorn, m, 0, 240, out)
			local score = m.scores[1]
			lose(m)
			run(acorn, m, 0, 60, out)
			t.eq(count(out, CUE.DRAIN), 1)
			t.eq(count(out, CUE.SAVE), 1)
			t.eq(m.say, SAY.BALL_SAVED)
			t.eq(Machine.TEXT[m.say], "BALL SAVED")
			t.eq(m.phase, PHASE.PLAY, "the ball is not over")
			t.eq(m.ball, 1)
			t.eq(m.queue, 1, "the machine owes the plunger a ball")
			t.eq(#m.phys.balls, 0)
			-- it comes up, and the machine launches it without the player
			run(acorn, m, 0, Machine.FEED_TICKS, out)
			t.eq(#m.phys.balls, 1)
			t.near(m.phys.balls[1].y, acorn.def.plunger.y, 0.01)
			table.clear(out)
			run(acorn, m, 0, Machine.AUTO_TICKS + 2, out)
			t.eq(count(out, CUE.PLUNGE), 1, "auto-launched")
			t.truthy(m.phys.balls[1].vy > acorn.def.plunger.vMin)
			t.truthy(m.scores[1] >= score)
			t.eq(count(out, CUE.BALL_END), 0)
		end
	)

	t.test("PIN-R2: after the ball save (and its short grace) a drain ends the ball", function()
		local m = Machine.new(acorn, 1, 1)
		local out: { number } = {}
		launch(acorn, m, 0.9, out)
		-- the ball is kept safe while the time runs
		park(acorn, m, BTN.LEFT, acorn.sheet.saveTicks - 10, out)
		t.truthy(m.saveLeft > 0, "still on")
		park(acorn, m, BTN.LEFT, 12, out)
		t.eq(m.saveLeft, 0)
		t.truthy(m.graceLeft > 0, "the lamp is out but a drain right now is still forgiven")
		t.eq(Machine.lamps(acorn, m, {})[acorn.ix.lamp.shoot_again], 0)
		park(acorn, m, BTN.LEFT, Machine.SAVE_GRACE + 2, out)
		t.eq(m.graceLeft, 0)
		lose(m)
		run(acorn, m, 0, 60, out)
		t.eq(count(out, CUE.SAVE), 0)
		t.eq(count(out, CUE.BALL_END), 1)
		t.eq(m.phase, PHASE.BONUS)
	end)

	t.test("PIN-R2: the end-of-ball bonus is counted out step by step with its multiplier", function()
		local m = Machine.new(acorn, 1, 1)
		local out: { number } = {}
		launch(acorn, m, 0.9, out)
		m.saveLeft, m.graceLeft = 0, 0
		-- seven targets and lanes made on this ball, two acorns in the hoard, the 3x lit
		local sheet = m.sheets[1]
		sheet.made, sheet.hoard, sheet.mult = 7, 2, 3
		local base, mult = acorn.sheet.bonus(m, sheet)
		t.eq(base, 7 * acorn.POINTS.bonusMade + 2 * acorn.POINTS.bonusAcorn)
		t.eq(mult, 3)
		local before = m.scores[1]
		lose(m)
		table.clear(out)
		run(acorn, m, 0, 40, out)
		t.eq(m.phase, PHASE.BONUS)
		t.eq(m.bonusBase, base)
		t.eq(m.bonusMult, 3)
		t.eq(m.say, SAY.BONUS)
		t.eq(m.sayValue, base * 3, "the display shows the bonus total")
		-- counted out: the score climbs in steps, each one a tick of the counter
		local seen: { number } = {}
		for _ = 1, 2000 do
			Machine.step(acorn, m, 0, out)
			if seen[#seen] ~= m.scores[1] then
				table.insert(seen, m.scores[1])
			end
			if m.phase ~= PHASE.BONUS then
				break
			end
		end
		t.eq(m.scores[1], before + base * 3, "all of it, exactly")
		t.truthy(#seen >= 8, `in steps ({#seen})`)
		t.eq(count(out, CUE.BONUS_TICK), #seen - 1 + (if seen[1] == before then 0 else 1))
		t.eq(m.stats[1].bestBonus, base * 3)
		t.eq(m.phase, PHASE.PLAY, "then the next ball comes up")
		t.eq(m.ball, 2)
	end)

	t.test("PIN-R3: a nudge shoves the ball; nudges with time between them never warn", function()
		local m = Machine.new(acorn, 1, 1)
		local out: { number } = {}
		launch(acorn, m, 0.9, out)
		local b = m.phys.balls[1]
		b.x, b.y, b.vx, b.vy = Layout.XC, 2.0, 0, 0
		Machine.step(acorn, m, BTN.NUDGE_L, out)
		t.near(b.vx, Machine.NUDGE_SIDE, 0.05, "a nudge from the left sends the ball right")
		b.x, b.y, b.vx, b.vy = Layout.XC, 2.0, 0, 0
		run(acorn, m, 0, 5, out)
		Machine.step(acorn, m, BTN.NUDGE_R, out)
		t.truthy(b.vx > -0.1, "pressed again at once it is the same shove (key bounce)")
		for i = 1, 6 do
			b.x, b.y, b.vx, b.vy = Layout.XC, 2.0, 0, 0
			run(acorn, m, 0, 420, out)
			Machine.step(
				acorn,
				m,
				if i % 3 == 0 then BTN.NUDGE_UP elseif i % 2 == 0 then BTN.NUDGE_R else BTN.NUDGE_L,
				out
			)
		end
		t.eq(m.warnings, 0)
		t.falsy(m.tilted)
		t.eq(count(out, CUE.TILT_WARN), 0)
		t.truthy(count(out, CUE.NUDGE) >= 7)
	end)

	t.test("PIN-R3: two warnings, the third tilts: flippers dead, the ball and its bonus lost", function()
		local m = Machine.new(acorn, 1, 1)
		local out: { number } = {}
		launch(acorn, m, 0.9, out)
		local b = m.phys.balls[1]
		m.sheets[1].made = 5 -- a bonus is waiting
		local function shove()
			b.x, b.y, b.vx, b.vy, b.asleep = Layout.XC, 2.4, 0, 0, false
			Machine.step(acorn, m, BTN.NUDGE_L, out)
			run(acorn, m, 0, Machine.NUDGE_COOL + 4, out)
		end
		shove()
		t.eq(m.warnings, 0, "one shove is free")
		shove()
		t.eq(m.warnings, 1)
		t.eq(m.say, SAY.TILT_WARNING)
		t.falsy(m.tilted)
		shove()
		t.eq(m.warnings, 2)
		t.eq(Machine.WARNINGS, 2)
		t.falsy(m.tilted)
		t.eq(count(out, CUE.TILT_WARN), 2)
		local score = m.scores[1]
		shove()
		t.truthy(m.tilted, "the third tilts")
		t.eq(count(out, CUE.TILT), 1)
		t.eq(m.say, SAY.TILT)
		t.truthy(m.phys.dead)
		t.eq(m.saveLeft, 0, "no ball save")
		-- the flippers are dead and nothing scores
		run(acorn, m, BTN.LEFT + BTN.RIGHT, 60, out)
		t.eq(m.phys.fa[1], acorn.c.frest[1])
		t.eq(m.phys.fa[2], acorn.c.frest[2])
		Machine.add(m, 1000)
		t.eq(m.scores[1], score, "a tilted machine scores nothing")
		t.falsy(Machine.extraBall(m, out), "and gives nothing")
		-- the ball drains by itself; the bonus is lost
		table.clear(out)
		for _ = 1, 240 * 30 do
			Machine.step(acorn, m, BTN.LEFT, out)
			if m.phase ~= PHASE.PLAY then
				break
			end
		end
		t.eq(m.phase, PHASE.BONUS)
		t.eq(count(out, CUE.SAVE), 0)
		t.eq(m.bonusLeft, 0)
		t.eq(m.bonusBase, 0)
		run(acorn, m, 0, Machine.BONUS_HOLD + Machine.BONUS_STEP_TICKS + 5, out)
		t.eq(m.scores[1], score)
		-- the next ball is a fresh start
		t.eq(m.phase, PHASE.PLAY)
		t.eq(m.ball, 2)
		t.falsy(m.tilted)
		t.falsy(m.phys.dead)
		t.eq(m.warnings, 0)
		run(acorn, m, BTN.LEFT, 60, out)
		t.eq(m.phys.fa[1], acorn.c.fup[1], "the flippers are alive again")
	end)

	t.test(
		"PIN-R3: nudging with no ball out on the playfield does nothing (the ball on the plunger cannot be tilted away)",
		function()
			local m = Machine.new(acorn, 1, 1)
			local out: { number } = {}
			for _ = 1, 8 do
				Machine.step(acorn, m, BTN.NUDGE_L, out)
				run(acorn, m, 0, Machine.NUDGE_COOL + 2, out)
			end
			t.eq(m.warnings, 0)
			t.falsy(m.tilted)
			t.near(m.phys.balls[1].y, acorn.def.plunger.y, 0.01)
		end
	)

	t.test("squirrel: a thump on the glass is one nudge that can warn but never tilt", function()
		local m = Machine.new(acorn, 1, 1)
		local out: { number } = {}
		launch(acorn, m, 0.9, out)
		local b = m.phys.balls[1]
		b.x, b.y, b.vx, b.vy = Layout.XC, 2.4, 0, 0
		Machine.step(acorn, m, BTN.THUMP, out)
		t.truthy(math.abs(b.vx) > 0.2, "the ball felt it")
		t.eq(m.say, SAY.THUMP)
		t.eq(Machine.TEXT[SAY.THUMP], "SOMETHING THUMPED THE GLASS!")
		t.eq(m.warnings, 0)
		t.near(m.bob, Machine.THUMP_BOB, 1e-9, "half a nudge of swing on the tilt bob")
		t.truthy(Machine.THUMP_BOB <= 0.5)
		-- on top of the player's own shoving it can be the swing that warns: the first warning, never the second
		local function shoved(warnings: number): Machine.State
			local s = Machine.new(acorn, 1, 1)
			launch(acorn, s, 0.9, out)
			park(acorn, s, BTN.NUDGE_L, 1, out)
			park(acorn, s, 0, 20, out)
			s.warnings = warnings
			t.truthy(s.bob + Machine.THUMP_BOB > Machine.BOB_LIMIT)
			park(acorn, s, BTN.THUMP, 1, out)
			return s
		end
		local first = shoved(0)
		t.eq(first.warnings, 1, "a thump while the bob is swinging can warn")
		t.falsy(first.tilted)
		local second = shoved(1)
		t.eq(second.warnings, 1, "it never spends the last warning")
		t.falsy(second.tilted)
		-- and with both warnings already spent by the player, a thump still does not tilt
		local spent = shoved(Machine.WARNINGS)
		t.eq(spent.warnings, Machine.WARNINGS)
		t.falsy(spent.tilted)
		t.eq(count(out, CUE.TILT), 0)
	end)

	t.test("PIN-R4: one extra ball at most per game; it is the same player's ball again", function()
		local m = Machine.new(acorn, 1, 2)
		local out: { number } = {}
		launch(acorn, m, 0.9, out)
		t.eq(Machine.EXTRA_BALLS, 1, "one in the whole game, whoever earns it")
		-- player 2's sheet has its extra ball lit from an earlier ball
		m.sheets[2].extraLit = 1
		t.truthy(Machine.extraOpen(m))
		t.truthy(Machine.extraBall(m, out))
		t.falsy(Machine.extraOpen(m))
		t.falsy(Machine.extraBall(m, out), "never a second one")
		t.eq(m.extras[1], 1)
		t.eq(m.sheets[2].extraLit, 0, "every player's extra-ball light goes out once it is taken")
		t.eq(count(out, CUE.EXTRA_BALL), 1)
		t.eq(Machine.lamps(acorn, m, {})[acorn.ix.lamp.shoot_again] > 0, true)
		m.saveLeft, m.graceLeft = 0, 0
		lose(m)
		for _ = 1, 4000 do
			Machine.step(acorn, m, 0, out)
			if m.phase == PHASE.PLAY and m.ballTicks == 0 then
				break
			end
		end
		t.eq(m.up, 1, "player 1 shoots again")
		t.eq(m.ball, 1, "the same ball number")
		t.eq(m.say, SAY.SHOOT_AGAIN)
		t.falsy(m.shootAgain)
		-- it was the game's one: neither player can earn another
		t.falsy(Machine.extraBall(m, out))
		loseBall(acorn, m, out)
		t.eq(m.up, 2)
		t.falsy(Machine.extraBall(m, out), "player 2 cannot earn a second extra ball for the game")
		t.eq(m.extras[2], 0)
		-- in all: seven balls are played, never eight
		for _ = 1, 12 do
			if m.phase == PHASE.OVER then
				break
			end
			loseBall(acorn, m, out)
		end
		t.eq(m.phase, PHASE.OVER)
		t.eq(m.stats[1].balls, 4)
		t.eq(m.stats[2].balls, 3)
		t.eq(m.stats[1].extraBalls, 1)
		t.eq(m.stats[2].extraBalls, 0)
		t.eq(count(out, CUE.EXTRA_BALL), 1)
	end)

	t.test("PIN-R4: free play: the machine knows no credit, no coin, no replay award and no match number", function()
		local m = Machine.new(acorn, 1, 1)
		for key in m :: any do
			local k = string.lower(key)
			for _, word in { "credit", "coin", "match", "replay", "price", "stake", "wager" } do
				t.falsy(string.find(k, word, 1, true), `state field {key}`)
			end
		end
		for _, text in Machine.TEXT do
			local low = string.lower(text)
			t.falsy(string.find(low, "credit", 1, true))
			t.falsy(string.find(low, "coin", 1, true))
			t.falsy(string.find(low, "match", 1, true))
		end
		t.eq(Machine.TEXT[SAY.FREE_PLAY], "FREE PLAY")
		for _, id in Tables.IDS do
			for _, text in Tables.need(id).sheet.text do
				local low = string.lower(text)
				t.falsy(string.find(low, "credit", 1, true) or string.find(low, "replay", 1, true))
			end
		end
	end)

	t.test(
		"PIN-R5: one to four players alternate ball by ball, each with a score and a rule sheet of their own",
		function()
			t.eq(Machine.MAX_PLAYERS, 4)
			t.fails(function()
				Machine.new(acorn, 1, 5)
			end)
			t.fails(function()
				Machine.new(acorn, 1, 0)
			end)
			local m = Machine.new(acorn, 1, 3)
			local order: { string } = {}
			for _ = 1, 9 do
				table.insert(order, `{m.up}:{m.ball}`)
				launch(acorn, m, 0.9)
				-- each player scores something of their own
				Machine.add(m, m.up * 1000)
				m.sheets[m.up].hoard = m.up
				m.saveLeft, m.graceLeft = 0, 0
				lose(m)
				for _ = 1, 4000 do
					Machine.step(acorn, m, 0, {})
					if m.phase == PHASE.OVER or (m.phase == PHASE.PLAY and m.ballTicks == 0) then
						break
					end
				end
			end
			t.eq(table.concat(order, " "), "1:1 2:1 3:1 1:2 2:2 3:2 1:3 2:3 3:3")
			t.eq(m.phase, PHASE.OVER)
			for seat = 1, 3 do
				t.truthy(m.scores[seat] >= seat * 3000, `player {seat} kept their own score`)
				t.eq(m.sheets[seat].hoard, seat, "and their own hoard")
			end
			t.truthy(m.scores[3] > m.scores[1])
		end
	)

	t.test(
		"multiball plumbing: a ball the machine owes comes up when the lane is clear, and the ball ends with the last",
		function()
			local m = Machine.new(acorn, 1, 1)
			local out: { number } = {}
			launch(acorn, m, 0.9, out)
			m.saveLeft, m.graceLeft = 0, 0
			Machine.feed(m, 2)
			t.eq(Machine.live(m), 3)
			park(acorn, m, BTN.LEFT, Machine.FEED_TICKS + Machine.AUTO_TICKS + 40, out)
			t.eq(#m.phys.balls, 2, "one at a time")
			park(acorn, m, BTN.LEFT, 900, out)
			t.eq(m.queue, 0)
			t.eq(Machine.live(m), #m.phys.balls)
			t.truthy(count(out, CUE.PLUNGE) >= 3)
			-- lose them one by one: only the last ends the ball
			for left = #m.phys.balls, 1, -1 do
				t.eq(m.phase, PHASE.PLAY, `{left} still in play`)
				local one = m.phys.balls[1]
				one.x, one.y, one.vx, one.vy, one.asleep = Layout.XC, 0.3, 0, -2, false
				for _ = 1, 60 do
					Machine.step(acorn, m, 0, out)
					if #m.phys.balls < left then
						break
					end
				end
				for _, rest in m.phys.balls do
					rest.x, rest.y, rest.vx, rest.vy, rest.asleep = Layout.XC, 2.0, 0, 0, true
				end
			end
			t.eq(m.phase, PHASE.BONUS)
		end
	)

	t.test(
		"a ball that lies still where no flipper holds it is found by a ball search; a cradled one is left alone",
		function()
			local m = Machine.new(acorn, 1, 1)
			local out: { number } = {}
			launch(acorn, m, 0.9, out)
			local b = m.phys.balls[1]
			park(acorn, m, BTN.LEFT, 60, out)
			run(acorn, m, BTN.LEFT, Machine.SEARCH_TICKS * 3, out)
			t.eq(count(out, CUE.SEARCH), 0, "a held flipper keeps the search away (a cradle is the player's)")
			t.eq(b.y, 2.0)
			park(acorn, m, 0, 60, out)
			run(acorn, m, 0, Machine.SEARCH_TICKS - 70, out)
			t.eq(count(out, CUE.SEARCH), 0)
			run(acorn, m, 0, 20, out)
			t.eq(count(out, CUE.SEARCH), 1)
			t.falsy(b.asleep)
			t.truthy(b.vy > 0.5, "kicked loose")
			-- a moving ball is never searched for, however long it goes without a switch
			local m2 = Machine.new(acorn, 1, 1)
			launch(acorn, m2, 0.9, out)
			table.clear(out)
			local b2 = m2.phys.balls[1]
			for _ = 1, Machine.SEARCH_TICKS * 2 do
				b2.x, b2.y, b2.vx, b2.vy = Layout.XC, 2.0, 1, 0
				Machine.step(acorn, m2, 0, out)
			end
			t.eq(count(out, CUE.SEARCH), 0)
		end
	)

	t.test(
		"an abandoned ball is played out dead: launched by the machine, no flippers, no ball save, ended in time",
		function()
			for _, id in Tables.IDS do
				local tbl = Tables.need(id)
				local m = Machine.new(tbl, 3, 2)
				local out: { number } = {}
				Machine.forfeit(tbl, m, out)
				t.truthy(m.forfeit)
				local ticks = 0
				while m.phase == PHASE.PLAY and m.forfeit and ticks < Machine.FORFEIT_TICKS + 10 do
					Machine.step(tbl, m, BTN.LEFT + BTN.RIGHT + BTN.PLUNGE, out)
					ticks += 1
					t.eq(m.phys.fa[1], tbl.c.frest[1], "the buttons do nothing")
				end
				t.truthy(ticks <= Machine.FORFEIT_TICKS, `{id}: ended within the minute ({ticks / 240} s)`)
				t.eq(count(out, CUE.SAVE), 0)
				t.eq(count(out, CUE.PLUNGE), 1, "the machine launched it")
				t.eq(m.phase, PHASE.BONUS)
				run(tbl, m, 0, 2000, out)
				t.eq(m.up, 2, "and the next player is up")
				t.falsy(m.forfeit)
				t.falsy(m.phys.dead)
			end
		end
	)

	t.test(
		"PIN-R5: a player who leaves with an extra ball owed is not given it: the next player still here is up",
		function()
			for _, when in { "in mid-ball", "during the bonus count" } do
				local m = Machine.new(acorn, 1, 2)
				local out: { number } = {}
				launch(acorn, m, 0.9, out)
				t.truthy(Machine.extraBall(m, out), when)
				t.truthy(m.shootAgain)
				if when == "during the bonus count" then
					m.saveLeft, m.graceLeft = 0, 0
					lose(m)
					for _ = 1, 600 do
						Machine.step(acorn, m, 0, out)
						if m.phase == PHASE.BONUS then
							break
						end
					end
					t.eq(m.phase, PHASE.BONUS, when)
				end
				Machine.retire(acorn, m, 1, out)
				t.falsy(m.shootAgain, `{when}: the ball owed went with the player`)
				for _ = 1, Machine.FORFEIT_TICKS + 4000 do
					Machine.step(acorn, m, 0, out)
					if m.phase == PHASE.PLAY and m.ballTicks == 0 and not m.forfeit then
						break
					end
				end
				t.eq(m.phase, PHASE.PLAY, when)
				t.eq(m.up, 2, `{when}: player 2's ball stands on the plunger`)
				t.falsy(m.forfeit, when)
				t.eq(m.stats[1].extraBalls, 0, `{when}: the extra ball was never played`)
				t.eq(count(out, CUE.SAY, SAY.SHOOT_AGAIN), 0, when)
			end
			-- and whatever the state says, a ball is never started for a seat that has gone
			local m = Machine.new(acorn, 1, 2)
			local out: { number } = {}
			launch(acorn, m, 0.9, out)
			Machine.retire(acorn, m, 1, out)
			m.shootAgain = true
			for _ = 1, Machine.FORFEIT_TICKS + 4000 do
				Machine.step(acorn, m, 0, out)
				if m.phase == PHASE.PLAY and m.ballTicks == 0 and not m.forfeit then
					break
				end
			end
			t.eq(m.up, 2)
		end
	)

	t.test("squirrel: any number of thumps and then one nudge from the player is never a tilt", function()
		for _, gap in { 2, 24, 100, 240, 480, 700 } do
			local m = Machine.new(acorn, 1, 1)
			local out: { number } = {}
			launch(acorn, m, 0.9, out)
			for _ = 1, 30 do
				park(acorn, m, BTN.THUMP, 1, out)
				park(acorn, m, 0, gap - 1, out)
			end
			t.truthy(m.warnings < Machine.WARNINGS, `thumps {gap} ticks apart left the last warning alone`)
			t.truthy(m.bob < Machine.BOB_LIMIT, `thumps {gap} ticks apart did not pin the bob ({m.bob})`)
			t.falsy(m.tilted)
			park(acorn, m, BTN.NUDGE_L, 1, out)
			t.falsy(m.tilted, `thumps {gap} ticks apart, then the player's one nudge: no tilt`)
			t.eq(count(out, CUE.TILT), 0)
		end
		-- thumps by themselves, however many, never even warn: a second one inside THUMP_COOL is the same thump
		local m = Machine.new(acorn, 1, 1)
		local out: { number } = {}
		launch(acorn, m, 0.9, out)
		for _ = 1, 40 do
			park(acorn, m, BTN.THUMP, 1, out)
			park(acorn, m, 0, 23, out)
		end
		t.eq(m.warnings, 0)
		t.eq(count(out, CUE.TILT_WARN), 0)
		t.truthy(Machine.THUMP_COOL >= 2 * Physics.HZ, "two seconds between thumps")
		t.truthy(count(out, CUE.NUDGE, 4) <= 40 * 24 // Machine.THUMP_COOL + 1)
	end)

	t.test("PIN-R3: a tilted machine is dark and its rule sheet sees nothing but the drain", function()
		for _, id in Tables.IDS do
			local tbl = Tables.need(id)
			local m = Machine.new(tbl, 3, 1)
			local out: { number } = {}
			launch(tbl, m, 0.9, out)
			for _ = 1, 6 do
				park(tbl, m, BTN.NUDGE_L, 1, out)
				park(tbl, m, 0, Machine.NUDGE_COOL + 2, out)
			end
			t.truthy(m.tilted, id)
			local before = digest(m.sheets[1])
			local score = m.scores[1]
			local stats = digest(m.stats[1])
			table.clear(out)
			-- the dead ball is thrown round the table from a dozen places for twenty seconds
			for k = 1, 12 do
				for _, b in m.phys.balls do
					if b.mode == Physics.FREE then
						b.x, b.y = 0.3 + 0.15 * k, 2.2 + 0.1 * (k % 5)
						b.vx, b.vy, b.asleep = if k % 2 == 0 then 3 else -3, 5, false
					end
				end
				for _ = 1, 400 do
					Machine.step(tbl, m, BTN.LEFT + BTN.RIGHT, out)
					if m.phase ~= PHASE.PLAY then
						break
					end
					t.eq(digest(m.sheets[1]), before, `{id}: the sheet is frozen`)
				end
				if m.phase ~= PHASE.PLAY then
					break
				end
				for _, lamp in Machine.lamps(tbl, m, {}) do
					t.eq(lamp, 0, `{id}: every lamp is out`)
				end
			end
			t.eq(m.scores[1], score, id)
			t.eq(digest(m.stats[1]), stats, `{id}: nothing a dead ball hits is counted`)
			t.eq(count(out, CUE.SAY), 0, `{id}: nothing is said after TILT`)
			t.eq(count(out, CUE.JINGLE), 0, `{id}: no jingle`)
			t.eq(count(out, CUE.EXTRA_BALL), 0, id)
		end
	end)

	t.test("determinism: the same seed and the same buttons give the same machine, cue for cue", function()
		for _, id in Tables.IDS do
			local tbl = Tables.need(id)
			local function play(): (string, string)
				local m = Machine.new(tbl, 77, 2)
				local out: { number } = {}
				local s = 5
				for tick = 1, 240 * 45 do
					s = (s * 69069 + 1) % 4294967296
					local r = math.floor(s / 65536)
					local buttons = 0
					if r % 7 < 2 then
						buttons += BTN.LEFT
					end
					if r % 11 < 3 then
						buttons += BTN.RIGHT
					end
					if tick % 900 < 200 then
						buttons += BTN.PLUNGE
					end
					if r % 2000 == 0 then
						buttons += BTN.NUDGE_L
					end
					Machine.step(tbl, m, buttons, out)
				end
				local cues = {}
				for i = 1, #out do
					cues[i] = string.format("%.17g", out[i])
				end
				return digest(m), table.concat(cues, ",")
			end
			local a, ac = play()
			local b, bc = play()
			t.eq(a, b, id)
			t.eq(ac, bc, id)
		end
	end)

	t.test("no hidden state: a clone continues exactly as the original, and the state is plain data", function()
		local tbl = Tables.need("pinball_space")
		local m = Machine.new(tbl, 9, 1)
		local out: { number } = {}
		launch(tbl, m, 0.8, out)
		for tick = 1, 2000 do
			Machine.step(tbl, m, if tick % 100 < 20 then BTN.LEFT + BTN.RIGHT else 0, out)
		end
		local twin = Machine.clone(m)
		t.eq(digest(twin), digest(m))
		local function plain(v: any, path: string)
			local kind = type(v)
			t.truthy(kind == "number" or kind == "boolean" or kind == "table", `{path} is a {kind}`)
			if kind == "number" then
				t.truthy(v == v and math.abs(v) < math.huge, `{path} is a finite number`)
			elseif kind == "table" then
				for k, x in v do
					t.truthy(type(k) == "number" or type(k) == "string", `{path} key`)
					plain(x, `{path}.{k}`)
				end
			end
		end
		plain(m, "state")
		local out2: { number } = {}
		for tick = 1, 3000 do
			local buttons = if tick % 130 < 25 then BTN.LEFT elseif tick % 170 < 30 then BTN.RIGHT else 0
			Machine.step(tbl, m, buttons, out)
			Machine.step(tbl, twin, buttons, out2)
		end
		t.eq(digest(twin), digest(m))
	end)
end
