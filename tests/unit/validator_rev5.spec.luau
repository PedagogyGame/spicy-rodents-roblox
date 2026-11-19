--!strict
-- Review round 5 (adversarial) of the validator round-5 fix merged at w0-foundation 6484a3c: failing cases only.
--   railT     a rail packet's position agrees with its rail parameter only where the envelope judges it (section 1).
--             A packet it does not judge (the first after a silence over maxDt, the first of an epoch at the gate, the
--             very first) is held by hop() on x, y, z alone: its routeId and railT are taken as they come. The next
--             packet is judged by railT alone (section 2 same rail; the transfer and exit sections from the stretch
--             round prev.railT), so it may be anywhere along that rail, or on any rail of the world: 562 studs along a
--             wire, or 1552 studs off to another route, in 0.05 s, 0 violations; on the rig 0 snaps
--   gate      a hand-off's first packet that passes the gate (MovementService) but has a field out of bounds is no
--             baseline (MoveValidator.accept, new this round): the gate is already cleared and the body unpinned, so the
--             snap that follows has no clean packet and no gate to go to and puts the body at sq.lastX/Y/Z: 0, 0, 0
--   touches   off a rail onto a rail (section 3) the grab's reach (airGrab, 8.5 st) counts in every direction, along
--             the rail too; an honest grab lands at the rail's NEAREST point (straight across a trunk, never 8.5 st
--             up it). Off, on, off, on ... a greedy client climbs a trunk at 32 to 121 st/s (the trunk's pace 19.2)
--             and runs a wire at 89 to 197 st/s (the wire 32, a leap along it 45), 0 violations at 2 to 20 packets a
--             second (round 5's own "rail touches" case never grabbed: its search for the grab needs t = 0 to pass)
--   ledge     (LOW) the ledge allowance off a rail grants the launch onto the ledge and the launch off it each over
--             the whole gap (not the time shared, as climbThenLaunch does): at 2 and 4 packets a second about a
--             leap's apex more than an honest leap, land and leap again reaches
--   level     (LOW) a grounded packet at the height it last stood is held only to floorBelow (FLOOR_DEPTH 3.5): from a
--             ledge 3 studs up (a wall top, a car's roof) a body walks on level over open ground, unflagged
local SquirrelMotor = require("@shared/Movement/SquirrelMotor")
local SquirrelWire = require("@shared/Movement/SquirrelWire")
local MoveValidator = require("@server/Movement/MoveValidator")
local MovementService = require("@server/Movement/MovementService")
local ValidatorWorld = require("@server/Movement/ValidatorWorld")
local TestWorld = require("@tests/cheat/TestWorld")
local LiveRig = require("@tests/lib/LiveRig")
local Driver = require("@tests/cheat/Driver")
local Units = require("@shared/Config/Units")

type State = SquirrelMotor.State

local QUIET = { latency = 0.1, jitter = 0.01, loss = 0 }
local P = SquirrelMotor.params
local E = SquirrelMotor.envelopeParams

-- the S3 world with open ground (y 0), `boxes` as solid boxes (their tops floors), and its validator world
local function worldWith(boxes: { TestWorld.Box }): (any, any)
	local world = TestWorld.build({ boxes = boxes })
	local function wall(ox: number, oy: number, oz: number, dx: number, _dy: number, dz: number): boolean
		return TestWorld.segmentCrossesBox(boxes, ox, oz, ox + dx, oz + dz, oy)
	end
	local function down(ox: number, oy: number, oz: number, _dx: number, dy: number, _dz: number): boolean
		local lo = oy + dy
		if lo <= 0 and oy >= 0 then
			return true
		end
		for _, b in boxes do
			if ox > b.minX and ox < b.maxX and oz > b.minZ and oz < b.maxZ and b.top >= lo and b.top <= oy then
				return true
			end
		end
		return false
	end
	return world, ValidatorWorld.build(world, { wall = wall, down = down })
end

local function codesOf(list: { { code: string } }): string
	local out = {}
	for _, v in list do
		table.insert(out, v.code)
	end
	return table.concat(out, ",")
end

local function longestWire(world: any): any
	local best: any = nil
	for _, r in world.registry:all() do
		if r.kind == "wire" and (best == nil or r.length > best.length) then
			best = r
		end
	end
	return best
end

local function onRail(world: any, r: any, tt: number, clock: number): State
	local p = world.registry:pointAt(r, tt)
	local s = SquirrelMotor.new(p.x, p.y, p.z)
	s.routeId, s.railT, s.grounded, s.clock = r.id, tt, false, clock
	return s
end

local function flat(a: any, b: any): number
	return math.sqrt((a.x - b.x) ^ 2 + (a.z - b.z) ^ 2)
end

-- does the validator's envelope and field check pass the move (the greedy adversary's oracle)?
local function clean(v: any, prev: State, next: State, dt: number): boolean
	if #SquirrelMotor.fieldCheck(SquirrelMotor.serialize(next), v.world) > 0 then
		return false
	end
	local found, _, _, judged = SquirrelMotor.envelope(prev, next, dt, v.world, false)
	return #found == 0 and not judged.longWall
end

-- the largest x in [lo, hi] that `ok` passes (nil when lo does not): 20 halvings
local function most(lo: number, hi: number, ok: (x: number) -> boolean): number?
	if not ok(lo) then
		return nil
	end
	if ok(hi) then
		return hi
	end
	for _ = 1, 20 do
		local mid = (lo + hi) / 2
		if ok(mid) then
			lo = mid
		else
			hi = mid
		end
	end
	return lo
end

return function(t)
	-- railT ------------------------------------------------------------------------------------------------------------
	t.test(
		"railT: after a 0.6 s silence a packet claims railT 0.95 where it stands at 0.05; the next is at 0.95",
		function()
			local world, vworld = worldWith({})
			local wire = longestWire(world)
			local start = world.registry:pointAt(wire, 0.05)
			-- the other target: a route of the world far from the wire
			local far: any = nil
			for _, r in world.registry:all() do
				if flat(world.registry:pointAt(r, 0.5), start) > 1500 then
					far = r
					break
				end
			end
			local results = {}
			for _, target in { { r = wire, tt = 0.95 }, { r = far, tt = 0.5 } } do
				local v = MoveValidator.new(vworld)
				local seq, clock = 0, 0
				local function send(s: State): any
					seq += 1
					return v:accept("a", { seq = seq, snapshot = SquirrelMotor.serialize(s) }, clock)
				end
				for i = 0, 20 do
					clock = i * 0.05
					send(onRail(world, wire, 0.05, clock))
				end
				-- silent for 0.6 s (a gap the envelope does not judge: hop() over x, y, z), then the claim, standing
				clock += 0.6
				local s = onRail(world, wire, 0.05, clock)
				s.routeId, s.railT = target.r.id, target.tt
				local r1 = send(s)
				-- then where that rail parameter is, 0.05 s later (section 1: on the rail; section 2: no way along it)
				clock += 0.05
				local r2 = send(onRail(world, target.r, target.tt, clock))
				clock += 0.05
				local r3 = send(onRail(world, target.r, target.tt, clock))
				local d = flat(world.registry:pointAt(target.r, target.tt), start)
				local n = #r1.violations + #r2.violations + #r3.violations
				print(
					`      to route {target.r.id} ({target.r.kind}) t {target.tt}: {string.format("%.0f", d)} st in 0.05 s: [{codesOf(
						r1.violations
					)}|{codesOf(r2.violations)}|{codesOf(r3.violations)}]`
				)
				table.insert(results, { d = d, n = n })
			end
			for _, x in results do
				t.truthy(x.n >= 1, `a {string.format("%.0f", x.d)}-stud jump by a rail parameter is flagged`)
			end
		end
	)

	t.test("railT: the first packet of a hand-off (the gate) claims railT 0.95 where the body is at 0.05", function()
		local world, vworld = worldWith({})
		local wire = longestWire(world)
		local p = world.registry:pointAt(wire, 0.05)
		local corrections = 0
		local ms = MovementService.new({
			validator = MoveValidator.new(vworld),
			enforce = true,
			poseOf = function(_actor: any): (number, number, number)
				return p.x, p.y, p.z
			end,
			engine = {
				correct = function(_id: any, _msg: any)
					corrections += 1
				end,
				pin = function(_id: any, _on: boolean): boolean
					return true
				end,
				hold = function() end,
			},
		})
		ms:onHandoff({ id = "a", species = "squirrel" }, nil, "possess")
		ms:watch("a", p.x, p.y, p.z, 100)
		local function send(seq: number, s: State, now: number): any
			local _, e, dec = SquirrelWire.decode(SquirrelWire.encode(seq, ms:epochOf("a"), SquirrelMotor.serialize(s)))
			return ms:packet("a", "squirrel", { seq = seq, epoch = e, snapshot = dec }, now)
		end
		local s = onRail(world, wire, 0.05, 5)
		s.railT = 0.95
		local r1 = send(1, s, 100.1)
		local r2 = send(2, onRail(world, wire, 0.95, 5.05), 100.15)
		local r3 = send(3, onRail(world, wire, 0.951, 5.1), 100.2)
		local snap = ms:motorOf("a")
		local d = flat(snap :: any, p)
		print(
			`      gate: [{codesOf(r1.violations or {})}|{codesOf(r2.violations or {})}|{codesOf(r3.violations or {})}], {corrections} corrections; the duel's pose {string.format(
				"%.0f",
				d
			)} st along the wire 0.1 s later`
		)
		t.truthy(corrections >= 1 or d < 50, `the gate's rail parameter put the body {d} st along the wire`)
	end)

	t.test("railT: on the rig, a 0.6 s silence and a rail parameter put the root 563 st along a wire", function()
		local world, vworld = worldWith({})
		local wire = longestWire(world)
		local t0 = 0.05
		local p = world.registry:pointAt(wire, t0)
		local stage, tA, tB = 0, math.huge, math.huge
		local rig = LiveRig.new({
			world = world,
			vworld = vworld,
			link = QUIET,
			seed = 7,
			-- silent from 5 s to 5.6 s; the first packet after it claims railT 0.95 where the body is
			packetCheat = function(snap: { [string]: any }, now: number): boolean?
				if now < 5 then
					return nil
				end
				if now < 5.6 then
					return false
				end
				if stage == 0 then
					stage, tA = 1, now
					snap.railT = 0.95
				end
				return nil
			end,
			-- the frame after it, the motor is there
			cheat = function(s: State, _inp: SquirrelMotor.Input, now: number, _w: any)
				if stage == 1 and now > tA then
					stage, tB = 2, now
					local q = world.registry:pointAt(wire, 0.95)
					s.railT = 0.95
					s.x, s.y, s.z = q.x, q.y, q.z
				end
			end,
			-- the root (the client's own physics): a small step at 5.2 s, then held at the start until the packets at
			-- the far end are in (a root standing still is judged against where the packets were when it last moved)
			rootCheat = function(r: { x: number, y: number, z: number }, now: number, _s: State)
				if now > 5.2 and now < 5.4 then
					r.x += 0.2
				elseif stage >= 1 and now < tB + 0.1 then
					r.x, r.y, r.z = p.x, p.y, p.z
				end
			end,
		})
		local s0 = SquirrelMotor.new(p.x, p.y, p.z)
		s0.routeId, s0.railT, s0.grounded = wire.id, t0, false
		rig:possess(s0, function(_now: number, _s: State, _e: { SquirrelMotor.Event }): SquirrelMotor.Input
			return SquirrelMotor.idleInput(0)
		end)
		rig:run(8)
		local r = rig:result()
		local d = flat(r.root, p)
		print(
			`      {LiveRig.describe("a rail parameter after a silence", r)}; the root {string.format("%.0f", d)} st along the wire`
		)
		t.truthy(d < 50, `the root ended {d} st along the wire`)
	end)

	t.test(
		"gate: a hand-off's first packet that passes the gate with a field out of bounds snaps the body to 0, 0, 0",
		function()
			local world, vworld = worldWith({})
			local wire = longestWire(world)
			local p = world.registry:pointAt(wire, 0.05)
			local moves = {}
			local ms = MovementService.new({
				validator = MoveValidator.new(vworld),
				enforce = true,
				poseOf = function(_actor: any): (number, number, number)
					return p.x, p.y, p.z
				end,
				engine = {
					correct = function(_id: any, msg: any)
						table.insert(moves, msg)
					end,
					pin = function(_id: any, _on: boolean): boolean
						return true
					end,
					hold = function() end,
				},
			})
			ms:onHandoff({ id = "a", species = "squirrel" }, nil, "possess")
			ms:watch("a", p.x, p.y, p.z, 100)
			local s = onRail(world, wire, 0.05, 5)
			local snap = SquirrelMotor.serialize(s) :: any
			snap.stamina = 2 -- (any field fieldCheck holds: its first packet is never a baseline)
			local _, e, dec = SquirrelWire.decode(SquirrelWire.encode(1, ms:epochOf("a"), snap))
			local r = ms:packet("a", "squirrel", { seq = 1, epoch = e, snapshot = dec }, 100.1)
			local m = moves[1]
			local d = if m then math.sqrt((m.x - p.x) ^ 2 + (m.y - p.y) ^ 2 + (m.z - p.z) ^ 2) else 0
			print(
				`      [{codesOf(r.violations or {})}]: {#moves} moves, the body put at {if m
					then string.format("%.0f, %.0f, %.0f", m.x, m.y, m.z)
					else "-"} ({string.format("%.0f", d)} st from where it was handed over); pinned {ms:isPinned("a")}`
			)
			t.truthy(m == nil or d < 10, `a field fault at the gate moved the body {d} st`)
		end
	)

	-- touches ----------------------------------------------------------------------------------------------------------
	t.test(
		"touches: off a rail and back on, a greedy grab up a trunk and along a wire at 2 to 20 packets a second",
		function()
			local world, vworld = worldWith({})
			local trunks = Driver.targetsAround(world, 0, 0, 2000)
			local tall = trunks[1]
			for _, r in trunks do
				if r.length > tall.length then
					tall = r
				end
			end
			local wire = longestWire(world)
			local launchXZ = SquirrelMotor.launchCapXZ(false) * E.launchTol
			local rows, fails = {}, {}
			for _, case in { { r = tall, name = "trunk" }, { r = wire, name = "wire" } } do
				local r = case.r
				local cap = SquirrelMotor.routeCap(r, false) * E.railTol
				-- (an honest body: the rail's pace, or for a level rail a leap along it; up a trunk a leap off it and a
				-- grab back lands at the trunk's nearest point, at the body's own height: no faster than the climb and a
				-- leap, the time shared. Half as much again, to be generous)
				local bound = if case.name == "trunk" then 1.5 * cap else 1.1 * math.max(cap, launchXZ)
				for _, rate in { 2, 4, 10, 20 } do
					local v = MoveValidator.new(vworld)
					local dt = 1 / rate
					local tt = 0.05
					local s = onRail(world, r, tt, 0)
					v:accept("a", { seq = 1, snapshot = SquirrelMotor.serialize(s) }, 0)
					local y0, a0 = s.y, world.registry:pointAt(r, tt)
					local clock, n, bad, peak = 0, 1, 0, 0
					while clock < 3 - 1e-9 and tt < 0.97 do
						clock += dt
						n += 1
						local prev = v:last("a")
						local cand: State
						if prev.routeId then
							local vis = SquirrelMotor.visualPose(prev, world)
							if case.name == "trunk" then
								-- off: straight up from the drawn pose, as high as passes at any vertical speed
								local bestH, bestVy = 0, 0
								for vy = -P.gravity * dt, P.leapUp * E.launchTol, 1 do
									local h = most(0, 60, function(x: number): boolean
										local c = SquirrelMotor.new(vis.x, vis.y + x, vis.z)
										c.grounded, c.committedAirborne, c.vy, c.clock = false, true, vy, clock
										return clean(v, prev, c, dt)
									end)
									if h and h > bestH then
										bestH, bestVy = h, vy
									end
								end
								cand = SquirrelMotor.new(vis.x, vis.y + bestH, vis.z)
								cand.grounded, cand.committedAirborne, cand.vy, cand.clock = false, true, bestVy, clock
							else
								-- off: along the wire at its height, as far as passes
								local q = world.registry:pointAt(r, math.min(1, tt + 0.01))
								local dx, dz = q.x - vis.x, q.z - vis.z
								local l = math.sqrt(dx * dx + dz * dz)
								dx, dz = dx / l, dz / l
								local function at(x: number): State
									local c = SquirrelMotor.new(vis.x + dx * x, vis.y, vis.z + dz * x)
									c.grounded, c.committedAirborne, c.vy, c.clock = false, true, 0, clock
									c.vx, c.vz = dx * 40, dz * 40
									return c
								end
								cand = at(most(0, 80, function(x: number): boolean
									return clean(v, prev, at(x), dt)
								end) or 0)
							end
						else
							-- on: the furthest point of the rail ahead a grab passes (scanned, then refined)
							local best: number? = nil
							local x = tt
							while x <= 1 do
								if clean(v, prev, onRail(world, r, x, clock), dt) then
									best = x
								end
								x += 0.002
							end
							if best then
								local lo, hi = best, math.min(1, best + 0.002)
								for _ = 1, 12 do
									local mid = (lo + hi) / 2
									if clean(v, prev, onRail(world, r, mid, clock), dt) then
										lo = mid
									else
										hi = mid
									end
								end
								tt = lo
								cand = onRail(world, r, tt, clock)
							else
								-- (no grab: the plain arc)
								cand = SquirrelMotor.clone(prev)
								cand.vy = math.max(prev.vy - P.gravity * dt, -P.terminalFall)
								cand.y = prev.y + (prev.vy + cand.vy) / 2 * dt
								cand.clock = clock
							end
						end
						local res = v:accept("a", { seq = n, snapshot = SquirrelMotor.serialize(cand) }, clock)
						bad += #res.violations
						if case.name == "trunk" then
							peak = math.max(peak, cand.y - y0)
						else
							peak = math.max(peak, flat(cand, a0))
						end
					end
					local pace = peak / clock
					table.insert(
						rows,
						`{case.name} {rate}/s: {string.format("%.1f", pace)} st/s ({string.format("%.0f", peak)} st in {string.format(
							"%.2f",
							clock
						)} s, {bad} violations; the rail's pace {string.format("%.1f", cap)}, bound {string.format(
							"%.1f",
							bound
						)})`
					)
					if bad == 0 and pace > bound then
						table.insert(fails, `{case.name} at {rate}/s: {string.format("%.1f", pace)} st/s`)
					end
				end
			end
			for _, row in rows do
				print(`      {row}`)
			end
			t.eq(#fails, 0, `rail touches faster than the rail and a leap, unflagged: {table.concat(fails, "; ")}`)
		end
	)

	-- ledge ------------------------------------------------------------------------------------------------------------
	t.test(
		"ledge: the launch onto a ledge and the launch off it share the gap's time (2 and 4 packets a second)",
		function()
			local base = TestWorld.build()
			local trunk = Driver.targetsAround(base, 0, 0, 200)[1]
			local foot = base.registry:foot(trunk)
			local launchUp = P.leapUp * E.launchTol
			local g = P.gravity
			local cap = SquirrelMotor.routeCap(trunk, false) * E.railTol
			local step = Units.st(1.4)
			local function leapRise(time: number): number
				local tu = math.min(time, launchUp / g)
				return launchUp * tu - 0.5 * g * tu * tu
			end
			local rows, fails = {}, {}
			for _, rate in { 2, 4 } do
				local dt = 1 / rate
				local pt = base.registry:pointAt(trunk, 0.3)
				-- the greedy's highest off the trunk beside a box whose top (a ledge) is `over` studs over the drawn pose,
				-- from the box's top up (nil boxes: the same spot over open ground)
				local function highest(over: number?): number
					local boxes = {}
					if over then
						table.insert(boxes, {
							minX = foot.x + 3,
							maxX = foot.x + 13,
							minZ = foot.z - 5,
							maxZ = foot.z + 5,
							top = pt.y + over,
						})
					end
					local world, vworld = worldWith(boxes)
					local v = MoveValidator.new(vworld)
					local prev = onRail(world, trunk, 0.3, 0)
					prev.trunkNormalX, prev.trunkNormalZ = 1, 0
					local vis = SquirrelMotor.visualPose(prev, world)
					local best = -math.huge
					for vy = -g * dt, launchUp, 0.5 do
						local h = most(over or 0, 50, function(x: number): boolean
							local n = SquirrelMotor.new(foot.x + 5, vis.y + x, foot.z)
							n.grounded, n.committedAirborne, n.vy, n.clock = false, true, vy, dt
							return clean(v, prev, n, dt)
						end)
						best = math.max(best, h or -math.huge)
					end
					return best
				end
				local without = highest(nil)
				-- the ledges: the highest an honest leap reaches with a step, and the highest the allowance takes (the
				-- stretch's climb in the whole gap, a launch's rise in the whole gap and a step)
				for _, over in { leapRise(dt) + step - 0.1, cap * dt + leapRise(dt) + step - 0.1 } do
					local best = highest(over)
					-- an honest body: up the trunk for tc, a leap until t1 that reaches the ledge with a step, a leap off it
					-- for the rest of the gap (the best split); with no such split, what the gap allows with no ledge
					local honest = without
					for i = 0, 100 do
						local t1 = dt * i / 100
						for j = 0, 20 do
							local tc = t1 * j / 20
							if cap * tc + leapRise(t1 - tc) + step + E.floorSlack >= over then
								honest = math.max(honest, over + leapRise(dt - t1) + E.floorSlack + E.posSlack + 1)
								break
							end
						end
					end
					table.insert(
						rows,
						`{rate}/s, a ledge {string.format("%.1f", over)} st over: up {string.format("%.1f", best)} st (an honest climb, leap, land and leap {string.format(
							"%.1f",
							honest
						)}; no ledge {string.format("%.1f", without)})`
					)
					if best > honest + 0.05 then
						table.insert(
							fails,
							`{rate}/s ledge {string.format("%.1f", over)}: {string.format("%.1f", best - honest)} st over`
						)
					end
				end
			end
			for _, row in rows do
				print(`      {row}`)
			end
			t.eq(#fails, 0, `the ledge allowance over an honest leap, land and leap: {table.concat(fails, "; ")}`)
		end
	)

	-- level ------------------------------------------------------------------------------------------------------------
	t.test("level: off a ledge 3 st up, walking on level over open ground for 3 s at 20 packets a second", function()
		local box = { minX = -10, maxX = 10, minZ = -10, maxZ = 10, top = 3 }
		local _, vworld = worldWith({ box })
		local v = MoveValidator.new(vworld)
		local clock, seq, bad = 0, 1, 0
		local s = SquirrelMotor.new(0, 3, 0)
		s.grounded = true
		v:accept("a", { seq = 1, snapshot = SquirrelMotor.serialize(s) }, 0)
		local x = 0
		while clock < 3 do
			clock += 0.05
			seq += 1
			x += 7 * 0.05 -- (a walk)
			local n = SquirrelMotor.new(x, 3, 0)
			n.grounded, n.vx, n.clock = true, 7, clock
			local r = v:accept("a", { seq = seq, snapshot = SquirrelMotor.serialize(n) }, clock)
			bad += #r.violations
		end
		print(`      {string.format("%.0f", x - 10)} st past the ledge's edge, 3 st over the ground: {bad} violations`)
		t.truthy(bad > 0, "walking on air 3 st over open ground is flagged")
	end)
end
