--!strict
-- ServerScriptService.Server.WorldGen.Bake
-- Entry point: walks districts and lots in a fixed order, calls builders, stamps BakeHash.
-- Interface (BUILD_PLAN §1.4, D6): run(data, factory) -> Model
-- W0 skeleton stub: no behaviour yet. Requiring this module must have no side effects
-- (rule 4: requiring never starts a thread; services expose init(ctx) and step(dt, now)).

local Bake = {}

Bake.__skeleton = true

return Bake
