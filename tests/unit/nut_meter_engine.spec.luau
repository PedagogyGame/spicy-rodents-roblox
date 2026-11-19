--!strict
-- The nut meter on the squirrel's own screen on a fake engine (Client/UI/NutMeter; owner D16 #22): it follows the
-- attributes the server writes (Server/Boot/Game from Foraging/ForageService and HollowService). The cases live in
-- tests/isolated/nut_meter_client.luau and run in their own Lune process (tests/lib/Isolated says why); each one is
-- reported here as its own test.
local Isolated = require("@tests/lib/Isolated")

return function(t)
	Isolated.register(t, "tests/isolated/nut_meter_client")
end
