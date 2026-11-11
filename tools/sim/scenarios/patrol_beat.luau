--!strict
-- Scenario: the patrol car alone over two whole legs of its beat (traffic.md §5.7: it shuttles between
-- the ends of patrol_beat and turns round there). patrol_turn shows one turn; this shows what comes
-- after it: the leg driven after a turn, and the second turn at the other end.
-- Measured on the base tree: at each end the server moves the car the whole beat (about 1,475 studs) in
-- one tick, unflagged, onto the other side of the road and round 180 degrees; every second leg is then
-- driven backwards (the car faces west and travels east) in the westbound lane, against its traffic.
-- Mechanism: LaneMath.pingPong keeps `s` measured from the lane's start end and turns it round in that
-- frame (s' = length - overshoot, then s decreasing), but LaneMath.pointAt measures `s` from the END for
-- dir = -1 (along = endAt - s): the two conventions disagree, so the turn maps to the far end and the
-- return leg runs the wrong way.
local Fleet = require("@shared/Traffic/Fleet")
local Replay = require("../lib/Replay")

local scenario: Replay.Scenario = {
	name = "patrol_beat",
	about = "the patrol car alone for two legs of its beat: both turns and the leg driven between them",
	seconds = 130,
	ci = 70,
	entries = { Fleet.byClass("patrol")[1] },
	setup = function(sim: Replay.Sim)
		local v = sim.traffic.byId[12]
		v.speed = v.cruise
	end,
	expect = { none = { "speed_stutter", "sink", "float", "teleport_bit_dropped", "appear", "disappear" } },
	known = { "sim_jump_unflagged", "sim_yaw_snap", "teleport_unflagged", "reverse_travel" },
}

return scenario
