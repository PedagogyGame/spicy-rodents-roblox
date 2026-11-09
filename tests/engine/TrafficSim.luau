--!strict
-- ServerStorage.EngineTests.TrafficSim (CI place only; ci.project.json)
-- Track B W1 #8-#11 in the real engine (BUILD_PLAN §4.4, §6.5):
--   * traffic: the 25-vehicle fleet on the unified lanes (World/Height y) for `minutes` simulated minutes
--     at 30 Hz with scripted pedestrians and squirrels, ghost placeholders rendered from the encoded pose
--     stream through Traffic/Ghost (one BulkMoveTo per frame), ms per tick for the sim and the render;
--   * placeholders: every PuppetSpec and VehiclePuppet built with the engine library and RigSpec-validated,
--     plus R15 humans from STOCK HumanoidDescriptions (RolePalettes) via CreateHumanoidModelFromDescription
--     with our sockets added, validated against RigSpec.human;
--   * routes: Routes/Patches attached to Data.default():routes() (40 re-seated, every route loads);
--   * avatar: AvatarBlendService with the engine fetchers on two dev UserIds, applied and reverted on a
--     squirrel puppet and a placeholder human.
-- Interface: run(opts?) -> result table (JSON-able). Never runs on require.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local shared = ReplicatedStorage:WaitForChild("Shared")
local server = ServerScriptService:WaitForChild("Server")

local function req(root: Instance, path: string): any
	local node: Instance = root
	for part in string.gmatch(path, "[^/]+") do
		node = node:FindFirstChild(part) or error(`TrafficSim: {path} missing at {part}`)
	end
	return (require :: any)(node)
end

local TrafficSim = {}

export type Options = { minutes: number?, userIds: { number }? }

function TrafficSim.run(opts: Options?): { [string]: any }
	local o: Options = opts or {}
	local Data = req(shared, "Data")
	local Height = req(shared, "World/Height")
	local Ghost = req(shared, "Traffic/Ghost")
	local PartBuilder = req(shared, "Avatar/PartBuilder")
	local PuppetSpec = req(shared, "Avatar/PuppetSpec")
	local RolePalettes = req(shared, "Avatar/RolePalettes")
	local VehiclePuppet = req(shared, "Traffic/VehiclePuppet")
	local RigSpec = req(shared, "Actors/RigSpec")
	local Patches = req(shared, "Routes/Patches")
	local TrafficService = req(server, "Traffic/TrafficService")
	local AvatarBlendService = req(server, "Avatar/AvatarBlendService")

	local result: { [string]: any } = { failures = {} }
	local function fail(msg: string)
		table.insert(result.failures, msg)
	end
	local data = Data.default()
	local lib = PartBuilder.engineLib()
	local folder = Instance.new("Folder")
	folder.Name = "TrafficSimScratch"
	folder.Parent = workspace

	-- placeholders --------------------------------------------------------------------------
	local built, bad = 0, {}
	local function check(model: Instance, species: string)
		model.Parent = folder
		local rep = RigSpec.validate(model, species)
		built += 1
		if not rep.ok then
			local missing = {}
			for _, list in { rep.missingBones, rep.missingSockets, rep.missingRegions, rep.missingParts } do
				for _, m in list do
					table.insert(missing, m)
				end
			end
			table.insert(
				bad,
				`{model.Name} [{table.concat(missing, " ")}{if rep.primaryPartOk then "" else " primary"}]`
			)
		end
	end
	for _, s in { "squirrel", "rodent", "fox", "deer", "drone" } do
		check(PartBuilder.instantiate(PuppetSpec.spec(s), lib), s)
	end
	for _, role in RolePalettes.ROLES do
		check(PartBuilder.instantiate(PuppetSpec.human(role, 1, lib), lib), "human")
	end
	for _, kind in VehiclePuppet.KINDS do
		check(PartBuilder.instantiate(VehiclePuppet.spec(kind), lib), "car")
	end
	local stockOk, stockErr = pcall(function()
		for i, role in RolePalettes.ROLES do
			local desc = RolePalettes.description(role, i, lib)
			local model = Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
			model.Name = `Stock_{role}`
			PuppetSpec.finishStockR15(model, lib)
			result.stockJoints = model:GetAttributes()
			check(model, "human")
		end
	end)
	if not stockOk then
		fail(`stock R15: {stockErr}`)
	end
	result.placeholders = { built = built, failedRigSpec = bad, stockR15 = stockOk }
	if #bad > 0 then
		fail(`RigSpec failures: {table.concat(bad, ", ")}`)
	end

	-- routes ----------------------------------------------------------------------------------
	local routes = data:routes()
	Patches.attach(routes, data:module("HarvestPatches") :: any, data:lots())
	local patched = 0
	for _, r in routes:all() do
		if r.patched == "reseat" then
			patched += 1
		end
	end
	result.routes = { count = #routes:all(), reseated = patched }
	if patched ~= 40 then
		fail(`reseated {patched} routes, expected 40`)
	end

	-- traffic ---------------------------------------------------------------------------------
	local svc = TrafficService.new({ lanes = data:lanes(), roads = data:roads(), heightAt = Height.at, seed = 11 })
	local people = {
		{ x = 0, y = 0, z = 100, kind = "human" },
		{ x = 1000, y = 0, z = 0, kind = "human" },
	}
	local squirrels = {
		{ id = "sq1", x = -40, y = 0.45, z = 200 },
		{ id = "sq2", x = 900, y = 0.45, z = 30 },
	}
	local hits = 0
	svc.RunOver:connect(function()
		hits += 1
	end)
	svc:dispatchResponder({ -250, -450 })
	svc:dispatchIncident({ -375, -150 })
	local ghost = Ghost.new()
	local kinds = svc:kinds()
	local models = {}
	local ticks = math.floor((o.minutes or 3) * 60 * 30)
	local simMs, renderMs, renderN = 0, 0, 0
	local nan = 0
	for i = 1, ticks do
		local ph = math.sin(i / 30 * math.pi / 6)
		people[1].x = ph * 35
		people[2].z = ph * 40
		squirrels[1].x = -40 + ph * 30
		squirrels[2].z = 30 - ph * 30
		local t0 = os.clock()
		svc:step(1 / 30, { people = people, squirrels = squirrels })
		simMs += (os.clock() - t0) * 1000
		if i % 2 == 0 then -- 15 Hz pose stream
			ghost:push(i / 30, svc:poseRecords())
			local t1 = os.clock()
			Ghost.render(ghost, i / 30, folder, kinds, Height.at, models)
			renderMs += (os.clock() - t1) * 1000
			renderN += 1
		end
		for _, v in svc.vehicles do
			if v.x ~= v.x or v.z ~= v.z or v.y ~= v.y then
				nan += 1
			end
		end
	end
	local stats = svc:stats()
	local stuckMax = 0
	for _, s in stats.stuck do
		stuckMax = math.max(stuckMax, s)
	end
	result.traffic = {
		vehicles = #svc.vehicles,
		ticks = stats.ticks,
		meanTickMs = simMs / ticks,
		maxTickMs = stats.maxTickMs,
		meanRenderMs = if renderN > 0 then renderMs / renderN else 0,
		ghosts = #folder:GetChildren(),
		events = stats.events,
		runOvers = hits,
		stuckMaxSecs = stuckMax,
		nan = nan,
		unified = svc.unified,
	}
	if nan > 0 then
		fail("NaN poses")
	end
	if stuckMax > 60 then
		fail(`a vehicle was stuck {stuckMax} s`)
	end
	if (stats.events.stopped or 0) == 0 then
		fail("nobody stopped at the sign sites")
	end

	-- avatar ----------------------------------------------------------------------------------
	local blend = AvatarBlendService.new(AvatarBlendService.engineDeps())
	local applied = {}
	for _, uid in (o.userIds or { 1, 156 }) :: { number } do
		local ok, err = pcall(function()
			local sq = PartBuilder.instantiate(PuppetSpec.spec("squirrel"), lib)
			sq.Parent = folder
			local before = (sq:FindFirstChild("Body") :: BasePart).Color
			local look = blend:lookFor(uid, "squirrel")
			if not look then
				error("no look")
			end
			local n = blend:apply(sq, "squirrel", look)
			blend:revert(sq)
			local restored = (sq:FindFirstChild("Body") :: BasePart).Color == before
			local human = PartBuilder.instantiate(PuppetSpec.human("townsperson", 1, lib), lib)
			human.Parent = folder
			local hl = blend:lookFor(uid, "human")
			local hn = if hl then blend:apply(human, "human", hl) else 0
			table.insert(
				applied,
				{ userId = uid, animalOps = n, humanOps = hn, restored = restored, signature = look.signature }
			)
		end)
		if not ok then
			fail(`blend {uid}: {err}`)
		end
	end
	result.avatar = applied

	folder:Destroy()
	result.ok = #result.failures == 0
	return result
end

return TrafficSim
