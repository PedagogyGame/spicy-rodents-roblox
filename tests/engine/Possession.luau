--!strict
-- ServerStorage.EngineTests.Possession
-- Spike S2 in the real engine (Open Cloud Luau Execution; BUILD_PLAN §4.3 S2, §1.5, D1, B4).
-- Builds 6 stock R15 bodies (CreateHumanoidModelFromDescription) and 3 squirrel puppets (the S7
-- puppet from ServerStorage.S2Templates or ReplicatedStorage.Assets.test, else the S5 part puppet),
-- registers them with ActorService, and runs the shared PossessionSoak with PlayerLike stubs:
-- the body side (anchoring, Humanoid state machine, momentum, PivotTo, Model counts, joints,
-- health) is the real engine; the player side (Character, SetNetworkOwner to a player) is
-- recorded by the stub engine because Luau Execution has no players. SetNetworkOwner(nil) and
-- CanSetNetworkOwnership() are called for real at every handoff. Then the 49-slot cap with 50 stubs.
-- What only OS-1a can show: mid-stride feel at 150 ms lag, no T-pose, camera, Reset menu, bubble.
-- Interface: run(opts?) -> result table (JSON-able)

local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local server = ServerScriptService:WaitForChild("Server")
local actorsFolder = server:WaitForChild("Actors")
local ActorService = (require :: any)(actorsFolder:WaitForChild("ActorService"))
local Possession = (require :: any)(actorsFolder:WaitForChild("Possession"))
local RoleService = (require :: any)(server:WaitForChild("Roles"):WaitForChild("RoleService"))
local LoopWalker = (require :: any)(
	ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Actors"):WaitForChild("LoopWalker")
)
local Soak = (require :: any)((script.Parent :: Instance):WaitForChild("PossessionSoak"))

local PossessionSuite = {}

local function findSquirrelTemplate(): (Model?, string)
	local s2 = ServerStorage:FindFirstChild("S2Templates")
	local t = s2 and s2:FindFirstChild("squirrel_puppet_s7")
	if t and t:IsA("Model") then
		return t, "ServerStorage.S2Templates.squirrel_puppet_s7"
	end
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local test = assets and assets:FindFirstChild("test")
	t = test and test:FindFirstChild("squirrel_puppet_s7")
	if t and t:IsA("Model") then
		return t, "ReplicatedStorage.Assets.test.squirrel_puppet_s7"
	end
	return nil, "none (S5 part puppet)"
end

local function partCount(m: Instance): number
	local n = 0
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") or d:IsA("Motor6D") then
			n += 1
		end
	end
	return n
end

export type Opts = { cycles: number?, seed: number?, humans: number?, squirrels: number? }

function PossessionSuite.run(opts: Opts?): { [string]: any }
	local o: Opts = opts or {}
	local started = os.clock()
	local folder = Instance.new("Folder")
	folder.Name = "PossessionSoakBodies"
	folder.Parent = workspace
	local floorY = 0

	-- bodies
	local template, templateSource = findSquirrelTemplate()
	local actors = ActorService.new()
	local walkers: { [string]: any } = {}
	local offsets: { [string]: number } = {}
	local roots: { BasePart } = {}
	local rootActors: { any } = {}
	local loop = { { x = -60, z = -60 }, { x = 60, z = -60 }, { x = 60, z = 60 }, { x = -60, z = 60 } }
	local buildMs: { [string]: number } = {}
	local nH, nS = o.humans or 6, o.squirrels or 3
	for i = 1, nH + nS do
		local species = if i <= nH then "human" else "squirrel"
		local id = `{species}_{i}`
		local t0 = os.clock()
		local model: Model
		if species == "human" then
			model = ActorService.buildHuman(i)
		elseif template then
			model = template:Clone()
		else
			local Puppets = (require :: any)(server:WaitForChild("AI"):WaitForChild("Puppets"))
			model = Puppets.build("squirrel", "normal", i, folder).model
		end
		ActorService.prepareBody(model, id, species)
		model.Parent = folder
		buildMs[species] = (buildMs[species] or 0) + (os.clock() - t0) * 1000
		local w = LoopWalker.new(loop, if species == "human" then 3 else 20, i * 37, "walk")
		walkers[id] = w
		offsets[id] = ActorService.groundOffset(model)
		local x, z, yaw = LoopWalker.pose(w)
		model:PivotTo(CFrame.new(x, floorY + offsets[id], z) * CFrame.Angles(0, yaw, 0))
		local actor = actors:register(ActorService.actor(id, species, "test", model, LoopWalker.brain(w)))
		table.insert(roots, model.PrimaryPart :: BasePart)
		table.insert(rootActors, actor)
	end
	local partsStart = partCount(folder)

	-- stub engine: the player side recorded, the body side real
	local clock = { t = 0 }
	local checks = { canSetFalse = 0, canSetReasons = {} :: { string }, ownerNilCalls = 0, ownerNilErrors = 0 }
	local engine = Possession.engine()
	local realSetOwner = engine.setOwner
	engine.streamAround = function() end
	engine.setOwner = function(root: any, player: any?)
		if player == nil then
			checks.ownerNilCalls += 1
			local ok = pcall(realSetOwner, root, nil)
			if not ok then
				checks.ownerNilErrors += 1
			end
		else
			local ok, can, reason = pcall(function()
				return (root :: BasePart):CanSetNetworkOwnership()
			end)
			if not ok or not can then
				checks.canSetFalse += 1
				if #checks.canSetReasons < 5 then
					table.insert(checks.canSetReasons, tostring(reason or can))
				end
				error(`cannot set network owner: {reason}`)
			end
		end
	end
	engine.setCharacter = function(player: any, model: any?)
		player.Character = model
	end
	engine.now = function(): number
		return clock.t
	end
	engine.serverTime = engine.now

	local wallPossess, wallRelease = { max = 0, total = 0, n = 0 }, { max = 0, total = 0, n = 0 }
	local possession = Possession.new({ actors = actors, engine = engine })
	local rawPossess, rawRelease = possession.possess, possession.release
	possession.possess = function(self: any, player: any, actor: any): (boolean, string?)
		local t0 = os.clock()
		local a, b = rawPossess(self, player, actor)
		local ms = (os.clock() - t0) * 1000
		wallPossess.max = math.max(wallPossess.max, ms)
		wallPossess.total += ms
		wallPossess.n += 1
		return a, b
	end
	possession.release = function(self: any, player: any, why: string?): string?
		local t0 = os.clock()
		local r = rawRelease(self, player, why)
		local ms = (os.clock() - t0) * 1000
		wallRelease.max = math.max(wallRelease.max, ms)
		wallRelease.total += ms
		wallRelease.n += 1
		return r
	end

	local function pickBody(_p: any): any
		for _, a in actors:all() do
			if a.species == "human" and possession:controllerOf(a) == "ai" then
				return a
			end
		end
		return nil
	end
	local roles = RoleService.new({
		possession = possession,
		pickBody = pickBody,
		kick = function(p: any, msg: string)
			p.kicked = msg
		end,
	})

	-- AI frame: walkers -> BulkMoveTo on AI roots only (rule 4)
	local moveParts: { BasePart } = {}
	local moveCFrames: { CFrame } = {}
	local aiMs = { max = 0, total = 0, n = 0 }
	local function stepAI(dt: number)
		local t0 = os.clock()
		table.clear(moveParts)
		table.clear(moveCFrames)
		for i, a in rootActors do
			if a.mode == "ai" then
				local x, z, yaw = LoopWalker.step(walkers[a.id], dt)
				table.insert(moveParts, roots[i])
				table.insert(moveCFrames, CFrame.new(x, floorY + offsets[a.id], z) * CFrame.Angles(0, yaw, 0))
			end
		end
		if #moveParts > 0 then
			workspace:BulkMoveTo(moveParts, moveCFrames, Enum.BulkMoveMode.FireCFrameChanged)
		end
		local ms = (os.clock() - t0) * 1000
		aiMs.max = math.max(aiMs.max, ms)
		aiMs.total += ms
		aiMs.n += 1
	end

	local players = {}
	for i = 1, 6 do
		players[i] = { UserId = -i, Name = `Player{i}`, Character = nil }
	end
	local soak = Soak.run({
		possession = possession,
		actors = actors,
		roles = roles,
		players = players,
		cycles = o.cycles or 500,
		seed = o.seed,
		advance = function(dt: number)
			clock.t += dt
		end,
		stepAI = stepAI,
		aiTicks = function(a: any): number
			return walkers[a.id].ticks
		end,
		bodyCount = function(): number
			local n = 0
			for _, c in folder:GetChildren() do
				if c:IsA("Model") then
					n += 1
				end
			end
			return n
		end,
	})

	-- engine-side end state
	local endState = { anchoredRoots = 0, humanoidsHealthy = 0, humanoidsDead = 0, stateMachineOff = 0 }
	for i, a in rootActors do
		if roots[i].Anchored then
			endState.anchoredRoots += 1
		end
		local h = (a.body :: Model):FindFirstChildOfClass("Humanoid")
		if h then
			if h.Health == h.MaxHealth then
				endState.humanoidsHealthy += 1
			end
			if h:GetState() == Enum.HumanoidStateType.Dead then
				endState.humanoidsDead += 1
			end
			if not h.EvaluateStateMachine then
				endState.stateMachineOff += 1
			end
		end
	end
	local partsEnd = partCount(folder)
	local strayModels = 0
	for _, c in workspace:GetChildren() do
		if c:IsA("Model") and c:GetAttribute("ActorId") ~= nil then
			strayModels += 1
		end
	end

	-- B4 cap with 50 stubs on a fresh service (bodies: the same 9; most joiners wait bodiless)
	local cap = Soak.capCheck(roles, possession, function(i: number): any
		return { UserId = 1000 + i, Name = `Cap{i}`, Character = nil }
	end, 50)

	folder:Destroy()
	local ok = soak.ok
		and cap.ok
		and partsEnd == partsStart
		and strayModels == 0
		and checks.canSetFalse == 0
		and checks.ownerNilErrors == 0
		and endState.anchoredRoots == nH + nS
		and endState.humanoidsDead == 0
	return {
		suite = "Possession",
		ok = ok,
		squirrelTemplate = templateSource,
		bodies = { humans = nH, squirrels = nS, buildMs = buildMs },
		soak = soak,
		cap = cap,
		engineChecks = checks,
		joints = { start = partsStart, ["end"] = partsEnd },
		strayModels = strayModels,
		endState = endState,
		wallMs = {
			possessMax = wallPossess.max,
			possessAvg = if wallPossess.n > 0 then wallPossess.total / wallPossess.n else 0,
			releaseMax = wallRelease.max,
			releaseAvg = if wallRelease.n > 0 then wallRelease.total / wallRelease.n else 0,
			aiFrameMax = aiMs.max,
			aiFrameAvg = if aiMs.n > 0 then aiMs.total / aiMs.n else 0,
		},
		elapsedSeconds = os.clock() - started,
	}
end

return PossessionSuite
