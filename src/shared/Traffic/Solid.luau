--!strict
-- ReplicatedStorage.Shared.Traffic.Solid
-- Cars as solid boxes, in numbers (owner's playtest 2026-11-18: "I did run right through a car"). The town's cars are
-- server state drawn on each client (Traffic/Ghost); nothing made them solid. A car's solid is its logical box
-- (Traffic/Boxes: the box the fatal test sweeps and the drawn car fills), standing on the road, turned to its heading.
-- Three users meet the same boxes:
--   * the squirrel's motor on its own client (Client/World/ClientWorld via squirrelWorld): a car is a wall it cannot
--     run into, at the motor's own body (the box BODY_HALF to each side, from STEP to BODY_TOP over the feet; the narrow
--     core), and its roof is ground, found by the same ray down from RAY_ABOVE over the feet as the town's ground
--     (v5.4 traffic.md §7: "Standing on roofs", vehicleHitboxAt in getGroundAt; vehicles do not carry the squirrel: a
--     moving one slides out from under it). The cars there are the ones that client draws (Ghost.render fills the set).
--   * the server's movement validator (Server/Movement/ValidatorWorld): its wall and floor rays meet the boxes the
--     traffic service keeps (Server/Traffic/TrafficService.solids): a wall only where a car has stood still long
--     enough for every client to draw it there, a floor wherever a client may still draw a car.
--   * a person's body meets the ghost's invisible RootPart, the same box as a part (Traffic/Ghost.solidify).
-- A ray that starts inside a box does not meet it (as Roblox's raycasts): a body a car stopped on, or appeared over,
-- walks out, and is never judged to have gone through.
-- Interface: hull(kind, x, base, z, yaw, trail?) -> Hull; box(width, length, height, x, base, z, yaw, trail?) -> Hull;
--   inside(h, x, z); overlaps(h, x, z, half, y0, y1); enters(h, ox, oy, oz, dx, dy, dz) -> t?;
--   newSet() -> Set; clear(set); add(set, h); blocked(set, x, z, half, y0, y1, skip?); roof(set, x, z, from) -> top?;
--   ray(set, ox, oy, oz, dx, dy, dz) -> boolean; body(set, x, z, y, half, skip?); core(set, x, z, y, skip?);
--   caught(set, x, z, y, into) (the cars the body's core is already inside); depth(a, b) (plan overlap of two boxes);
--   pushes(set, from, to) (a driven vehicle's footprint moving into, or deeper into, a car);
--   squirrelWorld(world, set) -> world (a copy whose groundAt, blocked, blockedCore and blockedHalf meet the set, and
--   whose wallsFrom(x, z, y) lets a body out of a car it is already inside);
--   BODY (the squirrel motor's body: Client/World/ClientWorld's numbers)
-- Pure: no engine calls, no side effects on require. Studs, HTML yaw (a car faces (sin yaw, cos yaw)).

local Boxes = require("./Boxes")

local Solid = {}

-- The squirrel motor's body as Client/World/ClientWorld measures it (a spec holds the two to the same numbers).
Solid.BODY = table.freeze({
	STEP = 0.75, -- what the body steps onto: the wall box starts this far over the feet
	TOP = 1.7, -- the top of the body's box over the feet
	HALF = 1.0, -- the box's half-width
	CORE = 0.35, -- the narrow probe's radius (from STEP to STEP + 2 CORE)
	RAY_ABOVE = 1.5, -- the ground ray starts this far over the feet
})

export type Hull = {
	x: number, -- the footprint's centre
	z: number,
	base: number, -- the bottom of the box (the road under it)
	top: number,
	c: number, -- cos and sin of the heading: across = c dx - s dz, along = s dx + c dz
	s: number,
	hw: number, -- half the width (across)
	hl: number, -- half the length (along)
	reach: number, -- the footprint's circumradius, for the quick reject
}

export type Set = { hulls: { Hull }, n: number }

-- box(width, length, height, x, base, z, yaw, trail?): the box of a vehicle that size whose footprint's centre is (x, z)
-- on ground `base`. `trail` (studs) stretches it that far behind (where a client drawing it late may still show it).
function Solid.box(
	width: number,
	length: number,
	height: number,
	x: number,
	base: number,
	z: number,
	yaw: number,
	trail: number?
): Hull
	local c, s = math.cos(yaw), math.sin(yaw)
	local back = math.max(trail or 0, 0)
	local hw, hl = width / 2, length / 2 + back / 2
	-- the centre moves half the trail back along the heading
	local cx, cz = x - s * back / 2, z - c * back / 2
	return {
		x = cx,
		z = cz,
		base = base,
		top = base + height,
		c = c,
		s = s,
		hw = hw,
		hl = hl,
		reach = math.sqrt(hw * hw + hl * hl),
	}
end

-- hull(kind, x, base, z, yaw, trail?): the logical box of a vehicle of that kind (Traffic/Boxes).
function Solid.hull(kind: string, x: number, base: number, z: number, yaw: number, trail: number?): Hull
	local b = Boxes.get(kind)
	return Solid.box(b.width, b.length, b.height, x, base, z, yaw, trail)
end

-- inside(h, x, z): is (x, z) within the footprint?
function Solid.inside(h: Hull, x: number, z: number): boolean
	local dx, dz = x - h.x, z - h.z
	return math.abs(h.c * dx - h.s * dz) < h.hw and math.abs(h.s * dx + h.c * dz) < h.hl
end

-- overlaps(h, x, z, half, y0, y1): does the upright square box `half` to each side of (x, z), from y0 to y1, overlap the
-- hull? (Separating axes in plan: the world's two and the hull's two; and the heights.)
function Solid.overlaps(h: Hull, x: number, z: number, half: number, y0: number, y1: number): boolean
	if y1 <= h.base or y0 >= h.top then
		return false
	end
	local dx, dz = x - h.x, z - h.z
	local ac, as = math.abs(h.c), math.abs(h.s)
	if math.abs(dx) >= half + h.hw * ac + h.hl * as then
		return false
	end
	if math.abs(dz) >= half + h.hw * as + h.hl * ac then
		return false
	end
	local spread = half * (ac + as)
	if math.abs(h.c * dx - h.s * dz) >= h.hw + spread then
		return false
	end
	return math.abs(h.s * dx + h.c * dz) < h.hl + spread
end

-- enters(h, ox, oy, oz, dx, dy, dz) -> t?: where (0 < t <= 1) the segment origin -> origin + d first enters the box,
-- or nil (it misses, or it starts inside: Roblox's raycasts do not meet a part they start in).
function Solid.enters(h: Hull, ox: number, oy: number, oz: number, dx: number, dy: number, dz: number): number?
	local rx, rz = ox - h.x, oz - h.z
	-- the segment in the hull's frame: a (across), y (up), b (along)
	local a0, b0 = h.c * rx - h.s * rz, h.s * rx + h.c * rz
	local da, db = h.c * dx - h.s * dz, h.s * dx + h.c * dz
	local enter, exit = -math.huge, math.huge
	for axis = 1, 3 do
		local p, d, lo, hi
		if axis == 1 then
			p, d, lo, hi = a0, da, -h.hw, h.hw
		elseif axis == 2 then
			p, d, lo, hi = oy, dy, h.base, h.top
		else
			p, d, lo, hi = b0, db, -h.hl, h.hl
		end
		if math.abs(d) < 1e-12 then
			if p <= lo or p >= hi then
				return nil
			end
		else
			local t0, t1 = (lo - p) / d, (hi - p) / d
			if t0 > t1 then
				t0, t1 = t1, t0
			end
			enter = math.max(enter, t0)
			exit = math.min(exit, t1)
			if enter >= exit then
				return nil
			end
		end
	end
	if enter <= 0 or enter > 1 then
		return nil -- starts inside (or the box is behind or beyond the segment)
	end
	return enter
end

-- depth(a, b): how far two boxes overlap in plan, along the axis they overlap least (separating axes: the two boxes'
-- four), or 0 when they are apart or apart in height. Studs.
function Solid.depth(a: Hull, b: Hull): number
	if a.top <= b.base or a.base >= b.top then
		return 0
	end
	local dx, dz = b.x - a.x, b.z - a.z
	local least = math.huge
	-- each box's across (c, -s) and along (s, c) unit vectors in (x, z)
	for axis = 1, 4 do
		local h = if axis <= 2 then a else b
		local ux, uz
		if axis % 2 == 1 then
			ux, uz = h.c, -h.s
		else
			ux, uz = h.s, h.c
		end
		local ra = a.hw * math.abs(ux * a.c - uz * a.s) + a.hl * math.abs(ux * a.s + uz * a.c)
		local rb = b.hw * math.abs(ux * b.c - uz * b.s) + b.hl * math.abs(ux * b.s + uz * b.c)
		local o = ra + rb - math.abs(ux * dx + uz * dz)
		if o <= 0 then
			return 0
		end
		least = math.min(least, o)
	end
	return least
end

-- pushes(set, from, to): does a box moving from `from` to `to` (a driven vehicle's footprint) run into a box of the set,
-- or deeper into one it already overlaps? (A town car drawn over a stopped player's car never locks it in: any move
-- that does not deepen the overlap is free, so it drives out; Client/Controllers/Vehicle.)
function Solid.pushes(set: Set, from: Hull, to: Hull): boolean
	local hulls = set.hulls
	for i = 1, set.n do
		local h = hulls[i]
		local r = h.reach + to.reach
		local dx, dz = to.x - h.x, to.z - h.z
		if dx * dx + dz * dz < r * r then
			local now = Solid.depth(to, h)
			if now > 0 and now > Solid.depth(from, h) + 1e-4 then
				return true
			end
		end
	end
	return false
end

function Solid.newSet(): Set
	return { hulls = {}, n = 0 }
end

-- clear(set): no boxes (the tables are kept for the next fill).
function Solid.clear(set: Set)
	set.n = 0
end

-- add(set, h): one more box (kept until the next clear).
function Solid.add(set: Set, h: Hull)
	set.n += 1
	set.hulls[set.n] = h
end

-- blocked(set, x, z, half, y0, y1, skip?): does the upright box overlap any box of the set (but those in `skip`)?
function Solid.blocked(
	set: Set,
	x: number,
	z: number,
	half: number,
	y0: number,
	y1: number,
	skip: { [Hull]: boolean }?
): boolean
	local hulls = set.hulls
	for i = 1, set.n do
		local h = hulls[i]
		local r = h.reach + half * 1.415
		local dx, dz = x - h.x, z - h.z
		if dx * dx + dz * dz < r * r and not (skip and skip[h]) and Solid.overlaps(h, x, z, half, y0, y1) then
			return true
		end
	end
	return false
end

-- roof(set, x, z, from) -> top?: the highest roof a ray straight down from height `from` at (x, z) meets (a box the ray
-- starts in is not met), or nil.
function Solid.roof(set: Set, x: number, z: number, from: number): number?
	local best: number? = nil
	local hulls = set.hulls
	for i = 1, set.n do
		local h = hulls[i]
		if from > h.top and (best == nil or h.top > best) and Solid.inside(h, x, z) then
			best = h.top
		end
	end
	return best
end

-- ray(set, ox, oy, oz, dx, dy, dz): does the segment meet any box of the set?
function Solid.ray(set: Set, ox: number, oy: number, oz: number, dx: number, dy: number, dz: number): boolean
	local hulls = set.hulls
	local half = math.sqrt(dx * dx + dz * dz) / 2
	local mx, mz = ox + dx / 2, oz + dz / 2
	for i = 1, set.n do
		local h = hulls[i]
		local r = h.reach + half
		local ex, ez = mx - h.x, mz - h.z
		if ex * ex + ez * ez < r * r and Solid.enters(h, ox, oy, oz, dx, dy, dz) ~= nil then
			return true
		end
	end
	return false
end

local BODY = Solid.BODY

-- body(set, x, z, y, half, skip?): the squirrel's body box at half-width `half` over feet y meets a car
-- (ClientWorld.blockedHalf).
function Solid.body(set: Set, x: number, z: number, y: number, half: number, skip: { [Hull]: boolean }?): boolean
	return set.n > 0 and Solid.blocked(set, x, z, half, y + BODY.STEP, y + BODY.TOP, skip)
end

-- core(set, x, z, y, skip?): the body's narrow core over feet y meets a car (ClientWorld.blockedCore).
function Solid.core(set: Set, x: number, z: number, y: number, skip: { [Hull]: boolean }?): boolean
	return set.n > 0 and Solid.blocked(set, x, z, BODY.CORE, y + BODY.STEP, y + BODY.STEP + 2 * BODY.CORE, skip)
end

-- caught(set, x, z, y, into): fills `into` (cleared first) with the cars whose box the body's core over feet y already
-- overlaps (a car that came over the body: it pulled up or appeared on it, the body was handed over or put back under
-- it). The motor's walls leave those out for the step that starts there, so the body walks out of a car the way the
-- validator's rays do (a ray that starts inside a box does not meet it); once the core is out the car is a wall again.
function Solid.caught(set: Set, x: number, z: number, y: number, into: { [Hull]: boolean })
	table.clear(into)
	local y0, y1 = y + BODY.STEP, y + BODY.STEP + 2 * BODY.CORE
	local hulls = set.hulls
	for i = 1, set.n do
		local h = hulls[i]
		if Solid.overlaps(h, x, z, BODY.CORE, y0, y1) then
			into[h] = true
		end
	end
end

-- squirrelWorld(world, set): a copy of a squirrel motor world whose ground and walls also meet the set's cars (read
-- each time they are asked: the set may be refilled every frame). The rest of the world is shared. Its `wallsFrom`
-- (the motors call it where each wall sweep starts) leaves out, for that sweep, every car the body's core is already
-- inside (Solid.caught): a car that came over a squirrel never holds it; it walks out by any side.
function Solid.squirrelWorld(world: any, set: Set): any
	local out = table.clone(world)
	local skip: { [Hull]: boolean } = {}
	local wallsFrom = world.wallsFrom
	out.wallsFrom = function(x: number, z: number, y: number)
		if set.n > 0 then
			Solid.caught(set, x, z, y, skip)
		elseif next(skip) ~= nil then
			table.clear(skip)
		end
		if wallsFrom then
			wallsFrom(x, z, y)
		end
	end
	local groundAt, blocked, blockedCore, blockedHalf =
		world.groundAt, world.blocked, world.blockedCore, world.blockedHalf
	out.groundAt = function(x: number, z: number, refY: number): number
		local g = groundAt(x, z, refY)
		if set.n == 0 then
			return g
		end
		local r = Solid.roof(set, x, z, refY + BODY.RAY_ABOVE)
		return if r and r > g then r else g
	end
	out.blocked = function(x: number, z: number, y: number): boolean
		return Solid.body(set, x, z, y, BODY.HALF, skip) or (blocked ~= nil and blocked(x, z, y))
	end
	-- (a world without the narrow tests keeps its whole wall test for its own walls: only a car is left at the core)
	local baseCore = blockedCore or blocked
	local baseHalf = blockedHalf
		or if blocked
			then function(x: number, z: number, y: number, _half: number): boolean
				return blocked(x, z, y)
			end
			else nil
	out.blockedCore = function(x: number, z: number, y: number): boolean
		return Solid.core(set, x, z, y, skip) or (baseCore ~= nil and baseCore(x, z, y))
	end
	out.blockedHalf = function(x: number, z: number, y: number, half: number): boolean
		return Solid.body(set, x, z, y, half, skip) or (baseHalf ~= nil and baseHalf(x, z, y, half))
	end
	return out
end

return Solid
