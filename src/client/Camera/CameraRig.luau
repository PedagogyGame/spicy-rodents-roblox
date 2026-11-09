--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Camera.CameraRig
-- Per-mode camera rigs from Camera/CameraPolicy (BUILD_PLAN §1.4 Camera/CameraRig, §4.4 #5; brief v2
-- §14). Modes:
--   humanThird / humanFirst  the default Roblox camera on the Humanoid; first person through
--                            Player.CameraMode = LockFirstPerson (the V toggle flips it)
--   lockFirst                LockFirstPerson with the toggle refused (arena, lounges)
--   animalThird              the default follow camera on the body's Head (else PrimaryPart), zoom
--                            limits sized to the body (the subject is set from a LocalScript because
--                            the engine only auto-assigns Humanoid subjects)
--   chaseLock                scriptable: behind the body along its facing, looking forward
--   vehicleFirst             scriptable at the vehicle's EyeSocket; mouse/right-stick look within
--                            +/-110 degrees of the nose; vehicleThird follows the vehicle root
--   drone                    the follow camera on the drone root
--   overview / outbreak      a parked scriptable shot
-- Interface: apply(decision, targets) where targets = { body?, vehicle?, drone? }; follow(body);
--   overview(position, lookAt); subjectOf(body); stop()
-- No side effects on require (services are looked up inside the functions).

local CameraRig = {}

local BIND = "SpicyCameraRig"
local bound = false
local onUnbind: (() -> ())? = nil

local function unbind()
	if bound then
		game:GetService("RunService"):UnbindFromRenderStep(BIND)
		bound = false
	end
	local f = onUnbind
	onUnbind = nil
	if f then
		f()
	end
	local UIS = game:GetService("UserInputService")
	UIS.MouseBehavior = Enum.MouseBehavior.Default
end

local function bind(fn: (dt: number) -> ())
	unbind()
	game:GetService("RunService"):BindToRenderStep(BIND, Enum.RenderPriority.Camera.Value - 1, fn)
	bound = true
end

function CameraRig.subjectOf(body: Model): Instance?
	local humanoid = body:FindFirstChildOfClass("Humanoid")
	if humanoid then
		return humanoid
	end
	return body:FindFirstChild("Head") or body.PrimaryPart
end

local function setFirstPerson(on: boolean)
	local player = game:GetService("Players").LocalPlayer
	if on then
		player.CameraMode = Enum.CameraMode.LockFirstPerson
	else
		player.CameraMode = Enum.CameraMode.Classic
		player.CameraMinZoomDistance = 0.5
	end
end

-- A smoothed, client-only focus part for bodies without a Humanoid (squirrels, the rodent, fox,
-- deer, vehicles, the drone). Following the rig's Head or raw root made the camera bounce with the
-- gait's head nod and body bob (owner feedback 2026-11-09): the focus tracks the root quickly in X/Z
-- and slowly in Y, so running is steady while climbing still follows.
local focus: BasePart? = nil
local function focusPart(): BasePart
	local f = focus
	if f and f.Parent then
		return f
	end
	local p = Instance.new("Part")
	p.Name = "SpicyCameraFocus"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Transparency = 1
	p.Size = Vector3.new(0.2, 0.2, 0.2)
	p.Parent = workspace.CurrentCamera -- local to this client, never replicated
	focus = p
	return p
end

function CameraRig.follow(body: Model)
	unbind()
	local camera = workspace.CurrentCamera
	local humanoid = body:FindFirstChildOfClass("Humanoid")
	if humanoid then
		camera.CameraType = Enum.CameraType.Custom
		camera.CameraSubject = humanoid
		return
	end
	local root = body.PrimaryPart
	if root == nil then
		local subject = CameraRig.subjectOf(body)
		if subject then
			camera.CameraType = Enum.CameraType.Custom
			camera.CameraSubject = subject :: any
		end
		return
	end
	local rootPart = root :: BasePart
	local f = focusPart()
	local _, size = body:GetBoundingBox()
	local lift = math.max(0.6, size.Y * 0.6) -- look slightly above the body, not at its feet
	local pos = rootPart.Position + Vector3.new(0, lift, 0)
	f.CFrame = CFrame.new(pos)
	camera.CameraType = Enum.CameraType.Custom
	camera.CameraSubject = f
	bind(function(dt: number)
		if rootPart.Parent == nil then
			return
		end
		local target = rootPart.Position + Vector3.new(0, lift, 0)
		local a = 1 - math.exp(-dt * 25) -- horizontal: tight
		local b = 1 - math.exp(-dt * 7) -- vertical: smooths bob and terrain steps
		pos =
			Vector3.new(pos.X + (target.X - pos.X) * a, pos.Y + (target.Y - pos.Y) * b, pos.Z + (target.Z - pos.Z) * a)
		-- never lag more than 3 studs (teleports, respawns, long drops)
		if (target - pos).Magnitude > 3 then
			pos = target
		end
		f.CFrame = CFrame.new(pos)
	end)
end

function CameraRig.overview(position: Vector3, lookAt: Vector3)
	unbind()
	setFirstPerson(false)
	local camera = workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = CFrame.lookAt(position, lookAt)
end

function CameraRig.stop()
	unbind()
end

local function sizeOf(model: Model): number
	local _, size = model:GetBoundingBox()
	return math.max(size.X, size.Y, size.Z)
end

export type Targets = { body: Model?, vehicle: Model?, drone: Model? }

function CameraRig.apply(decision: { mode: string, firstPerson: boolean }, targets: Targets)
	local Players = game:GetService("Players")
	local UIS = game:GetService("UserInputService")
	local player = Players.LocalPlayer
	local camera = workspace.CurrentCamera
	local mode = decision.mode
	if mode == "humanThird" or mode == "humanFirst" or mode == "lockFirst" then
		local body = targets.body
		if body then
			CameraRig.follow(body)
			player.CameraMaxZoomDistance = 40
			setFirstPerson(mode ~= "humanThird")
		end
	elseif mode == "animalThird" then
		local body = targets.body
		if body then
			setFirstPerson(false)
			CameraRig.follow(body)
			local s = sizeOf(body)
			player.CameraMinZoomDistance = math.max(2, s * 1.5)
			player.CameraMaxZoomDistance = math.max(24, s * 10)
		end
	elseif mode == "chaseLock" then
		local body = targets.body
		local root = body and body.PrimaryPart
		if root then
			setFirstPerson(false)
			camera.CameraType = Enum.CameraType.Scriptable
			local dist = math.max(6, sizeOf(body :: Model) * 4)
			bind(function()
				local cf = root.CFrame
				local back = cf.Position - cf.LookVector * dist + Vector3.new(0, dist * 0.45, 0)
				camera.CFrame = CFrame.lookAt(back, cf.Position + cf.LookVector * dist)
			end)
		end
	elseif mode == "vehicleFirst" then
		local vehicle = targets.vehicle
		local eye = vehicle and vehicle:FindFirstChild("EyeSocket", true)
		if eye and eye:IsA("Attachment") then
			setFirstPerson(false)
			camera.CameraType = Enum.CameraType.Scriptable
			local yaw, pitch = 0, 0
			-- the eye sits where the driver's head is: hide the driver's own body on this screen
			-- (the default camera does this only for its own first person)
			local hidden: { BasePart } = {}
			local driver = targets.body
			bind(function()
				if driver and #hidden == 0 then
					for _, d in driver:GetDescendants() do
						if d:IsA("BasePart") then
							table.insert(hidden, d)
						end
					end
				end
				for _, part in hidden do
					part.LocalTransparencyModifier = 1
				end
				if UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then
					UIS.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
					local d = UIS:GetMouseDelta()
					yaw = math.clamp(yaw - d.X * 0.004, -1.9, 1.9)
					pitch = math.clamp(pitch - d.Y * 0.004, -0.9, 0.7)
				else
					UIS.MouseBehavior = Enum.MouseBehavior.Default
					yaw *= 0.92
					pitch *= 0.92
				end
				camera.CFrame = eye.WorldCFrame * CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)
			end)
			onUnbind = function()
				for _, part in hidden do
					part.LocalTransparencyModifier = 0
				end
			end
		elseif vehicle then
			CameraRig.follow(vehicle)
		end
	elseif mode == "vehicleThird" then
		local vehicle = targets.vehicle
		if vehicle then
			setFirstPerson(false)
			CameraRig.follow(vehicle)
			player.CameraMinZoomDistance = 8
			player.CameraMaxZoomDistance = 60
		end
	elseif mode == "drone" then
		local drone = targets.drone
		if drone then
			setFirstPerson(false)
			CameraRig.follow(drone)
			player.CameraMinZoomDistance = 6
			player.CameraMaxZoomDistance = 120
		end
	else
		unbind()
		setFirstPerson(false)
		camera.CameraType = Enum.CameraType.Scriptable
	end
end

return CameraRig
