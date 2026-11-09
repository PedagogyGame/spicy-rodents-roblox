--!strict
-- ServerScriptService.Server.Infection.InfectionService
-- Per-actor infection, red-eye tell, walk-in routing, squirrel share, critical mass.
-- Interface (BUILD_PLAN §1.4, D17): infect, cure, isInfected, townPercent, onCriticalMass
-- W0 skeleton stub: no behaviour yet. Requiring this module must have no side effects
-- (rule 4: requiring never starts a thread; services expose init(ctx) and step(dt, now)).

local InfectionService = {}

InfectionService.__skeleton = true

return InfectionService
