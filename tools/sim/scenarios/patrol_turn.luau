--!strict
-- Scenario: the patrol car alone, 80 studs short of the east end of its beat (traffic.md §5.7: it
-- shuttles between the ends and turns round there). What does the turn look like?
local Fleet = require("@shared/Traffic/Fleet")
local Replay = require("../lib/Replay")

local scenario: Replay.Scenario = {
	name = "patrol_turn",
	about = "the patrol car 80 st short of the east end of its beat: it turns round after about 3 s",
	seconds = 14,
	ci = 14,
	entries = { Fleet.byClass("patrol")[1] },
	setup = function(sim: Replay.Sim)
		local v = sim.traffic.byId[12]
		v.s = v.lane.length - 80
		v.speed = v.cruise
	end,
	expect = {
		none = {
			"speed_stutter",
			"sink",
			"float",
			"teleport_bit_dropped",
			"sim_jump_unflagged",
			"sim_yaw_snap",
			"teleport_unflagged",
			"reverse_travel",
			"yaw_jump",
		},
	},
}

return scenario
