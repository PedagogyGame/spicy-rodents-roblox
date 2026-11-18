--!strict
-- Server/Rides/SkyLiftService on a fake engine against Shared/Rides/SkyLift's timetable: riders up and down,
-- refusals with words, a full cabin, walking away, a player leaving or swapping bodies mid-ride, a soak with
-- nothing left behind, the gate's board and arm, the telescope and the counter's lunch. The cases live in
-- tests/isolated/skylift_service.luau and run in their own Lune process (tests/lib/Isolated says why); each
-- one is reported here as its own test.
local Isolated = require("@tests/lib/Isolated")

return function(t)
	Isolated.register(t, "tests/isolated/skylift_service")
end
