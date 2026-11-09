--!strict
-- ReplicatedStorage.Shared.World.Ground
-- Ground, roofs and porches as a pure function of position and a reference height.
-- Interface (BUILD_PLAN §1.4): groundAt(x, z, refY), roofAt(x, z, refY), surfaceKind(x, z)
-- W0 skeleton stub: no behaviour yet. Requiring this module must have no side effects
-- (rule 4: requiring never starts a thread; services expose init(ctx) and step(dt, now)).

local Ground = {}

Ground.__skeleton = true

return Ground
