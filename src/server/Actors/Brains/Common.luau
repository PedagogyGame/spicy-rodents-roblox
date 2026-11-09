--!strict
-- ServerScriptService.Server.Actors.Brains.Common
-- Shared contract for the minimal W0 brains: the Actor state they read, the Intent they write and
-- the per-tick Ctx the scheduler hands them (BUILD_PLAN §1.4 Brains/*, §1.5 Actor; spike S5).
-- Interface: types Actor, Intent, Ctx, Brain, Snapshot; newIntent(), newActor(), steer helpers.
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
