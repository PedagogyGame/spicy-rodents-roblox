--!strict
-- ReplicatedStorage.Shared.World.Height
-- Verbatim baseTerrainHeight/terrainHeight port (worldgen_core §3, §16).
-- Interface (BUILD_PLAN §1.4): base(x, z), at(x, z)
-- W0 skeleton stub: no behaviour yet. Requiring this module must have no side effects
-- (rule 4: requiring never starts a thread; services expose init(ctx) and step(dt, now)).

local Height = {}

Height.__skeleton = true

return Height
