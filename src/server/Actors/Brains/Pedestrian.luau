--!strict
-- ServerScriptService.Server.Actors.Brains.Pedestrian
-- Pedestrian brain (one of the per-species brains; the others arrive in W1).
-- Interface (BUILD_PLAN §1.4, §4.4): new(actor, params), think(dt, ctx) -> Intent, suspend() -> snapshot, resume(snapshot), onEvent(evt)
-- W0 skeleton stub: no behaviour yet. Requiring this module must have no side effects
-- (rule 4: requiring never starts a thread; services expose init(ctx) and step(dt, now)).

local Pedestrian = {}

Pedestrian.__skeleton = true

return Pedestrian
