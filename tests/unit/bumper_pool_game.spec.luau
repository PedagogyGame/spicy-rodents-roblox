--!strict
-- Bumper pool through all of its glue on the fake engine (tests/lib/MinigameRig): the real MinigameService with
-- bumper pool's Table and the real MinigameClient with pool's controller and playback, the player's hands on
-- the mouse. The cases live in tests/isolated/bumper_pool_game.luau and run in their own Lune process
-- (tests/lib/Isolated says why); each one is reported here as its own test.
local Isolated = require("@tests/lib/Isolated")

return function(t)
	Isolated.register(t, "tests/isolated/bumper_pool_game")
end
