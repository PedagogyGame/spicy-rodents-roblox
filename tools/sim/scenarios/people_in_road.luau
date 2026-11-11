--!strict
-- Scenario: the game's 25 vehicles and townspeople who stop in the middle of a lane for a while (a
-- player's human standing in the road, a crowd round an accident, someone chatting on the crossing).
-- One person on every lane a fleet vehicle drives: every 40 s (staggered) they walk in from the kerb on
-- the lane's right (10 st out, at 4 st/s), stand on the lane's centre line for 8 s and walk back; on the
-- boulevard lanes the patrol car's beat passes them too. Which vehicles stop short of the person, and which drive into or through them (the
-- meetings detector's through_person)?
local Height = require("@shared/World/Height")
local LaneMath = require("@shared/Traffic/LaneMath")
local Replay = require("../lib/Replay")

-- lane id, how far along (0..1 of its length, in its travel direction), when the first stand starts
-- stylua: ignore
local SPOTS = {
	{ "res_main_ns_northbound", 0.58, 5 },
	{ "res_main_ns_southbound", 0.33, 10 },
	{ "res_west_ns_x-180_northbound", 0.6, 15 },
	{ "blvd_eastbound", 0.62, 20 },
	{ "blvd_westbound", 0.45, 25 },
	{ "trolley_track", 0.75, 30 },
	{ "north_arterial_legacy_ambulance", 0.3, 35 },
}
local EVERY, HOLD, KERB, WALK = 40, 8, 10, 4

local scenario: Replay.Scenario = {
	name = "people_in_road",
	about = "the 25 vehicles and one person walking out to stand in every lane for 8 s of every 40 s",
	seconds = 600,
	ci = 60,
	setup = function(sim: Replay.Sim)
		local spots = {}
		for i, s in SPOTS do
			local lane = sim.traffic.lanes[s[1]]
			local dir = if lane.dir == 0 then 1 else lane.dir
			local p = LaneMath.pointAt(lane, LaneMath.length(lane, dir) * s[2], dir)
			-- the kerb on the right of the travel direction (drive on the right: the outer side)
			local rx, rz = -math.cos(p.yaw), math.sin(p.yaw)
			table.insert(spots, { id = `person_{i}`, x = p.x, z = p.z, kx = rx * KERB, kz = rz * KERB, start = s[3] })
		end
		sim.state.spots = spots
	end,
	world = function(sim: Replay.Sim): any
		local people = {}
		for _, s in sim.state.spots do
			local t = sim.wall - s.start
			if t >= 0 then
				local walk = KERB / WALK
				local u = t % EVERY
				local out = nil -- 1: at the kerb, 0: on the centre line
				if u < walk then
					out = 1 - u / walk
				elseif u < walk + HOLD then
					out = 0
				elseif u < 2 * walk + HOLD then
					out = (u - walk - HOLD) / walk
				end
				if out then
					local x, z = s.x + s.kx * out, s.z + s.kz * out
					table.insert(people, { id = s.id, x = x, y = Height.at(x, z), z = z, kind = "human" })
				end
			end
		end
		return { people = people, squirrels = {} }
	end,
}

return scenario
