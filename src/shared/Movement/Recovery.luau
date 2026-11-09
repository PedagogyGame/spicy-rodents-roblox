--!strict
-- ReplicatedStorage.Shared.Movement.Recovery
-- River-fall recovery, last-safe-position history, unstick for the Reset button.
-- Interface (BUILD_PLAN §1.4): safePos(actor), riverRecover(pos), onVehicleMoved(car, riders)
-- W0 skeleton stub: no behaviour yet. Requiring this module must have no side effects
-- (rule 4: requiring never starts a thread; services expose init(ctx) and step(dt, now)).

local Recovery = {}

Recovery.__skeleton = true

return Recovery
