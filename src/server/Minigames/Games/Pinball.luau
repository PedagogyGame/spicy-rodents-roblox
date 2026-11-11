--!strict
-- ServerScriptService.Server.Minigames.Games.Pinball
-- Pinball's server half on the minigame framework: NOT BUILT YET (its Spec, Shared/Minigames/Pinball/Spec, says
-- `soon`). This stub holds its line in Server/Minigames/ServerGames. To build it, return
-- { game = "pinball", new = function(ctx: ServerGame.Ctx): ServerGame.Table ... end }: Server/Minigames/ServerGame
-- lists what a Table may supply and what the Ctx gives it; Games/Bowling and Games/Darts are worked examples.
-- Interface: { game } (a stub: no `new`)

return { game = "pinball" }
