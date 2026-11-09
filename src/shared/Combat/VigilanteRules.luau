--!strict
-- ReplicatedStorage.Shared.Combat.VigilanteRules
-- Keeps exactly round(0.08 x human actors) vigilante flags on AI bodies.
-- Interface (BUILD_PLAN §1.4): rebalance(humans, flags) -> flags
-- W0 skeleton stub: no behaviour yet. Requiring this module must have no side effects
-- (rule 4: requiring never starts a thread; services expose init(ctx) and step(dt, now)).

local VigilanteRules = {}

VigilanteRules.__skeleton = true

return VigilanteRules
