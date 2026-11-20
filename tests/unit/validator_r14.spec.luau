--!strict
-- Validator round 14 (the round-13 review's findings; the failing cases are validator_r13rv): a rail credit only where the
-- server itself has the body on the rail, and every launch charged first. The mechanics those cases do not reach:
--   grab search       the motor's own E+Space climb at ten packets a second: each launch's grab is the motor's own step
--                     from the last accepted place (grasped, six frames): free, nothing charged; at four packets a second
--                     mostly the same (round 15: the search reaches grabSimDt, two of the longest honest packets, within
--                     its work); at two a second the visit is only near: charged leapCost, its flight never a free one
--                     a body 4 st under a bough "grabbing" it every 0.1 s: no grab (a leap off a grab ends no lower than
--                     one off the lowest sample it can take): charged
--   ground to a bough a gap from the ground ending in a fresh flight beside a bough: a leap off the ground, charged, not free
--   off the rail      a gap from a bough to open ground: a free leap off it carries what it carries, the rest of the way is
--                     a ground move (drained past a walk)
--   off an edge       a gap from the ground ending in the air past its apex: no leap where a ledge it could have walked off
--                     stands at the height its fall started (fellOff) and it stood on it; from under it (round 15) or over
--                     open ground the leap is paid (validator_r13rv)
--   flight time       a ground gap read as a leap refills none of the leap's flight
--   ray clock         budgeted()'s refill clock never goes back
-- About 3 s: `lune run tests/run.luau validator_r14`.
local SquirrelMotor = require("@shared/Movement/SquirrelMotor")
local ValidatorWorld = require("@server/Movement/ValidatorWorld")
local MoveValidator = require("@server/Movement/MoveValidator")
local TestWorld = require("@tests/cheat/TestWorld")

type State = SquirrelMotor.State

local P = SquirrelMotor.params

return function(t)
	-- (flat ground at y 0, no walls; `ledge`: a floor at y 7 for x in [lx - 20, lx] (and half a stud for rounding), z anywhere)
	local function world(lx: number?): (any, any)
		local tw = TestWorld.build({})
		local function wall(): boolean
			return false
		end
		local function down(ox: number, oy: number, _oz: number, _dx: number, dy: number, _dz: number): boolean
			local lo = math.min(oy, oy + dy)
			if lx and ox >= lx - 20 and ox <= lx + 0.5 and oy >= 7 and lo <= 7 then
				return true
			end
			return oy >= 0 and lo <= 0
		end
		return tw, ValidatorWorld.build(tw, { wall = wall, down = down })
	end

	local function rig(lx: number?): (any, any, (State) -> any)
		local tw, vw = world(lx)
		local v = MoveValidator.new(vw)
		local seq = 0
		return tw,
			v,
			function(s: State): any
				seq += 1
				return v:accept("a", { seq = seq, snapshot = SquirrelMotor.serialize(s) }, s.clock + 1)
			end
	end

	local function bough(vworld: any, x: number, z: number): (number, number, any)
		local best, id, tt = math.huge, nil, 0
		vworld.index:forEachNear(
			x,
			0,
			z,
			5,
			function(rid: number, rt: number, sx: number, sy: number, sz: number): boolean?
				local d = (sx - x) ^ 2 + (sz - z) ^ 2
				if d < best and sy < 10 then
					best, id, tt = d, rid, rt
				end
				return nil
			end
		)
		assert(id, "a bough near the start")
		return id :: number, tt, vworld.registry:pointAt(vworld.registry:get(id :: number), tt)
	end

	local function stand(feed: (State) -> any, x: number, y: number, z: number, clock: number): number
		for _ = 1, 10 do
			clock += 0.05
			local s = SquirrelMotor.new(x, y, z)
			s.clock = clock
			feed(s)
		end
		return clock
	end

	t.test(
		"grab search: the motor's climb at ten packets a second is free, at four mostly; at two, near only, charged",
		function()
			for _, rate in { 10, 4, 2 } do
				local tw, v, feed = rig()
				local tall: any = nil
				for _, r in tw.registry:all() do
					if r.kind == "trunk" and (tall == nil or r.length > tall.length) then
						tall = r
					end
				end
				local p = tw.registry:pointAt(tall, 0.05)
				local s = SquirrelMotor.new(p.x, p.y, p.z)
				s.routeId, s.railT, s.grounded, s.clock = tall.id, 0.05, false, 0
				s.tireless = true
				feed(SquirrelMotor.clone(s))
				local m = v._marks.a
				local codes, launches, freeOnes = {}, 0, 0
				local every = math.floor(60 / rate + 0.5)
				for f = 1, 120 do
					local i = SquirrelMotor.idleInput(0)
					i.grab, i.leap = f % 4 == 0, f % 4 == 0
					SquirrelMotor.step(s, i, 1 / 60, tw)
					if f % every == 0 then
						local r = feed(SquirrelMotor.clone(s))
						for _, x in r.violations do
							table.insert(codes, x.code)
						end
						if r.launched then
							launches += 1
							freeOnes += if m.speedRail then 1 else 0
						end
					end
				end
				print(
					`      {rate}/s: {launches} launches, {freeOnes} free, meter {string.format("%.2f", m.stamina)}, [{table.concat(
						codes,
						","
					)}]`
				)
				t.eq(#codes, 0, `the motor's own climb at {rate}/s is clean`)
				if rate == 10 then
					t.eq(freeOnes, launches, "every launch a grab the motor's step explains: free")
					t.truthy(m.stamina >= 1 - 1e-6, "nothing charged")
				elseif rate == 4 then
					-- (packets of 0.25 s, inside the search: three or four grabs each, E+Space fifteen times a second, no
					-- person's rate; a pattern that deep is at times past the search's work, and charged, never a violation)
					t.truthy(freeOnes > launches / 2, "the motor's grabs explain most launches: free")
				else
					t.eq(freeOnes, 1, "only the launch off the trunk the server saw is free")
					t.truthy(m.stamina < 1 - P.leapCost * (launches - 2), "the visits near only are charged")
				end
			end
		end
	)

	t.test(
		"grab search: a body 4 st under a bough relaunching every 0.1 s grabbed nothing: charged, not free",
		function()
			local _, v, feed = rig()
			local id, tt, pt = bough(v.world, 0, -200)
			local clock = 0
			for _ = 1, 10 do
				clock += 0.05
				local s = SquirrelMotor.new(pt.x, pt.y, pt.z)
				s.routeId, s.railT, s.grounded, s.clock = id, tt, false, clock
				feed(s)
			end
			local m = v._marks.a
			local x, dir, charged, launches = pt.x, 1, 0, 0
			for k = 1, 20 do
				if math.abs(x - pt.x) > 3 then
					dir = -dir
				end
				-- (a relaunch: 1.5 st over the ground, rising at 10 st/s; then a plain arc)
				x += dir * 4.2
				clock += 0.1
				local before = m.stamina
				local s = SquirrelMotor.new(x, 1.5, pt.z)
				s.grounded, s.vx, s.vy, s.clock = false, dir * 42, 10, clock
				local r = feed(s)
				if r.launched and k > 1 then
					launches += 1
					-- (charged: the meter down by a leap, or held at its floor once there)
					local paid = m.stamina < before - 1e-6 or m.stamina <= -0.5 + 1e-6
					charged += if paid and not m.speedRail then 1 else 0
				end
				x += dir * 4.2
				clock += 0.1
				local a = SquirrelMotor.new(x, 1.5 + 0.25, pt.z)
				a.grounded, a.vx, a.vy, a.clock = false, dir * 37.9, 10 - P.gravity * 0.1, clock
				feed(a)
			end
			print(`      {launches} relaunches, {charged} charged and not free`)
			t.truthy(launches > 0 and charged == launches, "every relaunch under the bough is a charged leap")
		end
	)
	t.test(
		"ground to a bough: a gap from the ground ending in a fresh flight beside a bough is a charged leap",
		function()
			local _, v, feed = rig()
			local _, _, pt = bough(v.world, 0, -200)
			local clock = stand(feed, pt.x, 0, pt.z, 0)
			local m = v._marks.a
			local before = m.stamina
			local age = 0.2
			local s = SquirrelMotor.new(pt.x + 4, pt.y + P.leapUp * age - 0.5 * P.gravity * age * age, pt.z)
			s.grounded, s.vx, s.vy, s.clock = false, P.leapForward, P.leapUp - P.gravity * age, clock + 0.7
			feed(s)
			print(`      free {m.speedRail}, meter {before} -> {m.stamina}`)
			t.eq(m.speedRail, nil, "not free: no rail the server had the body on")
			t.truthy(m.stamina <= before - P.leapCost + 1e-6, "leapCost charged")
		end
	)

	t.test("off the rail: a free leap off a bough carries its flight, the rest of the way is a ground move", function()
		local results = {}
		for _, out in { 35, 70 } do
			local _, v, feed = rig()
			local id, tt, pt = bough(v.world, 0, -200)
			local clock = 0
			for _ = 1, 10 do
				clock += 0.05
				local s = SquirrelMotor.new(pt.x, pt.y, pt.z)
				s.routeId, s.railT, s.grounded, s.clock = id, tt, false, clock
				feed(s)
			end
			local m = v._marks.a
			local before = m.stamina
			local g = SquirrelMotor.new(pt.x, 0, pt.z + out)
			g.clock = clock + 1.1
			feed(g)
			results[out] = before - m.stamina
			print(`      {out} st out in 1.1 s: drained {string.format("%.3f", before - m.stamina)}`)
		end
		t.truthy(results[35] <= 1e-6, "inside a free leap's carry and a walk: nothing drained")
		t.truthy(results[70] > 0.05, "past it: the ground part drains")
	end)

	t.test(
		"off an edge: a fall past a ledge it walked off pays no leap; from under the ledge or over open ground it does",
		function()
			-- (validator round 15, the round-14 review's LOW b: a ledge explains no leap to a body that stood more than a
			-- step under it: getting onto it took a leap)
			for _, case in { { ledge = true, y = 7 }, { ledge = true, y = 0 }, { ledge = false, y = 0 } } do
				local lx = 600
				local _, v, feed = rig(if case.ledge then lx else nil)
				local clock = stand(feed, lx - 5, case.y, -1000, 0)
				local m = v._marks.a
				local before = m.stamina
				-- (0.55 s on: 3 st past the ledge's edge, falling at 7.5 st/s, its fall begun at the ledge's height)
				local vy = -7.5
				local fall = -vy / P.gravity
				local s = SquirrelMotor.new(lx + 3, 7 - 0.5 * P.gravity * fall * fall, -1000)
				s.grounded, s.vx, s.vy, s.clock = false, 3 / fall, vy, clock + 0.55
				feed(s)
				print(`      ledge {case.ledge}, standing at y {case.y}: meter {before} -> {m.stamina}`)
				if case.ledge and case.y == 7 then
					t.truthy(m.stamina >= before - 1e-6, "off the ledge it stood on: no leap charged")
				else
					t.truthy(
						m.stamina <= before - P.leapCost + 1e-6,
						"under the ledge or over open ground: the leap is paid"
					)
				end
			end
		end
	)

	t.test("flight time: a ground gap read as a leap refills none of the leap's flight", function()
		local _, v, feed = rig()
		local x, z = 5000, 5000
		local clock = stand(feed, x, 0, z, 0)
		local m = v._marks.a
		m.stamina = 0.5
		local span = 1.0
		local g = SquirrelMotor.new(x + 52, 0, z)
		g.clock = clock + span
		feed(g)
		local flight = 2 * P.leapUp / P.gravity
		print(`      meter 0.5 -> {m.stamina}`)
		t.truthy(m.stamina <= 0.5 - P.leapCost + (span - flight) / P.sprintRefill + 1e-6, "no refill in the flight")
	end)

	t.test("ray clock: budgeted's refill never goes back in time", function()
		local _, v = rig()
		local most = v.world.aroundBudget
		local pool = v.world.aroundPool
		v:budgeted("a", 10, function(): any
			pool.left = 0
			return nil
		end)
		local m = v._marks.a
		v:budgeted("a", 9.5, function(): any
			return nil
		end)
		t.eq(m.raysAt, 10, "an older caller's time leaves the clock where it was")
		local left = 0
		v:budgeted("a", 10.5, function(): any
			left = pool.left
			return nil
		end)
		t.truthy(math.abs(left - 0.5 * most) < 1e-6, "half a second refills half a second's rays")
	end)
end
