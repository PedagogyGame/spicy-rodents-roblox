--!strict
-- Server/Items/ItemWorld's kite on a fake engine (server-authoritative steering: up, KiteUp, steer clamped and
-- rate-limited, only the flier's, settles back, put away). The cases live in tests/isolated/item_world_kite.luau
-- and run in their own Lune process (tests/lib/Isolated says why); each one is reported here as its own test.
local Isolated = require("@tests/lib/Isolated")

return function(t)
	Isolated.register(t, "tests/isolated/item_world_kite")
end
