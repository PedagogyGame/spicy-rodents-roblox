--!strict
-- Server/World/SewerService.start on a fake engine (the terrain carve and the cover going on and off). The cases
-- live in tests/isolated/sewer_service.luau and run in their own Lune process (tests/lib/Isolated says why); each
-- one is reported here as its own test. The cover itself, on the real town AI, is tests/unit/sewers_cover.
local Isolated = require("@tests/lib/Isolated")

return function(t)
	Isolated.register(t, "tests/isolated/sewer_service")
end
