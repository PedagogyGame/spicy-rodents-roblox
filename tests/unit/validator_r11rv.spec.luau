--!strict
-- Validator round-11 review (scratchpad review_validator_r11.md): failing cases against w0-foundation d8a6a83.
--   gaps from the air  a client that withholds its packets from a moment after each leap (charged leapCost) until it is
--                      on the ground again: a gap that starts in the air is neither drained nor charged by its distance
--                      (MoveValidator._stamina), and the governor allows the fastest pace (47.4 st/s) across it. With
--                      1.19 s gaps and a 1.1 s walk between (which refills the leap): 33.2 st/s for good (10 minutes,
--                      the meter steady at 0.88); with 3 s gaps: 38.9 st/s. Honest, sustained: 20 to 22 st/s
--   flight at full speed  a crafted stream that keeps a leap's launch speed (41.25 st/s, under the envelope's ground cap)
--                      for its whole flight, then walks 1.1 s to refill its leapCost: 28 st/s for good, no gap, no loss
--                      (the motor's flight slows by dragAir and steers toward the walk; the envelope never asks)
--   sprint held        honest: W and the sprint key held on open ground, a clean link: the server's meter loses about
--                      0.05 to the motor's every sprint-winded-recover cycle (4.6 s) and never makes it up, so after about
--                      45 s every cycle's sprint is "stamina" (3 snaps in 90 s, then held)
-- About 5 s: `lune run tests/run.luau validator_r11rv`.
local SquirrelMotor = require("@shared/Movement/SquirrelMotor")
local SquirrelWire = require("@shared/Movement/SquirrelWire")
local ValidatorWorld = require("@server/Movement/ValidatorWorld")
local MoveValidator = require("@server/Movement/MoveValidator")
local MovementService = require("@server/Movement/MovementService")
local LiveRig = require("@tests/lib/LiveRig")
local TestWorld = require("@tests/cheat/TestWorld")

type State = SquirrelMotor.State

return function(t)
	-- (open, flat ground at y 0 everywhere, no walls)
	local function flat(): any
		local function wall(): boolean
			return false
		end
		local function down(_ox: number, oy: number, _oz: number, _dx: number, dy: number, _dz: number): boolean
			return oy >= 0 and math.min(oy, oy + dy) <= 0
		end
		return ValidatorWorld.build(TestWorld.build({}), { wall = wall, down = down })
	end

	-- a crafted client on flat ground through MovementService (enforcing): `play(send, P)` sends its packets; the root is
	-- written with each packet. Returns the snaps' reasons, the seconds played and the studs covered along x
	local function stream(
		seconds: number,
		cycle: (send: (State, number) -> (), x: number) -> number
	): ({ string }, number, number)
		local vworld = flat()
		local snaps: { string } = {}
		local at = { x = 0, y = 0, z = -200 }
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
			send(SquirrelMotor.new(at.x, 0, at.z), 0.05)
		end
		local x, start = at.x, now
		while now - start < seconds do
			x = cycle(send, x)
		end
		return snaps, now - start, x - at.x
	end

	local P = SquirrelMotor.params
	-- a walk on the ground at the walk's pace for `secs` (refills the meter), from x
	local function walk(send: (State, number) -> (), x: number, secs: number): number
		for _ = 1, math.max(1, math.floor(secs * 30 + 0.5)) do
			x += P.walk / 30
			local s = SquirrelMotor.new(x, 0, -200)
			s.vx = P.walk
			send(s, 1 / 30)
		end
		return x
	end

	t.test(
		"gaps from the air: a leap, its packets withheld from 0.1 s into it until the ground (1.19 s or 3 s gaps), a 1.1 s walk between: snapped within 120 s",
		function()
			local fastest = MoveValidator.new(flat()):fastest("a")
			local results: { string } = {}
			local unsnapped = 0
			for _, shape in { { gap = 1.19, walk = 1.1 }, { gap = 3, walk = 1.1 } } do
				local snaps, secs, dist = stream(120, function(send: (State, number) -> (), x: number): number
					x = walk(send, x, shape.walk)
					-- the leap (charged): three packets of its arc
					local y, vy = 0, P.leapUp
					for _ = 1, 3 do
						vy -= P.gravity / 30
						y += vy / 30
						x += P.leapForward / 30
						local s = SquirrelMotor.new(x, y, -200)
						s.grounded, s.vx, s.vy = false, P.leapForward, vy
						send(s, 1 / 30)
					end
					-- the gap, from the air, ending on the ground at just under the governor's pace
					x += fastest * 0.98 * shape.gap
					send(SquirrelMotor.new(x, 0, -200), shape.gap)
					return x
				end)
				table.insert(
					results,
					`{shape.gap} s gaps: {string.format("%.1f", dist / secs)} st/s for {string.format("%.0f", secs)} s, {#snaps} snaps [{table.concat(
						snaps,
						", ",
						1,
						math.min(#snaps, 4)
					)}]`
				)
				if #snaps == 0 then
					unsnapped += 1
				end
			end
			for _, r in results do
				print(`      {r}`)
			end
			t.eq(unsnapped, 0, "a sprint hidden in gaps that start in the air is snapped")
		end
	)

	t.test(
		"flight at full speed: every leap's whole flight at its launch speed (no drag), then a walk of 1.1 s, 120 s on a clean link: snapped",
		function()
			local snaps, secs, dist = stream(120, function(send: (State, number) -> (), x: number): number
				x = walk(send, x, 1.1)
				local y, vy = 0, P.leapUp
				while true do
					vy -= P.gravity / 30
					y += vy / 30
					x += P.leapForward / 30
					if y <= 0 then
						local s = SquirrelMotor.new(x, 0, -200)
						s.vx = P.walk
						send(s, 1 / 30)
						return x
					end
					local s = SquirrelMotor.new(x, y, -200)
					s.grounded, s.vx, s.vy = false, P.leapForward, vy
					send(s, 1 / 30)
				end
			end)
			print(
				`      {string.format("%.1f", dist / secs)} st/s for {string.format("%.0f", secs)} s, {#snaps} snaps [{table.concat(
					snaps,
					", ",
					1,
					math.min(#snaps, 4)
				)}]`
			)
			t.truthy(#snaps > 0, "a flight held at its launch speed for good is snapped")
		end
	)

	t.test("sprint held: honest, W and the sprint key held 90 s on open ground, a clean link: 0 snaps", function()
		local town = LiveRig.town()
		local rig = LiveRig.new({
			world = town.noWalls,
			vworld = town.vworld,
			link = { latency = 0.06, jitter = 0.02, loss = 0 },
			seed = 5,
		})
		rig:possess(
			town.openStart(),
			function(_now: number, _s: State, _e: { SquirrelMotor.Event }): SquirrelMotor.Input
				local inp = SquirrelMotor.idleInput(-math.pi / 2)
				inp.fw = 1
				inp.sprint = true
				return inp
			end
		)
		rig:run(90)
		local r = rig:result()
		print(`      {LiveRig.describe("sprint held", r)}`)
		for i, v in r.violations do
			if i <= 3 then
				print(`        {v}`)
			end
		end
		t.eq(r.snaps, 0, "an honest client holding the sprint key is not snapped")
	end)
end
