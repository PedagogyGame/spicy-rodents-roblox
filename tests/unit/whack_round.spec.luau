--!strict
-- Minigames/WhackAMole/Round, Rules and HighScores: the owner's rules as a pure seeded model the server keeps
-- (docs/reference/whack_a_mole: his browser game's pacing, rise and drop; +10 a hit, -2 a miss, never below
-- zero, one hit per rise), strikes judged at the moment they were made, and the refusals that keep a client's
-- word from being more than a stamped swing.
local HighScores = require("@shared/Minigames/WhackAMole/HighScores")
local Minigame = require("@shared/Minigames/Minigame")
local Round = require("@shared/Minigames/WhackAMole/Round")
local Rules = require("@shared/Minigames/WhackAMole/Rules")
local Rng = require("@shared/Util/Rng")
local Test = require("../lib/Test")

local DT = 1 / 60

-- a whole round with nobody striking: the moles decided, as the server would decide them
local function idle(seed: number): Round.State
	local s = Round.new(seed)
	while not Round.over(s) do
		Round.advance(s, DT)
	end
	return s
end

-- a player who strikes every mole `delay` seconds after it starts to rise (in the order of the round, one mallet)
local function player(seed: number, delay: number, keep: number?): Round.State
	local s = Round.new(seed)
	local done: { [number]: boolean } = {}
	local n = 0
	while not Round.over(s) do
		Round.advance(s, DT)
		for _, r in s.rises do
			if not done[r.id] and r.at + delay <= s.now then
				done[r.id] = true
				n += 1
				if keep == nil or n % keep ~= 0 then
					local t = math.max(r.at + delay, s.lastStrike + Round.MIN_GAP)
					if t <= s.now + Round.AHEAD and t < Round.SECONDS then
						Round.strike(s, r.hole, t)
					end
				end
			end
		end
	end
	return s
end

-- the unhit moles up at round time t
local function upAt(s: Round.State, t: number): number
	local n = 0
	for _, r in s.rises do
		if r.at <= t and t < r.at + r.dur and (r.hitAt == nil or t < r.hitAt) then
			n += 1
		end
	end
	return n
end

return function(t: Test.T)
	t.test("the round is seeded: the same seed gives the same moles, another seed others", function()
		local a, b, c = idle(7), idle(7), idle(8)
		t.eq(#a.rises, #b.rises)
		for i, r in a.rises do
			t.eq(r.hole, b.rises[i].hole)
			t.eq(r.at, b.rises[i].at)
			t.eq(r.dur, b.rises[i].dur)
		end
		local same = #a.rises == #c.rises
		if same then
			for i, r in a.rises do
				same = same and r.hole == c.rises[i].hole and r.at == c.rises[i].at
			end
		end
		t.falsy(same, "seed 8 is not seed 7")
	end)

	t.test("his pacing: first at 0.3 s, none in the count-in or after 45 s, one at a time then two", function()
		for seed = 1, 40 do
			local s = idle(seed)
			t.near(s.rises[1].at, Round.FIRST, 1e-9, "the first try is at 0.3 s and always finds a hole")
			t.truthy(#s.rises >= 40 and #s.rises <= 75, `{#s.rises} moles in a round`)
			local last = 0
			for i, r in s.rises do
				t.truthy(r.at >= 0 and r.at < Round.SECONDS, `mole {i} rises in the round`)
				local p = r.at / Round.SECONDS
				t.truthy(r.dur >= 1.55 - p * 0.6 - 1e-9 and r.dur <= 1.55 - p * 0.6 + 0.22 + 1e-9, "his stay")
				if i > 1 then
					t.truthy(r.at > s.rises[i - 1].at, "in order")
					t.truthy(r.at - s.rises[i - 1].at >= 0.76 - 0.42 - 1e-9, "never sooner than his quickest try")
				end
				-- never the hole that was just used (five holes and at most two up: another is always free)
				t.neq(r.hole, last, "not the same hole twice running")
				last = r.hole
				-- two in one hole never overlap
				for j = i + 1, #s.rises do
					local o = s.rises[j]
					if o.hole == r.hole then
						t.truthy(o.at >= r.at + r.dur - 1e-9, "a hole holds one mole at a time")
					end
				end
			end
			-- one up at a time for the first 35 % of the round, two at most after
			local two = false
			for k = 0, 4500 do
				local at = k / 100
				local n = upAt(s, at)
				t.truthy(n <= (if at < 0.35 * Round.SECONDS then 1 else 2), `{n} up at {at}`)
				two = two or n == 2
			end
			t.truthy(two, "two moles are up together some of the time late in the round")
		end
	end)

	t.test("rise, hold and drop: 0.17 s up easing out, 0.21 s down, smooth, and a hit mole drops at once", function()
		local r: Round.Rise = { id = 1, hole = 2, at = 10, dur = 1.4 }
		t.eq(Round.height(r, 9.99), 0)
		t.eq(Round.height(r, 10), 0)
		t.near(Round.height(r, 10 + Round.RISE / 2), 1 - 0.125, 1e-9, "ease out: 87.5 % up half way through")
		t.near(Round.height(r, 10 + Round.RISE), 1, 1e-9)
		t.eq(Round.height(r, 10.8), 1)
		t.near(Round.height(r, 10 + 1.4 - Round.FALL / 2), 0.75, 1e-9)
		t.eq(Round.height(r, 11.4), 0)
		-- no jumps anywhere: a 1/240 s step never moves it more than its fastest speed allows
		local was = 0
		for k = 1, 480 do
			local h = Round.height(r, 9.9 + k / 240)
			t.truthy(math.abs(h - was) <= 3 / Round.RISE / 240 + 1e-6, "smooth")
			was = h
		end
		-- the owner's window: up more than 22 %, and not within 45 % of the drop time of its start
		t.falsy(Round.hittable(r, 10.01), "barely out of the hole")
		t.truthy(Round.hittable(r, 10.05))
		t.truthy(Round.hittable(r, 10 + 1.4 - Round.LATE_CUT - 0.01))
		t.falsy(Round.hittable(r, 10 + 1.4 - Round.LATE_CUT + 0.01), "about to drop")
		r.hitAt = 10.5
		r.from = 1
		t.falsy(Round.hittable(r, 10.6), "hit already")
		t.near(Round.height(r, 10.5 + Round.FALL / 2), 0.25, 1e-9, "drops from where it was hit")
		t.eq(Round.height(r, 10.5 + Round.FALL), 0)
		t.eq(Round.height(r, 10.9), 0, "gone after the hit's drop, not at its own end")
	end)

	t.test("+10 a hit, -2 a miss, never below zero, one hit per rise", function()
		local s = Round.new(3)
		Round.advance(s, Round.READY + 0.5)
		local r = s.rises[1]
		t.truthy(r ~= nil)
		local empty = if r.hole == 1 then 2 else 1
		-- a miss at zero stays at zero
		local ok, why, out = Round.strike(s, empty, 0.31)
		t.truthy(ok, why)
		t.eq((out :: any).kind, "miss")
		t.eq(s.score, 0)
		t.eq(s.misses, 1)
		-- the mole: +10
		ok, why, out = Round.strike(s, r.hole, r.at + 0.12)
		t.truthy(ok, why)
		t.eq((out :: any).kind, "hit")
		t.eq((out :: any).id, r.id)
		t.eq(s.score, 10)
		t.eq(r.hitAt, r.at + 0.12)
		-- the same mole, dropping: nothing either way
		ok, why, out = Round.strike(s, r.hole, r.at + 0.24)
		t.truthy(ok, why)
		t.eq((out :: any).kind, "again")
		t.eq(s.score, 10)
		t.eq(s.hits, 1)
		-- once it has gone the hole is empty: a miss, 10 - 2
		Round.advance(s, 0.3)
		ok, why, out = Round.strike(s, r.hole, r.at + 0.12 + Round.FALL + 0.01)
		t.truthy(ok, why)
		t.eq((out :: any).kind, "miss")
		t.eq(s.score, 8)
		Round.advance(s, 2 - s.now)
		for k = 0, 5 do
			local at = 1.5 + k * 0.11
			local hole = 1
			while Round.at(s, hole, at) ~= nil do
				hole += 1
			end
			Round.strike(s, hole, at)
		end
		t.eq(s.score, 0, "never below zero")
		t.eq(s.hits + s.misses, 9)
		t.eq(s.strikes, 10)
		t.eq(s.last and s.last.kind, "miss")
	end)

	t.test("refused, with nothing scored: junk, early, ahead, late, out of order, too fast, time up", function()
		local s = Round.new(5)
		Round.advance(s, 1)
		t.eq(select(2, Round.strike(s, 1, -0.5)), "early", "in the count-in")
		Round.advance(s, Round.READY)
		local now = s.now
		for _, bad in { 0, 6, 2.5, -1, 0 / 0, "3", math.huge } do
			local ok, why = Round.strike(s, bad, now)
			t.falsy(ok)
			t.eq(why, "no such hole")
		end
		for _, bad in { 0 / 0, math.huge, -math.huge, "1", true } do
			local ok, why = Round.strike(s, 1, bad)
			t.falsy(ok)
			t.eq(why, "no time")
		end
		t.eq(select(2, Round.strike(s, 1, now + Round.AHEAD + 0.01)), "ahead")
		t.eq(select(2, Round.strike(s, 1, now - Round.MAX_LAG - 0.01)), "late")
		t.truthy((Round.strike(s, 1, now - 0.2)))
		t.eq(select(2, Round.strike(s, 2, now - 0.25)), "out of order")
		t.eq(select(2, Round.strike(s, 2, now - 0.2 + Round.MIN_GAP / 2)), "too fast")
		t.truthy((Round.strike(s, 2, now - 0.2 + Round.MIN_GAP)), "a whole swing later is fine")
		t.eq(s.strikes, 2)
		while s.now < Round.SECONDS + 0.2 do
			Round.advance(s, DT)
		end
		t.eq(select(2, Round.strike(s, 3, Round.SECONDS)), "time is up")
		t.falsy(Round.over(s), "the result waits GRACE for strikes stamped before the end")
		t.truthy((Round.strike(s, 3, Round.SECONDS - 0.25)), "one stamped before the end still counts")
		Round.advance(s, Round.GRACE)
		t.truthy(Round.over(s))
	end)

	t.test("lag: a strike judged at the moment it was made scores what the player saw", function()
		local s = Round.new(11)
		Round.advance(s, Round.READY + 0.3 + 0.12)
		local r = s.rises[1]
		-- the server is 0.15 s past the swing when it arrives; the mole is judged as it was at the swing
		local swing = r.at + 0.12
		Round.advance(s, 0.15)
		local ok, why, out = Round.strike(s, r.hole, swing)
		t.truthy(ok, why)
		t.eq((out :: any).kind, "hit")
		-- and a strike stamped at the very end of a mole's window, arriving after it dropped, still counts
		local s2 = Round.new(11)
		Round.advance(s2, Round.READY + 0.3)
		local r2 = s2.rises[1]
		local lastChance = r2.at + r2.dur - Round.LATE_CUT - 0.01
		while s2.now < r2.at + r2.dur + 0.2 do
			Round.advance(s2, DT)
		end
		ok, why, out = Round.strike(s2, r2.hole, lastChance)
		t.truthy(ok, why)
		t.eq((out :: any).kind, "hit")
	end)

	t.test("a hit frees its hole sooner: a good player sees more moles, the same on every replay", function()
		local more = 0
		for seed = 1, 20 do
			local none = idle(seed)
			local good = player(seed, 0.3)
			local again = player(seed, 0.3)
			t.eq(good.score, again.score, "the same strikes in the same order give the same round")
			t.eq(#good.rises, #again.rises)
			t.truthy(#good.rises >= #none.rises, `{#good.rises} >= {#none.rises}`)
			if #good.rises > #none.rises then
				more += 1
			end
			t.eq(good.score, good.hits * Round.HIT, "a player who never misses never loses a point")
			t.truthy(good.hits >= #good.rises - 3, `{good.hits} of {#good.rises}`)
			-- a player who lets every third mole go still never loses anything for it
			local fair = player(seed, 0.3, 3)
			t.eq(fair.misses, 0)
		end
		t.truthy(more >= 15, `hits sped the round up in {more} of 20`)
	end)

	t.test("too slow is a miss: a swing after the mole has dropped", function()
		local s = player(4, 1.6)
		t.truthy(s.misses > 0)
		t.truthy(s.score >= 0)
	end)

	t.test("Rules: the Minigame contract, the clock, the result after GRACE, a leaver's round ends", function()
		t.truthy(Minigame.check(Rules))
		t.eq(Rules.def.seats, 1)
		t.eq(Rules.def.money, "none")
		t.truthy(Rules.serverVerbs and Rules.serverVerbs.stop)
		t.falsy(Rules.serverVerbs and Rules.serverVerbs.whack)
		local g = Minigame.start(Rules, 1, 99)
		local step = Rules.step :: (any, number) -> ()
		local view = Rules.view :: (any) -> { [string]: any }
		local v = view(g.state)
		t.eq(v.ready, Round.READY)
		t.eq(v.left, Round.SECONDS)
		t.eq(v.score, 0)
		t.truthy(v.freePlay)
		step(g.state, Round.READY + 10)
		v = view(g.state)
		t.eq(v.ready, 0)
		t.eq(v.left, Round.SECONDS - 10)
		t.eq(select(2, Minigame.input(g, 1, "whack", { 9, 9 })), "no such hole")
		t.eq(select(2, Minigame.input(g, 1, "dance", {})), "verb")
		step(g.state, Round.SECONDS - 10)
		t.eq(Minigame.result(g), nil, "not before GRACE")
		step(g.state, Round.GRACE)
		local r = Minigame.result(g) :: any
		t.truthy(r and r.done)
		t.eq(r.scores[1], 0)
		t.falsy(r.stopped)
		local g2 = Minigame.start(Rules, 1, 99)
		step(g2.state, 5);
		(Rules.gone :: any)(g2.state, 1)
		local r2 = Minigame.result(g2) :: any
		t.truthy(r2 and r2.done and r2.stopped)
	end)

	t.test("the board: house rounds to beat, best first, five places, nothing for zero", function()
		local b = HighScores.new()
		t.eq(#b.entries, HighScores.SIZE)
		t.eq(HighScores.place(b, 0), nil)
		local low = HighScores.HOUSE[HighScores.SIZE].score
		t.eq(HighScores.place(b, low), nil, "a tie stands below the house")
		t.eq(HighScores.add(b, "Ben", low + 1), 5)
		t.eq(HighScores.add(b, "A very long name indeed for a board", 900), 1)
		t.eq(#b.entries, HighScores.SIZE)
		t.eq(b.entries[1].name, string.sub("A very long name indeed for a board", 1, HighScores.NAME_MAX))
		t.eq(b.entries[5].name, "CHARCOAL", "the lowest falls off")
		t.eq(HighScores.lines(b)[1], `1. {b.entries[1].name}  900`)
		t.eq(HighScores.list(b)[1].score, 900)
		t.eq(HighScores.list(b)[5].name, "CHARCOAL")
	end)

	-- a hand at the cabinet: strikes the first mole it sees `react` seconds after it starts up, needs `move`
	-- seconds between two strikes, and now and then (`slip`) strikes the next hole instead
	local function hand(seed: number, react: number, move: number, slip: number): number
		local s = Round.new(seed)
		local slips = Rng.new(seed + 1000)
		local free = 0
		while not Round.over(s) do
			Round.advance(s, DT)
			local now = s.now
			if now >= free and now < Round.SECONDS then
				for _, r in s.rises do
					if now >= r.at + react and Round.hittable(r, now) then
						local hole = if slips.next() < slip then r.hole % Round.HOLES + 1 else r.hole
						Round.strike(s, hole, now)
						free = now + move
						break
					end
				end
			end
		end
		return s.score
	end

	local function mean(react: number, move: number, slip: number): number
		local sum = 0
		for seed = 1, 12 do
			sum += hand(seed, react, move, slip)
		end
		return sum / 12
	end

	t.test("the house board: a first round reaches the bottom, only a quick and sure hand tops it", function()
		local H = HighScores.HOUSE
		local quick = mean(0.35, 0.25, 0)
		local steady = mean(0.55, 0.45, 0.08)
		local casual = mean(0.7, 0.55, 0.1)
		local first = mean(0.9, 0.7, 0.15)
		t.truthy(quick > H[1].score, `a quick sure hand ({quick}) tops the house ({H[1].score})`)
		t.truthy(steady > H[3].score and steady < H[1].score, `a steady hand ({steady}) reaches the middle`)
		t.truthy(casual > H[4].score and casual < H[2].score, `a casual hand ({casual}) gets on the board`)
		t.truthy(first > H[5].score and first < H[3].score, `a first round ({first}) reaches the bottom`)
	end)
end
