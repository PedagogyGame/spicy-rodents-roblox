--!strict
-- The people's stair and the guard platform as baked (tools/bake/alley/RoofStairs; BRIEF_ADDENDUM D9, owner questions
-- Q3, Q6, Q12's defaults), on the alley baked in memory by its own bake code (tests/lib/BakedWorld.bakeAlley), with a
-- person's body (tests/lib/HumanWalk: an R15 Humanoid's 2 x 5.2, stepping 0.75, jumping 7.2):
--   * walking from the foot of the stair in the yard, a person climbs all three flights and reaches the top landing,
--     the walkway, the strip in front of the louvre (the guard's spot), the north strip and the apron;
--   * jumping and falling as well, a person who starts on the platform never gets anywhere at roof height outside the
--     fenced area round the vent and the stair (not the open roof, the unit's top, the duct, the hall's roof);
--   * the stair stands on the ground: the pad, every column reaches it, no tread is under the ground;
--   * a running jump (walking 17 or sprinting 28, 7.2 high) from anywhere a person stands on the stair, its guard
--     rails' tops included, never lands at roof height outside that area (the people fence runs the wing's whole back
--     parapet: a rail climber jumping for the parapet east of the platform meets it);
--   * a squirrel passes the people's fence (between its posts, under its bottom rail, and straight across in front of
--     the louvre, where no post stands) and is stopped at the top of the people's stair (the squirrel fence, Q12); a
--     squirrel leaping off the stair, its guard rails included, never gets onto the roof or its parapets; a person
--     passes the squirrel fence.
local AlleyLayout = require("@shared/Attractions/AlleyLayout")
local AlleyRoof = require("@shared/Attractions/AlleyRoof")
local CollisionGroups = require("@shared/World/CollisionGroups")
local SquirrelMotor = require("@shared/Movement/SquirrelMotor")
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

	-- Where a person may be: out is anywhere at the hall's deck or higher; at roof height outside the fence and the
	-- stair; on the unit or the duct (standing on a rail or the back parapet inside the fence is allowed: nothing more
	-- comes of it). (The stair's side of the back parapet: only over the stair's top landing, the parapet cut.)
	local function allowed(X: number, Y: number, D: number): boolean
		if Y >= R.HALL_ROOF.deckY0 - 1 then
			return false
		end
		if Y < R.WING_ROOF.y - 1.5 then
			return true -- the stair's flights, or off it into the yard
		end
		local inFence = X >= 101.8 - 0.01 and X <= 121 and D >= 8 and D <= 30.8
		local onStair = X >= 101.8 - 0.01 and X <= ST.footX + 3 and D >= 30.8 and D <= ST.d1 + 1
		local c = R.AHU.curb
		local onUnit = X >= 101.8 and X <= c.x1 and D >= c.d0 and D <= c.d1 and Y > R.WING_ROOF.copingY + 0.05
		return (inFence or onStair) and not onUnit
	end

	-- The places on the stair a jump goes from: along every flight and landing at 1-stud steps, in the middle of the
	-- tread and on the outer guard rail's top (a person can hop onto it), wherever a person's body finds a footing.
	local function personSolid(p: any): boolean
		return p.collide and CollisionGroups.solidToPeople(p.group)
	end
	local function footing(X: number, D: number, top: number): number?
		local x, y, z = W(X, top, D)
		local tHit = world.raycast(x, y, z, 0, -30, 0, personSolid)
		if tHit == nil then
			return nil
		end
		return top - 30 * tHit
	end
	local stairTops: { { number } } = {}
	for X = R.WING_ROOF.x0 + 1, ST.footX, 1 do
		for _, D in { (ST.d0 + ST.d1) / 2, ST.d1 - 0.12 } do
			local Y = footing(X, D, R.WING_ROOF.y + 2)
			if Y and Y > 0 then
				table.insert(stairTops, { X, Y, D })
			end
		end
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
		-- (halfway between each two posts, and every half stud across the bent slat and 1.5 either side; short of
		-- the back parapet: the body keeps clear of its coping)
		local F = R.PEOPLE_FENCE
		local open, blocked = 0, 0
		local spots = {}
		local posts = R.fencePosts(1)
		for i = 1, #posts - 1 do
			if posts[i + 1] - posts[i] > 2.5 then
				table.insert(spots, (posts[i] + posts[i + 1]) / 2)
			end
		end
		for v = R.MOUTH.slat.d0 - 1.5, R.MOUTH.slat.d1 + 1.5, 0.5 do
			table.insert(spots, v)
		end
		for _, v in spots do
			if v >= R.WING_ROOF.d1 - 1.5 then
				continue
			end
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
		end
		t.truthy(F.posts.clear.d0 <= R.MOUTH.slat.d0 - 2 and F.posts.clear.d1 >= R.MOUTH.slat.d1 + 2)
		t.eq(blocked, 0, `{blocked} spots along the people's fence stop a squirrel`)
		-- the squirrel fence: at the cut a squirrel is stopped; a person walks through it (the walk test above)
		local cut = ST.parapetCut
		local x, _, z = W((cut.x0 + cut.x1) / 2, 0, R.SQUIRREL_FENCE.d0 + 0.1)
		local y = world.groundAt(x, z, place.floorY + R.PLATFORM.y + 0.5)
		t.truthy(world.blocked(x, z, y), "the squirrel fence stops a squirrel at the parapet cut")
		print(`      {open} spots along the people's fence let a squirrel through`)
	end)

	t.test(
		"a running jump from anywhere on the stair, its rails' tops included, never lands out on the roof",
		function()
			-- a Humanoid's jump: 7.2 high under the game's gravity (196.2), at the walk (17) or the sprint (28), in 16
			-- directions; the body (2 x 5.2) swept along the arc at 30 Hz meets what people meet, and falls from where it
			-- was stopped; where it lands must be somewhere a person may be
			local G = 196.2
			local V0 = math.sqrt(2 * G * HumanWalk.JUMP)
			local DT = 1 / 30
			local AXES = { { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 } }
			local half = HumanWalk.HALF - 0.02
			local function hits(X: number, Y: number, D: number): boolean
				local x, y, z = W(X, Y + (0.1 + HumanWalk.HEAD) / 2, D)
				return #world.overlapBox(x, y, z, AXES, { half, (HumanWalk.HEAD - 0.1) / 2, half }, personSolid) > 0
			end
			local escapes, jumps = {}, 0
			for _, s in stairTops do
				for k = 0, 15 do
					local a = k * math.pi / 8
					local dX, dD = math.cos(a), math.sin(a)
					for _, speed in { 17, 28 } do
						jumps += 1
						local X, Y, D, vy = s[1], s[2], s[3], V0
						local landed: { number }? = nil
						for _ = 1, 60 do
							local nX, nD = X + dX * speed * DT, D + dD * speed * DT
							local nY = Y + vy * DT - 0.5 * G * DT * DT
							vy -= G * DT
							if hits(nX, nY, nD) then
								-- stopped: down from where it was onto what is under it
								local g = footing(X, D, Y + 0.5)
								landed = { X, g or -99, D }
								break
							end
							X, Y, D = nX, nY, nD
							if vy < 0 then
								local g = footing(X, D, Y + 0.5)
								if g and g >= Y then
									landed = { X, g, D }
									break
								end
							end
						end
						if landed and not allowed(landed[1], landed[2], landed[3]) then
							table.insert(
								escapes,
								string.format(
									"from (%.1f, %.1f, %.1f) at %d heading %d -> (%.1f, %.1f, %.1f)",
									s[1],
									s[2],
									s[3],
									speed,
									k * 22.5,
									landed[1],
									landed[2],
									landed[3]
								)
							)
						end
					end
				end
			end
			t.truthy(#stairTops > 60, `{#stairTops} places on the stair to jump from`)
			t.eq(
				#escapes,
				0,
				`{#escapes} jumps land out on the roof: {table.concat(escapes, "; ", 1, math.min(#escapes, 6))}`
			)
			print(`      {jumps} running jumps from {#stairTops} places on the stair, none out on the roof`)
		end
	)

	t.test("a squirrel leaping off the people's stair, its rails included, never gets onto the roof", function()
		-- the real motor at 30 Hz, sprinting and leaping from each place on the stair above its first landing in 8
		-- directions (W held through the air, E pressed on the way down); it must never stand on the wing at the
		-- parapet's or the roof's height (the platform included)
		local motorWorld = world:motorWorld(BakedWorld.recordsData(R.records(place) :: any))
		local up, tries = {}, 0
		for _, s in stairTops do
			if s[2] < ST.landings[1].y + 2 then
				continue
			end
			for k = 0, 7 do
				tries += 1
				local a = k * math.pi / 4
				local x, _, z = W(s[1], s[2], s[3])
				local state = SquirrelMotor.new(x, motorWorld.groundAt(x, z, place.floorY + s[2] + 0.5), z)
				local dx, _, dz = W(s[1] + math.cos(a), s[2], s[3] + math.sin(a))
				local cam = BakedWorld.cameraYawToward(dx - x, dz - z)
				for f = 1, 60 do
					local input = BakedWorld.keys(cam, {
						fw = if f > 2 then 1 else 0,
						sprint = true,
						leap = f == 3,
						grab = f > 6 and state.vy < 0 and not state.grounded,
					})
					SquirrelMotor.step(state, input, 1 / 30, motorWorld)
					local X, Y, D = L(state.x, state.y, state.z)
					-- (the stair's own top landing is the stair: the squirrel fence stops it at the cut)
					if (state.grounded or state.routeId) and Y >= R.WING_ROOF.y - 0.3 and D < R.WING_ROOF.outerD1 then
						table.insert(
							up,
							string.format(
								"from (%.1f, %.1f, %.1f) heading %d -> (%.1f, %.1f, %.1f)",
								s[1],
								s[2],
								s[3],
								k * 45,
								X,
								Y,
								D
							)
						)
						break
					end
				end
			end
		end
		t.truthy(tries > 100, `{tries} leaps`)
		t.eq(#up, 0, `{#up} leaps reach the roof: {table.concat(up, "; ", 1, math.min(#up, 6))}`)
		print(`      {tries} sprinting leaps off the stair, none onto the roof`)
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
				elseif d.Name == "SquirrelFence" or d.Name == "SquirrelCap" then
					t.eq(d.CollisionGroup, G.SQUIRREL_FENCE)
					squirrel += 1
				else
					t.eq(d.CollisionGroup, "Default", d:GetFullName())
				end
			end
		end
		t.eq(walls, #R.PEOPLE_FENCE.lines)
		t.eq(caps, #R.PEOPLE_FENCE.caps)
		t.eq(squirrel, 2)
	end)
end
