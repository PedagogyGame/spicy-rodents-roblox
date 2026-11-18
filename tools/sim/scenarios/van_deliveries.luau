--!strict
-- Scenario: the ice cream van alone for several loops (traffic.md §5.3): it brakes into each of its two
-- stops on a sqrt(2 a d) profile, dwells 5.8, 6.8 or 7.8 s (deliveries mod 3) and pulls away again.
-- Five minutes covers seven deliveries, so the later cycles (the 6.8 and 7.8 s dwells, the second
-- time round each stop) are seen as well as the first.
-- Measured on the base tree (both fixed since: the van arrives when its braking profile reaches the stop,
-- and LaneMath gives loop lanes a dense arc-length table): each arrival ended in a jolt. The stop snaps when the van is within
-- max(0.35 u, speed x dt + 0.35 u) of it (0.875 st plus a tick's travel), where the braking profile still
-- allows about 4.7 st/s, so the van goes from about 5 st/s to a dead stop in one 30 Hz tick and hops the
-- last stretch (up to 0.97 st) in that tick (AICarMotor stepClass.van: `v.s = target; v.speed = 0`).
-- It also hitches twice a loop while cruising, at the two tips of the loop (s = 599.8 and 1249.6 st):
-- there a constant advance of s moves the van only 26 to 29 % as far on the ground for one tick (and
-- 20 % further just before), because Routes/Curve places it through three.js's 200-division arc-length
-- table, which is linear inside a division while the spline's own parameter speed is not near those
-- control points. On screen the van drops from 19 to about 10 st/s for a send interval and catches up.
local Fleet = require("@shared/Traffic/Fleet")
local Replay = require("../lib/Replay")

local scenario: Replay.Scenario = {
	name = "van_deliveries",
	about = "the ice cream van alone for about seven deliveries: every stop, dwell and pull-away",
	seconds = 300,
	ci = 45,
	entries = { Fleet.byClass("van")[1] },
	expect = {
		none = {
			"teleport_unflagged",
			"teleport_bit_dropped",
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
