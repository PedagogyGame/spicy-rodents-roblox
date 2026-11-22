--!strict
-- Owner D21 (2026-11-21): "make sure those regular squirrels can be run over by cars, if they are not careful"; D15 #6:
-- cars brake for people only. On the real lanes (Traffic/TrafficService, the 25 vehicles) and the real town
-- (AI/TownAI):
--   * a player's squirrel on the road: every kind of vehicle in the fatal fleet runs it over where it stands in its
--     way (the RunOver that Boot/Game turns into "RUN OVER"); the same spot up on a wire, a branch or a roof is safe;
--     a motorcycle hurts nobody; no car slows for it, every car stops for a person;
--   * the fatal sweep keeps no stale place for a squirrel that was out of its list (the computer's are in it only
--     while they are out on the asphalt), and TrafficService:cars() is the fleet as a squirrel at the kerb sees it;
--   * the rule (Shared/Wildlife/RoadCrossing): where the crossings are, what a careful look waits for, the misjudged
--     moment;
--   * the computer's squirrel crossing: down its tree, to the kerb, a look, across in a gap, up the tree beyond;
--     it waits for a car; it goes back up when no gap comes; one that races a car is met by the car;
--   * knocked flat (Server/Wildlife/RoadSquirrels): lying, out of every grid and pick, back at a tree; the cap; who is
--     not this service's;
--   * ten minutes of the town with its traffic: squirrels cross, careful ones are never hit, the few hit are the
--     ones that raced a car, never more than two a minute, every one back within two minutes;
--   * what the client draws (Client/Render/FlatView) and what it all costs.
local Data = require("@shared/Data")
local Height = require("@shared/World/Height")
local Units = require("@shared/Config/Units")
local Boxes = require("@shared/Traffic/Boxes")
local AICarMotor = require("@shared/Traffic/AICarMotor")
local PlayRules = require("@shared/Combat/PlayRules")
local RoadCrossing = require("@shared/Wildlife/RoadCrossing")
local Rng = require("@shared/Util/Rng")
local ForageRules = require("@shared/Foraging/ForageRules")
local NutSpots = require("@shared/Foraging/NutSpots")
local TownAI = require("@server/AI/TownAI")
local TrafficService = require("@server/Traffic/TrafficService")
local SweptCollision = require("@server/Traffic/SweptCollision")
local RoadSquirrels = require("@server/Wildlife/RoadSquirrels")
local ForageService = require("@server/Foraging/ForageService")
local FlatView = require("@client/Render/FlatView")

local DT = 1 / 30
local C = RoadCrossing.C
-- the trees with a crossing on the real town (TownAI.setRoad): the town's own trees, the set D21 was tuned on (168
-- with the D35 light posts counted)
local D21_SITES = 118

return function(t)
	local data = Data.default()
	local rail: any = nil

	local function fleet(): any
		return TrafficService.new({ lanes = data:lanes(), roads = data:roads(), heightAt = Height.at, seed = 7 })
	end

	local function town(squirrels: number?, seed: number?): any
		local world = TownAI.build({ data = data, seed = seed or 1, squirrels = squirrels, rail = rail })
		rail = world.rail
		return world
	end

	t.test("today's rules hold: cars brake for people only, and a run-over player reads RUN OVER", function()
		t.eq(AICarMotor.BRAKE_FOR_SQUIRRELS, false, "owner D15 #6")
		local title = PlayRules.deathMessage("traffic")
		t.eq(title, "RUN OVER!")
		for kind, fatal in Boxes.FATAL do
			t.eq(fatal, kind ~= "motorcycle", `{kind}: every vehicle but a motorcycle runs a squirrel over`)
		end
	end)

	-- A vehicle of `kind` that is moving, and a body standing where that vehicle will be a second and a half on (a twin
	-- fleet of the same seed says where: nothing the body does changes the vehicle's way, unless it stops for it), `up`
	-- studs over the road, kept there. Returns whether RunOver fired within six seconds, the vehicle's slowest pace
	-- meanwhile, its pace before, and its name ("none moving" when no vehicle of the kind drives in the first minutes).
	local function inTheWay(kind: string, up: number, as: string): (boolean, number, number, string)
		local traffic, twin = fleet(), fleet()
		local hit = false
		traffic.RunOver:connect(function(id: any)
			if id == "sq" then
				hit = true
			end
		end)
		local v: any = nil
		for _ = 1, 240 * 30 do
			traffic:step(DT, {})
			twin:step(DT, {})
			for _, o in traffic.vehicles do
				if o.kind == kind and o.visible and o.speed > 12 then
					v = o
					break
				end
			end
			if v then
				break
			end
		end
		if v == nil then
			return false, 0, 0, "none moving"
		end
		for _ = 1, 45 do
			twin:step(DT, {})
		end
		local there = twin.byId[v.id]
		local x, z = there.x, there.z
		local y = Height.at(x, z) + up
		local cruise = v.speed
		local slowest = v.speed
		for _ = 1, 6 * 30 do
			local world = if as == "person"
				then { people = { { kind = "human", x = x, y = y, z = z, visible = true } } }
				else { squirrels = { { id = "sq", x = x, y = y, z = z } } }
			traffic:step(DT, world)
			slowest = math.min(slowest, v.speed)
			if hit then
				break
			end
		end
		return hit, slowest, cruise, v.name
	end

	t.test("a player's squirrel on the road in a car's way is run over, by every kind in the fatal fleet", function()
		local seen = {}
		for _, kind in { "sedan", "rv", "dump_truck", "ice_cream_van", "trolley", "patrol_car", "ambulance" } do
			local hit, slowest, cruise, name = inTheWay(kind, 0.45, "squirrel")
			if name == "none moving" then
				continue -- (a kind that only drives when called out: the same box, the same sweep)
			end
			table.insert(seen, kind)
			t.truthy(hit, `{name} ({kind}) runs it over`)
			t.truthy(slowest > cruise * 0.9, `{name} does not slow for it ({slowest} of {cruise} studs/s)`)
		end
		print(`      run over on the real lanes by: {table.concat(seen, ", ")}`)
		t.truthy(#seen >= 5, `the kinds that drive every day ({#seen})`)
		-- a motorcycle hurts nobody (not in the fatal fleet)
		local hit, _, _, name = inTheWay("motorcycle", 0.45, "squirrel")
		if name ~= "none moving" then
			t.falsy(hit, "a motorcycle runs nobody over")
		end
	end)

	t.test("... but not up on a wire, a branch or a roof over the road; and every car stops for a person", function()
		for _, up in { 12, 20, 35 } do
			local hit = inTheWay("sedan", up, "squirrel")
			t.falsy(hit, `{up} studs over the road: safe`)
			hit = inTheWay("dump_truck", up, "squirrel")
			t.falsy(hit, `{up} studs over a dump truck's road: safe (its box is {Boxes.get("dump_truck").height} tall)`)
		end
		-- (standing on the car's own roof is safe too: the box's top is under its feet)
		local sedan = Boxes.get("sedan")
		local sweep = SweptCollision.new()
		local hits = sweep:step(
			{ { id = 1, x = 0, y = sedan.height, z = 3, prevX = 0, prevY = sedan.height, prevZ = 0 } },
			{
				{
					id = 1,
					kind = "sedan",
					x = 0,
					y = 0,
					z = 3,
					yaw = 0,
					prevX = 0,
					prevY = 0,
					prevZ = 0,
					prevYaw = 0,
					visible = true,
					prevVisible = true,
				},
			},
			DT
		)
		t.eq(#hits, 0, "riding on its roof")
		local hit, slowest, cruise, name = inTheWay("sedan", 0, "person")
		t.falsy(hit, "a person is never run over")
		t.truthy(slowest < cruise * 0.2, `{name} stops for a person ({slowest} of {cruise} studs/s)`)
	end)

	t.test("the sweep keeps no stale place; cars() is the fleet with its velocities", function()
		local traffic = fleet()
		local hits = 0
		traffic.RunOver:connect(function()
			hits += 1
		end)
		for _ = 1, 30 * 30 do
			traffic:step(DT, {})
		end
		local v: any = nil
		for _, o in traffic.vehicles do
			if o.kind == "sedan" and o.visible and o.speed > 12 then
				v = o
				break
			end
		end
		t.truthy(v ~= nil)
		-- cars(): every visible vehicle, moving the way it moves
		local cars = traffic:cars()
		local visible = 0
		for _, o in traffic.vehicles do
			if o.visible then
				visible += 1
			end
		end
		t.eq(#cars, visible)
		local car: any = nil
		for _, c in cars do
			if c.id == v.id then
				car = c
			end
		end
		t.truthy(car ~= nil)
		t.near(math.sqrt(car.vx ^ 2 + car.vz ^ 2), v.speed, 1.5, "its pace")
		t.truthy(car.vx * math.sin(v.yaw) + car.vz * math.cos(v.yaw) > 0, "its heading")
		t.eq(car.width, Boxes.get("sedan").width)
		-- a squirrel in the list far to one side of the car, out of the list for a second, then back in the list on the
		-- other side: its move is not swept across the car
		local fx, fz = math.sin(v.yaw), math.cos(v.yaw)
		local function beside(side: number): any
			return { id = "ai", x = v.x - fz * side, y = Height.at(v.x, v.z) + 0.45, z = v.z + fx * side }
		end
		for _ = 1, 3 do
			traffic:step(DT, { squirrels = { beside(40) } })
		end
		for _ = 1, 30 do
			traffic:step(DT, {})
		end
		for _ = 1, 3 do
			traffic:step(DT, { squirrels = { beside(-40) } })
		end
		t.eq(hits, 0, "no hit from where it stood a second ago")
		-- ... while a real dash across in front of it is one
		local side = 30
		for _ = 1, 60 do
			side -= 33 * DT
			local p = beside(side)
			p.x += fx * 4
			p.z += fz * 4
			traffic:step(DT, { squirrels = { p } })
		end
		t.truthy(hits >= 1, "a dash across under its nose")
	end)

	-- a crossing of a 45-stud road that runs along z at x = 0: from the east kerb (x = 24) to the west (x = -24)
	local SITE: any = {
		route = 1,
		s = 0,
		ax = 50,
		az = 0,
		kx = 24,
		kz = 0,
		fx = -24,
		fz = 0,
		to = 2,
		toS = 0,
		bx = -50,
		bz = 0,
		width = 48,
		length = 100,
	}
	local function carAt(x: number, z: number, vz: number): any
		return { id = 1, x = x, z = z, vx = 0, vz = vz, width = 6, length = 11 }
	end

	t.test("the rule: a careful look, the misjudged moment, a car worth coming down for", function()
		t.near(RoadCrossing.need(SITE), 48 / 33 + 0.8, 1e-9, "the dash and the margin")
		t.near(C.pace, Units.st(13.2), 1e-9, "it dashes at a squirrel's sprint")
		-- a car in the near lane (x = 11), 100 studs south, coming north at 20
		local t1, at = RoadCrossing.arrival(carAt(11, -100, 20), SITE)
		t.near(t1 :: number, (100 - 5.5) / 20, 1e-6, "until its nose is on the line")
		t.near(at :: number, 13, 1e-6, "its path, from the near kerb")
		t.eq(RoadCrossing.arrival(carAt(11, 100, 20), SITE), nil, "going away")
		t.eq(RoadCrossing.arrival(carAt(40, -100, 20), SITE), nil, "driving by beyond the kerb")
		t.eq(RoadCrossing.arrival(carAt(11, 3, 20), SITE), 0, "on the line now")
		t.eq(RoadCrossing.arrival(carAt(11, -12, 0), SITE), 0, "standing right by the line: it may pull off")
		t.eq(RoadCrossing.arrival(carAt(11, -40, 0), SITE), nil, "standing well back")
		t.truthy(RoadCrossing.arrival(carAt(-11, 100, -20), SITE) ~= nil, "the far lane, from the north")
		local clear = RoadCrossing.look({ carAt(11, -100, 20) }, SITE)
		t.truthy(clear, "4.7 s away: a gap")
		local blocked, car, tb = RoadCrossing.look({ carAt(11, -100, 20), carAt(-11, 40, -20) }, SITE)
		t.falsy(blocked, "1.7 s away: wait")
		t.eq((car :: any).x, -11, "the one that will be there soonest")
		t.near(tb :: number, (40 - 5.5) / 20, 1e-6)
		t.truthy(RoadCrossing.fast(carAt(0, 0, 20)))
		t.falsy(RoadCrossing.fast(carAt(0, 0, 8)), "a crawl is nothing to misjudge")
		-- the misjudged moment: the car no more than C.late further off than the dash to its path
		t.falsy(RoadCrossing.dares(2, 13), "too early: it would be across with time to spare")
		t.truthy(RoadCrossing.dares(13 / 33 + C.late, 13))
		t.falsy(RoadCrossing.dares(0, 13), "the car is on the line")
		-- a car worth coming down for: there after the squirrel is at the kerb, but not by long
		t.truthy(RoadCrossing.races(5, 3))
		t.falsy(RoadCrossing.races(3.2, 3), "it would be past before the squirrel got there")
		t.falsy(RoadCrossing.races(12, 3), "too far off to bother")
	end)

	t.test(
		"where: a crossing at about half the town's trees by a road, each run clear, kerb to kerb, tree to tree",
		function()
			local world = town(4)
			local n = TownAI.setRoad(world, function()
				return {}
			end)
			local road = world.ctx.road :: any
			print(`      {n} trees with a crossing`)
			-- D21's own set: the town's trees only. The D35 light posts' climbs and the D34 woods' trunks are "trunk"
			-- routes too (both in the town's routes here, so the checks below bite), climbed but never crossed from or
			-- to: with the posts counted the crossings came to 168, ~42% more than the owner tuned.
			local lamps, woods = 0, 0
			for _, r in world.routes.routes do
				if r.kind == "trunk" and r.lamp then
					lamps += 1
				elseif r.kind == "trunk" and r.woods then
					woods += 1
				end
			end
			t.truthy(lamps > 0 and woods > 0, `light post climbs {lamps}, woods trunks {woods}`)
			t.eq(n, D21_SITES, "the trees with a crossing are D21's")
			for id, site in road.sites do
				t.eq(site.route, id)
				local from, to = world.routes.byId(site.route), world.routes.byId(site.to)
				t.eq(from.kind, "trunk")
				t.eq(to.kind, "trunk")
				t.falsy(from.lamp or to.lamp, `no crossing from or to a light post ({site.route} -> {site.to})`)
				t.falsy(from.woods or to.woods, `nor a woods tree ({site.route} -> {site.to})`)
				t.truthy(site.width >= 20 and site.width <= 80, `kerb to kerb {site.width}`)
				t.truthy(site.length <= 2 * C.reach + site.width, `the whole run {site.length}`)
				-- the kerbs are off the asphalt, the middle is on it
				local mx, mz = (site.kx + site.fx) / 2, (site.kz + site.fz) / 2
				local onAsphalt = function(x: number, z: number): boolean
					for _, s in world.town.strips do
						if s.kind == "asphalt" then
							local along, across = if s.axis == "z" then z else x, if s.axis == "z" then x else z
							if math.abs(across - s.coord) <= s.half and along >= s.min and along <= s.max then
								return true
							end
						end
					end
					return false
				end
				t.truthy(onAsphalt(mx, mz), "the middle of the crossing is road")
				t.falsy(onAsphalt(site.ax, site.az), "the tree is not in the road")
				t.falsy(onAsphalt(site.bx, site.bz), "nor the one beyond")
				t.truthy(world.ctx.clear(site.ax, site.az, site.kx, site.kz), "a clear run to the kerb")
				t.truthy(world.ctx.clear(site.kx, site.kz, site.fx, site.fz), "across")
				t.truthy(world.ctx.clear(site.fx, site.fz, site.bx, site.bz), "and on to the tree")
			end
		end
	)

	-- One of the computer's squirrels on a tree with a crossing, about to cross, the cars as `cars()` says; every frame
	-- the fatal sweep of `sedan` (a vehicle pose, when given) against it while it is out on the asphalt.
	local function crosser(cars: () -> { any }, rand: (() -> number)?)
		local world = town(1)
		TownAI.setRoad(world, cars)
		local road = world.ctx.road :: any
		local sq: any = nil
		for _, a in world.actors do
			if a.species == "squirrel" and a.variant == "normal" then
				sq = a
			end
		end
		local brain = world.brains[sq.id] :: any
		if rand then
			brain.params = table.clone(brain.params)
			brain.params.rng = rand
		end
		-- on the first tree with a crossing, two thirds of the way up
		local site: any = nil
		local ids = {}
		for id in road.sites do
			table.insert(ids, id)
		end
		table.sort(ids)
		site = road.sites[ids[1]]
		local route = world.routes.byId(site.route)
		brain.route = route
		sq.intent.mode = "rail"
		sq.intent.routeId = route.id
		sq.intent.s = math.abs(site.s - route.length * 0.3)
		TownAI.setFocus(world, function()
			return { { x = sq.x, z = sq.z } }
		end)
		return world, sq, brain, site
	end
	local function onRoad(site: any, x: number, z: number): boolean
		-- between the kerbs (the line's own length, less the kerb strips)
		local dx, dz = site.fx - site.kx, site.fz - site.kz
		local u = ((x - site.kx) * dx + (z - site.kz) * dz) / (dx * dx + dz * dz)
		return u > C.kerb / site.width and u < 1 - C.kerb / site.width
	end

	t.test("a careful squirrel: down its tree, to the kerb, a look, across in a gap and up the tree beyond", function()
		local cars: { any } = {}
		local world, sq, brain, site = crosser(function()
			return cars
		end)
		brain.crossAt = 0.01 -- (its thought of crossing is due)
		local phases: { string } = {}
		local swept = 0
		local done = false
		local t0 = world.now
		for _ = 1, 40 * 60 do
			TownAI.stepFrame(world, 1 / 60)
			local c = brain.cross
			local ph = if c then c.phase else "none"
			if phases[#phases] ~= ph then
				table.insert(phases, ph)
			end
			if sq.crossing then
				swept += 1
				t.truthy(sq.intent.mode == "walk", "running, on the ground")
			end
			if onRoad(site, sq.x, sq.z) then
				t.truthy(sq.crossing, "in the fatal sweep the whole way across the asphalt")
			end
			if #phases > 1 and ph == "none" then
				done = true
				break
			end
		end
		t.truthy(done, "the crossing ends")
		t.deepEq(phases, { "none", "down", "toKerb", "look", "dash", "away", "none" })
		t.eq(brain.route.id, site.to, "on the tree beyond")
		t.eq(sq.intent.mode, "rail")
		t.eq(sq.crossing, nil)
		t.eq((world.ctx.road :: any).crossing, 0, "the town's count is back to none")
		t.truthy(swept > 0.8 * site.width / C.pace * 60, `in the sweep while on the road ({swept} frames)`)
		print(
			`      a crossing of {math.floor(site.length)} studs ({math.floor(site.width)} kerb to kerb) took {math.floor(
				(world.now - t0) * 10
			) / 10} s`
		)
	end)

	t.test("it waits at the kerb for a car, and goes back up its tree when no gap comes", function()
		-- a car that will be on the line in a second, for ever: no gap
		local cars: { any } = {}
		local world, sq, brain, site = crosser(function()
			return cars
		end, function(): number
			return 0.99 -- (never misjudges, never races)
		end)
		brain.crossAt = 0.01
		-- the car: on the crossing's own line, off to one side, coming at 20 studs/s, always 30 studs away
		local dx, dz = site.fx - site.kx, site.fz - site.kz
		local w = math.sqrt(dx * dx + dz * dz)
		local ux, uz = dx / w, dz / w
		local mx, mz = site.kx + dx * 0.3, site.kz + dz * 0.3
		cars[1] = { id = 7, x = mx + uz * 30, z = mz - ux * 30, vx = -uz * 20, vz = ux * 20, width = 6, length = 11 }
		local phases: { string } = {}
		local waited = 0
		for _ = 1, 60 * 60 do
			TownAI.stepFrame(world, 1 / 60)
			local c = brain.cross
			local ph = if c then c.phase else "none"
			if phases[#phases] ~= ph then
				table.insert(phases, ph)
			end
			if ph == "look" then
				waited += 1 / 60
			end
			t.falsy(onRoad(site, sq.x, sq.z), "never out on the road with the car coming")
			t.falsy(sq.crossing)
			if #phases > 1 and ph == "none" then
				break
			end
		end
		t.deepEq(phases, { "none", "down", "toKerb", "look", "back", "none" })
		t.truthy(waited >= C.patience and waited < C.patience + 1, `it waited {waited} s`)
		t.eq(brain.route.id, site.route, "back on its own tree")
		t.eq((world.ctx.road :: any).crossing, 0)
		-- the car gone by: the next time it gets across
		cars[1] = nil
		brain.crossAt = world.now
		local crossed = false
		for _ = 1, 60 * 60 do
			TownAI.stepFrame(world, 1 / 60)
			if brain.route.id == site.to then
				crossed = true
				break
			end
		end
		t.truthy(crossed, "with the road empty it crosses")
	end)

	t.test("a squirrel that races a car is met by it: knocked flat, lying, gone, and back at a tree", function()
		-- a sedan driving the road past the crossing at 21 studs/s, as the squirrel sees it and as the sweep has it
		local cars: { any } = {}
		local world, sq, brain, site = crosser(function()
			return cars
		end, function(): number
			return 0 -- (every dice says: go for it)
		end)
		brain.crossAt = math.huge -- (no thought of crossing of its own: only the car brings it down)
		rawset(brain.route, "links", {}) -- (and it stays on this tree meanwhile: every dice here says "take the link")
		local attrs: { [string]: any } = {}
		local possessable: boolean? = nil
		local dropped, cues = 0, {}
		local rng = Rng.new(5)
		local roads = RoadSquirrels.new({
			world = world,
			rand = function(): number
				return rng.next()
			end,
			setAttr = function(id: number, name: string, value: any)
				t.eq(id, sq.id)
				attrs[name] = if value == nil then "nil" else value
			end,
			setPossessable = function(_id: number, value: boolean)
				possessable = value
			end,
			onDown = function()
				dropped += 1
			end,
			cue = function(_id: number, name: string)
				table.insert(cues, name)
			end,
			serverTime = function(): number
				return 9000 + world.now
			end,
		})
		local dx, dz = site.fx - site.kx, site.fz - site.kz
		local w = math.sqrt(dx * dx + dz * dz)
		local ux, uz = dx / w, dz / w
		-- the car's lane: 70 % of the way across (the far lane), driving along the road
		local mx, mz = site.kx + dx * 0.7, site.kz + dz * 0.7
		local cx, cz = mx + uz * 400, mz - ux * 400
		local speed = 21
		local box = Boxes.get("sedan")
		local car =
			{ id = 7, x = cx, z = cz, vx = -uz * speed, vz = ux * speed, width = box.width, length = box.length }
		cars[1] = car
		local sweep = SweptCollision.new()
		local yaw = math.atan2(car.vx, car.vz)
		local prev = { x = sq.x, y = sq.y, z = sq.z }
		local hitAt: number? = nil
		local wasCrossing = false
		local careless = false
		local phases: { string } = {}
		for _ = 1, 40 * 60 do
			local px, pz = car.x, car.z
			car.x += car.vx / 60
			car.z += car.vz / 60
			TownAI.stepFrame(world, 1 / 60)
			roads:step(1 / 60)
			local c = brain.cross
			local ph = if c then c.phase else "none"
			if phases[#phases] ~= ph then
				table.insert(phases, ph)
			end
			careless = careless or (c ~= nil and c.careless)
			if sq.crossing then
				local y = Height.at(car.x, car.z)
				local hits = sweep:step({
					{
						id = sq.id,
						x = sq.x,
						y = sq.y - sq.hip,
						z = sq.z,
						prevX = prev.x,
						prevY = prev.y - sq.hip,
						prevZ = prev.z,
						teleported = not wasCrossing,
					},
				}, {
					{
						id = 7,
						kind = "sedan",
						x = car.x,
						y = y,
						z = car.z,
						yaw = yaw,
						prevX = px,
						prevY = y,
						prevZ = pz,
						prevYaw = yaw,
						visible = true,
						prevVisible = true,
					},
				}, 1 / 60)
				if #hits > 0 and hitAt == nil then
					hitAt = world.now
					t.truthy(roads:hit(sq.id), "knocked flat")
					break
				end
			end
			wasCrossing = sq.crossing == true
			prev.x, prev.y, prev.z = sq.x, sq.y, sq.z
		end
		t.truthy(hitAt ~= nil, "the car met it")
		t.truthy(careless, "it had misjudged the car")
		t.deepEq(
			phases,
			{ "none", "down", "toKerb", "look", "dash" },
			"it came down for that car and went at the last moment"
		)
		t.truthy(onRoad(site, sq.x, sq.z), "out on the road")
		-- knocked flat: lying on its side where it was hit, still
		t.eq(sq.gone, true)
		t.eq(sq.roll, RoadSquirrels.C.roll, "on its side")
		t.eq(sq.lift, RoadSquirrels.C.lieLift)
		t.eq(sq.crossing, nil, "out of the sweep")
		t.eq(brain.cross, nil)
		t.eq((world.ctx.road :: any).crossing, 0)
		t.near(attrs.Flat, 9000 + world.now, 1e-6, "the body's Flat: the server time of the hit")
		t.eq(possessable, false, "no player is handed it")
		t.eq(dropped, 1, "its nuts are lost")
		t.deepEq(cues, { "Road.Flat" })
		t.eq(roads:down(), 1)
		t.falsy(roads:hit(sq.id), "not twice")
		local x, z = sq.x, sq.z
		local buf = {}
		for _ = 1, 2 * 60 do
			TownAI.stepFrame(world, 1 / 60)
			roads:step(1 / 60)
		end
		t.near(sq.x, x, 1e-6, "it lies still")
		t.near(sq.z, z, 1e-6)
		t.eq(sq.lift, RoadSquirrels.C.lieLift, "still lying after two seconds")
		t.eq(world.grid:query(x, z, 50, buf), 0, "out of the grid: nobody sees it, nothing hunts it")
		brain:onEvent({ type = "startle", x = x, z = z })
		brain:onEvent({ type = "bait", x = x, z = z, untilTime = world.now + 60 })
		TownAI.stepFrame(world, 1 / 60)
		t.eq(sq.intent.mode, "stand", "nothing rouses it")
		-- gone: after three seconds it is out of sight
		for _ = 1, 1.2 * 60 do
			TownAI.stepFrame(world, 1 / 60)
			roads:step(1 / 60)
		end
		t.eq(sq.lift, RoadSquirrels.C.sink, "sunk out of sight")
		t.eq(sq.gone, true)
		-- back: within 93 s of the hit, on a tree, as new
		local away = RoadSquirrels.C.awaySecs
		local backAt: number? = nil
		for _ = 1, (away[2] + 5) * 60 do
			TownAI.stepFrame(world, 1 / 60)
			roads:step(1 / 60)
			if sq.gone == nil then
				backAt = world.now
				break
			end
		end
		t.truthy(backAt ~= nil, "it comes back")
		local gone = (backAt :: number) - (hitAt :: number)
		t.truthy(
			gone >= RoadSquirrels.C.lieSecs + away[1] - 0.1 and gone <= RoadSquirrels.C.lieSecs + away[2] + 0.1,
			`away {gone} s`
		)
		t.eq(sq.lift, nil)
		t.eq(sq.roll, nil)
		t.eq(attrs.Flat, "nil", "the attribute is gone")
		t.eq(possessable, true)
		t.eq(brain.route.kind, "trunk", "on a tree")
		-- (a tree, never a light post's climb: none is among the trunks it comes back on)
		t.falsy(brain.route.lamp, "not a light post")
		for _, r in (roads :: any).trunks do
			t.falsy(r.lamp, `trunk {r.id} to come back on is a light post's climb`)
		end
		t.eq(sq.intent.mode, "rail")
		local h = sq.y - Height.at(sq.x, sq.z)
		t.truthy(h > 3, `up its trunk ({h} studs over the ground)`)
		TownAI.stepFrame(world, 1 / 60)
		t.truthy(world.grid:query(sq.x, sq.z, 5, buf) >= 1, "in the grid again")
		t.eq(roads:down(), 0)
		local stats = roads:stats()
		t.eq(stats.hits, 1)
		t.eq(stats.back, 1)
		-- and it lives on: it moves again
		local moved0 = sq.moved
		for _ = 1, 20 * 60 do
			TownAI.stepFrame(world, 1 / 60)
		end
		t.truthy(sq.moved - moved0 > 5, "running its routes")
	end)

	t.test("the cap, and who is not knocked flat: a player's, the Spicy Rodent, an infected one", function()
		local world = town(6)
		local rng = Rng.new(2)
		local roads = RoadSquirrels.new({
			world = world,
			rand = function(): number
				return rng.next()
			end,
		})
		local list: { any } = {}
		local rodent: any = nil
		for _, a in world.actors do
			if a.species == "squirrel" and a.variant == "normal" then
				table.insert(list, a)
			elseif a.variant == "spicy" then
				rodent = a
			end
		end
		t.eq(#list, 6)
		t.falsy(roads:hit(rodent.id), "the Spicy Rodent is not this service's")
		t.eq(rodent.gone, nil)
		list[6].infected = true
		t.falsy(roads:hit(list[6].id), "nor an infected squirrel")
		TownAI.suspend(world, list[5].id)
		t.falsy(roads:hit(list[5].id), "nor a body a player holds (that is Boot/Game's RUN OVER)")
		t.falsy(roads:hit(123456), "nor nobody")
		for _, a in world.actors do
			if a.species == "human" then
				t.falsy(roads:hit(a.id), "nor a person")
				break
			end
		end
		t.truthy(roads:hit(list[1].id))
		t.truthy(roads:hit(list[2].id))
		t.falsy(roads:hit(list[3].id), "a third in the same minute is a near miss")
		t.falsy(roads:hit(list[3].id))
		t.eq(list[3].gone, nil)
		t.eq(roads:stats().spared, 1, "counted once")
		t.eq(roads:down(), 2)
		for _ = 1, 61 * 30 do
			TownAI.stepFrame(world, DT)
			roads:step(DT)
		end
		t.truthy(roads:hit(list[3].id), "a minute later the cap has room")
		-- stop(): everyone back at once
		roads:stop()
		t.eq(roads:down(), 0)
		for _, a in list do
			t.eq(a.gone, nil)
			t.eq(a.lift, nil)
		end
	end)

	t.test("a squirrel that is gone eats no nuts and is no one's pick", function()
		local world = town(3)
		local sq: any = nil
		for _, a in world.actors do
			if a.species == "squirrel" and a.variant == "normal" then
				sq = a
				break
			end
		end
		local picks = 0
		local forage = ForageService.new({
			world = world,
			hollows = {
				carry = function()
					return 0
				end,
				carried = function()
					return 0
				end,
			} :: any,
			placeOf = function(): (number?, number?, number?)
				return nil, nil, nil
			end,
			groundAt = Height.at,
			day = function(): number
				return 20
			end,
			onPick = function()
				picks += 1
			end,
			rng = function(): number
				return 0
			end,
		})
		local s = NutSpots.SPOTS[1]
		sq.x, sq.y, sq.z = s.x + 1, Height.at(s.x, s.z) + sq.hip, s.z
		world.brains[sq.id] = { onEvent = function() end } :: any
		sq.gone = true
		forage:step(ForageRules.C.aiEvery, 10)
		t.eq(picks, 0, "gone: it eats nothing")
		sq.gone = nil
		forage:step(ForageRules.C.aiEvery, 20)
		t.eq(picks, 1, "back: it eats again")
	end)

	t.test(
		"ten minutes of the town and its traffic: they cross, the careful are never hit, the few hit are back",
		function()
			local world = town(nil, 1)
			local traffic = fleet()
			TownAI.setRoad(world, function()
				return traffic:cars()
			end)
			local rng = Rng.new(9)
			local roads = RoadSquirrels.new({
				world = world,
				rand = function(): number
					return rng.next()
				end,
			})
			local squirrels: { any } = {}
			for _, a in world.actors do
				if a.species == "squirrel" and a.variant == "normal" then
					table.insert(squirrels, a)
				end
			end
			-- (a player by every squirrel: the busiest the roads can be)
			TownAI.setFocus(world, function()
				local out = {}
				for _, a in squirrels do
					table.insert(out, { x = a.x, z = a.z })
				end
				return out
			end)
			local flat: { number } = {}
			local carefulHit = 0
			traffic.RunOver:connect(function(id: any)
				local c = (world.brains[id] :: any).cross
				if roads:hit(id) then
					table.insert(flat, world.now)
					if not (c and c.careless) then
						carefulHit += 1
					end
				end
			end)
			local dashes, careless, back = 0, 0, 0
			local was: { [number]: string } = {}
			local longest = 0
			local since: { [number]: number } = {}
			local list: { any } = {}
			local worstTick = 0
			for _ = 1, 10 * 60 * 30 do
				TownAI.stepFrame(world, DT)
				table.clear(list)
				for _, a in squirrels do
					local c = (world.brains[a.id] :: any).cross
					local ph = if c then c.phase else "none"
					if ph ~= was[a.id] then
						if ph == "dash" then
							dashes += 1
							if c.careless then
								careless += 1
							end
						elseif ph == "back" then
							back += 1
						end
						was[a.id] = ph
						since[a.id] = world.now
					elseif ph ~= "none" then
						longest = math.max(longest, world.now - (since[a.id] or world.now))
					end
					if a.crossing then
						table.insert(list, { id = a.id, x = a.x, y = a.y - a.hip, z = a.z })
					end
				end
				t.truthy(#list <= C.atOnce, "never more than three on their way at once")
				local t0 = os.clock()
				traffic:step(DT, { squirrels = list })
				worstTick = math.max(worstTick, (os.clock() - t0) * 1000)
				roads:step(DT)
			end
			print(
				`      10 min, {#squirrels} squirrels, each with a player near: {dashes} crossings ({back} turned back at the kerb), {careless} raced a car, {#flat} knocked flat`
			)
			t.truthy(dashes >= 20, `they cross ({dashes} in ten minutes)`)
			t.eq(carefulHit, 0, "no careful squirrel is hit")
			t.truthy(#flat <= careless, "only one that raced a car is")
			t.truthy(careless <= dashes * 0.2, `mostly careful ({careless} of {dashes})`)
			for i = 3, #flat do
				t.truthy(flat[i] - flat[i - 2] >= 60, "never more than two knocked flat in a minute")
			end
			t.truthy(longest < 31, `no leg of a crossing hangs ({longest} s)`)
			-- the town's squirrels recover: two minutes on, every one is back and running
			for _ = 1, 100 * 30 do
				TownAI.stepFrame(world, DT)
				roads:step(DT)
			end
			t.eq(roads:down(), 0, "every squirrel is back")
			for _, a in squirrels do
				t.eq(a.gone, nil)
				t.eq(a.lift, nil)
			end
			t.eq(roads:stats().back, roads:stats().hits)
			print(`      the worst traffic tick with squirrels on the road: {worstTick} ms`)
		end
	)

	t.test("what the client draws: solid while it lies, a fade over the last second, a puff of pale dust", function()
		t.eq(FlatView.LIE, RoadSquirrels.C.lieSecs)
		t.eq(FlatView.FADE, RoadSquirrels.C.fadeSecs)
		t.eq(FlatView.fade(0), 0)
		t.eq(FlatView.fade(1.9), 0, "solid while it lies")
		t.near(FlatView.fade(2.5), 0.5, 1e-9)
		t.eq(FlatView.fade(3), 1)
		t.eq(FlatView.fade(60), 1, "unseen while it is away")
		local P = FlatView.PUFF
		t.truthy(P.count <= 6, "a handful of parts")
		for i = 1, P.count do
			local s0, r0, a0 = FlatView.puff(0, i)
			local s1, r1, a1 = FlatView.puff(P.secs * 0.9, i)
			t.truthy(
				(s1 :: number) > (s0 :: number) and (r1 :: number) > (r0 :: number) and (a1 :: number) > (a0 :: number)
			)
			t.truthy((s1 :: number) < 2.5, "small")
			t.eq(FlatView.puff(P.secs, i), nil, "over in half a second")
		end
		-- pale dust: never green, never red
		local r, g, b = P.color[1], P.color[2], P.color[3]
		t.truthy(math.abs(r - g) < 30 and math.abs(g - b) < 40 and r >= g, "a pale dust colour")
		t.truthy(string.match(RoadSquirrels.SOUNDS["Road.Flat"], "^rbxassetid://%d+$") ~= nil, "the hit has its sound")
	end)

	t.test(
		"cost: the crossings are found in a few milliseconds; a squirrel's think with the roads is microseconds",
		function()
			local world = town(14)
			local traffic = fleet()
			for _ = 1, 60 do
				traffic:step(DT, {})
			end
			local t0 = os.clock()
			local n = TownAI.setRoad(world, function()
				return traffic:cars()
			end)
			local found = (os.clock() - t0) * 1000
			t.truthy(n > 0)
			t.truthy(found < 60, `setRoad {found} ms`)
			local squirrels: { any } = {}
			for _, a in world.actors do
				if a.species == "squirrel" and a.variant == "normal" then
					table.insert(squirrels, a)
				end
			end
			-- every squirrel on a tree with a crossing, thinking with the fleet before it (the looks at the cars)
			local road = world.ctx.road :: any
			local sites = {}
			for id in road.sites do
				table.insert(sites, id)
			end
			table.sort(sites)
			for i, a in squirrels do
				local brain = world.brains[a.id] :: any
				local route = world.routes.byId(sites[i])
				brain.route = route
				a.intent.routeId = route.id
				a.intent.s = route.length * 0.5
				brain.crossAt = math.huge
			end
			local thinks = 0
			t0 = os.clock()
			for _ = 1, 300 do
				world.ctx.now += 0.1
				for _, a in squirrels do
					(world.brains[a.id] :: any):think(0.1, world.ctx)
					thinks += 1
				end
			end
			local each = (os.clock() - t0) * 1e6 / thinks
			print(
				`      setRoad {found} ms once; a squirrel's think on a tree by a road {each} us ({#traffic:cars()} cars looked at)`
			)
			t.truthy(each < 60, `a think {each} us`)
		end
	)
end
