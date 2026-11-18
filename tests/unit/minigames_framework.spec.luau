--!strict
-- The minigame framework under review (Server/Minigames/MinigameService, Client/Minigames/MinigameClient,
-- Client/UI/MinigameUI, tests/lib/MinigameRig and FakeEngine): what a review found, each finding pinned. The
-- fortune card that outlived its game and the linger timer that closed the wrong one; a game's own keys before
-- Q, gamepad B and Space, the walking pace a game may set, and F that is no kick while a game is open; the rig's
-- network (the real Net's rate limit; no remotes of a game's own); ctx.town; a second prompt that joins another
-- station's game; computer players by name, per table, removed and rolled into a next game; one game's Table
-- that cannot take the others down; the two clocks and a finger that stays one InputObject. The cases live in
-- tests/isolated/minigames_framework.luau and run in their own Lune process (tests/lib/Isolated says why); each
-- one is reported here as its own test.
local Isolated = require("@tests/lib/Isolated")

return function(t)
	Isolated.register(t, "tests/isolated/minigames_framework")
end
