--!strict
-- Scenario: the patrol car alone over two whole round trips of its beat (x = 55 to 645 u on the z = 0
-- road and the boulevard; traffic.md §5.7: it shuttles between the ends and turns round at each). Both
-- ends, both directions, the boulevard stop lines both ways.
local Fleet = require("@shared/Traffic/Fleet")
local Replay = require("../lib/Replay")

local scenario: Replay.Scenario = {
	name = "patrol_beat",
	about = "the patrol car alone for two round trips of its beat: both turns, both directions, both stop lines",
	seconds = 260,
	ci = 130,
	entries = { Fleet.byClass("patrol")[1] },
	-- it turned round by jumping the whole beat and drove the next leg backwards (LaneMath.pingPong measured
	-- s from the wrong end); now it drives a 14 st U-turn onto the other side of the road
	expect = {
		none = {
			"speed_stutter",
			"sink",
			"float",
			"teleport_bit_dropped",
			"off_road",
			"through_building",
			"sim_jump_unflagged",
			"sim_yaw_snap",
			"teleport_unflagged",
			"reverse_travel",
			"yaw_jump",
			"sideways_slide",
			"accel_spike",
		},
	},
}

return scenario
