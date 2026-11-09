--!strict
-- ServerScriptService.Server.Actors.Nav
-- Sidewalk lane graph, interior room graphs, cached escapes (BUILD_PLAN §1.4 Actors/Nav, §4.4 #3).
-- * Sidewalk graph: every concrete strip from World/Town is a lane; nodes are the strip ends and
--   every crossing of two perpendicular strips (within both widths); edges join consecutive nodes
--   along a strip. path(from, to) snaps both ends onto their nearest strip and runs A* (Euclidean).
-- * Room graphs: the compiled interior templates (generated/Interiors): rooms and the doors joining
--   them ("outside" included), keyed by template id and by lot id; roomPath(lotId, from, to) is BFS.
-- * Escapes: nearestNode is cached per 8-stud cell.
-- Interface: build(town, interiors?) -> Nav; path(nav, x0, z0, x1, z1) -> { {x, z} }?;
--   nearestNode(nav, x, z) -> number?; lanes(nav) -> Pedestrian lanes; roomGraph(nav, lotOrTemplate)
--   -> { rooms, adj }?; roomPath(nav, lotOrTemplate, from, to) -> { string }?
-- Pure; studs. No side effects on require.

export type Node = { id: number, x: number, z: number }
export type Lane = { axis: "x" | "z", fixed: number, min: number, max: number, inward: number? }
export type RoomGraph = { id: string, lot: string?, rooms: { string }, adj: { [string]: { string } } }
export type Nav = {
	nodes: { Node },
	edges: { [number]: { { to: number, d: number } } },
	strips: { any },
	stripNodes: { [number]: { number } }, -- strip index -> node ids sorted along the strip
	rooms: { [string]: RoomGraph },
	cache: { [number]: number },
}

local Nav = {}

local CELL = 8

local function addEdge(nav: Nav, a: number, b: number)
	if a == b then
		return
	end
	local na, nb = nav.nodes[a], nav.nodes[b]
	local d = math.sqrt((na.x - nb.x) ^ 2 + (na.z - nb.z) ^ 2)
	table.insert(nav.edges[a], { to = b, d = d })
	table.insert(nav.edges[b], { to = a, d = d })
end

local function pointOn(strip: any, along: number): (number, number)
	if strip.axis == "z" then
		return strip.coord, along
	end
	return along, strip.coord
end

function Nav.build(town: any, interiors: { [string]: any }?): Nav
	local strips = town:sidewalks()
	local nav: Nav = { nodes = {}, edges = {}, strips = strips, stripNodes = {}, rooms = {}, cache = {} }
	local alongs: { [number]: { { along: number, node: number } } } = {}
	local function newNode(x: number, z: number): number
		local id = #nav.nodes + 1
		nav.nodes[id] = { id = id, x = x, z = z }
		nav.edges[id] = {}
		return id
	end
	for i, s in strips do
		alongs[i] = {}
		for _, a in { s.min, s.max } do
			local x, z = pointOn(s, a)
			table.insert(alongs[i], { along = a, node = newNode(x, z) })
		end
	end
	-- crossings of perpendicular strips
	for i, a in strips do
		for j = i + 1, #strips do
			local b = strips[j]
			if a.axis ~= b.axis then
				-- a runs along a.axis at a.coord; b runs along b.axis at b.coord
				local alongA, alongB = b.coord, a.coord
				if
					alongA >= a.min - b.half
					and alongA <= a.max + b.half
					and alongB >= b.min - a.half
					and alongB <= b.max + a.half
				then
					local x, z = pointOn(a, alongA)
					local id = newNode(x, z)
					table.insert(alongs[i], { along = alongA, node = id })
					table.insert(alongs[j], { along = alongB, node = id })
				end
			end
		end
	end
	for i, list in alongs do
		table.sort(list, function(p, q)
			return p.along < q.along
		end)
		local ids = {}
		for k, entry in list do
			ids[k] = entry.node
			if k > 1 then
				addEdge(nav, list[k - 1].node, entry.node)
			end
		end
		nav.stripNodes[i] = ids
	end
	-- interior room graphs
	local templates: { [string]: any } = interiors or {}
	for id, t in templates do
		local rooms, adj = {}, {}
		local roomList: { any } = t.rooms or {}
		local doorList: { any } = t.doors or {}
		for _, r in roomList do
			table.insert(rooms, r.id)
			adj[r.id] = {}
		end
		adj.outside = adj.outside or {}
		for _, d in doorList do
			adj[d.a] = adj[d.a] or {}
			adj[d.b] = adj[d.b] or {}
			table.insert(adj[d.a], d.b)
			table.insert(adj[d.b], d.a)
		end
		local g = { id = id, lot = t.lot, rooms = rooms, adj = adj }
		nav.rooms[id] = g
		if t.lot then
			nav.rooms[t.lot] = g
		end
	end
	return nav
end

-- Pedestrian lanes from the sidewalk strips (Brains/Pedestrian.Lane), longest first.
function Nav.lanes(nav: Nav): { Lane }
	local out: { Lane } = {}
	for _, s in nav.strips do
		table.insert(out, { axis = s.axis, fixed = s.coord, min = s.min, max = s.max })
	end
	table.sort(out, function(a, b)
		local ca, cb = math.abs(a.fixed), math.abs(b.fixed)
		if ca ~= cb then
			return ca < cb
		end
		return a.max - a.min > b.max - b.min
	end)
	return out
end

function Nav.nearestNode(nav: Nav, x: number, z: number): number?
	local key = math.floor(x / CELL) * 65536 + math.floor(z / CELL)
	local hit = nav.cache[key]
	if hit then
		return hit
	end
	local best, bestD = nil, math.huge
	for _, n in nav.nodes do
		local d = (n.x - x) ^ 2 + (n.z - z) ^ 2
		if d < bestD then
			best, bestD = n.id, d
		end
	end
	if best then
		nav.cache[key] = best
	end
	return best
end

-- A* over the sidewalk graph between the nodes nearest to the two points.
function Nav.path(nav: Nav, x0: number, z0: number, x1: number, z1: number): { { number } }?
	local a, b = Nav.nearestNode(nav, x0, z0), Nav.nearestNode(nav, x1, z1)
	if not a or not b then
		return nil
	end
	local goal = nav.nodes[b]
	local function h(id: number): number
		local n = nav.nodes[id]
		return math.sqrt((n.x - goal.x) ^ 2 + (n.z - goal.z) ^ 2)
	end
	local g: { [number]: number } = { [a] = 0 }
	local came: { [number]: number } = {}
	local open: { number } = { a }
	local inOpen: { [number]: boolean } = { [a] = true }
	local closed: { [number]: boolean } = {}
	while #open > 0 do
		local bi, bf = 1, math.huge
		for i, id in open do
			local f = g[id] + h(id)
			if f < bf then
				bi, bf = i, f
			end
		end
		local cur = table.remove(open, bi) :: number
		inOpen[cur] = nil
		if cur == b then
			local out = {}
			local c: number? = cur
			while c do
				local n = nav.nodes[c]
				table.insert(out, 1, { n.x, n.z })
				c = came[c]
			end
			table.insert(out, 1, { x0, z0 })
			table.insert(out, { x1, z1 })
			return out
		end
		closed[cur] = true
		for _, e in nav.edges[cur] do
			if not closed[e.to] then
				local ng = g[cur] + e.d
				if g[e.to] == nil or ng < g[e.to] then
					g[e.to] = ng
					came[e.to] = cur
					if not inOpen[e.to] then
						table.insert(open, e.to)
						inOpen[e.to] = true
					end
				end
			end
		end
	end
	return nil
end

function Nav.roomGraph(nav: Nav, key: string): RoomGraph?
	return nav.rooms[key]
end

-- BFS through doors: the room sequence from one room to another (or "outside").
function Nav.roomPath(nav: Nav, key: string, from: string, to: string): { string }?
	local g = nav.rooms[key]
	if not g or not g.adj[from] then
		return nil
	end
	local prev: { [string]: string } = {}
	local seen = { [from] = true }
	local queue = { from }
	while #queue > 0 do
		local cur = table.remove(queue, 1) :: string
		if cur == to then
			local out = { cur }
			while prev[out[1]] do
				table.insert(out, 1, prev[out[1]])
			end
			return out
		end
		local nexts: { string } = g.adj[cur] or {}
		for _, nxt in nexts do
			if not seen[nxt] then
				seen[nxt] = true
				prev[nxt] = cur
				table.insert(queue, nxt)
			end
		end
	end
	return nil
end

return Nav
