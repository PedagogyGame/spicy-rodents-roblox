--!strict
-- ReplicatedStorage.Shared.Combat.CombatRules
-- Pounce wind-up/commit/recovery, contact, bite chance, strikes, damage, regen, zig-zag, feint, stamina.
-- Interface (BUILD_PLAN §1.4): pounceVelocity, contact, biteChance, strikeHits, damage, regen, zigzag, feint
-- W0 skeleton stub: no behaviour yet. Requiring this module must have no side effects
-- (rule 4: requiring never starts a thread; services expose init(ctx) and step(dt, now)).

local CombatRules = {}

CombatRules.__skeleton = true

return CombatRules
