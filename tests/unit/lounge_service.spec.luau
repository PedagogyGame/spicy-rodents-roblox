--!strict
-- Server/Attractions/LoungeService (THE GILDED ACORN's door, guards and bar) on a fake engine: the engine check's
-- own flow (tests/engine/Lounge), the prompts, the posts and the Town from the game. The cases live in
-- tests/isolated/lounge_service.luau and run in their own Lune process (tests/lib/Isolated says why); each one is
-- reported here as its own test.
local Isolated = require("@tests/lib/Isolated")

return function(t)
	Isolated.register(t, "tests/isolated/lounge_service")
end
