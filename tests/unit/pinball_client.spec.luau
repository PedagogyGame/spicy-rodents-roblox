--!strict
-- Pinball played through all of its glue on a fake engine (tests/lib/MinigameRig): the real MinigameService with
-- the game's Table and the model's replay on one side, the real MinigameClient with MinigameUI and the game's
-- Controller, Hands and Cabinet on the other, the fake lagged network with the real Net's schema and rate limit
-- between them. Whole games alone and with others, keys, mouse, gamepad and touch, watchers near the cabinet and a
-- late one, a player who leaves or walks away, lag, the attract show, and the server check's own flow
-- (tests/engine/PinballFlow). The cases live in tests/isolated/pinball_client.luau and run in their own Lune
-- process (tests/lib/Isolated says why); each one is reported here as its own test.
local Isolated = require("@tests/lib/Isolated")

return function(t)
	Isolated.register(t, "tests/isolated/pinball_client")
end
