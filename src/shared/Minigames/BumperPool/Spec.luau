--!strict
-- ReplicatedStorage.Shared.Minigames.BumperPool.Spec
-- Bumper pool's line in the minigame registry (Minigames/Games). NOT BUILT YET: `soon` makes the station's prompt
-- say so and turns a player who presses E away with these words.
-- No rules module exists yet.
-- To build it: give this Spec its rules, flow, session, verbs and words and drop `soon` (the recipe is in the
-- header of Minigames/Games); the station list below already stands where the furniture is.
-- Pure. Interface: a GameSpec.Spec.

local AlleyLayout = require("../../Attractions/AlleyLayout")
local GameSpec = require("../GameSpec")

local Spec: GameSpec.Spec = {
	game = "bumper_pool",
	title = "Bumper pool",
	soon = "Bumper pool is coming in the next build. Try the lanes, the darts or Madame Acorna!",
	flow = "turns",
	verbs = {},
	prompt = { action = "Play (soon)" },
	stations = function(sites: { [string]: GameSpec.Place }): { GameSpec.StationDef }
		local out: { GameSpec.StationDef } = {}
		if sites.bowling_alley == nil then
			return out
		end
		table.insert(out, {
			id = "bumper_pool_1",
			game = "bumper_pool",
			label = "Bumper pool",
			site = "bowling_alley",
			x = AlleyLayout.BUMPER_POOL.x,
			y = 3,
			d = AlleyLayout.BUMPER_POOL.d,
		})
		return out
	end,
}

return Spec
