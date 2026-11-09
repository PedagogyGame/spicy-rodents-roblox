--!strict
-- ServerScriptService.Server.WorldGen.RoomGraph
-- Room graph (nav waypoints) for building programmes and interior templates (BUILD_PLAN §3.4: "nav
-- waypoints (room centres, door midpoints, hide spots) are generated"; invariant 9). Nodes carry
-- coordinates in the layout's own frame (fractional for interiors, lot-local HTML units for
-- buildings); Builders/Interior and Builders/Programme place them in the world.
-- Interface: build(rooms, doors, extras) -> Graph; unreached(graph, from) -> { nodeId }
--   rooms  = { { id, rect = { x0, x1, z0, z1 } } }
--   doors  = { { id, a, b ("outside" allowed), at = { x, z } } }
--   extras = { { id, room, at = { x, z }? } }   (hide spots, stations, shelves)
-- Pure: no Instances, used by tools/compile (invariant 9) and by the builders.

local RoomGraph = {}

export type Node = { id: string, kind: string, room: string?, x: number, z: number }
export type Graph = { nodes: { Node }, byId: { [string]: Node }, links: { [string]: { string } } }

local function link(g: Graph, a: string, b: string)
	g.links[a] = g.links[a] or {}
	g.links[b] = g.links[b] or {}
	table.insert(g.links[a], b)
	table.insert(g.links[b], a)
end

local function add(g: Graph, n: Node)
	table.insert(g.nodes, n)
	g.byId[n.id] = n
	g.links[n.id] = g.links[n.id] or {}
end

function RoomGraph.build(rooms: { any }, doors: { any }, extras: { any }): Graph
	local g: Graph = { nodes = {}, byId = {}, links = {} }
	add(g, { id = "outside", kind = "outside", x = 0, z = 0 })
	local rectOf: { [string]: { number } } = {}
	for _, r in rooms do
		rectOf[r.id] = r.rect
		add(g, {
			id = "room:" .. r.id,
			kind = "room",
			room = r.id,
			x = (r.rect[1] + r.rect[2]) / 2,
			z = (r.rect[3] + r.rect[4]) / 2,
		})
		if r.exterior then
			link(g, "room:" .. r.id, "outside") -- exterior rooms (ambulance bay) open onto the street
		end
	end
	for _, d in doors do
		local id = "door:" .. d.id
		add(g, { id = id, kind = "door", x = d.at[1], z = d.at[2] })
		for _, side in { d.a, d.b } do
			local target = if side == "outside" then "outside" else "room:" .. side
			if g.byId[target] then
				link(g, id, target)
			end
		end
	end
	for _, e in extras do
		local r = rectOf[e.room]
		local x = if e.at then e.at[1] elseif r then (r[1] + r[2]) / 2 else 0
		local z = if e.at then e.at[2] elseif r then (r[3] + r[4]) / 2 else 0
		add(g, { id = e.id, kind = e.kind or "spot", room = e.room, x = x, z = z })
		if g.byId["room:" .. e.room] then
			link(g, e.id, "room:" .. e.room)
		end
	end
	return g
end

-- Node ids not reachable from `from`, sorted (empty when the graph is connected).
function RoomGraph.unreached(g: Graph, from: string): { string }
	local seen: { [string]: boolean } = { [from] = true }
	local queue = { from }
	local i = 1
	while i <= #queue do
		for _, nb in g.links[queue[i]] or {} do
			if not seen[nb] then
				seen[nb] = true
				table.insert(queue, nb)
			end
		end
		i += 1
	end
	local out: { string } = {}
	for _, n in g.nodes do
		if not seen[n.id] then
			table.insert(out, n.id)
		end
	end
	table.sort(out)
	return out
end

return RoomGraph
