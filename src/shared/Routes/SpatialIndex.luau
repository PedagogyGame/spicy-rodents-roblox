--!strict
-- ReplicatedStorage.Shared.Routes.SpatialIndex
-- 20-stud index over route samples.
-- Interface (BUILD_PLAN §1.4): nearest(pos, maxDist, excl)
--
-- The port of v5.4's `routeSpatial` (routes_movement §1.3): a hash of 8 u (20 st) cells on all three
-- axes, one entry per arc-length sample with `t = i / (sampleCount - 1)`, 81,613 entries for the
-- harvest. `nearest` scans +-ceil(maxDist / cell) cells like `nearestRoute` (L5718); `forEachNear`
-- is the 3x3x3 neighbourhood walk that `switchRoute` and `junctionCandidates` use.
-- Cells store parallel arrays (ids, ts, xs, ys, zs) so a query allocates nothing.
-- Pure, unit-agnostic (the cell size is passed in; default 20 studs).

local Units = require("../Config/Units")
local Registry = require("./Registry")

local SpatialIndex = {}
SpatialIndex.__index = SpatialIndex

export type Cell = { ids: { number }, ts: { number }, xs: { number }, ys: { number }, zs: { number }, n: number }

export type Hit = { routeId: number, t: number, d: number, x: number, y: number, z: number }

export type SpatialIndex = typeof(setmetatable(
	{} :: {
		cellSize: number,
		_cells: { [number]: Cell },
		_cellCount: number,
		_entryCount: number,
	},
	SpatialIndex
))

SpatialIndex.CELL_UNITS = 8 -- HTML units (routes_movement §1.3)

-- Cell coordinates are packed into one number: 8192 cells per axis (+-4096) is 163,840 studs each way.
local AXIS = 8192
local HALF = 4096

local function cellKey(ix: number, iy: number, iz: number): number
	return (ix + HALF) + (iy + HALF) * AXIS + (iz + HALF) * AXIS * AXIS
end

function SpatialIndex.new(cellSize: number?): SpatialIndex
	local self = setmetatable({
		cellSize = cellSize or Units.st(SpatialIndex.CELL_UNITS),
		_cells = {} :: { [number]: Cell },
		_cellCount = 0,
		_entryCount = 0,
	}, SpatialIndex)
	return self
end

-- build(registry, cellSize?): index every route of the registry (loads every chunk).
function SpatialIndex.build(registry: Registry.Registry, cellSize: number?): SpatialIndex
	local self = SpatialIndex.new(cellSize)
	for _, route in registry:all() do
		self:insertRoute(route.id, registry:samples(route))
	end
	return self
end

function SpatialIndex.insert(self: SpatialIndex, routeId: number, t: number, x: number, y: number, z: number)
	local cs = self.cellSize
	local key = cellKey(math.floor(x / cs), math.floor(y / cs), math.floor(z / cs))
	local cell = self._cells[key]
	if not cell then
		cell = { ids = {}, ts = {}, xs = {}, ys = {}, zs = {}, n = 0 }
		self._cells[key] = cell
		self._cellCount += 1
	end
	local n = cell.n + 1
	cell.n = n
	cell.ids[n] = routeId
	cell.ts[n] = t
	cell.xs[n] = x
	cell.ys[n] = y
	cell.zs[n] = z
	self._entryCount += 1
end

-- insertRoute(id, samples): one entry per sample, t = i / (n - 1) (indexRoute, L277-293).
function SpatialIndex.insertRoute(self: SpatialIndex, routeId: number, samples: { Registry.Vec3 })
	local n = #samples
	for i, p in samples do
		self:insert(routeId, (i - 1) / (n - 1), p.x, p.y, p.z)
	end
end

function SpatialIndex.cellCount(self: SpatialIndex): number
	return self._cellCount
end

function SpatialIndex.entryCount(self: SpatialIndex): number
	return self._entryCount
end

-- nearest(x, y, z, maxDist, excludeRouteId?, accept?): the closest sample within maxDist, or nil
-- (nearestRoute L5718: scans +-ceil(maxDist / cell) cells, strict `d < best`). `accept(routeId, t)`, when given,
-- skips the samples it refuses (Routes/Enclosure: an enclosed route is not reached through its wall); without it
-- the search is exactly v5.4's.
function SpatialIndex.nearest(
	self: SpatialIndex,
	x: number,
	y: number,
	z: number,
	maxDist: number,
	excludeRouteId: number?,
	accept: ((routeId: number, t: number) -> boolean)?
): Hit?
	local cs = self.cellSize
	local tx, ty, tz = math.floor(x / cs), math.floor(y / cs), math.floor(z / cs)
	local r = math.ceil(maxDist / cs)
	local best: Hit? = nil
	local bd = maxDist
	local cells = self._cells
	for i = -r, r do
		for j = -r, r do
			for k = -r, r do
				local cell = cells[cellKey(tx + i, ty + j, tz + k)]
				if cell then
					local ids, ts, xs, ys, zs = cell.ids, cell.ts, cell.xs, cell.ys, cell.zs
					for e = 1, cell.n do
						local id = ids[e]
						if id ~= excludeRouteId then
							local dx, dy, dz = xs[e] - x, ys[e] - y, zs[e] - z
							local d = math.sqrt(dx * dx + dy * dy + dz * dz)
							if d < bd and (accept == nil or accept(id, ts[e])) then
								bd = d
								best = { routeId = id, t = ts[e], d = d, x = xs[e], y = ys[e], z = zs[e] }
							end
						end
					end
				end
			end
		end
	end
	return best
end

-- forEachNear(x, y, z, radiusCells, fn): visit every entry in the (2r+1)^3 cells around the point.
-- fn(routeId, t, x, y, z) returning true stops the walk.
function SpatialIndex.forEachNear(
	self: SpatialIndex,
	x: number,
	y: number,
	z: number,
	radiusCells: number,
	fn: (routeId: number, t: number, x: number, y: number, z: number) -> boolean?
)
	local cs = self.cellSize
	local tx, ty, tz = math.floor(x / cs), math.floor(y / cs), math.floor(z / cs)
	local cells = self._cells
	for i = -radiusCells, radiusCells do
		for j = -radiusCells, radiusCells do
			for k = -radiusCells, radiusCells do
				local cell = cells[cellKey(tx + i, ty + j, tz + k)]
				if cell then
					local ids, ts, xs, ys, zs = cell.ids, cell.ts, cell.xs, cell.ys, cell.zs
					for e = 1, cell.n do
						if fn(ids[e], ts[e], xs[e], ys[e], zs[e]) then
							return
						end
					end
				end
			end
		end
	end
end

-- nearestOnRoute(routeId, x, y, z, maxDist): closest sample of ONE route within maxDist (3x3x3 walk
-- when maxDist <= cell size, wider otherwise).
function SpatialIndex.nearestOnRoute(
	self: SpatialIndex,
	routeId: number,
	x: number,
	y: number,
	z: number,
	maxDist: number
): Hit?
	local best: Hit? = nil
	local bd = maxDist
	self:forEachNear(x, y, z, math.max(1, math.ceil(maxDist / self.cellSize)), function(id, t, sx, sy, sz)
		if id == routeId then
			local dx, dy, dz = sx - x, sy - y, sz - z
			local d = math.sqrt(dx * dx + dy * dy + dz * dz)
			if d < bd then
				bd = d
				best = { routeId = id, t = t, d = d, x = sx, y = sy, z = sz }
			end
		end
		return nil
	end)
	return best
end

return SpatialIndex
