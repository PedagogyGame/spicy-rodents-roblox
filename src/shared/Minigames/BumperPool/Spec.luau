--!strict
-- ReplicatedStorage.Shared.Minigames.BumperPool.Spec
-- Bumper pool's line in the minigame registry (Minigames/Games): the bumper pool table in the bowling alley's
-- games room (Attractions/AlleyLayout.BUMPER_POOL). Two seats, or one alone for practice; the rules are
-- Pool/BumperPool (the table model is pool's, Shared/Minigames/Pool, read here and never copied); three
-- computer players of three levels (Pool/Computer.BUMPER_PLAYERS: their level rides on the computer's key).
-- Both players strike their marked ball in the opening (the rules wait for the second strike and play the two
-- together), then it is a turn game. A turn is 45 seconds; an idle turn passes the shot.
-- Pure. Interface: a GameSpec.Spec.

local AlleyLayout = require("../../Attractions/AlleyLayout")
local GameSpec = require("../GameSpec")
local BumperPool = require("../Pool/BumperPool")
local Computer = require("../Pool/Computer")

local computers: { { [string]: any } } = {}
for _, p in Computer.BUMPER_PLAYERS do
	table.insert(computers, { name = p.name, level = p.level })
end

local Spec: GameSpec.Spec = {
	game = "bumper_pool",
	title = "Bumper pool",
	rules = BumperPool,
	flow = "turns",
	session = { lobbySeconds = 10, turnSeconds = 45, doneSeconds = 30 },
	verbs = { "shoot", "aim" },
	prompt = { action = "Play bumper pool", busy = "wait for the next game" },
	words = {
		start = "Bumper pool: the opening! Both of you, bank your marked ball off your right-hand cushion",
		unit = "shot",
		removed = "You were taken off the bumper pool table: two shots in a row went unplayed",
		finished = "That game is over and the balls are back on their spots. Press E at the table to play.",
	},
	computers = computers,
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
			index = 1,
			-- (a player walks all the way round the table, and a step back from it)
			reach = 18,
		})
		return out
	end,
}

return Spec
