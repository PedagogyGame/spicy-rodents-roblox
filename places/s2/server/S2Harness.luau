--!strict
-- ServerScriptService.S2.S2Harness (places/s2 only: the owner's possession test place, OS-1a)
-- Builds a self-contained possession test (BUILD_PLAN §4.3 S2): a flat area, 6 walking AI R15
-- humans on a sidewalk loop and 3 running AnimationController squirrel puppets (the S7 puppet
-- and its uploaded Run clip), Possession + RoleService wired to Players (49 cap, release on
-- leave), the Reset button routed to recovery, and a debug panel's commands (take a walking
-- person / a running squirrel / swap / release / bubble fallback). AI bodies are anchored and
-- moved with BulkMoveTo on their roots (rule 4); clients animate every body locally (D3).
-- `build()` makes the world without starting loops (the Luau Execution smoke calls it);
-- `start()` builds and connects everything (the place's Script calls it).
-- Interface: build() -> World; start() -> World; stepAI(world, dt)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local server = ServerScriptService:WaitForChild("Server")
local ActorService = (require :: any)(server:WaitForChild("Actors"):WaitForChild("ActorService"))
local Possession = (require :: any)(server.Actors:WaitForChild("Possession"))
local RoleService = (require :: any)(server:WaitForChild("Roles"):WaitForChild("RoleService"))
local sharedActors = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Actors")
local LoopWalker = (require :: any)(sharedActors:WaitForChild("LoopWalker"))
local PossessionState = (require :: any)(sharedActors:WaitForChild("PossessionState"))

local S2Harness = {}

local HUMAN_SPEED = 3.5 -- studs/s (Species human walk R(0.8, 1.6) u/s = 2-4 st/s)
local SQUIRREL_SPEED = 20 -- studs/s (Species squirrel ground walk 8 u/s)
local FLOOR_Y = 0.2 -- top of the sidewalk

export type World = {
	actors: any,
	possession: any,
	roles: any,
	walkers: { [string]: any },
	offsets: { [string]: number },
	list: { any },
	folder: Folder,
	net: Folder,
	lastResumeMs: number?,
}

local function remote(parent: Instance, name: string): RemoteEvent
	local r = parent:FindFirstChild(name)
	if r and r:IsA("RemoteEvent") then
		return r
	end
	local e = Instance.new("RemoteEvent")
	e.Name = name
	e.Parent = parent
	return e
end

local function rect(cx: number, cz: number, hx: number, hz: number): { { x: number, z: number } }
	return {
		{ x = cx - hx, z = cz - hz },
		{ x = cx + hx, z = cz - hz },
		{ x = cx + hx, z = cz + hz },
		{ x = cx - hx, z = cz + hz },
	}
end

function S2Harness.build(): World
	local folder = workspace:FindFirstChild("Bodies") :: Folder?
	if folder == nil then
		local f = Instance.new("Folder")
		f.Name = "Bodies"
		f.Parent = workspace
		folder = f
	end
	local bodies = folder :: Folder
	local net = ReplicatedStorage:FindFirstChild(PossessionState.NET.folder) :: Folder?
	if net == nil then
		local f = Instance.new("Folder")
		f.Name = PossessionState.NET.folder
		f.Parent = ReplicatedStorage
		net = f
	end
	local netFolder = net :: Folder
	for _, name in { PossessionState.NET.Granted, PossessionState.NET.Released, PossessionState.NET.Recover, "S2Debug" } do
		remote(netFolder, name)
	end

	local templates = ServerStorage:FindFirstChild("S2Templates")
	local template = templates and templates:FindFirstChild("squirrel_puppet_s7")
	local actors = ActorService.new()
	local world: World = {
		actors = actors,
		possession = nil,
		roles = nil,
		walkers = {},
		offsets = {},
		list = {},
		folder = bodies,
		net = netFolder,
		lastResumeMs = nil,
	}
	local humanLoop = rect(0, 0, 60, 60) -- the sidewalk's edge, 480 st around
	local squirrelLoop = rect(0, 0, 40, 25)
	local t0 = workspace:GetServerTimeNow()
	for i = 1, 9 do
		local species = if i <= 6 then "human" else "squirrel"
		local id = `{species}_{i}`
		local model: Model
		if species == "human" then
			model = ActorService.buildHuman(i)
		elseif template then
			model = (template :: Model):Clone()
		else
			error("S2Harness: ServerStorage.S2Templates.squirrel_puppet_s7 missing")
		end
		ActorService.prepareBody(model, id, species)
		local w = if species == "human"
			then LoopWalker.new(humanLoop, HUMAN_SPEED + (i % 3) * 0.3, i * 80, "walk")
			else LoopWalker.new(squirrelLoop, SQUIRREL_SPEED, (i - 6) * 43, "run")
		world.walkers[id] = w
		world.offsets[id] = ActorService.groundOffset(model)
		local x, z, yaw = LoopWalker.pose(w)
		model:PivotTo(CFrame.new(x, FLOOR_Y + world.offsets[id], z) * CFrame.Angles(0, yaw, 0))
		model:SetAttribute(PossessionState.ATTR.MoveState, w.mode)
		model:SetAttribute(PossessionState.ATTR.Clip, w.mode)
		model:SetAttribute(PossessionState.ATTR.ClipT0, t0)
		model:SetAttribute(PossessionState.ATTR.Speed, w.speed)
		model.Parent = bodies
		table.insert(world.list, actors:register(ActorService.actor(id, species, "test", model, LoopWalker.brain(w))))
	end

	local granted = netFolder:FindFirstChild(PossessionState.NET.Granted) :: RemoteEvent
	local released = netFolder:FindFirstChild(PossessionState.NET.Released) :: RemoteEvent
	world.possession = Possession.new({
		actors = actors,
		onGranted = function(player: Player, payload: any)
			granted:FireClient(player, payload)
		end,
		onReleased = function(player: Player, actorId: string, why: string)
			if player.Parent == Players then
				released:FireClient(player, actorId, why)
			end
		end,
		safePose = function(actor: any): (number, number, number, number)
			local x, _y, z, yaw = actors:poseOf(actor)
			x, z = math.clamp(x, -150, 150), math.clamp(z, -150, 150)
			return x, FLOOR_Y + world.offsets[actor.id] + 1, z, yaw
		end,
	})
	world.roles = RoleService.new({
		possession = world.possession,
		pickBody = function(player: Player): any
			return S2Harness.nearestFree(world, "human", player)
		end,
	})
	return world
end

-- The free body of `species` nearest to the player's current body (or the centre).
function S2Harness.nearestFree(world: World, species: string, player: Player?): any
	local px, pz = 0, 0
	local current = player and world.possession:actorOf(player)
	if current then
		local x, _, z = world.actors:poseOf(current)
		px, pz = x, z
	end
	local best, bestD = nil, math.huge
	for _, a in world.list do
		if a.species == species and world.possession:controllerOf(a) == "ai" then
			local x, _, z = world.actors:poseOf(a)
			local d = (x - px) ^ 2 + (z - pz) ^ 2
			if d < bestD then
				best, bestD = a, d
			end
		end
	end
	return best
end

local moveParts: { BasePart } = {}
local moveCFrames: { CFrame } = {}

function S2Harness.stepAI(world: World, dt: number)
	table.clear(moveParts)
	table.clear(moveCFrames)
	local now = os.clock()
	for _, a in world.list do
		local body = a.body :: Model
		if a.mode == "ai" then
			local x, z, yaw = LoopWalker.step(world.walkers[a.id], dt)
			table.insert(moveParts, body.PrimaryPart :: BasePart)
			table.insert(moveCFrames, CFrame.new(x, FLOOR_Y + world.offsets[a.id], z) * CFrame.Angles(0, yaw, 0))
			if a.releasedAt then
				world.lastResumeMs = (now - a.releasedAt) * 1000
				workspace:SetAttribute("S2LastResumeMs", math.floor((world.lastResumeMs :: number) + 0.5))
				a.releasedAt = nil
			end
		else
			local root = body.PrimaryPart
			if root and root.Position.Y < -50 then
				world.possession:recover(world.possession:controllerOf(a))
			end
		end
	end
	if #moveParts > 0 then
		workspace:BulkMoveTo(moveParts, moveCFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

function S2Harness.start(): World
	local world = S2Harness.build()
	local possession, roles = world.possession, world.roles
	workspace:SetAttribute("BubbleFallback", false)

	local function join(player: Player)
		local result = roles:onJoin(player)
		print(`[S2] {player.Name} joined: {result}`)
	end
	Players.PlayerAdded:Connect(join)
	for _, p in Players:GetPlayers() do
		task.spawn(join, p)
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		roles:onLeave(player) -- release first (§1.5)
	end)

	local recover = world.net:FindFirstChild(PossessionState.NET.Recover) :: RemoteEvent
	recover.OnServerEvent:Connect(function(player: Player)
		local ok = possession:recover(player)
		print(`[S2] Reset from {player.Name} routed to recovery: {ok}`)
	end)

	local debug = world.net:FindFirstChild("S2Debug") :: RemoteEvent
	debug.OnServerEvent:Connect(function(player: Player, cmd: unknown)
		if cmd == "human" or cmd == "squirrel" then
			local target = S2Harness.nearestFree(world, cmd, player)
			if target then
				local ok, why = possession:possess(player, target)
				print(`[S2] {player.Name} take {cmd} {target.id}: {ok} {why or ""}`)
			end
		elseif cmd == "swap" then
			local current = possession:actorOf(player)
			local other = if current and current.species == "human" then "squirrel" else "human"
			local target = S2Harness.nearestFree(world, other, player)
			if target then
				local ok, why = possession:swap(player, target)
				print(`[S2] {player.Name} swap to {target.id}: {ok} {why or ""}`)
			end
		elseif cmd == "release" then
			possession:release(player, "debug")
		elseif cmd == "bubble" then
			workspace:SetAttribute("BubbleFallback", not workspace:GetAttribute("BubbleFallback"))
		end
	end)

	RunService.Heartbeat:Connect(function(dt: number)
		S2Harness.stepAI(world, dt)
	end)
	print("[S2] possession test place ready: 6 humans, 3 squirrels")
	return world
end

return S2Harness
