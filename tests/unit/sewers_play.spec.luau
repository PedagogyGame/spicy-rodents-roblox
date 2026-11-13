--!strict
-- The storm drains end to end, the three sewer lanes joined (the motor on the real bake, World/SewerService on the
-- real town AI, World/SewerAmbience on the client): down the drain at P1's grate, through the chamber, up at the far
-- corner, the police losing it at the grate. The case lives in tests/isolated/sewers_play.luau and runs in its own
-- Lune process (tests/lib/Isolated says why).
local Isolated = require("@tests/lib/Isolated")

return function(t)
	Isolated.register(t, "tests/isolated/sewers_play")
end
