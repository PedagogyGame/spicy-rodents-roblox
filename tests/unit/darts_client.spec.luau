--!strict
-- Darts played from start to finish through all of its glue on a fake engine: the real MinigameService with
-- its Dartboard on one side, the real MinigameClient with MinigameUI and DartsClient on the other, a fake
-- network between them, the mouse moved in pixels. Walking up and the prompt, the lobby and 501 or Cricket,
-- three-dart turns, busts and a double-out, a whole game of cricket, the end of a game, leaving in the middle
-- and at the end, a computer player, touch, and the main client's three rules (shots inside CameraRig.hold,
-- the cursor through CameraRig.wantCursor, input flushed at each hand-over). The cases live in
-- tests/isolated/darts_client.luau and run in their own Lune process (tests/lib/Isolated says why); each one
-- is reported here as its own test.
local Isolated = require("@tests/lib/Isolated")

return function(t)
	Isolated.register(t, "tests/isolated/darts_client")
end
