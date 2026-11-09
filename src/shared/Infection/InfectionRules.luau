--!strict
-- ReplicatedStorage.Shared.Infection.InfectionRules
-- Per-actor infection, town %, squirrel-share maturation, critical mass, cure-time multiplier.
-- Interface (BUILD_PLAN §1.4): townPercent, squirrelShare, criticalMass, cureTime
-- W0 skeleton stub: no behaviour yet. Requiring this module must have no side effects
-- (rule 4: requiring never starts a thread; services expose init(ctx) and step(dt, now)).

local InfectionRules = {}

InfectionRules.__skeleton = true

return InfectionRules
