--!strict
-- Server/Attractions/RafterService on a fake engine (BRIEF_ADDENDUM D9, lane L5): the people under the alley's
-- rafters spot a squirrel that walks (not one that creeps), say a line, call out the lane, make it glow for 6 s, show
-- its player the meter; the Spicy Rodent sets off the alarm (people run, an officer comes to the door); a guard's
-- kick reaches the louvre but not inside the vent unit. The cases live in tests/isolated/rafter_service.luau and run
-- in their own Lune process (tests/lib/Isolated says why); each one is reported here as its own test.
local Isolated = require("@tests/lib/Isolated")

return function(t)
	Isolated.register(t, "tests/isolated/rafter_service")
end
