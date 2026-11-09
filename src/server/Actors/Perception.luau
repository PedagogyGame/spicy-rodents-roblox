--!strict
-- ServerScriptService.Server.Actors.Perception
-- Spatial-grid threat queries; ported spotted() with the v5.4 concealment terms.
-- Interface (BUILD_PLAN §1.4): spotted(observer, target), nearby(pos, r, filter)
-- W0 skeleton stub: no behaviour yet. Requiring this module must have no side effects
-- (rule 4: requiring never starts a thread; services expose init(ctx) and step(dt, now)).

local Perception = {}

Perception.__skeleton = true

return Perception
