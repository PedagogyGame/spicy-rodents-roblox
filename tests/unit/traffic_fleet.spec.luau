--!strict
-- Traffic W1 #9: handedness unified on all 25 records, stop control at the sign sites, the AI fleet
-- (every class), yielding to humans and squirrels with relative visibility, run-over through the service,
-- dispatches, and the ghost pose stream (BUILD_PLAN §4.4 W1 #9; traffic.md §3-§6, §8, §13).
local Units = require("@shared/Config/Units")
local LaneMath = require("@shared/Traffic/LaneMath")
local Control = require("@shared/Traffic/Control")
local Fleet = require("@shared/Traffic/Fleet")
local Ghost = require("@shared/Traffic/Ghost")
local VehiclePuppet = require("@shared/Traffic/VehiclePuppet")
local Boxes = require("@shared/Traffic/Boxes")
local Schemas = require("@shared/Net/Schemas")
local Net = require("@shared/Net/Net")
local BufferCodec = require("@shared/Util/BufferCodec")
local TrafficService = require("@server/Traffic/TrafficService")

local st = Units.st

return function(t)
	local records = require("../../generated/Lanes") :: any
	local roads = require("../../generated/Roads") :: any

	local function service(entries: { any }?, seed: number?)
		return TrafficService.new({ lanes = records, roads = roads, entries = entries, seed = seed })
	end

	t.test(
		"drive on the right: every one-way vehicle lane sits right of its road; the boulevard is mirrored",
		function()
			local lanes = LaneMath.load(records)
			local changed = LaneMath.unify(lanes, roads, records)
			local roadCoord = {}
			for _, r in roads do
				roadCoord[r.id] = r.coord
			end
			local checked = 0
			for _, rec in records do
				local lane = lanes[rec.id]
				if lane and lane.vehicle and lane.shape == "straight" and rec.roads and rec.roads[1] then
					local road = roadCoord[rec.roads[1]]
					local function rightOk(coord: number, dir: number): boolean
						if math.abs(coord - road) < 1e-9 then
							return true -- on its own track
						end
						if lane.axis == "z" then
							return (coord - road) * dir < 0 -- heading +z keeps -x
						end
						return (coord - road) * dir > 0 -- heading +x keeps +z
					end
					if lane.dir ~= 0 then
						t.truthy(rightOk(lane.coord :: number, lane.dir), `{rec.id} keeps right`)
					else
						local cf = lane.coordFor
						if cf then
							t.truthy(rightOk(cf[1], 1) and rightOk(cf[-1], -1), `{rec.id} keeps right both ways`)
						else
							t.near(lane.coord :: number, road, 1e-9, `{rec.id} runs on its own track`)
						end
					end
					checked += 1
				end
			end
			t.truthy(checked >= 6, `checked {checked} straight vehicle lanes`)
			t.near(lanes.blvd_eastbound.coord :: number, st(5.6), 1e-9, "eastbound now runs at z > 0")
			t.near(lanes.blvd_westbound.coord :: number, -st(5.6), 1e-9)
			t.near(lanes.res_main_ns_northbound.coord :: number, -st(5.4), 1e-9, "residential lanes were already right")
			t.truthy(table.find(changed, "patrol_beat") ~= nil)
			-- polylines: the legacy ambulance heads -x along z = 283 u, so it keeps to z < 283 u
			local amb = lanes.north_arterial_legacy_ambulance
			local p = LaneMath.pointAt(amb, st(50), 1)
			t.near(p.z, st(283) - LaneMath.POLY_OFFSET, 1e-6)
			t.near(p.yaw, -math.pi / 2, 1e-9)
			-- the responder trunk keeps right both ways: on the long x = -722.5 leg (heading -z out, +z back)
			-- the outbound path runs at x = -722.5 + offset and the return at -722.5 - offset
			local trunk = lanes.responder_ambulance_trunk
			local outX, backX = nil, nil
			for i = 0, 200 do
				local po = LaneMath.pointAt(trunk, LaneMath.length(trunk, 1) * i / 200, 1)
				if math.abs(po.z) < 20 and math.cos(po.yaw) < -0.99 then
					outX = po.x
				end
				local pb = LaneMath.pointAt(trunk, LaneMath.length(trunk, -1) * i / 200, -1)
				if math.abs(pb.z) < 20 and math.cos(pb.yaw) > 0.99 then
					backX = pb.x
				end
			end
			t.near(outX :: number, -722.5 + LaneMath.POLY_OFFSET, 1e-6, "outbound keeps right")
			t.near(backX :: number, -722.5 - LaneMath.POLY_OFFSET, 1e-6, "return keeps right")
		end
	)

	t.test("all 25 records drive: segments and the outer sidewalk set expand; templates resolve per scene", function()
		local lanes = LaneMath.load(records)
		for i = 1, 3 do
			t.truthy(lanes[`event_barbecue_cars#{i}`] and lanes[`event_softball_cars#{i}`], `event lane {i}`)
		end
		for i = 1, 8 do
			t.truthy(lanes[`sidewalk_outer_set#{i}`], `outer sidewalk {i}`)
		end
		local glide = lanes["event_barbecue_cars#1"]
		t.near(glide.length, st(14), 1e-9, "a 14 u glide (traffic §5.11)")
		local route = LaneMath.incidentRoute(1, { -495, -81 }, { st(100), st(40) })
		t.eq(#route, 4)
		t.near(route[4][1], st(109), 1e-9, "car 1 parks at p.x + 9")
		t.near(route[4][2], st(50), 1e-9)
	end)

	t.test("stop control at the existing sign sites: both boulevard approaches and the patrol beat", function()
		local lanes = LaneMath.load(records)
		LaneMath.unify(lanes, roads, records)
		local stops = Control.resolve(Control.DEFAULT, lanes)
		t.eq(#stops.blvd_eastbound, 1)
		t.near(stops.blvd_eastbound[1].s, st(322) - st(280), 1e-6, "eastbound line at x = 322 u")
		t.near(stops.blvd_westbound[1].s, st(660) - st(372), 1e-6, "westbound line at x = 372 u")
		t.eq(#stops.patrol_beat, 2, "one line per direction")
		-- FSM: brake to the line, wait 1.2 s, go when clear; a rolling stop emits a violation
		local state = Control.newState()
		local s, speed, events, stoppedAt = 0, st(8), {}, nil
		local line = stops.blvd_eastbound
		for _ = 1, 30 * 20 do
			local cap, ev = Control.step(state, line, s, 1, speed, st(9), 1 / 30, true, 0.5, { rollingStop = 0.08 })
			if ev then
				table.insert(events, ev)
				if ev == "stopped" then
					stoppedAt = s
				end
			end
			speed = math.min(st(8), cap, speed + st(3) / 30)
			s += speed / 30
		end
		t.truthy(table.find(events, "stopped") and table.find(events, "go"), table.concat(events, ","))
		t.truthy(math.abs((stoppedAt :: number) - line[1].s) < st(0.5), `stopped {stoppedAt} vs line {line[1].s}`)
		local rolling = Control.newState()
		local evs = {}
		s, speed = 0, st(8)
		for _ = 1, 30 * 20 do
			local cap, ev = Control.step(rolling, line, s, 1, speed, st(9), 1 / 30, true, 0.01, { rollingStop = 0.08 })
			if ev then
				table.insert(evs, ev)
			end
			speed = math.min(st(8), cap)
			s += speed / 30
		end
		t.truthy(table.find(evs, "rollingStop") and not table.find(evs, "stopped"), table.concat(evs, ","))
	end)

	t.test("fleet: 25 vehicles, 5 simulated minutes at 30 Hz, everyone moves, nobody stuck > 60 s, no NaN", function()
		local svc = service(nil, 77)
		t.eq(#svc.vehicles, Fleet.count())
		-- a few pedestrians crossing the residential street and the boulevard
		local people = {
			{ x = 0, y = 0, z = st(40), kind = "human" },
			{ x = st(400), y = 0, z = 0, kind = "human" },
		}
		for _, dest in { { st(-100), st(-180) }, { st(60), st(-200) }, { st(-200), st(-120) } } do
			t.truthy(svc:dispatchResponder(dest), "an idle responder takes the job")
		end
		t.eq(svc:dispatchResponder({ 0, 0 }), nil, "all three busy")
		t.eq(svc:dispatchIncident({ st(-150), st(-60) }), 2)
		local seen: { [number]: number } = {}
		local start: { [number]: { number } } = {}
		for _, v in svc.vehicles do
			start[v.id] = { v.x, v.z }
		end
		local maxMs = 0
		for step = 1, 30 * 300 do
			-- people walk back and forth across the roads (12 s period)
			local ph = math.sin(step / 30 * math.pi / 6)
			people[1].x = ph * st(14)
			people[2].z = ph * st(16)
			local t0 = os.clock()
			svc:step(1 / 30, { people = people })
			maxMs = math.max(maxMs, (os.clock() - t0) * 1000)
			for _, v in svc.vehicles do
				t.truthy(v.x == v.x and v.z == v.z and v.y == v.y and v.yaw == v.yaw, `NaN on {v.name}`)
				if v.visible and ((v.x - start[v.id][1]) ^ 2 + (v.z - start[v.id][2]) ^ 2) > st(5) ^ 2 then
					seen[v.id] = (seen[v.id] or 0) + 1
				end
			end
		end
		local stats = svc:stats()
		for _, v in svc.vehicles do
			if v.offset >= 1200 then
				t.falsy(v.visible, `{v.name}: the softball event starts at 1200 s`)
				continue
			end
			t.truthy(seen[v.id], `{v.name} ({v.class}) moved at least 5 u from its spawn`)
			t.truthy((stats.stuck[v.id] or 0) <= 60, `{v.name} stuck {stats.stuck[v.id]} s`)
		end
		t.truthy((stats.events.stopped or 0) > 0, "stopped at a sign")
		t.truthy((stats.events.arrived or 0) >= 3 and (stats.events.home or 0) >= 3, "dispatched trips completed")
		t.truthy((stats.events.delivery or 0) > 0 and (stats.events.bell or 0) > 0, "van and trolley schedules ran")
		t.truthy((stats.events.wrap or 0) > 0, "wraps happened (teleport flagged)")
		print(
			`      {stats.ticks} ticks, mean {string.format("%.3f", stats.ms / stats.ticks)} ms, max {string.format(
				"%.3f",
				stats.maxTickMs
			)} ms; events {(function()
				local parts = {}
				for k, n in stats.events do
					table.insert(parts, `{k}={n}`)
				end
				table.sort(parts)
				return table.concat(parts, " ")
			end)()}`
		)
	end)

	local function sedanNB()
		local svc = service({ Fleet.ENTRIES[1] }, 3)
		local v = svc.vehicles[1]
		return svc, v
	end

	t.test(
		"yielding: sedans stop for a human and a ground squirrel ahead, but not for a squirrel up on a wire",
		function()
			-- human 20 u ahead in the lane
			local svc, v = sedanNB()
			local ahead = v.z + st(20)
			local human = { x = v.x, y = 0, z = ahead, kind = "human" }
			for _ = 1, 30 * 10 do
				svc:step(1 / 30, { people = { human } })
			end
			t.truthy(v.z < ahead - st(3), `stopped short of the human ({Units.u(ahead - v.z)} u)`)
			t.near(v.speed, 0, 1e-3)
			-- squirrel on the ground: also a hazard now (rebuild fix, traffic §13)
			svc, v = sedanNB()
			ahead = v.z + st(20)
			local sq = { id = "sq", x = v.x, y = st(0.18), z = ahead }
			for _ = 1, 30 * 10 do
				svc:step(1 / 30, { squirrels = { sq } })
			end
			t.truthy(v.z < ahead - st(2), "stopped short of the ground squirrel")
			t.eq(svc:stats().hits, 0)
			-- squirrel on a wire 17 u up: invisible to the driver (relative 4.76 u), passes under, no hit
			svc, v = sedanNB()
			ahead = v.z + st(20)
			local wire = { id = "w", x = v.x, y = st(17), z = ahead }
			for _ = 1, 30 * 10 do
				svc:step(1 / 30, { squirrels = { wire } })
			end
			t.truthy(v.z > ahead + st(5), "drove under the wire")
			t.eq(svc:stats().hits, 0)
		end
	)

	t.test("run-over: a squirrel darting into the lane just ahead of a moving sedan fires RunOver once", function()
		local svc, v = sedanNB()
		for _ = 1, 30 * 3 do
			svc:step(1 / 30, {})
		end
		t.truthy(v.speed > st(5), "at cruise")
		local victims = {}
		svc.RunOver:connect(function(actorId: any, vehicle: any)
			table.insert(victims, { actorId, vehicle.name })
		end)
		-- the squirrel waits on the kerb outside the corridor and leaps into the lane 0.55 u ahead of the
		-- bumper: the sedan brakes (rate 9) but cannot stop inside the 0.18 u pad
		local z0 = v.z + Boxes.BOXES.sedan.length / 2 + st(0.55) + v.speed / 30
		local sq = { id = "rodent", x = v.x - st(4), y = st(0.18), z = z0 }
		svc:step(1 / 30, { squirrels = { sq } })
		sq.x = v.x
		for _ = 1, 20 do
			svc:step(1 / 30, { squirrels = { sq } })
		end
		t.truthy(#victims >= 1, "run over")
		t.eq(victims[1][1], "rodent")
		t.eq(victims[1][2], "Sedan NB")
		-- a teleported squirrel (rule 12) is never swept on its handoff tick
		svc, v = sedanNB()
		for _ = 1, 30 * 3 do
			svc:step(1 / 30, {})
		end
		local hit = 0
		svc.RunOver:connect(function()
			hit += 1
		end)
		svc:markTeleported("p")
		svc:step(1 / 30, { squirrels = { { id = "p", x = v.x, y = st(0.18), z = v.z, teleported = true } } })
		t.eq(hit, 0, "handoff tick never kills")
	end)

	t.test("ghost stream: 13-byte records through Net.stream, decode, 100 ms interpolation, teleports snap", function()
		local svc = service(nil, 9)
		local sent = {}
		local net = Net.new({
			send = function(_player: any, name: string, payload: any)
				table.insert(sent, { name, payload })
			end,
			players = function(): { any }
				return {}
			end,
		})
		local buf = Ghost.new()
		local tNow = 0
		for i = 1, 30 do
			svc:step(1 / 15, {})
			tNow += 1 / 15
			local b = net:stream(nil, "VehiclePoses", svc:poseRecords())
			if i == 1 then
				t.eq(buffer.len(b), 13 * Fleet.count(), "13 bytes per vehicle")
			end
			buf:push(tNow, Net.decodeStream(Schemas.VehiclePose, b))
		end
		t.eq(#sent, 30, "one VehiclePoses send per stream call")
		local poses = buf:sample(tNow)
		local v = svc.byId[1]
		local p = poses[1]
		t.truthy(p.visible)
		-- 100 ms behind: within one tick-and-a-half of travel of the server pose
		local d = math.sqrt((p.x - v.x) ^ 2 + (p.z - v.z) ^ 2)
		t.truthy(d <= v.cruise * 0.2 + 0.5, `ghost lag {d} st`)
		-- codec round trip
		local rec = Ghost.encode({
			id = 7,
			x = 12.5,
			z = -3,
			yaw = -2.0,
			speed = 23.4,
			visible = true,
			beacons = true,
			teleported = true,
			stopped = false,
		})
		local back = Ghost.decode(BufferCodec.decode(Schemas.VehiclePose, BufferCodec.encode(Schemas.VehiclePose, rec)))
		t.near(back.yaw, -2.0, 2 * math.pi / 256)
		t.near(back.speed, 23.4, Ghost.SPEED_STEP)
		t.truthy(back.visible and back.beacons and back.teleported and not back.stopped)
		-- a teleported pose snaps
		local g = Ghost.new({ delay = 0 })
		g:push(0, {
			Ghost.encode({
				id = 1,
				x = 0,
				z = 0,
				yaw = 0,
				speed = 1,
				visible = true,
				beacons = false,
				teleported = false,
				stopped = false,
			}),
		})
		g:push(1, {
			Ghost.encode({
				id = 1,
				x = 100,
				z = 0,
				yaw = 0,
				speed = 1,
				visible = true,
				beacons = false,
				teleported = true,
				stopped = false,
			}),
		})
		t.near(g:sample(0.5)[1].x, 100, 1e-6, "teleport snaps")
		local h = Ghost.new({ delay = 0 })
		h:push(0, {
			Ghost.encode({
				id = 1,
				x = 0,
				z = 0,
				yaw = 0,
				speed = 1,
				visible = true,
				beacons = false,
				teleported = false,
				stopped = false,
			}),
		})
		h:push(1, {
			Ghost.encode({
				id = 1,
				x = 100,
				z = 0,
				yaw = 0,
				speed = 1,
				visible = true,
				beacons = false,
				teleported = false,
				stopped = false,
			}),
		})
		t.near(h:sample(0.5)[1].x, 50, 1e-4, "interpolates")
	end)

	-- Owner 2026-11-10: "some of the cars are glitching out".
	t.test(
		"ghost cars move evenly: the server's clock spaces the snapshots, a late send is carried over, cars pitch on slopes",
		function()
			local function rec(x: number, stopped: boolean?): { [string]: number }
				return Ghost.encode({
					id = 7,
					x = x,
					z = 0,
					yaw = math.pi / 2,
					speed = if stopped then 0 else 30,
					visible = true,
					beacons = false,
					teleported = false,
					stopped = stopped == true,
				})
			end
			-- the stamp survives the wire and is taken out of the records
			local wire =
				BufferCodec.decode(Schemas.VehiclePose, BufferCodec.encode(Schemas.VehiclePose, Ghost.stamp(1234.5)))
			local sentRecords = { rec(10), wire }
			t.near(Ghost.takeStamp(sentRecords) :: number, 1234.5, 1e-3)
			t.eq(#sentRecords, 1)
			t.eq(Ghost.takeStamp(sentRecords), nil, "a send without a stamp")
			-- the clock: packets sent every 1/15 s arrive with up to 40 ms of jitter; the local times are
			-- spaced as they were sent, to within a couple of milliseconds
			local clock = Ghost.newClock()
			local jitter = { 0.012, 0.04, 0.0, 0.031, 0.008, 0.039, 0.002, 0.02, 0.035, 0.0 }
			local last: number? = nil
			for i = 1, 60 do
				local sent = i / 15
				local local0 = clock:localTime(sent, 500 + sent + 0.05 + jitter[(i - 1) % #jitter + 1])
				if last and i > 3 then
					t.near(local0 - last, 1 / 15, 0.005, `send {i} is spaced as the server spaced it`)
				end
				last = local0
			end
			-- a car at 30 st/s, two snapshots 1/15 s apart; the next send is late
			local g = Ghost.new({ delay = 0.13 })
			g:push(100, { rec(0) })
			g:push(100 + 1 / 15, { rec(2) })
			local newest = 100 + 1 / 15
			t.near(g:sample(newest + 0.13)[7].x, 2, 1e-4, "exactly at the newest snapshot")
			local carried = g:sample(newest + 0.13 + 0.05)[7].x
			t.near(carried, 2 + 30 * 0.05, 0.05, "50 ms late: it carries on at its speed instead of freezing")
			local capped = g:sample(newest + 0.13 + 5)[7].x
			t.near(capped, 2 + 30 * Ghost.EXTRAPOLATE, 0.05, "and stops carrying on after EXTRAPOLATE")
			-- when the late send arrives the car is close to where it was drawn (no throw forward)
			g:push(100 + 3 / 15, { rec(6) })
			local after = g:sample(newest + 0.13 + 0.05 + 1 / 60)[7].x
			t.truthy(math.abs(after - carried) < 1.2, `a step of {after - carried} st on recovery`)
			-- a stopped car never creeps
			local h = Ghost.new({ delay = 0.13 })
			h:push(10, { rec(5, true) })
			h:push(10 + 1 / 15, { rec(5, true) })
			t.eq(h:sample(11)[7].x, 5)
			-- on a slope the car sits on the mean of its axle heights and pitches with the road
			local function hill(x: number, _z: number): number
				return x * 0.2
			end
			local y, pitch = Ghost.seat(10, 0, math.pi / 2, 11, hill) -- heading +x, uphill
			t.near(y, 2, 1e-6)
			t.near(pitch, math.atan(0.2), 1e-6, "nose up the hill")
			local _, down = Ghost.seat(10, 0, -math.pi / 2, 11, hill)
			t.near(down, -math.atan(0.2), 1e-6, "nose down going the other way")
			local flatY, flatPitch = Ghost.seat(3, 4, 1.1, 11, function(): number
				return 7
			end)
			t.eq(flatY, 7)
			t.eq(flatPitch, 0)
			-- across a slope, given its track, the car leans with the road: right side up when the ground
			-- rises to its right; level along the slope; a two-wheeler stays upright
			local _, sidePitch, roll = Ghost.seat(10, 0, 0, 11, hill, 4) -- heading +z: its right is -x
			t.near(sidePitch, 0, 1e-9)
			t.near(roll, -math.atan(0.2), 1e-6, "the ground falls to its right")
			local _, _, rollBack = Ghost.seat(10, 0, math.pi, 11, hill, 4)
			t.near(rollBack, math.atan(0.2), 1e-6, "heading -z, its right is +x: uphill")
			local _, _, untracked = Ghost.seat(10, 0, 0, 11, hill)
			t.eq(untracked, 0)
			t.eq(VehiclePuppet.track("motorcycle"), nil)
			t.truthy((VehiclePuppet.track("sedan") :: number) > 0)
			-- and the CFrame really lifts its right side: the seen pose's right wheel is on the ground
			local roblox = require("@lune/roblox")
			local lib = { CFrame = roblox.CFrame, Vector3 = roblox.Vector3 }
			local pose: any = { x = 10, z = 0, yaw = 0, visible = true }
			local x, sy, z, yaw, p, r = Ghost.seen(pose, "sedan", hill)
			local cf = Ghost.rootCFrame(lib, x, sy, z, yaw, p, true, r)
			local track = VehiclePuppet.track("sedan") :: number
			local wheel = cf * roblox.Vector3.new(track / 2, -VehiclePuppet.baseOffset("sedan"), 0)
			-- (the root turns about its centre, so its base slides a little sideways on a 11 degree crossfall)
			t.near(wheel.Y, hill(wheel.X, wheel.Z), 0.1, "the right wheel stands on the slope")
			local leftWheel = cf * roblox.Vector3.new(-track / 2, -VehiclePuppet.baseOffset("sedan"), 0)
			t.near(leftWheel.Y, hill(leftWheel.X, leftWheel.Z), 0.1, "and so does the left")
		end
	)
end
