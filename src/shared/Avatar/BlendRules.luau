--!strict
-- ReplicatedStorage.Shared.Avatar.BlendRules
-- 70/30 avatar composition; palette clamp; bizarre-avatar signature pick.
-- Interface (BUILD_PLAN §1.4, D13): traits(desc, productInfo), compose(species, stock, traits) -> Look, isBizarre
-- W0 skeleton stub: no behaviour yet. Requiring this module must have no side effects
-- (rule 4: requiring never starts a thread; services expose init(ctx) and step(dt, now)).

local BlendRules = {}

BlendRules.__skeleton = true

return BlendRules
