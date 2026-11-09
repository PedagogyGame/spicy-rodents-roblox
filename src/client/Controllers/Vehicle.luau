--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Controllers.Vehicle
-- Controller for every player vehicle (car, cart, bike, pickup, SUV, jet ski; BUILD_PLAN §1.4
-- Controllers/Vehicle, §1.5 Devices, §4.4 #5): Shared/Movement/CarMotor with the kind's
-- Vehicles/VehicleKinds parameters, driven by InputMap through BodyDriver on the vehicle's root
-- (the server hands its network ownership to the driver). Bikes lean into turns. The possessed
-- human stays welded to the DriverSeat by the server; the camera goes first person at EyeSocket.
-- Interface: start(vehicle, kind, metrics, ctx) -> stop(); ctx = { world, input }
-- No side effects on require.

local Import = require("../Import")
local CarMotor = Import.shared("Movement/CarMotor") :: typeof(require("../../shared/Movement/CarMotor"))
local BodyDriver = require("./BodyDriver")

local Vehicle = {}

function Vehicle.start(vehicle: Model, kind: string, metrics: { [string]: any }, ctx: { [string]: any }): () -> ()
	local root = vehicle.PrimaryPart
	if root == nil then
		return function() end
	end
	local world = ctx.world
	local input = ctx.input
	local p = root.Position
	local state = CarMotor.new(kind, p.X, p.Y, p.Z, BodyDriver.rootYawHtml(root))
	local motorWorld = {
		groundAt = world.groundAt,
		waterAt = world.waterAt,
		blocked = function(x: number, z: number, y: number, r: number): boolean
			return world.blockedRadius(x, z, y, r)
		end,
		clamp = world.clamp,
	}
	metrics.vehicleKind = kind
	return BodyDriver.drive(root, function(dt: number)
		local f = input:sample(BodyDriver.cameraYawHtml())
		CarMotor.step(state, { throttle = f.fw, steer = f.side, handbrake = f.handbrake }, dt, motorWorld)
		metrics.vehicleSpeed = state.speed
		local vel = Vector3.new(math.sin(state.yaw) * state.speed, state.vy, math.cos(state.yaw) * state.speed)
		local tilt = if state.lean ~= 0 then CFrame.Angles(0, 0, state.lean) else nil
		return Vector3.new(state.x, state.y, state.z), state.yaw, vel, tilt
	end)
end

return Vehicle
