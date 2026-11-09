--!strict
-- Minigames/MinigameRules/Pool8Ball (brief v2 §13a pool tables; BUILD_PLAN §3.16 "8-ball rules, fouls"): the
-- break, groups from the first legal pot, fouls and ball in hand, the 8 to win or lose, the server's "shot" verb.
local Minigame = require("@shared/Minigames/Minigame")
local Pool8Ball = require("@shared/Minigames/MinigameRules/Pool8Ball")

return function(t)
	t.test("contract: two seats, no money; groups by number", function()
		t.truthy(Minigame.check(Pool8Ball))
		t.eq(Pool8Ball.groupOf(3), "solids")
		t.eq(Pool8Ball.groupOf(12), "stripes")
		t.eq(Pool8Ball.groupOf(8), "eight")
	end)

	t.test("break, groups, a miss passes the turn, a foul gives ball in hand", function()
		local s = Pool8Ball.init(2, 1)
		t.truthy(s.ballInHand)
		t.eq(Pool8Ball.shot(s, 1, { 3 }, false, true), "continue") -- a pot on the break keeps the table
		t.eq(s.group[1], nil, "the table stays open after the break")
		t.eq(Pool8Ball.shot(s, 11, { 11 }, false, true), "continue")
		t.eq(s.group[1], "stripes")
		t.eq(s.group[2], "solids")
		t.eq(Pool8Ball.shot(s, 12, {}, false, true), "pass")
		t.eq(s.seat, 2)
		-- seat 2 (solids) hits a stripe first: foul, seat 1 has ball in hand
		t.eq(Pool8Ball.shot(s, 9, {}, false, true), "foul")
		t.eq(s.seat, 1)
		t.truthy(s.ballInHand)
		-- scratch is a foul even with a pot
		t.eq(Pool8Ball.shot(s, 13, { 13 }, true, true), "foul")
		t.eq(s.seat, 2)
		-- no rail and no pot after contact is a foul
		t.eq(Pool8Ball.shot(s, 2, {}, false, false), "foul")
	end)

	t.test("the 8: early or with a foul loses; after clearing your group wins", function()
		local s = Pool8Ball.init(2, 1)
		Pool8Ball.shot(s, 1, {}, false, true) -- break, nothing down
		t.eq(s.seat, 2)
		Pool8Ball.shot(s, 2, { 2 }, false, true) -- seat 2 takes solids
		t.eq(s.group[2], "solids")
		t.eq(Pool8Ball.shot(s, 3, { 3, 8 }, false, true), "lose")
		t.truthy(s.done)
		t.eq(s.winner, 1)
		-- clearing then the 8
		local w = Pool8Ball.init(2, 1)
		Pool8Ball.shot(w, 1, {}, false, true)
		Pool8Ball.shot(w, 1, { 1 }, false, true)
		Pool8Ball.shot(w, 2, { 2, 3, 4, 5, 6, 7 }, false, true)
		t.eq(Pool8Ball.shot(w, 9, {}, false, true), "foul", "on the 8, hitting a stripe first is a foul")
		Pool8Ball.shot(w, 10, {}, false, true) -- seat 1 (stripes) misses
		t.eq(w.seat, 2)
		t.eq(Pool8Ball.shot(w, 8, { 8 }, false, true), "win")
		t.eq(w.winner, 2)
		local r = Pool8Ball.result(w) :: any
		t.eq(r.scores[2], 7)
	end)

	t.test("input: only the shooter; pocket list parsed; the 8 on the break is spotted", function()
		local s = Pool8Ball.init(2, 1)
		t.falsy(Pool8Ball.input(s, 2, "shot", { 1, "", false, true }))
		t.truthy(Pool8Ball.input(s, 1, "shot", { 1, "8,4", false, true }))
		t.truthy(s.onTable[8], "8 spotted")
		t.falsy(s.onTable[4])
		t.falsy(s.done)
		Pool8Ball.skipTurn(s)
		t.truthy(s.ballInHand)
		t.eq(Pool8Ball.view(s).kind, "pool")
	end)
end
