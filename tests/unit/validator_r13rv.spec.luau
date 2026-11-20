--!strict
-- Validator round-13 review (scratchpad review_validator_r13.md): failing cases against w0-foundation 0067ec3.
--   judged relaunch    a relaunch in the air inside an ordinary (judged) packet beside a bough: the envelope's hidden rail
--                      visit (railWithinReach and railHigh: a rail sample within airGrab + 38 st/s x dt of `next` alone,
--                      at a height a leap off it explains) sets judged.railLaunch, so every such packet starts a fresh free
--                      flight (v5.4's sprint steering, nothing drained). 0.4 s packets, a relaunch and a plain arc in turn,
--                      back and forth within 12 st of the bough at 1.5 to 3.5 st over the ground: 42 st/s for good, no gap,
--                      no violation of any kind, the meter full
--   air gaps by a bough  gaps of 1.19 s from the air (a step off a 0 st edge) ending on the ground, back and forth beside a
--                      bough: both ends within the gap's rail reach (airGrab + 45 st/s x the gap, 62 st, at any height), so
--                      the gap's rest is credited as a free rail leap (d2), a second leap's carry on top (byLeap, leapCost)
--                      and its time refilled as ground time. 48 st/s in each gap, 39 st/s for good, the meter full
--   ground-rail gaps   gaps of 1.19 s between the tip of a bough and open ground 56 st from it, in turn: a gap with an end on
--                      a rail drains nothing and refills its whole time (MoveValidator._stamina's rail branch), so 47 st/s
--                      over open ground in every gap; 33 st/s for good, the meter full
--   past the apex      one gap from the ground that ends in the air past its hidden leap's apex (vertical speed 0, 7 st
--                      over open ground, 45 st/s across): a "fall off an edge" for the meter, so the leap is never charged
--                      and the speed kept is the launch cap's (25.4 st/s for good: LOW)
-- Honest sustained pace on open ground: 22.5 st/s (the sprint, 33, in bursts). About 5 s:
-- `lune run tests/run.luau validator_r13rv`.
local SquirrelMotor = require("@shared/Movement/SquirrelMotor")
local SquirrelWire = require("@shared/Movement/SquirrelWire")
local ValidatorWorld = require("@server/Movement/ValidatorWorld")
local MoveValidator = require("@server/Movement/MoveValidator")
local MovementService = require("@server/Movement/MovementService")
local TestWorld = require("@tests/cheat/TestWorld")

type State = SquirrelMotor.State
type Send = (State, number) -> ()

local P = SquirrelMotor.params
local DT = 0.05

return function(t)
	-- (open, flat ground at y 0 everywhere, no walls; v5.4's routes stand where the generated chunks put them)
	local function flat(): any
		local function wall(): boolean
			return false
		end
		local function down(_ox: number, oy: number, _oz: number, _dx: number, dy: number, _dz: number): boolean
			return oy >= 0 and math.min(oy, oy + dy) <= 0
		end
		return ValidatorWorld.build(TestWorld.build({}), { wall = wall, down = down })
	end

	-- the low bough near (0, -200) the round-12 cases start on: (route, t, its point)
	local function bough(vworld: any): (number, number, any)
		local best, railId, railT = math.huge, nil, 0
		vworld.index:forEachNear(
			0,
			0,
			-200,
			5,
			function(id: number, tt: number, sx: number, sy: number, sz: number): boolean?
				local d = sx * sx + (sz + 200) ^ 2
				if d < best and sy < 10 then
					best, railId, railT = d, id, tt
				end
				return nil
			end
		)
		assert(railId, "a bough near the start")
		local pt = vworld.registry:pointAt(vworld.registry:get(railId :: number), railT)
		return railId :: number, railT, pt
	end

	-- a crafted client through MovementService (enforcing), standing on the ground at (x0, 0, z0) for half a second;
	-- `cycle(send)` sends packets and returns the distance covered so far. Returns the snaps' reasons, the seconds played,
	-- the studs covered and the validator
	local function stream(
		vworld: any,
		x0: number,
		z0: number,
		seconds: number,
		cycle: (send: Send) -> number
	): ({ string }, number, number, any)
		local snaps: { string } = {}
		local validator = MoveValidator.new(vworld)
		local ms = MovementService.new({
			validator = validator,
			enforce = true,
			poseOf = function(_a: any): (number, number, number)
				return x0, 0, z0
			end,
			engine = {
				correct = function(_id: any, msg: any)
					if msg.snap then
						table.insert(snaps, msg.why)
					end
				end,
				pin = function(): boolean
					return true
				end,
				hold = function() end,
			},
		})
		ms:onHandoff({ id = "a", species = "squirrel" }, nil, "possess")
		local seq, now = 0, 100
		local function send(st: State, dt: number)
			seq += 1
			now += dt
			st.clock = now - 90
			local _, e, dec =
				SquirrelWire.decode(SquirrelWire.encode(seq, ms:epochOf("a"), SquirrelMotor.serialize(st)))
			ms:packet("a", "squirrel", { seq = seq, epoch = e, snapshot = dec }, now)
			ms:watch("a", st.x, st.y, st.z, now)
		end
		for _ = 1, 10 do
			send(SquirrelMotor.new(x0, 0, z0), DT)
		end
		local start, covered = now, 0
		while now - start < seconds do
			covered = cycle(send)
		end
		return snaps, now - start, covered, validator
	end

	local function report(snaps: { string }, secs: number, covered: number)
		print(
			`      {string.format("%.1f", covered / secs)} st/s for {string.format("%.0f", secs)} s: {#snaps} snaps {table.concat(
				snaps,
				", ",
				1,
				math.min(#snaps, 4)
			)}`
		)
	end

	t.test("judged relaunch: 0.4 s packets relaunching in the air beside a bough, no gap, 42 st/s", function()
		local vworld = flat()
		local _, _, pt = bough(vworld)
		local V, D, V1, R = 42, 0.4, 10, 12
		local x, z, dir, travelled, first = pt.x, pt.z, 1, 0, true
		local y1 = 1.5
		local snaps, secs, covered = stream(vworld, pt.x, pt.z, 120, function(send: Send): number
			if (x - pt.x) * dir > R then
				dir = -dir
			end
			-- a relaunch (the first one off the ground: a charged leap), ending rising at V1
			local dt = if first then DT else D
			first = false
			x += dir * V * dt
			travelled += V * dt
			local s = SquirrelMotor.new(x, y1, z)
			s.grounded, s.vx, s.vy = false, dir * V, V1
			send(s, dt)
			-- then a plain arc (claiming under the ground cap; the envelope lets it move at the speed kept x speedTol)
			local v2 = V1 - P.gravity * D
			x += dir * V * D
			travelled += V * D
			local s2 = SquirrelMotor.new(x, y1 + (V1 + v2) / 2 * D, z)
			s2.grounded, s2.vx, s2.vy = false, dir * 37.9, v2
			send(s2, D)
			return travelled
		end)
		report(snaps, secs, covered)
		t.truthy(#snaps > 0, "a free flight started in every packet by a rail only near `next` is snapped")
	end)

	t.test("air gaps by a bough: 1.19 s gaps from the air ending on the ground, 48 st/s in each, 39 st/s", function()
		local vworld = flat()
		local _, _, pt = bough(vworld)
		local GAP, GV, R = 1.19, 48, 40
		local x, z, dir, travelled = pt.x, pt.z, 1, 0
		local snaps, secs, covered = stream(vworld, pt.x, pt.z, 120, function(send: Send): number
			for _ = 1, 10 do
				x += dir * P.walk * 1.079 * DT
				travelled += P.walk * 1.079 * DT
				local s = SquirrelMotor.new(x, 0, z)
				s.vx = dir * P.walk
				send(s, DT)
			end
			-- off a 0 st edge: in the air at the floor's height, falling
			x += dir * P.walk * DT
			travelled += P.walk * DT
			local e = SquirrelMotor.new(x, 0.1, z)
			e.grounded, e.vx, e.vy = false, dir * P.walk, -3.5
			send(e, DT)
			if (x - pt.x) * dir > R then
				dir = -dir
			end
			x += dir * GV * GAP
			travelled += GV * GAP
			local g = SquirrelMotor.new(x, 0, z)
			g.vx = dir * P.walk
			send(g, GAP)
			return travelled
		end)
		report(snaps, secs, covered)
		t.truthy(#snaps > 0, "gaps at 48 st/s over open ground beside a bough are snapped")
	end)

	t.test("ground-rail gaps: 1.19 s gaps between a bough's tip and open ground 56 st from it, 33 st/s", function()
		local vworld = flat()
		local railId, railT, pt = bough(vworld)
		local GAP, GV = 1.19, 47
		-- (the bough runs along x and ends at pt: a ground end straight out sideways is GV x GAP from every point of it)
		local lat = math.sqrt((GV * GAP) ^ 2 - pt.y ^ 2)
		local side, onRail, travelled = 1, false, 0
		local snaps, secs, covered = stream(vworld, pt.x, pt.z, 120, function(send: Send): number
			if onRail then
				local gz = pt.z + side * lat
				side = -side
				local s = SquirrelMotor.new(pt.x, 0, gz)
				s.vz = side * P.walk
				send(s, GAP)
				for _ = 1, 10 do
					send(SquirrelMotor.new(pt.x, 0, gz), DT)
				end
			else
				local s = SquirrelMotor.new(pt.x, pt.y, pt.z)
				s.routeId, s.railT, s.grounded = railId, railT, false
				send(s, GAP)
				for _ = 1, 10 do
					local s2 = SquirrelMotor.new(pt.x, pt.y, pt.z)
					s2.routeId, s2.railT, s2.grounded = railId, railT, false
					send(s2, DT)
				end
			end
			onRail = not onRail
			travelled += GV * GAP
			return travelled
		end)
		report(snaps, secs, covered)
		t.truthy(#snaps > 0, "56 st of open ground to or from a rail in 1.19 s, every gap, is snapped")
	end)

	t.test(
		"past the apex: a gap from the ground ending in the air with no vertical speed pays its hidden leap",
		function()
			local vworld = flat()
			local x = 600
			local _, _, _, validator = stream(vworld, x, -1000, 0, function(_send: Send): number
				return 0
			end)
			-- (stream played no cycle: drive the validator directly from the same baseline)
			local now = 100.5
			local function send(st: State, dt: number)
				now += dt
				st.clock = now - 90
				validator:accept(
					"a",
					{ seq = math.floor(now * 1000), epoch = 0, snapshot = SquirrelMotor.serialize(st) },
					now
				)
			end
			for _ = 1, 10 do
				x += P.walk * DT
				local s = SquirrelMotor.new(x, 0, -1000)
				s.vx = P.walk
				send(s, DT)
			end
			local before = validator:meterOf("a", now)
			-- the gap: 0.55 s at a walk's distance, ending 7 st up at its apex, 45 st/s across
			x += P.walk * 0.55
			local g = SquirrelMotor.new(x, 7, -1000)
			g.grounded, g.vx, g.vy = false, 45, 0
			send(g, 0.55)
			local after = validator:meterOf("a", now)
			local actor = (validator :: any)._actors.a
			print(
				`      meter {string.format("%.3f", before)} -> {string.format("%.3f", after)}, speed kept {actor.marks.speedU}`
			)
			t.truthy(
				after <= before - P.leapCost + 1e-3,
				"a body 7 st over open ground after a gap from the ground leapt in it: leapCost is paid"
			)
		end
	)
end
