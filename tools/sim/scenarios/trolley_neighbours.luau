--!strict
-- Scenario: the eastbound boulevard traffic beside the trolley (Sedan EB, Dump truck EB and the trolley,
-- alone): what a car does when "something ahead" is the trolley on its own track one lane over.
-- Measured on the base tree (10 minutes of the fleet scenario: Sedan EB held by the trolley 32.8 s in
-- 115 episodes, Dump truck EB 26.3 s in 11). The lane now keeps clear of the track (LaneMath.unify,
-- RAIL_CLEARANCE): nobody waits for the trolley and nothing overlaps it; the sedan still lurches behind
-- the dump truck.
--   * both brake, stop dead and wait for the trolley although it is not in their lane. The trolley runs
--     at z = 21.6 st, the eastbound lane at z = 14 (7.6 st apart), and LaneMath.vehicleAhead's corridor
--     is halfWidth + the other's width / 2 + 0.5 st wide: 3 + 4.4 + 0.5 = 7.9 st for the sedan, 9.1 st
--     for the dump truck, so the trolley is always "in the lane ahead". Its yaw is fixed at pi / 2
--     (AICarMotor stepClass.trolley), so sameWay counts it even when it drives west, towards them.
--   * the sedan lurches behind it: its look-ahead (9 u + 0.65 x speed) shrinks as it brakes, the trolley
--     drops out of it, it accelerates, the trolley is back in it, and so on, tick after tick
--     (speed_pumping, from detectors/pumping.luau)
--   * the dump truck and the trolley overlap by 0.94 st when side by side: the two bodies are 8.4 and
--     8.75 st wide on centrelines 7.6 st apart
local Fleet = require("@shared/Traffic/Fleet")
local Replay = require("../lib/Replay")

local entries = {}
for _, e in Fleet.ENTRIES do
	if e.id == 6 or e.id == 7 or e.id == 13 then
		table.insert(entries, e)
	end
end

local scenario: Replay.Scenario = {
	name = "trolley_neighbours",
	about = "Sedan EB and Dump truck EB in the eastbound lane beside the trolley on its own track",
	seconds = 120,
	ci = 120,
	entries = entries,
	expect = { none = { "speed_stutter", "reverse_travel", "sink", "float", "box_overlap" } },
	known = { "speed_pumping" },
}

return scenario
