--!strict
-- Scenario: a motorcycle comes up behind slower traffic. Each motorcycle pulls out from the kerb with a
-- sedan and a heavy vehicle a little way ahead of it on its way round the boulevard (traffic.md §5.12:
-- v5.4's riders stopped only for people). Does it follow, or ride through them?
local Fleet = require("@shared/Traffic/Fleet")
local LaneMath = require("@shared/Traffic/LaneMath")
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
	about = "each motorcycle pulls out behind a sedan and a heavy vehicle on its way round the boulevard",
	seconds = 60,
	ci = 60,
	entries = { entry(6), entry(7), entry(8), entry(9), entry(10), entry(11) },
	setup = function(sim: Replay.Sim)
		local t = sim.traffic
		local function at(id: number, x: number)
			local v = t.byId[id]
			v.s = LaneMath.arcOf(v.lane, x, v.z, v.dir)
		end
		-- Morgan Rider pulls out at x = 740 on the westbound side, turns at the west end and rides east:
		-- the eastbound sedan and the dump truck are just ahead of it there
		t.byId[8].timer = 0.5
		at(6, 760)
		at(7, 880)
		-- Alex Rider pulls out at x = 1625, westbound: the westbound sedan and the RV ahead of it
		t.byId[11].timer = 0.5
		at(9, 1560)
		at(10, 1440)
	end,
	-- they rode straight through both (3.8 st deep); now they settle in behind at the leader's speed
	expect = {
		none = {
			"speed_stutter",
			"sink",
			"float",
			"sideways_slide",
			"box_overlap",
			"accel_spike",
			"appear",
			"disappear",
			"speed_pumping",
		},
	},
}

return scenario
