--!strict
-- ReplicatedStorage.Shared.Minigames.Fortune.Spec
-- Madame Acorna's line in the minigame registry (Minigames/Games): the free fortune-teller cabinet in the bowling
-- alley's games room. One seat, no lobby: every press of the prompt is a pull of the lever, and the card is the
-- whole game (never money: brief v2 §13a, Q20).
-- Pure. Interface: a GameSpec.Spec.

local AlleyLayout = require("../../Attractions/AlleyLayout")
local GameSpec = require("../GameSpec")
local FortuneMachine = require("../MinigameRules/FortuneMachine")

local Spec: GameSpec.Spec = {
	game = "fortune_machine",
	title = "Madame Acorna",
	rules = FortuneMachine,
	flow = "solo",
	session = { lobbySeconds = 0, turnSeconds = 0, doneSeconds = 4 },
	verbs = { "pull" },
	prompt = { action = "Pull the lever", object = "Madame Acorna (free)" },
	words = { start = "" }, -- (the card is its own beginning and ending)
	stations = function(sites: { [string]: GameSpec.Place }): { GameSpec.StationDef }
		if sites.bowling_alley == nil then
			return {}
		end
		return {
			{
				id = "fortune_1",
				game = "fortune_machine",
				label = "Madame Acorna",
				site = "bowling_alley",
				x = AlleyLayout.FORTUNE.x - 1.6,
				y = 3,
				d = AlleyLayout.FORTUNE.d - 1.6,
			},
		}
	end,
}

return Spec
