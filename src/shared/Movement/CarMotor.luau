--!strict
-- ReplicatedStorage.Shared.Movement.CarMotor
-- Kinematic arcade car motor (AI fleet and player patrol cars).
-- Interface (BUILD_PLAN §1.4, D10): new, step, serialize, deserialize, envelope
-- W0 skeleton stub: no behaviour yet. Requiring this module must have no side effects
-- (rule 4: requiring never starts a thread; services expose init(ctx) and step(dt, now)).

local CarMotor = {}

CarMotor.__skeleton = true

return CarMotor
