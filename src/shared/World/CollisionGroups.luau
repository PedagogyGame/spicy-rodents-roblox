--!strict
-- ReplicatedStorage.Shared.World.CollisionGroups
-- The game's collision groups, and who meets what, in one place: the server registers them (Server/Attractions/
-- AttractionService), the squirrel's world queries run in the group SQUIRREL_PROBE (Client/World/ClientWorld), and the
-- specs judge baked parts by the same rule (tests/lib/BakedWorld for the squirrel, tests/lib/HumanWalk for people).
-- People's bodies are in Roblox's "Default" group. (A part's CanQuery does not help here: Roblox only honours
-- CanQuery = false on a part that does not collide.)
--   BowlingPhysics  the lanes' balls and pins (baked)
--   LaneGuard       keeps people off the lanes; the ball and the pins pass
--   PeopleFence     keeps people on the alley roof's walkway and guard platform; squirrels pass (AlleyRoof)
--   SquirrelFence   keeps squirrels off the people's stair onto the roof; people pass (AlleyRoof, owner Q12's default)
--   SquirrelProbe   the group the squirrel's own queries (ground, walls) run in
--   SightRay        the group a person's line of sight runs in (Server/Attractions/RafterService): the three invisible
--                   walls above (LaneGuard, PeopleFence, SquirrelFence) do not stop it; what can be seen does
-- What a raycast hits, as Roblox decides it: a part that takes queries (every colliding part does, whatever its
-- CanQuery says) and whose group meets the ray's (rayHits; the specs judge baked parts by it).
-- Pure. Interface: GROUPS; APART (pairs that do not meet); DEFAULT; meets(a, b) -> boolean; solidToSquirrel(group?),
--   solidToPeople(group?) -> boolean; rayHits(rayGroup?, collide, query, group?) -> boolean

local CollisionGroups = {}

CollisionGroups.DEFAULT = "Default"
CollisionGroups.BOWLING_PHYSICS = "BowlingPhysics"
CollisionGroups.LANE_GUARD = "LaneGuard"
CollisionGroups.PEOPLE_FENCE = "PeopleFence"
CollisionGroups.SQUIRREL_FENCE = "SquirrelFence"
CollisionGroups.SQUIRREL_PROBE = "SquirrelProbe"
CollisionGroups.SIGHT_RAY = "SightRay"

CollisionGroups.GROUPS = {
	CollisionGroups.BOWLING_PHYSICS,
	CollisionGroups.LANE_GUARD,
	CollisionGroups.PEOPLE_FENCE,
	CollisionGroups.SQUIRREL_FENCE,
	CollisionGroups.SQUIRREL_PROBE,
	CollisionGroups.SIGHT_RAY,
}

CollisionGroups.APART = {
	{ CollisionGroups.LANE_GUARD, CollisionGroups.BOWLING_PHYSICS },
	{ CollisionGroups.PEOPLE_FENCE, CollisionGroups.SQUIRREL_PROBE },
	{ CollisionGroups.PEOPLE_FENCE, CollisionGroups.BOWLING_PHYSICS },
	{ CollisionGroups.SQUIRREL_FENCE, CollisionGroups.DEFAULT },
	{ CollisionGroups.SQUIRREL_FENCE, CollisionGroups.BOWLING_PHYSICS },
	{ CollisionGroups.SIGHT_RAY, CollisionGroups.LANE_GUARD },
	{ CollisionGroups.SIGHT_RAY, CollisionGroups.PEOPLE_FENCE },
	{ CollisionGroups.SIGHT_RAY, CollisionGroups.SQUIRREL_FENCE },
}

-- Do parts of these two groups meet? (Every pair meets unless APART says otherwise, as in Roblox.)
function CollisionGroups.meets(a: string?, b: string?): boolean
	local x, y = a or CollisionGroups.DEFAULT, b or CollisionGroups.DEFAULT
	for _, pair in CollisionGroups.APART do
		if (pair[1] == x and pair[2] == y) or (pair[1] == y and pair[2] == x) then
			return false
		end
	end
	return true
end

-- Does a colliding part of this group stop the squirrel (its queries run in SQUIRREL_PROBE)?
function CollisionGroups.solidToSquirrel(group: string?): boolean
	return CollisionGroups.meets(CollisionGroups.SQUIRREL_PROBE, group)
end

-- Does a colliding part of this group stop a person (a body in the Default group)?
function CollisionGroups.solidToPeople(group: string?): boolean
	return CollisionGroups.meets(CollisionGroups.DEFAULT, group)
end

-- Does a ray cast in `rayGroup` hit a part (CanCollide `collide`, CanQuery `query`, in `group`)? Roblox honours
-- CanQuery = false only on a part that does not collide, and a ray passes every part whose group its own does not
-- meet.
function CollisionGroups.rayHits(rayGroup: string?, collide: boolean, query: boolean, group: string?): boolean
	return (collide or query) and CollisionGroups.meets(rayGroup, group)
end

return CollisionGroups
