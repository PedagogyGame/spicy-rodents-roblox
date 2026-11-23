--!strict
-- ReplicatedStorage.Shared.World.BranchNooks
-- Branches that feel like a squirrel's (owner D34, 2026-11-22: "little nooks in the branches ... a little shift from
-- running over the nodules, but still smooth movement feel and play, the points where the branches are can have stash
-- places off to the side and a little place to hangout, cozy! improve and add branching"). Worked out for EVERY
-- climbable tree from its route data alone, so a tree added later gets the same once it is compiled:
--   a climbable tree = a route of kind "trunk" with canopy forks (the harvest's generated/Forks, the tree shapes'
--   grown and planted forks, any later module's forks merged the same way) whose branches are open routes of kind
--   "branch". Nothing else is read: no tree list, no names.
-- What it lays on such a tree (tools/compile lib/BranchNooks calls plan() over every route and fork compiled before
-- it and writes generated/BranchNooks.luau; Shared/Data appends its routes to the Registry after the tree shapes):
--   NOOK      a short route of kind "branch" leaving a bough just past its collar (the bough's own sample, so the
--             motor's A/D junction choice offers it and E takes it: no jump) and curling back to the trunk into the
--             crook between the bough and the bark; it ends a step lower than the bough, in a cupped hollow drawn round
--             its end (Client/World/BranchNookView: a floor, bark walls, a soft lip). Up to C.nooksPerTree a tree (one
--             more on a big tree), on different boughs, lowest first.
--   STASH     each nook has one: a knot-hole cache in the bark beside its cup (off to the side of the branch point),
--             a stash spot of the nut system: E in the cup stores what the squirrel carries or takes nuts out, per
--             player (Server/Foraging/BranchStash; the hint "E  stash" shows within C.stashReach).
--   HANGOUT   at the wider forks (a bough whose neighbour on that side leaves the trunk at least C.hangoutGap degrees
--             round), a longer flat crook of the same kind: a mossy ledge round the trunk with room for three
--             squirrels to sit (sitting: Client/World/BranchNookClient, the seat rules' keys and STAND button). Up to
--             C.hangoutsPerTree a tree (one more on a big tree: C.bigTree forks or more).
--   SPUR      a short side branch off the middle of a long bough (more places to go), arched and rising, of kind
--             "branch"; up to C.spursPerTree a tree (one more on a big tree).
--   NODULES   knots along every branch's run path (nodules(route): arc distances), drawn small on the bark and felt as a
--             quick settle of the drawn body as it runs over one (Shared/Movement/BranchFeel). Client only: the motor,
--             the server and the validator never see them.
-- Every new route: starts exactly on a sample of its bough; stays C.clear studs from every other route beyond its first
-- C.clearFrom studs (C.clearEnclosed from a hollow's runs and perches), outside the trunk's bark, C.overGround over the
-- ground, out of the buildings (C.buildingPad round their boxes); no stretch steeper than C.maxSlope. A candidate that breaks any of these is left out (the other side of the
-- bough, another bough, or none). Seeded per trunk (Park-Miller, exact in doubles): a rebuild is the same tree.
-- THE INTERFACE
--   BranchNooks.plan(registry, forks, heightAt, blocked?) -> Compiled   (the compiler only; registry over every route so
--                                                                  far; blocked(x, y, z): a building's box holds it)
--   BranchNooks.new(compiled) -> Nooks                            a lookup over generated/BranchNooks.luau
--   BranchNooks.nodules(route) -> { number }                      arc distances (studs) of a branch's knots (cached)
--   BranchNooks.barkRadius(trunk, t) -> studs                     the bark the game takes a trunk to have at t
--   BranchNooks.rngOf(text) -> () -> [0, 1)
--   BranchNooks.C
-- Compiled: routes { RouteRecord } (origin "branchNook"), places { Place }, trees { { trunk, nooks, hangouts, spurs }
--   (route ids) }. Place = { route, kind "nook" | "hangout" | "spur", trunk, parent (the bough), parentT (where on it
--   the route leaves), at { x, y, z } (its far end: the motor's point there; the feet stand C.lift higher), out { x, z }
--   (level unit: facing out of the
--   crook, away from the trunk), seatFrom (t from which a squirrel may sit; nook and hangout), stash? { x, y, z, nx,
--   nz } (a nook's knot-hole: its middle and level normal out of the bark) }.
-- Nooks: places, routes, place(routeId) -> Place?, stashes() -> { Place }, stashNear(x, y, z, reach?) -> Place?,
--   seatAt(routeId, t) -> Place? (the place whose seat stretch holds t), entranceNear(routeId, t, reach?) -> Place?
--   (a nook or hangout leaving this bough within reach studs of t), tree(trunk) -> { Place }.
-- Studs, world space, y up. Pure: no engine calls. No side effects on require.

local Curve = require("../Routes/Curve")
local Motion = require("../Routes/Motion")

local BranchNooks = {}

BranchNooks.C = table.freeze({
	idBase = 30001, -- route ids from here (clear of the harvest 0-1331, the 9000s of drains, hollows and tree shapes, the 20000s of lamp posts)
	spu = 2.5, -- studs per HTML unit (Config/Units)
	lift = Motion.C.visualBranchLift, -- the feet over a branch's line (Routes/Motion §14)
	-- a nook: leaves its bough where the bough's line is nookOut studs outside the bark, turns nookTurn degrees from the
	-- bough's level heading back toward the trunk and runs nookLen studs, ending nookDrop studs lower (a step down into
	-- the cup), its end cupGap studs outside the bark
	nooksPerTree = 2, -- (one more on a big tree: bigTree)
	nookOuts = table.freeze({ 1.6, 2.6, 3.6 }), -- tried in turn: further out where the crook is crowded
	nookSeatFrom = 0.7,
	nookLen = 2.8,
	nookTurns = table.freeze({ 128, 112, 96, 140 }),
	nookDrop = 0.3,
	cupRadius = 1.2, -- the cup's floor (studs)
	cupWall = 0.9, -- the bark wall round its back, over the floor
	cupLip = 0.35, -- the soft lip at its front
	nookSurface = 1.0, -- the nook's surfaceRadius
	-- a stash: a knot-hole in the bark beside the cup, stashUp over the cup's floor, stashSide studs round the trunk
	-- from the cup toward the bough it left; used from the cup: the body's point (the motor's, which the server holds)
	-- within stashReach of the nook's far end
	stashUp = 0.7,
	stashSide = 0.9,
	stashReach = 1.5,
	stashMargin = 0.4, -- no other route comes within stashReach + this of a cup
	stashHole = 0.55, -- the hole's radius
	boughBark = 1.1, -- a bough's bark from its line (Builders/Trees: its drawn radius near the trunk)
	-- a hangout: a flat crook from a bough at a wide fork, hangoutLen studs round the trunk; sitting from seatFrom on
	hangoutsPerTree = 1,
	-- trees kept calm (by trunk route name): at most these, whatever their size (owner D41: the tree by the Spicy
	-- Rodent's start, "horrible to navigate all cluttered")
	calm = table.freeze({
		["planted P2 Villa Oak South trunk"] = table.freeze({ nooks = 1, hangouts = 1, spurs = 0 }),
	}),
	bigTree = 10, -- a tree with this many forks or more gets one more nook, hangout and spur
	hangoutGap = 70, -- degrees: the fork's gap to the next bough round the trunk on that side
	hangoutOuts = table.freeze({ 1.4, 2.4, 3.4 }),
	hangoutLen = 4.8,
	hangoutTurns = table.freeze({ 118, 104, 132 }),
	hangoutSeatFrom = 0.4,
	hangoutWidth = 2.6, -- the ledge (studs across)
	-- a spur: from a bough of at least spurMinParent studs, between spurFrom and spurTo of it, spurAngle degrees off its
	-- level heading, spurLen long, rising spurRise and arched spurArch over its chord, curling spurCurl degrees
	spursPerTree = 2,
	spurMinParent = 12,
	spurFrom = 0.38,
	spurTo = 0.62,
	spurAngles = table.freeze({ 48, 40, 56 }),
	spurLens = table.freeze({ 6.5, 5.5, 7.5 }),
	spurRise = 1.8,
	spurArch = 0.9,
	spurCurl = 14,
	spurSurface = 0.6, -- of its bough's surfaceRadius
	shape = table.freeze({ 0, 0.18, 0.42, 0.7, 1 }), -- where along a new route its five centre-line points lie
	-- the rules every new route keeps
	clear = 2.0, -- studs from any other route's line, beyond clearFrom studs along it
	clearFrom = 1.4,
	clearNear = 1.5, -- ... and this much from any but its bough, everywhere (over the motor's 1.2-stud automatic switch)
	startGap = 3, -- studs from the start of a new route to any other new route
	clearOwn = 1.8, -- from its own bough's line, at the most (its far end)
	ownSlope = 0.55, -- ... and at least this much of the way walked from it
	clearEnclosed = 6, -- from a hollow's runs and its perches (their hops and leaps are specced to land elsewhere)
	barkPad = 0.9, -- outside the bark (barkRadius) this much
	overGround = 6, -- over the ground at every sample (a walker passes under)
	buildingPad = 1.5, -- studs round a building's box (World/Colliders) no new route comes into
	maxSlope = 56, -- degrees (the harvest's boughs leave at 54)
	-- nodules: knots on a branch's run path, one every noduleGap (seeded in [min, max]) studs from noduleStart past the
	-- collar to noduleEnd before the tip
	noduleGap = table.freeze({ 5, 8 }),
	noduleStart = 3,
	noduleEnd = 1.5,
})
local C = BranchNooks.C

export type Place = {
	route: number,
	kind: string,
	trunk: number,
	parent: number,
	parentT: number,
	at: { number },
	out: { number },
	seatFrom: number?,
	stash: { number }?,
}
export type TreeRec = { trunk: number, nooks: { number }, hangouts: { number }, spurs: { number } }
export type Compiled = { routes: { any }, places: { Place }, trees: { TreeRec }, rejected: { [string]: number }? }

local function r4(v: number): number
	return math.floor(v * 10000 + 0.5) / 10000
end

-- rngOf(text): a seeded stream in [0, 1) (Park-Miller over the text's bytes; exact in doubles, as HollowLayout's)
function BranchNooks.rngOf(text: string): () -> number
	local s = 0
	for i = 1, #text do
		s = (s * 31 + string.byte(text, i)) % 2147483647
	end
	if s == 0 then
		s = 1
	end
	return function(): number
		s = (s * 48271) % 2147483647
		return s / 2147483647
	end
end

-- the bark the game takes a trunk to have at t (Routes/Motion.visualPose: where the feet of a climbing squirrel are,
-- a tapering radius plus the pad)
function BranchNooks.barkRadius(trunk: any, t: number): number
	local MC = Motion.C
	local r = if trunk.surfaceRadius > 0 then trunk.surfaceRadius else MC.visualDefaultR
	if trunk.flags and (trunk.flags.fixedSurfaceZ or trunk.flags.isPole) then
		return r + MC.visualTrunkFixedPad
	end
	local tapered
	if trunk.flags and trunk.flags.isGiant then
		tapered = math.max(MC.visualGiantMinR, r / 0.95 - MC.visualGiantTaper * t)
	else
		tapered = math.max(MC.visualTrunkMinR, r * (1 - MC.visualTrunkTaper * t))
	end
	return tapered + MC.visualTrunkPad
end

-- nodules(route): the arc distances (studs from its start) of the knots on a branch's run path: none on anything but
-- a branch, a nook or a hangout (too short: their own cup or ledge), seeded per route
local noduleCache: { [any]: { number } } = setmetatable({}, { __mode = "k" }) :: any
function BranchNooks.nodules(route: any): { number }
	local known = noduleCache[route]
	if known then
		return known
	end
	local out: { number } = {}
	local name = route.name or ""
	local crookRoute = route.origin == "branchNook"
		and (string.sub(name, 1, 5) == "nook " or string.sub(name, 1, 8) == "hangout ")
	if route.kind == "branch" and route.enclosure == nil and not crookRoute then
		local rand = BranchNooks.rngOf(`nodules {route.id}`)
		local s = math.max(C.noduleStart, (route.trunkClearance or 0) + C.noduleStart)
		local L = route.length
		s += rand() * C.noduleGap[1] * 0.5
		while s <= L - C.noduleEnd do
			table.insert(out, r4(s))
			s += C.noduleGap[1] + rand() * (C.noduleGap[2] - C.noduleGap[1])
		end
	end
	noduleCache[route] = out
	return out
end

-- planning --------------------------------------------------------------------------------------------------------

type V3 = { x: number, y: number, z: number }

local function level(a: V3, b: V3): number
	return math.sqrt((a.x - b.x) ^ 2 + (a.z - b.z) ^ 2)
end

-- the trunk sample nearest a height, and its t
local function trunkAt(reg: any, trunk: any, y: number): (V3, number)
	local samples = reg:samples(trunk)
	local best, bd = 1, math.huge
	for i, s in samples do
		local d = math.abs(s.y - y)
		if d < bd then
			best, bd = i, d
		end
	end
	return samples[best], (best - 1) / math.max(#samples - 1, 1)
end

-- a spatial hash of every route's samples (cell 4 studs)
local CELL = 4
type Hash = { [string]: { { x: number, y: number, z: number, id: number } } }
local function key(x: number, y: number, z: number): string
	return `{math.floor(x / CELL)},{math.floor(y / CELL)},{math.floor(z / CELL)}`
end
local function addSamples(hash: Hash, id: number, samples: { V3 })
	for _, s in samples do
		local k = key(s.x, s.y, s.z)
		local cell = hash[k]
		if not cell then
			cell = {}
			hash[k] = cell
		end
		table.insert(cell, { x = s.x, y = s.y, z = s.z, id = id })
	end
end
-- the nearest sample of any route but `skip` within `r` (one cell's reach), as (distance, id)
local function nearestOther(hash: Hash, p: V3, skip: { [number]: boolean }): (number, number?)
	local cx, cy, cz = math.floor(p.x / CELL), math.floor(p.y / CELL), math.floor(p.z / CELL)
	local best, bid = math.huge, nil
	for dx = -2, 2 do
		for dy = -2, 2 do
			for dz = -2, 2 do
				local cell = hash[`{cx + dx},{cy + dy},{cz + dz}`]
				if cell then
					for _, s in cell do
						if not skip[s.id] then
							local d = (s.x - p.x) ^ 2 + (s.y - p.y) ^ 2 + (s.z - p.z) ^ 2
							if d < best then
								best, bid = d, s.id
							end
						end
					end
				end
			end
		end
	end
	return math.sqrt(best), bid
end

-- five centre-line points from `start` heading `hx, hz` (level unit): reach studs out, turning `curl` degrees along it,
-- rising `rise`, bowed `arch` over the chord
local function pointsFrom(start: V3, hx: number, hz: number, reach: number, rise: number, arch: number, curl: number)
	local out = {}
	local h0 = math.atan2(hx, hz)
	for i, u in C.shape do
		if i == 1 then
			table.insert(out, { start.x, start.y, start.z })
			continue
		end
		-- (the level path integrates the heading: a curl bends the route, not just its end)
		local x, z = start.x, start.z
		local steps = 8
		for k = 1, steps do
			local uu = u * (k - 0.5) / steps
			local h = h0 + math.rad(curl) * uu
			x += math.sin(h) * reach * u / steps
			z += math.cos(h) * reach * u / steps
		end
		table.insert(out, { r4(x), r4(start.y + rise * u + arch * math.sin(math.pi * u)), r4(z) })
	end
	return out
end

local function curveOf(points: { { number } }): Curve.Curve
	local v = {}
	for i, p in points do
		v[i] = Curve.vec3(p[1], p[2], p[3])
	end
	return Curve.new(v)
end

local function record(id: number, name: string, points: { { number } }, surface: number): { [string]: any }
	-- (the Registry's defaults fill the rest: speed 1, sprint 1, flags from the name and kind: tree travel)
	local length = curveOf(points):getLength()
	return {
		id = id,
		name = name,
		kind = "branch",
		surfaceRadius = r4(surface),
		length = r4(length),
		sampleCount = Curve.sampleSteps(length / C.spu) + 1,
		points = points,
		origin = "branchNook",
	}
end

type Ctx = {
	reg: any,
	hash: Hash,
	boughs: { [number]: Hash },
	why: { [string]: number },
	enclosed: Hash,
	mine: Hash,
	heightAt: (number, number) -> number,
	blocked: ((x: number, y: number, z: number) -> boolean)?,
}

-- does a candidate keep every rule? (its samples, its bough and trunk)
local function keeps(ctx: Ctx, samples: { V3 }, bough: any, trunk: any): boolean
	local skipOwn = { [bough.id] = true, [trunk.id] = true }
	local onlyBough: Hash = ctx.boughs[bough.id]
	local none = {}
	local trunkSamples = ctx.reg:samples(trunk)
	local trunkTop = trunkSamples[#trunkSamples].y
	local walked = 0
	local function no(why: string): boolean
		ctx.why[why] = (ctx.why[why] or 0) + 1
		return false
	end
	for i, p in samples do
		if i > 1 then
			local q = samples[i - 1]
			local h = level(p, q)
			walked += math.sqrt(h * h + (p.y - q.y) ^ 2)
			if math.deg(math.atan2(math.abs(p.y - q.y), math.max(h, 1e-6))) > C.maxSlope then
				return no("slope")
			end
		end
		if p.y - ctx.heightAt(p.x, p.z) < C.overGround then
			return no("ground")
		end
		local blockedAt = ctx.blocked
		if blockedAt and blockedAt(p.x, p.y, p.z) then
			return no("building")
		end
		-- outside the bark at its height
		if p.y <= trunkTop + 1 then
			local a, tt = trunkAt(ctx.reg, trunk, p.y)
			if level(p, a) < BranchNooks.barkRadius(trunk, tt) + C.barkPad then
				return no("bark")
			end
		end
		-- every other route: clearNear near the start, clear beyond clearFrom; its own bough falls away behind it
		-- (ownSlope of the way walked, up to clearOwn); a hollow's anything clearEnclosed
		local d = nearestOther(ctx.hash, p, skipOwn)
		if d < (if walked < C.clearFrom then C.clearNear else C.clear) then
			return no("routes")
		end
		if i > 1 then
			local db = nearestOther(onlyBough, p, none)
			if db < math.min(C.clearOwn, C.ownSlope * walked) - 1e-6 then
				return no("bough")
			end
		end
		local de = nearestOther(ctx.enclosed, p, none)
		if de < C.clearEnclosed then
			return no("hollow")
		end
		-- the other new routes: clear beyond clearFrom, and none starts within startGap of another (two starts side by
		-- side on one bough: running back down one to its start would switch onto the other's end by itself)
		if walked >= C.clearFrom or i == 1 then
			local dm = nearestOther(ctx.mine, p, none)
			if dm < (if i == 1 then C.startGap else C.clear) then
				return no("mine")
			end
		end
	end
	return true
end

-- the samples a record will have (as the Registry builds them)
local function samplesOf(rec: { [string]: any }): { V3 }
	return curveOf(rec.points):getSpacedPoints(rec.sampleCount - 1) :: any
end

-- the bough's sample nearest an arc length from its start, and that sample's t
local function boughSample(reg: any, bough: any, arc: number): (V3, number)
	local samples = reg:samples(bough)
	local n = #samples
	local i = math.clamp(math.floor(arc / bough.length * (n - 1) + 0.5), 1, n - 2)
	return samples[i + 1], i / (n - 1)
end

-- the first sample of a bough whose line is `out` studs outside the bark (level), and its t; nil when it never is
local function pastCollar(reg: any, bough: any, trunk: any, out: number, maxT: number): (V3?, number?)
	local samples = reg:samples(bough)
	for i, s in samples do
		local tt = (i - 1) / (#samples - 1)
		if tt > maxT then
			return nil, nil
		end
		local a, ta = trunkAt(reg, trunk, s.y)
		if level(s, a) >= BranchNooks.barkRadius(trunk, ta) + out then
			return s, tt
		end
	end
	return nil, nil
end

-- the bough's level heading at t (unit), from its tangent
local function headingAt(reg: any, bough: any, t: number): (number, number)
	local tg = reg:tangentAt(bough, math.clamp(t, 0.002, 0.998))
	local l = math.sqrt(tg.x * tg.x + tg.z * tg.z)
	if l < 1e-6 then
		return 0, 1
	end
	return tg.x / l, tg.z / l
end

local function rotate(x: number, z: number, deg: number): (number, number)
	-- clockwise seen from above (bearing convention: x = sin, z = cos)
	local a = math.rad(deg)
	local c, s = math.cos(a), math.sin(a)
	return x * c + z * s, -x * s + z * c
end

-- the level direction out of the crook at a route's end: away from the trunk's axis
local function outOf(reg: any, trunk: any, p: V3): { number }
	local a = trunkAt(reg, trunk, p.y)
	local dx, dz = p.x - a.x, p.z - a.z
	local l = math.sqrt(dx * dx + dz * dz)
	if l < 1e-6 then
		return { 0, 1 }
	end
	return { r4(dx / l), r4(dz / l) }
end

function BranchNooks.plan(
	reg: any,
	forks: { any },
	heightAt: (number, number) -> number,
	blocked: ((x: number, y: number, z: number) -> boolean)?
): Compiled
	local ctx: Ctx = {
		reg = reg,
		hash = {},
		boughs = {},
		why = {},
		enclosed = {},
		mine = {},
		heightAt = heightAt,
		blocked = blocked,
	}
	for _, r in reg:all() do
		if r.enclosure ~= nil or r.origin == "hollow" then
			addSamples(ctx.enclosed, r.id, reg:samples(r))
		end
		if r.enclosure == nil then
			addSamples(ctx.hash, r.id, reg:samples(r))
		end
	end
	local trunks: { { trunk: any, boughs: { { route: any, fork: any } } } } = {}
	for _, rec in forks do
		local trunk = reg:get(rec.trunk)
		if trunk == nil or trunk.kind ~= "trunk" or trunk.enclosure ~= nil or trunk.origin == "lampPost" then
			continue
		end
		local boughs = {}
		for _, f in rec.forks do
			local b = reg:get(f.branch)
			if b and b.kind == "branch" and b.enclosure == nil and b.origin ~= "hollow" then
				table.insert(boughs, { route = b, fork = f })
				local own: Hash = {}
				addSamples(own, b.id, reg:samples(b))
				ctx.boughs[b.id] = own
			end
		end
		if #boughs > 0 then
			table.sort(boughs, function(a, b)
				if a.fork.height ~= b.fork.height then
					return a.fork.height < b.fork.height
				end
				return a.route.id < b.route.id
			end)
			table.insert(trunks, { trunk = trunk, boughs = boughs })
		end
	end
	table.sort(trunks, function(a, b)
		return a.trunk.id < b.trunk.id
	end)

	local routes: { any } = {}
	local places: { Place } = {}
	local trees: { TreeRec } = {}
	local nextId = C.idBase
	local function accept(rec: { [string]: any }, place: Place)
		table.insert(routes, rec)
		table.insert(places, place)
		addSamples(ctx.mine, rec.id, samplesOf(rec))
		nextId += 1
	end

	for _, tr in trunks do
		local trunk = tr.trunk
		local rand = BranchNooks.rngOf(`branch nooks {trunk.id}`)
		local tree: TreeRec = { trunk = trunk.id, nooks = {}, hangouts = {}, spurs = {} }
		local used: { [number]: boolean } = {} -- boughs that already have a nook or hangout
		local big = if #tr.boughs >= C.bigTree then 1 else 0
		local calm = C.calm[trunk.name]
		local maxNooks = if calm then calm.nooks else C.nooksPerTree + big
		local maxSpurs = if calm then calm.spurs else C.spursPerTree + big

		-- a route leaving bough `b` at sample `s` (t `st`) turning `turn` degrees (signed) from its heading
		local function curled(b: any, s: V3, st: number, turn: number, len: number, rise: number, curl: number)
			local hx, hz = headingAt(reg, b, st)
			local dx, dz = rotate(hx, hz, turn)
			return pointsFrom(s, dx, dz, len, rise, 0, curl)
		end
		-- the knot-hole for a cup ending at `e` (the motor's point): in the nearer wood, the trunk's bark round toward the
		-- bough it left, or the bough's own bark beside the cup; its middle and level normal out of the wood
		local function knotHole(b: any, e: V3, side: number): { number }
			local fx, fy, fz = e.x, e.y + C.lift, e.z -- the feet in the cup
			local y = fy + C.stashUp
			local a, ta = trunkAt(reg, trunk, y)
			local R = BranchNooks.barkRadius(trunk, ta)
			local ang = math.atan2(e.x - a.x, e.z - a.z) - side * C.stashSide / math.max(R, 0.5)
			local nx, nz = math.sin(ang), math.cos(ang)
			local onTrunk = { a.x + nx * R, y, a.z + nz * R, nx, nz }
			-- the bough: its sample nearest the cup, the bark facing the cup
			local best, bd = nil, math.huge
			for _, q in reg:samples(b) do
				local dd = (q.x - e.x) ^ 2 + (q.y - e.y) ^ 2 + (q.z - e.z) ^ 2
				if dd < bd then
					best, bd = q, dd
				end
			end
			local q = best :: V3
			local qx, qz = e.x - q.x, e.z - q.z
			local ql = math.sqrt(qx * qx + qz * qz)
			local pick = onTrunk
			if ql > 1e-6 then
				local rb = C.boughBark
				local onBough = { q.x + qx / ql * rb, q.y + C.lift * 0.6, q.z + qz / ql * rb, qx / ql, qz / ql }
				local function far(h: { number }): number
					return (h[1] - fx) ^ 2 + (h[2] - fy) ^ 2 + (h[3] - fz) ^ 2
				end
				if far(onBough) < far(onTrunk) then
					pick = onBough
				end
			end
			return { r4(pick[1]), r4(pick[2]), r4(pick[3]), r4(pick[4]), r4(pick[5]) }
		end
		local function crook(kind: string, b: any, outs: { number }, turns: { number }, len: number, sides: { number })
			for _, out in outs do
				local s, st = pastCollar(reg, b, trunk, out, 0.6)
				if s == nil or st == nil then
					return false
				end
				for _, side in sides do
					for _, turn in turns do
						local rise = if kind == "nook" then -C.nookDrop else 0
						local pts = curled(b, s, st, side * turn, len, rise, side * 18)
						pts[1] = { s.x, s.y, s.z }
						local rec = record(nextId, `{kind} off route {b.id}`, pts, C.nookSurface)
						local smp = samplesOf(rec)
						-- (a nook's cup: no other route within the stash's reach of its end, its own bough and the
						-- trunk's axis included, so the stash is used from the cup and nowhere else)
						local tail = smp[#smp]
						local cupClear = kind ~= "nook"
							or nearestOther(ctx.hash, tail, {}) >= C.stashReach + C.stashMargin
						if cupClear and keeps(ctx, smp, b, trunk) then
							local e = smp[#smp]
							local place: Place = {
								route = rec.id,
								kind = kind,
								trunk = trunk.id,
								parent = b.id,
								parentT = st,
								at = { r4(e.x), r4(e.y), r4(e.z) },
								out = outOf(reg, trunk, e),
								seatFrom = if kind == "nook" then C.nookSeatFrom else C.hangoutSeatFrom,
							}
							if kind == "nook" then
								place.stash = knotHole(b, e, side)
							end
							accept(rec, place)
							return true
						end
					end
				end
			end
			return false
		end

		-- nooks: lowest boughs first, a side drawn per bough
		for _, bf in tr.boughs do
			if #tree.nooks >= maxNooks then
				break
			end
			local first = if rand() < 0.5 then 1 else -1
			if crook("nook", bf.route, C.nookOuts, C.nookTurns, C.nookLen, { first, -first }) then
				used[bf.route.id] = true
				table.insert(tree.nooks, nextId - 1)
			end
		end

		-- hangouts: at the wider forks (the gap round the trunk to the next bough at about that height)
		local cap = if calm then calm.hangouts else C.hangoutsPerTree + big
		local foot = reg:foot(trunk)
		local function bearing(f: any): number
			return math.deg(math.atan2(f.outward.x or f.outward[1], f.outward.z or f.outward[3]))
		end
		for _, bf in tr.boughs do
			if #tree.hangouts >= cap then
				break
			end
			if used[bf.route.id] then
				continue
			end
			local mine = bearing(bf.fork)
			-- the gap clockwise (+1) and anticlockwise (-1) to the nearest bough leaving within 6 studs of its height
			local gaps = { [1] = 360, [-1] = 360 }
			for _, other in tr.boughs do
				if other ~= bf and math.abs(other.fork.height - bf.fork.height) < 6 then
					local d = (bearing(other.fork) - mine) % 360
					gaps[1] = math.min(gaps[1], d)
					gaps[-1] = math.min(gaps[-1], 360 - d)
				end
			end
			local sides = {}
			for _, side in { 1, -1 } do
				if gaps[side] >= C.hangoutGap then
					table.insert(sides, side)
				end
			end
			if #sides == 2 and gaps[-1] > gaps[1] then
				sides = { -1, 1 }
			end
			if #sides > 0 and crook("hangout", bf.route, C.hangoutOuts, C.hangoutTurns, C.hangoutLen, sides) then
				used[bf.route.id] = true
				table.insert(tree.hangouts, nextId - 1)
			end
		end
		local _ = foot

		-- spurs: off the middle of the long boughs, the longest first
		local long = {}
		for _, bf in tr.boughs do
			if bf.route.length >= C.spurMinParent then
				table.insert(long, bf)
			end
		end
		table.sort(long, function(a, b)
			if a.route.length ~= b.route.length then
				return a.route.length > b.route.length
			end
			return a.route.id < b.route.id
		end)
		for _, bf in long do
			if #tree.spurs >= maxSpurs then
				break
			end
			local b = bf.route
			local at = C.spurFrom + (C.spurTo - C.spurFrom) * rand()
			local s, st = boughSample(reg, b, at * b.length)
			local first = if rand() < 0.5 then 1 else -1
			local done = false
			for _, side in { first, -first } do
				for k, ang in C.spurAngles do
					local hx, hz = headingAt(reg, b, st)
					local dx, dz = rotate(hx, hz, side * ang)
					local pts = pointsFrom(s, dx, dz, C.spurLens[k], C.spurRise, C.spurArch, -side * C.spurCurl)
					pts[1] = { s.x, s.y, s.z }
					local rec = record(nextId, `spur off route {b.id}`, pts, b.surfaceRadius * C.spurSurface)
					local smp = samplesOf(rec)
					if keeps(ctx, smp, b, trunk) then
						local e = smp[#smp]
						accept(rec, {
							route = rec.id,
							kind = "spur",
							trunk = trunk.id,
							parent = b.id,
							parentT = st,
							at = { r4(e.x), r4(e.y), r4(e.z) },
							out = outOf(reg, trunk, e),
						})
						table.insert(tree.spurs, nextId - 1)
						done = true
						break
					end
				end
				if done then
					break
				end
			end
		end
		if #tree.nooks + #tree.hangouts + #tree.spurs > 0 then
			table.insert(trees, tree)
		end
	end
	return { routes = routes, places = places, trees = trees, rejected = ctx.why }
end

-- lookups at run time ----------------------------------------------------------------------------------------------

export type Nooks = {
	places: { Place },
	routes: { any },
	place: (routeId: number) -> Place?,
	stashes: () -> { Place },
	stashNear: (x: number, y: number, z: number, reach: number?) -> Place?,
	seatAt: (routeId: number, t: number) -> Place?,
	entranceNear: (registry: any, routeId: number, t: number, reach: number?) -> Place?,
	tree: (trunk: number) -> { Place },
}

function BranchNooks.new(compiled: Compiled?): Nooks
	local places: { Place } = if compiled then compiled.places else {}
	local byRoute: { [number]: Place } = {}
	local byParent: { [number]: { Place } } = {}
	local byTrunk: { [number]: { Place } } = {}
	local stashes: { Place } = {}
	for _, p in places do
		byRoute[p.route] = p
		local list = byParent[p.parent]
		if not list then
			list = {}
			byParent[p.parent] = list
		end
		table.insert(list, p)
		local tl = byTrunk[p.trunk]
		if not tl then
			tl = {}
			byTrunk[p.trunk] = tl
		end
		table.insert(tl, p)
		if p.stash then
			table.insert(stashes, p)
		end
	end
	local self: Nooks = {
		places = places,
		routes = if compiled then compiled.routes else {},
		place = function(routeId: number): Place?
			return byRoute[routeId]
		end,
		stashes = function(): { Place }
			return stashes
		end,
		stashNear = function(x: number, y: number, z: number, reach: number?): Place?
			local r = reach or C.stashReach
			local best, bd = nil, r * r
			for _, p in stashes do
				local s = p.at
				local d = (s[1] - x) ^ 2 + (s[2] - y) ^ 2 + (s[3] - z) ^ 2
				if d <= bd then
					best, bd = p, d
				end
			end
			return best
		end,
		seatAt = function(routeId: number, t: number): Place?
			local p = byRoute[routeId]
			if p and p.seatFrom and t >= p.seatFrom then
				return p
			end
			return nil
		end,
		entranceNear = function(registry: any, routeId: number, t: number, reach: number?): Place?
			local list = byParent[routeId]
			if list == nil then
				return nil
			end
			local route = registry:get(routeId)
			if route == nil then
				return nil
			end
			local r = reach or 1.5
			for _, p in list do
				if p.kind ~= "spur" and math.abs(p.parentT - t) * route.length <= r then
					return p
				end
			end
			return nil
		end,
		tree = function(trunk: number): { Place }
			return byTrunk[trunk] or {}
		end,
	}
	return self
end

return BranchNooks
