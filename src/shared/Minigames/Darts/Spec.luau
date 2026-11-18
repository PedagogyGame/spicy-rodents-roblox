--!strict
-- ReplicatedStorage.Shared.Minigames.Darts.Spec
-- Darts' line in the minigame registry (Minigames/Games): 501 or cricket (the lobby's choice: rules.MODES), three
-- darts a turn, up to four at the board, three pub darts players as computers, and the one board in the bowling
-- alley's games room (Attractions/AlleyLayout.board).
-- Pure. Interface: a GameSpec.Spec.

local AlleyLayout = require("../../Attractions/AlleyLayout")
local GameSpec = require("../GameSpec")
local Darts = require("../MinigameRules/Darts")

local Spec: GameSpec.Spec = {
	game = "darts",
	title = "Darts",
	rules = Darts,
	flow = "turns",
	session = { lobbySeconds = 8, turnSeconds = 45, doneSeconds = 25 },
	verbs = { "throw" },
	-- (there is one board: nothing else to try)
	prompt = { action = "Play darts", busy = "wait for the next game" },
	words = {
		unit = "turn",
		removed = "You were taken off the dartboard: two turns in a row went unplayed",
		finished = "That game is over and the dartboard is free. Press E at the dartboard to play again.",
	},
	computers = { { name = "Treble Trev" }, { name = "Bullseye Bea" }, { name = "Oche Ollie" } },
	stations = function(sites: { [string]: GameSpec.Place }): { GameSpec.StationDef }
		if sites.bowling_alley == nil then
			return {}
		end
		local b = AlleyLayout.board()
		return {
			{
				id = "darts_1",
				game = "darts",
				label = "Dartboard",
				site = "bowling_alley",
				x = b.ocheX + 1.2,
				y = 3,
				d = b.d,
			},
		}
	end,
}

return Spec
