--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Controllers.Squirrel
-- W0 (spike S2) ground motor for a possessed non-Humanoid squirrel body (the AnimationController
-- puppet). The client owns the unanchored assembly and writes its root CFrame and velocity every
-- PreSimulation; a local VectorForce cancels gravity between writes (it exists only where the
-- assembly is simulated, on this client). Input is the default PlayerModule move vector, made
-- camera-relative; Shift sprints. The motor resumes where the body is rendered on this client
-- with the snapshot's heading and momentum, holding the AI's direction for up to 0.75 s or until
-- the first input, so the handoff shows no visual jump for the possessor; the gap between the
-- rendered and the server's snapshot position is recorded (metrics.gap) for the S2 checklist.
-- W1 replaces this with Shared/Movement/SquirrelMotor (rails, S3) behind the same start/stop.
-- No side effects on require.
-- Interface: start(body, payload, metrics, opts?) -> stop()

local Import = require("../Import")
local PossessionState =
	Import.shared("Actors/PossessionState") :: typeof(require("../../shared/Actors/PossessionState"))

export type Metrics = { [string]: any }
export type Opts = { walk: number?, sprint: number?, accel: number?, ignore: { Instance }? }

local Squirrel = {}

function Squirrel.start(body: Model, payload: PossessionState.GrantPayload, metrics: Metrics, opts: Opts?): () -> ()
	local RunService = game:GetService("RunService")
	local UserInputService = game:GetService("UserInputService")
	local Players = game:GetService("Players")
	local o = opts or {}
	local walk = o.walk or 20 -- 8 u/s (Species.squirrel.speeds.walk)
	local sprint = o.sprint or 42 -- 16.8 u/s
	local accel = o.accel or 10 -- 1/s approach rate
	local root = body.PrimaryPart
	if root == nil then
		return function() end
	end
	local rootPart = root :: BasePart

	local snap = payload.snapshot
	local pos = rootPart.Position
	local yaw = snap.yaw
	local vel = Vector3.new(snap.vx, 0, snap.vz)
	local holdUntil = os.clock() + payload.holdSeconds
	local holding = vel.Magnitude > 0.1

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = o.ignore or { body }
	local function groundY(p: Vector3): number?
		local hit = workspace:Raycast(p + Vector3.new(0, 6, 0), Vector3.new(0, -40, 0), params)
		return if hit then hit.Position.Y else nil
	end
	local g0 = groundY(pos)
	local hip = if g0 then pos.Y - g0 else 0.5

	local antiGravity = Instance.new("VectorForce")
	local attach = Instance.new("Attachment")
	attach.Parent = rootPart
	antiGravity.Attachment0 = attach
	antiGravity.RelativeTo = Enum.ActuatorRelativeTo.World
	antiGravity.ApplyAtCenterOfMass = true
	antiGravity.Force = Vector3.new(0, rootPart.AssemblyMass * workspace.Gravity, 0)
	antiGravity.Parent = rootPart

	local ctl: any? = nil
	pcall(function()
		local ps = (Players.LocalPlayer :: any).PlayerScripts :: Instance
		ctl = (require :: any)(ps:WaitForChild("PlayerModule", 5)):GetControls()
	end)
	local inputAt: number? = nil
	local inputVel = Vector3.zero

	local conns = {}
	table.insert(
		conns,
		RunService.PreSimulation:Connect(function(dt: number)
			local move = if ctl then ctl:GetMoveVector() :: Vector3 else Vector3.zero
			local target: Vector3
			if move.Magnitude > 0.05 then
				holding = false
				if inputAt == nil then
					inputAt = os.clock()
					inputVel = vel
				end
				local cam = workspace.CurrentCamera.CFrame
				local fwd = Vector3.new(cam.LookVector.X, 0, cam.LookVector.Z)
				fwd = if fwd.Magnitude > 1e-3 then fwd.Unit else Vector3.new(0, 0, -1)
				local right = Vector3.new(-fwd.Z, 0, fwd.X)
				local wish = right * move.X - fwd * move.Z
				local speed = if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then sprint else walk
				target = (if wish.Magnitude > 1 then wish.Unit else wish) * speed
			elseif holding and os.clock() < holdUntil then
				target = vel
			else
				holding = false
				target = Vector3.zero
			end
			vel += (target - vel) * math.min(1, accel * dt)
			pos += vel * dt
			if vel.Magnitude > 0.5 then
				yaw = math.atan2(-vel.X, -vel.Z)
			end
			local gy = groundY(pos)
			if gy then
				pos = Vector3.new(pos.X, gy + hip, pos.Z)
			end
			rootPart.CFrame = CFrame.new(pos) * CFrame.Angles(0, yaw, 0)
			rootPart.AssemblyLinearVelocity = vel
			rootPart.AssemblyAngularVelocity = Vector3.zero
			local t0 = inputAt
			if t0 and metrics.inputToMoveMs == nil and (vel - inputVel).Magnitude > 1 then
				metrics.inputToMoveMs = math.floor((os.clock() - t0) * 1000 + 0.5)
			end
		end)
	)
	return function()
		for _, c in conns do
			c:Disconnect()
		end
		antiGravity:Destroy()
		attach:Destroy()
	end
end

return Squirrel
