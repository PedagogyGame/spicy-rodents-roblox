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
--   * `areas` (opts): the open cells' connected areas are labelled once, at build (each row's runs of open
--     cells, joined to the touching runs of the row before), so a search between two areas that no link
--     joins (a fenced yard, the top of the Lookout, the far bank with no bridge) returns nil at once,
--     without opening a cell: the dearest search there was, for a way that does not exist.
--   * `links` (opts): a way between two points that the grid does not have (a bridge's deck, which the
--     ground closes): { ax, az, bx, bz }, walked straight either way. A search from one area to another
--     goes by the links that join them (the fewest, then the shortest by straight lines), each stretch
--     between them a search of its own (the stretch on each bank is short: a way over the river fits the
--     budget a single search round the river never did).
-- Interface: new(opts) -> Finder; find(finder, x0, z0, x1, z1, opts?) -> ({ {x, z} }?, length)
--   (the waypoints after the start, the goal last); clear(finder, x0, z0, x1, z1, skip?) -> boolean;
--   boxesAt(finder, x, z) -> { [Box]: true }? (the buildings a point is inside); areaAt(finder, x, z) ->
--   number? (the connected area of the open cell holding a point; nil: closed, or no areas);
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
	areas: boolean?, -- label the connected areas at build (see the header)
	links: { { number } }?, -- ways the grid does not have: { ax, az, bx, bz }, walked straight either way
}

export type FindOpts = {
	maxNodes: number?,
	maxLength: number?, -- studs: a longer way than this is no way
	-- a search out of budget gives the way to the cell it reached nearest the goal (when that is PARTIAL_GAIN
	-- nearer than the start): the walker walks it and asks again from there (a long walk in the countryside)
	partial: boolean?,
	hop: boolean?, -- (inside: a stretch between links; it never goes by links itself)
}

export type Finder = {
	cell: number,
	radius: number,
	maxNodes: number,
	bounds: { minX: number, maxX: number, minZ: number, maxZ: number },
	boxes: { Colliders.Box }, -- the obstacles
	colliders: Colliders.Colliders, -- their spatial hash (clear asks it for the boxes near a line)
	tall: { [Colliders.Box]: boolean }, -- the obstacles as a set
	closed: { [number]: boolean }, -- cells a grown box touches
	wet: { [number]: boolean }, -- cells isBlocked closes (remembered)
	isBlocked: ((x: number, z: number) -> boolean)?,
	blockedBox: { minX: number, maxX: number, minZ: number, maxZ: number }?,
	searches: number,
	opened: number, -- cells opened by the last search
	early: number, -- searches that returned nil at once: no link joins the two ends' areas
	-- the connected areas (opts.areas): per row of cells, its runs of open cells (first and last column) and
	-- each run's area; nil without
	rows: { [number]: Row }?,
	links: { Link },
}

-- a row's runs of open cells: starts and ends are columns (ascending), area the run's area
export type Row = { starts: { number }, ends: { number }, area: { number } }
-- a link, with the areas of its two ends (0: an end on a closed cell, or no areas)
export type Link = { ax: number, az: number, bx: number, bz: number, len: number, areaA: number, areaB: number }

local FootPath = {}

FootPath.CELL = 6 -- studs
FootPath.RADIUS = 1.5 -- studs: a walker's half width
FootPath.MAX_NODES = 4000
FootPath.GREED = 1.5 -- weight on the distance-to-go estimate
FootPath.PARTIAL_GAIN = 30 -- studs nearer the goal a partial way (FindOpts.partial) must get
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
		colliders = opts.colliders,
		tall = {},
		closed = {},
		wet = {},
		isBlocked = opts.isBlocked,
		blockedBox = opts.blockedBox,
		searches = 0,
		opened = 0,
		early = 0,
		rows = nil,
		links = {},
	}
	-- the closed runs of each row (opts.areas): column ranges, from the boxes
	local closedRuns: { [number]: { { number } } }? = if opts.areas then {} else nil
	for _, b in opts.colliders.boxes do
		if b.eave - b.y0 >= minHeight then
			table.insert(finder.boxes, b)
			finder.tall[b] = true
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
			if closedRuns then
				for iz = iz0, iz1 do
					local list = closedRuns[iz]
					if list == nil then
						list = {}
						closedRuns[iz] = list
					end
					table.insert(list, { ix0, ix1 })
				end
			end
		end
	end
	if closedRuns then
		FootPath.label(finder, closedRuns)
	end
	local links: { { number } } = opts.links or {}
	for _, l in links do
		table.insert(finder.links, {
			ax = l[1],
			az = l[2],
			bx = l[3],
			bz = l[4],
			len = math.sqrt((l[3] - l[1]) ^ 2 + (l[4] - l[2]) ^ 2),
			areaA = FootPath.areaAt(finder, l[1], l[2]) or 0,
			areaB = FootPath.areaAt(finder, l[3], l[4]) or 0,
		})
	end
	return finder
end

-- is the cell closed ground (isBlocked: the river)? asked once a cell and remembered
local function wetAt(f: Finder, ix: number, iz: number, k: number): boolean
	local isBlocked = f.isBlocked
	if isBlocked == nil then
		return false
	end
	local x, z = ix * f.cell, iz * f.cell
	local box = f.blockedBox
	if box and not (x >= box.minX and x <= box.maxX and z >= box.minZ and z <= box.maxZ) then
		return false
	end
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
	return wet == true
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
	return not wetAt(f, ix, iz, k)
end

-- the columns and rows of the cells inside the bounds (a cell is its centre: ix * cell, iz * cell)
local function extent(f: Finder): (number, number, number, number)
	local b, c = f.bounds, f.cell
	return math.ceil(b.minX / c), math.floor(b.maxX / c), math.ceil(b.minZ / c), math.floor(b.maxZ / c)
end

-- label(finder, closedRuns): the connected areas of the open cells (four-way: a diagonal step needs both cells
-- beside it open, so it joins nothing that four-way steps do not). Each row is cut into runs of open cells by its
-- closed runs (the boxes', `closedRuns`, and the closed ground's, asked of isBlocked only inside blockedBox when
-- there is one); a run joins every run of the row before that shares a column (union-find).
function FootPath.label(f: Finder, closedRuns: { [number]: { { number } } })
	local ix0, ix1, iz0, iz1 = extent(f)
	local box = f.blockedBox
	local wx0, wx1, wz0, wz1 = ix0, ix1, iz0, iz1
	if box then
		local c = f.cell
		wx0, wx1 = math.max(ix0, math.ceil(box.minX / c)), math.min(ix1, math.floor(box.maxX / c))
		wz0, wz1 = math.max(iz0, math.ceil(box.minZ / c)), math.min(iz1, math.floor(box.maxZ / c))
	end
	local parent: { number } = {}
	local function root(i: number): number
		while parent[i] ~= i do
			parent[i] = parent[parent[i]]
			i = parent[i]
		end
		return i
	end
	local rows: { [number]: Row } = {}
	local prev: Row? = nil
	local n = 0
	for iz = iz0, iz1 do
		local runs = table.clone(closedRuns[iz] or {})
		if f.isBlocked and iz >= wz0 and iz <= wz1 then
			local from: number? = nil
			for ix = wx0, wx1 do
				local k = key(ix, iz)
				local wet = not f.closed[k] and wetAt(f, ix, iz, k)
				if wet and from == nil then
					from = ix
				elseif not wet and from ~= nil then
					table.insert(runs, { from, ix - 1 })
					from = nil
				end
			end
			if from ~= nil then
				table.insert(runs, { from, wx1 })
			end
		end
		table.sort(runs, function(a: { number }, b: { number }): boolean
			return a[1] < b[1]
		end)
		local row: Row = { starts = {}, ends = {}, area = {} }
		local function run(a: number, b: number)
			if b >= a then
				n += 1
				parent[n] = n
				table.insert(row.starts, a)
				table.insert(row.ends, b)
				table.insert(row.area, n)
			end
		end
		local at = ix0
		for _, r in runs do
			if r[1] > at then
				run(at, math.min(r[1] - 1, ix1))
			end
			at = math.max(at, r[2] + 1)
			if at > ix1 then
				break
			end
		end
		run(at, ix1)
		-- join the runs of the row before that share a column
		local p = prev
		if p then
			local i, j = 1, 1
			while i <= #p.starts and j <= #row.starts do
				if p.ends[i] < row.starts[j] then
					i += 1
				elseif row.ends[j] < p.starts[i] then
					j += 1
				else
					local a, b = root(p.area[i]), root(row.area[j])
					if a ~= b then
						parent[math.max(a, b)] = math.min(a, b)
					end
					if p.ends[i] < row.ends[j] then
						i += 1
					else
						j += 1
					end
				end
			end
		end
		rows[iz] = row
		prev = row
	end
	for _, row in rows do
		for i, a in row.area do
			row.area[i] = root(a)
		end
	end
	f.rows = rows
end

-- areaAt(finder, x, z): the connected area of the open cell holding (x, z) (its nearest cell centre), or nil (a
-- closed cell, or a finder without areas)
function FootPath.areaAt(f: Finder, x: number, z: number): number?
	local rows = f.rows
	if rows == nil then
		return nil
	end
	local ix, iz = math.floor(x / f.cell + 0.5), math.floor(z / f.cell + 0.5)
	local row = rows[iz]
	if row == nil then
		return nil
	end
	local starts = row.starts
	local lo, hi = 1, #starts
	while lo <= hi do
		local mid = (lo + hi) // 2
		if starts[mid] <= ix then
			lo = mid + 1
		else
			hi = mid - 1
		end
	end
	if hi >= 1 and row.ends[hi] >= ix then
		return row.area[hi]
	end
	return nil
end

-- boxesAt(finder, x, z): the boxes (grown by the radius) that hold a point, or nil in the open: a
-- walker who starts or ends inside one may cross that one's wall (pass the set to `clear` as `skip`)
function FootPath.boxesAt(f: Finder, x: number, z: number): { [Colliders.Box]: boolean }?
	local out: { [Colliders.Box]: boolean }? = nil
	local r = f.radius
	for _, b in Colliders.query(f.colliders, x - r, z - r, x + r, z + r) do
		if f.tall[b] and math.abs(x - b.cx) < b.hw + r and math.abs(z - b.cz) < b.hd + r then
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

local function inside(b: Colliders.Box, x: number, z: number): boolean
	return math.abs(x - b.cx) < b.hw and math.abs(z - b.cz) < b.hd
end

-- clear(finder, x0, z0, x1, z1, skip?): can a walker go straight from one point to the other? No
-- building on the way and no closed ground. A box in `skip` (one an end is in, grown by the walker's half
-- width) does not count when an end is inside its walls (that end leaves or is reached through them); when
-- the end is only beside a wall, the walk may go along that wall but never into it.
function FootPath.clear(
	f: Finder,
	x0: number,
	z0: number,
	x1: number,
	z1: number,
	skip: { [Colliders.Box]: boolean }?
): boolean
	local r = f.radius
	local minX, maxX = math.min(x0, x1) - r, math.max(x0, x1) + r
	local minZ, maxZ = math.min(z0, z1) - r, math.max(z0, z1) + r
	for _, b in Colliders.query(f.colliders, minX, minZ, maxX, maxZ) do
		if not f.tall[b] then
			continue
		end
		if skip and skip[b] then
			if not inside(b, x0, z0) and not inside(b, x1, z1) and not misses(b, 0, x0, z0, x1, z1) then
				return false
			end
		elseif not misses(b, r, x0, z0, x1, z1) then
			return false
		end
	end
	return not FootPath.wetLine(f, x0, z0, x1, z1)
end

-- wetLine(finder, x0, z0, x1, z1): does the straight line cross closed ground (isBlocked: the river)? Sampled every
-- half cell, only where it passes blockedBox.
function FootPath.wetLine(f: Finder, x0: number, z0: number, x1: number, z1: number): boolean
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
				return true
			end
		end
	end
	return false
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

local function dist(ax: number, az: number, bx: number, bz: number): number
	return math.sqrt((bx - ax) ^ 2 + (bz - az) ^ 2)
end

-- The links to cross, in order, from the areas `fromA` (a start's) to the areas `toA` (a goal's): the shortest by
-- straight lines between the link ends (a handful of links: every pair is looked at). Each entry: the link and
-- whether it is crossed from B to A. Nil: no links join them.
local function linkChain(
	f: Finder,
	x0: number,
	z0: number,
	x1: number,
	z1: number,
	fromA: { [number]: boolean },
	toA: { [number]: boolean }
): { { link: Link, back: boolean } }?
	-- nodes: link i crossed forwards (2i - 1) or backwards (2i); cost[node] = straight studs to its landing
	local links = f.links
	local cost: { [number]: number } = {}
	local before: { [number]: number } = {}
	local function ends(node: number): (Link, number, number, number, number, number, number)
		local l = links[(node + 1) // 2]
		if node % 2 == 1 then
			return l, l.ax, l.az, l.bx, l.bz, l.areaA, l.areaB
		end
		return l, l.bx, l.bz, l.ax, l.az, l.areaB, l.areaA
	end
	local queue: { number } = {}
	for node = 1, #links * 2 do
		local l, ax, az, _, _, fromArea, toArea = ends(node)
		if fromArea ~= 0 and toArea ~= 0 and fromA[fromArea] then
			cost[node] = dist(x0, z0, ax, az) + l.len
			table.insert(queue, node)
		end
	end
	local best, bestNode = math.huge, nil
	local done: { [number]: boolean } = {}
	while #queue > 0 do
		local k, at = 1, queue[1]
		for i, node in queue do
			if cost[node] < cost[at] then
				k, at = i, node
			end
		end
		table.remove(queue, k)
		if done[at] then
			continue
		end
		done[at] = true
		local _, _, _, lx, lz, _, landArea = ends(at)
		if toA[landArea] and cost[at] + dist(lx, lz, x1, z1) < best then
			best, bestNode = cost[at] + dist(lx, lz, x1, z1), at
		end
		for node = 1, #links * 2 do
			local l, ax, az, _, _, fromArea, toArea = ends(node)
			if not done[node] and fromArea == landArea and toArea ~= 0 then
				local c = cost[at] + dist(lx, lz, ax, az) + l.len
				if cost[node] == nil or c < cost[node] then
					cost[node], before[node] = c, at
					table.insert(queue, node)
				end
			end
		end
	end
	if bestNode == nil then
		return nil
	end
	local chain = {}
	local node: number? = bestNode
	while node do
		table.insert(chain, 1, { link = links[(node + 1) // 2], back = node % 2 == 0 })
		node = before[node]
	end
	return chain
end

-- the way by `chain`'s links: each stretch between them a search of its own (complete, in budget), each link walked
-- straight; nil when a stretch has none
local function byLinks(
	f: Finder,
	x0: number,
	z0: number,
	x1: number,
	z1: number,
	chain: { { link: Link, back: boolean } },
	opts: FindOpts?
): ({ { number } }?, number)
	local points: { { number } } = {}
	local px, pz = x0, z0
	local opened = 0
	local sub: FindOpts = { maxNodes = if opts then opts.maxNodes else nil, hop = true }
	local function stretch(tx: number, tz: number): boolean
		local part = FootPath.find(f, px, pz, tx, tz, sub)
		opened += f.opened
		if part == nil then
			return false
		end
		for _, p in part do
			table.insert(points, p)
		end
		px, pz = tx, tz
		return true
	end
	local ok = true
	for _, hop in chain do
		local l = hop.link
		local ax, az, bx, bz = l.ax, l.az, l.bx, l.bz
		if hop.back then
			ax, az, bx, bz = bx, bz, ax, az
		end
		ok = stretch(ax, az)
		if not ok then
			break
		end
		table.insert(points, { bx, bz })
		px, pz = bx, bz
	end
	ok = ok and stretch(x1, z1)
	f.opened = opened
	if not ok then
		return nil, 0
	end
	local length = FootPath.length(x0, z0, points)
	if opts and opts.maxLength and length > opts.maxLength then
		return nil, 0
	end
	return points, length
end

-- find(finder, x0, z0, x1, z1, opts?): the waypoints from (x0, z0) to (x1, z1), the goal last, and
-- the length of the walk; nil when there is no way (or none within the budget or the length asked).
-- The third result is true when the way is partial (opts.partial): it ends short of the goal.
function FootPath.find(
	f: Finder,
	x0: number,
	z0: number,
	x1: number,
	z1: number,
	opts: FindOpts?
): ({ { number } }?, number, boolean?)
	f.searches += 1
	f.opened = 0
	local maxLength = if opts and opts.maxLength then opts.maxLength else math.huge
	local skip: { [Colliders.Box]: boolean }? = FootPath.boxesAt(f, x0, z0)
	local atGoal = FootPath.boxesAt(f, x1, z1)
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
	local hop = opts ~= nil and opts.hop == true
	local fromA: { [number]: boolean }, toA: { [number]: boolean } = {}, {}
	if f.rows then
		-- (the connected areas: two ends in no common area are joined by links, or by nothing)
		local same = false
		for _, c in from do
			fromA[FootPath.areaAt(f, c.ix * cell, c.iz * cell) or 0] = true
		end
		for _, c in to do
			local a = FootPath.areaAt(f, c.ix * cell, c.iz * cell) or 0
			toA[a] = true
			same = same or fromA[a] == true
		end
		if not same then
			local chain = if hop then nil else linkChain(f, x0, z0, x1, z1, fromA, toA)
			if chain == nil then
				f.early += 1
				return nil, 0
			end
			return byLinks(f, x0, z0, x1, z1, chain, opts)
		end
	end
	-- the river between them (one area: its banks meet beyond its ends, a long way round): over a bridge first
	if not hop and #f.links > 0 and f.rows and FootPath.wetLine(f, x0, z0, x1, z1) then
		local chain = linkChain(f, x0, z0, x1, z1, fromA, toA)
		if chain then
			local points, length = byLinks(f, x0, z0, x1, z1, chain, opts)
			if points then
				return points, length
			end
		end
		f.opened = 0
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
	local nearest, nearestD = nil, math.huge -- the opened cell nearest the goal (a partial way's end)
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
		local ix, iz = k // SPAN - OFFSET, k % SPAN - OFFSET
		local d = (ix * cell - x1) ^ 2 + (iz * cell - z1) ^ 2
		if d < nearestD then
			nearest, nearestD = k, d
		end
		if f.opened >= budget or g[k] > maxLength then
			break
		end
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
	local partial = false
	if last == nil then
		-- out of budget: the way to the cell nearest the goal, when that is well nearer than the start
		if
			not (opts and opts.partial)
			or nearest == nil
			or math.sqrt(nearestD) > direct - FootPath.PARTIAL_GAIN
			or #heap == 0
		then
			return nil, 0
		end
		last, partial = nearest, true
	end
	-- the chain of cell centres, start to goal (a partial way's: to the cell it reached)
	local chain: { { number } } = if partial then {} else { { x1, z1 } }
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
	return points, length, if partial then true else nil
end

return FootPath
