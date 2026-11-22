--!strict
-- ReplicatedStorage.Shared.World.HollowLayout
-- The hollow trees' insides and the fallen hollow log (brief v2 §3 "Hollow trees"; BRIEF_ADDENDUM D6: "the hollow
-- trees' insides ... and the alley's ball-return tunnel are both enclosed squirrel routes, built and played the same
-- way"). Every hollow is one space and a few enclosed runs on the landed contract (Shared/Routes/Enclosure, kind
-- "tunnel"); nothing here is a mechanic of its own. data/hollows.json is authored (the design: tiers, chambers, the
-- meter; and per hollow an `inside` block in studs about its harvested trunk); tools/compile (lib/HollowTrees) calls
-- HollowLayout.build on it with the harvested routes and writes generated/HollowTrees.luau; Shared/Data appends its
-- route records to the Registry; the server builds the shell parts at boot (Server/World/HollowShell) and everything
-- else reads this module. Pure: no engine calls. Studs, world space, y up. No side effects on require.
--
-- THE TREE-LOCAL FRAME: a point is [bearing, radius, height]: bearing in degrees clockwise from +z seen from above
-- (x = sin, z = cos), radius from the trunk route's own axis at that height, height above the trunk's foot. The bark
-- is the harvested trunk's visual radius (Builders/Trees and the Blender trees: r(1 - 0.48 t), giants
-- max(0.45 u, r/0.95 - 1.05 u t)); a cavity keeps C.wall of it.
--
-- THE KINDS (`variant`; every one entered on foot through a knothole at the ground, mouth "ground", any facing into
-- it, never with E: the ball return's run-through style, so a squirrel chased across a lawn dives in without
-- stopping; the hole's mouth point lies C.holeOut outside the bark, so the walk-in onto the outside trunk is never
-- nearer than it):
--   knothole  a single chamber: the hole, a short run across the floor to a dead end at the back (S turns back)
--   shaft     the hole and the floor; a climb up the cavity wall that winds across it (owner D32: "knarly, knotted
--             sometimes"): from the side of bough `wall` round to the knothole onto bough `knot` part-way (E, or A/D
--             picks it) and back to the top knothole onto bough `wall` (running out goes on along it); a hideout shelf
--             off the climb at `hideout` studs (A/D picks it)
--   escape    as the shaft without the hideout: three apertures, three exits (the ground, bough `knot`, bough `wall`)
--   spiral    the hole and the floor; the winding climb (owner D32: "those spiral staircase way inside the tree is too
--             uniform"): a run of knotty ledges along the inside wall, never nearer the axis than `radius`, swinging
--             in and out by up to `wander` studs round the knots (burls) that bulge from the wall, rising `pitch`
--             studs a turn on average (steeper and shallower by turns, never steeper than C.maxSlope), flat ledges
--             (chambers) at `landings` studs and `ledges` more without one, crossing the hollow on a gnarled root at
--             each of `crossings` (an S across the middle, then on round the other way: a switchback), knotholes at
--             `holes` heights onto short branches of the tree, and out at the top knothole onto the outside trunk
--   log       the fallen hollow log: a straight run through on the ground, a mouth at each end (not claimable)
-- Every tree is different (owner D32: "realistic"): the wander, the pitch, the knots and the boards' shades come from a
-- seeded stream per hollow (rngOf(id)), so a rebuild is the same tree and two trees are never the same.
--
-- GETTING OUT OF A HOLE UP THE TRUNK (owner D32: "smoothly adequately jump out of any hole ... preferably onto a
-- branch, to then wander out"). Every hole above the ground is a "link" mouth with a `hop`: Space there is a short hop
-- out of the bark (Enclosure rule 3, Motion.launchPoint) that the motor's air-catch lands on a branch of the same tree
-- just outside: the bough the hole is cut over (a shaft's knothole is raised over its bough until the hop lands on it:
-- HollowLayout.flight), or else a short branch of its own (a "perch": a route of kind branch, drawn by the shell) laid
-- under the hop's path. E at the hole takes the same branch; from it the squirrel runs out, or E back to the trunk.
--
-- THE INTERFACE
--   HollowLayout.build(doc, harvest, heightAt, opts?) -> Compiled   data/hollows.json + the harvest (the compiler only)
--   HollowLayout.new(compiled) -> Layout     a layout over a compiled table (generated/HollowTrees.luau)
--   HollowLayout.default() -> Layout?        over Shared/Data's "HollowTrees" module (nil when not compiled)
--   HollowLayout.C                           the fixed numbers below
-- Layout:
--   hollows, routes                  the compiled lists (read-only)
--   hollow(id) -> Hollow?            "H1" ... "H12", "LOG"
--   spaceOf(routeId) -> string?      the space (= the routes' enclosure id, "hollow.H1") of a hollow route, else nil
--   hollowOfRoute(routeId) -> Hollow?
--   hollowOfSpace(space?) -> Hollow?  the hollow of a space ("hollow.H1", "hollow.LOG": what contains() gives), else nil
--   contains(x, y, z) -> string?     the space whose cavity holds the point (the server's refuge test); a space, not
--                                    an id: hollowOfSpace turns it into its Hollow (hollow() takes the id, "H1")
--   within(hollow, x, y, z) -> boolean   that hollow's cavity holds the point (its Combat/Cover shape)
--   keepCamera(x, y, z, hx, hy, hz) -> (x, y, z)   a camera point held inside the cavity round a head inside a
--                                    hollow (C.cameraIn inside its wall, floor and roof) and inside its staves (its
--                                    `view`); unchanged for a head outside
--   peekAt(x, y, z) -> Mouth?        the hole up a trunk (a mouth that is not a ground hole) whose point is within
--                                    C.peekReach of the body's feet: the inside camera looks out of it
--   nearest(x, z, maxDist?) -> (Hollow?, number)   level distance to the trunk's foot (the log's middle)
--   HollowLayout.flight(harvest, from, vel, target, opts?) -> (t?, d)   where a hop or leap from `from` lands on route
--                                    `target` by the motor's air-catch rule (C.flight), or nil
--   HollowLayout.rngOf(text) -> () -> [0, 1)   the seeded stream a hollow's shape is drawn from
-- A Hollow (compiled): id, tier, variant, tree, trunk (route id; nil for the log), space, claimable, x, y, z (the
--   trunk's foot; the log's middle on the ground), routes { id } (its enclosed runs), perches { id } (its short
--   branches outside: open routes of kind branch, not in the hollow), mouths { Mouth } (a Mouth's depth and hop as the
--   route's; perch: the branch a hop out of it lands on), chambers { Chamber } (where nuts are stored: a route and t),
--   cavities { Cavity } (each a vertical cylinder: x, z, radius, bottom, top; the log's is along its axis: a, b,
--   radius), meter { capacity, ownAt }, parts { Piece } (the shell the server builds: Piece = role, shape "Block" |
--   "Cylinder" | "Ball", p {x, y, z} centre, xv / yv the frame's right and up (unit), size {x, y, z}, tone? -1..1 a
--   shade either side of the role's colour), view? { {x, z, radius, bottom, top} } (a tree's: where the camera may be,
--   slices up its cavities round the trunk's own axis, inside its staves).

local Curve = require("../Routes/Curve")
local Enclosure = require("../Routes/Enclosure")

local HollowLayout = {}

HollowLayout.C = {
	spu = 2.5, -- studs per HTML unit (Config/Units; data/hollows.json keeps the design's x, z in HTML units)
	wall = 0.45, -- studs of bark kept round a cavity
	holeOut = 1.5, -- studs from the bark's outside to the ground hole's mouth point (the walk-in must not reach the
	-- outside trunk first: Motion.C.walkInReach less Enclosure.C.reach is 3.8 from the axis of a 2.95 stud trunk)
	holeMin = 4.4, -- studs: never nearer the axis than this
	floorLift = 0.3, -- studs: a floor's top above the highest ground under its cavity (and a lawn's grass plate)
	room = 2.8, -- studs: a chamber's height from its floor to its roof
	liner = 0.25, -- studs: the thickness of a liner board
	tier = 6, -- studs: the height of one ring of liner boards up a shaft or the spiral
	ringMin = 9, -- boards in a ring (more on a wide cavity: one each C.ringArc studs of the circumference)
	ringArc = 2.2,
	gap = 1.9, -- studs: the chord a passage cuts through a ring (the body is 1.6 wide)
	shaftIn = 0.4, -- studs: a climb's line inside its cavity's wall (the belly's edges stay off the curved wall, and
	-- off a ring centred on the leaning axis half a tier away)
	boughOut = 0.6, -- studs past the bark where a bough's link is taken (its route comes out of the trunk's axis)
	treadStep = 30, -- degrees of the spiral per tread
	treadDrop = 0.08, -- studs: a tread's top under the run's line
	treadLength = 0.92, -- of the chord between its ends
	shelfMax = 2.3, -- studs: the most a round shelf under the winding climb is across
	shelfDeep = { 1.0, 1.4 }, -- its thickness under its top, in the board's 0.3 (seeded)
	post = 0.55, -- studs: the spiral's heartwood post's clearance inside the ramp's inner edge
	shelf = 1.5, -- studs: a hideout shelf's length across the shaft
	logWall = 0.3,
	-- studs inside each open end of the log: an invisible disc that stops a body walking in off the run (one taken
	-- onto the run rides past it); deeper than half the body's wall probe (ClientWorld.BODY_HALF 1.0), so a body
	-- stepping out of the end is clear of it
	logThreshold = 1.2,
	logOpen = 1.0, -- studs: a body nearer an open end of the log than this is in its opening, seen (not in the cavity)
	cameraIn = 0.3, -- studs: the tunnel camera kept this far inside a cavity's wall (the liner boards stand outside it)
	viewSlice = 2, -- studs: the height of a slice of where the camera may be (a hollow's `view`)
	-- the bark mesh has 14 flats (Builders/Trees, the Blender trees): between its corners it is this much of the
	-- nominal radius; every corner of the shell stays C.barkClear inside that at its height, lean included
	barkFace = math.cos(math.pi / 14),
	barkClear = 0.08,
	-- THE WINDING CLIMB (spiral)
	nodeArc = 1.0, -- studs between the climb's points
	laneClear = 0.2, -- studs between the body's side (Enclosure.BODY width / 2) and the liner boards
	maxSlope = 0.5, -- the steepest the climb rises, studs per stud along it (27 degrees: the old spiral's 0.48)
	minSlope = 0.2, -- and the shallowest, off the ledges
	slopeSwing = 0.45, -- the pitch swings this fraction either side of the authored mean
	crossRise = 0.7, -- studs the root across the hollow rises, all in its middle part (level where it turns at each
	-- end); half a turn either side of it the climb is at its steepest, so the runs over and under it clear it
	rootRadius = 0.45, -- studs: the root's thickness (a log under the run, its top C.ledgeDrop under the line)
	passGap = 2.4, -- studs (level) within which one turn of the climb passes over another: a body's half and a ledge
	passRise = 2.5, -- and the height it must clear it by there: the headroom, a ledge and its drop, and a margin
	crossFoot = 1.5, -- studs of level ledge at each end of a root across
	ledgeWide = 0.35, -- studs further in a chamber's ledge reaches
	ledgeDrop = 0.15, -- studs: a ledge's or a root's top under the winding climb's line (a board laid straight under
	-- a run that turns and rises pokes up at its corners by the turn's angle times the rise)
	crossBow = 3.0, -- the S across: its end tangents this many lane radii long (turns of about 0.75 lane radii)
	landingArc = { 4.5, 6.5 }, -- studs of flat ledge at a chamber (a seeded length between)
	ledgeArc = { 2.4, 3.4 }, -- and at a ledge without one
	holeClear = 3.0, -- studs along the climb between a hole and a ledge or the root across
	burlRoom = 0.4, -- studs between the body's side and the wall a knot needs to bulge into
	burlGap = 0.15, -- studs left between a knot and the body's side
	burlMax = 1.9, -- studs: a knot's largest diameter
	burlCrown = 0.8, -- studs: a knot this wide or wider is rounded by a crown
	-- THE WALL (owner D33): the closed ring of staves round a cavity (HollowLayout.staves)
	stave = {
		width = 1.3, -- studs: a stave's share of the ring's inside (at least minN staves round)
		minN = 10,
		thick = 0.3, -- studs
		lap = 0.12, -- a stave is this much wider than its share, so neighbours overlap and no seam opens
		joint = 0.15, -- studs each board reaches past a joint up its column into the next
		length = { 10, 17 }, -- studs: a board's length up its column (seeded; the first of each column cut shorter)
		jitter = 0.06, -- studs: the most a stave stands in from the ring
		bend = 0.2, -- studs: the most the trunk's axis strays from a straight board up it
		streak = 0.18, -- the share of staves that are a dark streak
		door = 2.1, -- studs over the floor the ground hole's opening reaches (the body's section and a margin)
		doorWide = 2.4, -- studs: the chord it keeps clear at the staves (the body is 1.6 wide; the run in is not
		-- square to a leaning wall)
		window = 1.8, -- studs: the chord of a hole's opening up the trunk at the staves
		sill = -0.15, -- studs over the climb's line at the hole: the opening's bottom
		head = 1.95, -- and its top (the oval on the bark is 2 studs tall, its middle 0.85 over the line)
		rim = 0.25, -- studs: the thickness of a hole's lining back to the bark
		lip = 0.12, -- studs the lining stands proud of the staves
	},
	-- GETTING OUT ABOVE THE GROUND
	hopSpeed = 9, -- st/s: a hole's hop out (Space): level speed (its rise is Enclosure.C.hopUp)
	perchUnder = 0.35, -- studs: a perch's line under the hop's path where the air-catch takes it
	perchLength = { 6, 8 }, -- studs out from the bark
	perchRadius = { 0.5, 0.28 }, -- studs: a perch branch's thickness at the bark and at its tip
	peekReach = 1.6, -- studs from a hole's point (the feet) at which the inside camera peeks out of it
	-- the motor's numbers the flight is worked out with (SquirrelMotor.params, Motion.C; tests/unit/hollows_gnarl
	-- holds them equal): gravity, a full leap off a rail, a mouth's hop rise, the air-catch's reach and the travel
	-- before it takes anything, the launch's clearance outside an opening (Enclosure.C.clear)
	flight = {
		gravity = 75,
		leapForward = 41.25,
		leapUp = 32,
		hopUp = 8.6,
		catch = 1.5,
		catchClear = 2.5,
		clear = 0.9,
		margin = 0.5, -- studs inside the catch's reach a planned landing must come
	},
}
local C = HollowLayout.C

-- told the player on stopping at the far end of a dead end inside (the route record's `hint`: Client/Controllers/Squirrel)
HollowLayout.HINTS = {
	chamber = "Hidden in the hollow: nobody can see you in here (S runs back out)",
	hideout = "The hideout: nobody can see you in here (S goes back down the shaft)",
}

export type Vec3 = { x: number, y: number, z: number }
export type Piece = {
	role: string,
	shape: string,
	p: { number },
	xv: { number },
	yv: { number },
	size: { number },
	tone: number?,
}
export type Mouth = {
	route: number,
	t: number,
	name: string,
	opens: string,
	x: number,
	y: number,
	z: number,
	out: { number },
	link: number?,
	depth: number?,
	hop: number?,
	perch: number?,
}
export type Chamber = {
	id: string,
	route: number,
	t: number,
	x: number,
	y: number,
	z: number,
	cap: number,
	lookout: boolean?,
	hideout: boolean?,
}
export type Cavity = {
	x: number,
	z: number,
	radius: number,
	bottom: number,
	top: number,
	a: { number }?,
	b: { number }?,
}
export type Hollow = {
	id: string,
	tier: string,
	variant: string,
	tree: string,
	trunk: number?,
	space: string,
	claimable: boolean,
	x: number,
	y: number,
	z: number,
	routes: { number },
	perches: { number }?,
	mouths: { Mouth },
	chambers: { Chamber },
	cavities: { Cavity },
	meter: { capacity: number, ownAt: number },
	parts: { Piece },
	view: { { number } }?,
}
export type Compiled = { routes: { any }, hollows: { Hollow } }
export type Layout = {
	hollows: { Hollow },
	routes: { any },
	hollow: (id: string) -> Hollow?,
	spaceOf: (routeId: number) -> string?,
	hollowOfRoute: (routeId: number) -> Hollow?,
	hollowOfSpace: (space: string?) -> Hollow?,
	contains: (x: number, y: number, z: number) -> string?,
	within: (h: Hollow, x: number, y: number, z: number) -> boolean,
	keepCamera: (x: number, y: number, z: number, hx: number, hy: number, hz: number) -> (number, number, number),
	peekAt: (x: number, y: number, z: number) -> Mouth?,
	nearest: (x: number, z: number, maxDist: number?) -> (Hollow?, number),
}

-- anything shaped like Routes/Registry (the compiler passes one over the harvest records)
export type Harvest = {
	get: (self: any, id: number) -> any?,
	pointAt: (self: any, route: any, t: number) -> Vec3,
	tangentAt: (self: any, route: any, t: number) -> Vec3,
}

local function r4(n: number): number
	return math.floor(n * 10000 + 0.5) / 10000
end

local function unit(v: { number }): { number }
	local l = math.sqrt(v[1] * v[1] + v[2] * v[2] + v[3] * v[3])
	if l < 1e-9 then
		return { 0, 1, 0 }
	end
	return { v[1] / l, v[2] / l, v[3] / l }
end

local function cross(a: { number }, b: { number }): { number }
	return { a[2] * b[3] - a[3] * b[2], a[3] * b[1] - a[1] * b[3], a[1] * b[2] - a[2] * b[1] }
end

local function dirOf(bearing: number): (number, number)
	local a = math.rad(bearing)
	return math.sin(a), math.cos(a)
end

local function polyLength(points: { { number } }): number
	local v = {}
	for i, p in points do
		v[i] = Curve.vec3(p[1], p[2], p[3])
	end
	return Curve.new(v):getLength()
end

-- A seeded stream of numbers in [0, 1) (Park-Miller over the text's bytes): exact in doubles, so the same on every
-- machine; a hollow's shape is drawn from rngOf(its id).
function HollowLayout.rngOf(text: string): () -> number
	local s = 7
	for i = 1, #text do
		s = (s * 31 + string.byte(text, i)) % 2147483647
	end
	s = math.max(1, s)
	local function nextOf(): number
		s = (s * 48271) % 2147483647
		return s / 2147483647
	end
	for _ = 1, 4 do
		nextOf()
	end
	return nextOf
end

-- A smooth wobble in [-1, 1] along u (studs): three sines of seeded wavelengths (about 8, 20 and 42 studs) and phases.
local function wave(rand: () -> number): (u: number) -> number
	local ks, ps = {}, {}
	for i, span in { { 6, 11 }, { 15, 26 }, { 33, 51 } } do
		ks[i] = 2 * math.pi / (span[1] + (span[2] - span[1]) * rand())
		ps[i] = 2 * math.pi * rand()
	end
	return function(u: number): number
		return math.sin(ks[1] * u + ps[1]) * 0.5 + math.sin(ks[2] * u + ps[2]) * 0.3 + math.sin(ks[3] * u + ps[3]) * 0.2
	end
end

local function between(rand: () -> number, span: { number }): number
	return span[1] + (span[2] - span[1]) * rand()
end

-- The nearest point of a route to (x, y, z): its t and distance (sampled every 0.1 stud, then refined).
local function nearestOn(harvest: Harvest, route: any, x: number, y: number, z: number): (number, number)
	local n = math.max(8, math.ceil((route.length or 10) / 0.1))
	local best, bt = math.huge, 0
	for i = 0, n do
		local p = harvest:pointAt(route, i / n)
		local d = (p.x - x) ^ 2 + (p.y - y) ^ 2 + (p.z - z) ^ 2
		if d < best then
			best, bt = d, i / n
		end
	end
	return bt, math.sqrt(best)
end

-- flight(harvest, from, vel, target, opts?): a body launched at `from` {x, y, z} with velocity `vel` {x, y, z} (studs,
-- st/s) under the motor's gravity, frame by frame (1/60 s), as the motor's air-catch sees it (SquirrelMotor catchRail,
-- Motion.airCatch): once it has travelled C.flight.catchClear from the launch, the first frame route `target` passes
-- within C.flight.catch less C.flight.margin of it lands it there. Returns the t it lands at (nil when it never does
-- within opts.seconds, default 1.2) and the nearest it came after the clear travel.
function HollowLayout.flight(
	harvest: Harvest,
	from: { number },
	vel: { number },
	target: number,
	opts: { seconds: number? }?
): (number?, number)
	local F = C.flight
	local route = harvest:get(target)
	assert(route, `hollow: flight target {target} missing`)
	local x, y, z = from[1], from[2], from[3]
	local vx, vy, vz = vel[1], vel[2], vel[3]
	local dt = 1 / 60
	local closest = math.huge
	for _ = 1, math.ceil(((opts and opts.seconds) or 1.2) / dt) do
		vy -= F.gravity * dt
		x, y, z = x + vx * dt, y + vy * dt, z + vz * dt
		local travelled = math.sqrt((x - from[1]) ^ 2 + (y - from[2]) ^ 2 + (z - from[3]) ^ 2)
		if travelled >= F.catchClear then
			local t, d = nearestOn(harvest, route, x, y, z)
			closest = math.min(closest, d)
			if d <= F.catch - F.margin then
				return t, d
			end
		end
	end
	return nil, closest
end

-- A trunk's frame: its axis and bark at a height above its foot (tree-local -> world).
export type Trunk = {
	route: any,
	foot: Vec3,
	axisAt: (h: number) -> (number, number, number, number), -- x, y, z and the route's t
	bark: (h: number) -> number,
	toWorld: (bearing: number, radius: number, h: number) -> { number },
	bearingOf: (x: number, z: number, h: number) -> number,
}

function HollowLayout.trunk(harvest: Harvest, id: number): Trunk
	local route = harvest:get(id)
	assert(route and route.kind == "trunk", `hollow: trunk route {id} is not a trunk`)
	local foot = harvest:pointAt(route, 0)
	local top = harvest:pointAt(route, 1)
	local function tAt(h: number): number
		if h <= 0 then
			return 0
		end
		if foot.y + h >= top.y then
			return 1
		end
		local lo, hi = 0, 1
		for _ = 1, 40 do
			local mid = (lo + hi) / 2
			if harvest:pointAt(route, mid).y < foot.y + h then
				lo = mid
			else
				hi = mid
			end
		end
		return (lo + hi) / 2
	end
	local function axisAt(h: number): (number, number, number, number)
		local t = tAt(h)
		local p = harvest:pointAt(route, t)
		return p.x, foot.y + h, p.z, t
	end
	local giant = string.find(string.lower(route.name or ""), "giant trunk", 1, true) ~= nil
	local function bark(h: number): number
		local t = tAt(h)
		local r = route.surfaceRadius
		if giant then
			return math.max(0.45 * C.spu, r / 0.95 - 1.05 * C.spu * t)
		end
		return math.max(0.32 * C.spu, r * (1 - 0.48 * t))
	end
	local function toWorld(bearing: number, radius: number, h: number): { number }
		local x, y, z = axisAt(h)
		local dx, dz = dirOf(bearing)
		return { x + radius * dx, y, z + radius * dz }
	end
	local function bearingOf(x: number, z: number, h: number): number
		local ax, _, az = axisAt(h)
		return math.deg(math.atan2(x - ax, z - az)) % 360
	end
	return {
		route = route,
		foot = foot,
		axisAt = axisAt,
		bark = bark,
		toWorld = toWorld,
		bearingOf = bearingOf,
	}
end

-- Where a bough comes out of the bark (C.boughOut past it): its t, the point, the bearing and height of that point.
function HollowLayout.boughExit(harvest: Harvest, trunk: Trunk, boughId: number): (number, Vec3, number, number)
	local b = harvest:get(boughId)
	assert(b, `hollow: bough route {boughId} missing`)
	for i = 1, 400 do
		local tt = i / 800
		local p = harvest:pointAt(b, tt)
		local h = p.y - trunk.foot.y
		local ax, _, az = trunk.axisAt(h)
		if math.sqrt((p.x - ax) ^ 2 + (p.z - az) ^ 2) >= trunk.bark(h) + C.boughOut then
			return tt, p, trunk.bearingOf(p.x, p.z, h), h
		end
	end
	error(`hollow: bough {boughId} never leaves the bark of trunk {trunk.route.id}`)
end

-- A ring of liner boards round the trunk's axis from a0 to a1 (world points on it; the ring leans with it): boards of
-- inner radius `radius`, leaving out every board whose arc meets one of `gaps` (bearings, degrees, each `gapChord`
-- studs wide at the ring).
local function ring(
	parts: { Piece },
	role: string,
	a0: { number },
	a1: { number },
	radius: number,
	gaps: { number },
	rand: (() -> number)?
)
	local n = math.max(C.ringMin, math.ceil(2 * math.pi * radius / C.ringArc))
	local half = math.pi / n
	local width = 2 * (radius + C.liner) * math.tan(half) + 0.05
	local u = unit({ a1[1] - a0[1], a1[2] - a0[2], a1[3] - a0[3] })
	local len = math.sqrt((a1[1] - a0[1]) ^ 2 + (a1[2] - a0[2]) ^ 2 + (a1[3] - a0[3]) ^ 2)
	local cx, cy, cz = (a0[1] + a1[1]) / 2, (a0[2] + a1[2]) / 2, (a0[3] + a1[3]) / 2
	for k = 0, n - 1 do
		local a = (k + 0.5) * 2 * half -- the board's middle bearing, radians
		local open = false
		for _, g in gaps do
			local ga = math.rad(g)
			local d = math.abs((a - ga + math.pi) % (2 * math.pi) - math.pi)
			-- the board spans [a - half, a + half]; the passage spans its chord's angle either side of g
			local passHalf = math.asin(math.min(1, (C.gap / 2) / radius))
			if d < half + passHalf then
				open = true
			end
		end
		if open then
			continue
		end
		-- the bearing's level direction, square to the axis
		local dx, dz = math.sin(a), math.cos(a)
		local along = dx * u[1] + dz * u[3]
		local rad = unit({ dx - u[1] * along, -u[2] * along, dz - u[3] * along })
		local xv = cross(u, rad)
		local rr = radius + C.liner / 2
		table.insert(parts, {
			role = role,
			shape = "Block",
			p = { r4(cx + rad[1] * rr), r4(cy + rad[2] * rr), r4(cz + rad[3] * rr) },
			xv = { r4(xv[1]), r4(xv[2]), r4(xv[3]) },
			yv = { r4(u[1]), r4(u[2]), r4(u[3]) },
			size = { r4(width), r4(len), C.liner },
			-- (each board a shade of its own: the wall reads as bark, not as a barrel)
			tone = if rand then r4(rand() * 2 - 1) else nil,
		})
	end
end

-- The corners of a piece (a Block's eight; a Cylinder's rims, 24 points each), world points.
function HollowLayout.corners(pc: Piece): { { number } }
	local xv, yv = pc.xv, pc.yv
	local zv = cross(xv, yv)
	local hx, hy, hz = pc.size[1] / 2, pc.size[2] / 2, pc.size[3] / 2
	local out = {}
	local function at(a: number, b: number, c: number)
		table.insert(out, {
			pc.p[1] + xv[1] * a + yv[1] * b + zv[1] * c,
			pc.p[2] + xv[2] * a + yv[2] * b + zv[2] * c,
			pc.p[3] + xv[3] * a + yv[3] * b + zv[3] * c,
		})
	end
	if pc.shape == "Ball" then
		-- a sphere of the smallest size (the engine's rule): 26 points round it, 13 % out (no direction is more than 28
		-- degrees from one of them, 1 / cos 28 = 1.13, so no point of the sphere reaches past them)
		local r = math.min(hx, hy, hz) * 1.13
		for _, d in { -1, 0, 1 } do
			for _, e in { -1, 0, 1 } do
				for _, f in { -1, 0, 1 } do
					local l = math.sqrt(d * d + e * e + f * f)
					if l > 0 then
						at(d / l * r, e / l * r, f / l * r)
					end
				end
			end
		end
		return out
	end
	for _, sx in { -1, 1 } do
		if pc.shape == "Cylinder" then
			-- the axis along xv, round in yv and zv
			for k = 0, 23 do
				local ang = k * math.pi / 12
				at(hx * sx, math.cos(ang) * hy, math.sin(ang) * hy)
			end
		else
			for _, sy in { -1, 1 } do
				for _, sz in { -1, 1 } do
					at(hx * sx, hy * sy, hz * sz)
				end
			end
		end
	end
	return out
end

-- How far the farthest corner of `pieces` stands outside the bark's flats less C.barkClear (studs; <= 0: inside),
-- measured level from the axis at each corner's own height. Corners under the trunk's foot are not measured.
function HollowLayout.barkOver(tr: Trunk, pieces: { Piece }): number
	local over = -math.huge
	for _, pc in pieces do
		for _, c in HollowLayout.corners(pc) do
			local h = c[2] - tr.foot.y
			if h >= 0 then
				local ax, _, az = tr.axisAt(h)
				local d = math.sqrt((c[1] - ax) ^ 2 + (c[3] - az) ^ 2)
				over = math.max(over, d - (tr.bark(h) * C.barkFace - C.barkClear))
			end
		end
	end
	return over
end

-- A flat disc (a vertical-axis cylinder part) at (cx, cz), its top at `top`.
local function disc(parts: { Piece }, role: string, cx: number, cz: number, radius: number, top: number, thick: number)
	table.insert(parts, {
		role = role,
		shape = "Cylinder",
		p = { r4(cx), r4(top - thick / 2), r4(cz) },
		xv = { 0, 1, 0 }, -- a Cylinder's axis is its X
		yv = { -1, 0, 0 },
		size = { r4(thick), r4(2 * radius), r4(2 * radius) },
	})
end

-- A box whose top face runs along a -> b (a tread or a shelf), `width` across, `thick` deep; shifted `off` studs
-- across (level, square to a -> b: the line stays in its top face) away from trunk `tr`'s axis when one is given.
local function slab(
	parts: { Piece },
	role: string,
	a: { number },
	b: { number },
	width: number,
	thick: number,
	off: number?,
	tr: any?
)
	local d = { b[1] - a[1], b[2] - a[2], b[3] - a[3] }
	local len = math.sqrt(d[1] * d[1] + d[2] * d[2] + d[3] * d[3])
	local f = unit(d)
	local side = unit(cross(f, { 0, 1, 0 }))
	local up = cross(side, f)
	local shift = off or 0
	if tr and shift ~= 0 then
		local my = (a[2] + b[2]) / 2
		local ax, _, az = tr.axisAt(my - tr.foot.y)
		local outward = side[1] * ((a[1] + b[1]) / 2 - ax) + side[3] * ((a[3] + b[3]) / 2 - az)
		if outward < 0 then
			shift = -shift
		end
	end
	local mid = {
		(a[1] + b[1]) / 2 - up[1] * thick / 2 + side[1] * shift,
		(a[2] + b[2]) / 2 - up[2] * thick / 2 + side[2] * shift,
		(a[3] + b[3]) / 2 - up[3] * thick / 2 + side[3] * shift,
	}
	table.insert(parts, {
		role = role,
		shape = "Block",
		p = { r4(mid[1]), r4(mid[2]), r4(mid[3]) },
		xv = { r4(side[1]), r4(side[2]), r4(side[3]) },
		yv = { r4(up[1]), r4(up[2]), r4(up[3]) },
		size = { r4(width), r4(thick), r4(len) },
	})
end

-- The dark oval of a knothole on the bark (seen from outside), facing `out` at a world point.
local function knot(parts: { Piece }, p: { number }, out: { number }, w: number, h: number)
	local o = unit({ out[1], 0, out[3] })
	table.insert(parts, {
		role = "knothole",
		shape = "Cylinder",
		p = { r4(p[1]), r4(p[2]), r4(p[3]) },
		xv = { r4(o[1]), 0, r4(o[3]) },
		yv = { 0, 1, 0 },
		size = { 0.12, r4(h), r4(w) },
	})
end

local function record(id: number, name: string, hid: string, pts: { { number } }, enclosure: any): { [string]: any }
	local rounded = {}
	for i, p in pts do
		rounded[i] = { r4(p[1]), r4(p[2]), r4(p[3]) }
	end
	local length = polyLength(rounded)
	return {
		id = id,
		name = name,
		kind = "tunnel",
		speedMult = 1,
		sprintMult = 1,
		surfaceRadius = 0,
		visualOffset = 0,
		length = r4(length),
		sampleCount = Curve.sampleSteps(length / C.spu) + 1,
		points = rounded,
		origin = "hollow",
		generator = "hollow:" .. hid,
		flags = {
			autoGrabExcluded = true,
			isPole = false,
			isGiant = false,
			fixedSurfaceZ = false,
			treeTravel = false,
		},
		enclosure = enclosure,
	}
end

-- t along a polyline (by length) of its point `i`
local function tOfIndex(pts: { { number } }, i: number): number
	local total, upTo = 0, 0
	for k = 2, #pts do
		local a, b = pts[k - 1], pts[k]
		local l = math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2 + (b[3] - a[3]) ^ 2)
		total += l
		if k <= i then
			upTo += l
		end
	end
	return if total > 0 then upTo / total else 0
end

-- studs along `out` (level) from a world point to the outside of the bark at height h
local function depthOut(trunk: Trunk, p: { number }, out: { number }, h: number): number
	local ax, _, az = trunk.axisAt(h)
	local px, pz = p[1] - ax, p[3] - az
	local ol = math.sqrt(out[1] * out[1] + out[3] * out[3])
	local ox, oz = out[1] / ol, out[3] / ol
	local b = px * ox + pz * oz
	-- (the bark as the motor's checks see it: never thinner than the trunk route's surface radius)
	local c = px * px + pz * pz - math.max(trunk.bark(h), trunk.route.surfaceRadius) ^ 2
	return r4(-b + math.sqrt(math.max(0, b * b - c)) + 0.1)
end

local function outOf(bearing: number): { number }
	local dx, dz = dirOf(bearing)
	return { r4(dx), 0, r4(dz) }
end

local function cavityRecord(c: Cavity): any
	return { axis = { c.x, c.z }, radius = c.radius, bottom = c.bottom, top = c.top }
end

local function chamberAt(list: { Chamber }, design: any, route: number, t: number, p: { number })
	if not design then
		return
	end
	table.insert(list, {
		id = design.id,
		route = route,
		t = r4(t),
		x = r4(p[1]),
		y = r4(p[2]),
		z = r4(p[3]),
		cap = design.cap,
		lookout = design.lookout,
		hideout = design.hideout,
	})
end

type Build = {
	rand: () -> number,
	harvest: Harvest,
	heightAt: (x: number, z: number) -> number,
	trunk: Trunk,
	hollow: Hollow,
	base: number,
	routes: { any },
	wallIn: ((h: number) -> number)?, -- the staves' inner radius at a height (wallOf), once the floor is known
}

-- The highest ground under a disc of `radius` round the trunk's foot and at the hole: the floor sits on it.
local function floorHeight(b: Build, radius: number, hole: { number }): number
	local tr = b.trunk
	local best = b.heightAt(hole[1], hole[3])
	for k = 0, 11 do
		for _, rr in { 0, radius * 0.5, radius } do
			local p = tr.toWorld(k * 30, rr, 0)
			best = math.max(best, b.heightAt(p[1], p[3]))
		end
	end
	return best - tr.foot.y + C.floorLift
end

local function cavityOf(tr: Trunk, radius: number, h0: number, h1: number): Cavity
	local x, _, z = tr.axisAt((h0 + h1) / 2)
	return { x = r4(x), z = r4(z), radius = r4(radius), bottom = r4(tr.foot.y + h0), top = r4(tr.foot.y + h1) }
end

-- the ground hole: its mouth point on the ground outside the bark, then in to the cavity's floor
local function holeRun(b: Build, bearing: number): ({ { number } }, number, number)
	local tr = b.trunk
	local holeR = math.max(C.holeMin, tr.bark(0) + C.holeOut)
	local hole = tr.toWorld(bearing, holeR, 0)
	hole[2] = b.heightAt(hole[1], hole[3])
	local floorH = floorHeight(b, tr.bark(0), hole)
	local rc0 = tr.bark(floorH + C.room) - C.wall
	return { hole, tr.toWorld(bearing, rc0 + 0.3, floorH) }, floorH, rc0
end

-- The rings of liner boards from h0 to h1 (tree-local heights): each tier C.tier high (a short last one joins the
-- one under it), leaning with the axis, as wide as the bark lets it be at its top and narrowed until every corner of
-- its boards stays inside the bark's flats (HollowLayout.barkOver): { h, top, a0, a1, rc }.
type Tier = { h: number, top: number, a0: { number }, a1: { number }, rc: number }
local function tierRings(tr: Trunk, h0: number, h1: number): { Tier }
	local out: { Tier } = {}
	local h = h0
	while h < h1 - 0.01 do
		local top = math.min(h + C.tier, h1)
		if h1 - top < 1.5 then
			top = h1
		end
		local x0, y0, z0 = tr.axisAt(h)
		local x1, y1, z1 = tr.axisAt(top)
		local a0, a1 = { x0, y0, z0 }, { x1, y1, z1 }
		if h == h0 then
			-- the bottom ring stands upright on the floor (round the axis at its middle): leaning, its low side would
			-- dip into the ground
			local mx, _, mz = tr.axisAt((h + top) / 2)
			a0, a1 = { mx, y0, mz }, { mx, y1, mz }
		end
		local rc = tr.bark(top) - C.wall
		for _ = 1, 40 do
			local trial: { Piece } = {}
			ring(trial, "liner", a0, a1, rc, {})
			local over = HollowLayout.barkOver(tr, trial)
			if over <= 0 then
				break
			end
			rc -= over + 0.002
		end
		table.insert(out, { h = h, top = top, a0 = a0, a1 = a1, rc = rc })
		h = top
	end
	return out
end

-- the narrowest ring of `rings` within a tier of height h (a climb line between points C.tier apart keeps inside it)
local function ringNear(rings: { Tier }, h: number): number
	local rc = math.huge
	for _, r in rings do
		if r.top >= h - C.tier and r.h <= h + C.tier then
			rc = math.min(rc, r.rc)
		end
	end
	return rc
end

local function caps(b: Build, floorH: number, rcFloor: number, roofH: number, rcRoof: number)
	local tr = b.trunk
	local fx, _, fz = tr.axisAt(floorH)
	disc(b.hollow.parts, "floor", fx, fz, rcFloor, tr.foot.y + floorH, 0.4)
	local rx, _, rz = tr.axisAt(roofH)
	local roofR = rcRoof + C.liner
	for _ = 1, 40 do
		local trial: { Piece } = {}
		disc(trial, "roof", rx, rz, roofR, tr.foot.y + roofH + 0.3, 0.3)
		local over = HollowLayout.barkOver(tr, trial)
		if over <= 0 then
			break
		end
		roofR -= over + 0.002
	end
	disc(b.hollow.parts, "roof", rx, rz, roofR, tr.foot.y + roofH + 0.3, 0.3)
end

local function holeKnot(b: Build, bearing: number, h: number)
	local tr = b.trunk
	knot(b.hollow.parts, tr.toWorld(bearing, tr.bark(h) + 0.03, h), outOf(bearing), 1.9, 2.0)
end

-- The body's box along each span of the build's enclosed runs, as the clearance sweep has it (Enclosure.BODY: half
-- its width either side of the line, from a hair over it up to its headroom along the section's up): a climb with an
-- `up` off its wall leans its box off that wall; a climb on world up (the winding climb) and every level run stand it
-- up. Worked out once a build, as the runs are laid (a piece is checked against the runs laid before it).
type Box = { a: { number }, f: { number }, side: { number }, up: { number }, seg: number, route: number, i: number }
local function boxesOf(b: Build): { Box }
	local out: { Box } = {}
	for _, r in b.routes do
		local pts = r.points
		local e = r.enclosure
		if e == nil then
			continue
		end
		for i = 2, #pts do
			local a, z = pts[i - 1], pts[i]
			local f = unit({ z[1] - a[1], z[2] - a[2], z[3] - a[3] })
			local seg = math.sqrt((z[1] - a[1]) ^ 2 + (z[2] - a[2]) ^ 2 + (z[3] - a[3]) ^ 2)
			local up = { 0, 1, 0 }
			if e.climb and e.upAt then
				local k = e.upAt[math.min(i, #e.upAt)]
				up = { k[2], k[3], k[4] }
			elseif e.climb and e.up and not (e.up[1] == 0 and e.up[3] == 0) then
				up = e.up
			end
			local dot = up[1] * f[1] + up[2] * f[2] + up[3] * f[3]
			up = unit({ up[1] - f[1] * dot, up[2] - f[2] * dot, up[3] - f[3] * dot })
			table.insert(out, { a = a, f = f, side = cross(f, up), up = up, seg = seg, route = r.id, i = i })
		end
	end
	return out
end

-- does any of `points` stand in a body's box (from 0.1 over the line, 0.05 wider either side than the body; `margin`
-- more all round)? The boxes of route `own` from span i0 to i1 (the stretch the piece is laid under: the drop under
-- its own line keeps it out of those, and the clearance sweep holds it to that) are not asked.
local function intrudes(
	boxes: { Box },
	points: { { number } },
	own: number?,
	i0: number?,
	i1: number?,
	margin: number?
): boolean
	local m = margin or 0
	local half = Enclosure.BODY.width / 2 + 0.05 + m
	for _, q in points do
		for _, bx in boxes do
			if bx.route == own and bx.i >= (i0 or 0) and bx.i <= (i1 or 0) then
				continue
			end
			local dx, dy, dz = q[1] - bx.a[1], q[2] - bx.a[2], q[3] - bx.a[3]
			local f, side, up = bx.f, bx.side, bx.up
			local along = dx * f[1] + dy * f[2] + dz * f[3]
			if along < -0.05 - m or along > bx.seg + 0.05 + m then
				continue
			end
			local across = dx * side[1] + dy * side[2] + dz * side[3]
			local upward = dx * up[1] + dy * up[2] + dz * up[3]
			if math.abs(across) <= half and upward >= 0.1 - m and upward <= Enclosure.C.height + 0.05 + m then
				return true
			end
		end
	end
	return false
end

-- points over a piece's surface (a Block's top and bottom faces, 5 by 5 each; a Cylinder's round, 12 about at 5 along)
local function surfacePoints(pc: Piece): { { number } }
	local xv, yv = pc.xv, pc.yv
	local zv = cross(xv, yv)
	local out = {}
	local function at(a: number, bb: number, c: number)
		table.insert(out, {
			pc.p[1] + xv[1] * a + yv[1] * bb + zv[1] * c,
			pc.p[2] + xv[2] * a + yv[2] * bb + zv[2] * c,
			pc.p[3] + xv[3] * a + yv[3] * bb + zv[3] * c,
		})
	end
	local steps = { -0.5, -0.25, 0, 0.25, 0.5 }
	if pc.shape == "Cylinder" then
		local rad = pc.size[2] / 2
		for _, a in steps do
			for k = 0, 11 do
				local ang = k * math.pi / 6
				at(a * pc.size[1], math.cos(ang) * rad, math.sin(ang) * rad)
			end
		end
		-- (and its end faces, the middle and half way out)
		for _, a in { -0.5, 0.5 } do
			at(a * pc.size[1], 0, 0)
			for k = 0, 5 do
				local ang = k * math.pi / 3
				at(a * pc.size[1], math.cos(ang) * rad / 2, math.sin(ang) * rad / 2)
			end
		end
		return out
	end
	for _, a in steps do
		for _, c in steps do
			at(a * pc.size[1], pc.size[2] / 2, c * pc.size[3])
			at(a * pc.size[1], -pc.size[2] / 2, c * pc.size[3])
		end
	end
	return out
end

-- A knot (burl) bulging from the inside wall at (bearing, h): a round boss whose face, `size` across (at most
-- C.burlMax), stands `inner` studs from the axis and which reaches back into the staves (a cylinder along the level
-- radial, at least 0.6 of its width deep: a few dozen triangles, where a ball is hundreds), shrunk until no point of it
-- passes the bark's flats (HollowLayout.barkOver) and it keeps C.burlGap off every run's body; a knot of C.burlCrown
-- or more is rounded by a crown (a smaller boss standing proud of its middle, owner D33: "rounded bulges and burls",
-- not flat discs) where that keeps clear too. Whether one of at least 0.5 studs fits.
local function burl(b: Build, bearing: number, inner: number, h: number, size: number): boolean
	local tr = b.trunk
	local boxes = boxesOf(b)
	local d = math.min(size, C.burlMax)
	-- (its back into the staves, so it grows out of the wall rather than standing off it)
	local back = if b.wallIn then b.wallIn(h) + 0.12 else 0
	local ox, oz = dirOf(bearing)
	local function boss(face: number, depth: number, across: number): Piece
		local c = tr.toWorld(bearing, face + depth / 2, h)
		return {
			role = "burl",
			shape = "Cylinder",
			p = { r4(c[1]), r4(c[2]), r4(c[3]) },
			xv = { r4(ox), 0, r4(oz) },
			yv = { 0, 1, 0 },
			size = { r4(depth), r4(across), r4(across) },
		}
	end
	while d >= 0.5 do
		local pc = boss(inner, math.max(d * 0.6, back - inner), d)
		if
			HollowLayout.barkOver(tr, { pc }) <= 0 and not intrudes(boxes, surfacePoints(pc), nil, nil, nil, C.burlGap)
		then
			pc.tone = r4(b.rand() * 2 - 1)
			table.insert(b.hollow.parts, pc)
			if d >= C.burlCrown then
				local crown = boss(inner - 0.16 * d, 0.3 * d, 0.55 * d)
				if not intrudes(boxes, surfacePoints(crown), nil, nil, nil, C.burlGap) then
					crown.tone = r4(math.clamp((pc.tone :: number) + 0.35, -1, 1))
					table.insert(b.hollow.parts, crown)
				end
			end
			return true
		end
		d -= 0.1
	end
	return false
end

-- A few knots on a chamber's or a shaft's wall where nothing runs (`count` tries between heights h0 and h1, at
-- bearings off `away(h)` by 70 to 290 degrees), each pushed out of every run's way or left out.
local function wallKnots(b: Build, count: number, h0: number, h1: number, away: (h: number) -> number)
	local tr = b.trunk
	for _ = 1, count do
		local h = h0 + (h1 - h0) * b.rand()
		local bearing = away(h) + 70 + 220 * b.rand()
		local rc = tr.bark(h + 1) - C.wall
		local d = 0.7 + 0.8 * b.rand()
		burl(b, bearing, rc - d * 0.45, h, d)
	end
end

-- THE WALL (owner D33, inside H1: "patch stuff together with more textured gnarliness inside the hollow part, but also
-- grainularity"; his screenshot showed a few flat boards with wide gaps to the lawn and the sky). From within, the
-- tree's bark mesh is not drawn at all, so the wall is all that closes the hollow: a ring of narrow staves round the
-- cavity from its floor to its roof. Each stave is a straight board up its column on the trunk's own leaning axis, its
-- outer corners just inside the bark's flats (it follows the trunk's taper: never nearer the axis than the planning
-- rings, tierRings, so it is never in a body's way); C.stave.width a stave round the ring (at least C.stave.minN), a
-- little wider than its share (C.stave.lap) so neighbours overlap and no seam opens from any angle; the joints up a
-- column at seeded heights (no ring of joints across the wall), the boards lapping C.stave.joint past each; a seeded
-- shade a stave, standing in from the ring by up to C.stave.jitter, now and then a dark streak.
-- The only openings are the holes: at the ground hole the staves within a body's passage either side of its bearing
-- (C.stave.doorWide) are left out from the floor to C.stave.door over it; at a hole up the trunk those within
-- C.stave.window of its bearing, from C.stave.sill to C.stave.head over the climb's line there, and the hole is
-- lined back to the bark (role "rim": a sill, a lintel and two jambs, standing C.stave.lip proud of the staves): a dark
-- recess with a lip, the light of the town in it. Where the trunk's axis bends, a board is cut shorter (C.stave.bend).
-- The inner radius of the staves at a height (their faces' distance from the axis), and how many go round (pure).
local function wallOf(tr: Trunk, h0: number): (number, (h: number) -> number)
	local S = C.stave
	local function innerAt(n: number, h: number): number
		-- a board of its share's width (lap included) at inner radius r: its outer corners at (r + thick) * sqrt(1 + k^2)
		local k = math.tan(math.pi / n) * (1 + S.lap)
		local R = tr.bark(h) * C.barkFace - C.barkClear - 0.02
		return R / math.sqrt(1 + k * k) - S.thick
	end
	local n = math.max(S.minN, math.ceil(2 * math.pi * innerAt(S.minN, h0) / S.width))
	return n, function(h: number): number
		return innerAt(n, h)
	end
end

-- a plate (a Block) at `bearing` round the trunk: from radius r0 to r1 out along the level radial, `wide` across it
-- (square to the radial, level), from height y0 to y1 (tree-local), centred `shift` studs across
local function plate(
	tr: Trunk,
	bearing: number,
	r0: number,
	r1: number,
	wide: number,
	y0: number,
	y1: number,
	shift: number
): Piece
	local c = tr.toWorld(bearing, (r0 + r1) / 2, (y0 + y1) / 2)
	local ox, oz = dirOf(bearing)
	-- (x across, y up, z out: right-handed, x = y cross z)
	local xv = { oz, 0, -ox }
	return {
		role = "rim",
		shape = "Block",
		p = { r4(c[1] + xv[1] * shift), r4(c[2]), r4(c[3] + xv[3] * shift) },
		xv = { r4(xv[1]), 0, r4(xv[3]) },
		yv = { 0, 1, 0 },
		size = { r4(wide), r4(y1 - y0), r4(r1 - r0) },
	}
end

-- The closed wall of a hollow from h0 to h1 (tree-local heights); `gaps` = { {h, bearing} }: the ground hole first
-- (h its floor), then each hole up the trunk (h the climb's line there). The rims are laid against the runs already
-- in b.routes (every run of the hollow), each kept out of every body's box or left out.
local function staves(b: Build, h0: number, h1: number, gaps: { { number } })
	local tr, S, parts = b.trunk, C.stave, b.hollow.parts
	local rand = HollowLayout.rngOf("hollow wall " .. b.hollow.id)
	local n, inner = wallOf(tr, h0)
	local step = 360 / n
	local turn = rand() * step
	local halfRad = math.pi / n
	type Opening = { b: number, lo: number, hi: number, half: number, up: boolean, cols: { number } }
	local opens: { Opening } = {}
	for i, g in gaps do
		if i == 1 then
			-- the ground hole: every stave whose span meets the body's passage (C.stave.doorWide) at the staves
			local ri = inner(g[1] + 1)
			local pass = math.asin(math.min(1, (S.doorWide / 2) / ri))
			table.insert(
				opens,
				{ b = g[2], lo = h0 - 1, hi = g[1] + S.door, half = math.deg(halfRad + pass), up = false, cols = {} }
			)
		else
			-- a hole up the trunk: every stave whose middle is within the window's chord and half a stave
			local ri = inner(g[1] + 1)
			local w = math.asin(math.min(1, (S.window / 2) / ri))
			table.insert(opens, {
				b = g[2],
				lo = g[1] + S.sill,
				hi = g[1] + S.head,
				half = math.deg(w + halfRad * 0.5),
				up = true,
				cols = {},
			})
		end
	end
	local function off(a: number, z: number): number
		return (a - z + 180) % 360 - 180
	end
	-- one board up column `a` from e0 to e1, standing `jit` in from the ring
	local function board(a: number, e0: number, e1: number, jit: number, tone: number)
		local width = 2 * (inner(e0) + S.thick) * math.tan(halfRad) * (1 + S.lap)
		for _ = 1, 30 do
			local p0 = tr.toWorld(a, inner(e0) - jit + S.thick / 2, e0)
			local p1 = tr.toWorld(a, inner(e1) - jit + S.thick / 2, e1)
			local d = { p1[1] - p0[1], p1[2] - p0[2], p1[3] - p0[3] }
			local u = unit(d)
			local len = math.sqrt(d[1] * d[1] + d[2] * d[2] + d[3] * d[3])
			local dx, dz = dirOf(a)
			local along = dx * u[1] + dz * u[3]
			local rad = unit({ dx - u[1] * along, -u[2] * along, dz - u[3] * along })
			local xv = cross(u, rad)
			local pc: Piece = {
				role = "liner",
				shape = "Block",
				p = { r4((p0[1] + p1[1]) / 2), r4((p0[2] + p1[2]) / 2), r4((p0[3] + p1[3]) / 2) },
				xv = { r4(xv[1]), r4(xv[2]), r4(xv[3]) },
				yv = { r4(u[1]), r4(u[2]), r4(u[3]) },
				size = { r4(width), r4(len), S.thick },
				tone = r4(tone),
			}
			local over = HollowLayout.barkOver(tr, { pc })
			if over <= 0 then
				table.insert(parts, pc)
				return
			end
			jit += over + 0.002
		end
	end
	for k = 0, n - 1 do
		local a = turn + (k + 0.5) * step
		-- the column's runs: h0 to h1 less the openings it meets
		local runs = { { h0, h1 } }
		for _, o in opens do
			if math.abs(off(a, o.b)) < o.half then
				table.insert(o.cols, off(a, o.b))
				local nextRuns = {}
				for _, r in runs do
					if o.hi <= r[1] or o.lo >= r[2] then
						table.insert(nextRuns, r)
					else
						if o.lo > r[1] then
							table.insert(nextRuns, { r[1], o.lo })
						end
						if o.hi < r[2] then
							table.insert(nextRuns, { o.hi, r[2] })
						end
					end
				end
				runs = nextRuns
			end
		end
		local jit = rand() * S.jitter
		local tone = if rand() < S.streak then -1 else rand() * 1.6 - 0.6
		for _, r in runs do
			if r[2] - r[1] < 0.2 then
				continue
			end
			-- the boards up this run: the first cut short by a seeded share (the joints stagger round the ring)
			-- (and a board is cut shorter where the trunk's axis bends: a straight board follows it within C.stave.bend)
			local function bent(a0: number, a1: number): boolean
				local x0, _, z0 = tr.axisAt(a0)
				local x1, _, z1 = tr.axisAt(a1)
				local xm, _, zm = tr.axisAt((a0 + a1) / 2)
				return math.sqrt((xm - (x0 + x1) / 2) ^ 2 + (zm - (z0 + z1) / 2) ^ 2) > S.bend
			end
			local seeded = { r[1] }
			local at = r[1] + between(rand, S.length) * (0.3 + 0.7 * rand())
			while at < r[2] - 2.5 do
				table.insert(seeded, at)
				at += between(rand, S.length)
			end
			table.insert(seeded, r[2])
			local cuts = { r[1] }
			for i = 2, #seeded do
				-- (halved until straight enough, each half in turn)
				local stack = { seeded[i] }
				while #stack > 0 do
					local from, to = cuts[#cuts], stack[#stack]
					if to - from > 2 and bent(from, to) then
						table.insert(stack, (from + to) / 2)
					else
						table.insert(cuts, to)
						table.remove(stack)
					end
				end
			end
			for i = 2, #cuts do
				local e0 = cuts[i - 1] - (if i > 2 then S.joint else 0)
				local e1 = cuts[i] + (if i < #cuts then S.joint else 0)
				board(a, e0, e1, jit, tone)
				-- (each board of a column a shade of its own, near the column's)
				tone = math.clamp(tone + (rand() - 0.5) * 0.5, -1, 1)
			end
		end
	end
	-- the lining of each hole up the trunk: a sill, a lintel and the two jambs, from C.stave.lip proud of the staves back
	-- to the bark; each narrowed off the bark's flats, kept out of every body's box (a sill lowered first) or left out
	local boxes = boxesOf(b)
	for _, o in opens do
		if not o.up or #o.cols == 0 then
			continue
		end
		local lo, hi = math.huge, -math.huge
		for _, c in o.cols do
			lo, hi = math.min(lo, c - step / 2), math.max(hi, c + step / 2)
		end
		local hc = (o.lo + o.hi) / 2
		local ri = inner(hc) - S.lip
		local outer = tr.bark(hc) * C.barkFace - C.barkClear
		local chord = 2 * inner(hc) * math.sin(math.rad(hi - lo) / 2)
		local mid = o.b + (lo + hi) / 2
		-- (each piece's maker, and the drops to try it at: a sill may sink a little under the climb's line)
		type Try = { make: (drop: number, r1: number) -> Piece, drops: { number } }
		local tries: { Try } = {
			{
				make = function(drop: number, r1: number): Piece
					return plate(tr, mid, ri, r1, chord + 2 * S.rim, o.lo - S.rim - drop, o.lo - drop, 0)
				end,
				drops = { 0, 0.1, 0.2, 0.3 },
			},
			{
				make = function(_drop: number, r1: number): Piece
					return plate(tr, mid, ri, r1, chord + 2 * S.rim, o.hi, o.hi + S.rim, 0)
				end,
				drops = { 0 },
			},
		}
		for _, side in { -1, 1 } do
			local edge = o.b + (if side < 0 then lo else hi)
			table.insert(tries, {
				make = function(_drop: number, r1: number): Piece
					-- (its face on the opening's edge: shifted half its thickness into the opening)
					return plate(tr, edge, ri, r1, S.rim, o.lo, o.hi, -side * S.rim / 2)
				end,
				drops = { 0 },
			})
		end
		for _, try in tries do
			local make, drops = try.make, try.drops
			for _, drop in drops do
				local r1 = outer
				local pc = make(drop, r1)
				for _ = 1, 30 do
					local over = HollowLayout.barkOver(tr, { pc })
					if over <= 0 then
						break
					end
					r1 -= over + 0.002
					pc = make(drop, r1)
				end
				if
					r1 > ri + 0.1
					and HollowLayout.barkOver(tr, { pc }) <= 0
					and not intrudes(boxes, surfacePoints(pc), nil, nil, nil, 0)
				then
					pc.tone = r4(-0.5 - 0.5 * rand())
					table.insert(parts, pc)
					break
				end
			end
		end
	end
end

-- A branch record (an open route of kind branch: running, leaping and E as on any bough; its far end told by `hint`).
local function branchRecord(id: number, name: string, hid: string, pts: { { number } }): { [string]: any }
	local rounded = {}
	for i, p in pts do
		rounded[i] = { r4(p[1]), r4(p[2]), r4(p[3]) }
	end
	local length = polyLength(rounded)
	return {
		id = id,
		name = name,
		kind = "branch",
		speedMult = 1,
		sprintMult = 1,
		surfaceRadius = C.perchRadius[1],
		visualOffset = 0, -- (the line is the branch's top: the body is drawn on it)
		length = r4(length),
		sampleCount = Curve.sampleSteps(length / C.spu) + 1,
		points = rounded,
		origin = "hollow",
		generator = "hollow:" .. hid,
		hint = "The end of the branch: Space leaps on, Q drops down, S runs back to the trunk",
		flags = {
			autoGrabExcluded = true,
			isPole = false,
			isGiant = false,
			fixedSurfaceZ = false,
			treeTravel = true,
		},
	}
end

-- The hop out of a hole whose point (the feet) is `p`, `out` level, the bark's face `depth` out along it: the launch
-- point (Motion.launchPoint) and the point of the hop's path where it has travelled C.flight.catchClear + 0.4.
local function hopPath(p: { number }, out: { number }, depth: number, speed: number): ({ number }, { number })
	local F = C.flight
	local ol = math.sqrt(out[1] ^ 2 + out[3] ^ 2)
	local ox, oz = out[1] / ol, out[3] / ol
	local l = { p[1] + ox * (depth + F.clear), p[2], p[3] + oz * (depth + F.clear) }
	local tt = 0
	while tt < 1 do
		tt += 1 / 240
		local x, y = speed * tt, F.hopUp * tt - F.gravity * tt * tt / 2
		if math.sqrt(x * x + y * y) >= F.catchClear + 0.4 then
			return l, { l[1] + ox * x, l[2] + y, l[3] + oz * x }
		end
	end
	return l, l
end

-- A perch: a short branch of the tree under a hole's hop (C.hopSpeed): its line passes C.perchUnder under the hop's
-- path where the air-catch takes it, rises a little back to the bark at the hole's bearing, and runs on out to about
-- C.perchLength from the bark, bending and drooping a seeded amount. Its pieces (role "perch") are tapering bark
-- cylinders whose tops are the line, the first one sunk into the bark. Returns the record and the t of the catch.
local function perch(
	b: Build,
	id: number,
	name: string,
	p: { number },
	out: { number },
	depth: number,
	bearing: number
): ({ [string]: any }, number)
	local tr, rand = b.trunk, b.rand
	local _, q = hopPath(p, out, depth, C.hopSpeed)
	q = { q[1], q[2] - C.perchUnder, q[3] }
	local hq = q[2] - tr.foot.y
	local base = tr.toWorld(bearing, tr.bark(hq + 0.3) + 0.1, hq + 0.3)
	local ax, _, az = tr.axisAt(hq)
	local reach = math.sqrt((q[1] - ax) ^ 2 + (q[3] - az) ^ 2) - tr.bark(hq)
	local rest = math.max(2, between(rand, C.perchLength) - reach)
	local bx, bz = dirOf(bearing + (rand() * 2 - 1) * 25)
	local droop = (rand() * 2 - 1) * 0.6 - 0.2
	local mid = { q[1] + bx * rest * 0.5, q[2] + droop * 0.35, q[3] + bz * rest * 0.5 }
	local tip = { q[1] + bx * rest, q[2] + droop, q[3] + bz * rest }
	local pts = { base, q, mid, tip }
	local rec = branchRecord(id, name, b.hollow.id, pts)
	-- the pieces: one cylinder a span, its top on the line, the first reaching 0.6 back into the bark
	local r0, r1 = C.perchRadius[1], C.perchRadius[2]
	local total = rec.length
	local along = 0
	for i = 2, #pts do
		local a, z = pts[i - 1], pts[i]
		local f = unit({ z[1] - a[1], z[2] - a[2], z[3] - a[3] })
		local len = math.sqrt((z[1] - a[1]) ^ 2 + (z[2] - a[2]) ^ 2 + (z[3] - a[3]) ^ 2)
		local rad = r0 + (r1 - r0) * (along + len / 2) / total
		along += len
		local back = if i == 2 then 0.6 else 0
		local cx = (a[1] + z[1]) / 2 - f[1] * back / 2
		local cy = (a[2] + z[2]) / 2 - f[2] * back / 2 - rad
		local cz = (a[3] + z[3]) / 2 - f[3] * back / 2
		local side = unit(cross(f, { 0, 1, 0 }))
		table.insert(b.hollow.parts, {
			role = "perch",
			shape = "Cylinder",
			p = { r4(cx), r4(cy), r4(cz) },
			xv = { r4(f[1]), r4(f[2]), r4(f[3]) },
			yv = { r4(side[1]), r4(side[2]), r4(side[3]) },
			size = { r4(len + back), r4(2 * rad), r4(2 * rad) },
			tone = r4(rand() * 2 - 1),
		})
	end
	return rec, r4(tOfIndex(rec.points, 2))
end

-- A hole up the trunk at a climb's point `p` (height h, `bearing` its side, `out` level): onto bough `bough` when a hop
-- or a full leap out of it lands there (HollowLayout.flight: the first of a hop at C.hopSpeed, slower hops and the
-- leap that does, nearest the trunk), else onto a perch of its own (perchId) under a hop. Returns the mouth record
-- (opens "link"; its `t` set by the caller), the perch record if one was made, and the out it launches along.
local function holeOnto(
	b: Build,
	p: { number },
	h: number,
	bearing: number,
	out: { number },
	bough: number?,
	boughT: number?,
	perchId: number,
	name: string
): ({ [string]: any }, { [string]: any }?)
	local tr, F = b.trunk, C.flight
	local depth = depthOut(tr, p, out, h)
	if bough then
		local ol = math.sqrt(out[1] ^ 2 + out[3] ^ 2)
		local ox, oz = out[1] / ol, out[3] / ol
		local l = { p[1] + ox * (depth + F.clear), p[2], p[3] + oz * (depth + F.clear) }
		for _, speed in { C.hopSpeed, 5, 3.5, 11, 0 } do
			local vel = if speed > 0
				then { ox * speed, F.hopUp, oz * speed }
				else { ox * F.leapForward, F.leapUp, oz * F.leapForward }
			local landT = HollowLayout.flight(b.harvest, l, vel, bough)
			if landT and landT <= 0.4 then
				return {
					opens = "link",
					out = out,
					depth = depth,
					hop = if speed > 0 then speed else nil,
					links = { { route = bough, t = r4(boughT or landT), dir = 1 } },
					name = name,
				},
					nil
			end
		end
	end
	local rec, catchT = perch(b, perchId, `hollow {b.hollow.id} {name} branch`, p, out, depth, bearing)
	return {
		opens = "link",
		out = out,
		depth = depth,
		hop = C.hopSpeed,
		links = { { route = perchId, t = catchT, dir = 1 } },
		name = name,
	},
		rec
end

local VARIANTS: { [string]: (b: Build, design: any, inside: any) -> () } = {}

-- a single chamber: the hole, across the floor to a dead end at the back; a few knots in its wall
VARIANTS.knothole = function(b: Build, design: any, inside: any)
	local tr, hl = b.trunk, b.hollow
	local bearing = inside.hole
	local pts, floorH, rc0 = holeRun(b, bearing)
	local _, wallIn = wallOf(tr, floorH - 0.05)
	b.wallIn = wallIn
	table.insert(pts, tr.toWorld(bearing + 180, rc0 - 1.0, floorH))
	local id = b.base + 1
	local cav = cavityOf(tr, rc0, floorH, floorH + C.room)
	table.insert(hl.cavities, cav)
	table.insert(
		b.routes,
		record(id, `hollow {hl.id} ground hole and chamber`, hl.id, pts, {
			id = hl.space,
			mouths = { { t = 0, opens = "ground", name = "ground hole" } },
			cavity = cavityRecord(cav),
		})
	)
	b.routes[#b.routes].hint = HollowLayout.HINTS.chamber
	chamberAt(hl.chambers, design.chambers[1], id, 1, pts[#pts])
	staves(b, floorH - 0.05, floorH + C.room, { { floorH, bearing } })
	caps(b, floorH, rc0, floorH + C.room, rc0)
	holeKnot(b, bearing, floorH + 0.9)
	wallKnots(b, 3, floorH + 0.9, floorH + C.room - 0.6, function()
		return bearing
	end)
end

-- the climb up the cavity wall (shaft; escape without the hideout): it winds from the wall side of bough `wall` round
-- to the knothole over bough `knot` and back to the top knothole onto bough `wall`, the shorter way round each time, a
-- seeded wobble between
local function shaftLike(b: Build, design: any, inside: any, hideout: boolean)
	local tr, hl, rand = b.trunk, b.hollow, b.rand
	local bearing = inside.hole
	local wallT, _, wallB, wallH = HollowLayout.boughExit(b.harvest, tr, inside.wall)
	local knotT, _, knotB, knotH0 = HollowLayout.boughExit(b.harvest, tr, inside.knot)
	local top = wallH - 1
	local pts, floorH, rc0 = holeRun(b, bearing)
	local _, wallIn = wallOf(tr, floorH - 0.05)
	b.wallIn = wallIn
	-- the climb's line: C.shaftIn inside the wall above it, and inside the rings round it (narrowed to the bark)
	local rings = tierRings(tr, floorH - 0.05, top + C.room)
	local function rho(h: number): number
		return math.min(tr.bark(math.min(h + C.tier, top + C.room)) - C.wall, ringNear(rings, h)) - C.shaftIn
	end
	local h0 = floorH + 0.5
	local hideH = inside.hideout or 0
	-- the knothole's height: over its bough by as little as lets a hop (or a leap) out of it land on the bough, clear
	-- of the hideout and the top; its bearing the bough's
	local knotOut = outOf(knotB)
	local knotH = knotH0
	for dh = 0, 2.4, 0.4 do
		local hh = knotH0 + dh
		if hh > top - 3 or (hideout and math.abs(hh - hideH) < 2.5) then
			continue
		end
		local p = tr.toWorld(knotB, rho(hh), hh)
		local m = holeOnto(b, p, hh, knotB, knotOut, inside.knot, nil, -1, "probe")
		if m.links[1].route == inside.knot then
			knotH = hh
			break
		end
		-- (a perch probe drew pieces: take them back)
		while #hl.parts > 0 and hl.parts[#hl.parts].role == "perch" do
			table.remove(hl.parts)
		end
	end
	-- the climb's bearing at a height: anchors at the foot (the wall's side, a seeded way off it), the knothole and the
	-- top, each step the shorter way round, eased in and out; a seeded wobble that is nil at the anchors between
	local function signed(a: number): number
		return (a + 180) % 360 - 180
	end
	local anchors = { { h0, wallB + (rand() * 2 - 1) * 30 }, { knotH, knotB }, { top, wallB } }
	for i = 2, #anchors do
		anchors[i][2] = anchors[i - 1][2] + signed(anchors[i][2] - anchors[i - 1][2])
	end
	local wobble, amp = wave(rand), 10 + 8 * rand()
	local function bearingAt(h: number): number
		if h <= anchors[1][1] then
			return anchors[1][2]
		end
		for i = 2, #anchors do
			local a, z = anchors[i - 1], anchors[i]
			if h <= z[1] then
				local f = (h - a[1]) / math.max(z[1] - a[1], 1e-6)
				local ease = f * f * (3 - 2 * f)
				return a[2] + (z[2] - a[2]) * ease + amp * wobble(h) * math.sin(math.pi * f)
			end
		end
		return anchors[#anchors][2]
	end
	table.insert(pts, tr.toWorld(bearingAt(h0), rho(floorH) - 0.7, floorH))
	local floorId, shaftId, hideId = b.base + 1, b.base + 2, b.base + 3
	local knotPerchId, topPerchId = b.base + 4, b.base + 5
	-- the line, a point a stud of height (and exactly at the knothole and the hideout), its section's up off the wall
	local heights = {}
	local h = h0
	while h < top - 0.01 do
		table.insert(heights, h)
		h = math.min(h + 1, top)
		if top - h < 0.5 then
			h = top
		end
	end
	table.insert(heights, top)
	for _, extra in { knotH, if hideout then hideH else nil } do
		local seen = false
		for _, hh in heights do
			seen = seen or math.abs(hh - extra) < 0.3
		end
		if not seen then
			table.insert(heights, extra)
		end
	end
	table.sort(heights)
	local shaft, ups = {}, {}
	local knotI, hideI = 1, 1
	for i, hh in heights do
		local bb = bearingAt(hh)
		shaft[i] = tr.toWorld(bb, rho(hh), hh)
		local o = outOf(bb + 180)
		ups[i] = o
		if math.abs(hh - knotH) < 0.3 then
			knotI = i
		end
		if hideout and math.abs(hh - hideH) < 0.3 then
			hideI = i
		end
	end
	local upAt = {}
	for i, o in ups do
		upAt[i] = { r4(tOfIndex(shaft, i)), o[1], 0, o[3] }
	end
	local knotTs = tOfIndex(shaft, knotI)
	local hideT = tOfIndex(shaft, hideI)
	local forks = {}
	if hideout then
		table.insert(forks, { t = r4(hideT), route = hideId, toT = 0, dir = 1, name = "hideout" })
	end
	local rcTop = tr.bark(top + C.room) - C.wall
	local floorCav = cavityOf(tr, rc0, floorH, floorH + C.room)
	local shaftCav = cavityOf(tr, rcTop, floorH, top + C.room)
	table.insert(hl.cavities, floorCav)
	table.insert(hl.cavities, shaftCav)
	table.insert(
		b.routes,
		record(floorId, `hollow {hl.id} ground hole and floor`, hl.id, pts, {
			id = hl.space,
			mouths = { { t = 0, opens = "ground", name = "ground hole" } },
			atEnd = { route = shaftId, t = 0, dir = 1 },
			cavity = cavityRecord(floorCav),
		})
	)
	-- the knothole over bough `knot` and the top knothole along bough `wall` (Motion.mouthOut: its bark is measured that
	-- way), each onto its bough when a hop or a leap lands there, else onto a perch
	local knotMouth, knotPerch =
		holeOnto(b, shaft[knotI], knotH, knotB, knotOut, inside.knot, knotT, knotPerchId, "knothole")
	knotMouth.t = r4(knotTs)
	local wt = b.harvest:tangentAt(assert(b.harvest:get(inside.wall)), wallT)
	local wallOut = { r4(wt.x), 0, r4(wt.z) }
	local wl = math.sqrt(wallOut[1] ^ 2 + wallOut[3] ^ 2)
	wallOut = { r4(wallOut[1] / wl), 0, r4(wallOut[3] / wl) }
	local topMouth, topPerch =
		holeOnto(b, shaft[#shaft], top, wallB, wallOut, inside.wall, wallT, topPerchId, "top knothole")
	topMouth.t = 1
	-- (the top runs on along bough `wall` with W whatever Space lands on)
	topMouth.links = { { route = inside.wall, t = r4(wallT), dir = 1 }, topMouth.links[1] }
	if topMouth.links[2].route == inside.wall then
		table.remove(topMouth.links, 2)
	end
	table.insert(
		b.routes,
		record(shaftId, `hollow {hl.id} shaft`, hl.id, shaft, {
			id = hl.space,
			climb = true,
			upAt = upAt,
			atStart = { route = floorId, t = 1, dir = -1 },
			forks = if #forks > 0 then forks else nil,
			cavity = cavityRecord(shaftCav),
			mouths = { knotMouth, topMouth },
		})
	)
	local chambers = design.chambers
	chamberAt(hl.chambers, chambers[1], floorId, 1, pts[#pts])
	if hideout then
		-- across the cavity from the wall it climbs (the climbing body's back stays clear of the shelf)
		local hideB = inside.hideoutBearing or (bearingAt(hideH) + 180)
		local rcHide = tr.bark(hideH + C.tier) - C.wall
		local hide = {
			shaft[hideI],
			tr.toWorld(hideB, 0.8, hideH + 0.1),
			tr.toWorld(hideB, rcHide - 0.6, hideH + 0.2),
		}
		table.insert(
			b.routes,
			record(hideId, `hollow {hl.id} hideout`, hl.id, hide, {
				id = hl.space,
				atStart = { route = shaftId, t = r4(hideT), dir = -1 }, -- (S off the shelf goes on down the shaft)
				cavity = cavityRecord(shaftCav),
			})
		)
		b.routes[#b.routes].hint = HollowLayout.HINTS.hideout
		slab(hl.parts, "shelf", tr.toWorld(hideB, 0.6, hideH + 0.1), tr.toWorld(hideB, rcHide, hideH + 0.2), 1.9, 0.3)
		-- the middle store: on the shaft half way up to the hideout (a knothole is a mouth: never a hiding place)
		local midH = (h0 + hideH) / 2
		local midI = 1
		for i, hh in heights do
			if math.abs(hh - midH) < math.abs(heights[midI] - midH) then
				midI = i
			end
		end
		chamberAt(hl.chambers, chambers[2], shaftId, tOfIndex(shaft, midI), shaft[midI])
		chamberAt(hl.chambers, chambers[3], hideId, 1, hide[#hide])
	end
	for _, rec in { knotPerch, topPerch } do
		if rec then
			table.insert(b.routes, rec)
		end
	end
	local topB = bearingAt(top)
	staves(b, floorH - 0.05, top + C.room, { { floorH, bearing }, { knotH, knotB }, { top, topB } })
	caps(b, floorH, rc0, top + C.room, rcTop)
	holeKnot(b, bearing, floorH + 0.9)
	holeKnot(b, knotB, knotH + 0.85)
	holeKnot(b, topB, top + 0.85)
	-- knots on the wall the climb leaves free (clear of the holes)
	wallKnots(b, 10, floorH + 1.5, top, function(hh: number): number
		return bearingAt(hh)
	end)
end

VARIANTS.shaft = function(b: Build, design: any, inside: any)
	shaftLike(b, design, inside, true)
end
VARIANTS.escape = function(b: Build, design: any, inside: any)
	shaftLike(b, design, inside, false)
end

-- THE WINDING CLIMB (variant spiral): knotty ledges along the inside wall, round and up, the other way after each root
-- across the hollow, knotholes onto short branches on the way, out at the top onto the outside trunk
type Node = { b: number, r: number, h: number, kind: string, u: number, s: number }
VARIANTS.spiral = function(b: Build, design: any, inside: any)
	local tr, hl, rand = b.trunk, b.hollow, b.rand
	local bearing = inside.hole
	local topH = inside.top
	local pts, floorH, rc0 = holeRun(b, bearing)
	local _, wallIn = wallOf(tr, floorH - 0.05)
	b.wallIn = wallIn
	local rings = tierRings(tr, floorH - 0.05, topH + C.room)
	local half = Enclosure.BODY.width / 2
	local function laneMax(h: number): number
		return ringNear(rings, h) - half - C.laneClear
	end
	local rMin = inside.radius
	local wander = inside.wander or 0.8
	local wR, wS = wave(rand), wave(rand)
	local function laneAt(h: number, u: number): number
		local hi = laneMax(h)
		local lo = math.min(hi, math.max(rMin, hi - wander))
		return hi - (hi - lo) * (0.5 + 0.5 * wR(u))
	end
	local mean = inside.pitch / (2 * math.pi * (laneMax(floorH) - wander / 2))
	local holes: { number } = table.clone(inside.holes or {})
	local landings: { number } = table.clone(inside.landings or {})
	table.insert(landings, topH)
	local crossings: { number } = table.clone(inside.crossings or {})
	-- ledges without a chamber: seeded heights clear of the others by 3 studs
	local ledges: { number } = {}
	for _ = 1, inside.ledges or 0 do
		for _ = 1, 30 do
			local lh = floorH + 4 + (topH - 7 - floorH) * rand()
			local ok = true
			for _, list in { landings, crossings, ledges, holes } do
				for _, x in list do
					ok = ok and math.abs(lh - x) >= 3
				end
			end
			if ok then
				table.insert(ledges, lh)
				break
			end
		end
	end
	table.sort(ledges)
	-- the nodes, a stud apart along the lane (tree-local: bearing, radius, height; `u` studs along, `s` the slope)
	local nodes: { Node } = {}
	local dir = if rand() < 0.5 then 1 else -1
	local theta = bearing + 40 * dir
	local h, u = floorH, 0
	local r = laneAt(h, u)
	local function add(kind: string, s: number)
		table.insert(nodes, { b = theta, r = r, h = h, kind = kind, u = u, s = s })
	end
	add("lane", 0)
	local nextL, nextX, nextE = 1, 1, 1
	local flatLeft, flatHalf, chamberDue = 0, 0, false
	local footed = false -- the level foot before the next root is laid
	local lastCross = -math.huge -- u at the end of the last root
	local landingAt: { number } = {}
	while true do
		if flatLeft <= 0 and crossings[nextX] and h >= crossings[nextX] and not footed then
			-- a level foot where the root leaves the wall
			footed = true
			flatLeft, flatHalf, chamberDue = C.crossFoot, 0, false
		elseif flatLeft <= 0 and crossings[nextX] and h >= crossings[nextX] then
			-- the root across: an S from here through the middle to the far side (its end tangents along the lane's
			-- travel, C.crossBow lane radii long), rising C.crossRise in its middle; then on round the other way. Laid
			-- only where all of it clears the turns under it (C.passGap, C.passRise): else the climb goes on a stud and
			-- tries again (and gives up 4 studs over the height asked)
			local a = nodes[#nodes]
			local hb = a.h + C.crossRise
			local rb = laneAt(hb, u + 2 * a.r)
			local ba = math.rad(a.b)
			local p0x, p0z = a.r * math.sin(ba), a.r * math.cos(ba)
			local p1x, p1z = -rb * math.sin(ba), -rb * math.cos(ba)
			local tx, tz = math.cos(ba) * dir, -math.sin(ba) * dir
			local mag = C.crossBow * (a.r + rb) / 2
			local n = math.max(4, math.ceil((a.r + rb) * 1.5 / C.nodeArc))
			local across: { { number } } = {}
			local clear = true
			for i = 1, n do
				local sv = i / n
				local h00, h10 = 2 * sv ^ 3 - 3 * sv ^ 2 + 1, sv ^ 3 - 2 * sv ^ 2 + sv
				local h01, h11 = -2 * sv ^ 3 + 3 * sv ^ 2, sv ^ 3 - sv ^ 2
				local x = h00 * p0x + (h10 + h11) * tx * mag + h01 * p1x
				local z = h00 * p0z + (h10 + h11) * tz * mag + h01 * p1z
				-- (rising in the middle, level at both ends where it turns hardest: a board under a turn that rises
				-- would poke up at its inside corner)
				local m = math.clamp((sv - 0.3) / 0.4, 0, 1)
				local hh = a.h + C.crossRise * m * m * (3 - 2 * m)
				local rr = math.sqrt(x * x + z * z)
				local lim = laneMax(hh)
				if rr > lim then
					x, z, rr = x * lim / rr, z * lim / rr, lim
				end
				for _, nd in nodes do
					if nd.u < a.u - 6 then
						local qx, qz = nd.r * math.sin(math.rad(nd.b)), nd.r * math.cos(math.rad(nd.b))
						-- (a root is a log, deeper under its line than a ledge)
						local rise = C.passRise + 2 * C.rootRadius - 0.3
						if (x - qx) ^ 2 + (z - qz) ^ 2 < C.passGap ^ 2 and hh - nd.h < rise then
							clear = false
						end
					end
				end
				table.insert(across, { x, z, hh, rr })
			end
			if clear or h > crossings[nextX] + 4 then
				nextX += 1
				footed = false
			end
			if clear then
				local px, pz = p0x, p0z
				for i, q in across do
					u += math.sqrt((q[1] - px) ^ 2 + (q[2] - pz) ^ 2)
					px, pz = q[1], q[2]
					theta = if q[4] > 1e-6 then math.deg(math.atan2(q[1], q[2])) else theta
					r, h = q[4], q[3]
					add(if i < n then "cross" else "lane", 0)
				end
				theta = a.b + 180
				dir = -dir
				lastCross = u
				-- and a level foot where it meets the far wall
				flatLeft, flatHalf, chamberDue = C.crossFoot, 0, false
				continue
			end
		end
		local step = C.nodeArc
		local rNext = laneAt(h, u + step)
		-- the rise the next few studs need to stay a body and a ledge over any earlier turn they pass over
		local need = 0
		for k = 1, 5 do
			local th = math.rad(theta + math.deg(k * step / rNext) * dir)
			local px, pz = rNext * math.sin(th), rNext * math.cos(th)
			for _, nd in nodes do
				if nd.u < u - 6 then
					local qx, qz = nd.r * math.sin(math.rad(nd.b)), nd.r * math.cos(math.rad(nd.b))
					if (px - qx) ^ 2 + (pz - qz) ^ 2 < C.passGap ^ 2 then
						need = math.max(need, (nd.h + C.passRise - h) / (k * step))
					end
				end
			end
		end
		theta += math.deg(step / ((r + rNext) / 2)) * dir
		u += step
		r = rNext
		local kind, s = "lane", 0
		if flatLeft > 0 and need > 0 and nextL <= #landings then
			-- (a ledge over an earlier turn ends where the climb must rise again)
			flatLeft = 0
			if chamberDue then
				chamberDue = false
				nodes[#nodes].kind = "flat"
				table.insert(landingAt, #nodes)
			end
		end
		if flatLeft > 0 then
			flatLeft -= step
			kind = "flat"
			if chamberDue and flatLeft <= flatHalf then
				chamberDue = false
				table.insert(landingAt, #nodes + 1)
			end
		else
			s = math.clamp(mean * (1 + C.slopeSwing * wS(u)), C.minSlope, C.maxSlope)
			s = math.clamp(math.max(s, need), 0, C.maxSlope)
			-- half a turn either side of a root it climbs at its steepest: the run over the root's middle (and the
			-- root over the run under it) a body and a ledge apart
			local nextX0 = crossings[nextX]
			if u - lastCross < math.pi * r or (nextX0 and nextX0 - h < C.maxSlope * math.pi * r) then
				s = C.maxSlope
			end
			local was = h
			h += s * step
			local target, ledge = landings[nextL], ledges[nextE]
			if target and h >= target then
				h = math.max(was, target)
				local arc = between(rand, C.landingArc)
				flatLeft, flatHalf, chamberDue = arc, arc / 2, true
				nextL += 1
			elseif ledge and h >= ledge then
				h = math.max(was, ledge)
				flatLeft, flatHalf, chamberDue = between(rand, C.ledgeArc), 0, false
				nextE += 1
			end
			s = (h - was) / step
		end
		add(kind, s)
		if nextL > #landings and flatLeft <= 0 then
			break
		end
	end
	local ramp = {}
	for i, nd in nodes do
		ramp[i] = tr.toWorld(nd.b, nd.r, nd.h)
	end
	local floorId, rampId = b.base + 1, b.base + 2
	table.insert(pts, ramp[1])
	-- the holes: at the first plain stretch of lane at or over each height, C.holeClear along from any ledge or root
	local function plain(i: number): boolean
		local nd = nodes[i]
		if nd.kind ~= "lane" or i < 3 or i > #nodes - 3 then
			return false
		end
		for j = 1, #nodes do
			if nodes[j].kind ~= "lane" and math.abs(nodes[j].u - nd.u) < C.holeClear then
				return false
			end
		end
		return true
	end
	local holeAt: { number } = {}
	for _, hh in holes do
		for i, nd in nodes do
			if nd.h >= hh and plain(i) then
				table.insert(holeAt, i)
				break
			end
		end
	end
	local mouths: { any } = {}
	local perches: { any } = {}
	local gaps = { { floorH, bearing } }
	for k, i in holeAt do
		local nd = nodes[i]
		local m, rec = holeOnto(b, ramp[i], nd.h, nd.b, outOf(nd.b), nil, nil, b.base + 2 + k, `knothole {k}`)
		m.t = r4(tOfIndex(ramp, i))
		table.insert(mouths, m)
		table.insert(perches, rec)
		table.insert(gaps, { nd.h, nd.b })
		holeKnot(b, nd.b, nd.h + 0.85)
	end
	local last = nodes[#nodes]
	local endBearing = last.b
	local _, _, _, trunkT = tr.axisAt(topH)
	local topOut = outOf(endBearing)
	local topMouth, topRec =
		holeOnto(b, ramp[#ramp], topH, endBearing, topOut, nil, nil, b.base + 3 + #holeAt, "top knothole")
	topMouth.t = 1
	-- (W runs on up the outside trunk; Space hops onto the top's branch; E takes the trunk)
	table.insert(topMouth.links, 1, { route = tr.route.id, t = r4(trunkT), dir = 1 })
	table.insert(mouths, topMouth)
	table.insert(perches, topRec)
	table.insert(gaps, { topH, endBearing })
	local rcTop = tr.bark(topH + C.room) - C.wall
	local floorCav = cavityOf(tr, rc0, floorH, floorH + C.room)
	local rampCav = cavityOf(tr, rcTop, floorH, topH + C.room)
	table.insert(hl.cavities, floorCav)
	table.insert(hl.cavities, rampCav)
	table.insert(
		b.routes,
		record(floorId, `hollow {hl.id} ground hole and floor`, hl.id, pts, {
			id = hl.space,
			mouths = { { t = 0, opens = "ground", name = "ground hole" } },
			atEnd = { route = rampId, t = 0, dir = 1 },
			cavity = cavityRecord(floorCav),
		})
	)
	table.insert(
		b.routes,
		record(rampId, `hollow {hl.id} winding climb`, hl.id, ramp, {
			id = hl.space,
			climb = true,
			up = { 0, 1, 0 },
			atStart = { route = floorId, t = 1, dir = -1 },
			cavity = cavityRecord(rampCav),
			mouths = mouths,
		})
	)
	for _, rec in perches do
		table.insert(b.routes, rec)
	end
	for i, at in landingAt do
		chamberAt(hl.chambers, design.chambers[i], rampId, tOfIndex(ramp, at), ramp[at])
	end
	-- what it runs on: a ledge under each span of lane, from the body's inner side (further in on a chamber's ledge)
	-- to the wall, its top C.ledgeDrop under the line and the line in its top face (the board is laid along the line
	-- and shifted out across it, never tilted); a gnarled root (a log of C.rootRadius) under the S across. A piece that
	-- would stand in a body's box on another stretch of the climb (a ledge reaching in over the root below, a board's
	-- corner at a hard turn) is narrowed from its inner side, then shortened, then lowered, until it does not; one that
	-- still would is left out. The first spans run off the floor itself.
	local boxes = boxesOf(b)
	local function place(pc: Piece, i0: number, i1: number): boolean
		if intrudes(boxes, surfacePoints(pc), rampId, i0, i1) then
			return false
		end
		pc.tone = r4(rand() * 2 - 1)
		table.insert(hl.parts, pc)
		return true
	end
	local i = 1
	while i < #nodes do
		local a = nodes[i]
		local j = i + 1
		local c = nodes[j]
		if a.kind == "cross" or c.kind == "cross" then
			for drop = C.ledgeDrop, C.ledgeDrop + 0.3, 0.1 do
				local pa = tr.toWorld(a.b, a.r, a.h - drop)
				local pc = tr.toWorld(c.b, c.r, c.h - drop)
				local f = unit({ pc[1] - pa[1], pc[2] - pa[2], pc[3] - pa[3] })
				local side = unit(cross(f, { 0, 1, 0 }))
				local up = cross(side, f)
				local len = math.sqrt((pc[1] - pa[1]) ^ 2 + (pc[2] - pa[2]) ^ 2 + (pc[3] - pa[3]) ^ 2) + 0.2
				local R = C.rootRadius
				local piece: Piece = {
					role = "root",
					shape = "Cylinder",
					p = {
						r4((pa[1] + pc[1]) / 2 - up[1] * R),
						r4((pa[2] + pc[2]) / 2 - up[2] * R),
						r4((pa[3] + pc[3]) / 2 - up[3] * R),
					},
					xv = { r4(f[1]), r4(f[2]), r4(f[3]) },
					yv = { r4(up[1]), r4(up[2]), r4(up[3]) },
					size = { r4(len), r4(2 * R), r4(2 * R) },
				}
				if place(piece, i - 1, j + 2) then
					break
				end
			end
			i = j
			continue
		end
		if math.max(a.h, c.h) >= floorH + 0.5 then
			local wide = if a.kind == "flat" then C.ledgeWide else 0
			local inner0 = math.max(0.2, math.min(a.r, c.r) - half - 0.1 - 0.25 * rand() - wide)
			-- (into the staves a little: a shelf grows out of the wall)
			local wallR = if b.wallIn
				then b.wallIn(math.max(a.h, c.h)) + 0.05
				else tr.bark(math.max(a.h, c.h) + C.tier) - C.wall - 0.02
			local grow = between(rand, C.shelfDeep)
			local length = C.treadLength + 0.06 * (rand() - 0.5)
			local rr = (a.r + c.r) / 2
			-- (narrower from the inside, shorter, lower; at the last a plank just the body's width, off the wall)
			for _, try in
				{
					{ 0, 0, 0 },
					{ 0.2, 0, 0 },
					{ 0.4, 0, 0 },
					{ 0.4, 0.1, 0 },
					{ 0.4, 0.2, 0.1 },
					{ 0.4, 0.2, 0.2 },
					{ 9, 0.1, 0.1, 1 },
					{ 9, 0.2, 0.25, 1 },
				}
			do
				local inner = math.min(inner0 + try[1], rr - half + 0.05)
				local drop = C.ledgeDrop + try[3]
				local outer = if try[4] then rr + half - 0.05 else wallR
				local pa = tr.toWorld(a.b, a.r, a.h - drop)
				local pc = tr.toWorld(c.b, c.r, c.h - drop)
				local k = (1 - (length - try[2])) / 2
				local qa = { pa[1] + (pc[1] - pa[1]) * k, pa[2] + (pc[2] - pa[2]) * k, pa[3] + (pc[3] - pa[3]) * k }
				local qc = { pc[1] + (pa[1] - pc[1]) * k, pc[2] + (pa[2] - pc[2]) * k, pc[3] + (pa[3] - pc[3]) * k }
				-- a round shelf (owner D33: ledges "like fungus shelves or growths rather than planks"): at most
				-- C.shelfMax across, its outer edge on the wall, its top face the board's (the line in it)
				local across = math.min(outer - inner, C.shelfMax)
				local trial: { Piece } = {}
				slab(trial, "tread", qa, qc, across, 0.3, outer - across / 2 - rr, tr)
				local sl = trial[1]
				local up = sl.yv
				local deep = 0.3 * grow
				local round: Piece = {
					role = "tread",
					shape = "Cylinder",
					p = {
						r4(sl.p[1] - up[1] * (deep - 0.3) / 2),
						r4(sl.p[2] - up[2] * (deep - 0.3) / 2),
						r4(sl.p[3] - up[3] * (deep - 0.3) / 2),
					},
					xv = up,
					yv = sl.xv,
					size = { r4(deep), r4(across), r4(across) },
				}
				if place(round, -1, -1) then
					break
				end
			end
		end
		i = j
	end
	-- the knots the lane winds round: where it swings furthest in, a knot bulges from the wall beside it (clear of the
	-- holes, the roots and the ground hole's run)
	for n = 2, #nodes - 1 do
		local nd = nodes[n]
		if nd.kind ~= "lane" or nd.r > nodes[n - 1].r or nd.r > nodes[n + 1].r then
			continue
		end
		local near = false
		for _, hi in holeAt do
			near = near or math.abs(nodes[hi].u - nd.u) < C.holeClear
		end
		for _, other in nodes do
			near = near or (other.kind == "cross" and math.abs(other.u - nd.u) < C.holeClear)
		end
		local room = laneMax(nd.h) + C.laneClear - nd.r - C.burlGap
		if not near and room >= C.burlRoom and nd.h > floorH + 1 then
			burl(b, nd.b, nd.r + half + 2 * C.burlGap, nd.h + 0.95, room + 0.8)
		end
	end
	-- and more on the wall between the turns, wherever one keeps clear of every run
	wallKnots(b, 10, floorH + 2, topH, function(): number
		return 360 * rand()
	end)
	staves(b, floorH - 0.05, topH + C.room, gaps)
	caps(b, floorH, rc0, topH + C.room, rcTop)
	holeKnot(b, bearing, floorH + 0.9)
	holeKnot(b, endBearing, topH + 0.85)
end

-- the fallen hollow log: a straight run through on the ground, open at both ends
local function buildLog(doc: any, heightAt: (x: number, z: number) -> number, base: number): (Hollow, { any })
	local log = doc.log
	local inside = log.inside or {}
	local cx, cz = log.x * C.spu, log.z * C.spu
	local half = log.lengthU * C.spu / 2
	local dx, dz = math.sin(log.yaw), math.cos(log.yaw)
	local ax, az, bx, bz = cx - dx * half, cz - dz * half, cx + dx * half, cz + dz * half
	local inner = inside.radius or 1.5
	local floorDrop = 0.55
	local ya = heightAt(ax, az) + 0.1
	local yb = heightAt(bx, bz) + 0.1
	local n = math.max(2, math.ceil(2 * half / 4))
	local pts = {}
	for i = 0, n do
		local f = i / n
		table.insert(pts, { ax + (bx - ax) * f, ya + (yb - ya) * f, az + (bz - az) * f })
	end
	local space = "hollow." .. log.id
	local hl: Hollow = {
		id = log.id,
		tier = "log",
		variant = "log",
		tree = "fallen hollow log",
		trunk = nil,
		space = space,
		claimable = false,
		x = r4(cx),
		y = r4(heightAt(cx, cz)),
		z = r4(cz),
		routes = { base + 1 },
		mouths = {},
		chambers = {},
		cavities = {},
		meter = { capacity = 0, ownAt = 1 },
		parts = {},
	}
	local rec = record(base + 1, "hollow log run-through", log.id, pts, {
		id = space,
		mouths = { { t = 0, opens = "ground", name = "log end" }, { t = 1, opens = "ground", name = "log end" } },
	})
	-- the shell: boards round the log's axis (floorDrop over the run), a floor board along the run
	local a, z1 = pts[1], pts[#pts]
	local axisA = { a[1], a[2] + floorDrop, a[3] }
	local axisB = { z1[1], z1[2] + floorDrop, z1[3] }
	local f = unit({ axisB[1] - axisA[1], axisB[2] - axisA[2], axisB[3] - axisA[3] })
	local side = unit(cross(f, { 0, 1, 0 }))
	local up = cross(side, f)
	local len = math.sqrt((axisB[1] - axisA[1]) ^ 2 + (axisB[2] - axisA[2]) ^ 2 + (axisB[3] - axisA[3]) ^ 2)
	local boards = 10
	local width = 2 * (inner + C.logWall) * math.tan(math.pi / boards) + 0.05
	local mid = { (axisA[1] + axisB[1]) / 2, (axisA[2] + axisB[2]) / 2, (axisA[3] + axisB[3]) / 2 }
	for k = 0, boards - 1 do
		local ang = (k + 0.5) * 2 * math.pi / boards
		local cs, sn = math.cos(ang), math.sin(ang)
		local nrm = { side[1] * cs + up[1] * sn, side[2] * cs + up[2] * sn, side[3] * cs + up[3] * sn }
		local tan = { -side[1] * sn + up[1] * cs, -side[2] * sn + up[2] * cs, -side[3] * sn + up[3] * cs }
		local rr = inner + C.logWall / 2
		-- the board's frame: x round the axis, y out from it, z along the log
		table.insert(hl.parts, {
			role = "log",
			shape = "Block",
			p = { r4(mid[1] + nrm[1] * rr), r4(mid[2] + nrm[2] * rr), r4(mid[3] + nrm[3] * rr) },
			xv = { r4(tan[1]), r4(tan[2]), r4(tan[3]) },
			yv = { r4(nrm[1]), r4(nrm[2]), r4(nrm[3]) },
			size = { r4(width), C.logWall, r4(len) },
		})
	end
	slab(hl.parts, "floor", pts[1], pts[#pts], 1.9, 0.3)
	-- a threshold just inside each end (Server/World/HollowShell: invisible, collides, queried by the walls test)
	for i, q in { axisA, axisB } do
		local d = if i == 1 then C.logThreshold else -C.logThreshold -- (inward from each end)
		table.insert(hl.parts, {
			role = "threshold",
			shape = "Cylinder",
			p = { r4(q[1] + f[1] * d), r4(q[2] + f[2] * d), r4(q[3] + f[3] * d) },
			xv = { r4(f[1]), r4(f[2]), r4(f[3]) }, -- a Cylinder's axis is its X: along the log
			yv = { r4(side[1]), r4(side[2]), r4(side[3]) },
			size = { 0.2, r4(2 * inner), r4(2 * inner) },
		})
	end
	for i, p in { pts[1], pts[#pts] } do
		table.insert(hl.mouths, {
			route = base + 1,
			t = i - 1,
			name = "log end",
			opens = "ground",
			x = r4(p[1]),
			y = r4(p[2]),
			z = r4(p[3]),
			out = if i == 1 then { r4(-dx), 0, r4(-dz) } else { r4(dx), 0, r4(dz) },
		})
	end
	table.insert(hl.cavities, {
		x = r4(cx),
		z = r4(cz),
		radius = inner,
		bottom = r4(math.min(ya, yb) - 0.2),
		top = r4(math.max(ya, yb) + 2 * inner),
		a = { r4(axisA[1]), r4(axisA[2]), r4(axisA[3]) },
		b = { r4(axisB[1]), r4(axisB[2]), r4(axisB[3]) },
	})
	return hl, { rec }
end

local function mouthPoint(r: any, t: number): { number }
	if t <= 0 then
		return r.points[1]
	elseif t >= 1 then
		return r.points[#r.points]
	end
	local best, bi = math.huge, 1
	for i = 1, #r.points do
		local d = math.abs(tOfIndex(r.points, i) - t)
		if d < best then
			best, bi = d, i
		end
	end
	return r.points[bi]
end

export type BuildOptions = { idBase: number? }

-- build(doc, harvest, heightAt): data/hollows.json (decoded) and the harvested routes -> the compiled table
function HollowLayout.build(
	doc: any,
	harvest: Harvest,
	heightAt: (x: number, z: number) -> number,
	opts: BuildOptions?
): Compiled
	local idBase = (opts and opts.idBase) or 9400
	local compiled: Compiled = { routes = {}, hollows = {} }
	local defaults = doc.meterDefaults
	for n, design in doc.hollows do
		local inside = design.inside
		local tr = HollowLayout.trunk(harvest, inside.trunk)
		local hl: Hollow = {
			id = design.id,
			tier = design.tier,
			variant = design.variant,
			tree = design.tree,
			trunk = inside.trunk,
			space = "hollow." .. design.id,
			claimable = design.claimable,
			x = r4(tr.foot.x),
			y = r4(tr.foot.y),
			z = r4(tr.foot.z),
			routes = {},
			mouths = {},
			chambers = {},
			cavities = {},
			meter = {
				capacity = (design.meter and design.meter.capacity) or defaults.capacity,
				ownAt = (design.meter and design.meter.ownAt) or defaults.ownAt,
			},
			parts = {},
		}
		local b: Build = {
			rand = HollowLayout.rngOf("hollow " .. design.id),
			harvest = harvest,
			heightAt = heightAt,
			trunk = tr,
			hollow = hl,
			base = idBase + 10 * n,
			routes = {},
		}
		local make = VARIANTS[design.variant]
		assert(make, `hollow {design.id}: unknown variant {design.variant}`)
		make(b, design, inside)
		-- where the camera may be inside it (keepCamera): slices C.viewSlice tall up the cavities, each round the trunk's
		-- own axis at its middle and C.cameraIn inside the staves all the way up it (the cavities are upright cylinders
		-- round one point; a trunk that bends or leans leaves the staves nearer on one side)
		local wallIn = b.wallIn
		if wallIn then
			local lo, hi = math.huge, -math.huge
			for _, c in hl.cavities do
				lo, hi = math.min(lo, c.bottom), math.max(hi, c.top)
			end
			local view = {}
			local y = lo
			while y < hi - 1e-6 do
				local y1 = math.min(hi, y + C.viewSlice)
				local mx, _, mz = tr.axisAt((y + y1) / 2 - tr.foot.y)
				local r = math.huge
				for k = 0, 4 do
					local hh = y + (y1 - y) * k / 4 - tr.foot.y
					local ax, _, az = tr.axisAt(hh)
					r = math.min(r, wallIn(hh) - math.sqrt((ax - mx) ^ 2 + (az - mz) ^ 2))
				end
				table.insert(view, { r4(mx), r4(mz), r4(math.max(0.05, r - C.cameraIn)), r4(y), r4(y1) })
				y = y1
			end
			hl.view = view
		end
		local perchIds: { [number]: boolean } = {}
		for _, r in b.routes do
			table.insert(compiled.routes, r)
			if r.enclosure == nil then
				-- a perch outside: an open branch, not one of the hollow's runs
				hl.perches = hl.perches or {}
				table.insert(hl.perches :: { number }, r.id)
				perchIds[r.id] = true
			end
		end
		-- the perch a mouth's links name (the branch its hop lands on), if any
		local function perchOf(m: any): number?
			for _, l in m.links or {} do
				if perchIds[l.route] then
					return l.route
				end
			end
			return nil
		end
		for _, r in b.routes do
			if r.enclosure == nil then
				continue
			end
			table.insert(hl.routes, r.id)
			for _, m in r.enclosure.mouths or {} do
				local p = mouthPoint(r, m.t)
				local out = m.out
				if not out then
					local q = r.points[#r.points - 1]
					out = { r4(p[1] - q[1]), 0, r4(p[3] - q[3]) }
				end
				table.insert(hl.mouths, {
					route = r.id,
					t = m.t,
					name = m.name or "",
					opens = m.opens,
					x = p[1],
					y = p[2],
					z = p[3],
					out = out,
					link = if m.links then m.links[1].route else nil,
					depth = m.depth,
					hop = m.hop,
					perch = perchOf(m),
				})
			end
		end
		table.insert(compiled.hollows, hl)
	end
	if doc.log then
		local hl, recs = buildLog(doc, heightAt, idBase + 10 * (#doc.hollows + 1))
		for _, r in recs do
			table.insert(compiled.routes, r)
		end
		table.insert(compiled.hollows, hl)
	end
	return compiled
end

function HollowLayout.new(compiled: Compiled): Layout
	local byId: { [string]: Hollow } = {}
	local byRoute: { [number]: Hollow } = {}
	local bySpace: { [string]: Hollow } = {}
	for _, h in compiled.hollows do
		byId[h.id] = h
		bySpace[h.space] = h
		for _, rid in h.routes do
			byRoute[rid] = h
		end
	end
	local layout = {} :: Layout
	layout.hollows = compiled.hollows
	layout.routes = compiled.routes
	function layout.hollow(id: string): Hollow?
		return byId[id]
	end
	function layout.hollowOfRoute(routeId: number): Hollow?
		return byRoute[routeId]
	end
	function layout.hollowOfSpace(space: string?): Hollow?
		return if space then bySpace[space] else nil
	end
	function layout.spaceOf(routeId: number): string?
		local h = byRoute[routeId]
		return if h then h.space else nil
	end
	function layout.within(h: Hollow, x: number, y: number, z: number): boolean
		for _, c in h.cavities do
			local a, bb = c.a, c.b
			if a and bb then
				-- the log: within its radius of the segment a -> b, more than C.logOpen inside its open ends (a
				-- squirrel in an end's opening, or out past it, is in the open)
				local abx, aby, abz = bb[1] - a[1], bb[2] - a[2], bb[3] - a[3]
				local l2 = abx * abx + aby * aby + abz * abz
				local tt = ((x - a[1]) * abx + (y - a[2]) * aby + (z - a[3]) * abz) / l2
				local px, py, pz = a[1] + abx * tt - x, a[2] + aby * tt - y, a[3] + abz * tt - z
				local edge = math.min(0.5, C.logOpen / math.sqrt(l2))
				if tt > edge and tt < 1 - edge and px * px + py * py + pz * pz <= (c.radius + 0.3) ^ 2 then
					return true
				end
			elseif y >= c.bottom - 0.5 and y <= c.top and (x - c.x) ^ 2 + (z - c.z) ^ 2 <= (c.radius + 0.6) ^ 2 then
				return true
			end
		end
		return false
	end
	function layout.contains(x: number, y: number, z: number): string?
		for _, h in compiled.hollows do
			if layout.within(h, x, y, z) then
				return h.space
			end
		end
		return nil
	end
	-- (x, y, z) held inside cavity c (C.cameraIn inside its wall, floor and roof)
	local function keepIn(c: Cavity, x: number, y: number, z: number): (number, number, number)
		local a, bb = c.a, c.b
		local r = math.max(0.05, c.radius - C.cameraIn)
		if a and bb then
			-- the log: across its axis within r, along it between its open ends (C.cameraIn inside each)
			local abx, aby, abz = bb[1] - a[1], bb[2] - a[2], bb[3] - a[3]
			local l2 = abx * abx + aby * aby + abz * abz
			local tt = ((x - a[1]) * abx + (y - a[2]) * aby + (z - a[3]) * abz) / l2
			local dx, dy, dz = x - (a[1] + abx * tt), y - (a[2] + aby * tt), z - (a[3] + abz * tt)
			local d = math.sqrt(dx * dx + dy * dy + dz * dz)
			if d > r then
				dx, dy, dz = dx / d * r, dy / d * r, dz / d * r
			end
			local edge = math.min(0.5, C.cameraIn / math.sqrt(l2))
			tt = math.clamp(tt, edge, 1 - edge)
			return a[1] + abx * tt + dx, a[2] + aby * tt + dy, a[3] + abz * tt + dz
		end
		local dx, dz = x - c.x, z - c.z
		local d = math.sqrt(dx * dx + dz * dz)
		if d > r then
			dx, dz = dx / d * r, dz / d * r
		end
		local y0, y1 = c.bottom + C.cameraIn, c.top - C.cameraIn
		return c.x + dx, if y1 > y0 then math.clamp(y, y0, y1) else (y0 + y1) / 2, c.z + dz
	end
	-- (x, y, z) held inside a hollow's `view` (the slice at its height, round the trunk's own axis there)
	local function inView(h: Hollow, x: number, y: number, z: number): (number, number, number)
		local view = h.view
		if view == nil or #view == 0 then
			return x, y, z
		end
		local sl = view[#view]
		for _, v in view do
			if y < v[5] then
				sl = v
				break
			end
		end
		local dx, dz = x - sl[1], z - sl[2]
		local d = math.sqrt(dx * dx + dz * dz)
		if d > sl[3] then
			x, z = sl[1] + dx / d * sl[3], sl[2] + dz / d * sl[3]
		end
		return x, y, z
	end
	function layout.keepCamera(
		x: number,
		y: number,
		z: number,
		hx: number,
		hy: number,
		hz: number
	): (number, number, number)
		for _, h in compiled.hollows do
			if not layout.within(h, hx, hy, hz) then
				continue
			end
			-- of the cavities round the head (a floor and its shaft overlap), the one that moves the point least
			local bx, by, bz, bd = x, y, z, math.huge
			local held: Cavity? = nil
			for _, c in h.cavities do
				if layout.within({ cavities = { c } } :: any, hx, hy, hz) then
					local kx, ky, kz = keepIn(c, x, y, z)
					local d = (kx - x) ^ 2 + (ky - y) ^ 2 + (kz - z) ^ 2
					if d < bd then
						bx, by, bz, bd, held = kx, ky, kz, d, c
					end
				end
			end
			-- a shaft too narrow to be behind the body in (held against the head): across the shaft from it and a stud
			-- lower, looking over at it
			local c = held
			if c and c.a == nil and (bx - hx) ^ 2 + (bz - hz) ^ 2 < 1 then
				local ux, uz = hx - c.x, hz - c.z
				local ul = math.sqrt(ux * ux + uz * uz)
				if ul > 0.2 then
					bx, by, bz = keepIn(c, c.x - ux / ul * c.radius, hy - 1, c.z - uz / ul * c.radius)
				end
			end
			return inView(h, bx, by, bz)
		end
		return x, y, z
	end
	function layout.peekAt(x: number, y: number, z: number): Mouth?
		local best: Mouth?, bd = nil, C.peekReach
		for _, h in compiled.hollows do
			if (h.x - x) ^ 2 + (h.z - z) ^ 2 > 400 then
				continue
			end
			for _, m in h.mouths do
				if m.opens ~= "ground" then
					local d = math.sqrt((m.x - x) ^ 2 + (m.y - y) ^ 2 + (m.z - z) ^ 2)
					if d <= bd then
						best, bd = m, d
					end
				end
			end
		end
		return best
	end
	function layout.nearest(x: number, z: number, maxDist: number?): (Hollow?, number)
		local best, bd = nil, maxDist or math.huge
		for _, h in compiled.hollows do
			local d = math.sqrt((h.x - x) ^ 2 + (h.z - z) ^ 2)
			if d < bd then
				best, bd = h, d
			end
		end
		return best, bd
	end
	return layout
end

local cached: Layout? = nil
function HollowLayout.default(): Layout?
	if cached then
		return cached
	end
	local Data = (require :: any)("../Data")
	local d = Data.default()
	if not d:has("HollowTrees") then
		return nil
	end
	cached = HollowLayout.new(d:module("HollowTrees") :: any)
	return cached
end

return HollowLayout
