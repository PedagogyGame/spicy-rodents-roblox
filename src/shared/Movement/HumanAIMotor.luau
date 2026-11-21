--!strict
-- ReplicatedStorage.Shared.Movement.HumanAIMotor
-- The kinematic AI motor for anchored bodies (BUILD_PLAN §1.3 server frame step 3, §1.4, §1.5 body
-- modes; folded in from the S5 spike's Server/AI/Kinematics, which now delegates here). Integrates
-- an actor's Intent every frame the way v5.4 steps its humans (humans_actors §5.2 11-14: smoothed
-- speed, step <= speed dt, turn-rate clamp, lane lock damp lambda 8, world clamp, ground snap) and
-- wildlife (heading steering). Rail mode walks a route polyline by arc length (RouteLike points).
-- People move smoothly (owner D27: "waddles, jolts left right ... does not walk or run in a straight smooth line"):
--   * a turn is eased in and out (easeTurn: the yaw rate rises at TURN_ACCEL x the brain's turn rate and falls away
--     in proportion to the angle left), where the v5.4 clamp started and stopped it within one frame;
--   * a step aside on a lane (round a post, back onto the lane's line) is walked as a shallow diagonal (laneSide: no
--     steeper than LANE_SLOPE, eased in and out, the pace along the ground unchanged), where the v5.4 lane lock slid
--     the body sideways at up to 8 x the offset a second while it faced straight on;
--   * the body faces where it is going (the diagonal included), so the torso leads.
--   The path between the points of a walk is unchanged (straight legs: World/WalkWay keeps them off the walls).
--   Wildlife keep the v5.4 steps.
-- Interface: step(actor, dt, ctx), railPose(route, s) -> x, y, z, serialize(actor), deserialize(actor, snap);
--   easeTurn(yaw, rate, desired, cap, dt) -> yaw, rate (pure); laneSide(side, err, pace, dt) -> studs/s (pure);
--   TURN_GAIN, TURN_ACCEL, LANE_GAIN, LANE_SLOPE, LANE_ACCEL
-- Pure; studs; yaw is the HTML yaw (0 faces +Z). No side effects on require.

-- Structural types (the server's Brains/Common.Actor and Ctx satisfy them).
export type Intent = {
	mode: string,
	tx: number,
	tz: number,
	speed: number,
	turnRate: number,
	damp: number,
	laneAxis: string?,
	laneCoord: number?,
	heading: number,
	routeId: number,
	s: number,
	dir: number,
	railEnd: boolean,
}
export type Actor = {
	x: number,
	y: number,
	z: number,
	yaw: number,
	speed: number,
	hip: number,
	moved: number,
	intent: Intent,
	[string]: any,
}
export type Ctx = {
	groundAt: (x: number, z: number) -> number,
	bounds: { minX: number, maxX: number, minZ: number, maxZ: number },
	routes: any?,
	[string]: any,
}

type Route = {
	id: number,
	length: number,
	points: { { number } },
	cum: { number }?, -- cumulative arc length per point (built lazily)
}

local HumanAIMotor = {}

local TAU = math.pi * 2

local function angleDelta(a: number, b: number): number
	return (b - a + math.pi) % TAU - math.pi
end

local function yawOf(dx: number, dz: number): number
	return math.atan2(dx, dz)
end

local function cumulative(route: Route): { number }
	local existing = route.cum
	if existing then
		return existing
	end
	local cum: { number } = { 0 }
	local pts = route.points
	for i = 2, #pts do
		local a, b = pts[i - 1], pts[i]
		local dx, dy, dz = b[1] - a[1], b[2] - a[2], b[3] - a[3]
		cum[i] = cum[i - 1] + math.sqrt(dx * dx + dy * dy + dz * dz)
	end
	route.cum = cum
	return cum
end

-- Position along the polyline at arc length s (clamped). Linear search from the end that is nearer.
function HumanAIMotor.railPose(route: Route, s: number): (number, number, number)
	local pts = route.points
	local cum = cumulative(route)
	local n = #pts
	local total = cum[n]
	if s <= 0 or n == 1 then
		local p = pts[1]
		return p[1], p[2], p[3]
	elseif s >= total then
		local p = pts[n]
		return p[1], p[2], p[3]
	end
	local i = 2
	while cum[i] < s do
		i += 1
	end
	local a, b = pts[i - 1], pts[i]
	local seg = cum[i] - cum[i - 1]
	local t = if seg > 0 then (s - cum[i - 1]) / seg else 0
	return a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t
end

-- Exponential damping factor for lambda over dt.
local function damp(current: number, target: number, lambda: number, dt: number): number
	local k = 1 - math.exp(-lambda * dt)
	return current + (target - current) * k
end

HumanAIMotor.TURN_GAIN = 8 -- 1/s: the last of a turn dies away at this rate (the yaw rate is at most this x the angle left)
HumanAIMotor.TURN_ACCEL = 10 -- 1/s: the yaw rate changes by at most this x the turn rate a second (0.1 s to full rate)
HumanAIMotor.LANE_GAIN = 3 -- 1/s: the last of a step aside dies away at this rate
HumanAIMotor.LANE_SLOPE = 0.4 -- a step aside is walked no steeper than this to the lane (about 22 degrees)
HumanAIMotor.LANE_ACCEL = 2 -- 1/s: the sideways pace changes by at most this x the walking pace a second

-- easeTurn(yaw, rate, desired, cap, dt): one frame of a person's turn toward `desired`, `rate` the yaw rate it has
-- now (rad/s, signed): at most `cap`, never more than TURN_GAIN x the angle left (so it arrives without passing),
-- and changed by at most TURN_ACCEL x cap a second. Returns the yaw and the rate.
function HumanAIMotor.easeTurn(yaw: number, rate: number, desired: number, cap: number, dt: number): (number, number)
	local d = angleDelta(yaw, desired)
	local want = math.clamp(HumanAIMotor.TURN_GAIN * d, -cap, cap)
	local change = HumanAIMotor.TURN_ACCEL * cap * dt
	local w = rate + math.clamp(want - rate, -change, change)
	local step = w * dt
	if d == 0 or step * d < 0 then
		-- (still turning the other way: slowed first, which `change` does; an angle of 0 just holds)
		return yaw + step, w
	elseif math.abs(step) >= math.abs(d) then
		return yaw + d, 0
	end
	return yaw + step, w
end

-- laneSide(side, err, pace, dt): the sideways pace (studs/s, signed) of a person `err` studs off the line they
-- walk along at `pace`, one frame on: toward the line no steeper than LANE_SLOPE, dying away at LANE_GAIN as it
-- arrives, changed by at most LANE_ACCEL x pace a second.
function HumanAIMotor.laneSide(side: number, err: number, pace: number, dt: number): number
	local cap = HumanAIMotor.LANE_SLOPE * pace
	local want = math.clamp(HumanAIMotor.LANE_GAIN * err, -cap, cap)
	local change = HumanAIMotor.LANE_ACCEL * math.max(pace, 1) * dt
	return side + math.clamp(want - side, -change, change)
end

local function person(actor: Actor): boolean
	return actor.species == "human"
end

local function turnToward(yaw: number, desired: number, rate: number, dt: number): number
	local d = angleDelta(yaw, desired)
	local maxStep = rate * dt
	if d > maxStep then
		d = maxStep
	elseif d < -maxStep then
		d = -maxStep
	end
	return yaw + d
end

-- a person's eased turn (the yaw rate kept on the actor); wildlife turn at the plain clamp
local function turnActor(actor: Actor, desired: number, cap: number, dt: number)
	if person(actor) then
		actor.yaw, actor.yawRate = HumanAIMotor.easeTurn(actor.yaw, actor.yawRate or 0, desired, cap, dt)
	else
		actor.yaw = turnToward(actor.yaw, desired, cap, dt)
	end
end

function HumanAIMotor.step(actor: Actor, dt: number, ctx: Ctx)
	local intent = actor.intent
	local mode = intent.mode
	local x0, y0, z0 = actor.x, actor.y, actor.z

	if mode ~= "walk" then
		actor.side = nil -- (a step aside is a walk's)
	end
	if mode == "rail" then
		local routes = ctx.routes
		local route: Route? = if routes then routes.byId(intent.routeId) else nil
		if route then
			if intent.speed > 0 then
				-- the polyline's own length is the effective rail length (a downsampled polyline is
				-- shorter than the curve's arc length; W1's Curve removes the difference)
				local cum = cumulative(route)
				local total = cum[#cum]
				local s = intent.s + intent.dir * intent.speed * dt
				if s < 0 then
					s = 0
					intent.railEnd = true
				elseif s > total then
					s = total
					intent.railEnd = true
				end
				intent.s = s
			end
			local x, y, z = HumanAIMotor.railPose(route, intent.s)
			local dx, dz = x - actor.x, z - actor.z
			if dx * dx + dz * dz > 1e-6 then
				actor.yaw = yawOf(dx, dz)
			end
			actor.x, actor.y, actor.z = x, y, z
			actor.speed = if intent.speed > 0 then intent.speed else 0
		end
	elseif mode == "stand" then
		actor.speed = damp(actor.speed, 0, 10, dt)
		if intent.heading ~= actor.yaw and intent.heading ~= 0 then
			turnActor(actor, intent.heading, 4, dt)
		end
		actor.y = ctx.groundAt(actor.x, actor.z) + actor.hip
	elseif mode == "walk" then
		local dx, dz = intent.tx - actor.x, intent.tz - actor.z
		local axis, coord = intent.laneAxis, intent.laneCoord
		actor.speed = damp(actor.speed, intent.speed, intent.damp, dt)
		if person(actor) and coord and (axis == "x" or axis == "z") then
			-- along a lane: straight along its line, any step aside (round a post, back onto the line) a shallow
			-- diagonal at the same pace over the ground; the body faces where it goes
			local du, err
			if axis == "x" then
				du, err = dx, coord - actor.z
			else
				du, err = dz, coord - actor.x
			end
			local side = HumanAIMotor.laneSide(actor.side or 0, err, actor.speed, dt)
			if math.abs(err) < 1e-3 and math.abs(side) < 1e-3 then
				side = 0
			end
			actor.side = side
			local forward = math.sqrt(math.max(0, actor.speed * actor.speed - side * side))
			local stepU = math.min(math.abs(du), forward * dt) * (if du >= 0 then 1 else -1)
			local stepC = side * dt
			if math.abs(stepC) > math.abs(err) and stepC * err > 0 then
				stepC = err
			end
			local mx, mz
			if axis == "x" then
				mx, mz = stepU, stepC
			else
				mx, mz = stepC, stepU
			end
			if mx * mx + mz * mz > 1e-10 then
				turnActor(actor, yawOf(mx, mz), intent.turnRate, dt)
				actor.x += mx
				actor.z += mz
			end
		else
			actor.side = nil
			local dist = math.sqrt(dx * dx + dz * dz)
			local stepLen = math.min(dist, actor.speed * dt)
			if dist > 1e-4 and stepLen > 0 then
				turnActor(actor, yawOf(dx, dz), intent.turnRate, dt)
				local ux, uz = dx / dist, dz / dist
				actor.x += ux * stepLen
				actor.z += uz * stepLen
			end
			-- lane lock (wildlife and bare actors): damp the cross-axis coordinate back to the lane (lambda 8)
			if axis == "x" and coord then
				actor.z = damp(actor.z, coord, 8, dt)
			elseif axis == "z" and coord then
				actor.x = damp(actor.x, coord, 8, dt)
			end
		end
		actor.y = ctx.groundAt(actor.x, actor.z) + actor.hip
	elseif mode == "heading" then
		actor.yaw = turnToward(actor.yaw, intent.heading, intent.turnRate, dt)
		actor.speed = damp(actor.speed, intent.speed, intent.damp, dt)
		local stepLen = actor.speed * dt
		actor.x += math.sin(actor.yaw) * stepLen
		actor.z += math.cos(actor.yaw) * stepLen
		actor.y = ctx.groundAt(actor.x, actor.z) + actor.hip
	end

	-- world clamp (humans_actors §5.2 11; the rail is trusted)
	if mode ~= "rail" then
		local b = ctx.bounds
		if actor.x < b.minX then
			actor.x = b.minX
		elseif actor.x > b.maxX then
			actor.x = b.maxX
		end
		if actor.z < b.minZ then
			actor.z = b.minZ
		elseif actor.z > b.maxZ then
			actor.z = b.maxZ
		end
	end
	local mx, my, mz = actor.x - x0, actor.y - y0, actor.z - z0
	actor.moved += math.sqrt(mx * mx + my * my + mz * mz)
end

-- Flat snapshot for possession (BUILD_PLAN §1.5 step 2): position, yaw, velocity, intent rail state.
function HumanAIMotor.serialize(actor: Actor): { [string]: any }
	local i = actor.intent
	return {
		x = actor.x,
		y = actor.y,
		z = actor.z,
		yaw = actor.yaw,
		vx = math.sin(actor.yaw) * actor.speed,
		vy = 0,
		vz = math.cos(actor.yaw) * actor.speed,
		speed = actor.speed,
		mode = i.mode,
		routeId = i.routeId,
		s = i.s,
		dir = i.dir,
	}
end

-- Re-seats an actor from a snapshot (release: the body's last validated pose).
function HumanAIMotor.deserialize(actor: Actor, snap: { [string]: any })
	actor.x = snap.x or actor.x
	actor.y = snap.y or actor.y
	actor.z = snap.z or actor.z
	actor.yaw = snap.yaw or actor.yaw
	actor.speed = 0
end

return HumanAIMotor
