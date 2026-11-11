--!strict
-- ServerStorage.EngineTests.Paintball (CI place only; ci.project.json)
-- Spike S18 (BUILD_PLAN §4.3, D29): the paintball arena inside the town server. Runs the S5 AI
-- scenario (Server/AI/Scenario, 72 AI humans + riders, squirrels, deer, fox, 45 vehicles, 2 fender
-- benders, 49 focus points, puppets moved with BulkMoveTo roots-only) and, in the same 60 Hz frames,
-- the S18 harness (Server/Paintball/Harness: 16 stub players + 10 bots on the five-floor box, server
-- balls with lag-compensated hit tests, splats) with its 26 bodies as puppets. Measures the arena's
-- added ms per frame (server work + its BulkMoveTo) and hit agreement with the shooter's view at
-- 0, 100 and 150 ms. No physics, no players (Luau Execution). Returns JSON.
-- Pass criteria (plan): arena adds < 1.5 ms per frame; >= 95 % agreement at 150 ms.

local ServerScriptService = game:GetService("ServerScriptService")
local Stats = game:GetService("Stats")

local server = ServerScriptService:WaitForChild("Server")
local aiFolder = server:WaitForChild("AI")
local Scenario = (require :: any)(aiFolder:WaitForChild("Scenario"))
local Puppets = (require :: any)(aiFolder:WaitForChild("Puppets"))
local Harness = (require :: any)(server:WaitForChild("Paintball"):WaitForChild("Harness"))

export type Options = { latenciesMs: { number }?, frames: number?, rewindMode: string?, wallLimitSeconds: number? }

local Paintball = {}

local function summarise(list: { number }): { [string]: number }
	local sorted = table.clone(list)
	table.sort(sorted)
	local sum = 0
	for _, v in sorted do
		sum += v
	end
	local n = #sorted
	local function pct(p: number): number
		return if n == 0 then 0 else sorted[math.max(1, math.ceil(n * p))]
	end
	return { avg = if n > 0 then sum / n else 0, p50 = pct(0.5), p99 = pct(0.99), max = pct(1) }
end

function Paintball.run(options: Options?): { [string]: any }
	local opts: Options = options or {}
	local started = os.clock()
	local deadline = started + (opts.wallLimitSeconds or 200)
	local dt = 1 / 60
	local frames = opts.frames or 1800
	local folder = Instance.new("Folder")
	folder.Name = "PaintballSpike"
	folder.Parent = workspace

	-- the S5 town population, built once and stepped through every condition
	local world = Scenario.build({ seed = 1 })
	local townRigs = {}
	for i, actor in world.actors do
		table.insert(townRigs, Puppets.build(actor.species, actor.variant, i, folder))
	end
	for i, v in world.vehicles do
		table.insert(townRigs, Puppets.buildVehicle(i, folder, v.width, v.height, v.length))
	end
	Puppets.anchorLimbs(townRigs, false)
	local townPoses = {}
	for i = 1, #townRigs do
		townPoses[i] = { x = 0, y = 0, z = 0, yaw = 0 }
	end
	local buffers = Puppets.newBuffers()
	local memBefore = Stats:GetTotalMemoryUsageMb()

	local conditions: { { [string]: any } } = {} -- a Harness report, or { rttMs, skipped }
	local latencies: { number } = opts.latenciesMs or { 0, 100, 150 }
	for _, rtt in latencies do
		if os.clock() > deadline - 10 then
			table.insert(conditions, { rttMs = rtt, skipped = "wall limit" })
			continue
		end
		local h = Harness.new({ shooters = 16, bots = 10, rttMs = rtt, seed = 18 + rtt, rewindMode = opts.rewindMode })
		local arenaRigs = {}
		for i = 1, #h.bodies do
			table.insert(arenaRigs, Puppets.build("human", "paintball", 1000 + i, folder))
		end
		Puppets.anchorLimbs(arenaRigs, false)
		local arenaPoses = {}
		for i = 1, #arenaRigs do
			arenaPoses[i] = { x = 0, y = 0, z = 0, yaw = 0 }
		end
		local arenaBuffers = Puppets.newBuffers()
		local townMs, arenaServerMs, arenaMoveMs, addedMs, harnessMs = {}, {}, {}, {}, {}
		for f = 1, frames do
			local t0 = os.clock()
			Scenario.stepFrame(world, dt)
			local na = #world.actors
			for i, actor in world.actors do
				local p = townPoses[i]
				p.x, p.y, p.z, p.yaw = actor.x, actor.y, actor.z, actor.yaw
			end
			for i, v in world.vehicles do
				local p = townPoses[na + i]
				p.x, p.y, p.z, p.yaw = v.x, v.y, v.z, v.yaw
			end
			Puppets.move(townRigs, townPoses, "roots", buffers)
			local t1 = os.clock()
			local arenaMs, hMs = Harness.step(h, dt)
			local t2 = os.clock()
			for i, b in h.bodies do
				local p = arenaPoses[i]
				p.x, p.y, p.z, p.yaw = 3000 + b.x, b.y + 3, b.z, b.yaw
			end
			Puppets.move(arenaRigs, arenaPoses, "roots", arenaBuffers)
			local t3 = os.clock()
			townMs[f] = (t1 - t0) * 1000
			arenaServerMs[f] = arenaMs
			harnessMs[f] = hMs
			arenaMoveMs[f] = (t3 - t2) * 1000
			addedMs[f] = arenaMs + arenaMoveMs[f]
			if os.clock() > deadline then
				break
			end
		end
		local report = Harness.report(h)
		report.townMs = summarise(townMs)
		report.arenaServerMs = summarise(arenaServerMs)
		report.arenaMoveMs = summarise(arenaMoveMs)
		report.addedMs = summarise(addedMs)
		report.harnessOnlyMs = summarise(harnessMs)
		report.arenaMs = nil
		report.harnessMs = nil
		report.pass = {
			addedUnder1_5ms = report.addedMs.avg < 1.5,
			agreement95 = rtt < 150 or report.agreement >= 0.95,
			shots200 = report.shots >= 200,
			splatsCapped = report.splats.max <= report.splats.cap,
		}
		table.insert(conditions, report)
		for _, r in arenaRigs do
			r.model:Destroy()
		end
	end
	local ok = true
	for _, c in conditions do
		if c.pass then
			ok = ok and c.pass.addedUnder1_5ms and c.pass.agreement95 and c.pass.shots200 and c.pass.splatsCapped
		else
			ok = false
		end
	end
	local result = {
		suite = "Paintball",
		ok = ok,
		town = { actors = #world.actors, vehicles = #world.vehicles, rigs = #townRigs },
		conditions = conditions,
		memoryMb = { before = memBefore, after = Stats:GetTotalMemoryUsageMb() },
		luauHeapKb = gcinfo(),
		elapsedSeconds = os.clock() - started,
		placeVersion = game.PlaceVersion,
	}
	folder:Destroy()
	return result
end

return Paintball
