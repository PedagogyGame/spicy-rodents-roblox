--!strict
-- Whack-a-mole's server half in the real MinigameService (tests/isolated/whack_a_mole_server.luau, run in its own
-- Lune process: tests/lib/Isolated says why); each case is reported here as its own test.
local Isolated = require("@tests/lib/Isolated")

return function(t)
	Isolated.register(t, "tests/isolated/whack_a_mole_server")
end
