--!strict
-- Scenario: the vehicles that are hidden until dispatched (traffic.md §5.9, §5.10): the three responder
-- ambulances and the two incident police cars, alone. One responder is sent to a house two seconds in,
-- the incident pair to a scene at four seconds; each drives out along its route (polylines, corners
-- rounded), holds at the scene, U-turns and drives back the way it came. The game does not dispatch them yet
-- (nothing calls TrafficService.dispatchResponder / dispatchIncident), so this is what players will see
-- once the bite-to-ambulance work lands.
local Fleet = require("@shared/Traffic/Fleet")
local Replay = require("../lib/Replay")

local entries = {}
for _, e in Fleet.byClass("responder") do
	table.insert(entries, e)
end
for _, e in Fleet.byClass("incident") do
	table.insert(entries, e)
end

local scenario: Replay.Scenario = {
	name = "dispatch",
	about = "one responder ambulance and both incident cars dispatched, held at the scene and sent home",
	seconds = 170,
	ci = 40,
	entries = entries,
	sceneSecs = 6, -- the responder's hold at the scene (30 s in the game)
	-- the square corners are rounded (LaneMath.CORNER_RADIUS), the turn back at the scene is a U-turn (it
	-- flipped round on the spot and jumped 15 st sideways), they pull away and brake, and the second
	-- incident car parks behind the first instead of driving through it to its spot beyond
	expect = {
		none = {
			"teleport_unflagged",
			"sink",
			"float",
			"reverse_travel",
			"sim_yaw_snap",
			"yaw_jump",
			"sideways_slide",
			"sim_jump_unflagged",
			"position_jump",
			"accel_spike",
			"box_overlap",
		},
	},
	-- shows today: routes straight across lots and through houses (LaneMath.incidentRoute and the
	-- responder's tail are straight lines, not roads)
	known = { "through_building", "off_road" },
	frame = function(sim: Replay.Sim)
		if sim.wall >= 2 and not sim.state.responder then
			sim.state.responder = true
			sim.traffic:dispatchResponder({ sim.st(-40), sim.st(60) })
		end
		if sim.wall >= 4 and not sim.state.incident then
			sim.state.incident = true
			sim.traffic:dispatchIncident({ sim.st(100), sim.st(-80) })
		end
	end,
}

return scenario
