--!strict
-- Scenario: the legacy ambulance (traffic.md §5.8), alone, forced onto its route 400 studs before the
-- end: it runs down the arterial, turns the square corner into the hospital drive, parks for 16 s and
-- hides. The corner is a polyline vertex: what does a 90 degree turn at a point look like?
local Fleet = require("@shared/Traffic/Fleet")
local Replay = require("../lib/Replay")

local scenario: Replay.Scenario = {
	name = "ambulance_corner",
	about = "the legacy ambulance 400 st before the end of its route: the square corner, the park, the hide",
	seconds = 36,
	ci = 20,
	entries = Fleet.byClass("legacy_ambulance"),
	setup = function(sim: Replay.Sim)
		local v = sim.traffic.byId[14]
		v.phase, v.visible, v.dir, v.timer = "drive", true, 1, 0
		v.s = v.lane.length - 400
	end,
	expect = { none = { "sim_jump_unflagged", "teleport_unflagged", "speed_stutter", "sink", "float" } },
	known = { "sim_yaw_snap", "yaw_jump" },
}

return scenario
