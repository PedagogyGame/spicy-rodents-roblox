--!strict
-- Server/Infection/InfectionService and Server/Hospital/HospitalService on the real town (TownAI's
-- 102 actors, the real TrafficService, the real roads and buildings), stepped by hand: a bite that
-- collapses at once runs through the scene, the crowd, the ambulance, the bed and the walk home; a
-- delayed bite shows nothing for 40 s and then walks in; five scenes share three ambulances; a soak
-- over every kind of person leaves nothing behind (no order, no hidden body, no held ambulance); a
-- person a player holds is told what to do and is never moved; and nobody is cured anywhere but in
-- the hospital (owner 2026-11-10).
local Data = require("@shared/Data")
local Height = require("@shared/World/Height")
local Colliders = require("@shared/World/Colliders")
local HospitalLayout = require("@shared/Infection/HospitalLayout")
local InfectionRules = require("@shared/Infection/InfectionRules")
local MedicalRoute = require("@shared/Infection/MedicalRoute")
local Lines = require("@shared/Speech/Lines")
local Rng = require("@shared/Util/Rng")
local TownAI = require("@server/AI/TownAI")
local TrafficService = require("@server/Traffic/TrafficService")
local HospitalService = require("@server/Hospital/HospitalService")
local InfectionService = require("@server/Infection/InfectionService")

local DT = 0.2

type Harness = {
	world: any,
	traffic: any,
	svc: any,
	attrs: { [number]: { [string]: any } },
	medLog: { [number]: { string } },
	possessable: { [number]: boolean },
	toasts: { { id: number, key: string } },
	players: { [number]: boolean },
	time: number,
	step: (secs: number, each: (() -> ())?) -> (),
	runUntil: (limit: number, done: () -> boolean, each: (() -> ())?) -> boolean,
	rodent: number,
}

return function(t)
	local data = Data.default()
	local rail = nil :: any
	local colliders = Colliders.fromData(data)
	local layout = HospitalLayout.fromData(data) :: HospitalLayout.Layout

	-- `first` are the first dice (the bite's path and timer); after them a seeded generator
	local function harness(seed: number, first: { number }?, tune: ((params: any) -> ())?): Harness
		local world = TownAI.build({ data = data, seed = 1, squirrels = 3, deer = 0, fox = 0, rail = rail })
		rail = world.rail
		local traffic =
			TrafficService.new({ lanes = data:lanes(), roads = data:roads(), heightAt = Height.at, seed = 7 })
		local rng = Rng.new(seed)
		local scripted = table.clone(first or {})
		local params = InfectionRules.defaults()
		if tune then
			tune(params)
		end
		local h = {
			world = world,
			traffic = traffic,
			attrs = {},
			medLog = {},
			possessable = {},
			toasts = {},
			players = {},
			time = 0,
			rodent = 0,
		} :: any
		for _, a in world.actors do
			if a.variant == "spicy" then
				h.rodent = a.id
			end
		end
		h.svc = InfectionService.new({
			world = world,
			traffic = traffic,
			data = data,
			params = params,
			rand = function(): number
				if #scripted > 0 then
					return table.remove(scripted, 1) :: number
				end
				return rng.next()
			end,
			controllerOf = function(id: number): string
				return if h.players[id] then "player" else "ai"
			end,
			setAttr = function(id: number, name: string, value: any)
				h.attrs[id] = h.attrs[id] or {}
				h.attrs[id][name] = value
				if name == "Med" then
					h.medLog[id] = h.medLog[id] or {}
					table.insert(h.medLog[id], if value == nil then "-" else value)
				end
			end,
			setPossessable = function(id: number, value: boolean)
				h.possessable[id] = value
			end,
			notify = function(id: number, payload: { [string]: any })
				t.eq(payload.kind, "med")
				t.truthy(type(payload.text) == "string" and #payload.text > 10, `toast {payload.key} has no text`)
				table.insert(h.toasts, { id = id, key = payload.key })
			end,
			serverTime = function(): number
				return 5000 + h.time
			end,
		})
		local people = {}
		local function trafficWorld()
			-- what Boot/Game sends, less the people no vehicle is near (they cannot matter to traffic,
			-- and the yield tests are most of this spec's run time)
			table.clear(people)
			for _, a in world.actors do
				if a.species == "human" then
					for _, v in traffic.vehicles do
						if v.visible and (v.x - a.x) ^ 2 + (v.z - a.z) ^ 2 < 70 * 70 then
							table.insert(people, {
								kind = "human",
								x = a.x,
								y = a.y - a.hip,
								z = a.z,
								hospital = h.svc:trafficFlags(a.id),
							})
							break
						end
					end
				end
			end
			return { people = people }
		end
		h.step = function(secs: number, each: (() -> ())?)
			for _ = 1, math.floor(secs / DT + 0.5) do
				h.time += DT
				TownAI.stepFrame(world, DT)
				traffic:step(DT, trafficWorld())
				h.svc:step(DT)
				if each then
					each()
				end
			end
		end
		h.runUntil = function(limit: number, done: () -> boolean, each: (() -> ())?): boolean
			local stop = h.time + limit
			while h.time < stop do
				if done() then
					return true
				end
				h.step(DT, each)
			end
			return done()
		end
		return h
	end

	local function townspeople(h: Harness): { any }
		local out = {}
		for _, a in h.world.actors do
			if a.species == "human" and a.post == "townsperson" then
				table.insert(out, a)
			end
		end
		return out
	end

	local function nearest(list: { any }, x: number, z: number): any
		local best, bestD = nil, math.huge
		for _, a in list do
			local d = (a.x - x) ^ 2 + (a.z - z) ^ 2
			if d < bestD then
				best, bestD = a, d
			end
		end
		return best
	end

	local function responders(h: Harness): { any }
		local out = {}
		for _, v in h.traffic.vehicles do
			if v.class == "responder" then
				table.insert(out, v)
			end
		end
		return out
	end

	local function clean(h: Harness, what: string)
		for _, a in h.world.actors do
			if a.species == "human" then
				local brain = h.world.brains[a.id] :: any
				t.eq(brain.directive.mode, nil, `{what}: {a.post} {a.id} still under orders ({brain.directive.mode})`)
				t.eq(a.lift, nil, `{what}: {a.post} {a.id} still sunk`)
				t.truthy(not a.infected, `{what}: {a.post} {a.id} still infected`)
				t.truthy(h.possessable[a.id] ~= false, `{what}: {a.post} {a.id} is not possessable`)
				t.eq((h.attrs[a.id] or {}).Med, nil, `{what}: {a.post} {a.id} still shows Med`)
			end
		end
		for _, v in responders(h) do
			t.eq(v.phase, "idle", `{what}: {v.name} is {v.phase}`)
			t.truthy(not v.held, `{what}: {v.name} is still held`)
		end
		t.eq(next(h.svc.busy), nil, `{what}: someone is still busy at a scene`)
		t.eq(next(h.svc.scenes), nil, `{what}: a scene is still open`)
		t.eq(next(h.svc.leaving), nil, `{what}: someone never got home`)
		t.eq(#h.svc.queue, 0)
		t.eq(#h.svc.hospital:patients(), 0, `{what}: the hospital still has patients`)
		t.eq(h.svc:townPercent(), 0)
	end

	t.test("hospital: beds, a first-come queue, treatment for treatSecs, discharge frees the bed", function()
		local hosp = HospitalService.new({ beds = 2, treatSecs = 30 })
		t.eq(hosp:stateOf("a"), "none")
		t.eq(hosp:admit("a", 0), 1)
		t.eq(hosp:admit("b", 5), 2)
		t.eq(hosp:admit("c", 6), nil, "full: c waits")
		t.eq(hosp:admit("d", 7), nil)
		t.eq(hosp:admit("a", 9), 1, "admitting twice changes nothing")
		t.eq(hosp:stateOf("c"), "queued")
		t.eq(hosp:freeBeds(), 0)
		t.eq(#hosp:step(29.9), 0)
		t.deepEq(hosp:step(30), { "a" })
		t.eq(hosp:stateOf("a"), "done")
		t.eq(#hosp:step(31), 0, "reported once")
		t.eq(hosp:stateOf("c"), "queued", "a finished patient still holds the bed until discharged")
		hosp:discharge("a")
		t.eq(hosp:stateOf("a"), "none")
		hosp:step(32)
		t.eq(hosp:bedOf("c"), 1, "first come, first served")
		t.eq(hosp:stateOf("d"), "queued")
		t.deepEq(hosp:step(35), { "b" })
		t.eq(#hosp:step(61.9), 0, "c's 30 s started with the bed, at 32")
		t.deepEq(hosp:step(62), { "c" })
		hosp:discharge("d") -- a queued patient taken off the list
		hosp:discharge("b")
		hosp:step(63)
		t.eq(hosp:freeBeds(), 1)
		t.eq(#hosp:patients(), 1)
		t.eq(hosp:stats().admitted, 4)
		t.eq(hosp:stats().treated, 3)
		t.eq(hosp:stats().maxQueue, 2)
		-- a later arrival never jumps the queue into a bed that is about to be handed on
		local q = HospitalService.new({ beds = 1, treatSecs = 10 })
		q:admit(1, 0)
		q:admit(2, 1)
		q:step(10)
		q:discharge(1)
		t.eq(q:admit(3, 10.5), nil, "2 was first")
		q:step(11)
		t.eq(q:bedOf(2), 1)
	end)

	t.test("collapse at once: scene, crowd, ambulance on the roads, bed, cure, the walk home", function()
		local h = harness(11, { 0, 0 }) -- the collapse path, after the shortest run
		h.svc.tun.crowdChance = 1
		h.step(20) -- let the town settle onto its lanes
		local victim = nearest(townspeople(h), 0, 0)
		local id = victim.id
		local roads = h.svc.roads
		t.truthy(h.svc:biteable(id))
		t.truthy(h.svc:bite(id, h.rodent), "a new infection")
		t.truthy(h.svc:isInfected(id) and victim.infected == true)
		t.eq(h.svc:stateOf(id), "bitten")
		t.eq(h.world.brains[id].state, "flee", "the bitten person runs")
		local line = h.attrs[id].Say
		t.truthy(table.find(Lines.GROUPS.bitten, line) ~= nil, `the victim shouts ("{line}")`)
		t.near(h.attrs[id].SayAt, 5000 + h.time, 1e-6, "stamped with the clock clients share")
		t.eq(h.medLog[id], nil, "nothing shows yet")
		t.truthy(not h.svc:biteable(id), "not twice in a row")
		-- down within 1.5 s; the scene opens
		t.truthy(h.runUntil(5, function(): boolean
			return h.svc:stateOf(id) == "down"
		end))
		t.deepEq(h.medLog[id], { "down" })
		t.eq(h.possessable[id], false, "nobody can pick a patient on the ground")
		t.eq(h.world.brains[id].directive.mode, "down")
		local sx, sz = victim.x, victim.z
		local scene = h.svc.scenes[id]
		t.truthy(scene ~= nil)
		local crowd = #scene.bystanders
		t.truthy(crowd == 0 or (crowd >= 2 and crowd <= 4) or crowd == 1, `{crowd} bystanders`)
		print(`      scene at ({math.floor(sx)}, {math.floor(sz)}): {crowd} bystanders called over`)
		for _, b in scene.bystanders do
			t.eq(h.world.brains[b.id].directive.mode, "hold")
			t.truthy(h.svc:trafficFlags(b.id), "the ambulance does not stop for the crowd")
		end
		t.truthy(h.svc:trafficFlags(id))
		-- the call goes out after 4 s; an ambulance is dispatched and drives on the roads
		local worstOff, seenOut = 0, false
		local arrived = h.runUntil(140, function(): boolean
			local s = h.svc:stateOf(id)
			return s ~= "down" and s ~= "scene" and s ~= "enroute"
		end, function()
			t.eq(victim.x, sx, "the patient stays where they fell")
			t.eq(victim.z, sz)
			for _, v in responders(h) do
				if v.phase == "out" then
					seenOut = true
					local off = 0
					while off < 60 and not MedicalRoute.onRoad(roads, v.x, v.z, off) do
						off += 1
					end
					worstOff = math.max(worstOff, off)
				end
			end
		end)
		t.truthy(arrived and seenOut, `ambulance never arrived (state {h.svc:stateOf(id)})`)
		t.truthy(worstOff <= MedicalRoute.JOIN_GAP, `the ambulance was {worstOff} studs off the road`)
		t.eq(h.svc:stats().dispatched, 1)
		t.eq(h.svc:stats().abandoned, 0)
		local rec = h.svc.records[id]
		t.eq(rec.vehicle.phase, "hold", "held on scene")
		-- the crowd has gathered round the patient and is looking at them
		for _, b in scene.bystanders do
			local o = h.world.actorsById[b.id]
			local d = math.sqrt((o.x - sx) ^ 2 + (o.z - sz) ^ 2)
			t.truthy(d < 36, `bystander {b.id} is {d} studs away`)
			t.truthy(
				Colliders.pointIn(colliders, o.x, o.z, Height.at(o.x, o.z) + 3) == nil,
				"a bystander in a building"
			)
			t.truthy(table.find(Lines.GROUPS.bystander, (h.attrs[b.id] or {}).Say) ~= nil, "each bystander says a line")
		end
		-- crew, assessment, loading; then out of sight and off to the hospital
		local crew = rec.crew
		t.truthy(
			h.runUntil(140, function(): boolean
				return h.svc:stateOf(id) == "transit"
			end, function()
				t.eq(rec.vehicle.phase, "hold", "the ambulance waits until the patient is aboard")
			end),
			`never loaded (state {h.svc:stateOf(id)})`
		)
		if crew then
			t.truthy(table.find(Lines.GROUPS.crew, (h.attrs[crew] or {}).Say) ~= nil, "the crew speaks at the patient")
		end
		t.deepEq(h.medLog[id], { "down", "transit" })
		t.eq(victim.lift, InfectionService.SINK, "hidden: drawn under the ground")
		t.near(victim.x, layout.intake[1], 0.01, "and already at the hospital's intake")
		t.eq(next(h.svc.scenes), nil, "the scene is over")
		for _, b in scene.bystanders do
			t.eq(h.world.brains[b.id].directive.mode, nil, "the crowd goes back to its day")
		end
		t.truthy(victim.infected, "still infected")
		-- the ambulance drives home; the patient gets a bed
		t.truthy(
			h.runUntil(200, function(): boolean
				return h.svc:stateOf(id) == "treated"
			end),
			`never in a bed (state {h.svc:stateOf(id)})`
		)
		t.deepEq(h.medLog[id], { "down", "transit", "treated" })
		t.eq(victim.lift, nil)
		local bed = layout.beds[h.svc.hospital:bedOf(id)]
		t.near(victim.x, bed.x, 0.01)
		t.near(victim.z, bed.z, 0.01)
		for _, v in responders(h) do
			t.eq(v.phase, "idle", "the ambulance is parked again")
		end
		if crew then
			t.eq(h.world.actorsById[crew].lift, nil, "the crew member is back at the bay")
			t.eq(h.possessable[crew], true)
		end
		-- treated for 30 s, then cured in the hospital and nowhere else
		local treatedAt = h.time
		t.truthy(h.runUntil(40, function(): boolean
			return h.svc:stateOf(id) == nil
		end, function()
			if h.svc:stateOf(id) ~= nil then
				t.truthy(victim.infected, "infected until the treatment ends")
			end
		end))
		t.truthy(h.time - treatedAt >= 29.5, `treated for {h.time - treatedAt} s`)
		t.truthy(HospitalLayout.contains(layout, victim.x, victim.z), "cured inside the hospital")
		t.truthy(not victim.infected and not h.svc:isInfected(id))
		t.deepEq(h.medLog[id], { "down", "transit", "treated", "-" })
		t.eq(h.possessable[id], true)
		t.eq(h.svc:stats().cured, 1)
		-- home on foot the way a walk-in comes, never through a building
		t.truthy(h.svc.leaving[id] ~= nil)
		t.truthy(
			h.runUntil(700, function(): boolean
				return h.svc.leaving[id] == nil
			end, function()
				if not HospitalLayout.contains(layout, victim.x, victim.z, 4) then
					t.truthy(
						Colliders.pointIn(colliders, victim.x, victim.z, Height.at(victim.x, victim.z) + 3) == nil,
						`walked through a building at ({victim.x}, {victim.z})`
					)
				end
			end),
			"never got home"
		)
		t.truthy(math.sqrt((victim.x - sx) ^ 2 + (victim.z - sz) ^ 2) < 90, "back where they were bitten")
		h.step(30)
		clean(h, "after one case")
		t.truthy(h.world.brains[id].state == "walk" or h.world.brains[id].state == "flee", "walking the lane again")
	end)

	t.test("symptoms later: nothing shows for 40 s, then red eyes, then a walk in to the hospital", function()
		local h = harness(5, { 0.99, 0 }, function(params: any)
			params.walkInChance = 1
		end)
		h.step(20)
		-- the townsperson with the shortest walk to the hospital
		local victim, bestLen = nil, math.huge
		local routed = 0
		for _, a in townspeople(h) do
			local route, len = h.svc:walkRoute(a.x, a.z)
			if route then
				routed += 1
				t.deepEq(route[#route], layout.entrance)
				if len < bestLen then
					victim, bestLen = a, len
				end
			end
		end
		t.truthy(victim ~= nil, "nobody can walk to the hospital")
		print(
			`      {routed} of {#townspeople(h)} townspeople have a walk-in route; shortest {math.floor(bestLen)} studs`
		)
		t.truthy(routed >= #townspeople(h) * 0.5, `only {routed} townspeople can walk in`)
		local id = victim.id
		t.truthy(h.svc:bite(id, h.rodent))
		t.eq(h.svc:stateOf(id), "incubating")
		t.eq(h.world.brains[id].state, "flee")
		local function looksFine()
			t.eq(h.medLog[id], nil, "Med is never written while the case incubates")
			t.eq(h.world.brains[id].directive.mode, nil, "they look and act like anyone else")
			t.truthy(h.possessable[id] ~= false)
		end
		h.step(30, looksFine)
		t.truthy(h.svc:biteable(id), "an infected person on their feet can be bitten again")
		t.truthy(not h.svc:bite(id, h.rodent), "a second bite is not a second infection")
		t.eq(h.svc:stats().cases, 1)
		h.step(9.5, looksFine)
		t.truthy(h.runUntil(3, function(): boolean
			return h.svc:stateOf(id) == "symptomatic"
		end))
		t.deepEq(h.medLog[id], { "symptomatic" })
		t.truthy(table.find(Lines.GROUPS.symptoms, h.attrs[id].Say) ~= nil)
		t.truthy(h.runUntil(25, function(): boolean
			return h.svc:stateOf(id) == "walkin"
		end))
		t.eq(h.world.brains[id].directive.mode, "route")
		t.eq(h.svc:stats().walkIns, 1)
		t.eq(h.svc:stats().dispatched, 0, "no ambulance for a walk-in")
		local giveUp = h.svc.records[id].case.untilT - h.svc.now
		t.truthy(
			h.runUntil(giveUp + 5, function(): boolean
				local s = h.svc:stateOf(id)
				return s == "admitted" or s == "treated"
			end, function()
				if not HospitalLayout.contains(layout, victim.x, victim.z, 4) then
					t.truthy(
						Colliders.pointIn(colliders, victim.x, victim.z, Height.at(victim.x, victim.z) + 3) == nil,
						`walked through a building at ({victim.x}, {victim.z})`
					)
				end
				t.eq(victim.lift, nil, "a walk-in is never hidden")
			end),
			`did not reach the door (state {h.svc:stateOf(id)})`
		)
		t.truthy(
			HospitalLayout.nearEntrance(layout, victim.x, victim.z, 30)
				or HospitalLayout.contains(layout, victim.x, victim.z)
		)
		t.truthy(
			h.runUntil(60, function(): boolean
				return h.medLog[id][#h.medLog[id]] == "treated"
			end),
			"never sat down on the bed"
		)
		local bed = layout.beds[h.svc.hospital:bedOf(id)]
		t.near(victim.x, bed.x, 0.01)
		t.truthy(h.runUntil(40, function(): boolean
			return h.svc:stateOf(id) == nil
		end))
		t.deepEq(h.medLog[id], { "symptomatic", "treated", "-" })
		t.truthy(not victim.infected)
		t.eq(h.svc:stats().cured, 1)
	end)

	t.test("no way to walk, or the dice say no: the delayed case collapses and gets an ambulance", function()
		local h = harness(8, { 0.99, 0 }, function(params: any)
			params.walkInChance = 0
		end)
		h.step(20)
		local victim = nearest(townspeople(h), 300, 300)
		local id = victim.id
		h.svc:bite(id, h.rodent)
		t.truthy(h.runUntil(75, function(): boolean
			return h.svc:stateOf(id) == "down"
		end))
		t.deepEq(h.medLog[id], { "symptomatic", "down" })
		t.truthy(
			h.runUntil(420, function(): boolean
				return h.svc:stateOf(id) == nil
			end),
			`stuck in {h.svc:stateOf(id)}`
		)
		t.eq(h.svc:stats().cured, 1)
		t.eq(h.svc:stats().dispatched + h.svc:stats().abandoned, 1)
	end)

	t.test("no ambulance free for too long: the patient is taken in anyway, and the request is dropped", function()
		local h = harness(9, { 0, 0 }, function(params: any)
			params.ambulanceTimeoutSecs = 25
		end)
		h.step(20)
		-- all three responders are out on other business and never come back in time
		local away = {}
		for _ = 1, 3 do
			table.insert(
				away,
				h.traffic:dispatchResponder(
					{ 0, 0 },
					{ route = { { -890, 737.5 }, { -890, 707.5 }, { 0, 707.5 } }, hold = true }
				)
			)
		end
		local victim = nearest(townspeople(h), 0, 0)
		local id = victim.id
		h.svc:bite(id, h.rodent)
		t.truthy(h.runUntil(12, function(): boolean
			return h.svc:stateOf(id) == "scene"
		end))
		t.eq(#h.svc.queue, 1, "waiting for a responder")
		t.truthy(h.runUntil(30, function(): boolean
			return h.svc:stateOf(id) ~= "scene"
		end))
		t.eq(h.svc:stats().abandoned, 1)
		t.eq(#h.svc.queue, 0, "the request is dropped")
		t.eq(victim.lift, InfectionService.SINK)
		t.truthy(victim.infected, "taken in is not cured")
		t.truthy(h.runUntil(45, function(): boolean
			return h.svc:stateOf(id) == nil
		end))
		t.truthy(HospitalLayout.contains(layout, victim.x, victim.z))
		t.eq(h.svc:stats().cured, 1)
		for _, v in away do
			h.traffic:releaseResponder(v)
		end
	end)

	t.test("five scenes, three ambulances: everyone is collected, treated and released", function()
		local h = harness(21, nil, function(params: any)
			params.immediateChance = 1
		end)
		h.step(20)
		local people = townspeople(h)
		local ids = {}
		for i = 1, 5 do
			local a = people[i * 5]
			table.insert(ids, a.id)
			t.truthy(h.svc:bite(a.id, h.rodent))
		end
		local humans = 0
		for _, a in h.world.actors do
			if a.species == "human" then
				humans += 1
			end
		end
		t.eq(h.svc:townPercent(), 100 * 5 / humans)
		local maxOut = 0
		local allDone = h.runUntil(900, function(): boolean
			for _, id in ids do
				if h.svc:stateOf(id) ~= nil then
					return false
				end
			end
			return true
		end, function()
			local out = 0
			for _, v in responders(h) do
				if v.phase ~= "idle" then
					out += 1
				end
			end
			maxOut = math.max(maxOut, out)
		end)
		local stuck = {}
		for _, id in ids do
			table.insert(stuck, tostring(h.svc:stateOf(id)))
		end
		t.truthy(allDone, `not everyone was released: {table.concat(stuck, ", ")}`)
		t.eq(h.svc:stats().cured, 5)
		t.eq(maxOut, 3, "all three ambulances were out at once")
		t.eq(h.svc:stats().dispatched + h.svc:stats().abandoned >= 5, true)
		print(
			`      5 scenes: {h.svc:stats().dispatched} ambulance trips, {h.svc:stats().abandoned} taken in without one, {h.svc:stats().crowds} crowds, {h.svc:stats().lines} lines, done at {math.floor(
				h.time
			)} s`
		)
		t.truthy(
			h.runUntil(900, function(): boolean
				return next(h.svc.leaving) == nil
			end),
			"someone never got home"
		)
		h.step(60)
		clean(h, "after five scenes")
	end)

	t.test(
		"soak: 3 seeds, 16 people of every kind bitten; everyone is cured in the hospital and nothing is left behind",
		function()
			for seed = 1, 3 do
				local h = harness(seed * 101)
				local rng = Rng.new(seed)
				h.step(10)
				local humans = {}
				for _, a in h.world.actors do
					if a.species == "human" then
						table.insert(humans, a)
					end
				end
				rng.shuffle(humans)
				local posts: { [string]: number } = {}
				local bitten = {}
				for i = 1, 16 do
					local a = humans[i]
					posts[a.post] = (posts[a.post] or 0) + 1
					h.step(rng.int(0, 4))
					if h.svc:biteable(a.id) and h.svc:bite(a.id, h.rodent) then
						bitten[a.id] = true
					end
				end
				local open: { [number]: boolean } = table.clone(bitten)
				local done = h.runUntil(1500, function(): boolean
					return next(h.svc:cases()) == nil
				end, function()
					for id in open do
						if h.svc:stateOf(id) == nil then
							open[id] = nil
							local a = h.world.actorsById[id]
							t.truthy(
								HospitalLayout.contains(layout, a.x, a.z),
								`seed {seed}: {a.post} {id} was cured at ({a.x}, {a.z}), outside the hospital`
							)
						else
							t.truthy(
								h.world.actorsById[id].infected,
								`seed {seed}: {id} lost the infection in {h.svc:stateOf(id)}`
							)
						end
					end
					local held = 0
					for _, v in responders(h) do
						if v.phase ~= "idle" then
							held += 1
						end
					end
					t.truthy(held <= 3)
				end)
				local left = {}
				for id, case in h.svc:cases() do
					table.insert(left, `{h.world.actorsById[id].post} {id}: {case.state}`)
				end
				t.truthy(done, `seed {seed}: still open after {math.floor(h.time)} s: {table.concat(left, "; ")}`)
				local n = 0
				for _ in bitten do
					n += 1
				end
				t.eq(h.svc:stats().cured, n, `seed {seed}`)
				t.truthy(
					h.runUntil(900, function(): boolean
						return next(h.svc.leaving) == nil
					end),
					`seed {seed}: someone never got home`
				)
				h.step(60)
				clean(h, `seed {seed}`)
				local kinds = {}
				for post, c in posts do
					table.insert(kinds, `{c} {post}`)
				end
				table.sort(kinds)
				local s = h.svc:stats()
				print(
					`      seed {seed}: {n} cases ({table.concat(kinds, ", ")}): {s.dispatched} ambulance trips, {s.walkIns} walk-ins, {s.abandoned} without an ambulance, {s.crowds} crowds, {s.lines} lines; all home at {math.floor(
						h.time
					)} s`
				)
			end
		end
	)

	t.test(
		"a person a player holds: told what to do, never ordered about or moved, cured by standing in the hospital",
		function()
			local h = harness(31, { 0 }) -- the dice would say "collapse at once"
			h.step(20)
			local victim = nearest(townspeople(h), 0, 0)
			local id = victim.id
			h.players[id] = true
			h.world.possessed[id] = true -- the motor leaves a held body alone
			t.truthy(h.svc:bite(id, h.rodent))
			t.eq(h.svc:stateOf(id), "incubating", "a held person never collapses")
			t.deepEq(h.toasts[1], { id = id, key = "bitten" })
			t.truthy(table.find(Lines.GROUPS.bitten, h.attrs[id].Say) ~= nil, "their body still shouts")
			local x0, z0 = victim.x, victim.z
			h.step(130, function()
				t.eq(h.world.brains[id].directive.mode, nil, "no order for a held body")
				t.eq(victim.x, x0)
				t.eq(victim.z, z0)
				t.eq(victim.lift, nil)
				t.truthy(h.possessable[id] ~= false)
			end)
			t.eq(h.svc:stateOf(id), "symptomatic")
			t.deepEq(h.medLog[id], { "symptomatic" }, "the red eyes show on a held body too")
			local keys = {}
			for _, toast in h.toasts do
				if toast.id == id then
					table.insert(keys, toast.key)
				end
			end
			t.deepEq(keys, { "bitten", "symptoms" })
			-- the rodent's player (not held here) would have been told too
			t.truthy(h.toasts[#h.toasts].key == "symptoms" or h.toasts[#h.toasts].key == "victimSick")
			-- the player walks into the hospital
			victim.x, victim.z = layout.reception[1], layout.reception[2]
			h.step(1)
			t.eq(h.svc:stateOf(id), "treated")
			h.step(20)
			victim.x, victim.z = layout.outside[1], layout.outside[2] - 40 -- wanders out early
			h.step(1)
			t.eq(h.svc:stateOf(id), "symptomatic")
			t.truthy(victim.infected)
			victim.x, victim.z = layout.reception[1], layout.reception[2]
			h.step(29)
			t.truthy(h.svc:isInfected(id), "not yet")
			h.step(3)
			t.eq(h.svc:stateOf(id), nil)
			t.truthy(not victim.infected)
			keys = {}
			for _, toast in h.toasts do
				if toast.id == id then
					table.insert(keys, toast.key)
				end
			end
			t.deepEq(keys, { "bitten", "symptoms", "treating", "leftEarly", "treating", "cured" })
			t.deepEq(h.medLog[id], { "symptomatic", "-" })
			t.eq(h.svc.hospital:stats().admitted, 0, "no bed is used")
			t.eq(h.world.brains[id].directive.mode, nil)
		end
	)

	t.test("the rodent's death cures nobody: only the hospital does", function()
		local h = harness(41, { 0.99, 0.99 }) -- incubates for close to two minutes
		h.step(10)
		local victim = nearest(townspeople(h), 0, 0)
		h.svc:bite(victim.id, h.rodent)
		-- the rodent is knocked out and respawns at its hide: nothing in the service reacts to that
		local rodent = h.world.actorsById[h.rodent]
		rodent.x, rodent.z = 2000, 2000
		t.eq((h.svc :: any).cure, nil, "there is no cure call")
		t.eq((h.svc :: any).resetToRodent, nil)
		h.step(100)
		t.truthy(h.svc:isInfected(victim.id) and victim.infected, "still infected 100 s after the rodent is gone")
		t.eq(h.svc:stats().cured, 0)
	end)

	t.test(
		"speech: people who spot the Spicy Rodent say so, a few at a time; an ordinary squirrel gets no comment",
		function()
			local h = harness(51)
			h.step(5)
			local people = townspeople(h)
			local normal = 0
			for _, a in h.world.actors do
				if a.species == "squirrel" and a.variant == "normal" then
					normal = a.id
				end
			end
			for _, a in people do
				h.svc:onSpotted(a.id, normal)
			end
			t.eq(h.svc:stats().lines, 0, "just a squirrel")
			for _, a in people do
				h.svc:onSpotted(a.id, h.rodent)
			end
			t.eq(h.svc:stats().lines, 3, "34 people saw it in the same instant: three speak")
			local said = 0
			for _, a in people do
				local line = (h.attrs[a.id] or {}).Say
				if line then
					said += 1
					t.truthy(
						table.find(Lines.GROUPS.spotting, line) ~= nil or table.find(Lines.GROUPS.fleeing, line) ~= nil,
						`"{line}" is not a spotting line`
					)
					t.near(h.attrs[a.id].SayAt, 5000 + h.time, 1e-6)
				end
			end
			t.eq(said, 3)
			-- an infected squirrel is "one of those squirrels" too
			h.world.actorsById[normal].infected = true
			h.step(6)
			local before = h.svc:stats().lines
			for _, a in people do
				h.svc:onSpotted(a.id, normal)
			end
			t.eq(h.svc:stats().lines - before, 3)
			-- over a few minutes of spotting, the owner's line is heard
			local heard: { [string]: boolean } = {}
			for _ = 1, 150 do
				h.step(2)
				for _, a in people do
					h.svc:onSpotted(a.id, h.rodent)
					local line = (h.attrs[a.id] or {}).Say
					if line then
						heard[line] = true
					end
				end
			end
			t.truthy(heard[Lines.THE_LINE], `"{Lines.THE_LINE}" was never said`)
			-- the brain's own report reaches the service: put the rodent in front of someone
			local h2 = harness(52)
			h2.step(5)
			local who = nearest(townspeople(h2), 0, 0)
			local rodent = h2.world.actorsById[h2.rodent]
			local spoke = false
			for _ = 1, 60 do
				-- keep the rodent 10 studs ahead of the walker, in plain view, moving
				rodent.x, rodent.z = who.x + math.sin(who.yaw) * 10, who.z + math.cos(who.yaw) * 10
				rodent.y = h2.world.ctx.groundAt(rodent.x, rodent.z) + 0.5
				rodent.speed = 40
				h2.world.possessed[h2.rodent] = true -- as if a player held it there
				h2.world.grid:set(h2.rodent, rodent.x, rodent.z)
				h2.step(0.5)
				if h2.svc:stats().lines > 0 then
					spoke = true
					break
				end
			end
			t.truthy(spoke, "a townsperson who saw the rodent said something")
		end
	)
end
