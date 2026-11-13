--!strict
-- The town's wallet as the game runs it, on a fake engine: Server/Economy/Credits on engine Players (the
-- balance a client reads changes the moment the money does), Roles/RoleService holding the wallet's purse, the
-- real MinigameService with the wallet behind ctx.town.charge, and Client/UI/WalletHud drawing it. The cases
-- live in tests/isolated/wallet.luau and run in their own Lune process (tests/lib/Isolated says why); each one
-- is reported here as its own test. The pure core is tests/unit/economy_bank.spec.luau.
local Isolated = require("@tests/lib/Isolated")
local Game = require("@server/Boot/Game")

return function(t)
	Isolated.register(t, "tests/isolated/wallet")

	t.test("Game.gameSeconds: the game clock the passes are timed on, as DayClock publishes it", function()
		-- a server that opened at server time 5000 on game second 6990, read 90 real seconds later
		t.eq(Game.gameSeconds(5090, 5000, 6990, 1), 7080)
		t.eq(Game.gameSeconds(5000, 5000, 6990, 1), 6990)
		t.eq(Game.gameSeconds(5090, 5000, 6990, 4), 7350, "a faster clock runs a pass down faster")
	end)
end
