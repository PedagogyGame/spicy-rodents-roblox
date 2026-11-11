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
	-- on an ideal network with steady frames nothing stutters, hops, twitches, sinks or floats
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
			"ghost_visibility",
			"teleport_bit_lost",
			"teleport_bit_dropped",
			"teleport_unflagged",
		},
	},
	-- shows today (vehicles that share a lane)
	known = { "box_overlap" },
}

return scenario
