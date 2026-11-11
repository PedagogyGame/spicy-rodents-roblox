--!strict
-- ServerStorage.EngineTests.BiteHospital (CI place only; injected with --inject ci.project.json)
-- The bite-to-hospital sequence in the real engine (owner 2026-11-10), through Open Cloud Luau
-- Execution: Server/Boot/Game boots the whole game with PlayerLike stubs (no players, no physics, no
-- Heartbeat: frames are stepped by hand), then
--   1. the rodent bites an AI townsperson with the dice set to "collapse at once": the Say/SayAt
--      attributes, Med "down" and not possessable, an ambulance out on the roads, Med "transit" with
--      the body drawn under the ground, Med "treated" inside the hospital, then cured there (Med gone,
--      possessable again) and home on foot;
--   2. the rodent bites a townsperson a (stub) player holds: the "med" events that say what to do,
--      the Infected attribute for the status line, the body never moved or hidden, and the cure by
--      standing inside the hospital;
--   3. nothing is left behind (no order, no sunk body, no held ambulance) and the possession ledger
--      still checks.
-- NOT YET RUN: the session that wrote it (2026-11-11) had the cloud checks off limits. The Lune suite
-- (tests/unit/infection_service.spec.luau) covers the same service with the same seams.
-- Interface: run(opts?) -> Result (JSON-friendly)

local ServerScriptService = game:GetService("ServerScriptService")
local server = ServerScriptService:WaitForChild("Server")
local Game = (require :: any)(server:WaitForChild("Boot"):WaitForChild("Game"))
local Possession = (require :: any)(server:WaitForChild("Actors"):WaitForChild("Possession"))

local BiteHospital = {}

local STEP = 0.1 -- seconds per hand-stepped frame (the runtime clamps a frame to this)

function BiteHospital.run(_opts: { [string]: any }?): { [string]: any }
	local failures: { string } = {}
	local numbers: { [string]: any } = {}
	local function check(cond: boolean, msg: string)
		if not cond then
			table.insert(failures, msg)
		end
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
	local possession = rt.possession
	local infection = G.infection
	if infection == nil or infection.layout == nil then
		G.stop()
		return {
			ok = false,
			failures = { "the infection service (or the hospital layout) did not start" },
			numbers = numbers,
		}
	end
	local layout = infection.layout
	local clock = 0
	local function step(secs: number)
		for _ = 1, math.max(1, math.floor(secs / STEP + 0.5)) do
			G.step(STEP)
			clock += STEP
		end
	end
	-- step until done() or the limit; returns whether it happened and the seconds it took
	local function waitFor(limit: number, done: () -> boolean): (boolean, number)
		local t0 = clock
		while clock - t0 < limit do
			if done() then
				return true, clock - t0
			end
			step(STEP)
		end
		return done(), clock - t0
	end
	local function inHospital(a: any, pad: number): boolean
		return math.abs(a.x - layout.lot.x) <= layout.lot.hw + pad
			and math.abs(a.z - layout.lot.z) <= layout.lot.hd + pad
	end
	local function bodyOf(townId: number): Model
		return rt.byTownId[townId].body :: Model
	end
	local function med(townId: number): any
		return bodyOf(townId):GetAttribute("Med")
	end
	-- how far under the terrain a body's root is drawn (a hidden body: about 40 studs)
	local function buried(a: any, root: BasePart): number
		return G.traffic.heightAt(a.x, a.z) - root.Position.Y
	end
	local function keysOf(player: any): { string }
		local out = {}
		for _, e in player.events do
			if e.kind == "med" then
				table.insert(out, tostring(e.key))
			end
		end
		return out
	end

	step(10) -- the town settles onto its lanes
	-- every bite collapses at once, and a crowd is always wanted
	infection.params.immediateChance = 1
	infection.tun.crowdChance = 1

	local rodentPlayer: { [string]: any } = { UserId = 7101, Name = "Rodent", Character = nil, attrs = {}, events = {} }
	local function becomeRodent(): any
		G.stateOf(rodentPlayer).lastPick = -math.huge
		local ok, why = G.pick(rodentPlayer, "rodent")
		check(ok, `pick rodent: {why}`)
		return possession:actorOf(rodentPlayer)
	end
	-- the rodent's body is put beside a person until the bite lands, then handed back to the AI
	local function biteThe(townId: number): boolean
		local rodent = becomeRodent()
		if rodent == nil then
			return false
		end
		local root = bodyOf(townId).PrimaryPart :: BasePart
		local landed = waitFor(3, function(): boolean
			rodent.body:PivotTo(CFrame.new(root.Position + Vector3.new(1.5, -1, 0)))
			return infection:isInfected(townId)
		end)
		possession:release(rodentPlayer, "test")
		G.stateOf(rodentPlayer).role = nil
		return landed
	end

	-- 1. an AI townsperson, bitten in the middle of town ---------------------------------------------
	local victim, bestD = nil, math.huge
	for _, a in world.actors do
		if a.species == "human" and a.post == "townsperson" then
			local d = a.x * a.x + a.z * a.z
			if d < bestD then
				victim, bestD = a, d
			end
		end
	end
	if victim == nil then
		G.stop()
		return { ok = false, failures = { "no townsperson to bite" }, numbers = numbers }
	end
	local id = victim.id
	local actor = rt.byTownId[id]
	local body = bodyOf(id)
	check(biteThe(id), "the bite did not land")
	check(victim.infected == true, "the bitten person is not infected")
	check(type(body:GetAttribute("Say")) == "string", "no line over the victim (Say)")
	check(type(body:GetAttribute("SayAt")) == "number", "no SayAt stamp")
	check(med(id) == nil, `Med shows before the collapse: {med(id)}`)
	local bit = false
	for _, e in rodentPlayer.events do
		bit = bit or e.kind == "bite"
	end
	check(bit, "the rodent's player got no bite event")

	local down, downSecs = waitFor(8, function(): boolean
		return med(id) == "down"
	end)
	numbers.downAfter = downSecs
	check(down, `never collapsed (state {infection:stateOf(id)})`)
	check(actor.possessable == false, "a patient on the ground is still possessable")
	local scene = infection.scenes[id]
	numbers.bystanders = if scene then #scene.bystanders else -1
	check(scene ~= nil, "no scene opened")
	check(scene == nil or #scene.bystanders ~= 1, "a crowd of one")

	local out, outSecs = waitFor(30, function(): boolean
		for _, v in G.traffic.vehicles do
			if v.class == "responder" and v.phase == "out" and v.visible then
				return true
			end
		end
		return false
	end)
	numbers.ambulanceOutAfter = outSecs
	check(out, "no ambulance was dispatched")
	local crew = infection.records[id] and infection.records[id].crew
	if crew then
		local crewRoot = bodyOf(crew).PrimaryPart :: BasePart
		step(1)
		local depth = buried(world.actorsById[crew], crewRoot)
		numbers.crewAboardDepth = depth
		check(depth > 15, `the crew member aboard is drawn in sight ({depth} studs under the ground)`)
	end

	local loaded, loadSecs = waitFor(260, function(): boolean
		return med(id) == "transit"
	end)
	numbers.loadedAfter = loadSecs
	check(loaded, `never loaded (state {infection:stateOf(id)}, Med {med(id)})`)
	step(0.3)
	local root = body.PrimaryPart :: BasePart
	numbers.transitDepth = buried(victim, root)
	check(buried(victim, root) > 15, `a patient in transit is drawn in sight ({buried(victim, root)} studs under)`)
	check(infection.scenes[id] == nil, "the scene is still open after the load")

	local bedded, bedSecs = waitFor(260, function(): boolean
		return med(id) == "treated"
	end)
	numbers.bedAfter = bedSecs
	check(bedded, `never in a bed (state {infection:stateOf(id)}, Med {med(id)})`)
	step(0.3)
	check(inHospital(victim, 0), `the bed is not in the hospital ({victim.x}, {victim.z})`)
	check(buried(victim, root) < 5, `the patient in bed is still under the ground ({buried(victim, root)} studs)`)
	check(victim.infected == true, "cured before the treatment")

	local cured, cureSecs = waitFor(45, function(): boolean
		return infection:stateOf(id) == nil
	end)
	numbers.curedAfter = cureSecs
	check(cured, `never cured (state {infection:stateOf(id)})`)
	check(cureSecs >= 25, `treated for only {cureSecs} s`)
	check(inHospital(victim, 0), "cured outside the hospital")
	check(not victim.infected and not infection:isInfected(id), "still infected after the cure")
	check(med(id) == nil, `Med still shows after the cure: {med(id)}`)
	check(actor.possessable ~= false, "not possessable after the cure")

	local home, homeSecs = waitFor(600, function(): boolean
		return infection.leaving[id] == nil
	end)
	numbers.homeAfter = homeSecs
	check(home, "never got home")
	check(not inHospital(victim, 30), "still at the hospital after the walk home")

	-- 2. a person a player holds ------------------------------------------------------------------------
	local holder: { [string]: any } = { UserId = 7102, Name = "Holder", Character = nil, attrs = {}, events = {} }
	local okPick, whyPick = G.pick(holder, "townsperson")
	check(okPick, `pick townsperson: {whyPick}`)
	local held = possession:actorOf(holder)
	local heldId = if held then G.townIdOf(held.id) else nil
	if held and heldId then
		local heldBody = held.body :: Model
		local at = heldBody:GetPivot().Position
		check(biteThe(heldId), "the bite on the held person did not land")
		step(2.5)
		numbers.heldToasts = keysOf(holder)
		check(table.find(keysOf(holder), "bitten") ~= nil, "the bitten player was not told")
		check(holder.attrs.Infected == "infected", `Infected attribute is {holder.attrs.Infected}`)
		check(infection:stateOf(heldId) == "incubating", `a held person is {infection:stateOf(heldId)}`)
		check((heldBody:GetPivot().Position - at).Magnitude < 1, "the service moved a body a player holds")
		check(heldBody:GetAttribute("Med") == nil, "Med shows while incubating")
		-- the player walks in through the front doors and stands in reception
		local r = layout.reception
		heldBody:PivotTo(CFrame.new(r[1], G.traffic.heightAt(r[1], r[2]) + 3.5, r[2]))
		step(2.5)
		check(infection:stateOf(heldId) == "treated", `in reception the case is {infection:stateOf(heldId)}`)
		check(holder.attrs.Infected == "treating", `Infected attribute is {holder.attrs.Infected}`)
		step(31)
		numbers.heldToastsAfter = keysOf(holder)
		check(infection:stateOf(heldId) == nil, `not cured after 30 s inside ({infection:stateOf(heldId)})`)
		check(table.find(keysOf(holder), "cured") ~= nil, "the cured player was not told")
		step(1.5)
		check(holder.attrs.Infected == nil, `Infected attribute is still {holder.attrs.Infected}`)
		check(possession:actorOf(holder) == held, "the player lost the body")
	else
		table.insert(failures, "no body for the holder")
	end

	-- 3. nothing left behind ----------------------------------------------------------------------------
	-- (the rodent may have caught somebody else who stood beside a victim: their case runs out first)
	local drained, drainSecs = waitFor(900, function(): boolean
		return next(infection:cases()) == nil and next(infection.leaving) == nil
	end)
	numbers.drainedAfter = drainSecs
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
	for _, v in G.traffic.vehicles do
		if v.class == "responder" then
			check(v.phase == "idle" and not v.held, `{v.name} is {v.phase}`)
		end
	end
	numbers.stats = infection:stats()
	check(infection:stats().faults == 0, `{infection:stats().faults} contained faults`)
	check(infection:stats().cured >= 2, `{infection:stats().cured} cures`)
	check(
		infection:stats().cured == infection:stats().cases,
		`{infection:stats().cases} cases, {infection:stats().cured} cured`
	)
	local okLedger, errors = possession:check()
	check(okLedger, `possession ledger: {table.concat(errors, "; ")}`)
	G.stop()
	return { ok = #failures == 0, failures = failures, numbers = numbers }
end

return BiteHospital
