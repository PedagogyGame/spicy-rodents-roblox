--!strict
-- Scenario: every vehicle that wraps (the one-way lanes' v5.4 teleport, traffic.md §5.1, §5.5) placed
-- 2 to 5 s short of its lane's end, so all eight wraps happen in the first seconds: where does the car
-- vanish, where does it reappear, and does the client snap it or streak it across?
local Fleet = require("@shared/Traffic/Fleet")
local Replay = require("../lib/Replay")

local entries = {}
for _, e in Fleet.ENTRIES do
	if e.class == "sedan" or e.class == "heavy" then
		table.insert(entries, e)
	end
end

local scenario: Replay.Scenario = {
	name = "lane_ends",
	about = "the eight wrapping vehicles 2 to 5 s short of their lanes' ends: eight wraps in a few seconds",
	seconds = 12,
	ci = 12,
	entries = entries,
	setup = function(sim: Replay.Sim)
		for i, v in sim.traffic.vehicles do
			v.speed = v.cruise
			v.s = v.lane.length - math.max(v.cruise, 10) * (2 + 0.4 * i)
		end
	end,
	expect = { none = { "speed_stutter", "sink", "float", "sim_jump_unflagged" }, some = { "teleport_flagged" } },
	known = { "teleport_bit_dropped", "teleport_unflagged" },
}

return scenario
