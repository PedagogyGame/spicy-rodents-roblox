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
			local worst = 0
			local checked = 0
			while moving do
				moving = Physics.step(w)
				if w.steps % 7 == 0 then
					for i, b in w.balls do
						local x, z, y, mode = Shot.pose(s, i, w.t)
						if b.mode == Cloth.DOWN then
							t.eq(mode, Cloth.DOWN, "a potted ball is down in the script too")
						else
							worst = math.max(worst, math.abs(x - b.x), math.abs(z - b.z), math.abs(y - b.y))
							checked += 1
						end
					end
				end
			end
			t.truthy(checked > 1000)
			t.truthy(worst < 1e-6, `seed {seed}: playback strays {worst} studs from the model`)
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
		t.truthy(worst < 6000, `the biggest break is {worst} numbers`)
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
