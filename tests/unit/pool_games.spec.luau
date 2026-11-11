--!strict
-- Minigames/Pool/Computer: the computer players (checklist C3: names that belong to the game, three skill
-- levels, and they can always finish a game) playing whole games of eight-ball and bumper pool to the end
-- through the same inputs a person gives, on several seeds.
local BumperPool = require("@shared/Minigames/Pool/BumperPool")
local Computer = require("@shared/Minigames/Pool/Computer")
local EightBall = require("@shared/Minigames/Pool/EightBall")
local Rng = require("@shared/Util/Rng")
local Shot = require("@shared/Minigames/Pool/Shot")
local Tables = require("@shared/Minigames/Pool/Tables")

return function(t)
	type PoolStats = { shots: number, visits: { number }, pots: { number }, refused: number, longest: number }

	-- one game of eight-ball between two computer players (or one alone); returns the final state
	local function pool(levels: { number }, seed: number, stats: PoolStats?): EightBall.State
		local s = EightBall.init(#levels, seed)
		local turns = 0
		while not s.done and turns < 400 do
			local seat = s.seat
			local level = levels[seat]
			local inputs = Computer.eightBall(s, level, seed)
			t.truthy(#inputs >= 1 and inputs[#inputs].verb == "shoot", "a turn always ends in a strike")
			for _, inp in inputs do
				t.truthy(EightBall.verbs[inp.verb], "only a player's verbs")
				local ok, why = EightBall.input(s, seat, inp.verb, inp.args)
				if not ok and stats then
					stats.refused += 1
				end
				t.truthy(ok, `seed {seed}, turn {turns}: {inp.verb} refused ({why})`)
			end
			turns += 1
			local script = EightBall.script(s) :: Shot.Script
			t.falsy(script.capped)
			t.eq(script.knots, 0)
			local last = s.last :: EightBall.Last
			if stats then
				stats.shots += 1
				stats.longest = math.max(stats.longest, script.tEnd)
				if not last.breakShot then
					stats.visits[level] += 1
					if last.event == "continue" or last.event == "win" then
						stats.pots[level] += 1
					end
				end
			end
		end
		return s
	end

	local function bumper(levels: { number }, seed: number): BumperPool.State
		local s = BumperPool.init(#levels, seed)
		local turns = 0
		while not s.done and turns < 300 do
			local waiting = BumperPool.waiting(s)
			t.truthy(#waiting >= 1)
			for _, seat in waiting do
				local inputs = Computer.bumper(s, seat, levels[seat], seed)
				t.eq(#inputs, 1)
				t.eq(inputs[1].verb, "shoot")
				local ok, why = BumperPool.input(s, seat, inputs[1].verb, inputs[1].args)
				t.truthy(ok, `seed {seed}, turn {turns}: refused ({why})`)
			end
			turns += 1
			local script = BumperPool.script(s) :: Shot.Script
			t.falsy(script.capped)
			t.eq(script.knots, 0)
			t.truthy(script.tEnd < 12, `a bumper pool shot took {script.tEnd} s`)
		end
		return s
	end

	t.test("C3 three computer players for each game, with names that belong to it and rising skill", function()
		t.eq(#Computer.POOL_PLAYERS, 3)
		t.eq(#Computer.BUMPER_PLAYERS, 3)
		local seen: { [string]: boolean } = {}
		for i = 1, 3 do
			for _, p in { Computer.POOL_PLAYERS[i], Computer.BUMPER_PLAYERS[i] } do
				t.eq(p.level, i)
				t.truthy(#p.name >= 4 and not seen[p.name], "its own name")
				seen[p.name] = true
			end
		end
		t.eq(#Computer.LEVELS, 3)
		for i = 2, 3 do
			t.truthy(Computer.LEVELS[i].aim < Computer.LEVELS[i - 1].aim, "a steadier aim")
			t.truthy(Computer.LEVELS[i].bank < Computer.LEVELS[i - 1].bank)
			t.truthy(Computer.LEVELS[i].power < Computer.LEVELS[i - 1].power, "a better touch")
			t.truthy(Computer.LEVELS[i].sims >= Computer.LEVELS[i - 1].sims)
		end
		t.eq(Computer.LEVELS[1].sims, 0, "the beginner plays what it sees")
	end)

	t.test("eight-ball: every pairing plays whole games to the end on several seeds", function()
		local stats: PoolStats = { shots = 0, visits = { 0, 0, 0 }, pots = { 0, 0, 0 }, refused = 0, longest = 0 }
		local games, byEight = 0, 0
		for _, levels in { { 1, 1 }, { 2, 2 }, { 3, 3 }, { 1, 3 }, { 3, 2 } } do
			for seed = 1, 5 do
				local s = pool(levels, seed * 13 + levels[1], stats)
				t.truthy(s.done, `levels {levels[1]} v {levels[2]}, seed {seed}: the game did not finish`)
				t.truthy(s.winner == 1 or s.winner == 2)
				t.truthy(EightBall.HOW_TEXT[s.how :: string] ~= nil)
				local r = EightBall.result(s) :: any
				t.eq(r.done, true)
				games += 1
				if s.how == "eight" then
					byEight += 1
					t.eq(EightBall.left(s, s.winner :: number), 0, "the winner cleared its group first")
				end
			end
		end
		t.eq(stats.refused, 0)
		t.truthy(byEight >= games * 0.6, `{byEight} of {games} games ended with the 8 in the called pocket`)
		t.truthy(stats.shots / games < 80, `{stats.shots / games} shots a game`)
		t.truthy(stats.longest < 12, `the longest shot took {stats.longest} s`)
		-- skill shows: the share of visits that pot a ball rises with the level
		local rate =
			{ stats.pots[1] / stats.visits[1], stats.pots[2] / stats.visits[2], stats.pots[3] / stats.visits[3] }
		t.truthy(rate[1] > 0.12 and rate[1] < 0.5, `the beginner pots on {rate[1]} of its visits`)
		t.truthy(rate[2] > rate[1] + 0.1, `the club player on {rate[2]}`)
		t.truthy(rate[3] > rate[2] + 0.05 and rate[3] < 0.95, `the best on {rate[3]}, and it still misses`)
	end)

	t.test("eight-ball: the best player beats the beginner from either seat; a game is the same game twice", function()
		local wins = 0
		for seed = 1, 6 do
			local a = pool({ 3, 1 }, 100 + seed)
			if a.winner == 1 then
				wins += 1
			end
			local b = pool({ 1, 3 }, 200 + seed)
			if b.winner == 2 then
				wins += 1
			end
		end
		t.truthy(wins >= 9, `the best player won {wins} of 12`)
		local x, y = pool({ 2, 3 }, 31), pool({ 2, 3 }, 31)
		t.deepEq(EightBall.view(x), EightBall.view(y), "seeded: the same seed is the same game")
		t.deepEq(EightBall.script(x), EightBall.script(y))
	end)

	t.test("eight-ball practice: each computer player clears a table alone", function()
		for level = 1, 3 do
			local s = pool({ level }, 40 + level)
			t.truthy(s.done)
			local r = EightBall.result(s) :: any
			t.truthy(r.shots[1] >= 8, "at least the break, seven balls and the 8... or an early end")
			t.truthy(r.bestRun[1] >= 1)
		end
	end)

	t.test(
		"eight-ball: whatever the table looks like, the computer player has a strike (it can always go on)",
		function()
			local rng = Rng.new(99)
			local tb = Tables.eightBall()
			for case = 1, 40 do
				local s = EightBall.init(2, case)
				s.broken = true
				s.inHand = if case % 3 == 0 then "anywhere" else "none"
				-- a random scatter: some balls down, the rest anywhere they fit (clusters, cushions, snookers)
				local spots: { Tables.Spot } = {}
				for id = 0, 15 do
					if id == 0 or id == 8 or rng.next() < 0.6 then
						for _ = 1, 50 do
							local x, z = rng.range(-2.5, 2.5), rng.range(-5.2, 5.2)
							if Tables.canPlace(tb, x, z, spots, nil) then
								table.insert(spots, { id = id, x = x, z = z })
								break
							end
						end
					elseif id >= 1 then
						s.onTable[id] = false
					end
				end
				s.spots = spots
				if case % 2 == 0 then
					s.group[1], s.group[2] = "solids", "stripes"
				end
				s.seat = 1 + case % 2
				local seat = s.seat
				local level = 1 + case % 3
				local inputs = Computer.eightBall(s, level, case)
				t.eq(inputs[#inputs].verb, "shoot")
				for _, inp in inputs do
					local ok, why = EightBall.input(s, seat, inp.verb, inp.args)
					t.truthy(ok, `case {case}: {inp.verb} refused ({why})`)
				end
				t.eq(s.shots[seat], 1)
			end
		end
	)

	t.test("bumper pool: every level plays whole games to the end, the simultaneous opening included", function()
		local games, shots = 0, 0
		for _, levels in { { 1, 1 }, { 2, 2 }, { 3, 3 }, { 2, 1 } } do
			for seed = 1, 3 do
				local s = bumper(levels, seed * 7 + levels[2])
				t.truthy(s.done, `levels {levels[1]} v {levels[2]}, seed {seed}: the game did not finish`)
				t.truthy(s.winner == 1 or s.winner == 2)
				t.truthy(s.sunk[s.winner :: number] == 5 or s.how == "last_ball_wrong_cup")
				t.truthy(s.shots[1] >= 1 and s.shots[2] >= 1, "both struck in the opening")
				games += 1
				shots += s.shots[1] + s.shots[2]
			end
		end
		t.truthy(shots / games > 9 and shots / games < 80, `{shots / games} shots a game`)
	end)

	t.test("bumper pool: the best player beats the beginner; a game is the same game twice", function()
		local wins = 0
		for seed = 1, 4 do
			if bumper({ 3, 1 }, 300 + seed).winner == 1 then
				wins += 1
			end
			if bumper({ 1, 3 }, 400 + seed).winner == 2 then
				wins += 1
			end
		end
		t.truthy(wins >= 6, `the best player won {wins} of 8`)
		local x, y = bumper({ 2, 2 }, 5), bumper({ 2, 2 }, 5)
		t.deepEq(BumperPool.view(x), BumperPool.view(y))
	end)

	t.test("bumper pool practice: each computer player sinks its five alone", function()
		local shots: { number } = {}
		for level = 1, 3 do
			local s = bumper({ level }, 50 + level)
			t.truthy(s.done)
			t.eq(s.sunk[1], 5)
			shots[level] = s.shots[1]
			t.truthy(s.shots[1] >= 5 and s.shots[1] < 120, `level {level}: {s.shots[1]} shots`)
		end
	end)
end
