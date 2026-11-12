--!strict
-- ReplicatedStorage.Shared.Minigames.Pool.Spec
-- Pool's line in the minigame registry (Minigames/Games). NOT BUILT YET: `soon` makes the station's prompt
-- say so and turns a player who presses E away with these words.
-- Eight-ball rules already exist and are tested (MinigameRules/Pool8Ball).
-- To build it: give this Spec its rules, flow, session, verbs and words and drop `soon` (the recipe is in the
-- header of Minigames/Games); the station list below already stands where the furniture is.
-- Pure. Interface: a GameSpec.Spec.

local AlleyLayout = require("../../Attractions/AlleyLayout")
local GameSpec = require("../GameSpec")

local Spec: GameSpec.Spec = {
	game = "pool",
	title = "Pool",
	soon = "Pool is coming in the next build: the table is racked and waiting. Try the lanes, the darts or Madame Acorna!",
	flow = "turns",
	verbs = {},
	prompt = { action = "Play (soon)" },
	stations = function(sites: { [string]: GameSpec.Place }): { GameSpec.StationDef }
		local out: { GameSpec.StationDef } = {}
		if sites.bowling_alley == nil then
			return out
		end
		for i, t in AlleyLayout.POOL_TABLES do
			table.insert(out, {
				id = `pool_{i}`,
				game = "pool",
				label = `Pool table {i}`,
				site = "bowling_alley",
				x = t.x,
				y = 3,
				d = t.d,
				index = i,
			})
		end
		return out
	end,
}

return Spec
