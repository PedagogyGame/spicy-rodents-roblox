--!strict
-- Traffic/LaneMath and Server/Traffic/SweptCollision (spike S4; BUILD_PLAN §4.3 S4): lane poses from the
-- compiled lanes (incl. the 519.92 u ice-cream loop), 1,000 randomised straight crossings against an
-- independent dense-sampling oracle, the 0.51 s sedan jump window (traffic.md §8.4), the per-tick
-- service (filters, teleport flags, first hit wins) and the perf budget 15 squirrels x 50 vehicles
-- <= 0.5 ms per tick.
local Units = require("@shared/Config/Units")
local Swept = require("@shared/Traffic/Swept")
local LaneMath = require("@shared/Traffic/LaneMath")
local SweptCollision = require("@server/Traffic/SweptCollision")
local Rng = require("@tests/cheat/Rng")

local BOX = SweptCollision.BOXES

return function(t)
	local records = require("../../generated/Lanes") :: any
	local lanes, skipped = LaneMath.load(records)

	t.test(
		"lanes: all 25 compiled records load as 36 lanes (W1 expands the polyline, segment, template and lane-set records); poses and yaws (traffic.md §3)",
		function()
			local n = 0
			for _ in lanes do
				n += 1
			end
			t.eq(n, 36)
			local skippedN = 0
			for _ in skipped do
				skippedN += 1
			end
			t.eq(skippedN, 0, "no record is skipped")
			local nb = lanes["res_main_ns_northbound"]
			t.near(nb.length, Units.st(520), 1e-9)
			local p = LaneMath.pointAt(nb, Units.st(10))
			t.near(p.x, Units.st(-5.4), 1e-9)
			t.near(p.z, Units.st(-250), 1e-9)
			t.near(p.yaw, 0, 1e-12, "+z heading is yaw 0")
			local sb = lanes["res_main_ns_southbound"]
			local q = LaneMath.pointAt(sb, 0)
			t.near(q.z, Units.st(260), 1e-9)
			t.near(q.yaw, math.pi, 1e-12, "-z heading is yaw pi")
			local eb = lanes["blvd_eastbound"]
			t.near(LaneMath.pointAt(eb, 0).yaw, math.pi / 2, 1e-12, "+x heading is yaw pi/2")
			t.near(LaneMath.pointAt(lanes["blvd_westbound"], 0).yaw, -math.pi / 2, 1e-12)
			t.near(eb.speeds.sedan, Units.st(8.6), 1e-9, "sedan cruise max on the boulevard")
			-- one-way wrap and ping-pong
			local s, wrapped = LaneMath.advance(nb, nb.length - 0.5, 60, 1 / 60) -- 1 st past the end
			t.truthy(wrapped)
			t.truthy(s >= 0 and s < 1, `wrapped s = {s}, length {nb.length}`)
			local beat = lanes["patrol_beat"]
			t.eq(beat.dir, 0, "patrol beat runs both ways")
			local s2, dir2, turned = LaneMath.pingPong(beat, beat.length - 0.1, 1, 26.25, 1 / 60)
			t.truthy(turned)
			t.eq(dir2, -1)
			t.truthy(s2 < beat.length)
		end
	)

	t.test("ice-cream loop: closed centripetal Catmull-Rom, length 519.92 u (traffic.md verifier 13)", function()
		local loop = lanes["icecream_loop"]
		t.eq(loop.shape, "loop")
		t.near(Units.u(loop.length), 519.92, 0.01)
		local p0 = LaneMath.pointAt(loop, 0)
		local pHalf = LaneMath.pointAt(loop, loop.length / 2)
		t.truthy(math.abs(p0.x) > 0 and math.abs(pHalf.x) > 0)
		t.truthy((p0.x < 0) ~= (pHalf.x < 0), "the two legs are on opposite sides of the road")
		-- stops at 0.16 and 0.59 of the loop (traffic.md §2.4): x about -5.7 heading north, +6.06 heading south
		local a = LaneMath.pointAt(loop, 0.16 * loop.length)
		local b = LaneMath.pointAt(loop, 0.59 * loop.length)
		t.truthy(Units.u(a.x) < -5 and math.cos(a.yaw) > 0.9, "stop 1 on the west leg heading north")
		t.truthy(Units.u(b.x) > 5 and math.cos(b.yaw) < -0.9, "stop 2 on the east leg heading south")
	end)

	t.test("trafficVehicleAhead: corridor test with the other body's projected half-length (L15721-15736)", function()
		local me: LaneMath.Body = { x = 0, z = 0, yaw = 0, width = BOX.sedan.width, length = BOX.sedan.length }
		local ahead: LaneMath.Body =
			{ x = 0, z = Units.st(10), yaw = 0, width = BOX.sedan.width, length = BOX.sedan.length }
		local behind: LaneMath.Body =
			{ x = 0, z = -Units.st(10), yaw = 0, width = BOX.sedan.width, length = BOX.sedan.length }
		local beside: LaneMath.Body =
			{ x = Units.st(6), z = Units.st(5), yaw = 0, width = BOX.sedan.width, length = BOX.sedan.length }
		local hidden: LaneMath.Body =
			{ x = 0, z = Units.st(5), yaw = 0, width = BOX.sedan.width, length = BOX.sedan.length, visible = false }
		local range, hw = Units.st(9 + 0.65 * 8), Units.st(1.2)
		t.truthy(LaneMath.vehicleAhead(me, 0, 1, range, hw, { ahead }))
		t.falsy(LaneMath.vehicleAhead(me, 0, 1, range, hw, { behind }))
		t.falsy(LaneMath.vehicleAhead(me, 0, 1, range, hw, { beside }))
		t.falsy(LaneMath.vehicleAhead(me, 0, 1, range, hw, { hidden }))
		local leader, gap = LaneMath.leader(100, 1, { { s = 90 }, { s = 130 }, { s = 115 } })
		t.eq((leader :: { s: number }).s, 115)
		t.near(gap, 15, 1e-12)
	end)

	-- Independent oracle for a straight crossing (constant yaw): sample the relative path densely and
	-- test each point against the padded box; cases within `margin` of any face are skipped because the
	-- two methods may legitimately differ there.
	local function denseOracle(
		p0: Swept.Vec3,
		p1: Swept.Vec3,
		v0: Swept.Vec3,
		v1: Swept.Vec3,
		yaw: number,
		box: SweptCollision.Box,
		scale: number
	): (boolean?, number)
		local pad = 0.18 * scale
		local hw, hl = box.width / 2 + pad, box.length / 2 + pad
		local minY, maxY = -0.3 * scale, box.height - 0.16 * scale
		local c, s = math.cos(yaw), math.sin(yaw)
		local r0 = { x = p0.x - v0.x, y = p0.y - v0.y, z = p0.z - v0.z }
		local r1 = { x = p1.x - v1.x, y = p1.y - v1.y, z = p1.z - v1.z }
		local inside = false
		local minMargin = math.huge
		local N = 4000
		for i = 0, N do
			local a = i / N
			local x, y, z = r0.x + (r1.x - r0.x) * a, r0.y + (r1.y - r0.y) * a, r0.z + (r1.z - r0.z) * a
			local lx, lz = c * x - s * z, s * x + c * z
			-- signed distance to the box (negative inside)
			local dx, dy, dz = math.abs(lx) - hw, math.max(minY - y, y - maxY), math.abs(lz) - hl
			local d = math.max(dx, dy, dz)
			minMargin = math.min(minMargin, math.abs(d))
			if d <= 0 then
				inside = true
			end
		end
		return inside, minMargin
	end

	t.test("1,000 randomised straight crossings agree with the dense-sampling oracle (studs)", function()
		local rng = Rng.new(4105)
		local kinds = { "sedan", "delivery_van", "ice_cream_van", "trolley", "dump_truck", "rv" }
		local agree, judged, hits = 0, 0, 0
		local tries = 0
		while judged < 1000 and tries < 20000 do
			tries += 1
			local box = BOX[kinds[math.floor(rng.next() * #kinds) + 1]]
			local yaw = rng.range(-math.pi, math.pi)
			local speed = Units.st(rng.range(0, 14)) -- u/s -> st/s, one 1/30 s tick
			local dt = 1 / 30
			local v0 = { x = Units.st(rng.range(-20, 20)), y = Units.st(0.04), z = Units.st(rng.range(-20, 20)) }
			local v1 = { x = v0.x + math.sin(yaw) * speed * dt, y = v0.y, z = v0.z + math.cos(yaw) * speed * dt }
			-- squirrel somewhere around the vehicle, moving at up to sprint speed in any direction, at a
			-- height from the sewer to above the roof
			local spread = 0.75 * box.length -- around the padded box so hits and misses are both common
			local p0 = {
				x = v0.x + rng.range(-1, 1) * spread, -- BOXES are already in studs
				y = rng.range(Units.st(-0.5), box.height + Units.st(0.5)),
				z = v0.z + rng.range(-1, 1) * spread,
			}
			local ang = rng.range(-math.pi, math.pi)
			local move = Units.st(rng.range(0, 16.8)) * dt
			local p1 = {
				x = p0.x + math.sin(ang) * move,
				y = p0.y + Units.st(rng.range(-0.4, 0.4)),
				z = p0.z + math.cos(ang) * move,
			}
			local want, margin = denseOracle(p0, p1, v0, v1, yaw, box, Units.STUDS_PER_UNIT)
			if margin < 1e-3 then
				continue -- on a face: both answers are right
			end
			judged += 1
			local got = Swept.hit(p0, p1, v0, v1, yaw, yaw, box.width, box.length, box.height)
			if got == want then
				agree += 1
			end
			if want then
				hits += 1
			end
		end
		print(`      {agree}/{judged} agree ({hits} hits) after {tries} draws`)
		t.eq(judged, 1000)
		t.eq(agree, 1000)
		t.truthy(hits > 100 and hits < 900, "the mix is informative")
	end)

	t.test(
		"the sedan jump window: about 0.51 s above the sedan's ceiling per leap, never hit there, parked and moving (traffic.md §8.4)",
		function()
			local k = Units.STUDS_PER_UNIT
			local box = BOX.sedan
			local ceiling = box.height - Swept.CEILING_UNITS * k -- relative to the vehicle base
			for _, carSpeed in { 0, 6 } do
				local aboveFrames, hitsAbove, hitsBelowOver = 0, 0, 0
				for f = 0, 50 do
					local t0, t1 = f / 60, (f + 1) / 60
					local function sq(tt: number): Swept.Vec3
						return { x = Units.st(-4 + 8 * tt), y = Units.st(0.18 + 12.8 * tt - 15 * tt * tt), z = 0 }
					end
					local function car(tt: number): Swept.Vec3
						return { x = Units.st(-carSpeed * tt), y = Units.st(0.04), z = 0 }
					end
					local a, b, ca, cb = sq(t0), sq(t1), car(t0), car(t1)
					local hit = Swept.hit(a, b, ca, cb, math.pi / 2, math.pi / 2, box.width, box.length, box.height, k)
					local above = math.min(a.y - ca.y, b.y - cb.y) > ceiling
					local over = math.abs(a.x - ca.x) < box.length / 2 + Swept.PAD_UNITS * k
					if above then
						aboveFrames += 1
						if hit then
							hitsAbove += 1
						end
					elseif over and hit then
						hitsBelowOver += 1
					end
				end
				local window = aboveFrames / 60
				print(
					`      car {carSpeed} u/s: {aboveFrames} frames above the ceiling = {string.format("%.3f", window)} s`
				)
				t.truthy(window >= 0.48 and window <= 0.53, `window {window}`)
				t.eq(hitsAbove, 0, "never hit while above the ceiling")
				t.truthy(hitsBelowOver > 0, "hit when over the footprint below the ceiling")
			end
		end
	)

	t.test("SweptCollision.step: filters (invisible, stationary, wrap, teleport), first hit wins", function()
		local svc = SweptCollision.new()
		local k = Units.STUDS_PER_UNIT
		local function car(id: any, x0: number, x1: number, extra: { [string]: any }?): SweptCollision.VehiclePose
			local v: SweptCollision.VehiclePose = {
				id = id,
				kind = "sedan",
				x = x1,
				y = 0.04 * k,
				z = 0,
				yaw = math.pi / 2,
				prevX = x0,
				prevY = 0.04 * k,
				prevZ = 0,
				prevYaw = math.pi / 2,
				visible = true,
				prevVisible = true,
				teleported = nil,
				box = nil,
				label = "vehicle",
				driver = nil,
			}
			if extra then
				for key, val in extra do
					(v :: any)[key] = val
				end
			end
			return v
		end
		local squirrel: SweptCollision.ActorPose =
			{ id = "s1", x = 0, y = 0.18 * k, z = 0, prevX = 0, prevY = 0.18 * k, prevZ = 0, teleported = nil }
		-- a car driving +x through the squirrel kills
		local hits = svc:step({ squirrel }, { car("a", -8 * k, 4 * k) }, 1 / 30)
		t.eq(#hits, 1)
		t.eq(hits[1].vehicleId, "a")
		-- stationary never kills, even with the squirrel inside the box
		t.eq(#svc:step({ squirrel }, { car("b", 0, 0) }, 1 / 30), 0)
		-- a wrap (travel > 12 u) is skipped
		t.eq(#svc:step({ squirrel }, { car("c", -300 * k, 4 * k) }, 1 / 30), 0)
		-- invisible at either end is skipped
		t.eq(#svc:step({ squirrel }, { car("d", -8 * k, 4 * k, { prevVisible = false }) }, 1 / 30), 0)
		-- a teleported vehicle is skipped; a teleported actor is skipped for one step
		t.eq(#svc:step({ squirrel }, { car("e", -8 * k, 4 * k, { teleported = true }) }, 1 / 30), 0)
		svc:markTeleported("s1")
		t.eq(#svc:step({ squirrel }, { car("f", -8 * k, 4 * k) }, 1 / 30), 0)
		t.eq(#svc:step({ squirrel }, { car("g", -8 * k, 4 * k) }, 1 / 30), 1, "the mark lasts one step")
		-- two cars hit the same squirrel: the first in fleet order wins, once
		local two = svc:step({ squirrel }, { car("h", -8 * k, 4 * k), car("i", 4 * k, -8 * k) }, 1 / 30)
		t.eq(#two, 1)
		t.eq(two[1].vehicleId, "h")
		-- a squirrel on a wire 17 u up is safe from a dump truck
		local high: SweptCollision.ActorPose =
			{ id = "s2", x = 0, y = 17 * k, z = 0, prevX = 0, prevY = 17 * k, prevZ = 0, teleported = nil }
		local truck = car("j", -8 * k, 4 * k, { kind = "dump_truck" })
		t.eq(#svc:step({ high, squirrel }, { truck }, 1 / 30), 1)
		-- unknown kinds without a box override are skipped, overrides are used
		t.eq(#svc:step({ squirrel }, { car("k", -8 * k, 4 * k, { kind = "bicycle" }) }, 1 / 30), 0)
		t.eq(#svc:step({ squirrel }, { car("l", -8 * k, 4 * k, { kind = "bicycle", box = BOX.cart }) }, 1 / 30), 1)
	end)

	t.test("perf: 15 squirrels x 50 vehicles on the real lanes <= 0.5 ms per tick (Lune)", function()
		local rng = Rng.new(99)
		local svc = SweptCollision.new()
		local laneList: { LaneMath.Lane } = {}
		for _, id in
			{
				"res_main_ns_northbound",
				"res_main_ns_southbound",
				"res_west_ns_x-180_northbound",
				"blvd_eastbound",
				"blvd_westbound",
				"patrol_beat",
				"trolley_track",
			}
		do
			table.insert(laneList, lanes[id])
		end
		local kinds = {
			"sedan",
			"sedan",
			"sedan",
			"sedan",
			"rv",
			"dump_truck",
			"ice_cream_van",
			"trolley",
			"cart",
			"delivery_van",
		}
		type Veh = { pose: SweptCollision.VehiclePose, lane: LaneMath.Lane, s: number, dir: number, speed: number }
		local fleet: { Veh } = {}
		local poses: { SweptCollision.VehiclePose } = {}
		for i = 1, 50 do
			local lane = laneList[((i - 1) % #laneList) + 1]
			local s = rng.next() * lane.length
			local dir = if lane.dir == 0 then (if rng.next() < 0.5 then 1 else -1) else lane.dir
			local p = LaneMath.pointAt(lane, s, dir, Units.st(0.04))
			local pose: SweptCollision.VehiclePose = {
				id = i,
				kind = kinds[((i - 1) % #kinds) + 1],
				x = p.x,
				y = p.y,
				z = p.z,
				yaw = p.yaw,
				prevX = p.x,
				prevY = p.y,
				prevZ = p.z,
				prevYaw = p.yaw,
				visible = true,
				prevVisible = true,
				teleported = nil,
				box = nil,
				label = nil,
				driver = nil,
			}
			table.insert(fleet, { pose = pose, lane = lane, s = s, dir = dir, speed = Units.st(rng.range(6.5, 10.7)) })
			table.insert(poses, pose)
		end
		-- squirrels crossing the roads at ground height around the residential and boulevard lanes
		local actors: { SweptCollision.ActorPose } = {}
		for i = 1, 15 do
			local lane = laneList[((i - 1) % 5) + 1]
			local p = LaneMath.pointAt(lane, rng.next() * lane.length, 1, 0)
			local a: SweptCollision.ActorPose = {
				id = `sq{i}`,
				x = p.x + Units.st(rng.range(-6, 6)),
				y = Units.st(0.18),
				z = p.z + Units.st(rng.range(-6, 6)),
				prevX = 0,
				prevY = Units.st(0.18),
				prevZ = 0,
				teleported = nil,
			}
			a.prevX, a.prevZ = a.x, a.z
			table.insert(actors, a)
		end
		local dt = 1 / 30
		local ticks = 600
		local totalHits, totalPairs, totalNarrow = 0, 0, 0
		local started = os.clock()
		for _ = 1, ticks do
			-- move the fleet (kinematic, on-lane) and the squirrels (random walk across the road)
			for _, v in fleet do
				local pose = v.pose
				pose.prevX, pose.prevY, pose.prevZ, pose.prevYaw = pose.x, pose.y, pose.z, pose.yaw
				local wrapped = false
				if v.lane.dir == 0 then
					local s, d = LaneMath.pingPong(v.lane, v.s, v.dir, v.speed, dt)
					v.s, v.dir = s, d
				else
					v.s, wrapped = LaneMath.advance(v.lane, v.s, v.speed, dt)
				end
				local p = LaneMath.pointAt(v.lane, v.s, v.dir, Units.st(0.04))
				pose.x, pose.y, pose.z, pose.yaw = p.x, p.y, p.z, p.yaw
				pose.teleported = if wrapped then true else nil
			end
			for _, a in actors do
				a.prevX, a.prevY, a.prevZ = a.x, a.y, a.z
				a.x += Units.st(rng.range(-1, 1)) * 8 * dt
				a.z += Units.st(rng.range(-1, 1)) * 8 * dt
			end
			local hits = svc:step(actors, poses, dt)
			totalHits += #hits
			totalPairs += svc.stats.pairs
			totalNarrow += svc.stats.narrow
		end
		local perTick = (os.clock() - started) / ticks * 1000
		print(
			`      {string.format("%.3f", perTick)} ms per tick incl. fleet motion; pairs {totalPairs / ticks} per tick, narrow {string.format(
				"%.1f",
				totalNarrow / ticks
			)}, hits {totalHits} in {ticks} ticks`
		)
		t.truthy(perTick <= 0.5, `{perTick} ms per tick`)
		t.truthy(totalHits > 0, "some squirrels were run over in 20 s of traffic")
	end)
end
