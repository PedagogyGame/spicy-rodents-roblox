--!strict
-- Scenario: two heavy vehicles at a constant speed on straight, empty lanes, on a server whose frames are
-- not an exact 60 Hz (the "live" pacing profile: each frame a millisecond or two off, an occasional
-- longer one). Nothing brakes, turns or wraps in the first forty seconds, and the network is ideal, so
-- any unevenness on screen comes from the server's own timing: a send is stamped with the frame clock,
-- but carries the state of the last whole 30 Hz tick (see the wire detector's stateOlderThanStamp).
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
	name = "live_server",
	about = "an RV and a dump truck cruising on straight lanes while the server's frame times wander (ideal network)",
	seconds = 40,
	ci = 40,
	server = "live",
	entries = { entry(3), entry(4) },
	expect = { none = { "teleport_unflagged", "position_jump", "rubber_band", "yaw_jump", "sink", "float" } },
	-- shows today: the cars surge and drag although they drive at a constant speed
	known = { "speed_stutter" },
}

return scenario
