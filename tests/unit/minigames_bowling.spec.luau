--!strict
-- Minigames/MinigameRules/Bowling (brief v2 §13a "working scoreboards"; BUILD_PLAN §3.16 "ten_frames"):
-- ten-frame scoring with strikes, spares and the tenth frame's bonus balls; turn order across bowlers; what
-- the pinsetter sets; the server-only "roll" verb; the scoreboard marks.
local Bowling = require("@shared/Minigames/MinigameRules/Bowling")
local Minigame = require("@shared/Minigames/Minigame")

local function play(rolls: { number }): Bowling.State
	local s = Bowling.init(1, 1)
	for _, r in rolls do
		local ok, why = Bowling.input(s, 1, "roll", { r })
		assert(ok, why)
	end
	return s
end

return function(t)
	t.test("contract: shared table, 4 seats, no money; roll is a server verb", function()
		t.truthy(Minigame.check(Bowling))
		t.eq(Bowling.def.seats, 4)
		t.eq(Bowling.def.money, "none")
		t.truthy(Bowling.serverVerbs.roll)
	end)

	t.test("perfect game is 300; twelve strikes", function()
		local rolls = table.create(12, 10)
		local s = play(rolls)
		t.truthy(s.done)
		t.eq(Bowling.total(s.rolls[1]), 300)
		local sc = Bowling.score(s.rolls[1])
		t.eq(sc[1], 30)
		t.eq(sc[9], 270)
		t.eq(sc[10], 300)
		t.deepEq(Bowling.marks(s.rolls[1])[10], { "X", "X", "X" })
		t.deepEq(Bowling.marks(s.rolls[1])[1], { "", "X" })
	end)

	t.test("all gutters is 0 in 20 balls; all 9-/ spares with a 9 bonus is 190", function()
		local s = play(table.create(20, 0))
		t.truthy(s.done)
		t.eq(Bowling.total(s.rolls[1]), 0)
		t.eq(Bowling.marks(s.rolls[1])[3][1], "-")
		local spares = {}
		for _ = 1, 10 do
			table.insert(spares, 9)
			table.insert(spares, 1)
		end
		table.insert(spares, 9)
		local s2 = play(spares)
		t.truthy(s2.done)
		t.eq(Bowling.total(s2.rolls[1]), 190)
		t.deepEq(Bowling.marks(s2.rolls[1])[1], { "9", "/" })
		t.deepEq(Bowling.marks(s2.rolls[1])[10], { "9", "/", "9" })
	end)

	t.test("a known game: 167 with pending bonuses shown as blanks", function()
		-- X, 7/, 9-, X, -8, 8/, -6, X, X, X81
		local rolls = { 10, 7, 3, 9, 0, 10, 0, 8, 8, 2, 0, 6, 10, 10, 10, 8, 1 }
		local s = play(rolls)
		t.truthy(s.done)
		local sc = Bowling.score(s.rolls[1])
		t.eq(sc[1], 20)
		t.eq(sc[2], 39)
		t.eq(sc[3], 48)
		t.eq(sc[4], 66)
		t.eq(sc[5], 74)
		t.eq(sc[6], 84)
		t.eq(sc[7], 90)
		t.eq(sc[8], 120)
		t.eq(sc[9], 148)
		t.eq(sc[10], 167)
		-- mid-game: a strike waits for two more balls
		local p = play({ 10, 7 })
		local partial = Bowling.score(p.rolls[1])
		t.eq(partial[1], false)
		t.eq(Bowling.total(p.rolls[1]), 0)
	end)

	t.test("pinsetter: keep after a first-ball count, full after the frame; tenth frame racks", function()
		local s = Bowling.init(1, 1)
		local ev, rack = Bowling.roll(s, 1, 6)
		t.eq(ev, "next")
		t.eq(rack, "keep")
		t.eq(s.pinsUp, 4)
		t.eq(Bowling.rackFor(s), "keep")
		t.falsy(Bowling.input(s, 1, "roll", { 5 })) -- only 4 standing
		ev, rack = Bowling.roll(s, 1, 4)
		t.eq(ev, "spare")
		t.eq(rack, "full")
		t.eq(s.pinsUp, 10)
		-- straight to the tenth
		for _ = 2, 9 do
			Bowling.roll(s, 1, 10)
		end
		ev, rack = Bowling.roll(s, 1, 10)
		t.eq(ev, "strike")
		t.eq(rack, "full")
		t.eq(s.ballOf[1], 2)
		ev, rack = Bowling.roll(s, 1, 3)
		t.eq(rack, "keep")
		t.eq(s.pinsUp, 7)
		t.eq(s.ballOf[1], 3)
		ev = Bowling.roll(s, 1, 7)
		t.eq(ev, "gameover")
		t.truthy(s.done)
		t.deepEq(Bowling.marks(s.rolls[1])[10], { "X", "3", "/" })
	end)

	t.test("tenth frame open: two balls only", function()
		local rolls = table.create(18, 0)
		table.insert(rolls, 3)
		table.insert(rolls, 4)
		local s = play(rolls)
		t.truthy(s.done)
		t.eq(Bowling.total(s.rolls[1]), 7)
	end)

	t.test("turn order: whole frames in turn across three bowlers; game ends after everyone's tenth", function()
		local s = Bowling.init(3, 1)
		local order = {}
		local guard = 0
		while not s.done and guard < 200 do
			guard += 1
			local seat = Bowling.turn(s) :: number
			table.insert(order, seat)
			t.falsy(Bowling.input(s, (seat % 3) + 1, "roll", { 0 }), "only the bowler whose turn it is")
			t.truthy(Bowling.input(s, seat, "roll", { if seat == 2 then 10 else 4 }))
		end
		t.truthy(s.done)
		t.eq(Bowling.turn(s), nil)
		-- first frames: seat 1 twice (4, 4), seat 2 once (strike), seat 3 twice
		t.deepEq({ order[1], order[2], order[3], order[4], order[5] }, { 1, 1, 2, 3, 3 })
		local r = Bowling.result(s) :: any
		t.eq(r.scores[2], 300)
		t.eq(r.scores[1], 80)
		t.eq(r.winner, 2)
		local v = Bowling.view(s)
		t.eq(v.seats[2].total, 300)
		t.eq(v.seats[1].totals[10], 80)
	end)

	t.test("skipTurn plays out one frame as misses and passes the turn", function()
		local s = Bowling.init(2, 1)
		Bowling.roll(s, 1, 5)
		Bowling.skipTurn(s)
		t.eq(s.seat, 2)
		t.deepEq(s.rolls[1], { 5, 0 })
		Bowling.skipTurn(s)
		t.eq(s.seat, 1)
		t.deepEq(s.rolls[2], { 0, 0 })
		-- single bowler: one frame only, not the rest of the game
		local one = Bowling.init(1, 1)
		Bowling.skipTurn(one)
		t.eq(#one.rolls[1], 2)
		t.eq(one.frameOf[1], 2)
	end)
	t.test("all 5/ spares with a 5 bonus is 150; every frame adds 15", function()
		local s = play(table.create(21, 5))
		t.truthy(s.done)
		t.eq(#s.rolls[1], 21)
		t.eq(Bowling.total(s.rolls[1]), 150)
		local sc = Bowling.score(s.rolls[1])
		for f = 1, 10 do
			t.eq(sc[f], 15 * f, `frame {f}`)
		end
		local marks = Bowling.marks(s.rolls[1])
		t.deepEq(marks[1], { "5", "/" })
		t.deepEq(marks[10], { "5", "/", "5" })
		t.falsy(Bowling.input(s, 1, "roll", { 0 }), "no 22nd ball")
	end)

	t.test("gutter game: every box is a dash, every frame total is 0, no winner alone is still a result", function()
		local s = play(table.create(20, 0))
		local marks = Bowling.marks(s.rolls[1])
		for f = 1, 10 do
			t.deepEq(marks[f], { "-", "-" }, `frame {f}`)
			t.eq(Bowling.score(s.rolls[1])[f], 0)
		end
		local st = Bowling.stats(s.rolls[1])
		t.eq(st.misses, 20)
		t.eq(st.opens, 10)
		t.eq(st.strikes + st.spares, 0)
		local r = Bowling.result(s) :: any
		t.eq(r.scores[1], 0)
	end)

	t.test("the tenth frame: every shape scores, marks and ends as it should", function()
		-- { the tenth's balls, the frame's own score, its marks }
		local cases: { { any } } = {
			{ { 10, 10, 10 }, 30, { "X", "X", "X" } },
			{ { 10, 10, 9 }, 29, { "X", "X", "9" } },
			{ { 10, 9, 1 }, 20, { "X", "9", "/" } },
			{ { 10, 0, 10 }, 20, { "X", "-", "/" } },
			{ { 10, 0, 0 }, 10, { "X", "-", "-" } },
			{ { 10, 3, 4 }, 17, { "X", "3", "4" } },
			{ { 9, 1, 10 }, 20, { "9", "/", "X" } },
			{ { 9, 1, 0 }, 10, { "9", "/", "-" } },
			{ { 0, 10, 5 }, 15, { "-", "/", "5" } },
			{ { 8, 1 }, 9, { "8", "1" } },
			{ { 0, 0 }, 0, { "-", "-" } },
		}
		for _, c in cases do
			local rolls = table.create(18, 0)
			for _, v in c[1] do
				table.insert(rolls, v)
			end
			local s = play(rolls)
			local tag = table.concat(c[1], ",")
			t.truthy(s.done, `{tag}: the game is over`)
			t.eq(Bowling.total(s.rolls[1]), c[2], `{tag}: total`)
			t.eq(Bowling.score(s.rolls[1])[10], c[2], `{tag}: frame ten`)
			t.deepEq(Bowling.marks(s.rolls[1])[10], c[3], `{tag}: marks`)
			local ok, why = Bowling.input(s, 1, "roll", { 0 })
			t.falsy(ok, `{tag}: another ball`)
			t.eq(why, "game over")
		end
		-- the racks inside the tenth: after X the pins are fresh; after X 3 seven stand; after 9 / fresh
		local s = play(table.create(18, 0))
		Bowling.roll(s, 1, 10)
		t.eq(s.pinsUp, 10)
		Bowling.roll(s, 1, 0)
		t.eq(s.pinsUp, 10)
		t.falsy(s.done, "X 0 still has a third ball")
		local ev = Bowling.roll(s, 1, 10)
		t.eq(ev, "gameover")
		local s2 = play(table.create(18, 0))
		Bowling.roll(s2, 1, 9)
		local ev2, rack2 = Bowling.roll(s2, 1, 1)
		t.eq(ev2, "spare")
		t.eq(rack2, "full")
		t.falsy(Bowling.input(s2, 1, "roll", { 11 }), "never more than ten")
	end)

	t.test("bonuses wait: a strike in the ninth is not totalled until two tenth-frame balls are in", function()
		local rolls = table.create(16, 0)
		table.insert(rolls, 10) -- ninth
		local s = play(rolls)
		t.eq(Bowling.score(s.rolls[1])[9], false)
		Bowling.roll(s, 1, 10)
		t.eq(Bowling.score(s.rolls[1])[9], false)
		Bowling.roll(s, 1, 4)
		t.eq(Bowling.score(s.rolls[1])[9], 24)
		t.eq(Bowling.score(s.rolls[1])[10], false, "X 4 still owes a ball")
		Bowling.roll(s, 1, 6)
		t.eq(Bowling.score(s.rolls[1])[10], 44)
		t.eq(Bowling.view(s).seats[1].totals[10], 44)
	end)

	t.test("a tie has no winner; more pins than stand is refused; nothing counts after the game", function()
		local s = Bowling.init(2, 1)
		for _ = 1, 20 do
			local seat = Bowling.turn(s) :: number
			t.truthy(Bowling.input(s, seat, "roll", { 3 }))
			t.truthy(Bowling.input(s, seat, "roll", { 4 }))
		end
		t.truthy(s.done)
		local r = Bowling.result(s) :: any
		t.eq(r.scores[1], 70)
		t.eq(r.scores[2], 70)
		t.eq(r.winner, nil)
		local ok, why = Bowling.input(s, 1, "roll", { 1 })
		t.falsy(ok)
		t.eq(why, "game over")
		local s2 = Bowling.init(1, 1)
		Bowling.roll(s2, 1, 7)
		local bad, badWhy = Bowling.input(s2, 1, "roll", { 4 })
		t.falsy(bad)
		t.eq(badWhy, "pins")
		t.falsy(Bowling.input(s2, 1, "roll", { -1 }))
		t.falsy(Bowling.input(s2, 1, "roll", { 2.5 }))
		t.falsy(Bowling.input(s2, 1, "roll", { "3" }))
	end)

	t.test("stats and streak: the 167 game, a turkey, a perfect game", function()
		local rolls = { 10, 7, 3, 9, 0, 10, 0, 8, 8, 2, 0, 6, 10, 10, 10, 8, 1 }
		local st = Bowling.stats(rolls)
		t.eq(st.strikes, 5)
		t.eq(st.spares, 2)
		t.eq(st.opens, 3) -- 9-, -8, -6 (the tenth X 8 1 carries a strike)
		t.eq(st.misses, 3)
		t.eq(st.balls, 17)
		t.eq(Bowling.streak(rolls), 0)
		t.eq(Bowling.streak({ 10, 10, 10 }), 3)
		t.eq(Bowling.streak({ 10, 7, 3, 10, 10 }), 2)
		t.eq(Bowling.streak({ 10, 10, 4 }), 0)
		t.eq(Bowling.streak({}), 0)
		local perfect = table.create(12, 10)
		t.eq(Bowling.stats(perfect).strikes, 12)
		t.eq(Bowling.streak(perfect), 12)
		-- a first-ball 0 then 10 is a spare, not a strike
		t.eq(Bowling.streak({ 0, 10 }), 0)
		t.eq(Bowling.stats({ 0, 10 }).spares, 1)
	end)
end
