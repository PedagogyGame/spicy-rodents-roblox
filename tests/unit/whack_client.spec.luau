--!strict
-- Whack-a-mole played through all of its glue on the fake engine (tests/isolated/whack_a_mole_client.luau, run in
-- its own Lune process: tests/lib/Isolated says why); each case is reported here as its own test.
local Isolated = require("@tests/lib/Isolated")

return function(t)
	Isolated.register(t, "tests/isolated/whack_a_mole_client")
end
