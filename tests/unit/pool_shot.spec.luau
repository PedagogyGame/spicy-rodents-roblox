--!strict
-- Minigames/Pool/Shot: one whole shot as a script (checklist C1, C10, C11, C12; POOL-R4 pots in drop order;
-- POOL-S4 the sound cue points): the script plays back exactly what the model did, at any frame rate; it says
-- what the rules need; it is plain numbers a client can be sent; a long slow shot is never refused.
local Cloth = require("@shared/Minigames/Pool/Cloth")
local Cue = require("@shared/Minigames/Pool/Cue")
local Physics = require("@shared/Minigames/Pool/Physics")
local Shot = require("@shared/Minigames/Pool/Shot")
local Tables = require("@shared/Minigames/Pool/Tables")

return function(t)
	local pool = Tables.eightBall()
	local bumper = Tables.bumper()
	local R = Tables.BALL_R

	local function roll(id: number, vx: number, vz: number): Shot.Strike
		return { id = id, vx = vx, vz = vz, qx = vx, qz = vz, s = 0 }
	end

	t.test("C1 the script plays back what the model did: every ball, every instant of a break", function()
		for _, seed in { 2, 9 } do
			local spots = Tables.rack(seed)
			local st = Cue.strike(0, 0, 1, 0.2, 0.3, seed)
			local s = Shot.run(pool, spots, { st })
			local w = Physics.world(pool, spots)
			Physics.strike(w, st.id, st.vx, st.vz, st.qx, st.qz, st.s)
			local moving = true
			local worst, pushed = 0, 0
			local checked = 0
			while moving do
				moving = Physics.step(w)
				if w.steps % 7 == 0 then
					for i, b in w.balls do
						local x, z, y, mode = Shot.pose(s, i, w.t)
						if b.mode == Cloth.DOWN then
							t.eq(mode, Cloth.DOWN, "a potted ball is down in the script too")
						else
							local off = math.max(math.abs(x - b.x), math.abs(z - b.z), math.abs(y - b.y))
							if w.late[i] then
								-- it is being pushed along by a ball leaning on it: its key points come every
								-- KEY_QUIET, and between them it is out by a hair
								pushed = math.max(pushed, off)
							else
								worst = math.max(worst, off)
							end
							checked += 1
						end
					end
				end
			end
			t.truthy(checked > 1000)
			t.truthy(worst < 1e-6, `seed {seed}: playback strays {worst} studs from the model`)
			t.truthy(pushed < 2e-4, `seed {seed}: a pushed ball strays {pushed} studs`)
		end
	end)

	t.test("C10 playback at any frame rate ends on the rest positions; nothing is drawn off its table", function()
		local s = Shot.run(pool, Tables.rack(4), { Cue.strike(0, 0, 1, 0, 0.3, 4) })
		local rest: { [number]: Tables.Spot } = {}
		for _, r in Shot.rest(s) do
			rest[r.id] = r
		end
		for i, id in s.ids do
			local x, z, y, mode, vx, vz = Shot.pose(s, i, s.tEnd)
			local r = rest[id]
			if r then
				t.near(x, r.x, 1e-6)
				t.near(z, r.z, 1e-6)
				t.eq(y, 0)
				t.eq(mode, Cloth.REST)
				t.eq(vx, 0)
				t.eq(vz, 0)
			else
				t.eq(mode, Cloth.DOWN, `ball {id} is either at rest or potted`)
				t.near(y, -Shot.SINK, 1e-9, "sunk out of sight, no further")
			end
			-- before the strike it is where it was racked
			local x0, z0 = Shot.pose(s, i, -1)
			t.eq(x0, s.start[i * 2 - 1])
			t.eq(z0, s.start[i * 2])
		end
		-- at 24, 60 and 144 frames a second every ball stays over the table's own footprint
		for _, fps in { 24, 60, 144 } do
			local time = 0
			while time < s.tEnd + 1 do
				for i = 1, #s.ids do
					local x, z, y = Shot.pose(s, i, time)
					t.truthy(math.abs(x) < pool.halfW + 0.75 and math.abs(z) < pool.halfL + 0.75, "inside the table")
					t.truthy(y <= 0 and y >= -Shot.SINK)
				end
				time += 1 / fps
			end
		end
		t.near(s.tEnd, s.steps * Physics.DT + Shot.REST_PAD, 1e-9, "the shot lasts until the last ball has stopped")
	end)

	t.test(
		"POOL-R4 what the rules need: first ball hit, pots in the order they dropped, a cushion after contact",
		function()
			-- the cue ball pots the 3 in the foot right corner; the 11, further off, is potted by nothing
			local hole = pool.holes[6]
			local ox, oz = hole.x + hole.mx * 1.2, hole.z + hole.mz * 1.2
			local spots = {
				{ id = 0, x = ox + hole.mx * 1.5, z = oz + hole.mz * 1.5 },
				{ id = 3, x = ox, z = oz },
				{ id = 11, x = -2, z = -3 },
			}
			local s = Shot.run(pool, spots, { roll(0, -hole.mx * 6, -hole.mz * 6) })
			t.eq(Shot.firstHit(s, 0), 3)
			t.eq(s.first[1], 3)
			t.truthy(s.firstT > 0)
			local pots = Shot.pots(s)
			t.eq(pots[1].ball, 3)
			t.eq(pots[1].hole, 6)
			t.eq(pots[1].cushions, 0)
			-- a rolling cue ball follows a straight pot in: the scratch comes second, in drop order
			t.eq(#pots, 2)
			t.eq(pots[2].ball, 0)
			t.truthy(pots[2].t > pots[1].t)
			t.eq(#Shot.rest(s), 1, "only the 11 is left")
			t.eq(Shot.rest(s)[1].id, 11)
			t.eq(Shot.firstHit(s, 11), 0, "a ball that was not struck has no first hit")
			-- a miss: no ball touched
			local miss = Shot.run(pool, { { id = 0, x = 0, z = 0 }, { id = 5, x = 2, z = 4 } }, { roll(0, 0, -3) })
			t.eq(miss.first[1], 0)
			t.eq(miss.firstT, -1)
			t.falsy(miss.railAfter, "a cushion without a ball first does not count")
			-- a soft touch that reaches no cushion
			local soft = Shot.run(pool, { { id = 0, x = 0, z = 0 }, { id = 5, x = 0, z = 1 } }, { roll(0, 0, 1.6) })
			t.eq(soft.first[1], 5)
			t.falsy(soft.railAfter)
			-- the same, firmer: the object ball reaches the foot cushion
			local firm = Shot.run(pool, { { id = 0, x = 0, z = 0 }, { id = 5, x = 0, z = 1 } }, { roll(0, 0, 6) })
			t.truthy(firm.railAfter)
			local i5 = Shot.indexOf(firm, 5) :: number
			t.truthy(firm.rails[i5] >= 1)
		end
	)

	t.test("POOL-S4 sound cue points: the tip, the crack of the break, cushions, the drop; clicks merged", function()
		local s = Shot.run(pool, Tables.rack(5), { Cue.strike(0, 0, 1, 0, 0.3, 5) })
		local cues = Shot.cues(s)
		t.eq(cues[1].name, "strike")
		t.eq(cues[1].t, 0)
		t.eq(cues[1].volume, 1, "full power is the loudest strike")
		local names: { [string]: number } = {}
		local last = 0
		for _, c in cues do
			names[c.name] = (names[c.name] or 0) + 1
			t.truthy(c.t >= last, "in time order")
			last = c.t
			t.truthy(c.volume >= 0.05 and c.volume <= 1, "volume from the speed of the hit")
		end
		t.truthy((names.crack or 0) >= 1, "the rack opening is one crack")
		t.truthy((names.cushion or 0) >= 5)
		local ballEvents = 0
		for e = 1, #s.events, Physics.EVENT_STRIDE do
			if s.events[e + 1] == Physics.EV.ball then
				ballEvents += 1
			end
		end
		t.truthy((names.click or 0) + (names.crack or 0) < ballEvents, "clustered clicks are merged")
		-- a soft strike is quiet, and a pot has its drop
		local hole = pool.holes[4]
		local pot = Shot.run(pool, { { id = 1, x = 1, z = 0 } }, { roll(1, 2.5, 0) })
		local potCues = Shot.cues(pot)
		t.truthy(potCues[1].volume < 0.2)
		t.eq(potCues[#potCues].name, "drop")
		t.eq(hole.mz, 0)
		-- bumper pool: the rubber thock and the cup
		local b = Shot.run(bumper, { { id = 1, x = 0, z = -1.5 } }, { roll(1, 0, 5) })
		local post = false
		for _, c in Shot.cues(b) do
			post = post or c.name == "post"
		end
		t.truthy(post)
	end)

	t.test(
		"C12 the animal rule: the script says when a moving ball first reaches a point; the model never knows",
		function()
			local spots = { { id = 0, x = 0, z = -4 }, { id = 7, x = 1.5, z = 3 } }
			local s = Shot.run(pool, spots, { roll(0, 0, 5) })
			local when, ball = Shot.firstNear(s, 0, 0, 0.3)
			t.eq(ball, 0)
			t.truthy(when ~= nil and when > 0.6 and when < 1.1, `{when}`)
			-- a ball at rest never knocks anything off (an animal may not be blamed on a still ball)
			t.eq((Shot.firstNear(s, 1.5, 3, 0.2)), nil)
			-- nowhere near any ball's path
			t.eq((Shot.firstNear(s, -2.3, -5, 0.2)), nil)
		end
	)

	t.test(
		"C1 a script is plain data for the wire, and a script off the wire is checked before it is played",
		function()
			local s = Shot.run(pool, Tables.rack(6), { Cue.strike(0, 0, 0.7, 0, 0, 6) })
			local function plain(v: any, depth: number)
				assert(depth < 4, "too deep")
				local kind = type(v)
				if kind == "table" then
					local n = #v
					local count = 0
					for k, x in v do
						count += 1
						plain(x, depth + 1)
						t.truthy(type(k) == "string" or type(k) == "number")
					end
					t.truthy(n == 0 or count == n, "an array is only an array")
				elseif kind == "number" then
					t.truthy(v == v and math.abs(v) < 1e9, "no NaN, nothing infinite")
				else
					t.truthy(kind == "string" or kind == "boolean")
				end
			end
			plain(s, 0)
			local ok, why = Shot.check(s)
			t.truthy(ok ~= nil, why)
			t.eq((Shot.check(nil)), nil)
			t.eq((Shot.check({ v = 99 })), nil)
			local function broken(change: (any) -> ()): boolean
				local copy = table.clone(s) :: any
				copy.tracks = table.clone(s.tracks)
				change(copy)
				return Shot.check(copy) == nil
			end
			t.truthy(broken(function(c)
				c.table = "snooker"
			end))
			t.truthy(broken(function(c)
				c.ids = {}
			end))
			t.truthy(broken(function(c)
				c.tracks[1] = { 1, 2, 3 }
			end))
			t.truthy(broken(function(c)
				c.tracks[1] = { 0 / 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }
			end))
			t.truthy(broken(function(c)
				c.tracks[1] = { 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0 }
			end))
			t.truthy(broken(function(c)
				c.tEnd = "soon"
			end))
			t.truthy(broken(function(c)
				c.events = { 1, 2, 3 }
			end))
			t.truthy(broken(function(c)
				c.firstAll = nil
			end))
			t.truthy(broken(function(c)
				c.firstAll = { { "nine" } }
			end))
			t.truthy(broken(function(c)
				c.touch = { 1 }
			end))
			t.truthy(broken(function(c)
				c.pots = { 1, 2, 3, 4 }
			end))
		end
	)

	t.test("C10 a slow shot is never refused for being long, and a script stays small", function()
		-- the softest roll the length of the table: seconds long, a handful of numbers
		local slow = Shot.run(pool, { { id = 0, x = 0, z = -5.2 } }, { roll(0, 0, 4.3) })
		t.truthy(slow.tEnd > 4.5)
		t.falsy(slow.capped)
		t.truthy(Shot.check(slow) ~= nil)
		t.truthy(Shot.size(slow) < 60, `{Shot.size(slow)} numbers`)
		local hole = pool.holes[6]
		local pot = Shot.run(
			pool,
			{ { id = 0, x = 0, z = 0 }, { id = 3, x = hole.x + hole.mx * 1.2, z = hole.z + hole.mz * 1.2 } },
			{ Cue.strike(0, Cue.angleOf(hole.x + hole.mx * 1.2, hole.z + hole.mz * 1.2), 0.3, 0, -0.3, nil) }
		)
		t.truthy(Shot.size(pot) < 400, `an ordinary shot is {Shot.size(pot)} numbers`)
		local worst = 0
		for seed = 1, 20 do
			worst = math.max(worst, Shot.size(Shot.run(pool, Tables.rack(seed), { Cue.strike(0, 0, 1, 0, 0.3, seed) })))
		end
		-- (one break in a hundred used to be 4,000 to 9,000: a ball leaning on another wrote two key points a step)
		t.truthy(worst < 2600, `the biggest break is {worst} numbers`)
	end)

	t.test("the first hit: two balls lying together are met as one, whichever the table lists first", function()
		-- the cue ball is sent at the 9 with the 1 lying 0.003 studs short of touching it as it arrives: one
		-- instant, two balls. Which comes "first" used to be the order of the table's list: a legal hit or a
		-- wrong-ball foul by the luck of it. The script now names both
		local a = math.rad(60)
		local gz = 1 - 2 * R
		local place = {
			[9] = { x = 0, z = 1 },
			[1] = { x = (2 * R + 0.003) * math.sin(a), z = gz + (2 * R + 0.003) * math.cos(a) },
		}
		local firsts: { number } = {}
		for _, order in { { 9, 1 }, { 1, 9 } } do
			local spots: { Tables.Spot } = { { id = 0, x = 0, z = gz - 1 } }
			for _, id in order do
				table.insert(spots, { id = id, x = place[id].x, z = place[id].z })
			end
			local s = Shot.run(pool, spots, { roll(0, 0, 4) })
			local all = Shot.firstHits(s, 0)
			table.sort(all)
			t.deepEq(all, { 1, 9 }, "both, in either order of the list")
			t.truthy(table.find(all, Shot.firstHit(s, 0)) ~= nil)
			table.insert(firsts, Shot.firstHit(s, 0))
			t.truthy(Shot.check(s) ~= nil)
		end
		t.truthy(firsts[1] ~= firsts[2], "the single first hit does follow the list, which is why it is not the rule")
		-- a clear gap between them is two hits: only the first counts
		local apart = Shot.run(
			pool,
			{ { id = 0, x = 0, z = gz - 1 }, { id = 9, x = 0, z = 1 }, { id = 1, x = 0.3, z = 1.2 } },
			{ roll(0, 0, 4) }
		)
		t.deepEq(Shot.firstHits(apart, 0), { 9 })
		t.deepEq(Shot.firstHits(apart, 9), {}, "a ball that was not struck has none")
		-- a miss has none
		local miss = Shot.run(pool, { { id = 0, x = 0, z = 0 }, { id = 5, x = 2, z = 4 } }, { roll(0, 0, -3) })
		t.deepEq(Shot.firstHits(miss, 0), {})
	end)

	t.test("the first touch of a struck ball: a ball, a cushion, a post, or nothing", function()
		local EV = Physics.EV
		local ball = Shot.run(pool, { { id = 0, x = 0, z = 0 }, { id = 5, x = 0, z = 1 } }, { roll(0, 0, 3) })
		local k1, w1 = Shot.firstTouch(ball, 0)
		t.eq(k1, EV.ball)
		t.eq(w1, 5)
		-- into the right-hand long cushion of the bumper table (its segment 2), then on to other things
		local side = Shot.run(bumper, { { id = 1, x = 1, z = -1.5 } }, { roll(1, 4, 2) })
		local k2, w2 = Shot.firstTouch(side, 1)
		t.eq(k2, EV.cushion)
		t.eq(w2, 2)
		t.truthy(bumper.segs[2].x1 > 0 and bumper.segs[2].x2 > 0, "segment 2 is the +x cushion")
		t.truthy(bumper.segs[1].x1 < 0, "and segment 1 the -x cushion")
		local post = Shot.run(bumper, { { id = 1, x = 0, z = -1.5 } }, { roll(1, 0, 5) })
		t.eq((Shot.firstTouch(post, 1)), EV.post)
		local none = Shot.run(pool, { { id = 0, x = 0, z = 0 } }, { roll(0, 0, 1) })
		local k4, w4 = Shot.firstTouch(none, 0)
		t.eq(k4, 0)
		t.eq(w4, 0)
		t.eq((Shot.firstTouch(ball, 5)), 0, "a ball that was not struck has none")
	end)

	t.test("a pot knows what led to it: the cushions before the rim, and whose strike reached the ball", function()
		-- BANKS. Straight at the cup from the front at 31 speeds: every one drops, most of them touch the end
		-- cushion behind the cup while already over it, and none of them is a bank (24 of them used to be)
		local sank, touched = 0, 0
		for i = 0, 30 do
			local s = Shot.run(bumper, { { id = 1, x = 0, z = Tables.CUP_Z - 1.26 } }, { roll(1, 0, 3 + i * 0.2) })
			local pots = Shot.pots(s)
			if #pots == 1 then
				sank += 1
				t.eq(pots[1].cushions, 0, `straight in at {3 + i * 0.2} studs/s is not a bank`)
				if s.rails[1] > 0 then
					touched += 1
				end
			end
		end
		t.truthy(sank >= 25, `{sank} of 31 dropped`)
		t.truthy(touched >= 10, `{touched} touched the cushion behind the cup on the way down`)
		-- a true bank: the marked ball off the side cushion and into the far cup
		local bank: Shot.Script? = nil
		for i = 0, 160 do
			local s = Shot.run(
				bumper,
				Tables.bumperStart({ true, false }),
				{ Cue.strike(1, math.rad(30 + i * 0.125), 0.2, 0, 0.8, nil) }
			)
			if #s.pots > 0 and s.first[1] == 0 then
				bank = s
				break
			end
		end
		assert(bank, "no opening bank sinks the marked ball")
		local pot = Shot.pots(bank)[1]
		t.eq(pot.ball, 1)
		t.eq(pot.hole, 2)
		t.truthy(pot.cushions >= 1, "off the side cushion: a bank")
		local before = 0
		for e = 1, #bank.events, Physics.EVENT_STRIDE do
			if bank.events[e + 1] == Physics.EV.enter then
				break
			elseif bank.events[e + 1] == Physics.EV.cushion then
				before += 1
			end
		end
		t.eq(pot.cushions, before, "the cushions it touched before it crossed the rim")
		t.eq(pot.by, 1, "sent by the one strike")
		-- WHOSE STRIKE. Two strikes in one run (bumper pool's opening): ball 1 is rolled into ball 9, which
		-- drops in the cup behind it; ball 6, struck at the other end, touches nothing
		local spots = {
			{ id = 1, x = 0, z = 1.2 },
			{ id = 9, x = 0, z = 1.9 },
			{ id = 6, x = 1.2, z = -1.5 },
			{ id = 3, x = -1.2, z = -1.5 },
		}
		local two = Shot.run(bumper, spots, { roll(1, 0, 3.4), roll(6, 0.5, 0) })
		local pots = Shot.pots(two)
		t.truthy(#pots >= 1)
		t.eq(pots[1].ball, 9)
		t.eq(pots[1].by, 1, "only the first strike's chain reached it")
		-- the same with the strikes the other way round: it is the second strike's now
		local swapped = Shot.run(bumper, spots, { roll(6, 0.5, 0), roll(1, 0, 3.4) })
		t.eq(Shot.pots(swapped)[1].ball, 9)
		t.eq(Shot.pots(swapped)[1].by, 2)
		-- a chain: 6 into 1 into 9. Both strikes have a hand in it
		local chain = Shot.run(bumper, {
			{ id = 6, x = 0, z = 0.9 },
			{ id = 1, x = 0, z = 1.4 },
			{ id = 9, x = 0, z = 1.9 },
			{ id = 2, x = -1.2, z = -1.5 },
		}, { roll(6, 0, 4.2), roll(2, 0.3, 0) })
		local cp = Shot.pots(chain)
		t.truthy(#cp >= 1)
		t.eq(cp[1].ball, 9)
		t.eq(cp[1].by, 1, "through ball 1, which nobody struck, back to the strike that started it")
	end)

	t.test("C12 the animal rule at full power: the pass that made it, to a thousandth of a second", function()
		-- a full-power cue ball covers a stud between two looks at 60 a second: 7 of these 41 places on its
		-- line were reported late (on a later pass) or never
		local s = Shot.run(pool, { { id = 0, x = 0, z = -5 } }, { Cue.strike(0, 0, 1, 0, 0, nil) })
		local r = 0.25
		for k = 0, 40 do
			local z = -4 + k * 0.2
			local when, ball = Shot.firstNear(s, 0, z, r)
			-- the true moment, by looking every 20 millionths of a second
			local truth: number? = nil
			local time = 0
			while time < 1 do
				local x, zz = Shot.pose(s, 1, time)
				if x * x + (zz - z) * (zz - z) <= (r + R) * (r + R) then
					truth = time
					break
				end
				time += 2e-5
			end
			assert(truth, "the ball does pass over it")
			t.eq(ball, 0)
			t.truthy(when ~= nil and math.abs(when - truth) < 1e-3, `at z = {z}: {when} against {truth}`)
		end
		-- a graze counts and a near miss does not: a place just inside and just outside its reach, off the line
		t.truthy((Shot.firstNear(s, r + R - 0.01, 2, r)) ~= nil)
		local missT = Shot.firstNear(s, 1.2, 2, r)
		local hitT = Shot.firstNear(s, r + R - 0.01, 2, r) :: number
		t.truthy(missT == nil or missT > hitT + 0.05, "a place well off the line is not reached on that pass")
		-- the first ball there is the one named, when two are moving
		local both = Shot.run(
			pool,
			{ { id = 0, x = 0, z = -4 }, { id = 7, x = 0, z = -2 } },
			{ Cue.strike(0, 0, 0.8, 0, 0, nil) }
		)
		local _, who = Shot.firstNear(both, 0, 2, r)
		t.eq(who, 7, "the object ball gets there first")
	end)

	t.test("C1 the wire: a script packs to a buffer under half the size and unpacks to the same shot", function()
		local worst, worstSeed, sum = 0, 0, 0
		local N = 60
		for seed = 1, N do
			local s = Shot.run(pool, Tables.rack(seed), { Cue.strike(0, 0, 1, 0, 0.3, seed) })
			local n = buffer.len(Shot.pack(s))
			sum += n
			if n > worst then
				worst, worstSeed = n, seed
			end
			-- as plain numbers a remote would carry 9 bytes for each
			t.truthy(n < Shot.size(s) * 9 * 0.45, `seed {seed}: {n} bytes for {Shot.size(s)} numbers`)
		end
		t.truthy(worst < 9000, `the biggest of {N} breaks is {worst} bytes (seed {worstSeed})`)
		t.truthy(sum / N < 7000, `a break is {sum / N} bytes on average`)
		local s = Shot.run(pool, Tables.rack(worstSeed), { Cue.strike(0, 0, 1, 0, 0.3, worstSeed) })
		local packed = Shot.pack(s)
		local u, why = Shot.unpack(packed)
		assert(u, why)
		-- everything the rules and the sounds read is the same
		t.eq(u.v, s.v)
		t.eq(u.table, s.table)
		t.deepEq(u.ids, s.ids)
		t.deepEq(u.first, s.first)
		t.deepEq(u.firstAll, s.firstAll)
		t.deepEq(u.touch, s.touch)
		t.deepEq(u.rails, s.rails)
		t.deepEq(u.pots, s.pots)
		t.deepEq(u.rest, s.rest, "the rest places are exact")
		t.eq(u.tEnd, s.tEnd)
		t.eq(u.firstT, s.firstT)
		t.eq(u.railAfter, s.railAfter)
		t.eq(u.capped, s.capped)
		t.eq(u.steps, s.steps)
		t.eq(u.contacts, s.contacts)
		t.eq(#u.events, #s.events)
		for e = 1, #s.events, Physics.EVENT_STRIDE do
			t.eq(u.events[e], s.events[e], "event times are exact")
			t.eq(u.events[e + 1], s.events[e + 1])
			t.eq(u.events[e + 2], s.events[e + 2])
			t.eq(u.events[e + 3], s.events[e + 3])
			t.near(u.events[e + 4], s.events[e + 4], 1e-4)
		end
		t.eq(#Shot.cues(u), #Shot.cues(s))
		-- and it plays back the same: every ball, 60 times a second, within a hair
		local off = 0
		local time = 0
		while time <= s.tEnd do
			for i = 1, #s.ids do
				local x, z, y, mode = Shot.pose(s, i, time)
				local ux, uz, uy, umode = Shot.pose(u, i, time)
				t.eq(umode, mode)
				off = math.max(off, math.abs(ux - x), math.abs(uz - z), math.abs(uy - y))
			end
			time += 1 / 60
		end
		t.truthy(off < 1e-4, `playback of the unpacked script is out by {off} studs at most`)
		for i = 1, #s.ids do
			t.eq(#u.tracks[i], #s.tracks[i])
			for o = 1, #s.tracks[i], Physics.KEY_STRIDE do
				t.eq(u.tracks[i][o], s.tracks[i][o], "key point times are exact")
				t.eq(u.tracks[i][o + 9], s.tracks[i][o + 9], "and modes")
			end
		end
		-- packing what was unpacked gives the same bytes
		t.eq(buffer.tostring(Shot.pack(u)), buffer.tostring(packed))
		-- bumper pool's opening (two strikes) goes the same way
		local two = Shot.run(
			bumper,
			Tables.bumperStart(),
			{ Cue.strike(1, math.rad(38), 0.2, 0, 0.8, nil), Cue.strike(6, math.rad(218), 0.2, 0, 0.8, nil) }
		)
		local u2 = Shot.unpack(Shot.pack(two))
		assert(u2, "the opening unpacks")
		t.eq(u2.table, "bumper")
		t.eq(#u2.strikes, 12)
		t.deepEq(u2.rest, two.rest)
		t.truthy(buffer.len(Shot.pack(two)) < 1500, `an opening is {buffer.len(Shot.pack(two))} bytes`)
		-- what is not a whole script is refused, not played
		t.eq((Shot.unpack(nil)), nil)
		t.eq((Shot.unpack("a string")), nil)
		t.eq((Shot.unpack(buffer.create(0))), nil)
		t.eq((Shot.unpack(buffer.create(3))), nil)
		local n = buffer.len(packed)
		local short = buffer.create(n - 7)
		buffer.copy(short, 0, packed, 0, n - 7)
		t.eq((Shot.unpack(short)), nil, "cut short")
		local long = buffer.create(n + 4)
		buffer.copy(long, 0, packed, 0, n)
		t.eq((Shot.unpack(long)), nil, "padded")
		local wrong = buffer.create(n)
		buffer.copy(wrong, 0, packed, 0, n)
		buffer.writeu8(wrong, 0, 99)
		t.eq((Shot.unpack(wrong)), nil, "another version")
		local nan = buffer.create(n)
		buffer.copy(nan, 0, packed, 0, n)
		buffer.writef64(nan, 5, 0 / 0)
		t.eq((Shot.unpack(nan)), nil, "a time that is not a number")
	end)

	t.test("a shot cut short by its cap still ends with every ball at rest where the script says", function()
		local s = Shot.run(pool, Tables.rack(1), { Cue.strike(0, 0, 1, 0, 0.3, 1) }, 0.5)
		t.truthy(s.capped)
		t.near(s.tEnd, 0.5 + Shot.REST_PAD, Physics.DT + 1e-9)
		local rest = Shot.rest(s)
		t.truthy(#rest >= 14)
		for _, r in rest do
			local i = Shot.indexOf(s, r.id) :: number
			local x, z, _, mode = Shot.pose(s, i, s.tEnd)
			t.near(x, r.x, 1e-6)
			t.near(z, r.z, 1e-6)
			t.eq(mode, Cloth.REST)
		end
		t.truthy(2 * R > 0)
	end)
end
