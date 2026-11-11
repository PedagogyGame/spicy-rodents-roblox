--!strict
-- Scenario: a motorcycle comes up behind slower traffic. Each motorcycle appears on its boulevard lane
-- with a sedan and a heavy vehicle a little way ahead of it (traffic.md §5.12: riders stop only for
-- people). Does it follow, or ride through them?
local Fleet = require("@shared/Traffic/Fleet")
local Replay = require("../lib/Replay")

local function entry(id: number): any
	for _, e in Fleet.ENTRIES do
		if e.id == id then
			return e
		end
	end
	error(`no fleet entry {id}`)
end

local scenario: Replay.Scenario = {
	name = "motorcycle_follow",
	about = "each motorcycle appears behind a sedan and a heavy vehicle on its boulevard lane",
	seconds = 40,
	ci = 40,
	entries = { entry(6), entry(7), entry(8), entry(9), entry(10), entry(11) },
	setup = function(sim: Replay.Sim)
		local t = sim.traffic
		-- eastbound: Morgan Rider appears at 296 u; the sedan and the dump truck ahead of it
		t.byId[8].timer = 0.5
		t.byId[6].s = t.byId[8].spawnS + 40
		t.byId[7].s = t.byId[8].spawnS + 160
		-- westbound: Alex Rider appears at 650 u
		t.byId[11].timer = 0.5
		t.byId[9].s = t.byId[11].spawnS + 40
		t.byId[10].s = t.byId[11].spawnS + 160
	end,
	expect = { none = { "speed_stutter", "sink", "float", "sideways_slide" } },
	known = { "box_overlap" },
}

return scenario
