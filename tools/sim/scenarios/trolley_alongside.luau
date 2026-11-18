--!strict
-- Scenario: the eastbound dump truck drives past the trolley. Under drive-on-the-right (owner decision 9)
-- the boulevard's eastbound lane is z = +5.6 u, the side the trolley track runs on (z = 8.65 u, rails at
-- 7.38 / 9.92): a 3.35 u dump truck there reaches z = 7.275 u, a 3.5 u trolley reaches down to 6.9 u.
-- The truck starts 60 st behind the trolley, which leaves its first station after a 2 s wait.
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
	name = "trolley_alongside",
	about = "the eastbound dump truck overtakes the trolley on the boulevard (the trolley track is in its lane)",
	seconds = 30,
	ci = 30,
	entries = { entry(13), entry(7) },
	setup = function(sim: Replay.Sim)
		local truck = sim.traffic.byId[7]
		local trolley = sim.traffic.byId[13]
		truck.s = math.max(0, trolley.x - truck.lane.startAt - 60)
		truck.speed = truck.cruise
		trolley.phase, trolley.timer = "dwell", 2
	end,
	-- the truck used to pass 0.94 st inside the trolley; the lane now keeps LaneMath.RAIL_CLEARANCE from the rails
	expect = { none = { "speed_stutter", "sink", "float", "box_overlap" } },
}

return scenario
