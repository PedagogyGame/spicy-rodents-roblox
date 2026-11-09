--!strict
-- ServerScriptService.Server.Actors.ActorService
-- Actor registry and lifecycle; bodies created once, never destroyed.
-- Interface (BUILD_PLAN §1.4, §1.5): spawn, get, query, nearest, kill, setBodyMode; signals Possessed, Released, Died
-- W0 skeleton stub: no behaviour yet. Requiring this module must have no side effects
-- (rule 4: requiring never starts a thread; services expose init(ctx) and step(dt, now)).

local ActorService = {}

ActorService.__skeleton = true

return ActorService
