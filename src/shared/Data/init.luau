--!strict
-- ReplicatedStorage.Shared.Data
-- Read-only accessors over the compiled data in Shared.Generated (compiler output of tools/compile).
-- Interface (BUILD_PLAN §1.4, §3): lots(), lot(id), lotType(t), routes(), lanes(), nav(), colliders(), forage(), hollows(), quests(), markers(), assets(), bakeHash
-- W0 skeleton stub: no behaviour yet. Requiring this module must have no side effects
-- (rule 4: requiring never starts a thread; services expose init(ctx) and step(dt, now)).

local Data = {}

Data.__skeleton = true

return Data
