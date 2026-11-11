--!strict
-- Scenario: the two motorcycles (traffic.md §5.12), alone, with their waits cut to two and four seconds:
-- each appears on the boulevard at full speed, rides to the end of its lane (about 35 s) and disappears.
local Fleet = require("@shared/Traffic/Fleet")
local Replay = require("../lib/Replay")

local scenario: Replay.Scenario = {
	name = "motorcycles",
	about = "both motorcycles appear on the boulevard (after 2 s and 4 s), ride its length and vanish",
	seconds = 44,
	ci = 44,
	entries = Fleet.byClass("motorcycle"),
	setup = function(sim: Replay.Sim)
		sim.traffic.byId[8].timer = 2
		sim.traffic.byId[11].timer = 4
	end,
	expect = {
		none = { "teleport_unflagged", "sim_jump_unflagged", "speed_stutter", "reverse_travel", "sideways_slide" },
	},
	known = { "appear", "disappear" },
}

return scenario
