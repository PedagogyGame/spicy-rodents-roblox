--!strict
-- Minigames/Pinball/Shots: each table's shot book, and the tables held to it. A shot a rule is built on must
-- be makeable by timing alone, so its window (how many ticks of flip timing in a row reach it, from a cradled
-- ball) is pinned here per table: the main shots at a fair two screen frames or near it, every letter and
-- lock in reach of some flipper. Also here: the rule sheets' "what to shoot for now" (sheet.wants) names real,
-- makeable shots; SPACE SQUIRREL's pods tell a soft shot from a hard one; and the WIZARD computer player,
-- aiming by the book through the buttons alone, reaches each table's goal (PIN-R6 "one clear goal").
local Bot = require("@shared/Minigames/Pinball/Bot")
local HighScores = require("@shared/Minigames/Pinball/HighScores")
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
-- a table's main shot (the one its goal is built on) is wider than a fair shot: buttons are read once a screen
-- frame, four ticks at 60 frames a second, so this is near three frames
local MAIN_TICKS = 11

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
				t.truthy(either(acorn, EV.BUMPER, i) >= 5, `bumper {i} can be shot at`)
			end
			-- the two oak targets are late shots across the table, each a screen frame wide
			t.truthy(ticks(acorn, EV.STANDUP, ix.target.oak_r, LEFT) >= 4, "the right oak from the left flipper")
			t.truthy(ticks(acorn, EV.STANDUP, ix.target.oak_l, RIGHT) >= 4, "the left oak from the right flipper")
		end
	)

	t.test(
		"PIN-R6 SPICY RODENT: the wire is a fair shot from either flipper; the bite and all five letters are in reach",
		function()
			local ix = spicy.ix
			local wireL = ticks(spicy, EV.RAIL_OUT, ix.rail.wire, LEFT)
			local wireR = ticks(spicy, EV.RAIL_OUT, ix.rail.wire, RIGHT)
			-- (the table's main shot: its mouth is flared wide, so the window is near three screen frames at 60 a
			-- second from either flipper; a player's buttons are read once a frame)
			t.truthy(wireR >= MAIN_TICKS, `the wire from the right flipper: {wireR} ticks`)
			t.truthy(wireL >= MAIN_TICKS, `and from the left: {wireL} ticks`)
			t.truthy(wireR <= 16 and wireL <= 16, "but it still takes timing: the fast table")
			t.truthy(ticks(spicy, EV.SAUCER, ix.saucer.bite, LEFT) >= 4, "the bite is the left flipper's shot")
			t.truthy(ticks(spicy, EV.SAUCER, ix.saucer.bite, RIGHT) >= 3, "and can be had from the right")
			-- the flipper's own side: S the earliest, softest backhand, P a little later, and later still the
			-- channel up to the nest (the widest shot on the table)
			t.truthy(ticks(spicy, EV.STANDUP, ix.target.spicy_s, LEFT) >= 4, "S by the softest backhand")
			t.truthy(ticks(spicy, EV.STANDUP, ix.target.spicy_p, LEFT) >= Shots.FAIR_TICKS, "P by the backhand")
			t.truthy(ticks(spicy, EV.STANDUP, ix.target.spicy_y, RIGHT) >= 4)
			t.truthy(ticks(spicy, EV.STANDUP, ix.target.spicy_c, RIGHT) >= Shots.FAIR_TICKS)
			local nest = 0
			for i = 1, 3 do
				nest = math.max(nest, ticks(spicy, EV.BUMPER, i, LEFT))
			end
			t.truthy(nest >= 10, `the nest is the left flipper's hard backhand: {nest} ticks`)
			for _, name in { "spicy_s", "spicy_p", "spicy_i", "spicy_c", "spicy_y" } do
				local w = either(spicy, EV.STANDUP, ix.target[name])
				t.truthy(w >= 3, `{name}: {w} ticks`)
			end
		end
	)

	t.test(
		"PIN-P5 SPICY RODENT: the skill shot is the soft plunge; a hard one comes round the arch and down into the nest",
		function()
			local ix = spicy.ix
			local out: { number } = {}
			-- nobody at the flippers: what one ball does after a pull of this share
			local function plunge(pull: number): (boolean, number, number, number)
				local m = Machine.new(spicy, 11, 1)
				for _ = 1, math.floor(pull * spicy.def.plunger.pullTicks + 0.5) do
					Machine.step(spicy, m, Machine.BTN.PLUNGE, out)
				end
				table.clear(out)
				local hot, pops, nest, before = false, 0, 0, 0
				for _ = 1, 240 * 8 do
					Machine.step(spicy, m, 0, out)
					for i = 1, #out, 3 do
						if out[i] == Machine.CUE.SAY and out[i + 1] == spicy.SAY.HOT_SHOT then
							hot = true
							before = pops
						elseif out[i] == Machine.CUE.BUMPER then
							pops += 1
							if out[i + 1] == ix.bumper.bumper_1 or out[i + 1] == ix.bumper.bumper_3 then
								nest += 1
							end
						end
					end
					table.clear(out)
				end
				return hot, pops, nest, before
			end
			for _, pull in { 0.1, 0.15, 0.2 } do
				local hot, _, _, before = plunge(pull)
				t.truthy(hot, `a pull of {pull}: the ball dribbles down the hot lane`)
				t.eq(before, 0, `a pull of {pull}: and meets no bumper on the way there`)
			end
			-- from half a pull up the ball goes round the arch, and the guide on the left rail turns it into the
			-- nest: a hard plunge is no skill shot (it used to bounce back round the arch into the hot lane)
			local all, fed = 0, 0
			for _, pull in { 0.5, 0.6, 0.7, 0.8, 0.9, 1 } do
				local hot, pops, nest = plunge(pull)
				t.falsy(hot, `a pull of {pull} is no skill shot`)
				t.truthy(nest >= 1, `a pull of {pull}: into the nest ({nest} pops there)`)
				all += pops
				if pops >= 3 then
					fed += 1
				end
			end
			t.truthy(fed >= 4, `{fed} of 6 hard plunges are batted about (three pops or more)`)
			t.truthy(all >= 24, `{all} pops from six hard plunges`)
		end
	)

	t.test(
		"PIN-R6 SPACE SQUIRREL: both ramps from both flippers; the pod, the orbit and a FUEL target by the backhand",
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
			-- The flipper's own side is three true backhands, told apart by timing alone: the earliest and
			-- softest is the pod, a little later and harder the orbit, the latest and hardest the FUEL target
			-- at the corner of the ramp. Each is wider than a fair shot, and they come in that order.
			local book = Shots.book(space)
			for flipper = LEFT, RIGHT do
				local pod = if flipper == LEFT then ix.saucer.pod_1 else ix.saucer.pod_2
				local fuel = if flipper == LEFT then ix.target.fuel_u else ix.target.fuel_e
				local wPod = Shots.best(book, Machine.key(EV.SAUCER, pod), flipper)
				local wOrbit = Shots.best(book, Machine.key(EV.ROLLOVER, ix.sensor.orbit_top), flipper)
				local wFuel = Shots.best(book, Machine.key(EV.STANDUP, fuel), flipper)
				assert(
					wPod and wOrbit and wFuel,
					`flipper {flipper}: the pod, the orbit and the FUEL target are in its book`
				)
				t.truthy(wPod.ticks >= Shots.FAIR_TICKS, `the pod from flipper {flipper}: {wPod.ticks} ticks`)
				t.truthy(wOrbit.ticks >= 10, `the orbit from flipper {flipper}: {wOrbit.ticks} ticks`)
				t.truthy(wFuel.ticks >= Shots.FAIR_TICKS, `its FUEL target from flipper {flipper}: {wFuel.ticks} ticks`)
				t.truthy(wPod.to < wOrbit.from and wOrbit.to < wFuel.from, "soft, harder, hardest: in that order")
				t.truthy(wPod.speed < wOrbit.speed and wOrbit.speed < wFuel.speed)
				for _, w in { wPod, wOrbit, wFuel } do
					t.truthy(w.angle < -10, `a backhand: {w.angle} degrees, up the flipper's own side`)
				end
			end
			for _, name in { "fuel_f", "fuel_u", "fuel_e", "fuel_l" } do
				local w = either(space, EV.STANDUP, ix.target[name])
				t.truthy(w >= 4, `{name}: {w} ticks`)
			end
			-- F and L can be had from either flipper
			t.truthy(ticks(space, EV.STANDUP, ix.target.fuel_f, LEFT) >= 3)
			t.truthy(ticks(space, EV.STANDUP, ix.target.fuel_f, RIGHT) >= 3)
		end
	)

	t.test("PIN-R6 SPACE SQUIRREL flows: an orbit made comes down the far rail and into the far inlane", function()
		-- from the shot book: every backhand that goes round the top of the orbit ends in the inlane on the
		-- other side (never on the slingshot, never down the outlane)
		local ix = space.ix
		local book = Shots.book(space)
		local top = Machine.key(EV.ROLLOVER, ix.sensor.orbit_top)
		for flipper = LEFT, RIGHT do
			local far = Machine.key(EV.ROLLOVER, if flipper == LEFT then ix.sensor.inlane_r else ix.sensor.inlane_l)
			local out = Machine.key(EV.ROLLOVER, if flipper == LEFT then ix.sensor.outlane_r else ix.sensor.outlane_l)
			local made, fed, lost = 0, 0, 0
			for _, tr in book.trials[flipper] do
				if tr.angle < 0 and table.find(tr.keys, top) then
					made += 1
					if table.find(tr.keys, far) then
						fed += 1
					elseif table.find(tr.keys, out) then
						lost += 1
					end
				end
			end
			t.truthy(made >= 10, `flipper {flipper}: {made} flip timings make the orbit`)
			-- (the rest are the slowest ones round, which rattle at the shooter lane's gate and are not down
			-- again before the trial ends)
			t.truthy(fed >= made * 0.7, `flipper {flipper}: {fed} of {made} orbits feed the far inlane`)
			t.eq(lost, 0, `flipper {flipper}: no orbit made is lost down the outlane`)
		end
		-- and a ball that comes down a rail by itself, at any speed, is turned into the inlane by the ball guide
		local c = space.c
		local ev: { number } = {}
		local into, tried = 0, 0
		for _, x in { 0.066, 0.1, 0.14 } do
			for _, speed in { 0.5, 2, 4, 6, 8, 10, 12 } do
				local s = Physics.new(c, 1)
				Physics.addBall(s, x, 3.3, 0, -speed)
				tried += 1
				local first = 0
				for _ = 1, 240 * 6 do
					table.clear(ev)
					Physics.step(c, s, false, false, ev)
					for k = 1, #ev, 4 do
						if first == 0 and ev[k] == EV.ROLLOVER then
							local name = space.def.sensors[ev[k + 1]].id
							if name == "inlane_l" or name == "outlane_l" then
								first = if name == "inlane_l" then 1 else 2
							end
						elseif first == 0 and ev[k] == EV.SLING then
							first = 3
						end
					end
					if first ~= 0 or s.balls[1].mode ~= Physics.FREE then
						break
					end
				end
				if first == 1 then
					into += 1
				end
			end
		end
		t.truthy(into >= tried - 2, `{into} of {tried} balls down the left rail roll into the left inlane`)
	end)

	t.test(
		"SPACE SQUIRREL: a pod is a scoop in the orbit lane: a soft ball drops in, a hard one skips over and goes round",
		function()
			local c = space.c
			local pod = space.def.saucers[space.ix.saucer.pod_1]
			local function through(speed: number, down: boolean?): (boolean, boolean)
				local s = Physics.new(c, 3)
				local ev: { number } = {}
				if down then
					-- down the lane from above, over the hood
					Physics.addBall(s, pod.x + 0.02, pod.y + 0.3, 0, -speed)
				else
					-- up the lane, over the middle of the hole
					Physics.addBall(s, pod.x + 0.03, pod.y - 0.3, -0.1 * speed, 0.995 * speed)
				end
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
			held, top = through(pod.maxSpeed + 3)
			t.falsy(held, "a hard one skips over the hole")
			t.truthy(top, "and goes round the top of the orbit")
			-- a ball coming down the lane out of the orbit rides over the hood, however slowly: the orbit's
			-- return is never swallowed
			for _, speed in { 1, 4, pod.maxSpeed * 0.9 } do
				held = through(speed, true)
				t.falsy(held, `coming down at {speed}: over the hood`)
			end
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
			-- the machine's own board of best scores is set by these: a first game is near its foot, a very good
			-- one is on it above the foot, and the top is still there to play for
			local board = HighScores.new(id)
			local foot, top = board.entries[HighScores.SIZE].score, board.entries[1].score
			t.truthy(mid[1] > foot * 0.4 and mid[1] < foot * 2.5, `{id}: NOVICE {mid[1]} against the foot {foot}`)
			local place = HighScores.place(board, mid[3])
			t.truthy(place and place <= 4, `{id}: the WIZARD's middling game {mid[3]} takes place {place}`)
			t.truthy(top > mid[3], `{id}: the top of the board {top} is above the WIZARD's middling game`)
		end
	end)
end
