--!strict
-- Scenario: the barbecue trio's whole cycle from a fresh server, and the start of its second cycle
-- (traffic.md §5.11; offset 0, so its first cycle starts the moment the server does). event_cars shows
-- the softball trio; this one covers the cycle start at boot and the wrap of the 2,400 s cycle.
-- The fleet clock is moved forward twice (the cars stand parked across the first move and hidden across
-- the second): at 60 s to 10 s before they leave, and at 135 s to 5 s before the second cycle.
-- Measured on the base tree: each car pops into view at its home spot (about 1,110 st inside the town)
-- and glides 35 st to its space at 0.73 st/s; on leaving it glides back and vanishes where it stands.
-- The glide itself is smooth; the pops are the port (AICarMotor stepClass.event: `visible` flips with
-- the cycle phase, no drive in or out).
local Fleet = require("@shared/Traffic/Fleet")
local Replay = require("../lib/Replay")

local entries = {}
for _, e in Fleet.byClass("event") do
	if e.offset == 0 then
		table.insert(entries, e)
	end
end

local scenario: Replay.Scenario = {
	name = "event_barbecue",
	about = "the barbecue trio appears at boot, parks, leaves and hides, then its second cycle starts",
	seconds = 160,
	ci = 145,
	entries = entries,
	frame = function(sim: Replay.Sim)
		if sim.wall >= 60 and not sim.state.leave then
			sim.state.leave = true
			sim.traffic.now = 590
		elseif sim.wall >= 135 and not sim.state.again then
			sim.state.again = true
			sim.traffic.now = 2395
		end
	end,
	expect = {
		none = {
			"teleport_unflagged",
			"sim_jump_unflagged",
			"speed_stutter",
			"accel_spike",
			"yaw_jump",
			"sideways_slide",
			"ghost_visibility",
			"sink",
			"float",
		},
	},
	known = { "appear", "disappear" },
}

return scenario
