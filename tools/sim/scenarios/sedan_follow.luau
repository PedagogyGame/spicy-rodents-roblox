--!strict
-- Scenario: a sedan catching up with a vehicle stopped in its lane: Sedan SB and the ice cream van alone.
-- The van's loop runs in the main street's lanes and it dwells at its stops there (traffic.md §5.3), so
-- Sedan SB comes up behind it parked at (15, 183) about 50 s in, and waits until it pulls away.
-- Measured on the base tree: the sedan does not brake to a halt behind it, it lurches up to it. For
-- about 3 s its speed goes down and up on alternate ticks (26 reversals in 2 s; 11 -> 0 st/s) before it
-- settles. Mechanism (AICarMotor stepClass.sedan, the v5.4 rule): any vehicle within the look-ahead
-- 9 u + 0.65 x speed sets the desired speed to 0 (brake at rate 9); braking shortens that look-ahead
-- until the van drops out of it, the desired speed jumps back to cruise (rate 1.3), the look-ahead grows
-- and the van is back in it: a bang-bang limit cycle at the tick rate. The same happens behind the
-- trolley (trolley_neighbours) and behind any slower vehicle.
local Fleet = require("@shared/Traffic/Fleet")
local Replay = require("../lib/Replay")

local entries = {}
for _, e in Fleet.ENTRIES do
	if e.id == 2 or e.id == 5 then
		table.insert(entries, e)
	end
end

local scenario: Replay.Scenario = {
	name = "sedan_follow",
	about = "Sedan SB comes up behind the ice cream van dwelling at its stop in the southbound lane",
	seconds = 70,
	ci = 60,
	entries = entries,
	setup = function(sim: Replay.Sim)
		-- the van dwells at its south-heading stop from 48.8 s to 55.6 s: start the sedan 124 st (6 s)
		-- further back than its spawn, so that it comes up behind the van while it stands there
		local v = sim.traffic.byId[2]
		v.s -= 124
	end,
	expect = { none = { "speed_stutter", "reverse_travel", "box_overlap", "sink", "float" } },
	known = { "speed_pumping" },
}

return scenario
