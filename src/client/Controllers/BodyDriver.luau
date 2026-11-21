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
-- The force is sized from the assembly's mass every frame it changes (antiGravity's refresh): the engine reads an
-- ANCHORED assembly's mass as infinite, and a controller started while the server still holds the body anchored (the
-- validator's pin or hold, the sky lift, the telescope) would otherwise carry an infinite force into the moment the
-- body is let go. A step that throws is counted (Controllers/MotorHealth, the owner's F8 panel) and printed at most
-- once every few seconds, never once a frame.
-- Interface: drive(root, step: (dt) -> (pos: Vector3, htmlYaw: number, vel: Vector3, tilt: CFrame?))
--   -> stop(); driveRender(root, step: (dt) -> (cf: CFrame, vel: Vector3)) -> stop();
--   rootYawHtml(root) -> number; cameraYawHtml() -> number
-- No side effects on require.

local Import = require("../Import")
local Units = Import.shared("Config/Units") :: typeof(require("../../shared/Config/Units"))
local MotorHealth = require("./MotorHealth")

local BodyDriver = {}

local renderSeq = 0

-- The mass of the root's parts by their own word (an anchored assembly's AssemblyMass is infinite).
local function partsMass(root: BasePart): number
	local total = 0
	local ok = pcall(function()
		for _, part in root:GetConnectedParts(true) do
			if part == root or not part.Massless then
				total += part:GetMass()
			end
		end
	end)
	return if ok then total else 0
end

-- The local force that cancels gravity on the client-owned assembly; returns its remover and its refresh (called
-- every frame: the force follows the assembly's mass, and is never sized from an anchored assembly's infinite one).
local function antiGravity(root: BasePart): (() -> (), () -> ())
	local attach = Instance.new("Attachment")
	attach.Name = "BodyDriverAttachment"
	attach.Parent = root
	local anti = Instance.new("VectorForce")
	anti.Name = "BodyDriverAntiGravity"
	anti.Attachment0 = attach
	anti.RelativeTo = Enum.ActuatorRelativeTo.World
	anti.ApplyAtCenterOfMass = true
	local seen: number? = nil
	local function refresh()
		local reading = root.AssemblyMass
		if reading == seen then
			return
		end
		seen = reading
		local finite = reading == reading and reading > 0 and reading < math.huge
		local mass = MotorHealth.finiteMass(reading, if finite then reading else partsMass(root))
		anti.Force = Vector3.new(0, mass * workspace.Gravity, 0)
	end
	refresh()
	anti.Parent = root
	return function()
		anti:Destroy()
		attach:Destroy()
	end, refresh
end

-- A controller's step threw: counted for the owner's panel, printed at most once every few seconds.
local function failed(err: any)
	if MotorHealth.fault(err) then
		warn(`BodyDriver: controller step failed: {err}`)
	end
end

function BodyDriver.drive(root: BasePart, step: (dt: number) -> (Vector3, number, Vector3, CFrame?)): () -> ()
	local RunService = game:GetService("RunService")
	local release, refresh = antiGravity(root)
	local conn = RunService.PreSimulation:Connect(function(dt: number)
		refresh()
		local ok, pos, yaw, vel, tilt = pcall(step, dt)
		if not ok then
			failed(pos)
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
	local release, refresh = antiGravity(root)
	renderSeq += 1
	local name = `SpicyBodyDriver{renderSeq}`
	-- before the camera rig (Camera - 1) and the engine camera, so both follow this frame's pose
	RunService:BindToRenderStep(name, Enum.RenderPriority.Camera.Value - 2, function(dt: number)
		refresh()
		local ok, cf, vel = pcall(step, dt)
		if not ok then
			failed(cf)
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
