--!strict
-- Scenario: two cruising heavy vehicles on an ideal network, on a server that has run for 50 hours.
-- The stamp travels as a 32-bit float: at 50 h (180,000 s) it resolved only 15.6 ms, so snapshots were
-- spaced unevenly and every car jerked (accel_spike; at 200 h, 62.5 ms: speed_stutter everywhere). The
-- stamp is now sent modulo Ghost.STAMP_WRAP and unwrapped by the client.
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
	name = "long_uptime",
	about = "an RV and a dump truck cruising on a server that has been up for 50 hours",
	seconds = 30,
	entries = { entry(3), entry(4) },
	uptime = 50 * 3600,
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
