--!strict
-- Reputation/ReputationRules and the vote window (BUILD_PLAN §3.15, §4.4 #6b; brief v2 §13a): event
-- deltas, the [-100, 100] range, 5 up + 5 down per voter per in-game day, one vote per target per day,
-- weights clamp(0.25 + rep/100, 0.25, 1.5), and a brigading bound.
local ReputationRules = require("@shared/Reputation/ReputationRules")

return function(t)
	t.test("events and clamp", function()
		t.eq(ReputationRules.tick(0, "gig_tip"), 2)
		t.eq(ReputationRules.tick(0, "gig_bad"), -1)
		t.eq(ReputationRules.tick(0, "cafe_seat_per_game_hour", 3), 3)
		t.eq(ReputationRules.tick(99, "rescue"), 100)
		t.eq(ReputationRules.tick(-100, "false_report"), -100)
		t.fails(function()
			ReputationRules.tick(0, "nope")
		end)
	end)

	t.test("weights", function()
		t.eq(ReputationRules.weight(-100), 0.25)
		t.eq(ReputationRules.weight(0), 0.25)
		t.eq(ReputationRules.weight(50), 0.75)
		t.eq(ReputationRules.weight(100), 1.25)
		t.eq(ReputationRules.weight(1000), 1.5)
	end)

	t.test("vote window: quotas, one per target, no self votes, daily reset", function()
		local w = ReputationRules.newVoteWindow()
		t.deepEq({ ReputationRules.applyVote(w, 1, "a", 50, "a", 0, 1) }, { false, "self" })
		t.deepEq({ ReputationRules.applyVote(w, 1, "a", 50, "b", 0, 1) }, { true, 1.5 })
		t.deepEq({ ReputationRules.applyVote(w, 1, "a", 50, "b", 0, -1) }, { false, "same target today" })
		for i = 1, 4 do
			t.truthy((ReputationRules.applyVote(w, 1, "a", 50, `t{i}`, 0, 1)))
		end
		t.deepEq({ ReputationRules.applyVote(w, 1, "a", 50, "t9", 0, 1) }, { false, "no up votes left" })
		t.truthy((ReputationRules.applyVote(w, 1, "a", 50, "t9", 0, -1)))
		t.truthy((ReputationRules.applyVote(w, 2, "a", 50, "b", 0, 1))) -- new day
	end)

	t.test("brigading: 48 fresh accounts down-voting once a day move a target by at most 24 a day", function()
		local w = ReputationRules.newVoteWindow()
		local rep = 40
		for v = 1, 48 do
			local ok, r = ReputationRules.applyVote(w, 7, `fresh{v}`, 0, "victim", rep, -1)
			t.truthy(ok)
			rep = r :: number
		end
		t.eq(rep, 40 - 48 * 2 * 0.25)
	end)

	t.test("entourage is capped", function()
		t.eq(ReputationRules.entourage(2.7), 2)
		t.eq(ReputationRules.entourage(10), 4)
		t.eq(ReputationRules.entourage(-1), 0)
	end)
end
