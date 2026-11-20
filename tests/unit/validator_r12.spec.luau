--!strict
-- Validator round 12 (the round-11 review, scratchpad review_validator_r11.md; its failing cases are validator_r11rv): the
-- server's sprint meter and air bound step the motor's own speed model (SquirrelMotor.speedBound: speedSmooth,
-- accelGround / accelAir, dragGround / dragAir, a pounce's window, railLeap's v5.4 speeds), MoveValidator._stamina.
--   the motor's step   the motor's own frames (random keys, sprint and focus, leaps and pounces, frames of 1/144 to 0.08
--                      s) never cover more than speedBound from the true speed, moveSpeed and window, by C.STAMINA_STEP
--   honest, 5 min      W held with the sprint key (the meter running out and back), with hops, hopping whenever the meter
--                      allows with the sprint in the air, and the duel's chaser (sprint held, zig-zags, pounces as often
--                      as the duel allows with feints' pauses), each on a clean link and on 150 ms, 300 ms jitter, 8 %
--                      loss: 0 snaps
--   instant sprint     a crafted stream that sprints at once from a walk for a few packets, slows by the motor's own
--                      walk-steered step, walks a packet: snapped (the slowing this round lets through is earned by a
--                      sprint the motor ramps up to: one claimed at once pays for what it skipped)
--   relaunch in a gap  a walk of 1.1 s (it refills the leap), a leap, its packets withheld from 0.1 s in to a moment into a
--                      second leap's flight (a landing and a leap hidden), that flight seen to the ground, on open ground
--                      with no rail within reach: snapped (the round-11 meter charged the leap seen and took the hidden one
--                      as free: 27.4 st/s for good, 0 snaps)
-- About 8 s: `lune run tests/run.luau validator_r12`.
local Tunables = require("@shared/Config/Tunables")
local SquirrelMotor = require("@shared/Movement/SquirrelMotor")
local SquirrelWire = require("@shared/Movement/SquirrelWire")
local ValidatorWorld = require("@server/Movement/ValidatorWorld")
local MoveValidator = require("@server/Movement/MoveValidator")
local MovementService = require("@server/Movement/MovementService")
local Squirrel = require("@client/Controllers/Squirrel")
local LiveRig = require("@tests/lib/LiveRig")
local Rng = require("@tests/cheat/Rng")
local TestWorld = require("@tests/cheat/TestWorld")

type State = SquirrelMotor.State

local P = SquirrelMotor.params

return function(t)
	t.test(
		"the motor's step: its own frames (random keys, frames of 1/144 to 0.08 s) never cover more than speedBound from its true speed, by C.STAMINA_STEP",
		function()
			local world = TestWorld.build({})
			world.clamp = { minX = -1e7, maxX = 1e7, minZ = -1e7, maxZ = 1e7 }
			local V54 = SquirrelMotor.V54
			local worst, windows = 0, 0
			for seed = 1, 12 do
				local rng = Rng.new(seed)
				local s = SquirrelMotor.new(0, world.groundHeight, 0)
				local inp = SquirrelMotor.idleInput(0)
				local frames = {}
				local nextKey = 0
				local dts = { 1 / 30, 1 / 45, 1 / 60, 1 / 90, 1 / 144, 0.08 }
				local dt = 1 / 60
				for _ = 1, 60 * 40 do
					if s.clock >= nextKey then
						nextKey = s.clock + 0.05 + rng.next() * 0.4
						inp.fw = if rng.next() < 0.8 then 1 else 0
						inp.side = math.floor(rng.next() * 3) - 1
						inp.sprint = rng.next() < 0.6
						inp.cameraYaw = rng.next() * math.pi * 2
						inp.focus = rng.next() < 0.05
						dt = dts[math.floor(rng.next() * #dts) + 1]
					end
					inp.leap = rng.next() < 0.03
					inp.pounce = rng.next() < 0.01
					local f = {
						clock = s.clock,
						x = s.x,
						z = s.z,
						u = math.sqrt(s.vx * s.vx + s.vz * s.vz),
						ms = s.moveSpeed,
						grounded = s.grounded,
						hold = s.attackWindow,
						railLeap = s.railLeap,
						key = inp.sprint,
						sprint = inp.sprint and not s.winded,
						onRail = s.routeId ~= nil,
						event = false,
					}
					local _, ev = SquirrelMotor.step(s, inp, dt, world)
					for _, e in ev do
						f.event = f.event or e.kind ~= "winded"
					end
					table.insert(frames, f)
				end
				-- every window of about 0.05, 0.1 and 0.3 s on the ground or in the air throughout, no launch, landing or
				-- rail in it, the sprint key unchanged: the goal the sprint when the motor sprinted in it
				for i = 1, #frames - 1 do
					local a = frames[i]
					for _, w in { 0.05, 0.1, 0.3 } do
						local j, ok, sprinted = i, true, false
						while true do
							local f = frames[j]
							if f.event or f.onRail or f.grounded ~= a.grounded or f.key ~= a.key then
								ok = false
								break
							end
							sprinted = sprinted or f.sprint
							if j + 1 > #frames or frames[j + 1].clock - a.clock >= w then
								break
							end
							j += 1
						end
						local b = frames[j + 1]
						if ok and b and b.grounded == a.grounded and not b.onRail then
							local d = math.sqrt((b.x - a.x) ^ 2 + (b.z - a.z) ^ 2)
							local bound = SquirrelMotor.speedBound(
								a.u,
								a.ms,
								if sprinted then P.sprint else P.walk,
								a.grounded,
								b.clock - a.clock,
								a.hold,
								if a.railLeap and not a.grounded then (if a.key then V54.sprint else V54.walk) else nil
							)
							windows += 1
							if d > 0.05 then
								worst = math.max(worst, d / bound)
							end
						end
					end
				end
			end
			print(string.format("      %d windows: the motor covers at most %.4f x speedBound", windows, worst))
			t.truthy(windows > 10000, "windows judged")
			t.truthy(
				worst <= MoveValidator.C.STAMINA_STEP,
				"the motor never covers more than the bound, by STAMINA_STEP"
			)
		end
	)

	-- honest, 5 minutes on open ground, the heading turned back every 12 s (the run stays on the open ground)
	local town = LiveRig.town()
	local links = {
		{ name = "clean", link = { latency = 0.06, jitter = 0.02, loss = 0 } },
		{ name = "150 ms, 300 ms jitter, 8 % loss", link = { latency = 0.15, jitter = 0.3, loss = 0.08 } },
	}
	local windup = Tunables.get("pounce.windup")
	local patterns: { { name: string, keys: (rng: Rng.Rng) -> LiveRig.Keys } } = {
		{
			name = "W and the sprint key held",
			keys = function(_rng: Rng.Rng): LiveRig.Keys
				return function(now: number, _s: State, _e: { SquirrelMotor.Event }): SquirrelMotor.Input
					local inp =
						SquirrelMotor.idleInput(if math.floor(now / 12) % 2 == 0 then -math.pi / 2 else math.pi / 2)
					inp.fw, inp.sprint = 1, true
					return inp
				end
			end,
		},
		{
			name = "sprint held, a hop every 1.5 s",
			keys = function(_rng: Rng.Rng): LiveRig.Keys
				local last = -10
				return function(now: number, s: State, _e: { SquirrelMotor.Event }): SquirrelMotor.Input
					local inp =
						SquirrelMotor.idleInput(if math.floor(now / 12) % 2 == 0 then -math.pi / 2 else math.pi / 2)
					inp.fw, inp.sprint = 1, true
					if s.grounded and now - last > 1.5 then
						inp.leap, last = true, now
					end
					return inp
				end
			end,
		},
		{
			name = "a hop whenever the meter allows, the sprint in the air",
			keys = function(_rng: Rng.Rng): LiveRig.Keys
				return function(now: number, s: State, _e: { SquirrelMotor.Event }): SquirrelMotor.Input
					local inp =
						SquirrelMotor.idleInput(if math.floor(now / 12) % 2 == 0 then -math.pi / 2 else math.pi / 2)
					inp.fw = 1
					inp.sprint = not s.grounded
					inp.leap = s.grounded and s.stamina >= 0.15 and not s.winded
					return inp
				end
			end,
		},
		{
			name = "the duel's chaser",
			keys = function(rng: Rng.Rng): LiveRig.Keys
				local pending: number? = nil
				local weave, weaveAt = 1, 0
				return function(now: number, s: State, _e: { SquirrelMotor.Event }): SquirrelMotor.Input
					local inp =
						SquirrelMotor.idleInput(if math.floor(now / 12) % 2 == 0 then -math.pi / 2 else math.pi / 2)
					if now >= weaveAt then
						weave = -weave
						weaveAt = now + 0.25 + rng.next() * 0.2
					end
					inp.fw, inp.side, inp.sprint = 1, weave * 0.6, true
					local pressed = (now % 3) < 2.2
					local go, pend = Squirrel.windup(pending, now, pressed, windup, s.cooldown <= 0)
					pending = pend
					inp.pounce = go
					return inp
				end
			end,
		},
	}
	for _, pat in patterns do
		t.test(`honest, 5 min on open ground: {pat.name}, clean and lossy: 0 snaps`, function()
			for li, l in links do
				local rig = LiveRig.new({
					world = town.noWalls,
					vworld = town.vworld,
					link = l.link :: any,
					seed = 40 + li,
				})
				local s0 = town.openStart()
				rig:possess(s0, pat.keys(Rng.new(7 + li)))
				rig:run(300)
				local r = rig:result()
				local pace = math.sqrt((r.client.x - s0.x) ^ 2 + (r.client.z - s0.z) ^ 2)
				print(`      {LiveRig.describe(l.name, r)}; {string.format("%.0f", pace)} st from the start`)
				for i, v in r.violations do
					if i <= 4 then
						print(`        {v}`)
					end
				end
				t.eq(r.snaps, 0, `snaps on the {l.name} link`)
			end
		end)
	end

	-- crafted streams through MovementService (enforcing) on flat, open ground, from x 600 on (no rail within reach)
	local function flat(): any
		local function wall(): boolean
			return false
		end
		local function down(_ox: number, oy: number, _oz: number, _dx: number, dy: number, _dz: number): boolean
			return oy >= 0 and math.min(oy, oy + dy) <= 0
		end
		return ValidatorWorld.build(TestWorld.build({}), { wall = wall, down = down })
	end
	local function stream(
		seconds: number,
		cycle: (send: (State, number) -> (), x: number) -> number
	): ({ string }, number)
		local snaps: { string } = {}
		local at = { x = 600, y = 0, z = -200 }
		local ms = MovementService.new({
			validator = MoveValidator.new(flat()),
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
			send(SquirrelMotor.new(at.x, 0, at.z), 0.05)
		end
		local x, start = at.x, now
		while now - start < seconds do
			x = cycle(send, x)
		end
		return snaps, (x - at.x) / (now - start)
	end
	local DT = 0.05
	local function ground(send: (State, number) -> (), x: number, v: number): number
		x += v * DT
		local s = SquirrelMotor.new(x, 0, -200)
		s.vx = v
		send(s, DT)
		return x
	end

	t.test(
		"instant sprint: four packets at the sprint at once from a walk, the walk-steered slowing the server allows, a walk packet, for 120 s: snapped",
		function()
			local snaps, pace = stream(120, function(send: (State, number) -> (), x: number): number
				local u, s = P.walk, P.walk
				for _ = 1, 4 do
					x = ground(send, x, P.sprint)
					local _
					_, u, s = SquirrelMotor.speedBound(u, s, P.sprint, true, DT)
				end
				for _ = 1, 6 do
					local d
					d, u, s = SquirrelMotor.speedBound(u, s, P.walk, true, DT)
					x = ground(send, x, math.max(d * 1.019, P.walk * 1.079 * DT) / DT)
				end
				return ground(send, x, P.walk * 1.079)
			end)
			print(
				`      {string.format("%.1f", pace)} st/s, {#snaps} snaps [{table.concat(
					snaps,
					", ",
					1,
					math.min(#snaps, 4)
				)}]`
			)
			t.truthy(#snaps > 0, "a sprint claimed at once from a walk, again and again, is snapped")
		end
	)

	t.test(
		"relaunch in a gap: a walk of 1.1 s, a leap, its packets withheld from 0.1 s in to 0.1 s into a second leap's flight, that flight seen to the ground, 120 s: snapped",
		function()
			local snaps, pace = stream(120, function(send: (State, number) -> (), x: number): number
				for _ = 1, 22 do
					x = ground(send, x, P.walk)
				end
				-- (a flight at tt seconds in: the leap's arc; across at the leap's speed hidden, the walk-steered step seen)
				local function at(tt: number, vx: number): State
					local s = SquirrelMotor.new(x, P.leapUp * tt - 0.5 * P.gravity * tt * tt, -200)
					s.grounded, s.vx, s.vy = false, vx, P.leapUp - P.gravity * tt
					return s
				end
				for k = 1, 2 do
					x += P.leapForward * DT
					send(at(k * DT, P.leapForward), DT)
				end
				local flight = 2 * P.leapUp / P.gravity
				x += P.leapForward * flight
				send(at(2 * DT, P.leapForward), flight)
				-- (the motor's own air steering toward the walk, at accelAir)
				local u = P.leapForward
				local tt = 2 * DT
				while tt + DT < flight do
					tt += DT
					u = P.walk + (u - P.walk) * math.exp(-P.accelAir * DT)
					x += u * DT
					send(at(tt, u), DT)
				end
				x += P.walk * DT
				local s1 = SquirrelMotor.new(x, 0, -200)
				s1.vx = P.walk
				send(s1, DT)
				return x
			end)
			print(
				`      {string.format("%.1f", pace)} st/s, {#snaps} snaps [{table.concat(
					snaps,
					", ",
					1,
					math.min(#snaps, 4)
				)}]`
			)
			t.truthy(#snaps > 0, "leaps hidden in gaps from the air, back to back, are snapped")
		end
	)
end
