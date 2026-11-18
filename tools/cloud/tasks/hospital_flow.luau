--!strict
-- Luau Execution task: the bite-to-hospital flow on a server with no clients, as plain results
-- (review of 2026-11-11). Boots the whole game (Server/Boot/Game; no players, frames stepped by hand),
-- forces bites through the infection service and reports what happened to each case:
--   collapse  a townsperson bitten with the dice set to "collapse at once": a line is sent (Say and
--             SayAt on the body), the ambulance is called and one is dispatched (a responder leaves
--             the bay), it stops clear of the patient, the patient is loaded and the ambulance pulls
--             away only after that, the case reaches a bed in the hospital and is cured there.
--   walkIn    a townsperson bitten with the dice set to "symptoms later, then walk": nothing shows
--             while it incubates, then Med "symptomatic", the walk to the door at a walking pace, a
--             bed, the cure in the hospital.
--   review    what the review changed and only a running server can show: a nurse bitten inside the
--             hospital runs without leaving it, a cyclist is never a patient, a person a (stub)
--             player holds on the hospital drive does not hold the ambulance at the bay, and the
--             door is published for the client's marker (Workspace attribute HospitalDoor).
-- Nothing here needs a client: the poses, the red eyes, the stagger, the bubbles and the marker are
-- drawn by clients and are checked by eye in a Play session.
-- NOT YET RUN: the session that wrote it (2026-11-11) had the cloud tools off limits.
-- Sent by: node tools/cloud/cloud.mjs run_engine_tests tools/cloud/tasks/hospital_flow.luau --version <v> --place ci
-- The run steps about 15 minutes of game time (0.1 s frames).

local ServerScriptService = game:GetService("ServerScriptService")

local server = ServerScriptService:WaitForChild("Server")
local Game = (require :: any)(server:WaitForChild("Boot"):WaitForChild("Game"))
local Possession = (require :: any)(server:WaitForChild("Actors"):WaitForChild("Possession"))

local STEP = 0.1 -- seconds per hand-stepped frame
local started = os.clock()
local failures: { string } = {}
local results: { [string]: { [string]: any } } = { collapse = {}, walkIn = {}, review = {} }

local function check(cond: boolean, msg: string): boolean
	if not cond then
		table.insert(failures, msg)
	end
	return cond
end

local engine = Possession.engine()
engine.streamAround = function() end
engine.setOwner = function(_root: any, _player: any?) end
engine.setCharacter = function(player: any, model: any?)
	player.Character = model
end

local G = Game.start({ players = false, engine = engine, heartbeat = false })
local rt = G.runtime
local world = rt.world
local infection = G.infection
if infection == nil or infection.layout == nil then
	G.stop()
	return {
		suite = "hospital_flow",
		ok = false,
		failures = { "the infection service (or the hospital layout) did not start" },
		results = results,
		placeVersion = game.PlaceVersion,
		elapsedSeconds = os.clock() - started,
	}
end
local layout = infection.layout

local clock = 0
-- (yield now and then: the engine stops a script that runs too long without one)
local lastYield = os.clock()
local function step(secs: number, each: (() -> ())?)
	for _ = 1, math.max(1, math.floor(secs / STEP + 0.5)) do
		G.step(STEP)
		clock += STEP
		if os.clock() - lastYield > 1 then
			task.wait()
			lastYield = os.clock()
		end
		if each then
			each()
		end
	end
end
-- step until done() or the limit; returns whether it happened and the seconds it took
local function waitFor(limit: number, done: () -> boolean, each: (() -> ())?): (boolean, number)
	local t0 = clock
	while clock - t0 < limit do
		if done() then
			return true, clock - t0
		end
		step(STEP, each)
	end
	return done(), clock - t0
end
local function inHospital(a: any, pad: number): boolean
	return math.abs(a.x - layout.lot.x) <= layout.lot.hw + pad and math.abs(a.z - layout.lot.z) <= layout.lot.hd + pad
end
local function bodyOf(townId: number): Model
	return rt.byTownId[townId].body :: Model
end
local function med(townId: number): any
	return bodyOf(townId):GetAttribute("Med")
end
local function responders(): { any }
	local out = {}
	for _, v in G.traffic.vehicles do
		if v.class == "responder" then
			table.insert(out, v)
		end
	end
	return out
end
local function freeTownspeople(): { any }
	local out = {}
	for _, a in world.actors do
		if
			a.species == "human"
			and a.post == "townsperson"
			and infection:stateOf(a.id) == nil
			and infection.busy[a.id] == nil
			and infection.leaving[a.id] == nil
			and rt.byTownId[a.id].possessable ~= false
			and rt.possession:controllerOf(rt.byTownId[a.id]) == "ai"
		then
			table.insert(out, a)
		end
	end
	return out
end

local rodentId: number? = nil
for _, a in world.actors do
	if a.variant == "spicy" then
		rodentId = a.id
	end
end
check(rodentId ~= nil, "the town has no Spicy Rodent")

step(10) -- the town settles onto its lanes

-- review: the door is published for the client's marker ------------------------------------------
do
	local door = workspace:GetAttribute("HospitalDoor")
	local okDoor = typeof(door) == "Vector3"
		and math.abs((door :: Vector3).X - layout.entrance[1]) < 1
		and math.abs((door :: Vector3).Z - layout.entrance[2]) < 1
	results.review.doorPublished = okDoor
	check(okDoor, `Workspace.HospitalDoor is {tostring(door)}`)
end

-- review: a player-held person standing on the hospital drive, in front of the ambulance bay --------
local blocker: { [string]: any } = { UserId = 7201, Name = "OnTheDrive", Character = nil, attrs = {}, events = {} }
do
	local okPick, whyPick = G.pick(blocker, "townsperson")
	check(okPick, `pick townsperson for the drive: {whyPick}`)
	local held = rt.possession:actorOf(blocker)
	local home = G.traffic:responderHome()
	if held and home then
		-- in the responders' own lane, a few studs ahead of where they start
		local x, z = home[1] + 6, home[2] - 6.5
		local body = held.body :: Model
		body:PivotTo(CFrame.new(x, G.traffic.heightAt(x, z) + 3.5, z))
		results.review.blockerAt = { x, z }
	else
		table.insert(failures, "no body to stand on the hospital drive")
	end
	step(1)
end

-- 1. collapse at once -------------------------------------------------------------------------------
infection.params.immediateChance = 1
infection.tun.crowdChance = 1
do
	local r = results.collapse
	-- a townsperson in the middle of town
	local victim, bestD = nil, math.huge
	for _, a in freeTownspeople() do
		local d = a.x * a.x + a.z * a.z
		if d < bestD then
			victim, bestD = a, d
		end
	end
	if victim == nil then
		table.insert(failures, "no townsperson to bite")
	else
		local id = victim.id
		local body = bodyOf(id)
		local linesBefore = infection:stats().lines
		local dispatchedBefore = infection:stats().dispatched
		r.bitten = infection:bite(id, rodentId)
		check(r.bitten == true, "the forced bite opened no case")
		-- a speech line is sent
		r.say = body:GetAttribute("Say")
		r.sayAt = body:GetAttribute("SayAt")
		r.lineSent = type(r.say) == "string" and type(r.sayAt) == "number" and infection:stats().lines > linesBefore
		check(r.lineSent, `no line was sent at the bite (Say {tostring(r.say)}, SayAt {tostring(r.sayAt)})`)
		check(med(id) == nil, `Med shows before the collapse: {tostring(med(id))}`)
		-- down, and not in the road
		local down, downSecs = waitFor(12, function(): boolean
			return med(id) == "down"
		end)
		r.downAfter = downSecs
		check(down, `never collapsed (state {infection:stateOf(id)})`)
		local scene = infection.scenes[id]
		r.bystanders = if scene then #scene.bystanders else -1
		-- the call goes out and an ambulance is dispatched
		local called, callSecs = waitFor(15, function(): boolean
			local s = infection:stateOf(id)
			return s == "scene" or s == "enroute"
		end)
		r.calledAfter = callSecs
		check(called, `the ambulance was never called (state {infection:stateOf(id)})`)
		local out, outSecs = waitFor(20, function(): boolean
			for _, v in responders() do
				if v.phase == "out" and v.visible then
					return true
				end
			end
			return false
		end)
		r.dispatchedAfterCall = outSecs
		r.ambulanceDispatched = out and infection:stats().dispatched > dispatchedBefore
		check(r.ambulanceDispatched, "an ambulance was called and none was dispatched")
		-- the person on the drive does not hold it at the bay: it is on scene well within the
		-- timeout, and never on top of the patient
		local rec = infection.records[id]
		local closest = math.huge
		local arrived, arriveSecs = waitFor(140, function(): boolean
			local v = rec and rec.vehicle
			return v ~= nil and v.phase == "hold"
		end, function()
			local v = rec and rec.vehicle
			if v and v.visible then
				local fx, fz = math.sin(v.yaw), math.cos(v.yaw)
				local dx, dz = victim.x - v.x, victim.z - v.z
				local along, across = math.abs(dx * fx + dz * fz), math.abs(dx * fz - dz * fx)
				closest = math.min(closest, math.max(along - v.box.length / 2, across - v.box.width / 2))
			end
		end)
		r.arrivedAfter = arriveSecs
		r.closestToPatient = closest
		results.review.ambulancePassedTheBlocker = arrived
		check(arrived, `the ambulance did not reach the scene in {arriveSecs} s (a person stood on the drive)`)
		check(closest > 1, `the ambulance came within {closest} studs of the patient`)
		-- loaded: out of sight first, the ambulance still standing there; then it pulls away
		local loaded, loadSecs = waitFor(200, function(): boolean
			return med(id) == "transit"
		end)
		r.loadedAfter = loadSecs
		check(loaded, `never loaded (state {infection:stateOf(id)}, Med {tostring(med(id))})`)
		local v = rec and rec.vehicle
		r.ambulanceWaitedForTheLoad = v ~= nil and v.phase == "hold"
		check(r.ambulanceWaitedForTheLoad == true, "the ambulance left in the same step as its patient vanished")
		step(0.3)
		local root = body.PrimaryPart :: BasePart
		r.transitDepth = G.traffic.heightAt(victim.x, victim.z) - root.Position.Y
		check(r.transitDepth > 15, `a patient in transit is drawn in sight ({r.transitDepth} studs under)`)
		-- the hospital: a bed, the treatment, the cure
		local bedded, bedSecs = waitFor(260, function(): boolean
			return med(id) == "treated"
		end)
		r.bedAfter = bedSecs
		r.reachedHospital = bedded and inHospital(victim, 0)
		check(r.reachedHospital, `never in a hospital bed (state {infection:stateOf(id)}, at {victim.x}, {victim.z})`)
		check(victim.infected == true, "cured before the treatment")
		local cured, cureSecs = waitFor(45, function(): boolean
			return infection:stateOf(id) == nil
		end)
		r.curedAfter = cureSecs
		r.cured = cured and not victim.infected and not infection:isInfected(id)
		r.curedInHospital = inHospital(victim, 0)
		check(r.cured, `never cured (state {infection:stateOf(id)})`)
		check(r.curedInHospital, "cured outside the hospital")
		check(med(id) == nil, `Med still shows after the cure: {tostring(med(id))}`)
		-- every responder gets home (none is left held at a scene or at the bay)
		local home, homeSecs = waitFor(200, function(): boolean
			for _, veh in responders() do
				if veh.phase ~= "idle" then
					return false
				end
			end
			return true
		end)
		r.ambulancesHomeAfter = homeSecs
		check(home, "an ambulance never came home")
	end
end

-- the person on the drive walks off (the body goes back to the AI)
rt.possession:release(blocker, "test")
G.stateOf(blocker).role = nil

-- 2. symptoms later, then a walk in -----------------------------------------------------------------
infection.params.immediateChance = 0
infection.params.incubateSecs = { 6, 8 }
infection.params.symptomSecs = { 2, 3 }
infection.params.walkInChance = 1
do
	local r = results.walkIn
	-- the townsperson with the shortest way to the door
	local walker, bestLen = nil, math.huge
	for _, a in freeTownspeople() do
		local route, len = infection:walkRoute(a.x, a.z)
		if route and len < bestLen and not inHospital(a, 60) then
			walker, bestLen = a, len
		end
	end
	if walker == nil then
		table.insert(failures, "no townsperson with a way to the hospital on foot")
	else
		local id = walker.id
		r.routeLen = bestLen
		r.bitten = infection:bite(id, rodentId)
		check(r.bitten == true, "the forced bite opened no case (walk in)")
		r.lineSent = type(bodyOf(id):GetAttribute("Say")) == "string"
		check(r.lineSent, "no line at the bite (walk in)")
		step(3)
		check(med(id) == nil, `Med shows while the infection incubates: {tostring(med(id))}`)
		check(rt.byTownId[id].possessable ~= false, "an incubating person cannot be picked")
		local sick, sickSecs = waitFor(15, function(): boolean
			return med(id) == "symptomatic"
		end)
		r.symptomsAfter = sickSecs + 3
		check(sick, `the symptoms never showed (state {infection:stateOf(id)})`)
		local walking = waitFor(8, function(): boolean
			return infection:stateOf(id) == "walkin"
		end)
		r.walkedIn = walking
		check(walking, `did not start the walk in (state {infection:stateOf(id)})`)
		-- the pace: a brisk stagger at a walk, never a run
		local x0, z0, t0 = walker.x, walker.z, clock
		local walked, top = 0, 0
		local arrived, walkSecs = waitFor(bestLen / 4 + 90, function(): boolean
			local s = infection:stateOf(id)
			return s ~= "walkin"
		end, function()
			local d = math.sqrt((walker.x - x0) ^ 2 + (walker.z - z0) ^ 2)
			walked += d
			top = math.max(top, d / STEP)
			x0, z0 = walker.x, walker.z
		end)
		r.walkSecs = walkSecs
		r.walkedStuds = walked
		r.meanPace = if clock > t0 then walked / (clock - t0) else 0
		r.topPace = top
		check(arrived, `still walking in after {walkSecs} s`)
		check(top < 12, `the walk in peaked at {top} studs/s (a run)`)
		local s = infection:stateOf(id)
		check(s == "admitted" or s == "treated", `the walk in ended in {tostring(s)}, not at the door`)
		local bedded, bedSecs = waitFor(120, function(): boolean
			return med(id) == "treated"
		end)
		r.bedAfter = bedSecs
		r.reachedHospital = bedded and inHospital(walker, 0)
		check(r.reachedHospital, `the walk-in never sat in a bed (state {infection:stateOf(id)})`)
		local cured, cureSecs = waitFor(45, function(): boolean
			return infection:stateOf(id) == nil
		end)
		r.curedAfter = cureSecs
		r.cured = cured and not walker.infected
		r.curedInHospital = inHospital(walker, 0)
		check(
			r.cured and r.curedInHospital,
			`the walk-in was not cured in the hospital (state {infection:stateOf(id)})`
		)
	end
end

-- review: a nurse bitten inside the hospital runs, and stays inside ----------------------------------
do
	local nurse = nil
	for _, a in world.actors do
		if a.species == "human" and a.post == "hospital_staff" and infection:stateOf(a.id) == nil and nurse == nil then
			nurse = a
		end
	end
	if nurse == nil then
		table.insert(failures, "no hospital staff to bite")
	else
		local brain = world.brains[nurse.id] :: any
		local x0, z0 = nurse.x, nurse.z
		infection.params.incubateSecs = { 40, 60 }
		check(infection:bite(nurse.id, rodentId) == true, "the bite on the nurse opened no case")
		local d = brain.directive
		results.review.nurseRuns = d ~= nil and d.mode == "route"
		check(results.review.nurseRuns == true, "a nurse bitten in the hospital was given no run")
		-- (the run is 8 to 30 studs; when it is over she walks back to her round)
		local inside, furthest = true, 0
		step(2.5, function()
			inside = inside and inHospital(nurse, 0)
			furthest = math.max(furthest, math.sqrt((nurse.x - x0) ^ 2 + (nurse.z - z0) ^ 2))
		end)
		results.review.nurseRan = furthest
		results.review.nurseStayedInside = inside
		check(furthest > 6, `the bitten nurse got {furthest} studs away in 2.5 s`)
		check(inside, "the bitten nurse ran out through the hospital wall")
	end
end

-- review: a cyclist is never a patient -------------------------------------------------------------
do
	local rider = nil
	for _, a in world.actors do
		if a.species == "human" and a.post == "rider" and rider == nil then
			rider = a
		end
	end
	if rider then
		local opened = infection:bite(rider.id, rodentId)
		results.review.riderInfected = opened == true or infection:stateOf(rider.id) ~= nil
		check(not results.review.riderInfected, "a rider became a patient")
		check(type(bodyOf(rider.id):GetAttribute("Say")) == "string", "the bitten rider said nothing")
	end
end

-- everything runs out: nothing is left behind -----------------------------------------------------
infection.params.incubateSecs = { 6, 8 }
do
	local drained, drainSecs = waitFor(900, function(): boolean
		return next(infection:cases()) == nil and next(infection.leaving) == nil
	end)
	results.review.drainedAfter = drainSecs
	check(drained, "a case is still open 15 minutes after the last bite")
	step(5)
	local orders, sunk = 0, 0
	for _, a in world.actors do
		if a.species == "human" then
			local brain = world.brains[a.id] :: any
			if brain and brain.directive and brain.directive.mode ~= nil then
				orders += 1
			end
			if (a.lift or 0) ~= 0 then
				sunk += 1
			end
		end
	end
	check(orders == 0, `{orders} people still under orders`)
	check(sunk == 0, `{sunk} people still sunk`)
	for _, v in responders() do
		check(v.phase == "idle" and not v.held, `{v.name} is {v.phase}`)
	end
end

local stats = infection:stats()
check(stats.faults == 0, `{stats.faults} contained faults`)
check(stats.cured == stats.cases, `{stats.cases} cases, {stats.cured} cured`)
local okLedger, ledgerErrors = rt.possession:check()
check(okLedger, `possession ledger: {table.concat(ledgerErrors, "; ")}`)
G.stop()

print(`hospital_flow: ok={#failures == 0} failures={#failures}`)
for _, f in failures do
	print("  FAIL " .. f)
end
return {
	suite = "hospital_flow",
	ok = #failures == 0,
	failures = failures,
	-- the three questions, at a glance
	reachedHospitalAndCured = results.collapse.cured == true and results.walkIn.cured == true,
	ambulanceDispatchedWhenCalled = results.collapse.ambulanceDispatched == true,
	speechLineSent = results.collapse.lineSent == true,
	results = results,
	stats = stats,
	placeVersion = game.PlaceVersion,
	elapsedSeconds = os.clock() - started,
}
