--!strict
-- ServerScriptService.Server.Actors.Brains.Common
-- Shared contract for the minimal W0 brains: the Actor state they read, the Intent they write and
-- the per-tick Ctx the scheduler hands them (BUILD_PLAN §1.4 Brains/*, §1.5 Actor; spike S5).
-- Interface: types Actor, Intent, Ctx (with the optional `emit` event sink and the town's `way` and `clear`),
--   Brain, Snapshot, Leg; newIntent(), newActor(), halt(actor), newLeg(), toward(leg, actor, ctx, tx, tz) (the
--   point to walk to now on the way to a spot, never through a wall), forget(leg), steer helpers.
-- Pure. Positions are studs, yaw is the HTML yaw (0 faces +Z; Config/Units adds the +pi at the
-- CFrame boundary, D21). Brains never allocate per tick: they write into actor.intent in place.

export type Intent = {
	mode: "stand" | "walk" | "heading" | "rail",
	tx: number, -- walk target (studs)
	tz: number,
	speed: number, -- desired studs/s
	turnRate: number, -- rad/s clamp on yaw changes
	damp: number, -- speed smoothing lambda (per second)
	laneAxis: string?, -- "x" | "z": lane lock axis (pedestrians); nil = none
	laneCoord: number?, -- fixed cross-axis coordinate for the lane lock
	heading: number, -- heading mode: desired yaw
	routeId: number, -- rail mode
	s: number, -- arc length along the route (studs)
	dir: number, -- +1 / -1 along the route
	railEnd: boolean, -- set by the motor when s hits an end; cleared by the brain
}

export type Actor = {
	id: number,
	species: string,
	variant: string,
	post: string?,
	brainKind: string,
	x: number,
	y: number,
	z: number,
	yaw: number,
	speed: number, -- current smoothed scalar speed (studs/s)
	hip: number, -- hip height above ground (studs)
	intent: Intent,
	tier: string,
	alert: number, -- humans: seconds of alert left
	moved: number, -- distance moved so far (liveness check)
	rig: any?, -- engine body handle (Puppets)
	infected: boolean?, -- carries the infection (Infection/InfectionService; squirrels: the "one of those" tell)
	lift: number?, -- studs added to the drawn body's height (a hidden patient is sunk out of sight)
	task: string?, -- what a member of staff is doing at a work stop (Brains/Staff; the body's Task attribute)
	job: string?, -- a named employee's job (Shared/Attractions/AlleyStaff: "shoe_clerk", "mechanic", ...)
	ride: number?, -- a street rider's slot (Shared/Vehicles/RidePuppet.rider: 1 the mime, 2-6 the kids, 7-8 the scooters)
}

export type Grid = {
	query: (self: Grid, x: number, z: number, r: number, out: { number }) -> number,
}

export type Ctx = {
	now: number,
	rng: () -> number, -- uniform [0, 1)
	groundAt: (x: number, z: number) -> number,
	threats: Grid, -- squirrel-species actors by id
	actorsById: { [number]: Actor },
	bounds: { minX: number, maxX: number, minZ: number, maxZ: number },
	routes: any?, -- SpikeRoutes-like: byId(id) -> { length, points, links, kind }
	queryBuffer: { number }, -- shared scratch list for grid queries
	-- optional event sink: a brain reports something the services care about ("spotted": a person
	-- just saw a squirrel and started to run). AI/TownAI collects them (drainEvents).
	emit: ((kind: string, actor: Actor, other: Actor?) -> ())?,
	-- the town's way on foot (World/WalkWay, AI/TownAI): the points after the start, the goal last, or nil when
	-- there is no way that does not go through a wall; clear: a straight walk passes nothing. Without them (a
	-- test's bare world) every walk is straight.
	way: ((x0: number, z0: number, x1: number, z1: number) -> { { number } }?)?,
	clear: ((x0: number, z0: number, x1: number, z1: number) -> boolean)?,
}

-- A walk to a spot that may be round a corner (Common.toward keeps it): the spot, the way there, the point on it
-- being walked to, and when a spot with no way may be asked for again.
export type Leg = {
	tx: number,
	tz: number,
	points: { { number } }?,
	at: number,
	retry: number,
	sx: number, -- where the body stood when the way was found (the first leg starts there)
	sz: number,
	misses: number, -- ways asked for in a row that were none (each wait before asking again is twice as long)
}

export type Snapshot = { [string]: any }

export type Brain = {
	kind: string,
	think: (self: Brain, dt: number, ctx: Ctx) -> (),
	suspend: (self: Brain) -> Snapshot,
	resume: (self: Brain, snapshot: Snapshot) -> (),
	onEvent: (self: Brain, evt: { [string]: any }) -> (),
}

local Common = {}

Common.TAU = math.pi * 2

function Common.newIntent(): Intent
	return {
		mode = "stand",
		tx = 0,
		tz = 0,
		speed = 0,
		turnRate = 4,
		damp = 6.8,
		laneAxis = nil,
		laneCoord = nil,
		heading = 0,
		routeId = 0,
		s = 0,
		dir = 1,
		railEnd = false,
	}
end

function Common.newActor(
	id: number,
	species: string,
	variant: string,
	brainKind: string,
	x: number,
	z: number,
	hip: number
): Actor
	return {
		id = id,
		species = species,
		variant = variant,
		post = nil,
		brainKind = brainKind,
		x = x,
		y = hip,
		z = z,
		yaw = 0,
		speed = 0,
		hip = hip,
		intent = Common.newIntent(),
		tier = "near",
		alert = 0,
		moved = 0,
		rig = nil,
	}
end

-- halt(actor): the body stands where it is until its brain thinks again. A brain that is handed a
-- body back (a player let go of it) calls this: the intent still holds what the brain wanted before
-- the hand-over (a walk target, a lane lock on a lane that may now be a block away), and the motor
-- would act on it every frame until the next think, which for a far body is a whole second.
function Common.halt(actor: Actor)
	local intent = actor.intent
	intent.mode = "stand"
	intent.speed = 0
	intent.tx, intent.tz = actor.x, actor.z
	intent.laneAxis, intent.laneCoord = nil, nil
	intent.heading = 0 -- the motor leaves the yaw alone
end

function Common.newLeg(): Leg
	return { tx = math.huge, tz = math.huge, points = nil, at = 1, retry = 0, sx = 0, sz = 0, misses = 0 }
end

Common.LEG_REACH = 1.2 -- studs: a point of a way counts as reached
Common.LEG_RETRY = 4 -- seconds before a spot with no way is asked for again (doubled each time, to LEG_RETRY_MAX)
Common.LEG_RETRY_MAX = 64
Common.LEG_OFF = 3 -- studs off the way being walked: the body was taken off it (an order, a call): asked for again

-- toward(leg, actor, ctx, tx, tz): the point to walk to now on the way to (tx, tz): the spot itself when the line
-- is clear (or the world has no ways), else the next point of the town's way there (ctx.way), asked for once per
-- spot, and again when the body is found more than LEG_OFF off the way (something else walked it elsewhere in
-- between: an order, a call). nil when there is no way (the body stands; asked for again after LEG_RETRY).
function Common.toward(leg: Leg, actor: Actor, ctx: Ctx, tx: number, tz: number): (number?, number?)
	local way, clear = ctx.way, ctx.clear
	if way == nil or clear == nil then
		return tx, tz
	end
	local fresh = math.abs(leg.tx - tx) + math.abs(leg.tz - tz) > 0.5 or (leg.points == nil and ctx.now >= leg.retry)
	for _ = 1, 2 do
		if fresh then
			leg.tx, leg.tz, leg.at = tx, tz, 1
			leg.sx, leg.sz = actor.x, actor.z
			if clear(actor.x, actor.z, tx, tz) then
				leg.points = { { tx, tz } }
			else
				leg.points = way(actor.x, actor.z, tx, tz)
				if leg.points == nil then
					-- (across the river from home, say: a search that finds nothing is the dearest, so it is not
					-- repeated often)
					leg.retry = ctx.now + math.min(Common.LEG_RETRY * 2 ^ leg.misses, Common.LEG_RETRY_MAX)
					leg.misses += 1
				else
					leg.misses = 0
				end
			end
		end
		local points = leg.points
		if points == nil then
			return nil, nil
		end
		while
			leg.at < #points
			and Common.dist2d(actor.x, actor.z, points[leg.at][1], points[leg.at][2]) < Common.LEG_REACH
		do
			leg.at += 1
		end
		-- still on the way? (the leg being walked runs from the point before to this one)
		local a = if leg.at > 1 then points[leg.at - 1] else { leg.sx, leg.sz }
		local p = points[leg.at]
		local ex, ez = p[1] - a[1], p[2] - a[2]
		local l2 = ex * ex + ez * ez
		local t = if l2 > 0 then math.clamp(((actor.x - a[1]) * ex + (actor.z - a[2]) * ez) / l2, 0, 1) else 0
		if fresh or Common.dist2d(actor.x, actor.z, a[1] + ex * t, a[2] + ez * t) <= Common.LEG_OFF then
			return p[1], p[2]
		end
		fresh = true -- taken off it since: from here
	end
	return nil, nil
end

-- forget(leg): the next toward() asks for the way again (the body was moved: a hand-back)
function Common.forget(leg: Leg)
	leg.tx, leg.tz, leg.points, leg.retry, leg.misses = math.huge, math.huge, nil, 0, 0
end

-- Shortest signed angle from a to b.
function Common.angleDelta(a: number, b: number): number
	local d = (b - a + math.pi) % Common.TAU - math.pi
	return d
end

-- Yaw from a horizontal direction (HTML convention: yaw 0 faces +Z, +X is yaw pi/2).
function Common.yawOf(dx: number, dz: number): number
	return math.atan2(dx, dz)
end

-- Uniform in [a, b) from a [0, 1) draw.
function Common.range(rng: () -> number, a: number, b: number): number
	return a + (b - a) * rng()
end

function Common.dist2d(ax: number, az: number, bx: number, bz: number): number
	local dx, dz = ax - bx, az - bz
	return math.sqrt(dx * dx + dz * dz)
end

return Common
