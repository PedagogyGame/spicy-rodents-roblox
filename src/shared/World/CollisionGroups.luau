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
-- Pure. Interface: GROUPS; APART (pairs that do not meet); DEFAULT; meets(a, b) -> boolean; solidToSquirrel(group?),
--   solidToPeople(group?) -> boolean

local CollisionGroups = {}

CollisionGroups.DEFAULT = "Default"
CollisionGroups.BOWLING_PHYSICS = "BowlingPhysics"
CollisionGroups.LANE_GUARD = "LaneGuard"
CollisionGroups.PEOPLE_FENCE = "PeopleFence"
CollisionGroups.SQUIRREL_FENCE = "SquirrelFence"
CollisionGroups.SQUIRREL_PROBE = "SquirrelProbe"

CollisionGroups.GROUPS = {
	CollisionGroups.BOWLING_PHYSICS,
	CollisionGroups.LANE_GUARD,
	CollisionGroups.PEOPLE_FENCE,
	CollisionGroups.SQUIRREL_FENCE,
	CollisionGroups.SQUIRREL_PROBE,
}

CollisionGroups.APART = {
	{ CollisionGroups.LANE_GUARD, CollisionGroups.BOWLING_PHYSICS },
	{ CollisionGroups.PEOPLE_FENCE, CollisionGroups.SQUIRREL_PROBE },
	{ CollisionGroups.PEOPLE_FENCE, CollisionGroups.BOWLING_PHYSICS },
	{ CollisionGroups.SQUIRREL_FENCE, CollisionGroups.DEFAULT },
	{ CollisionGroups.SQUIRREL_FENCE, CollisionGroups.BOWLING_PHYSICS },
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

return CollisionGroups
