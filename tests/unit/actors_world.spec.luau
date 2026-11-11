--!strict
-- W1 §4.4 #2 and #3 on the real data under Lune:
-- * World/Ground: golden terrain.json (11,060 v5.4 vectors) through Ground.world for every row in the
--   verbatim rectangle (terrain below the deck, the deck from on top), plus pavement, curbs, roofs
--   (World/Colliders) and the trampoline bed in the v5.4 getGroundAt order (6227-6247).
-- * World/Colliders, World/Town (lotAt, districtTag incl. offroad, pavementDistance), Actors/Nav
--   (sidewalk graph, A*, interior room paths), AI/RouteAdapter (real routes and links).
-- * Population per data/population.json: floors hold through 200 scripted joins, promotions and leaves.
-- * AI/TownAI: every species spawned on the real town; 60 simulated seconds: every actor moves, no NaN,
--   nobody outside the clamp, squirrels on real routes; suspend/resume round trips (possession seam).
local fs = require("@lune/fs")
local PreciseJson = require("@tests/lib/PreciseJson")
local Data = require("@shared/Data")
local Height = require("@shared/World/Height")
local Ground = require("@shared/World/Ground")
local Colliders = require("@shared/World/Colliders")
local Town = require("@shared/World/Town")
local Trampoline = require("@shared/Movement/Trampoline")
local RailWorld = require("@shared/Movement/RailWorld")
local Population = require("@shared/Actors/Population")
local Nav = require("@server/Actors/Nav")
local RouteAdapter = require("@server/AI/RouteAdapter")
local TownAI = require("@server/AI/TownAI")

local S = 2.5

local function num(v: any): number
	if type(v) == "table" then
		return tonumber(v.raw or v.value or v[1]) :: number
	end
	return v :: number
end

return function(t)
	local data = Data.default()
	local town = Town.fromData(data)
	local colliders = Colliders.fromData(data)

	t.test("Ground golden: terrain and the bridge deck match terrain.json through Ground.world", function()
		local golden = PreciseJson.decode(fs.readFile("tests/golden/terrain.json"))
		local g = Ground.world({})
		local R = Height.PLAYABLE_U
		local n, bad, decks = 0, 0, 0
		for _, row in golden.rows do
			local x, z = num(row[2]), num(row[3])
			if x >= R.minX and x <= R.maxX and z >= R.minZ and z <= R.maxZ then
				n += 1
				local h = num(row[5]) * S
				-- (a building site cuts the ground level under the hospital and the police station:
				-- world_height.spec holds the cut to the sites; there the golden row is the ground
				-- before the cut)
				if Height.at(x * S, z * S) < Height.natural(x * S, z * S) then
					t.near(Height.natural(x * S, z * S), h, 1e-6)
					h = Height.at(x * S, z * S)
				end
				if math.abs(g.groundAt(x * S, z * S, -1e9) - h) > 1e-6 then
					bad += 1
				end
				if row[9] ~= nil then
					local deck = num(row[9]) * S
					if deck > h then
						decks += 1
						if math.abs(g.groundAt(x * S, z * S, deck) - deck) > 1e-6 then
							bad += 1
						end
					end
				end
			end
		end
		print(`      {n} golden rows, {decks} deck rows, {bad} mismatches`)
		t.truthy(n > 7000 and decks > 0, "coverage")
		t.eq(bad, 0)
	end)

	t.test("Ground layers: pavement and curbs over terrain, roofs within 0.47 u, the trampoline bed", function()
		local g =
			Ground.world({ town = town, colliders = colliders, trampolines = { Trampoline.site(-33 * S, 80 * S, 0) } })
		-- the x = -12.1 u sidewalk in the flat core
		local y = g.groundAt(-12.1 * S, 50 * S, 0)
		t.near(y, 0.09 * S, 1e-9, "sidewalk offset")
		t.eq(g.surfaceKind(-12.1 * S, 50 * S, 0), "pavement")
		t.near(g.groundAt(10.1 * S, 60 * S, 0), 0.245 * S, 1e-9, "core curb")
		-- a building roof: standing on it only from above
		local box = colliders.boxes[1]
		local top = Colliders.roofOf(box, box.cx, box.cz)
		t.near(g.groundAt(box.cx, box.cz, top + 1), top, 1e-9, "on the roof")
		t.truthy(g.groundAt(box.cx, box.cz, box.y0) < top - 1, "under the roof: the floor")
		t.eq(g.surfaceKind(box.cx, box.cz, top), "roof")
		t.near(g.groundAt(-33 * S, 80 * S, 2 * S), 1.65 * S, 1e-9, "trampoline bed")
	end)

	t.test("Colliders: boxes for solid lots, wall test, gable roofs peak at the ridge", function()
		t.truthy(#colliders.boxes > 100, `{#colliders.boxes} boxes`)
		local box = colliders.boxes[1]
		t.truthy(Colliders.pointIn(colliders, box.cx, box.cz, box.y0 + 1) ~= nil, "inside")
		t.truthy(
			Colliders.blocked(colliders, box.cx - box.hw - 5, box.cz, box.cx, box.cz, 0.5, box.y0 + 1),
			"walk into it"
		)
		t.truthy(not Colliders.blocked(colliders, box.cx, box.cz, box.cx, box.cz, 0.5, box.peak + 2), "above the roof")
		local gables = 0
		for _, b in colliders.boxes do
			if b.ridge then
				gables += 1
				t.truthy(Colliders.roofOf(b, b.cx, b.cz) >= Colliders.roofOf(b, b.cx + b.hw * 0.9, b.cz + b.hd * 0.9))
			end
		end
		t.truthy(gables > 0, "some gable roofs")
		t.eq(#Colliders.query(colliders, box.cx - 1, box.cz - 1, box.cx + 1, box.cz + 1) > 0, true)
	end)

	t.test("Town: lots, districts (offroad without jurisdiction), pavement distance", function()
		local lot = data:lot("hospital_main")
		local hit = town:lotAt(lot.x, lot.z)
		t.truthy(hit ~= nil, "hospital lot found")
		t.eq(town:districtTag(lot.x, lot.z), (hit :: any).district)
		t.eq(town:districtTag(1400 * S, 0), "offroad")
		t.eq(town:pavementDistance(-12.1 * S, 0), 0)
		t.truthy(town:pavementDistance(-40 * S, -40 * S) > 0)
		t.truthy(#town:sidewalks() > 50)
	end)

	t.test("Nav: sidewalk graph, A* along the sidewalks, interior room paths", function()
		local nav = Nav.build(town, data:module("Interiors") :: any)
		t.truthy(#nav.nodes > 100, `{#nav.nodes} nodes`)
		local path = Nav.path(nav, -12.1 * S, -100 * S, 12.1 * S, 100 * S)
		t.truthy(path ~= nil and #(path :: any) >= 3, "a path across the core")
		local lanes = Nav.lanes(nav)
		t.truthy(#lanes == #town:sidewalks() and math.abs(lanes[1].fixed) <= 13 * S, "core lanes first")
		local any = false
		for key, g in nav.rooms do
			if g.lot == key then
				local rp = Nav.roomPath(nav, key, g.rooms[1], "outside")
				t.truthy(rp ~= nil and rp[#rp] == "outside", `{key}: a way out`)
				any = true
			end
		end
		t.truthy(any, "FRB interiors have room graphs")
	end)

	t.test("RouteAdapter: every harvested route with arc length and graph links", function()
		local rail = RailWorld.get(data, Height.at)
		local a = RouteAdapter.new(rail)
		-- 1,332 harvested plus the attraction routes (data/attractions.json: the bowling alley's vents and tunnels)
		local harvested = 0
		for _, r in rail.registry:all() do
			if r.origin ~= "attraction" then
				harvested += 1
			end
		end
		t.eq(harvested, 1332)
		t.eq(a.count, #rail.registry:all())
		local linked = 0
		for i = 1, 200 do
			local r = a.routes[i]
			t.truthy(r.length > 0 and #r.points >= 2)
			for _, l in r.links do
				linked += 1
				t.truthy(l.s >= 0 and l.s <= r.length + 1e-6)
				local to = a.byId(l.to) :: any
				t.truthy(l.toS >= 0 and l.toS <= to.length + 1e-6)
			end
		end
		t.truthy(linked > 50, `{linked} links`)
	end)

	t.test("Population (data): floors hold through 200 scripted joins, promotions and leaves", function()
		local cfg = Population.fromData(data:population(), "frb")
		local ok, errors = Population.validate(cfg)
		t.truthy(ok, table.concat(errors, "; "))
		local state = Population.newState(cfg)
		local seed = 7
		local function rnd(n: number): number
			seed = (seed * 1103515245 + 12345) % 2147483648
			return seed % n + 1
		end
		local held: { string } = {}
		local promo = { "police", "hospital_staff" }
		for _ = 1, 200 do
			local r = rnd(10)
			if (r <= 5 and #held < 49) or #held == 0 then
				local d = Population.pickBody("townsperson", state, cfg)
				if d.kind ~= "wait" then
					Population.apply(state, d)
					table.insert(held, "townsperson")
				end
			elseif r <= 7 then
				local i = rnd(#held)
				if held[i] == "townsperson" then
					local to = promo[rnd(2)]
					local d = Population.pickBody(to, state, cfg)
					if d.kind ~= "wait" then
						Population.release(state, "townsperson")
						Population.apply(state, d)
						held[i] = to
					end
				end
			else
				local i = rnd(#held)
				Population.release(state, held[i])
				table.remove(held, i)
			end
			local fine, why = Population.floorsOk(state, cfg)
			t.truthy(fine, table.concat(why, "; "))
		end
	end)

	t.test("TownAI: every species on the real town; 60 s liveness; suspend and resume", function()
		local world = TownAI.build({ data = data, seed = 5 })
		local c = TownAI.counts(world)
		t.eq(c.human, 72 + 8, "72 standing (FRB) + 8 riders")
		t.eq(c.squirrel, 14 + 1, "14 squirrels + the rodent")
		t.eq(c.deer, 6)
		t.eq(c.fox, 1)
		local total = 0
		for _ = 1, 60 * 60 do
			total += TownAI.stepFrame(world, 1 / 60).totalMs
		end
		local live = TownAI.liveness(world)
		print(`      {live.actors} actors, avg {string.format("%.3f", total / 3600)} ms/frame (Lune)`)
		t.truthy(live.ok, `stuck {#live.stuck} nan {live.nan} outside {live.outside}`)
		local onRail = 0
		for _, a in world.actors do
			if a.brainKind == "Squirrel" and a.intent.mode == "rail" then
				onRail += 1
				t.truthy(world.routes.byId(a.intent.routeId) ~= nil)
			end
		end
		t.eq(onRail, 14, "squirrels run real routes")
		-- possession seam: suspend freezes the actor, resume re-enters the AI where the player left it
		local ped = TownAI.actorsOf(world, function(a)
			return a.post == "townsperson"
		end)[1]
		local snap = TownAI.suspend(world, ped.id)
		t.truthy(snap.x == ped.x and snap.brain ~= nil)
		local x0 = ped.x
		for _ = 1, 30 do
			TownAI.stepFrame(world, 1 / 60)
		end
		t.eq(ped.x, x0, "frozen while possessed")
		TownAI.resume(world, ped.id, ped.x + 3, ped.y, ped.z)
		for _ = 1, 120 do
			TownAI.stepFrame(world, 1 / 60)
		end
		t.truthy(ped.x ~= x0 + 3 or ped.z ~= snap.z, "AI resumed")
	end)
end
