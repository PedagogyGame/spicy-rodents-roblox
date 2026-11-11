--!strict
-- Scenario: two sedans, each a few seconds short of the end of its one-way lane, on lanes with no way
-- back, as v5.4 drove them (in the game every street has one, LaneMath.link, and the sedans turn round:
-- see lane_ends; here the link is taken away). Each reaches the end and wraps to the start (the v5.4
-- teleport, traffic.md §5.1): 1,300 studs in one tick, flagged for that tick. It keeps the flagged
-- teleport measured from the service to the screen, which a dispatch still relies on.
-- The smallest case of "does a wrap reach the client as a snap or as a streak": the northbound
-- sedan wraps on a tick that is not followed by a send, the southbound one on a tick that is. The
-- service remembers a jump until the next send carries it (TrafficService.jumped), so both snap.
-- This file is also the pattern to copy for a focused case: pick the vehicles, force their state in
-- `setup`, and say what must hold.
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
	name = "sedan_wrap",
	about = "two sedans about 60 st short of their lanes' ends: each wraps to the start after about 3 s",
	seconds = 12,
	ci = 12,
	entries = { entry(1), entry(2) },
	setup = function(sim: Replay.Sim)
		-- sim.traffic is the real TrafficService; a vehicle's lane position is `s` (studs from the start)
		local north, south = sim.traffic.byId[1], sim.traffic.byId[2]
		north.lane.returnLane, south.lane.returnLane = nil, nil
		north.s = north.lane.length - 62
		north.speed = north.cruise
		south.s = south.lane.length - 62
		south.speed = south.cruise
	end,
	-- holds today and must keep holding (the northbound sedan's flag used to miss the send: it streaked)
	expect = {
		none = {
			"sim_jump_unflagged",
			"position_jump",
			"speed_stutter",
			"yaw_jump",
			"sideways_slide",
			"sink",
			"float",
			-- a jump is held until a send carries it (TrafficService.jumped)
			"teleport_bit_dropped",
			"teleport_unflagged",
			"accel_spike",
		},
		some = { "teleport_flagged" },
	},
}

return scenario
