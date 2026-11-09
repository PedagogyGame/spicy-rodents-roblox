--!strict
-- ReplicatedStorage.Shared.Time.Clock
-- Game time from GetServerTimeNow() plus an epoch attribute.
-- Interface (BUILD_PLAN §1.4, D19): now(), game() -> { day, hour, week, isWinter, lunarAge, phase }
-- W0 skeleton stub: no behaviour yet. Requiring this module must have no side effects
-- (rule 4: requiring never starts a thread; services expose init(ctx) and step(dt, now)).

local Clock = {}

Clock.__skeleton = true

return Clock
