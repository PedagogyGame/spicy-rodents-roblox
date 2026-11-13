--!strict
-- Air hockey's three computer opponents (the owner's Lounge, Club and Pro: Sim.ai with his three difficulty
-- numbers, unchanged), MEASURED, and the rails that hold, over whole matches.
-- Nothing here tunes him. Each level is played to seven against three hands a person might bring (Line.hands):
--   still: a mallet that never moves from where the match puts it;
--   keeper: along the goal line under the puck, never striking;
--   pointer: the pointer put on the puck whenever it is in your half (what a new player does with a mouse).
-- The results are RECORDED below as they are: a later change to the simulation, to the opponent or to the rule
-- that keeps the puck on the table shows here as a changed number, and whoever changes it says so on the owner's
-- check sheet (docs/owner/AIR_HOCKEY_CHECK.md has this table in words). What the numbers say today: a still
-- mallet beats Lounge 7-6 because Lounge puts the puck in its own goal; a goalkeeper who never strikes beats
-- Lounge and Club; a pointer on the puck loses most matches to Club and Pro.
-- The same matches are the proof that the puck stays on the table: with the plainest hand there is, pressing
-- pucks into rails several times a match, no puck is ever put back for a serve and every match ends.
local Sim = require("@shared/Minigames/AirHockey/Sim")
local Line = require("../../tools/games/air_hockey/Line")

local LIMIT = 240 * 900 -- ticks: no match may take a quarter of an hour

type Tally = { won: number, goalsFor: number, goalsAgainst: number, seconds: number, held: number, served: number }

-- `matches` matches to seven at one level, the hand at the Glacier end, read sixty times a second.
local function play(hand: Line.Hand, difficulty: number, matches: number): Tally
	local out: Tally = { won = 0, goalsFor = 0, goalsAgainst = 0, seconds = 0, held = 0, served = 0 }
	for m = 1, matches do
		local s = Sim.new()
		s.difficulty = difficulty
		local tick = 0
		while s.winner < 0 and tick < LIMIT do
			tick += 1
			if tick % 4 == 1 then
				local x, y = hand(0, s, tick + m * 1000)
				Sim.setTarget(s, 0, x, y)
			end
			-- (a step of a match, as Sim.play has it, with the rail's hold counted)
			Sim.tick(s, Sim.STEP, 0, true)
			if s.winner < 0 and s.countdown <= 0 then
				if Sim.contain(s) then
					out.held += 1
				end
				if Sim.offTable(s) then
					out.served += 1
					Sim.resetPuck(s)
				end
			end
		end
		assert(s.winner >= 0, `match {m} at difficulty {difficulty} did not end in {LIMIT / 240} s`)
		out.seconds += tick / 240
		if s.winner == 0 then
			out.won += 1
		end
		out.goalsFor += s.score0
		out.goalsAgainst += s.score1
	end
	return out
end

local LEVELS = {
	{ name = "Lounge", difficulty = Sim.DIFFICULTY.easy },
	{ name = "Club", difficulty = Sim.DIFFICULTY.medium },
	{ name = "Pro", difficulty = Sim.DIFFICULTY.hard },
}

-- RECORDED (see the header): { won, goals for, goals against } of 1 match (still, keeper: no two differ) and of
-- 12 (pointer)
local RECORD: { [string]: { [string]: { number } } } = {
	Lounge = { still = { 1, 7, 6 }, keeper = { 1, 7, 0 }, pointer = { 8, 74, 57 } },
	Club = { still = { 0, 0, 7 }, keeper = { 1, 7, 2 }, pointer = { 2, 51, 76 } },
	Pro = { still = { 0, 0, 7 }, keeper = { 0, 1, 7 }, pointer = { 2, 33, 79 } },
}

return function(t)
	for _, level in LEVELS do
		t.test(`{level.name}: a still mallet, a goalkeeper and a pointer on the puck, as recorded`, function()
			local got = {
				still = play(Line.hands.still, level.difficulty, 1),
				keeper = play(Line.hands.keeper, level.difficulty, 1),
				pointer = play(Line.hands.pointer(0.02), level.difficulty, 12),
			}
			local lines = {}
			for _, name in { "still", "keeper", "pointer" } do
				local g: Tally = (got :: any)[name]
				local want = RECORD[level.name][name]
				table.insert(
					lines,
					`{name} = \{ {g.won}, {g.goalsFor}, {g.goalsAgainst} \} ({math.floor(g.seconds)} s, rails held {g.held})`
				)
				t.eq(g.served, 0, `{level.name}, {name}: no puck is ever put back for a serve`)
				if g.won ~= want[1] or g.goalsFor ~= want[2] or g.goalsAgainst ~= want[3] then
					error(
						`{level.name}, {name}: won {g.won}, goals {g.goalsFor}-{g.goalsAgainst}; recorded {want[1]}, {want[2]}-{want[3]}. If the change is meant, record it here and on the owner's check sheet. All: {table.concat(
							lines,
							"; "
						)}`
					)
				end
			end
			-- the plainest hand presses pucks into rails: the rails held, and not on every step
			t.truthy(got.pointer.held >= 1, "the pointer hand pressed a puck into a rail at least once")
			t.truthy(got.pointer.held <= 12 * 40, `rails held {got.pointer.held} times in 12 matches`)
		end)
	end

	t.test("a hand with no wobble at all still plays whole matches (it used to re-serve every four seconds)", function()
		for _, level in LEVELS do
			local g = play(Line.hands.pointer(0), level.difficulty, 2)
			t.eq(g.served, 0)
			t.truthy(g.seconds < 2 * 600, `{level.name}: {g.seconds} s for two matches`)
		end
	end)
end
