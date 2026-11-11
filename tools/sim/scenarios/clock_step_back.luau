--!strict
-- Scenario: two cruising heavy vehicles on an ideal network; at 10 s the client's clock
-- (workspace:GetServerTimeNow) steps 250 ms back, as a resync of its estimate could. Before the fix the
-- render time stepped back with it: every car jumped back a quarter second of driving.
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
	name = "clock_step_back",
	about = "an RV and a dump truck cruising; at 10 s the client's clock steps 250 ms back (a resync)",
	seconds = 30,
	entries = { entry(3), entry(4) },
	clockStepAt = 10,
	clockStep = -0.25,
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
