--!strict
-- ReplicatedStorage.Shared.Minigames.Paintball.Spec
-- Paintball's line in the minigame registry (Minigames/Games). NOT BUILT YET, and its place is not baked: it has
-- no station, so nothing of it shows in the world.
-- The pure pieces exist (Shared/Paintball, Server/Paintball); the arena is 120 x 120, five floors.
-- Where it goes: site "f3_tv_station" (the venue's frame in generated/Expansion; data/expansion.json), anchor
-- "arena_origin" at local (0, 0, 15) (X across, Y above the venue floor, +D is world -Z at yaw 0).
-- To build it: bake its place (tools/bake/games/Paintball.luau), give this Spec its rules, flow, session, verbs
-- and words, drop `soon`, and return the station from stations() (the recipe is in the header of
-- Minigames/Games).
-- Pure. Interface: a GameSpec.Spec; SITE; AT.

local GameSpec = require("../GameSpec")

local SITE = "f3_tv_station"
local AT = { x = 0, y = 0, d = 15 } -- anchor "arena_origin"

local Spec: GameSpec.Spec = {
	game = "paintball",
	title = "Paintball",
	soon = "The paintball arena opens in a later build.",
	flow = "match",
	verbs = {},
	prompt = { action = "Play (soon)" },
	stations = function(sites: { [string]: GameSpec.Place }): { GameSpec.StationDef }
		-- (when it is built: a station at AT on SITE, if the site was baked)
		local _ = sites[SITE] and AT
		return {}
	end,
}

return Spec
