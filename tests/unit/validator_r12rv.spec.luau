--!strict
-- Validator round-12 review (scratchpad review_validator_r12.md): failing cases against w0-foundation fe0d405.
--   free flight kept   one honest leap off a low bough (a free launch: its flight steers at v5.4's sprint, 42 st/s, and
--                      drains nothing), then 1 s gaps that each end in a fresh flight whose vertical speed is the clamp
--                      (leapUp x launchTol): the hidden relaunch is dated 0 s old (tau 0), so it is neither charged nor
--                      judged, and the flight's free flag carries on (MoveValidator._stamina, a gap from the air). 42 st/s
--                      for good, anywhere, no rail after the first (10 minutes: 0 snaps, the meter full)
--   relaunch near a rail  the same chain with every hidden relaunch dated (tau > 0), on open ground within the air-gap
--                      rule's rail reach (a rail sample within airGrab + 45 st/s x the gap, 54 st for 1 s, at any height,
--                      of either end; here back and forth over 150 st past the low bough it left, on the ground): each
--                      relaunch is "a chain of free rail leaps", free and free-flying. 42 st/s for good
--   hop, never winded  leaps chained with one ground packet between: each launch's ground part refills a little after its
--                      leapCost (validator round 12), so the meter sits just over its floor and is never "winded"; every
--                      leap carries at full speed (30.5 st/s for good, no gap; at the round-11 base: 56 snaps in 120 s)
--   launch packet's ground  a 0.49 s packet (a loss burst under maxDt) that runs at 45 st/s and leaps at its end: the
--                      launch packet's move is never drained, and its time refills; the leap claims a winded one's speed,
--                      so the meter's winded rule passes it. 28 st/s for good, no gap
-- Honest sustained pace on open ground: 22.5 st/s (the sprint, 33, in bursts). About 5 s:
-- `lune run tests/run.luau validator_r12rv`.
local SquirrelMotor = require("@shared/Movement/SquirrelMotor")
local SquirrelWire = require("@shared/Movement/SquirrelWire")
local ValidatorWorld = require("@server/Movement/ValidatorWorld")
local MoveValidator = require("@server/Movement/MoveValidator")
local MovementService = require("@server/Movement/MovementService")
local TestWorld = require("@tests/cheat/TestWorld")

type State = SquirrelMotor.State
type Send = (State, number) -> ()

local P = SquirrelMotor.params
local E = SquirrelMotor.envelopeParams
local DT = 0.05
local Z = -200
-- (the line the packets run along: the start's z, set by stream)
local zLine = Z

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

	-- a crafted client through MovementService (enforcing). `onRail`: it starts on the lowest bough near (0, Z) (route,
	-- t, point); else on the ground at (0, 0, Z). `cycle(send, x)` sends packets and returns the distance covered so
	-- far. Returns the snaps' reasons, the seconds played and the studs covered
	local function stream(
		seconds: number,
		onRail: boolean,
		cycle: (send: Send, start: { x: number, y: number }) -> number
	): ({ string }, number, number)
		local vworld = flat()
		local snaps: { string } = {}
		local at = { x = 0, y = 0, z = Z }
		local railId: number?, railT = nil, 0
		if onRail then
			local best = math.huge
			vworld.index:forEachNear(
				at.x,
				0,
				at.z,
				5,
				function(id: number, tt: number, sx: number, sy: number, sz: number): boolean?
					local d = (sx - at.x) ^ 2 + (sz - at.z) ^ 2
					if d < best and sy < 10 then
						best, railId, railT = d, id, tt
					end
					return nil
				end
			)
			assert(railId, "a bough near the start")
			local pt = vworld.registry:pointAt(vworld.registry:get(railId :: number), railT)
			at.x, at.y, at.z = pt.x, pt.y, pt.z
		end
		zLine = at.z
		local ms = MovementService.new({
			validator = MoveValidator.new(vworld),
			enforce = true,
			poseOf = function(_a: any): (number, number, number)
				return at.x, at.y, at.z
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
			local s = SquirrelMotor.new(at.x, at.y, at.z)
			if railId then
				s.routeId, s.railT, s.grounded = railId, railT, false
			end
			send(s, DT)
		end
		local start, covered = now, 0
		while now - start < seconds do
			covered = cycle(send, { x = at.x, y = at.y })
		end
		return snaps, now - start, covered
	end

	-- a flight from (x, y) at vy, `secs` of it seen at `v` st/s along x (dir), then a gap of `gap` s at `v` that ends
	-- in a fresh flight at height y0 with vertical speed `vy0`. Returns the new x
	local function flightThenGap(
		send: Send,
		x: number,
		dir: number,
		y: number,
		vy: number,
		v: number,
		secs: number,
		gap: number,
		y0: number,
		vy0: number
	): number
		for _ = 1, math.floor(secs / DT + 0.5) do
			vy -= P.gravity * DT
			y += vy * DT
			x += dir * v * DT
			local s = SquirrelMotor.new(x, y, zLine)
			s.grounded, s.vx, s.vy = false, dir * v, vy
			send(s, DT)
		end
		x += dir * v * gap
		local s = SquirrelMotor.new(x, y0, zLine)
		s.grounded, s.vx, s.vy = false, dir * v, vy0
		send(s, gap)
		return x
	end

	-- a leap off the bough the stream starts on (the motor's railLeap: free), then flights and gaps at 42 st/s: 0.8 s
	-- of each flight seen, 1 s hidden (5.6 gaps in 10 s, under gapMax 6). `near`: back and forth past the start (turning
	-- once more than 30 st past it), each relaunch dated (vy under the clamp); else on along x, each relaunch at the
	-- clamp (tau 0)
	local function freeChain(near: boolean): ({ string }, number, number)
		local V = 42
		local clampVy = P.leapUp * E.launchTol
		local vy0 = if near then clampVy - 0.1 else clampVy + 1
		local first = true
		local x, dir, travelled = 0, 1, 0
		return stream(120, true, function(send: Send, start: { x: number, y: number }): number
			if first then
				first = false
				x = start.x + P.leapForward * DT
				local y = start.y + P.leapUp * DT - 0.5 * P.gravity * DT * DT
				local vy = P.leapUp - P.gravity * DT
				local s = SquirrelMotor.new(x, y, zLine)
				s.grounded, s.vx, s.vy = false, P.leapForward, vy
				send(s, DT)
				x = flightThenGap(send, x, dir, y, vy, V, 0.8, 1, 0.5, vy0)
				travelled = math.abs(x - start.x)
				return travelled
			end
			if near and (x - start.x) * dir > 30 then
				dir = -dir
			end
			x = flightThenGap(send, x, dir, 0.5, clampVy, V, 0.8, 1, 0.5, vy0)
			travelled += V * 1.8
			return travelled
		end)
	end

	t.test(
		"free flight kept: a leap off a bough, then 1 s gaps ending in a fresh flight at the clamp, 42 st/s",
		function()
			local snaps, secs, covered = freeChain(false)
			print(
				`      {string.format("%.1f", covered / secs)} st/s for {string.format("%.0f", secs)} s: {#snaps} snaps {table.concat(
					snaps,
					", ",
					1,
					math.min(#snaps, 4)
				)}`
			)
			t.truthy(#snaps > 0, "42 st/s for good off one free launch is snapped")
		end
	)

	t.test(
		"relaunch near a rail: the same chain back and forth past the bough, each relaunch dated, 42 st/s",
		function()
			local snaps, secs, covered = freeChain(true)
			print(
				`      {string.format("%.1f", covered / secs)} st/s for {string.format("%.0f", secs)} s: {#snaps} snaps {table.concat(
					snaps,
					", ",
					1,
					math.min(#snaps, 4)
				)}`
			)
			t.truthy(#snaps > 0, "free relaunches from open ground tens of studs from any rail are snapped")
		end
	)

	-- a walk of `walkS` s, a launch packet of `launchS` s that runs at `v` and leaps at its end claiming `claim` st/s,
	-- then the flight at the walk-steered bound from the claim (the server's own model, x 1.019) to the ground
	local function hopCycle(send: Send, x: number, walkS: number, launchS: number, v: number, claim: number): number
		for _ = 1, math.max(1, math.floor(walkS / DT + 0.5)) do
			x += P.walk * 1.079 * DT
			local s = SquirrelMotor.new(x, 0, zLine)
			s.vx = P.walk
			send(s, DT)
		end
		local tau = 0.02
		x += v * launchS
		local y, vy = P.leapUp * tau - 0.5 * P.gravity * tau * tau, P.leapUp - P.gravity * tau
		local s0 = SquirrelMotor.new(x, y, zLine)
		s0.grounded, s0.vx, s0.vy = false, claim, vy
		send(s0, launchS)
		local u, sp = claim, P.walk
		while true do
			vy -= P.gravity * DT
			y += vy * DT
			local d
			d, u, sp = SquirrelMotor.speedBound(u, sp, P.walk, false, DT)
			x += d * 1.019
			if y <= 0 then
				local s = SquirrelMotor.new(x, 0, zLine)
				s.vx = P.walk
				send(s, DT)
				return x
			end
			local s = SquirrelMotor.new(x, y, zLine)
			s.grounded, s.vx, s.vy = false, u, vy
			send(s, DT)
		end
	end

	t.test("hop, never winded: leaps at full speed with one ground packet between, no gap, 30 st/s", function()
		local x = 0
		local snaps, secs = stream(120, false, function(send: Send, _start): number
			x = hopCycle(send, x, DT, DT, P.leapForward * E.launchTol, P.leapForward * E.launchTol)
			return x
		end)
		print(
			`      {string.format("%.1f", x / secs)} st/s for {string.format("%.0f", secs)} s: {#snaps} snaps {table.concat(
				snaps,
				", ",
				1,
				math.min(#snaps, 4)
			)}`
		)
		t.truthy(#snaps > 0, "an endless full-speed hop is snapped (the meter winds)")
	end)

	t.test(
		"launch packet's ground: 0.49 s launch packets at 45 st/s, a winded leap's claim, no gap, 28 st/s",
		function()
			local x = 0
			local snaps, secs = stream(120, false, function(send: Send, _start): number
				x = hopCycle(send, x, DT, 0.49, P.leapForward * E.launchTol, P.leapForwardWinded)
				return x
			end)
			print(
				`      {string.format("%.1f", x / secs)} st/s for {string.format("%.0f", secs)} s: {#snaps} snaps {table.concat(
					snaps,
					", ",
					1,
					math.min(#snaps, 4)
				)}`
			)
			t.truthy(#snaps > 0, "a launch packet's run is judged as a ground move")
		end
	)
end
