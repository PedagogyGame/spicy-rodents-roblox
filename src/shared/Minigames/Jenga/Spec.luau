--!strict
-- ReplicatedStorage.Shared.Minigames.Jenga.Spec
-- Giant Jenga's line in the minigame registry (Minigames/Games). NOT BUILT YET, and its place is not baked: it has
-- no station, so nothing of it shows in the world.
-- A four-foot tower of 54 blocks on a table on the raised deck (50 x 40).
-- Where it goes: site "f3_steakhouse" (the venue's frame in generated/Expansion; data/expansion.json), anchor
-- "jenga_table" at local (85, 1.5, 60) (X across, Y above the venue floor, +D is world -Z at yaw 0).
-- To build it: bake its place (tools/bake/games/Jenga.luau), give this Spec its rules, flow, session, verbs
-- and words, drop `soon`, and return the station from stations() (the recipe is in the header of
-- Minigames/Games).
-- Pure. Interface: a GameSpec.Spec; SITE; AT.

local GameSpec = require("../GameSpec")

local SITE = "f3_steakhouse"
local AT = { x = 85, y = 1.5, d = 60 } -- anchor "jenga_table"

local Spec: GameSpec.Spec = {
	game = "giant_jenga",
	title = "Giant Jenga",
	soon = "The giant Jenga tower opens in a later build.",
	flow = "turns",
	verbs = {},
	prompt = { action = "Play (soon)" },
	stations = function(sites: { [string]: GameSpec.Place }): { GameSpec.StationDef }
		-- (when it is built: a station at AT on SITE, if the site was baked)
		local _ = sites[SITE] and AT
		return {}
	end,
}

return Spec
