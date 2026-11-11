--!strict
-- Infection/Bystanders (owner 2026-11-10: "a crowd gather sometimes"; humans_actors §7.4): who comes
-- over, where each one stands, and that nobody is told to stand in a building, on the road where the
-- ambulance stops, or on top of someone else. A person who cannot walk over is replaced by the next
-- nearest, and one onlooker alone is not a crowd.
local Bystanders = require("@shared/Infection/Bystanders")
local Data = require("@shared/Data")
local Town = require("@shared/World/Town")
local Colliders = require("@shared/World/Colliders")
local Height = require("@shared/World/Height")
local MedicalRoute = require("@shared/Infection/MedicalRoute")
local Rng = require("@shared/Util/Rng")

local PARAMS: Bystanders.Params = { chance = 0.85, min = 2, max = 4, radius = 180 }

local function dice(values: { number }): () -> number
	local i = 0
	return function(): number
		i += 1
		return values[i] or 0.5
	end
end

local function crowd(n: number, eligibleEvery: number?): { Bystanders.Candidate }
	local out = {}
	for i = 1, n do
		table.insert(out, { id = i, x = i * 10, z = 0, eligible = eligibleEvery == nil or i % eligibleEvery ~= 0 })
	end
	return out
end

return function(t)
	t.test("select: sometimes nobody; otherwise a size of 2 to 4 and everyone who could come, nearest first", function()
		local scene = { x = 0, z = 0 }
		local nobody, none = Bystanders.select(scene, crowd(10), dice({ 0.9 }), PARAMS)
		t.eq(#nobody, 0, "the dice said no crowd")
		t.eq(none, 0)
		local everyone = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 }
		local ids, want = Bystanders.select(scene, crowd(10), dice({ 0, 0 }), PARAMS)
		t.deepEq(ids, everyone, "all the candidates: the ones who cannot walk over are replaced from these")
		t.eq(want, 2)
		ids, want = Bystanders.select(scene, crowd(10), dice({ 0, 0.34 }), PARAMS)
		t.deepEq(ids, everyone)
		t.eq(want, 3)
		ids, want = Bystanders.select(scene, crowd(10), dice({ 0, 0.999 }), PARAMS)
		t.eq(want, 4)
		-- ineligible people (already at a scene, infected and showing it, held by a player) are skipped
		ids = Bystanders.select(scene, crowd(10, 2), dice({ 0, 0.999 }), PARAMS)
		t.deepEq(ids, { 1, 3, 5, 7, 9 })
		-- out of range is out
		local far = { { id = "a", x = 181, z = 0, eligible = true }, { id = "b", x = 0, z = 179, eligible = true } }
		t.deepEq((Bystanders.select(scene, far, dice({ 0, 0.999 }), PARAMS)), { "b" })
		ids, want = Bystanders.select(scene, {}, dice({ 0, 0 }), PARAMS)
		t.eq(#ids, 0, "an empty street")
		t.eq(want, 2, "(the size is still drawn: the dice stay in step)")
	end)

	t.test("select over 1,000 seeds: the size is 0 or 2 to 4; a crowd forms about 85 % of the time", function()
		local rng = Rng.new(11)
		local formed = 0
		local sizes: { [number]: number } = {}
		for _ = 1, 1000 do
			local picked, want = Bystanders.select({ x = 0, z = 0 }, crowd(12, 3), rng.next, PARAMS)
			sizes[want] = (sizes[want] or 0) + 1
			t.truthy(want == 0 or (want >= 2 and want <= 4), `a crowd of {want}`)
			if want > 0 then
				formed += 1
				t.eq(#picked, 8, "every eligible person in range is a candidate")
			else
				t.eq(#picked, 0)
			end
			for i, id in picked do
				t.truthy(id % 3 ~= 0, "an ineligible person was picked")
				t.truthy(i == 1 or id > picked[i - 1], "not nearest first")
			end
		end
		t.truthy(formed > 800 and formed < 900, `{formed} crowds`)
		t.truthy((sizes[2] or 0) > 200 and (sizes[3] or 0) > 200 and (sizes[4] or 0) > 200, "all three sizes come up")
		-- the same seed gives the same crowd
		local a, wa = Bystanders.select({ x = 0, z = 0 }, crowd(12), Rng.new(5).next, PARAMS)
		local b, wb = Bystanders.select({ x = 0, z = 0 }, crowd(12), Rng.new(5).next, PARAMS)
		t.deepEq(a, b)
		t.eq(wa, wb)
	end)

	t.test("spots: the v5.4 ring; rejected spots move round or in and out; never two on one spot", function()
		local scene = { x = 100, z = -40 }
		local function free(): boolean
			return true
		end
		local ring = Bystanders.spots(scene, 4, free, 20)
		t.eq(#ring, 4)
		for i, s in ring do
			local a = (i - 1 + 0.33) * 2 * math.pi / 4
			t.near(s[1], 100 + math.cos(a) * 20, 1e-9, `spot {i}`)
			t.near(s[2], -40 + math.sin(a) * 20, 1e-9)
		end
		-- the half plane z > -40 is a building: everyone ends up on the free side, apart from each other
		local half = Bystanders.spots(scene, 4, function(_x: number, z: number): boolean
			return z <= -40
		end, 20)
		t.eq(#half, 4, "four places wanted, four found on the free side")
		for i, s in half do
			t.truthy(s[2] <= -40, "a spot in the building")
			for j = i + 1, #half do
				local o = half[j]
				t.truthy(math.sqrt((o[1] - s[1]) ^ 2 + (o[2] - s[2]) ^ 2) >= Bystanders.MIN_APART - 1e-9, "too close")
			end
		end
		-- a victim on a pavement has the road along one side: a crowd of two still finds two places
		-- (the ring's own two places are one each side, and the one on the road used to be lost)
		for turn = 0, 7 do
			local nx, nz = math.cos(turn * math.pi / 4), math.sin(turn * math.pi / 4)
			local function offRoad(x: number, z: number): boolean
				return (x - scene.x) * nx + (z - scene.z) * nz <= 3 -- the road starts 3 studs away
			end
			for n = 2, 4 do
				local found = Bystanders.spots(scene, n, offRoad, 20)
				t.eq(#found, n, `road on side {turn}: {#found} places for a crowd of {n}`)
				for _, s in found do
					t.truthy(offRoad(s[1], s[2]), "a place on the road")
				end
			end
		end
		-- nowhere free: no spots, no crowd
		t.eq(#Bystanders.spots(scene, 3, function(): boolean
			return false
		end, 20), 0)
	end)

	t.test("assign: each person takes the nearest spot they can walk to; the rest stay out of it", function()
		local spots = { { 0, 10 }, { 10, 0 }, { 0, -10 } }
		local people = { { id = "n", x = 0, z = 30 }, { id = "e", x = 30, z = 0 }, { id = "s", x = 0, z = -30 } }
		local function straight(_p: Bystanders.Place, x: number, z: number): { { number } }?
			return { { x, z } }
		end
		local all = Bystanders.assign(people, spots, straight)
		t.eq(#all, 3)
		for i, want in { { "n", 0, 10 }, { "e", 10, 0 }, { "s", 0, -10 } } do
			t.eq(all[i].id, want[1])
			t.eq(all[i].x, want[2])
			t.eq(all[i].z, want[3])
			t.deepEq(all[i].path, { { want[2], want[3] } }, "each comes with the walk to their spot")
		end
		-- "e" cannot walk anywhere (a house in the way): two bystanders, not three
		local two = Bystanders.assign(
			people,
			spots,
			function(p: Bystanders.Place, x: number, z: number): { { number } }?
				return if p.id ~= "e" then { { x, z } } else nil
			end
		)
		t.eq(#two, 2)
		t.eq(two[1].id, "n")
		t.eq(two[2].id, "s")
		-- more people than spots: first come, first served
		local one = Bystanders.assign(people, { { 0, 0 } }, straight)
		t.eq(#one, 1)
		t.eq(one[1].id, "n")
		t.near(Bystanders.SAY_FIRST + 2 * Bystanders.SAY_EACH, 3.9, 1e-9, "the third bystander speaks at 3.9 s")
	end)

	t.test("assign: someone who cannot walk over is replaced by the next nearest; one onlooker is no crowd", function()
		local scene = { x = 0, z = 0 }
		local spots = Bystanders.spots(scene, 3, function(): boolean
			return true
		end, 20)
		-- ten people in a line, nearest first; the 1st, 2nd and 4th have a house in the way
		local people: { Bystanders.Place } = {}
		for i = 1, 10 do
			table.insert(people, { id = i, x = 30 + i * 10, z = 5 })
		end
		local blocked = { [1] = true, [2] = true, [4] = true }
		local asked: { [number]: number } = {}
		local function wayTo(p: Bystanders.Place, x: number, z: number): { { number } }?
			asked[p.id] = (asked[p.id] or 0) + 1
			return if blocked[p.id] then nil else { { x, z } }
		end
		local placed = Bystanders.assign(people, spots, wayTo, 3, 2)
		local ids = {}
		for _, p in placed do
			table.insert(ids, p.id)
		end
		t.deepEq(ids, { 3, 5, 6 }, "three wanted, three came: the blocked ones were replaced")
		t.eq(asked[7], nil, "nobody is asked once the crowd is complete")
		t.truthy(asked[1] <= Bystanders.SPOT_TRIES, "a blocked person is not tried against every spot")
		-- the crowd wanted is smaller than the ring: no more than wanted
		t.eq(#Bystanders.assign(people, spots, wayTo, 2, 2), 2)
		-- only one person can come: nobody does (a crowd is two at least)
		local lonely = Bystanders.assign(
			people,
			spots,
			function(p: Bystanders.Place, x: number, z: number): { { number } }?
				return if p.id == 9 then { { x, z } } else nil
			end,
			3,
			2
		)
		t.eq(#lonely, 0, "one onlooker alone is not a crowd")
		-- two can: they do
		local pair = Bystanders.assign(
			people,
			spots,
			function(p: Bystanders.Place, x: number, z: number): { { number } }?
				return if p.id >= 9 then { { x, z } } else nil
			end,
			4,
			2
		)
		t.eq(#pair, 2)
		-- nobody at all
		t.eq(#Bystanders.assign({}, spots, wayTo, 3, 2), 0)
		t.eq(#Bystanders.assign(people, {}, wayTo, 3, 2), 0)
	end)

	t.test("on the real town: 200 scenes on the sidewalks; no spot in a building or on the road", function()
		local data = Data.default()
		local town = Town.fromData(data)
		local colliders = Colliders.fromData(data)
		local roads = MedicalRoute.build(town.strips :: any)
		local walks = town:sidewalks()
		local rng = Rng.new(3)
		local total, scenes = 0, 0
		for _ = 1, 200 do
			local s = walks[1 + math.floor(rng.next() * #walks)]
			local along = rng.range(s.min, s.max)
			local scene = if s.axis == "z" then { x = s.coord, z = along } else { x = along, z = s.coord }
			local function free(x: number, z: number): boolean
				return Colliders.pointIn(colliders, x, z, Height.at(x, z) + 3, 3) == nil
					and not MedicalRoute.onRoad(roads, x, z, 4)
			end
			local spots = Bystanders.spots(scene, 4, free, 20)
			scenes += 1
			total += #spots
			for i, p in spots do
				t.truthy(free(p[1], p[2]), `scene ({scene.x}, {scene.z}): spot {i} is not free`)
				local d = math.sqrt((p[1] - scene.x) ^ 2 + (p[2] - scene.z) ^ 2)
				t.truthy(d >= 14 and d <= 33, `spot {i} is {d} studs from the victim`)
			end
		end
		t.truthy(total / scenes > 3.8, `{total / scenes} spots per scene on average`)
	end)
end
