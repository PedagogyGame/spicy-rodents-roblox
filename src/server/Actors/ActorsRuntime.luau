--!strict
-- ServerScriptService.Server.Actors.ActorsRuntime
-- The engine runtime of the actor model (BUILD_PLAN §1.3 server frame, §1.5, §4.4 #3, #5): builds the
-- town's AI population (Server/AI/TownAI on Shared/Data), gives every actor a body
-- (Actors/BodyFactory) in workspace.Bodies, registers them with ActorService, wires Possession
-- (the single handoff; onHandoff marks the actor teleported in SweptCollision and resets the
-- MoveValidator through Movement/MovementService when given, rule 12), RoleService (join, leave,
-- the 50th-arrival turn-away) and the device fleet (Actors/DeviceService). Every Heartbeat: TownAI
-- steps brains and AI motors, then one workspace:BulkMoveTo over the AI bodies' roots (rule 4);
-- possessed bodies are the players'. Reset routes to Possession.recover (Movement/Recovery picks the
-- quay or the last safe position; for a held squirrel, Movement/MovementService.safeTarget: the places its accepted
-- clean grounded packets stood on a floor).
-- The one call Main.server needs: ActorsRuntime.start({}) (after WorldBoot). The S2 test place keeps
-- its own harness.
-- Interface: start(opts) -> Runtime { world, actors, possession, roles, devices, pickBody(player, rung),
--   become(player, species, variant?) -> (ok, reason), stop() }; speciesForRung(rung); AI_ONLY;
--   pickFree(actors, free, species, variant?, near?) -> town actor? (pure)
-- Engine only inside the functions. No side effects on require.

local Import = require("../Import")
local PossessionState =
	Import.shared("Actors/PossessionState") :: typeof(require("../../shared/Actors/PossessionState"))
local Data = Import.shared("Data") :: typeof(require("../../shared/Data"))
local Units = Import.shared("Config/Units") :: typeof(require("../../shared/Config/Units"))
local Recovery = Import.shared("Movement/Recovery") :: typeof(require("../../shared/Movement/Recovery"))
local ActorService = require("./ActorService")
local Possession = require("./Possession")
local BodyFactory = require("./BodyFactory")
local DeviceService = require("./DeviceService")
local TownAI = require("../AI/TownAI")

export type Opts = {
	data: any?,
	seed: number?,
	humans: number?, -- override standing humans (engine tests)
	squirrels: number?,
	devices: boolean?, -- spawn the vehicle fleet (default true)
	players: boolean?, -- connect PlayerAdded / PlayerRemoving (default true)
	movement: any?, -- Movement/MovementService instance (onHandoff)
	roles: any?, -- a RoleService constructor module (default Server/Roles/RoleService)
	purse: ((player: any) -> any)?, -- the town wallet's purse for a joining player (Boot/Game.wallet's purse hook: join, then the face)
	engine: any?, -- Possession.Engine override (engine tests drive PlayerLike stubs)
}

export type Runtime = {
	world: any,
	actors: any,
	possession: any,
	roles: any?,
	devices: any?,
	bodies: Folder,
	byTownId: { [number]: any },
	pickBody: (player: any, rung: string?) -> any?,
	become: (player: any, species: string, variant: string?) -> (boolean, string?),
	step: (dt: number) -> (),
	stop: () -> (),
}

local ActorsRuntime = {}

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

-- species and variant a Ladder rung asks for (rung names from Roles/Ladder)
function ActorsRuntime.speciesForRung(rung: string?): (string, string?)
	local r = string.lower(rung or "")
	if string.find(r, "rodent", 1, true) then
		return "squirrel", "spicy"
	elseif string.find(r, "squirrel", 1, true) then
		return "squirrel", "normal"
	elseif string.find(r, "deer", 1, true) then
		return "deer", nil
	elseif string.find(r, "fox", 1, true) then
		return "fox", nil
	end
	return "human", nil
end

-- Posts whose bodies are AI-only and never handed to a player: the street riders (decision 21, data/population.json
-- nonHumanoid: part-built rigs with no Humanoid, which a player could not move and which would fall once let go).
ActorsRuntime.AI_ONLY = table.freeze({ rider = true }) :: { [string]: boolean }

-- pickFree(actors, free, species, variant?, near?): the town actor (TownAI world.actors) a player may be handed: the
-- nearest to `near` (or the lowest id) of that species and variant that `free` allows, a person only from the street
-- (post townsperson); failing that any free person of another post. Never an AI-only post.
function ActorsRuntime.pickFree(
	actors: { any },
	free: (a: any) -> boolean,
	species: string,
	variant: string?,
	near: Vector3?
): any?
	local best, bestD = nil, math.huge
	for _, a in actors do
		if
			a.species == species
			and (variant == nil or a.variant == variant)
			and not ActorsRuntime.AI_ONLY[a.post or ""]
			and (species ~= "human" or a.post == "townsperson")
			and free(a)
		then
			local d = if near then math.sqrt((a.x - near.X) ^ 2 + (a.z - near.Z) ^ 2) else a.id
			if d < bestD then
				best, bestD = a, d
			end
		end
	end
	if best == nil and species == "human" then
		-- above-floor bodies of any other post (Population's re-post step, simplified for W1)
		for _, a in actors do
			if a.species == "human" and not ActorsRuntime.AI_ONLY[a.post or ""] and free(a) then
				return a
			end
		end
	end
	return best
end

function ActorsRuntime.start(opts: Opts): Runtime
	local Players = game:GetService("Players")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local RunService = game:GetService("RunService")

	local data = opts.data or Data.default()
	local world = TownAI.build({ data = data, seed = opts.seed, humans = opts.humans, squirrels = opts.squirrels })

	local net = ReplicatedStorage:FindFirstChild(PossessionState.NET.folder) or Instance.new("Folder")
	net.Name = PossessionState.NET.folder
	net.Parent = ReplicatedStorage
	local granted = remote(net, PossessionState.NET.Granted)
	local released = remote(net, PossessionState.NET.Released)
	local recover = remote(net, PossessionState.NET.Recover)

	local bodies = workspace:FindFirstChild("Bodies") or Instance.new("Folder")
	bodies.Name = "Bodies"
	bodies.Parent = workspace

	local actors = ActorService.new()
	local byTownId: { [number]: any } = {}
	local townIdOf: { [string]: number } = {}
	local offsets: { [number]: number } = {}
	local roots: { [number]: BasePart } = {}
	local history: { [string]: any } = {}
	local t0 = workspace:GetServerTimeNow()

	for _, a in world.actors do
		local model = BodyFactory.build(a.species, a.variant, a.id, a.post, a.ride)
		local id = `{a.species}_{a.id}`
		model.Name = id
		model:SetAttribute(PossessionState.ATTR.ActorId, id)
		model:SetAttribute(PossessionState.ATTR.ClipT0, t0)
		offsets[a.id] = ActorService.groundOffset(model)
		roots[a.id] = model.PrimaryPart :: BasePart
		model:PivotTo(Units.yawCFrame(a.yaw, Vector3.new(a.x, a.y - a.hip + offsets[a.id], a.z)))
		model.Parent = bodies
		local townId = a.id
		local brain = {
			suspend = function(): { [string]: any }
				local snap = TownAI.suspend(world, townId)
				return { vx = snap.vx, vy = 0, vz = snap.vz, mode = snap.mode, brain = snap.brain }
			end,
			resume = function(x: number, y: number, z: number)
				local actor = world.actorsById[townId]
				TownAI.resume(world, townId, x, y - offsets[townId] + actor.hip, z)
			end,
		}
		local actor = actors:register(ActorService.actor(id, a.species, a.variant, model, brain, true))
		byTownId[a.id] = actor
		townIdOf[id] = a.id
	end

	local movement = opts.movement
	local possession = Possession.new({
		actors = actors,
		engine = opts.engine,
		onGranted = function(player: any, payload: any)
			payload.variant = (byTownId[townIdOf[payload.actorId]] or {}).variant
			-- the motor epoch the driver's packets carry (Movement/MovementService; onHandoff made it just before)
			if movement and movement.epochOf then
				payload.motorEpoch = movement:epochOf(payload.actorId)
			end
			if typeof(player) == "Instance" then
				granted:FireClient(player :: Player, payload)
			end
		end,
		onReleased = function(player: any, actorId: string, why: string)
			if typeof(player) == "Instance" and player.Parent == Players then
				released:FireClient(player :: Player, actorId, why)
			end
		end,
		onHandoff = function(actor: any, player: any?, kind: "possess" | "release")
			if movement and movement.onHandoff then
				movement:onHandoff(actor, player, kind)
			end
		end,
		onTeleport = function(actor: any, x: number, y: number, z: number, why: string)
			if movement and movement.teleported and (actor.species == "squirrel" or actor.species == "rodent") then
				local okH, hip = pcall(function()
					return actor.body:GetAttribute("HipHeight")
				end)
				local feet = y - (if okH and type(hip) == "number" then hip else 0)
				movement:teleported(actor.id, x, feet, z, why, workspace:GetServerTimeNow())
			end
		end,
		safePose = function(actor: any): (number, number, number, number)
			local x, y, z, yaw = actors:poseOf(actor)
			local okH, hip = pcall(function()
				return actor.body:GetAttribute("HipHeight")
			end)
			local lift = if okH and type(hip) == "number" then hip else 0
			if movement and movement.safeTarget and (actor.species == "squirrel" or actor.species == "rodent") then
				-- a held squirrel: only where the validator accepted a clean grounded packet over a floor (the server's
				-- own ray), the feet on that floor, never 3 st over it; or the river's quay (validator round 7: the raw
				-- root was recorded as safe, and a Reset put the body 3 st over it, again and again, into the air)
				local fx, fy, fz = movement:safeTarget(actor.id)
				if fx and fy and fz then
					return fx, fy + lift, fz, yaw
				end
				return x, y, z, yaw -- (no place the server holds: left where it is, no lift)
			end
			local h = history[actor.id]
			local rx, ry, rz = x, y + 3, z
			if h then
				local tx, ty, tz = Recovery.resetTarget(h, x, y, z)
				rx, ry, rz = tx, ty + 3, tz
			else
				local qx, qy, qz = Recovery.riverFall(x, y, z)
				if qx and qy and qz then
					rx, ry, rz = qx, qy + 3, qz
				end
			end
			return rx, ry, rz, yaw
		end,
	})

	-- a body the AI holds and that is possessable right now (not a patient on the ground, in an ambulance or in a
	-- hospital bed: Infection/InfectionService); pickFree never offers a street rider (AI_ONLY)
	local function free(a: any): boolean
		local actor = byTownId[a.id]
		return actor.possessable ~= false and possession:controllerOf(actor) == "ai"
	end
	local function freeOf(species: string, variant: string?, near: Vector3?): any?
		local a = ActorsRuntime.pickFree(world.actors, free, species, variant, near)
		return if a then byTownId[a.id] else nil
	end

	local function pickBody(player: any, rung: string?): any?
		local species, variant = ActorsRuntime.speciesForRung(rung)
		local near: Vector3? = nil
		local current = possession:actorOf(player)
		if current then
			near = (current.body :: Model):GetPivot().Position
		end
		return freeOf(species, variant, near)
	end

	local roles: any? = nil
	local okRoles, RoleService = pcall(function()
		return opts.roles or require("../Roles/RoleService") :: any
	end)
	if okRoles and RoleService then
		roles = RoleService.new({ possession = possession, pickBody = pickBody, purse = opts.purse })
	end

	local devices: any? = nil
	if opts.devices ~= false then
		devices = DeviceService.start({
			net = net :: Folder,
			speciesOf = function(player: Player): string?
				local a = possession:actorOf(player)
				return if a then a.species else nil
			end,
			bodyOf = function(player: Player): Model?
				local a = possession:actorOf(player)
				return if a then a.body else nil
			end,
			placements = DeviceService.defaultPlacements(data),
		})
	end

	local function become(player: any, species: string, variant: string?): (boolean, string?)
		local target = freeOf(species, variant, nil)
		if target == nil then
			return false, `no free {species}`
		end
		if possession:actorOf(player) then
			if devices then
				devices:exitAll(player)
			end
			return possession:swap(player, target)
		end
		return possession:possess(player, target)
	end

	local parts: { BasePart } = {}
	local cfs: { CFrame } = {}
	local lastAttr = 0
	local function step(dt: number)
		TownAI.stepFrame(world, math.min(dt, 0.1))
		table.clear(parts)
		table.clear(cfs)
		local now = os.clock()
		local writeAttrs = now - lastAttr > 0.25
		if writeAttrs then
			lastAttr = now
		end
		for _, a in world.actors do
			local actor = byTownId[a.id]
			if actor.mode == "ai" then
				table.insert(parts, roots[a.id])
				-- `lift` sinks a hidden patient out of sight (Infection/InfectionService.SINK)
				table.insert(
					cfs,
					Units.yawCFrame(a.yaw, Vector3.new(a.x, a.y - a.hip + offsets[a.id] + (a.lift or 0), a.z))
				)
				if writeAttrs then
					local body = actor.body :: Model
					body:SetAttribute(PossessionState.ATTR.Speed, math.floor(a.speed * 10 + 0.5) / 10)
					body:SetAttribute(
						PossessionState.ATTR.MoveState,
						if a.speed < 0.3 then "idle" elseif a.speed < 9 then "walk" else "run"
					)
					-- a member of staff at work (Brains/Staff work stops: the alley's employees); nil otherwise
					if body:GetAttribute("Task") ~= a.task then
						body:SetAttribute("Task", a.task)
					end
				end
			else
				local r = roots[a.id]
				local p = r.Position
				-- the held body's pose feeds the AI world (perception: people spot and flee a held
				-- rodent; traffic yields to and sweeps held squirrels); the brain stays suspended
				local v = r.AssemblyLinearVelocity
				a.x, a.z = p.X, p.Z
				a.y = p.Y - offsets[a.id] + a.hip
				a.speed = math.sqrt(v.X * v.X + v.Z * v.Z)
				local h = history[actor.id]
				if h == nil then
					h = Recovery.newHistory()
					history[actor.id] = h
				end
				Recovery.record(
					h,
					now,
					p.X,
					p.Y,
					p.Z,
					r.AssemblyLinearVelocity.Y > -1
						and r.AssemblyLinearVelocity.Y < 1
						and (actor.body :: Model):GetAttribute("Ride") == nil -- a sky-lift seat is not safe ground
				)
				local qx = Recovery.riverFall(p.X, p.Y, p.Z)
				if qx or not Recovery.isSane(p.X, p.Y, p.Z) then
					local driver = possession:controllerOf(actor)
					if driver ~= "ai" then
						possession:recover(driver)
					end
				end
			end
		end
		if #parts > 0 then
			workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
		end
	end

	TownAI.setFocus(world, function()
		local out = {}
		for _, p in Players:GetPlayers() do
			local c = p.Character
			if c then
				local pos = c:GetPivot().Position
				table.insert(out, { x = pos.X, z = pos.Z })
			end
		end
		return out
	end)

	local conns: { RBXScriptConnection } = {}
	table.insert(conns, RunService.Heartbeat:Connect(step))
	table.insert(
		conns,
		recover.OnServerEvent:Connect(function(player: Player)
			possession:recover(player)
		end)
	)
	if opts.players ~= false then
		local function join(player: Player)
			if roles then
				roles:onJoin(player)
			else
				local body = pickBody(player, nil)
				if body then
					possession:possess(player, body)
				end
			end
		end
		table.insert(conns, Players.PlayerAdded:Connect(join))
		for _, p in Players:GetPlayers() do
			task.spawn(join, p)
		end
		table.insert(
			conns,
			Players.PlayerRemoving:Connect(function(player: Player)
				if devices then
					devices:exitAll(player)
				end
				if roles then
					roles:onLeave(player)
				else
					possession:release(player, "left")
				end
			end)
		)
	end

	return {
		world = world,
		actors = actors,
		possession = possession,
		roles = roles,
		devices = devices,
		bodies = bodies :: Folder,
		byTownId = byTownId,
		pickBody = pickBody,
		become = become,
		step = step,
		stop = function()
			for _, c in conns do
				c:Disconnect()
			end
		end,
	}
end

return ActorsRuntime
