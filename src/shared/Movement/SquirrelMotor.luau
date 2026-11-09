--!strict
-- ReplicatedStorage.Shared.Movement.SquirrelMotor
-- Squirrel rail/ground motor shared by AI (server) and players (client).
-- Interface (BUILD_PLAN §1.4, D2): new(params), step(state, input, dt, world) -> state, events, serialize, deserialize, envelope
-- W0 skeleton stub: no behaviour yet. Requiring this module must have no side effects
-- (rule 4: requiring never starts a thread; services expose init(ctx) and step(dt, now)).

local SquirrelMotor = {}

SquirrelMotor.__skeleton = true

return SquirrelMotor
