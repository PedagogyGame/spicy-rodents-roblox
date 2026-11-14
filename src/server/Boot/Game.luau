--!strict
-- ServerScriptService.Server.Boot.Game
-- The first playable build (owner directive 2026-11-09, docs/owner/PLAY_FIRST_BUILD.md): assembles what
-- W0 and W1 built into one game. Boot, in order, publishing progress for the client's loading screen
-- (ReplicatedStorage attributes BootStage, BootProgress, BootReady, BootError):
--   1. Lighting: World/LightingPreset (the v5.4 golden preset as pleasant daylight); Boot/DayClock publishes the
--      day clock (ClockEpoch/Base/Rate attributes) that every client turns into the day cycle (Client/World/Sky).
--   2. Terrain: WorldGen/WorldTerrain (river, roads, hills, beach; Workspace.Town is baked into the place), then
--      WorldGen/BackdropTerrain (the band beyond the world clamp, the coast and the near sea; Workspace.Backdrop
--      is baked into the place too).
--   3. Data, TrafficService (25 AI vehicles on the lanes; the exact swept test), MovementService
--      (log-only validator, rule 12 seams: onHandoff marks the actor teleported in the traffic sweep).
--   4. Actors/ActorsRuntime: 102 bodies (people, squirrels, deer, the fox, the rodent), Possession,
--      RoleService (the 49 cap and the Ladder stay in force: a joining player is a townsperson, the
--      50th is turned away), the device fleet (patrol cars, carts, bikes, the drone).
--   5. ReplicatedStorage.PlayNet remotes: Pick(choice) from the menu, Kick() (townsperson F), Event
--      (server -> client: picked, refused, bite, bitten, med, hurt, died, kick).
-- Every frame: ActorsRuntime steps the AI (its own Heartbeat); here traffic steps at 30 Hz against the
-- people and the player-held squirrels (RunOver kills: "RUN OVER"), poses stream to clients at 15 Hz
-- (Net VehiclePoses, rendered by Client/Render/VehicleView), the rodent bites people it touches
-- (Combat/PlayRules; Power per Rodent/PowerRules, brief v2 §15), Power fades while playing.
-- A bite starts the bite-to-hospital sequence (owner 2026-11-10; Infection/InfectionService, stepped
-- here after traffic): the person is infected and runs, collapses at once or shows symptoms later,
-- an ambulance and a crowd come or they walk in, and the hospital is the only cure. The service
-- writes the Med, Say and SayAt attributes on the bodies (clients draw the red eyes, the poses and
-- the speech bubbles) and sends the player holding a bitten body a "med" event that says what to do;
-- the same thing stays on screen through the player attribute Infected ("infected" | "symptoms" |
-- "treating"; UI/PlayMenu draws a line under the status), refreshed once a second.
-- Knocking the rodent out cures nobody (the old brief v2 §8 instant cure is off: Tunables
-- infection.recentBiteSecs = 0).
-- A patient (on the ground, in the ambulance, in a bed) is not possessable: Police and Drone picks
-- skip such an officer (pickOfficer), and an officer who is moved to the patrol car for a pick that
-- is then refused is put back where they were.
-- Streaming and input (W1 client review): the device fleet (patrol cars, carts, bikes, the drone) is
-- ModelStreamingMode Persistent, so a DeviceGranted model is never nil on the driver's client; the body a
-- player holds is PersistentPerPlayer for that player (persist), so the client always finds its body;
-- Shift Lock is off (StarterPlayer.EnableMouseLockOption, Player.DevEnableMouseLock) because Shift is
-- sprint. A "picked" event carries a `note` when the police car or the drone was not free.
-- Money (Economy/Credits, the town's one wallet): Game.wallet(deps) makes it on the day clock with every hook
-- the game hangs on it, and start() only plugs those hooks in (so the wiring itself is driven by a spec on a
-- fake engine: tests/isolated/wallet.luau). A joining player gets an account and pocket money when
-- RoleService asks for their purse (ActorsRuntime opts.purse = hooks.purse: join, then the wallet's face),
-- with the once-a-second sweep as the safety net; a leaving player's account is closed and kept; the
-- minigames' ctx.town.charge is wallet.spend and ctx.town.pass is wallet.pass; wallet.tell(player, words) is
-- the "notice" toast on that player's screen. Every later shop, door and counter takes this same `wallet`.
-- Engine only inside the functions; no side effects on require.
-- Interface: start(opts?) -> Game { runtime, traffic, movement, wallet (Economy/Credits: spend, add, balance,
--   pass), pick(player, choice) -> (ok, why?),
--   kick(player) -> (hit?), remotes { Pick(player, choice), Kick(player) } (the PlayNet handlers),
--   kill(actor, cause), step(dt), stateOf(player), health(actorId), attractions (Server/Attractions:
--   the bowling alley's MinigameService; nil without Workspace.Attractions), infection (Infection/
--   InfectionService; nil when it could not start), skylift (Rides/SkyLiftService; nil when it could not
--   start), townIdOf(actorId), stop() };
--   pickOfficer(people) -> actor? (pure); refusalText(why) -> string (pure);
--   putBack(free, possessable) -> boolean (pure); gameSeconds(serverTime, epoch, base, rate) (pure);
--   wallet(deps: WalletDeps) -> WalletHooks { wallet, purse(player), sweep(), leave(player), charge(player,
--   cents, why), pass } (the town's wallet as start() wires it; no engine but what deps hands in)
-- For a bitten player the hospital's door is published as the Workspace attribute HospitalDoor (a
-- Vector3): the client draws a marker over it and the distance to it (Client/UI/PlayMenu).

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
local VehicleKinds = Import.shared("Vehicles/VehicleKinds") :: typeof(require("../../shared/Vehicles/VehicleKinds"))
local ActorsRuntime = require("../Actors/ActorsRuntime")
local TrafficService = require("../Traffic/TrafficService")
local MovementService = require("../Movement/MovementService")
local AttractionService = require("../Attractions/AttractionService")
local InfectionService = require("../Infection/InfectionService")
local SkyLiftService = require("../Rides/SkyLiftService")
local HospitalProps = require("../Hospital/HospitalProps")
local DayClock = require("./DayClock")
local Credits = require("../Economy/Credits")
local TreeArt = require("../Assets/TreeArt")
local HeroArt = require("../Assets/HeroArt")
local ShopArt = require("../Assets/ShopArt")
local PoseStream = Import.shared("Traffic/PoseStream") :: typeof(require("../../shared/Traffic/PoseStream"))

export type Opts = {
	players: boolean?, -- connect joins (default true; the engine smoke drives PlayerLike stubs)
	engine: any?, -- Possession.Engine override (smoke)
	heartbeat: boolean?, -- connect Heartbeat loops (default true; false = step(dt) by hand)
	terrain: boolean?, -- write terrain (default true)
	heroes: boolean?, -- load the sculpted squirrel and rodent models (default true; false keeps the puppets)
	net: boolean?, -- create ReplicatedStorage.Net and stream poses (default true)
}

local Game = {}

Game.CHOICES = table.freeze({ "rodent", "squirrel", "townsperson", "police", "drone" })
Game.PICK_COOLDOWN = 0.75
Game.FAULT_LIMIT = 60 -- contained faults of the infection service within FAULT_WINDOW that switch it off
Game.FAULT_WINDOW = 60 -- seconds

-- What a player reads when a pick is refused (Actors/Possession's reasons are for the log).
Game.REFUSALS = table.freeze({
	["not possessable"] = "That person has just collapsed and is waiting for an ambulance. Pick again.",
	["body is driven"] = "Someone else is playing that body. Pick again.",
	["body was taken while streaming"] = "Someone else took that body first. Pick again.",
}) :: { [string]: string }

function Game.refusalText(why: string?): string
	return if why then (Game.REFUSALS[why] or why) else "that body is busy"
end

-- putBack(free, possessable): an officer was moved to the patrol car for a pick that was then
-- refused: do they go back where they were? Only while the AI still has the body AND they are still
-- on their feet. One who collapsed during the hand-over (the usual reason for the refusal) fell at
-- the car: the scene, the crowd's places and the ambulance's stop were all worked out there, and
-- moved back the patient sat alone hundreds of studs from their own scene.
function Game.putBack(free: boolean, possessable: boolean): boolean
	return free and possessable
end

export type OfficerCandidate = { actor: any, police: boolean, free: boolean, possessable: boolean }

-- pickOfficer(people): the body for a player who picks Police or the drone: the first police officer
-- who is free (the AI has the body) and possessable (not a patient on the ground, in the ambulance or
-- in a bed: Infection/InfectionService), else the first such person of any post. `people` are the
-- town's humans in their fixed order.
function Game.pickOfficer(people: { OfficerCandidate }): any?
	local fallback = nil
	for _, p in people do
		if p.free and p.possessable then
			if p.police then
				return p.actor
			end
			fallback = fallback or p.actor
		end
	end
	return fallback
end

-- gameSeconds(serverTime, epoch, base, rate): the game clock as Boot/DayClock publishes it (and as
-- Shared/Time/Clock reads it on every client): what the wallet's passes are timed on.
function Game.gameSeconds(serverTime: number, epoch: number, base: number, rate: number): number
	return base + (serverTime - epoch) * rate
end

-- What the town's wallet is wired to: where the day clock is published, the clock both sides share, the
-- game's own way of sending a player an event, and who is in the game.
export type WalletDeps = {
	clock: any, -- the Instance Boot/DayClock published on (ReplicatedStorage): ClockEpoch, ClockBase, ClockRate
	published: { epoch: number, base: number, rate: number }, -- what DayClock.publish answered (read if an attribute is gone)
	serverTime: () -> number, -- workspace:GetServerTimeNow
	fire: (player: any, payload: { [string]: any }) -> (), -- one PlayNet event to one player
	players: () -> { any }, -- Players:GetPlayers
	log: ((line: string) -> ())?, -- (a spec's; default the server's output)
	warn: ((line: string) -> ())?,
}
export type WalletHooks = {
	wallet: Credits.Wallet,
	purse: (player: any) -> Credits.Purse, -- RoleService's: the account is opened (pocket money) and its face handed over
	sweep: () -> (), -- once a second: anyone in the game whose join was missed is joined
	leave: (player: any) -> (), -- PlayerRemoving: closed and kept
	charge: (player: any, cents: number, why: string) -> (boolean, string?), -- the minigames' ctx.town.charge
	pass: Credits.Pass, -- the minigames' ctx.town.pass
}

-- The town's one wallet, as the game runs it: on the game clock (a pass is sold in in-game days; the clock's
-- attributes are read each time, so a re-anchored clock is followed), speaking through the "notice" toast.
-- Nobody is given an account by being charged: only by arriving (purse, sweep). A key that never came
-- through the door (a computer player, a stand-in) is refused with "You have no wallet yet."
function Game.wallet(deps: WalletDeps): WalletHooks
	local function attr(name: string, fallback: number): number
		local v = deps.clock:GetAttribute(name)
		return if type(v) == "number" then v else fallback
	end
	local wallet = Credits.new({
		tell = function(player: any, text: string)
			deps.fire(player, { kind = "notice", text = text })
		end,
		gameSeconds = function(): number
			return Game.gameSeconds(
				deps.serverTime(),
				attr("ClockEpoch", deps.published.epoch),
				attr("ClockBase", deps.published.base),
				attr("ClockRate", deps.published.rate)
			)
		end,
		daySeconds = DayClock.REAL_SECONDS_PER_DAY,
		log = deps.log,
		warn = deps.warn,
	})
	return {
		wallet = wallet,
		purse = function(player: any): Credits.Purse
			wallet.join(player)
			return wallet.purse(player)
		end,
		sweep = function()
			for _, player in deps.players() do
				wallet.join(player) -- (nothing for someone already here)
			end
		end,
		leave = function(player: any)
			wallet.leave(player) -- closed and kept: nothing more can be spent, a refund still lands
		end,
		charge = function(player: any, cents: number, why: string): (boolean, string?)
			return wallet.spend(player, cents, why)
		end,
		pass = wallet.pass,
	}
end

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
	pcall(function()
		(game:GetService("StarterPlayer") :: any).EnableMouseLockOption = false
	end)
	local function noShiftLock(player: Player)
		pcall(function()
			(player :: any).DevEnableMouseLock = false
		end)
	end
	for _, p in Players:GetPlayers() do
		noShiftLock(p)
	end
	local t0 = os.clock()
	local timings: { [string]: number } = {}
	local function mark(name: string, since: number)
		timings[name] = math.floor((os.clock() - since) * 1000) / 1000
	end

	-- 1. sky ------------------------------------------------------------------------------------
	stage(0.03, "Setting up the sky and the afternoon sun")
	LightingPreset.apply(game:GetService("Lighting"))
	local dayClock = DayClock.publish(ReplicatedStorage) -- the day cycle: every client derives it (Client/World/Sky)
	-- the town's one wallet (Game.wallet above has the wiring; the remotes it speaks through come later)
	local fireLater: ((player: any, payload: { [string]: any }) -> ())? = nil
	local money = Game.wallet({
		clock = ReplicatedStorage,
		published = dayClock,
		serverTime = function(): number
			return workspace:GetServerTimeNow()
		end,
		fire = function(player: any, payload: { [string]: any })
			if fireLater then
				fireLater(player, payload)
			end
		end,
		players = function(): { any }
			return Players:GetPlayers()
		end,
	})
	local wallet = money.wallet
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
		-- Roblox's animated grass blades stand as tall as a squirrel's legs and made the animals look
		-- half buried (owner feedback 2026-11-09); v5.4's grass was a flat texture. Terrain.Decoration is
		-- off in the place file (the project files' Workspace.Terrain): a game script may not write it
		-- (it needs the Plugin or Open Cloud capability, which is why the cloud checks never saw this).
		local server = script.Parent and script.Parent.Parent
		local worldGen = server and server:FindFirstChild("WorldGen")
		local mod = worldGen and worldGen:FindFirstChild("WorldTerrain")
		if mod and mod:IsA("ModuleScript") then
			local WorldTerrain = (require :: any)(mod)
			WorldTerrain.write(workspace.Terrain)
			-- the band beyond the world clamp, the north coast and the near sea (WorldGen/BackdropTerrain)
			local backdrop = worldGen and worldGen:FindFirstChild("BackdropTerrain")
			if backdrop and backdrop:IsA("ModuleScript") then
				local ok, err = pcall(function()
					(require :: any)(backdrop).write(workspace.Terrain)
				end)
				if not ok then
					warn(`[SpicyRodents] backdrop terrain failed: {err}`)
				end
			end
			-- the editor-only grass skin (tools/bake/editor_ground) is replaced by the real terrain
			local editorGround = workspace:FindFirstChild("EditorGround")
			if editorGround then
				editorGround:Destroy()
			end
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
	-- the sculpted squirrel and Spicy Rodent, loaded before any body is built (a failed load keeps the
	-- part-built puppet for that animal: Assets/HeroArt)
	if o.heroes ~= false then
		local th = os.clock()
		local okH, report = pcall(HeroArt.install)
		if not okH then
			warn(`[SpicyRodents] hero art failed: {report}`)
		else
			for name, why in (report :: any).failed do
				warn(`[SpicyRodents] hero art: {name} keeps its stand-in body ({why})`)
			end
			playNet:SetAttribute("HeroArt", table.concat((report :: any).installed, ","))
		end
		mark("heroes", th)
	end
	stage(0.6, "Waking up the town: 102 people and animals")
	local ta = os.clock()
	local rt = ActorsRuntime.start({
		data = data,
		movement = movement,
		engine = o.engine,
		players = o.players,
		purse = money.purse, -- RoleService: a joining player's purse is the wallet's (pocket money comes with it)
	})
	if o.heartbeat == false then
		rt.stop() -- the smoke steps frames by hand
	end
	mark("actors", ta)
	stage(0.92, "Parking the patrol cars and the police drone")

	local world = rt.world
	local possession = rt.possession
	local devices = rt.devices
	local skylift: any = nil -- the sky lift (section 6 below): riders are refused a new body, a car and a game
	-- the fleet is small (10 models): always on every client, so E never hands over a nil model
	if devices then
		for _, model in devices.models do
			pcall(function()
				(model :: Model).ModelStreamingMode = Enum.ModelStreamingMode.Persistent
			end)
		end
	end
	-- the held body is always streamed to its driver (PersistentPerPlayer), whatever the radius
	local persisted: { [any]: Model? } = {}
	local function persist(player: any)
		if typeof(player) ~= "Instance" then
			return
		end
		local actor = possession:actorOf(player)
		local body: Model? = if actor then actor.body :: Model else nil
		local old = persisted[player]
		if old == body then
			return
		end
		local ok, err = pcall(function()
			if old and old.Parent then
				old:RemovePersistentPlayer(player :: Player)
			end
			if body then
				body.ModelStreamingMode = Enum.ModelStreamingMode.PersistentPerPlayer
				body:AddPersistentPlayer(player :: Player)
			end
		end)
		if not ok then
			warn(`[SpicyRodents] persist body failed: {err}`)
		end
		persisted[player] = body
	end
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
	local lastSay: { [number]: string } = {} -- town id -> the line last shown over that body
	local sickShown: { [any]: string? } = {} -- player -> the Infected attribute as last written

	local function fire(player: any, payload: { [string]: any })
		if typeof(player) == "Instance" then
			if (player :: Instance).Parent == Players then
				eventRemote:FireClient(player :: Player, payload)
			end
		elseif type(player) == "table" and type(player.events) == "table" then
			table.insert(player.events, payload) -- PlayerLike stub (engine smoke): what the client would get
		end
	end
	fireLater = fire -- wallet.tell: a shop's or a door's words for one player, as the toast every refusal uses

	-- the bite-to-hospital sequence (Infection/InfectionService): built here, stepped in step(dt)
	local infection: any = nil
	local infectionFault: (where: string, err: any) -> ()
	local okI, errI = pcall(function()
		infection = InfectionService.new({
			world = world,
			traffic = traffic,
			data = data,
			controllerOf = function(id: number): string
				local actor = rt.byTownId[id]
				return if actor and possession:controllerOf(actor) ~= "ai" then "player" else "ai"
			end,
			busy = function(id: number): boolean
				local actor = rt.byTownId[id]
				return actor ~= nil and (actor.body :: Model):GetAttribute("Ride") ~= nil
			end,
			setAttr = function(id: number, name: string, value: any)
				local actor = rt.byTownId[id]
				if actor then
					(actor.body :: Model):SetAttribute(name, value)
				end
				if name == "Say" then
					lastSay[id] = value
				end
			end,
			setPossessable = function(id: number, value: boolean)
				local actor = rt.byTownId[id]
				if actor then
					actor.possessable = value
				end
			end,
			notify = function(id: number, payload: { [string]: any })
				local actor = rt.byTownId[id]
				local driver = if actor then possession:controllerOf(actor) else nil
				if driver ~= nil and driver ~= "ai" then
					fire(driver, payload)
				end
			end,
			-- who plays a body now: the service keeps it with each bite, so news about a victim
			-- reaches the player who bit them and not whoever has taken the rodent since
			driverOf = function(id: number): any?
				local actor = rt.byTownId[id]
				local driver = if actor then possession:controllerOf(actor) else nil
				return if driver ~= "ai" then driver else nil
			end,
			serverTime = function(): number
				return workspace:GetServerTimeNow()
			end,
			onFault = function(where: string, err: any)
				infectionFault(where, err)
			end,
		})
	end)
	if not okI then
		infection = nil
		warn(`[SpicyRodents] the infection service did not start (bites still score, nobody falls ill): {errI}`)
	elseif infection.layout then
		-- the cots the patients sit up on (eight, in the two wards); decoration, never fatal
		local okP, errP = pcall(HospitalProps.build, infection.layout)
		if not okP then
			warn(`[SpicyRodents] the hospital cots were not built: {errP}`)
		end
		-- where a bitten player has to go: the client marks the door (UI/PlayMenu)
		local door = infection.layout.entrance
		pcall(function()
			workspace:SetAttribute("HospitalDoor", Vector3.new(door[1], Height.at(door[1], door[2]), door[2]))
		end)
	end
	-- a fault in the sequence must never stop traffic, bites or the pose stream: it is caught where
	-- it is called (the service contains its own parts too and reports them here), warned about the
	-- first few times and, if it keeps failing (FAULT_LIMIT within FAULT_WINDOW seconds), switched
	-- off: every patient is let go where they are (in sight, playable), nobody is cured by it
	local infectionFaults, faultsInWindow, windowStart = 0, 0, 0
	function infectionFault(where: string, err: any)
		infectionFaults += 1
		if infectionFaults <= 5 then
			warn(`[SpicyRodents] infection {where} failed: {err}`)
		end
		if now - windowStart > Game.FAULT_WINDOW then
			windowStart, faultsInWindow = now, 0
		end
		faultsInWindow += 1
		if faultsInWindow >= Game.FAULT_LIMIT and infection ~= nil then
			local dead = infection
			infection = nil
			pcall(dead.shutdown, dead)
			warn("[SpicyRodents] the infection service keeps failing: switched off (bites still score)")
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
		local people: { OfficerCandidate } = {}
		for _, a in world.actors do
			if a.species == "human" then
				local actor = rt.byTownId[a.id]
				table.insert(people, {
					actor = actor,
					police = a.post == "police",
					free = possession:controllerOf(actor) == "ai",
					possessable = actor.possessable ~= false,
				})
			end
		end
		return Game.pickOfficer(people)
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
		local riding = if skylift then skylift:refusal(player, "pick") else nil
		if riding then
			fire(player, { kind = "refused", text = riding })
			return false, "riding"
		end
		local clock = os.clock()
		if clock - s.lastPick < Game.PICK_COOLDOWN then
			return false, "one moment…"
		end
		s.lastPick = clock
		local current = possession:actorOf(player)
		local ok, why = false, nil :: string?
		local noDevice = false
		if choice == "rodent" or choice == "squirrel" then
			local variant = if choice == "rodent" then "spicy" else "normal"
			if current and current.species == "squirrel" and current.variant == variant then
				ok = true
			else
				ok, why = rt.become(player, "squirrel", variant)
				if not ok and why and string.find(why, "no free", 1, true) then
					-- there is one Spicy Rodent in town (brief v2): say so instead of "no free squirrel"
					why = if choice == "rodent"
						then "Someone else is already the Spicy Rodent. Pick another body."
						else "Every squirrel is taken. Pick another body."
				end
			end
		elseif choice == "townsperson" then
			if current and current.species == "human" and s.role == "townsperson" then
				ok = true
			else
				ok, why = rt.become(player, "human", nil)
				if not ok and why and string.find(why, "no free", 1, true) then
					why = "Every townsperson is taken. Pick another body."
				end
			end
		else -- police, drone
			local officer = if current
					and current.species == "human"
					and (s.role == "police" or s.role == "drone")
				then current
				else freeOfficer()
			local target = deviceModel(if choice == "drone" then "drone_" else "car_")
			noDevice = target == nil
			if officer == nil then
				fire(player, { kind = "refused", text = "Every police officer is taken. Pick another body." })
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
				-- the officer is moved to the car first so the client streams that place in before the
				-- hand-over; if the hand-over is then refused they are put back where they were, unless
				-- they collapsed there in the meantime (Game.putBack)
				local at = world.actorsById[townIdOf[officer.id]]
				local bx, bz, byaw = if at then at.x else nil, if at then at.z else nil, if at then at.yaw else 0
				if spot then
					placeAI(officer, spot.X, spot.Z, yaw)
				end
				ok, why = takeBody(player, officer)
				if
					not ok
					and spot
					and bx
					and bz
					and Game.putBack(possession:controllerOf(officer) == "ai", officer.possessable ~= false)
				then
					placeAI(officer, bx, bz, byaw)
				end
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
		persist(player)
		if ok then
			s.role = choice
			local actor = possession:actorOf(player)
			if actor and isSquirrelFamily(actor) then
				health[actor.id] = PlayRules.HEALTH
			end
			publish(player)
			local note = nil
			if choice == "police" and noDevice then
				note = "Every patrol car is in use: you are an officer on foot"
			elseif choice == "drone" and noDevice then
				note = "Someone else is flying the drone: you are an officer on foot"
			end
			fire(player, { kind = "picked", role = choice, note = note })
		else
			fire(player, { kind = "refused", text = Game.refusalText(why) })
		end
		return ok, why
	end

	-- a squirrel-family actor is knocked out: its player (if any) is told and released to the menu;
	-- the body goes back to the AI at its spawn with full health (bodies are never destroyed, D1).
	-- Knocking out the Spicy Rodent cures NOBODY (owner 2026-11-10: the hospital is the only cure;
	-- Tunables infection.recentBiteSecs = 0): the people it bit stay infected until they are treated.
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
			persist(driver)
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
	local cars: { { [string]: any } } = {}
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
				-- AICarMotor's `hospital` flag: the emergency vehicles do not stop for the hospital's
				-- own people or for anyone at a scene; a patient out of sight is nobody's hazard
				rec.hospital = infection ~= nil and infection:trafficFlags(a.id)
				rec.visible = (a.lift or 0) == 0
			elseif isSquirrelFamily(actor) and actor.mode ~= "ai" then
				table.insert(squirrels, { id = actor.id, x = a.x, y = a.y - a.hip, z = a.z })
			end
		end
		for i = #people, n + 1, -1 do
			people[i] = nil
		end
		-- the players' vehicles, parked or driven: the fleet queues behind them (TrafficService.PlayerCar)
		table.clear(cars)
		if devices then
			for id, model in devices.models do
				local v = PlayerVehicles.get(devices.fleet, id)
				local root = (model :: Model).PrimaryPart
				if v and root then
					local size = VehicleKinds.kind(v.kind).size
					local p, look = root.Position, root.CFrame.LookVector
					table.insert(cars, {
						id = id,
						x = p.X,
						z = p.Z,
						yaw = math.atan2(look.X, look.Z),
						width = size[1],
						length = size[3],
						speed = root.AssemblyLinearVelocity.Magnitude,
					})
				end
			end
		end
		return { people = people, squirrels = squirrels, cars = cars }
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
						if infection and not infection:biteable(vt) then
							continue -- a patient on the ground, in the ambulance or in a bed is left alone
						end
						local officer = va ~= nil and va.post == "police"
						local delta = PowerRules.apply(
							s.power,
							{ kind = if officer then "biteOfficer" else "bitePerson", y = Units.u(p.Y) }
						)
						s.bites += 1 -- every client plays the bite on the rodent's body (Animation/AnimationDriver watches this)
						(actor.body :: Model):SetAttribute("BiteAt", now)
						shoutN += 1
						local line = PlayRules.shout(shoutN)
						local driver = if victim then possession:controllerOf(victim) else "ai"
						if infection then
							-- infected: they run and shout (the Say attribute; clients draw the bubble),
							-- and the sequence to the hospital begins. A player holding the victim gets a
							-- "med" event from the service that says what happened and what to do.
							local okB, errB = pcall(infection.bite, infection, vt, townIdOf[actor.id], player)
							if not okB then
								infectionFault("bite", errB)
							end
							line = lastSay[vt] or line
						elseif driver == "ai" then
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

	local biteAcc, fadeAcc = 0, 0
	local function step(dt: number)
		now += dt
		-- the fleet steps, then an even 15 pose sends a second go out stamped with `now`: one call that
		-- the headless replay (tools/sim) makes too, so what it measures is what this server does
		local hits = traffic:frame(dt, now, trafficWorld() :: any, net)
		local _ = hits
		-- the bite-to-hospital sequence steps after the fleet: an ambulance it dispatches or turns round
		-- now is flagged as a jump in the very next pose send (TrafficService remembers jumps between sends)
		if infection then
			local okS, errS = pcall(infection.step, infection, dt)
			if not okS then
				infectionFault("step", errS)
			end
		end
		biteAcc += dt
		if biteAcc >= 0.1 then
			biteAcc = 0
			bites()
		end
		fadeAcc += dt
		if fadeAcc >= 1 then
			money.sweep() -- (everyone joined through RoleService already: this only catches a join that was missed)
			-- a joining player is handed a townsperson by RoleService (Ladder: lowest rank)
			for _, player in Players:GetPlayers() do
				persist(player) -- the join's townsperson and any body change made elsewhere
				local actor = possession:actorOf(player)
				local s = stateOf(player)
				if s.role == nil and actor and actor.species == "human" then
					s.role = "townsperson"
					publish(player)
				end
			end
			-- what a bitten player must do stays on their screen (the toast alone is easily missed)
			for player in states do
				local actor = possession:actorOf(player)
				local townId = if actor then townIdOf[actor.id] else nil
				local status = if infection and townId then infection:statusOf(townId) else nil
				if sickShown[player] ~= status then
					sickShown[player] = status
					setAttr(player, "Infected", status)
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

	-- the remote handlers (the engine smoke calls these with PlayerLike stubs: same path as the menu)
	local function onPick(player: any, choice: any)
		local ok, err = pcall(function()
			pick(player, choice)
		end)
		if not ok then
			warn(`[SpicyRodents] pick {choice} failed: {err}`)
			fire(player, { kind = "refused", text = "Something went wrong; try again" })
		end
	end
	local function onKick(player: any)
		local ok, err = pcall(function()
			kick(player)
		end)
		if not ok then
			warn(`[SpicyRodents] kick failed: {err}`)
		end
	end
	local conns: { RBXScriptConnection } = {}
	table.insert(conns, pickRemote.OnServerEvent:Connect(onPick))
	table.insert(conns, kickRemote.OnServerEvent:Connect(onKick))
	table.insert(
		conns,
		Players.PlayerRemoving:Connect(function(player: Player)
			states[player] = nil
			persisted[player] = nil
			sickShown[player] = nil
			money.leave(player)
		end)
	)
	table.insert(conns, Players.PlayerAdded:Connect(noShiftLock))
	if o.heartbeat ~= false then
		table.insert(
			conns,
			RunService.Heartbeat:Connect(function(dt: number)
				local ok, err = pcall(function()
					step(math.min(dt, PoseStream.MAX_FRAME_DT))
				end)
				if not ok then
					warn(`[SpicyRodents] step failed: {err}`)
				end
			end)
		)
	end

	-- 5. the bowling alley and its minigames (Workspace.Attractions; people only; brief v2 §13a)
	stage(0.96, "Opening the bowling alley")
	local attractions: any = nil
	local okA, errA = pcall(function()
		attractions = AttractionService.start({
			net = net,
			heartbeat = o.heartbeat ~= false,
			terrain = o.terrain ~= false,
			canPlay = function(player: any): (boolean, string?)
				local actor = possession:actorOf(player)
				if actor == nil then
					return false, "Pick a person from the menu first (M)"
				end
				if actor.species ~= "human" then
					return false, "Only people can play. Animals can watch (or sneak through the ball return)"
				end
				local lift = if skylift then skylift:refusal(player, "play") else nil
				if lift then
					return false, lift
				end
				if
					devices
					and type(player.UserId) == "number"
					and PlayerVehicles.vehicleOf(devices.fleet, player.UserId)
				then
					return false, "Get out of the vehicle first (E)"
				end
				return true
			end,
			bodyOf = function(player: any): Model?
				local actor = possession:actorOf(player)
				return if actor then actor.body :: Model else nil
			end,
			-- what the games may ask of the rest of the town (Server/Minigames/ServerGame.Town): `people`, and
			-- `charge` and `pass`, which are the town's wallet and its one pass. There is nobody to lend as a
			-- computer player's body and no profile for a personal best yet, so the service's own stand-ins answer
			-- for those.
			games = {
				charge = money.charge,
				pass = money.pass,
				people = function(): { { [string]: any } }
					local out = {}
					for _, player in Players:GetPlayers() do
						local actor = possession:actorOf(player)
						local body = actor and actor.body :: Model?
						local r = body and body.PrimaryPart
						if actor and r then
							local q = r.Position
							table.insert(out, {
								key = player,
								name = if player.DisplayName ~= "" then player.DisplayName else player.Name,
								species = actor.species,
								x = q.X,
								y = q.Y,
								z = q.Z,
							})
						end
					end
					return out
				end,
			},
			-- squirrels and the Spicy Rodent, wherever they are: a lane in play knocks them off it
			animals = function(): { { [string]: any } }
				local out = {}
				for _, a in world.actors do
					local other = rt.byTownId[a.id]
					if other and isSquirrelFamily(other) then
						local r = (other.body :: Model).PrimaryPart
						if r then
							local q = r.Position
							table.insert(out, {
								id = other.id,
								kind = if other.variant == "spicy" then "rodent" else "squirrel",
								x = q.X,
								y = q.Y,
								z = q.Z,
							})
						end
					end
				end
				return out
			end,
			knock = function(id: any, x: number, y: number, z: number, text: string)
				local townId = townIdOf[id]
				local target = townId and rt.byTownId[townId]
				if target == nil then
					return
				end
				local driver = possession:controllerOf(target)
				if driver ~= "ai" and driver ~= nil then
					-- a player's body: put it there (its controller restarts where it finds itself) and say why
					local body = target.body :: Model
					body:PivotTo(CFrame.new(x, y + 0.6, z) * body:GetPivot().Rotation)
					fire(driver, { kind = "notice", text = text })
				else
					local a = world.actorsById[townId]
					if a then
						a.x, a.z = x, z
					end
				end
			end,
		})
	end)
	if not okA then
		warn(`[SpicyRodents] bowling alley failed to open: {errA}`)
	end

	-- 6. the sky lift up the hill to the Lookout (Workspace.Expansion.F4; people only; brief v2 line 250)
	stage(0.98, "Starting the sky lift")
	local okL, errL = pcall(function()
		skylift = SkyLiftService.start({
			game = {
				possession = possession,
				runtime = rt,
				devices = devices,
				fire = fire,
				attractions = function(): any
					return attractions
				end,
			},
			heartbeat = o.heartbeat ~= false,
			terrain = o.terrain ~= false,
		})
	end)
	if not okL then
		warn(`[SpicyRodents] sky lift failed to start: {errL}`)
	end
	if skylift and devices then
		-- E mid-ride: no car from a cabin (the client says so too); true, so the client is not told "released"
		devices.interact = skylift:guardInteract(devices.interact, function(player: any, text: string)
			fire(player, { kind = "refused", text = text })
		end)
	end

	mark("total", t0)
	ReplicatedStorage:SetAttribute("BootSeconds", timings.total)
	stage(1, "Ready")
	ReplicatedStorage:SetAttribute("BootReady", true)

	-- The trees' normal and roughness maps arrive after the town is playable (each tree already shows
	-- its colour texture): Assets/TreeArt loads the uploaded models one by one, off the boot path.
	if town and o.heartbeat ~= false then
		task.spawn(function()
			local okT, report = pcall(TreeArt.run, town)
			if okT then
				print(
					`[SpicyRodents] tree art: {report.upgraded}/{report.trees} trees with full maps, {report.failed} failed, {math.floor(
						report.seconds
					)} s`
				)
			else
				warn(`[SpicyRodents] tree art failed: {report}`)
			end
		end)
	end

	-- The owner's Neighbourhood Shop (Workspace.Expansion.NeighbourhoodShop, addendum D12): its shell is baked;
	-- Assets/ShopArt carves the terrain inside it and loads his interior and roof off the boot path
	ShopArt.start(
		workspace:FindFirstChild("Expansion"),
		{ terrain = o.terrain ~= false, heartbeat = o.heartbeat ~= false }
	)

	return {
		runtime = rt,
		traffic = traffic,
		movement = movement,
		wallet = wallet,
		timings = timings,
		pick = pick,
		kick = kick,
		remotes = { Pick = onPick, Kick = onKick },
		kill = kill,
		step = function(dt: number)
			rt.step(dt)
			step(dt)
			if attractions and o.heartbeat == false then
				attractions.step(dt)
			end
			if skylift and o.heartbeat == false then
				skylift:step(dt)
			end
		end,
		stateOf = stateOf,
		health = healthOf,
		placeAI = placeAI,
		attractions = attractions,
		infection = infection,
		skylift = skylift,
		townIdOf = function(actorId: string): number?
			return townIdOf[actorId]
		end,
		stop = function()
			rt.stop()
			if attractions then
				attractions.stop()
			end
			if skylift then
				skylift:stop()
			end
			for _, c in conns do
				c:Disconnect()
			end
		end,
	}
end

return Game
