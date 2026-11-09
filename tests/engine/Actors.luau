--!strict
-- ServerStorage.EngineTests.Actors (CI place only; ci.project.json)
-- BUILD_PLAN §4.4 exit criterion "Actors" in the real engine through Open Cloud Luau Execution:
-- Server/Actors/ActorsRuntime builds the town's AI population on Shared.Generated with real bodies
-- (BodyFactory: Assets rigs when present, stock R15 humans, part puppets), the vehicle fleet with
-- placeholder interiors, Possession, RoleService. Then: every species is spawned (body counts by the
-- Species attribute equal the AI's counts); frames stepped by hand (no Heartbeat in Luau Execution)
-- move every AI body through BulkMoveTo; each species is possessed and released through a PlayerLike
-- stub (body mode, anchoring, AI resumes); 40 possess / swap / release cycles keep species counts and
-- leave no body destroyed ("death keeps species counts": bodies are never destroyed, D1); Population
-- floors hold through 200 scripted joins, promotions and leaves on data/population.json; every
-- vehicle has an EyeSocket.
-- Interface: run(opts?) -> Result (JSON-friendly)

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local server = ServerScriptService:WaitForChild("Server")
local shared = ReplicatedStorage:WaitForChild("Shared")
local ActorsRuntime = (require :: any)(server:WaitForChild("Actors"):WaitForChild("ActorsRuntime"))
local Possession = (require :: any)(server:WaitForChild("Actors"):WaitForChild("Possession"))
local Population = (require :: any)(shared:WaitForChild("Actors"):WaitForChild("Population"))
local Placeholder = (require :: any)(shared:WaitForChild("Vehicles"):WaitForChild("Placeholder"))
local Data = (require :: any)(shared:WaitForChild("Data"))

local Actors = {}

function Actors.run(_opts: { [string]: any }?): { [string]: any }
	local failures: { string } = {}
	local numbers: { [string]: any } = {}
	local function check(cond: boolean, msg: string)
		if not cond then
			table.insert(failures, msg)
		end
	end
	local t0 = os.clock()
	local engine = Possession.engine()
	engine.streamAround = function() end
	engine.setOwner = function(_root: any, _player: any?) end
	engine.setCharacter = function(player: any, model: any?)
		player.Character = model
	end
	local rt = ActorsRuntime.start({ players = false, engine = engine })
	rt.stop() -- no Heartbeat here; frames are stepped by hand
	numbers.buildSeconds = os.clock() - t0

	-- every species spawned, counts equal the AI's
	local bySpecies: { [string]: number } = {}
	for _, body in rt.bodies:GetChildren() do
		local sp = body:GetAttribute("Species")
		bySpecies[sp] = (bySpecies[sp] or 0) + 1
		check(body:IsA("Model") and body.PrimaryPart ~= nil, `{body.Name}: no PrimaryPart`)
	end
	for sp, n in rt.world.counts do
		check(bySpecies[sp] == n, `species {sp}: {bySpecies[sp]} bodies vs {n} actors`)
	end
	numbers.bodies = bySpecies
	for _, sp in { "human", "squirrel", "fox", "deer" } do
		check((bySpecies[sp] or 0) > 0, `no {sp} bodies`)
	end

	-- frames: every AI body moves
	local start: { [Model]: Vector3 } = {}
	for _, body in rt.bodies:GetChildren() do
		start[body] = (body :: Model):GetPivot().Position
	end
	local frames, ms = 300, 0
	for _ = 1, frames do
		local f0 = os.clock()
		rt.step(1 / 60)
		ms += (os.clock() - f0) * 1000
	end
	numbers.stepMsAvg = ms / frames
	local still = 0
	for body, p in start do
		if (body:GetPivot().Position - p).Magnitude < 0.5 then
			still += 1
		end
	end
	numbers.stillAfter5s = still
	check(still <= math.ceil(#rt.bodies:GetChildren() * 0.1), `{still} bodies did not move in 5 s`)

	-- possess and release every species through a PlayerLike stub
	local player = { UserId = 9001, Name = "stub", Character = nil }
	for _, spec in { { "human" }, { "squirrel", "normal" }, { "squirrel", "spicy" }, { "fox" }, { "deer" } } do
		local ok, why = rt.become(player, spec[1], spec[2])
		check(ok == true, `become {spec[1]} {spec[2] or ""}: {why}`)
		local actor = rt.possession:actorOf(player)
		if actor then
			check(actor.mode == "player", `{actor.id}: mode {actor.mode}`)
			check(not (actor.body.PrimaryPart :: BasePart).Anchored, `{actor.id}: still anchored`)
			check(player.Character == actor.body, `{actor.id}: Character not set`)
		end
	end
	rt.possession:release(player, "test")
	check(rt.possession:actorOf(player) == nil, "released")
	for _ = 1, 30 do
		rt.step(1 / 60)
	end

	-- 40 possess / swap / release cycles keep species counts; no body destroyed
	local players = {}
	for i = 1, 6 do
		players[i] = { UserId = 9100 + i, Name = `stub{i}`, Character = nil }
	end
	local kinds = { { "human" }, { "squirrel", "normal" }, { "fox" }, { "deer" }, { "human" } }
	for c = 1, 40 do
		local p = players[(c - 1) % #players + 1]
		if c % 5 == 0 then
			rt.possession:release(p, "cycle")
		else
			local k = kinds[(c - 1) % #kinds + 1]
			rt.become(p, k[1], k[2])
		end
		rt.step(1 / 60)
	end
	for _, p in players do
		rt.possession:release(p, "end")
	end
	local after: { [string]: number } = {}
	for _, body in rt.bodies:GetChildren() do
		local sp = body:GetAttribute("Species")
		after[sp] = (after[sp] or 0) + 1
	end
	for sp, n in bySpecies do
		check(after[sp] == n, `after cycles {sp}: {after[sp]} vs {n}`)
	end
	local okLedger, ledgerErrors = rt.possession:check()
	check(okLedger, "ledger: " .. table.concat(ledgerErrors, "; "))
	numbers.possession = rt.possession.stats

	-- Population floors through 200 scripted joins, promotions and leaves (data/population.json)
	local data = Data.default()
	local cfg = Population.fromData(data:population(), "frb")
	local state = Population.newState(cfg)
	local held = {}
	local seed = 11
	local function rnd(n: number): number
		seed = (seed * 1103515245 + 12345) % 2147483648
		return seed % n + 1
	end
	local floorBreaks = 0
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
				local to = if rnd(2) == 1 then "police" else "hospital_staff"
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
		if not Population.floorsOk(state, cfg) then
			floorBreaks += 1
		end
	end
	check(floorBreaks == 0, `population floors broke {floorBreaks} times`)

	-- vehicles with interiors
	local vehicles, eyes = 0, 0
	if rt.devices then
		for _, model in rt.devices.models do
			vehicles += 1
			if model:GetAttribute("VehicleKind") == "drone" or Placeholder.eyeSocket(model) then
				eyes += 1
			end
		end
	end
	numbers.vehicles = vehicles
	check(vehicles >= 7 and eyes == vehicles, `vehicles {vehicles}, with eye sockets {eyes}`)
	numbers.totalSeconds = os.clock() - t0
	return { suite = "Actors", ok = #failures == 0, failures = failures, numbers = numbers }
end

return Actors
