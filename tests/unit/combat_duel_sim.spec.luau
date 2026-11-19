--!strict
-- The duel's balance (owner playtest 2026-11-18: the tough people "extra aggressive and extra successful in landing blows
-- against you, and extra resistant of being bitten. Still possible, but harder"), proved on the game's own Combat/Duel
-- and Combat/CombatRules with tests/lib/DuelSim: 400 seeded duels a line, the person already aware of the rodent 30
-- studs off on open ground, the server stepping the duel ten times a second, the motor pouncing along the body's
-- heading, and the link a real one: the rodent's player sees the person a round trip late (100 and 150 ms; 0 ms is
-- reported). There is no door to run to: a person runs as the brain does (Duel.FLEE_SECS along the lane) and stays on
-- guard if the rodent is still at their heels. On those links a skilled rodent (timing, zig-zag, feints, the
-- vigilante's stance read) beats a vigilante 25-45 % of the time and an ordinary calm person 70-90 %; a straight sprint
-- loses to a vigilante almost always; and near a fresh bite (alert.bitePenalty) a bite is close to impossible.
local DuelSim = require("@tests/lib/DuelSim")

local N = 400
local LINKS = { 0.1, 0.15 } -- the round trips the balance is held on

return function(t)
	local cache: { [string]: DuelSim.Summary } = {}
	local function batch(temper: string, rodent: string, lag: number, boosted: boolean?): DuelSim.Summary
		local key = `{temper}/{rodent}/{lag}/{boosted == true}`
		local s = cache[key]
		if s == nil then
			s = DuelSim.batch(N, { temper = temper :: any, rodent = rodent, seed = 7, lag = lag, boosted = boosted })
			cache[key] = s
			print(
				string.format(
					"      %3d ms  %-5s %-8s %-10s wins %3d %%  (knocked out %d, lost %d, out of time %d; %.1f pounces, %.1f feints, %.2f blows taken, %.1f s)",
					math.floor(lag * 1000 + 0.5),
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

	t.test("the table at 0, 100 and 150 ms", function()
		for _, lag in { 0, 0.1, 0.15 } do
			for _, row in
				{
					{ "tough", "skilled" },
					{ "tough", "sprinter" },
					{ "wary", "skilled" },
					{ "calm", "skilled" },
					{ "calm", "sprinter" },
				}
			do
				batch(row[1], row[2], lag)
			end
		end
	end)

	t.test(
		"a skilled rodent beats a vigilante 25-45 % of the time at 100 and 150 ms: still possible, but harder",
		function()
			for _, lag in LINKS do
				local s = batch("tough", "skilled", lag)
				t.truthy(s.rate >= 0.25 and s.rate <= 0.45, `skilled vs vigilante at {lag} s: {s.rate}`)
				t.truthy(s.feints > 0.5, "the skilled rodent feints against a vigilante")
			end
		end
	)

	t.test(
		"a skilled rodent beats a calm person 70-90 % of the time at 100 and 150 ms, and a wary one less often",
		function()
			for _, lag in LINKS do
				local calm = batch("calm", "skilled", lag)
				local wary = batch("wary", "skilled", lag)
				t.truthy(calm.rate >= 0.7 and calm.rate <= 0.9, `skilled vs calm at {lag} s: {calm.rate}`)
				t.truthy(wary.rate >= 0.55, `skilled vs wary at {lag} s: {wary.rate}`)
				t.truthy(wary.rate <= calm.rate, "a wary person is no easier than a calm one")
			end
		end
	)

	t.test("a straight sprint loses to a vigilante almost every time, at any link; skill is what wins", function()
		for _, lag in { 0, 0.1, 0.15 } do
			local sprint = batch("tough", "sprinter", lag)
			t.truthy(sprint.rate <= 0.2, `sprinter vs vigilante at {lag} s: {sprint.rate}`)
			t.truthy(sprint.knockouts >= N * 0.75, "a sprinter is mostly knocked out")
		end
		for _, lag in LINKS do
			local sprint, skilled = batch("tough", "sprinter", lag), batch("tough", "skilled", lag)
			t.truthy(skilled.rate - sprint.rate >= 0.1, `the skilled rodent does clearly better at {lag} s`)
		end
	end)

	t.test("a vigilante lands more blows than a calm person and is bitten less", function()
		for _, lag in LINKS do
			local tough = batch("tough", "skilled", lag)
			local calm = batch("calm", "skilled", lag)
			t.truthy(
				tough.hitsTaken > calm.hitsTaken * 3,
				`blows taken at {lag} s: vigilante {tough.hitsTaken}, calm {calm.hitsTaken}`
			)
			local sprintTough, sprintCalm = batch("tough", "sprinter", lag), batch("calm", "sprinter", lag)
			t.truthy(sprintTough.rate < sprintCalm.rate / 3, "a straight lunge mostly fails on a vigilante")
		end
	end)

	t.test(
		"near a fresh bite a bite is close to impossible: wins per pounce a tenth of what they were or less (100 ms)",
		function()
			for _, temper in { "calm", "wary", "tough" } do
				local away = batch(temper, "skilled", 0.1)
				local near = batch(temper, "skilled", 0.1, true)
				local perAway = away.rate / math.max(away.pounces, 1e-6)
				local perNear = near.rate / math.max(near.pounces, 1e-6)
				t.truthy(perNear <= perAway / 10, `{temper}: {perNear} a pounce near a bite against {perAway} away`)
			end
			t.truthy(
				batch("tough", "skilled", 0.1, true).rate <= 0.05,
				"a vigilante by a fresh bite is all but unbeatable"
			)
		end
	)
end
