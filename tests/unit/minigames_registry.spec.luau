--!strict
-- The minigame registry (Shared/Minigames/Games, Server/Minigames/ServerGames, Client/Minigames/ClientGames):
-- the three lists line up and the framework's own files name no game; and games registered only in this test
-- (tests/lib/FakeGames: one per kind, turns / a real-time rally / a continuous single-player machine / a team
-- match, plus a game that is only a Spec and rules) stand at their stations with their prompts, seat a player,
-- run their controllers and report a result through the real MinigameService and MinigameClient on a fake
-- engine (tests/lib/MinigameRig). The cases live in tests/isolated/minigames_registry.luau and run in their own
-- Lune process (tests/lib/Isolated says why); each one is reported here as its own test.
local Isolated = require("@tests/lib/Isolated")

return function(t)
	Isolated.register(t, "tests/isolated/minigames_registry")
end
