--!strict
-- ReplicatedStorage.Shared.Routes.Graph
-- Precomputed end-links, transfers, forks, islands.
-- Interface (BUILD_PLAN §1.4): endLinks(id), transfers(id), forks(id)
--
-- The static route graph that AI brains and the MoveValidator read (routes_movement §3, §11, §12):
-- * transfers: two routes are linked when any sample pair is within 1.7 u (the explicit E-transfer
--   limit); union-find over those links gives the islands (harvest: 149 islands, largest 563, 40
--   singletons).
-- * endLinks: the automatic `switchRoute` candidates at each route end: other routes' samples in the
--   end window (t <= 0.07 or t >= 0.93) within 0.48 u, closest per route, trunks only reachable from a
--   bridge (L5941-5986); 0 of the 715 branch tips have one.
-- * forks: `canopyForks` from the compiled generated/Forks.luau (rebuildCanopyForks L4324-4357), by
--   trunk and by branch.
-- Built once from a Registry and a SpatialIndex; pure, unit-agnostic (constants scale with
-- studsPerUnit). Matches data/harvest/graph.json exactly (tests/unit/routes_graph.spec.luau).

local Registry = require("./Registry")
local SpatialIndex = require("./SpatialIndex")
local Units = require("../Config/Units")

local Graph = {}
Graph.__index = Graph

export type Vec3 = Registry.Vec3

export type EndLink = { to: number, t: number, gap: number }

export type Fork = {
	trunk: number,
	branch: number,
	t: number, -- trunk parameter of the nearest sample
	height: number, -- y of that trunk sample
	origin: Vec3, -- branch start (getPointAt(0))
	outward: Vec3, -- XZ unit vector start -> getPointAt(0.19)
	trunkClearance: number,
}

export type ForkRecord = {
	trunk: number,
	forks: {
		{
			branch: number,
			t: number,
			height: number,
			origin: { number },
			outward: { number },
			trunkClearance: number?,
		}
	},
}

export type Options = {
	forks: { ForkRecord }?,
	studsPerUnit: number?,
}

export type Graph = typeof(setmetatable(
	{} :: {
		linkDistance: number,
		endGap: number,
		_adjacent: { [number]: { [number]: boolean } },
		_endLinks: { [number]: { [boolean]: { EndLink } } },
		_forksByTrunk: { [number]: { Fork } },
		_forkByBranch: { [number]: Fork },
		_islands: { { number } },
		_islandOf: { [number]: number },
		branchTipLinks: number,
		endLinkCount: number,
	},
	Graph
))

Graph.LINK_UNITS = 1.7 -- explicit transfer limit, HTML units (routes_movement §3, L5783)
Graph.END_GAP_UNITS = 0.48 -- automatic switch gap (RouteJunction.canTransfer, L5785)
Graph.END_T_LOW = 0.07 -- end window (switchRoute, L5951)
Graph.END_T_HIGH = 0.93

local function find(parent: { number }, i: number): number
	while parent[i] ~= i do
		parent[i] = parent[parent[i]]
		i = parent[i]
	end
	return i
end

local function union(parent: { number }, a: number, b: number)
	local ra, rb = find(parent, a), find(parent, b)
	if ra ~= rb then
		parent[rb] = ra
	end
end

-- Transfer adjacency (any sample pair within link) with a temporary fine hash of cell = link, as
-- tools/harvest/src/analyze.js does; returns adjacency sets and the union-find parents.
local function buildTransfers(
	registry: Registry.Registry,
	link: number
): ({ [number]: { [number]: boolean } }, { number }, { Registry.Route })
	local routes = registry:all()
	local ids: { number } = {}
	local xs: { number } = {}
	local ys: { number } = {}
	local zs: { number } = {}
	local cells: { [string]: { number } } = {}
	local n = 0
	for _, route in routes do
		for _, p in registry:samples(route) do
			n += 1
			ids[n] = route.id
			xs[n] = p.x
			ys[n] = p.y
			zs[n] = p.z
			local key = `{math.floor(p.x / link)},{math.floor(p.y / link)},{math.floor(p.z / link)}`
			local cell = cells[key]
			if not cell then
				cell = {}
				cells[key] = cell
			end
			table.insert(cell, n)
		end
	end

	local adjacent: { [number]: { [number]: boolean } } = {}
	local parent: { number } = {}
	for _, route in routes do
		adjacent[route.id] = {}
		parent[route.id] = route.id
	end
	-- Every route id must be a union-find node even when there are gaps in the id sequence.
	local link2 = link * link
	for e = 1, n do
		local id, x, y, z = ids[e], xs[e], ys[e], zs[e]
		local cx, cy, cz = math.floor(x / link), math.floor(y / link), math.floor(z / link)
		local adj = adjacent[id]
		for i = -1, 1 do
			for j = -1, 1 do
				for k = -1, 1 do
					local cell = cells[`{cx + i},{cy + j},{cz + k}`]
					if cell then
						for _, f in cell do
							local other = ids[f]
							if other ~= id and not adj[other] then
								local dx, dy, dz = xs[f] - x, ys[f] - y, zs[f] - z
								if dx * dx + dy * dy + dz * dz <= link2 then
									adj[other] = true
									adjacent[other][id] = true
									union(parent, id, other)
								end
							end
						end
					end
				end
			end
		end
	end
	return adjacent, parent, routes
end

function Graph.build(registry: Registry.Registry, index: SpatialIndex.SpatialIndex, opts: Options?): Graph
	local options: Options = opts or {}
	local studsPerUnit = options.studsPerUnit or registry:studsPerUnit()
	local link = Graph.LINK_UNITS * studsPerUnit
	local endGap = Graph.END_GAP_UNITS * studsPerUnit

	local adjacent, parent, routes = buildTransfers(registry, link)

	-- Islands: groups sorted by size desc, then by first id (harvest order).
	local groups: { [number]: { number } } = {}
	for _, route in routes do
		local root = find(parent, route.id)
		local group = groups[root]
		if not group then
			group = {}
			groups[root] = group
		end
		table.insert(group, route.id)
	end
	local islands: { { number } } = {}
	for _, group in groups do
		table.sort(group)
		table.insert(islands, group)
	end
	table.sort(islands, function(a, b)
		if #a ~= #b then
			return #a > #b
		end
		return a[1] < b[1]
	end)
	local islandOf: { [number]: number } = {}
	for i, island in islands do
		for _, id in island do
			islandOf[id] = i
		end
	end

	-- End links (switchRoute candidates).
	local endLinks: { [number]: { [boolean]: { EndLink } } } = {}
	local branchTipLinks = 0
	local endLinkCount = 0
	for _, route in routes do
		local samples = registry:samples(route)
		local perEnd: { [boolean]: { EndLink } } = {}
		for _, atStart in { true, false } do
			local cur = if atStart then samples[1] else samples[#samples]
			local best: { [number]: EndLink } = {}
			index:forEachNear(cur.x, cur.y, cur.z, 1, function(otherId, t, sx, sy, sz)
				if otherId == route.id or (t > Graph.END_T_LOW and t < Graph.END_T_HIGH) then
					return nil
				end
				local dx, dy, dz = sx - cur.x, sy - cur.y, sz - cur.z
				local gap = math.sqrt(dx * dx + dy * dy + dz * dz)
				if gap > endGap then
					return nil
				end
				local other = registry:get(otherId)
				if other and other.kind == "trunk" and route.kind ~= "bridge" then
					return nil
				end
				local prev = best[otherId]
				if not prev or gap < prev.gap then
					best[otherId] = { to = otherId, t = t, gap = gap }
				end
				return nil
			end)
			local links: { EndLink } = {}
			for _, l in best do
				table.insert(links, l)
			end
			-- Sorted by gap (quantised to 1e-6 u, as the harvest's graph.json is), then by id.
			local quantum = 1e-6 * studsPerUnit
			table.sort(links, function(a, b)
				local qa, qb = math.floor(a.gap / quantum + 0.5), math.floor(b.gap / quantum + 0.5)
				if qa ~= qb then
					return qa < qb
				end
				return a.to < b.to
			end)
			perEnd[atStart] = links
			if #links > 0 then
				endLinkCount += 1
				if route.kind == "branch" and not atStart then
					branchTipLinks += 1
				end
			end
		end
		endLinks[route.id] = perEnd
	end

	-- Forks from the compiled canopyForks (sorted by height, as in the game).
	local forksByTrunk: { [number]: { Fork } } = {}
	local forkByBranch: { [number]: Fork } = {}
	if options.forks then
		for _, rec in options.forks do
			local list: { Fork } = {}
			for _, f in rec.forks do
				local fork: Fork = {
					trunk = rec.trunk,
					branch = f.branch,
					t = f.t,
					height = f.height,
					origin = { x = f.origin[1], y = f.origin[2], z = f.origin[3] },
					outward = { x = f.outward[1], y = f.outward[2], z = f.outward[3] },
					trunkClearance = f.trunkClearance or 0,
				}
				table.insert(list, fork)
				forkByBranch[f.branch] = fork
			end
			table.sort(list, function(a, b)
				return a.height < b.height
			end)
			forksByTrunk[rec.trunk] = list
		end
	end

	local self = setmetatable({
		linkDistance = link,
		endGap = endGap,
		_adjacent = adjacent,
		_endLinks = endLinks,
		_forksByTrunk = forksByTrunk,
		_forkByBranch = forkByBranch,
		_islands = islands,
		_islandOf = islandOf,
		branchTipLinks = branchTipLinks,
		endLinkCount = endLinkCount,
	}, Graph)
	return self
end

local EMPTY_LINKS: { EndLink } = table.freeze({})
local EMPTY_FORKS: { Fork } = table.freeze({})

-- endLinks(id, atStart): automatic switch candidates at that end (closest sample per route, sorted).
function Graph.endLinks(self: Graph, routeId: number, atStart: boolean): { EndLink }
	local perEnd = self._endLinks[routeId]
	if not perEnd then
		return EMPTY_LINKS
	end
	return perEnd[atStart] or EMPTY_LINKS
end

-- transfers(id): routes with any sample pair within 1.7 u (sorted ids).
function Graph.transfers(self: Graph, routeId: number): { number }
	local out: { number } = {}
	local adj = self._adjacent[routeId]
	if adj then
		for other in adj do
			table.insert(out, other)
		end
		table.sort(out)
	end
	return out
end

function Graph.linked(self: Graph, a: number, b: number): boolean
	local adj = self._adjacent[a]
	return adj ~= nil and adj[b] == true
end

-- forks(trunkId): canopy forks of a trunk sorted by height (empty for non-trunks).
function Graph.forks(self: Graph, trunkId: number): { Fork }
	return self._forksByTrunk[trunkId] or EMPTY_FORKS
end

-- forkOf(branchId): the fork record whose branch this is (parent trunk), or nil.
function Graph.forkOf(self: Graph, branchId: number): Fork?
	return self._forkByBranch[branchId]
end

-- siblings(branchId): forks on the same trunk other than this branch.
function Graph.siblings(self: Graph, branchId: number): { Fork }
	local parent = self._forkByBranch[branchId]
	if not parent then
		return EMPTY_FORKS
	end
	local out: { Fork } = {}
	for _, f in self:forks(parent.trunk) do
		if f.branch ~= branchId then
			table.insert(out, f)
		end
	end
	return out
end

-- related(a, b): any structural relation a legal route-to-route move can use: a transfer link,
-- an end link, a trunk-fork pair or two sibling boughs.
function Graph.related(self: Graph, a: number, b: number): boolean
	if a == b then
		return true
	end
	if self:linked(a, b) then
		return true
	end
	for _, atStart in { true, false } do
		for _, l in self:endLinks(a, atStart) do
			if l.to == b then
				return true
			end
		end
	end
	local fa, fb = self._forkByBranch[a], self._forkByBranch[b]
	if (fa and fa.trunk == b) or (fb and fb.trunk == a) then
		return true
	end
	if fa and fb and fa.trunk == fb.trunk then
		return true
	end
	return false
end

function Graph.islands(self: Graph): { { number } }
	return self._islands
end

function Graph.islandOf(self: Graph, routeId: number): number?
	return self._islandOf[routeId]
end

function Graph.islandCount(self: Graph): number
	return #self._islands
end

function Graph.largestIsland(self: Graph): number
	local first = self._islands[1]
	return if first then #first else 0
end

function Graph.singletonCount(self: Graph): number
	local n = 0
	for _, island in self._islands do
		if #island == 1 then
			n += 1
		end
	end
	return n
end

function Graph.forkCounts(self: Graph): (number, number)
	local trunks, forks = 0, 0
	for _, list in self._forksByTrunk do
		trunks += 1
		forks += #list
	end
	return trunks, forks
end

Graph.STUDS_PER_UNIT = Units.STUDS_PER_UNIT

return Graph
