--!strict
-- The alley roof run on the squirrel's own screen on a fake engine (BRIEF_ADDENDUM D9, lane L6): the sneak meter
-- (Client/UI/SneakMeter) following the server's RafterMeter and RafterSeen, and the held squirrel's controller
-- toasting "Jump now to reach the branch" and "Q: drop onto the roof" at the ridge's and the bough's ends. The cases
-- live in tests/isolated/alley_roof_client.luau and run in their own Lune process (tests/lib/Isolated says why);
-- each one is reported here as its own test.
local Isolated = require("@tests/lib/Isolated")

return function(t)
	Isolated.register(t, "tests/isolated/alley_roof_client")
end
