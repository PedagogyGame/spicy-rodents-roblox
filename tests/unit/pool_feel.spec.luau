--!strict
-- How the cue tables feel at the table (tests/lib/MinigameRig): the eye down the cue, the stroke and the rise,
-- the other player's aim, the winning shot's replay, the fine touch of keys and fingers, the How-to-play card.
-- The cases live in tests/isolated/pool_feel.luau and run in their own Lune process (tests/lib/Isolated says
-- why); each one is reported here as its own test.
local Isolated = require("@tests/lib/Isolated")

return function(t)
	Isolated.register(t, "tests/isolated/pool_feel")
end
