--!strict
-- ReplicatedStorage.Shared.Minigames.AirHockey.Spec
-- Air hockey's line in the minigame registry (Minigames/Games): the owner's AER / 01 table in the bowling
-- alley's games room, along the back wall beyond the bumper pool. Walk up to either end and press the prompt:
-- that end is yours (the Glacier end's prompt is the table's station; the Ember end's joins it). A short lobby
-- lets a second person take the other end; nobody there, and the computer plays it (his three opponents: Lounge,
-- Club, Pro), until someone does, and again if they leave. First to seven. Nothing is staked.
-- The game is "live": both ends act at every moment. A hand is not a message per frame but a log by tick sent in
-- segments ("log": AirHockey/Wire); a seat whose log stops arriving for idleSeconds is taken off.
-- Pure. Interface: a GameSpec.Spec.

local GameSpec = require("../GameSpec")
local Layout = require("./Layout")
local Rules = require("./Rules")

local Spec: GameSpec.Spec = {
	game = "air_hockey",
	title = "Air hockey",
	rules = Rules,
	flow = "live",
	session = { lobbySeconds = 8, doneSeconds = 20, idleSeconds = 6 },
	verbs = { "log" },
	prompt = { action = "Play air hockey", busy = "watch this one" },
	words = {
		start = "", -- (the table says READY itself)
		removed = "You were taken off the air hockey table: your game stopped answering",
		finished = "That match is over and the table is free. Press E at either end to play again.",
	},
	computers = Rules.COMPUTERS,
	stations = Layout.stations,
}

return Spec
