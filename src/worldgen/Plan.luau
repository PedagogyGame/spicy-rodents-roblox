--!strict
-- ServerScriptService.Server.WorldGen.Plan
-- Lots to a deterministic BuildPlan (parts, doors, prompts, sockets, colliders, nav, routes, terrain, roads).
-- Interface (BUILD_PLAN §1.4): plan(lot, lotType, ctx) -> BuildPlan
-- W0 skeleton stub: no behaviour yet. Requiring this module must have no side effects
-- (rule 4: requiring never starts a thread; services expose init(ctx) and step(dt, now)).

local Plan = {}

Plan.__skeleton = true

return Plan
