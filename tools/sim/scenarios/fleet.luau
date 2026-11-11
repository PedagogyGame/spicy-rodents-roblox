--!strict
-- Scenario: the game's whole fleet (Traffic/Fleet.ENTRIES, 25 vehicles) exactly as Server/Boot/Game
-- starts it (seed 7), on a town with nobody on the roads. The baseline: everything a player sees of
-- traffic when no person or squirrel makes a vehicle brake. The responders and the incident cars stay
-- parked out of sight (nobody is bitten here; see scenarios/dispatch for a call).
local Replay = require("../lib/Replay")

local scenario: Replay.Scenario = {
	name = "fleet",
	about = "the game's 25 vehicles, seed 7, nobody on the roads",
	seconds = 600,
	ci = 60,
	-- on an ideal network with steady frames nothing stutters, hops, twitches, sinks or floats, on the
	-- analytic ground or the drawn roads
	expect = {
		none = {
			"speed_stutter",
			"position_jump",
			"height_jump",
			"pitch_jump",
			"sink",
			"float",
			"tilt_mismatch",
			"roll_missing",
			"ledge",
			"hover",
			"buried",
			"ghost_visibility",
			"teleport_bit_lost",
			"teleport_bit_dropped", -- a jump is held until a send carries it (TrafficService.jumped)
			"teleport_unflagged",
			"box_overlap", -- the eastbound lane keeps clear of the trolley track
			"teleport_flagged", -- nobody wraps: every lane vehicle turns round at the end of its street
			"speed_pumping",
		},
	},
}

return scenario
