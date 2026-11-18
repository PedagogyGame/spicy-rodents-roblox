--!strict
-- The cue tables as every screen shows them once the rules have had their say (tests/lib/MinigameRig): balls the
-- rules put back after a shot, a client that walks up mid-shot, the words when someone leaves or is taken off,
-- an opening the clock decides. The cases live in tests/isolated/pool_table.luau and run in their own Lune
-- process (tests/lib/Isolated says why); each one is reported here as its own test.
local Isolated = require("@tests/lib/Isolated")

return function(t)
	Isolated.register(t, "tests/isolated/pool_table")
end
