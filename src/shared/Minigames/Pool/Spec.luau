--!strict
-- ReplicatedStorage.Shared.Minigames.Pool.Spec
-- Pool's line in the minigame registry (Minigames/Games): eight-ball on the two tables in the bowling alley's
-- games room (Attractions/AlleyLayout.POOL_TABLES). Two seats, or one alone for practice; the rules are
-- Pool/EightBall (which run the table model on every "shoot"); three computer players of three levels
-- (Pool/Computer.POOL_PLAYERS: their level rides on the computer's key).
-- A turn is a minute: a shot at pool is thought about. An idle turn is a foul (the rules' skipTurn).
-- Pure. Interface: a GameSpec.Spec.

local AlleyLayout = require("../../Attractions/AlleyLayout")
local GameSpec = require("../GameSpec")
local Computer = require("./Computer")
local EightBall = require("./EightBall")

local computers: { { [string]: any } } = {}
for _, p in Computer.POOL_PLAYERS do
	table.insert(computers, { name = p.name, level = p.level })
end

local Spec: GameSpec.Spec = {
	game = "pool",
	title = "Pool",
	rules = EightBall,
	flow = "turns",
	session = { lobbySeconds = 10, turnSeconds = 60, doneSeconds = 30 },
	verbs = { "shoot", "call", "place" },
	prompt = { action = "Play pool", busy = "try the other table" },
	words = {
		start = "Eight-ball: break!",
		unit = "shot",
		removed = "You were taken off the pool table: two shots in a row went unplayed",
		finished = "That game is over and the table is racked again. Press E at a pool table to play.",
	},
	computers = computers,
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
				-- (a player walks all the way round the table, and a step back from it)
				reach = 22,
			})
		end
		return out
	end,
}

return Spec
