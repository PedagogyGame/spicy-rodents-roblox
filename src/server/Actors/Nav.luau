--!strict
-- ServerScriptService.Server.Actors.Nav
-- Sidewalk lane graph, interior room graphs, cached escapes.
-- Interface (BUILD_PLAN §1.4): path(from, to, opts), roomGraph(lotId)
-- W0 skeleton stub: no behaviour yet. Requiring this module must have no side effects
-- (rule 4: requiring never starts a thread; services expose init(ctx) and step(dt, now)).

local Nav = {}

Nav.__skeleton = true

return Nav
