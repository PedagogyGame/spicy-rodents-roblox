--!strict
-- The people's stair and the guard platform as baked (tools/bake/alley/RoofStairs; BRIEF_ADDENDUM D9, owner questions
-- Q3, Q6, Q12's defaults), on the alley baked in memory by its own bake code (tests/lib/BakedWorld.bakeAlley), with a
-- person's body (tests/lib/HumanWalk: an R15 Humanoid's 2 x 5.2, stepping 0.75, jumping 7.2):
--   * walking from the foot of the stair in the yard, a person climbs all three flights and reaches the top landing,
--     the walkway, the strip in front of the louvre (the guard's spot), the north strip and the apron;
--   * jumping and falling as well, a person who starts on the platform never gets anywhere at roof height outside the
--     fenced area round the vent and the stair (not the open roof, the unit's top, the duct, the hall's roof);
--   * the stair stands on the ground: the pad, every column reaches it, no tread is under the ground;
--   * a squirrel passes the people's fence (between its posts, under its bottom rail) and is stopped at the top of
--     the people's stair (the squirrel fence, Q12); a person passes the squirrel fence.
local AlleyLayout = require("@shared/Attractions/AlleyLayout")
local AlleyRoof = require("@shared/Attractions/AlleyRoof")
local CollisionGroups = require("@shared/World/CollisionGroups")
local BakedWorld = require("../lib/BakedWorld")
local HumanWalk = require("../lib/HumanWalk")

local R = AlleyRoof
local ST = R.STAIR

return function(t)
	local world, place, root = BakedWorld.bakeAlley()
	local function W(X: number, Y: number, D: number): (number, number, number)
		return AlleyLayout.toWorld(place, X, Y, D)
	end
	local function L(x: number, y: number, z: number): (number, number, number)
		return AlleyLayout.toLocal(place, x, y, z)
	end
	-- the search: the yard behind the wing and the wing's roof round the vent (local X 95..156, D 2..40)
	local ax, _, az = W(95, 0, 2)
	local bx, _, bz = W(156, 0, 40)
	local box = { x0 = math.min(ax, bx), x1 = math.max(ax, bx), z0 = math.min(az, bz), z1 = math.max(az, bz) }
	local function startAtFoot(): { number }
		local X, D = ST.footX + 2.5, (ST.d0 + ST.d1) / 2
		local x, _, z = W(X, 0, D)
		return { x, world.groundAt(x, z, 1000), z }
	end
	local function reached(reach: HumanWalk.Reach, X: number, Y: number, D: number): boolean
		local x, y, z = W(X, Y, D)
		for _, h in reach.at(x, z) do
			if math.abs(h - y) < 0.3 then
				return true
			end
		end
		return false
	end

	t.test("walking from the stair's foot a person reaches every landing, the platform and the apron", function()
		local o = table.clone(box) :: any
		local reach = HumanWalk.fill(world, startAtFoot(), o)
		for i, l in ST.landings do
			t.truthy(reached(reach, (l.x0 + l.x1) / 2, l.y, (ST.d0 + ST.d1) / 2), `landing {i}`)
		end
		local y = R.PLATFORM.y
		for _, r in R.PLATFORM.rects do
			for _, c in
				{ { r.x0 + 1.2, r.d0 + 1.2 }, { r.x1 - 1.2, r.d1 - 1.2 }, { (r.x0 + r.x1) / 2, (r.d0 + r.d1) / 2 } }
			do
				t.truthy(reached(reach, c[1], y, c[2]), `the {r.name} at ({c[1]}, {c[2]})`)
			end
		end
		t.truthy(reached(reach, R.GUARD.x, y, R.GUARD.d), "the guard's spot at the louvre")
		local a = R.APRON
		t.truthy(reached(reach, (a.x0 + a.x1) / 2, R.WING_ROOF.y, R.MOUTH.d + 3), "the apron in front of the louvre")
		print(`      {#reach.states} places a person can walk to from the stair's foot`)
	end)

	t.test("jumping and falling, a person on the platform never gets out at roof height", function()
		local F = R.PEOPLE_FENCE
		-- out: anywhere at the hall's deck or higher; at roof height outside the fence and the stair; on the unit or
		-- the duct (standing on a rail or the back parapet inside the fence is allowed: nothing more comes of it)
		local function allowed(X: number, Y: number, D: number): boolean
			if Y >= R.HALL_ROOF.deckY0 - 1 then
				return false
			end
			if Y < R.WING_ROOF.y - 1.5 then
				return true -- the stair's flights, or off it into the yard
			end
			local inFence = X >= 101.8 - 0.01 and X <= 121 and D >= 8 and D <= 30.8
			local onStair = X >= 101.8 - 0.01 and X <= ST.footX + 3 and D >= 30.4 and D <= ST.d1 + 1
			local c = R.AHU.curb
			local onUnit = X >= 101.8 and X <= c.x1 and D >= c.d0 and D <= c.d1 and Y > R.WING_ROOF.copingY + 0.05
			return (inFence or onStair) and not onUnit
		end
		local escapes = {}
		local o = table.clone(box) :: any
		o.jump = true
		o.stop = function(x: number, y: number, z: number): boolean
			local X, Y, D = L(x, y, z)
			if not allowed(X, Y, D) then
				table.insert(escapes, string.format("(%.1f, %.1f, %.1f)", X, Y, D))
				return true
			end
			return Y < -1 -- in the yard: no further
		end
		local sx, sy, sz = W(R.GUARD.x, R.PLATFORM.y, R.GUARD.d)
		local reach = HumanWalk.fill(world, { sx, sy, sz }, o)
		t.eq(#escapes, 0, `out of the fenced area at: {table.concat(escapes, " ", 1, math.min(#escapes, 12))}`)
		t.truthy(F.wallY1 - R.PLATFORM.y > HumanWalk.JUMP + HumanWalk.HEAD, "the fence's wall is above a jump")
		print(`      {#reach.states} places reached jumping and falling, none outside the fence`)
	end)

	t.test("the stair stands on the ground", function()
		local stairs = root:FindFirstChild("RoofStairs") :: any
		for _, d in stairs:GetDescendants() do
			if d:IsA("BasePart") and (d.Name == "Column" or d.Name == "FootPad") then
				local p = d.CFrame.Position
				local bottom = p.Y - d.Size.Y / 2
				local g = world.terrainAt(p.X, p.Z)
				t.truthy(bottom <= g + 0.05, `{d:GetFullName()} stops {bottom - g} above the ground`)
				t.truthy(bottom >= g - 1.0, `{d:GetFullName()} sinks {g - bottom} into the ground`)
			end
		end
		for _, f in ST.flights do
			for k = 1, 8 do
				local X = f.x0 - (k - 0.5) * ST.tread
				local x, y, z = W(X, f.y0 + k * ST.riser, (ST.d0 + ST.d1) / 2)
				t.truthy(y - world.terrainAt(x, z) > 0.3, `the tread at X {X} is above the ground`)
			end
		end
	end)

	t.test("a squirrel passes the people's fence and is stopped at the top of the people's stair", function()
		-- along the east line, halfway between posts, on the louvre strip's grating and on the roof outside it
		local F = R.PEOPLE_FENCE
		local open, blocked = 0, 0
		local v = F.posts.d0 + F.postPitch / 2
		-- (short of the back parapet: the body keeps clear of its coping)
		while v < R.WING_ROOF.d1 - 1.5 do
			for _, X in { 120.2, 121.8 } do
				local x, _, z = W(X, 0, v)
				local y = world.groundAt(x, z, place.floorY + R.PLATFORM.y + 0.5)
				local stop = world.blocker(x, z, y, BakedWorld.BODY_HALF)
				if stop then
					blocked += 1
					print(`      stopped at ({X}, {v}) by {stop.path}`)
				else
					open += 1
				end
			end
			v += F.postPitch
		end
		t.eq(blocked, 0, `{blocked} spots along the people's fence stop a squirrel`)
		-- the squirrel fence: at the cut a squirrel is stopped; a person walks through it (the walk test above)
		local cut = ST.parapetCut
		local x, _, z = W((cut.x0 + cut.x1) / 2, 0, R.SQUIRREL_FENCE.d0 + 0.1)
		local y = world.groundAt(x, z, place.floorY + R.PLATFORM.y + 0.5)
		t.truthy(world.blocked(x, z, y), "the squirrel fence stops a squirrel at the parapet cut")
		print(`      {open} spots along the people's fence let a squirrel through`)
	end)

	t.test("the fences' collision groups: people meet the people fence, squirrels the squirrel fence", function()
		local G = CollisionGroups
		t.truthy(G.solidToPeople(G.PEOPLE_FENCE) and not G.solidToSquirrel(G.PEOPLE_FENCE))
		t.truthy(G.solidToSquirrel(G.SQUIRREL_FENCE) and not G.solidToPeople(G.SQUIRREL_FENCE))
		t.truthy(G.solidToPeople(nil) and G.solidToSquirrel(nil), "everything else meets both")
		t.truthy(G.solidToPeople(G.LANE_GUARD) and not G.meets(G.LANE_GUARD, G.BOWLING_PHYSICS))
		local stairs = root:FindFirstChild("RoofStairs") :: any
		local walls, caps, squirrel = 0, 0, 0
		for _, d in stairs:GetDescendants() do
			if d:IsA("BasePart") then
				if d.Name == "FenceWall" or d.Name == "PeopleCap" then
					t.eq(d.CollisionGroup, G.PEOPLE_FENCE, d.Name)
					t.truthy(d.CanCollide and d.Transparency == 1, `{d.Name} is an invisible wall`)
					if d.Name == "FenceWall" then
						walls += 1
					else
						caps += 1
					end
				elseif d.Name == "SquirrelFence" then
					t.eq(d.CollisionGroup, G.SQUIRREL_FENCE)
					squirrel += 1
				else
					t.eq(d.CollisionGroup, "Default", d:GetFullName())
				end
			end
		end
		t.eq(walls, #R.PEOPLE_FENCE.lines)
		t.eq(caps, #R.PEOPLE_FENCE.caps)
		t.eq(squirrel, 1)
	end)
end
