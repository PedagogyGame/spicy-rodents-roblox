--!strict
-- ReplicatedStorage.Shared.Minigames.Racquetball.Spec
-- Racquetball's line in the minigame registry (Minigames/Games). NOT BUILT YET, and its place is not baked: it has
-- no station, so nothing of it shows in the world.
-- The court volume is 24 x 48 x 24 studs (X -12..12, D -6..42 of the anchor) with a glass back wall.
-- Where it goes: site "f3_racquet_club" (the venue's frame in generated/Expansion; data/expansion.json), anchor
-- "court" at local (0, 0, 18) (X across, Y above the venue floor, +D is world -Z at yaw 0).
-- To build it: bake its place (tools/bake/games/Racquetball.luau), give this Spec its rules, flow, session, verbs
-- and words, drop `soon`, and return the station from stations() (the recipe is in the header of
-- Minigames/Games).
-- Pure. Interface: a GameSpec.Spec; SITE; AT.

local GameSpec = require("../GameSpec")

local SITE = "f3_racquet_club"
local AT = { x = 0, y = 0, d = 18 } -- anchor "court"

local Spec: GameSpec.Spec = {
	game = "racquetball",
	title = "Racquetball",
	soon = "The racquetball court opens in a later build.",
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
