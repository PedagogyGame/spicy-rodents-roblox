--!strict
-- ReplicatedStorage.Shared.Roles.Ladder
-- THE ladder, stated once, with every number it uses in Ladder.params.
-- Interface (BUILD_PLAN §3.7, rule 2): rungs, subroles, sideExits, score(rung, stats), rankOrder, slots(rung, state), resolve(event, ctx) -> { Transition }
-- W0 skeleton stub: no behaviour yet. Requiring this module must have no side effects
-- (rule 4: requiring never starts a thread; services expose init(ctx) and step(dt, now)).

local Ladder = {}

Ladder.__skeleton = true

return Ladder
