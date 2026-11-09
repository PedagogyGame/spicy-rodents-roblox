--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Camera.CameraRig
-- W0 (spike S2) subset of the per-mode camera rigs (BUILD_PLAN §1.4 Camera/CameraRig, brief v2
-- §14): the default Roblox follow camera on whatever body the player drives. A Humanoid body uses
-- the Humanoid as subject; a non-Humanoid body (the AnimationController squirrel) uses its `Head`
-- part, else its PrimaryPart; this is set from a LocalScript because the engine only auto-assigns
-- Humanoid subjects. `overview` parks a scriptable camera when the player drives nothing.
-- No side effects on require (services are looked up inside the functions).
-- Interface: follow(body), overview(position, lookAt), subjectOf(body)

local CameraRig = {}

function CameraRig.subjectOf(body: Model): Instance?
	local humanoid = body:FindFirstChildOfClass("Humanoid")
	if humanoid then
		return humanoid
	end
	return body:FindFirstChild("Head") or body.PrimaryPart
end

function CameraRig.follow(body: Model)
	local camera = workspace.CurrentCamera
	local subject = CameraRig.subjectOf(body)
	if subject == nil then
		return
	end
	camera.CameraType = Enum.CameraType.Custom
	camera.CameraSubject = subject :: any
end

function CameraRig.overview(position: Vector3, lookAt: Vector3)
	local camera = workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = CFrame.lookAt(position, lookAt)
end

return CameraRig
