--!strict
-- Scenario: every vehicle that drives a lane by itself (not the dispatched responders and incident cars),
-- for a whole 2,400 s living-event cycle, on a town with nobody on the roads. At the fleet's speeds this
-- is 15 to 60 laps of every one-way lane and its wrap, 40 round trips of the patrol beat, 30 loops of the
-- ice cream van, 70 trolley stations, 25 motorcycle rides, 9 legacy ambulance runs and both event-car
-- cycles (barbecue at 0 s, softball at 1,200 s): every straight, corner, U-turn, stop and lane end the
-- fleet uses, several times over. The geometry hunt's coverage run (`--scenario lane_tour`).
local Fleet = require("@shared/Traffic/Fleet")
local Replay = require("../lib/Replay")

local entries = {}
for _, e in Fleet.ENTRIES do
	if e.class ~= "responder" and e.class ~= "incident" then
		table.insert(entries, e)
	end
end

local scenario: Replay.Scenario = {
	name = "lane_tour",
	about = "every lane-driving vehicle for a whole 2,400 s event cycle: every straight, corner, stop and lane end",
	seconds = 2400,
	entries = entries,
	expect = {
		none = {
			"position_jump",
			"speed_stutter",
			"height_jump",
			"pitch_jump",
			"sink",
			"float",
			"tilt_mismatch",
			"roll_missing",
			"off_road",
			"through_building",
			-- fixed in this round: the patrol car's turn, the polyline corners, the van and trolley stops,
			-- the van's U-turn speed, wraps that streaked, motorcycles and the trolley inside other cars
			"box_overlap",
			"teleport_unflagged",
			"teleport_bit_dropped",
			"sim_jump_unflagged",
			"sim_yaw_snap",
			"yaw_jump",
			"reverse_travel",
			"sideways_slide",
		},
	},
}

return scenario
