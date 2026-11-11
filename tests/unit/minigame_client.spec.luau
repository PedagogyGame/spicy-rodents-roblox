--!strict
-- Client/Minigames/MinigameClient with the real MinigameUI, BowlingClient and BowlingPlayback on a fake engine,
-- fed the messages a server sends through a bowling game: every screen piece is built and updated without an
-- error, the words are right, the scorecard is not rebuilt when nothing changed, buttons and keys send what
-- they say, the camera and controls are always handed back. The cases live in
-- tests/isolated/minigame_client.luau and run in their own Lune process (tests/lib/Isolated says why); each
-- one is reported here as its own test.
local Isolated = require("@tests/lib/Isolated")

return function(t)
	Isolated.register(t, "tests/isolated/minigame_client")
end
