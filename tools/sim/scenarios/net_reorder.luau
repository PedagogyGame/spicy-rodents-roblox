--!strict
-- Scenario: two cruising heavy vehicles; the network holds one packet in ten back by 100 ms (it lands
-- after the next one) and delivers one in ten twice. Out-of-order snapshots must be put back in order and
-- copies dropped.
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
	name = "net_reorder",
	about = "an RV and a dump truck cruising; one packet in ten held back 100 ms, one in ten arriving twice",
	seconds = 40,
	entries = { entry(3), entry(4) },
	net = {
		latency = 0.04,
		jitter = 0,
		loss = 0,
		burstEvery = 0,
		burstLength = 0,
		burstLoss = 0,
		burstDelay = 0,
		reorder = 0.1,
		reorderDelay = 0.1,
		duplicate = 0.1,
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
