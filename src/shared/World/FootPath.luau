--!strict
-- ReplicatedStorage.Shared.World.FootPath
-- A way on foot between any two points of the town that never goes through a building or the river.
-- The people here are kinematic: nothing stops a walker at a wall, so whoever sends one somewhere must
-- hand them a path that goes round. The sidewalk graph (Server/Actors/Nav) only knows the pavements,
-- and a good part of the town does not stand on one (the police station yard, shop floors, drives,
-- the park): this is the fallback for everyone and everywhere else (the bite-to-hospital sequence:
-- a walk in from off the pavements, the ambulance crew's walk round a house, the walk home).
--   * The building boxes of World/Colliders are grown by the walker's radius and drawn onto a grid
--     once (CELL studs); a cell any grown box touches is closed, so every step between two open
--     neighbours is clear by construction (a diagonal step needs both cells beside it open too).
--   * `isBlocked(x, z)` closes more ground (the river); it is asked once per cell and remembered,
--     and only inside `blockedBox` when one is given (a line that stays outside it is never sampled).
--   * A point inside a box (a shop worker on the shop floor, a patient's bed) leaves, or is reached,
--     straight through the nearest wall of that box only.
--   * A* over the open cells (the estimate weighted by GREED, so it heads for the goal), then the
--     chain of cells is pulled straight wherever the direct line is clear (an exact segment test
--     against the grown boxes; the furthest clear point is found by halving, a dozen tests a leg).
--   * A search that has opened `maxNodes` cells gives up and returns nil: the caller always has
--     another way (an ambulance, a place out of sight), so a search can never hold up a frame for long
--     (MAX_NODES cells is about 15 ms under Lune; most searches open a few hundred).
-- Interface: new(opts) -> Finder; find(finder, x0, z0, x1, z1, opts?) -> ({ {x, z} }?, length)
--   (the waypoints after the start, the goal last); clear(finder, x0, z0, x1, z1, skip?) -> boolean;
--   length(x0, z0, points) -> studs; CELL, RADIUS, MAX_NODES
-- Pure; studs. No side effects on require.

local Colliders = require("./Colliders")

export type Opts = {
	colliders: Colliders.Colliders,
	bounds: { minX: number, maxX: number, minZ: number, maxZ: number },
	isBlocked: ((x: number, z: number) -> boolean)?, -- more closed ground (water)
	blockedBox: { minX: number, maxX: number, minZ: number, maxZ: number }?, -- where isBlocked can be true
	cell: number?,
	radius: number?,
	maxNodes: number?,
	minHeight: number?, -- boxes lower than this (studs) can be stepped over: not obstacles
}

export type FindOpts = {
	maxNodes: number?,
	maxLength: number?, -- studs: a longer way than this is no way
}

export type Finder = {
	cell: number,
	radius: number,
	maxNodes: number,
	bounds: { minX: number, maxX: number, minZ: number, maxZ: number },
	boxes: { Colliders.Box }, -- the obstacles
	closed: { [number]: boolean }, -- cells a grown box touches
	wet: { [number]: boolean }, -- cells isBlocked closes (remembered)
	isBlocked: ((x: number, z: number) -> boolean)?,
	blockedBox: { minX: number, maxX: number, minZ: number, maxZ: number }?,
	searches: number,
	opened: number, -- cells opened by the last search
}

local FootPath = {}

FootPath.CELL = 6 -- studs
FootPath.RADIUS = 1.5 -- studs: a walker's half width
FootPath.MAX_NODES = 4000
FootPath.GREED = 1.5 -- weight on the distance-to-go estimate
local MIN_HEIGHT = 3 -- studs

local OFFSET, SPAN = 4096, 8192

local function key(ix: number, iz: number): number
	return (ix + OFFSET) * SPAN + (iz + OFFSET)
end

function FootPath.new(opts: Opts): Finder
	local cell = opts.cell or FootPath.CELL
	local radius = opts.radius or FootPath.RADIUS
	local minHeight = opts.minHeight or MIN_HEIGHT
	local finder: Finder = {
		cell = cell,
		radius = radius,
		maxNodes = opts.maxNodes or FootPath.MAX_NODES,
		bounds = opts.bounds,
		boxes = {},
		closed = {},
		wet = {},
		isBlocked = opts.isBlocked,
		blockedBox = opts.blockedBox,
		searches = 0,
		opened = 0,
	}
	for _, b in opts.colliders.boxes do
		if b.eave - b.y0 >= minHeight then
			table.insert(finder.boxes, b)
			-- a cell is the square of side `cell` round its centre (ix * cell, iz * cell)
			local half = cell / 2
			local ix0 = math.ceil((b.cx - b.hw - radius - half) / cell)
			local ix1 = math.floor((b.cx + b.hw + radius + half) / cell)
			local iz0 = math.ceil((b.cz - b.hd - radius - half) / cell)
			local iz1 = math.floor((b.cz + b.hd + radius + half) / cell)
			for ix = ix0, ix1 do
				for iz = iz0, iz1 do
					finder.closed[key(ix, iz)] = true
				end
			end
		end
	end
	return finder
end

local function open(f: Finder, ix: number, iz: number): boolean
	local k = key(ix, iz)
	if f.closed[k] then
		return false
	end
	local x, z = ix * f.cell, iz * f.cell
	local b = f.bounds
	if x < b.minX or x > b.maxX or z < b.minZ or z > b.maxZ then
		return false
	end
	local isBlocked = f.isBlocked
	local box = f.blockedBox
	if isBlocked and (box == nil or (x >= box.minX and x <= box.maxX and z >= box.minZ and z <= box.maxZ)) then
		local wet = f.wet[k]
		if wet == nil then
			-- the centre and the four corners: a cell half in the river is closed
			local h = f.cell / 2
			wet = isBlocked(x, z)
				or isBlocked(x - h, z - h)
				or isBlocked(x + h, z - h)
				or isBlocked(x - h, z + h)
				or isBlocked(x + h, z + h)
			f.wet[k] = wet
		end
		if wet then
			return false
		end
	end
	return true
end

-- the boxes (grown by the radius) that hold a point: a walker who starts or ends inside one may
-- cross that one's wall
local function boxesAt(f: Finder, x: number, z: number): { [Colliders.Box]: boolean }?
	local out: { [Colliders.Box]: boolean }? = nil
	for _, b in f.boxes do
		if math.abs(x - b.cx) < b.hw + f.radius and math.abs(z - b.cz) < b.hd + f.radius then
			local set = out or {}
			set[b] = true
			out = set
		end
	end
	return out
end

-- Does the segment miss the box grown by r? (the slab test)
local function misses(b: Colliders.Box, r: number, x0: number, z0: number, x1: number, z1: number): boolean
	local t0, t1 = 0, 1
	local dx, dz = x1 - x0, z1 - z0
	local minX, maxX = b.cx - b.hw - r, b.cx + b.hw + r
	local minZ, maxZ = b.cz - b.hd - r, b.cz + b.hd + r
	if math.abs(dx) < 1e-9 then
		if x0 <= minX or x0 >= maxX then
			return true
		end
	else
		local a, c = (minX - x0) / dx, (maxX - x0) / dx
		if a > c then
			a, c = c, a
		end
		t0, t1 = math.max(t0, a), math.min(t1, c)
		if t0 >= t1 then
			return true
		end
	end
	if math.abs(dz) < 1e-9 then
		if z0 <= minZ or z0 >= maxZ then
			return true
		end
	else
		local a, c = (minZ - z0) / dz, (maxZ - z0) / dz
		if a > c then
			a, c = c, a
		end
		t0, t1 = math.max(t0, a), math.min(t1, c)
		if t0 >= t1 then
			return true
		end
	end
	return false
end

-- clear(finder, x0, z0, x1, z1, skip?): can a walker go straight from one point to the other? No
-- building on the way (the boxes in `skip` do not count) and no closed ground.
function FootPath.clear(
	f: Finder,
	x0: number,
	z0: number,
	x1: number,
	z1: number,
	skip: { [Colliders.Box]: boolean }?
): boolean
	local r = f.radius
	for _, b in f.boxes do
		if not (skip and skip[b]) and not misses(b, r, x0, z0, x1, z1) then
			return false
		end
	end
	local isBlocked = f.isBlocked
	local box = f.blockedBox
	if
		isBlocked
		and (
			box == nil
			or not (
				math.max(x0, x1) < box.minX
				or math.min(x0, x1) > box.maxX
				or math.max(z0, z1) < box.minZ
				or math.min(z0, z1) > box.maxZ
			)
		)
	then
		local dx, dz = x1 - x0, z1 - z0
		local n = math.max(1, math.ceil(math.sqrt(dx * dx + dz * dz) / (f.cell / 2)))
		for i = 0, n do
			if isBlocked(x0 + dx * i / n, z0 + dz * i / n) then
				return false
			end
		end
	end
	return true
end

function FootPath.length(x0: number, z0: number, points: { { number } }): number
	local total, px, pz = 0, x0, z0
	for _, p in points do
		total += math.sqrt((p[1] - px) ^ 2 + (p[2] - pz) ^ 2)
		px, pz = p[1], p[2]
	end
	return total
end

-- The open cells a point can step onto: those within a few cells with a straight clear line (through
-- the point's own box only). Nearest first, a handful at most.
local function doors(
	f: Finder,
	x: number,
	z: number,
	skip: { [Colliders.Box]: boolean }?
): { { ix: number, iz: number, d: number } }
	local cell = f.cell
	local reach = 4
	if skip then
		-- from inside a building: far enough to get past its nearest wall
		for b in skip do
			local out = math.min(b.hw - math.abs(x - b.cx), b.hd - math.abs(z - b.cz))
			reach = math.max(reach, math.ceil((out + 2 * f.radius) / cell) + 2)
		end
	end
	local cx, cz = math.floor(x / cell + 0.5), math.floor(z / cell + 0.5)
	local found: { { ix: number, iz: number, d: number } } = {}
	for ix = cx - reach, cx + reach do
		for iz = cz - reach, cz + reach do
			if open(f, ix, iz) then
				local px, pz = ix * cell, iz * cell
				table.insert(found, { ix = ix, iz = iz, d = math.sqrt((px - x) ^ 2 + (pz - z) ^ 2) })
			end
		end
	end
	table.sort(found, function(a, b)
		if a.d ~= b.d then
			return a.d < b.d
		elseif a.ix ~= b.ix then
			return a.ix < b.ix
		end
		return a.iz < b.iz
	end)
	local out = {}
	for _, c in found do
		if FootPath.clear(f, x, z, c.ix * cell, c.iz * cell, skip) then
			table.insert(out, c)
			if #out >= 6 then
				break
			end
		end
	end
	return out
end

-- a binary heap of cell keys ordered by priority
local function push(heap: { number }, prio: { number }, k: number, p: number)
	local i = #heap + 1
	heap[i], prio[i] = k, p
	while i > 1 do
		local parent = i // 2
		if prio[parent] <= p then
			break
		end
		heap[i], prio[i] = heap[parent], prio[parent]
		heap[parent], prio[parent] = k, p
		i = parent
	end
end

local function pop(heap: { number }, prio: { number }): number
	local n = #heap
	local top = heap[1]
	local k, p = heap[n], prio[n]
	heap[n], prio[n] = nil, nil
	n -= 1
	if n > 0 then
		local i = 1
		while true do
			local child = i * 2
			if child > n then
				break
			end
			if child < n and prio[child + 1] < prio[child] then
				child += 1
			end
			if prio[child] >= p then
				break
			end
			heap[i], prio[i] = heap[child], prio[child]
			i = child
		end
		heap[i], prio[i] = k, p
	end
	return top
end

local STEPS = {
	{ 1, 0, 1 },
	{ -1, 0, 1 },
	{ 0, 1, 1 },
	{ 0, -1, 1 },
	{ 1, 1, math.sqrt(2) },
	{ 1, -1, math.sqrt(2) },
	{ -1, 1, math.sqrt(2) },
	{ -1, -1, math.sqrt(2) },
}

-- find(finder, x0, z0, x1, z1, opts?): the waypoints from (x0, z0) to (x1, z1), the goal last, and
-- the length of the walk; nil when there is no way (or none within the budget or the length asked).
function FootPath.find(
	f: Finder,
	x0: number,
	z0: number,
	x1: number,
	z1: number,
	opts: FindOpts?
): ({ { number } }?, number)
	f.searches += 1
	f.opened = 0
	local maxLength = if opts and opts.maxLength then opts.maxLength else math.huge
	local skip: { [Colliders.Box]: boolean }? = boxesAt(f, x0, z0)
	local atGoal = boxesAt(f, x1, z1)
	if atGoal then
		local set = skip or {}
		for b in atGoal do
			set[b] = true
		end
		skip = set
	end
	local direct = math.sqrt((x1 - x0) ^ 2 + (z1 - z0) ^ 2)
	local bounds = f.bounds
	if direct > maxLength or x1 < bounds.minX or x1 > bounds.maxX or z1 < bounds.minZ or z1 > bounds.maxZ then
		return nil, 0 -- too far, or off the edge of the world
	end
	if FootPath.clear(f, x0, z0, x1, z1, skip) then
		return { { x1, z1 } }, direct
	end
	local cell = f.cell
	local from, to = doors(f, x0, z0, skip), doors(f, x1, z1, skip)
	if #from == 0 or #to == 0 then
		return nil, 0
	end
	local exit: { [number]: number } = {} -- cell key -> studs from that cell to the goal
	for _, c in to do
		exit[key(c.ix, c.iz)] = c.d
	end
	-- the estimate is weighted: the search heads for the goal instead of fanning out over the whole
	-- open town (the chain is pulled straight afterwards, so a slightly longer chain costs nothing)
	local function h(ix: number, iz: number): number
		local dx, dz = math.abs(ix * cell - x1), math.abs(iz * cell - z1)
		return (math.max(dx, dz) + (math.sqrt(2) - 1) * math.min(dx, dz)) * FootPath.GREED
	end
	local g: { [number]: number } = {}
	local came: { [number]: number } = {}
	local done: { [number]: boolean } = {}
	local heap: { number }, prio: { number } = {}, {}
	for _, c in from do
		local k = key(c.ix, c.iz)
		g[k] = c.d
		push(heap, prio, k, c.d + h(c.ix, c.iz))
	end
	local budget = if opts and opts.maxNodes then opts.maxNodes else f.maxNodes
	local last: number? = nil
	while #heap > 0 do
		local k = pop(heap, prio)
		if done[k] then
			continue
		end
		done[k] = true
		f.opened += 1
		if exit[k] ~= nil then
			last = k
			break
		end
		if f.opened >= budget or g[k] > maxLength then
			break
		end
		local ix, iz = k // SPAN - OFFSET, k % SPAN - OFFSET
		local gk = g[k]
		for _, s in STEPS do
			local nx, nz = ix + s[1], iz + s[2]
			local nk = key(nx, nz)
			if not done[nk] and open(f, nx, nz) then
				-- no cutting a corner between two closed cells
				if s[1] ~= 0 and s[2] ~= 0 and not (open(f, ix + s[1], iz) and open(f, ix, iz + s[2])) then
					continue
				end
				local ng = gk + s[3] * cell
				local old = g[nk]
				if old == nil or ng < old - 1e-9 then
					g[nk] = ng
					came[nk] = k
					push(heap, prio, nk, ng + h(nx, nz))
				end
			end
		end
	end
	if last == nil then
		return nil, 0
	end
	-- the chain of cell centres, start to goal
	local chain: { { number } } = { { x1, z1 } }
	local c: number? = last
	while c do
		table.insert(chain, 1, { (c // SPAN - OFFSET) * cell, (c % SPAN - OFFSET) * cell })
		c = came[c]
	end
	-- pull it straight: from each kept point, walk on to the furthest later point in a clear line.
	-- chain[i] is always reachable from the point before it (a step between open neighbours, or a
	-- door checked above); the furthest clear one after it is found by halving.
	local points: { { number } } = {}
	local px, pz = x0, z0
	local i = 1
	local n = #chain
	while i <= n do
		local best = i
		if FootPath.clear(f, px, pz, chain[n][1], chain[n][2], skip) then
			best = n
		else
			local lo, hi = i, n -- chain[lo] is clear, chain[hi] is not
			while hi - lo > 1 do
				local mid = (lo + hi) // 2
				if FootPath.clear(f, px, pz, chain[mid][1], chain[mid][2], skip) then
					lo = mid
				else
					hi = mid
				end
			end
			best = lo
		end
		table.insert(points, chain[best])
		px, pz = chain[best][1], chain[best][2]
		i = best + 1
	end
	local length = FootPath.length(x0, z0, points)
	if length > maxLength then
		return nil, 0
	end
	return points, length
end

return FootPath
