--!strict
-- World/FootPath: the way on foot round the buildings (the fallback for everyone the sidewalk graph
-- does not reach, in the bite-to-hospital sequence): a straight line when nothing is in the way, a
-- detour round a house with every leg clear of its walls, out of (and into) a building through that
-- building's own wall only, never across closed ground, no way out of a walled yard, a budget that
-- ends a hopeless search, and on the real town a way from every person to the hospital door.
local Colliders = require("@shared/World/Colliders")
local FootPath = require("@shared/World/FootPath")
local Data = require("@shared/Data")
local Height = require("@shared/World/Height")
local Ground = require("@shared/World/Ground")
local HospitalLayout = require("@shared/Infection/HospitalLayout")

local BOUNDS = { minX = -500, maxX = 500, minZ = -500, maxZ = 500 }

local function box(id: string, cx: number, cz: number, hw: number, hd: number, height: number?): Colliders.Box
	return {
		id = id,
		cx = cx,
		cz = cz,
		hw = hw,
		hd = hd,
		y0 = 0,
		eave = height or 20,
		peak = height or 20,
		ridge = nil,
	}
end

local function town(boxes: { Colliders.Box }): Colliders.Colliders
	local c = Colliders.new()
	for _, b in boxes do
		Colliders.add(c, b)
	end
	return c
end

-- every leg of the walk misses every box by the walker's radius (boxes in `own` may be crossed by
-- the first or the last leg only)
local function legsClear(
	t: any,
	c: Colliders.Colliders,
	x0: number,
	z0: number,
	points: { { number } },
	own: { [string]: boolean }?
)
	local px, pz = x0, z0
	for i, p in points do
		local n = math.max(1, math.ceil(math.sqrt((p[1] - px) ^ 2 + (p[2] - pz) ^ 2) / 0.5))
		for k = 0, n do
			local x, z = px + (p[1] - px) * k / n, pz + (p[2] - pz) * k / n
			local hit = Colliders.pointIn(c, x, z, 3, FootPath.RADIUS - 0.01)
			if hit and not (own and own[hit.id] and (i == 1 or i == #points)) then
				t.truthy(false, `leg {i} goes through {hit.id} at ({x}, {z})`)
			end
		end
		px, pz = p[1], p[2]
	end
end

return function(t)
	t.test("nothing in the way: one straight leg; a house in the way: round it, clear of its walls", function()
		local c = town({ box("house", 0, 0, 30, 20) })
		local f = FootPath.new({ colliders = c, bounds = BOUNDS })
		local points, len = FootPath.find(f, -100, 80, 100, 80)
		t.deepEq(points, { { 100, 80 } })
		t.near(len, 200, 1e-9)
		t.eq(f.opened, 0, "no search for a clear line")
		-- straight through the middle of the house
		t.truthy(not FootPath.clear(f, -100, 0, 100, 0))
		points, len = FootPath.find(f, -100, 0, 100, 0)
		t.truthy(points ~= nil, "a way round")
		local way = points :: { { number } }
		t.deepEq(way[#way], { 100, 0 }, "the goal is the last waypoint")
		legsClear(t, c, -100, 0, way)
		t.truthy(len > 200 and len < 260, `{len} studs round a 60 x 40 house`)
		t.truthy(#way <= 4, `pulled straight: {#way} waypoints`)
		t.near(FootPath.length(-100, 0, way), len, 1e-9)
		-- the same question again gives the same answer
		local again = FootPath.find(f, -100, 0, 100, 0)
		t.deepEq(again, way)
		-- a low box (a doghouse, a kerb) is stepped over, not walked round
		local low = FootPath.new({ colliders = town({ box("step", 0, 0, 30, 20, 2) }), bounds = BOUNDS })
		t.deepEq((FootPath.find(low, -100, 0, 100, 0)), { { 100, 0 } })
	end)

	t.test("out of a building and into one: through that building's own wall, round every other", function()
		local c = town({ box("shop", 0, 0, 25, 25), box("next", 70, 0, 25, 25), box("home", 200, 0, 20, 20) })
		local f = FootPath.new({ colliders = c, bounds = BOUNDS })
		-- from the shop floor to a point beyond the next building
		local points, len = FootPath.find(f, 0, 0, 130, 0)
		t.truthy(points ~= nil)
		legsClear(t, c, 0, 0, points :: any, { shop = true })
		t.truthy(len > 130 and len < 220, `{len} studs`)
		-- and on into a third building (its bed, its counter)
		points = FootPath.find(f, 0, 0, 200, 0)
		t.truthy(points ~= nil)
		legsClear(t, c, 0, 0, points :: any, { shop = true, home = true })
		t.deepEq((points :: any)[#(points :: any)], { 200, 0 })
		-- clear(skip) is the same rule for one line
		t.truthy(not FootPath.clear(f, 0, 0, 40, 0))
	end)

	t.test("no way: a walled yard, closed ground on every side, a goal too far, a search over budget", function()
		-- a yard closed by four long buildings
		local c = town({
			box("n", 0, 60, 80, 10),
			box("s", 0, -60, 80, 10),
			box("e", 70, 0, 10, 70),
			box("w", -70, 0, 10, 70),
		})
		local f = FootPath.new({ colliders = c, bounds = BOUNDS })
		local points = FootPath.find(f, 0, 0, 300, 0)
		t.eq(points, nil, "no way out of the yard")
		t.truthy(f.opened < 400, `the yard is searched and no more ({f.opened} cells)`)
		t.truthy(FootPath.find(f, 0, 0, 30, 20) ~= nil, "inside the yard is fine")
		-- a river right across the map with no crossing
		local wet = FootPath.new({
			colliders = town({}),
			bounds = BOUNDS,
			isBlocked = function(x: number, _z: number): boolean
				return x > 40 and x < 70
			end,
		})
		t.truthy(not FootPath.clear(wet, 0, 0, 100, 0))
		t.eq((FootPath.find(wet, 0, 0, 100, 0)), nil, "nobody wades")
		t.truthy(FootPath.find(wet, 0, 0, 30, 200) ~= nil)
		-- the same river with a gap: the walk goes through the gap
		local ford = FootPath.new({
			colliders = town({}),
			bounds = BOUNDS,
			isBlocked = function(x: number, z: number): boolean
				return x > 40 and x < 70 and math.abs(z - 200) > 15
			end,
			blockedBox = { minX = 40, maxX = 70, minZ = -500, maxZ = 500 },
		})
		local across, len = FootPath.find(ford, 0, 0, 100, 0)
		t.truthy(across ~= nil, "through the gap")
		local px, pz = 0, 0
		for _, p in across :: { { number } } do
			for k = 0, 40 do
				local x, z = px + (p[1] - px) * k / 40, pz + (p[2] - pz) * k / 40
				t.truthy(not (x > 40 and x < 70 and math.abs(z - 200) > 15), `wet feet at ({x}, {z})`)
			end
			px, pz = p[1], p[2]
		end
		t.truthy(len > 400, `{len} studs by the gap`)
		-- too far, and over budget
		local open = FootPath.new({ colliders = town({ box("house", 0, 0, 30, 20) }), bounds = BOUNDS })
		t.eq((FootPath.find(open, -100, 0, 100, 0, { maxLength = 150 })), nil, "200 studs is more than 150")
		t.eq((FootPath.find(open, -100, 0, 100, 0, { maxLength = 201 })), nil, "the way round is longer than 201")
		t.truthy(FootPath.find(open, -100, 0, 100, 0, { maxLength = 300 }) ~= nil)
		t.eq((FootPath.find(open, -100, 0, 100, 0, { maxNodes = 3 })), nil, "gives up at the budget")
		t.truthy(open.opened <= 3)
		-- outside the world there is nothing to walk on
		t.eq((FootPath.find(open, 0, 100, 0, 900)), nil)
	end)

	t.test(
		"the real town: a way from where anyone stands to the hospital door, quickly, never through a wall",
		function()
			local data = Data.default()
			local colliders = Colliders.fromData(data)
			local layout = HospitalLayout.fromData(data) :: HospitalLayout.Layout
			local river = Height.RIVER
			local f = FootPath.new({
				colliders = colliders,
				bounds = Height.worldClamp(),
				isBlocked = function(x: number, z: number): boolean
					return Ground.surfaceKind(x, z) ~= "terrain"
				end,
				blockedBox = {
					minX = river.startX * 2.5,
					maxX = river.endX * 2.5,
					minZ = river.zMin * 2.5,
					maxZ = river.zMax * 2.5,
				},
			})
			local out = layout.outside
			-- the police station (yard and inside), a shop floor in the core, the far west and the far
			-- north-east of the old town, a pavement the sidewalk graph does not reach
			local from = {
				{ -1277, -380 },
				{ -1269, -283 },
				{ 385, 134 },
				{ -388, -171 },
				{ 1511, -237 },
				{ 604, -793 },
				{ 71, -732 },
				{ 668, 44 },
				{ -1400, 500 },
			}
			local worstMs, worstOpened = 0, 0
			for _, p in from do
				local t0 = os.clock()
				local points, len = FootPath.find(f, p[1], p[2], out[1], out[2])
				worstMs = math.max(worstMs, (os.clock() - t0) * 1000)
				worstOpened = math.max(worstOpened, f.opened)
				t.truthy(points ~= nil, `no way from ({p[1]}, {p[2]})`)
				local way = points :: { { number } }
				local direct = math.sqrt((p[1] - out[1]) ^ 2 + (p[2] - out[2]) ^ 2)
				t.truthy(len < direct * 1.25 + 40, `({p[1]}, {p[2]}): {len} studs for {direct} in a straight line`)
				-- no leg through a building, except out of the one the walk starts in
				local own: { [string]: boolean } = {}
				for _, b in colliders.boxes do
					local r = FootPath.RADIUS
					if math.abs(p[1] - b.cx) < b.hw + r and math.abs(p[2] - b.cz) < b.hd + r then
						own[b.id] = true
					end
				end
				local px, pz = p[1], p[2]
				for i, q in way do
					local n = math.max(1, math.ceil(math.sqrt((q[1] - px) ^ 2 + (q[2] - pz) ^ 2) / 1))
					for k = 0, n do
						local x, z = px + (q[1] - px) * k / n, pz + (q[2] - pz) * k / n
						local hit = Colliders.pointIn(colliders, x, z, Height.at(x, z) + 3, 1)
						t.truthy(
							hit == nil or (i == 1 and own[hit.id]),
							`from ({p[1]}, {p[2]}): leg {i} goes through {if hit then hit.id else ""}`
						)
						t.eq(Ground.surfaceKind(x, z), "terrain", "and never into the river")
					end
					px, pz = q[1], q[2]
				end
			end
			print(`      {#from} walks to the hospital door: worst search {worstOpened} cells`)
			t.truthy(worstOpened <= FootPath.MAX_NODES, "within the budget of one search")
			t.truthy(worstMs < 60, `a search took {worstMs} ms`)
			-- beyond the river the detour is too long for one search: it gives up inside its budget
			local points = FootPath.find(f, 2696, 760, out[1], out[2])
			t.eq(points, nil)
			t.truthy(f.opened <= FootPath.MAX_NODES)
		end
	)
end
