--!strict
-- The paintball server (Server/Minigames/Paintball/PaintballService; checklist PB-3, PB-4, PB-6, PB-11,
-- PB-12, PB-14): a whole game on the fake engine, with the real MinigameService and Session, a scripted
-- match model in the stub Rules' place and scripted clients on paintball's own wire. The cases live in
-- tests/isolated/ (they install the fake engine: tests/lib/Isolated says why) and are reported here one by
-- one:
--   paintball_server        the door and the pass, the roster and its bots, rolling on, the audience, a
--                           late joiner; what a client may claim about where it is
--   paintball_server_fire   the click: what makes it a shot, every tag, splats; liars; lag, jitter and loss
--   paintball_server_joined the service with nothing put in anything's place: the real match model, the real
--                           brains and the game's own building. One line here while Rules is the contract's
--                           stub; a whole match and a person among the bots once the lanes are joined
--   paintball_server_meeting the client lane's own seat and show behind a connection, against the real service:
--                           one line here while the client's cores are not in the tree
local Isolated = require("@tests/lib/Isolated")

return function(t)
	Isolated.register(t, "tests/isolated/paintball_server")
	Isolated.register(t, "tests/isolated/paintball_server_fire")
	Isolated.register(t, "tests/isolated/paintball_server_joined")
	Isolated.register(t, "tests/isolated/paintball_server_meeting")
end
