--!strict
-- ReplicatedStorage.Shared.Util.Rng
-- mulberry32 port (seeded RNG shared with the v5.4 reference).
-- Interface (BUILD_PLAN §1.4): new(seed), next(), range(a, b)
-- W0 skeleton stub: no behaviour yet. Requiring this module must have no side effects
-- (rule 4: requiring never starts a thread; services expose init(ctx) and step(dt, now)).

local Rng = {}

Rng.__skeleton = true

return Rng
