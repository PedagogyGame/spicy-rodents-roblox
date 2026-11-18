--!strict
-- Scenario: the legacy ambulance's whole cycle, twice (traffic.md §5.8): it appears at the east end of
-- the north arterial (wait cut from 18 s to 2 s), drives the arterial west at full speed, turns the
-- square corner into the hospital drive, parks for 16 s and hides; its 145 s wait is then cut to 3 s so
-- the second run is seen as well.
-- Now: it stands parked in view at its kerbside bay by the hospital, pulls out, drives the arterial to
-- its far end, turns round, comes back and pulls in to the same bay (two rounds here: its 161 s wait is
-- cut short). Measured on the base tree, the same on both runs:
--   * it pops into view at (1,598, 700), about 410 st inside the town, already at 31 st/s (AICarMotor
--     stepClass.legacy_ambulance: appear at s = 0, drivePolyline sets `v.speed = speed` at once)
--   * at the corner the server turns it 90 degrees in one tick (polyline legs, `place` takes the leg's
--     heading); clients spin it over one send interval while it moves diagonally across the corner
--   * it arrives at the end of the drive at 26.6 st/s and is parked the next tick: a dead stop
--   * after 16 s parked it vanishes where it stands at (-898, 738), about 370 st inside the town
local Fleet = require("@shared/Traffic/Fleet")
local Replay = require("../lib/Replay")

local scenario: Replay.Scenario = {
	name = "ambulance_life",
	about = "the legacy ambulance appears, drives the arterial, turns into the hospital drive, parks, hides, and does it again",
	seconds = 400,
	ci = 200,
	entries = Fleet.byClass("legacy_ambulance"),
	setup = function(sim: Replay.Sim)
		sim.traffic.byId[14].timer = 2
	end,
	frame = function(sim: Replay.Sim)
		local v = sim.traffic.byId[14]
		if v.phase == "idle" and v.timer > 100 and sim.wall > 60 and not sim.state.second then
			sim.state.second = true
			v.timer = 3
		end
	end,
	expect = {
		none = {
			"teleport_unflagged",
			"sim_jump_unflagged",
			"reverse_travel",
			"speed_stutter",
			"sink",
			"float",
			"sim_yaw_snap",
			"yaw_jump",
			"accel_spike",
			"appear",
			"disappear",
			"teleport_flagged",
			"off_road",
			"through_building",
			"box_overlap",
		},
	},
}

return scenario
