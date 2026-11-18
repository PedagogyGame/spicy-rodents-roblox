--!strict
-- Infection/MedicalRoute and Infection/HospitalLayout on the real town data (owner 2026-11-10: the
-- ambulance comes to the nearest road point; the hospital is where the cure is): the road graph
-- joins every asphalt strip, a stage is on a road centreline, every trip leg is axis-aligned and on
-- asphalt apart from the short joins in the data, the walk-in tail reaches the door without crossing
-- a building, and the hospital's door, intake and beds are where the baked hospital is.
local Data = require("@shared/Data")
local Town = require("@shared/World/Town")
local Colliders = require("@shared/World/Colliders")
local Height = require("@shared/World/Height")
local MedicalRoute = require("@shared/Infection/MedicalRoute")
local HospitalLayout = require("@shared/Infection/HospitalLayout")
local Rng = require("@shared/Util/Rng")

return function(t)
	local data = Data.default()
	local town = Town.fromData(data)
	local roads = MedicalRoute.build(town.strips :: any)
	local layout = HospitalLayout.fromData(data) :: HospitalLayout.Layout
	local HOME = { -890, 737.5 } -- the responder trunk's first point (generated/Lanes)

	local function legsOk(points: { { number } }, what: string): number
		local off = 0
		for i = 2, #points do
			local a, b = points[i - 1], points[i]
			local dx, dz = math.abs(b[1] - a[1]), math.abs(b[2] - a[2])
			t.truthy(dx < 1e-6 or dz < 1e-6, `{what}: leg {i - 1} is diagonal`)
			local len = dx + dz
			t.truthy(len > 0.8, `{what}: leg {i - 1} is {len} studs long`)
			local steps = math.max(1, math.ceil(len / 2))
			for k = 0, steps do
				local f = k / steps
				local x, z = a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f
				t.truthy(
					MedicalRoute.onRoad(roads, x, z, MedicalRoute.JOIN_GAP),
					`{what}: ({x}, {z}) is nowhere near a road`
				)
				if not MedicalRoute.onRoad(roads, x, z, 0) then
					off += len / steps
				end
			end
		end
		return off
	end

	t.test("road graph: 17 asphalt strips, collinear ones merged, one connected network", function()
		local asphalt = 0
		for _, s in town.strips do
			if s.kind == "asphalt" then
				asphalt += 1
			end
		end
		t.eq(asphalt, 17, "asphalt strips in generated/Roads")
		t.truthy(#roads.lines < asphalt, `{#roads.lines} lines: the boulevard and the hospital road merged`)
		local seen: { [string]: boolean } = {}
		for _, line in roads.lines do
			for _, id in line.ids do
				t.truthy(not seen[id], `{id} twice`)
				seen[id] = true
			end
			t.truthy(#line.nodes >= 1, `{line.ids[1]} joins nothing`)
		end
		-- the hospital road and the north cross are one line along z = 283 u
		local found = false
		for _, line in roads.lines do
			if table.find(line.ids, "rd_065_hospital_road_z283") then
				found = table.find(line.ids, "rd_049_north_cross_z283") ~= nil
			end
		end
		t.truthy(found, "hospital road + north cross")
		-- connected: flood from node 1
		local reached, stack = { [1] = true }, { 1 }
		local count = 1
		while #stack > 0 do
			local cur = table.remove(stack) :: number
			for _, e in roads.edges[cur] do
				if not reached[e.to] then
					reached[e.to] = true
					count += 1
					table.insert(stack, e.to)
				end
			end
		end
		t.eq(count, #roads.nodes, "every join is reachable from every other")
		-- without the join gap the westside street does not reach the hospital road
		local old = MedicalRoute.JOIN_GAP
		MedicalRoute.JOIN_GAP = 0
		local strict = MedicalRoute.build(town.strips :: any)
		MedicalRoute.JOIN_GAP = old
		t.truthy(#strict.nodes < #roads.nodes, "the data's gaps are real")
	end)

	t.test("stage: the nearest road centreline point; on asphalt for 500 seeded town points", function()
		local s = MedicalRoute.stage(roads, -800, 300) :: MedicalRoute.Stage
		t.near(s.x, -722.5, 1e-9, "the westside street")
		t.near(s.z, 300, 1e-9)
		t.eq(s.axis, "z")
		t.near(s.dist, 77.5, 1e-9)
		local c = MedicalRoute.stage(roads, 100, 250) :: MedicalRoute.Stage
		t.near(c.x, 0, 1e-9, "the main north-south street")
		t.near(c.z, 250, 1e-9)
		local rng = Rng.new(54)
		for i = 1, 500 do
			local x, z = rng.range(-1100, 1800), rng.range(-800, 1000)
			local st = MedicalRoute.stage(roads, x, z) :: MedicalRoute.Stage
			t.truthy(MedicalRoute.onRoad(roads, st.x, st.z, 0), `point {i}: stage off the road`)
			t.near(st.dist, math.sqrt((st.x - x) ^ 2 + (st.z - z) ^ 2), 1e-6)
			-- nothing nearer exists on any strip's centreline
			for _, line in roads.lines do
				local along = math.clamp(if line.axis == "z" then z else x, line.min, line.max)
				local px, pz =
					if line.axis == "z" then line.coord else along, if line.axis == "z" then along else line.coord
				t.truthy(math.sqrt((px - x) ^ 2 + (pz - z) ^ 2) >= st.dist - 1e-6)
			end
		end
	end)

	t.test("trip: golden routes from the hospital drive; axis-aligned legs on asphalt", function()
		local function trip(x: number, z: number): { { number } }
			local stage = MedicalRoute.stage(roads, x, z) :: MedicalRoute.Stage
			local p = MedicalRoute.trip(roads, HOME, stage)
			t.truthy(p ~= nil, `no trip to ({x}, {z})`)
			return p :: { { number } }
		end
		-- a westside stop: down the westside street (v5.4: (-289, 283) -> (-289, tz))
		t.deepEq(trip(-800, 300), { { -890, 737.5 }, { -890, 707.5 }, { -722.5, 707.5 }, { -722.5, 300 } })
		-- the old town's main street: along the hospital road and the north cross, then down x = 0
		t.deepEq(trip(100, 600), { { -890, 737.5 }, { -890, 707.5 }, { 0, 707.5 }, { 0, 600 } })
		-- a stop on the z = -174 u street: v5.4's chain drove down x = dest.x through the blocks here
		local south = trip(-200, -400)
		t.deepEq(south[#south], { -200, -435 })
		t.deepEq(south[#south - 1], { -450, -435 }, "it turns onto the street at a junction")
		-- the commercial district: onto the boulevard, never across the blocks
		local east = trip(1200, 60)
		t.deepEq(east[#east], { 1200, 0 })
		for _, p in { south, east, trip(-800, 300), trip(100, 250), trip(900, -300), trip(0, -790), trip(440, 900) } do
			t.deepEq(p[1], HOME)
			local off = legsOk(p, "golden")
			t.truthy(off <= 2 * MedicalRoute.JOIN_GAP + 4, `{off} studs off asphalt`)
		end
	end)

	t.test(
		"trip: 300 seeded stops all have a route; no shorter one through the joins exists by going direct",
		function()
			local rng = Rng.new(7)
			local longest = 0
			for i = 1, 300 do
				local x, z = rng.range(-1100, 1800), rng.range(-800, 1000)
				local stage = MedicalRoute.stage(roads, x, z) :: MedicalRoute.Stage
				local p = MedicalRoute.trip(roads, HOME, stage)
				if p == nil then
					-- only a stop right at the ambulance's own parking spot has nothing to drive
					t.truthy(math.abs(stage.x - HOME[1]) + math.abs(stage.z - HOME[2]) < 2, `stop {i} has no route`)
					continue
				end
				local off = legsOk(p, `stop {i}`)
				t.truthy(off <= 2 * MedicalRoute.JOIN_GAP + 4, `stop {i}: {off} studs off asphalt`)
				t.truthy(
					math.abs(p[#p][1] - stage.x) + math.abs(p[#p][2] - stage.z) < 0.9,
					`stop {i}: ends off the stage`
				)
				local len = MedicalRoute.length(p)
				local manhattan = math.abs(stage.x - HOME[1]) + math.abs(stage.z - HOME[2])
				t.truthy(len >= manhattan - 0.9, "no route is shorter than the grid distance")
				t.truthy(len <= manhattan + 1400, `stop {i}: a {len}-stud detour for {manhattan}`)
				longest = math.max(longest, len)
			end
			t.truthy(longest < 4500, `longest trip {longest}`)
			print(`      longest ambulance trip {math.floor(longest)} studs, about {math.floor(longest / 60)} s out`)
		end
	)

	t.test("trip: nothing to drive when the stop is the parking spot; length adds the legs", function()
		local here = MedicalRoute.stage(roads, HOME[1], HOME[2]) :: MedicalRoute.Stage
		t.eq(MedicalRoute.trip(roads, HOME, here), nil)
		t.eq(MedicalRoute.length({ { 0, 0 }, { 3, 0 }, { 3, 4 } }), 7)
		t.eq(MedicalRoute.length({}), 0)
	end)

	t.test("hospital layout: the door, the intake and eight beds where the baked hospital is", function()
		t.near(layout.entrance[1], -890, 2)
		t.near(layout.entrance[2], 762.5, 2, "the front wall faces -Z")
		t.truthy(layout.outside[2] < layout.entrance[2], "outside is in front of the door")
		t.truthy(not HospitalLayout.contains(layout, layout.outside[1], layout.outside[2]))
		t.truthy(HospitalLayout.contains(layout, layout.reception[1], layout.reception[2]))
		t.truthy(HospitalLayout.contains(layout, layout.intake[1], layout.intake[2]))
		t.truthy(layout.reception[2] > layout.entrance[2], "reception is behind the door")
		t.eq(#layout.beds, 8)
		local b = data:buildings().hospital
		local wardRect: { [string]: { number } } = {}
		for _, r in b.rooms do
			wardRect[r.id] = r.rect
		end
		local lot = data:lot("hospital_main")
		for i, bed in layout.beds do
			t.truthy(HospitalLayout.contains(layout, bed.x, bed.z, -5), `bed {i} is outside the hospital`)
			-- back into the lot's local frame (facing -Z: lx = dx, lz = -dz, HTML units)
			local lx, lz = (bed.x - lot.x) / 2.5, -(bed.z - lot.z) / 2.5
			local r = wardRect[bed.ward]
			t.truthy(
				lx > r[1] + 2 and lx < r[2] - 2 and lz > r[3] + 2 and lz < r[4] - 2,
				`bed {i} is not in {bed.ward}`
			)
			for j = i + 1, #layout.beds do
				local o = layout.beds[j]
				t.truthy(math.abs(o.x - bed.x) + math.abs(o.z - bed.z) > 12, `beds {i} and {j} overlap`)
			end
			local out = HospitalLayout.pathOut(layout, bed)
			t.deepEq(out[#out], layout.outside)
			local inn = HospitalLayout.pathIn(layout, bed)
			t.deepEq(inn[1], layout.entrance)
			t.deepEq(inn[#inn], { bed.x, bed.z })
		end
		t.eq(#(HospitalLayout.fromData(data, 5) :: HospitalLayout.Layout).beds, 5)
		t.truthy(HospitalLayout.nearEntrance(layout, -885, 760, 15))
		t.truthy(not HospitalLayout.nearEntrance(layout, -850, 700, 15))
		-- a town without a hospital has no layout (the services then stay off)
		local none = HospitalLayout.fromData({
			lot = function()
				return nil
			end,
			buildings = function()
				return {}
			end,
		})
		t.eq(none, nil)
	end)

	t.test("walk-in tail: from the westside sidewalk's north end to the door, no leg through a building", function()
		local tail = MedicalRoute.walkTail(town.strips :: any, layout.entrance) :: { { number } }
		t.truthy(tail ~= nil)
		t.deepEq(tail[1], { -747.5, 680 }, "the last node the sidewalk graph reaches")
		t.deepEq(tail[#tail], layout.entrance)
		local colliders = Colliders.fromData(data)
		for i = 2, #tail do
			local a, b = tail[i - 1], tail[i]
			t.truthy(math.abs(a[1] - b[1]) < 1e-6 or math.abs(a[2] - b[2]) < 1e-6, `tail leg {i - 1} is diagonal`)
			if i < #tail then
				local refY = Height.at(a[1], a[2]) + 3
				t.truthy(
					not Colliders.blocked(colliders, a[1], a[2], b[1], b[2], 1, refY),
					`tail leg {i - 1} ({a[1]}, {a[2]}) -> ({b[1]}, {b[2]}) crosses a building`
				)
			end
		end
		-- the last leg is the walk in through the door: it starts in front of the wall
		local turn = tail[#tail - 1]
		t.truthy(not HospitalLayout.contains(layout, turn[1], turn[2]), "the turn-in point is outside")
		t.near(turn[1], layout.entrance[1], 1e-9)
		t.truthy(MedicalRoute.length(tail) < 320, `tail {MedicalRoute.length(tail)} studs`)
		-- strips missing: no tail (the service then has no walk-in route)
		t.eq(MedicalRoute.walkTail({}, layout.entrance), nil)
	end)
end
