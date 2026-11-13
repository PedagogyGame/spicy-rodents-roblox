--!strict
-- ServerScriptService.Server.Minigames.Paintball.BotNav
-- What a paintball bot knows of the building before a match starts (checklist PB-10): the arena's
-- navigation graph (Shared/Minigames/Paintball/Arena: nodes, links, cover) worked into the tables a
-- brain reads every tick without searching, and the route search itself. Built once per arena by
-- Bots.new; pure; nothing here knows about a match.
--   adjacency   each node's links as a flat list (to, link index, cost).
--   doors       the nodes just outside a spawn room's ways out (a "walk" link joins them to a node
--               of the room). The OTHER team never walks onto one, and never chooses to stand
--               within KEEP_OFF studs of one on that storey ("never camp a spawn room"): keepOff.
--               A body within DOORSTEP of its own team's door is on its doorstep: atDoor.
--   entry       for each spawn point, the node of its room a body can walk to in a straight line.
--   goals       per floor, the nodes a bot may choose to go and stand on: nobody's room, not a door.
--   cover       per node, the arena's cover records; and for each cover spot the two PEEKS, a short
--               sidestep either way across the sheltered direction that is clear to walk (chest and
--               eye), on the same floor, and far enough out to SEE the way the cover faces (the
--               shortest of a few steps that does; none if none does): where a bot behind a pillar
--               steps out to shoot and back.
--   views       per node, how far a standing eye sees in each of VIEWS directions round the compass
--               (one arena.sweep each, capped at VIEW_FAR; worked out the first time a bot asks, kept
--               for good): a bot at a post looks where there is something to see, not at a wall.
--   dip         per node, how steeply a standing eye can look down towards the building's axis and
--               see something (over the atrium's rail, not at it); found the same lazy way.
--   route       A* over the links. A team never enters the other team's room or its doors; its own
--               room it only leaves (a step back into it costs BACK_IN). Each bot has a TASTE, a
--               fixed multiplier per link (stairs more than floors), so that eight bots asked for
--               the same place do not all file up one stair (PB-10: "do not all take one stair").
-- Interface: build(arena) -> Nav; taste(nav, seed) -> { number }; route(nav, from, alt?, altCost?,
--   to, team, taste) -> { node id }? (nil: no way); nearest(nav, x, y, z, team?) -> node id;
--   roomOf(nav, x, y, z) -> team or 0; atDoor(nav, team, x, y, z, more?) -> boolean; dip(nav, node) -> radians; views(nav, node)
--   -> { studs } (direction k of VIEWS is yaw (k - 1) * 2 pi / VIEWS); KEEP_OFF, PEEK, DOORSTEP, VIEWS,
--   VIEW_FAR; types Nav, Peek

local Import = require("../../Import")
local ArenaModule: typeof(require(game.ReplicatedStorage.Shared.Minigames.Paintball.Arena)) =
	Import.shared("Minigames/Paintball/Arena")

type Arena = typeof(ArenaModule.T.Arena)
type NavNode = typeof(ArenaModule.T.NavNode)
type Cover = typeof(ArenaModule.T.Cover)
type Spawn = typeof(ArenaModule.T.Spawn)

-- A sidestep from a cover spot: where to, and the unit vector of the step.
export type Peek = { x: number, z: number }

export type Nav = {
	arena: Arena,
	nodes: { NavNode },
	count: number,
	adjacent: { { number } }, -- by node: to, link, cost, to, link, cost ...
	door: { number }, -- by node: the team whose room it is a way out of, else 0
	doors: { { number } }, -- by team: its room's door nodes
	keepOff: { { boolean } }, -- by team (the one that must keep off), by node
	entry: { { number } }, -- by team, by spawn index: the node to walk to first
	goals: { { number } }, -- by floor + 1: nodes a bot may go and stand on
	coverAt: { [number]: Cover }, -- by node: its cover record (the first, if it has several)
	peeks: { [number]: { Peek } }, -- by node: the sidesteps that are clear
	links: number,
	stair: { boolean }, -- by link index
	viewsAt: { [number]: { number } }, -- by node, once asked for: studs of clear view in each of VIEWS directions
	dipAt: { [number]: number }, -- by node, once asked for: how steeply a standing eye can look down towards the atrium
}

local BotNav = {}

BotNav.KEEP_OFF = 30 -- studs from a door of the other team's room inside which a bot does not stand
BotNav.PEEK = 2.6 -- studs a bot steps out from a cover spot to shoot round it, at the least
-- (a wide pillar or the end of a wall wants a longer step: the shortest of these that SEES is the peek)
local PEEKS = { BotNav.PEEK, 3.4, 4.2, 5.0 }
local PEEK_SEES = 12 -- studs of clear view the way the cover faces that make a step a peek
BotNav.DOORSTEP = 14 -- studs round a door of a spawn room: no bot fires at its owners while they are on it
BotNav.VIEWS = 12 -- directions round the compass a node's views are measured in
BotNav.VIEW_FAR = 40 -- studs: no view is measured further
local BACK_IN = 400 -- the cost of a step into one's own spawn room from outside it
local STAIR_TASTE = 0.9 -- a stair link costs a bot up to this much more than its length, by its taste
local FLOOR_TASTE = 0.35

function BotNav.roomOf(nav: Nav, x: number, y: number, z: number): number
	local rooms = nav.arena.spawnRooms
	for team = 1, 2 do
		local room = rooms[team]
		if room ~= nil and ArenaModule.inRoom(room, x, y + 0.1, z) then
			return team
		end
	end
	return 0
end

function BotNav.build(arena: Arena): Nav
	local nodes, links = arena.nodes, arena.links
	local n = #nodes
	local adjacent: { { number } } = table.create(n)
	local door: { number } = table.create(n, 0)
	for i = 1, n do
		adjacent[i] = {}
	end
	local stair: { boolean } = table.create(#links, false)
	for index, link in links do
		local a, b = nodes[link.a], nodes[link.b]
		if a == nil or b == nil then
			continue
		end
		stair[index] = link.kind == "stair"
		local la, lb = adjacent[link.a], adjacent[link.b]
		table.insert(la, link.b)
		table.insert(la, index)
		table.insert(la, link.cost)
		table.insert(lb, link.a)
		table.insert(lb, index)
		table.insert(lb, link.cost)
		if a.team ~= 0 and b.team == 0 then
			door[link.b] = a.team
		elseif b.team ~= 0 and a.team == 0 then
			door[link.a] = b.team
		end
	end
	local keepOff: { { boolean } } = { table.create(n, false), table.create(n, false) }
	for i, node in nodes do
		local owner = door[i]
		if owner ~= 0 then
			local other = 3 - owner
			for j, near in nodes do
				local flat = math.sqrt((near.x - node.x) ^ 2 + (near.z - node.z) ^ 2)
				if math.abs(near.y - node.y) < arena.floorHeight * 0.5 and flat <= BotNav.KEEP_OFF then
					keepOff[other][j] = true
				end
			end
		end
	end
	local doors: { { number } } = { {}, {} }
	for i = 1, n do
		if door[i] ~= 0 then
			table.insert(doors[door[i]], i)
		end
	end
	local goals: { { number } } = {}
	for f = 1, arena.floors do
		goals[f] = {}
	end
	for i, node in nodes do
		if node.team == 0 and door[i] == 0 and goals[node.floor + 1] ~= nil then
			table.insert(goals[node.floor + 1], i)
		end
	end
	local chest, eye = ArenaModule.CHEST, ArenaModule.EYE
	local function walkable(x0: number, y0: number, z0: number, x1: number, z1: number): boolean
		return arena.sweep(x0, y0 + chest, z0, x1, y0 + chest, z1) == nil
			and arena.sweep(x0, y0 + eye, z0, x1, y0 + eye, z1) == nil
	end
	local entry: { { number } } = { {}, {} }
	for team = 1, 2 do
		local points: { Spawn } = arena.spawns[team] or {}
		for index, sp in points do
			local best, bestD = 0, math.huge
			local fallback, fallbackD = 0, math.huge
			for i, node in nodes do
				local d = math.sqrt((node.x - sp.x) ^ 2 + (node.z - sp.z) ^ 2)
				if math.abs(node.y - sp.y) > 0.5 then
					continue
				end
				if d < fallbackD then
					fallback, fallbackD = i, d
				end
				if node.team == team and d < bestD and walkable(sp.x, sp.y, sp.z, node.x, node.z) then
					best, bestD = i, d
				end
			end
			entry[team][index] = if best ~= 0 then best else fallback
		end
	end
	local coverAt: { [number]: Cover } = {}
	local peeks: { [number]: { Peek } } = {}
	for _, c in arena.cover do
		local node = nodes[c.node]
		if node == nil or coverAt[c.node] ~= nil then
			continue
		end
		coverAt[c.node] = c
		local list: { Peek } = {}
		for _, side in { 1, -1 } do
			-- across the sheltered direction: (nx, nz) turned a quarter; the shortest step that sees
			for _, reach in PEEKS do
				local px, pz = node.x - c.nz * side * reach, node.z + c.nx * side * reach
				local g = arena.ground(px, node.y + 0.5, pz)
				if g == nil or math.abs(g - node.y) >= 0.05 or not walkable(node.x, node.y, node.z, px, pz) then
					break -- no walking that way: a longer step is no better
				end
				-- and a little further, so that the body is not left hanging over an edge or in a wall
				local fx, fz = node.x - c.nz * side * (reach + 1.3), node.z + c.nx * side * (reach + 1.3)
				local g2 = arena.ground(fx, node.y + 0.5, fz)
				if g2 == nil or math.abs(g2 - node.y) >= 0.05 or not walkable(px, node.y, pz, fx, fz) then
					break
				end
				-- out from behind it: a standing eye there sees the way the cover faces
				local y = node.y + eye
				if arena.sweep(px, y, pz, px + c.nx * PEEK_SEES, y, pz + c.nz * PEEK_SEES) == nil then
					table.insert(list, { x = px, z = pz })
					break
				end
			end
		end
		peeks[c.node] = list
	end
	return {
		arena = arena,
		nodes = nodes,
		count = n,
		adjacent = adjacent,
		door = door,
		doors = doors,
		keepOff = keepOff,
		entry = entry,
		goals = goals,
		coverAt = coverAt,
		peeks = peeks,
		links = #links,
		stair = stair,
		viewsAt = {},
		dipAt = {},
	}
end

-- How steeply (radians below level, 0 = not at all) a standing eye at this node can look down
-- towards the building's axis and still see DIP_CLEAR studs: over a rail into the atrium, not at
-- the rail. Worked out once a node.
local DIPS = { 0.7, 0.55, 0.4, 0.25 }
local DIP_CLEAR = 9
function BotNav.dip(nav: Nav, node: number): number
	local had = nav.dipAt[node]
	if had ~= nil then
		return had
	end
	local at = nav.nodes[node]
	local found = 0
	if at ~= nil and (at.x ~= 0 or at.z ~= 0) then
		local sweep = nav.arena.sweep
		local y = at.y + ArenaModule.EYE
		local yaw = math.atan2(at.x, at.z)
		for _, dip in DIPS do
			local clear = true
			for _, off in { -0.5, 0, 0.5 } do
				local flat = math.cos(dip) * DIP_CLEAR
				local dx, dz = -math.sin(yaw + off) * flat, -math.cos(yaw + off) * flat
				if sweep(at.x, y, at.z, at.x + dx, y - math.sin(dip) * DIP_CLEAR, at.z + dz) ~= nil then
					clear = false
					break
				end
			end
			if clear then
				found = dip
				break
			end
		end
	end
	nav.dipAt[node] = found
	return found
end

-- How far a standing eye at this node sees, level, in each of VIEWS directions: direction k looks
-- along yaw (k - 1) * 2 pi / VIEWS (Body.look's yaw: 0 looks along -z). Worked out once a node.
function BotNav.views(nav: Nav, node: number): { number }
	local had = nav.viewsAt[node]
	if had ~= nil then
		return had
	end
	local at = nav.nodes[node]
	local out: { number } = table.create(BotNav.VIEWS, 0)
	if at ~= nil then
		local sweep = nav.arena.sweep
		local y = at.y + ArenaModule.EYE
		local far = BotNav.VIEW_FAR
		for k = 1, BotNav.VIEWS do
			local yaw = (k - 1) * 2 * math.pi / BotNav.VIEWS
			local dx, dz = -math.sin(yaw), -math.cos(yaw)
			local hit = sweep(at.x, y, at.z, at.x + dx * far, y, at.z + dz * far)
			out[k] = if hit ~= nil then hit * far else far
		end
	end
	nav.viewsAt[node] = out
	return out
end

-- Is a body of `team` at (x, y, z) on its own doorstep: within DOORSTEP (and `more`, if given) of a
-- way out of its spawn room?
function BotNav.atDoor(nav: Nav, team: number, x: number, y: number, z: number, more: number?): boolean
	local list = nav.doors[team]
	if list == nil then
		return false
	end
	local reach = BotNav.DOORSTEP + (more or 0)
	for _, id in list do
		local node = nav.nodes[id]
		if math.abs(node.y - y) < 3 and (node.x - x) ^ 2 + (node.z - z) ^ 2 <= reach * reach then
			return true
		end
	end
	return false
end

-- A bot's taste: one multiplier per link, fixed for the bot (a hash of its seed and the link).
function BotNav.taste(nav: Nav, seed: number): { number }
	local out: { number } = table.create(nav.links, 1)
	local s = math.floor(seed) % 65521
	for index = 1, nav.links do
		local h = (s * 7919 + index * 104729 + s * index * 31) % 1009 / 1009
		out[index] = 1 + h * (if nav.stair[index] then STAIR_TASTE else FLOOR_TASTE)
	end
	return out
end

-- The node nearest a point on its own storey; with `team`, never one of the other team's room or doors.
function BotNav.nearest(nav: Nav, x: number, y: number, z: number, team: number?): number
	local best, bestD = 1, math.huge
	local half = nav.arena.floorHeight * 0.5
	for i, node in nav.nodes do
		if team ~= nil and ((node.team ~= 0 and node.team ~= team) or (nav.door[i] ~= 0 and nav.door[i] ~= team)) then
			continue
		end
		local dy = math.abs(node.y - y)
		local d = (node.x - x) ^ 2 + (node.z - z) ^ 2 + (if dy > half then 1e6 else dy * dy)
		if d < bestD then
			best, bestD = i, d
		end
	end
	return best
end

-- The cheapest walk from `from` (or from `alt`, which costs `altCost` more to start at: the other
-- end of the link the bot stands on) to `to`, as node ids starting with the node it sets out from.
function BotNav.route(
	nav: Nav,
	from: number,
	alt: number?,
	altCost: number?,
	to: number,
	team: number,
	taste: { number }
): { number }?
	local nodes = nav.nodes
	local goal = nodes[to]
	if goal == nil or nodes[from] == nil then
		return nil
	end
	local other = 3 - team
	local cost: { [number]: number } = {}
	local came: { [number]: number } = {}
	local closed: { [number]: boolean } = {}
	-- a binary heap of (priority, node) pairs
	local heapP: { number } = {}
	local heapN: { number } = {}
	local size = 0
	local function push(p: number, node: number)
		size += 1
		local i = size
		while i > 1 do
			local parent = i // 2
			if heapP[parent] <= p then
				break
			end
			heapP[i], heapN[i] = heapP[parent], heapN[parent]
			i = parent
		end
		heapP[i], heapN[i] = p, node
	end
	local function pop(): number
		local top = heapN[1]
		local p, node = heapP[size], heapN[size]
		heapP[size], heapN[size] = nil, nil
		size -= 1
		local i = 1
		while size > 0 do
			local child = i * 2
			if child > size then
				break
			end
			if child < size and heapP[child + 1] < heapP[child] then
				child += 1
			end
			if heapP[child] >= p then
				break
			end
			heapP[i], heapN[i] = heapP[child], heapN[child]
			i = child
		end
		if size > 0 then
			heapP[i], heapN[i] = p, node
		end
		return top
	end
	local function h(i: number): number
		local node = nodes[i]
		return math.sqrt((node.x - goal.x) ^ 2 + (node.y - goal.y) ^ 2 + (node.z - goal.z) ^ 2)
	end
	cost[from] = 0
	push(h(from), from)
	if alt ~= nil and nodes[alt] ~= nil and alt ~= from then
		cost[alt] = altCost or 0
		push((altCost or 0) + h(alt), alt)
	end
	local door = nav.door
	while size > 0 do
		local at = pop()
		if at == to then
			break
		end
		if closed[at] then
			continue
		end
		closed[at] = true
		local list = nav.adjacent[at]
		local here = nodes[at]
		local base = cost[at]
		for k = 1, #list, 3 do
			local next = list[k]
			if closed[next] then
				continue
			end
			local node = nodes[next]
			if node.team == other or door[next] == other then
				continue -- the other team's room and its doors are shut to this bot
			end
			local c = base + list[k + 2] * taste[list[k + 1]]
			if node.team == team and here.team ~= team then
				c += BACK_IN
			end
			local had = cost[next]
			if had == nil or c < had then
				cost[next] = c
				came[next] = at
				push(c + h(next), next)
			end
		end
	end
	if cost[to] == nil then
		return nil
	end
	local back: { number } = { to }
	local at = to
	while came[at] ~= nil do
		at = came[at]
		table.insert(back, at)
	end
	local path: { number } = table.create(#back)
	for i = #back, 1, -1 do
		table.insert(path, back[i])
	end
	return path
end

return BotNav
