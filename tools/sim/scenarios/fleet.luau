--!strict
-- Scenario: the game's whole fleet (Traffic/Fleet.ENTRIES, 25 vehicles) exactly as Server/Boot/Game
-- starts it (seed 7), on a town with nobody on the roads. The baseline: everything a player sees of
-- traffic when no person or squirrel makes a vehicle brake. The responders and the incident cars stay
-- hidden (the game does not dispatch them yet; see scenarios/dispatch).
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
			"box_overlap",
		},
	},
	-- A wrap's flag now reaches the wire however the tick falls between two sends (TrafficService.poseRecords
	-- carries it until the next send); the eastbound lane keeps clear of the trolley track
}

return scenario
