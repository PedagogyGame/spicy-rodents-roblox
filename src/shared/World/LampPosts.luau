--!strict
-- ReplicatedStorage.Shared.World.LampPosts
-- Every light post in the town climbable (owner D35, 2026-11-22: "make all trees climbable, and even all light posts").
-- The posts are what the bakes place (the town's street lamps and the ways' (worldgen LampPlan), Bowl Lane's and Lift
-- Road's kit lamps, the bowling alley's forecourt lamps, the yards' porch lights; not the backdrop pier's),
-- found in the baked models by tools/bake/LampScan and written to data/lamp_posts.json by tools/bake/lamp_posts.luau.
-- tools/compile (lib/LampPosts) calls LampPosts.build on that file and writes generated/LampPosts.luau; Shared/Data
-- appends its routes to the Registry (after the tree shapes) and merges its forks into the canopy forks, so the
-- squirrel, the town's AI, the movement validator and every rail user see one set of routes. Routes are data, not
-- parts: nothing is drawn for them (the lamps look as they did; the lights keep their shared timing).
-- Nothing here is a mechanic of its own: a post is climbed as a tree trunk is.
--   the climb   a route of kind "trunk" up the post's axis, from the feet of a squirrel standing at its foot
--               (C.stand over the ground) to the post's top (on the finial, where the post has an arm), where it
--               stops: the perch. Flags: treeTravel (the
--               trees' pace up and down), isPole (as a telephone pole: E or a walk into it takes it within the
--               pole gate, the body drawn a fixed distance off the axis, the post being one width all the way up);
--   the arm     where a post has one (the town's lamps, Bowl Lane's, Lift Road's): a route of kind "branch" along
--               the curved arm from the post to the lamp head (the arm's shape, armPoints), leaving the climb at a
--               trunk sample with a canopy fork made by the harvest's own rule, as a tree's bough does: A/D on the
--               post picks it, W takes it, and its tip over the lamp head is a second perch. An arm whose tip hangs
--               over a road's car lane stops short of it (`run`, tools/bake/LampScan.armRun): no route over a lane.
-- Off the top the motor's own leap, E and the end-of-route rules reach whatever wire, bough or roof is in reach; at
-- the foot S runs down to the ground's height and Q lets go, as on a tree.
--
-- THE INTERFACE
--   LampPosts.build(doc) -> Compiled          (the compiler only)
--   LampPosts.armPoints(x, z, top, arm) -> { {x,y,z} }   the arm's centre line, post axis to tip (four points)
--   LampPosts.cut(points, run) -> { {x,y,z} }            that line up to `run` studs out from the axis
--   LampPosts.C                               the fixed numbers below
-- doc: { idBase, posts { Post } }, Post = { id, source, path, x, z, ground, top, radius, arm = { ox, oz, reach }? }
-- (studs, world space, y up; `ground` the height a squirrel stands at the post's foot, `top` the post's top).
-- Compiled: routes { RouteRecord } (origin "lampPost"), forks { ForkRecord } (one per post with an arm), posts
--   { { id, source, climb, arm? } } (route ids per post). Pure: no engine calls. No side effects on require.

local Curve = require("../Routes/Curve")

local LampPosts = {}

LampPosts.C = table.freeze({
	spu = 2.5, -- studs per HTML unit (Config/Units)
	stand = 0.18 * 2.5, -- studs: the climb's foot over the ground (a squirrel's feet standing there)
	armDrop = 0.9, -- studs under the post's top where the arm leaves it (worldgen Skyline, Street, Approach: p0)
	-- the arm's bends from the post (out along the arm, up): p0 -> p1 -> p2, then to the tip at `reach`, `tipDrop` lower
	armBends = table.freeze({ table.freeze({ 1.3, 1.1 }), table.freeze({ 1.8, 0.25 }) }),
	tipDrop = 0.55,
	armRadius = 0.2, -- studs: the arm rod's radius (the widest drawn: the Skyline's 0.4)
	armLift = 0.75, -- studs: the body drawn over the arm's centre line (a wire's lift and the rod's radius)
	forkOut = 0.19, -- the fork's outward: start -> getPointAt(0.19), level (rebuildCanopyForks)
	minHeight = 3, -- studs: a post shorter than this over the ground is no climb
	-- studs: a post with an arm has a finial; its climb ends this far over the post's top, on the finial, so the arm's
	-- start (at or under armDrop below the top) is out of the end-of-route switch's reach (Motion.C.autoSwitchGap, 1.2):
	-- the top is a stop, the perch, and the arm is the fork A/D picks
	finial = 0.5,
})

-- reach: the drawn arm's tip from the post's axis (level, studs); run: where the route along it stops when that is
-- short of the tip (a tip over a road's car lane: tools/bake/LampScan.armRun), else nil
export type Arm = { ox: number, oz: number, reach: number, run: number? }
export type Post = {
	id: string,
	source: string,
	path: string?,
	x: number,
	z: number,
	ground: number,
	top: number,
	radius: number,
	arm: Arm?,
}
export type Doc = { idBase: number, posts: { Post } }
export type ForkEntry = {
	branch: number,
	t: number,
	height: number,
	origin: { number },
	outward: { number },
	trunkClearance: number?,
}
export type ForkRecord = { trunk: number, forks: { ForkEntry } }
export type PostRoutes = { id: string, source: string, climb: number, arm: number? }
export type Compiled = { routes: { any }, forks: { ForkRecord }, posts: { PostRoutes } }

local function r4(v: number): number
	return math.floor(v * 10000 + 0.5) / 10000
end

local function curveOf(points: { { number } }): Curve.Curve
	local v = {}
	for i, p in points do
		v[i] = Curve.vec3(p[1], p[2], p[3])
	end
	return Curve.new(v)
end

local function flags(kind: string): { [string]: boolean }
	return {
		autoGrabExcluded = false,
		isPole = kind == "trunk",
		isGiant = false,
		fixedSurfaceZ = false,
		treeTravel = true,
	}
end

local function record(id: number, name: string, kind: string, points: { { number } }, source: string): { [string]: any }
	local length = curveOf(points):getLength()
	return {
		id = id,
		name = name,
		kind = kind,
		speedMult = 1,
		sprintMult = 1,
		surfaceRadius = 0,
		length = r4(length),
		sampleCount = Curve.sampleSteps(length / LampPosts.C.spu) + 1,
		points = points,
		origin = "lampPost",
		generator = "lampPost@" .. source,
		flags = flags(kind),
	}
end

-- armPoints(x, z, top, arm): the arm's centre line from the post's axis (armDrop under the top) by its two bends to the
-- tip over the lamp head
function LampPosts.armPoints(x: number, z: number, top: number, arm: Arm): { { number } }
	local C = LampPosts.C
	local out, along, y = { { x, top - C.armDrop, z } }, 0, top - C.armDrop
	for _, b in C.armBends do
		along += b[1]
		y += b[2]
		table.insert(out, { x + arm.ox * along, y, z + arm.oz * along })
	end
	table.insert(out, { x + arm.ox * arm.reach, y - C.tipDrop, z + arm.oz * arm.reach })
	return out
end

-- cut(points, run): the arm's centre line (armPoints) up to `run` studs out (level) from the post's axis
function LampPosts.cut(points: { { number } }, run: number): { { number } }
	local x0, z0 = points[1][1], points[1][3]
	local function out(p: { number }): number
		return math.sqrt((p[1] - x0) ^ 2 + (p[3] - z0) ^ 2)
	end
	local res = { points[1] }
	for i = 2, #points do
		local a, b = points[i - 1], points[i]
		local oa, ob = out(a), out(b)
		if ob <= run + 1e-9 then
			table.insert(res, b)
		else
			local u = (run - oa) / (ob - oa)
			table.insert(res, { a[1] + (b[1] - a[1]) * u, a[2] + (b[2] - a[2]) * u, a[3] + (b[3] - a[3]) * u })
			break
		end
	end
	return res
end

function LampPosts.build(doc: Doc): Compiled
	local C = LampPosts.C
	local routes: { any } = {}
	local forks: { ForkRecord } = {}
	local posts: { PostRoutes } = {}
	local nextId = doc.idBase
	for _, p in doc.posts do
		local foot = p.ground + C.stand
		assert(p.top - foot >= C.minHeight, `lamp posts: {p.id} is {p.top - foot} studs tall`)
		local id = nextId
		nextId += 1
		local arm = p.arm
		local top = if arm then p.top + C.finial else p.top -- (a finial on every post with an arm)
		local climb = record(id, `lamp post climb {p.id}`, "trunk", {
			{ r4(p.x), r4(foot), r4(p.z) },
			{ r4(p.x), r4((foot + top) / 2), r4(p.z) },
			{ r4(p.x), r4(top), r4(p.z) },
		}, p.source)
		climb.surfaceRadius = r4(p.radius)
		table.insert(routes, climb)
		local entry: PostRoutes = { id = p.id, source = p.source, climb = id }
		if arm and arm.run ~= 0 then
			-- the arm leaves the climb at the highest climb sample not over its own start (the start is that sample,
			-- unrounded)
			local pts = LampPosts.cut(LampPosts.armPoints(p.x, p.z, p.top, arm), arm.run or arm.reach)
			local samples = curveOf(climb.points):getSpacedPoints(climb.sampleCount - 1)
			local best = 1
			for i, s in samples do
				if s.y <= pts[1][2] + 1e-6 then
					best = i
				end
			end
			local s = samples[best]
			pts[1] = { s.x, s.y, s.z }
			for i = 2, #pts do
				pts[i] = { r4(pts[i][1]), r4(pts[i][2]), r4(pts[i][3]) }
			end
			local armId = nextId
			nextId += 1
			local rec = record(armId, `lamp post arm {p.id}`, "branch", pts, p.source)
			rec.surfaceRadius = C.armRadius
			rec.visualOffset = C.armLift
			rec.trunkClearance = r4(p.radius)
			table.insert(routes, rec)
			-- the canopy fork, by the harvest's rule (TreeShapes' forkFor)
			local curve = curveOf(pts)
			local o = curve:getPointAt(0)
			local ahead = curve:getPointAt(C.forkOut)
			local ox, oz = ahead.x - o.x, ahead.z - o.z
			local l = math.sqrt(ox * ox + oz * oz)
			table.insert(forks, {
				trunk = id,
				forks = {
					{
						branch = armId,
						t = (best - 1) / (#samples - 1),
						height = s.y,
						origin = { o.x, o.y, o.z },
						outward = { ox / l, 0, oz / l },
						trunkClearance = r4(p.radius),
					},
				},
			})
			entry.arm = armId
		end
		table.insert(posts, entry)
	end
	return { routes = routes, forks = forks, posts = posts }
end

return LampPosts
