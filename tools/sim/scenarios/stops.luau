--!strict
-- Scenario: the two vehicles that run to a timetable, alone: the ice cream van round its loop with its
-- two delivery stops and two U-turns (traffic.md §5.3), and the trolley shuttling along its track between
-- stations (§5.4). Braking into a stop, the dwell, pulling away, the turns.
local Fleet = require("@shared/Traffic/Fleet")
local Replay = require("../lib/Replay")

local scenario: Replay.Scenario = {
	name = "stops",
	about = "the ice cream van (a full loop: two stops, two U-turns) and the trolley (its stations), alone",
	seconds = 110,
	ci = 30,
	entries = { Fleet.byClass("van")[1], Fleet.byClass("trolley")[1] },
	expect = {
		-- both used to stop dead from 9 to 14 st/s (a snap over the last 0.25 to 0.35 u), and the van surged and
		-- dragged by up to 74 % around its U-turns (a 200-division arc table)
		none = {
			"teleport_unflagged",
			"teleport_bit_dropped",
			"speed_stutter",
			"reverse_travel",
			"sink",
			"float",
			"accel_spike",
			"sim_jump_unflagged",
			"position_jump",
		},
	},
}

return scenario
