--!strict
-- Air hockey played through all of its glue on a fake engine (tests/lib/MinigameRig): the real MinigameService
-- with the game's Table and referee on one side, the real MinigameClient with MinigameUI and the game's
-- Controller and Rink on the other, the fake lagged network with the real Net's schema and rate limit between
-- them, the mouse moved in pixels. Walking up to either end, the lobby and the computer's difficulty, a whole
-- match to seven, what the player is shown against what the referee decided at 0, 80 and 150 ms, mouse, keys,
-- stick, touch and the two views, a second person taking the computer's end and handing it back, two people
-- from the lobby, a hand that stops answering, a late watcher, every way off the table, and the server check's
-- own flow (tests/engine/AirHockeyFlow). The cases live in tests/isolated/air_hockey_client.luau and run in
-- their own Lune process (tests/lib/Isolated says why); each one is reported here as its own test.
local Isolated = require("@tests/lib/Isolated")

return function(t)
	Isolated.register(t, "tests/isolated/air_hockey_client")
end
