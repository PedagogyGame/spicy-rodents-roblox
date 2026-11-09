--!strict
-- ReplicatedStorage.Shared.Movement.DroneMotor
-- The police drone's flight motor (BUILD_PLAN §1.4, §1.5 Devices, §4.4 #5; spike S11's test drone
-- folded in): camera-relative WASD on the level, up/down, boost so the far view covers 2 km in
-- seconds; smoothed velocity, a minimum clearance over ground and roofs, a ceiling, yaw follows the
-- camera. The client drives it; the server validates with envelope.
-- Interface: params(), new(x, y, z, yaw?), idleInput(camYaw?), step(state, input, dt, world, p?)
--            -> state, events; serialize, deserialize, envelope(prev, next, dt, p?)
-- Pure; studs; HTML yaw. No side effects on require.

export type Params = {
	speed: number, -- studs/s cruise
	boost: number, -- multiplier with Shift
	vertical: number, -- studs/s up/down
	accel: number, -- per second (exponential approach)
	ceiling: number, -- absolute studs
	clearance: number, -- minimum height over the ground below
}

export type State = {
	x: number,
	y: number,
	z: number,
	vx: number,
	vy: number,
	vz: number,
	yaw: number,
	clock: number,
}

export type Input = {
	fw: number,
	side: number,
	up: number, -- +1 Space/E, -1 Ctrl/Q
	boost: boolean,
	cameraYaw: number,
}

export type World = {
	groundAt: (x: number, z: number, refY: number) -> number,
	clamp: { minX: number, maxX: number, minZ: number, maxZ: number }?,
}

local DroneMotor = {}

local DEFAULT: Params = table.freeze({
	speed = 60,
	boost = 4,
	vertical = 40,
	accel = 4,
	ceiling = 900,
	clearance = 4,
})

function DroneMotor.params(): Params
	return DEFAULT
end

function DroneMotor.new(x: number, y: number, z: number, yaw: number?): State
	return { x = x, y = y, z = z, vx = 0, vy = 0, vz = 0, yaw = yaw or 0, clock = 0 }
end

function DroneMotor.idleInput(cameraYaw: number?): Input
	return { fw = 0, side = 0, up = 0, boost = false, cameraYaw = cameraYaw or 0 }
end

function DroneMotor.step(s: State, input: Input, dt: number, world: World, p: Params?): (State, { { kind: string } })
	local P = p or DEFAULT
	local h = math.min(dt, 0.1)
	local c = input.cameraYaw
	local dx = -math.sin(c) * input.fw + math.cos(c) * input.side
	local dz = -math.cos(c) * input.fw - math.sin(c) * input.side
	local l = math.sqrt(dx * dx + dz * dz)
	if l > 1 then
		dx, dz = dx / l, dz / l
	end
	local mult = if input.boost then P.boost else 1
	local a = 1 - math.exp(-P.accel * h)
	s.vx += (dx * P.speed * mult - s.vx) * a
	s.vz += (dz * P.speed * mult - s.vz) * a
	s.vy += (math.clamp(input.up, -1, 1) * P.vertical * mult - s.vy) * a
	s.x += s.vx * h
	s.y += s.vy * h
	s.z += s.vz * h
	local events = {}
	local floor = world.groundAt(s.x, s.z, s.y) + P.clearance
	if s.y < floor then
		s.y = floor
		s.vy = math.max(0, s.vy)
	elseif s.y > P.ceiling then
		s.y = P.ceiling
		s.vy = math.min(0, s.vy)
		table.insert(events, { kind = "ceiling" })
	end
	local cl = world.clamp
	if cl then
		s.x = math.clamp(s.x, cl.minX, cl.maxX)
		s.z = math.clamp(s.z, cl.minZ, cl.maxZ)
	end
	-- the drone's nose follows the camera (yaw of the camera's forward)
	s.yaw = math.atan2(-math.sin(c), -math.cos(c))
	s.clock += h
	return s, events
end

function DroneMotor.serialize(s: State): { [string]: any }
	return table.clone(s) :: any
end

function DroneMotor.deserialize(t: { [string]: any }): State
	local s = DroneMotor.new(t.x or 0, t.y or 0, t.z or 0, t.yaw)
	s.vx, s.vy, s.vz, s.clock = t.vx or 0, t.vy or 0, t.vz or 0, t.clock or 0
	return s
end

function DroneMotor.envelope(prev: State, nxt: State, dt: number, p: Params?): (boolean, string?)
	local P = p or DEFAULT
	local cap = P.speed * P.boost * 1.1
	local dx, dy, dz = nxt.x - prev.x, nxt.y - prev.y, nxt.z - prev.z
	if math.sqrt(dx * dx + dz * dz) > cap * dt + 0.5 then
		return false, "step"
	end
	if math.abs(dy) > P.vertical * P.boost * 1.1 * dt + 0.5 then
		return false, "climb"
	end
	if nxt.y > P.ceiling + 1e-6 then
		return false, "ceiling"
	end
	return true, nil
end

return DroneMotor
