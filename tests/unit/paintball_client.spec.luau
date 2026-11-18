--!strict
-- The paintball client played through the real minigame framework on a fake engine: keys, the mouse, a gamepad
-- and fingers in; what is drawn (puppets, balls, splats, the marker, the HUD's words, the camera's height) and
-- what is sent (poses and clicks through the real Shared/Net) out. The case plays the server. The cases live in
-- tests/isolated/paintball_client.luau and run in their own Lune process (tests/lib/Isolated says why); each one
-- is reported here as its own test. The two headless cores have their own spec beside this one
-- (paintball_client_core.spec.luau).
local Isolated = require("@tests/lib/Isolated")

return function(t)
	Isolated.register(t, "tests/isolated/paintball_client")
end
