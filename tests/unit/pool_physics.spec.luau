--!strict
-- Minigames/Pool/Physics: the table model both cue games share, pinned against the checklist's "what real must
-- mean" lines (POOL-P1..P6, BP-P1..P5) and against the known cases of any fixed-step model: energy never grows,
-- nothing tunnels at top speed, the same inputs give the same bytes, and a rest state is always reached.
local Cloth = require("@shared/Minigames/Pool/Cloth")
local Cue = require("@shared/Minigames/Pool/Cue")
local Physics = require("@shared/Minigames/Pool/Physics")
local Rng = require("@shared/Util/Rng")
local Shot = require("@shared/Minigames/Pool/Shot")
local Tables = require("@shared/Minigames/Pool/Tables")

return function(t)
	local pool = Tables.eightBall()
	local bumper = Tables.bumper()
	local R = Tables.BALL_R
	local EV = Physics.EV
	local ES = Physics.EVENT_STRIDE

	local function strike(id: number, vx: number, vz: number, roll: number, side: number?): Shot.Strike
		return { id = id, vx = vx, vz = vz, qx = roll * vx, qz = roll * vz, s = side or 0 }
	end

	local function world(tb: Tables.Table, spots: { Tables.Spot }, st: Shot.Strike): Physics.World
		local w = Physics.world(tb, spots)
		Physics.strike(w, st.id, st.vx, st.vz, st.qx, st.qz, st.s)
		return w
	end

	-- step until `n` contacts have been recorded (or everything has stopped)
	local function untilEvents(w: Physics.World, n: number)
		while #w.events < n * ES do
			if not Physics.step(w) then
				break
			end
		end
	end

	local function toRest(w: Physics.World): number
		local guard = 0
		while Physics.step(w) do
			guard += 1
			assert(guard < 240 * 60, "the table never came to rest")
		end
		return w.t
	end

	local function kinds(s: Shot.Script, kind: number, before: number?): number
		local n = 0
		for e = 1, #s.events, ES do
			if s.events[e + 1] == kind and (before == nil or s.events[e] < before) then
				n += 1
			end
		end
		return n
	end

	local function restOf(s: Shot.Script, id: number): (number, number)
		for _, r in Shot.rest(s) do
			if r.id == id then
				return r.x, r.z
			end
		end
		error(`ball {id} is not on the table`)
	end

	-- the object ball set for a cut of `deg` degrees against a cue ball arriving up the table at the origin
	local function cut(deg: number, speed: number, roll: number, side: number?): Physics.World
		local a = math.rad(deg)
		local spots = { { id = 0, x = 0, z = -0.002 }, { id = 1, x = 2 * R * math.sin(a), z = 2 * R * math.cos(a) } }
		local w = world(pool, spots, strike(0, 0, speed, roll, side))
		untilEvents(w, 1)
		return w
	end

	t.test(
		"POOL-P1 a full hit with a stunned cue ball: the object ball takes the speed, the cue ball stops dead",
		function()
			local w = cut(0, 4, 0)
			local c, o = w.balls[1], w.balls[2]
			t.eq(w.events[2], EV.ball)
			t.near(o.vz, 4 * (1 + Physics.E_BALL) / 2, 0.05, "near-elastic, equal masses")
			t.truthy(c.vz >= 0 and c.vz < 0.35, "the cue ball keeps almost nothing")
			t.near(c.vz + o.vz, 4, 0.12, "momentum is kept (less what the cloth took in the rest of the step)")
			toRest(w)
			t.truthy(math.abs(c.z) < 0.03, `it stops where it hit ({c.z})`)
		end
	)

	t.test("POOL-P1 the 90 degree rule: a stunned cue ball leaves along the tangent line", function()
		for _, deg in { 20, 30, 45, 60 } do
			local w = cut(deg, 12, 0)
			local c, o = w.balls[1], w.balls[2]
			local between = math.deg(math.abs(math.atan2(o.vx, o.vz) - math.atan2(c.vx, c.vz)))
			t.truthy(between > 81 and between < 92, `{deg} degree cut: the balls part at {between}`)
			-- the object ball leaves along the line of centres (give or take the throw)
			t.near(math.deg(math.atan2(o.vx, o.vz)), deg, 5)
		end
	end)

	t.test("POOL-P1 a rolling cue ball bends forward of the tangent line (and a drawn one behind it)", function()
		local function finalAngle(roll: number): number
			local w = cut(30, 8, roll)
			local c = w.balls[1]
			-- once it rolls again (no slip left) its direction is where it is really going
			local guard = 0
			while math.abs(c.vx - c.qx) + math.abs(c.vz - c.qz) > 1e-9 and guard < 2000 do
				Physics.step(w)
				guard += 1
			end
			return math.deg(math.atan2(-c.vx, c.vz)) -- off its original line, away from the object ball
		end
		local stun, roll, draw = finalAngle(0), finalAngle(1), finalAngle(-1)
		t.truthy(stun > 50 and stun < 66, `stun leaves near the tangent ({stun}; the tangent is 60)`)
		t.truthy(roll > 20 and roll < 45, `a rolling ball is turned about 30 degrees ({roll})`)
		t.truthy(draw > 90, `a drawn ball comes back past the tangent ({draw})`)
	end)

	t.test(
		"throw: a cut drags the object ball a little off the line of centres; side spin does it on a full hit",
		function()
			local w = cut(30, 6, 0)
			local o = w.balls[2]
			local thrown = 30 - math.deg(math.atan2(o.vx, o.vz))
			t.truthy(thrown > 0.5 and thrown < 5, `cut throw {thrown} degrees`)
			-- a full hit with right-hand side: the object ball goes left and picks up a little of the opposite spin
			local f = cut(0, 6, 0, 8)
			local fo = f.balls[2]
			local side = math.deg(math.atan2(fo.vx, fo.vz))
			t.truthy(side < -0.3 and side > -5, `spin throw {side} degrees`)
			t.truthy(fo.s < 0, "spin is handed on, reversed")
			t.truthy(f.balls[1].s < 8, "and taken from the cue ball")
			-- no spin, full hit: dead straight
			local p = cut(0, 6, 0)
			t.eq(p.balls[2].vx, 0)
		end
	)

	t.test("POOL-P2 through the cue: follow rolls on, a stop shot stops, draw comes back", function()
		local function past(tipY: number): number
			local spots = { { id = 0, x = 0, z = -5 }, { id = 1, x = 0, z = -4 } }
			local s = Shot.run(pool, spots, { Cue.strike(0, 0, 0.25, 0, tipY, nil) })
			local _, z = restOf(s, 0)
			return z - (-4 - 2 * R)
		end
		local follow, stop, draw = past(0.8), past(-0.35), past(-0.8)
		t.truthy(follow > 1.5, `follow goes on {follow} studs`)
		t.truthy(math.abs(stop) < 0.08, `a stop shot stays put ({stop})`)
		t.truthy(draw < -0.4, `draw comes back {draw} studs`)
	end)

	t.test("POOL-P3 a cushion gives back 75 to 85 % of the speed, slightly less on hard shots", function()
		local last = 1
		for _, v in { 2, 5, 10, 20, 35, 55 } do
			local w = world(pool, { { id = 0, x = 0, z = pool.halfL - R - 0.05 } }, strike(0, 0, v, 1))
			untilEvents(w, 1)
			t.eq(w.events[2], EV.cushion)
			local back = -w.balls[1].vz / w.events[5]
			t.truthy(back >= 0.74 and back <= 0.86, `{v} studs/s: {back}`)
			t.truthy(back <= last + 0.02, "harder is never livelier")
			last = back
		end
		t.truthy(last < 0.78, "the hardest shot is the deadest")
	end)

	t.test(
		"POOL-P3 side spin widens or narrows the angle off a cushion; the same bank is the same bank (BP-P3)",
		function()
			local function off(side: number, degIn: number?): number
				local a = math.rad(degIn or 45)
				local v = 10
				local w = world(pool, { { id = 0, x = -2, z = pool.halfL - R - 0.3 } }, {
					id = 0,
					vx = v * math.cos(a),
					vz = v * math.sin(a),
					qx = v * math.cos(a),
					qz = v * math.sin(a),
					s = side,
				})
				untilEvents(w, 1)
				local b = w.balls[1]
				return math.deg(math.atan2(-b.vz, b.vx)) -- the angle off the cushion on the way out
			end
			local plain, running, check = off(0), off(8), off(-8)
			t.truthy(running < plain - 4, `running side comes off longer ({running} against {plain})`)
			t.truthy(check > plain + 4, `check side comes off shorter ({check} against {plain})`)
			t.truthy(plain > 44 and plain < 54, `no side is near a mirror, a little short ({plain})`)
			t.eq(off(0), plain, "the same shot is the same shot")
			-- a bank can be learned: a small change in comes out as a small change
			t.truthy(math.abs(off(0, 45.2) - plain) < 0.6)
			t.truthy(off(0, 30) < off(0, 45) and off(0, 45) < off(0, 60), "steeper in, steeper out")
		end
	)

	t.test("POOL-P3 the angle shortens a little at speed: a hard bank comes off steeper than a soft one", function()
		-- a ball into the foot cushion at 45 degrees. Returns the angle off the cushion as it leaves, and the
		-- angle it settles to once the cloth has it rolling again (v = (5 v + 2 q) / 7)
		local function bank(v: number, roll: number): (number, number)
			local c = v * 0.7071067811865476
			local w = world(pool, { { id = 0, x = -2.2, z = pool.halfL - R - 0.01 } }, {
				id = 0,
				vx = c,
				vz = c,
				qx = roll * c,
				qz = roll * c,
				s = 0,
			})
			untilEvents(w, 1)
			t.eq(w.events[2], EV.cushion)
			local k = w.keys[1]
			local o = #k - Physics.KEY_STRIDE
			local vx, vz, qx, qz = k[o + 4], k[o + 5], k[o + 6], k[o + 7]
			local off = math.deg(math.atan2(-vz, vx))
			return off, math.deg(math.atan2(-(5 * vz + 2 * qz), 5 * vx + 2 * qx))
		end
		-- a ball that arrives rolling: each harder bank leaves a little steeper and settles a little steeper
		local lastOff, lastSettled = 0, 0
		for _, v in { 2, 5, 9, 14, 22, 34 } do
			local off, settled = bank(v, 1)
			t.truthy(off > lastOff, `{v} studs/s leaves at {off} (softer: {lastOff})`)
			t.truthy(settled > lastSettled, `{v} studs/s settles at {settled} (softer: {lastSettled})`)
			lastOff, lastSettled = off, settled
		end
		local softOff, softSettled = bank(2, 1)
		local hardOff, hardSettled = bank(22, 1)
		t.truthy(
			hardOff - softOff > 2 and hardOff - softOff < 7,
			`a little: {hardOff - softOff} degrees off the cushion`
		)
		t.truthy(
			hardSettled - softSettled > 0.8 and hardSettled - softSettled < 5,
			`{hardSettled - softSettled} settled`
		)
		-- a rolling ball banks long of a mirror (its roll carries it on); a firm shot arrives still sliding and
		-- banks short of one: the same cushion, the two banks a player learns
		local _, rolling = bank(9, 1)
		local _, sliding = bank(9, 0)
		t.truthy(rolling < 45 and rolling > 36, `rolling in: {rolling}`)
		t.truthy(sliding > 45 and sliding < 62, `sliding in: {sliding}`)
	end)

	t.test("POOL-P4 a clean pot drops: straight into a corner and straight into a side pocket", function()
		for _, h in { 6, 4, 1, 3 } do
			local hole = pool.holes[h]
			local sx, sz = hole.x + hole.mx * 2.4, hole.z + hole.mz * 2.4
			for _, speed in { 3, 9, 25 } do
				local s = Shot.run(
					pool,
					{ { id = 1, x = sx, z = sz } },
					{ strike(1, -hole.mx * speed, -hole.mz * speed, 1) }
				)
				local pots = Shot.pots(s)
				t.eq(#pots, 1, `pocket {h} at {speed}`)
				t.eq(pots[1].hole, h)
				t.eq(kinds(s, EV.jaw), 0, "it touched nothing on the way in")
				t.eq(#s.rest, 0, "and it is off the table")
			end
		end
	end)

	t.test("POOL-P4 the side pockets refuse a ball from along the cushion; the corners take it", function()
		local hole = pool.holes[4]
		for _, speed in { 4, 12, 30 } do
			-- 72 degrees off the side pocket's centre line, aimed at the middle of its mouth
			local a = math.rad(72)
			local dx, dz = math.cos(a), math.sin(a)
			local from = { { id = 1, x = pool.halfW - 2.2 * dx, z = -2.2 * dz } }
			local s = Shot.run(pool, from, { strike(1, dx * speed, dz * speed, 1) }, 2.2 / speed * 1.5 + 0.4)
			t.eq(#Shot.pots(s), 0, `refused at {speed}`)
			t.truthy(kinds(s, EV.jaw) + kinds(s, EV.cushion) > 0, "it hit the far jaw")
			local x = restOf(s, 1)
			t.truthy(x < pool.halfW, "and stayed on the table")
		end
		-- a ball rolled down the long cushion drops in the corner
		local s = Shot.run(pool, { { id = 1, x = pool.halfW - R - 0.02, z = 2 } }, { strike(1, 0, 6, 1) })
		t.eq(#Shot.pots(s), 1)
		t.eq(Shot.pots(s)[1].hole, 6)
		t.eq(hole.mz, 0)
	end)

	t.test("POOL-P4 jaws: across a sweep of lines some drop clean, some rattle in, some rattle and stay up", function()
		local hole = pool.holes[6]
		local clean, rattledIn, stayedUp, wide = 0, 0, 0, 0
		for i = -40, 40 do
			local off = i * 0.0125
			-- along the pocket's centre line, shifted sideways
			local sx = hole.x + hole.mx * 2.5 - hole.mz * off
			local sz = hole.z + hole.mz * 2.5 + hole.mx * off
			local s = Shot.run(pool, { { id = 1, x = sx, z = sz } }, { strike(1, -hole.mx * 7, -hole.mz * 7, 1) }, 1)
			local jaws = kinds(s, EV.jaw)
			if #s.pots > 0 then
				if jaws == 0 then
					clean += 1
				else
					rattledIn += 1
				end
			elseif jaws > 0 then
				stayedUp += 1
			else
				wide += 1
			end
		end
		t.truthy(clean >= 10, `clean pots {clean}`)
		t.truthy(rattledIn >= 2, `off a jaw and in {rattledIn}`)
		t.truthy(stayedUp >= 2, `off a jaw and out {stayedUp}`)
		t.truthy(wide >= 10, `the cushion beside the pocket is still a cushion ({wide})`)
		t.truthy(clean + rattledIn < 40, "the pocket is not a bucket: under half of a three-ball-wide sweep goes in")
	end)

	t.test("POOL-P4 a pocket plays tighter when it is hammered: pocket speed drops what a hard shot rattles", function()
		-- down the long cushion into the foot right corner, a third of a ball off the cushion to a ball and a
		-- quarter off it: at pocket speed every line drops; hammered, the wider lines rattle in the jaws and stay up
		local function downTheRail(speed: number): (number, number, number)
			local pots, rattles, lines = 0, 0, 0
			for g = 3, 14 do
				lines += 1
				local from = { { id = 1, x = pool.halfW - R - g * 0.1 * R, z = 0.8 } }
				local s = Shot.run(pool, from, { strike(1, 0, speed, 1) }, 6 / speed + 1.5)
				local pot = Shot.pots(s)
				if #pot > 0 then
					t.eq(pot[1].hole, 6)
					pots += 1
				elseif kinds(s, EV.jaw) > 0 then
					rattles += 1
				end
			end
			return pots, rattles, lines
		end
		local softPots, _, lines = downTheRail(5)
		t.eq(softPots, lines, "at pocket speed the corner takes every one of them")
		local firmPots = downTheRail(16)
		local hardPots, hardRattles = downTheRail(40)
		t.truthy(firmPots <= softPots and hardPots <= firmPots, `never easier when harder ({firmPots}, {hardPots})`)
		t.truthy(hardPots <= lines - 4, `hammered, the pocket turns the wider lines away ({hardPots} of {lines})`)
		t.truthy(hardRattles >= 4, `and they rattle in the jaws ({hardRattles})`)
		t.truthy(hardPots >= 1, "a hard shot tight on the cushion still goes")
		-- straight down a pocket's centre line the speed does not matter (POOL-P4 "a clean pot drops")
		local hole = pool.holes[6]
		for _, speed in { 4, 16, 40 } do
			local from = { { id = 1, x = hole.x + hole.mx * 2.4, z = hole.z + hole.mz * 2.4 } }
			t.eq(#Shot.pots(Shot.run(pool, from, { strike(1, -hole.mx * speed, -hole.mz * speed, 1) })), 1)
		end
		-- a side pocket from 45 degrees: wide at pocket speed, narrow when hammered
		local function sideWindow(speed: number): number
			local side = pool.holes[4]
			local c = 0.7071067811865476
			local n = 0
			for i = -20, 20 do
				local off = i * 0.02
				-- travelling toward +x and +z, aimed at the middle of the mouth, shifted sideways by `off`
				local from = { { id = 1, x = side.x - 0.26 - c * 2 - c * off, z = -c * 2 + c * off } }
				local s = Shot.run(pool, from, { strike(1, c * speed, c * speed, 1) }, 3 / speed + 0.6)
				if #s.pots > 0 then
					n += 1
				end
			end
			return n
		end
		local slow, fast = sideWindow(4), sideWindow(36)
		t.truthy(slow >= 10, `at pocket speed the side takes a ball-wide window ({slow} lines)`)
		t.truthy(fast <= slow - 4, `hammered it takes far less ({fast} against {slow})`)
	end)

	t.test("POOL-P4 a ball can hang on the lip of a corner pocket, and a touch drops it", function()
		local hole = pool.holes[6]
		-- the middle of the mouth is CORNER_SHELF + CORNER_HOLE_R from the hole's centre, on its centre line
		local toMouth = Tables.CORNER_SHELF + Tables.CORNER_HOLE_R
		local mx, mz = hole.x + hole.mx * toMouth, hole.z + hole.mz * toMouth
		local v = Cloth.speedFor(1 + Tables.CORNER_SHELF * 0.5)
		local spots = { { id = 1, x = mx + hole.mx, z = mz + hole.mz } }
		local s = Shot.run(pool, spots, { strike(1, -hole.mx * v, -hole.mz * v, 1) })
		t.eq(#s.pots, 0, "it did not drop")
		local x, z = restOf(s, 1)
		local fromHole = math.sqrt((x - hole.x) ^ 2 + (z - hole.z) ^ 2)
		t.truthy(
			fromHole > hole.r and fromHole < toMouth,
			`it sits on the lip, between the jaws ({fromHole - hole.r} from the drop)`
		)
		-- a little harder and it is gone
		local s2 = Shot.run(pool, spots, { strike(1, -hole.mx * (v + 0.4), -hole.mz * (v + 0.4), 1) })
		t.eq(#Shot.pots(s2), 1)
		-- and the hanging ball goes down when another ball touches it
		local two = { { id = 1, x = x, z = z }, { id = 0, x = x + hole.mx * 2, z = z + hole.mz * 2 } }
		local s3 = Shot.run(pool, two, { strike(0, -hole.mx * 3, -hole.mz * 3, 1) })
		t.eq(Shot.pots(s3)[1].ball, 1)
	end)

	t.test("POOL-P5 the break scatters a full rack; no two balls ever pass through each other", function()
		for seed = 1, 6 do
			local w = Physics.world(pool, Tables.rack(seed))
			local st = Cue.strike(0, 0, 1, 0, 0.3, seed)
			Physics.strike(w, st.id, st.vx, st.vz, st.qx, st.qz, st.s)
			local worst = 0
			local moving = true
			while moving do
				moving = Physics.step(w)
				for i = 1, #w.balls - 1 do
					local a = w.balls[i]
					if a.mode == Cloth.CLOTH or a.mode == Cloth.REST then
						for j = i + 1, #w.balls do
							local b = w.balls[j]
							if b.mode == Cloth.CLOTH or b.mode == Cloth.REST then
								local d = math.sqrt((a.x - b.x) ^ 2 + (a.z - b.z) ^ 2)
								worst = math.max(worst, 2 * R - d)
							end
						end
					end
				end
			end
			t.truthy(worst < 2e-3, `seed {seed}: balls sank {worst} studs into each other`)
			t.eq(w.knots, 0)
			local moved = 0
			for _, b in w.balls do
				if
					b.id ~= 0
					and (b.mode ~= Cloth.REST or math.abs(b.z - pool.footZ - 0.6) > 0.7 or math.abs(b.x) > 0.7)
				then
					moved += 1
				end
			end
			t.truthy(moved >= 9, `seed {seed}: {moved} of 15 left the rack area`)
		end
	end)

	t.test(
		"POOL-P5 over many breaks: something is potted often, the cue ball is not always lost, no two alike",
		function()
			local N = 60
			local pots, dry, scratches, far, head = 0, 0, 0, 0, 0
			local layouts: { [string]: boolean } = {}
			local distinct = 0
			for seed = 1, N do
				local s = Shot.run(pool, Tables.rack(seed), { Cue.strike(0, 0, 1, 0, 0.3, seed) })
				t.falsy(s.capped)
				local n = 0
				for _, p in Shot.pots(s) do
					if p.ball == 0 then
						scratches += 1
					else
						n += 1
					end
				end
				pots += n
				if n == 0 then
					dry += 1
				end
				local key = ""
				for _, r in Shot.rest(s) do
					if r.id ~= 0 then
						if (r.x * r.x + (r.z - pool.footZ - 0.6) ^ 2) > 4 then
							far += 1
						end
						if r.z < 0 then
							head += 1
						end
					end
					key ..= string.format("%d:%.4f,%.4f;", r.id, r.x, r.z)
				end
				if not layouts[key] then
					layouts[key] = true
					distinct += 1
				end
			end
			t.eq(distinct, N, "every break is its own")
			t.truthy(pots / N > 0.4 and pots / N < 1.6, `balls potted per break {pots / N}`)
			t.truthy(dry / N > 0.15 and dry / N < 0.65, `dry breaks {dry / N}`)
			t.truthy(scratches / N < 0.4, `scratches {scratches / N}`)
			t.truthy(scratches > 0, "but it can happen")
			t.truthy(far / N >= 8, `balls more than 2 studs from the rack: {far / N} of 15`)
			t.truthy(head / N >= 3.5, `balls up in the head half: {head / N}`)
		end
	)

	t.test("POOL-P5 simultaneous contacts are settled in a fixed order: the same break is the same bytes", function()
		local function bytes(seed: number): string
			local s = Shot.run(pool, Tables.rack(seed), { Cue.strike(0, 0, 1, 0, 0.3, seed) })
			local parts: { string } = {}
			for _, track in s.tracks do
				for _, v in track do
					table.insert(parts, string.format("%.17g", v))
				end
			end
			for _, v in s.events do
				table.insert(parts, string.format("%.17g", v))
			end
			for _, v in s.rest do
				table.insert(parts, string.format("%.17g", v))
			end
			return table.concat(parts, ",")
		end
		local a, b = bytes(11), bytes(11)
		t.truthy(a == b, "determinism: same seed and inputs, same bytes")
		t.truthy(bytes(12) ~= a)
		t.truthy(#a > 5000)
	end)

	t.test("POOL-P5 a ball driven into two at once treats them alike: the split is a mirror image", function()
		local h = math.sqrt(3) * R
		local spots = { { id = 0, x = 0, z = -0.5 }, { id = 1, x = -R, z = h }, { id = 2, x = R, z = h } }
		local w = world(pool, spots, strike(0, 0, 10, 0))
		untilEvents(w, 2)
		local c, a, b = w.balls[1], w.balls[2], w.balls[3]
		t.eq(w.events[1], w.events[ES + 1], "both contacts at the same moment")
		t.near(a.vx, -b.vx, 1e-6)
		t.near(a.vz, b.vz, 1e-6)
		t.near(c.vx, 0, 1e-6)
		t.near(math.deg(math.atan2(b.vx, b.vz)), 30, 2.5, "each leaves along its line of centres")
		t.truthy(c.vz < 0, "and the cue ball comes back off the pair")
		t.truthy(Physics.energy(w) < 0.5 * 10 * 10)
	end)

	t.test("energy never grows: breaks, hard shots with every spin, and bumper pool among the posts", function()
		local function watch(w: Physics.World, label: string)
			local e = Physics.energy(w)
			local moving = true
			local guard = 0
			while moving do
				moving = Physics.step(w)
				local now = Physics.energy(w)
				if now > e * (1 + 1e-12) + 1e-12 then
					error(`{label}: energy grew from {e} to {now} at t = {w.t}`)
				end
				e = now
				guard += 1
				assert(guard < 240 * 60, `{label}: never came to rest`)
			end
			t.eq(e, 0, "at rest there is none left")
		end
		for seed = 1, 5 do
			local w = Physics.world(pool, Tables.rack(seed))
			local st = Cue.strike(0, 0, 1, 0, 0.3, seed)
			Physics.strike(w, st.id, st.vx, st.vz, st.qx, st.qz, st.s)
			watch(w, `break {seed}`)
		end
		local rng = Rng.new(42)
		for k = 1, 30 do
			local spots = Tables.rack(k)
			local st = Cue.strike(0, rng.range(-0.6, 0.6), rng.range(0.3, 0.9), rng.range(-1, 1), rng.range(-1, 1), nil)
			watch(world(pool, spots, st), `shot {k}`)
		end
		for k = 1, 30 do
			local st =
				Cue.strike(1 + (k % 5), rng.range(-math.pi, math.pi), rng.range(0.2, 1), rng.range(-1, 1), 0, nil)
			watch(world(bumper, Tables.bumperStart(), st), `bumper {k}`)
		end
	end)

	t.test("nothing tunnels at top speed: a ball never crosses a cushion, a bumper or another ball", function()
		local rng = Rng.new(7)
		local top = Cue.MAX_SPEED
		for k = 1, 60 do
			local angle = rng.range(-math.pi, math.pi)
			local w = world(
				pool,
				{ { id = 0, x = rng.range(-2, 2), z = rng.range(-4.5, 4.5) } },
				strike(0, top * math.sin(angle), top * math.cos(angle), rng.range(-1, 1), rng.range(-40, 40))
			)
			local moving = true
			while moving do
				moving = Physics.step(w)
				local b = w.balls[1]
				if b.mode == Cloth.CLOTH or b.mode == Cloth.REST then
					local nearPocket = false
					for _, hole in pool.holes do
						if (b.x - hole.x) ^ 2 + (b.z - hole.z) ^ 2 < 0.8 ^ 2 then
							nearPocket = true
						end
					end
					if not nearPocket then
						t.truthy(math.abs(b.x) <= pool.halfW - R + 1e-4, `shot {k}: through a side cushion ({b.x})`)
						t.truthy(math.abs(b.z) <= pool.halfL - R + 1e-4, `shot {k}: through an end cushion ({b.z})`)
					end
				end
				t.truthy(math.abs(b.x) < pool.halfW + 0.75 and math.abs(b.z) < pool.halfL + 0.75, "never off the table")
			end
		end
		for k = 1, 60 do
			local angle = rng.range(-math.pi, math.pi)
			local w = world(
				bumper,
				Tables.bumperStart({ true, false }),
				strike(1, top * math.sin(angle), top * math.cos(angle), 1)
			)
			local moving = true
			while moving do
				moving = Physics.step(w)
				for _, b in w.balls do
					if b.mode == Cloth.CLOTH or b.mode == Cloth.REST then
						t.truthy(math.abs(b.x) <= bumper.halfW - R + 1e-4 and math.abs(b.z) <= bumper.halfL - R + 1e-4)
						for _, p in bumper.posts do
							local d = math.sqrt((b.x - p.x) ^ 2 + (b.z - p.z) ^ 2)
							t.truthy(d >= p.r + R - 1e-4, `shot {k}: inside a bumper ({d})`)
						end
					end
				end
			end
		end
		-- a thin target at the far end of the table, full speed: it is hit, not passed
		for i = -3, 3 do
			local spots = { { id = 0, x = 0, z = -5 }, { id = 1, x = i * 0.1, z = 5 } }
			local s = Shot.run(pool, spots, { strike(0, 0, top, 0) }, 0.5)
			t.eq(s.first[1], 1, `offset {i * 0.1}`)
			t.near(s.firstT, (10 - math.sqrt(4 * R * R - (i * 0.1) ^ 2)) / top, 0.02)
		end
	end)

	t.test("POOL-P6 a rest state is always reached, within about ten seconds", function()
		local longest = 0
		for seed = 1, 40 do
			local s = Shot.run(pool, Tables.rack(seed), { Cue.strike(0, 0, 1, 0, 0.3, seed) })
			t.falsy(s.capped, `break {seed} ran into the cap`)
			t.eq(s.knots, 0)
			longest = math.max(longest, s.tEnd)
		end
		t.truthy(longest < 10.5, `the longest break took {longest} s`)
		local rng = Rng.new(3)
		for _ = 1, 40 do
			local st = Cue.strike(0, rng.range(-math.pi, math.pi), 1, rng.range(-1, 1), rng.range(-1, 1), nil)
			local s = Shot.run(pool, { { id = 0, x = rng.range(-2, 2), z = rng.range(-4, 4) } }, { st })
			t.falsy(s.capped)
			t.truthy(s.tEnd < 10.5, `a lone ball at full power took {s.tEnd} s`)
		end
		-- a soft shot is a real shot: it rolls for seconds, and nothing refuses it for being slow
		local soft = Shot.run(pool, { { id = 0, x = 0, z = -5 } }, { strike(0, 0, 4.2, 1) })
		t.truthy(soft.tEnd > 4 and soft.tEnd < 6.5, `{soft.tEnd}`)
	end)

	t.test("touching balls rolling on together do not lock the table (the closing-speed floor)", function()
		-- two balls in contact, the back one pushing: thousands of contacts in a step before the floor was added
		local w = Physics.world(pool, { { id = 1, x = 0, z = 0 }, { id = 2, x = 0, z = 2 * R } })
		Physics.strike(w, 1, 0, 2, 0, 2, 0)
		local time = toRest(w)
		t.truthy(time < 6)
		t.eq(w.knots, 0)
		t.truthy(w.contacts < 400, `{w.contacts} contacts`)
		t.truthy(w.balls[2].z > w.balls[1].z + 2 * R - 1e-3, "and they never changed places")
	end)

	t.test("BP-P1 a bumper is lively rubber; a ball can rattle between two of them", function()
		for _, v in { 3, 10, 25 } do
			local w = world(bumper, { { id = 1, x = 0, z = -Tables.CROSS_INNER - 0.5 } }, strike(1, 0, v, 1))
			untilEvents(w, 1)
			t.eq(w.events[2], EV.post)
			local back = -w.balls[1].vz / w.events[5]
			t.truthy(back >= 0.84 and back <= 0.93, `{v}: {back}`)
			t.truthy(back > Physics.CUSHION.eSoft - 0.04, "livelier than a cushion at the same speed")
		end
		-- up into the notch between an inner and an outer post of one arm: it cannot pass and hits both
		local mid = (Tables.CROSS_INNER + Tables.CROSS_OUTER) / 2
		local s = Shot.run(bumper, { { id = 1, x = mid + 0.01, z = -1 } }, { strike(1, 0, 8, 1) }, 1)
		t.truthy(kinds(s, EV.post, 0.5) >= 2, "a rattle")
		local _, z = restOf(s, 1)
		t.truthy(z < 0, "and it came back out the way it went in")
	end)

	t.test("BP-P1 the gap in the cross lets exactly one ball through, without a touch, a tunnel or a jitter", function()
		local d = 0.7071067811865476
		local function through(off: number, speed: number): (number, number)
			local from = { { id = 1, x = -0.9 + off * d, z = -0.9 - off * d } }
			local s = Shot.run(bumper, from, { strike(1, speed * d, speed * d, 1) }, 1.8 / speed + 0.1)
			local x, z = Shot.pose(s, 1, 1.8 / speed)
			return kinds(s, EV.post, 1.8 / speed), x + z
		end
		for _, speed in { 2, 6, 20, Cue.MAX_SPEED } do
			local posts, along = through(0, speed)
			t.eq(posts, 0, `down the middle at {speed}`)
			t.truthy(along > 0.1, `it came out the far side ({along})`)
			local hit = through(0.06, speed)
			t.truthy(hit >= 1, `0.06 off the middle at {speed} it clips a post`)
		end
		-- a ball as wide as the gap plus a hair would not fit: the gap is under a ball and a quarter
		local s = Shot.run(bumper, { { id = 1, x = -0.9, z = -0.9 } }, { strike(1, 5 * d, 5 * d, 1) })
		t.eq(s.knots, 0)
		t.truthy(s.contacts < 60, "no jitter in the gap")
	end)

	t.test("BP-P2 a cup takes a ball by its speed: soft drops, hard skips over, a graze lips out", function()
		-- a cup alone in the middle of the cloth (no bumpers, no cushion behind it), so only the cup speaks
		local lone = table.clone(bumper)
		lone.posts = {}
		lone.holes = { { x = 0, z = 0, r = Tables.CUP_R, mx = 0, mz = 0, cup = true, depth = Tables.CUP_DEPTH } }
		local function at(tb: Tables.Table, cz: number, speed: number, off: number): (string, Shot.Script)
			local from = { { id = 1, x = off, z = cz - 1.2 } }
			local s = Shot.run(tb, from, { strike(1, 0, speed, 1) }, 1.2 / speed + 0.25)
			for e = 1, #s.events, ES do
				if s.events[e + 1] == EV.drop then
					return "drop", s
				elseif s.events[e + 1] == EV.rim then
					return "out", s
				end
			end
			return "none", s
		end
		for _, speed in { 1.8, 2.5, 3.5 } do
			t.eq((at(lone, 0, speed, 0)), "drop", `{speed} studs/s drops`)
			t.eq((at(lone, 0, speed, 0.15)), "drop", `{speed} studs/s drops off centre too`)
		end
		-- the middle of the cup takes a faster ball than its edge: at 4.2 the centre line drops, a line two
		-- thirds of the way out rides the lip and comes out, and right at the edge even a slow ball does
		t.eq((at(lone, 0, 4.2, 0)), "drop")
		t.eq((at(lone, 0, 4.2, 0.15)), "out", "off centre at the same speed it lips out")
		t.eq((at(lone, 0, 3.6, 0.205)), "out", "a graze at the very edge")
		t.eq((at(lone, 0, 1.8, 0.205)), "drop", "unless it is rolling dead slow")
		for _, speed in { 5.5, 9, 14, 30 } do
			local what, s = at(lone, 0, speed, 0)
			t.eq(what, "out", `{speed} studs/s skips over`)
			t.eq(#s.pots, 0)
		end
		-- skipping over costs speed: the ball comes out slower than it went in
		local _, fast = at(lone, 0, 7, 0)
		local vin, vout = 0, 0
		for e = 1, #fast.events, ES do
			if fast.events[e + 1] == EV.enter then
				vin = fast.events[e + 4]
			elseif fast.events[e + 1] == EV.rim then
				vout = fast.events[e + 4]
			end
		end
		t.truthy(vout > 0 and vout < vin - 0.5, `in at {vin}, out at {vout}`)
		-- a graze: in over the rim and out again, turned off its line (a lip-out)
		local what, lip = at(lone, 0, 6.5, 0.17)
		t.eq(what, "out", "a lip-out")
		local _, _, _, _, vx = Shot.pose(lip, 1, 1.2 / 6.5 + 0.2)
		t.truthy(math.abs(vx) > 0.15, `turned off its line ({vx})`)
		t.eq(#lip.pots, 0)
		-- on the real table the end cushion stands just behind the cup: a firm ball hits the back and drops,
		-- a really hard one comes back out over the front
		local cup = bumper.holes[2]
		for _, speed in { 1.8, 3, 5 } do
			t.eq((at(bumper, cup.z, speed, 0)), "drop", `{speed} studs/s drops`)
		end
		for _, speed in { 12, 20 } do
			t.eq((at(bumper, cup.z, speed, 0)), "out", `{speed} studs/s comes back out`)
		end
	end)

	t.test("BP-P4 a ball left in front of a cup really blocks it", function()
		local cup = bumper.holes[2]
		local blocker = { id = 6, x = 0, z = cup.z - Tables.CUP_R - R - 0.05 }
		local s = Shot.run(bumper, { { id = 1, x = 0, z = 1 }, blocker }, { strike(1, 0, 2.6, 1) })
		t.eq(s.first[1], 6, "the shot meets the blocker")
		for _, p in Shot.pots(s) do
			t.truthy(p.ball ~= 1, "the shooter's ball does not get to the cup")
		end
		-- without the blocker the same shot drops
		local open = Shot.run(bumper, { { id = 1, x = 0, z = 1 } }, { strike(1, 0, 2.6, 1) })
		t.eq(Shot.pots(open)[1].ball, 1)
	end)

	t.test("BP-P5 the opening is two strikes in one model run, and the table is fair to both ends", function()
		local spots = Tables.bumperStart()
		local a = Cue.strike(1, math.rad(38), 0.2, 0, 0.8, nil)
		local b = Cue.strike(6, math.rad(38) + math.pi, 0.2, 0, 0.8, nil)
		local s = Shot.run(bumper, spots, { a, b })
		t.eq(#s.first, 2)
		local i1, i6 = Shot.indexOf(s, 1) :: number, Shot.indexOf(s, 6) :: number
		t.truthy(#s.tracks[i1] > 0 and #s.tracks[i6] > 0, "both balls were struck")
		t.eq(s.tracks[i1][1], 0)
		t.eq(s.tracks[i6][1], 0, "at the same moment")
		-- the two strikes are mirror images through the middle of the table, so the two balls are too
		for _, time in { 0.2, 0.6, 1.5, s.tEnd } do
			local x1, z1 = Shot.pose(s, i1, time)
			local x6, z6 = Shot.pose(s, i6, time)
			t.near(x1, -x6, 1e-6, `x at {time}`)
			t.near(z1, -z6, 1e-6, `z at {time}`)
		end
		t.truthy(kinds(s, EV.cushion) >= 2, "each banked off its side cushion")
	end)
end
