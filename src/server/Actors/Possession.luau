--!strict
-- ServerScriptService.Server.Actors.Possession
-- THE single handoff mechanism.
-- Interface (BUILD_PLAN §1.5, D1): possess(player, actor), release(player, why), swap(player, toActor), controllerOf(actor)
-- W0 skeleton stub: no behaviour yet. Requiring this module must have no side effects
-- (rule 4: requiring never starts a thread; services expose init(ctx) and step(dt, now)).

local Possession = {}

Possession.__skeleton = true

return Possession
