--!strict
-- The duel's balance (owner playtest 2026-11-18: the tough people "extra aggressive and extra successful in landing blows
-- against you, and extra resistant of being bitten. Still possible, but harder"), proved on the game's own Combat/Duel
-- and Combat/CombatRules with tests/lib/DuelSim: 400 seeded duels a line, the person already aware of the rodent 30
-- studs off on open ground. A skilled rodent (timing, zig-zag, feints, the vigilante's stance read) beats a vigilante
-- 25-45 % of the time and an ordinary calm person at least 70 %; a straight sprint loses to a vigilante almost always;
-- and near a fresh bite (alert.bitePenalty) a bite is close to impossible.
local DuelSim = require("@tests/lib/DuelSim")

local N = 400

return function(t)
	local cache: { [string]: DuelSim.Summary } = {}
	local function batch(temper: string, rodent: string, boosted: boolean?): DuelSim.Summary
		local key = `{temper}/{rodent}/{boosted == true}`
		local s = cache[key]
		if s == nil then
			s = DuelSim.batch(N, { temper = temper :: any, rodent = rodent, seed = 7, boosted = boosted })
			cache[key] = s
			print(
				string.format(
					"      %-5s %-8s %-11s wins %3d %%  (knocked out %d, got away %d, out of time %d; %.1f pounces, %.1f feints, %.2f blows taken, %.1f s)",
					temper,
					rodent,
					if boosted then "fresh bite" else "",
					math.floor(s.rate * 100 + 0.5),
					s.knockouts,
					s.escapes,
					s.timeouts,
					s.pounces,
					s.feints,
					s.hitsTaken,
					s.meanSecs
				)
			)
		end
		return s
	end

	t.test("a skilled rodent beats a vigilante 25-45 % of the time: still possible, but harder", function()
		local s = batch("tough", "skilled")
		t.truthy(s.rate >= 0.25 and s.rate <= 0.45, `skilled vs vigilante {s.rate}`)
		t.truthy(s.feints > 0.5, "the skilled rodent feints against a vigilante")
	end)

	t.test(
		"a skilled rodent beats an ordinary calm person at least 70 % of the time, and a wary one less often",
		function()
			local calm = batch("calm", "skilled")
			local wary = batch("wary", "skilled")
			t.truthy(calm.rate >= 0.7, `skilled vs calm {calm.rate}`)
			t.truthy(wary.rate >= 0.6, `skilled vs wary {wary.rate}`)
			t.truthy(wary.rate <= calm.rate, "a wary person is no easier than a calm one")
		end
	)

	t.test("a straight sprint loses to a vigilante almost every time; skill is what wins", function()
		local sprint = batch("tough", "sprinter")
		local skilled = batch("tough", "skilled")
		t.truthy(sprint.rate <= 0.2, `sprinter vs vigilante {sprint.rate}`)
		t.truthy(skilled.rate - sprint.rate >= 0.15, "the skilled rodent does clearly better")
		t.truthy(sprint.knockouts >= N * 0.75, "a sprinter is mostly knocked out")
	end)

	t.test("a vigilante lands more blows than a calm person and is bitten less", function()
		local tough = batch("tough", "skilled")
		local calm = batch("calm", "skilled")
		t.truthy(
			tough.hitsTaken > calm.hitsTaken * 4,
			`blows taken: vigilante {tough.hitsTaken}, calm {calm.hitsTaken}`
		)
		local sprintTough, sprintCalm = batch("tough", "sprinter"), batch("calm", "sprinter")
		t.truthy(sprintTough.rate < sprintCalm.rate / 3, "a straight lunge mostly fails on a vigilante")
	end)

	t.test(
		"near a fresh bite a bite is close to impossible: wins per pounce a tenth of what they were or less",
		function()
			for _, temper in { "calm", "wary", "tough" } do
				local away = batch(temper, "skilled")
				local near = batch(temper, "skilled", true)
				local perAway = away.rate / math.max(away.pounces, 1e-6)
				local perNear = near.rate / math.max(near.pounces, 1e-6)
				t.truthy(perNear <= perAway / 10, `{temper}: {perNear} a pounce near a bite against {perAway} away`)
			end
			t.truthy(batch("tough", "skilled", true).rate <= 0.05, "a vigilante by a fresh bite is all but unbeatable")
		end
	)
end
