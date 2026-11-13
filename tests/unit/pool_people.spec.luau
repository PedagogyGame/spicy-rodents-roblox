--!strict
-- Eight-ball with other people on the fake engine (tests/lib/MinigameRig): a second player and a leaver, a
-- watcher, a slow line, the idle clock, walking away, the gamepad and the touch screen. The cases live in
-- tests/isolated/pool_people.luau and run in their own Lune process (tests/lib/Isolated says why); each one is
-- reported here as its own test.
local Isolated = require("@tests/lib/Isolated")

return function(t)
	Isolated.register(t, "tests/isolated/pool_people")
end
