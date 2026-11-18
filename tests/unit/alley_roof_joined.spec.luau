--!strict
-- The alley roof run joined into the game, end to end (BRIEF_ADDENDUM D9, D10): a squirrel on the real motor climbs
-- the house, leaps to the bough, crosses, goes in at the louvre and out onto a rafter, where walking it is spotted
-- by a computer bowler and creeping it is not; a person climbs the stair to the platform and kicks a squirrel at the
-- louvre, not one inside the unit; Boot/Game and Client/Main start it. The case lives in
-- tests/isolated/alley_roof_joined.luau and runs in its own Lune process (tests/lib/Isolated says why).
local Isolated = require("@tests/lib/Isolated")

return function(t)
	Isolated.register(t, "tests/isolated/alley_roof_joined")
end
