--!strict
-- Infection/Bystanders (owner 2026-11-10: "a crowd gather sometimes"; humans_actors §7.4): who comes
-- over, where each one stands, and that nobody is told to stand in a building, on the road where the
-- ambulance stops, or on top of someone else.
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
	t.test("select: sometimes nobody; otherwise 2 to 4 of the nearest eligible people, nearest first", function()
		local scene = { x = 0, z = 0 }
		t.eq(#Bystanders.select(scene, crowd(10), dice({ 0.9 }), PARAMS), 0, "the dice said no crowd")
		t.deepEq(Bystanders.select(scene, crowd(10), dice({ 0, 0 }), PARAMS), { 1, 2 })
		t.deepEq(Bystanders.select(scene, crowd(10), dice({ 0, 0.34 }), PARAMS), { 1, 2, 3 })
		t.deepEq(Bystanders.select(scene, crowd(10), dice({ 0, 0.999 }), PARAMS), { 1, 2, 3, 4 })
		-- ineligible people (already at a scene, infected and showing it, held by a player) are skipped
		t.deepEq(Bystanders.select(scene, crowd(10, 2), dice({ 0, 0.999 }), PARAMS), { 1, 3, 5, 7 })
		-- out of range is out
		local far = { { id = "a", x = 181, z = 0, eligible = true }, { id = "b", x = 0, z = 179, eligible = true } }
		t.deepEq(Bystanders.select(scene, far, dice({ 0, 0.999 }), PARAMS), { "b" })
		t.eq(#Bystanders.select(scene, {}, dice({ 0, 0 }), PARAMS), 0, "an empty street")
	end)

	t.test("select over 1,000 seeds: the count is 0 or 2 to 4; a crowd forms about 85 % of the time", function()
		local rng = Rng.new(11)
		local formed = 0
		local sizes: { [number]: number } = {}
		for _ = 1, 1000 do
			local picked = Bystanders.select({ x = 0, z = 0 }, crowd(12, 3), rng.next, PARAMS)
			local n = #picked
			sizes[n] = (sizes[n] or 0) + 1
			t.truthy(n == 0 or (n >= 2 and n <= 4), `{n} bystanders`)
			if n > 0 then
				formed += 1
			end
			for i, id in picked do
				t.truthy(id % 3 ~= 0, "an ineligible person was picked")
				t.truthy(i == 1 or id > picked[i - 1], "not nearest first")
			end
		end
		t.truthy(formed > 800 and formed < 900, `{formed} crowds`)
		t.truthy((sizes[2] or 0) > 200 and (sizes[3] or 0) > 200 and (sizes[4] or 0) > 200, "all three sizes come up")
		-- the same seed gives the same crowd
		local a = Bystanders.select({ x = 0, z = 0 }, crowd(12), Rng.new(5).next, PARAMS)
		local b = Bystanders.select({ x = 0, z = 0 }, crowd(12), Rng.new(5).next, PARAMS)
		t.deepEq(a, b)
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
		t.truthy(#half >= 2, `{#half} spots on the free side`)
		for i, s in half do
			t.truthy(s[2] <= -40, "a spot in the building")
			for j = i + 1, #half do
				local o = half[j]
				t.truthy(math.sqrt((o[1] - s[1]) ^ 2 + (o[2] - s[2]) ^ 2) >= Bystanders.MIN_APART - 1e-9, "too close")
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
		local all = Bystanders.assign(people, spots, function(): boolean
			return true
		end)
		t.deepEq(all, { { id = "n", x = 0, z = 10 }, { id = "e", x = 10, z = 0 }, { id = "s", x = 0, z = -10 } })
		-- "e" cannot walk anywhere (a house in the way): two bystanders, not three
		local two = Bystanders.assign(people, spots, function(p: Bystanders.Place): boolean
			return p.id ~= "e"
		end)
		t.eq(#two, 2)
		t.eq(two[1].id, "n")
		t.eq(two[2].id, "s")
		-- more people than spots: first come, first served
		local one = Bystanders.assign(people, { { 0, 0 } }, function(): boolean
			return true
		end)
		t.deepEq(one, { { id = "n", x = 0, z = 0 } })
		t.near(Bystanders.SAY_FIRST + 2 * Bystanders.SAY_EACH, 3.9, 1e-9, "the third bystander speaks at 3.9 s")
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
		t.truthy(total / scenes > 3, `{total / scenes} spots per scene on average`)
	end)
end
