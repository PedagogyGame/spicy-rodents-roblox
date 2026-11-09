--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Possession.PossessionClient
-- Client half of possession (BUILD_PLAN §1.5, D1, D3; spike S2). On `Granted` it finds the body
-- (player.Character, or by ActorId while it streams in), records the gap between where this
-- client renders the body and the server's snapshot, starts the species controller, points the
-- camera at the body (a LocalScript is the only place a non-Humanoid camera subject can be set)
-- and records request-to-control latency. On `Released` it stops the controller and parks the
-- camera. The Roblox menu's Reset is routed to the server's recovery through
-- StarterGui:SetCore("ResetButtonCallback", BindableEvent): it never kills or respawns a body.
-- No side effects on require.
-- Interface: start(opts) -> Client; Client.metrics, Client.markRequest(), Client.current()

local Import = require("../Import")
local PossessionState =
	Import.shared("Actors/PossessionState") :: typeof(require("../../shared/Actors/PossessionState"))
local CameraRig = require("../Camera/CameraRig")
local Human = require("../Controllers/Human")
local Squirrel = require("../Controllers/Squirrel")

export type Opts = {
	bodies: Instance, -- the folder holding every body
	overview: { position: Vector3, lookAt: Vector3 }?, -- camera when driving nothing
}

export type Client = {
	metrics: { [string]: any },
	markRequest: () -> (),
	current: () -> Model?,
}

local PossessionClient = {}

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
	local net = ReplicatedStorage:WaitForChild(PossessionState.NET.folder)
	local granted = net:WaitForChild(PossessionState.NET.Granted) :: RemoteEvent
	local released = net:WaitForChild(PossessionState.NET.Released) :: RemoteEvent
	local recover = net:WaitForChild(PossessionState.NET.Recover) :: RemoteEvent

	local metrics: { [string]: any } = { handoffs = 0, resets = 0 }
	local requestAt: number? = nil
	local stopController: (() -> ())? = nil
	local body: Model? = nil

	local function stop()
		local s = stopController
		stopController = nil
		if s then
			s()
		end
	end

	granted.OnClientEvent:Connect(function(payload: { [string]: any })
		local t0 = os.clock()
		stop()
		local found = player.Character
		if found == nil or found:GetAttribute(PossessionState.ATTR.ActorId) ~= payload.actorId then
			found = findBody(opts.bodies, payload.actorId, 3)
		end
		if found == nil then
			warn(`PossessionClient: body {payload.actorId} did not stream in`)
			return
		end
		local model = found :: Model
		body = model
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
		if payload.species == "human" then
			stopController = Human.start(model, payload, metrics)
		else
			stopController = Squirrel.start(model, payload, metrics, { ignore = { opts.bodies } })
		end
		CameraRig.follow(model)
		local r = requestAt
		metrics.requestToControlMs = if r then math.floor((os.clock() - r) * 1000 + 0.5) else nil
		metrics.grantToControlMs = math.floor((os.clock() - t0) * 1000 + 0.5)
		requestAt = nil
	end)

	released.OnClientEvent:Connect(function(_actorId: string, why: string)
		stop()
		body = nil
		metrics.species = nil
		metrics.actorId = nil
		metrics.lastRelease = why
		local o = opts.overview
		if o then
			CameraRig.overview(o.position, o.lookAt)
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
	}
end

return PossessionClient
