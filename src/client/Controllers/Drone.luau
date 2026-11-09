--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Controllers.Drone
-- The police drone's device controller (BUILD_PLAN §1.5 Devices, §4.4 #5; the S11 test drone
-- folded into Shared/Movement/DroneMotor): WASD fly camera-relative on the level, Space/E up,
-- Ctrl/Q down, Shift boost; the client owns the drone root through BodyDriver. Streaming follows
-- Player.ReplicationFocus, which the server points at this root while flying (F-13).
-- Interface: start(drone, metrics, ctx) -> stop(); ctx = { world, input, params? }
-- No side effects on require.

local Import = require("../Import")
local DroneMotor = Import.shared("Movement/DroneMotor") :: typeof(require("../../shared/Movement/DroneMotor"))
local BodyDriver = require("./BodyDriver")

local Drone = {}

function Drone.start(drone: Model, metrics: { [string]: any }, ctx: { [string]: any }): () -> ()
	local root = drone.PrimaryPart
	if root == nil then
		return function() end
	end
	local p = root.Position
	local state = DroneMotor.new(p.X, p.Y, p.Z, BodyDriver.rootYawHtml(root))
	local world = { groundAt = ctx.world.groundAt, clamp = ctx.world.clamp }
	local input = ctx.input
	return BodyDriver.drive(root, function(dt: number)
		local f = input:sample(BodyDriver.cameraYawHtml())
		DroneMotor.step(
			state,
			{ fw = f.fw, side = f.side, up = f.up, boost = f.sprint, cameraYaw = f.cameraYaw },
			dt,
			world,
			ctx.params
		)
		metrics.droneAltitude = state.y
		return Vector3.new(state.x, state.y, state.z), state.yaw, Vector3.new(state.vx, state.vy, state.vz), nil
	end)
end

return Drone
