--!strict
-- ReplicatedStorage.Shared.Minigames.Volleyball.Spec
-- Beach volleyball's line in the minigame registry (Minigames/Games). NOT BUILT YET, and its place is not baked: it has
-- no station, so nothing of it shows in the world.
-- Sand pit 80 x 50 with the net across X; court 48 x 24; a loose beach ball at local (160, 0, 80).
-- Where it goes: site "f3_steakhouse" (the venue's frame in generated/Expansion; data/expansion.json), anchor
-- "volleyball_net" at local (175, 0, 65) (X across, Y above the venue floor, +D is world -Z at yaw 0).
-- To build it: bake its place (tools/bake/games/Volleyball.luau), give this Spec its rules, flow, session, verbs
-- and words, drop `soon`, and return the station from stations() (the recipe is in the header of
-- Minigames/Games).
-- Pure. Interface: a GameSpec.Spec; SITE; AT.

local GameSpec = require("../GameSpec")

local SITE = "f3_steakhouse"
local AT = { x = 175, y = 0, d = 65 } -- anchor "volleyball_net"

local Spec: GameSpec.Spec = {
	game = "volleyball",
	title = "Beach volleyball",
	soon = "The beach volleyball court opens in a later build.",
	flow = "live",
	verbs = {},
	prompt = { action = "Play (soon)" },
	stations = function(sites: { [string]: GameSpec.Place }): { GameSpec.StationDef }
		-- (when it is built: a station at AT on SITE, if the site was baked)
		local _ = sites[SITE] and AT
		return {}
	end,
}

return Spec
