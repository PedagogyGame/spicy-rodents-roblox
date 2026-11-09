--!strict
-- ReplicatedStorage.Shared.Time.DayCurve
-- Non-linear day curve that holds sunrise, golden hours, sunset and blue hour.
-- Interface (BUILD_PLAN §3.8 clock.dayCurve): hourAt(dayFraction)
-- W0 skeleton stub: no behaviour yet. Requiring this module must have no side effects
-- (rule 4: requiring never starts a thread; services expose init(ctx) and step(dt, now)).

local DayCurve = {}

DayCurve.__skeleton = true

return DayCurve
