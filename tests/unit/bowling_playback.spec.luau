--!strict
-- Client/Minigames/BowlingPlayback against the server's lane on a fake engine: the client's drawing of a throw
-- ends exactly where the server has the pins and the ball, every pin of the rack is written every frame, pit
-- pins are hidden locally and unhidden after, cues fire in order, a cut-short throw restores the rack, and a
-- lane that is not on this client plays nothing. The cases live in tests/isolated/bowling_playback.luau and
-- run in their own Lune process (tests/lib/Isolated says why); each one is reported here as its own test.
local Isolated = require("@tests/lib/Isolated")

return function(t)
	Isolated.register(t, "tests/isolated/bowling_playback")
end
