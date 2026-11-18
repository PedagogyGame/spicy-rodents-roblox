--!strict
-- ReplicatedStorage.Shared.Minigames.Pinball.Spec
-- Pinball's line in the minigame registry (Minigames/Games): three machines in the bowling alley's games room,
-- one game. Each station carries its machine as `variant` (acorn: ACORN ATTACK, rodent: SPICY RODENT, space:
-- SPACE SQUIRREL) and is labelled with the machine's own title; when a game starts the station's Table names
-- its machine to the rules (the server verb "machine": Pinball/Rules.game). One to four players take a ball
-- each in turn through the ordinary lobby (friends have eight seconds to join; Space starts at once); no
-- computer player (the owner's checklist PIN-R5: solo is the game); free play, nothing staked.
-- A pinball turn is one ball and it is not one message: the player's own machine runs the model and sends its
-- input log about ten times a second ("log": InputLog.pack's three arguments and its Replay.sum); the server
-- replays it and is the score of record (Pinball/Replay). The turn clock is the log's: a ball whose log stops
-- arriving for turnSeconds is played out dead, and the second in a row takes the player off.
-- Pure. Interface: a GameSpec.Spec.

local AlleyLayout = require("../../Attractions/AlleyLayout")
local GameSpec = require("../GameSpec")
local Rules = require("./Rules")
local Tables = require("./Tables")

local Spec: GameSpec.Spec = {
	game = "pinball",
	title = "Pinball",
	rules = Rules.game,
	flow = "turns",
	session = { lobbySeconds = 8, turnSeconds = 12, doneSeconds = 25, maxTimeouts = 2 },
	verbs = Rules.CLIENT_VERBS,
	prompt = { action = "Play", busy = "watch the ball" },
	words = {
		start = "", -- (the backglass says the ball and the player up)
		unit = "ball",
		removed = "You were taken off the pinball machine: your game stopped answering",
		finished = "That pinball game is over and the machine is free. Press E to play again.",
	},
	stations = function(sites: { [string]: GameSpec.Place }): { GameSpec.StationDef }
		local out: { GameSpec.StationDef } = {}
		if sites.bowling_alley == nil then
			return out
		end
		for i, p in AlleyLayout.PINBALLS do
			local id = Tables.forVariant(p.theme)
			local tbl = id and Tables.get(id)
			table.insert(out, {
				id = `pinball_{i}`,
				game = "pinball",
				label = if tbl then tbl.title else "Pinball",
				site = "bowling_alley",
				x = p.x,
				y = 3,
				d = AlleyLayout.PINBALL_D + 3,
				index = i,
				variant = p.theme,
				reach = 12, -- (a player who walks off from the cabinet's front is taken off at once)
			})
		end
		return out
	end,
}

return Spec
