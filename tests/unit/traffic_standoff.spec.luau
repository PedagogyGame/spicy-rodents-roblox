--!strict
-- The corner standoff (found by tests/unit/infection_service.spec's chaos run, seed 1, once the town's people no longer
-- ran from ordinary squirrels and its timeline changed): a responder on its way home, turning left out of the hospital
-- road's side street across the boulevard's westbound lane, and a sedan in that lane. The sedan stops behind the
-- ambulance (it is six studs ahead of the sedan along the sedan's heading); the ambulance, part-way round its turn, took
-- the sedan for a vehicle ahead on its route (the sedan's centre a stud ahead of its own along its own heading, and
-- heading the way the route is about to). Each waited for the other for good, and the second responder, a lorry, an RV,
-- the patrol car and a rider queued up behind them for the rest of the session.
-- Shared/Traffic/AICarMotor.leads: of two vehicles that each have the other's centre ahead, the one further ahead of
-- the other leads, and only the other waits. Here: the rule, and the jam as it stood (every vehicle where the chaos
-- run left it, on the real lanes), clearing.
local Data = require("@shared/Data")
local Height = require("@shared/World/Height")
local AICarMotor = require("@shared/Traffic/AICarMotor")
local LaneMath = require("@shared/Traffic/LaneMath")
local TrafficService = require("@server/Traffic/TrafficService")

local DT = 1 / 30

-- the jam (infection_service chaos seed 1, 60 s after everyone was cured): the lane vehicles ...
local LANE = {
	{ id = 6, lane = "blvd_westbound", dir = -1, s = 720.333, x = 952.167, z = -14, yaw = -math.pi / 2 },
	{ id = 7, lane = "blvd_westbound", dir = -1, s = 742.020, x = 930.480, z = -14, yaw = -math.pi / 2 },
	{ id = 9, lane = "blvd_westbound", dir = -1, s = 805.591, x = 866.909, z = -14, yaw = -math.pi / 2 },
	{ id = 10, lane = "blvd_eastbound", dir = 1, s = 127.057, x = 804.557, z = 12.75, yaw = math.pi / 2 },
	{ id = 12, lane = "patrol_beat", dir = 1, s = 642.391, x = 779.891, z = 12.75, yaw = math.pi / 2 },
}
-- ... and the two responders on their way back (the way back's corner points, and how far along it each stood)
local BACK = {
	[15] = {
		s = 460.412,
		x = 862.5,
		z = -33.588,
		yaw = 0,
		pts = {
			{ 862.5, -494 },
			{ 862.5, -5 },
			{ -455, -5 },
			{ -455, 702.5 },
			{ -890, 702.5 },
			{ -954, 702.5 },
			{ -954, 712.5 },
			{ -945, 712.5 },
			{ -927, 719 },
			{ -924, 719 },
		},
	},
	[16] = {
		s = 476.709,
		x = 861.033,
		z = -17.480,
		yaw = -0.3855,
		pts = {
			{ 862.5, -494 },
			{ 862.5, -5 },
			{ -455, -5 },
			{ -455, 702.5 },
			{ -890, 702.5 },
			{ -992, 702.5 },
			{ -992, 712.5 },
			{ -983, 712.5 },
			{ -965, 719 },
			{ -962, 719 },
		},
	},
}

return function(t)
	local data = Data.default()

	t.test("who leads: of two that each have the other's centre ahead, the one further ahead of the other", function()
		local function car(id: number, x: number, z: number, yaw: number): any
			return { id = id, x = x, z = z, yaw = yaw, width = 5.875, length = 11.125 }
		end
		-- the corner: the ambulance turning left across the sedan's nose
		local ambulance, sedan = car(16, 861.033, -17.48, -0.3855), car(9, 866.909, -14, -math.pi / 2)
		local aheadOfAmbulance = (sedan.x - ambulance.x) * math.sin(ambulance.yaw)
			+ (sedan.z - ambulance.z) * math.cos(ambulance.yaw)
		local aheadOfSedan = (ambulance.x - sedan.x) * math.sin(sedan.yaw)
			+ (ambulance.z - sedan.z) * math.cos(sedan.yaw)
		t.truthy(aheadOfAmbulance > 0 and aheadOfSedan > 0, "each has the other's centre ahead")
		t.truthy(
			AICarMotor.leads(ambulance, sedan, aheadOfAmbulance),
			"the ambulance leads: it is six studs ahead of the sedan"
		)
		t.falsy(AICarMotor.leads(sedan, ambulance, aheadOfSedan), "and the sedan does not: it waits")
		-- one behind another in a lane: the one in front leads, the one behind never does
		local front, behind = car(1, 0, 20, 0), car(2, 0, 0, 0)
		t.falsy(AICarMotor.leads(behind, front, 20), "a follower waits for the one ahead, as ever")
		-- the same distance each way: the lower id
		local a, b = car(3, 0, 0, 0), car(4, 5, 5, -math.pi / 2)
		t.truthy(AICarMotor.leads(a, b, 5))
		t.falsy(AICarMotor.leads(b, a, 5))
		-- a player's car waits for nobody: nobody leads it
		local player = car(5, 866.909, -14, -math.pi / 2)
		player.player = true
		t.falsy(AICarMotor.leads(ambulance, player, aheadOfAmbulance))
	end)

	t.test("the jam as it stood clears: both responders drive home, the street behind them moves again", function()
		local traffic =
			TrafficService.new({ lanes = data:lanes(), roads = data:roads(), heightAt = Height.at, seed = 7 })
		for _, v in traffic.vehicles do
			v.visible = false -- (only the jam's own vehicles: the rest of the fleet is parked out of it)
			v.phase = if v.class == "responder" or v.class == "incident" then "idle" else v.phase
		end
		local byId = traffic.byId
		for _, j in LANE do
			local v = byId[j.id]
			local lane = traffic.lanes[j.lane]
			t.truthy(lane ~= nil, j.lane)
			v.lane, v.dir, v.s, v.speed, v.phase, v.visible = lane, j.dir, j.s, 0, "drive", true
			v.x, v.z, v.yaw = j.x, j.z, j.yaw
			local p = LaneMath.pointAt(lane, j.s, j.dir)
			t.near(p.x, j.x, 0.05, `{v.name} stands where the run left it`)
			t.near(p.z, j.z, 0.05)
		end
		for id, j in BACK do
			local v = byId[id]
			local fwd = {}
			for i = #j.pts, 1, -1 do
				table.insert(fwd, j.pts[i])
			end
			local back = LaneMath.poly(j.pts)
			local route = LaneMath.makeRoute(`responder_{id}`, fwd, v.lane.speeds, 0)
			route.polyRev = back
			v.route, v.dir, v.s, v.speed, v.phase, v.visible = route, -1, j.s, 0, "back", true
			v.held, v.blocked, v.timer = false, 0, 0
			local p = LaneMath.pointAt(route, j.s, -1)
			t.near(p.x, j.x, 0.05, `{v.name} stands where the run left it`)
			t.near(p.z, j.z, 0.05)
			t.near(p.yaw, j.yaw, 0.01)
			v.x, v.z, v.yaw = p.x, p.z, p.yaw
		end
		local r1, r2, sedan = byId[15], byId[16], byId[9]
		local sx = sedan.x
		for _ = 1, 10 * 30 do
			traffic:step(DT, {})
		end
		local moved = math.sqrt((r2.x - 861.033) ^ 2 + (r2.z + 17.48) ^ 2)
		t.truthy(moved > 20, `ten seconds on, the ambulance in the corner has driven on ({moved} studs)`)
		t.truthy(sx - sedan.x > 10, `and the sedan behind it ({sx - sedan.x} studs)`)
		-- no two of them ever inside each other on the way out of it
		local home = false
		for _ = 1, 240 * 30 do
			traffic:step(DT, {})
			if r1.phase == "idle" and r2.phase == "idle" then
				home = true
				break
			end
		end
		t.truthy(home, `both responders are home (Responder 1 {r1.phase}, Responder 2 {r2.phase})`)
		t.truthy(byId[7].speed > 0 or math.abs(byId[7].x - 930.48) > 50, "the lorry that queued behind them drives")
	end)
end
