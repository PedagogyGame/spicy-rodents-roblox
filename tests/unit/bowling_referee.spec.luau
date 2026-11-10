--!strict
-- Minigames/Bowling/Referee: whose sheet a throw goes on (never the next bowler's when the thrower has gone),
-- when the lane must be re-racked to match the rules, what the banner says, the end-of-game summary, and the
-- computer players (three skills in three score bands, shooting spares at the right pin).
local Bowling = require("@shared/Minigames/MinigameRules/Bowling")
local Session = require("@shared/Minigames/Session")
local BallPath = require("@shared/Minigames/Bowling/BallPath")
local LaneCycle = require("@shared/Minigames/Bowling/LaneCycle")
local PinModel = require("@shared/Minigames/Bowling/PinModel")
local Referee = require("@shared/Minigames/Bowling/Referee")
local RollScript = require("@shared/Minigames/Bowling/RollScript")
local Rng = require("@shared/Util/Rng")

local NO_FLAGS: RollScript.Flags =
	{ gutter = false, first = true, pocket = nil, headOn = false, split = false, splitName = nil }

local function table2(lobby: number?): any
	local s = Session.new(Bowling, { lobbySeconds = lobby or 5, turnSeconds = 60, maxTimeouts = 2 })
	Session.join(s, "a", "Ann", 0)
	Session.join(s, "b", "Bob", 0)
	Session.start(s, 1)
	Session.step(s, 1)
	return s
end

local function maskOf(list: { number }): { boolean }
	local m = table.create(10, false)
	for _, n in list do
		m[n] = true
	end
	return m
end

return function(t)
	t.test("a counted throw goes on the thrower's sheet, with the rack the rules want next", function()
		local s = table2()
		local v = Referee.score(s, { pins = 7, seat = 1, flags = NO_FLAGS }, 2)
		t.truthy(v.applied)
		t.eq(v.pins, 7)
		t.eq(v.rack, "keep")
		t.eq(v.mark, "7")
		t.eq(v.text, "7 pins")
		t.eq(v.big, false)
		t.eq(v.seat, 1)
		t.deepEq(s.game.state.rolls[1], { 7 })
		v = Referee.score(s, { pins = 3, seat = 1, flags = NO_FLAGS }, 3)
		t.eq(v.mark, "/")
		t.eq(v.text, "SPARE!")
		t.truthy(v.big)
		t.eq(v.rack, "full")
		t.eq(Session.turn(s), 2)
		v = Referee.score(s, { pins = 10, seat = 2, flags = NO_FLAGS }, 4)
		t.eq(v.text, "STRIKE!")
		t.eq(v.rack, "full")
		-- more pins than stand can never be written
		v = Referee.score(s, { pins = 4, seat = 1, flags = NO_FLAGS }, 5)
		v = Referee.score(s, { pins = 9, seat = 1, flags = NO_FLAGS }, 6)
		t.eq(v.pins, 6)
		t.deepEq(s.game.state.rolls[1], { 7, 3, 4, 6 })
	end)

	t.test("the thrower left while the ball rolled: nothing is scored against the next bowler", function()
		local s = table2()
		-- Ann lets go; while her ball rolls she walks away
		Session.leave(s, "a", 2)
		Session.step(s, 2.1, true) -- the lane is busy; her frame is played out as misses and Bob is up
		t.eq(Session.turn(s), 2)
		t.deepEq(s.game.state.rolls[1], { 0, 0 })
		-- her ball arrives: a strike that must not land on Bob's sheet
		local v = Referee.score(s, { pins = 10, seat = 1, flags = NO_FLAGS }, 4)
		t.eq(v.applied, false)
		t.eq(v.rack, "full", "Bob gets ten fresh pins")
		t.eq(v.text, nil)
		t.deepEq(s.game.state.rolls[2], {}, "Bob has not bowled")
		t.deepEq(s.game.state.rolls[1], { 0, 0 })
		t.eq(Session.turn(s), 2)
		-- and Bob's own throw then counts as his
		v = Referee.score(s, { pins = 8, seat = 2, flags = NO_FLAGS }, 5)
		t.truthy(v.applied)
		t.deepEq(s.game.state.rolls[2], { 8 })
	end)

	t.test("no game, the wrong seat, a finished game: never scored, always a fresh rack", function()
		local idle = Session.new(Bowling, {})
		local v = Referee.score(idle, { pins = 5, seat = 1, flags = NO_FLAGS }, 0)
		t.eq(v.applied, false)
		t.eq(v.rack, "full")
		local s = table2()
		t.eq(Referee.score(s, { pins = 5, seat = 2, flags = NO_FLAGS }, 2).applied, false, "not Bob's turn")
		t.eq(Referee.score(s, { pins = 5, seat = nil, flags = NO_FLAGS }, 2).applied, false, "nobody's throw")
		t.deepEq(s.game.state.rolls[1], {})
		t.deepEq(s.game.state.rolls[2], {})
	end)

	t.test("the last ball of the game says so and asks for a fresh rack", function()
		local s = Session.new(Bowling, { lobbySeconds = 0, turnSeconds = 60 })
		Session.join(s, "a", "Ann", 0)
		local v
		for i = 1, 12 do
			v = Referee.score(s, { pins = 10, seat = 1, flags = NO_FLAGS }, i)
			t.truthy(v.applied)
			if i == 3 then
				t.eq(v.text, "TURKEY! Three strikes in a row")
			elseif i == 2 then
				t.eq(v.text, "DOUBLE! Two strikes in a row")
			elseif i == 5 then
				t.eq(v.text, "5 STRIKES IN A ROW!")
			end
		end
		t.truthy(v.over)
		t.eq(v.text, "12 STRIKES IN A ROW! - that is the game!")
		t.eq(v.rack, "full")
		t.eq(s.phase, "done")
		t.eq(s.result.scores[1], 300)
		t.eq(Referee.score(s, { pins = 10, seat = 1, flags = NO_FLAGS }, 20).applied, false)
	end)

	t.test("the lane is re-racked when the rules expect ten and the deck shows a leave", function()
		local s = table2()
		t.eq(Referee.sync(s, 10), nil)
		Referee.score(s, { pins = 6, seat = 1, flags = NO_FLAGS }, 2)
		t.eq(Referee.sync(s, 4), nil, "mid-frame: the four that stand are right")
		-- Ann never throws her second ball: the idle clock plays her frame out and Bob is up
		local events = Session.step(s, 70)
		t.eq(events[1].kind, "timeout")
		t.eq(Session.turn(s), 2)
		t.eq(Bowling.standing(s.game.state), 10)
		t.eq(Referee.sync(s, 4), "full", "Bob must not bowl at Ann's four")
		t.eq(Referee.sync(s, 10), nil)
		-- with a real lane: the leave is on the deck, the order sets ten
		local c = LaneCycle.new()
		LaneCycle.release(
			c,
			RollScript.build({ offset = 0.5, angle = 0, power = 0.7, spin = 0 }, LaneCycle.mask(c), 4),
			1
		)
		while c.phase ~= "counted" do
			LaneCycle.step(c, 0.1)
		end
		LaneCycle.take(c)
		LaneCycle.set(c, "keep", true)
		t.truthy(LaneCycle.standingCount(c) < 10)
		t.eq(Referee.sync(s, LaneCycle.standingCount(c)), "full")
		LaneCycle.set(c, "full", true)
		t.eq(Referee.sync(s, LaneCycle.standingCount(c)), nil)
		-- no game on: a deck that is not full is always re-racked
		local idle = Session.new(Bowling, {})
		t.eq(Referee.sync(idle, 7), "full")
		t.eq(Referee.sync(idle, 10), nil)
	end)

	t.test("callouts: every kind of throw has its words", function()
		local gutter: RollScript.Flags =
			{ gutter = true, first = true, pocket = nil, headOn = false, split = false, splitName = nil }
		local split: RollScript.Flags =
			{ gutter = false, first = true, pocket = nil, headOn = true, split = true, splitName = "7-10" }
		local function say(
			mark: string,
			pins: number,
			flags: RollScript.Flags?,
			streak: number?,
			over: boolean?
		): (string, boolean)
			return Referee.callout(mark, pins, flags, streak or 0, over == true)
		end
		t.deepEq({ say("X", 10, NO_FLAGS, 1) }, { "STRIKE!", true } :: { any })
		t.deepEq({ say("/", 4, NO_FLAGS) }, { "SPARE!", true } :: { any })
		t.deepEq({ say("-", 0, gutter) }, { "Gutter ball", false } :: { any })
		t.deepEq({ say("-", 0, NO_FLAGS) }, { "Missed everything", false } :: { any })
		t.deepEq({ say("8", 8, split) }, { "SPLIT! The 7-10 is left", false } :: { any })
		t.deepEq({ say("1", 1, NO_FLAGS) }, { "1 pin", false } :: { any })
		t.deepEq({ say("6", 6, nil) }, { "6 pins", false } :: { any })
		t.eq((say("3", 3, NO_FLAGS, 0, true)), "3 pins - that is the game!")
		t.eq((say("-", 0, gutter, 0, true)), "Gutter ball - that is the game!")
		-- a zero on the lane is never called a gutter ball, and a gutter ball is never "missed"
		t.truthy((say("-", 0, NO_FLAGS)) ~= (say("-", 0, gutter)))
	end)

	t.test("summary: ranked, with strikes, spares and misses; a winner, a tie, or a solo score", function()
		local s = table2()
		-- Ann: strikes; Bob: 9 then a miss, every frame
		local guard = 0
		while s.phase == "playing" and guard < 200 do
			guard += 1
			local seat = Session.turn(s) :: number
			local st = s.game.state
			local pins = if seat == 1 then 10 elseif st.ballOf[2] == 1 then 9 else 0
			Referee.score(s, { pins = pins, seat = seat, flags = NO_FLAGS }, 2)
			Session.step(s, 2)
		end
		t.eq(s.phase, "done")
		local sum = Referee.summary(Session.view(s, 3))
		t.eq(#sum.rows, 2)
		t.eq(sum.rows[1].name, "Ann")
		t.eq(sum.rows[1].total, 300)
		t.eq(sum.rows[1].strikes, 12)
		t.eq(sum.rows[1].place, 1)
		t.eq(sum.rows[2].name, "Bob")
		t.eq(sum.rows[2].total, 90)
		t.eq(sum.rows[2].misses, 10)
		t.eq(sum.rows[2].spares, 0)
		t.eq(sum.rows[2].place, 2)
		t.eq(sum.winner, "Ann")
		t.eq(sum.tie, false)
		t.eq(sum.line, "Ann wins with 300!")
		-- a tie
		local tie = table2()
		guard = 0
		while tie.phase == "playing" and guard < 200 do
			guard += 1
			Referee.score(tie, { pins = 4, seat = Session.turn(tie), flags = NO_FLAGS }, 2)
			Session.step(tie, 2)
		end
		local ts = Referee.summary(Session.view(tie, 3))
		t.truthy(ts.tie)
		t.eq(ts.winner, nil)
		t.eq(ts.line, "A tie at 80!")
		t.eq(ts.rows[1].place, 1)
		t.eq(ts.rows[2].place, 1)
		t.eq(ts.rows[1].seat, 1, "ties keep seat order")
		-- alone
		local solo = Session.new(Bowling, { lobbySeconds = 0 })
		Session.join(solo, "a", "Ann", 0)
		for _ = 1, 20 do
			Referee.score(solo, { pins = 3, seat = 1, flags = NO_FLAGS }, 1)
		end
		local ss = Referee.summary(Session.view(solo, 2))
		t.eq(ss.line, "Final score: 60")
		t.eq(ss.rows[1].misses, 0)
		-- someone who left is marked
		local left = table2()
		Session.leave(left, "b", 2)
		t.truthy(Referee.summary(Session.view(left, 2)).rows[2].gone)
	end)

	t.test("computer players: three skills, three score bands, and every throw is a legal one", function()
		local means: { [string]: number } = {}
		for _, skill in { "easy", "normal", "sharp" } do
			local sum, lo, hi = 0, 301, -1
			for g = 1, 30 do
				local score, rolls = Referee.playGame(skill, g * 31)
				t.truthy(score >= 0 and score <= 300)
				t.truthy(#rolls >= 11 and #rolls <= 21)
				sum += score
				lo, hi = math.min(lo, score), math.max(hi, score)
			end
			means[skill] = sum / 30
			t.truthy(lo > 30, `{skill}: the worst game was {lo}`)
			t.truthy(hi < 290, `{skill}: the best game was {hi}`)
		end
		t.truthy(means.easy >= 70 and means.easy <= 125, `easy averages {means.easy}`)
		t.truthy(means.normal >= 125 and means.normal <= 175, `normal averages {means.normal}`)
		t.truthy(means.sharp >= 175 and means.sharp <= 235, `sharp averages {means.sharp}`)
		-- the same seed is the same game
		t.deepEq({ Referee.playGame("normal", 5) }, { Referee.playGame("normal", 5) })
		-- names map to skills
		t.eq(Referee.skillOf("Gutter Gus (computer)"), "easy")
		t.eq(Referee.skillOf("Strike Sally (computer)"), "sharp")
		t.eq(Referee.skillOf("Bowlbot (computer)"), "normal")
		t.eq(Referee.skillOf("someone"), "normal")
		local rng = Rng.new(3)
		for i = 1, 200 do
			local skill = ({ "easy", "normal", "sharp" })[i % 3 + 1]
			local p = Referee.aiThrow(rng, skill, PinModel.fullRack())
			t.truthy(p.offset >= -1 and p.offset <= 1)
			t.truthy(math.abs(p.angle) <= BallPath.RANGES.angle)
			t.truthy(p.power >= 0 and p.power <= 1)
		end
	end)

	t.test("computer players shoot spares at the pin that is there", function()
		local rng = Rng.new(11)
		-- a lone 10-pin: the normal player takes it most of the time, the sharp one nearly always
		for _, case in { { "normal", 0.5 }, { "sharp", 0.9 } } do
			local made = 0
			for i = 1, 100 do
				local mask = maskOf({ 10 })
				local script = RollScript.build(Referee.aiThrow(rng, case[1], mask), mask, i)
				made += script.down
			end
			t.truthy(made / 100 >= case[2], `{case[1]} converts the 10-pin {made}%`)
		end
		-- and it aims at the leave, not at the pocket: for the 7-pin the ball goes left
		local left = 0
		for _ = 1, 50 do
			local p = Referee.aiThrow(rng, "sharp", maskOf({ 7 }))
			local path = BallPath.trace(p)
			if path.entry and path.entry.x < -1 then
				left += 1
			end
			t.eq(p.spin, 0, "no hook on a spare")
		end
		t.truthy(left >= 45, `{left} of 50 balls went at the 7-pin`)
		-- aiming allows for the hook: a hooked first ball still arrives at the pocket
		local angle = Referee.aimAngle(0.55, 0.7, -0.6, 0.27, 56)
		local e = BallPath.trace({ offset = 0.55, angle = angle, power = 0.7, spin = -0.6 }).entry :: BallPath.Entry
		t.near(e.x + e.vx / e.vd * 1.3, 0.27, 0.03)
		t.truthy(e.vx < 0, "coming in from the right")
	end)
end
