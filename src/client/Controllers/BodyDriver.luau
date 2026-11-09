--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Controllers.BodyDriver
-- The shared engine half of every motor-driven controller (squirrel, quadruped, vehicle, drone;
-- BUILD_PLAN §1.4 Controllers): the client owns the unanchored assembly, a local VectorForce cancels
-- gravity (it exists only where the assembly simulates, on this client), and every PreSimulation the
-- controller's step function returns the pose the pure motor computed; the root's CFrame and
-- velocities are written from it. The S2 squirrel controller's proven pattern, factored out.
-- driveRender is the kinematic variant (squirrel, owner rule 2026-11-09 "a kinematic body glued to the
-- ground and to rails"): the step runs in the render step, just before the camera, and the CFrame it
-- returns is the one that frame draws. A pose written in PreSimulation is drawn one physics step later
-- (pose + velocity x dt), which is what made a running squirrel hop at every change of slope; here physics
-- only carries the body between frames (for the server's and other clients' copies) and never decides
-- what is seen.
-- Interface: drive(root, step: (dt) -> (pos: Vector3, htmlYaw: number, vel: Vector3, tilt: CFrame?))
--   -> stop(); driveRender(root, step: (dt) -> (cf: CFrame, vel: Vector3)) -> stop();
--   rootYawHtml(root) -> number; cameraYawHtml() -> number
-- No side effects on require.

local Import = require("../Import")
local Units = Import.shared("Config/Units") :: typeof(require("../../shared/Config/Units"))

local BodyDriver = {}

local renderSeq = 0

-- The local force that cancels gravity on the client-owned assembly; returns its remover.
local function antiGravity(root: BasePart): () -> ()
	local attach = Instance.new("Attachment")
	attach.Name = "BodyDriverAttachment"
	attach.Parent = root
	local anti = Instance.new("VectorForce")
	anti.Name = "BodyDriverAntiGravity"
	anti.Attachment0 = attach
	anti.RelativeTo = Enum.ActuatorRelativeTo.World
	anti.ApplyAtCenterOfMass = true
	anti.Force = Vector3.new(0, root.AssemblyMass * workspace.Gravity, 0)
	anti.Parent = root
	return function()
		anti:Destroy()
		attach:Destroy()
	end
end

function BodyDriver.drive(root: BasePart, step: (dt: number) -> (Vector3, number, Vector3, CFrame?)): () -> ()
	local RunService = game:GetService("RunService")
	local release = antiGravity(root)
	local conn = RunService.PreSimulation:Connect(function(dt: number)
		local ok, pos, yaw, vel, tilt = pcall(step, dt)
		if not ok then
			warn(`BodyDriver: controller step failed: {pos}`)
			return
		end
		local cf = Units.yawCFrame(yaw, pos)
		if tilt then
			cf *= tilt
		end
		root.CFrame = cf
		root.AssemblyLinearVelocity = vel
		root.AssemblyAngularVelocity = Vector3.zero
	end)
	return function()
		conn:Disconnect()
		release()
	end
end

function BodyDriver.driveRender(root: BasePart, step: (dt: number) -> (CFrame, Vector3)): () -> ()
	local RunService = game:GetService("RunService")
	local release = antiGravity(root)
	renderSeq += 1
	local name = `SpicyBodyDriver{renderSeq}`
	-- before the camera rig (Camera - 1) and the engine camera, so both follow this frame's pose
	RunService:BindToRenderStep(name, Enum.RenderPriority.Camera.Value - 2, function(dt: number)
		local ok, cf, vel = pcall(step, dt)
		if not ok then
			warn(`BodyDriver: controller step failed: {cf}`)
			return
		end
		root.CFrame = cf
		root.AssemblyLinearVelocity = vel
		root.AssemblyAngularVelocity = Vector3.zero
	end)
	return function()
		RunService:UnbindFromRenderStep(name)
		release()
	end
end

-- The root's facing as an HTML yaw (forward = (sin h, cos h)).
function BodyDriver.rootYawHtml(root: BasePart): number
	local lv = root.CFrame.LookVector
	return math.atan2(lv.X, lv.Z)
end

-- The camera's orbit yaw in SquirrelMotor's convention (forward = (-sin c, -cos c)).
function BodyDriver.cameraYawHtml(): number
	local lv = workspace.CurrentCamera.CFrame.LookVector
	return math.atan2(-lv.X, -lv.Z)
end

return BodyDriver
