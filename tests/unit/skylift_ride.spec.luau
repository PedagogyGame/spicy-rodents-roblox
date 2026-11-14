--!strict
-- The sky lift joined end to end: the real server service against the real client view on one fake engine and one
-- clock (board, ride up, toggle the view, alight, ride down). The case lives in tests/isolated/skylift_ride.luau
-- and runs in its own Lune process (tests/lib/Isolated says why).
local Isolated = require("@tests/lib/Isolated")

return function(t)
	Isolated.register(t, "tests/isolated/skylift_ride")
end
