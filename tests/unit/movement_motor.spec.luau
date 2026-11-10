--!strict
-- Routes/Motion and Movement/SquirrelMotor golden and behaviour tests (spike S3; BUILD_PLAN §6.2
-- "Routes/*" advance golden, junction choice, serialize -> deserialize; "Motors" leap apex 2.73 u,
-- speed caps, determinism).
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local Units = require("@shared/Config/Units")
local Curve = require("@shared/Routes/Curve")
local Motion = require("@shared/Routes/Motion")
local Registry = require("@shared/Routes/Registry")
local SquirrelMotor = require("@shared/Movement/SquirrelMotor")
local TestWorld = require("@tests/cheat/TestWorld")

local function dist(a: Curve.Vec3, b: { number }): number
	local dx, dy, dz = a.x - b[1], a.y - b[2], a.z - b[3]
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function num(v: any): number
	if type(v) == "string" then
		return tonumber(v) :: number
	end
	return v
end

return function(t)
	t.test("golden advance.json: 2,000 RouteMotion.advance cases to 1e-12 (HTML units, minLength 1)", function()
		local g = serde.decode("json", fs.readFile("tests/golden/advance.json"))
		t.eq(#g.rows, 2000)
		for _, row in g.rows do
			local r = Motion.advance(row[1], row[2], row[3], row[4], row[5], row[6], 1)
			t.near(r, row[7], 1e-12)
		end
		-- the stud default guards at 1 u = 2.5 st
		t.near(Motion.advance(0, 1, 1, 0.05, Units.st(7.2), Units.st(0.5)), 0.05 * 7.2 / 1, 1e-12)
	end)

	t.test("golden rail_motion.json: 60 routes x 40 steps (t to 1e-12, pose and tangent to 0.01 u)", function()
		local g = serde.decode("json", fs.readFile("tests/golden/rail_motion.json"))
		local harvest = serde.decode("json", fs.readFile("data/harvest/routes.json")).routes
		local byId: { [number]: any } = {}
		for _, r in harvest do
			byId[r.id] = r
		end
		local maxPos, maxTan = 0, 0
		for _, seq in g.sequences do
			local h = byId[seq.id]
			local reg = Registry.fromRecords({
				{
					id = h.id,
					name = h.name,
					kind = h.kind,
					points = h.points,
					length = h.length,
					surfaceRadius = h.surfaceRadius,
					sampleCount = h.sampleCount,
				},
			}, 1)
			local route = reg:get(seq.id) :: Registry.Route
			-- the start parameter is not recorded: recover it from the first raw advance
			local first = seq.steps[1]
			local dt0 = math.max(0, math.min(first.dt, 0.05))
			local tt = first.raw - (first.forward * seq.dir * dt0 * seq.speed) / math.max(1, seq.length)
			for _, step in seq.steps do
				local raw = Motion.advance(tt, seq.dir, step.forward, step.dt, seq.speed, seq.length, 1)
				t.near(raw, step.raw, 1e-12, `route {seq.id}`)
				tt = math.clamp(raw, 0, 1)
				t.near(tt, step.t, 1e-12)
				maxPos = math.max(maxPos, dist(reg:pointAt(route, tt), step.pos))
				maxTan = math.max(maxTan, dist(reg:tangentAt(route, tt), step.tangent))
			end
		end
		print(`      rail_motion max pose deviation {maxPos} u, tangent {maxTan}`)
		t.truthy(maxPos <= 0.01, `pose {maxPos}`)
		t.truthy(maxTan <= 1e-6, `tangent {maxTan}`)
	end)

	t.test("golden junction.json: inward, canTransfer (studs), ease", function()
		local g = serde.decode("json", fs.readFile("tests/golden/junction.json"))
		t.eq(#g.cases, 49)
		for _, c in g.cases do
			if c.fn == "inward" then
				t.eq(Motion.inward(c.t, c.desired), c.result, `inward {c.t}`)
			elseif c.fn == "canTransfer" then
				t.eq(Motion.canTransfer(Units.st(num(c.gap)), c.explicit), c.result, `canTransfer {c.gap} {c.explicit}`)
			else
				t.near(Motion.ease(c.p), c.result, 1e-12)
			end
		end
	end)

	t.test("golden pounce.json: attackHeading, pounceVelocity, jumpVelocity (5,200 rows, 1e-9 u/s)", function()
		local g = serde.decode("json", fs.readFile("tests/golden/pounce.json"))
		t.eq(#g.rows, 5200)
		for _, row in g.rows do
			local yaw, railKind, trunkNormal, pitch, focus, moveSpeed, boost =
				row[1], row[2], row[3], row[4], row[5], row[6], row[7]
			local onTrunk = railKind == "trunk"
			local nx: number? = nil
			local nz: number? = nil
			if trunkNormal then
				nx, nz = trunkNormal[1], trunkNormal[3]
			end
			local heading = SquirrelMotor.attackHeading(onTrunk, nx, nz, yaw)
			t.near(heading, row[8], 1e-12)
			local px, py, pz = SquirrelMotor.pounceVelocity(pitch, focus, Units.st(moveSpeed), boost > 0, heading)
			t.near(Units.u(px), row[9][1], 1e-9)
			t.near(Units.u(py), row[9][2], 1e-9)
			t.near(Units.u(pz), row[9][3], 1e-9)
			local jx, jy, jz = SquirrelMotor.jumpVelocity(heading, boost > 0)
			t.near(Units.u(jx), row[10][1], 1e-9)
			t.near(Units.u(jy), row[10][2], 1e-9)
			t.near(Units.u(jz), row[10][3], 1e-9)
		end
	end)

	-- One shared headless world over the compiled routes (flat ground at 0.18 u).
	local world = TestWorld.build()
	local input = SquirrelMotor.idleInput

	t.test(
		"leap apex is 2.73 u continuous and about 0.1 u lower at 60 Hz (routes_movement §13, verifier 10)",
		function()
			t.near(Units.u(SquirrelMotor.leapApex()), 2.7306666, 1e-5)
			local s = SquirrelMotor.new(Units.st(300), world.groundHeight, Units.st(300))
			local inp = input()
			inp.leap = true
			local maxY = s.y
			local airtime = 0
			SquirrelMotor.step(s, inp, 1 / 60, world)
			inp.leap = false
			for _ = 1, 120 do
				if s.grounded then
					break
				end
				maxY = math.max(maxY, s.y)
				airtime += 1 / 60
				SquirrelMotor.step(s, inp, 1 / 60, world)
			end
			local apex = Units.u(maxY - world.groundHeight)
			print(`      simulated apex {apex} u, airtime {airtime} s`)
			t.truthy(apex > 2.55 and apex < 2.74, `apex {apex}`)
			t.truthy(airtime > 0.75 and airtime < 0.95, `airtime {airtime}`)
			t.truthy(s.grounded)
			-- flat-ground leap distance with no input: about 8.97 u (§13)
			local dx = Units.u(math.sqrt((s.x - Units.st(300)) ^ 2 + (s.z - Units.st(300)) ^ 2))
			t.truthy(dx > 8.3 and dx < 9.3, `leap distance {dx} u`)
		end
	)

	t.test(
		"ground run: speed caps at walk 7.2 / sprint 13.2 / boost x1.6 u/s and velocity follows the camera",
		function()
			local s = SquirrelMotor.new(Units.st(300), world.groundHeight, Units.st(300))
			local inp = input(math.pi) -- camera at yaw pi: forward = (0, +1) in XZ
			inp.fw = 1
			for _ = 1, 180 do
				SquirrelMotor.step(s, inp, 1 / 60, world)
			end
			local speed = Units.u(math.sqrt(s.vx * s.vx + s.vz * s.vz))
			t.near(speed, 7.2, 0.02, "walk")
			t.eq(SquirrelMotor.V54.walk, Units.st(8.0))
			t.eq(SquirrelMotor.V54.sprint, Units.st(16.8))
			t.truthy(s.vz > 0 and math.abs(s.vx) < 1e-6, "runs along +z for camera yaw pi")
			t.truthy(s.grounded)
			inp.sprint = true
			for _ = 1, 180 do
				SquirrelMotor.step(s, inp, 1 / 60, world)
			end
			t.near(Units.u(math.sqrt(s.vx * s.vx + s.vz * s.vz)), 13.2, 0.02, "sprint")
			s.boostRemaining = 30
			s.tireless = true
			for _ = 1, 180 do
				SquirrelMotor.step(s, inp, 1 / 60, world)
			end
			t.near(Units.u(math.sqrt(s.vx * s.vx + s.vz * s.vz)), 13.2 * 1.6, 0.05, "sprint + boost")
		end
	)

	-- Owner 2026-11-10: "the squirrel runs a bit too fast ... and run out of sprint bursts".
	t.test("sprint is a burst: 4 s of it, then a walk until the meter is back; a ground leap costs some", function()
		local P = SquirrelMotor.params
		local function speedOf(s: SquirrelMotor.State): number
			return math.sqrt(s.vx * s.vx + s.vz * s.vz)
		end
		local s = SquirrelMotor.new(Units.st(300), world.groundHeight, Units.st(300))
		local inp = input(math.pi)
		inp.fw = 1
		inp.sprint = true
		t.eq(s.stamina, 1)
		local winded, windedAt, frames = 0, 0, 0
		local function run(seconds: number)
			for _ = 1, math.round(seconds * 60) do
				frames += 1
				local _, events = SquirrelMotor.step(s, inp, 1 / 60, world)
				for _, e in events do
					if e.kind == "winded" then
						winded += 1
						windedAt = frames / 60
					end
				end
			end
		end
		run(3.5)
		t.near(speedOf(s), P.sprint, 0.05, "sprinting")
		t.near(s.stamina, 1 - 3.5 / P.sprintSeconds, 1e-6)
		t.eq(winded, 0)
		run(1)
		t.eq(winded, 1, "one winded event")
		t.near(windedAt, P.sprintSeconds, 1 / 60 + 1e-9)
		t.near(speedOf(s), P.walk, 0.1, "Shift held, out of breath: a walk")
		t.eq(s.winded, true)
		-- still holding Shift: the meter comes back, and at sprintRecover of it the sprint returns
		run(P.sprintRecover * P.sprintRefill - 0.5 - 0.1)
		t.eq(s.winded, true)
		t.near(speedOf(s), P.walk, 0.05)
		run(0.5)
		t.eq(s.winded, false)
		t.near(speedOf(s), P.sprint, 0.6, "sprinting again")
		t.eq(winded, 1)
		-- resting refills it in sprintRefill seconds from empty
		inp.sprint = false
		inp.fw = 0
		s.stamina = 0
		run(P.sprintRefill / 2)
		t.near(s.stamina, 0.5, 1e-6)
		run(P.sprintRefill)
		t.eq(s.stamina, 1)
		-- the meter survives a handoff
		s.stamina, s.winded = 0.2, true
		local back = SquirrelMotor.deserialize(SquirrelMotor.serialize(s))
		t.eq(back.stamina, 0.2)
		t.eq(back.winded, true)
		-- a leap off the ground costs leapCost and goes the full distance; a winded one goes less far
		s.stamina, s.winded = 1, false
		inp.leap = true
		SquirrelMotor.step(s, inp, 1 / 60, world)
		inp.leap = false
		t.near(s.stamina, 1 - P.leapCost, 1 / 60 / P.sprintRefill + 1e-6) -- less one frame of refill
		t.near(speedOf(s), P.leapForward, 1, "a full leap (less one frame of air drag)")
		run(2)
		t.eq(s.grounded, true)
		s.stamina, s.winded = 0.05, true
		inp.leap = true
		SquirrelMotor.step(s, inp, 1 / 60, world)
		inp.leap = false
		t.near(speedOf(s), P.leapForwardWinded, 1, "a winded leap")
		t.near(s.vy, P.leapUp, P.gravity / 60 + 1e-6, "as high as any leap")
		-- a tireless body (AI, tests) never drains
		local a = SquirrelMotor.new(Units.st(300), world.groundHeight, Units.st(300))
		a.tireless = true
		inp.fw, inp.sprint = 1, true
		for _ = 1, 600 do
			SquirrelMotor.step(a, inp, 1 / 60, world)
		end
		t.eq(a.stamina, 1)
		t.near(speedOf(a), P.sprint, 0.05)
	end)

	-- Review 2026-11-10: chained pounces held 28 st/s for ever and hops 24 st/s for half a minute.
	t.test("hopping and pounce-chaining are no way round the sprint meter", function()
		local P = SquirrelMotor.params
		local function average(press: string, every: number): (number, number)
			local s = SquirrelMotor.new(Units.st(300), world.groundHeight, Units.st(300))
			local inp = input(math.pi)
			inp.fw = 1
			local nextAt, late0, firstWinded = 0, 0, math.huge
			for i = 1, 60 * 60 do
				local now = i / 60
				local anyInp = inp :: any
				anyInp[press] = false
				if (every == 0 and s.grounded) or (every > 0 and now >= nextAt) then
					anyInp[press] = true
					nextAt = now + every
				end
				local _, events = SquirrelMotor.step(s, inp, 1 / 60, world)
				for _, e in events do
					if e.kind == "winded" then
						firstWinded = math.min(firstWinded, now)
					end
				end
				if i == 30 * 60 then
					late0 = s.z
				end
			end
			return (s.z - late0) / 30, firstWinded
		end
		local hop, hopWinded = average("leap", 0)
		t.truthy(hopWinded < 10, `hopping empties the meter in {hopWinded} s`)
		t.truthy(hop <= P.walk * 1.03, `winded hopping averages {hop} st/s (walk {P.walk})`)
		for _, every in { 0.7, 0.72, 1.0 } do
			local pounce, pounceWinded = average("pounce", every)
			t.truthy(pounceWinded < 10, `pouncing every {every} s empties the meter in {pounceWinded} s`)
			t.truthy(pounce <= P.walk * 1.06, `pouncing every {every} s averages {pounce} st/s (walk {P.walk})`)
		end
		-- the first pounce of a fresh squirrel is a full lunge
		local s = SquirrelMotor.new(Units.st(300), world.groundHeight, Units.st(300))
		local inp = input(math.pi)
		inp.pounce = true
		SquirrelMotor.step(s, inp, 1 / 60, world)
		t.truthy(math.sqrt(s.vx * s.vx + s.vz * s.vz) > P.walk * 1.4, "a full pounce")
		t.near(s.stamina, 1 - P.pounceCost, 1e-6, "no refill in the air")
	end)

	t.test("a leap off a rail carries as far as v5.4's did, winded or not", function()
		local P = SquirrelMotor.params
		local trunk = world.registry:get(220) :: Registry.Route
		local foot = world.registry:foot(trunk)
		local function carry(winded: boolean): number
			local s = SquirrelMotor.new(foot.x, world.groundHeight, foot.z - Units.st(1.2))
			local inp = input(math.pi)
			inp.grab = true
			SquirrelMotor.step(s, inp, 1 / 60, world)
			inp.grab = false
			t.eq(s.routeId, 220)
			-- climb a little so the flight is long enough to measure
			inp.fw = 1
			for _ = 1, 90 do
				SquirrelMotor.step(s, inp, 1 / 60, world)
			end
			if winded then
				s.stamina, s.winded = 0, true
			end
			inp.leap = true
			SquirrelMotor.step(s, inp, 1 / 60, world)
			inp.leap = false
			t.eq(s.railLeap, true)
			-- steer along the leap with Shift held
			inp.cameraYaw = math.atan2(s.vx, s.vz) + math.pi
			inp.sprint = true
			for _ = 1, 30 do
				SquirrelMotor.step(s, inp, 1 / 60, world)
			end
			t.eq(s.grounded, false, "still in the air")
			return math.sqrt(s.vx * s.vx + s.vz * s.vz)
		end
		local fresh, tired = carry(false), carry(true)
		t.truthy(fresh >= P.leapForward * 0.97, `half a second into a rail leap: {fresh} st/s`)
		t.near(tired, fresh, 1e-6, "the meter does not shorten a leap between branches")
		-- and on the ground the flag is gone
		local s = SquirrelMotor.new(Units.st(300), world.groundHeight, Units.st(300))
		local inp = input(math.pi)
		inp.leap = true
		SquirrelMotor.step(s, inp, 1 / 60, world)
		t.eq(s.railLeap, false, "a ground leap is not a rail leap")
	end)

	-- Owner 2026-11-10: "when jumping from branch or line, if the squirrel's jump and fall lines up with
	-- other branch or line, make it land on that".
	t.test("a leap off a rail lands on a branch or wire its flight lines up with", function()
		local C = Motion.C
		-- a long, fairly level rail that is not a trunk: a wire or a bough
		local wire: Registry.Route? = nil
		for _, r in world.registry:all() do
			if r.kind ~= "trunk" and not r.flags.isPole and r.length > Units.st(30) then
				local a, b = world.registry:pointAt(r, 0.3), world.registry:pointAt(r, 0.7)
				if math.abs(a.y - b.y) < 2 and a.y > world.groundHeight + 12 then
					wire = r
					break
				end
			end
		end
		assert(wire, "a long level rail above the ground")
		local mid = world.registry:pointAt(wire, 0.5)
		-- the pure search: on the curve, beside it inside the radius, and outside it
		local on = Motion.airCatch(world, mid.x, mid.y, mid.z, C.airCatch)
		assert(on, "the wire is caught at its own point")
		t.eq(on.routeId, wire.id)
		t.near(on.t, 0.5, 0.02)
		t.truthy(on.d < 0.05, `on the curve: {on.d}`)
		local above = Motion.airCatch(world, mid.x, mid.y + C.airCatch - 0.1, mid.z, C.airCatch)
		assert(above, "the wire is caught from just inside the radius")
		t.eq(above.routeId, wire.id)
		t.near(above.d, C.airCatch - 0.1, 0.05)
		t.eq(Motion.airCatch(world, mid.x, mid.y + C.airCatch + 0.6, mid.z, C.airCatch, nil), nil, "too far above")
		t.eq(Motion.airCatch(world, mid.x, mid.y, mid.z, C.airCatch, wire.id), nil, "the excluded rail is not caught")
		-- no trunk or pole is ever caught in the air
		local trunk = world.registry:get(220) :: Registry.Route
		local tp = world.registry:pointAt(trunk, 0.5)
		local hit = Motion.airCatch(world, tp.x, tp.y, tp.z, C.airCatch)
		t.truthy(hit == nil or hit.routeId ~= 220, "a trunk is not caught")
		-- in flight from a leap off another rail, falling past the wire: it lands on it
		local function falling(from: number?): SquirrelMotor.State
			local s = SquirrelMotor.new(mid.x, world.groundHeight, mid.z)
			s.x, s.y, s.z = mid.x, mid.y + 3, mid.z
			s.grounded = false
			s.vy = -8
			s.airFromRoute = from
			s.airX, s.airY, s.airZ = mid.x + 30, mid.y + 10, mid.z
			return s
		end
		local s = falling(220)
		local caught = false
		for _ = 1, 40 do
			local _, events = SquirrelMotor.step(s, input(math.pi), 1 / 60, world)
			for _, e in events do
				if e.kind == "catch" then
					caught = true
					t.eq(e.routeId, wire.id)
				end
			end
			if s.routeId then
				break
			end
		end
		t.eq(s.routeId, wire.id, "landed on the wire")
		t.eq(caught, true)
		t.eq(s.airFromRoute, nil)
		t.near(s.y, world.registry:pointAt(wire, s.railT).y, 0.05)
		-- a plain fall (no leap off a rail: a drop with Q, a pounce, a fall off a roof) passes it
		local f = falling(nil)
		for _ = 1, 40 do
			SquirrelMotor.step(f, input(math.pi), 1 / 60, world)
		end
		t.eq(f.routeId, nil, "a fall that is not a leap off a rail catches nothing")
		t.truthy(f.y < mid.y - 3)
		-- a leap along the wire comes down on the same wire further on, not at the launch point
		local w = SquirrelMotor.new(mid.x, world.groundHeight, mid.z)
		local start = world.registry:pointAt(wire, 0.25)
		w.routeId, w.railT, w.railDir, w.grounded = wire.id, 0.25, 1, false
		w.x, w.y, w.z = start.x, start.y, start.z
		local inp = input(math.pi)
		SquirrelMotor.step(w, inp, 1 / 60, world) -- settles the heading along the rail
		inp.leap = true
		SquirrelMotor.step(w, inp, 1 / 60, world)
		inp.leap = false
		t.eq(w.routeId, nil)
		t.eq(w.airFromRoute, wire.id)
		local air = 0
		for _ = 1, 120 do
			SquirrelMotor.step(w, inp, 1 / 60, world)
			if w.routeId or w.grounded then
				break
			end
			air += 1
		end
		t.truthy(air > 20, `it flew for {air} frames before anything caught it`)
		if w.routeId == wire.id then
			local landed = world.registry:pointAt(wire, w.railT)
			local far = math.sqrt((landed.x - start.x) ^ 2 + (landed.z - start.z) ^ 2)
			t.truthy(far >= C.airCatchOwn, `back on the wire {far} st further on`)
		end
		-- Q lets go for the ground: nothing is caught on the way down
		local d = SquirrelMotor.new(mid.x, world.groundHeight, mid.z)
		d.routeId, d.railT, d.railDir, d.grounded = wire.id, 0.5, 1, false
		d.x, d.y, d.z = mid.x, mid.y, mid.z
		local q = input(math.pi)
		q.drop = true
		SquirrelMotor.step(d, q, 1 / 60, world)
		t.eq(d.airFromRoute, nil)
	end)

	t.test("a leap off a rail is always a full one, and costs nothing", function()
		local P = SquirrelMotor.params
		local trunk = world.registry:get(220) :: Registry.Route
		local foot = world.registry:foot(trunk)
		local s = SquirrelMotor.new(foot.x, world.groundHeight, foot.z - Units.st(1.2))
		local inp = input(math.pi)
		inp.grab = true
		SquirrelMotor.step(s, inp, 1 / 60, world)
		inp.grab = false
		t.eq(s.routeId, 220)
		s.stamina, s.winded = 0, true
		inp.leap = true
		SquirrelMotor.step(s, inp, 1 / 60, world)
		t.eq(s.routeId, nil)
		t.near(math.sqrt(s.vx * s.vx + s.vz * s.vz), P.leapForward, 1, "less one frame of air drag")
		t.truthy(s.stamina < 0.01, "nothing spent")
	end)

	t.test("walk-in auto-grab onto the BUR OAK trunk, climb at 4.32 u/s, A/D picks a bough, E takes it", function()
		local trunk = world.registry:get(220) :: Registry.Route
		local foot = world.registry:foot(trunk)
		-- start 1.5 u south of the foot, camera behind the squirrel looking north (+z): yaw = pi
		local s = SquirrelMotor.new(foot.x, world.groundHeight, foot.z - Units.st(1.5))
		local inp = input(math.pi)
		inp.fw = 1
		local attached = false
		for _ = 1, 120 do
			local _, events = SquirrelMotor.step(s, inp, 1 / 60, world)
			for _, e in events do
				if e.kind == "attach" then
					attached = true
					t.eq(e.routeId, 220)
				end
			end
			if attached then
				break
			end
		end
		t.truthy(attached, "walk-in grab")
		t.eq(s.routeId, 220)
		t.eq(s.railDir, 1, "trunks climb +1")
		-- climb for one second at walk speed: 4.32 u along a 17.85 u trunk
		local t0 = s.railT
		for _ = 1, 60 do
			SquirrelMotor.step(s, inp, 1 / 60, world)
		end
		t.near((s.railT - t0) * Units.u(trunk.length), 4.32, 0.05, "wood walk speed")
		local p = world.registry:pointAt(trunk, s.railT)
		t.near(s.x, p.x, 1e-9)
		t.near(s.y, p.y, 1e-9)
		-- choose a fork on the right, then climb into it with W (auto-take) or E
		inp.choose = 1
		local _, ev = SquirrelMotor.step(s, inp, 1 / 60, world)
		inp.choose = 0
		local chosen = false
		for _, e in ev do
			if e.kind == "forkChosen" then
				chosen = true
			end
		end
		t.truthy(chosen, "fork chosen")
		t.truthy(s.pendingFork ~= nil)
		local taken = false
		for _ = 1, 600 do
			local _, events = SquirrelMotor.step(s, inp, 1 / 60, world)
			for _, e in events do
				if e.kind == "forkTaken" then
					taken = true
				end
			end
			if taken then
				break
			end
		end
		t.truthy(taken, "fork taken by holding W")
		local bough = world.registry:get(s.routeId :: number) :: Registry.Route
		t.eq(bough.kind, "branch")
		t.truthy(s.railT >= 0.018 - 1e-9)
		-- the visual pose sits above the bough centreline by the kind lift
		local vis = SquirrelMotor.visualPose(s, world)
		t.truthy(vis.y > s.y, "bough lift")
	end)

	t.test("serialize -> deserialize resumes identically mid-stride (the handoff property)", function()
		local trunk = world.registry:get(220) :: Registry.Route
		local foot = world.registry:foot(trunk)
		local a = SquirrelMotor.new(foot.x, world.groundHeight, foot.z - Units.st(1.5))
		local inp = input(math.pi)
		inp.fw = 1
		inp.sprint = true
		for _ = 1, 90 do
			SquirrelMotor.step(a, inp, 1 / 60, world)
		end
		t.truthy(a.routeId ~= nil, "on the trunk")
		local snap = SquirrelMotor.serialize(a)
		for k, v in snap do
			t.truthy(type(v) == "number" or type(v) == "boolean", `flat snapshot field {k}`)
		end
		local b = SquirrelMotor.deserialize(snap)
		t.deepEq(SquirrelMotor.serialize(b), snap)
		for _ = 1, 240 do
			SquirrelMotor.step(a, inp, 1 / 60, world)
			SquirrelMotor.step(b, inp, 1 / 60, world)
		end
		t.deepEq(SquirrelMotor.serialize(a), SquirrelMotor.serialize(b), "identical continuation")
		-- a leap mid-way, then the same again
		inp.leap = true
		SquirrelMotor.step(a, inp, 1 / 60, world)
		SquirrelMotor.step(b, inp, 1 / 60, world)
		inp.leap = false
		for _ = 1, 120 do
			SquirrelMotor.step(a, inp, 1 / 60, world)
			SquirrelMotor.step(b, inp, 1 / 60, world)
		end
		t.deepEq(SquirrelMotor.serialize(a), SquirrelMotor.serialize(b), "identical after a leap")
	end)

	t.test("determinism under fixed dt and the 0.08 s frame cap with 5 substeps", function()
		local s1 = SquirrelMotor.new(Units.st(310), world.groundHeight, Units.st(300))
		local s2 = SquirrelMotor.new(Units.st(310), world.groundHeight, Units.st(300))
		local inp = input(1.3)
		inp.fw = 1
		inp.side = -1
		for _ = 1, 60 do
			SquirrelMotor.step(s1, inp, 1 / 60, world)
			SquirrelMotor.step(s2, inp, 1 / 60, world)
		end
		t.deepEq(SquirrelMotor.serialize(s1), SquirrelMotor.serialize(s2))
		-- a 0.5 s frame is capped at 0.08 s = 5 substeps of 1/60
		local before = s1.clock
		SquirrelMotor.step(s1, inp, 0.5, world)
		t.near(s1.clock - before, 0.08, 1e-12)
	end)

	t.test(
		"Q drop leaves the rail with a 3.3 u/s hop from the visible position; E in the air grabs within 3.4 u",
		function()
			local trunk = world.registry:get(220) :: Registry.Route
			local p = world.registry:pointAt(trunk, 0.5)
			local s = SquirrelMotor.new(p.x, p.y, p.z)
			local inp = input(math.pi)
			inp.grab = true
			local _, ev = SquirrelMotor.step(s, inp, 1 / 60, world)
			inp.grab = false
			t.eq(ev[1].kind, "attach")
			t.eq(s.routeId, 220)
			inp.drop = true
			SquirrelMotor.step(s, inp, 1 / 60, world)
			inp.drop = false
			t.eq(s.routeId, nil)
			t.truthy(s.vy > 0 and s.vy <= Units.st(3.3), "hop")
			t.truthy(s.committedAirborne)
			local off = math.sqrt((s.x - p.x) ^ 2 + (s.z - p.z) ^ 2)
			t.truthy(off > Units.st(0.4) and off < Units.st(2.5), `launched from the bark, offset {off} st`)
			-- mid-air E re-grabs the trunk (within 3.4 u)
			inp.grab = true
			local _, ev2 = SquirrelMotor.step(s, inp, 1 / 60, world)
			t.eq(ev2[1].kind, "attach")
			t.eq(s.routeId, 220)
		end
	)

	t.test("rail end without a link pins at the end; a pole top auto-switches onto a wire", function()
		-- Chili's roof (id 0) is a singleton: walking off its end pins railT
		local roof = world.registry:get(0) :: Registry.Route
		local p = world.registry:pointAt(roof, 0.95)
		local s = SquirrelMotor.new(p.x, p.y, p.z)
		local inp = input(-math.pi / 2) -- camera forward = (-sin(-pi/2), -cos(-pi/2)) = (+1, 0): along +x
		inp.grab = true
		SquirrelMotor.step(s, inp, 1 / 60, world)
		inp.grab = false
		inp.fw = 1
		local pinned = false
		for _ = 1, 240 do
			local _, events = SquirrelMotor.step(s, inp, 1 / 60, world)
			for _, e in events do
				if e.kind == "railEnd" then
					pinned = true
					t.eq(e.reason, "none")
				end
			end
		end
		t.truthy(pinned)
		t.eq(s.routeId, 0)
		t.truthy(s.railT == 0 or s.railT == 1)
		-- a residential pole (trunk, excluded from nothing) ends in up to 4 wires: climb to its top
		local poleId: number? = nil
		for _, r in world.registry:all() do
			if r.flags.isPole and #world.graph:endLinks(r.id, false) >= 2 then
				poleId = r.id
				break
			end
		end
		t.truthy(poleId ~= nil, "a pole with wire links at its top")
		local pole = world.registry:get(poleId :: number) :: Registry.Route
		local top = world.registry:pointAt(pole, 0.9)
		local s2 = SquirrelMotor.new(top.x, top.y, top.z)
		local link = world.graph:endLinks(pole.id, false)[1]
		local wire = world.registry:get(link.to) :: Registry.Route
		-- aim the camera along the wire's inward tangent so the switch is unambiguous
		local tan = world.registry:tangentAt(wire, math.clamp(link.t, 0.002, 0.998))
		local dir = Motion.inward(link.t, 1)
		local camYaw = math.atan2(-tan.x * dir, -tan.z * dir)
		local inp2 = input(camYaw)
		inp2.grab = true
		SquirrelMotor.step(s2, inp2, 1 / 60, world)
		inp2.grab = false
		t.eq(s2.routeId, pole.id)
		inp2.fw = 1
		local switched = false
		for _ = 1, 600 do
			local _, events = SquirrelMotor.step(s2, inp2, 1 / 60, world)
			for _, e in events do
				if e.kind == "autoSwitch" then
					switched = true
				end
			end
			if switched then
				break
			end
		end
		t.truthy(switched, "pole top -> wire")
		local onto = world.registry:get(s2.routeId :: number) :: Registry.Route
		t.eq(onto.kind, "wire")
	end)
end
