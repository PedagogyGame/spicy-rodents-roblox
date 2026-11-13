--!strict
-- tools/games/paintball/arena/path: the cheapest walk along the arena's navigation links between two points.
--   lune run tools/games/paintball/arena/path.luau x y z  x y z   (feet points; the nearest node to each is used)
-- Prints the cost in studs and every node on the way: for finding out why a route is longer than it looks.
local process = require("@lune/process")
local ArenaData = require("../../../../src/shared/Minigames/Paintball/ArenaData")

local arena = ArenaData.build()
local nodes, links = arena.nodes, arena.links
local adjacent: { [number]: { { number } } } = {}
for _, l in links do
	adjacent[l.a] = adjacent[l.a] or {}
	adjacent[l.b] = adjacent[l.b] or {}
	table.insert(adjacent[l.a], { l.b, l.cost })
	table.insert(adjacent[l.b], { l.a, l.cost })
end
local function nearest(x: number, y: number, z: number): number
	local best, bd = 0, math.huge
	for _, n in nodes do
		local d = (n.x - x) ^ 2 + (n.y - y) ^ 2 + (n.z - z) ^ 2
		if d < bd then
			best, bd = n.id, d
		end
	end
	return best
end
local v: { number } = {}
for i = 1, 6 do
	v[i] = tonumber(process.args[i]) or error("six numbers: x y z x y z")
end
local a, b = nearest(v[1], v[2], v[3]), nearest(v[4], v[5], v[6])
local cost: { [number]: number } = { [a] = 0 }
local prev: { [number]: number } = {}
local open = { a }
while #open > 0 do
	local bi = 1
	for k = 2, #open do
		if cost[open[k]] < cost[open[bi]] then
			bi = k
		end
	end
	local at = table.remove(open, bi) :: number
	for _, e in adjacent[at] or {} do
		local c = cost[at] + e[2]
		if cost[e[1]] == nil or c < cost[e[1]] then
			cost[e[1]] = c
			prev[e[1]] = at
			if not table.find(open, e[1]) then
				table.insert(open, e[1])
			end
		end
	end
end
local out: { string } = {}
local at: number? = b
while at do
	local n = nodes[at]
	table.insert(out, 1, string.format("(%.1f, %.0f, %.1f)", n.x, n.y, n.z))
	at = prev[at]
end
print(string.format("%.1f studs over %d nodes:", cost[b] or -1, #out), table.concat(out, " "))
