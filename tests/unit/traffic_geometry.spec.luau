--!strict
-- Vehicle glitches found by driving every lane (tools/sim scenarios lane_tour, patrol_beat, lane_ends,
-- stops, trolley_alongside, motorcycle_follow, ambulance_corner): each case pins the fix on the server's
-- own state, tick by tick, so it holds without the replay.
local LaneMath = require("@shared/Traffic/LaneMath")
local Fleet = require("@shared/Traffic/Fleet")
local TrafficService = require("@server/Traffic/TrafficService")
local Ghost = require("@shared/Traffic/Ghost")

local function entry(id: number): any
	for _, e in Fleet.ENTRIES do
		if e.id == id then
			return e
		end
	end
	error(`no fleet entry {id}`)
end

local function wrapAngle(a: number): number
	return math.atan2(math.sin(a), math.cos(a))
end

return function(t)
	local records = require("../../generated/Lanes") :: any
	local roads = require("../../generated/Roads") :: any

	local function service(entries: { any }, seed: number?)
		return TrafficService.new({ lanes = records, roads = roads, entries = entries, seed = seed or 7 })
	end

	-- every tick: no step longer than the speed allows, no heading change a car cannot steer, never
	-- moving against its nose; returns the events counted
	local function drive(svc: any, id: number, seconds: number, maxTurn: number): { [string]: number }
		local v = svc.byId[id]
		local dt = 1 / 30
		for _ = 1, math.floor(seconds * 30) do
			local px, pz, pyaw, pspeed, pvis = v.x, v.z, v.yaw, v.speed, v.visible
			svc:step(dt)
			if pvis and v.visible and not v.teleported then
				local dx, dz = v.x - px, v.z - pz
				local step = math.sqrt(dx * dx + dz * dz)
				t.truthy(
					step <= math.max(pspeed, v.speed) * dt + 0.05,
					`{v.name}: a {step} st step at {pspeed} st/s at ({v.x}, {v.z})`
				)
				t.truthy(
					math.abs(wrapAngle(v.yaw - pyaw)) <= maxTurn,
					`{v.name}: heading turned {wrapAngle(v.yaw - pyaw)} rad in one tick at ({v.x}, {v.z})`
				)
				if step > 0.05 then
					local along = (dx * math.sin(v.yaw) + dz * math.cos(v.yaw)) / step
					t.truthy(
						along > 0.9,
						`{v.name}: moving {math.deg(math.acos(math.clamp(along, -1, 1)))} deg off its nose`
					)
				end
			end
		end
		return table.clone(svc:stats().events)
	end

	t.test("patrol car: a U-turn onto the other side of the road at each end, never a jump or a reverse", function()
		local beat = LaneMath.load(records)
		LaneMath.unify(beat, roads, records)
		local lane = beat.patrol_beat
		-- the U-turn joins the end of one direction to the start of the other
		for _, dir in { 1, -1 } do
			local a = LaneMath.pointAt(lane, lane.length, dir)
			local b = LaneMath.uturnPoint(lane, dir, 0)
			t.near(a.x, b.x, 1e-9)
			t.near(a.z, b.z, 1e-9)
			t.near(wrapAngle(a.yaw - b.yaw), 0, 1e-9)
			local c = LaneMath.uturnPoint(lane, dir, LaneMath.uturnLength(lane))
			local d = LaneMath.pointAt(lane, 0, -dir)
			t.near(c.x, d.x, 1e-9)
			t.near(c.z, d.z, 1e-9)
			t.near(wrapAngle(c.yaw - d.yaw), 0, 1e-9)
		end
		-- s grows in both directions (the frame pointAt and the stop lines use)
		local s, d, turned = LaneMath.pingPong(lane, lane.length - 1, -1, 60, 1 / 30)
		t.truthy(turned)
		t.eq(d, 1)
		t.near(s, 1, 1e-9, "the overshoot, measured from the end it turned at")
		local svc = service({ entry(12) })
		local events = drive(svc, 12, 260, 0.1)
		t.truthy((events.turn or 0) >= 4, `turned {events.turn} times`)
		t.truthy((events.stopped or 0) + (svc:stats().violations.rollingStop or 0) >= 4, "stop lines both ways")
	end)

	t.test("ice cream loop: even speed by arc length, through both U-turns", function()
		local lanes = LaneMath.load(records)
		local loop = lanes.icecream_loop
		local step = 19 / 30 -- the van's cruise, one tick
		local worst = 0
		local s = 0
		local p = LaneMath.pointAt(loop, 0)
		while s < loop.length do
			s += step
			local q = LaneMath.pointAt(loop, s)
			worst = math.max(worst, math.abs(math.sqrt((q.x - p.x) ^ 2 + (q.z - p.z) ^ 2) / step - 1))
			p = q
		end
		t.truthy(worst < 0.02, `a tick's distance is off its arc length by {worst * 100} %`)
	end)

	t.test("van and trolley: braked into every stop, no lurch and no dead stop from speed", function()
		for _, id in { 5, 13 } do
			local svc = service({ entry(id) })
			local v = svc.byId[id]
			local dt = 1 / 30
			local stops, last = 0, v.speed
			for _ = 1, 30 * 200 do
				local px, pz, pphase = v.x, v.z, v.phase
				svc:step(dt)
				local moved = math.sqrt((v.x - px) ^ 2 + (v.z - pz) ^ 2)
				t.truthy(moved <= math.max(last, v.speed) * dt + 0.02, `{v.name}: {moved} st in a tick at {last} st/s`)
				if v.phase == "dwell" and pphase ~= "dwell" then
					stops += 1
					t.truthy(last < 2.5, `{v.name}: stopped dead from {last} st/s`)
				end
				last = v.speed
			end
			t.truthy(stops >= 5, `{v.name}: {stops} stops`)
		end
	end)

	t.test("polylines: every corner is an arc, the path is continuous, the heading turns smoothly", function()
		local lanes = LaneMath.load(records)
		LaneMath.unify(lanes, roads, records)
		local routes = {
			{ lanes.north_arterial_legacy_ambulance, 1 },
			{ lanes.responder_ambulance_trunk, 1 },
			{ lanes.responder_ambulance_trunk, -1 },
			{ LaneMath.makeRoute("incident", LaneMath.incidentRoute(0, { -525, -81 }, { 250, -200 }), {}), 1 },
			{ LaneMath.makeRoute("incident", LaneMath.incidentRoute(0, { -525, -81 }, { 250, -200 }), {}), -1 },
		}
		for _, r in routes do
			local lane, dir = r[1], r[2]
			local len = LaneMath.length(lane, dir)
			local step = 0.5
			local p = LaneMath.pointAt(lane, 0, dir)
			local s = 0
			while s + step <= len do
				s += step
				local q = LaneMath.pointAt(lane, s, dir)
				local d = math.sqrt((q.x - p.x) ^ 2 + (q.z - p.z) ^ 2)
				t.truthy(
					math.abs(d - step) < 0.01,
					`{lane.id} ({dir}): {d} st between points {step} st apart at s = {s}`
				)
				local turn = math.abs(wrapAngle(q.yaw - p.yaw))
				t.truthy(turn <= step / 4, `{lane.id} ({dir}): heading turns {turn} rad in {step} st at s = {s}`)
				local along = ((q.x - p.x) * math.sin(q.yaw) + (q.z - p.z) * math.cos(q.yaw)) / math.max(d, 1e-9)
				t.truthy(
					along > 0.99,
					`{lane.id} ({dir}): travel {math.deg(math.acos(math.clamp(along, -1, 1)))} deg off the heading`
				)
				p = q
			end
			-- it still ends where the polyline ends
			local poly = if dir < 0 then lane.polyRev else lane.poly
			local last = poly.pts[#poly.pts]
			local e = LaneMath.pointAt(lane, len, dir)
			t.near(e.x, last[1], 1e-6)
			t.near(e.z, last[2], 1e-6)
		end
		-- the legacy ambulance's whole run, tick by tick
		local svc = service({ entry(14) })
		svc.byId[14].timer = 0.1
		local events = drive(svc, 14, 140, 0.15)
		t.truthy((events.park or 0) >= 1, "it reached the hospital and parked")
	end)

	-- the overlap of two boxes on the ground (centre, HTML yaw, half width, half length): the smallest
	-- overlap along the four separating axes, <= 0 when apart
	local function overlap(a: { number }, b: { number }): number
		local depth = math.huge
		for _, yaw in { a[3], b[3] } do
			for pass = 1, 2 do
				local ax, az = math.sin(yaw), math.cos(yaw)
				if pass == 2 then
					ax, az = az, -ax
				end
				local function reach(o: { number }): number
					local fx, fz = math.sin(o[3]), math.cos(o[3])
					return math.abs(fx * ax + fz * az) * o[5] + math.abs(fz * ax - fx * az) * o[4]
				end
				depth = math.min(depth, reach(a) + reach(b) - math.abs((b[1] - a[1]) * ax + (b[2] - a[2]) * az))
			end
		end
		return depth
	end

	t.test("the lane fleet never drives one vehicle into another (10 simulated minutes)", function()
		local entries = {}
		for _, e in Fleet.ENTRIES do
			if e.class ~= "responder" and e.class ~= "incident" then
				table.insert(entries, e)
			end
		end
		local svc = service(entries)
		local worst, where = 0, ""
		for _ = 1, 30 * 600 do
			svc:step(1 / 30)
			local vs = svc.vehicles
			for i = 1, #vs do
				local a = vs[i]
				if a.visible then
					for j = i + 1, #vs do
						local b = vs[j]
						if b.visible and math.abs(a.x - b.x) < 30 and math.abs(a.z - b.z) < 30 then
							local d = overlap(
								{ a.x, a.z, a.yaw, a.box.width / 2, a.box.length / 2 },
								{ b.x, b.z, b.yaw, b.box.width / 2, b.box.length / 2 }
							)
							if d > worst then
								worst, where = d, `{a.name} and {b.name} at ({a.x}, {a.z}), t = {svc.now}`
							end
						end
					end
				end
			end
		end
		t.truthy(worst < 0.3, `{worst} st deep: {where}`)
	end)

	t.test("ghosts: a reordered packet is sampled in time order; a repeated wrap flag snaps once", function()
		local function rec(x: number, teleported: boolean?): { [string]: number }
			return Ghost.encode({
				id = 1,
				x = x,
				z = 0,
				yaw = math.pi / 2, -- heading +x
				speed = 30,
				visible = true,
				beacons = false,
				teleported = teleported == true,
				stopped = false,
			})
		end
		local g = Ghost.new({ delay = 0 })
		g:push(0, { rec(0) })
		g:push(2 / 15, { rec(4) })
		g:push(1 / 15, { rec(2) }) -- overtaken on the way
		t.near(g:sample(1.5 / 15)[1].x, 3, 1e-4, "between the 2nd and 3rd send, not run backwards")
		-- a wrap at 1/15 s, its flag repeated on the next send: the car carries on to the snap, then never
		-- goes back
		local w = Ghost.new({ delay = 0 })
		w:push(0, { rec(1000) })
		w:push(1 / 15, { rec(10, true) })
		w:push(2 / 15, { rec(12, true) })
		w:push(3 / 15, { rec(14) })
		local last = w:sample(0)[1].x
		local snaps = 0
		for i = 1, 11 do
			local p = w:sample(i / 60)[1]
			if p.x < last - 100 then
				snaps += 1
			else
				t.truthy(p.x >= last - 1e-6, `drawn back from {last} to {p.x} at frame {i}`)
			end
			last = p.x
		end
		t.eq(snaps, 1)
	end)
end
