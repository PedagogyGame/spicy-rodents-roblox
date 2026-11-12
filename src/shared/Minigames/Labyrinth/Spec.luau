--!strict
-- ReplicatedStorage.Shared.Minigames.Labyrinth.Spec
-- Tilt labyrinth's line in the minigame registry (Minigames/Games). NOT BUILT YET, and its place is not baked: it has
-- no station, so nothing of it shows in the world.
-- Its controls are the owner's and never change: W/S tilt forward and back; Up arrow right, Down arrow left.
-- Where it goes: site "f2_doctor" (the venue's frame in generated/Expansion; data/expansion.json), anchor
-- "tilt_labyrinth" at local (8, 2.6, -10.5) (X across, Y above the venue floor, +D is world -Z at yaw 0).
-- To build it: bake its place (tools/bake/games/Labyrinth.luau), give this Spec its rules, flow, session, verbs
-- and words, drop `soon`, and return the station from stations() (the recipe is in the header of
-- Minigames/Games).
-- Pure. Interface: a GameSpec.Spec; SITE; AT.

local GameSpec = require("../GameSpec")

local SITE = "f2_doctor"
local AT = { x = 8, y = 2.6, d = -10.5 } -- anchor "tilt_labyrinth"

local Spec: GameSpec.Spec = {
	game = "tilt_labyrinth",
	title = "Tilt labyrinth",
	soon = "The tilt labyrinth opens in a later build.",
	flow = "solo",
	verbs = {},
	prompt = { action = "Play (soon)" },
	stations = function(sites: { [string]: GameSpec.Place }): { GameSpec.StationDef }
		-- (when it is built: a station at AT on SITE, if the site was baked)
		local _ = sites[SITE] and AT
		return {}
	end,
}

return Spec
