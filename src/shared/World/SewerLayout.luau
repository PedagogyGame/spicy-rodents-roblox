--!strict
-- ReplicatedStorage.Shared.World.SewerLayout
-- The storm drains under the town (BRIEF_ADDENDUM D8: "a few underground pipes that the squirrel can run through,
-- like a short cut or two through a system under the city, just basic sewers"). Three pipes, each one space and one
-- enclosed run on the landed contract (Shared/Routes/Enclosure, kind "tunnel"); nothing here is a mechanic of its
-- own. data/sewers.json is authored; tools/compile (lib/Sewers) calls SewerLayout.build on it and writes
-- generated/Sewers.luau; Shared/Data appends its route records to the Registry; everything else reads this module.
-- Pure: no engine calls. Studs, world space, y up, north = +z. No side effects on require.
--
-- THE INTERFACE (what the bake, the server and the client lanes build against)
--   SewerLayout.build(doc, opts?) -> Compiled      authored data/sewers.json -> the compiled table (the compiler only)
--   SewerLayout.new(compiled) -> Layout            a layout over a compiled table (generated/Sewers.luau)
--   SewerLayout.default() -> Layout?               over Shared/Data's "Sewers" module (nil when not compiled)
--   SewerLayout.C                                  the fixed numbers below (re-entry distances, the walk-in caveat)
-- Layout (all positions world studs):
--   pipes, mouths, chambers, anchors, carves, routes   the compiled lists (read-only)
--   pipe(id) -> Pipe?            "P1" crossroads, "P2" culvert, "P3" bowl lane
--   mouth(id) -> Mouth?          "P1.NW" ... (every street mouth, with its shaft, opening and carve column)
--   mouthsOf(pipeId) -> { Mouth }
--   nearestMouth(x, z, maxDist?) -> (Mouth?, number)   level distance to the mouth point
--   spaceOf(routeId) -> string?   the space (= the routes' enclosure id) of a sewer route, nil for any other route
--   contains(x, y, z) -> string?  the space whose volume holds the point (passages, the chamber, the shafts below the
--                                 last half stud under the street): the server's "underground" test (lane S2)
--   reentryMouth(deathX, deathZ, people?) -> Mouth?   where a dead rodent climbs back out (BUILD_PLAN R5 S-10):
--                                 a mouth at least C.reentryMin from the death with nobody within C.reentryClear,
--                                 the one nearest the town centre; else the clear one farthest from the death; else
--                                 the farthest. `people` is a list of {x, z}.
--   carveBoxes() -> { Box }       the terrain to clear at boot (FillBlock Air, 4-stud grid; lane S2 carves, the bake
--                                 writes them as a TerrainCarve folder as the alley does)
--   surfaceWalk(from, to) -> SurfaceWay?   the way over the top between two mouths (polyline and length)
--
-- WHAT THE COMPILED TABLE HOLDS (types below)
--   routes     Registry route records 9301-9304 (P1's four arms), 9311 (P2), 9321 (P3): kind "tunnel", origin
--              "sewer", flags treeTravel false and autoGrabExcluded true, speedMult = Tunables sewer.speedMult (the
--              pipe pace; the motor does not read speedMult yet: see below), and an `enclosure` record: id = the
--              space, a "ground" mouth at each street end (out = the shaft's rung side, level; reach from the data),
--              P1's arms joined at the crossing by end links (straight on) and forks (A/D: the two side arms), width
--              and height of the walkway and shaft, upAt (the back faces away from the rungs in a shaft, up along a run).
--   mouths     id, pipe, space, kind ("grate" in a verge or lawn, "cover" on a quay walk), name, the mouth point
--              (x, y = street level, z: where the squirrel stands to press E and where it stands after coming out),
--              out {x, z}, reach, route and t, opening {x0, x1, z0, z1} (the hole the frame leaves; the squirrel
--              goes down through it), shaft { cx, cz, inside, wall, top, bottom, rungs {x, z} } (a square well with
--              iron rungs on the `rungs` wall; the route runs rungGap off that wall), column (the shaft's carve box).
--   pipes      id, name, space, sign, section kind, mouth ids, route ids, passages, chamber id, surface ways.
--   passages   one per run of pipe: `points` the passage axis at walkway height (y = the walkway top the route
--              runs on; the axis is the art module's centre line), `side` +1 when the walkway is left of the axis
--              looking along `points` (-1 right), `offset` the route's distance from the axis, `section` the
--              section kind; points[1] is the end wall behind a shaft, the last point the end wall or the chamber port.
--   sections   brick (01_Brick_Sewer_Passage: walkways both sides of a water channel) and dry
--              (03_Concrete_Maintenance_Tunnel), in studs at `art.studsPerMetre`: innerHalf, outerHalf, below (the
--              floor under the walkway top), crown (outer top above it), spring, walkway band, routeOffset, water.
--   chambers   P1's four-way junction (02_Four_Way_Sewer_Junction): centre x, y (floor), z, half, the four ports
--              { route, x, z, outward } the module's arches line up with, the crossing point of the routes, the lid.
--   anchors    kind "lamp" (one per art module along each passage, on the wall away from the walkway: the bake's
--              PointLights, all disabled, each named with its space), "sign" (the drain's stencil at each shaft foot,
--              text and facing), "lightGrate" (P1's manhole lid over the chamber, P3's grate in the boulevard), and
--              "fashionStand" (in P1's chamber, beside the crossing, facing it; W4 #9 builds the stand).
--   carves     4-stud-aligned boxes, kind "passage" (top at least `carve.cover` studs under the ground and on the grid
--              below the surface voxel), "chamber" or "shaft" (whole voxel columns opened to the street; the bake
--              covers each with the mouth's frame and grate or cover; every other hole is under a road, kerb or quay
--              slab already).
-- Sound cue points are not here (lane S3 places them from mouths and passages; ids stay empty until audio exists).
--
-- WHAT THE CONTRACT DOES NOT GIVE YET (reported, not worked round)
--   * Only E: a "ground" mouth also takes a body that walks into it heading in (Enclosure rule 1). A grate cannot say
--     "E only, never walked into" (the survey's hatch mouth, N3). `out` is the shaft's rung side, so only a body
--     heading straight at the grate from that side (within 60 degrees) walks in; across it or from the other sides
--     it does not (sewers_runthrough pins both).
--   * The rungs' side is chosen so the body, its back away from the rungs, stays inside the passage's walls below the
--     street (P1's shafts are square to the streets, its arms diagonal).
--   * Pace: route.speedMult (the pipe pace, Tunables sewer.speedMult) is carried by every record and read by nothing
--     (SquirrelMotor calls Motion.railSpeed without it, N2). P1 and P2 beat their surface ways at the street pace; P3
--     beats its straight walk only at the pipe pace.
--   * A four-way: two forks onto one route in opposite directions cannot be told apart (A/D selects a route id), so
--     P1 is four arms meeting at the crossing, not two crossing routes.

local Curve = require("../Routes/Curve")

local SewerLayout = {}

SewerLayout.C = {
	reentryMin = 100, -- studs: a re-entering rodent comes out at least this far from where it died (survey S2)
	reentryClear = 15, -- studs: and nobody stands this near the mouth
	reentryCentre = { 0, 0 }, -- the town centre (the Main Street / Centre Street crossing)
	streetSkin = 0.5, -- studs: the top of a shaft this far under the street is not "underground" (the mouth window)
	shaftStep = 4, -- studs between route points down a shaft
	runStep = 6, -- studs between route points along a run
	bend = 0.8, -- studs: route points either side of a bend so the curve keeps to the walkway and the shaft
	twist = { 1.0, 2.8 }, -- studs over a shaft's foot: the body's back turns from the rungs' side to the run's way here
	endWall = 2.0, -- studs from a shaft foot back to the passage's end wall
	sampleStep = 0.5, -- studs between footprint samples when the carve is worked out
	stand = 1.9, -- studs from the chamber centre (each axis) to the fashion stand, in the quadrant away from the routes
}

export type Vec3 = { x: number, y: number, z: number }
export type Vec2 = { x: number, z: number }
export type Rect = { x0: number, x1: number, z0: number, z1: number }
export type Box =
	{ x0: number, x1: number, y0: number, y1: number, z0: number, z1: number, kind: string?, pipe: string? }
export type Section = {
	kind: string,
	art: string,
	innerHalf: number,
	outerHalf: number,
	below: number,
	crown: number,
	spring: number,
	walkway: { number },
	routeOffset: number,
	water: number?,
	width: number,
	headroom: number,
	lamp: { number },
}
export type Shaft = {
	cx: number,
	cz: number,
	inside: number,
	wall: number,
	top: number,
	bottom: number,
	rungs: Vec2,
}
export type Mouth = {
	id: string,
	pipe: string,
	space: string,
	kind: string,
	name: string,
	x: number,
	y: number,
	z: number,
	out: Vec2,
	reach: number,
	route: number,
	t: number,
	opening: Rect,
	shaft: Shaft,
	column: Box,
}
export type Passage = {
	pipe: string,
	space: string,
	route: number,
	section: string,
	side: number,
	offset: number,
	points: { Vec3 },
}
export type Port = { route: number, x: number, z: number, outward: Vec2 }
export type Chamber = {
	id: string,
	pipe: string,
	space: string,
	art: string,
	x: number,
	y: number,
	z: number,
	half: number,
	ports: { Port },
	crossing: Vec3,
	lid: Vec2,
}
export type Anchor = {
	kind: string,
	pipe: string,
	space: string,
	x: number,
	y: number,
	z: number,
	facing: Vec2?,
	text: string?,
	route: number?,
	t: number?,
}
export type SurfaceWay = { from: string, to: string, points: { Vec2 }, length: number, note: string? }
export type Pipe = {
	id: string,
	name: string,
	space: string,
	sign: string,
	section: string,
	mouths: { string },
	routes: { number },
	passages: { Passage },
	chamber: string?,
	surface: { SurfaceWay },
}
export type Compiled = {
	units: string,
	art: { pack: string, studsPerMetre: number },
	sections: { [string]: Section },
	shaft: { inside: number, wall: number, rungGap: number },
	carve: { voxel: number, margin: number, slabBottom: number, cover: number },
	pace: number,
	pipes: { Pipe },
	mouths: { Mouth },
	chambers: { Chamber },
	anchors: { Anchor },
	carves: { Box },
	routes: { any },
}

export type Layout = {
	data: Compiled,
	pipes: { Pipe },
	mouths: { Mouth },
	chambers: { Chamber },
	anchors: { Anchor },
	carves: { Box },
	routes: { any },
	pipe: (id: string) -> Pipe?,
	mouth: (id: string) -> Mouth?,
	mouthsOf: (pipeId: string) -> { Mouth },
	nearestMouth: (x: number, z: number, maxDist: number?) -> (Mouth?, number),
	spaceOf: (routeId: number) -> string?,
	contains: (x: number, y: number, z: number) -> string?,
	reentryMouth: (deathX: number, deathZ: number, people: { { number } }?) -> Mouth?,
	carveBoxes: () -> { Box },
	surfaceWalk: (from: string, to: string) -> SurfaceWay?,
}

-- small vector helpers (plan: x, z) ---------------------------------------------------------------------------------

-- rounded to 1e-4 (and never -0, so the compiled text is the same on every run)
local function r4(n: number): number
	return math.floor(n * 1e4 + 0.5) / 1e4 + 0
end

local function unit2(x: number, z: number): (number, number)
	local l = math.sqrt(x * x + z * z)
	if l < 1e-9 then
		return 0, 0
	end
	return x / l, z / l
end

-- the left of a level heading (dx, dz) with y up: (dz, -dx) (Motion's right is (-dz, dx))
local function left2(dx: number, dz: number): (number, number)
	return dz, -dx
end

local AXES: { [string]: Vec2 } = {
	["+x"] = { x = 1, z = 0 },
	["-x"] = { x = -1, z = 0 },
	["+z"] = { x = 0, z = 1 },
	["-z"] = { x = 0, z = -1 },
}

local function floorTo(v: number, step: number): number
	return math.floor(v / step + 1e-9) * step + 0
end

local function ceilTo(v: number, step: number): number
	return math.ceil(v / step - 1e-9) * step + 0
end

local function polyLength(points: { Vec2 }): number
	local len = 0
	for i = 2, #points do
		len += math.sqrt((points[i].x - points[i - 1].x) ^ 2 + (points[i].z - points[i - 1].z) ^ 2)
	end
	return len
end

-- the passage axis: the walkway line offset by `offset` to the side away from the walkway (mitred at bends)
local function offsetLine(line: { Vec3 }, side: number, offset: number): { Vec3 }
	local out: { Vec3 } = {}
	local n = #line
	for i = 1, n do
		local p = line[i]
		local ax, az, bx, bz = 0, 0, 0, 0
		if i > 1 then
			ax, az = unit2(p.x - line[i - 1].x, p.z - line[i - 1].z)
		end
		if i < n then
			bx, bz = unit2(line[i + 1].x - p.x, line[i + 1].z - p.z)
		end
		if i == 1 then
			ax, az = bx, bz
		elseif i == n then
			bx, bz = ax, az
		end
		local lax, laz = left2(ax, az)
		local lbx, lbz = left2(bx, bz)
		local mx, mz = unit2(lax + lbx, laz + lbz)
		local cosHalf = math.max(mx * lax + mz * laz, 0.2)
		-- the walkway is on `side` of the axis, so the axis is on the other side of the walkway
		local k = -side * offset / cosHalf
		table.insert(out, { x = r4(p.x + mx * k), y = p.y, z = r4(p.z + mz * k) })
	end
	return out
end

-- where two plan lines (a point and a direction each) meet
local function meet(p: Vec3, d: Vec2, q: Vec3, e: Vec2): Vec2?
	local den = d.x * e.z - d.z * e.x
	if math.abs(den) < 1e-9 then
		return nil
	end
	local s = ((q.x - p.x) * e.z - (q.z - p.z) * e.x) / den
	return { x = p.x + d.x * s, z = p.z + d.z * s }
end

-- the route's t nearest a point (sampled on the curve: compile time only)
local function tNear(curve: Curve.Curve, length: number, p: Vec3): number
	local n = math.max(200, math.ceil(length / 0.05))
	local best, bestT = math.huge, 0
	for i = 0, n do
		local u = i / n
		local q = curve:getPointAt(u)
		local d = (q.x - p.x) ^ 2 + (q.y - p.y) ^ 2 + (q.z - p.z) ^ 2
		if d < best then
			best, bestT = d, u
		end
	end
	return bestT
end

-- build -------------------------------------------------------------------------------------------------------------

export type BuildOptions = { pace: number? }

local function sectionOf(doc: any, kind: string): Section
	local s = doc.sections[kind]
	assert(s, `SewerLayout: no section {kind}`)
	local shaft = doc.shaft
	return {
		kind = kind,
		art = s.art,
		innerHalf = s.innerHalf,
		outerHalf = s.outerHalf,
		below = s.below,
		crown = s.crown,
		spring = s.spring,
		walkway = s.walkway,
		routeOffset = s.routeOffset,
		water = s.water,
		width = s.width,
		-- the section height the enclosure gives the body: under the vault at the walkway, or across a shaft from the
		-- rungs, whichever is less
		headroom = math.min(s.headroom, shaft.inside - shaft.rungGap),
		lamp = s.lamp,
	}
end

-- one route's points: down a shaft (when it starts at a mouth), along its walkway line, up a shaft (when it ends at
-- one). `line` is the walkway line in plan with its walkway height per vertex (the shaft feet included).
local function routePoints(line: { Vec3 }, topA: Vec3?, topB: Vec3?): { { number } }
	local C = SewerLayout.C
	local pts: { { number } } = {}
	local function add(x: number, y: number, z: number)
		table.insert(pts, { r4(x), r4(y), r4(z) })
	end
	local first, last = line[1], line[#line]
	if topA then
		local drop = topA.y - (first.y + C.bend)
		local n = math.max(1, math.ceil(drop / C.shaftStep))
		add(topA.x, topA.y, topA.z)
		for i = 1, n do
			add(first.x, topA.y - drop * i / n, first.z)
		end
	end
	add(first.x, first.y, first.z)
	for i = 1, #line - 1 do
		local a, b = line[i], line[i + 1]
		local len = math.sqrt((b.x - a.x) ^ 2 + (b.z - a.z) ^ 2)
		local dx, dz = (b.x - a.x) / len, (b.z - a.z) / len
		local function at(s: number)
			local f = s / len
			add(a.x + dx * s, a.y + (b.y - a.y) * f, a.z + dz * s)
		end
		-- a bend at a (a shaft foot or a turn) and at b gets points C.bend either side
		local s0 = if i > 1 or topA then C.bend else 0
		local s1 = if i < #line - 1 or topB then len - C.bend else len
		if s0 > 0 then
			at(s0)
		end
		local inner = s1 - s0
		local n = math.max(1, math.ceil(inner / C.runStep))
		for k = 1, n - 1 do
			at(s0 + inner * k / n)
		end
		if s1 < len then
			at(s1)
		end
		add(b.x, b.y, b.z)
	end
	if topB then
		local rise = topB.y - (last.y + C.bend)
		local n = math.max(1, math.ceil(rise / C.shaftStep))
		for i = 0, n - 1 do
			add(last.x, last.y + C.bend + rise * i / n, last.z)
		end
		add(topB.x, topB.y, topB.z)
	end
	return pts
end

-- the carve: every 4 x 4 column the footprint touches, with the heights it needs, merged into boxes
type Column = { y0: number, y1: number, kind: string }

local function addColumn(
	cols: { [string]: Column },
	voxel: number,
	x: number,
	z: number,
	y0: number,
	y1: number,
	kind: string
)
	local i, j = math.floor(x / voxel), math.floor(z / voxel)
	local key = `{i},{j}`
	local c = cols[key]
	if not c then
		cols[key] = { y0 = y0, y1 = y1, kind = kind }
		return
	end
	c.y0 = math.min(c.y0, y0)
	c.y1 = math.max(c.y1, y1)
	if kind == "shaft" or (kind == "chamber" and c.kind == "passage") then
		c.kind = kind
	end
end

local function mergeColumns(cols: { [string]: Column }, voxel: number, pipe: string): { Box }
	type Cell = { i: number, j: number, c: Column }
	local cells: { Cell } = {}
	for key, c in cols do
		local si, sj = string.match(key, "^(-?%d+),(-?%d+)$")
		table.insert(cells, { i = tonumber(si) :: number, j = tonumber(sj) :: number, c = c })
	end
	table.sort(cells, function(a: Cell, b: Cell): boolean
		if a.j ~= b.j then
			return a.j < b.j
		end
		return a.i < b.i
	end)
	-- runs along x within each row of the same heights and kind
	type Strip = { i0: number, i1: number, j0: number, j1: number, c: Column }
	local strips: { Strip } = {}
	for _, cell in cells do
		local s = strips[#strips]
		if
			s
			and s.j0 == cell.j
			and s.i1 + 1 == cell.i
			and s.c.y0 == cell.c.y0
			and s.c.y1 == cell.c.y1
			and s.c.kind == cell.c.kind
		then
			s.i1 = cell.i
		else
			table.insert(strips, { i0 = cell.i, i1 = cell.i, j0 = cell.j, j1 = cell.j, c = cell.c })
		end
	end
	-- strips stacked along z with the same extent
	local merged: { Strip } = {}
	for _, s in strips do
		local joined = false
		for k = #merged, 1, -1 do
			local m = merged[k]
			if m.j1 + 1 < s.j0 then
				break
			end
			if
				m.j1 + 1 == s.j0
				and m.i0 == s.i0
				and m.i1 == s.i1
				and m.c.y0 == s.c.y0
				and m.c.y1 == s.c.y1
				and m.c.kind == s.c.kind
			then
				m.j1 = s.j0
				joined = true
				break
			end
		end
		if not joined then
			table.insert(merged, { i0 = s.i0, i1 = s.i1, j0 = s.j0, j1 = s.j1, c = s.c })
		end
	end
	local out: { Box } = {}
	for _, m in merged do
		table.insert(out, {
			x0 = m.i0 * voxel,
			x1 = (m.i1 + 1) * voxel,
			y0 = m.c.y0,
			y1 = m.c.y1,
			z0 = m.j0 * voxel,
			z1 = (m.j1 + 1) * voxel,
			kind = m.c.kind,
			pipe = pipe,
		})
	end
	return out
end

-- build(doc, opts?): data/sewers.json (decoded, studs) -> the compiled table. opts.pace: the pipe pace written into
-- every route record's speedMult (the compiler passes Tunables sewer.speedMult).
function SewerLayout.build(doc: any, opts: BuildOptions?): Compiled
	local C = SewerLayout.C
	local o: BuildOptions = opts or {}
	local pace = o.pace or 1
	local shaftDoc = doc.shaft
	local carveDoc = doc.carve
	local voxel = carveDoc.voxel
	local margin = carveDoc.margin
	local slabBottom = carveDoc.slabBottom
	local reachDefault = doc.mouth.reach
	local riseDefault = doc.mouth.rise

	local sections: { [string]: Section } = {}
	for kind in doc.sections do
		sections[kind] = sectionOf(doc, kind)
	end

	local compiled: Compiled = {
		units = "studs",
		art = { pack = doc.art.pack, studsPerMetre = doc.art.studsPerMetre },
		sections = sections,
		shaft = { inside = shaftDoc.inside, wall = shaftDoc.wall, rungGap = shaftDoc.rungGap },
		carve = { voxel = voxel, margin = margin, slabBottom = slabBottom, cover = carveDoc.cover },
		pace = pace,
		pipes = {},
		mouths = {},
		chambers = {},
		anchors = {},
		carves = {},
		routes = {},
	}

	for _, p in doc.pipes do
		local section = sections[p.section]
		assert(section, `SewerLayout: pipe {p.id} names section {p.section}`)
		local pipe: Pipe = {
			id = p.id,
			name = p.name,
			space = p.space,
			sign = p.sign,
			section = p.section,
			mouths = {},
			routes = {},
			passages = {},
			chamber = nil,
			surface = {},
		}
		local mouthDocs: { [string]: any } = {}
		for _, m in p.mouths do
			mouthDocs[m.id] = m
		end
		-- the crossing of a junction pipe (P1): where the arms' walkway lines meet
		local junction = p.junction
		local crossing: Vec3? = nil
		if junction then
			crossing = { x = junction.at[1], y = p.walkway, z = junction.at[2] }
		end

		local cols: { [string]: Column } = {}
		local routeInfo: { [number]: { foot: Vec3, dir: Vec2, axis: { Vec3 }, side: number } } = {}
		local pending: { { curve: Curve.Curve, length: number, line: { Vec3 }, r: any } } = {}

		for _, r in p.routes do
			local fromDoc = mouthDocs[r.from]
			assert(fromDoc, `SewerLayout: route {r.id} from unknown mouth {r.from}`)
			local toDoc = if r.to == "junction" then nil else mouthDocs[r.to]
			assert(r.to == "junction" or toDoc, `SewerLayout: route {r.id} to unknown mouth {r.to}`)
			local wFrom = r.wFrom or p.walkway
			local wTo = r.wTo or p.walkway
			-- the walkway line: the foot of the first shaft, the authored bends, the foot of the last shaft or the
			-- crossing
			local line: { Vec3 } = { { x = fromDoc.at[1], y = wFrom, z = fromDoc.at[2] } }
			for _, v in r.via or {} do
				table.insert(line, { x = v[1], y = v[3], z = v[2] })
			end
			if toDoc then
				table.insert(line, { x = toDoc.at[1], y = wTo, z = toDoc.at[2] })
			else
				local c = crossing :: Vec3
				table.insert(line, { x = c.x, y = wTo, z = c.z })
			end
			local topA: Vec3 = { x = fromDoc.at[1], y = fromDoc.ground, z = fromDoc.at[2] }
			local topB: Vec3? = if toDoc then { x = toDoc.at[1], y = toDoc.ground, z = toDoc.at[2] } else nil
			local pts = routePoints(line, topA, topB)
			local vecs = {}
			for i, q in pts do
				vecs[i] = Curve.vec3(q[1], q[2], q[3])
			end
			local curve = Curve.new(vecs)
			local length = curve:getLength()
			local side = if r.side == "left" then 1 else -1
			local dx, dz = unit2(line[2].x - line[1].x, line[2].z - line[1].z)
			routeInfo[r.id] = {
				foot = line[1],
				dir = { x = dx, z = dz },
				axis = offsetLine(line, side, section.routeOffset),
				side = side,
			}
			table.insert(pending, { curve = curve, length = length, line = line, r = r })
			table.insert(pipe.routes, r.id)

			-- the passage: the axis from the end wall behind the first shaft to the far end wall (or the chamber port,
			-- below, once the chamber is known)
			local axis = offsetLine(line, side, section.routeOffset)
			local a1, a2 = axis[1], axis[2]
			local ex, ez = unit2(a2.x - a1.x, a2.z - a1.z)
			local startWall: Vec3 = { x = r4(a1.x - ex * C.endWall), y = a1.y, z = r4(a1.z - ez * C.endWall) }
			local pass: { Vec3 } = { startWall }
			for i = 1, #axis do
				table.insert(pass, axis[i])
			end
			if toDoc then
				local an, am = axis[#axis], axis[#axis - 1]
				local fx, fz = unit2(an.x - am.x, an.z - am.z)
				table.insert(pass, { x = r4(an.x + fx * C.endWall), y = an.y, z = r4(an.z + fz * C.endWall) })
			end
			table.insert(pipe.passages, {
				pipe = p.id,
				space = p.space,
				route = r.id,
				section = p.section,
				side = side,
				offset = section.routeOffset,
				points = pass,
			})
		end

		-- the chamber: the junction module where the arms' axes cross
		if junction then
			local c = crossing :: Vec3
			local pairs = junction.straight
			local ia, ib = routeInfo[pairs[1][1]], routeInfo[pairs[2][1]]
			local centre = meet(ia.axis[1], ia.dir, ib.axis[1], ib.dir)
			assert(centre, "SewerLayout: the junction's two straight pairs are parallel")
			local half = doc.junction.half
			local ports: { Port } = {}
			for _, r in p.routes do
				local info = routeInfo[r.id]
				-- the port faces back along the arm toward its mouth
				local ox, oz = -info.dir.x, -info.dir.z
				table.insert(ports, {
					route = r.id,
					x = r4(centre.x + ox * half),
					z = r4(centre.z + oz * half),
					outward = { x = r4(ox), z = r4(oz) },
				})
			end
			local chamber: Chamber = {
				id = p.id .. ".chamber",
				pipe = p.id,
				space = p.space,
				art = doc.junction.art,
				x = r4(centre.x),
				y = c.y,
				z = r4(centre.z),
				half = half,
				ports = ports,
				crossing = { x = c.x, y = c.y, z = c.z },
				lid = { x = r4(centre.x), z = r4(centre.z) },
			}
			pipe.chamber = chamber.id
			-- the arms' passages end at their ports
			for _, pass in pipe.passages do
				for _, port in ports do
					if port.route == pass.route then
						local n = #pass.points
						pass.points[n] = { x = port.x, y = pass.points[n].y, z = port.z }
					end
				end
			end
			table.insert(compiled.chambers, chamber)
			-- the chamber's carve: the module's square, turned to the arms
			local u, v = ia.dir, ib.dir
			local h = half + margin
			local n = math.ceil(2 * h / C.sampleStep)
			for i = 0, n do
				local s = -h + 2 * h * i / n
				for k = 0, n do
					local q = -h + 2 * h * k / n
					addColumn(
						cols,
						voxel,
						centre.x + u.x * s + v.x * q,
						centre.z + u.z * s + v.z * q,
						c.y - section.below - margin,
						c.y + section.crown + margin,
						"chamber"
					)
				end
			end
			-- the fashion stand (BUILD_PLAN W4 #9; brief v2 decision 20 "sewer and fashion stand stay"): on the
			-- chamber floor in the quadrant away from the crossing, facing it
			local cu = (c.x - centre.x) * u.x + (c.z - centre.z) * u.z
			local cv = (c.x - centre.x) * v.x + (c.z - centre.z) * v.z
			local su = if cu >= 0 then -C.stand else C.stand
			local sv = if cv >= 0 then -C.stand else C.stand
			local sx, sz = centre.x + u.x * su + v.x * sv, centre.z + u.z * su + v.z * sv
			local fx, fz = unit2(c.x - sx, c.z - sz)
			table.insert(compiled.anchors, {
				kind = "fashionStand",
				pipe = p.id,
				space = p.space,
				x = r4(sx),
				y = c.y,
				z = r4(sz),
				facing = { x = r4(fx), z = r4(fz) },
				route = pairs[1][1],
				t = 1,
			})
			table.insert(compiled.anchors, {
				kind = "lightGrate",
				pipe = p.id,
				space = p.space,
				x = r4(centre.x),
				y = c.y,
				z = r4(centre.z),
				text = "manhole lid over the chamber",
			})
		end

		-- the route records
		local straightOf: { [number]: number } = {}
		if junction then
			for _, pair in junction.straight do
				straightOf[pair[1]] = pair[2]
				straightOf[pair[2]] = pair[1]
			end
		end
		for _, pend in pending do
			local r = pend.r
			local curve, length = pend.curve, pend.length
			local fromDoc = mouthDocs[r.from]
			local toDoc = if r.to == "junction" then nil else mouthDocs[r.to]
			local line = pend.line
			local mouths = {}
			local function mouthRec(m: any, t: number): { [string]: any }
				local rg = AXES[m.rungs]
				return {
					t = t,
					opens = "ground",
					out = { rg.x, 0, rg.z },
					reach = m.reach or reachDefault,
					rise = m.rise or riseDefault,
					name = m.id,
				}
			end
			table.insert(mouths, mouthRec(fromDoc, 0))
			if toDoc then
				table.insert(mouths, mouthRec(toDoc, 1))
			end
			-- the section's up (the body's back). High in a shaft it faces away from the rungs; lower down it turns (about
			-- the shaft's line) to face along the run, so the turn at the foot is a roll about the body's width: its width
			-- stays level and nothing dips into the floor or the side wall; along a run it is up.
			local upAt: { { number } } = {}
			local function key(p3: Vec3, x: number, y: number, z: number)
				table.insert(upAt, { r4(tNear(curve, length, p3)), r4(x), y, r4(z) })
			end
			local footA, nextA = line[1], line[2]
			local da = { x = 0, z = 0 }
			da.x, da.z = unit2(nextA.x - footA.x, nextA.z - footA.z)
			local ra = AXES[fromDoc.rungs]
			table.insert(upAt, { 0, r4(-ra.x), 0, r4(-ra.z) })
			key({ x = footA.x, y = footA.y + C.twist[2], z = footA.z }, -ra.x, 0, -ra.z)
			key({ x = footA.x, y = footA.y + C.twist[1], z = footA.z }, da.x, 0, da.z)
			key({ x = footA.x + da.x * C.bend, y = footA.y, z = footA.z + da.z * C.bend }, 0, 1, 0)
			if toDoc then
				local footB, prevB = line[#line], line[#line - 1]
				local db = { x = 0, z = 0 }
				db.x, db.z = unit2(footB.x - prevB.x, footB.z - prevB.z)
				local rb = AXES[toDoc.rungs]
				key({ x = footB.x - db.x * C.bend, y = footB.y, z = footB.z - db.z * C.bend }, 0, 1, 0)
				key({ x = footB.x, y = footB.y + C.twist[1], z = footB.z }, -db.x, 0, -db.z)
				key({ x = footB.x, y = footB.y + C.twist[2], z = footB.z }, -rb.x, 0, -rb.z)
				table.insert(upAt, { 1, r4(-rb.x), 0, r4(-rb.z) })
			end
			local enclosure: { [string]: any } = {
				id = p.space,
				mouths = mouths,
				width = section.width,
				height = section.headroom,
				upAt = upAt,
			}
			if junction then
				-- the crossing: straight on by the end link (W), the side arms by forks (A/D), all at the arms' t = 1
				local forks = {}
				for _, other in p.routes do
					if other.id ~= r.id and other.id ~= straightOf[r.id] then
						table.insert(forks, { t = 1, route = other.id, toT = 1, dir = -1, name = other.from })
					end
				end
				enclosure.atEnd = { route = straightOf[r.id], t = 1, dir = -1 }
				enclosure.forks = forks
			end
			local pts = {}
			for i = 1, #curve.points do
				local q = curve.points[i]
				pts[i] = { q.x, q.y, q.z }
			end
			local rec: { [string]: any } = {
				id = r.id,
				name = r.name,
				kind = "tunnel",
				speedMult = pace,
				surfaceRadius = 0,
				visualOffset = 0,
				length = r4(length),
				sampleCount = Curve.sampleSteps(length / 2.5) + 1,
				points = pts,
				origin = "sewer",
				generator = "sewer:" .. p.id,
				flags = {
					autoGrabExcluded = true,
					isPole = false,
					isGiant = false,
					fixedSurfaceZ = false,
					treeTravel = false,
				},
				enclosure = enclosure,
			}
			table.insert(compiled.routes, rec)
		end

		-- the mouths, their shafts and carve columns
		for _, m in p.mouths do
			local rg = AXES[m.rungs]
			assert(rg, `SewerLayout: mouth {m.id} rungs must be +x, -x, +z or -z`)
			local route, t = 0, 0
			for _, r in p.routes do
				if r.from == m.id then
					route, t = r.id, 0
				elseif r.to == m.id then
					route, t = r.id, 1
				end
			end
			local w = p.walkway
			for _, r in p.routes do
				if r.from == m.id and r.wFrom then
					w = r.wFrom
				elseif r.to == m.id and r.wTo then
					w = r.wTo
				end
			end
			local inside, wall, gap = shaftDoc.inside, shaftDoc.wall, shaftDoc.rungGap
			-- the route runs `gap` off the rung wall; the shaft is `inside` square from that wall
			local cx = m.at[1] - rg.x * (inside / 2 - gap)
			local cz = m.at[2] - rg.z * (inside / 2 - gap)
			local half = inside / 2 + wall
			local column: Box = {
				x0 = floorTo(cx - half, voxel),
				x1 = ceilTo(cx + half, voxel),
				y0 = math.max(floorTo(w - section.below - margin, voxel), slabBottom),
				y1 = ceilTo(m.ground, voxel),
				z0 = floorTo(cz - half, voxel),
				z1 = ceilTo(cz + half, voxel),
				kind = "shaft",
				pipe = p.id,
			}
			local x = column.x0 + voxel / 2
			while x < column.x1 do
				local z = column.z0 + voxel / 2
				while z < column.z1 do
					addColumn(cols, voxel, x, z, column.y0, column.y1, "shaft")
					z += voxel
				end
				x += voxel
			end
			local opening: Rect
			if m.opening then
				opening = { x0 = m.opening[1], x1 = m.opening[2], z0 = m.opening[3], z1 = m.opening[4] }
			else
				opening = {
					x0 = r4(cx - inside / 2),
					x1 = r4(cx + inside / 2),
					z0 = r4(cz - inside / 2),
					z1 = r4(cz + inside / 2),
				}
			end
			local mouth: Mouth = {
				id = m.id,
				pipe = p.id,
				space = p.space,
				kind = m.kind,
				name = m.name,
				x = m.at[1],
				y = m.ground,
				z = m.at[2],
				out = { x = rg.x, z = rg.z },
				reach = m.reach or reachDefault,
				route = route,
				t = t,
				opening = opening,
				shaft = {
					cx = r4(cx),
					cz = r4(cz),
					inside = inside,
					wall = wall,
					top = m.ground,
					bottom = w,
					rungs = { x = rg.x, z = rg.z },
				},
				column = column,
			}
			table.insert(compiled.mouths, mouth)
			table.insert(pipe.mouths, m.id)
		end

		-- the passages' carve, lamps and signs
		for _, pass in pipe.passages do
			local pts = pass.points
			for i = 1, #pts - 1 do
				local a, b = pts[i], pts[i + 1]
				local len = math.sqrt((b.x - a.x) ^ 2 + (b.z - a.z) ^ 2)
				if len < 1e-6 then
					continue
				end
				local dx, dz = (b.x - a.x) / len, (b.z - a.z) / len
				local lx, lz = left2(dx, dz)
				-- the outer shell plus the margin, sampled finely enough that no 4-stud column it touches is missed
				local hw = section.outerHalf + margin
				local ns = math.ceil((len + 2 * margin) / C.sampleStep)
				local nl = math.ceil(2 * hw / C.sampleStep)
				for k = 0, ns do
					local s = -margin + (len + 2 * margin) * k / ns
					local wy = a.y + (b.y - a.y) * math.clamp(s / len, 0, 1)
					for q = 0, nl do
						local l = -hw + 2 * hw * q / nl
						addColumn(
							cols,
							voxel,
							a.x + dx * s + lx * l,
							a.z + dz * s + lz * l,
							wy - section.below - margin,
							wy + section.crown + margin,
							"passage"
						)
					end
				end
			end
			-- lamps: one per art module length along the passage, on the wall away from the walkway
			local plan: { Vec2 } = {}
			for i, q in pts do
				plan[i] = { x = q.x, z = q.z }
			end
			local total = polyLength(plan)
			local every = doc.lampEvery
			local lampSide = if section.routeOffset > 0 then -pass.side else -1
			local d = every / 2
			while d < total do
				local acc = 0
				for i = 1, #pts - 1 do
					local a, b = pts[i], pts[i + 1]
					local len = math.sqrt((b.x - a.x) ^ 2 + (b.z - a.z) ^ 2)
					if d <= acc + len and len > 1e-6 then
						local f = (d - acc) / len
						local dx, dz = (b.x - a.x) / len, (b.z - a.z) / len
						local lx, lz = left2(dx, dz)
						local y = a.y + (b.y - a.y) * f
						table.insert(compiled.anchors, {
							kind = "lamp",
							pipe = p.id,
							space = p.space,
							x = r4(a.x + dx * (d - acc) + lx * lampSide * section.lamp[1]),
							y = r4(y + section.lamp[2]),
							z = r4(a.z + dz * (d - acc) + lz * lampSide * section.lamp[1]),
							facing = { x = r4(-lx * lampSide), z = r4(-lz * lampSide) },
						})
						break
					end
					acc += len
				end
				d += every
			end
		end
		-- a sign at each shaft foot, on the passage's end wall, facing along the run
		for _, pass in pipe.passages do
			local pts = pass.points
			local ends = { { pts[1], pts[2] } }
			if not junction then
				table.insert(ends, { pts[#pts], pts[#pts - 1] })
			end
			for _, e in ends do
				local w, nxt = e[1], e[2]
				local fx, fz = unit2(nxt.x - w.x, nxt.z - w.z)
				table.insert(compiled.anchors, {
					kind = "sign",
					pipe = p.id,
					space = p.space,
					x = r4(w.x + fx * 0.05),
					y = r4(w.y + 1.1),
					z = r4(w.z + fz * 0.05),
					facing = { x = r4(fx), z = r4(fz) },
					text = p.sign,
				})
			end
		end
		for _, g in p.lightGrates or {} do
			local best, by = math.huge, p.walkway
			for _, pass in pipe.passages do
				for i = 1, #pass.points - 1 do
					local a, b = pass.points[i], pass.points[i + 1]
					local abx, abz = b.x - a.x, b.z - a.z
					local ll = abx * abx + abz * abz
					local f = if ll > 0 then math.clamp(((g[1] - a.x) * abx + (g[2] - a.z) * abz) / ll, 0, 1) else 0
					local d = (a.x + abx * f - g[1]) ^ 2 + (a.z + abz * f - g[2]) ^ 2
					if d < best then
						best, by = d, a.y + (b.y - a.y) * f
					end
				end
			end
			table.insert(compiled.anchors, {
				kind = "lightGrate",
				pipe = p.id,
				space = p.space,
				x = g[1],
				y = r4(by),
				z = g[2],
				text = "light-only grate",
			})
		end

		-- the carve boxes: heights to the grid, the bottom no lower than the terrain slab
		for _, c in cols do
			c.y0 = math.max(floorTo(c.y0, voxel), slabBottom)
			if c.kind ~= "shaft" then
				c.y1 = ceilTo(c.y1, voxel)
			end
		end
		for _, b in mergeColumns(cols, voxel, p.id) do
			table.insert(compiled.carves, b)
		end

		for _, s in p.surface or {} do
			local pts: { Vec2 } = {}
			for i, q in s.points do
				pts[i] = { x = q[1], z = q[2] }
			end
			table.insert(
				pipe.surface,
				{ from = s.from, to = s.to, points = pts, length = r4(polyLength(pts)), note = s.note }
			)
		end
		table.insert(compiled.pipes, pipe)
	end
	return compiled
end

-- new -------------------------------------------------------------------------------------------------------------

-- the volumes `contains` tests: passage stretches (oriented boxes with a sloping floor), chambers, shafts
type Stretch = {
	space: string,
	ax: number,
	az: number,
	ay: number,
	by: number,
	dx: number,
	dz: number,
	len: number,
	half: number,
	below: number,
	crown: number,
}
type Well = { space: string, cx: number, cz: number, half: number, y0: number, y1: number }
type Room = {
	space: string,
	cx: number,
	cz: number,
	y: number,
	ux: number,
	uz: number,
	half: number,
	below: number,
	crown: number,
}

function SewerLayout.new(compiled: Compiled): Layout
	local C = SewerLayout.C
	local pipeById: { [string]: Pipe } = {}
	local mouthById: { [string]: Mouth } = {}
	local spaceByRoute: { [number]: string } = {}
	for _, p in compiled.pipes do
		pipeById[p.id] = p
	end
	for _, m in compiled.mouths do
		mouthById[m.id] = m
	end
	for _, r in compiled.routes do
		spaceByRoute[r.id] = r.enclosure.id
	end
	local stretches: { Stretch } = {}
	local wells: { Well } = {}
	local rooms: { Room } = {}
	for _, p in compiled.pipes do
		local section = compiled.sections[p.section]
		for _, pass in p.passages do
			for i = 1, #pass.points - 1 do
				local a, b = pass.points[i], pass.points[i + 1]
				local len = math.sqrt((b.x - a.x) ^ 2 + (b.z - a.z) ^ 2)
				if len > 1e-6 then
					table.insert(stretches, {
						space = p.space,
						ax = a.x,
						az = a.z,
						ay = a.y,
						by = b.y,
						dx = (b.x - a.x) / len,
						dz = (b.z - a.z) / len,
						len = len,
						half = section.outerHalf,
						below = section.below,
						crown = section.crown,
					})
				end
			end
		end
	end
	for _, m in compiled.mouths do
		local s = m.shaft
		local section = compiled.sections[(pipeById[m.pipe] :: Pipe).section]
		table.insert(wells, {
			space = m.space,
			cx = s.cx,
			cz = s.cz,
			half = s.inside / 2 + s.wall,
			y0 = s.bottom - section.below,
			y1 = s.top - C.streetSkin,
		})
	end
	for _, ch in compiled.chambers do
		local section = compiled.sections[(pipeById[ch.pipe] :: Pipe).section]
		local port = ch.ports[1]
		table.insert(rooms, {
			space = ch.space,
			cx = ch.x,
			cz = ch.z,
			y = ch.y,
			ux = port.outward.x,
			uz = port.outward.z,
			half = ch.half,
			below = section.below,
			crown = section.crown,
		})
	end

	local layout = {} :: Layout
	layout.data = compiled
	layout.pipes = compiled.pipes
	layout.mouths = compiled.mouths
	layout.chambers = compiled.chambers
	layout.anchors = compiled.anchors
	layout.carves = compiled.carves
	layout.routes = compiled.routes

	function layout.pipe(id: string): Pipe?
		return pipeById[id]
	end
	function layout.mouth(id: string): Mouth?
		return mouthById[id]
	end
	function layout.mouthsOf(pipeId: string): { Mouth }
		local out: { Mouth } = {}
		for _, m in compiled.mouths do
			if m.pipe == pipeId then
				table.insert(out, m)
			end
		end
		return out
	end
	function layout.nearestMouth(x: number, z: number, maxDist: number?): (Mouth?, number)
		local best: Mouth? = nil
		local bestD = maxDist or math.huge
		for _, m in compiled.mouths do
			local d = math.sqrt((m.x - x) ^ 2 + (m.z - z) ^ 2)
			if d <= bestD then
				best, bestD = m, d
			end
		end
		return best, if best then bestD else math.huge
	end
	function layout.spaceOf(routeId: number): string?
		return spaceByRoute[routeId]
	end
	function layout.contains(x: number, y: number, z: number): string?
		for _, w in wells do
			if math.abs(x - w.cx) <= w.half and math.abs(z - w.cz) <= w.half and y >= w.y0 and y <= w.y1 then
				return w.space
			end
		end
		for _, r in rooms do
			local px, pz = x - r.cx, z - r.cz
			local u = px * r.ux + pz * r.uz
			local v = -px * r.uz + pz * r.ux
			if math.abs(u) <= r.half and math.abs(v) <= r.half and y >= r.y - r.below and y <= r.y + r.crown then
				return r.space
			end
		end
		for _, s in stretches do
			local px, pz = x - s.ax, z - s.az
			local along = px * s.dx + pz * s.dz
			if along >= 0 and along <= s.len then
				local lateral = -px * s.dz + pz * s.dx
				local floor = s.ay + (s.by - s.ay) * along / s.len
				if math.abs(lateral) <= s.half and y >= floor - s.below and y <= floor + s.crown then
					return s.space
				end
			end
		end
		return nil
	end
	function layout.reentryMouth(deathX: number, deathZ: number, people: { { number } }?): Mouth?
		local crowd: { { number } } = people or {}
		local function clear(m: Mouth): boolean
			for _, q in crowd do
				if (q[1] - m.x) ^ 2 + (q[2] - m.z) ^ 2 < C.reentryClear * C.reentryClear then
					return false
				end
			end
			return true
		end
		local cx, cz = C.reentryCentre[1], C.reentryCentre[2]
		local best: Mouth? = nil
		local bestD = math.huge
		for _, m in compiled.mouths do
			local away = math.sqrt((m.x - deathX) ^ 2 + (m.z - deathZ) ^ 2)
			if away >= C.reentryMin and clear(m) then
				local d = math.sqrt((m.x - cx) ^ 2 + (m.z - cz) ^ 2)
				if d < bestD then
					best, bestD = m, d
				end
			end
		end
		if best then
			return best
		end
		-- nothing far enough and clear: the clear one farthest from the death, else the farthest
		for _, wantClear in { true, false } do
			local far = -1
			for _, m in compiled.mouths do
				if not wantClear or clear(m) then
					local away = math.sqrt((m.x - deathX) ^ 2 + (m.z - deathZ) ^ 2)
					if away > far then
						best, far = m, away
					end
				end
			end
			if best then
				return best
			end
		end
		return nil
	end
	function layout.carveBoxes(): { Box }
		local out: { Box } = {}
		for _, b in compiled.carves do
			table.insert(
				out,
				{ x0 = b.x0, x1 = b.x1, y0 = b.y0, y1 = b.y1, z0 = b.z0, z1 = b.z1, kind = b.kind, pipe = b.pipe }
			)
		end
		return out
	end
	function layout.surfaceWalk(from: string, to: string): SurfaceWay?
		for _, p in compiled.pipes do
			for _, s in p.surface do
				if s.from == from and s.to == to then
					return s
				end
				if s.from == to and s.to == from then
					local rev: { Vec2 } = {}
					for i = #s.points, 1, -1 do
						table.insert(rev, s.points[i])
					end
					return { from = from, to = to, points = rev, length = s.length, note = s.note }
				end
			end
		end
		return nil
	end
	return layout
end

-- default(): the layout over the compiled data (Shared/Data's "Sewers" module), nil when it has not been compiled.
local cached: Layout? = nil
function SewerLayout.default(): Layout?
	if cached then
		return cached
	end
	local Data = (require :: any)("../Data")
	local d = Data.default()
	if not d:has("Sewers") then
		return nil
	end
	cached = SewerLayout.new(d:module("Sewers") :: any)
	return cached
end

return SewerLayout
