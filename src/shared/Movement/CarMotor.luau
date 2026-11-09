--!strict
-- ReplicatedStorage.Shared.Movement.CarMotor
-- Kinematic arcade motor for every player-driven vehicle (BUILD_PLAN §1.4, D10, §4.4 #5): car,
-- cart, pickup and SUV (motor "car"), bike (motor "bike": balance-free, leans into turns) and the
-- jet ski (motor "jetski": rides the water surface, stops at the shore). Parameter sets come from
-- Vehicles/VehicleKinds. Bicycle model: yaw rate = speed * tan(steer) / wheelbase; the steering
-- angle eases toward the input and narrows with speed; throttle accelerates, the opposite pedal
-- brakes then reverses, Space is the handbrake; coasting drag. Ground and roof via
-- world.groundAt(x, z, refY); walls via world.blocked (the car stops and rebounds slightly).
-- AI traffic keeps Traffic/LaneMath (Track B); this motor is for player vehicles.
-- Interface: new(kind, x, y, z, yaw?), idleInput(), step(state, input, dt, world) -> state, events,
--            serialize, deserialize, envelope(prev, next, dt), corners(state) (logical box, studs)
-- Pure; studs; yaw is the HTML yaw (0 faces +Z). No side effects on require.

local VehicleKinds = require("../Vehicles/VehicleKinds")

export type State = {
	kind: string,
	x: number,
	y: number,
	z: number,
	yaw: number,
	speed: number, -- signed, along the heading (studs/s)
	steer: number, -- current wheel angle (rad)
	vy: number,
	lean: number, -- bikes: visual lean (rad)
	grounded: boolean,
	clock: number,
}

export type Input = {
	throttle: number, -- W/S: +1 forward, -1 back
	steer: number, -- D/A: +1 right, -1 left
	handbrake: boolean,
}

export type World = {
	groundAt: (x: number, z: number, refY: number) -> number,
	waterAt: ((x: number, z: number) -> number?)?, -- water surface height, nil on land
	blocked: ((x: number, z: number, y: number, radius: number) -> boolean)?,
	clamp: { minX: number, maxX: number, minZ: number, maxZ: number }?,
}

export type Event = { kind: string }

local CarMotor = {}

local GRAVITY = 75

function CarMotor.new(kindId: string, x: number, y: number, z: number, yaw: number?): State
	VehicleKinds.kind(kindId)
	return {
		kind = kindId,
		x = x,
		y = y,
		z = z,
		yaw = yaw or 0,
		speed = 0,
		steer = 0,
		vy = 0,
		lean = 0,
		grounded = true,
		clock = 0,
	}
end

function CarMotor.idleInput(): Input
	return { throttle = 0, steer = 0, handbrake = false }
end

local function approach(v: number, target: number, rate: number): number
	if v < target then
		return math.min(target, v + rate)
	end
	return math.max(target, v - rate)
end

local function substep(s: State, input: Input, h: number, world: World, k: VehicleKinds.Kind, events: { Event })
	-- longitudinal
	local t = math.clamp(input.throttle, -1, 1)
	if input.handbrake then
		s.speed = approach(s.speed, 0, k.brake * 1.2 * h)
	elseif t > 0 then
		if s.speed < 0 then
			s.speed = approach(s.speed, 0, k.brake * h)
		else
			s.speed = math.min(k.maxSpeed, s.speed + k.accel * t * h)
		end
	elseif t < 0 then
		if s.speed > 0 then
			s.speed = approach(s.speed, 0, k.brake * h)
		else
			s.speed = math.max(-k.reverseSpeed, s.speed + k.accel * 0.6 * t * h)
		end
	else
		s.speed = approach(s.speed, 0, k.drag * h)
	end
	-- steering narrows with speed (full lock below 25 % of top speed, 40 % of it at top speed)
	local frac = math.clamp(math.abs(s.speed) / k.maxSpeed, 0, 1)
	local lock = k.maxSteer * (1 - 0.6 * math.max(0, frac - 0.25) / 0.75)
	-- HTML yaw grows to the left (+X is yaw pi/2), so steering right (+1) lowers the yaw
	s.steer = approach(s.steer, -math.clamp(input.steer, -1, 1) * lock, k.steerRate * h)
	local yawRate = s.speed * math.tan(s.steer) / k.wheelbase
	s.yaw += yawRate * h
	if k.motor == "bike" then
		s.lean = approach(s.lean, math.clamp(-yawRate * math.abs(s.speed) * 0.02, -0.5, 0.5), 2 * h)
	end
	-- planar move with wall stop
	local ox, oz = s.x, s.z
	local nx = s.x + math.sin(s.yaw) * s.speed * h
	local nz = s.z + math.cos(s.yaw) * s.speed * h
	local radius = k.size[1] * 0.5
	local blocked = world.blocked
	if blocked and blocked(nx, nz, s.y, radius) then
		if math.abs(s.speed) > 8 then
			table.insert(events, { kind = "bump" })
		end
		s.speed = -s.speed * 0.2
		nx, nz = ox, oz
	end
	-- surface: water for the jet ski, ground for the rest
	local half = k.size[2] * 0.5
	if k.motor == "jetski" then
		local waterAt = world.waterAt
		local w = if waterAt then waterAt(nx, nz) else nil
		if w == nil then
			-- shore: the jet ski stays on the water
			if math.abs(s.speed) > 2 then
				table.insert(events, { kind = "shore" })
			end
			s.speed = 0
			nx, nz = ox, oz
			w = if waterAt then waterAt(ox, oz) else nil
		end
		s.x, s.z = nx, nz
		s.y = (w or s.y - half) + half * 0.6
		s.vy, s.grounded = 0, true
	else
		s.x, s.z = nx, nz
		local ground = world.groundAt(s.x, s.z, s.y - half) + half
		s.vy -= GRAVITY * h
		s.y += s.vy * h
		if s.y <= ground then
			if not s.grounded and s.vy < -20 then
				table.insert(events, { kind = "land" })
			end
			s.y, s.vy, s.grounded = ground, 0, true
		elseif s.grounded and s.y - ground < 1.2 then
			s.y, s.vy = ground, 0 -- follow the road down a slope
		else
			s.grounded = false
		end
	end
	local cl = world.clamp
	if cl then
		s.x = math.clamp(s.x, cl.minX, cl.maxX)
		s.z = math.clamp(s.z, cl.minZ, cl.maxZ)
	end
	s.clock += h
end

function CarMotor.step(s: State, input: Input, dt: number, world: World): (State, { Event })
	local events: { Event } = {}
	local k = VehicleKinds.kind(s.kind)
	local frameDt = math.min(dt, 0.1)
	local steps = math.clamp(math.ceil(frameDt * 60 - 1e-9), 1, 6)
	for _ = 1, steps do
		substep(s, input, frameDt / steps, world, k, events)
	end
	return s, events
end

function CarMotor.serialize(s: State): { [string]: any }
	return table.clone(s) :: any
end

function CarMotor.deserialize(t: { [string]: any }): State
	local s = CarMotor.new(t.kind or "car", t.x or 0, t.y or 0, t.z or 0, t.yaw)
	s.speed = t.speed or 0
	s.steer = t.steer or 0
	s.vy = t.vy or 0
	s.lean = t.lean or 0
	s.grounded = if t.grounded == nil then true else t.grounded
	s.clock = t.clock or 0
	return s
end

-- envelope(prev, next, dt): the validator's check: speed within the kind's top speed (+10 %) and
-- the planar step within that speed * dt (+0.5 st).
function CarMotor.envelope(prev: State, nxt: State, dt: number): (boolean, string?)
	local k = VehicleKinds.kind(prev.kind)
	local cap = k.maxSpeed * 1.1
	if math.abs(nxt.speed) > cap + 1e-6 then
		return false, "speed"
	end
	local dx, dz = nxt.x - prev.x, nxt.z - prev.z
	if math.sqrt(dx * dx + dz * dz) > cap * dt + 0.5 then
		return false, "step"
	end
	return true, nil
end

-- corners(state): the logical box's four ground corners (studs), front-left first, clockwise.
function CarMotor.corners(s: State): { { number } }
	local k = VehicleKinds.kind(s.kind)
	local hw, hl = k.size[1] * 0.5, k.size[3] * 0.5
	local fx, fz = math.sin(s.yaw), math.cos(s.yaw)
	local rx, rz = -fz, fx -- right of the heading in the HTML convention
	local out = {}
	for _, c in { { -1, 1 }, { 1, 1 }, { 1, -1 }, { -1, -1 } } do
		table.insert(out, { s.x + rx * hw * c[1] + fx * hl * c[2], s.z + rz * hw * c[1] + fz * hl * c[2] })
	end
	return out
end

return CarMotor
