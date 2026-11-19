--!strict
-- The player's vehicles as Server/Actors/DeviceService builds them (Shared/Vehicles/Placeholder.build): one camera eye
-- over the Seat at a seated driver's eyes, the Seat on the drawn saddle or seat, a seated R15 that fits, the box the
-- only solid part, shadows from the big parts only (review of feat/bikes-art). The cases live in
-- tests/isolated/vehicles_built.luau and run in their own Lune process (tests/lib/Isolated says why); each one is
-- reported here as its own test.
local Isolated = require("@tests/lib/Isolated")

return function(t)
	Isolated.register(t, "tests/isolated/vehicles_built")
end
