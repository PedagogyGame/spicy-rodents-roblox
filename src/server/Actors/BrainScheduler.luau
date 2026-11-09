--!strict
-- ServerScriptService.Server.Actors.BrainScheduler
-- Time-sliced brain ticks with distance LOD and a per-frame budget.
-- Interface (BUILD_PLAN §1.4, D4): register, unregister, setFocus(fn), metrics()
-- W0 skeleton stub: no behaviour yet. Requiring this module must have no side effects
-- (rule 4: requiring never starts a thread; services expose init(ctx) and step(dt, now)).

local BrainScheduler = {}

BrainScheduler.__skeleton = true

return BrainScheduler
