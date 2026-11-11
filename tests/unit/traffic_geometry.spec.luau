--!strict
-- Vehicle glitches found by driving every lane (tools/sim scenarios lane_tour, patrol_beat, lane_ends,
-- stops, trolley_alongside, motorcycle_follow, ambulance_corner): each case pins the fix on the server's
-- own state, tick by tick, so it holds without the replay.
local LaneMath = require("@shared/Traffic/LaneMath")
local Fleet = require("@shared/Traffic/Fleet")
local TrafficService = require("@server/Traffic/TrafficService")

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
end
