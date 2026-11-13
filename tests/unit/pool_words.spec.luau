--!strict
-- Minigames/Pool/Words: what happened at a cue table, in plain words, read off the rules' own views (the foul
-- and how a game ended are the rules' FOUL_TEXT / HOW_TEXT, never reworded), and the scoreboards beside the
-- tables.
local BumperPool = require("@shared/Minigames/Pool/BumperPool")
local EightBall = require("@shared/Minigames/Pool/EightBall")
local Words = require("@shared/Minigames/Pool/Words")

return function(t)
	local names = { "Ann", "Bob" }

	t.test("POOL-S3 a foul in the rules' own words, and who has the ball in hand", function()
		local s = EightBall.init(2, 1)
		-- the break hits nothing: a foul, the other player breaks from the kitchen
		EightBall.apply(s, { firstHit = 0, pots = {}, railAfter = false })
		local v = EightBall.view(s)
		t.eq(
			Words.eightBall(v, names, nil),
			`Foul: {EightBall.FOUL_TEXT.no_hit}. Bob has the ball in hand behind the head string.`
		)
		EightBall.skipTurn(s)
		-- (the rack is still to be broken: from the kitchen again)
		t.eq(
			Words.eightBall(EightBall.view(s), names, nil),
			"Bob ran out of time. Ann has the ball in hand behind the head string."
		)
	end)

	t.test("a pot keeps the table, and the group it gives is named", function()
		local s = EightBall.init(2, 1)
		EightBall.apply(s, { firstHit = 1, pots = {}, railAfter = true })
		EightBall.apply(s, { firstHit = 3, pots = { { ball = 3, hole = 1 } }, railAfter = true })
		local v = EightBall.view(s)
		t.eq(Words.eightBall(v, names, "solids"), "Bob potted the 3 and is on solids: still at the table.")
		t.eq(Words.group(v, 2), "solids")
		t.eq(Words.group(v, 1), "stripes")
	end)

	t.test("how a game ended: the 8 in the called pocket, and a forfeit by leaving", function()
		local s = EightBall.init(2, 1)
		EightBall.gone(s, 2)
		t.eq(Words.eightBallEnd(EightBall.view(s), names), "Ann wins: Bob left the table.")
		local b = BumperPool.init(2, 1)
		BumperPool.gone(b, 1)
		t.eq(Words.bumperEnd(BumperPool.view(b), names), "Bob wins: Ann left the table.")
	end)

	t.test("the scoreboards: an idle table invites, a game shows groups or balls down, and the sitting", function()
		t.eq(Words.eightBallBoard("TABLE 2", nil, {}, {}), "TABLE 2\nEight-ball: walk up and press E")
		local s = EightBall.init(2, 1)
		local board = Words.eightBallBoard("TABLE 1", EightBall.view(s), names, { Bob = 1, Ann = 2 })
		t.eq(board, "TABLE 1\nAnn: open table  <\nBob: open table\nGames won: Ann 2  -  Bob 1")
		local b = BumperPool.init(2, 1)
		local bumper = Words.bumperBoard(BumperPool.view(b), names, {})
		t.eq(bumper, "BUMPER POOL\nAnn (red): 0 of 5  <\nBob (white): 0 of 5")
	end)

	t.test("a refusal is said in words, and an unknown one is passed through", function()
		t.eq(Words.refusal("call a pocket"), "Call a pocket for the 8 first: click a pocket")
		t.eq(Words.refusal("not your ball"), "That is not one of your balls")
		t.eq(Words.refusal("something new"), "something new")
		t.eq(Words.refusal(nil), "That does not work at this table")
		t.eq(Words.pocket(3), "the left side pocket")
	end)
end
