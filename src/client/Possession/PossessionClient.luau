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
-- Interface: start(opts) -> Client; Client.metrics, Client.markRequest(), Client.current(),
--   Client.state() -> { species, device, decision }; controllerFor(species) -> string (pure)

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

local function findBody(bodies: Instance, actorId: string, timeout: number): Model?
	local deadline = os.clock() + timeout
	repeat
		for _, child in bodies:GetChildren() do
			if child:IsA("Model") and child:GetAttribute(PossessionState.ATTR.ActorId) == actorId then
				return child
			end
		end
		task.wait()
	until os.clock() > deadline
	return nil
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
	local net = ReplicatedStorage:WaitForChild(PossessionState.NET.folder)
	local granted = net:WaitForChild(PossessionState.NET.Granted) :: RemoteEvent
	local released = net:WaitForChild(PossessionState.NET.Released) :: RemoteEvent
	local recover = net:WaitForChild(PossessionState.NET.Recover) :: RemoteEvent
	local deviceGranted = net:FindFirstChild(PossessionState.NET.DeviceGranted) :: RemoteEvent?
	local deviceReleased = net:FindFirstChild(PossessionState.NET.DeviceReleased) :: RemoteEvent?
	local deviceRequest = net:FindFirstChild(PossessionState.NET.DeviceRequest) :: RemoteEvent?

	local world = ClientWorld.get()
	world.ignore({ opts.bodies })
	local input = InputMap.start()

	local metrics: { [string]: any } = { handoffs = 0, resets = 0 }
	local requestAt: number? = nil
	local stopController: (() -> ())? = nil
	local body: Model? = nil
	local payloadNow: { [string]: any }? = nil
	local device: { device: string, model: Model, kind: string? }? = nil
	local fpToggle = false
	local decision: { [string]: any } = CameraPolicy.modeFor({})

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
		local ctx = { world = world, input = input, species = payload.species }
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
			found = findBody(opts.bodies, payload.actorId, 3)
		end
		if found == nil then
			warn(`PossessionClient: body {payload.actorId} did not stream in`)
			if hud then
				hud.toast("Your body did not load; press Reset (Esc menu) to try again", 5)
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
			if model == nil then
				return
			end
			stop()
			device = { device = info.device, model = model, kind = info.kind }
			setJump(false) -- Space is the handbrake / climb: never unseat the driver
			local ctx = { world = world, input = input }
			if info.device == "drone" then
				stopController = Drone.start(model, metrics, ctx)
			else
				world.ignore({ model })
				stopController = Vehicle.start(model, info.kind or "car", metrics, ctx)
			end
			fpToggle = true -- first person on entry; V flips it (brief v2 §14)
			applyCamera()
		end)
	end
	if deviceReleased then
		deviceReleased.OnClientEvent:Connect(function(why: string)
			if device == nil then
				-- a refused request ("no vehicle within reach", "needs the key"): say so
				if hud then
					hud.toast(why, 2.5)
				end
				return
			end
			stop()
			device = nil
			setJump(true)
			local b, p = body, payloadNow
			if b and p then
				startBodyController(b, p)
			end
			fpToggle = false
			applyCamera()
			if hud and why ~= "exit" then
				hud.toast(why, 3)
			end
		end)
	end

	-- verbs that are not motor input: E (enter / exit), V (first-person toggle)
	local UIS = game:GetService("UserInputService")
	UIS.InputBegan:Connect(function(io: InputObject, processed: boolean)
		if processed then
			return
		end
		local name = io.KeyCode.Name
		-- E (pad Y) enters or leaves a vehicle or the drone; only people drive, and a squirrel's E is
		-- its grab (InputMap). F is the townsperson's kick (Client/Main, PlayNet.Kick).
		local onFoot = payloadNow ~= nil and payloadNow.species == "human"
		if (name == "E" or name == "ButtonY") and (device ~= nil or onFoot) then
			if deviceRequest and body then
				deviceRequest:FireServer("interact")
			elseif hud then
				hud.toast(if body then "No vehicles in this build yet" else "You need a body first", 2)
			end
		elseif name == "V" or name == "ButtonR3" then
			if decision.toggleAllowed then
				fpToggle = not fpToggle
				applyCamera()
			elseif hud and body then
				hud.toast("This camera is fixed here", 1.5)
			end
		end
	end)

	routeReset(function()
		metrics.resets += 1
		recover:FireServer()
	end)

	return {
		metrics = metrics,
		markRequest = function()
			requestAt = os.clock()
		end,
		current = function(): Model?
			return body
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
