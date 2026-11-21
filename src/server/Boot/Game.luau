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
--   5. ReplicatedStorage.PlayNet remotes: Pick(choice) from the menu, Kick() (townsperson F), Duel(verb) (the rodent's
--      click, "pounce", and F, "feint"), Event (server -> client: picked, refused, bite, bitten, med, hurt, died, kick,
--      duel).
-- Every frame: ActorsRuntime steps the AI (its own Heartbeat); here traffic steps at 30 Hz against the
-- people and the player-held squirrels (RunOver kills: "RUN OVER") and the computer's squirrels out on the asphalt
-- (RunOver knocks one flat: Wildlife/RoadSquirrels), poses stream to clients at 15 Hz
-- (Net VehiclePoses, rendered by Client/Render/VehicleView), the duel steps ten times a second (Combat/CombatService:
-- the rodent bites at the right moment of a pounce, never on contact; the townspeople and officers near it fight back,
-- vigilantes close in, a bite opens an alert zone and sends the police; Power per Rodent/PowerRules, brief v2 §15),
-- Power fades while playing.
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
--   kick(player) -> (hit?), remotes { Pick(player, choice), Kick(player), Duel(player, verb) } (the PlayNet handlers),
--   combat (Combat/CombatService; nil when it could not start),
--   kill(actor, cause), step(dt), stateOf(player), health(actorId), attractions (Server/Attractions:
--   the bowling alley's MinigameService; nil without Workspace.Attractions), infection (Infection/
--   InfectionService; nil when it could not start), sewers (World/SewerService: the storm drains' carve, cover
--   and the police at the grate; nil when it could not start), skylift (Rides/SkyLiftService; nil when it could
--   not start), rafters (Attractions/RafterService; nil when it could not start), overhead (Stealth/OverheadService:
--   the town's people looking up at a squirrel overhead; nil when it could not start), townSquirrels (Wildlife/
--   TownSquirrels: the people and the ordinary squirrels, owner D21; nil when it could not start), roadSquirrels
--   (Wildlife/RoadSquirrels: the computer's squirrels a car knocks flat; nil when it could not start), cornerStore (Items/CornerStore;
--   nil without its bake), lounge (Attractions/LoungeService: THE GILDED ACORN; nil when it could not start),
--   dogs (Wildlife/YardHazards: the yard dogs; nil when they could not start), clothes { saves (Persistence/
--   PlayerSaves), wardrobe (Cosmetics/Wardrobe), giftShop (Cosmetics/GiftShop; nil without the alley) }: clothing
--   saved between servers (D16 #25; section 6e),
--   townIdOf(actorId), stop() };
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
local CombatRules = Import.shared("Combat/CombatRules") :: typeof(require("../../shared/Combat/CombatRules"))
local PossessionState =
	Import.shared("Actors/PossessionState") :: typeof(require("../../shared/Actors/PossessionState"))
local PowerRules = Import.shared("Rodent/PowerRules") :: typeof(require("../../shared/Rodent/PowerRules"))
local Net = Import.shared("Net/Net") :: typeof(require("../../shared/Net/Net"))
local Units = Import.shared("Config/Units") :: typeof(require("../../shared/Config/Units"))
local PlayerVehicles =
	Import.shared("Vehicles/PlayerVehicles") :: typeof(require("../../shared/Vehicles/PlayerVehicles"))
local VehicleKinds = Import.shared("Vehicles/VehicleKinds") :: typeof(require("../../shared/Vehicles/VehicleKinds"))
local ActorsRuntime = require("../Actors/ActorsRuntime")
local TownAI = require("../AI/TownAI")
local TrafficService = require("../Traffic/TrafficService")
local MovementService = require("../Movement/MovementService")
local BodyPin = require("../Movement/BodyPin")
local MoveValidator = require("../Movement/MoveValidator")
local ValidatorWorld = require("../Movement/ValidatorWorld")
local RailWorld = Import.shared("Movement/RailWorld") :: typeof(require("../../shared/Movement/RailWorld"))
local SquirrelWire = Import.shared("Movement/SquirrelWire") :: typeof(require("../../shared/Movement/SquirrelWire"))
local AirTrick = Import.shared("Movement/AirTrick") :: typeof(require("../../shared/Movement/AirTrick"))
local AttractionService = require("../Attractions/AttractionService")
local InfectionService = require("../Infection/InfectionService")
local CombatService = require("../Combat/CombatService")
local SewerService = require("../World/SewerService")
local HollowService = require("../Foraging/HollowService")
local ForageService = require("../Foraging/ForageService")
local ForageRules = Import.shared("Foraging/ForageRules") :: typeof(require("../../shared/Foraging/ForageRules"))
local Tunables = Import.shared("Config/Tunables") :: typeof(require("../../shared/Config/Tunables"))
local SkyLiftService = require("../Rides/SkyLiftService")
local RafterService = require("../Attractions/RafterService")
local OverheadService = require("../Stealth/OverheadService")
local SpeechRules = Import.shared("Speech/SpeechRules") :: typeof(require("../../shared/Speech/SpeechRules"))
local AreaPace = Import.shared("Speech/AreaPace") :: typeof(require("../../shared/Speech/AreaPace"))
local LoungeService = require("../Attractions/LoungeService")
local HospitalProps = require("../Hospital/HospitalProps")
local DayClock = require("./DayClock")
local Credits = require("../Economy/Credits")
local TreeArt = require("../Assets/TreeArt")
local HeroArt = require("../Assets/HeroArt")
local PinballArt = require("../Assets/PinballArt")
local ShopArt = require("../Assets/ShopArt")
local CornerStore = require("../Items/CornerStore")
local PlayerSaves = require("../Persistence/PlayerSaves")
local Wardrobe = require("../Cosmetics/Wardrobe")
local GiftShop = require("../Cosmetics/GiftShop")
local YardHazards = require("../Wildlife/YardHazards")
local TownSquirrels = require("../Wildlife/TownSquirrels")
local RoadSquirrels = require("../Wildlife/RoadSquirrels")
local WhackArt = require("../Assets/WhackArt")
local LoungeArt = require("../Assets/LoungeArt")
local PeopleArt = require("../Assets/PeopleArt")
local PoseStream = Import.shared("Traffic/PoseStream") :: typeof(require("../../shared/Traffic/PoseStream"))

export type Opts = {
	players: boolean?, -- connect joins (default true; the engine smoke drives PlayerLike stubs)
	engine: any?, -- Possession.Engine override (smoke)
	heartbeat: boolean?, -- connect Heartbeat loops (default true; false = step(dt) by hand)
	terrain: boolean?, -- write terrain (default true)
	heroes: boolean?, -- load the sculpted squirrel and rodent models (default true; false keeps the puppets)
	people: boolean?, -- load the rounded townspeople once uploaded (default true; false keeps the stock R15s)
	net: boolean?, -- create ReplicatedStorage.Net and stream poses (default true)
	-- the duel's word on the rodent's motor (Combat/CombatService opts.motorOf), in place of the live validator's: the
	-- engine tests have no client to send motor packets (default: Movement/MovementService)
	motorOf: ((townId: number) -> any)?,
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

export type MovementDeps = {
	data: any, -- Shared/Data (its routes: the harvest's, the alley's, the drains', the hollows')
	swept: any?, -- Traffic/SweptCollision (TrafficService): markTeleported on every hand-off
	wall: ValidatorWorld.Ray?, -- the wall ray (ValidatorWorld.engineRays in the engine)
	down: ValidatorWorld.Ray?, -- the floor ray (a tree's bough cylinders are floor)
	cover: ValidatorWorld.Ray?, -- the down ray the roof check casts (past the bough cylinders); default `down`
	cars: ValidatorWorld.Cars?, -- the cars' boxes the rays meet as well (TrafficService.solids)
	boostOf: ((actorId: any) -> boolean)?, -- the server's knowledge of a squirrel's chili rush
}

-- movement(deps): the movement service the game runs, with the squirrel validator switched on (spike S3: every
-- squirrel packet is judged by Movement/MoveValidator against the town's rails and the baked town's walls and floors,
-- and the town's cars, Movement/ValidatorWorld). start() builds it with the engine's rays; tests/unit/movement_live.spec.luau holds the
-- wiring to it.
function Game.movement(deps: MovementDeps): any
	local rail = RailWorld.get(deps.data, Height.at)
	local world =
		ValidatorWorld.build(rail, { wall = deps.wall, down = deps.down, cover = deps.cover, cars = deps.cars })
	local validator = MoveValidator.new(world, { boostOf = deps.boostOf })
	return MovementService.new({ swept = deps.swept, validator = validator })
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
-- animals(townActors, byTownId, placeOf) -> { { id, kind, x, y, z } }: every squirrel-family body for the minigames
-- (the paintball pass, a bowling lane in play, a pool shot: they knock an animal found on them), each where the server
-- holds it (placeOf: Actors/ActorsRuntime.placeOf; invariant D, validator round 8: a root written inside the station or
-- on a lane between two watches knocks nobody anywhere). Pure
function Game.animals(
	townActors: { any },
	byTownId: { [number]: any },
	placeOf: (actor: any) -> (number, number, number)
): { { [string]: any } }
	local out = {}
	for _, a in townActors do
		local other = byTownId[a.id]
		if other and (other.species == "squirrel" or other.species == "rodent") then
			local qx, qy, qz = placeOf(other)
			table.insert(out, {
				id = other.id,
				kind = if other.variant == "spicy" then "rodent" else "squirrel",
				x = qx,
				y = qy,
				z = qz,
			})
		end
	end
	return out
end

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
	lastBiteAt: number?, -- the server clock (`now`) at the rodent's last bite: fed while within a game day
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
	local Debris = game:GetService("Debris")

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
	-- the walls and floors the validator's rays meet are the baked town's, built once the bodies' folder exists
	type Rays = { wall: ValidatorWorld.Ray, down: ValidatorWorld.Ray, cover: ValidatorWorld.Ray }
	local rays: Rays? = nil
	local function engineRays(): Rays
		if rays == nil then
			local exclude: { Instance } = {}
			for _, name in { "Bodies", "Vehicles" } do
				local f = workspace:FindFirstChild(name)
				if f then
					table.insert(exclude, f)
				end
			end
			local wall, down, cover = ValidatorWorld.engineRays(exclude)
			rays = { wall = wall, down = down, cover = cover }
		end
		return rays :: Rays
	end
	local movement = Game.movement({
		data = data,
		swept = traffic :: any,
		-- the cars are solid to the squirrel's motor on each client (Traffic/Solid): the validator meets them too
		cars = traffic:solids(),
		wall = function(ox: number, oy: number, oz: number, dx: number, dy: number, dz: number): boolean
			return engineRays().wall(ox, oy, oz, dx, dy, dz)
		end,
		down = function(ox: number, oy: number, oz: number, dx: number, dy: number, dz: number): boolean
			return engineRays().down(ox, oy, oz, dx, dy, dz)
		end,
		cover = function(
			ox: number,
			oy: number,
			oz: number,
			dx: number,
			dy: number,
			dz: number,
			kind: string?,
			pool: { left: number }?
		): boolean
			return engineRays().cover(ox, oy, oz, dx, dy, dz, kind, pool)
		end,
	})
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
	local duelRemote = remote(playNet, "Duel")
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
	-- the rounded townspeople, loaded before any body is built (nothing until their Models are uploaded:
	-- Shared/Avatar/PeopleAssets; a failed load keeps every stock R15), then the baked staff figures dressed
	if o.people ~= false then
		local tp = os.clock()
		local okP, report = pcall(PeopleArt.install)
		if not okP then
			warn(`[SpicyRodents] people art failed: {report}`)
		elseif (report :: any).ok then
			local okS, n = pcall(PeopleArt.start)
			playNet:SetAttribute("PeopleArt", if okS then n else -1)
		elseif (report :: any).failed.assets == nil then
			for key, why in (report :: any).failed do
				warn(`[SpicyRodents] people art: stock bodies kept ({key}: {why})`)
			end
		end
		mark("people", tp)
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
	-- the brains read a held squirrel's pace by its accepted motor packets, not the velocity its client reports
	-- (Brains/Pedestrian: a creep behind someone is not noticed; a client saying 0 is not a creep)
	world.ctx.paceOf = function(townId: number): number?
		local actor = rt.byTownId[townId]
		return if actor then movement:paceOf(actor.id) else nil
	end
	local skylift: any = nil -- the sky lift (section 6 below): riders are refused a new body, a car and a game
	local rafters: any = nil -- the people under the alley's rafters (section 6b below), stepped from step(dt)
	local overhead: any = nil -- the town's people looking up at a squirrel overhead (section 6b'' below), the same
	local townSquirrels: any = nil -- the people and the ordinary squirrels (section 6b-3 below), the same
	local roadSquirrels: any = nil -- the computer's squirrels a car knocks flat (section 6b-4 below), the same
	local lounge: any = nil -- THE GILDED ACORN's door, guards and bar (section 6c below)
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

	-- who holds a town body ("ai" | "player"), and an attribute on it (Say is remembered for the speech log):
	-- what Infection/InfectionService and World/SewerService ask of the town
	local function controllerOfTown(id: number): string
		local actor = rt.byTownId[id]
		return if actor and possession:controllerOf(actor) ~= "ai" then "player" else "ai"
	end
	local function setTownAttr(id: number, name: string, value: any)
		local actor = rt.byTownId[id]
		if actor then
			(actor.body :: Model):SetAttribute(name, value)
		end
		if name == "Say" then
			lastSay[id] = value
		end
	end

	-- the town's one speech pacing (Speech/SpeechRules: the per-person cooldown, the town window and the cap by place,
	-- on the town's clock), shared by every service that makes people talk: the sequence, the drains (through
	-- infection.speech), the alley's rafters and the overhead watch
	local townSpeech = SpeechRules.new(nil, {
		area = AreaPace.DEFAULTS,
		clock = function(): number
			return world.now
		end,
	})
	-- the bite-to-hospital sequence (Infection/InfectionService): built here, stepped in step(dt)
	local infection: any = nil
	local infectionFault: (where: string, err: any) -> ()
	local okI, errI = pcall(function()
		infection = InfectionService.new({
			world = world,
			speech = townSpeech,
			traffic = traffic,
			data = data,
			controllerOf = controllerOfTown,
			busy = function(id: number): boolean
				local actor = rt.byTownId[id]
				return actor ~= nil and (actor.body :: Model):GetAttribute("Ride") ~= nil
			end,
			setAttr = setTownAttr,
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

	-- the storm drains (World/SewerService): the carve (after the terrain write above), cover, the police at the grate
	local sewers: any = nil
	local sewersBaked = workspace:FindFirstChild("Sewers") ~= nil
	if not sewersBaked then
		warn(
			"[SpicyRodents] Workspace.Sewers missing (run lune run tools/bake/sewers.luau and rebuild): no drains carved"
				.. " and nobody hidden, but the drains' routes are still in the data (E at a corner goes down into the"
				.. " ground): do not publish this place"
		)
	end
	local okW, errW = pcall(function()
		sewers = SewerService.start({
			world = world,
			-- no pipes drawn, no holes in the ground (an open shaft with nothing under it), and nobody hidden in
			-- solid ground. The routes are in the data either way, and every bake is optional in the project files
			-- (a fresh tree builds before it is baked), so the warning above is the guard: bake before a publish
			carve = o.terrain ~= false and sewersBaked,
			cover = sewersBaked,
			speech = infection and infection.speech,
			clock = function(): number
				return if infection then infection.now else world.now
			end,
			serverTime = function(): number
				return workspace:GetServerTimeNow()
			end,
			controllerOf = controllerOfTown,
			setAttr = setTownAttr,
		})
	end)
	if not okW then
		sewers = nil
		warn(`[SpicyRodents] the storm drains did not start (the pipes run, nobody loses the rodent there): {errW}`)
	end
	-- the hollow trees and the fallen log (Foraging/HollowService): their insides built (World/HollowShell), the cover,
	-- the nut meter and the claim shown on each tree; a failure leaves the routes running and nobody hidden in them
	-- where the server holds a player's squirrel (the validator's invariants D and E: never the root its client moves,
	-- never a doubtful packet): MovementService.heldPlace in its strict mode (`current`): the held place only while it is
	-- also the newest accepted packet; nil before one (a body still pinned) or while a doubt stands. What the nuts read:
	-- a pick-up (Foraging/ForageService) and a deposit (HollowService)
	local function heldPlace(id: number): (number?, number?, number?)
		local actor = rt.byTownId[id]
		if actor == nil then
			return nil, nil, nil
		end
		return movement:heldPlace(actor.id, true)
	end
	-- a claim is the player's (by UserId), not the body's; the computer's bodies claim as themselves
	local function claimKey(id: number): string
		local actor = rt.byTownId[id]
		local holder = if actor then possession:controllerOf(actor) else nil
		if typeof(holder) == "Instance" and holder:IsA("Player") then
			return `player {holder.UserId}`
		end
		return `body {id}`
	end
	local hollows: any = nil
	local okH, errH = pcall(function()
		hollows = HollowService.start({
			world = world,
			keyOf = claimKey,
			placeOf = heldPlace,
			nameOf = function(key: any): string?
				local userId = tonumber(string.match(tostring(key), "^player (%-?%d+)$"))
				local player = if userId then Players:GetPlayerByUserId(userId) else nil
				return if player then player.DisplayName else nil
			end,
			-- a claim's words to its player, as the notice toast (the computer's squirrels are told nothing)
			tell = function(key: any, text: string)
				local userId = tonumber(string.match(tostring(key), "^player (%-?%d+)$"))
				local player = if userId then Players:GetPlayerByUserId(userId) else nil
				if player then
					fire(player, { kind = "notice", text = text })
				end
			end,
		})
	end)
	if not okH then
		hollows = nil
		warn(`[SpicyRodents] the hollow trees did not start (their runs work, nobody is hidden in them): {errH}`)
	end
	-- the game day (Boot/DayClock's clock), fractional
	local function gameDay(): number
		return Game.gameSeconds(workspace:GetServerTimeNow(), dayClock.epoch, dayClock.base, dayClock.rate)
			/ DayClock.REAL_SECONDS_PER_DAY
	end
	-- nut foraging (Foraging/ForageService): the acorns at the spots, a player's squirrel picking one up where the
	-- server holds it, the computer's squirrels nibbling; the dip on the body (PickAt) and the player's nut meter. A
	-- failure leaves the town without nuts and everything else running
	local forage: any = nil
	local showNuts: (player: any) -> () = function() end
	if hollows then
		local okF, errF = pcall(function()
			forage = ForageService.start({
				world = world,
				hollows = hollows,
				placeOf = heldPlace,
				groundAt = Height.at,
				day = gameDay,
				onPick = function(id: number, _spot: any, _held: number, _ai: boolean)
					local actor = rt.byTownId[id]
					if actor then
						(actor.body :: Model):SetAttribute("PickAt", workspace:GetServerTimeNow())
						local driver = possession:controllerOf(actor)
						if driver ~= "ai" and driver ~= nil then
							showNuts(driver)
						end
					end
				end,
				onFull = function(id: number, _spot: any)
					local actor = rt.byTownId[id]
					local driver = if actor then possession:controllerOf(actor) else nil
					if driver ~= "ai" and driver ~= nil then
						fire(driver, {
							kind = "notice",
							text = `Your paws are full ({Tunables.get("forage.carryMax")} nuts): run them into a hollow tree`,
						})
					end
				end,
			})
		end)
		if not okF then
			forage = nil
			warn(`[SpicyRodents] the nut spots did not start (no nuts to find; the hollows still work): {errF}`)
		end
	end
	-- the player's nut meter (Client/UI/NutMeter draws it): the nuts its squirrel carries, the hollow it holds and how
	-- full that is, and the claimable hollow it is in now ("H4|0.45|free", "yours" or "taken"); nothing while it plays
	-- anything else (the Spicy Rodent forages nothing)
	showNuts = function(player: any)
		local actor = possession:actorOf(player)
		local tid = if actor then townIdOf[actor.id] else nil
		local a = if tid then world.actorsById[tid] else nil
		if
			forage == nil
			or hollows == nil
			or tid == nil
			or a == nil
			or not ForageRules.forages(a.species, a.variant)
		then
			for _, k in { "NutsCarried", "NutsMax", "NutTree", "NutTreeName", "NutStore", "NutInside" } do
				setAttr(player, k, nil)
			end
			return
		end
		local key = claimKey(tid)
		local own, ownMeter = nil, -1
		local inside = ""
		local space = hollows:spaceOf(a)
		for _, h in hollows.layout.hollows do
			if not h.claimable then
				continue
			end
			local m = hollows:meter(h.id)
			local owner = hollows:owner(h.id)
			if owner == key and m > ownMeter then
				own, ownMeter = h, m
			end
			if space ~= nil and h.space == space then
				local state = if owner == nil then "free" elseif owner == key then "yours" else "taken"
				inside = `{h.id}|{math.floor(m * 100 + 0.5) / 100}|{state}`
			end
		end
		setAttr(player, "NutsCarried", hollows:carried(tid))
		setAttr(player, "NutsMax", Tunables.get("forage.carryMax"))
		setAttr(player, "NutTree", if own then own.id else "")
		setAttr(player, "NutTreeName", if own then own.tree else "")
		setAttr(player, "NutStore", if own then math.floor(ownMeter * 100 + 0.5) / 100 else 0)
		setAttr(player, "NutInside", inside)
	end
	-- the owner's sewer modules, once each, for the clients to draw near the body (Client/World/SewerArt); a module
	-- that does not load leaves its drains in the bake's plain parts
	if sewersBaked then
		local store = ReplicatedStorage:FindFirstChild("SewerArt")
		if store == nil then
			local f = Instance.new("Folder")
			f.Name = "SewerArt"
			f.Parent = ReplicatedStorage
			store = f
		end
		task.spawn(function()
			local okA, loaded, failed =
				pcall(SewerService.loadArt, workspace:FindFirstChild("Sewers") :: Instance, store)
			if not okA then
				warn(`[SpicyRodents] the sewer modules did not load (the drains stay in plain parts): {loaded}`)
				return
			end
			for module, why in failed do
				warn(`[SpicyRodents] sewer module {module} did not load (its drains stay in plain parts): {why}`)
			end
			print(`[SpicyRodents] sewer modules loaded: {table.concat(loaded, ", ")}`)
		end)
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

	-- The squirrel validator's hands (Movement/MovementService): the driver's "Correction", the server's own snap of the
	-- body, the hold; the held squirrel's motor states come up on Net "Squirrel.State". Positions are the feet (the
	-- root less the body's HipHeight), as the motor's are.
	local function hipOf(body: Model): number
		local h = body:GetAttribute("HipHeight")
		return if type(h) == "number" and h > 0 then h else 0
	end
	local function heldBy(actorId: any): (any?, any?)
		local actor = rt.actors:get(actorId)
		if actor == nil then
			return nil, nil
		end
		local driver = possession:controllerOf(actor)
		return actor, if driver ~= "ai" then driver else nil
	end
	movement.deps.poseOf = function(actor: any): (number?, number?, number?)
		local body = actor.body :: Model
		local root = body and body.PrimaryPart
		if root == nil then
			return nil, nil, nil
		end
		local p = root.Position
		return p.X, p.Y - hipOf(body), p.Z
	end
	-- the driver's round trip as the engine measures it: a latency that drops lowers the clock's arrival offset by up to
	-- that much, and the validator's clock check allows it (Movement/MoveValidator, pingOf)
	movement.deps.validator.pingOf = function(actorId: any): number?
		local _, driver = heldBy(actorId)
		if driver and typeof(driver) == "Instance" and driver:IsA("Player") then
			local ok, ping = pcall(function(): number
				return (driver :: Player):GetNetworkPing()
			end)
			return if ok then ping else nil
		end
		return nil
	end
	-- the validator's hands (Movement/BodyPin): a newly held squirrel is the server's (anchored, its own, marked kept)
	-- until its driver's first packet passes the gate, and only the validator's own unpin hands a kept body back (a
	-- hold's timer, the sky lift, never do); a client that never sends cannot move it, and nothing is judged while its
	-- town streams in
	movement.deps.engine = BodyPin.engine({
		heldBy = heldBy,
		isPinned = function(actorId: any): boolean
			return movement:isPinned(actorId)
		end,
		place = function(body: any, x: number, y: number, z: number)
			local model = body :: Model
			model:PivotTo(CFrame.new(x, y + hipOf(model), z) * model:GetPivot().Rotation)
		end,
		tell = function(driver: any, msg: any)
			if net and typeof(driver) == "Instance" then
				net:fire(driver, "Correction", msg)
			end
		end,
		delay = function(seconds: number, fn: () -> ())
			task.delay(seconds, fn)
		end,
	})
	-- the rodent's click as a copy in its motor packet (Movement/SquirrelWire clickSeq): taken by the duel as the Duel
	-- remote's is, the first of the two to arrive (set where the duel is)
	local clickCopy: ((player: any, clock: number, seq: number) -> ())? = nil
	if net then
		net:on("Squirrel.State", function(player: any, rec: any)
			local actor = possession:actorOf(player)
			if actor == nil or not isSquirrelFamily(actor) then
				return
			end
			local seq, epoch, snapshot = SquirrelWire.fromRecord(rec)
			local v = movement:packet(
				actor.id,
				actor.species,
				{ seq = seq, epoch = epoch, snapshot = snapshot },
				workspace:GetServerTimeNow()
			)
			-- the air trick (owner D17): an accepted packet's move goes on the body for every other client to pose
			-- (Shared/Movement/AirTrick: AirTrick, AirTrickAt; a snapped one is not shown)
			local body = actor.body :: Model?
			if type(v) == "table" and v.accepted and not v.snapped and body then
				local kind, at = AirTrick.mark(
					body:GetAttribute(AirTrick.ATTR.kind),
					body:GetAttribute(AirTrick.ATTR.at),
					tonumber(snapshot.trickKind) or 0,
					tonumber(snapshot.trickTime) or 0,
					workspace:GetServerTimeNow()
				)
				if kind and at then
					body:SetAttribute(AirTrick.ATTR.kind, kind)
					body:SetAttribute(AirTrick.ATTR.at, at)
					if kind == AirTrick.WIGGLE then
						-- (the twitch's seed, from the press the packet dates: the client draws the same from its own clock)
						local press = AirTrick.pressOf(tonumber(snapshot.clock) or 0, tonumber(snapshot.trickTime) or 0)
						body:SetAttribute(AirTrick.ATTR.seed, AirTrick.seedOf(press))
					end
				end
				-- (owner D18: the twitch follows the aim; written in twentieths, only when it moves, while a wiggle plays)
				if snapshot.trickKind == AirTrick.WIGGLE and (tonumber(snapshot.trickTime) or 0) > 0 then
					local ax, ay = AirTrick.aimAttr(tonumber(snapshot.aimYaw) or 0, tonumber(snapshot.aimReach) or 0)
					local was = body:GetAttribute(AirTrick.ATTR.aim)
					if typeof(was) ~= "Vector2" or was.X ~= ax or was.Y ~= ay then
						body:SetAttribute(AirTrick.ATTR.aim, Vector2.new(ax, ay))
					end
				end
			end
			local click = if type(v) == "table" then v.click else nil
			if click and clickCopy then
				clickCopy(player, click.clock, click.seq)
			end
		end)
	end
	-- a body the server itself moved (a minigame's knock, the lounge's door): its place is the validator's new
	-- baseline, under a new motor epoch the driver is told of. `at`: the pivot the server put it at (invariant D: the
	-- rule's own place); nil: read back in the same thread as the server's own PivotTo, before its client can write
	local function movedBody(body: any, why: string, at: Vector3?)
		local id = body and body:GetAttribute(PossessionState.ATTR.ActorId)
		local actor, driver = heldBy(id)
		if actor == nil or driver == nil or not isSquirrelFamily(actor) then
			return
		end
		local p = at or (body :: Model):GetPivot().Position
		movement:teleported(actor.id, p.X, p.Y - hipOf(body), p.Z, why, workspace:GetServerTimeNow())
	end
	-- fifteen times a second: the server's own view of every held squirrel's root (MovementService.watch), and the sky
	-- lift's riders (attribute Ride) left alone until the platform puts them down
	local onLift: { [any]: boolean } = {}
	local watchAcc = 0
	local function watchSquirrels(dt: number)
		watchAcc += dt
		if watchAcc < 1 / 15 then
			return
		end
		watchAcc = 0
		local t = workspace:GetServerTimeNow()
		for _, player in Players:GetPlayers() do
			local actor = possession:actorOf(player)
			local body = if actor and isSquirrelFamily(actor) then actor.body :: Model else nil
			local root = if body then body.PrimaryPart else nil
			if actor and body and root then
				local ride = body:GetAttribute("Ride") ~= nil
				local p = root.Position
				if ride ~= (onLift[actor.id] == true) then
					onLift[actor.id] = ride
					movement:suspend(actor.id, ride)
					if not ride then
						-- off the sky lift where the platform put it, under a new epoch
						movement:teleported(actor.id, p.X, p.Y - hipOf(body), p.Z, "ride", t)
					end
				end
				if not ride then
					movement:watch(actor.id, p.X, p.Y - hipOf(body), p.Z, t)
				end
			end
		end
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
		if hollows and townId then
			hollows:drop(townId) -- (the nuts it carried are lost)
		end
		local sp = spawn[townId]
		local a = world.actorsById[townId]
		if sp and a and actor.mode == "ai" then
			a.x, a.y, a.z = sp[1], sp[2], sp[3]
		end
	end

	-- a blow on a squirrel-family body (a player's kick, a townsperson's or an officer's in the duel): its health, the
	-- rodent's Power (the v5.4 pedestrian kick), the "hurt" toast, and the knock-out at 0
	local function hurtRodent(target: any, amount: number, cause: string): (number, boolean)
		local h, dead = CombatRules.applyDamage(healthOf(target.id), amount)
		health[target.id] = h
		local driver = possession:controllerOf(target)
		if driver ~= "ai" and driver ~= nil then
			local ds = stateOf(driver)
			if target.variant == "spicy" then
				PowerRules.apply(ds.power, { kind = "pedestrianKick" })
			end
			publish(driver)
			fire(driver, { kind = "hurt", by = cause, health = h })
		end
		if dead then
			kill(target, "kick")
		end
		return h, dead
	end

	-- the duel (Combat/CombatService), built below once the bite's consequences are defined; a player's kick reads its
	-- alert zones and tells it of the raised leg
	local combat: any = nil
	local duelRules = CombatRules.params()

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
		if combat and townIdOf[actor.id] then
			-- (a raised leg only when the kick was at the rodent: Combat/CombatService.heldKick)
			combat:heldKick(townIdOf[actor.id], now, look.X, look.Z)
		end
		local targets = {}
		local byId: { [string]: any } = {}
		for _, a in world.actors do
			local other = rt.byTownId[a.id]
			if isSquirrelFamily(other) then
				-- (where the server holds it: a held squirrel's validated place, never the root its client writes)
				local qx, qy, qz = rt.placeOf(other)
				table.insert(targets, { id = other.id, x = qx, y = qy, z = qz })
				byId[other.id] = other
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
		-- (the duel's i-frames hold for a player's kick too: a blow from anyone a moment ago and this one glances off)
		local targetTown = townIdOf[hitId]
		if combat and targetTown and not combat:takeBlow(targetTown, now) then
			fire(player, { kind = "kick", hit = false })
			return false
		end
		-- (the hidden strength boost by a fresh bite is a player's too: Combat/CombatService)
		local amount = CombatRules.damage(duelRules, "kick", combat ~= nil and combat:inAlert(p.X, p.Z, now))
		local h, dead = hurtRodent(target, amount, "kick")
		fire(player, {
			kind = "kick",
			hit = true,
			target = if target.variant == "spicy" then "rodent" else "squirrel",
			health = h,
		})
		if not dead and possession:controllerOf(target) == "ai" then
			-- knock the AI body back a few studs
			local a = world.actorsById[townIdOf[hitId]]
			if a then
				a.x += look.X * 4
				a.z += look.Z * 4
			end
		end
		return true
	end

	-- a car's sweep hit a squirrel: a player's is knocked out ("RUN OVER"); one of the computer's ordinary squirrels,
	-- out on the asphalt, is knocked flat and comes back later at a tree (Wildlife/RoadSquirrels; owner D21)
	traffic.RunOver:connect(function(actorId: any, _vehicle: any)
		local actor = rt.actors:get(actorId)
		if actor == nil then
			return
		end
		if possession:controllerOf(actor) ~= "ai" then
			kill(actor, "traffic")
		elseif roadSquirrels then
			local tid = townIdOf[actor.id]
			if tid then
				roadSquirrels:hit(tid)
			end
		end
	end)

	-- the traffic world: people (AI and held humans), the player-held squirrels and the computer's squirrels that are
	-- out on the asphalt (fatal sweep)
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
			elseif isSquirrelFamily(actor) and (actor.mode ~= "ai" or a.crossing) then
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

	-- A bite landed (Combat/CombatService decided it): Power, the bite count and the Bite clip on the rodent, the
	-- victim's shout, the bite-to-hospital sequence, and the news on both players' screens. Ids are town ids.
	local function landBite(vt: number, rodentTown: number)
		local actor = rt.byTownId[rodentTown]
		local victim = rt.byTownId[vt]
		local player = if actor then possession:controllerOf(actor) else nil
		if actor == nil or victim == nil or player == nil or player == "ai" then
			return
		end
		local s = stateOf(player)
		local root = (actor.body :: Model).PrimaryPart
		local va = world.actorsById[vt]
		local officer = va ~= nil and va.post == "police"
		local delta = PowerRules.apply(
			s.power,
			{ kind = if officer then "biteOfficer" else "bitePerson", y = Units.u(if root then root.Position.Y else 0) }
		)
		s.lastBiteAt = now
		s.bites += 1 -- every client plays the bite on the rodent's body (Animation/AnimationDriver watches this)
		(actor.body :: Model):SetAttribute("BiteAt", now)
		shoutN += 1
		local line = PlayRules.shout(shoutN)
		local driver = possession:controllerOf(victim)
		if infection then
			-- infected: they run and shout (the Say attribute; clients draw the bubble), and the sequence to the
			-- hospital begins. A player holding the victim gets a "med" event from the service that says what
			-- happened and what to do.
			local okB, errB = pcall(infection.bite, infection, vt, rodentTown, player)
			if not okB then
				infectionFault("bite", errB)
			end
			line = lastSay[vt] or line
		elseif driver == "ai" then
			local brain = world.brains[vt] :: any
			local me = world.actorsById[rodentTown]
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

	-- the players' Spicy Rodents that can fight now: not stunned by the water gun (Items/ItemWorld), not down a drain
	-- (World/SewerService) or inside a hollow tree (Foraging/HollowService)
	local function rodentsInPlay(): { number }
		local out = {}
		for player, s in states do
			local actor = possession:actorOf(player)
			if s.role == "rodent" and actor and actor.variant == "spicy" then
				local tid = townIdOf[actor.id]
				local stunnedUntil = (actor.body :: Model):GetAttribute(PossessionState.ATTR.StunnedUntil)
				local stunned = type(stunnedUntil) == "number" and workspace:GetServerTimeNow() < stunnedUntil
				local covered = tid ~= nil
					and ((sewers ~= nil and not sewers:mayBite(tid)) or (hollows ~= nil and not hollows:mayBite(tid)))
				if tid and not stunned and not covered then
					table.insert(out, tid)
				end
			end
		end
		return out
	end

	local okDuel, errDuel = pcall(function()
		combat = CombatService.new({
			world = world,
			infection = infection,
			params = duelRules,
			controllerOf = controllerOfTown,
			rodents = rodentsInPlay,
			-- the pounce the validator accepted (Movement/MovementService): a click alone bites nobody
			motorOf = function(id: number): any
				if o.motorOf then
					return o.motorOf(id)
				end
				local actor = rt.byTownId[id]
				if actor == nil then
					return nil
				end
				local snap, at, pounceAt, cleanAt = movement:motorOf(actor.id)
				if snap == nil or at == nil then
					return nil
				end
				local t = workspace:GetServerTimeNow() -- (the validator's clock; the duel has its own)
				return {
					age = t - at,
					cleanAge = if cleanAt then t - cleanAt else math.huge,
					launchAgo = if pounceAt then t - pounceAt else nil,
				}
			end,
			-- the rodent's place by its last accepted packet while the packets are fresh (a bite and a blow are judged
			-- there, not at the root its client moves; the round-3 review: by the last clean one, a run of packets each
			-- with a violation too small to flag froze it); the body's own when there is none or they stopped (no packet
			-- yet, a silent client, or the engine tests' own word on the motor)
			poseOf = function(id: number): (number?, number?, number?)
				local actor = rt.byTownId[id]
				if o.motorOf or actor == nil then
					return nil, nil, nil
				end
				local snap, at = movement:motorOf(actor.id)
				if snap == nil or at == nil or workspace:GetServerTimeNow() - at > duelRules.motorFresh then
					return nil, nil, nil
				end
				return snap.x :: number, snap.y :: number, snap.z :: number
			end,
			-- the rodent's pace by its accepted packets, on the server's clock (the duel hears a rodent faster than a creep);
			-- its root's at the duel's steps when there are none
			paceOf = function(id: number): number?
				local actor = rt.byTownId[id]
				if o.motorOf or actor == nil then
					return nil
				end
				return movement:paceOf(actor.id)
			end,
			linkOf = function(id: number): number?
				local actor = rt.byTownId[id]
				local driver = if actor then possession:controllerOf(actor) else nil
				if driver ~= nil and typeof(driver) == "Instance" and driver:IsA("Player") then
					local ok, ping = pcall(function(): number
						return (driver :: Player):GetNetworkPing()
					end)
					return if ok then ping else nil
				end
				return nil
			end,
			setAttr = setTownAttr,
			notify = function(id: number, payload: { [string]: any })
				local actor = rt.byTownId[id]
				local driver = if actor then possession:controllerOf(actor) else nil
				if driver ~= nil and driver ~= "ai" then
					fire(driver, payload)
				end
			end,
			hurt = function(id: number, amount: number, cause: string, _by: number)
				local actor = rt.byTownId[id]
				if actor then
					hurtRodent(actor, amount, cause)
				end
			end,
			bitten = landBite,
			covered = function(id: number): boolean
				return world.covered[id] ~= nil
			end,
			-- a Sound named after the cue at the body (silent until the library ids are chosen)
			cue = function(id: number, name: string)
				local actor = rt.byTownId[id]
				local root = if actor then (actor.body :: Model).PrimaryPart else nil
				local soundId = CombatService.SOUNDS[name] or ""
				if root and soundId ~= "" then
					local snd = Instance.new("Sound")
					snd.Name = name
					snd.SoundId = soundId
					snd.RollOffMaxDistance = 80
					snd.Parent = root
					snd:Play()
					Debris:AddItem(snd, 4)
				end
			end,
		})
	end)
	if not okDuel then
		combat = nil
		warn(`[SpicyRodents] the duel did not start (nobody can bite or be bitten): {errDuel}`)
	end
	local duelFaults = 0

	-- every 0.1 s: the duel (the people's side, the blows, and the bite at the right moment)
	local function bites()
		if combat == nil then
			return
		end
		local okD, errD = pcall(combat.step, combat, 0.1, now)
		if not okD then
			duelFaults += 1
			if duelFaults <= 5 then
				warn(`[SpicyRodents] the duel failed this tick: {errD}`)
			end
			if duelFaults >= Game.FAULT_LIMIT then
				pcall(combat.stop, combat)
				combat = nil
				warn("[SpicyRodents] the duel keeps failing: switched off")
			end
		end
	end

	-- the rodent's click (a pounce's tell, with the motor clock its client made it at, and its number) and F (a feint),
	-- from the PlayNet "Duel" remote or, for a click, its copy in a motor packet (clickCopy): the first to arrive is the
	-- click (MovementService.clickNew), CombatService.REMOTE_RATE calls a second heard, a refusal answered every
	-- REPLY_EVERY at most
	local function duel(player: any, verb: any, clock: any, seq: any)
		if combat == nil or (verb ~= "pounce" and verb ~= "feint") then
			return
		end
		local c = combat
		local s = stateOf(player)
		local actor = possession:actorOf(player)
		local tid = if actor then townIdOf[actor.id] else nil
		if s.role ~= "rodent" or actor == nil or actor.variant ~= "spicy" or tid == nil then
			return
		end
		if verb == "pounce" and not movement:clickNew(actor.id, seq) then
			return -- (a copy of a click already taken)
		end
		if not c:remoteGate(player, now) then
			return
		end
		-- (the click's time on the movement packets' clock, as the duel's own: the remote's trip is no part of the tie)
		local clickAt: number? = nil
		if verb == "pounce" then
			local t = workspace:GetServerTimeNow()
			local at = movement:clickAt(actor.id, clock, t)
			clickAt = if at then now - (t - at) else nil
		end
		local ok, why = c:rodentAct(tid, verb, now, clickAt)
		if not ok and not c:mayReply(player, now) then
			return
		end
		if not ok and verb == "feint" and why == "winded" then
			fire(player, { kind = "duel", what = "winded" })
		elseif not ok and verb == "pounce" then
			-- (the client clicks on the motor's own cooldown, so this is a click the link bunched up: its lunge bites
			-- nobody, and the player is told)
			fire(player, { kind = "duel", what = "notyet" })
		end
	end

	clickCopy = function(player: any, clock: number, seq: number)
		local ok, err = pcall(duel, player, "pounce", clock, seq)
		if not ok then
			warn(`[SpicyRodents] duel click copy failed: {err}`)
		end
	end

	local biteAcc, fadeAcc = 0, 0
	local function step(dt: number)
		now += dt
		local okSq, errSq = pcall(function()
			watchSquirrels(dt)
		end)
		if not okSq then
			warn(`[SpicyRodents] squirrel watch failed: {errSq}`)
		end
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
		if forage then
			local okF, errF = pcall(forage.step, forage, dt, now)
			if not okF then
				warn(`[SpicyRodents] the nut spots stopped: {errF}`)
				pcall(forage.stop, forage)
				forage = nil
			end
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
					local changed = PowerRules.fade(s.power, fadeAcc) > 0
					-- a refuge heals the fed rodent (World/SewerService: the hollow rate down a drain, D33 rev 4)
					local actor = possession:actorOf(player)
					local tid = if actor then townIdOf[actor.id] else nil
					if sewers and actor and tid and actor.variant == "spicy" then
						local h = healthOf(actor.id)
						local healed =
							sewers:heal(tid, h, PlayRules.HEALTH, fadeAcc, SewerService.fed(s.lastBiteAt, now))
						if healed ~= h then
							health[actor.id] = healed
							changed = true
						end
					end
					-- and so does a hollow tree (Foraging/HollowService, the same rate)
					if hollows and actor and tid and actor.variant == "spicy" then
						local h = healthOf(actor.id)
						local healed =
							hollows:heal(tid, h, PlayRules.HEALTH, fadeAcc, SewerService.fed(s.lastBiteAt, now))
						if healed ~= h then
							health[actor.id] = healed
							changed = true
						end
					end
					if changed then
						publish(player)
					end
				end
			end
			-- the hollows' meters and claims, on the game day (Boot/DayClock's clock)
			if hollows then
				local okD, errD = pcall(hollows.step, hollows, gameDay())
				if not okD then
					warn(`[SpicyRodents] the hollow meters failed this second: {errD}`)
				end
			end
			-- each player's nut meter
			for player in states do
				local okN, errN = pcall(function()
					showNuts(player)
				end)
				if not okN then
					warn(`[SpicyRodents] the nut meter failed: {errN}`)
					break
				end
			end
			fadeAcc = 0
		end
		if rafters then
			local okR, errR = pcall(rafters.step, rafters, dt)
			if not okR then
				warn(`[SpicyRodents] the rafter watch stopped: {errR}`)
				pcall(rafters.stop, rafters)
				rafters = nil
			end
		end
		if overhead then
			local okO, errO = pcall(overhead.step, overhead, dt)
			if not okO then
				warn(`[SpicyRodents] the overhead watch stopped: {errO}`)
				pcall(overhead.stop, overhead)
				overhead = nil
				if combat then
					combat.opts.overhead = nil
					combat.opts.under = nil
				end
			end
		end
		if roadSquirrels then
			local okRS, errRS = pcall(roadSquirrels.step, roadSquirrels, dt)
			if not okRS then
				warn(`[SpicyRodents] the squirrels on the roads stopped: {errRS}`)
				pcall(roadSquirrels.stop, roadSquirrels)
				roadSquirrels = nil
			end
		end
		if townSquirrels then
			local okTS, errTS = pcall(townSquirrels.step, townSquirrels, dt)
			if not okTS then
				warn(`[SpicyRodents] the people and the ordinary squirrels stopped: {errTS}`)
				pcall(townSquirrels.stop, townSquirrels)
				townSquirrels = nil
			end
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
	local function onDuel(player: any, verb: any, clock: any, seq: any)
		local ok, err = pcall(function()
			duel(player, verb, clock, seq)
		end)
		if not ok then
			warn(`[SpicyRodents] duel {verb} failed: {err}`)
		end
	end
	local conns: { RBXScriptConnection } = {}
	table.insert(conns, pickRemote.OnServerEvent:Connect(onPick))
	table.insert(conns, kickRemote.OnServerEvent:Connect(onKick))
	table.insert(conns, duelRemote.OnServerEvent:Connect(onDuel))
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
					return false, "Only people can play. Animals can watch"
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
							-- (a held squirrel where the server holds it: invariant D; a person at its root)
							local q = r.Position
							local qx, qy, qz = q.X, q.Y, q.Z
							if isSquirrelFamily(actor) then
								qx, qy, qz = rt.placeOf(actor)
							end
							table.insert(out, {
								key = player,
								name = if player.DisplayName ~= "" then player.DisplayName else player.Name,
								species = actor.species,
								x = qx,
								y = qy,
								z = qz,
							})
						end
					end
					return out
				end,
			},
			-- paintball (PaintballService.Deps): an infected player is refused at the arena door with "See a
			-- doctor first." (decision D6), so nobody collapses in a match. Its pass desk sells the town's one
			-- pass, games.pass above (the wallet's), so a pass bought there opens both lounges too
			paintball = {
				fit = function(player: any): (boolean, string?)
					local actor = possession:actorOf(player)
					local townId = if actor then townIdOf[actor.id] else nil
					if infection and townId and infection:statusOf(townId) ~= nil then
						return false, "infected"
					end
					return true, nil
				end,
			},
			-- a body a game moved itself (the paintball arena's sweep and its places): a held squirrel's validator is
			-- told, as for every server move
			moved = function(body: any, why: string)
				movedBody(body, why)
			end,
			-- squirrels and the Spicy Rodent, wherever they are: a lane in play knocks them off it
			animals = function(): { { [string]: any } }
				return Game.animals(world.actors, rt.byTownId, rt.placeOf)
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
					local at = Vector3.new(x, y + 0.6, z)
					body:PivotTo(CFrame.new(at) * body:GetPivot().Rotation)
					movedBody(body, "knocked", at)
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

	-- 6b. the people under the alley's rafters spot a squirrel that does not creep (Attractions/RafterService:
	-- addendum D9), and a guard's kick does not reach into the roof vent
	local okR, errR = pcall(function()
		rafters = RafterService.start({
			possession = possession,
			runtime = rt,
			fire = fire,
			attractions = attractions,
			speech = townSpeech,
		})
	end)
	if not okR then
		warn(`[SpicyRodents] the rafter watch failed to start: {errR}`)
	end

	-- 6b''. the town's people notice, and talk about, a squirrel stalking above them on a wire, a fence, a branch or a
	-- roof's edge (Stealth/OverheadService; owner playtest 2026-11-19); the rafters keep theirs. A person who has
	-- pointed the rodent out above them meets it aware in the duel (Combat/CombatService opts.overhead)
	local okO, errO = pcall(function()
		overhead = OverheadService.new({
			world = world,
			speech = townSpeech,
			infection = infection,
			combat = combat,
			groundAt = Height.at,
			-- the held rodent's route and footing, from the validator's last clean packet (a stale one says nothing)
			motorOf = function(id: number): any
				local actor = rt.byTownId[id]
				if actor == nil then
					return nil
				end
				local snap, at = movement:motorOf(actor.id)
				if snap == nil or at == nil or workspace:GetServerTimeNow() - at > 1 then
					return nil
				end
				return { routeId = (snap :: any).routeId, grounded = (snap :: any).grounded == true }
			end,
			exclude = function(id: number): boolean
				local actor = rt.byTownId[id]
				return rafters ~= nil and actor ~= nil and rafters:watches(actor.id)
			end,
			setAttr = setTownAttr,
			gaze = function(id: number, x: number?, y: number?, z: number?)
				setTownAttr(id, "Gaze", if x and y and z then Vector3.new(x, y, z) else nil)
			end,
			-- the rodent's own eye: the player holding it (Client/UI/SneakMeter)
			cue = function(id: number, meter: number?, seen: boolean?)
				local actor = rt.byTownId[id]
				local driver = if actor then possession:controllerOf(actor) else nil
				if driver ~= nil and driver ~= "ai" then
					pcall(function()
						driver:SetAttribute("OverheadMeter", meter)
						driver:SetAttribute("OverheadSeen", seen)
					end)
				end
			end,
			serverTime = function(): number
				return workspace:GetServerTimeNow()
			end,
		})
		if combat then
			combat.opts.overhead = function(person: number, rodent: number): boolean
				return overhead ~= nil and overhead:spotted(person, rodent)
			end
			combat.opts.under = function(person: number, rodent: number): (number?, number?)
				if overhead == nil then
					return nil, nil
				end
				return overhead:spotUnder(person, rodent)
			end
		end
	end)
	if not okO then
		overhead = nil
		warn(`[SpicyRodents] the overhead watch failed to start: {errO}`)
	end

	-- 6b-3. the town's people and the ORDINARY squirrels (Wildlife/TownSquirrels; owner D21): nobody runs from one; a
	-- player's that leaps right on someone or at them makes them start (a step back, a yelp), and now and then
	-- someone has a glance and a friendly word for one going by
	do
		local okTS, errTS = pcall(function()
			townSquirrels = TownSquirrels.new({
				world = world,
				speech = townSpeech,
				-- the leap as the validator's last accepted packet has it (the places are the AI world's record of the held
				-- body: Movement/MovementService.heldPlace through ActorsRuntime.feedHeld)
				airborne = function(id: number): boolean?
					local actor = rt.byTownId[id]
					if actor == nil then
						return nil
					end
					local snap, at = movement:motorOf(actor.id)
					return TownSquirrels.airborne(snap, if at then workspace:GetServerTimeNow() - at else nil)
				end,
				busy = function(id: number): boolean
					return (infection ~= nil and infection:engaged(id))
						or (combat ~= nil and combat:guardOf(id) ~= nil)
						or (overhead ~= nil and overhead:stageOf(id) ~= "none")
				end,
				setAttr = setTownAttr,
				gaze = function(id: number, x: number?, y: number?, z: number?)
					setTownAttr(id, "Gaze", if x and y and z then Vector3.new(x, y, z) else nil)
				end,
				serverTime = function(): number
					return workspace:GetServerTimeNow()
				end,
			})
		end)
		if not okTS then
			townSquirrels = nil
			warn(`[SpicyRodents] the people and the ordinary squirrels failed to start: {errTS}`)
		end
	end

	-- 6b-4. the computer's squirrels and the roads (owner D21): they cross by themselves, looking first (Brains/Squirrel
	-- on Shared/Wildlife/RoadCrossing, with the fleet as this server has it), and one a car gets is knocked flat and
	-- comes back later at a tree (Wildlife/RoadSquirrels; the RunOver handler above)
	do
		local okRS, errRS = pcall(function()
			roadSquirrels = RoadSquirrels.new({
				world = world,
				setAttr = setTownAttr,
				setPossessable = function(id: number, value: boolean)
					local actor = rt.byTownId[id]
					if actor then
						actor.possessable = value
					end
				end,
				onDown = function(id: number)
					if hollows then
						hollows:drop(id) -- (the nuts it carried are lost)
					end
				end,
				cue = function(id: number, name: string)
					local actor = rt.byTownId[id]
					local root = if actor then (actor.body :: Model).PrimaryPart else nil
					local soundId = RoadSquirrels.SOUNDS[name] or ""
					if root and soundId ~= "" then
						local snd = Instance.new("Sound")
						snd.Name = name
						snd.SoundId = soundId
						snd.RollOffMaxDistance = 80
						snd.Parent = root
						snd:Play()
						Debris:AddItem(snd, 4)
					end
				end,
				serverTime = function(): number
					return workspace:GetServerTimeNow()
				end,
			})
			TownAI.setRoad(world, function(): { any }
				return traffic:cars()
			end)
		end)
		if not okRS then
			roadSquirrels = nil
			warn(`[SpicyRodents] the squirrels on the roads failed to start: {errRS}`)
		end
	end

	-- 6b'. The yard dogs (Wildlife/YardHazards): eight friendly dogs in their yards, on the town's brain scheduler
	local dogs: any = nil
	local okD, errD = pcall(function()
		dogs = YardHazards.start({
			world = world,
			runtime = rt,
			possession = possession,
			fire = fire,
			groundAt = Height.at,
			heartbeat = o.heartbeat ~= false,
		})
	end)
	if not okD then
		warn(`[SpicyRodents] the yard dogs failed to start: {errD}`)
	end

	-- 6c. Pepper's Corner Store (Workspace.Expansion.F1): pick up off the shelves, pay once at the till through the
	-- town's wallet, nothing out unpaid (Items/CornerStore)
	local cornerStore: any = nil
	local okC, errC = pcall(function()
		local expansionData = data:module("Expansion") :: any
		cornerStore = CornerStore.start({
			expansion = workspace:FindFirstChild("Expansion"),
			runtime = rt,
			zones = if expansionData then expansionData.zones else nil,
			dogs = dogs,
			wallet = wallet,
			possession = possession,
			fire = fire,
			heartbeat = o.heartbeat ~= false,
			terrain = o.terrain ~= false,
		})
	end)
	if not okC then
		warn(`[SpicyRodents] the corner store failed to open: {errC}`)
	end

	-- 6d. THE GILDED ACORN, the 1940s lounge (Workspace.Expansion.LoungeClassic; addendum D14): the door lets a
	-- person with the wallet's one pass in (first person inside), the guards knock out any squirrel at the door
	-- (kill, cause "guard"), the bar sells its four drinks (Attractions/LoungeService)
	local okLo, errLo = pcall(function()
		lounge = LoungeService.start({
			town = LoungeService.gameTown({
				possession = possession,
				runtime = rt,
				wallet = wallet,
				squirrels = function(): { LoungeService.Squirrel }
					local out = {}
					for _, a in world.actors do
						local actor = rt.byTownId[a.id]
						if actor and isSquirrelFamily(actor) then
							table.insert(out, { actor = actor, x = a.x, y = a.y - a.hip, z = a.z })
						end
					end
					return out
				end,
				kill = kill,
				moved = function(body: any)
					movedBody(body, "lounge")
				end,
			}),
			heartbeat = o.heartbeat ~= false,
			terrain = o.terrain ~= false,
		})
	end)
	if not okLo then
		warn(`[SpicyRodents] the lounge failed to open: {errLo}`)
	end

	-- 6e. Clothing carries over between servers (owner D16 #25): Persistence/PlayerSaves holds one session-locked
	-- profile per player in the DataStore PlayerSaves.STORE (loaded on join, saved a few seconds after a change and
	-- every 30 s, within a server-wide write budget, released on leave and at shutdown), Cosmetics/Wardrobe writes only the clothing into it (what is owned and
	-- what is worn) and puts it on the player's body, Cosmetics/GiftShop sells the alley shirt. Money and every
	-- other item stay on this server. A DataStore failure never blocks play and never takes back a purchase
	-- (PlayerSaves: retry, a notice). The player attributes Clothes (what is worn) and ClothesSaved (the save's state)
	-- are for the Studio check (docs/owner/CLOTHING_SAVE_CHECK.md).
	local saves: any, wardrobe: any, giftShop: any = nil, nil, nil
	local clothesConns: { RBXScriptConnection } = {}
	local clothesRunning = true
	local okClothes, errClothes = pcall(function()
		local store: any = nil
		local okDs, ds = pcall(function(): any
			return game:GetService("DataStoreService"):GetDataStore(PlayerSaves.STORE)
		end)
		if okDs then
			store = ds
		else
			warn(`[SpicyRodents] no DataStore, clothing is not saved on this server: {ds}`)
		end
		saves = PlayerSaves.new({
			store = store,
			-- (each Studio session its own id: two Studio sessions never take each other's lock for their own)
			jobId = if game.JobId ~= ""
				then game.JobId
				else `studio-{game:GetService("HttpService"):GenerateGUID(false)}`,
			now = os.time,
			sleep = function(seconds: number)
				task.wait(seconds)
			end,
			spawn = function(fn: () -> ())
				task.spawn(fn)
			end,
			tell = function(player: any, words: string)
				fire(player, { kind = "notice", text = words })
			end,
			loaded = function(player: any, profileData: any): boolean
				return wardrobe ~= nil and wardrobe:loaded(player, profileData)
			end,
			pending = function(player: any): boolean
				return wardrobe ~= nil and wardrobe:pending(player)
			end,
			changed = function(player: any, state: string)
				setAttr(player, "ClothesSaved", state)
			end,
		})
		wardrobe = Wardrobe.new({
			saves = saves,
			bodyOf = function(player: any): (any?, string?)
				local a = possession:actorOf(player)
				return if a and a.body then a.body else nil, if a then a.species else nil
			end,
			players = function(): { any }
				return Players:GetPlayers()
			end,
			setAttr = setAttr,
		})
		giftShop = GiftShop.start({
			attractions = workspace:FindFirstChild("Attractions"),
			wallet = wallet,
			wardrobe = wardrobe,
			possession = possession,
			tell = function(player: any, words: string)
				fire(player, { kind = "notice", text = words })
			end,
		})
		if o.players ~= false then
			for _, player in Players:GetPlayers() do
				saves:join(player)
			end
			table.insert(
				clothesConns,
				Players.PlayerAdded:Connect(function(player: Player)
					wardrobe:join(player)
					saves:join(player)
				end)
			)
			table.insert(
				clothesConns,
				Players.PlayerRemoving:Connect(function(player: Player)
					wardrobe:leave(player)
					saves:leave(player)
				end)
			)
			game:BindToClose(function()
				saves:closeAll()
			end)
		end
		if o.heartbeat ~= false then
			task.spawn(function()
				while clothesRunning do
					task.wait(1)
					local okStep, errStep = pcall(function()
						wardrobe:sweep()
						saves:step(os.time())
					end)
					if not okStep then
						warn(`[SpicyRodents] clothing step failed: {errStep}`)
					end
				end
			end)
		end
	end)
	if not okClothes then
		warn(`[SpicyRodents] clothing saving failed to start: {errClothes}`)
	end

	mark("total", t0)
	ReplicatedStorage:SetAttribute("BootSeconds", timings.total)
	stage(1, "Ready")
	ReplicatedStorage:SetAttribute("BootReady", true)

	-- The trees' normal and roughness maps arrive after the town is playable (each tree already shows
	-- its colour texture): Assets/TreeArt loads the uploaded models one by one, off the boot path, and swaps in
	-- the new generator's tree for every trunk whose v2 Model has an id (Generated/TreeArtNext).
	if town and o.heartbeat ~= false then
		task.spawn(function()
			local okT, report = pcall(TreeArt.run, town)
			if okT then
				print(
					`[SpicyRodents] tree art: {report.swapped}/{report.trees} trees swapped for the new models, {report.upgraded} with full maps, {report.failed} failed, {math.floor(
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

	-- The owner's finished pinball models (Workspace.Attractions.<alley>.GamesRoom.Pinball<i>): Assets/PinballArt
	-- puts them on the baked machines off the boot path, once every Model is uploaded (until then it says so once)
	PinballArt.start(workspace:FindFirstChild("Attractions"), { heartbeat = o.heartbeat ~= false })
	-- and the owner's whack-a-mole cabinet in the same games room (Assets/WhackArt; nothing while it has no id)
	WhackArt.startIn(workspace:FindFirstChild("Attractions"), { heartbeat = o.heartbeat ~= false })
	-- and THE GILDED ACORN's Blender pieces (Assets/LoungeArt; nothing while Shared/Attractions/LoungeArt has no id)
	if o.heartbeat ~= false then
		LoungeArt.start()
	end

	return {
		runtime = rt,
		traffic = traffic,
		movement = movement,
		wallet = wallet,
		timings = timings,
		pick = pick,
		kick = kick,
		remotes = { Pick = onPick, Kick = onKick, Duel = onDuel },
		kill = kill,
		combat = combat,
		step = function(dt: number)
			rt.step(dt)
			step(dt)
			if attractions and o.heartbeat == false then
				attractions.step(dt)
			end
			if skylift and o.heartbeat == false then
				skylift:step(dt)
			end
			if lounge and o.heartbeat == false then
				lounge:step(dt)
			end
			if cornerStore and o.heartbeat == false then
				cornerStore:step()
			end
			if dogs and o.heartbeat == false then
				dogs.step(dt)
			end
			if wardrobe and o.heartbeat == false then
				wardrobe:sweep()
			end
		end,
		stateOf = stateOf,
		health = healthOf,
		placeAI = placeAI,
		attractions = attractions,
		infection = infection,
		sewers = sewers,
		hollows = hollows,
		forage = forage,
		skylift = skylift,
		rafters = rafters,
		overhead = overhead,
		townSquirrels = townSquirrels,
		roadSquirrels = roadSquirrels,
		lounge = lounge,
		cornerStore = cornerStore,
		dogs = dogs,
		clothes = { saves = saves, wardrobe = wardrobe, giftShop = giftShop },
		townIdOf = function(actorId: string): number?
			return townIdOf[actorId]
		end,
		stop = function()
			rt.stop()
			if attractions then
				attractions.stop()
			end
			if sewers then
				sewers:stop()
			end
			if hollows then
				hollows:stop()
			end
			if forage then
				forage:stop()
			end
			if skylift then
				skylift:stop()
			end
			if rafters then
				rafters:stop()
			end
			if overhead then
				overhead:stop()
			end
			if townSquirrels then
				townSquirrels:stop()
			end
			if roadSquirrels then
				roadSquirrels:stop()
			end
			if lounge then
				lounge:stop()
			end
			if cornerStore and cornerStore.stop then
				cornerStore.stop()
			end
			if dogs then
				dogs.stop()
			end
			clothesRunning = false
			for _, c in clothesConns do
				c:Disconnect()
			end
			if giftShop then
				giftShop.stop()
			end
			for _, c in conns do
				c:Disconnect()
			end
		end,
	}
end

return Game
