--!strict
-- ReplicatedStorage.Shared.World.TreeShapes
-- The trees reshaped and planted for the owner's D32 notes ("not just a single place and point where branches come
-- out of and all split ... add a few lower branches, make some trees even bigger, and add a couple trees").
-- data/tree_shapes.json is authored; tools/compile (lib/TreeShapes) calls TreeShapes.build on it with the harvested
-- routes and canopy forks and writes generated/TreeShapes.luau; Shared/Data appends its routes to the Registry (after
-- the hollow trees) and merges its forks into the canopy forks, so the squirrel, the town's AI, the movement validator
-- and the bake all see one set of routes. Nothing here is a mechanic of its own: a grown bough is a route of kind
-- "branch" leaving a trunk sample exactly as a harvested bough leaves its trunk, with a canopy fork made by the
-- harvest's own rule (rebuildCanopyForks: the trunk sample nearest the bough's start, the start's height, the level
-- outward from the start to 0.19 along it). Pure: no engine calls. Studs, world space, y up. No side effects on require.
--
-- RESHAPED TREES (`reshaped`): a harvested tree (never a hollow one: Shared/World/HollowLayout owns those trunks) keeps
-- every harvested route and gains boughs at other heights. A bough is written in THE TREE-LOCAL FRAME of
-- HollowLayout (bearing in degrees clockwise from +z seen from above: x = sin, z = cos; heights above the trunk's
-- foot):
--   at       studs above the foot where it leaves the trunk (snapped to the trunk's nearest sample)
--   bearing  the way it heads out
--   reach    studs out (level) from the trunk's axis to its tip
--   rise     the tip's height over where it leaves (negative: it ends lower)
--   arch     how far its middle bows over the straight line from start to tip (studs; negative sags)
--   curl     degrees it turns aside along its length (positive clockwise)
--   tier     "low" (reached from the ground or a short leap), "mid" or "high" (a high one may lift the crown)
-- The centre line runs through five points at u = 0, 0.18, 0.42, 0.7, 1: level distance reach*u on the bearing turned
-- by curl*u, height at + rise*u + arch*sin(pi u).
--
-- PLANTED TREES (`planted`): a copy of a harvested tree that has uploaded mesh art, moved level to (x, z) and seated
-- on the ground there (the copy's foot stands as high over World/Height as its source's foot does): its trunk and
-- every bough of its canopy forks, translated, and its forks with them. The bake places the source's meshes at the
-- copy's pivot (tools/compile lib/TreeShapes adds the art records), so the copy is the same tree, bark on its routes.
--
-- THE INTERFACE
--   TreeShapes.build(doc, harvest, forks, heightAt) -> Compiled   (the compiler only)
--   TreeShapes.mergeForks(base, extra) -> { ForkRecord }          the canopy forks with the grown and planted ones
--   TreeShapes.boughPoints(trunkFoot, start, spec) -> { {x,y,z} } a bough's five centre-line points (start on the axis)
--   TreeShapes.C                                                   the fixed numbers below
-- Compiled: routes { RouteRecord } (origin "treeShape"), forks { ForkRecord } (the new forks only, per trunk), trees
--   { Tree }: Tree = { trunk, kind "reshaped" | "planted", label, why, routes { id } (the routes it gained: a planted
--   tree's are all of them), boughs { { route, tier, at } }, source? (a planted tree's harvested trunk), offset?
--   ({dx, dy, dz}: source to copy) }.

local Curve = require("../Routes/Curve")

local TreeShapes = {}

TreeShapes.C = table.freeze({
	spu = 2.5, -- studs per HTML unit (Config/Units)
	boughRadius = 1.35 * 2.5, -- a bough's surfaceRadius (studs): the harvested boughs' 1.35 u
	forkOut = 0.19, -- the fork's outward: start -> getPointAt(0.19), level (rebuildCanopyForks)
	shape = table.freeze({ 0, 0.18, 0.42, 0.7, 1 }), -- where along a bough its five centre-line points lie
	maxSlope = 56, -- degrees: no stretch of a grown bough climbs or falls steeper (the harvest's boughs leave at 54)
	tiers = table.freeze({ low = true, mid = true, high = true }),
})

export type BoughSpec = {
	at: number,
	bearing: number,
	reach: number,
	rise: number,
	arch: number?,
	curl: number?,
	tier: string,
}
export type Reshape = { trunk: number, label: string, why: string?, big: boolean?, boughs: { BoughSpec } }
export type Plant = { id: string, source: number, x: number, z: number, label: string, why: string? }
export type Doc = { idBase: number, reshaped: { Reshape }, planted: { Plant }? }

export type ForkEntry = {
	branch: number,
	t: number,
	height: number,
	origin: { number },
	outward: { number },
	trunkClearance: number?,
}
export type ForkRecord = { trunk: number, forks: { ForkEntry } }

export type Tree = {
	trunk: number,
	kind: string,
	label: string,
	why: string?,
	routes: { number },
	boughs: { { route: number, tier: string, at: number } },
	source: number?,
	offset: { number }?,
}
export type Compiled = { routes: { any }, forks: { ForkRecord }, trees: { Tree } }

local function r4(v: number): number
	return math.floor(v * 10000 + 0.5) / 10000
end

local function dirOf(bearing: number): (number, number)
	local a = math.rad(bearing)
	return math.sin(a), math.cos(a)
end

-- TreeShapes.boughPoints(foot, start, spec): the five centre-line points of a bough leaving the trunk axis at `start`
-- ({x, y, z}); `foot` is the trunk's foot (heights in the spec are above it).
function TreeShapes.boughPoints(_foot: { number }, start: { number }, spec: BoughSpec): { { number } }
	local out = {}
	for _, u in TreeShapes.C.shape do
		local dx, dz = dirOf(spec.bearing + (spec.curl or 0) * u)
		local d = spec.reach * u
		table.insert(out, {
			r4(start[1] + dx * d),
			r4(start[2] + spec.rise * u + (spec.arch or 0) * math.sin(math.pi * u)),
			r4(start[3] + dz * d),
		})
	end
	return out
end

local function vec(p: { number }): Curve.Vec3
	return Curve.vec3(p[1], p[2], p[3])
end

local function curveOf(points: { { number } }): Curve.Curve
	local v = {}
	for i, p in points do
		v[i] = vec(p)
	end
	return Curve.new(v)
end

local function flags(kind: string): { [string]: boolean }
	return {
		autoGrabExcluded = false,
		isPole = false,
		isGiant = false,
		fixedSurfaceZ = false,
		treeTravel = kind == "trunk" or kind == "branch" or kind == "bridge" or kind == "lookout",
	}
end

-- the fork the harvest's rule makes for a bough on a trunk (Graph.Fork's record)
local function forkFor(harvest: any, trunk: any, bough: any): ForkEntry
	local curve = curveOf(bough.points)
	local o = curve:getPointAt(0)
	local ahead = curve:getPointAt(TreeShapes.C.forkOut)
	local samples = harvest:samples(trunk)
	local best, bd = 1, math.huge
	for i, s in samples do
		local d = (s.x - o.x) ^ 2 + (s.y - o.y) ^ 2 + (s.z - o.z) ^ 2
		if d < bd then
			best, bd = i, d
		end
	end
	local ox, oz = ahead.x - o.x, ahead.z - o.z
	local l = math.sqrt(ox * ox + oz * oz)
	return {
		branch = bough.id,
		t = (best - 1) / (#samples - 1),
		height = samples[best].y,
		origin = { o.x, o.y, o.z },
		outward = { ox / l, 0, oz / l },
		trunkClearance = trunk.surfaceRadius,
	}
end

local function record(id: number, name: string, kind: string, points: { { number } }, from: any?): { [string]: any }
	local length = curveOf(points):getLength()
	local rec: { [string]: any } = {
		id = id,
		name = name,
		kind = kind,
		speedMult = 1,
		sprintMult = 1,
		surfaceRadius = if from then from.surfaceRadius else TreeShapes.C.boughRadius,
		length = r4(length),
		sampleCount = Curve.sampleSteps(length / TreeShapes.C.spu) + 1,
		points = points,
		origin = "treeShape",
		generator = "treeShape@" .. (if from then "copy" else "bough"),
		flags = flags(kind),
	}
	if from then
		rec.visualOffset = from.visualOffset
		rec.trunkClearance = from.trunkClearance
		if from.center then
			rec.center = { r4(from.center.x), r4(from.center.y), r4(from.center.z) }
		end
		-- (a copy keeps its source's sample count: the same curve, moved)
		rec.sampleCount = from.sampleCount
	end
	return rec
end

local function arr(p: Curve.Vec3): { number }
	return { p.x, p.y, p.z }
end

-- the trunk sample nearest a height above the foot
local function sampleAtHeight(harvest: any, trunk: any, y: number): Curve.Vec3
	local best, bd = nil, math.huge
	for _, s in harvest:samples(trunk) do
		local d = math.abs(s.y - y)
		if d < bd then
			best, bd = s, d
		end
	end
	return best :: Curve.Vec3
end

local function trunkName(trunk: any): string
	local n = trunk.name
	return (string.gsub(n, " trunk$", ""))
end

function TreeShapes.build(doc: Doc, harvest: any, forks: { ForkRecord }, heightAt: (number, number) -> number): Compiled
	local routes: { any } = {}
	local newForks: { ForkRecord } = {}
	local trees: { Tree } = {}
	local nextId = doc.idBase
	local forksOf: { [number]: ForkRecord } = {}
	for _, f in forks do
		forksOf[f.trunk] = f
	end

	for _, rs in doc.reshaped do
		local trunk = harvest:get(rs.trunk)
		assert(trunk and trunk.kind == "trunk", `tree shapes: {rs.trunk} is not a trunk`)
		local foot = harvest:foot(trunk)
		local tree: Tree =
			{ trunk = rs.trunk, kind = "reshaped", label = rs.label, why = rs.why, routes = {}, boughs = {} }
		local rec: ForkRecord = { trunk = rs.trunk, forks = {} }
		for k, spec in rs.boughs do
			assert(TreeShapes.C.tiers[spec.tier], `tree shapes: bough tier {spec.tier}`)
			local s = sampleAtHeight(harvest, trunk, foot.y + spec.at)
			local pts = TreeShapes.boughPoints(arr(foot), { s.x, s.y, s.z }, spec)
			-- (the start is the trunk sample itself, unrounded: the fork's origin lies on the trunk's own curve)
			pts[1] = { s.x, s.y, s.z }
			local id = nextId
			nextId += 1
			local bough = record(id, `{trunkName(trunk)} grown bough {k}`, "branch", pts)
			bough.trunkClearance = trunk.surfaceRadius
			table.insert(routes, bough)
			table.insert(rec.forks, forkFor(harvest, trunk, bough))
			table.insert(tree.routes, id)
			table.insert(tree.boughs, { route = id, tier = spec.tier, at = r4(s.y - foot.y) })
		end
		table.insert(newForks, rec)
		table.insert(trees, tree)
	end

	for _, pl in doc.planted or {} do
		local src = harvest:get(pl.source)
		assert(src and src.kind == "trunk", `tree shapes: planted source {pl.source} is not a trunk`)
		local srcForks = forksOf[pl.source]
		assert(srcForks, `tree shapes: planted source {pl.source} has no canopy forks`)
		local foot = harvest:foot(src)
		local dx, dz = pl.x - foot.x, pl.z - foot.z
		local dy = heightAt(pl.x, pl.z) - heightAt(foot.x, foot.z)
		local function move(p: Curve.Vec3): { number }
			return { r4(p.x + dx), r4(p.y + dy), r4(p.z + dz) }
		end
		local tree: Tree = {
			trunk = nextId,
			kind = "planted",
			label = pl.label,
			why = pl.why,
			routes = {},
			boughs = {},
			source = pl.source,
			offset = { r4(dx), r4(dy), r4(dz) },
		}
		local idOf: { [number]: number } = {}
		local function copy(r: any): number
			local id = nextId
			nextId += 1
			local pts = {}
			for i, p in r.points do
				pts[i] = move(p)
			end
			local name = `planted {pl.id} {r.name}`
			local c = record(id, name, r.kind, pts, r)
			if r.center then
				c.center = move(r.center)
			end
			table.insert(routes, c)
			table.insert(tree.routes, id)
			idOf[r.id] = id
			return id
		end
		tree.trunk = copy(src)
		local rec: ForkRecord = { trunk = tree.trunk, forks = {} }
		for _, f in srcForks.forks do
			local b = harvest:get(f.branch)
			assert(b, `tree shapes: source fork branch {f.branch}`)
			local id = copy(b)
			table.insert(rec.forks, {
				branch = id,
				t = f.t,
				height = r4(f.height + dy),
				origin = { r4(f.origin[1] + dx), r4(f.origin[2] + dy), r4(f.origin[3] + dz) },
				outward = { f.outward[1], f.outward[2], f.outward[3] },
				trunkClearance = f.trunkClearance,
			})
			table.insert(tree.boughs, { route = id, tier = "copy", at = r4(f.height - foot.y) })
		end
		table.insert(newForks, rec)
		table.insert(trees, tree)
	end
	return { routes = routes, forks = newForks, trees = trees }
end

-- mergeForks(base, extra): the canopy forks of `base` with `extra`'s added (a trunk in both keeps base's forks and
-- gains extra's; a trunk only in extra is a new record). Neither input is changed.
function TreeShapes.mergeForks(base: { ForkRecord }, extra: { ForkRecord }): { ForkRecord }
	local add: { [number]: { ForkEntry } } = {}
	for _, r in extra do
		add[r.trunk] = r.forks
	end
	local out: { ForkRecord } = {}
	local seen: { [number]: boolean } = {}
	for _, r in base do
		local more = add[r.trunk]
		if more then
			local list = table.clone(r.forks)
			for _, f in more do
				table.insert(list, f)
			end
			table.insert(out, { trunk = r.trunk, forks = list })
			seen[r.trunk] = true
		else
			table.insert(out, r)
		end
	end
	for _, r in extra do
		if not seen[r.trunk] then
			table.insert(out, r)
		end
	end
	return out
end

return TreeShapes
