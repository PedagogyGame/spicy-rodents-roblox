--!strict
-- ReplicatedStorage.Shared.Config.Flags
-- Feature flags; dev gating (Studio or the owner's UserId).
-- Interface (BUILD_PLAN §1.4): enabled(name), isDev(player)
-- W0 skeleton stub: no behaviour yet. Requiring this module must have no side effects
-- (rule 4: requiring never starts a thread; services expose init(ctx) and step(dt, now)).

local Flags = {}

Flags.__skeleton = true

return Flags
