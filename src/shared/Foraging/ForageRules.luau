--!strict
-- ReplicatedStorage.Shared.Foraging.ForageRules
-- Yields, cooldowns on the game clock, carry cap, hollow meter, ownership, raid, winter, stink.
-- Interface (BUILD_PLAN §1.4): yield, meter, owner, stink, canFire, survives
-- W0 skeleton stub: no behaviour yet. Requiring this module must have no side effects
-- (rule 4: requiring never starts a thread; services expose init(ctx) and step(dt, now)).

local ForageRules = {}

ForageRules.__skeleton = true

return ForageRules
