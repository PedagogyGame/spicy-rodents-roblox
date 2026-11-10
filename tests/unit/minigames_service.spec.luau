--!strict
-- Server/Minigames/MinigameService with real BowlingLane hardware on a fake engine: the bowling glue end to
-- end (a whole game of real throws, a gutter ball, the thrower leaving mid-roll, an idle turn on a half frame,
-- a computer opponent, a squirrel on the lane, refusals, an abandoned throw). The cases live in
-- tests/isolated/minigames_service.luau and run in their own Lune process (tests/lib/Isolated says why); each
-- one is reported here as its own test.
local Isolated = require("@tests/lib/Isolated")

return function(t)
	Isolated.register(t, "tests/isolated/minigames_service")
end
