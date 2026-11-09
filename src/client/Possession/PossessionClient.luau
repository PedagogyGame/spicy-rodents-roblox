--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Possession.PossessionClient
-- Client half of possession (BUILD_PLAN §1.5, D1, D3; spike S2, extended in W1 §4.4 #5). On
-- `Granted` it finds the body (player.Character, or by ActorId while it streams in), records the gap
-- between where this client renders the body and the server's snapshot, starts the species
-- controller (human: Humanoid + handoff hold; squirrel and rodent: SquirrelMotor; fox and deer:
-- QuadrupedMotor), applies the camera from CameraPolicy and shows the HUD line for that body. On
-- `Released` it stops the controller and parks the camera. Devices (§1.5): `DeviceGranted` switches
-- to the Vehicle or Drone controller and the vehicle / drone camera while the body stays possessed;
-- `DeviceReleased` returns to the body. E asks the server to enter the nearest vehicle or get out (people only);
-- V toggles first person where CameraPolicy allows it. The Roblox menu's Reset is routed to the
-- server's recovery through StarterGui:SetCore("ResetButtonCallback", BindableEvent): it never kills
-- or respawns a body.
-- No side effects on require.
-- Robustness (W1 client review): remotes are awaited with timeouts and a missing one is said on
-- screen; the body is awaited up to 15 s while it streams in (the server also makes it persistent for
-- its driver); the default character controls are on for a person on foot and off in a vehicle or the
-- drone (the standing officer no longer walks off while the drone flies); E, V and Reset always answer
-- on screen; device refusals are said in plain words (reasonText).
-- Interface: start(opts) -> Client; Client.metrics, Client.markRequest(), Client.current(), Client.refreshCamera(),
--   Client.state() -> { species, device, decision }; controllerFor(species) -> string (pure);
--   reasonText(why) -> string? (pure; nil = say nothing)

local Import = require("../Import")
local PossessionState =
	Import.shared("Actors/PossessionState") :: typeof(require("../../shared/Actors/PossessionState"))
local CameraRig = require("../Camera/CameraRig")
local CameraPolicy = require("../Camera/CameraPolicy")
local InputMap = require("../Input/InputMap")
local ClientWorld = require("../World/ClientWorld")
local Human = require("../Controllers/Human")
local Squirrel = require("../Controllers/Squirrel")
local Quadruped = require("../Controllers/Quadruped")
local Vehicle = require("../Controllers/Vehicle")
local Drone = require("../Controllers/Drone")

export type Opts = {
	bodies: Instance, -- the folder holding every body
	overview: { position: Vector3, lookAt: Vector3 }?, -- camera when driving nothing
	hud: { set: (string, string) -> (), toast: (string, number?) -> () }?,
}

export type Client = {
	metrics: { [string]: any },
	markRequest: () -> (),
	current: () -> Model?,
	refreshCamera: () -> (),
	state: () -> { [string]: any },
}

local PossessionClient = {}

local TITLES = {
	human = "You are a townsperson",
	squirrel = "You are a squirrel",
	rodent = "You are the spicy rodent",
	fox = "You are the fox",
	deer = "You are a deer",
}

-- controllerFor(species, variant?): which controller drives a body (pure; Lune-tested).
function PossessionClient.controllerFor(species: string, variant: string?): string
	if species == "human" then
		return "human"
	elseif species == "squirrel" or species == "rodent" or variant == "spicy" then
		return "squirrel"
	end
	return "quadruped"
end

-- Plain words for the server's device and release reasons (pure; Lune and the Playtest smoke check
-- it). nil means say nothing (a normal exit).
local REASONS: { [string]: string } = {
	exit = "",
	swap = "",
	release = "",
	["no vehicle within reach"] = "No car or drone within reach: walk right up to it, then press E",
	["only people drive"] = "Only people can drive. Pick Townsperson or Police from the menu (M)",
	["the drone is in use"] = "Someone else is flying the drone",
	["no body"] = "Pick a body from the menu first (M)",
	["cannot"] = "You cannot get in right now",
}
function PossessionClient.reasonText(why: string?): string?
	if why == nil then
		return nil
	end
	local t = REASONS[why]
	if t == "" then
		return nil
	end
	if t then
		return t
	end
	if string.find(why, "key", 1, true) then
		return "That car is locked: police cars are for officers (pick Police)"
	end
	return `Cannot do that: {why}`
end

local function findBody(player: Player, bodies: Instance, actorId: string, timeout: number): Model?
	local deadline = os.clock() + timeout
	repeat
		local c = player.Character
		if c and c:GetAttribute(PossessionState.ATTR.ActorId) == actorId then
			return c
		end
		for _, child in bodies:GetChildren() do
			if child:IsA("Model") and child:GetAttribute(PossessionState.ATTR.ActorId) == actorId then
				return child
			end
		end
		task.wait(0.05)
	until os.clock() > deadline
	return nil
end

-- the body's root (parts of a streamed model can arrive a moment after the model)
local function rootOf(model: Model, timeout: number): BasePart?
	local deadline = os.clock() + timeout
	while model.PrimaryPart == nil and os.clock() < deadline and model.Parent ~= nil do
		task.wait(0.05)
	end
	return model.PrimaryPart
end

-- SetCore fails until the CoreScripts have registered the callback; retry for a while.
local function routeReset(onReset: () -> ())
	local StarterGui = game:GetService("StarterGui")
	local bindable = Instance.new("BindableEvent")
	bindable.Event:Connect(onReset)
	task.spawn(function()
		for _ = 1, 50 do
			local ok = pcall(function()
				StarterGui:SetCore("ResetButtonCallback", bindable)
			end)
			if ok then
				return
			end
			task.wait(0.2)
		end
		warn("PossessionClient: could not route the Reset button")
	end)
end

function PossessionClient.start(opts: Opts): Client
	local Players = game:GetService("Players")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local player = Players.LocalPlayer
	local hud = opts.hud
	if hud then
		hud.set("Connecting to the town…", "Waiting for the server to hand you a body")
	end
	local function need(parent: Instance?, name: string): Instance
		local found = if parent then parent:WaitForChild(name, 30) else nil
		if found == nil then
			if hud then
				hud.set("The game did not finish starting", `Missing {name}: press F9 and send the red lines`)
			end
			error(`PossessionClient: {name} missing after 30 s`)
		end
		return found :: Instance
	end
	local net = need(ReplicatedStorage, PossessionState.NET.folder)
	local granted = need(net, PossessionState.NET.Granted) :: RemoteEvent
	local released = need(net, PossessionState.NET.Released) :: RemoteEvent
	local recover = need(net, PossessionState.NET.Recover) :: RemoteEvent
	local deviceGranted = net:FindFirstChild(PossessionState.NET.DeviceGranted) :: RemoteEvent?
	local deviceReleased = net:FindFirstChild(PossessionState.NET.DeviceReleased) :: RemoteEvent?
	local deviceRequest = net:FindFirstChild(PossessionState.NET.DeviceRequest) :: RemoteEvent?

	local world = ClientWorld.get()
	world.ignore({ opts.bodies })
	local input = InputMap.start()
	local function toast(text: string, seconds: number?)
		if hud then
			hud.toast(text, seconds)
		end
	end
	-- no body yet (the join hands a townsperson; until then): a parked view of the town, never the void
	if player.Character == nil and opts.overview then
		CameraRig.overview(opts.overview.position, opts.overview.lookAt)
	end

	local metrics: { [string]: any } = { handoffs = 0, resets = 0 }
	local requestAt: number? = nil
	local stopController: (() -> ())? = nil
	local body: Model? = nil
	local payloadNow: { [string]: any }? = nil
	local device: { device: string, model: Model, kind: string? }? = nil
	local fpToggle = false
	local decision: { [string]: any } = CameraPolicy.modeFor({})
	local zoneConn: RBXScriptConnection? = nil

	local function stop()
		local s = stopController
		stopController = nil
		if s then
			s()
		end
	end

	local function setJump(on: boolean)
		local b = body
		local hum = if b then b:FindFirstChildOfClass("Humanoid") else nil
		if hum then
			hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, on)
		end
	end

	local function applyCamera()
		local p = payloadNow
		local ctx = {
			species = if p then (if p.variant == "spicy" then "rodent" else p.species) else nil,
			vehicle = if device and device.device == "vehicle" then device.kind else nil,
			drone = device ~= nil and device.device == "drone",
			firstPersonToggle = fpToggle,
			zone = if body then body:GetAttribute("CameraZone") :: string? else nil,
			chase = if body then body:GetAttribute("ChaseLock") == true else false,
		}
		decision = CameraPolicy.modeFor(ctx)
		CameraRig.apply(decision :: any, {
			body = body,
			vehicle = if device and device.device == "vehicle" then device.model else nil,
			drone = if device and device.device == "drone" then device.model else nil,
		})
		if hud then
			local role = if device
				then device.device
				elseif p then PossessionClient.controllerFor(p.species, p.variant)
				else ""
			local title = if device and device.device == "vehicle"
				then `Driving a {device.kind}`
				elseif device then "Flying the police drone"
				elseif p then (TITLES[ctx.species or ""] or `You are a {p.species}`)
				else "Watching the town"
			hud.set(title, InputMap.HINTS(role))
		end
	end

	local function startBodyController(model: Model, payload: { [string]: any })
		local kind = PossessionClient.controllerFor(payload.species, payload.variant)
		local ctx = { world = world, input = input, species = payload.species, toast = toast }
		-- the default controls walk and jump a Humanoid; motor-driven bodies have none, so this is
		-- harmless for them and needed for a person (a vehicle or the drone turned them off)
		InputMap.setCharacterControls(true)
		if kind == "human" then
			stopController = Human.start(model, payload, metrics)
		elseif kind == "squirrel" then
			stopController = Squirrel.start(model, payload, metrics, ctx)
		else
			stopController = Quadruped.start(model, payload, metrics, ctx)
		end
	end

	granted.OnClientEvent:Connect(function(payload: { [string]: any })
		local t0 = os.clock()
		stop()
		device = nil
		local found = player.Character
		if found == nil or found:GetAttribute(PossessionState.ATTR.ActorId) ~= payload.actorId then
			if hud then
				hud.set("Loading your body…", "Streaming the town around it")
			end
			found = findBody(player, opts.bodies, payload.actorId, 15)
		end
		if found == nil or rootOf(found :: Model, 5) == nil then
			warn(`PossessionClient: body {payload.actorId} did not stream in`)
			toast("Your body did not load. Press M and pick again.", 6)
			if hud then
				hud.set("Your body did not load", "Press M and pick again")
			end
			return
		end
		local model = found :: Model
		body = model
		payloadNow = payload
		payload.variant = payload.variant or model:GetAttribute("Variant")
		local root = model.PrimaryPart
		local snap = payload.snapshot
		if root then
			local rendered = root.Position
			metrics.gap = (Vector3.new(rendered.X, 0, rendered.Z) - Vector3.new(snap.x, 0, snap.z)).Magnitude
		end
		metrics.species = payload.species
		metrics.actorId = payload.actorId
		metrics.grantLatencyMs = math.floor((workspace:GetServerTimeNow() - payload.serverTime) * 1000 + 0.5)
		metrics.inputToMoveMs = nil
		metrics.handoffs += 1
		fpToggle = false
		startBodyController(model, payload)
		applyCamera()
		-- zone changes (the squirrel entering the bowling alley's tunnel) re-pick the camera
		if zoneConn then
			zoneConn:Disconnect()
		end
		zoneConn = model:GetAttributeChangedSignal("CameraZone"):Connect(function()
			if body == model and device == nil then
				applyCamera()
			end
		end)
		local r = requestAt
		metrics.requestToControlMs = if r then math.floor((os.clock() - r) * 1000 + 0.5) else nil
		metrics.grantToControlMs = math.floor((os.clock() - t0) * 1000 + 0.5)
		requestAt = nil
	end)

	released.OnClientEvent:Connect(function(_actorId: string, why: string)
		stop()
		body = nil
		payloadNow = nil
		device = nil
		metrics.species = nil
		metrics.actorId = nil
		metrics.lastRelease = why
		local o = opts.overview
		if o then
			CameraRig.overview(o.position, o.lookAt)
		end
		if hud then
			hud.set("Watching the town", `Released ({why}). Waiting for a new body…`)
		end
	end)

	if deviceGranted then
		deviceGranted.OnClientEvent:Connect(function(info: { [string]: any })
			local model = info.model :: Model?
			if model == nil or rootOf(model :: Model, 3) == nil then
				-- not streamed in on this computer: get out again rather than drive nothing
				toast("The vehicle has not loaded on your screen yet: try E again in a moment", 4)
				if deviceRequest then
					deviceRequest:FireServer("interact")
				end
				return
			end
			local m = model :: Model
			stop()
			device = { device = info.device, model = m, kind = info.kind }
			setJump(false) -- Space is the handbrake / climb: never unseat the driver
			InputMap.setCharacterControls(false) -- the seated or standing body must not walk or jump
			local hum = if body then body:FindFirstChildOfClass("Humanoid") else nil
			if hum then
				hum:Move(Vector3.zero)
			end
			local ctx = { world = world, input = input }
			world.ignore({ m })
			if info.device == "drone" then
				stopController = Drone.start(m, metrics, ctx)
				toast("Flying the police drone. WASD fly, Space up, Q down, E lands.", 4)
			else
				stopController = Vehicle.start(m, info.kind or "car", metrics, ctx)
				toast("Driving. W gas, S brake, A/D steer, V view, E gets out.", 4)
			end
			fpToggle = true -- first person on entry; V flips it (brief v2 §14)
			applyCamera()
		end)
	end
	if deviceReleased then
		deviceReleased.OnClientEvent:Connect(function(why: string)
			if device == nil then
				-- a refused request ("no vehicle within reach", "needs the key"): say so
				local text = PossessionClient.reasonText(why)
				if text then
					toast(text, 3)
				end
				return
			end
			stop()
			device = nil
			setJump(true)
			local b, p = body, payloadNow
			if b and p then
				local hum = b:FindFirstChildOfClass("Humanoid")
				if hum then
					hum.Sit = false
				end
				-- back on foot where the server put us: no AI stride to carry on
				local fresh = table.clone(p)
				fresh.snapshot = table.clone(p.snapshot or {})
				fresh.snapshot.vx, fresh.snapshot.vz = 0, 0
				fresh.holdSeconds = 0
				startBodyController(b, fresh)
			end
			fpToggle = false
			applyCamera()
			local text = PossessionClient.reasonText(why)
			if text then
				toast(text, 3)
			end
		end)
	end

	-- verbs that are not motor input: E (enter / exit), V (first-person toggle)
	local UIS = game:GetService("UserInputService")
	UIS.InputBegan:Connect(function(io: InputObject, processed: boolean)
		if InputMap.ignore(io, processed) then
			return
		end
		local name = io.KeyCode.Name
		-- E (pad Y) enters or leaves a vehicle or the drone; only people drive, and a squirrel's E is
		-- its grab (InputMap). F is the townsperson's kick (Client/Main, PlayNet.Kick).
		local onFoot = payloadNow ~= nil and payloadNow.species == "human"
		if name == "E" or name == "ButtonY" then
			-- a minigame or door prompt on screen (or a game in progress) owns E (Client/Minigames)
			if device == nil and (player:GetAttribute("PromptVisible") or player:GetAttribute("InMinigame")) then
				return
			end
			if device ~= nil or onFoot then
				if deviceRequest and body then
					deviceRequest:FireServer("interact")
				else
					toast(if body then "No vehicles in this build yet" else "Pick a body from the menu first (M)", 2)
				end
			elseif body == nil then
				toast("Pick a body from the menu first (M)", 2)
			end
		elseif name == "V" or name == "ButtonR3" then
			if decision.toggleAllowed then
				fpToggle = not fpToggle
				applyCamera()
			elseif body then
				toast("Animals keep the camera behind them (V is for people and cars)", 2)
			else
				toast("Pick a body from the menu first (M)", 2)
			end
		end
	end)

	routeReset(function()
		metrics.resets += 1
		if body == nil then
			toast("Nothing to reset: pick a body from the menu (M)", 3)
			return
		end
		recover:FireServer()
		toast("Moved you to a safe spot", 2)
	end)

	return {
		metrics = metrics,
		markRequest = function()
			requestAt = os.clock()
		end,
		current = function(): Model?
			return body
		end,
		refreshCamera = function()
			applyCamera()
		end,
		state = function(): { [string]: any }
			return {
				species = if payloadNow then payloadNow.species else nil,
				device = if device then device.device else nil,
				decision = decision,
			}
		end,
	}
end

return PossessionClient
