--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Controllers.BodyDriver
-- The shared engine half of every motor-driven controller (squirrel, quadruped, vehicle, drone;
-- BUILD_PLAN §1.4 Controllers): the client owns the unanchored assembly, a local VectorForce cancels
-- gravity (it exists only where the assembly simulates, on this client), and every PreSimulation the
-- controller's step function returns the pose the pure motor computed; the root's CFrame and
-- velocities are written from it. The S2 squirrel controller's proven pattern, factored out.
-- Interface: drive(root, step: (dt) -> (pos: Vector3, htmlYaw: number, vel: Vector3, tilt: CFrame?))
--   -> stop(); rootYawHtml(root) -> number; cameraYawHtml() -> number
-- No side effects on require.

local Import = require("../Import")
local Units = Import.shared("Config/Units") :: typeof(require("../../shared/Config/Units"))

local BodyDriver = {}

function BodyDriver.drive(root: BasePart, step: (dt: number) -> (Vector3, number, Vector3, CFrame?)): () -> ()
	local RunService = game:GetService("RunService")
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
		anti:Destroy()
		attach:Destroy()
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
