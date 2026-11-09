--!strict
-- ServerScriptService.Server.Drone.DroneService
-- Launch and dock; flight validation; ReplicationFocus; spot-and-mark.
-- Interface (BUILD_PLAN §1.4): launch, dock, mark(pilot, aim), activeMarks
-- W0 skeleton stub: no behaviour yet. Requiring this module must have no side effects
-- (rule 4: requiring never starts a thread; services expose init(ctx) and step(dt, now)).

local DroneService = {}

DroneService.__skeleton = true

return DroneService
