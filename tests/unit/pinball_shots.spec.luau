--!strict
-- Minigames/Pinball/Shots: each table's shot book, and the tables held to it. A shot a rule is built on must
-- be makeable by timing alone, so its window (how many ticks of flip timing in a row reach it, from a cradled
-- ball) is pinned here per table: the main shots at a fair two screen frames or near it, every letter and
-- lock in reach of some flipper. Also here: the rule sheets' "what to shoot for now" (sheet.wants) names real,
-- makeable shots; SPACE SQUIRREL's pods tell a soft shot from a hard one; and the WIZARD computer player,
-- aiming by the book through the buttons alone, reaches each table's goal (PIN-R6 "one clear goal").
local Bot = require("@shared/Minigames/Pinball/Bot")
local Machine = require("@shared/Minigames/Pinball/Machine")
local Physics = require("@shared/Minigames/Pinball/Physics")
local Shots = require("@shared/Minigames/Pinball/Shots")
local Tables = require("@shared/Minigames/Pinball/Tables")
local Test = require("../lib/Test")

local EV = Physics.EV
local acorn = Tables.need("pinball_acorn")
local spicy = Tables.need("pinball_rodent")
local space = Tables.need("pinball_space")
local LEFT, RIGHT = 1, 2

-- the window for a named element from one flipper (0 when that flipper cannot reach it)
local function ticks(tbl: Machine.Table, code: number, ref: number, flipper: number): number
	local w = Shots.best(Shots.book(tbl), Machine.key(code, ref), flipper)
	return if w then w.ticks else 0
end

local function either(tbl: Machine.Table, code: number, ref: number): number
	return math.max(ticks(tbl, code, ref, LEFT), ticks(tbl, code, ref, RIGHT))
end

-- play whole games with a computer player and count how many of them say each callout at least once
-- (worked out once per table and level: two specs read the same games)
local PLAYED: { [string]: { said: { [number]: number }, scores: { number } } } = {}
local GAMES = 21
local function games(tbl: Machine.Table, level: number): ({ [number]: number }, { number })
	local memo = PLAYED[`{tbl.id}:{level}`]
	if memo then
		return memo.said, memo.scores
	end
	local n = GAMES
	local said: { [number]: number } = {}
	local scores: { number } = {}
	local out: { number } = {}
	for seed = 1, n do
		local m = Machine.new(tbl, seed, 1)
		local bot = Bot.new(level, seed * 31 + level)
		local seen: { [number]: boolean } = {}
		local guard = 0
		while m.phase ~= Machine.PHASE.OVER and guard < 240 * 3600 do
			Machine.step(tbl, m, Bot.step(bot, tbl, m), out)
			for i = 1, #out, 3 do
				if out[i] == Machine.CUE.SAY then
					seen[out[i + 1]] = true
				end
			end
			table.clear(out)
			guard += 1
		end
		for id in seen do
			said[id] = (said[id] or 0) + 1
		end
		table.insert(scores, m.scores[1])
	end
	table.sort(scores)
	PLAYED[`{tbl.id}:{level}`] = { said = said, scores = scores }
	return said, scores
end

return function(t: Test.T)
	t.test("the book is measured from the table: one trial for every tick of delay, the same every time", function()
		for _, id in Tables.IDS do
			local tbl = Tables.need(id)
			local book = Shots.book(tbl)
			t.eq(book, Shots.book(tbl), "worked out once and kept")
			for i = 1, tbl.c.nFlip do
				local trials = book.trials[i]
				t.truthy(#trials > 100, `{id} flipper {i}: {#trials} trials`)
				for n = 2, #trials do
					t.eq(trials[n].delay, trials[n - 1].delay + 1)
					t.truthy(trials[n].along >= trials[n - 1].along - 1e-9, "the ball only rolls outward")
				end
				for kk, w in book.windows[i] do
					t.eq(w.key, kk)
					t.eq(w.flipper, i)
					t.eq(w.ticks, w.to - w.from + 1)
					t.truthy(w.along > -0.15 and w.along < 1.1)
					t.truthy(Shots.name(tbl, kk) ~= "")
				end
			end
			t.truthy(#book.keys >= 8, `{id}: at least eight things can be aimed at ({#book.keys})`)
		end
	end)

	t.test("the two flippers of a symmetric table have mirrored books", function()
		-- SPACE SQUIRREL is laid out as a mirror image: what the left flipper makes of the left ramp, the right
		-- flipper makes of the right one
		local ix = space.ix
		t.near(
			ticks(space, EV.RAIL_OUT, ix.rail.ramp_l, LEFT),
			ticks(space, EV.RAIL_OUT, ix.rail.ramp_r, RIGHT),
			1,
			"the backhand ramp"
		)
		t.near(
			ticks(space, EV.RAIL_OUT, ix.rail.ramp_r, LEFT),
			ticks(space, EV.RAIL_OUT, ix.rail.ramp_l, RIGHT),
			1,
			"the ramp across the table"
		)
	end)

	t.test(
		"PIN-R6 ACORN ATTACK: every letter of the bank is in the left flipper's backhand, the gentlest shot there is",
		function()
			local ix = acorn.ix
			-- (a ball let go from the cradle rolls straight off down the flipper, so the backhand is over in a
			-- tenth of a second: each letter is a few ticks, the top one, N, the least)
			local sum, fair = 0, 0
			for _, name in { "acorn_a", "acorn_c", "acorn_o", "acorn_r", "acorn_n" } do
				local w = ticks(acorn, EV.DROP, ix.target[name], LEFT)
				t.truthy(w >= 2, `{name}: {w} ticks`)
				sum += w
				if w >= 4 then
					fair += 1
				end
			end
			t.truthy(fair >= 4, `{fair} of the five letters have a window of a screen frame or more`)
			t.truthy(sum >= 24, `the bank as a whole is {sum} ticks wide (a tenth of a second of timing)`)
			t.truthy(
				ticks(acorn, EV.SPINNER, ix.sensor.spinner, RIGHT) >= Shots.FAIR_TICKS,
				"the spinner lane is the right flipper's backhand"
			)
			t.truthy(either(acorn, EV.STANDUP, ix.target.oak_r) >= 4, "the right oak target (the extra ball)")
			for i = 1, 3 do
				t.truthy(either(acorn, EV.BUMPER, i) >= 6, `bumper {i} can be shot at`)
			end
		end
	)

	t.test(
		"PIN-R6 SPICY RODENT: the wire is a fair shot from either flipper; the bite and all five letters are in reach",
		function()
			local ix = spicy.ix
			local wireL = ticks(spicy, EV.RAIL_OUT, ix.rail.wire, LEFT)
			local wireR = ticks(spicy, EV.RAIL_OUT, ix.rail.wire, RIGHT)
			t.truthy(wireR >= Shots.FAIR_TICKS, `the wire from the right flipper: {wireR} ticks`)
			t.truthy(wireL >= 6, `and from the left (a backhand): {wireL} ticks`)
			t.truthy(wireR <= 16 and wireL <= 16, "but it still takes timing: the fast table")
			t.truthy(ticks(spicy, EV.SAUCER, ix.saucer.bite, LEFT) >= 5, "the bite is the left flipper's shot")
			t.truthy(ticks(spicy, EV.SAUCER, ix.saucer.bite, RIGHT) >= 3, "and can be had from the right")
			for _, name in { "spicy_s", "spicy_p", "spicy_i", "spicy_c", "spicy_y" } do
				local w = either(spicy, EV.STANDUP, ix.target[name])
				t.truthy(w >= 3, `{name}: {w} ticks`)
			end
		end
	)

	t.test(
		"PIN-R6 SPACE SQUIRREL: both ramps from both flippers, the orbit and the pods by the backhand: the flow table",
		function()
			local ix = space.ix
			for _, ramp in { "ramp_l", "ramp_r" } do
				for flipper = LEFT, RIGHT do
					local w = ticks(space, EV.RAIL_OUT, ix.rail[ramp], flipper)
					t.truthy(w >= 6, `{ramp} from flipper {flipper}: {w} ticks`)
				end
			end
			-- each ramp is a fair shot from the flipper on its own side
			t.truthy(ticks(space, EV.RAIL_OUT, ix.rail.ramp_l, LEFT) >= Shots.FAIR_TICKS)
			t.truthy(ticks(space, EV.RAIL_OUT, ix.rail.ramp_r, RIGHT) >= Shots.FAIR_TICKS)
			for flipper = LEFT, RIGHT do
				local orbit = ticks(space, EV.ROLLOVER, ix.sensor.orbit_top, flipper)
				t.truthy(orbit >= 10, `the orbit from flipper {flipper}: {orbit} ticks`)
			end
			t.truthy(ticks(space, EV.SAUCER, ix.saucer.pod_1, LEFT) >= Shots.FAIR_TICKS, "the left pod")
			t.truthy(ticks(space, EV.SAUCER, ix.saucer.pod_2, RIGHT) >= Shots.FAIR_TICKS, "the right pod")
			for _, name in { "fuel_f", "fuel_u", "fuel_e", "fuel_l" } do
				local w = either(space, EV.STANDUP, ix.target[name])
				t.truthy(w >= 4, `{name}: {w} ticks`)
			end
			-- F and L can be had from either flipper
			t.truthy(ticks(space, EV.STANDUP, ix.target.fuel_f, LEFT) >= 3)
			t.truthy(ticks(space, EV.STANDUP, ix.target.fuel_f, RIGHT) >= 3)
		end
	)

	t.test(
		"SPACE SQUIRREL: a pod is a hole in the orbit lane: a soft ball drops in, a hard one skips over and goes round",
		function()
			local c = space.c
			local pod = space.def.saucers[space.ix.saucer.pod_1]
			local function through(speed: number): (boolean, boolean)
				local s = Physics.new(c, 3)
				local ev: { number } = {}
				-- up the lane, over the middle of the hole
				Physics.addBall(s, pod.x + 0.03, pod.y - 0.3, -0.1 * speed, 0.995 * speed)
				local held, top = false, false
				for _ = 1, 240 * 4 do
					table.clear(ev)
					Physics.step(c, s, false, false, ev)
					for k = 1, #ev, 4 do
						if ev[k] == EV.SAUCER and ev[k + 1] == space.ix.saucer.pod_1 then
							held = true
						elseif ev[k] == EV.ROLLOVER and ev[k + 1] == space.ix.sensor.orbit_top then
							top = true
						end
					end
				end
				return held, top
			end
			local held, top = through(pod.maxSpeed * 0.7)
			t.truthy(held, "a soft ball is swallowed")
			t.falsy(top)
			held, top = through(9)
			t.falsy(held, "a hard one skips over the hole")
			t.truthy(top, "and goes round the top of the orbit")
		end
	)

	t.test("what a rule sheet wants is always something on the table, and something a flipper can make", function()
		for _, id in Tables.IDS do
			local tbl = Tables.need(id)
			local book = Shots.book(tbl)
			local m = Machine.new(tbl, 1, 1)
			local wants = tbl.sheet.wants(m, m.sheets[1])
			t.truthy(#wants >= 3, `{id}: a fresh game wants {#wants} things`)
			local makeable = 0
			for _, kk in wants do
				t.truthy(Shots.name(tbl, kk) ~= "", "a real element")
				local w = Shots.best(book, kk)
				if w and w.ticks >= Bot.MIN_WINDOW then
					makeable += 1
				end
			end
			t.truthy(makeable >= 3, `{id}: {makeable} of them can be made from a cradle`)
			-- and the first thing it wants is makeable: the goal is never out of reach
			local first = Shots.best(book, wants[1])
			t.truthy(first and first.ticks >= 4, `{id}: the first shot wanted has a window`)
		end
	end)

	t.test("what a sheet wants follows the game: lit shots come first", function()
		-- SPICY RODENT wants the wire, until the bite is lit
		local m = Machine.new(spicy, 1, 1)
		local sheet = m.sheets[1]
		local bite = Machine.key(EV.SAUCER, spicy.ix.saucer.bite)
		t.eq(spicy.sheet.wants(m, sheet)[1], Machine.key(EV.RAIL_OUT, spicy.ix.rail.wire))
		sheet.biteLit = 1
		t.eq(spicy.sheet.wants(m, sheet)[1], bite)
		-- SPACE SQUIRREL wants F-U-E-L, then the pods, then a ramp
		local m2 = Machine.new(space, 1, 1)
		local s2 = m2.sheets[1]
		local first = space.sheet.wants(m2, s2)[1]
		t.eq(first // 1000, EV.STANDUP, "a FUEL target first")
		s2.locksLit = 1
		t.eq(space.sheet.wants(m2, s2)[1] // 1000, EV.SAUCER, "the locks are lit: a pod")
		s2.locksLit, s2.locked = 0, 2
		t.eq(space.sheet.wants(m2, s2)[1] // 1000, EV.RAIL_OUT, "both pods full: a ramp")
		-- ACORN ATTACK wants a letter that is still standing
		local m3 = Machine.new(acorn, 1, 1)
		local want = acorn.sheet.wants(m3, m3.sheets[1])[1]
		t.eq(want, Machine.key(EV.DROP, acorn.ix.target.acorn_a))
		m3.phys.drop[acorn.ix.target.acorn_a] = true
		t.eq(acorn.sheet.wants(m3, m3.sheets[1])[1], Machine.key(EV.DROP, acorn.ix.target.acorn_c))
	end)

	t.test(
		"PIN-R6: each table's one clear goal can be reached through the buttons: the WIZARD gets there by timing",
		function()
			local N = GAMES
			-- ACORN ATTACK: an acorn in the hoard (the whole bank down)
			local said = games(acorn, 3)
			t.truthy((said[acorn.SAY.ACORN] or 0) >= N / 2, `an acorn in {said[acorn.SAY.ACORN] or 0} of {N} games`)
			-- SPICY RODENT: up the wire to FERAL in nearly every game, to SUPER in some
			said = games(spicy, 3)
			t.truthy((said[spicy.SAY.WIRE] or 0) >= N - 2, `the wire in {said[spicy.SAY.WIRE] or 0} of {N} games`)
			t.truthy((said[spicy.SAY.FERAL] or 0) >= N * 0.7, `FERAL in {said[spicy.SAY.FERAL] or 0} of {N}`)
			t.truthy((said[spicy.SAY.SUPER] or 0) >= 2, `SUPER in {said[spicy.SAY.SUPER] or 0} of {N}`)
			-- SPACE SQUIRREL: F-U-E-L, two locks, the countdown, LIFTOFF
			said = games(space, 3)
			t.truthy((said[space.SAY.LOCKS_LIT] or 0) >= N / 2, `the locks lit in {said[space.SAY.LOCKS_LIT] or 0}`)
			t.truthy((said[space.SAY.LIFTOFF] or 0) >= N / 2, `multiball in {said[space.SAY.LIFTOFF] or 0} of {N}`)
			t.truthy((said[space.SAY.JACKPOT] or 0) >= 1, "and a jackpot in it")
		end
	)

	t.test("three skill levels: on every table the WIZARD outscores the REGULAR, who outscores the NOVICE", function()
		for _, id in Tables.IDS do
			local tbl = Tables.need(id)
			local mid: { number } = {}
			for level = 1, 3 do
				local _, scores = games(tbl, level)
				mid[level] = scores[(GAMES + 1) // 2]
				t.truthy(scores[1] > 0, `{id} {Bot.NAMES[level]}: every game scores`)
			end
			t.truthy(mid[3] > mid[2] * 1.3, `{id}: WIZARD {mid[3]} against REGULAR {mid[2]}`)
			t.truthy(mid[2] > mid[1], `{id}: REGULAR {mid[2]} against NOVICE {mid[1]}`)
			t.truthy(mid[3] > mid[1] * 2, `{id}: WIZARD {mid[3]} against NOVICE {mid[1]}`)
		end
	end)
end
