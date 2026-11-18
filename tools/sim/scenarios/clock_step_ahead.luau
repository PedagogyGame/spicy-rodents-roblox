--!strict
-- Scenario: two cruising heavy vehicles on an ideal network; at 10 s the client's clock steps 250 ms
-- ahead. Before the fix the render time ran past every snapshot and the stamp clock crept back at 3 ms a
-- second: the cars moved in 15 steps a second for over a minute.
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
	name = "clock_step_ahead",
	about = "an RV and a dump truck cruising; at 10 s the client's clock steps 250 ms ahead (a resync)",
	seconds = 30,
	entries = { entry(3), entry(4) },
	clockStepAt = 10,
	clockStep = 0.25,
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
