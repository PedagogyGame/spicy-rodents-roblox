--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Controllers.Drone
-- W0 (spike S11) test-drone flight: the client owns the drone's unanchored root, cancels gravity
-- with a local VectorForce and writes CFrame and velocity every PreSimulation (as the squirrel
-- motor does). WASD fly camera-relative on the level, Space/E up, LeftControl/Q down, LeftShift
-- boosts (so the owner can cover 2 km in seconds). The camera follows the drone root. Streaming
-- follows Player.ReplicationFocus, which the server points at this root while flying (F-13).
-- W1's device controller (BUILD_PLAN §1.5 Devices) replaces it behind the same start/stop.
-- No side effects on require.
-- Interface: start(drone, opts?) -> stop()

export type Opts = { speed: number?, boost: number?, vertical: number?, ceiling: number? }

local Drone = {}

function Drone.start(drone: Model, opts: Opts?): () -> ()
	local RunService = game:GetService("RunService")
	local UserInputService = game:GetService("UserInputService")
	local o = opts or {}
	local speed, boost, vertical = o.speed or 80, o.boost or 300, o.vertical or 60
	local ceiling = o.ceiling or 1500
	local root = drone.PrimaryPart
	if root == nil then
		return function() end
	end
	local rootPart = root :: BasePart
	local attach = Instance.new("Attachment")
	attach.Parent = rootPart
	local antiGravity = Instance.new("VectorForce")
	antiGravity.Attachment0 = attach
	antiGravity.RelativeTo = Enum.ActuatorRelativeTo.World
	antiGravity.ApplyAtCenterOfMass = true
	antiGravity.Force = Vector3.new(0, rootPart.AssemblyMass * workspace.Gravity, 0)
	antiGravity.Parent = rootPart

	local camera = workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Custom
	camera.CameraSubject = rootPart
	local pos = rootPart.Position
	local vel = Vector3.zero
	local yaw = 0

	local function key(k: Enum.KeyCode): number
		return if UserInputService:IsKeyDown(k) then 1 else 0
	end

	local conn = RunService.PreSimulation:Connect(function(dt: number)
		local cam = camera.CFrame
		local fwd = Vector3.new(cam.LookVector.X, 0, cam.LookVector.Z)
		fwd = if fwd.Magnitude > 1e-3 then fwd.Unit else Vector3.new(0, 0, -1)
		local right = Vector3.new(-fwd.Z, 0, fwd.X)
		local f = key(Enum.KeyCode.W) + key(Enum.KeyCode.Up) - key(Enum.KeyCode.S) - key(Enum.KeyCode.Down)
		local r = key(Enum.KeyCode.D) + key(Enum.KeyCode.Right) - key(Enum.KeyCode.A) - key(Enum.KeyCode.Left)
		local u = math.clamp(
			key(Enum.KeyCode.Space) + key(Enum.KeyCode.E) - key(Enum.KeyCode.LeftControl) - key(Enum.KeyCode.Q),
			-1,
			1
		)
		local wish = fwd * f + right * r
		if wish.Magnitude > 1 then
			wish = wish.Unit
		end
		local s = if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then boost else speed
		local target = wish * s + Vector3.new(0, u * (if s > speed then vertical * 3 else vertical), 0)
		vel += (target - vel) * math.min(1, 4 * dt)
		pos += vel * dt
		pos = Vector3.new(pos.X, math.clamp(pos.Y, -50, ceiling), pos.Z)
		if wish.Magnitude > 0.1 then
			yaw = math.atan2(-wish.X, -wish.Z)
		end
		rootPart.CFrame = CFrame.new(pos) * CFrame.Angles(0, yaw, 0)
		rootPart.AssemblyLinearVelocity = vel
		rootPart.AssemblyAngularVelocity = Vector3.zero
	end)
	return function()
		conn:Disconnect()
		antiGravity:Destroy()
		attach:Destroy()
	end
end

return Drone
