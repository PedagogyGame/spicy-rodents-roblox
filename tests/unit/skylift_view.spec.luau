--!strict
-- The sky lift as a client sees it (Client/Rides/SkyLiftView) and the Lookout's telescope (Client/Rides/Telescope)
-- on the fake engine, the sky-lift plan's lane-5 proof: six cabins from the template, placed every frame from the
-- shared clock; every seat where the server seats its rider at the same clock (within 0.05); no cabin faster than
-- the line between frames through both stations with a jittery clock; every eye inside its cabin and at least 4.5
-- over the floor; doors, riders, night lights, the turning wheels, the words; the telescope in and out and its
-- limits. The cases live in tests/isolated/skylift_view.luau and run in their own Lune process (tests/lib/Isolated
-- says why); each one is reported here as its own test.
local Isolated = require("@tests/lib/Isolated")

return function(t)
	Isolated.register(t, "tests/isolated/skylift_view")
end
