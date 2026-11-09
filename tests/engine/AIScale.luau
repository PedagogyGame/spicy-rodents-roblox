--!strict
-- ServerStorage.EngineTests.AIScale (CI place only; ci.project.json)
-- Spike S5 / S19 (BUILD_PLAN §4.3, D4): the synthetic worst case in the real engine through Open
-- Cloud Luau Execution. Builds Server/AI/Scenario (AI humans on posts, riders, squirrels on the
-- spike routes, rodent, deer, fox, vehicle proxies, fender benders, 49 moving focus points), gives
-- every actor an anchored part puppet, then drives N frames at 60 Hz itself (no Heartbeat, no
-- physics in Luau Execution): BrainScheduler -> Kinematics -> grid -> traffic -> BulkMoveTo, timing
-- every phase with os.clock. Also micro-benchmarks BulkMoveTo for exactly 130 and 150 rigs in both
-- move modes and records memory. Returns JSON; the task script prints and returns it.
-- Pass criteria (plan): AI <= 4 ms per frame average (<= 8 ms p99); BulkMoveTo of 130 rigs <= 1 ms.

local ServerScriptService = game:GetService("ServerScriptService")
local Stats = game:GetService("Stats")

local server = ServerScriptService:WaitForChild("Server")
local aiFolder = server:WaitForChild("AI")
-- dynamic requires (luau-lsp cannot resolve instance paths statically; typed loosely on purpose)
local Scenario = (require :: any)(aiFolder:WaitForChild("Scenario"))
local Puppets = (require :: any)(aiFolder:WaitForChild("Puppets"))

export type ScenarioOpts = {
	name: string,
	humans: number?,
	riders: number?,
	squirrels: number?,
	deer: number?,
	fox: number?,
	vehicles: number?,
	fenderBenders: number?,
	players: number?,
	seed: number?,
	allNear: boolean?,
	frames: number?,
	moveMode: ("all" | "roots")?,
}

export type Options = {
	scenarios: { ScenarioOpts }?,
	wallLimitSeconds: number?,
}

local AIScale = {}

local function percentile(sorted: { number }, p: number): number
	if #sorted == 0 then
		return 0
	end
	return sorted[math.max(1, math.ceil(#sorted * p))]
end

local function memoryMb(): { [string]: number }
	local out: { [string]: number } = {}
	out.total = Stats:GetTotalMemoryUsageMb()
	for _, tag in
		{ Enum.DeveloperMemoryTag.Instances, Enum.DeveloperMemoryTag.Script, Enum.DeveloperMemoryTag.BaseParts }
	do
		local ok, v = pcall(function()
			return Stats:GetMemoryUsageMbForTag(tag)
		end)
		if ok then
			out[tag.Name] = v
		end
	end
	out.luauHeapKb = gcinfo()
	return out
end

-- Build puppets for every actor and vehicle; returns the rigs in actor order, then vehicle order.
local function buildPuppets(world: any, parent: Instance): ({ any }, { any })
	local actorRigs = {}
	for i, actor in world.actors do
		local rig = Puppets.build(actor.species, actor.variant, i, parent)
		actor.rig = rig
		table.insert(actorRigs, rig)
	end
	local vehicleRigs = {}
	for i, v in world.vehicles do
		local rig = Puppets.buildVehicle(i, parent, v.width, v.height, v.length)
		v.rig = rig
		table.insert(vehicleRigs, rig)
	end
	return actorRigs, vehicleRigs
end

local function poseOf(actorOrVehicle: any, pose: any)
	pose.x = actorOrVehicle.x
	pose.y = actorOrVehicle.y
	pose.z = actorOrVehicle.z
	pose.yaw = actorOrVehicle.yaw
end

-- BulkMoveTo micro-benchmark on exactly `count` rigs (reps, median ms), both modes.
local function benchBulkMove(rigs: { any }, count: number, reps: number): { [string]: any }
	local subset = {}
	for i = 1, math.min(count, #rigs) do
		subset[i] = rigs[i]
	end
	local poses = {}
	for i = 1, #subset do
		poses[i] = { x = i * 7, y = 5, z = 0, yaw = i * 0.1 }
	end
	local buffers = Puppets.newBuffers()
	local out: { [string]: any } = { rigs = #subset, parts = Puppets.partCount(subset) }
	for _, mode in { "all", "roots" } do
		local samples = {}
		local moved = 0
		for r = 1, reps do
			for i = 1, #subset do
				poses[i].x = i * 7 + r * 0.01
			end
			local t0 = os.clock()
			moved = Puppets.move(subset, poses, mode, buffers)
			table.insert(samples, (os.clock() - t0) * 1000)
		end
		table.sort(samples)
		out[mode] = {
			medianMs = samples[math.ceil(#samples / 2)],
			minMs = samples[1],
			maxMs = samples[#samples],
			partsMoved = moved,
		}
	end
	-- plain CFrame assignment on roots for comparison
	do
		local samples = {}
		for r = 1, reps do
			local t0 = os.clock()
			for i = 1, #subset do
				subset[i].root.CFrame = CFrame.new(i * 7 + r * 0.02, 5, 0)
			end
			table.insert(samples, (os.clock() - t0) * 1000)
		end
		table.sort(samples)
		out.plainCFrameRoots = { medianMs = samples[math.ceil(#samples / 2)] }
	end
	-- does a roots-only move carry the welded limbs?
	Puppets.anchorLimbs(subset, false)
	Puppets.move(subset, poses, "roots", buffers)
	local followed, err = Puppets.checkFollow(subset[1])
	out.rootsOnlyLimbsFollow = { followed = followed, errorStuds = err }
	Puppets.anchorLimbs(subset, true)
	return out
end

local function runScenario(opts: ScenarioOpts, deadline: number): { [string]: any }
	local result: { [string]: any } = { name = opts.name, opts = opts }
	local tStart = os.clock()
	local memBefore = memoryMb()

	local world = Scenario.build(opts)
	local folder = Instance.new("Folder")
	folder.Name = `AIScale_{opts.name}`
	folder.Parent = workspace
	local tBuild0 = os.clock()
	local actorRigs, vehicleRigs = buildPuppets(world, folder)
	local buildMs = (os.clock() - tBuild0) * 1000
	local allRigs = table.clone(actorRigs)
	for _, r in vehicleRigs do
		table.insert(allRigs, r)
	end
	local memAfterBuild = memoryMb()

	local moveMode = opts.moveMode or "all"
	if moveMode == "roots" then
		Puppets.anchorLimbs(allRigs, false)
	end
	local poses = {}
	for i = 1, #allRigs do
		poses[i] = { x = 0, y = 0, z = 0, yaw = 0 }
	end
	local buffers = Puppets.newBuffers()

	local frames = opts.frames or 1800
	local dt = 1 / 60
	local aiMs, moveMs, totalMs = {}, {}, {}
	local phases = { brainMs = 0, motorMs = 0, gridMs = 0, trafficMs = 0 }
	local ticked, deferred = 0, 0
	local framesRun = 0
	for f = 1, frames do
		local t0 = os.clock()
		local m = Scenario.stepFrame(world, dt)
		local t1 = os.clock()
		for i, actor in world.actors do
			poseOf(actor, poses[i])
		end
		local na = #world.actors
		for i, v in world.vehicles do
			poseOf(v, poses[na + i])
		end
		Puppets.move(allRigs, poses, moveMode, buffers)
		local t2 = os.clock()
		aiMs[f] = (t1 - t0) * 1000
		moveMs[f] = (t2 - t1) * 1000
		totalMs[f] = (t2 - t0) * 1000
		phases.brainMs += m.brainMs
		phases.motorMs += m.motorMs
		phases.gridMs += m.gridMs
		phases.trafficMs += m.trafficMs
		ticked += m.ticked
		deferred += m.deferred
		framesRun = f
		if os.clock() > deadline then
			result.stoppedEarly = true
			break
		end
	end
	local memAfterRun = memoryMb()

	local function summarise(list: { number }): { [string]: number }
		local sorted = table.clone(list)
		table.sort(sorted)
		local sum = 0
		for _, v in sorted do
			sum += v
		end
		return {
			avg = if #sorted > 0 then sum / #sorted else 0,
			p50 = percentile(sorted, 0.5),
			p99 = percentile(sorted, 0.99),
			max = if #sorted > 0 then sorted[#sorted] else 0,
		}
	end

	local live = Scenario.liveness(world)
	local sched = world.scheduler:metrics()
	result.counts = {
		actors = #world.actors,
		vehicles = #world.vehicles,
		focus = #world.focus,
		rigs = #allRigs,
		parts = Puppets.partCount(allRigs),
		byKind = live.byKind,
	}
	result.framesRun = framesRun
	result.simSeconds = framesRun * dt
	result.buildMs = buildMs
	result.ai = summarise(aiMs)
	result.move = summarise(moveMs)
	result.total = summarise(totalMs)
	result.phasesAvgMs = {
		brain = phases.brainMs / math.max(1, framesRun),
		motor = phases.motorMs / math.max(1, framesRun),
		grid = phases.gridMs / math.max(1, framesRun),
		traffic = phases.trafficMs / math.max(1, framesRun),
	}
	result.scheduler = {
		ticksPerSecond = sched.ticksPerSecond,
		deferredTotal = deferred,
		tiers = sched.tiers,
		brains = sched.brains,
		perKindUsPerTick = (function()
			local out = {}
			for kind, ms in sched.perKindMs do
				out[kind] = ms / math.max(1, sched.perKindTicks[kind]) * 1e6
			end
			return out
		end)(),
		ticksTotal = ticked,
	}
	result.liveness = { ok = live.ok, stuck = #live.stuck, nan = live.nan, outside = live.outside }
	result.memoryMb = { before = memBefore, afterBuild = memAfterBuild, afterRun = memAfterRun }
	result.moveMode = moveMode
	result.bulkMove = {
		rigs130 = benchBulkMove(allRigs, 130, 25),
		rigs150 = benchBulkMove(allRigs, 150, 25),
		all = benchBulkMove(allRigs, #allRigs, 25),
	}
	result.pass = {
		aiAvgUnder4ms = result.ai.avg <= 4,
		aiP99Under8ms = result.ai.p99 <= 8,
		bulkMove130Under1ms = result.bulkMove.rigs130.all.medianMs <= 1 or result.bulkMove.rigs130.roots.medianMs <= 1,
		liveness = live.ok,
	}
	result.ok = result.pass.aiAvgUnder4ms and result.pass.bulkMove130Under1ms and result.pass.liveness
	result.elapsedSeconds = os.clock() - tStart
	folder:Destroy()
	return result
end

function AIScale.run(options: Options?): { [string]: any }
	local opts: Options = options or {}
	local started = os.clock()
	local deadline = started + (opts.wallLimitSeconds or 200)
	local scenarios = opts.scenarios
		or {
			{ name = "s5_72_humans", humans = 72, frames = 1800, moveMode = "all" },
			{ name = "s5_72_humans_allNear", humans = 72, frames = 900, allNear = true, moveMode = "all" },
			{ name = "s19_90_humans", humans = 90, frames = 1200, moveMode = "roots" },
		}
	local results: { { [string]: any } } = {}
	local ok = true
	for _, sc in scenarios do
		if os.clock() > deadline - 20 then
			table.insert(results, { name = sc.name, skipped = "wall limit" })
			continue
		end
		local okRun, res = pcall(runScenario, sc, deadline)
		if okRun then
			table.insert(results, res)
			ok = ok and res.ok == true
		else
			table.insert(results, { name = sc.name, error = tostring(res) })
			ok = false
		end
	end
	return {
		suite = "AIScale",
		ok = ok,
		scenarios = results,
		elapsedSeconds = os.clock() - started,
		placeId = game.PlaceId,
		placeVersion = game.PlaceVersion,
	}
end

return AIScale
