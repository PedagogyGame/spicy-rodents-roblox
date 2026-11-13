--!strict
-- The real paintball client against the real paintball server: the lane's own cases play the server
-- themselves; these put nothing in anything's place (the real framework, service, match model, brains and
-- building), and so run by themselves once the four lanes are joined. Until then the service and the match
-- model are the contract's stubs, and this spec is one line that says so. The cases live in
-- tests/isolated/paintball_client_joined.luau and run in their own Lune process (tests/lib/Isolated says why).
local Isolated = require("@tests/lib/Isolated")

return function(t)
	Isolated.register(t, "tests/isolated/paintball_client_joined")
end
