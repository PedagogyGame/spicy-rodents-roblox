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
}

return scenario
