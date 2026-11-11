--!strict
-- Minigames/Jenga/Physics (checklist JEN-P3, JEN-P4, JEN-P5, JEN-P6, JEN-P8; JEN-R3): the hand on a block
-- (loose follows at once, snug comes in jerks with a creak, load-bearing only creeps), what the pull does to
-- the tower (speed, straightness and tightness; a push through the middle against a drag from the side),
-- setting a block down, the rocking of a tall heavy thing (it hangs, then settles or goes), what the tower
-- remembers, an untouched tower standing for ever, energy that never grows, determinism and cost.
local Layout = require("@shared/Minigames/Jenga/Layout")
local Physics = require("@shared/Minigames/Jenga/Physics")
local Stability = require("@shared/Minigames/Jenga/Stability")
local Tower = require("@shared/Minigames/Jenga/Tower")

local G = Layout.GRAVITY
local L = Layout.BLOCK_L
local DT = Physics.DT

local function take(tw: Tower.Tower, level: number, slot: number): number
	local id = tw.levels[level][slot]
	assert(id ~= 0, "no block there")
	tw.levels[level][slot] = 0
	tw.blocks[id].level = 0
	Tower.touch(tw)
	return id
end

-- timber all the same thickness, with the levels in `thin` standing on their middle block alone
local function uniform(thin: { number }?): Tower.Tower
	local tw = Tower.new(1)
	for _, b in tw.blocks do
		b.dt = 0
	end
	for _, level in thin or {} do
		take(tw, level, 1)
		take(tw, level, 3)
	end
	Tower.touch(tw)
	return tw
end

type Pull = { fell: boolean, out: boolean, peak: number, seconds: number, creaks: number, lag: number }

-- draw a block at a hand speed (studs/s), the hand wandering `wobble` studs off the line
local function pull(tw: Tower.Tower, level: number, slot: number, speed: number, wobble: number, push: boolean?): Pull
	assert(Physics.grab(tw, level, slot, push == true))
	local goal, time, peak, creaks, lag = 0, 0, 0, 0, 0
	while tw.held ~= 0 and not tw.fallen and time < 40 do
		local b = tw.blocks[tw.held]
		goal = math.min(goal + speed * DT, b.along + 0.4)
		Physics.drag(tw, goal, wobble * math.sin(time * 7))
		Physics.step(tw)
		time += DT
		peak = math.max(peak, Physics.danger(tw))
		if tw.held ~= 0 then
			lag = math.max(lag, tw.hand - b.along)
		end
	end
	local out = tw.inHand ~= 0
	for _ = 1, 300 do
		Physics.step(tw)
		peak = math.max(peak, Physics.danger(tw))
	end
	for _, e in Tower.drain(tw) do
		if e.kind == "creak" then
			creaks += 1
		end
	end
	return { fell = tw.fallen ~= nil, out = out, peak = peak, seconds = time, creaks = creaks, lag = lag }
end

local function still(tw: Tower.Tower): string
	local c = Tower.clone(tw)
	c.step = 0
	return Tower.encode(c)
end

return function(t)
	t.test("JEN-P6 an untouched tower stands for ever with no movement at all (the 60 s check)", function()
		for seed = 1, 5 do
			local tw = Tower.new(seed)
			local before = still(tw)
			local an = Stability.ensure(tw)
			for i = 0, 17 do
				for d = 1, 2 do
					t.truthy(
						an.bL[Stability.at(i, d)] > 0.5 and an.bR[Stability.at(i, d)] > 0.5,
						"positive margin at every level"
					)
				end
			end
			Physics.run(tw, 60)
			t.eq(tw.step, 3600)
			t.eq(tw.fallen, nil)
			t.eq(still(tw), before, `seed {seed}: not one number changed in 60 s`)
			t.truthy(Physics.atRest(tw))
			t.eq(Physics.danger(tw), 0)
			t.eq(#tw.events, 0)
		end
	end)

	t.test(
		"JEN-P3 the hand: a loose block follows at once, a snug one jerks and creaks, a load-bearing one creeps",
		function()
			-- seed 1, level 13 slot 1 carries nothing
			local tw = Tower.new(1)
			local f = Physics.feel(tw, 13, 1) :: Physics.Feel
			t.eq(f.kind, "loose")
			assert(Physics.grab(tw, 13, 1, false))
			for k = 1, 12 do
				Physics.drag(tw, k * DT * 1.0, 0)
				Physics.step(tw)
			end
			local b = tw.blocks[tw.held]
			t.truthy(tw.hand - b.along < 0.01, `a loose block is {tw.hand - b.along} behind the hand after 0.2 s`)
			t.truthy(b.along > 0.18)

			-- timber all alike: a block at level 9 carries a third of 27 blocks. It can be started, but it holds,
			-- lets go and catches again
			tw = uniform()
			f = Physics.feel(tw, 9, 1) :: Physics.Feel
			t.near(f.load, 9, 1e-6)
			t.eq(f.kind, "tight")
			t.falsy(f.stuck)
			assert(Physics.grab(tw, 9, 1, false))
			local moving, stopped, creaks, lag = 0, 0, 0, 0
			local last = 0
			for k = 1, 600 do
				Physics.drag(tw, k * DT * 0.2, 0)
				Physics.step(tw)
				if tw.held == 0 then
					break
				end
				local blk = tw.blocks[tw.held]
				if blk.along > last + 1e-9 then
					moving += 1
				else
					stopped += 1
				end
				last = blk.along
				lag = math.max(lag, tw.hand - blk.along)
			end
			for _, e in Tower.drain(tw) do
				if e.kind == "creak" then
					creaks += 1
				end
			end
			t.truthy(lag > 0.1, `the hand runs {lag} ahead of a tight block`)
			t.truthy(moving > 20 and stopped > 20, `it comes in jerks: moved {moving} steps, held {stopped}`)
			t.truthy(creaks >= 3, `and creaks each time it lets go ({creaks})`)

			-- a block at level 2 carries a third of 48: no hand can start it, it only creeps
			tw = uniform()
			f = Physics.feel(tw, 2, 1) :: Physics.Feel
			t.truthy(f.stuck)
			assert(Physics.grab(tw, 2, 1, false))
			for _ = 1, 120 do
				Physics.drag(tw, L, 0)
				Physics.step(tw)
			end
			local crept = tw.blocks[tw.held].along
			t.truthy(crept > 0.02 and crept < 0.12, `in two seconds it has crept {crept}`)
			t.truthy(tw.hand - crept >= Physics.MAX_FORCE / Physics.KH - 1e-6, "with the arm at full stretch")
		end
	)

	t.test("JEN-P3 slow and straight on a loose block is safe; a yank on a block that carries weight is not", function()
		-- level 4 stands on its middle block alone, so the tower is thin in X there; levels 15 and 17 run along X
		local loose = pull(uniform({ 4 }), 17, 1, 0.3, 0)
		t.truthy(loose.out and not loose.fell)
		t.truthy(loose.peak < 0.02, `a light block drawn slowly barely stirs the tower ({loose.peak})`)

		local crawl = pull(uniform({ 4 }), 15, 1, 0.3, 0)
		t.truthy(crawl.out and not crawl.fell, "a snug block drawn slowly and straight comes out")
		t.truthy(crawl.peak < 0.05, `and the tower hardly rocks ({crawl.peak})`)

		local tw = uniform({ 4 })
		local yank = pull(tw, 15, 1, 8, 0)
		t.truthy(yank.fell, "the same block yanked brings it down")
		local fail = tw.fallen :: Tower.Failure
		t.eq(fail.dir, "x")
		t.truthy(fail.level == 3 or fail.level == 4, `it goes at the thin level (joint {fail.level})`)
		t.eq(fail.why, "sway")

		-- the tighter the block, the harder the same yank shoves the tower
		local light = pull(uniform({ 4 }), 17, 1, 8, 0)
		t.truthy(not light.fell and light.peak > loose.peak * 3, `yanking even a light block is felt ({light.peak})`)
		t.truthy(light.peak < 0.5)
	end)

	t.test(
		"JEN-P3 straightness counts, and pushing a middle block through is gentler than dragging a side block",
		function()
			local straight = pull(uniform({ 4 }), 15, 1, 1.2, 0)
			local wander = pull(uniform({ 4 }), 15, 1, 1.2, 0.2)
			t.truthy(wander.fell or wander.peak > straight.peak * 2, "a wandering hand rocks the tower more")
			local side = pull(uniform({ 4 }), 15, 1, 1.2, 0.2, false)
			local middle = pull(uniform({ 4 }), 15, 2, 1.2, 0.2, true)
			t.truthy(side.fell, "the side block dragged with a wandering hand brings it down")
			t.truthy(middle.out and not middle.fell, "the middle block pushed through with the same hand does not")
			t.truthy(middle.peak < 0.2, `({middle.peak})`)
			-- the same block, the same hand: pushed is gentler than dragged
			local dragged = pull(uniform({ 4 }), 15, 2, 1.2, 0.2, false)
			local pushed = pull(uniform({ 4 }), 15, 2, 1.2, 0.2, true)
			t.truthy(pushed.peak < dragged.peak, `pushed {pushed.peak} against dragged {dragged.peak}`)
		end
	)

	t.test("JEN-P3 the tower hangs at the tipping point, then settles or goes: worked out, not rolled", function()
		-- kick the part above joint 3 (under the thin level 4) toward +X with a set share of the energy it
		-- takes to carry its weight over the edge
		local function kick(share: number): (Tower.Tower, number)
			local tw = uniform({ 4 })
			local an = Stability.ensure(tw)
			local j = Stability.at(3, 1)
			t.truthy(an.active[j])
			local weight, h, b = G * an.mass[4], an.h[4], an.bR[j]
			local barrier = weight * b * b / (2 * h)
			tw.omX[4] = math.sqrt(2 * share * barrier / an.inertia[j])
			local time = 0
			while not tw.fallen and time < 30 do
				Physics.step(tw)
				time += DT
				if Physics.atRest(tw) and not tw.stale then
					break
				end
			end
			return tw, time
		end
		local low, lowTime = kick(0.5)
		t.eq(low.fallen, nil, "half the energy: it rocks and settles")
		t.truthy(Physics.atRest(low), "a rest state is reached")
		t.truthy(lowTime > 0.5 and lowTime < 20, `after {lowTime} s`)
		local high, highTime = kick(4)
		local f = high.fallen :: Tower.Failure
		t.truthy(f, "far more than enough: it goes")
		t.eq(f.level, 3)
		t.eq(f.dir, "x")
		t.eq(f.sign, 1)
		t.eq(f.why, "sway")
		-- between the two there is one threshold: below it the tower always settles, above it always goes
		local lo, hi = 0.5, 4
		for _ = 1, 14 do
			local mid = (lo + hi) / 2
			if kick(mid).fallen then
				hi = mid
			else
				lo = mid
			end
		end
		t.truthy(
			lo > 0.9 and lo < 2.5,
			`it takes {lo} times the energy of the weight's climb to the edge (the knocks lose some)`
		)
		for _, share in { lo * 0.7, lo * 0.9, lo * 0.99 } do
			t.eq(kick(share).fallen, nil, `{share} settles`)
		end
		for _, share in { hi * 1.01, hi * 1.3, hi * 2 } do
			t.truthy(kick(share).fallen, `{share} goes`)
		end
		-- and just past the threshold it hangs before it goes
		local _, nearTime = kick(hi * 1.01)
		t.truthy(nearTime > highTime * 1.8, `it hangs ({nearTime} s against {highTime} s for a hard shove)`)
		-- the same kick the other way goes the other way
		local tw = uniform({ 4 })
		tw.omX[4] = -3
		Physics.run(tw, 5)
		t.eq((tw.fallen :: Tower.Failure).sign, -1)
	end)

	t.test("energy never grows, and a rocked tower comes to rest", function()
		for _, case in { { 3, 0.3 }, { 3, 0.8 }, { 7, 0.6 } } do
			local tw = uniform({ 4, 8 })
			local an = Stability.ensure(tw)
			local i = case[1]
			local j = Stability.at(i, 1)
			local barrier = G * an.mass[i + 1] * an.bR[j] ^ 2 / (2 * an.h[i + 1])
			tw.omX[i + 1] = math.sqrt(2 * case[2] * barrier / an.inertia[j])
			local e0 = Physics.energy(tw)
			t.truthy(e0 > 0)
			local worst, steps = 0, 0
			while steps < 60 * 40 and not (Physics.atRest(tw) and not tw.stale) do
				Physics.step(tw)
				steps += 1
				worst = math.max(worst, Physics.energy(tw) / e0)
			end
			t.eq(tw.fallen, nil)
			t.truthy(worst <= 1.001, `joint {i}: energy reached {worst} of what it started with`)
			t.truthy(Physics.atRest(tw), `joint {i}: at rest after {steps / 60} s`)
			t.eq(Physics.energy(tw), 0)
			-- and it stays exactly there
			local before = still(tw)
			Physics.run(tw, 5)
			t.eq(still(tw), before)
		end
	end)

	t.test("JEN-P4 set down gently and square adds nothing; dropped off-centre it jolts the tower", function()
		local function withBlock(): Tower.Tower
			local tw = uniform({ 4 })
			tw.inHand = take(tw, 10, 2)
			return tw
		end
		local tw = withBlock()
		Stability.ensure(tw)
		t.truthy(Physics.place(tw, 2, 0, 0, 0))
		t.eq(tw.inHand, 0)
		t.eq(#tw.levels, 19)
		t.truthy(Physics.atRest(tw), "gently and square: nothing moves")
		Physics.run(tw, 3)
		t.eq(Physics.danger(tw), 0)
		t.eq(tw.fallen, nil)
		-- the same block dropped, half a width off square (level 19 runs along X, the thin direction)
		tw = withBlock()
		t.truthy(Physics.place(tw, 2, 0.4, 0, 6))
		t.near(
			tw.blocks[tw.levels[19][2]].along,
			Physics.PLACE_ALONG,
			1e-9,
			"no further off square than a block can sit"
		)
		t.falsy(Physics.atRest(tw), "dropped off-centre: the tower is jolted")
		local peak = 0
		for _ = 1, 180 do
			Physics.step(tw)
			peak = math.max(peak, Physics.danger(tw))
		end
		t.truthy(peak > 0.001, `it rocks ({peak})`)
		-- harder and further off is worse
		local soft = withBlock()
		Physics.place(soft, 2, 0.1, 0, 1)
		local softPeak = 0
		for _ = 1, 180 do
			Physics.step(soft)
			softPeak = math.max(softPeak, Physics.danger(soft))
		end
		t.truthy(softPeak < peak)
		-- an unfinished top level shifts the weight toward the block that is on it
		tw = withBlock()
		local before = Stability.ensure(tw).base[Stability.at(0, 2)]
		Physics.place(tw, 3, 0, 0, 0)
		local after = Stability.ensure(tw).base[Stability.at(0, 2)]
		t.truthy(after > before + 0.005, `the tower's weight moved {after - before} toward the new block`)
		-- only into a free place on the level being built, and only with a block in hand
		t.falsy((Physics.place(tw, 3, 0, 0, 0)), "no block in hand")
		tw.inHand = take(tw, 11, 2)
		local ok, why = Physics.place(tw, 3, 0, 0, 0)
		t.falsy(ok, "that place is taken")
		t.truthy(why)
		t.falsy((Physics.place(tw, 2, 0 / 0, 0, 0)), "not a number")
		t.truthy(Physics.place(tw, 1, 0, 0, 0))
	end)

	t.test(
		"JEN-P5 the tower remembers: abandoned blocks, dragged levels and rocked stacks stay where they got to",
		function()
			-- JEN-R3: a block may be given up before a third of the way, and stays where it was left
			local tw = Tower.new(1)
			assert(Physics.grab(tw, 13, 1, false))
			for _ = 1, 30 do
				Physics.drag(tw, 0.3, 0)
				Physics.step(tw)
			end
			t.truthy(Physics.letGo(tw))
			t.eq(tw.held, 0)
			Physics.run(tw, 2)
			t.near(tw.blocks[tw.levels[13][1]].along, 0.3, 0.01, "left where it was let go")
			-- beyond a third it is yours
			assert(Physics.grab(tw, 13, 1, false))
			for _ = 1, 30 do
				Physics.drag(tw, 0.6, 0)
				Physics.step(tw)
			end
			local ok, why = Physics.letGo(tw)
			t.falsy(ok)
			t.eq(why, "it is yours now")
			t.falsy((Physics.grab(tw, 11, 2, false)), "one block at a time")

			-- a block that carries most of its level takes the levels above with it (seed 1: level 14's middle)
			tw = Tower.new(1)
			local f = Physics.feel(tw, 14, 2) :: Physics.Feel
			t.truthy(f.share > 0.7)
			assert(Physics.grab(tw, 14, 2, false))
			for _ = 1, 90 do
				Physics.drag(tw, 0.25, 0)
				Physics.step(tw)
			end
			local dragged = tw.shiftZ[15]
			t.truthy(dragged > 0.05, `the levels above came {dragged} with it`)
			Physics.letGo(tw)
			Physics.run(tw, 3)
			t.eq(tw.shiftZ[15], dragged, "and stayed there")
			local p = Stability.poses(tw)
			t.truthy(p[(54 - 1) * 6 + 3] > 0.05, "which shows: the top is off to one side")
			t.truthy(Stability.margin(tw) < Stability.margin(Tower.new(1)) - 0.04, "and counts")
			-- poked through with a fingertip, the weight above mostly stays put
			local poked = Tower.new(1)
			assert(Physics.grab(poked, 14, 2, true))
			for _ = 1, 90 do
				Physics.drag(poked, 0.25, 0)
				Physics.step(poked)
			end
			t.truthy(poked.shiftZ[15] < dragged * 0.6, "a push drags the tower less than a pull")

			-- a stack that has rocked up and knocked back down has walked a hair
			tw = uniform({ 4 })
			tw.omX[4] = 0.25
			local clunks = 0
			for _ = 1, 600 do
				Physics.step(tw)
			end
			for _, e in Tower.drain(tw) do
				if e.kind == "clunk" then
					clunks += 1
				end
			end
			t.truthy(clunks >= 1, "it knocked back down")
			t.truthy(tw.shiftX[4] ~= 0, "and did not come back to quite where it was")
		end
	)

	t.test("taps: free on a loose block, felt by the tower on a tight one", function()
		local tw = Tower.new(1)
		local f = Physics.tap(tw, 13, 1) :: Physics.Feel
		t.eq(f.kind, "loose")
		t.truthy(Physics.atRest(tw), "knocking on a loose block moves nothing")
		local ev = Tower.drain(tw)
		t.eq(ev[1].kind, "tap")
		t.eq(ev[1].a, tw.levels[13][1])
		f = Physics.tap(tw, 9, 2) :: Physics.Feel
		t.eq(f.kind, "tight")
		t.falsy(Physics.atRest(tw), "a tight one passes the knock on")
		Physics.run(tw, 3)
		t.truthy(Physics.atRest(tw))
		t.eq(tw.fallen, nil)
		t.eq(Physics.tap(tw, 40, 1), nil)
	end)

	t.test("nothing skips: at any hand speed the block moves no faster than a hand, and leaves exactly once", function()
		local tw = Tower.new(1)
		assert(Physics.grab(tw, 13, 1, false))
		Physics.drag(tw, 1e9, 0)
		t.near(tw.goal, L + 0.2, 1e-9, "the goal is kept inside the reach")
		local id = tw.held
		local last, steps = 0, 0
		while tw.held ~= 0 and steps < 600 do
			Physics.step(tw)
			steps += 1
			local along = tw.blocks[id].along
			if tw.held ~= 0 then
				t.truthy(along - last <= Physics.MAX_HAND_SPEED * DT + 1e-9, "no faster than the hand")
				last = along
			end
		end
		t.truthy(steps >= math.floor(L / (Physics.MAX_HAND_SPEED * DT)), `it took {steps} steps`)
		t.eq(tw.inHand, id)
		t.eq(tw.moved, 1)
		t.eq(tw.blocks[id].level, 0)
		t.eq(tw.levels[13][1], 0)
		t.eq(tw.rev, 2)
		local outs = 0
		for _, e in Tower.drain(tw) do
			if e.kind == "out" then
				outs += 1
			end
		end
		t.eq(outs, 1)
		-- with a block in hand nothing else can be grabbed
		t.falsy((Physics.grab(tw, 11, 2, false)))
		-- nonsense samples are ignored
		assert(Physics.place(tw, 2, 0, 0, 0))
		assert(Physics.grab(tw, 11, 2, false))
		Physics.drag(tw, 0 / 0, 0)
		t.eq(tw.goal, 0)
		Physics.drag(tw, 0.1, 99)
		t.eq(tw.handLat, Physics.LAT_MAX)
	end)

	t.test("determinism: the same tower and the same inputs give the same bytes", function()
		local function run(seed: number): string
			local tw = Tower.new(seed)
			local s = 12345
			local function rnd(): number
				s = (s * 1103515245 + 12345) % 2147483648
				return s / 2147483648
			end
			for move = 1, 6 do
				local level, slot = 0, 0
				for _ = 1, 50 do
					level, slot = 1 + math.floor(rnd() * 17), 1 + math.floor(rnd() * 3)
					local f = Physics.feel(tw, level, slot)
					if Tower.legal(tw, level, slot) and f and f.kind ~= "tight" then
						break
					end
				end
				Physics.tap(tw, level, slot)
				if Physics.grab(tw, level, slot, move % 2 == 0) then
					local goal = 0
					for _ = 1, 900 do
						if tw.held == 0 or tw.fallen then
							break
						end
						goal += (0.5 + rnd()) * DT
						Physics.drag(tw, goal, (rnd() - 0.5) * 0.1)
						Physics.step(tw)
					end
				end
				if tw.inHand ~= 0 then
					local _, free = Tower.building(tw)
					Physics.place(tw, free[1], (rnd() - 0.5) * 0.2, 0, rnd() * 3)
				end
				Physics.run(tw, 2)
			end
			return Tower.encode(tw)
		end
		local a, b = run(5), run(5)
		t.eq(a, b)
		t.truthy(#a > 2000)
		t.neq(run(6), a)
	end)

	t.test("it is cheap: a quiet tower costs almost nothing, a pull a few tens of microseconds a step", function()
		local tw = Tower.new(3)
		local started = os.clock()
		for _ = 1, 20000 do
			Physics.step(tw)
		end
		local quiet = (os.clock() - started) / 20000 * 1e6
		t.truthy(quiet < 20, `a quiet step costs {quiet} us`)
		tw = uniform({ 4 })
		assert(Physics.grab(tw, 15, 2, true))
		local steps = 0
		started = os.clock()
		while tw.held ~= 0 and not tw.fallen and steps < 2000 do
			steps += 1
			Physics.drag(tw, steps * DT * 0.8, 0.05)
			Physics.step(tw)
		end
		local busy = (os.clock() - started) / steps * 1e6
		-- the game needs 60 steps a second: under 1 ms a step is under 6 % of one core
		t.truthy(busy < 1000, `a step while drawing a block costs {busy} us`)
	end)
end
