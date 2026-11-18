--!strict
-- Scenario: the two motorcycles (traffic.md §5.12), alone, with their waits cut to two and four seconds.
-- In v5.4 each appeared in the middle of the boulevard at full speed, rode to the end of its lane (about
-- 35 s) and vanished there. Now each stands parked at the kerb between rides, pulls out, rides once
-- round the boulevard (a turn at each end) and pulls in where it started: two rides each in 200 s, and
-- nothing pops in or out.
local Fleet = require("@shared/Traffic/Fleet")
local Replay = require("../lib/Replay")

local scenario: Replay.Scenario = {
	name = "motorcycles",
	about = "both motorcycles pull out from the kerb (after 2 s and 4 s), ride round the boulevard and park again",
	seconds = 200,
	ci = 100,
	entries = Fleet.byClass("motorcycle"),
	setup = function(sim: Replay.Sim)
		sim.traffic.byId[8].timer = 2
		sim.traffic.byId[11].timer = 4
	end,
	expect = {
		none = {
			"teleport_unflagged",
			"sim_jump_unflagged",
			"speed_stutter",
			"reverse_travel",
			"sideways_slide",
			"appear",
			"disappear",
			"teleport_flagged",
			"yaw_jump",
			"sim_yaw_snap",
			"accel_spike",
			"position_jump",
			"box_overlap",
			"buried",
			"through_building",
		},
	},
}

return scenario
