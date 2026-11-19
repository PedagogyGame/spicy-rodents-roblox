--!strict
-- Review round 4 (adversarial) of the validator round-3 fix merged at w0-foundation f11589f: failing cases only.
--   normal    a packet on a trunk carries its trunk normal, the client's own number, never checked (any length up to
--             the wire's 1e7): Motion.visualPose puts the drawn feet at pos + normal * offset, and the envelope's rail
--             exit (section 4) measures the step off the rail, and wall-tests it, from there. A normal 100 long puts the
--             "launch point" 150 studs off the trunk: a 150 to 600-stud teleport in one packet, through anything, clean,
--             at 20 packets a second (MovementService._explained reads the same normal for the root's crossings)
--   railspeed a long gap (over 0.05 s) on the same rail allows railCap*dt + airGrab + launchXZ*dt: the grab radius is
--             added again every packet, and the leap's speed on top of the rail's. Along a wire at 10 packets a second
--             that is 167 st/s (the wire's cap 30.5, a leap 41), at 16 a second 227 st/s; the rig takes it, 0 snaps
--   sphere    leaving a rail (section 4) is bounded only by a 3-D distance from the drawn pose: railCap*dt +
--             |launch|*dt + 1.25 + airGrab, in any direction. 43 st straight up (or level) in 0.45 s, 28 in 0.25 s,
--             17 in 0.1 s, where a climb and a leap rise ~11 in 0.25 s; two trunks 68 st apart crossed level in 0.9 s
--   roofed    a wall test's `rise` (a leap over a fence) clears any wall whose top is under the higher end + rise + 1.6,
--             whatever covers the far end: off a rail it is a full leap's apex at any gap (the new section-4 test), so a
--             step off a trunk or downspout 6 st up goes through the wall of a roofed house at 20 packets a second (the
--             new root-crossing explanation passes it the same way); from a leap 5 st up at 4 packets a second too
-- (Pre-existing at w0-foundation 06a32a1, before the round-3 fix, except where the round-3 fix's own new checks rely on the
-- same numbers: the section-4 wall test and MovementService._explained read the client's trunk normal and the full rise.)
local SquirrelMotor = require("@shared/Movement/SquirrelMotor")
local MoveValidator = require("@server/Movement/MoveValidator")
local ValidatorWorld = require("@server/Movement/ValidatorWorld")
local TestWorld = require("@tests/cheat/TestWorld")
local LiveRig = require("@tests/lib/LiveRig")
local Driver = require("@tests/cheat/Driver")
local Motion = require("@shared/Routes/Motion")

type State = SquirrelMotor.State

local QUIET = { latency = 0.1, jitter = 0.01, loss = 0 }
local CHEAT_AT = 5
local P = SquirrelMotor.params
local E = SquirrelMotor.envelopeParams

-- the S3 world with open ground (y 0 the ground's surface), its houses `boxes` (14 high, hollow ones as four walls,
-- `roofs` as floors at their top), and its validator world
local function worldWith(boxes: { TestWorld.Box }, roofs: { TestWorld.Box }?): (any, any)
	local world = TestWorld.build({ boxes = boxes })
	local function wall(ox: number, oy: number, oz: number, dx: number, _dy: number, dz: number): boolean
		return TestWorld.segmentCrossesBox(boxes, ox, oz, ox + dx, oz + dz, oy)
	end
	local function down(ox: number, oy: number, oz: number, _dx: number, dy: number, _dz: number): boolean
		local lo = oy + dy
		if lo <= 0 and oy >= 0 then
			return true
		end
		for _, b in roofs or boxes do
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

-- a client that grabs the trunk by its foot and climbs it to `climbTo` studs, then the cheat
local function climber(climbTo: number): LiveRig.Keys
	return function(now: number, s: State, _e: { SquirrelMotor.Event }): SquirrelMotor.Input
		local inp = SquirrelMotor.idleInput(-math.pi / 2)
		inp.grab = now > 1 and now < 1.1 and s.routeId == nil
		inp.fw = if now > 1.2 and s.routeId ~= nil and s.y < climbTo then 1 else 0
		return inp
	end
end

return function(t)
	local base = TestWorld.build()
	local trunk = Driver.targetsAround(base, 0, 0, 200)[1]
	local foot = base.registry:foot(trunk)

	t.test(
		"normal: a step off a trunk from a drawn pose the client's own long trunk normal put 31-151 st away",
		function()
			local world, vworld = worldWith({})
			local flagged = {}
			for _, k in { 1, 5, 20, 100 } do
				local tt = 0.3
				local pt = world.registry:pointAt(trunk, tt)
				local v = MoveValidator.new(vworld)
				local s = SquirrelMotor.new(pt.x, pt.y, pt.z)
				s.routeId, s.railT, s.grounded = trunk.id, tt, false
				v:accept("a", { seq = 1, snapshot = SquirrelMotor.serialize(s) }, 0)
				-- one packet on the trunk claiming the normal (x k), then one off it beside where that normal draws the feet
				s.clock = 0.05
				s.trunkNormalX, s.trunkNormalZ = k, 0
				local r1 = v:accept("a", { seq = 2, snapshot = SquirrelMotor.serialize(s) }, 0.05)
				local vis = SquirrelMotor.visualPose(s, world)
				local n = SquirrelMotor.new(vis.x + 1, vis.y, vis.z)
				n.grounded, n.committedAirborne, n.vy = false, true, -1
				n.clock = 0.1
				local r2 = v:accept("a", { seq = 3, snapshot = SquirrelMotor.serialize(n) }, 0.1)
				local nViol = #r1.violations + #r2.violations
				print(
					`      normal x{k}: {string.format("%.0f", n.x - pt.x)} st off the trunk in 0.05 s: [{codesOf(
						r1.violations
					)}|{codesOf(r2.violations)}]`
				)
				if k > 1 then
					table.insert(flagged, { k = k, n = nViol, d = n.x - pt.x })
				end
			end
			for _, x in flagged do
				t.truthy(
					x.n >= 1,
					`a {string.format("%.0f", x.d)}-stud step off a trunk in 0.05 s (normal x{x.k}) is flagged`
				)
			end
		end
	)

	t.test("normal: on the rig, a 600-stud teleport off a trunk by a long trunk normal is snapped", function()
		local world, vworld = worldWith({})
		local stage = 0
		local target: any = nil
		local rig = LiveRig.new({
			world = world,
			vworld = vworld,
			link = QUIET,
			seed = 55,
			cheat = function(s: State, _inp: SquirrelMotor.Input, now: number, _w: any)
				if now >= CHEAT_AT and stage == 0 and s.routeId ~= nil then
					-- a frame on the trunk claiming a normal 400 long ...
					stage = 1
					s.trunkNormalX, s.trunkNormalZ = 400, 0
					local vis = SquirrelMotor.visualPose(s, world)
					target = { x = vis.x + 1, y = vis.y, z = vis.z }
				elseif stage == 1 and now >= CHEAT_AT + 0.06 then
					-- ... and off it beside where that draws the feet
					stage = 2
					s.routeId, s.railT = nil, 0
					s.x, s.y, s.z = target.x, target.y, target.z
					s.vx, s.vy, s.vz = 0, 0, 0
					s.grounded, s.committedAirborne = false, true
					s.trunkNormalX, s.trunkNormalZ = 0, 1
				end
			end,
		})
		rig:possess(SquirrelMotor.new(foot.x - 1.5, world.groundHeight, foot.z), climber(10))
		rig:run(CHEAT_AT + 4)
		local r = rig:result()
		local away = r.root.x - foot.x
		print(
			`      {LiveRig.describe("normal x400", r)}; the root ends {string.format("%.0f", away)} st east of the trunk`
		)
		t.truthy(stage == 2, "(the client was on the trunk and stepped off)")
		t.truthy(r.snaps >= 1 and away < 50, "snapped back to the trunk")
	end)

	-- the longest wire of the S3 world (625 st, cap 30.5 st/s)
	local function longestWire(world: any): any
		local best: any = nil
		for _, r in world.registry:all() do
			if r.kind == "wire" and (best == nil or r.length > best.length) then
				best = r
			end
		end
		return best
	end

	t.test(
		"railspeed: along a wire at 4, 10 and 16 packets a second, 3 to 6 times its cap, every packet clean",
		function()
			local world, vworld = worldWith({})
			local wire = longestWire(world)
			local cap = SquirrelMotor.routeCap(wire, false)
			-- (the fastest an honest body goes along a rail: running on it, or a leap along it and a grab back, the grab
			-- landing at the nearest point of the rail: the leap's own speed, not the grab radius again every packet)
			local honest = math.max(cap * E.railTol, P.leapForward * E.launchTol)
			local results = {}
			for _, cfg in { { dt = 0.25, v = 105 }, { dt = 0.1, v = 140 }, { dt = 0.06, v = 200 } } do
				local v = MoveValidator.new(vworld)
				local tt = 0.02
				local p = world.registry:pointAt(wire, tt)
				local s = SquirrelMotor.new(p.x, p.y, p.z)
				s.routeId, s.railT, s.grounded = wire.id, tt, false
				local clock = 0
				v:accept("a", { seq = 1, snapshot = SquirrelMotor.serialize(s) }, clock)
				local n, bad = 0, 0
				while clock < 2.5 do
					clock += cfg.dt
					n += 1
					tt += cfg.v * cfg.dt / wire.length
					local q = world.registry:pointAt(wire, tt)
					s.railT, s.x, s.y, s.z, s.clock = tt, q.x, q.y, q.z, clock
					local r = v:accept("a", { seq = n + 1, snapshot = SquirrelMotor.serialize(s) }, clock)
					bad += #r.violations
				end
				print(
					`      every {cfg.dt} s at {cfg.v} st/s along wire {wire.id} (cap {cap}, an honest leap {string.format(
						"%.1f",
						honest
					)}): {bad} violations in {n} packets`
				)
				table.insert(results, { cfg = cfg, bad = bad })
			end
			for _, x in results do
				t.truthy(x.bad >= 1, `{x.cfg.v} st/s along a wire every {x.cfg.dt} s is flagged`)
			end
		end
	)

	t.test("railspeed: on the rig, 140 st/s along a wire at 10 packets a second is snapped", function()
		local world, vworld = worldWith({})
		local wire = longestWire(world)
		local t0 = 0.02
		local p = world.registry:pointAt(wire, t0)
		local from: number? = nil
		local lastSent = -math.huge
		local rig = LiveRig.new({
			world = world,
			vworld = vworld,
			link = QUIET,
			seed = 7,
			cheat = function(s: State, _inp: SquirrelMotor.Input, now: number, _w: any)
				if now < 3 then
					return
				end
				from = from or now
				local tt = math.min(0.98, t0 + 140 * (now - (from :: number)) / wire.length)
				local q = world.registry:pointAt(wire, tt)
				s.routeId, s.railT = wire.id, tt
				s.x, s.y, s.z = q.x, q.y, q.z
				s.vx, s.vy, s.vz = 0, 0, 0
				s.grounded = false
			end,
			packetCheat = function(_snap: { [string]: any }, now: number): boolean?
				if now < 3 then
					return nil
				end
				if now - lastSent < 0.1 - 1e-3 then
					return false
				end
				lastSent = now
				return nil
			end,
		})
		local s0 = SquirrelMotor.new(p.x, p.y, p.z)
		s0.routeId, s0.railT, s0.grounded = wire.id, t0, false
		rig:possess(s0, function(_now: number, _s: State, _e: { SquirrelMotor.Event }): SquirrelMotor.Input
			return SquirrelMotor.idleInput(0)
		end)
		rig:run(7)
		local r = rig:result()
		local d = math.sqrt((r.root.x - p.x) ^ 2 + (r.root.z - p.z) ^ 2)
		print(
			`      {LiveRig.describe("140 st/s along a wire", r)}; the root {string.format("%.0f", d)} st along it in 4 s`
		)
		t.truthy(r.snaps >= 1, "snapped")
	end)

	t.test(
		"sphere: off the top of a trunk 25 st straight up in 0.25 s, 40 in 0.45 s; two trunks 68 st apart level",
		function()
			local world, vworld = worldWith({})
			local railCap = SquirrelMotor.routeCap(trunk, false)
			local cases = {}
			for _, c in { { dt = 0.25, up = 25 }, { dt = 0.45, up = 40 } } do
				-- (the top of the trunk: no more of it to climb; an honest climb and leap rise railCap*dt + a leap's rise in dt)
				local tt = 1
				local pt = world.registry:pointAt(trunk, tt)
				local prev = SquirrelMotor.new(pt.x, pt.y, pt.z)
				prev.routeId, prev.railT, prev.grounded = trunk.id, tt, false
				local vis = SquirrelMotor.visualPose(prev, world)
				local next = SquirrelMotor.new(vis.x, vis.y + c.up, vis.z)
				next.grounded, next.committedAirborne, next.vy = false, true, 0
				next.clock = c.dt
				local found = SquirrelMotor.envelope(prev, next, c.dt, vworld, false)
				local launchUp = P.leapUp * E.launchTol
				local tUp = math.min(c.dt, launchUp / P.gravity)
				local honest = railCap * E.railTol * c.dt
					+ launchUp * tUp
					- 0.5 * P.gravity * tUp * tUp
					+ Motion.C.airGrab
				print(
					`      off the trunk's top {c.up} st straight up in {c.dt} s (an honest climb, leap and a grab: {string.format(
						"%.1f",
						honest
					)}): [{codesOf(found)}]`
				)
				table.insert(cases, { c = c, n = #found })
			end
			-- two trunks 60-75 st apart: off the first level toward the second, onto the second, 0.45 s each
			local hop: { n: number, d: number }? = nil
			local trunks = Driver.targetsAround(world, 0, 0, 2000)
			for i, a in trunks do
				for j, b in trunks do
					if hop == nil and i < j and a.length > 25 and b.length > 25 then
						local fa, fb = world.registry:foot(a), world.registry:foot(b)
						local d = math.sqrt((fa.x - fb.x) ^ 2 + (fa.z - fb.z) ^ 2)
						if d > 65 and d < 70 then
							local v = MoveValidator.new(vworld)
							local ta, tb = 20 / a.length, 20 / b.length
							local pa, pb = world.registry:pointAt(a, ta), world.registry:pointAt(b, tb)
							local s = SquirrelMotor.new(pa.x, pa.y, pa.z)
							s.routeId, s.railT, s.grounded = a.id, ta, false
							v:accept("a", { seq = 1, snapshot = SquirrelMotor.serialize(s) }, 0)
							local ux, uz = pb.x - pa.x, pb.z - pa.z
							local L = math.sqrt(ux * ux + uz * uz)
							ux, uz = ux / L, uz / L
							local s1 = SquirrelMotor.new(pa.x + ux * 40, pa.y, pa.z + uz * 40)
							s1.grounded, s1.committedAirborne = false, true
							s1.vx, s1.vz, s1.vy = ux * 40, uz * 40, 0
							s1.clock = 0.45
							local r1 = v:accept("a", { seq = 2, snapshot = SquirrelMotor.serialize(s1) }, 0.45)
							local s2 = SquirrelMotor.new(pb.x, pb.y, pb.z)
							s2.routeId, s2.railT, s2.grounded = b.id, tb, false
							s2.clock = 0.9
							local r2 = v:accept("a", { seq = 3, snapshot = SquirrelMotor.serialize(s2) }, 0.9)
							hop = { n = #r1.violations + #r2.violations, d = L }
							print(
								`      trunk {a.id} -> {b.id}, {string.format("%.1f", L)} st apart at {string.format(
									"%.0f",
									pa.y
								)} st, level in 0.9 s: [{codesOf(r1.violations)}|{codesOf(r2.violations)}]`
							)
						end
					end
				end
			end
			for _, x in cases do
				t.truthy(x.n >= 1, `{x.c.up} st straight up off a trunk in {x.c.dt} s is flagged`)
			end
			t.truthy(hop ~= nil, "(two trunks found)")
			-- (an honest leap off a rail 20 st up flies ~41 st/s and falls back to that height in 0.85 s: ~35 st, a grab 8.5)
			t.truthy(hop ~= nil and (hop :: any).n >= 1, "a 68-stud level hop between trunks in 0.9 s is flagged")
		end
	)

	t.test("sphere: on the rig, off a trunk 24 st straight up at 4 packets a second is snapped", function()
		local world, vworld = worldWith({})
		local moved: number? = nil
		local lastSent = -math.huge
		local sentPos: any = nil
		local peak = -math.huge
		local rig = LiveRig.new({
			world = world,
			vworld = vworld,
			link = QUIET,
			seed = 53,
			cheat = function(s: State, _inp: SquirrelMotor.Input, now: number, _w: any)
				if now >= CHEAT_AT and moved == nil and s.routeId ~= nil and now - lastSent < 0.02 then
					moved = now
					local vis = SquirrelMotor.visualPose(s, world)
					s.routeId, s.railT = nil, 0
					s.x, s.y, s.z = vis.x, vis.y + 24, vis.z
					s.vx, s.vy, s.vz = 0, 0, 0
					s.grounded, s.committedAirborne = false, true
				end
				peak = math.max(peak, s.y)
			end,
			packetCheat = function(snap: { [string]: any }, now: number): boolean?
				if now < 4 then
					return nil
				end
				if now - lastSent < 0.25 - 1e-3 then
					return false
				end
				lastSent = now
				sentPos = { x = snap.x, y = snap.y, z = snap.z }
				return nil
			end,
			-- (the root written where the last packet has the body)
			rootCheat = function(p: { x: number, y: number, z: number }, now: number, _s: State)
				if sentPos and now >= CHEAT_AT - 0.1 and now < CHEAT_AT + 1.5 then
					p.x, p.y, p.z = sentPos.x, sentPos.y, sentPos.z
				end
			end,
		})
		rig:possess(SquirrelMotor.new(foot.x - 1.5, world.groundHeight, foot.z), climber(15))
		rig:run(CHEAT_AT + 4)
		local r = rig:result()
		print(
			`      {LiveRig.describe("24 st up off a trunk", r)}; stepped off at {moved}, peak y {string.format(
				"%.1f",
				peak
			)}`
		)
		t.truthy(moved ~= nil, "(the client was on the trunk and stepped off)")
		t.truthy(r.snaps >= 1, "snapped")
	end)

	-- a hollow house (four walls 1 st thick, 14 high, a roof at 14) whose west wall is 1.5 st east of the trunk's foot
	local function roofedHouse(): (any, any, number, number, number)
		local x0, z0, W = foot.x + 1.5, foot.z - 8, 16
		local walls = {
			{ minX = x0, maxX = x0 + 1, minZ = z0, maxZ = z0 + W, top = 14 },
			{ minX = x0 + W - 1, maxX = x0 + W, minZ = z0, maxZ = z0 + W, top = 14 },
			{ minX = x0, maxX = x0 + W, minZ = z0, maxZ = z0 + 1, top = 14 },
			{ minX = x0, maxX = x0 + W, minZ = z0 + W - 1, maxZ = z0 + W, top = 14 },
		}
		local roof = { { minX = x0, maxX = x0 + W, minZ = z0, maxZ = z0 + W, top = 14 } }
		local world, vworld = worldWith(walls, roof)
		return world, vworld, x0, z0, W
	end

	t.test(
		"roofed: into a roofed house off a trunk 6 st up at 20 packets a second, or from a leap 5 st up at 4",
		function()
			local world, vworld, x0 = roofedHouse()
			local inX = x0 + 2.5
			local results = {}
			for _, c in { { dt = 0.05, h = 6.2 }, { dt = 0.05, h = 8.2 }, { dt = 0.1, h = 4.2 } } do
				local tt = c.h / trunk.length
				local pt = world.registry:pointAt(trunk, tt)
				local prev = SquirrelMotor.new(pt.x, pt.y, pt.z)
				prev.routeId, prev.railT, prev.grounded = trunk.id, tt, false
				local vis = SquirrelMotor.visualPose(prev, world)
				local next = SquirrelMotor.new(inX, vis.y - 1, foot.z)
				next.grounded, next.committedAirborne, next.vy = false, true, -5
				next.clock = c.dt
				local found = SquirrelMotor.envelope(prev, next, c.dt, vworld, false)
				print(
					`      off the trunk at y {string.format("%.1f", vis.y)} into the house in {c.dt} s: [{codesOf(
						found
					)}]`
				)
				table.insert(results, { what = `off the trunk at {c.h} st in {c.dt} s`, n = #found })
			end
			for _, c in { { dt = 0.25, h = 5 }, { dt = 0.45, h = 6.8 } } do
				local prev = SquirrelMotor.new(x0 - 1, world.groundHeight + c.h, foot.z)
				prev.grounded, prev.vy, prev.committedAirborne = false, 0, true
				local next = SquirrelMotor.new(inX, world.groundHeight, foot.z)
				next.grounded = true
				next.clock = c.dt
				local found = SquirrelMotor.envelope(prev, next, c.dt, vworld, false)
				print(`      from a leap {c.h} st up beside the wall into the house in {c.dt} s: [{codesOf(found)}]`)
				table.insert(results, { what = `from a leap {c.h} st up in {c.dt} s`, n = #found })
			end
			for _, x in results do
				t.truthy(x.n >= 1, `{x.what}: through the wall of a roofed house is a wall`)
			end
		end
	)

	t.test(
		"roofed: on the rig, off a trunk 6 st up through the wall of a roofed house at 20 packets a second",
		function()
			local world, vworld, x0, z0, W = roofedHouse()
			local moved: number? = nil
			local rig = LiveRig.new({
				world = world,
				vworld = vworld,
				link = QUIET,
				seed = 54,
				cheat = function(s: State, _inp: SquirrelMotor.Input, now: number, _w: any)
					if s.routeId ~= nil then
						s.trunkNormalX, s.trunkNormalZ = 1, 0 -- (a unit normal: the body drawn on the house's side of the bark)
					end
					if now >= CHEAT_AT and moved == nil and s.routeId ~= nil then
						moved = now
						local vis = SquirrelMotor.visualPose(s, world)
						s.routeId, s.railT = nil, 0
						s.x, s.y, s.z = x0 + 1.9, vis.y - 0.3, vis.z
						s.vx, s.vy, s.vz = 0, 0, 0
						s.grounded, s.committedAirborne = false, true
					end
				end,
			})
			rig:possess(SquirrelMotor.new(foot.x - 1.5, world.groundHeight, foot.z), climber(6.2))
			rig:run(CHEAT_AT + 4)
			local r = rig:result()
			local inside = r.root.x > x0 + 1 and r.root.x < x0 + W - 1 and r.root.z > z0 + 1 and r.root.z < z0 + W - 1
			print(
				`      {LiveRig.describe("into a roofed house", r)}; stepped off at {moved}; the root at ({string.format(
					"%.1f",
					r.root.x
				)}, {string.format("%.1f", r.root.y)}) inside its walls: {inside}`
			)
			t.truthy(moved ~= nil, "(the client was on the trunk and stepped off)")
			t.falsy(inside, "the root is not left inside a roofed house")
		end
	)
end
