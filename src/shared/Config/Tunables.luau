--!strict
-- ReplicatedStorage.Shared.Config.Tunables
-- Every gameplay number with unit, range and source; stud conversion on read; live overrides.
-- Interface (BUILD_PLAN §3.8): get(path), meta(path), onChanged(path, fn), applyOverrides(map), diff()
-- W0 skeleton stub: no behaviour yet. Requiring this module must have no side effects
-- (rule 4: requiring never starts a thread; services expose init(ctx) and step(dt, now)).

local Tunables = {}

Tunables.__skeleton = true

return Tunables
