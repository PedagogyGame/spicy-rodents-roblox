--!strict
-- Validator round 15 (the round-14 review's findings): the grab search's cost and reach, a move between two rails, and
-- the LOW notes.
--   grab cost         the worst crafted launch packets in the air at the town's densest rails (every packet length up to
--                     grabSimDt, falling or flying across, an end the search explains or not): the search's own work stays
--                     within envelopeParams.grabWork, each packet about 0.1 ms
--   grab snap 30 Hz   the motor's E+Space under a bough in a packet of two frames: no teleport (MEDIUM 4's other shape)
--   leap chain        the motor's own free leap chain along the river bridge's parapet through loss bursts: clean, the meter
--                     no lower than the base's (the honest reference beside MEDIUM 1)
--   onto a high rail  a gap from the ground onto a bough higher than a grab from the ground reaches pays a leap; one within
--                     a grab does not (LOW c)
--   pounce off a rail the motor's pounce off a bough is no rail leap's free flight; its leap is (LOW d)
-- About 15 s: `lune run tests/run.luau validator_r15`.
local process = require("@lune/process")
local SquirrelMotor = require("@shared/Movement/SquirrelMotor")
local ValidatorWorld = require("@server/Movement/ValidatorWorld")
local MoveValidator = require("@server/Movement/MoveValidator")
local Motion = require("@shared/Routes/Motion")
local TestWorld = require("@tests/cheat/TestWorld")

type State = SquirrelMotor.State

local P = SquirrelMotor.params
local E = SquirrelMotor.envelopeParams

return function(t)
	-- (flat ground at y 0, no walls: the TestWorld's own routes, the town's)
	local function flat(): (any, any)
		local tw = TestWorld.build({ boxes = {} })
		local function wall(): boolean
			return false
		end
		local function down(_ox: number, oy: number, _oz: number, _dx: number, dy: number, _dz: number): boolean
			return oy >= 0 and math.min(oy, oy + dy) <= 0
		end
		return tw, ValidatorWorld.build(tw, { wall = wall, down = down })
	end

	local function feeder(v: any): (State) -> any
		local seq = 0
		return function(s: State): any
			seq += 1
			return v:accept("a", { seq = seq, snapshot = SquirrelMotor.serialize(s) }, s.clock + 1)
		end
	end

	t.test("grab cost: the worst crafted launch packets at the densest rails stay within the search's work", function()
		local tw, vworld = flat()
		local index = vworld.index :: any
		local cs = index.cellSize
		-- (the cell whose 7 x 7 x 7 neighbourhood holds the most samples, as validator_r14rv's case finds it)
		local count: { [number]: number } = {}
		local key: { [number]: { number } } = {}
		for _, r in tw.registry:all() do
			for _, p in tw.registry:samples(r) do
				local k = (math.floor(p.x / cs) + 512)
					+ (math.floor(p.y / cs) + 512) * 1024
					+ (math.floor(p.z / cs) + 512) * 1048576
				count[k] = (count[k] or 0) + 1
				key[k] = key[k] or { p.x, p.y, p.z }
			end
		end
		local cells = {}
		for k, n in count do
			table.insert(cells, { n = n, at = key[k] })
		end
		table.sort(cells, function(a, b)
			return a.n > b.n
		end)
		local best, at = -1, nil
		for i = 1, math.min(40, #cells) do
			local c = cells[i].at
			local m = 0
			index:forEachNear(c[1], c[2], c[3], 3, function(): boolean?
				m += 1
				return nil
			end)
			if m > best then
				best, at = m, c
			end
		end
		assert(at, "a dense neighbourhood")
		local hit = index:nearest(at[1], at[2], at[3], 20)
		-- (the search's own index work: the cells it walks, SpatialIndex.cell)
		local walked = 0
		local cel = index.cell
		index.cell = function(self: any, ix: number, iy: number, iz: number): any
			local c = cel(self, ix, iy, iz)
			if c then
				walked += c.n
			end
			return c
		end
		local worstWalk, worstMs, shapes = 0, 0, 0
		local worstAt = ""
		for _, dt in { 0.05, 0.1, E.grabSimDt } do
			for _, pvy in { -2, -100, 10 } do
				for _, pvx in { 0, 40 } do
					for _, ny in { 2, 6, 16 } do
						local prev = SquirrelMotor.new(hit.x + 2, hit.y, hit.z + 2)
						prev.grounded, prev.vy, prev.vx, prev.clock = false, pvy, pvx, 10
						local nxt = SquirrelMotor.new(hit.x + 5, hit.y + ny, hit.z + 2)
						nxt.grounded, nxt.vy, nxt.vx, nxt.clock = false, 20, 30, 10 + dt
						walked = 0
						SquirrelMotor.envelope(prev, nxt, dt, vworld, false, nil)
						local w = walked
						local reps = 100
						local t0 = os.clock()
						for _ = 1, reps do
							SquirrelMotor.envelope(prev, nxt, dt, vworld, false, nil)
						end
						local ms = (os.clock() - t0) / reps * 1000
						shapes += 1
						if w > worstWalk then
							worstWalk = w
						end
						if ms > worstMs then
							worstMs, worstAt = ms, `{dt} s, prev vy {pvy} vx {pvx}, next {ny} st up`
						end
					end
				end
			end
		end
		index.cell = cel
		print(
			`      densest neighbourhood {best} samples: {shapes} packet shapes, the most cell entries walked {worstWalk} (work {E.grabWork}), the dearest envelope {string.format(
				"%.3f",
				worstMs
			)} ms ({worstAt})`
		)
		t.truthy(worstWalk <= E.grabWork, "the search walks no more cells than its work allows")
		-- (about 0.1 ms on an idle machine; the bound leaves room for a loaded one)
		t.truthy(worstMs <= 0.4, `the dearest packet {worstMs} ms`)
	end)

	t.test("grab snap 30 Hz: the motor's E+Space under a rail in a packet of two frames is no teleport", function()
		local tw, vworld = flat()
		-- (a rail top 4 to 8 st up that a leap off the ground rises past: a cedar fence's, near the town's middle)
		local found: any = nil
		for _, r in tw.registry:all() do
			if r.kind ~= "trunk" and r.enclosure == nil and r.length > 10 then
				local p = tw.registry:pointAt(r, 0.5)
				if p.y > 4 and p.y < 8 and (found == nil or math.abs(p.x) + math.abs(p.z) < found.d) then
					found = { r = r, p = p, d = math.abs(p.x) + math.abs(p.z) }
				end
			end
		end
		assert(found, "a low rail")
		local b = found.p
		local tried, clean = 0, 0
		for _, aside in { 2, 4, 6, 7.5 } do
			local v = MoveValidator.new(vworld)
			local feed = feeder(v)
			-- (standing `aside` from the bough's point, then a leap: packets every two frames, 30 a second)
			local s = SquirrelMotor.new(b.x + aside, tw.groundHeight, b.z)
			s.clock = 0
			feed(s)
			for _ = 1, 10 do
				SquirrelMotor.step(s, SquirrelMotor.idleInput(0), 2 / 60, tw)
				feed(s)
			end
			local i = SquirrelMotor.idleInput(0)
			i.leap = true
			SquirrelMotor.step(s, i, 1 / 60, tw)
			SquirrelMotor.step(s, SquirrelMotor.idleInput(0), 1 / 60, tw)
			feed(s)
			local frames = 0
			while not (s.y >= b.y - 1 and s.vy > 0) and frames < 40 do
				SquirrelMotor.step(s, SquirrelMotor.idleInput(0), 1 / 60, tw)
				frames += 1
				if frames % 2 == 0 then
					feed(s)
				end
			end
			if frames % 2 == 1 then
				SquirrelMotor.step(s, SquirrelMotor.idleInput(0), 1 / 60, tw)
				feed(s)
			end
			local j = SquirrelMotor.idleInput(0)
			j.grab, j.leap = true, true
			local leapt = false
			local _, ev = SquirrelMotor.step(s, j, 1 / 60, tw)
			for _, e in ev do
				leapt = leapt or (e.kind == "leap" and e.fromRouteId ~= nil)
			end
			SquirrelMotor.step(s, SquirrelMotor.idleInput(0), 1 / 60, tw)
			local r = feed(s)
			if leapt then
				tried += 1
				local codes = {}
				for _, x in r.violations do
					table.insert(codes, `{x.code}: {x.detail}`)
				end
				print(`      {aside} st aside: [{table.concat(codes, " | ")}]`)
				if #codes == 0 then
					clean += 1
				end
			end
		end
		t.truthy(tried >= 2, "the motor grabbed the bough")
		t.eq(clean, tried, "each grab-leap clean")
	end)

	t.test("leap chain: the motor's free leap chain along a long rail through loss bursts is clean", function()
		local tw, vworld = flat()
		local id = 1075 -- (the river bridge's stone parapet: 530 st straight)
		local r = tw.registry:get(id) :: any
		assert(r, "the parapet")
		local a, b = tw.registry:pointAt(r, 0.02), tw.registry:pointAt(r, 1)
		local yaw = math.atan2(-(b.x - a.x), -(b.z - a.z))
		local fails = {}
		for _, gaps in { false, true } do
			local s = SquirrelMotor.new(a.x, a.y, a.z)
			s.routeId, s.railT, s.grounded, s.clock, s.yaw = id, 0.02, false, 0, yaw
			local v = MoveValidator.new(vworld)
			local feed = feeder(v)
			feed(s)
			local codes: { [string]: number } = {}
			local x0, z0 = s.x, s.z
			local lastSent = 0
			for f = 1, 600 do
				local i = SquirrelMotor.idleInput(yaw)
				i.fw, i.sprint = 1, true
				i.leap = s.routeId ~= nil
				SquirrelMotor.step(s, i, 1 / 60, tw)
				-- (20 a second; with loss bursts, 0.3 to 1 s of nothing every 2 s)
				local lost = gaps and (f % 120) >= 60 and (f % 120) < 60 + 18 + (f // 120 % 4) * 14
				if s.clock - lastSent >= 0.05 - 1e-6 and not lost then
					lastSent = s.clock
					local res = feed(s)
					for _, x in res.violations do
						codes[x.code] = (codes[x.code] or 0) + 1
						if process.env.DBG then
							print(`        {f}: {x.code} {x.detail}`)
						end
					end
				end
			end
			local d = math.sqrt((s.x - x0) ^ 2 + (s.z - z0) ^ 2)
			local list = {}
			for code, n in codes do
				table.insert(list, `{code}={n}`)
			end
			print(
				`      {if gaps then "loss bursts" else "every packet"}: {string.format("%.1f", d / 10)} st/s for 10 s, meter {string.format(
					"%.2f",
					v._marks.a.stamina
				)}, [{table.concat(list, " ")}]`
			)
			if #list > 0 then
				table.insert(fails, table.concat(list, " "))
			end
		end
		t.eq(#fails, 0, "the motor's own leap chain is clean")
	end)

	t.test(
		"onto a high rail: a gap from the ground to a bough over a grab's reach pays a leap; one in reach does not",
		function()
			local tw, vworld = flat()
			-- (a point of an open rail, no trunk, at that height, nothing of any rail under it lower)
			local function boughAt(lo: number, hi: number): any
				for _, r in tw.registry:all() do
					if r.kind ~= "trunk" and r.enclosure == nil then
						for k = 1, 19 do
							local p = tw.registry:pointAt(r, k / 20)
							local hit = (vworld.index :: any):nearest(p.x, tw.groundHeight, p.z, p.y - 0.5)
							if p.y > lo and p.y < hi and hit == nil then
								return { r = r, p = p, t = k / 20 }
							end
						end
					end
				end
				return nil
			end
			for _, case in { { lo = 4, hi = 7, paid = false }, { lo = 13, hi = 18, paid = true } } do
				local found = boughAt(case.lo, case.hi)
				assert(found, "a bough at that height")
				local v = MoveValidator.new(vworld)
				local feed = feeder(v)
				local p = found.p
				local clock = 0
				for _ = 1, 10 do
					clock += 0.05
					local s = SquirrelMotor.new(p.x + 1, tw.groundHeight, p.z)
					s.clock = clock
					feed(s)
				end
				local m = v._marks.a
				local before = m.stamina
				-- (0.6 s on, on the bough right over where it stood)
				local s = SquirrelMotor.new(p.x, p.y, p.z)
				s.routeId, s.railT, s.grounded, s.clock = found.r.id, found.t, false, clock + 0.6
				feed(s)
				print(
					`      a bough {string.format("%.1f", p.y)} st up (a grab {Motion.C.airGrab}): meter {before} -> {m.stamina}`
				)
				if case.paid then
					-- (leapCost, less the refill of the 0.6 s on the ground before it at most)
					t.truthy(m.stamina <= before - P.leapCost + 0.6 / P.sprintRefill + 1e-6, "a leap onto it: paid")
				else
					t.truthy(m.stamina >= before - 1e-6, "a grab from the ground: nothing paid")
				end
			end
		end
	)

	t.test("pounce off a rail: the motor's pounce off a bough is no rail leap's free flight", function()
		local tw, vworld = flat()
		local found: any = nil
		for _, r in tw.registry:all() do
			if r.kind == "branch" and r.length > 10 then
				found = r
				break
			end
		end
		assert(found, "a bough")
		local results = {}
		for _, how in { "leap", "pounce" } do
			local p = tw.registry:pointAt(found, 0.5)
			local prev = SquirrelMotor.new(p.x, p.y, p.z)
			prev.routeId, prev.railT, prev.grounded, prev.clock = found.id, 0.5, false, 0
			local s = SquirrelMotor.clone(prev)
			local i = SquirrelMotor.idleInput(0)
			if how == "leap" then
				i.leap = true
			else
				i.pounce = true
			end
			SquirrelMotor.step(s, i, 1 / 60, tw)
			for _ = 1, 2 do
				SquirrelMotor.step(s, SquirrelMotor.idleInput(0), 1 / 60, tw)
			end
			assert(s.routeId == nil, `off the bough by a {how}`)
			local _, _, pounce, judged = SquirrelMotor.envelope(prev, s, s.clock - prev.clock, vworld, false, nil)
			print(`      a {how} off the bough: pounce {pounce}, railLaunch {judged.railLaunch}`)
			results[how] = judged.railLaunch == true
		end
		t.truthy(results.leap, "a leap off a rail: the rail leap's flight")
		t.truthy(not results.pounce, "a pounce off a rail: the pounce's own flight")
	end)
end
