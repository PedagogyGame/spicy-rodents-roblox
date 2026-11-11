--!strict
-- Scenario: two heavy vehicles at a constant speed on straight lanes; five seconds in, one server frame
-- takes half a second (a save, a join, a collection), then the server is an exact 60 Hz again.
-- Server/Boot/Game advances its clock by at most 0.1 s per frame (PoseStream.MAX_FRAME_DT), so after the
-- stall every stamp is 0.4 s older than the moment it was sent. What does the client make of that, and
-- for how long?
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
	name = "server_stall",
	about = "an RV and a dump truck cruising; at 5 s one server frame takes 0.5 s, then steady again",
	seconds = 30,
	ci = 30,
	entries = { entry(3), entry(4) },
	hitch = function(sim: Replay.Sim, dt: number): number
		if sim.wall >= 5 and not sim.state.stalled then
			sim.state.stalled = true
			return 0.5
		end
		return dt
	end,
	expect = { none = { "teleport_unflagged", "yaw_jump", "sink", "float" } },
	-- shows today: the server itself stood still for 0.5 s; the cars hold for about 0.25 s, then step with
	-- the next few sends for about 0.35 s while the playout clock falls back (Ghost.CATCH_UP), then run
	-- smoothly again (it used to be 25 s of stepping, until the stamp clock had crept back)
	known = { "speed_stutter" },
}

return scenario
