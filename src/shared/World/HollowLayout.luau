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
--   shaft     the hole and the floor; a straight climb up the cavity wall on the side of bough `wall` (W climbs);
--             part-way a knothole onto bough `knot` (E, or A/D picks it); at the top the knothole onto bough `wall`
--             (running out goes on along it); a hideout shelf off the shaft at `hideout` studs (A/D picks it)
--   escape    as the shaft without the hideout: three apertures, three exits (the ground, bough `knot`, bough `wall`)
--   spiral    the hole and the floor; a ramp spiralling up round a heartwood post (`radius` from the axis, `pitch`
--             studs a turn; W climbs, S goes down), flat landings (chambers) at `landings` studs, out at the top
--             knothole onto bough `top`
--   log       the fallen hollow log: a straight run through on the ground, a mouth at each end (not claimable)
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
--   contains(x, y, z) -> string?     the space whose cavity holds the point (the server's refuge test)
--   within(hollow, x, y, z) -> boolean   that hollow's cavity holds the point (its Combat/Cover shape)
--   keepCamera(x, y, z, hx, hy, hz) -> (x, y, z)   a camera point held inside the cavity round a head inside a
--                                    hollow (C.cameraIn inside its wall, floor and roof); unchanged for a head outside
--   nearest(x, z, maxDist?) -> (Hollow?, number)   level distance to the trunk's foot (the log's middle)
-- A Hollow (compiled): id, tier, variant, tree, trunk (route id; nil for the log), space, claimable, x, y, z (the
--   trunk's foot; the log's middle on the ground), routes { id }, mouths { Mouth }, chambers { Chamber } (where nuts
--   are stored: a route and t), cavities { Cavity } (each a vertical cylinder: x, z, radius, bottom, top; the log's is
--   along its axis: a, b, radius), meter { capacity, ownAt }, parts { Piece } (the shell the server builds: Piece =
--   role, shape "Block" | "Cylinder", p {x, y, z} centre, xv / yv the frame's right and up (unit), size {x, y, z}).

local Curve = require("../Routes/Curve")

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
	post = 0.55, -- studs: the spiral's heartwood post's clearance inside the ramp's inner edge
	shelf = 1.5, -- studs: a hideout shelf's length across the shaft
	logWall = 0.3,
	cameraIn = 0.3, -- studs: the tunnel camera kept this far inside a cavity's wall (the liner boards stand outside it)
	-- the bark mesh has 14 flats (Builders/Trees, the Blender trees): between its corners it is this much of the
	-- nominal radius; every corner of the shell stays C.barkClear inside that at its height, lean included
	barkFace = math.cos(math.pi / 14),
	barkClear = 0.08,
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
	mouths: { Mouth },
	chambers: { Chamber },
	cavities: { Cavity },
	meter: { capacity: number, ownAt: number },
	parts: { Piece },
}
export type Compiled = { routes: { any }, hollows: { Hollow } }
export type Layout = {
	hollows: { Hollow },
	routes: { any },
	hollow: (id: string) -> Hollow?,
	spaceOf: (routeId: number) -> string?,
	hollowOfRoute: (routeId: number) -> Hollow?,
	contains: (x: number, y: number, z: number) -> string?,
	within: (h: Hollow, x: number, y: number, z: number) -> boolean,
	keepCamera: (x: number, y: number, z: number, hx: number, hy: number, hz: number) -> (number, number, number),
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
local function ring(parts: { Piece }, role: string, a0: { number }, a1: { number }, radius: number, gaps: { number })
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

-- A box whose top face runs along a -> b (a tread or a shelf), `width` across, `thick` deep.
local function slab(parts: { Piece }, role: string, a: { number }, b: { number }, width: number, thick: number)
	local d = { b[1] - a[1], b[2] - a[2], b[3] - a[3] }
	local len = math.sqrt(d[1] * d[1] + d[2] * d[2] + d[3] * d[3])
	local f = unit(d)
	local side = unit(cross(f, { 0, 1, 0 }))
	local up = cross(side, f)
	local mid = {
		(a[1] + b[1]) / 2 - up[1] * thick / 2,
		(a[2] + b[2]) / 2 - up[2] * thick / 2,
		(a[3] + b[3]) / 2 - up[3] * thick / 2,
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
	harvest: Harvest,
	heightAt: (x: number, z: number) -> number,
	trunk: Trunk,
	hollow: Hollow,
	base: number,
	routes: { any },
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

-- the rings of liner boards from h0 to h1 (tierRings); `gaps` = { {h, bearing} } passages through a ring at
-- those heights
local function tiers(b: Build, h0: number, h1: number, gaps: { { number } })
	local tr = b.trunk
	for _, r in tierRings(tr, h0, h1) do
		local open = {}
		for _, g in gaps do
			if g[1] >= r.h - 1.0 and g[1] <= r.top + 1.0 then
				table.insert(open, g[2])
			end
		end
		ring(b.hollow.parts, "liner", r.a0, r.a1, r.rc, open)
	end
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

local VARIANTS: { [string]: (b: Build, design: any, inside: any) -> () } = {}

-- a single chamber: the hole, across the floor to a dead end at the back
VARIANTS.knothole = function(b: Build, design: any, inside: any)
	local tr, hl = b.trunk, b.hollow
	local bearing = inside.hole
	local pts, floorH, rc0 = holeRun(b, bearing)
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
	tiers(b, floorH - 0.05, floorH + C.room, { { floorH, bearing } })
	caps(b, floorH, rc0, floorH + C.room, rc0)
	holeKnot(b, bearing, floorH + 0.9)
end

-- a straight climb up the cavity wall (shaft; escape without the hideout)
local function shaftLike(b: Build, design: any, inside: any, hideout: boolean)
	local tr, hl = b.trunk, b.hollow
	local bearing = inside.hole
	local wallT, _, wallB, wallH = HollowLayout.boughExit(b.harvest, tr, inside.wall)
	local knotT, _, knotB, knotH = HollowLayout.boughExit(b.harvest, tr, inside.knot)
	local top = wallH - 1
	local pts, floorH, rc0 = holeRun(b, bearing)
	-- the climb's line: C.shaftIn inside the wall above it, and inside the rings round it (narrowed to the bark)
	local rings = tierRings(tr, floorH - 0.05, top + C.room)
	local function rho(h: number): number
		return math.min(tr.bark(math.min(h + C.tier, top + C.room)) - C.wall, ringNear(rings, h)) - C.shaftIn
	end
	local h0 = floorH + 0.5
	table.insert(pts, tr.toWorld(wallB, rho(floorH) - 0.7, floorH))
	local floorId, shaftId, hideId = b.base + 1, b.base + 2, b.base + 3
	local shaft = {}
	local h = h0
	while h < top - 0.01 do
		table.insert(shaft, tr.toWorld(wallB, rho(h), h))
		h = math.min(h + C.tier / 2, top) -- (half a tier: the line keeps to a bending axis)
		if top - h < 1 then
			h = top
		end
	end
	table.insert(shaft, tr.toWorld(wallB, rho(top), top))
	-- the top knothole leans out along bough `wall` (Motion.mouthOut): its bark is measured that way
	local wt = b.harvest:tangentAt(assert(b.harvest:get(inside.wall)), wallT)
	local wallOut = { wt.x, 0, wt.z }
	local knotTs = (knotH - h0) / (top - h0)
	local knotP = tr.toWorld(wallB, rho(knotH), knotH)
	local forks = {}
	local hideH = inside.hideout or 0
	local hideT = (hideH - h0) / (top - h0)
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
	table.insert(
		b.routes,
		record(shaftId, `hollow {hl.id} shaft`, hl.id, shaft, {
			id = hl.space,
			climb = true,
			up = outOf(wallB + 180),
			atStart = { route = floorId, t = 1, dir = -1 },
			forks = if #forks > 0 then forks else nil,
			cavity = cavityRecord(shaftCav),
			mouths = {
				{
					t = r4(knotTs),
					opens = "link",
					out = outOf(knotB),
					depth = depthOut(tr, knotP, outOf(knotB), knotH),
					links = { { route = inside.knot, t = r4(knotT), dir = 1 } },
					name = "knothole",
				},
				{
					t = 1,
					opens = "link",
					depth = depthOut(tr, shaft[#shaft], wallOut, top),
					links = { { route = inside.wall, t = r4(wallT), dir = 1 } },
					name = "top knothole",
				} :: any,
			},
		})
	)
	local chambers = design.chambers
	chamberAt(hl.chambers, chambers[1], floorId, 1, pts[#pts])
	if hideout then
		-- across the cavity from the wall it climbs (the climbing body's back stays clear of the shelf)
		local hideB = inside.hideoutBearing or (wallB + 180)
		local rcHide = tr.bark(hideH + C.tier) - C.wall
		local hide = {
			tr.toWorld(wallB, rho(hideH), hideH),
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
		chamberAt(hl.chambers, chambers[2], shaftId, (midH - h0) / (top - h0), tr.toWorld(wallB, rho(midH), midH))
		chamberAt(hl.chambers, chambers[3], hideId, 1, hide[#hide])
	end
	tiers(b, floorH - 0.05, top + C.room, { { floorH, bearing }, { knotH, knotB }, { top, wallB } })
	caps(b, floorH, rc0, top + C.room, rcTop)
	holeKnot(b, bearing, floorH + 0.9)
	holeKnot(b, knotB, knotH + 0.85)
	holeKnot(b, wallB, top + 0.85)
end

VARIANTS.shaft = function(b: Build, design: any, inside: any)
	shaftLike(b, design, inside, true)
end
VARIANTS.escape = function(b: Build, design: any, inside: any)
	shaftLike(b, design, inside, false)
end

-- a ramp spiralling up round a heartwood post, flat landings on the way, out at the top onto the outside trunk
VARIANTS.spiral = function(b: Build, design: any, inside: any)
	local tr, hl = b.trunk, b.hollow
	local bearing = inside.hole
	local radius, pitch, topH = inside.radius, inside.pitch, inside.top
	local pts, floorH, rc0 = holeRun(b, bearing)
	local theta = bearing + 40
	local start = tr.toWorld(theta, radius, floorH)
	table.insert(pts, start)
	local floorId, rampId = b.base + 1, b.base + 2
	local ramp = { start }
	local landingAt: { number } = {}
	local landings = table.clone(inside.landings :: { number })
	table.insert(landings, topH)
	local h, flat, nextL = floorH, 0, 1
	local step = 15
	while true do
		theta += step
		if flat > 0 then
			flat -= step
		else
			h += pitch * step / 360
			local target = landings[nextL]
			if target and h >= target then
				h = target
				flat = 90
				nextL += 1
			end
		end
		table.insert(ramp, tr.toWorld(theta, radius, h))
		if flat == 45 then
			table.insert(landingAt, #ramp)
		end
		if nextL > #landings and flat <= 0 then
			break
		end
	end
	local endBearing = theta
	local _, _, _, trunkT = tr.axisAt(topH)
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
		record(rampId, `hollow {hl.id} spiral ramp`, hl.id, ramp, {
			id = hl.space,
			climb = true,
			up = { 0, 1, 0 },
			atStart = { route = floorId, t = 1, dir = -1 },
			cavity = cavityRecord(rampCav),
			mouths = {
				{
					t = 1,
					opens = "link",
					out = outOf(endBearing),
					depth = depthOut(tr, ramp[#ramp], outOf(endBearing), topH),
					links = { { route = tr.route.id, t = r4(trunkT), dir = 1 } },
					name = "top knothole",
				},
			},
		})
	)
	for i, at in landingAt do
		chamberAt(hl.chambers, design.chambers[i], rampId, tOfIndex(ramp, at), ramp[at])
	end
	-- the post, one piece each two tiers; the treads, one each C.treadStep degrees, from the post to the wall
	local postR = radius - 0.8 - C.post
	local ph = floorH
	while ph < topH + C.room - 0.01 do
		local top = math.min(ph + C.tier * 2, topH + C.room)
		local x, _, z = tr.axisAt((ph + top) / 2)
		table.insert(hl.parts, {
			role = "post",
			shape = "Cylinder",
			p = { r4(x), r4(tr.foot.y + (ph + top) / 2), r4(z) },
			xv = { 0, 1, 0 },
			yv = { -1, 0, 0 },
			size = { r4(top - ph), r4(2 * postR), r4(2 * postR) },
		})
		ph = top
	end
	local every = C.treadStep // step
	-- (the first two spans run off the floor itself: no tread under them)
	for i = 1 + 2 * every, #ramp - every, every do
		local a, c = ramp[i], ramp[i + every]
		local ha, hc = a[2] - tr.foot.y, c[2] - tr.foot.y
		local outer = tr.bark(math.max(ha, hc) + C.tier) - C.wall - 0.02
		local mid = (postR + outer) / 2
		local ba = tr.bearingOf(a[1], a[3], ha)
		local bc = tr.bearingOf(c[1], c[3], hc)
		-- a little under the run and a little short of its ends (a straight board under a curving run: its corners
		-- would stand proud of the line where the next one starts)
		local pa, pc = tr.toWorld(ba, mid, ha - C.treadDrop), tr.toWorld(bc, mid, hc - C.treadDrop)
		local k = (1 - C.treadLength) / 2
		local qa = { pa[1] + (pc[1] - pa[1]) * k, pa[2] + (pc[2] - pa[2]) * k, pa[3] + (pc[3] - pa[3]) * k }
		local qc = { pc[1] + (pa[1] - pc[1]) * k, pc[2] + (pa[2] - pc[2]) * k, pc[3] + (pa[3] - pc[3]) * k }
		slab(hl.parts, "tread", qa, qc, outer - postR, 0.3)
	end
	tiers(b, floorH - 0.05, topH + C.room, { { floorH, bearing }, { topH, endBearing } })
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
		for _, r in b.routes do
			table.insert(hl.routes, r.id)
			table.insert(compiled.routes, r)
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
	for _, h in compiled.hollows do
		byId[h.id] = h
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
	function layout.spaceOf(routeId: number): string?
		local h = byRoute[routeId]
		return if h then h.space else nil
	end
	function layout.within(h: Hollow, x: number, y: number, z: number): boolean
		for _, c in h.cavities do
			local a, bb = c.a, c.b
			if a and bb then
				-- the log: within its radius of the segment a -> b, between its open ends (a squirrel out past an end
				-- is in the open)
				local abx, aby, abz = bb[1] - a[1], bb[2] - a[2], bb[3] - a[3]
				local l2 = abx * abx + aby * aby + abz * abz
				local tt = ((x - a[1]) * abx + (y - a[2]) * aby + (z - a[3]) * abz) / l2
				local px, py, pz = a[1] + abx * tt - x, a[2] + aby * tt - y, a[3] + abz * tt - z
				if tt >= 0 and tt <= 1 and px * px + py * py + pz * pz <= (c.radius + 0.3) ^ 2 then
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
			-- the log: across its axis within r, along it between its ends (C.cameraIn short of each)
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
					return keepIn(c, c.x - ux / ul * c.radius, hy - 1, c.z - uz / ul * c.radius)
				end
			end
			return bx, by, bz
		end
		return x, y, z
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
