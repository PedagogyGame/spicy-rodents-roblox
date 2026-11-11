--!strict
-- Scenario: the dispatched vehicles on a busy day (traffic.md §5.9, §5.10). The dispatch scenario sends
-- one responder and the incident pair once; here all three responder ambulances are sent one second
-- apart (two bites in quick succession is ordinary play once bites call an ambulance), and once all are
-- home, one responder and the incident pair are sent again, so the second trip of each is seen.
-- Measured on the base tree:
--   * every responder appears at the same point (s = 0 of the trunk, about 370 st inside the town) at its
--     full 60 st/s and hides at the same point on its return; sent a second apart they are 60 st apart,
--     so no two overlap here (sent in the same tick they would: dispatch -> appear(v, ctx, route, 0),
--     and the emergency classes yield to nothing)
--   * the incident pair: the car that starts behind reaches the first corner first, so the other one
--     drives through it to reach its own spot at the scene (box_overlap, 5.9 st, a third of a second)
--   * every trip leaves at full speed from a standstill, turns each square corner in one tick, and at the
--     scene turns round in one tick: `hold` -> `back` sets dir = -1, s = 0, which is the start of the
--     reversed polyline offset to the other side of the road: a 15 st sideways hop and a 180 degree
--     flip, unflagged, so clients slide the car across over one send interval
--   * the second trip is the same as the first: no state carries over
local Fleet = require("@shared/Traffic/Fleet")
local Replay = require("../lib/Replay")

local entries = {}
for _, e in Fleet.byClass("responder") do
	table.insert(entries, e)
end
for _, e in Fleet.byClass("incident") do
	table.insert(entries, e)
end

local SENDS = {
	{ at = 2, kind = "responder", dest = { -40, 60 } },
	{ at = 3, kind = "responder", dest = { 120, 140 } },
	{ at = 4, kind = "responder", dest = { -150, -100 } },
	{ at = 5, kind = "incident", dest = { 100, -80 } },
	{ at = 130, kind = "responder", dest = { 120, 140 } },
	{ at = 130, kind = "incident", dest = { -60, 120 } },
}

local scenario: Replay.Scenario = {
	name = "dispatch_busy",
	about = "three responders sent a second apart, the incident pair, then a second trip for each",
	seconds = 250,
	ci = 30,
	entries = entries,
	sceneSecs = 6,
	frame = function(sim: Replay.Sim)
		for i, send in SENDS do
			if sim.wall >= send.at and not sim.state[i] then
				sim.state[i] = true
				local dest = { sim.st(send.dest[1]), sim.st(send.dest[2]) }
				if send.kind == "responder" then
					sim.traffic:dispatchResponder(dest)
				else
					sim.traffic:dispatchIncident(dest)
				end
			end
		end
	end,
	expect = { none = { "teleport_unflagged", "sink", "float" } },
	known = { "box_overlap", "sim_yaw_snap", "yaw_jump", "appear" },
}

return scenario
