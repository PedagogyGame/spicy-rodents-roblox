--!strict
-- ReplicatedStorage.Shared.Util.BufferCodec
-- buffer encode/decode for high-rate streams (Motor.State, VehiclePoses).
-- Interface (BUILD_PLAN §1.6): encode(schema, t) -> buffer, decode(schema, buf) -> t
-- W0 skeleton stub: no behaviour yet. Requiring this module must have no side effects
-- (rule 4: requiring never starts a thread; services expose init(ctx) and step(dt, now)).

local BufferCodec = {}

BufferCodec.__skeleton = true

return BufferCodec
