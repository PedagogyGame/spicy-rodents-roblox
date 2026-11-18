--!strict
-- ServerStorage.EngineTests.BodyBudget (CI place only; ci.project.json)
-- Spike S19 (BUILD_PLAN §4.3, §1.5, D4, D23, D25): S5's worst case rebuilt at brief v2's floors. On
-- top of Server/AI/Scenario (AI humans on posts with the protected police, hospital and ambulance
-- posts, 8 riders, 14 squirrels, the rodent, 6 deer, a fox, 45 vehicles, 2 fender benders, 49 moving
-- focus points) it adds 49 human-player bodies riding the focus points and a 16-bot paintball match
-- (Server/Paintball/Harness, bots only), every body a Humanoid puppet (anchored root + Motor6D limbs,
-- BulkMoveTo on roots). A ladder of variants by total human Humanoids measures ms per frame (AI,
-- arena, moves, total; avg and p99), BulkMoveTo of 150 rigs, and memory. S5's AIScale is untouched.
-- Pass criteria (plan): AI <= 4 ms per frame average with about 90 Humanoids (p99 <= 8 ms as the
-- regression signal); BulkMoveTo of 150 anchored rigs < 1 ms; the hard cap recorded by measurement.

local ServerScriptService = game:GetService("ServerScriptService")
local Stats = game:GetService("Stats")

local server = ServerScriptService:WaitForChild("Server")
local aiFolder = server:WaitForChild("AI")
local Scenario = (require :: any)(aiFolder:WaitForChild("Scenario"))
local Puppets = (require :: any)(aiFolder:WaitForChild("Puppets"))
local Harness = (require :: any)(server:WaitForChild("Paintball"):WaitForChild("Harness"))

export type Variant = { name: string, aiHumans: number, playerBodies: number?, bots: number?, frames: number? }
export type Options = { variants: { Variant }?, wallLimitSeconds: number? }

local BodyBudget = {}

-- AI humans 31 = the spike config's protected posts (14 police incl. guard and car crew >= 6 + 3,
-- 14 hospital >= 10, 3 ambulance crew); the rest are townspeople, shop workers and attraction staff.
BodyBudget.VARIANTS = {
	{ name = "s19_96_floors", aiHumans = 31 }, -- 49 + 31 + 16 = 96: floors only, bots re-posted on top
	{ name = "s19_109_worst", aiHumans = 44 }, -- 49 + 44 + 16 = 109: brief v2 stack (shop, street, attractions)
	{ name = "s19_130_stress", aiHumans = 65 },
	{ name = "s19_160_stress", aiHumans = 95 },
}

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

local function memory(): { [string]: number }
	return { totalMb = Stats:GetTotalMemoryUsageMb(), luauHeapKb = gcinfo() }
end

local function runVariant(v: Variant, deadline: number): { [string]: any }
	local tStart = os.clock()
	local memBefore = memory()
	local players = v.playerBodies or 49
	local botCount = v.bots or 16
	local world = Scenario.build({
		humans = v.aiHumans,
		riders = 8,
		squirrels = 14,
		deer = 6,
		fox = 1,
		vehicles = 45,
		fenderBenders = 2,
		players = players,
		seed = 19,
	})
	local arena = Harness.new({ shooters = 0, bots = botCount, seed = 19, evaluate = false })
	local folder = Instance.new("Folder")
	folder.Name = `BodyBudget_{v.name}`
	folder.Parent = workspace
	local tBuild = os.clock()
	local rigs = {}
	for i, actor in world.actors do
		table.insert(rigs, Puppets.build(actor.species, actor.variant, i, folder))
	end
	local nActors = #rigs
	for i = 1, players do
		table.insert(rigs, Puppets.build("human", "player", 500 + i, folder))
	end
	for i = 1, #arena.bodies do
		table.insert(rigs, Puppets.build("human", "paintball", 800 + i, folder))
	end
	local nBodies = #rigs
	for i, veh in world.vehicles do
		table.insert(rigs, Puppets.buildVehicle(i, folder, veh.width, veh.height, veh.length))
	end
	local buildMs = (os.clock() - tBuild) * 1000
	Puppets.anchorLimbs(rigs, false)
	local humanoids = 0
	for _, d in folder:GetDescendants() do
		if d:IsA("Humanoid") then
			humanoids += 1
		end
	end
	local memAfterBuild = memory()
	local poses = {}
	for i = 1, #rigs do
		poses[i] = { x = 0, y = 0, z = 0, yaw = 0 }
	end
	local buffers = Puppets.newBuffers()
	local dt = 1 / 60
	local frames = v.frames or 1200
	local aiMs, arenaMs, moveMs, totalMs = {}, {}, {}, {}
	local framesRun = 0
	for f = 1, frames do
		local t0 = os.clock()
		Scenario.stepFrame(world, dt)
		local t1 = os.clock()
		Harness.step(arena, dt)
		local t2 = os.clock()
		for i, actor in world.actors do
			local p = poses[i]
			p.x, p.y, p.z, p.yaw = actor.x, actor.y, actor.z, actor.yaw
		end
		for i = 1, players do
			local fp = world.focus[i]
			local p = poses[nActors + i]
			if fp then
				p.x, p.y, p.z = fp.x, 3, fp.z
			end
		end
		for i, b in arena.bodies do
			local p = poses[nActors + players + i]
			p.x, p.y, p.z, p.yaw = 3000 + b.x, b.y + 3, b.z, b.yaw
		end
		for i, veh in world.vehicles do
			local p = poses[nBodies + i]
			p.x, p.y, p.z, p.yaw = veh.x, veh.y, veh.z, veh.yaw
		end
		Puppets.move(rigs, poses, "roots", buffers)
		local t3 = os.clock()
		aiMs[f] = (t1 - t0) * 1000
		arenaMs[f] = (t2 - t1) * 1000
		moveMs[f] = (t3 - t2) * 1000
		totalMs[f] = (t3 - t0) * 1000
		framesRun = f
		if os.clock() > deadline then
			break
		end
	end
	local memAfterRun = memory()
	-- BulkMoveTo of exactly 150 rigs, roots only (25 reps, median)
	local subset = table.move(rigs, 1, math.min(150, #rigs), 1, {})
	local samples = {}
	for r = 1, 25 do
		for i = 1, #subset do
			poses[i].x = i * 7 + r * 0.01
		end
		local t0 = os.clock()
		Puppets.move(subset, poses, "roots", buffers)
		table.insert(samples, (os.clock() - t0) * 1000)
	end
	table.sort(samples)
	local live = Scenario.liveness(world)
	local arenaReport = Harness.report(arena)
	local result: { [string]: any } = {
		name = v.name,
		counts = {
			humanHumanoids = v.aiHumans + players + botCount,
			humanoidsInWorkspace = humanoids,
			aiHumansPlanned = v.aiHumans,
			byKind = live.byKind,
			actors = #world.actors,
			playerBodies = players,
			paintballBots = botCount,
			vehicles = #world.vehicles,
			rigs = #rigs,
			parts = Puppets.partCount(rigs),
		},
		framesRun = framesRun,
		buildMs = buildMs,
		ai = summarise(aiMs),
		arena = summarise(arenaMs),
		move = summarise(moveMs),
		total = summarise(totalMs),
		bulkMove150RootsMs = { median = samples[13], min = samples[1], max = samples[25] },
		memory = { before = memBefore, afterBuild = memAfterBuild, afterRun = memAfterRun },
		liveness = { ok = live.ok, stuck = #live.stuck, nan = live.nan, outside = live.outside },
		arenaBots = {
			ballsFired = arenaReport.ballsFired,
			stuck = arenaReport.stuckBodies,
			splatsMax = arenaReport.splats.max,
		},
		elapsedSeconds = os.clock() - tStart,
	}
	result.pass = {
		aiAvgUnder4ms = result.ai.avg <= 4,
		aiP99Under8ms = result.ai.p99 <= 8,
		totalAvgUnder4ms = result.total.avg <= 4,
		bulkMove150Under1ms = samples[13] < 1,
		liveness = live.ok,
	}
	result.ok = result.pass.aiAvgUnder4ms and result.pass.bulkMove150Under1ms and result.pass.liveness
	folder:Destroy()
	return result
end

function BodyBudget.run(options: Options?): { [string]: any }
	local opts: Options = options or {}
	local started = os.clock()
	local deadline = started + (opts.wallLimitSeconds or 200)
	local results: { { [string]: any } } = {} -- a variant's report, or { name, skipped } or { name, error }
	local ok = true
	local variants: { Variant } = opts.variants or BodyBudget.VARIANTS
	for _, v in variants do
		if os.clock() > deadline - 15 then
			table.insert(results, { name = v.name, skipped = "wall limit" })
			continue
		end
		local okRun, res = pcall(runVariant, v, deadline)
		if okRun then
			table.insert(results, res)
			ok = ok and res.ok == true
		else
			table.insert(results, { name = v.name, error = tostring(res) })
			ok = false
		end
	end
	return {
		suite = "BodyBudget",
		ok = ok,
		variants = results,
		elapsedSeconds = os.clock() - started,
		placeVersion = game.PlaceVersion,
	}
end

return BodyBudget
