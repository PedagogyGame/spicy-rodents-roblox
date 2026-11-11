--!strict
-- Scenario: the trolley alone for two rounds of its timetable (traffic.md §5.4: x = 283, 310, 465, 616,
-- 657, 616, 465, 310 and back, dwelling 2.3 s at the termini and 4.2 s at stations). Every arrival,
-- every departure and every change of direction at a terminus, twice.
-- Measured on the base tree (fixed since: it arrives when the profile has brought it in): every arrival
-- ended in a jolt. The trolley brakes on a sqrt(2 a d) profile
-- but snaps to the station once within 0.25 u (0.625 st), where that profile still allows about
-- 4.4 st/s, so it stops dead from about 5 st/s in one 30 Hz tick and hops the last half stud
-- (AICarMotor stepClass.trolley: `x = destX; v.speed = 0`).
local Fleet = require("@shared/Traffic/Fleet")
local Replay = require("../lib/Replay")

local scenario: Replay.Scenario = {
	name = "trolley_schedule",
	about = "the trolley alone for two rounds of its timetable: 16 arrivals and departures",
	seconds = 220,
	ci = 20,
	entries = { Fleet.byClass("trolley")[1] },
	expect = {
		none = {
			"teleport_unflagged",
			"sim_jump_unflagged",
			"speed_stutter",
			"reverse_travel",
			"yaw_jump",
			"sideways_slide",
			"sink",
			"float",
			"accel_spike",
		},
	},
}

return scenario
