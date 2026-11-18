--!strict
-- Scenario: every vehicle of a one-way lane placed 2 to 14 s short of its lane's end, so all eight reach
-- the end of their street in the first 15 s. In v5.4 each wrapped there (traffic.md §5.1, §5.5): it
-- vanished and reappeared at the other end of the street, in plain view, some seven times a minute across
-- the fleet. Now each turns round at the end of its street and drives back along the other side
-- (LaneMath.link, AICarMotor.advanceLane): nothing vanishes, nothing appears, and no two of them meet in
-- the turn.
local Fleet = require("@shared/Traffic/Fleet")
local Replay = require("../lib/Replay")

local entries = {}
for _, e in Fleet.ENTRIES do
	if e.class == "sedan" or e.class == "heavy" then
		table.insert(entries, e)
	end
end

local scenario: Replay.Scenario = {
	name = "lane_ends",
	about = "the eight one-way-lane vehicles 2 to 14 s short of their lanes' ends: eight U-turns in 30 s",
	seconds = 45,
	ci = 45,
	entries = entries,
	setup = function(sim: Replay.Sim)
		for i, v in sim.traffic.vehicles do
			v.speed = v.cruise
			v.s = v.lane.length - math.max(v.cruise, 10) * (2 + 1.5 * i)
		end
	end,
	expect = {
		none = {
			"speed_stutter",
			"sink",
			"float",
			"sim_jump_unflagged",
			"teleport_bit_dropped",
			"teleport_unflagged",
			"accel_spike",
			"teleport_flagged",
			"appear",
			"disappear",
			"box_overlap",
			"yaw_jump",
			"sim_yaw_snap",
			"sideways_slide",
			"reverse_travel",
			"off_road",
			"through_building",
			"speed_pumping",
		},
	},
}

return scenario
