--!strict
-- tools/games/paintball/arena/probe: what the navigation graph has inside a rectangle of a storey.
--   lune run tools/games/paintball/arena/probe.luau level x0 z0 x1 z1
-- Prints every node in it with its links, and for every pair of them not linked, whether a body could walk the
-- straight line (NavBuild.walkable): for finding out why a room is thinly joined.
local process = require("@lune/process")
local ArenaData = require("../../../../src/shared/Minigames/Paintball/ArenaData")
local NavBuild = require("./NavBuild")

local v: { number } = {}
for i = 1, 5 do
	v[i] = tonumber(process.args[i]) or error("five numbers: level x0 z0 x1 z1")
end
local arena = ArenaData.build()
local inside: { number } = {}
for _, n in arena.nodes do
	if n.floor == v[1] and n.x >= v[2] and n.x <= v[4] and n.z >= v[3] and n.z <= v[5] then
		table.insert(inside, n.id)
	end
end
local linked: { [number]: { number } } = {}
for _, l in arena.links do
	linked[l.a] = linked[l.a] or {}
	linked[l.b] = linked[l.b] or {}
	table.insert(linked[l.a], l.b)
	table.insert(linked[l.b], l.a)
end
for _, id in inside do
	local n = arena.nodes[id]
	local to: { string } = {}
	for _, other in linked[id] or {} do
		local m = arena.nodes[other]
		table.insert(to, string.format("%d(%.1f,%.1f)", other, m.x, m.z))
	end
	print(string.format("%4d %-5s (%.1f, %.1f, %.1f) -> %s", id, n.kind, n.x, n.y, n.z, table.concat(to, " ")))
end
for i, a in inside do
	for j = i + 1, #inside do
		local b = inside[j]
		local na, nb = arena.nodes[a], arena.nodes[b]
		local d = math.sqrt((na.x - nb.x) ^ 2 + (na.z - nb.z) ^ 2)
		if d <= NavBuild.REACH and not table.find(linked[a] or {}, b) then
			local ok = NavBuild.walkable(arena.sweep, arena.ground, na.x, na.y, na.z, nb.x, nb.y, nb.z)
			print(string.format("  %d - %d: %.1f studs, %s", a, b, d, if ok then "walkable, not linked" else "blocked"))
		end
	end
end
