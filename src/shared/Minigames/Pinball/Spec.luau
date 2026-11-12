--!strict
-- ReplicatedStorage.Shared.Minigames.Pinball.Spec
-- Pinball's line in the minigame registry (Minigames/Games). NOT BUILT YET: `soon` makes the station's prompt
-- say so and turns a player who presses E away with these words.
-- Three machines, one game: each station carries its theme as `variant` (acorn, rodent, space).
-- To build it: give this Spec its rules, flow, session, verbs and words and drop `soon` (the recipe is in the
-- header of Minigames/Games); the station list below already stands where the furniture is.
-- Pure. Interface: a GameSpec.Spec.

local AlleyLayout = require("../../Attractions/AlleyLayout")
local GameSpec = require("../GameSpec")

local Spec: GameSpec.Spec = {
	game = "pinball",
	title = "Pinball",
	soon = "This pinball machine is out of order (a later build fixes it). Try the lanes, the darts or Madame Acorna!",
	flow = "solo",
	verbs = {},
	prompt = { action = "Play (out of order)", object = "Pinball" },
	stations = function(sites: { [string]: GameSpec.Place }): { GameSpec.StationDef }
		local out: { GameSpec.StationDef } = {}
		if sites.bowling_alley == nil then
			return out
		end
		for i, p in AlleyLayout.PINBALLS do
			table.insert(out, {
				id = `pinball_{i}`,
				game = "pinball",
				label = "Pinball",
				site = "bowling_alley",
				x = p.x,
				y = 3,
				d = AlleyLayout.PINBALL_D + 3,
				index = i,
				variant = p.theme,
			})
		end
		return out
	end,
}

return Spec
