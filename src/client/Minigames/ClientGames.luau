--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Minigames.ClientGames
-- The client registry of minigames: ONE LINE PER GAME (the game's line in Shared/Minigames/Games says what it is;
-- Client/Minigames/ClientGame says what a client half may supply). MinigameClient looks a game up here and
-- never names one. A game that is not built yet has a stub module that returns only its name, so its line
-- already exists and its builder fills in the module, not this file. Each game's sound cues are added to
-- MinigameSounds as the registry loads.
-- Interface: get(game) -> ClientGame?; ownerOf(kind) -> ClientGame? (whose everyone-message that kind is);
--   register(clientGame) (tests: a game added at run time); LIST

local ClientGame = require("./ClientGame")
local MinigameSounds = require("./MinigameSounds")

local ClientGames = {}

ClientGames.LIST = {
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
} :: { ClientGame.ClientGame }

-- the framework's own message kinds (Client/Minigames/MinigameClient)
local RESERVED: { [string]: boolean } = { joined = true, state = true, event = true, left = true, refused = true }

local function adopt(entry: ClientGame.ClientGame)
	if entry.sounds then
		MinigameSounds.add(entry.sounds)
	end
	for _, kind in entry.kinds or {} do
		assert(not RESERVED[kind], `ClientGames: {entry.game} cannot take the framework's message kind "{kind}"`)
		local owner = ClientGames.ownerOf(kind)
		assert(
			owner == nil or owner == entry,
			`ClientGames: message kind "{kind}" belongs to {owner and owner.game} and {entry.game}`
		)
	end
end

function ClientGames.get(game: string): ClientGame.ClientGame?
	for _, entry in ClientGames.LIST do
		if entry.game == game then
			return entry
		end
	end
	return nil
end

function ClientGames.ownerOf(kind: string): ClientGame.ClientGame?
	for _, entry in ClientGames.LIST do
		if entry.kinds and table.find(entry.kinds, kind) then
			return entry
		end
	end
	return nil
end

function ClientGames.register(entry: ClientGame.ClientGame)
	assert(type(entry.game) == "string", "ClientGames.register: { game, ... }")
	assert(ClientGames.get(entry.game) == nil, `ClientGames.register: {entry.game} is already registered`)
	adopt(entry)
	table.insert(ClientGames.LIST, entry)
end

for _, entry in ClientGames.LIST do
	adopt(entry)
end

return ClientGames
