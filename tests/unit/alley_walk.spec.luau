--!strict
-- The way on foot in and round the bowling alley (Shared/Attractions/AlleyWalk), walked by a body through the baked
-- building (tests/lib/BakedWorld.bakeAlley):
--   * from every spot of floor a person can stand on (a grid over the hall, the front rooms, the games room and the
--     back corridor) to each employee's loop: past the first hop onto the graph, no step meets a colliding part;
--     the hop itself stays in its room (never a wall, a door or a partition) and brushes a stool or a table's
--     corner from only a few spots; no step of any way enters a lane's ball path;
--   * from outside (the lawn, both sides, behind the wing, the rear alley) the way goes round the building and in
--     at the main doors: no step is inside the walls before the doorway.
local AlleyLayout = require("@shared/Attractions/AlleyLayout")
local AlleyStaff = require("@shared/Attractions/AlleyStaff")
local AlleyWalk = require("@shared/Attractions/AlleyWalk")
local BakedWorld = require("../lib/BakedWorld")

local L = AlleyLayout
local BODY_HALF = 0.9
local KNEE = 0.6
local HEAD = 5.2
local GRID = 3 -- studs between the starts
local BRUSH_MAX = 0.04 -- of the starts, the share whose hop onto the graph may brush a stool or a table

local function inBallPath(X: number, D: number): boolean
	return X > L.LANE_BLOCK_X0 and X < L.LANE_BLOCK_X1 and D >= L.FOUL_D and D <= L.PIT_END
end

-- the points of a way every half stud, with the leg each is on
local function steps(X0: number, D0: number, way: { { number } }, fn: (X: number, D: number, leg: number) -> ())
	local px, pd = X0, D0
	for i, p in way do
		local len = math.sqrt((p[1] - px) ^ 2 + (p[2] - pd) ^ 2)
		local k = math.max(1, math.ceil(len / 0.5))
		for j = 1, k do
			fn(px + (p[1] - px) * j / k, pd + (p[2] - pd) * j / k, i)
		end
		px, pd = p[1], p[2]
	end
end

return function(t)
	local world, place = BakedWorld.bakeAlley()
	local function hit(X: number, D: number): any?
		local floor = L.floorAt(X, D) or 0
		local x, y, z = L.toWorld(place, X, floor + KNEE + (HEAD - KNEE) / 2, D)
		local hits = world.overlapBox(
			x,
			y,
			z,
			{ { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 } },
			{ BODY_HALF, (HEAD - KNEE) / 2, BODY_HALF },
			function(p: any): boolean
				return p.collide == true
			end
		)
		return hits[1]
	end
	local goals = {}
	for _, e in AlleyStaff.EMPLOYEES do
		table.insert(goals, e.stops[1])
	end

	t.test(
		"from any spot inside, back to each employee's loop by the routes: through no wall, across no lane",
		function()
			local starts, brushed, bad = 0, 0, 0
			for X = L.X0 + 1, L.X1 - 1, GRID do
				for D = L.FRONT_D + 1, L.REAR_WALL_D - 1, GRID do
					local onLane = X > L.LANE_BLOCK_X0 and X < L.LANE_BLOCK_X1 and D > L.FOUL_D and D < L.MACHINE_D1
					-- (nobody can stand on a lane: the LaneGuard keeps people off)
					if AlleyStaff.insideLocal(X, D) and L.floorAt(X, D) and not onLane and hit(X, D) == nil then
						starts += 1
						local g = goals[starts % #goals + 1]
						local way = AlleyWalk.localWay(X, D, g.x, g.d)
						local last = way[#way]
						t.truthy(math.abs(last[1] - g.x) + math.abs(last[2] - g.d) < 0.01, "the way ends at the goal")
						local brush = false
						steps(X, D, way, function(sx: number, sd: number, leg: number)
							local h = hit(sx, sd)
							local wall = h and (string.find(h.path, "^Walls%.") or string.find(h.path, "^Doors%."))
							if inBallPath(sx, sd) or (h and (leg > 1 or wall)) then
								bad += 1
								if bad <= 5 then
									t.truthy(
										false,
										`from ({X}, {D}): leg {leg} at ({sx}, {sd}) {if h
											then "meets " .. h.path
											else "is on a lane"}`
									)
								end
							elseif h then
								brush = true
							end
						end)
						if brush then
							brushed += 1
						end
					end
				end
			end
			t.truthy(starts > 500, `{starts} starts (the test has no teeth)`)
			t.eq(bad, 0, "steps through a wall, a fitting past the first hop, or on a lane")
			t.truthy(
				brushed <= starts * BRUSH_MAX,
				`{brushed} of {starts} hops onto the graph brush a stool or a table`
			)
		end
	)

	t.test("from outside: round the building and in at the main doors", function()
		local outs = {
			{ 22, -90 }, -- the lawn in front of the doors
			{ 70, -95 },
			{ -40, -60 }, -- the west side
			{ -40, 40 },
			{ 160, -20 }, -- the east side
			{ 125, 60 }, -- behind the wing
			{ 40, 95 }, -- the rear alley
			{ -24, 95 },
		}
		local door = L.opening("entrance")
		for _, o in outs do
			for _, g in goals do
				local way = AlleyWalk.localWay(o[1], o[2], g.x, g.d)
				local through = false
				steps(o[1], o[2], way, function(sx: number, sd: number)
					local inWalls = sx >= L.X0 - L.WALL_T
						and sx <= L.X1 + L.WALL_T
						and sd >= L.FRONT_D - L.WALL_T
						and sd <= L.REAR_WALL_D + L.WALL_T
						and not (sx >= L.HALL_X1 and sd > L.GAME_ROOM_D1 + L.WALL_T)
					if inWalls and not through then
						-- the first step inside the walls is through the main doors
						t.truthy(
							sx > door.a and sx < door.b and sd <= L.FRONT_D + 1,
							`from ({o[1]}, {o[2]}): in at ({sx}, {sd}), not at the doors`
						)
						through = true
					end
					t.truthy(not inBallPath(sx, sd), `from ({o[1]}, {o[2]}): on a lane at ({sx}, {sd})`)
					if through and AlleyStaff.insideLocal(sx, sd) then
						local h = hit(sx, sd)
						t.truthy(h == nil, `from ({o[1]}, {o[2]}): meets {if h then h.path else ""} at ({sx}, {sd})`)
					end
				end)
				t.truthy(through, `from ({o[1]}, {o[2]}): never went in`)
			end
		end
		-- and out: from the shoe desk to the walk in front of the doors
		local ox, oz = AlleyWalk.outside(place)
		local X, _, D = L.toLocal(place, ox, 0, oz)
		t.truthy(math.abs(X - AlleyWalk.OUTSIDE.x) + math.abs(D - AlleyWalk.OUTSIDE.d) < 1e-6)
		t.truthy(D < L.RAMP.d0, "the walk outside is beyond the ramp's foot")
		local way = AlleyWalk.localWay(10.5, -57, X, D)
		t.truthy(#way >= 3, "out of the shoe rental by its gap, the lobby and the doors")
	end)
end
