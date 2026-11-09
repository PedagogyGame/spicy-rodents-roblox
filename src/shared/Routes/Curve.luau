--!strict
-- ReplicatedStorage.Shared.Routes.Curve
-- Centripetal Catmull-Rom (alpha 0.5, three.js r160 phantom ends, 200 arc divisions).
-- Interface (BUILD_PLAN routes_movement §1-§14): new(points), getPointAt(u), getSpacedPoints(n), length()
-- W0 skeleton stub: no behaviour yet. Requiring this module must have no side effects
-- (rule 4: requiring never starts a thread; services expose init(ctx) and step(dt, now)).

local Curve = {}

Curve.__skeleton = true

return Curve
