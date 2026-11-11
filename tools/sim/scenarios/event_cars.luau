--!strict
-- Scenario: the six living-event sedans (traffic.md §5.11), alone. Their 2,400 s cycle is far longer than
-- a replay, so the fleet's clock is set forward: the softball trio sets off ten seconds in and glides to
-- its spaces over 48 s; at 70 s the clock is moved on again (the cars stand parked on both sides of the
-- move) to fifteen seconds before they leave and glide back over 50 s. Between events every car stands
-- parked at its home spot (v5.4 hid it there: three cars popping in side by side, and out again).
local Fleet = require("@shared/Traffic/Fleet")
local Replay = require("../lib/Replay")

local scenario: Replay.Scenario = {
	name = "event_cars",
	about = "the six event sedans: the softball trio drives to its event, parks, and drives home (the fleet clock is moved forward twice)",
	seconds = 145,
	ci = 145,
	entries = Fleet.byClass("event"),
	setup = function(sim: Replay.Sim)
		sim.traffic.now = 1190 -- the softball cars' cycle starts at 1,200 s
	end,
	frame = function(sim: Replay.Sim)
		if sim.wall >= 70 and not sim.state.moved then
			sim.state.moved = true
			sim.traffic.now = 1785 -- parked; they leave at 1,800 s
		end
	end,
	expect = {
		none = {
			"appear",
			"disappear",
			"teleport_flagged",
			"teleport_unflagged",
			"sim_jump_unflagged",
			"position_jump",
			"speed_stutter",
			"accel_spike",
			"yaw_jump",
			"sideways_slide",
			"box_overlap",
			"through_building",
		},
	},
}

return scenario
