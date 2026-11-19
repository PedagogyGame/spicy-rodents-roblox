--!strict
-- Server/Items/ItemWorld on a fake engine: a bought thing stays its buyer's (owner, D16 #26; Server/Items/Lending):
-- catch, two players after one ball, a borrowed ball going home, the buyer leaving, a ball left lying, somebody
-- else's whoopee cushion, a lawn chair whose owner left. The cases live in tests/isolated/item_world_lending.luau
-- and run in their own Lune process (tests/lib/Isolated says why); each one is reported here as its own test.
local Isolated = require("@tests/lib/Isolated")

return function(t)
	Isolated.register(t, "tests/isolated/item_world_lending")
end
