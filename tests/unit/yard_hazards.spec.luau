--!strict
-- Server/Wildlife/YardHazards (the yard dogs) on a fake engine with the town's brain scheduler and threat grid, and
-- the dog treats through Items/ItemWorld. The cases live in tests/isolated/yard_hazards.luau and run in their own
-- Lune process (tests/lib/Isolated says why); each one is reported here as its own test.
local Isolated = require("@tests/lib/Isolated")

return function(t)
	Isolated.register(t, "tests/isolated/yard_hazards")
end
