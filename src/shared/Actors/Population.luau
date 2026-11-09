--!strict
-- ReplicatedStorage.Shared.Actors.Population
-- Posts, standing counts, AI floors, overflow floors, reserve and hard cap.
-- Interface (BUILD_PLAN §1.5): pickBody(post, state), floorsOk(state)
-- W0 skeleton stub: no behaviour yet. Requiring this module must have no side effects
-- (rule 4: requiring never starts a thread; services expose init(ctx) and step(dt, now)).

local Population = {}

Population.__skeleton = true

return Population
