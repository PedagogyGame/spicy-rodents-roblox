--!strict
-- The street riders as Actors/BodyFactory builds them (Server/AI/Puppets.build): the rider its town slot names, the
-- root at the old 2.2-stud height, the only part that takes queries (review of feat/bikes-art). The cases live in
-- tests/isolated/riders_built.luau and run in their own Lune process (tests/lib/Isolated says why); each one is
-- reported here as its own test.
local Isolated = require("@tests/lib/Isolated")

return function(t)
	Isolated.register(t, "tests/isolated/riders_built")
end
