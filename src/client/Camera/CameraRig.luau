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

local function unbind()
	if bound then
		game:GetService("RunService"):UnbindFromRenderStep(BIND)
		bound = false
	end
	local UIS = game:GetService("UserInputService")
	UIS.MouseBehavior = Enum.MouseBehavior.Default
end

local function bind(fn: (dt: number) -> ())
	unbind()
	game:GetService("RunService"):BindToRenderStep(BIND, Enum.RenderPriority.Camera.Value + 1, fn)
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

function CameraRig.follow(body: Model)
	unbind()
	local camera = workspace.CurrentCamera
	local subject = CameraRig.subjectOf(body)
	if subject == nil then
		return
	end
	camera.CameraType = Enum.CameraType.Custom
	camera.CameraSubject = subject :: any
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
			bind(function()
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
