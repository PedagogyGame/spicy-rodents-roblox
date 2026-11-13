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
local FootPath = require("@shared/World/FootPath")
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
	drivers: { [number]: any }, -- who plays a body (the service's driverOf)
	time: number,
	worstMs: number, -- the longest single step of the service (it runs inside a server frame)
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
			drivers = {},
			busy = {},
			time = 0,
			worstMs = 0,
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
			driverOf = function(id: number): any?
				return h.drivers[id]
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
			busy = function(id: number): boolean
				return h.busy[id] == true
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
				local t0 = os.clock()
				h.svc:step(DT)
				h.worstMs = math.max(h.worstMs, (os.clock() - t0) * 1000)
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

	-- A body in plain sight that moves further in one step than anyone can run is a teleport somebody
	-- may be watching. `look()` is called after every step; the jumps it saw are listed.
	local function jumpWatch(h: Harness): (() -> (), { string })
		local prev: { [number]: { number } } = {}
		local jumps: { string } = {}
		local function look()
			-- a cured person out of sight for the trip home is nobody's to play (a player handed that
			-- body would start under the ward)
			for id, l in h.svc.leaving do
				if l.away then
					t.eq(h.possessable[id], false, `{id} is on offer to players while out of sight on the way home`)
				end
			end
			for _, a in h.world.actors do
				if a.species == "human" then
					local shown = if (a.lift or 0) == 0 then 1 else 0
					local p = prev[a.id]
					if p == nil then
						prev[a.id] = { a.x, a.z, shown }
					else
						local d = math.sqrt((a.x - p[1]) ^ 2 + (a.z - p[2]) ^ 2)
						if d > 6 and p[3] == 1 and shown == 1 and not h.players[a.id] then
							table.insert(
								jumps,
								`{a.post} {a.id} moved {math.floor(d)} studs in one step at {math.floor(h.time)} s ({h.svc:stateOf(
									a.id
								) or "no case"})`
							)
						end
						p[1], p[2], p[3] = a.x, a.z, shown
					end
				end
			end
		end
		return look, jumps
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
		t.truthy(crowd == 0 or (crowd >= 2 and crowd <= 4), `{crowd} bystanders (one alone is not a crowd)`)
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
		-- (with a crew the patient is walked to the ambulance on their feet: "carried")
		local walked = rec.crewSecs > 0
		t.deepEq(h.medLog[id], if walked then { "down", "carried", "transit" } else { "down", "transit" })
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
		t.deepEq(
			h.medLog[id],
			if walked then { "down", "carried", "transit", "treated" } else { "down", "transit", "treated" }
		)
		t.eq(victim.lift, nil)
		local bed = layout.beds[h.svc.hospital:bedOf(id)]
		t.near(victim.x, bed.x, 0.01)
		t.near(victim.z, bed.z, 0.01)
		-- sitting up along the cot, looking down its length (their legs lie out in front of them: turned
		-- to the ward door they lay across the corner of the cot and through its frame)
		local d = h.world.brains[id].directive
		t.eq(d.mode, "down")
		local fx, fz = d.faceX - bed.x, d.faceZ - bed.z
		local fl = math.sqrt(fx * fx + fz * fz)
		t.near((fx * math.sin(layout.yaw) + fz * math.cos(layout.yaw)) / fl, 1, 1e-6, "facing along the cot")
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
		t.deepEq(
			h.medLog[id],
			if walked then { "down", "carried", "transit", "treated", "-" } else { "down", "transit", "treated", "-" }
		)
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

	t.test("a case that comes due while its body rides the sky lift waits for the platform (review)", function()
		local h = harness(5, { 0.99, 0 }, function(params: any)
			params.walkInChance = 1
		end)
		h.step(5)
		local victim = townspeople(h)[1]
		local id = victim.id
		t.truthy(h.svc:bite(id, h.rodent))
		t.eq(h.svc:stateOf(id), "incubating")
		h.busy[id] = true -- on the lift: the Ride attribute
		h.step(90)
		t.eq(h.svc:stateOf(id), "incubating", "symptoms came on in a cabin")
		t.eq(h.medLog[id], nil)
		h.busy[id] = nil -- off at the platform
		t.truthy(h.runUntil(5, function(): boolean
			return h.svc:stateOf(id) == "symptomatic"
		end))
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

	t.test(
		"two collapses a minute apart: the first patient's cure never takes the second patient's ambulance away",
		function()
			local h = harness(13, nil, function(params: any)
				params.immediateChance = 1
			end)
			h.step(20)
			local people = townspeople(h)
			local first = nearest(people, 0, 0)
			local a = first.id
			t.truthy(h.svc:bite(a, h.rodent))
			t.truthy(
				h.runUntil(400, function(): boolean
					return h.svc:stateOf(a) == "treated"
				end),
				`the first patient never got a bed (state {h.svc:stateOf(a)})`
			)
			t.eq(h.svc:stats().dispatched, 1)
			local recA = h.svc.records[a]
			t.eq(recA.vehicle, nil, "a record lets go of its ambulance once the trip is over")
			t.eq(recA.amb, "none")
			-- the second collapse, while the first patient is in bed: the same ambulance goes out again
			local second = nil
			for _, p in people do
				if p.id ~= a and h.svc.busy[p.id] == nil and h.svc.leaving[p.id] == nil then
					local d = (p.x - first.x) ^ 2 + (p.z - first.z) ^ 2
					if second == nil or d < (second.x - first.x) ^ 2 + (second.z - first.z) ^ 2 then
						second = p
					end
				end
			end
			local b = second.id
			t.truthy(h.svc:bite(b, h.rodent))
			local closedA, vehicle, sawHold = nil :: number?, nil :: any, false
			t.truthy(
				h.runUntil(300, function(): boolean
					return h.svc:stateOf(b) == "transit"
				end, function()
					if closedA == nil and h.svc:stateOf(a) == nil then
						closedA = h.time
					end
					local rec = h.svc.records[b]
					if rec and rec.vehicle and h.svc:stateOf(b) ~= "transit" then
						vehicle = vehicle or rec.vehicle
						t.eq(rec.vehicle, vehicle, "one ambulance for the whole call")
						t.eq(
							vehicle.held,
							true,
							`the ambulance was let go at {h.time} s, before the patient was aboard`
						)
						local s = h.svc:stateOf(b)
						if s == "approach" or s == "assess" or s == "loading" or s == "retrieve" then
							sawHold = true
							t.eq(vehicle.phase, "hold", `the ambulance left the scene during {s}`)
						end
					end
				end),
				`the second patient was never loaded (state {h.svc:stateOf(b)})`
			)
			t.truthy(vehicle ~= nil and sawHold, "the second patient's ambulance came and waited")
			t.truthy(
				closedA ~= nil,
				"the first patient was cured while the second call was running (or the test has no teeth)"
			)
			t.eq(h.svc:stats().dispatched, 2)
			t.eq(h.svc:stats().abandoned, 0, "nobody was left on the pavement")
			t.truthy(
				h.runUntil(300, function(): boolean
					return h.svc:stateOf(b) == nil
				end),
				`the second patient was never cured (state {h.svc:stateOf(b)})`
			)
			t.eq(h.svc:stats().cured, 2)
		end
	)

	t.test("an ambulance that is called off on the way: the patient is not left waiting for it", function()
		local h = harness(14, { 0, 0 })
		h.step(20)
		local victim = nearest(townspeople(h), 0, 0)
		local id = victim.id
		t.truthy(h.svc:bite(id, h.rodent))
		t.truthy(h.runUntil(60, function(): boolean
			return h.svc:stateOf(id) == "enroute"
		end))
		local rec = h.svc.records[id]
		local lost = rec.vehicle
		h.step(3)
		h.traffic:releaseResponder(lost) -- something else lets it go: it will turn round at the scene
		local other = nil :: any
		t.truthy(
			h.runUntil(300, function(): boolean
				return h.svc:stateOf(id) == "transit"
			end, function()
				local s = h.svc:stateOf(id)
				if rec.vehicle and rec.vehicle ~= lost then
					other = rec.vehicle
				end
				if s == "approach" or s == "assess" or s == "loading" or s == "retrieve" then
					t.truthy(rec.vehicle ~= lost, "nobody is loaded into an ambulance that is not waiting for them")
					t.eq(rec.vehicle.phase, "hold")
					t.eq(rec.vehicle.held, true)
				end
			end),
			`never loaded (state {h.svc:stateOf(id)})`
		)
		t.truthy(other ~= nil, "a second ambulance was sent")
		t.eq(h.svc:stats().abandoned, 0)
		t.eq(h.svc:stats().dispatched, 2)
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
					h.step(rng.int(0, 4))
					if h.svc:biteable(a.id) and h.svc:bite(a.id, h.rodent) then
						bitten[a.id] = true
						posts[a.post] = (posts[a.post] or 0) + 1
					else
						-- (a rider shouts and rides off: never a case)
						t.truthy(a.post == "rider" or not h.svc:biteable(a.id), `{a.post} {a.id} was not infected`)
					end
				end
				local open: { [number]: boolean } = table.clone(bitten)
				local look, jumps = jumpWatch(h)
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
					look()
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
					end, look),
					`seed {seed}: someone never got home`
				)
				h.step(60, look)
				-- nobody was moved in plain sight: not the patients, not the crews, not the crowds, not
				-- the cured on their way home (28 of 80 people used to vanish at the hospital door, and
				-- the paramedics used to pop from the bay to the scene)
				t.eq(#jumps, 0, `seed {seed}: {table.concat(jumps, "; ")}`)
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
					)} s; longest service step {math.floor(h.worstMs * 10) / 10} ms`
				)
				-- the service runs inside a server frame: no step may hold one up for long (the path
				-- searches are budgeted; this is Lune on a shared machine, so the bound is loose)
				t.truthy(h.worstMs < 40, `seed {seed}: a service step took {h.worstMs} ms`)
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
			-- what the player was told, in order (a repeat of the same message is a reminder)
			local function told(): ({ string }, number)
				local keys, repeats = {}, 0
				for _, toast in h.toasts do
					if toast.id == id then
						if keys[#keys] == toast.key then
							repeats += 1
						else
							table.insert(keys, toast.key)
						end
					end
				end
				return keys, repeats
			end
			local keys, reminders = told()
			t.deepEq(keys, { "bitten", "symptoms" })
			t.eq(reminders, 2, "symptoms at 40 s, told again at 80 s and 120 s")
			t.eq(h.svc:statusOf(id), "symptoms", "and the status line says so all the time")
			-- the rodent's player (not held here) would have been told too
			t.truthy(h.toasts[#h.toasts].key == "symptoms" or h.toasts[#h.toasts].key == "victimSick")
			-- a second bite: not a second infection, and the player is told about it too
			t.truthy(not h.svc:bite(id, h.rodent))
			t.deepEq(h.toasts[#h.toasts], { id = id, key = "bittenAgain" })
			t.eq(victim.x, x0, "still not moved")
			t.eq(h.world.brains[id].directive.mode, nil)
			-- the player walks into the hospital
			victim.x, victim.z = layout.reception[1], layout.reception[2]
			h.step(1)
			t.eq(h.svc:stateOf(id), "treated")
			t.eq(h.svc:statusOf(id), "treating")
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
			t.eq(h.svc:statusOf(id), nil, "nothing on the status line once cured")
			keys = told()
			t.deepEq(keys, { "bitten", "symptoms", "bittenAgain", "treating", "leftEarly", "treating", "cured" })
			t.deepEq(h.medLog[id], { "symptomatic", "-" })
			t.eq(h.svc.hospital:stats().admitted, 0, "no bed is used")
			t.eq(h.world.brains[id].directive.mode, nil)
		end
	)

	-- nobody walks through a building: `own` are the boxes a walk may start or end inside
	local function outdoors(a: any, what: string, own: { [string]: boolean }?)
		if HospitalLayout.contains(layout, a.x, a.z, 4) then
			return
		end
		local hit = Colliders.pointIn(colliders, a.x, a.z, Height.at(a.x, a.z) + 3)
		t.truthy(hit == nil or (own ~= nil and own[hit.id]), `{what} walked through {if hit then hit.id else ""}`)
	end

	local function boxesAt(x: number, z: number): { [string]: boolean }
		local own: { [string]: boolean } = {}
		for _, b in colliders.boxes do
			if math.abs(x - b.cx) < b.hw + 2 and math.abs(z - b.cz) < b.hd + 2 then
				own[b.id] = true
			end
		end
		return own
	end

	t.test(
		"off the pavements: someone the sidewalk graph cannot reach still walks in, across the open ground, round the buildings",
		function()
			local h = harness(61, { 0.99, 0 }, function(params: any)
				params.walkInChance = 1
			end)
			h.step(20)
			-- everyone who stands where no pavement leads to the hospital: the police yard and station,
			-- the shop floors, and the pavements the sidewalk graph does not join up
			local cut, walkable = {}, 0
			for _, a in h.world.actors do
				if
					a.species == "human"
					and not HospitalLayout.contains(layout, a.x, a.z)
					and h.svc:sidewalkRoute(a.x, a.z) == nil
				then
					table.insert(cut, a)
					local route, len = h.svc:walkRoute(a.x, a.z)
					if route then
						walkable += 1
						t.deepEq(route[#route], layout.entrance, "every walk in ends at the door")
						t.truthy(len <= h.svc.params.walkInMaxDist + 10)
					end
				end
			end
			print(
				`      {#cut} people stand where no pavement leads to the hospital; {walkable} of them can walk in all the same`
			)
			t.truthy(#cut >= 15, `only {#cut} people off the pavements (the test has no teeth)`)
			t.truthy(
				walkable >= #cut - 3,
				`only {walkable} of {#cut} have a way in (the three beyond the river may not)`
			)
			-- and when they collapse instead: the crew can walk from the nearest road to every person in
			-- town, round the buildings, but for the few beyond the river (those are taken in out of
			-- sight). Nobody is too far from a road to be collected.
			local reach = h.svc.tun.crewRunSpeed * h.svc.params.crewMaxSecs
			local humans, unreached, furthest = 0, 0, 0
			for _, a in h.world.actors do
				if a.species == "human" then
					humans += 1
					local stage = MedicalRoute.stage(h.svc.roads, a.x, a.z) :: MedicalRoute.Stage
					local path, len = FootPath.find(h.svc.foot, stage.x, stage.z, a.x, a.z, { maxLength = reach })
					if path == nil then
						unreached += 1
						t.truthy(a.x > 1900, `the crew cannot reach {a.post} {a.id} at ({a.x}, {a.z})`)
					else
						furthest = math.max(furthest, len)
					end
				end
			end
			print(
				`      the crew can walk to {humans - unreached} of {humans} people (furthest {math.floor(furthest)} studs from the road)`
			)
			t.truthy(unreached <= 3, `{unreached} people the crew cannot reach`)
			-- one of them, a police officer in the yard, far from any road, is bitten and walks in
			local victim = nil
			for _, a in cut do
				if a.post == "police" and h.world.brains[a.id].kind == "Officer" and h.svc:walkRoute(a.x, a.z) then
					victim = a
					break
				end
			end
			t.truthy(victim ~= nil, "no officer in the yard")
			local id = victim.id
			t.truthy(MedicalRoute.stage(h.svc.roads, victim.x, victim.z).dist > 300, "far from any road")
			t.truthy(h.svc:bite(id, h.rodent))
			t.truthy(
				h.runUntil(75, function(): boolean
					return h.svc:stateOf(id) == "walkin"
				end),
				`did not set off (state {h.svc:stateOf(id)})`
			)
			local giveUp = h.svc.records[id].case.untilT - h.svc.now
			t.truthy(
				h.runUntil(giveUp + 5, function(): boolean
					local s = h.svc:stateOf(id)
					return s == "admitted" or s == "treated"
				end, function()
					outdoors(victim, "the walk-in")
					t.eq(victim.lift, nil, "a walk-in is never hidden")
				end),
				`did not reach the door (state {h.svc:stateOf(id)})`
			)
			t.eq(h.svc:stats().dispatched, 0, "no ambulance for a walk-in")
			t.truthy(h.runUntil(120, function(): boolean
				return h.svc:stateOf(id) == nil
			end))
			t.truthy(HospitalLayout.contains(layout, victim.x, victim.z), "cured in the hospital")
			t.truthy(not victim.infected)
			-- and walks back to the beat, round the buildings again (no pop back to the station)
			local post = h.world.brains[id].points[1]
			t.deepEq(h.svc.leaving[id].home, post, "an officer goes back to the post, not to where the bite was")
			local worstStep, px, pz = 0, victim.x, victim.z
			t.truthy(
				h.runUntil(400, function(): boolean
					return h.svc.leaving[id] == nil
				end, function()
					outdoors(victim, "the walk home")
					worstStep = math.max(worstStep, math.sqrt((victim.x - px) ^ 2 + (victim.z - pz) ^ 2))
					px, pz = victim.x, victim.z
				end),
				"never got back"
			)
			t.truthy(worstStep < 6, `moved {worstStep} studs in one step on the way home (a teleport)`)
			t.truthy(math.sqrt((victim.x - post[1]) ^ 2 + (victim.z - post[2]) ^ 2) < 6, "back on the beat")
			h.step(20)
			clean(h, "after the officer's walk")
		end
	)

	t.test(
		"far from any road: the crew walks round the buildings to the patient and carries them back; beyond the river the patient is taken in out of sight",
		function()
			local h = harness(62, nil, function(params: any)
				params.immediateChance = 1
			end)
			h.svc.tun.crowdChance = 0
			h.step(20)
			-- a police clerk inside the station (540 studs from the nearest road, a building round them)
			-- and a shop worker beyond the river (no road, no way on foot)
			local clerk, far = nil, nil
			for _, a in h.world.actors do
				if a.species == "human" then
					local dist = MedicalRoute.stage(h.svc.roads, a.x, a.z).dist
					if a.post == "police" and h.world.brains[a.id].kind == "Staff" and clerk == nil then
						clerk = a
					elseif a.post == "shop_worker" and dist > 900 and far == nil then
						far = a
					end
				end
			end
			t.truthy(clerk ~= nil and far ~= nil, "the town has no such people")
			t.eq(h.svc:walkRoute(far.x, far.z), nil, "nobody walks in from beyond the river")
			local own = boxesAt(clerk.x, clerk.z)
			t.truthy(next(own) ~= nil, "the clerk stands inside the station")
			t.truthy(h.svc:bite(clerk.id, h.rodent))
			t.truthy(h.svc:bite(far.id, h.rodent))
			-- (the clerk runs first, inside the station, and falls where the run ends)
			local cx, cz, fx, fz = nil :: number?, clerk.z, far.x, far.z
			-- the clerk: an ambulance to the nearest road, the crew out of sight until it is there
			local recC = h.svc.records[clerk.id]
			local crew, crewActor = nil :: number?, nil :: any
			local steppedOut = nil :: { number }?
			local worstCrew = 0
			t.truthy(
				h.runUntil(400, function(): boolean
					return h.svc:stateOf(clerk.id) == "transit"
				end, function()
					local s = h.svc:stateOf(clerk.id)
					if recC.crew and crew == nil then
						crew = recC.crew
						crewActor = h.world.actorsById[crew]
					end
					if crewActor then
						if s == "scene" or s == "enroute" then
							t.eq(
								crewActor.lift,
								InfectionService.SINK,
								"the crew rides out of sight (no pop from the bay)"
							)
							t.eq(h.possessable[crew], false)
						elseif s == "approach" or s == "assess" or s == "loading" or s == "retrieve" then
							t.eq(crewActor.lift, nil, "the crew is out and in sight")
							if steppedOut == nil then
								steppedOut = { crewActor.x, crewActor.z }
							end
							outdoors(crewActor, "the crew", own)
							if s == "approach" or s == "retrieve" then
								worstCrew = math.max(worstCrew, crewActor.speed)
							end
						end
					end
					if s == "retrieve" then
						outdoors(clerk, "the carried patient", own)
						t.eq(clerk.lift, nil, "carried in sight")
					elseif s ~= "transit" and s ~= "bitten" then
						cx = cx or clerk.x
						t.eq(clerk.x, cx, "the patient stays where they fell until they are carried")
						t.truthy(
							own[(Colliders.pointIn(colliders, clerk.x, clerk.z, Height.at(clerk.x, clerk.z) + 3) :: any).id]
						)
					end
				end),
				`the clerk was never loaded (state {h.svc:stateOf(clerk.id)})`
			)
			t.truthy(crew ~= nil and steppedOut ~= nil, "a crew member walked to the patient")
			t.truthy(recC.crewSecs > 0 and recC.crewLen > 300, `a walk of {recC.crewLen} studs`)
			local stage = recC.stage
			local out = steppedOut :: { number }
			t.truthy(
				math.sqrt((out[1] - stage.x) ^ 2 + (out[2] - stage.z) ^ 2) < 8,
				"the crew steps out beside the ambulance"
			)
			t.truthy(worstCrew <= h.svc.tun.crewRunSpeed + 0.5, `the crew ran at {worstCrew} studs/s`)
			t.truthy(worstCrew > h.svc.tun.crewSpeed, "a far patient is hurried to")
			-- the worker beyond the river: collected all the same, never left on the ground for ever
			local recF = h.svc.records[far.id]
			t.truthy(
				h.runUntil(500, function(): boolean
					local s = h.svc:stateOf(far.id)
					return s == "transit" or s == "admitted" or s == "treated" or s == nil
				end, function()
					local s = h.svc:stateOf(far.id)
					if s == "down" or s == "scene" or s == "enroute" then
						t.eq(far.x, fx)
						t.eq(far.z, fz)
					end
				end),
				`the far patient is stuck in {h.svc:stateOf(far.id)}`
			)
			t.eq(recF.crewSecs, 0, "no crew can walk there: taken in where they sit")
			-- both are cured in the hospital and nowhere else
			local curedAt: { [number]: boolean } = {}
			local farAway = 0
			t.truthy(
				h.runUntil(500, function(): boolean
					-- (and on until the worker's trip home has been watched for a few steps: which of
					-- the two is cured last depends on which ambulance was quicker)
					return h.svc:stateOf(clerk.id) == nil
						and h.svc:stateOf(far.id) == nil
						and (farAway >= 5 or h.svc.leaving[far.id] == nil)
				end, function()
					-- the worker has no way home on foot: out of sight from the bed for the trip, and
					-- not on offer to players while under the ward
					local l = h.svc.leaving[far.id]
					if l then
						farAway += 1
						t.truthy(l.away)
						t.eq(far.lift, InfectionService.SINK, "out of sight until home")
						t.truthy(HospitalLayout.contains(layout, far.x, far.z), "and still at the bed, not at the door")
						t.eq(h.possessable[far.id], false, "nobody is handed a body under the ward")
					elseif farAway > 0 then
						t.eq(h.possessable[far.id], true, "home: anyone's to play again")
					end
					for _, a in { clerk, far } do
						if h.svc:stateOf(a.id) == nil and not curedAt[a.id] then
							curedAt[a.id] = true
							t.truthy(HospitalLayout.contains(layout, a.x, a.z), `{a.post} cured outside the hospital`)
						elseif h.svc:stateOf(a.id) ~= nil then
							t.truthy(a.infected)
						end
					end
				end),
				`not cured: {h.svc:stateOf(clerk.id)}, {h.svc:stateOf(far.id)}`
			)
			t.eq(h.svc:stats().cured, 2)
			t.truthy(farAway >= 5, `the worker was out of sight for {farAway} steps of the trip home`)
			t.eq(h.svc:stats().abandoned, 0, "an ambulance came for both")
			-- home: the clerk on foot, back into the station; the worker (no way on foot) out of sight
			-- from the bed and then at the shop, never walked out to the front door to vanish there
			local farLeft = false
			t.truthy(
				h.runUntil(500, function(): boolean
					return next(h.svc.leaving) == nil
				end, function()
					outdoors(clerk, "the clerk on the way home", own)
					if not farLeft and h.svc.leaving[far.id] ~= nil then
						t.eq(far.lift, InfectionService.SINK, "out of sight until home")
						t.truthy(HospitalLayout.contains(layout, far.x, far.z), "and still at the bed, not at the door")
						t.eq(h.possessable[far.id], false)
					elseif h.svc.leaving[far.id] == nil then
						farLeft = true
					end
				end),
				"someone never got home"
			)
			local postC, postF = h.world.brains[clerk.id].points[1], h.world.brains[far.id].points[1]
			t.truthy(
				math.sqrt((clerk.x - postC[1]) ^ 2 + (clerk.z - postC[2]) ^ 2) < 12,
				"the clerk is back at the desk"
			)
			t.truthy(math.sqrt((far.x - postF[1]) ^ 2 + (far.z - postF[2]) ^ 2) < 12, "the worker is back at the shop")
			t.truthy(cz ~= nil)
			h.step(30)
			clean(h, "after the far patients")
		end
	)

	t.test(
		"a paramedic bitten in town goes back to the bay when cured; nobody on the way home is sent out as crew",
		function()
			local h = harness(63, nil, function(params: any)
				params.immediateChance = 1
			end)
			h.svc.tun.crowdChance = 0
			h.step(20)
			local medic = nil
			for _, a in h.world.actors do
				if a.post == "ambulance_crew" then
					medic = a
					break
				end
			end
			local station = h.world.brains[medic.id].points[1]
			-- the paramedic is at a scene in the middle of town when the rodent gets them
			local spot = nearest(townspeople(h), 0, 0)
			medic.x, medic.z = spot.x + 6, spot.z
			h.world.brains[medic.id]:onEvent({ type = "medical", mode = "down" })
			t.truthy(h.svc:bite(medic.id, h.rodent))
			t.truthy(
				h.runUntil(420, function(): boolean
					return h.svc:stateOf(medic.id) == nil
				end),
				`the paramedic was never cured (state {h.svc:stateOf(medic.id)})`
			)
			local l = h.svc.leaving[medic.id]
			t.truthy(l ~= nil, "walking back")
			t.deepEq(l.home, station, "to the bay, not to the street corner where the bite was")
			-- while they walk back another patient needs a crew: not this one
			local other = nearest(townspeople(h), 300, 300)
			t.truthy(h.svc:bite(other.id, h.rodent))
			local sawCrew = false
			t.truthy(
				h.runUntil(120, function(): boolean
					return h.svc.leaving[medic.id] == nil
				end, function()
					local rec = h.svc.records[other.id]
					if rec and rec.crew then
						sawCrew = true
						t.truthy(rec.crew ~= medic.id, "a paramedic on the way home was sent out again")
					end
					outdoors(medic, "the paramedic")
				end),
				"the paramedic never got back to the bay"
			)
			t.truthy(sawCrew, "the other call had a crew (or the test has no teeth)")
			t.truthy(math.sqrt((medic.x - station[1]) ^ 2 + (medic.z - station[2]) ^ 2) < 6, "back at the bay")
			t.truthy(h.runUntil(600, function(): boolean
				return next(h.svc:cases()) == nil and next(h.svc.leaving) == nil
			end))
			h.step(30)
			clean(h, "after the paramedic")
		end
	)

	t.test(
		"the crowd: a blocked onlooker is replaced by the next nearest; a scene has a crowd of two to four or none",
		function()
			local h = harness(64, nil, function(params: any)
				params.immediateChance = 1
				params.collapseAfterSecs = { 0.2, 0.4 }
			end)
			h.svc.tun.crowdChance = 1
			h.step(20)
			-- scenes all over town, one after another, each closed again before the next (so the same
			-- people are free to come)
			local sizes: { [number]: number } = {}
			local scenes = 0
			local people = townspeople(h)
			for i = 1, #people, 2 do
				local a = people[i]
				if h.svc:biteable(a.id) and h.svc.busy[a.id] == nil and h.svc:bite(a.id, h.rodent) then
					t.truthy(h.runUntil(3, function(): boolean
						return h.svc:stateOf(a.id) == "down"
					end))
					local scene = h.svc.scenes[a.id]
					local n = #scene.bystanders
					sizes[n] = (sizes[n] or 0) + 1
					scenes += 1
					t.truthy(n == 0 or (n >= 2 and n <= 4), `a crowd of {n} at ({a.x}, {a.z})`)
					for _, b in scene.bystanders do
						local o = h.world.actorsById[b.id]
						t.truthy(
							(o.x - a.x) ^ 2 + (o.z - a.z) ^ 2 <= 180 ^ 2,
							"called from further than the scene radius"
						)
					end
					-- the scene ends (the test's own way of ending it: the service's shutdown path for one case)
					h.svc:shutdown()
					a.infected = nil
				end
			end
			local parts = {}
			for n = 0, 4 do
				table.insert(parts, `{sizes[n] or 0} of {n}`)
			end
			print(`      {scenes} scenes with a crowd wanted every time: {table.concat(parts, ", ")}`)
			t.eq(sizes[1] or 0, 0, "one onlooker alone is not a crowd")
			t.truthy(scenes - (sizes[0] or 0) >= scenes * 0.6, "most scenes on the pavements get their crowd")
		end
	)

	t.test(
		"a player ends up holding a patient: the person is back on their feet, the ambulance and the crew are let go, the hospital is still the cure",
		function()
			local h = harness(65, { 0, 0 })
			h.svc.tun.crowdChance = 1
			h.step(20)
			local victim = nearest(townspeople(h), 0, 0)
			local id = victim.id
			t.truthy(h.svc:bite(id, h.rodent))
			t.truthy(h.runUntil(60, function(): boolean
				return h.svc:stateOf(id) == "enroute"
			end))
			local rec = h.svc.records[id]
			local vehicle, crew = rec.vehicle, rec.crew
			t.truthy(vehicle ~= nil and crew ~= nil)
			t.eq(h.possessable[id], false, "a patient is never offered")
			-- the hand-over that should not have happened happens anyway
			h.players[id] = true
			h.world.possessed[id] = true
			local x0, z0 = victim.x, victim.z
			h.step(0.4)
			t.eq(h.svc:stateOf(id), "symptomatic", "on their feet, the case is a held person's now")
			t.truthy(victim.infected and h.svc:isInfected(id), "standing up is not a cure")
			t.eq(h.attrs[id].Med, "symptomatic", "red eyes; not posed, not hidden")
			t.eq(victim.lift, nil)
			t.eq(h.possessable[id], true)
			t.eq(h.world.brains[id].directive.mode, nil, "no order on a held body")
			t.eq(next(h.svc.scenes), nil, "the scene is closed")
			t.eq(next(h.svc.busy), nil, "the crowd and the crew are let go")
			t.eq(h.world.actorsById[crew].lift, nil, "the crew member is back in sight at the bay")
			t.eq(h.possessable[crew], true)
			t.eq(rec.vehicle, nil)
			t.eq(vehicle.held, false, "the ambulance is released")
			t.eq(#h.svc.queue, 0)
			t.eq(h.toasts[#h.toasts].key, "symptoms", "and the player is told what to do")
			t.eq(h.svc:statusOf(id), "symptoms")
			t.eq(h.svc:stats().stoodDown, 1)
			-- nothing is done to them from now on, however long they stay away
			h.step(200, function()
				t.eq(victim.x, x0, "a held body is never moved")
				t.eq(victim.z, z0)
				t.eq(victim.lift, nil)
				t.eq(h.world.brains[id].directive.mode, nil)
			end)
			t.eq(h.svc:stateOf(id), "symptomatic")
			for _, v in responders(h) do
				t.eq(v.phase, "idle", "the ambulance went home")
			end
			t.eq(h.svc:stats().cured, 0)
			-- the player walks into the hospital and is cured there
			victim.x, victim.z = layout.reception[1], layout.reception[2]
			h.step(32)
			t.eq(h.svc:stateOf(id), nil)
			t.truthy(not victim.infected)
			t.eq(h.svc:stats().cured, 1)
			h.players[id] = nil
			h.world.possessed[id] = nil
			h.step(5)
			clean(h, "after the held patient")
		end
	)

	t.test(
		"a patient let go by a player inside the hospital finishes as a patient there: no slide out through the wall",
		function()
			local h = harness(66, { 0 })
			h.step(20)
			local victim = nearest(townspeople(h), 0, 0)
			local id = victim.id
			-- the real hand-over: the brain is suspended while the player has the body
			TownAI.suspend(h.world, id)
			h.players[id] = true
			t.truthy(h.svc:bite(id, h.rodent))
			-- the player walks the body into the hospital and stands in reception
			victim.x, victim.z = layout.reception[1], layout.reception[2]
			h.step(10)
			t.eq(h.svc:stateOf(id), "treated")
			-- and lets go of it ten seconds into the treatment
			h.players[id] = nil
			TownAI.resume(h.world, id, victim.x, victim.y, victim.z)
			local worst, px, pz = 0, victim.x, victim.z
			t.truthy(
				h.runUntil(120, function(): boolean
					return h.svc:stateOf(id) == nil
				end, function()
					t.truthy(
						HospitalLayout.contains(layout, victim.x, victim.z, 12),
						`left the hospital: ({victim.x}, {victim.z}) in {h.svc:stateOf(id)}`
					)
					worst = math.max(worst, math.sqrt((victim.x - px) ^ 2 + (victim.z - pz) ^ 2))
					px, pz = victim.x, victim.z
				end),
				`never cured (state {h.svc:stateOf(id)})`
			)
			t.truthy(worst < 6, `moved {worst} studs in one step`)
			t.eq(h.svc:stats().dispatched, 0, "no ambulance: they were already there")
			t.eq(h.svc.hospital:stats().admitted, 1, "treated in a bed like any walk-in")
			t.deepEq(h.medLog[id], { "symptomatic", "treated", "-" })
			t.truthy(not victim.infected)
		end
	)

	t.test(
		"a body that leaves the world mid-scene: everything round it is let go, the case waits, and the cure is still the hospital",
		function()
			local h = harness(67, { 0, 0 })
			h.svc.tun.crowdChance = 1
			h.step(20)
			local victim = nearest(townspeople(h), 0, 0)
			local id = victim.id
			t.truthy(h.svc:bite(id, h.rodent))
			t.truthy(h.runUntil(60, function(): boolean
				return h.svc:stateOf(id) == "enroute"
			end))
			local vehicle = h.svc.records[id].vehicle
			-- the body is gone (the actor is no longer in the world's index)
			h.world.actorsById[id] = nil
			h.step(1)
			t.eq(next(h.svc.scenes), nil)
			t.eq(next(h.svc.busy), nil)
			t.eq(#h.svc.queue, 0)
			t.eq(vehicle.held, false, "the ambulance is let go")
			t.truthy(h.svc:isInfected(id), "the case is kept")
			t.eq(h.svc:stateOf(id), "symptomatic")
			-- five minutes later nothing has happened to the case, nothing has failed, nobody was cured
			h.step(300)
			t.eq(h.svc:stateOf(id), "symptomatic")
			t.eq(h.svc:stats().cured, 0)
			t.eq(h.svc:stats().faults, 0)
			for _, v in responders(h) do
				t.eq(v.phase, "idle")
			end
			t.eq(h.svc.hospital:stats().admitted, 0)
			-- the body is back: the person is ill on their feet and ends up in the hospital like anyone
			h.world.actorsById[id] = victim
			victim.infected = nil -- (a body that came back knows nothing)
			h.step(0.4)
			t.truthy(victim.infected, "still infected")
			t.eq(h.attrs[id].Med, "symptomatic")
			t.truthy(
				h.runUntil(700, function(): boolean
					return h.svc:stateOf(id) == nil
				end, function()
					if h.svc:stateOf(id) == nil then
						t.truthy(HospitalLayout.contains(layout, victim.x, victim.z), "cured outside the hospital")
					end
				end),
				`stuck in {h.svc:stateOf(id)} after coming back`
			)
			t.eq(h.svc:stats().cured, 1)
			t.truthy(h.runUntil(700, function(): boolean
				return next(h.svc.leaving) == nil
			end))
			h.step(30)
			clean(h, "after the body came back")
		end
	)

	t.test(
		"faults are contained: a broken dispatch, a broken brain and a switch-off leave nobody stuck and nobody cured for free",
		function()
			-- the ambulances cannot be sent at all: every patient is taken in after the timeout
			local faults = {}
			local h = harness(68, nil, function(params: any)
				params.immediateChance = 1
				params.ambulanceTimeoutSecs = 20
			end)
			h.svc.onFault = function(where: string, err: any)
				table.insert(faults, `{where}: {err}`)
			end
			h.step(20)
			local people = townspeople(h)
			h.traffic.dispatchResponder = function()
				error("no ambulances today")
			end
			local a, b = people[3], people[9]
			t.truthy(h.svc:bite(a.id, h.rodent))
			t.truthy(h.svc:bite(b.id, h.rodent))
			t.truthy(
				h.runUntil(120, function(): boolean
					return h.svc:stateOf(a.id) == nil and h.svc:stateOf(b.id) == nil
				end, function()
					for _, p in { a, b } do
						if h.svc:stateOf(p.id) ~= nil then
							t.truthy(p.infected, "nobody is cured by a fault")
						end
					end
				end),
				`stuck: {h.svc:stateOf(a.id)}, {h.svc:stateOf(b.id)}`
			)
			t.truthy(#faults > 0 and string.find(faults[1], "queue", 1, true) ~= nil, "the fault was reported")
			t.eq(h.svc:stats().abandoned, 2)
			t.eq(h.svc:stats().cured, 2)
			t.truthy(HospitalLayout.contains(layout, a.x, a.z, 40) or h.svc.leaving[a.id] ~= nil)
			-- one person's brain fails on an order: that case is put back on its feet and tried again;
			-- the other case in town is not held up by it
			local h2 = harness(69, nil, function(params: any)
				params.immediateChance = 1
			end)
			local reported = 0
			h2.svc.onFault = function()
				reported += 1
			end
			h2.step(20)
			local p2 = townspeople(h2)
			local bad, good = p2[4], p2[12]
			local brain = h2.world.brains[bad.id]
			local real = brain.onEvent
			local broke = 0
			brain.onEvent = function(self: any, evt: any)
				if evt.type == "medical" and evt.mode == "hidden" and broke < 1 then
					broke += 1
					error("this brain cannot hide")
				end
				return real(self, evt)
			end
			t.truthy(h2.svc:bite(bad.id, h2.rodent))
			t.truthy(h2.svc:bite(good.id, h2.rodent))
			t.truthy(
				h2.runUntil(900, function(): boolean
					return h2.svc:stateOf(bad.id) == nil and h2.svc:stateOf(good.id) == nil
				end, function()
					if h2.svc:stateOf(bad.id) ~= nil then
						t.truthy(bad.infected, "a fault is not a cure")
					end
				end),
				`stuck: {h2.svc:stateOf(bad.id)}, {h2.svc:stateOf(good.id)}`
			)
			t.eq(broke, 1, "the brain failed once")
			t.eq(reported, 1, "and it was reported")
			t.eq(h2.svc:stats().faults, 1)
			t.eq(h2.svc:stats().stoodDown, 1, "that case was put back on its feet")
			t.eq(h2.svc:stats().cured, 2)
			t.truthy(h2.runUntil(900, function(): boolean
				return next(h2.svc.leaving) == nil
			end))
			h2.step(30)
			clean(h2, "after the faults")
			-- switched off in the middle of everything: every body is let go, nothing is left held
			local h3 = harness(70, nil, function(params: any)
				params.immediateChance = 1
			end)
			h3.svc.tun.crowdChance = 1
			h3.step(20)
			local p3 = townspeople(h3)
			local bitten = {}
			for i = 2, 14, 4 do
				h3.svc:bite(p3[i].id, h3.rodent)
				table.insert(bitten, p3[i])
				h3.step(25)
			end
			h3.svc:shutdown()
			h3.step(120)
			t.eq(h3.svc:stats().cured, 0, "switching off cures nobody")
			for _, p in bitten do
				t.truthy(p.infected, "still infected (nobody is tracking it any more)")
				p.infected = nil
			end
			clean(h3, "after the switch-off")
		end
	)

	t.test(
		"ten minutes of everything at once (bites, players taking and dropping bodies, patients included, bodies leaving the world, ambulances called off): nothing fails, nobody is stuck, nothing is left behind",
		function()
			for seed = 1, 2 do
				local h = harness(700 + seed)
				local rng = Rng.new(900 + seed)
				local faults: { string } = {}
				h.svc.onFault = function(where: string, err: any)
					table.insert(faults, `{where}: {err}`)
				end
				h.step(10)
				local humans = {}
				for _, a in h.world.actors do
					if a.species == "human" then
						table.insert(humans, a)
					end
				end
				local heldAt: { [number]: { number } } = {} -- bodies players hold, and where they stand
				local gone: { [number]: any } = {}
				local counts = { bites = 0, taken = 0, patientsTaken = 0, dropped = 0, left = 0, calledOff = 0 }
				local function take(a: any)
					TownAI.suspend(h.world, a.id)
					h.players[a.id] = true
					heldAt[a.id] = { a.x, a.z, h.time }
					counts.taken += 1
				end
				local function drop(id: number)
					local a = h.world.actorsById[id] or gone[id]
					h.players[id] = nil
					heldAt[id] = nil
					TownAI.resume(h.world, id, a.x, a.y, a.z)
					counts.dropped += 1
				end
				local function meddle()
					local a = humans[rng.int(1, #humans)]
					local roll = rng.next()
					local here = h.world.actorsById[a.id] ~= nil
					if roll < 0.4 then
						if here and h.svc:biteable(a.id) then
							h.svc:bite(a.id, h.rodent)
							counts.bites += 1
						end
					elseif roll < 0.52 then
						-- a player takes a body that is on offer
						if here and not h.players[a.id] and h.possessable[a.id] ~= false then
							take(a)
						end
					elseif roll < 0.57 then
						-- the hand-over that should never happen: a player ends up holding a patient
						for _, p in humans do
							local s = h.svc:stateOf(p.id)
							if
								s ~= nil
								and h.possessable[p.id] == false
								and not h.players[p.id]
								and h.world.actorsById[p.id]
								and (p.lift or 0) == 0
							then
								take(p)
								counts.patientsTaken += 1
								break
							end
						end
					elseif roll < 0.7 then
						local id = next(heldAt)
						if id then
							drop(id)
						end
					elseif roll < 0.76 then
						-- a held player walks into the hospital
						local id = next(heldAt)
						if id and h.world.actorsById[id] then
							local b = h.world.actorsById[id]
							b.x, b.z = layout.reception[1], layout.reception[2]
							heldAt[id] = { b.x, b.z, heldAt[id][3] }
						end
					elseif roll < 0.84 then
						-- a body leaves the world (only one the AI has: a held one is the player's)
						if here and not h.players[a.id] then
							gone[a.id] = a
							h.world.actorsById[a.id] = nil
							counts.left += 1
						end
					elseif roll < 0.92 then
						for id, b in gone do
							h.world.actorsById[id] = b
							gone[id] = nil
							break
						end
					else
						for _, v in responders(h) do
							if v.phase == "out" then
								h.traffic:releaseResponder(v)
								counts.calledOff += 1
								break
							end
						end
					end
				end
				local nextMeddle = h.time
				h.step(600, function()
					if h.time >= nextMeddle then
						nextMeddle = h.time + 3
						meddle()
					end
					-- a body a player holds is never moved, hidden or ordered about
					for id, at in heldAt do
						local a = h.world.actorsById[id]
						if a then
							t.eq(a.x, at[1], `seed {seed}: held body {id} was moved ({h.svc:stateOf(id)})`)
							t.eq(a.z, at[2])
							-- (the service acts on its next tick: a patient taken this very step is put
							-- right within half a second)
							if h.time - at[3] > 0.5 then
								t.eq(a.lift, nil, `seed {seed}: held body {id} is hidden`)
								t.eq(h.world.brains[id].directive.mode, nil, `seed {seed}: held body {id} has an order`)
								local case = h.svc:cases()[id]
								t.truthy(
									case == nil or not InfectionRules.isPatient(case),
									`seed {seed}: a player holds a patient in {h.svc:stateOf(id)}`
								)
								t.truthy(
									h.possessable[id] ~= false,
									`seed {seed}: held body {id} is marked not possessable`
								)
							end
						end
					end
				end)
				t.eq(#faults, 0, `seed {seed}: {faults[1]}`)
				-- the meddling stops: every player lets go, every body is back
				for id in table.clone(heldAt) do
					drop(id)
				end
				for id, b in gone do
					h.world.actorsById[id] = b
				end
				table.clear(gone)
				local done = h.runUntil(2500, function(): boolean
					return next(h.svc:cases()) == nil and next(h.svc.leaving) == nil
				end, function()
					for id in h.svc:cases() do
						t.truthy(
							h.world.actorsById[id].infected,
							`seed {seed}: {id} lost the infection outside the hospital`
						)
					end
				end)
				local left = {}
				for id, case in h.svc:cases() do
					table.insert(left, `{h.world.actorsById[id].post} {id}: {case.state}`)
				end
				t.truthy(done, `seed {seed}: still open after {math.floor(h.time)} s: {table.concat(left, "; ")}`)
				t.eq(#faults, 0, `seed {seed}: {faults[1]}`)
				t.eq(h.svc:stats().faults, 0)
				-- the last ambulances drive home (they wait for a gap to turn round in, slow for their
				-- corners and pull in to their bays: a minute is no longer always enough)
				h.step(60)
				h.runUntil(240, function(): boolean
					for _, v in responders(h) do
						if v.phase ~= "idle" then
							return false
						end
					end
					return true
				end)
				clean(h, `chaos seed {seed}`)
				local s = h.svc:stats()
				print(
					`      seed {seed}: {counts.bites} bites ({s.cases} cases, {s.cured} cured), {counts.taken} bodies taken ({counts.patientsTaken} of them patients), {counts.left} bodies gone for a while, {counts.calledOff} ambulances called off, {s.stoodDown} stood down, {s.abandoned} taken in without an ambulance; clean at {math.floor(
						h.time
					)} s`
				)
				t.eq(s.cured, s.cases, `seed {seed}: every case ended in a cure`)
				t.truthy(
					s.cases >= 20 and counts.patientsTaken >= 2 and counts.left >= 5,
					"the chaos was chaotic enough"
				)
			end
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
	-- review round 2 (2026-11-11) ---------------------------------------------------------------------

	-- the rodent, parked beside (x, z) as if a player held it there
	local function parkRodent(h: Harness, x: number, z: number)
		local rodent = h.world.actorsById[h.rodent]
		h.world.possessed[h.rodent] = true
		rodent.x, rodent.z = x, z
		rodent.y = h.world.ctx.groundAt(x, z) + 0.5
		rodent.speed = 0
		h.world.grid:set(h.rodent, x, z)
	end

	t.test(
		"everyone runs when bitten: all 38 people with no lane, indoors without leaving the building, outdoors on clear ground",
		function()
			local h = harness(71, nil, function(params: any)
				params.immediateChance = 0
			end)
			h.step(20)
			local ran: { { a: any, x: number, z: number, len: number } } = {}
			local indoorsN, n = 0, 0
			for _, a in h.world.actors do
				local brain = h.world.brains[a.id] :: any
				if a.species == "human" and brain.kind ~= "Pedestrian" then
					n += 1
					-- the rodent 2 studs away, from a different side each time
					local x0, z0 = a.x, a.z
					parkRodent(h, x0 + math.cos(n * 2.4) * 2, z0 + math.sin(n * 2.4) * 2)
					local own = boxesAt(x0, z0)
					local indoors = Colliders.pointIn(colliders, x0, z0, Height.at(x0, z0) + 3) ~= nil
					t.truthy(h.svc:bite(a.id, h.rodent))
					local d = brain.directive
					t.eq(d.mode, "route", `{a.post} {a.id} at ({x0}, {z0}) was given no run`)
					t.eq(d.speed, InfectionService.FLEE_SPEED, "at a run")
					local len = FootPath.length(x0, z0, d.points)
					t.truthy(
						len >= InfectionService.RUN_MIN - 0.01 and len <= InfectionService.RUN * 1.5 + 0.01,
						`{a.post} {a.id}: a run of {len} studs`
					)
					-- no step of it goes through a wall: indoors it stays in the building, outdoors it
					-- enters none
					local px, pz = x0, z0
					for _, p in d.points do
						for i = 1, 12 do
							local sx, sz = px + (p[1] - px) * i / 12, pz + (p[2] - pz) * i / 12
							local hit = Colliders.pointIn(colliders, sx, sz, Height.at(sx, sz) + 3)
							if indoors then
								t.truthy(hit ~= nil and own[hit.id], `{a.post} {a.id} runs out through the wall`)
							else
								t.truthy(hit == nil, `{a.post} {a.id} runs into {if hit then hit.id else ""}`)
							end
						end
						px, pz = p[1], p[2]
					end
					if indoors then
						indoorsN += 1
					end
					table.insert(ran, { a = a, x = x0, z = z0, len = len })
				end
			end
			t.eq(n, 38, "shop workers, hospital staff, crews, police")
			t.truthy(indoorsN >= 25, `{indoorsN} of them work inside a building (they never ran before)`)
			h.world.possessed[h.rodent] = nil
			h.step(1.5)
			for _, r in ran do
				local moved = math.sqrt((r.a.x - r.x) ^ 2 + (r.a.z - r.z) ^ 2)
				t.truthy(moved >= math.min(r.len, 19) * 0.6, `{r.a.post} {r.a.id} moved {moved} studs in 1.5 s`)
			end
			-- and when the run is over they are back on their rounds, under no order
			h.step(6)
			for _, r in ran do
				t.eq(h.world.brains[r.a.id].directive.mode, nil, `{r.a.post} {r.a.id} still under an order`)
			end
		end
	)

	t.test(
		"a paramedic bitten at the scene: the patient still gets to the ambulance on foot and is loaded beside it; the paramedic runs, then walks back to the bay round the buildings",
		function()
			local h = harness(72, nil, function(params: any)
				params.immediateChance = 1
				params.incubateSecs = { 420, 420 } -- (the paramedic's own symptoms wait until they are home)
			end)
			h.svc.tun.crowdChance = 0
			h.step(20)
			local victim = nearest(townspeople(h), -700, 300)
			local id = victim.id
			t.truthy(h.svc:bite(id, h.rodent))
			local rec = h.svc.records[id]
			t.truthy(
				h.runUntil(240, function(): boolean
					return h.svc:stateOf(id) == "assess"
				end),
				`the crew never reached the patient (state {h.svc:stateOf(id)})`
			)
			local crew = rec.crew
			t.truthy(crew ~= nil and rec.crewSecs > 0, "a crew member walked over (or the test has no teeth)")
			local medic = h.world.actorsById[crew]
			local station = h.world.brains[crew].points[1]
			local stage = rec.stage
			-- the rodent is still there, and bites the paramedic
			h.svc.params.immediateChance = 0
			parkRodent(h, medic.x + 2, medic.z)
			t.truthy(h.svc:bite(crew, h.rodent), "the paramedic is a new case")
			h.world.possessed[h.rodent] = nil
			t.eq(rec.crew, nil, "no longer this patient's crew")
			t.eq(h.svc.busy[crew], nil)
			local medicBrain = h.world.brains[crew] :: any
			t.eq(medicBrain.directive.mode, "route", "the paramedic runs")
			t.eq(medicBrain.directive.speed, InfectionService.FLEE_SPEED)
			t.eq(medicBrain.directive.after, "stand", "and is not handed back to a brain that walks straight home")
			-- the patient: up and walking to the ambulance by the way the crew came, loaded beside it
			local lastX, lastZ = victim.x, victim.z
			local stood, walkedAlone = 0, false
			t.truthy(
				h.runUntil(120, function(): boolean
					return h.svc:stateOf(id) == "transit"
				end, function()
					local s = h.svc:stateOf(id)
					if s == "retrieve" then
						walkedAlone = true
						t.eq(h.world.brains[id].directive.mode, "route", "the patient has a way to walk")
						if math.abs(victim.x - lastX) + math.abs(victim.z - lastZ) < 0.05 then
							stood += DT
						end
					end
					if s ~= "transit" then
						lastX, lastZ = victim.x, victim.z
					end
					outdoors(medic, "the bitten paramedic")
				end),
				`the patient was never loaded (state {h.svc:stateOf(id)})`
			)
			t.truthy(walkedAlone, "the patient walked to the ambulance")
			t.truthy(table.find(h.medLog[id], "carried") ~= nil)
			local gap = math.sqrt((lastX - stage.x) ^ 2 + (lastZ - stage.z) ^ 2)
			t.truthy(gap < 12, `the patient went out of sight {gap} studs from the ambulance`)
			t.truthy(stood < rec.crewSecs * 0.5 + 1.5, `the patient stood on the spot for {stood} s of the walk`)
			-- the paramedic: back to the bay on foot by a real way, never through a house
			local walking = false
			local bittenAt = h.time
			local sceneGap = math.sqrt((medic.x - station[1]) ^ 2 + (medic.z - station[2]) ^ 2)
			t.truthy(
				h.runUntil(400, function(): boolean
					return walking and medicBrain.directive.mode == nil
				end, function()
					outdoors(medic, "the bitten paramedic")
					if
						medicBrain.directive.mode == "route"
						and medicBrain.directive.speed == h.svc.tun.dischargeSpeed
					then
						walking = true
					end
				end),
				`the paramedic never got back (order {medicBrain.directive.mode}, at {medic.x}, {medic.z})`
			)
			t.truthy(
				math.sqrt((medic.x - station[1]) ^ 2 + (medic.z - station[2]) ^ 2) < 8,
				`the paramedic is at ({medic.x}, {medic.z}), the bay at ({station[1]}, {station[2]})`
			)
			t.eq(h.svc:stateOf(crew), "incubating", "home before the symptoms")
			print(
				`      the bitten paramedic was back at the bay after {math.floor(h.time - bittenAt)} s, from {math.floor(
					sceneGap
				)} studs away, through no building`
			)
			-- everything runs out: both are cured in the hospital, nothing is left behind
			t.truthy(h.runUntil(1500, function(): boolean
				return next(h.svc:cases()) == nil and next(h.svc.leaving) == nil
			end))
			t.eq(h.svc:stats().cured, 2)
			h.step(30)
			clean(h, "after the bitten paramedic")
		end
	)

	t.test(
		"a bitten officer taken by a player a moment later: the run does not wait in the brain for the player to let go",
		function()
			local h = harness(73, nil, function(params: any)
				params.immediateChance = 0
			end)
			h.step(20)
			local officer = nil
			for _, a in h.world.actors do
				if a.post == "police" and (h.world.brains[a.id] :: any).kind == "Officer" and officer == nil then
					officer = a
				end
			end
			local id = officer.id
			local brain = h.world.brains[id] :: any
			parkRodent(h, officer.x + 2, officer.z)
			t.truthy(h.svc:bite(id, h.rodent))
			h.world.possessed[h.rodent] = nil
			t.eq(brain.directive.mode, "route", "the bitten officer runs")
			h.step(0.4)
			-- a Police pick takes this body (it is possessable while it incubates)
			t.truthy(h.possessable[id] ~= false)
			h.players[id] = true
			TownAI.suspend(h.world, id)
			h.step(0.6)
			t.eq(brain.directive.mode, nil, "a held body is under no order")
			h.step(30)
			-- the player drives across town and lets go there
			local gx, gz = 600, 0
			TownAI.resume(h.world, id, gx, h.world.ctx.groundAt(gx, gz) + officer.hip, gz)
			h.players[id] = nil
			local worst = 0
			h.step(10, function()
				worst = math.max(worst, officer.speed)
			end)
			t.truthy(worst < 8, `the body ran off at {worst} studs/s when the player let go`)
			t.eq(brain.directive.mode, nil)
		end
	)

	t.test(
		"the crowd sees the rodent: a bystander it bites runs, the others run when it comes near, and nobody gathers round it",
		function()
			local h = harness(11, { 0, 0 })
			h.svc.tun.crowdChance = 1
			h.step(20)
			local victim = nearest(townspeople(h), 0, 0)
			t.truthy(h.svc:bite(victim.id, h.rodent))
			t.truthy(h.runUntil(5, function(): boolean
				return h.svc:stateOf(victim.id) == "down"
			end))
			local scene = h.svc.scenes[victim.id]
			local crowd = table.clone(scene.bystanders)
			t.truthy(#crowd >= 2, `a crowd of {#crowd} (the test needs one)`)
			-- they walk over and stand looking at the patient
			h.runUntil(40, function(): boolean
				for _, b in crowd do
					if not (h.world.brains[b.id] :: any).directive.done then
						return false
					end
				end
				return true
			end)
			-- the rodent bites one of them where they stand, off their lane
			h.svc.params.immediateChance = 0
			local first = h.world.actorsById[crowd[1].id]
			local fx, fz = first.x, first.z
			parkRodent(h, fx + 2, fz)
			t.truthy(h.svc:bite(first.id, h.rodent))
			t.eq(h.svc.busy[first.id], nil, "bitten: out of the crowd")
			-- the others are within sight of it: they leave too, at a run
			local others: { { a: any, x: number, z: number } } = {}
			for i = 2, #crowd do
				local o = h.world.actorsById[crowd[i].id]
				table.insert(others, { a = o, x = o.x, z = o.z })
			end
			h.step(0.4)
			t.eq(#scene.bystanders, 0, "nobody stands in a ring round the rodent")
			for _, o in others do
				t.eq(h.svc.busy[o.a.id], nil)
			end
			h.step(2.6)
			local ran = math.sqrt((first.x - fx) ^ 2 + (first.z - fz) ^ 2)
			t.truthy(ran > 25, `the bitten bystander moved {ran} studs in 3 s (a stroll back to the pavement is 9)`)
			for _, o in others do
				local moved = math.sqrt((o.a.x - o.x) ^ 2 + (o.a.z - o.z) ^ 2)
				t.truthy(moved > 20, `a bystander beside the rodent moved {moved} studs in 3 s`)
				outdoors(o.a, "a fleeing bystander")
			end
			-- a collapse with the rodent sitting on it draws no crowd at all
			h.world.possessed[h.rodent] = nil
			h.svc.params.immediateChance = 1
			local second = nearest(townspeople(h), 300, 300)
			t.truthy(h.svc:biteable(second.id) and h.svc:bite(second.id, h.rodent))
			t.truthy(h.runUntil(6, function(): boolean
				return h.svc:stateOf(second.id) == "down"
			end, function()
				parkRodent(h, second.x + 3, second.z)
			end))
			t.eq(#h.svc.scenes[second.id].bystanders, 0, "nobody walks over to stand beside the rodent")
			-- everything runs out and nobody is left under an order
			h.world.possessed[h.rodent] = nil
			t.truthy(h.runUntil(1800, function(): boolean
				return next(h.svc:cases()) == nil and next(h.svc.leaving) == nil
			end))
			h.step(30)
			clean(h, "after the scared crowd")
		end
	)
	t.test("a cyclist or motorcyclist is never a patient: bitten, they shout and ride off", function()
		local h = harness(75, { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 })
		h.step(20)
		local riders = 0
		for _, a in h.world.actors do
			if a.species == "human" and a.post == "rider" then
				riders += 1
				local brain = h.world.brains[a.id] :: any
				parkRodent(h, a.x + 2, a.z)
				t.truthy(h.svc:biteable(a.id))
				t.eq(h.svc:bite(a.id, h.rodent), false, "no new infection")
				t.eq(h.svc:stateOf(a.id), nil, "no case")
				t.truthy(not a.infected and not h.svc:isInfected(a.id))
				t.eq(brain.state, "flee", "they ride off")
				t.truthy(table.find(Lines.GROUPS.bitten, (h.attrs[a.id] or {}).Say) ~= nil, "shouting")
				t.truthy(h.svc:biteable(a.id), "and can be bitten again")
				h.step(1.2)
			end
		end
		t.eq(riders, 8)
		t.eq(h.svc:stats().bites, 8, "every bite is counted")
		-- (the people who saw it run; none of that opens a case)
		t.eq(h.svc:stats().cases, 0)
		h.world.possessed[h.rodent] = nil
		h.step(30)
		for _, a in h.world.actors do
			if a.species == "human" then
				t.eq((h.attrs[a.id] or {}).Med, nil, `{a.post} {a.id} shows Med`)
			end
		end
		t.eq(h.svc:townPercent(), 0)
	end)

	t.test(
		"the patient goes out of sight beside the ambulance first; it pulls away a moment later, and never stays held",
		function()
			local h = harness(11, { 0, 0 })
			h.svc.tun.crowdChance = 0
			h.step(20)
			local victim = nearest(townspeople(h), 0, 0)
			local id = victim.id
			t.truthy(h.svc:bite(id, h.rodent))
			t.truthy(h.runUntil(300, function(): boolean
				return h.svc:stateOf(id) == "transit"
			end))
			local rec = h.svc.records[id]
			local v = rec.vehicle
			t.eq(victim.lift, InfectionService.SINK, "the patient is out of sight")
			t.eq(v.phase, "hold", "and the ambulance is still standing there")
			local x, z, yaw = v.x, v.z, v.yaw
			h.step(InfectionService.LOAD_LINGER - 0.4)
			t.eq(v.phase, "hold")
			t.truthy(v.x == x and v.z == z and v.yaw == yaw, "it has not moved")
			h.step(0.8)
			t.eq(v.phase, "turn", "then it turns for home (a U-turn it drives, AICarMotor)")
			-- a case that ends in that moment still lets the ambulance go (it was held for ever otherwise)
			local h2 = harness(11, { 0, 0 })
			h2.svc.tun.crowdChance = 0
			h2.step(20)
			local victim2 = nearest(townspeople(h2), 0, 0)
			t.truthy(h2.svc:bite(victim2.id, h2.rodent))
			t.truthy(h2.runUntil(300, function(): boolean
				return h2.svc:stateOf(victim2.id) == "transit"
			end))
			local v2 = h2.svc.records[victim2.id].vehicle
			t.eq(v2.phase, "hold")
			h2.svc:shutdown()
			t.truthy(
				h2.runUntil(200, function(): boolean
					return v2.phase == "idle"
				end),
				`the ambulance is still {v2.phase} after the switch-off`
			)
			t.truthy(not v2.held)
		end
	)

	t.test("news about a victim goes to the player who bit them, not to whoever plays the rodent later", function()
		local h = harness(11, { 0, 0 })
		h.svc.tun.crowdChance = 0
		h.step(20)
		local victim = nearest(townspeople(h), 0, 0)
		local function news(): number
			local n = 0
			for _, toast in h.toasts do
				if toast.id == h.rodent then
					n += 1
				end
			end
			return n
		end
		-- player A plays the rodent and bites; the collapse is A's news
		h.drivers[h.rodent] = "player A"
		t.truthy(h.svc:bite(victim.id, h.rodent, "player A"))
		t.truthy(h.runUntil(5, function(): boolean
			return h.svc:stateOf(victim.id) == "down"
		end))
		t.eq(news(), 1)
		t.eq(h.toasts[#h.toasts].key, "victimDown")
		-- A is knocked out; B picks the Spicy Rodent (the same body) and bites someone else
		h.drivers[h.rodent] = "player B"
		h.svc.params.immediateChance = 1
		local other = nearest(townspeople(h), 300, 300)
		t.truthy(h.svc:bite(other.id, h.rodent, "player B"))
		t.truthy(h.runUntil(1500, function(): boolean
			return next(h.svc:cases()) == nil
		end))
		t.eq(h.svc:stats().cured, 2)
		local keys = {}
		for _, toast in h.toasts do
			if toast.id == h.rodent then
				table.insert(keys, toast.key)
			end
		end
		-- A's: the collapse. B's: their own victim's collapse and cure. Not A's victim's cure.
		t.deepEq(keys, { "victimDown", "victimDown", "victimCured" })
		-- a second bite by the new player makes the victim theirs
		local h2 = harness(12, { 0.99, 0.99 })
		h2.step(10)
		local v2 = nearest(townspeople(h2), 0, 0)
		h2.drivers[h2.rodent] = "player B"
		t.truthy(h2.svc:bite(v2.id, h2.rodent, "player A"))
		h2.step(3)
		t.eq(h2.svc:bite(v2.id, h2.rodent, "player B"), false)
		t.eq(h2.svc.records[v2.id].by, "player B")
		-- with nobody named (a caller that does not say who bit) the news goes to the body, as before
		local h3 = harness(11, { 0, 0 })
		h3.step(20)
		local v3 = nearest(townspeople(h3), 0, 0)
		h3.drivers[h3.rodent] = "player C"
		t.truthy(h3.svc:bite(v3.id, h3.rodent))
		t.truthy(h3.runUntil(5, function(): boolean
			return h3.svc:stateOf(v3.id) == "down"
		end))
		t.eq(h3.toasts[#h3.toasts].key, "victimDown")
	end)

	t.test(
		"a collapse in the road: a runner reaches the kerb first; one who cannot is not parked on by the ambulance",
		function()
			-- (a) bitten on a crossing with the collapse due at once: they are off the asphalt when they fall
			local h = harness(76, nil, function(params: any)
				params.immediateChance = 1
				params.collapseAfterSecs = { 0.2, 0.2 }
			end)
			h.svc.tun.crowdChance = 0
			h.step(20)
			local roads = h.svc.roads
			-- the main street's own pavements are not road (the merged centreline is as wide as the
			-- commercial boulevard further east: by it, they were)
			t.truthy(not MedicalRoute.onRoad(roads, 110, -30.25, 2), "the pavement along the main street")
			t.truthy(MedicalRoute.onRoad(roads, 110, -20), "its asphalt")
			t.truthy(MedicalRoute.onRoad(roads, 1000, -30.25), "the boulevard is wider")
			-- someone walking a lane that crosses the north-south street at x = 0 (22.5 studs each side)
			local walker = nil
			for _, a in townspeople(h) do
				local lane = (h.world.brains[a.id] :: any).lane
				if lane.axis == "x" and math.abs(lane.fixed) > 100 and math.abs(lane.fixed) < 600 and walker == nil then
					walker = a
				end
			end
			t.truthy(walker ~= nil)
			local lane = (h.world.brains[walker.id] :: any).lane
			walker.x, walker.z = 3, lane.fixed
			t.truthy(MedicalRoute.onRoad(roads, walker.x, walker.z), "standing in the road")
			parkRodent(h, walker.x - 2, walker.z)
			t.truthy(h.svc:bite(walker.id, h.rodent))
			h.world.possessed[h.rodent] = nil
			local held = 0
			t.truthy(h.runUntil(10, function(): boolean
				return h.svc:stateOf(walker.id) == "down"
			end, function()
				if h.svc:stateOf(walker.id) == "bitten" then
					held += DT
				end
			end))
			t.truthy(
				not MedicalRoute.onRoad(roads, walker.x, walker.z, InfectionService.ROAD_PAD),
				`they sat down in the road at ({walker.x}, {walker.z})`
			)
			t.truthy(held > 0.3 and held < 4, `the fall waited {held} s for the kerb`)
			-- (b) someone who cannot get off it (no hold: they fall where they stand, in the ambulance's lane)
			local h2 = harness(77, nil, function(params: any)
				params.immediateChance = 1
				params.collapseAfterSecs = { 0.2, 0.2 }
				params.roadHoldSecs = 0
			end)
			h2.svc.tun.crowdChance = 0
			h2.step(20)
			local victim = nil
			for _, a in townspeople(h2) do
				local l = (h2.world.brains[a.id] :: any).lane
				if l.axis == "x" and math.abs(l.fixed) > 100 and math.abs(l.fixed) < 600 and victim == nil then
					victim = a
				end
			end
			local brain = h2.world.brains[victim.id] :: any
			victim.x, victim.z = 7.5, brain.lane.fixed
			t.truthy(h2.svc:bite(victim.id, h2.rodent))
			t.truthy(h2.runUntil(5, function(): boolean
				return h2.svc:stateOf(victim.id) == "down"
			end))
			local px, pz = victim.x, victim.z
			t.truthy(MedicalRoute.onRoad(h2.svc.roads, px, pz), "the patient is on the asphalt")
			local rec = h2.svc.records[victim.id]
			t.truthy(rec.stage.dist < 12, "in the ambulance's lane")
			local closest = math.huge
			t.truthy(
				h2.runUntil(300, function(): boolean
					return h2.svc:stateOf(victim.id) == "transit"
				end, function()
					local v = rec.vehicle
					if v and v.visible then
						-- the vehicle's box against the patient: along and across its heading
						local fx, fz = math.sin(v.yaw), math.cos(v.yaw)
						local dx, dz = px - v.x, pz - v.z
						local along, across = math.abs(dx * fx + dz * fz), math.abs(dx * fz - dz * fx)
						local gap = math.max(along - v.box.length / 2, across - v.box.width / 2)
						closest = math.min(closest, gap)
					end
				end),
				`never loaded (state {h2.svc:stateOf(victim.id)})`
			)
			t.truthy(closest > 2, `the ambulance came within {closest} studs of the patient (under 0: on them)`)
			t.truthy(rec.stop ~= nil, "the stop is on record")
			local short = math.sqrt((rec.stop[1] - px) ^ 2 + (rec.stop[2] - pz) ^ 2)
			t.truthy(short >= InfectionService.STOP_CLEAR - 0.01 and short < 40, `it stopped {short} studs from them`)
			t.truthy(rec.crewSecs > 0, "the crew walked the last steps")
			print(
				`      a patient in the road: the ambulance stopped {math.floor(short)} studs short, never nearer than {math.floor(
					closest
				)} studs`
			)
			t.truthy(h2.runUntil(1200, function(): boolean
				return next(h2.svc:cases()) == nil and next(h2.svc.leaving) == nil
			end))
			h2.step(30)
			clean(h2, "after the patient in the road")
		end
	)
end
