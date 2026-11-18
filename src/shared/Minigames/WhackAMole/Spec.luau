--!strict
-- ReplicatedStorage.Shared.Minigames.WhackAMole.Spec
-- Whack-a-mole's line in the minigame registry (Minigames/Games): the owner's cabinet (docs/reference/whack_a_mole;
-- docs/owner/DELIVERY_2026-11-18.md), the tenth game, in the bowling alley's games room beside the pinball row
-- (WhackAMole/Layout.AT). One player plays a 45-second round; anyone near watches the same moles. Pressing E
-- starts the round at once (a three-second count-in first); while it is on, the prompt says so and the next
-- player waits for the end. Free play: no coins, ever (the coin door is a FREE PLAY plate).
-- Pure. Interface: a GameSpec.Spec.

local GameSpec = require("../GameSpec")
local Layout = require("./Layout")
local Rules = require("./Rules")

local Spec: GameSpec.Spec = {
	game = Rules.GAME,
	title = "Whack-a-Mole",
	rules = Rules,
	flow = "solo",
	-- (one seat: the round starts on the press; a player who strikes nothing for 20 s is taken off)
	session = { lobbySeconds = 0, turnSeconds = 0, doneSeconds = 12, idleSeconds = 20 },
	verbs = Rules.CLIENT_VERBS,
	prompt = { action = "Play", object = "Whack-a-Mole (free play)", busy = "watch the moles" },
	words = {
		start = "", -- (the count-in says READY and GO)
		removed = "You were taken off the whack-a-mole: nothing was struck for a while",
		finished = "That round is over and the cabinet is free. Press E to play again.",
	},
	stations = function(sites: { [string]: GameSpec.Place }): { GameSpec.StationDef }
		if sites.bowling_alley == nil then
			return {}
		end
		local X, Y, D = Layout.toSite(Layout.PROMPT.u, Layout.PROMPT.v, Layout.PROMPT.w)
		return {
			{
				id = "whack_a_mole_1",
				game = Rules.GAME,
				label = "Whack-a-Mole",
				site = "bowling_alley",
				x = X,
				y = Y,
				d = D,
				index = 1,
				reach = 12, -- (a player who walks off from the cabinet's front is taken off at once)
			},
		}
	end,
}

return Spec
