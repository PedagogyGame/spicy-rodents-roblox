--!strict
-- Client/Minigames/BowlingClient driven by fake input and fake frames on a fake engine: a whole turn from "your
-- turn" to the camera handed back (aim, meter, one release, the throw camera with its one cut, the second
-- ball), a refused and an unanswered throw handing the controls back, typing in chat moving nothing, a click on
-- a button not being a throw, the turn clock and its warning. The cases live in
-- tests/isolated/bowling_client.luau and run in their own Lune process (tests/lib/Isolated says why); each one
-- is reported here as its own test.
local Isolated = require("@tests/lib/Isolated")

return function(t)
	Isolated.register(t, "tests/isolated/bowling_client")
end
