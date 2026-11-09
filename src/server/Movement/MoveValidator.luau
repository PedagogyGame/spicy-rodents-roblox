--!strict
-- ServerScriptService.Server.Movement.MoveValidator
-- Validates client motor packets; log-only until W7.
-- Interface (BUILD_PLAN §1.4): accept(actor, packet) -> ok, correction; pose(id, t)
-- W0 skeleton stub: no behaviour yet. Requiring this module must have no side effects
-- (rule 4: requiring never starts a thread; services expose init(ctx) and step(dt, now)).

local MoveValidator = {}

MoveValidator.__skeleton = true

return MoveValidator
