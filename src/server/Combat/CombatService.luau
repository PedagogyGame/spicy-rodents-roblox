--!strict
-- ServerScriptService.Server.Combat.CombatService
-- Server pounce, kick, swing, baton, shove and defender blows; health and death.
-- Interface (BUILD_PLAN §1.4): requestPounce, requestStrike, damage, healthOf; signals Hit, Kick, Killed
-- W0 skeleton stub: no behaviour yet. Requiring this module must have no side effects
-- (rule 4: requiring never starts a thread; services expose init(ctx) and step(dt, now)).

local CombatService = {}

CombatService.__skeleton = true

return CombatService
