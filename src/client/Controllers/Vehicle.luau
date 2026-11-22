--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Controllers.Vehicle
-- Controller for every player vehicle (car, cart, bike, pickup, SUV, jet ski; BUILD_PLAN §1.4
-- Controllers/Vehicle, §1.5 Devices, §4.4 #5): Shared/Movement/CarMotor with the kind's
-- Vehicles/VehicleKinds parameters, driven by InputMap through BodyDriver on the vehicle's root
-- (the server hands its network ownership to the driver). Bikes lean into turns. The possessed
-- human stays welded to the DriverSeat by the server; the camera goes first person at EyeSocket.
-- The town's cars this client draws are solid (Render/VehicleView: their RootPart collides with the bodies this client
-- simulates, a driven vehicle among them): the motor stops at their boxes (ClientWorld.cars, Traffic/Solid) as at a wall,
-- so the physics never has to push a driven vehicle back out of one every frame. The test is the vehicle's own turned
-- footprint (its logical box, CarMotor.corners), not a square at its centre, so its nose stops at a car's side; and a
-- move that does not take it deeper into a car it already overlaps is free (Solid.pushes: a town car drawn over it, a
-- car that pulled up against it, never locks it in; review 2026-11-18).
-- A shared vehicle that bumps someone (owner D29: the vehicle's BumpAt, Server/Vehicles/RideBumps) loses some of its speed:
-- the rider feels the bump (afterBump).
-- Interface: start(vehicle, kind, metrics, ctx) -> stop(); ctx = { world, input }; blocked(state, cars, walls) (the motor's
-- wall test); afterBump(speed, seen, stamp) -> (speed, seen)
-- No side effects on require.

local Import = require("../Import")
local CarMotor = Import.shared("Movement/CarMotor") :: typeof(require("../../shared/Movement/CarMotor"))
local VehicleKinds = Import.shared("Vehicles/VehicleKinds") :: typeof(require("../../shared/Vehicles/VehicleKinds"))
local Solid = Import.shared("Traffic/Solid") :: typeof(require("../../shared/Traffic/Solid"))
local SharedRides = Import.shared("Vehicles/SharedRides") :: typeof(require("../../shared/Vehicles/SharedRides"))
local BodyDriver = require("./BodyDriver")

local Vehicle = {}

-- blocked(state, cars, walls) -> CarMotor.World.blocked: the motor's wall test for the vehicle `state` drives (asked
-- with where it would move to, before the move; the state still holds where it is, at the new heading): the town's
-- cars (a Traffic/Solid set) meet its turned footprint, a slab a stud deep at its centre's height (as before), and the
-- world's own walls `walls` (ClientWorld.blockedRadius) the square of half its width. Pure but for `walls`.
function Vehicle.blocked(
	state: { kind: string, x: number, z: number, yaw: number }, -- a CarMotor.State (types do not cross Import)
	cars: any,
	walls: (x: number, z: number, y: number, r: number) -> boolean
): (x: number, z: number, y: number, r: number) -> boolean
	local size = VehicleKinds.kind(state.kind).size
	-- the heading the vehicle had where it stands (the motor turns it before it asks; asked once a step)
	local was = state.yaw
	return function(x: number, z: number, y: number, r: number): boolean
		local yaw = state.yaw
		local stood = was
		was = yaw
		if cars and cars.n > 0 then
			local from = Solid.box(size[1], size[3], 1, state.x, y - 0.5, state.z, stood)
			local to = Solid.box(size[1], size[3], 1, x, y - 0.5, z, yaw)
			if Solid.pushes(cars, from, to) then
				return true
			end
		end
		return walls(x, z, y, r)
	end
end

-- afterBump(speed, seen, stamp) -> (speed, seen): a shared vehicle that bumped someone (Server/Vehicles/RideBumps writes
-- the vehicle's BumpAt, owner D29): on a new stamp the rider keeps SharedRides.C.keep of the speed. Pure
function Vehicle.afterBump(speed: number, seen: any, stamp: any): (number, any)
	if stamp ~= nil and stamp ~= seen then
		return speed * SharedRides.C.keep, stamp
	end
	return speed, seen
end

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
		blocked = Vehicle.blocked(state, world.cars, world.blockedRadius),
		clamp = world.clamp,
	}
	metrics.vehicleKind = kind
	local bumpSeen = vehicle:GetAttribute("BumpAt")
	return BodyDriver.drive(root, function(dt: number)
		local f = input:sample(BodyDriver.cameraYawHtml())
		state.speed, bumpSeen = Vehicle.afterBump(state.speed, bumpSeen, vehicle:GetAttribute("BumpAt"))
		CarMotor.step(state, { throttle = f.fw, steer = f.side, handbrake = f.handbrake }, dt, motorWorld)
		metrics.vehicleSpeed = state.speed
		local vel = Vector3.new(math.sin(state.yaw) * state.speed, state.vy, math.cos(state.yaw) * state.speed)
		local tilt = if state.lean ~= 0 then CFrame.Angles(0, 0, state.lean) else nil
		return Vector3.new(state.x, state.y, state.z), state.yaw, vel, tilt
	end)
end

return Vehicle
