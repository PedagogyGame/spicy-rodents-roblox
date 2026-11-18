--!strict
-- Scenario: two heavy vehicles at a constant speed on straight lanes (nothing brakes, turns or wraps in
-- the first forty seconds) over a connection 60 ms away with 40 ms of mean jitter and no loss. Sends go
-- every 67 ms, so packets often overtake each other. Before the fix the snapshot buffer kept them in
-- arrival order: a late packet became the "newest" and the car froze, then jumped (tools/sim,
-- --jitter-ms 20: 18 stutter moments in 3 min; 60 ms: 24 % of frames starved, cars driving backwards).
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
	name = "net_jitter",
	about = "an RV and a dump truck cruising; 60 ms away with 40 ms of jitter (packets often overtake)",
	seconds = 40,
	entries = { entry(3), entry(4) },
	net = {
		latency = 0.06,
		jitter = 0.04,
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
