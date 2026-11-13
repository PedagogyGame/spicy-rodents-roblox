--!strict
-- ServerScriptService.Server.Minigames.ServerGames
-- The server registry of minigames: ONE LINE PER GAME (the game's line in Shared/Minigames/Games says what it is;
-- Server/Minigames/ServerGame says what a server half may supply). MinigameService looks a station's game up
-- here and never names one. A game that is not built yet (its Spec has `soon`) has a stub module that returns
-- only its name, so its line already exists and its builder fills in the module, not this file.
-- Interface: get(game) -> ServerGame?; register(serverGame) (tests: a game added at run time); LIST

local ServerGame = require("./ServerGame")

local ServerGames = {}

-- (a stub has no `new` yet)
type Entry = { game: string, new: ((ctx: ServerGame.Ctx) -> ServerGame.Table)? }

ServerGames.LIST = {
	require("./Games/Bowling"),
	require("./Games/Darts"),
	require("./Games/Fortune"),
	require("./Games/Pool"),
	require("./Games/BumperPool"),
	require("./Games/Pinball"),
	require("./Games/Racquetball"),
	require("./Games/Volleyball"),
	require("./Games/Jenga"),
	require("./Games/Labyrinth"),
	require("./Games/Paintball"),
	require("./Games/AirHockey"),
} :: { Entry }

function ServerGames.get(game: string): ServerGame.ServerGame?
	for _, entry in ServerGames.LIST do
		if entry.game == game and entry.new ~= nil then
			return entry :: any
		end
	end
	return nil
end

function ServerGames.register(entry: ServerGame.ServerGame)
	assert(type(entry.game) == "string" and type(entry.new) == "function", "ServerGames.register: { game, new }")
	assert(ServerGames.get(entry.game) == nil, `ServerGames.register: {entry.game} is already registered`)
	table.insert(ServerGames.LIST, entry)
end

return ServerGames
