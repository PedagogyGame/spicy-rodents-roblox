--!strict
-- ReplicatedStorage.Shared.Movement.QuadrupedMotor
-- Ground motor for the four-legged bodies a player can hold (fox, deer; BUILD_PLAN §1.4, §4.4 #5),
-- used by the client controller and, for validation, by the server. Same conventions as
-- SquirrelMotor's ground mode (routes_movement §8.1): camera-relative input (HTML convention,
-- forward = (-sin camYaw, -cos camYaw)), exponential accel/drag, turn-rate clamp, gravity, ground
-- snap through world.groundAt(x, z, refY), per-axis wall sliding through world.blocked, world clamp.
-- Speeds come from Actors/Species (fox 2.0 / 8.8 u/s, deer 1.25 / 11.8 u/s [wildlife_foraging
-- §11.8, §11.9]); a held body walks at max(def walk, 45 % of sprint) so the deer's 1.25 u/s graze is
-- not the player's walk (interpretation, recorded in docs/waves/W1.md).
-- Interface: paramsFor(species), new(x, y, z, yaw?), idleInput(camYaw?), step(state, input, dt, world)
--            -> state, events; serialize(state), deserialize(snap), envelope(prev, next, dt, params)
-- Pure; studs; yaw is the HTML yaw (0 faces +Z). No side effects on require.

local Species = require("../Actors/Species")

export type Params = {
	walk: number,
	sprint: number,
	accel: number, -- per second (exponential approach), grounded
	airAccel: number,
	drag: number, -- per second, grounded with no input
	turnRate: number, -- rad/s
	jumpV: number, -- studs/s
	gravity: number, -- studs/s^2
	hip: number, -- root height above ground
	radius: number,
}

export type State = {
	x: number,
	y: number,
	z: number,
	vx: number,
	vy: number,
	vz: number,
	yaw: number,
	grounded: boolean,
	clock: number,
}

export type Input = {
	fw: number,
	side: number,
	cameraYaw: number,
	sprint: boolean,
	jump: boolean,
}

export type World = {
	groundAt: (x: number, z: number, refY: number) -> number,
	blocked: ((x: number, z: number, y: number) -> boolean)?,
	clamp: { minX: number, maxX: number, minZ: number, maxZ: number }?,
}

export type Event = { kind: string }

local QuadrupedMotor = {}

local GRAVITY = 30 * 2.5 -- v5.4 squirrel gravity 30 u/s^2 in studs (routes_movement §8.1)

function QuadrupedMotor.paramsFor(species: string): Params
	local def = Species.def(species)
	local sprint = def.speeds.sprint
	return {
		walk = math.max(def.speeds.walk, sprint * 0.45),
		sprint = sprint,
		accel = 9,
		airAccel = 2,
		drag = 10,
		turnRate = if species == "deer" then 7 else 10,
		jumpV = if species == "deer" then 30 else 22,
		gravity = GRAVITY,
		hip = def.hipHeight,
		radius = def.hitbox.radius,
	}
end

function QuadrupedMotor.new(x: number, y: number, z: number, yaw: number?): State
	return { x = x, y = y, z = z, vx = 0, vy = 0, vz = 0, yaw = yaw or 0, grounded = true, clock = 0 }
end

function QuadrupedMotor.idleInput(cameraYaw: number?): Input
	return { fw = 0, side = 0, cameraYaw = cameraYaw or 0, sprint = false, jump = false }
end

local function turnToward(yaw: number, desired: number, rate: number, dt: number): number
	local d = (desired - yaw + math.pi) % (2 * math.pi) - math.pi
	local m = rate * dt
	return yaw + math.clamp(d, -m, m)
end

-- step(state, input, dt, world): substeps of <= 1/60 s (dt capped at 0.1 s). Root y = ground + hip.
function QuadrupedMotor.step(state: State, input: Input, dt: number, world: World, params: Params): (State, { Event })
	local events: { Event } = {}
	local frameDt = math.min(dt, 0.1)
	local steps = math.clamp(math.ceil(frameDt * 60 - 1e-9), 1, 6)
	local h = frameDt / steps
	if input.jump and state.grounded then
		state.vy = params.jumpV
		state.grounded = false
		table.insert(events, { kind = "jump" })
	end
	for _ = 1, steps do
		local fw, side = input.fw, input.side
		local moving = fw ~= 0 or side ~= 0
		if moving then
			local c = input.cameraYaw
			local dx = -math.sin(c) * fw + math.cos(c) * side
			local dz = -math.cos(c) * fw - math.sin(c) * side
			local l = math.sqrt(dx * dx + dz * dz)
			dx, dz = dx / l, dz / l
			local speed = if input.sprint then params.sprint else params.walk
			local a = 1 - math.exp(-h * (if state.grounded then params.accel else params.airAccel))
			state.vx += (dx * speed - state.vx) * a
			state.vz += (dz * speed - state.vz) * a
			state.yaw = turnToward(state.yaw, math.atan2(dx, dz), params.turnRate, h)
		elseif state.grounded then
			local f = math.exp(-h * params.drag)
			state.vx *= f
			state.vz *= f
		end
		local ox, oz = state.x, state.z
		state.vy -= params.gravity * h
		state.x += state.vx * h
		state.y += state.vy * h
		state.z += state.vz * h
		local blocked = world.blocked
		if blocked and blocked(state.x, state.z, state.y) then
			-- per-axis slide: keep the axis that is free
			if not blocked(state.x, oz, state.y) then
				state.z, state.vz = oz, 0
			elseif not blocked(ox, state.z, state.y) then
				state.x, state.vx = ox, 0
			else
				state.x, state.z, state.vx, state.vz = ox, oz, 0, 0
			end
		end
		local ground = world.groundAt(state.x, state.z, state.y - params.hip) + params.hip
		if state.y <= ground then
			if not state.grounded then
				table.insert(events, { kind = "land" })
			end
			state.y, state.vy, state.grounded = ground, 0, true
		elseif state.grounded and state.y - ground < 0.6 and state.vy <= 0 then
			state.y, state.vy = ground, 0 -- stick to slopes going down
		else
			state.grounded = false
		end
		local cl = world.clamp
		if cl then
			state.x = math.clamp(state.x, cl.minX, cl.maxX)
			state.z = math.clamp(state.z, cl.minZ, cl.maxZ)
		end
		state.clock += h
	end
	return state, events
end

function QuadrupedMotor.serialize(state: State): { [string]: any }
	return table.clone(state) :: any
end

function QuadrupedMotor.deserialize(s: { [string]: any }): State
	return {
		x = s.x or 0,
		y = s.y or 0,
		z = s.z or 0,
		vx = s.vx or 0,
		vy = s.vy or 0,
		vz = s.vz or 0,
		yaw = s.yaw or 0,
		grounded = if s.grounded == nil then true else s.grounded,
		clock = s.clock or 0,
	}
end

-- envelope(prev, next, dt, params): validator check. Horizontal speed within sprint (+10 %) and the
-- horizontal step within sprint * dt (+0.5 st slack); returns ok and a reason.
function QuadrupedMotor.envelope(prev: State, nxt: State, dt: number, params: Params): (boolean, string?)
	local cap = params.sprint * 1.1
	if math.sqrt(nxt.vx * nxt.vx + nxt.vz * nxt.vz) > cap + 1e-6 then
		return false, "speed"
	end
	local dx, dz = nxt.x - prev.x, nxt.z - prev.z
	if math.sqrt(dx * dx + dz * dz) > cap * dt + 0.5 then
		return false, "step"
	end
	return true, nil
end

return QuadrupedMotor
