--!strict
-- Scenario: two cruising heavy vehicles; the client joins 10 s after the server started sending, over a
-- jittery connection (60 ms, 20 ms of jitter, no loss). The first packets decide nothing for good: the
-- playout clock must settle without throwing the cars about.
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
	name = "late_join",
	about = "an RV and a dump truck cruising; the client joins 10 s in, 60 ms away with 20 ms of jitter",
	seconds = 30,
	entries = { entry(3), entry(4) },
	joinAt = 10,
	net = {
		latency = 0.06,
		jitter = 0.02,
		loss = 0,
		burstEvery = 0,
		burstLength = 0,
		burstLoss = 0,
		burstDelay = 0,
		reorder = 0,
		reorderDelay = 0.1,
		duplicate = 0,
	} :: any,
	expect = {
		none = {
			"speed_stutter",
			"accel_spike",
			"position_jump",
			"rubber_band",
			"reverse_travel",
			"teleport_unflagged",
			"yaw_jump",
			"sink",
			"float",
		},
	},
}

return scenario
