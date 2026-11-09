--!strict
-- ServerScriptService.Server.Boot.Game
-- The first playable build (owner directive 2026-11-09, docs/owner/PLAY_FIRST_BUILD.md): assembles what
-- W0 and W1 built into one game. Boot, in order, publishing progress for the client's loading screen
-- (ReplicatedStorage attributes BootStage, BootProgress, BootReady, BootError):
--   1. Lighting: World/LightingPreset (the v5.4 golden preset as pleasant daylight).
--   2. Terrain: WorldGen/WorldTerrain (river, roads, hills, beach; Workspace.Town is baked into the place).
--   3. Data, TrafficService (25 AI vehicles on the lanes; the exact swept test), MovementService
--      (log-only validator, rule 12 seams: onHandoff marks the actor teleported in the traffic sweep).
--   4. Actors/ActorsRuntime: 102 bodies (people, squirrels, deer, the fox, the rodent), Possession,
--      RoleService (the 49 cap and the Ladder stay in force: a joining player is a townsperson, the
--      50th is turned away), the device fleet (patrol cars, carts, bikes, the drone).
--   5. ReplicatedStorage.PlayNet remotes: Pick(choice) from the menu, Kick() (townsperson F), Event
--      (server -> client: picked, refused, bite, bitten, hurt, died, kick).
-- Every frame: ActorsRuntime steps the AI (its own Heartbeat); here traffic steps at 30 Hz against the
-- people and the player-held squirrels (RunOver kills: "RUN OVER"), poses stream to clients at 15 Hz
-- (Net VehiclePoses, rendered by Client/Render/VehicleView), the rodent bites people it touches
-- (Combat/PlayRules; Power per Rodent/PowerRules, brief v2 §15), Power fades while playing.
-- Engine only inside the functions; no side effects on require.
-- Interface: start(opts?) -> Game { runtime, traffic, movement, pick(player, choice) -> (ok, why?),
--   kick(player) -> (hit?), kill(actor, cause), step(dt), stateOf(player), health(actorId), stop() }

local Import = require("../Import")
local Data = Import.shared("Data") :: typeof(require("../../shared/Data"))
local Height = Import.shared("World/Height") :: typeof(require("../../shared/World/Height"))
local LightingPreset = Import.shared("World/LightingPreset") :: typeof(require("../../shared/World/LightingPreset"))
local PlayRules = Import.shared("Combat/PlayRules") :: typeof(require("../../shared/Combat/PlayRules"))
local PowerRules = Import.shared("Rodent/PowerRules") :: typeof(require("../../shared/Rodent/PowerRules"))
local Net = Import.shared("Net/Net") :: typeof(require("../../shared/Net/Net"))
local Units = Import.shared("Config/Units") :: typeof(require("../../shared/Config/Units"))
local PlayerVehicles =
	Import.shared("Vehicles/PlayerVehicles") :: typeof(require("../../shared/Vehicles/PlayerVehicles"))
local ActorsRuntime = require("../Actors/ActorsRuntime")
local TrafficService = require("../Traffic/TrafficService")
local MovementService = require("../Movement/MovementService")

export type Opts = {
	players: boolean?, -- connect joins (default true; the engine smoke drives PlayerLike stubs)
	engine: any?, -- Possession.Engine override (smoke)
	heartbeat: boolean?, -- connect Heartbeat loops (default true; false = step(dt) by hand)
	terrain: boolean?, -- write terrain (default true)
	net: boolean?, -- create ReplicatedStorage.Net and stream poses (default true)
}

local Game = {}

Game.CHOICES = table.freeze({ "rodent", "squirrel", "townsperson", "police", "drone" })
Game.PICK_COOLDOWN = 0.75

type PState = {
	role: string?,
	power: any, -- Rodent/PowerRules.State (types do not cross Import)
	bites: number,
	lastKick: number,
	lastPick: number,
}

local function setAttr(player: any, key: string, value: any)
	if typeof(player) == "Instance" then
		(player :: Instance):SetAttribute(key, value)
	elseif type(player) == "table" then
		player.attrs = player.attrs or {}
		player.attrs[key] = value
	end
end

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

local function shoutAt(body: Model, text: string)
	local anchor = body:FindFirstChild("Head") or body.PrimaryPart
	if anchor == nil then
		return
	end
	local old = anchor:FindFirstChild("Shout")
	if old then
		old:Destroy()
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "Shout"
	gui.Size = UDim2.fromOffset(240, 44)
	gui.StudsOffset = Vector3.new(0, 3, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 150
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.new(1, 1, 1)
	label.BackgroundTransparency = 0.1
	label.TextColor3 = Color3.fromRGB(30, 30, 30)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.Text = text
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = label
	label.Parent = gui
	gui.Parent = anchor
	task.delay(2.5, function()
		gui:Destroy()
	end)
end

function Game.start(opts: Opts?): any
	local o: Opts = opts or {}
	local Players = game:GetService("Players")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local RunService = game:GetService("RunService")
	local HttpService = game:GetService("HttpService")

	local function stage(p: number, text: string)
		ReplicatedStorage:SetAttribute("BootProgress", p)
		ReplicatedStorage:SetAttribute("BootStage", text)
		print(`[SpicyRodents] {math.floor(p * 100 + 0.5)}% {text}`)
	end
	ReplicatedStorage:SetAttribute("BootReady", false)
	local t0 = os.clock()
	local timings: { [string]: number } = {}
	local function mark(name: string, since: number)
		timings[name] = math.floor((os.clock() - since) * 1000) / 1000
	end

	-- 1. sky ------------------------------------------------------------------------------------
	stage(0.03, "Setting up the sky and the afternoon sun")
	LightingPreset.apply(game:GetService("Lighting"))
	local town = workspace:FindFirstChild("Town")
	local townParts = 0
	if town then
		for _, d in town:GetDescendants() do
			if d:IsA("BasePart") then
				townParts += 1
			end
		end
	end
	stage(0.08, `Town model: {townParts} parts{if town then "" else " (MISSING: rebuild with build/Town.rbxm)"}`)

	-- 2. terrain --------------------------------------------------------------------------------
	local tt = os.clock()
	if o.terrain ~= false then
		stage(0.12, "Shaping the ground, the river, the hills and the beach (a few seconds)")
		local server = script.Parent and script.Parent.Parent
		local worldGen = server and server:FindFirstChild("WorldGen")
		local mod = worldGen and worldGen:FindFirstChild("WorldTerrain")
		if mod and mod:IsA("ModuleScript") then
			local WorldTerrain = (require :: any)(mod)
			WorldTerrain.write(workspace.Terrain)
		else
			warn("[SpicyRodents] WorldGen.WorldTerrain missing: no terrain")
		end
	end
	mark("terrain", tt)

	-- 3. data, traffic, movement ------------------------------------------------------------------
	stage(0.45, "Reading the town data: lots, roads, lanes, 1,332 climbing routes")
	local td = os.clock()
	local data = Data.default()
	mark("data", td)
	stage(0.52, "Putting 25 cars on the roads")
	local traffic = TrafficService.new({ lanes = data:lanes(), roads = data:roads(), heightAt = Height.at, seed = 7 })
	local movement = MovementService.new({ swept = traffic :: any })
	local net: any? = nil
	if o.net ~= false then
		net = Net.engineServer()
	end

	-- PlayNet remotes before the runtime connects joins, so a client can wait on them
	local playNet = ReplicatedStorage:FindFirstChild("PlayNet") or Instance.new("Folder")
	playNet.Name = "PlayNet"
	playNet.Parent = ReplicatedStorage
	local pickRemote = remote(playNet, "Pick")
	local kickRemote = remote(playNet, "Kick")
	local eventRemote = remote(playNet, "Event")
	local kindsJson: { [string]: any } = {}
	for id, k in traffic:kinds() do
		kindsJson[tostring(id)] = k
	end
	playNet:SetAttribute("TrafficKinds", HttpService:JSONEncode(kindsJson))

	-- 4. actors -----------------------------------------------------------------------------------
	stage(0.6, "Waking up the town: 102 people and animals")
	local ta = os.clock()
	local rt = ActorsRuntime.start({
		data = data,
		movement = movement,
		engine = o.engine,
		players = o.players,
	})
	if o.heartbeat == false then
		rt.stop() -- the smoke steps frames by hand
	end
	mark("actors", ta)
	stage(0.92, "Parking the patrol cars and the police drone")

	local world = rt.world
	local possession = rt.possession
	local devices = rt.devices
	local townIdOf: { [string]: number } = {}
	local spawn: { [number]: { number } } = {}
	for townId, actor in rt.byTownId do
		townIdOf[actor.id] = townId
	end
	for _, a in world.actors do
		spawn[a.id] = { a.x, a.y, a.z, a.yaw }
	end
	local health: { [string]: number } = {}
	local states: { [any]: PState } = {}
	local lastBitten: { [any]: number } = {}
	local shoutN = 0
	local now = 0

	local function fire(player: any, payload: { [string]: any })
		if typeof(player) == "Instance" and (player :: Instance).Parent == Players then
			eventRemote:FireClient(player :: Player, payload)
		end
	end

	local function stateOf(player: any): PState
		local s = states[player]
		if s == nil then
			s = { role = nil, power = PowerRules.new(), bites = 0, lastKick = -math.huge, lastPick = -math.huge }
			states[player] = s
		end
		return s
	end

	local function isSquirrelFamily(actor: any): boolean
		return actor.species == "squirrel" or actor.species == "rodent"
	end

	local function healthOf(actorId: string): number
		return health[actorId] or PlayRules.HEALTH
	end

	local function publish(player: any)
		local s = stateOf(player)
		setAttr(player, "PlayRole", s.role)
		setAttr(player, "Bites", s.bites)
		setAttr(player, "Power", s.power.points)
		setAttr(player, "PowerStage", PowerRules.stage(s.power.points))
		local actor = possession:actorOf(player)
		setAttr(player, "Health", if actor and isSquirrelFamily(actor) then healthOf(actor.id) else nil)
	end

	local function groundY(x: number, z: number): number
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { rt.bodies, workspace:FindFirstChild("Vehicles") :: Instance }
		local hit = workspace:Raycast(Vector3.new(x, 400, z), Vector3.new(0, -800, 0), params)
		return if hit then hit.Position.Y else Height.at(x, z)
	end

	-- move an AI body (world actor + model) so streaming and the snapshot happen at the destination
	local function placeAI(actor: any, x: number, z: number, yaw: number)
		local townId = townIdOf[actor.id]
		local a = world.actorsById[townId]
		local body = actor.body :: Model
		local gy = groundY(x, z)
		local size = body:GetExtentsSize()
		if a then
			a.x, a.z = x, z
			a.y = gy + a.hip
			a.yaw = yaw
		end
		body:PivotTo(Units.yawCFrame(yaw, Vector3.new(x, gy + size.Y * 0.5 + 0.1, z)))
	end

	local function freeOfficer(): any?
		local fallback = nil
		for _, a in world.actors do
			local actor = rt.byTownId[a.id]
			if a.species == "human" and possession:controllerOf(actor) == "ai" then
				if a.post == "police" then
					return actor
				end
				fallback = fallback or actor
			end
		end
		return fallback
	end

	local function deviceModel(prefix: string): Model?
		if devices == nil then
			return nil
		end
		local ids = {}
		for id in devices.models do
			if string.sub(id, 1, #prefix) == prefix then
				table.insert(ids, id)
			end
		end
		table.sort(ids)
		for _, id in ids do
			local v = if prefix == "drone_" then nil else PlayerVehicles.get(devices.fleet, id)
			if v == nil or v.driver == nil then
				return devices.models[id]
			end
		end
		return nil
	end

	local function takeBody(player: any, target: any): (boolean, string?)
		if possession:actorOf(player) then
			if devices and typeof(player) == "Instance" then
				devices:exitAll(player)
			end
			return possession:swap(player, target)
		end
		return possession:possess(player, target)
	end

	local function pick(player: any, choice: any): (boolean, string?)
		if type(choice) ~= "string" or table.find(Game.CHOICES, choice) == nil then
			return false, "unknown choice"
		end
		local s = stateOf(player)
		local clock = os.clock()
		if clock - s.lastPick < Game.PICK_COOLDOWN then
			return false, "one moment…"
		end
		s.lastPick = clock
		local current = possession:actorOf(player)
		local ok, why = false, nil :: string?
		if choice == "rodent" or choice == "squirrel" then
			local variant = if choice == "rodent" then "spicy" else "normal"
			if current and current.species == "squirrel" and current.variant == variant then
				ok = true
			else
				ok, why = rt.become(player, "squirrel", variant)
			end
		elseif choice == "townsperson" then
			if current and current.species == "human" and s.role == "townsperson" then
				ok = true
			else
				ok, why = rt.become(player, "human", nil)
			end
		else -- police, drone
			local officer = if current
					and current.species == "human"
					and (s.role == "police" or s.role == "drone")
				then current
				else freeOfficer()
			local target = deviceModel(if choice == "drone" then "drone_" else "car_")
			if officer == nil then
				return false, "no free officer"
			end
			local root = if target then target.PrimaryPart else nil
			local spot: Vector3? = nil
			local yaw = 0
			if root then
				local width = (target :: Model):GetExtentsSize().X
				spot = if choice == "drone"
					then root.Position + Vector3.new(0, 0, -3)
					else root.Position - root.CFrame.RightVector * (width * 0.5 + 3)
				yaw = math.atan2(root.CFrame.LookVector.X, root.CFrame.LookVector.Z)
			end
			if officer ~= current then
				if spot then
					placeAI(officer, spot.X, spot.Z, yaw)
				end
				ok, why = takeBody(player, officer)
			else
				if devices and typeof(player) == "Instance" then
					devices:exitAll(player)
				end
				ok = true
			end
			if ok and spot then
				local body = officer.body :: Model
				body:PivotTo(CFrame.new(spot.X, groundY(spot.X, spot.Z) + 3.5, spot.Z))
			end
			if ok and choice == "drone" and devices and typeof(player) == "Instance" then
				local held = officer
				task.delay(1.0, function()
					if possession:actorOf(player) == held then
						local launched, reason = devices:interact(player :: Player)
						if not launched then
							fire(player, { kind = "refused", text = `The drone did not launch: {reason}` })
						end
					end
				end)
			end
		end
		if ok then
			s.role = choice
			local actor = possession:actorOf(player)
			if actor and isSquirrelFamily(actor) then
				health[actor.id] = PlayRules.HEALTH
			end
			publish(player)
			fire(player, { kind = "picked", role = choice })
		else
			fire(player, { kind = "refused", text = why or "that body is busy" })
		end
		return ok, why
	end

	-- a squirrel-family actor is knocked out: its player (if any) is told and released to the menu;
	-- the body goes back to the AI at its spawn with full health (bodies are never destroyed, D1)
	local function kill(actor: any, cause: string)
		local driver = possession:controllerOf(actor)
		health[actor.id] = PlayRules.HEALTH
		if driver ~= "ai" and driver ~= nil then
			local title, line = PlayRules.deathMessage(cause)
			fire(driver, { kind = "died", cause = cause, title = title, line = line })
			local s = stateOf(driver)
			s.role = nil
			possession:release(driver, if cause == "traffic" then "run over" else "knocked out")
			publish(driver)
		end
		local townId = townIdOf[actor.id]
		local sp = spawn[townId]
		local a = world.actorsById[townId]
		if sp and a and actor.mode == "ai" then
			a.x, a.y, a.z = sp[1], sp[2], sp[3]
		end
	end

	local function kick(player: any): boolean?
		local s = stateOf(player)
		local clock = os.clock()
		if clock - s.lastKick < PlayRules.KICK_COOLDOWN then
			return nil
		end
		s.lastKick = clock
		local actor = possession:actorOf(player)
		if actor == nil or actor.species ~= "human" then
			return nil
		end
		if devices and type(player.UserId) == "number" and PlayerVehicles.vehicleOf(devices.fleet, player.UserId) then
			return nil
		end
		local root = (actor.body :: Model).PrimaryPart
		if root == nil then
			return nil
		end
		local p = root.Position
		local look = root.CFrame.LookVector
		local targets = {}
		local byId: { [string]: any } = {}
		for _, a in world.actors do
			local other = rt.byTownId[a.id]
			if isSquirrelFamily(other) then
				local r = (other.body :: Model).PrimaryPart
				if r then
					local q = r.Position
					table.insert(targets, { id = other.id, x = q.X, y = q.Y, z = q.Z })
					byId[other.id] = other
				end
			end
		end
		local hitId = PlayRules.kickTarget(
			{ id = actor.id, x = p.X, y = p.Y, z = p.Z },
			{ x = look.X, z = look.Z },
			targets
		)
		if hitId == nil then
			fire(player, { kind = "kick", hit = false })
			return false
		end
		local target = byId[hitId]
		local h, dead = PlayRules.damage(healthOf(hitId), PlayRules.KICK_DAMAGE)
		health[hitId] = h
		fire(player, {
			kind = "kick",
			hit = true,
			target = if target.variant == "spicy" then "rodent" else "squirrel",
			health = h,
		})
		local driver = possession:controllerOf(target)
		if driver ~= "ai" and driver ~= nil then
			local ds = stateOf(driver)
			if target.variant == "spicy" then
				PowerRules.apply(ds.power, { kind = "pedestrianKick" })
			end
			publish(driver)
			fire(driver, { kind = "hurt", by = "kick", health = h })
		else
			-- knock the AI body back a few studs
			local a = world.actorsById[townIdOf[hitId]]
			if a then
				a.x += look.X * 4
				a.z += look.Z * 4
			end
		end
		if dead then
			kill(target, "kick")
		end
		return true
	end

	traffic.RunOver:connect(function(actorId: any, _vehicle: any)
		local actor = rt.actors:get(actorId)
		if actor and possession:controllerOf(actor) ~= "ai" then
			kill(actor, "traffic")
		end
	end)

	-- the traffic world: people (AI and held humans) and the player-held squirrels (fatal sweep)
	local people: { { [string]: any } } = {}
	local squirrels: { { [string]: any } } = {}
	local function trafficWorld(): { [string]: any }
		table.clear(squirrels)
		local n = 0
		for _, a in world.actors do
			local actor = rt.byTownId[a.id]
			if a.species == "human" then
				n += 1
				local rec = people[n]
				if rec == nil then
					rec = { kind = "human" }
					people[n] = rec
				end
				rec.x, rec.y, rec.z = a.x, a.y - a.hip, a.z
			elseif isSquirrelFamily(actor) and actor.mode ~= "ai" then
				table.insert(squirrels, { id = actor.id, x = a.x, y = a.y - a.hip, z = a.z })
			end
		end
		for i = #people, n + 1, -1 do
			people[i] = nil
		end
		return { people = people, squirrels = squirrels }
	end

	local function bites()
		local humans = nil
		for player, s in states do
			local actor = possession:actorOf(player)
			if s.role == "rodent" and actor and actor.variant == "spicy" then
				local root = (actor.body :: Model).PrimaryPart
				if root then
					if humans == nil then
						humans = {}
						for _, a in world.actors do
							if a.species == "human" then
								local other = rt.byTownId[a.id]
								local r = (other.body :: Model).PrimaryPart
								if r then
									local q = r.Position
									table.insert(humans, { id = other.id, x = q.X, y = q.Y, z = q.Z, townId = a.id })
								end
							end
						end
					end
					local p = root.Position
					local victims = PlayRules.biteVictims(
						{ id = actor.id, x = p.X, y = p.Y, z = p.Z },
						humans :: any,
						now,
						lastBitten
					)
					for _, vid in victims do
						local victim = rt.actors:get(vid)
						local vt = townIdOf[vid]
						local va = world.actorsById[vt]
						local officer = va ~= nil and va.post == "police"
						local delta = PowerRules.apply(
							s.power,
							{ kind = if officer then "biteOfficer" else "bitePerson", y = Units.u(p.Y) }
						)
						s.bites += 1
						shoutN += 1
						local line = PlayRules.shout(shoutN)
						if victim then
							shoutAt(victim.body, line)
						end
						local driver = if victim then possession:controllerOf(victim) else "ai"
						if driver == "ai" then
							local brain = world.brains[vt] :: any
							local me = world.actorsById[townIdOf[actor.id]]
							if brain and brain.lane and va and me then
								brain.state = "flee"
								brain.threat = me
								va.alert = 8
							end
						elseif driver ~= nil then
							fire(driver, { kind = "bitten", line = line })
						end
						publish(player)
						fire(player, {
							kind = "bite",
							bites = s.bites,
							power = s.power.points,
							delta = delta,
							stage = PowerRules.stage(s.power.points),
							line = line,
						})
					end
				end
			end
		end
	end

	local poseAcc, biteAcc, fadeAcc = 0, 0, 0
	local function step(dt: number)
		now += dt
		local hits = traffic:step(dt, trafficWorld() :: any)
		local _ = hits
		poseAcc += dt
		if net and poseAcc >= 1 / 15 then
			poseAcc = 0
			net:stream(nil, "VehiclePoses", traffic:poseRecords())
		end
		biteAcc += dt
		if biteAcc >= 0.1 then
			biteAcc = 0
			bites()
		end
		fadeAcc += dt
		if fadeAcc >= 1 then
			-- a joining player is handed a townsperson by RoleService (Ladder: lowest rank)
			for _, player in Players:GetPlayers() do
				local actor = possession:actorOf(player)
				local s = stateOf(player)
				if s.role == nil and actor and actor.species == "human" then
					s.role = "townsperson"
					publish(player)
				end
			end
			for player, s in states do
				if s.role == "rodent" then
					if PowerRules.fade(s.power, fadeAcc) > 0 then
						publish(player)
					end
				end
			end
			fadeAcc = 0
		end
	end

	local conns: { RBXScriptConnection } = {}
	table.insert(
		conns,
		pickRemote.OnServerEvent:Connect(function(player: Player, choice: any)
			local ok, err = pcall(function()
				pick(player, choice)
			end)
			if not ok then
				warn(`[SpicyRodents] pick {choice} failed: {err}`)
				fire(player, { kind = "refused", text = "Something went wrong; try again" })
			end
		end)
	)
	table.insert(
		conns,
		kickRemote.OnServerEvent:Connect(function(player: Player)
			local ok, err = pcall(function()
				kick(player)
			end)
			if not ok then
				warn(`[SpicyRodents] kick failed: {err}`)
			end
		end)
	)
	table.insert(
		conns,
		Players.PlayerRemoving:Connect(function(player: Player)
			states[player] = nil
		end)
	)
	if o.heartbeat ~= false then
		table.insert(
			conns,
			RunService.Heartbeat:Connect(function(dt: number)
				local ok, err = pcall(function()
					step(math.min(dt, 0.1))
				end)
				if not ok then
					warn(`[SpicyRodents] step failed: {err}`)
				end
			end)
		)
	end

	mark("total", t0)
	ReplicatedStorage:SetAttribute("BootSeconds", timings.total)
	stage(1, "Ready")
	ReplicatedStorage:SetAttribute("BootReady", true)

	return {
		runtime = rt,
		traffic = traffic,
		movement = movement,
		timings = timings,
		pick = pick,
		kick = kick,
		kill = kill,
		step = function(dt: number)
			rt.step(dt)
			step(dt)
		end,
		stateOf = stateOf,
		health = healthOf,
		placeAI = placeAI,
		stop = function()
			rt.stop()
			for _, c in conns do
				c:Disconnect()
			end
		end,
	}
end

return Game
