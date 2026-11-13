--!strict
-- tools/games/paintball/arena/NavBuild: the bots' ground (checklist PB-10): the navigation graph and the cover
-- spots of the real arena, WORKED OUT FROM THE BUILDING ITSELF, so that a wall moved in ArenaDataPlan moves the
-- graph with it and a link can never run through something solid. OWNED BY THE ARENA LANE. It is not in the game:
-- tools/games/paintball/arena/bake_nav.luau writes its answer into src/shared/Minigames/Paintball/
-- ArenaDataNavBaked.luau, which ArenaData reads, and tests/unit/paintball_arena_nav.spec.luau fails when that
-- file is not what this module makes of the plan today.
--   nodes   in this order: the plan's waypoints (one in every doorway and one either side of it), the galleries
--           north and south of the atrium and the ground under the cores, the foot and the head of every
--           flight, a lattice of points STEP studs apart on every storey, then FILL: any point of a finer
--           lattice that is still further than GAP from every node, so furniture that swallowed a lattice
--           point leaves no hole; then the cover spots. A point becomes a node only where a body can STAND:
--           floor under it and under its edges, nothing solid within its width from the shin to the head,
--           HEADROOM above. No node is within CLOSE of another (cover spots keep their own place).
--   links   "walk" between two nodes of a storey within REACH studs when a body's whole width can walk the
--           straight line: clear at chest height along the middle and along both shoulders, floor all the way
--           with no step over Arena.STEP_UP. At most DEGREE to a node, the nearest first. "stair" from the foot
--           to the head of each flight (a = the foot, b = the head).
--   spawn rooms   a hub in each and one chain of nodes round each baffle and out of each door: each door has
--           exactly ONE link across it (from the last node inside to the first outside, in that order), which
--           is what Arena.check counts as a way out. No other link crosses a room's edge.
--   cover   beside every low piece (Arena.RAIL_HEIGHT above the spot's floor: low = true) and every tall one a
--           body can hide behind (pillars, racks, flats, crates on crates), a spot OFF studs from the face,
--           where a body can stand; (nx, nz) points from the spot into the piece. Spots nearer than THIN to
--           one already taken are dropped.
-- Whatever cannot be walked to from team 1's spawn room is left out, so the graph is in one piece. Every
-- coordinate is rounded to four places, so the baked file reads back exactly.
-- Pure. Interface: build(plan, sweep, ground) -> (nodes, links, cover); compute() -> the same for the plan as it
--   stands; text(nodes, links, cover) -> the baked file's text; STEP, GAP, CLOSE, REACH, DEGREE, THIN,
--   OFF, WIDTH; standable(sweep, ground, x, y, z) -> y?; walkable(sweep, ground, ax, ay, az, bx, by, bz) -> boolean

local Arena = require("../../../../src/shared/Minigames/Paintball/Arena")
local ArenaDataPlan = require("../../../../src/shared/Minigames/Paintball/ArenaDataPlan")
local ArenaGrid = require("../../../../src/shared/Minigames/Paintball/ArenaGrid")

local Nav = {}

Nav.STEP = 12 -- the lattice
Nav.GAP = 12 -- a finer lattice point further than this from every node becomes one
Nav.CLOSE = 5 -- no two nodes of the lattices are nearer than this
Nav.REACH = 16 -- the longest walk link
Nav.DEGREE = 5 -- the most walk links the builder gives a node of its own accord
Nav.THIN = 12 -- cover spots are at least this far apart
Nav.OFF = 1.9 -- a cover spot's distance from the face it hides behind
Nav.WIDTH = 1.3 -- half a body's width, with a little to spare (Body.RADIUS is 1.2)
Nav.DETOUR = 1.7 -- a walk along the links this many times the walk itself earns a way of its own
Nav.SNAP = 3 -- a node this near a corner of a mended walk serves as that corner

local function round(v: number): number
	return math.floor(v * 1e4 + 0.5) / 1e4
end

-- Can a body stand with its feet at (x, about y, z)? The height of the floor there, or nil.
function Nav.standable(sweep: Arena.Sweep, ground: Arena.Ground, x: number, y: number, z: number): number?
	local g = ground(x, y, z)
	if g == nil or g < y - 0.01 then
		return nil
	end
	local w = Nav.WIDTH
	for _, d in { { w, 0 }, { -w, 0 }, { 0, w }, { 0, -w } } do
		local e = ground(x + d[1], g, z + d[2])
		if e == nil or math.abs(e - g) > Arena.STEP_UP then
			return nil
		end
	end
	if sweep(x, g + 0.2, z, x, g + Arena.HEADROOM, z) ~= nil then
		return nil
	end
	local r = w * 0.7071
	for _, h in { Arena.STEP_UP + 0.2, Arena.CHEST, 5.2 } do
		for _, d in { { w, 0 }, { -w, 0 }, { 0, w }, { 0, -w }, { r, r }, { r, -r }, { -r, r }, { -r, -r } } do
			if sweep(x, g + h, z, x + d[1], g + h, z + d[2]) ~= nil then
				return nil
			end
		end
	end
	return g
end

-- Can a body's whole width walk the straight line from a to b (feet points on the same storey)?
function Nav.walkable(
	sweep: Arena.Sweep,
	ground: Arena.Ground,
	ax: number,
	ay: number,
	az: number,
	bx: number,
	by: number,
	bz: number
): boolean
	local dx, dz = bx - ax, bz - az
	local len = math.sqrt(dx * dx + dz * dz)
	if len < 1e-6 then
		return false
	end
	local c = Arena.CHEST
	local px, pz = -dz / len * (Nav.WIDTH - 0.05), dx / len * (Nav.WIDTH - 0.05)
	for _, side in { 0, 1, -1 } do
		local ox, oz = px * side, pz * side
		if sweep(ax + ox, ay + c, az + oz, bx + ox, by + c, bz + oz) ~= nil then
			return false
		end
	end
	local n = math.ceil(len)
	local last = ay
	for k = 1, n do
		local t = k / n
		local g = ground(ax + dx * t, last, az + dz * t)
		if g == nil or math.abs(g - last) > Arena.STEP_UP then
			return false
		end
		last = g
	end
	return math.abs(last - by) < 0.05
end

function Nav.build(
	plan: ArenaDataPlan.Plan,
	sweep: Arena.Sweep,
	ground: Arena.Ground
): ({ Arena.NavNode }, { Arena.NavLink }, { Arena.Cover })
	local H, RAIL = Arena.FLOOR_HEIGHT, Arena.RAIL_HEIGHT
	local boxes, kinds = plan.boxes, plan.kinds
	type Node = Arena.NavNode
	local nodes: { Node } = {}
	local links: { Arena.NavLink } = {}
	local cover: { Arena.Cover } = {}
	local linked: { [number]: boolean } = {}
	local byLevel: { [number]: { number } } = {}
	for level = 0, Arena.FLOORS - 1 do
		byLevel[level] = {}
	end

	local function teamAt(x: number, y: number, z: number): number
		for t = 1, 2 do
			if Arena.inRoom(plan.spawnRooms[t], x, y + 0.1, z) then
				return t
			end
		end
		return 0
	end
	local function inExit(x: number, y: number, z: number): boolean
		for _, r in plan.exits do
			if Arena.inRoom(r, x, y + 0.1, z, 1.5) then
				return true
			end
		end
		return false
	end
	local function add(
		x: number,
		y: number,
		z: number,
		floor: number,
		kind: "open" | "cover" | "stair" | "spawn"
	): number
		x, y, z = round(x), round(y), round(z)
		local team = teamAt(x, y, z)
		local id = #nodes + 1
		nodes[id] =
			{ id = id, x = x, y = y, z = z, floor = floor, kind = if team ~= 0 then "spawn" else kind, team = team }
		if team == 0 then
			table.insert(byLevel[floor], id)
		end
		return id
	end
	local function link(a: number, b: number, kind: "walk" | "stair")
		local na, nb = nodes[a], nodes[b]
		local cost = math.sqrt((na.x - nb.x) ^ 2 + (na.y - nb.y) ^ 2 + (na.z - nb.z) ^ 2)
		table.insert(links, { a = a, b = b, cost = cost, kind = kind })
		linked[math.min(a, b) * 65536 + math.max(a, b)] = true
	end
	-- how far the nearest node of the storey is
	local function nearest(x: number, z: number, level: number): number
		local best = math.huge
		for _, id in byLevel[level] do
			local n = nodes[id]
			best = math.min(best, (n.x - x) ^ 2 + (n.z - z) ^ 2)
		end
		return math.sqrt(best)
	end
	-- the floor a body can stand on at a point of a storey, outside the spawn rooms and the way out
	local function floorAt(x: number, z: number, level: number): number?
		local g = Nav.standable(sweep, ground, x, level * H, z)
		if g == nil or g > level * H + Arena.STEP_UP or teamAt(x, g, z) ~= 0 or inExit(x, g, z) then
			return nil
		end
		return g
	end
	local function candidate(x: number, z: number, level: number, apart: number): number?
		x, z = round(x), round(z)
		if nearest(x, z, level) < apart then
			return nil
		end
		local g = floorAt(x, z, level)
		if g ~= nil then
			return add(x, g, z, level, "open")
		end
		return nil
	end
	local function inCore(x: number, z: number): boolean
		return math.abs(x) < Arena.ATRIUM + 1 and math.abs(z) > 21 and math.abs(z) < 31
	end

	-- the node at a point of a storey: one already within `apart` of it, or a new one where a body can stand
	local function nodeAt(x: number, z: number, level: number, apart: number): number?
		local best, bestD = nil, apart
		for _, id in byLevel[level] do
			local n = nodes[id]
			local d = math.sqrt((n.x - x) ^ 2 + (n.z - z) ^ 2)
			if d < bestD then
				best, bestD = id, d
			end
		end
		return best or candidate(x, z, level, 0)
	end
	-- the galleries north and south of the atrium, which the lattice misses, and the ground under the cores
	for level = 0, Arena.FLOORS - 1 do
		for _, s in { -1, 1 } do
			for _, x in { -12, -6, 0, 6, 12 } do
				candidate(x, s * 18.3, level, Nav.CLOSE)
			end
			if level == 0 then
				for _, x in { -6, 0, 6, 12.75 } do
					candidate(x, s * 24, level, Nav.CLOSE)
				end
			end
		end
	end
	-- the stairs: the foot and the head of every flight, on its landings
	local feet: { number } = {}
	local heads: { number } = {}
	local END = (plan.ramps[1].maxX + Arena.ATRIUM) / 2
	for i, fl in plan.flights do
		feet[i] = add(-fl.dir * END, fl.f * H, fl.z, fl.f, "stair")
		heads[i] = add(fl.dir * END, (fl.f + 1) * H, fl.z, fl.f + 1, "stair")
	end
	-- the doorways: a node either side of each, and the link through it
	for _, d in plan.doorways do
		local a = nodeAt(d.ax, d.az, d.level, 1)
		local b = nodeAt(d.bx, d.bz, d.level, 1)
		if a ~= nil and b ~= nil and a ~= b then
			local na, nb = nodes[a], nodes[b]
			if
				not linked[math.min(a, b) * 65536 + math.max(a, b)]
				and Nav.walkable(sweep, ground, na.x, na.y, na.z, nb.x, nb.y, nb.z)
			then
				link(a, b, "walk")
			end
		end
	end
	-- the lattice, storey by storey from the north-west corner, then the holes in it
	local reach = Arena.HALF - Nav.STEP / 2
	for level = 0, Arena.FLOORS - 1 do
		for x = -reach, reach, Nav.STEP do
			for z = -reach, reach, Nav.STEP do
				if not inCore(x, z) then
					candidate(x, z, level, Nav.CLOSE)
				end
			end
		end
	end
	for level = 0, Arena.FLOORS - 1 do
		for x = -Arena.HALF + 2, Arena.HALF - 2, 2 do
			for z = -Arena.HALF + 2, Arena.HALF - 2, 2 do
				if not inCore(x, z) then
					candidate(x, z, level, Nav.GAP)
				end
			end
		end
	end

	-- the cover spots
	local function spot(x: number, z: number, level: number, nx: number, nz: number, low: boolean)
		for _, c in cover do
			local n = nodes[c.node]
			if n.floor == level and (n.x - x) ^ 2 + (n.z - z) ^ 2 < Nav.THIN ^ 2 then
				return
			end
		end
		if inCore(x, z) then
			return
		end
		local g = floorAt(x, z, level)
		if g ~= nil then
			table.insert(cover, { node = add(x, g, z, level, "cover"), nx = nx, nz = nz, low = low })
		end
	end
	local KIND = Arena.KIND
	for i = 1, #kinds do
		local kind = kinds[i]
		if kind ~= KIND.cover and kind ~= KIND.rail and kind ~= KIND.pillar and kind ~= KIND.prop then
			continue
		end
		local k = (i - 1) * 6
		local x0, y0, z0, x1, y1, z1 =
			boxes[k + 1], boxes[k + 2], boxes[k + 3], boxes[k + 4], boxes[k + 5], boxes[k + 6]
		local level = math.floor(y0 / H + 0.01)
		local base = y0 - level * H
		if level < 0 or level >= Arena.FLOORS or base > 1.01 then
			continue -- hung from a ceiling or standing on something else
		end
		local height = y1 - y0
		local low = math.abs(height - RAIL) < 0.05
		local sx, sz = x1 - x0, z1 - z0
		if not low and height < Arena.HEADROOM then
			continue
		end
		if math.min(sx, sz) < (if low then 0.45 else 1.5) or math.max(sx, sz) < 2 then
			continue -- a truss member, a pole, a cable
		end
		-- along each face: one spot for a short face, more for a long one
		local function along(a: number, b: number): { number }
			local span = b - a
			if span <= 10 then
				return { (a + b) / 2 }
			end
			local out: { number } = {}
			local count = math.floor(span / 9)
			for j = 1, count do
				table.insert(out, a + span * (j - 0.5) / count)
			end
			return out
		end
		if sz >= 2 then
			for _, z in along(z0, z1) do
				spot(x0 - Nav.OFF, z, level, 1, 0, low)
				spot(x1 + Nav.OFF, z, level, -1, 0, low)
			end
		end
		if sx >= 2 then
			for _, x in along(x0, x1) do
				spot(x, z0 - Nav.OFF, level, 0, 1, low)
				spot(x, z1 + Nav.OFF, level, 0, -1, low)
			end
		end
	end

	-- walk links: each node to its nearest neighbours on its storey that a body can walk straight to
	local function join(a: number, limit: number, most: number)
		local na = nodes[a]
		local near: { { id: number, d: number } } = {}
		for _, b in byLevel[na.floor] do
			local nb = nodes[b]
			if b ~= a then
				local d = math.sqrt((na.x - nb.x) ^ 2 + (na.z - nb.z) ^ 2)
				if d <= limit and math.abs(na.y - nb.y) <= Arena.STEP_UP then
					table.insert(near, { id = b, d = d })
				end
			end
		end
		table.sort(near, function(p, q): boolean
			if p.d ~= q.d then
				return p.d < q.d
			end
			return p.id < q.id
		end)
		local made = 0
		for _, c in near do
			if made >= most then
				break
			end
			local b = c.id
			if linked[math.min(a, b) * 65536 + math.max(a, b)] then
				made += 1
			else
				local nb = nodes[b]
				if Nav.walkable(sweep, ground, na.x, na.y, na.z, nb.x, nb.y, nb.z) then
					link(a, b, "walk")
					made += 1
				end
			end
		end
	end
	for level = 0, Arena.FLOORS - 1 do
		for _, a in table.clone(byLevel[level]) do
			join(a, Nav.REACH, Nav.DEGREE)
		end
	end
	for i in plan.flights do
		link(feet[i], heads[i], "stair")
	end

	-- the spawn rooms: a hub, and a chain round each baffle and out of each door (written for team 1)
	local roomY = Arena.SPAWN_FLOOR * H
	local hubs: { number } = {}
	for team = 1, 2 do
		local s = if team == 1 then 1 else -1
		local hub = add(s * -48, roomY, 0, Arena.SPAWN_FLOOR, "spawn")
		hubs[team] = hub
		local function chain(points: { { number } })
			local last = hub
			for _, p in points do
				local id = add(s * p[1], roomY, s * p[2], Arena.SPAWN_FLOOR, "open")
				link(last, id, "walk")
				last = id
			end
			join(last, Nav.REACH + 3, 4) -- the node outside the door joins the building
		end
		chain({ { -46, -6.5 }, { -46, -9.5 }, { -57.5, -9.5 }, { -57.5, -17 } })
		chain({ { -57.5, 6.5 }, { -57.5, 9.5 }, { -46.5, 9.5 }, { -46.5, 17 } })
	end

	-- what the links reach from team 1's room
	local function reached(): { [number]: boolean }
		local adjacent: { [number]: { number } } = {}
		for _, l in links do
			adjacent[l.a] = adjacent[l.a] or {}
			adjacent[l.b] = adjacent[l.b] or {}
			table.insert(adjacent[l.a], l.b)
			table.insert(adjacent[l.b], l.a)
		end
		local seen: { [number]: boolean } = { [hubs[1]] = true }
		local queue = { hubs[1] }
		while #queue > 0 do
			local at = table.remove(queue) :: number
			for _, to in adjacent[at] or {} do
				if not seen[to] then
					seen[to] = true
					table.insert(queue, to)
				end
			end
		end
		return seen
	end

	-- MENDING. The links so far join what a straight line joins. Two things are left: a node no link reaches,
	-- in a place a body can walk out of (a nook behind furniture), and two nodes near each other whose way
	-- along the links is far longer than the walk between them (round a desk, when the links go round the
	-- room). For both, the walk itself is found a stud at a time, pulled straight, and nodes are laid at its
	-- corners.
	local size = 2 * Arena.HALF
	local cells: { [number]: number | false } = {}
	local function cell(level: number, ix: number, iz: number): number?
		if ix < 0 or ix >= size or iz < 0 or iz >= size then
			return nil
		end
		local k = (level * size + ix) * size + iz
		local v = cells[k]
		if v == nil then
			v = floorAt(ix - Arena.HALF + 0.5, iz - Arena.HALF + 0.5, level) or false
			cells[k] = v
		end
		return if v then v else nil
	end
	local steps: { [number]: boolean } = {}
	-- may a body step from cell k to its neighbour j (both standable)?
	local function step(level: number, k: number, j: number): boolean
		local key = (level * size * size + math.min(k, j)) * 4 + (if math.abs(k - j) == 1 then 1 else 2)
		local v = steps[key]
		if v == nil then
			local ix, iz, jx, jz = k // size, k % size, j // size, j % size
			v = Nav.walkable(
				sweep,
				ground,
				ix - Arena.HALF + 0.5,
				cell(level, ix, iz) :: number,
				iz - Arena.HALF + 0.5,
				jx - Arena.HALF + 0.5,
				cell(level, jx, jz) :: number,
				jz - Arena.HALF + 0.5
			)
			steps[key] = v
		end
		return v
	end
	-- The walk from node `from`, cell by cell and breadth first, to the first cell `accept` takes (it returns
	-- the node the walk was looking for). Cells outside the box (x0..x1, z0..z1) are not walked.
	local function walk(
		from: number,
		accept: (x: number, g: number, z: number) -> number?,
		x0: number,
		z0: number,
		x1: number,
		z1: number
	): ({ { number } }?, number)
		local n = nodes[from]
		local level = n.floor
		local sx, sz = math.floor(n.x + Arena.HALF), math.floor(n.z + Arena.HALF)
		local parent: { [number]: number } = {}
		local queue: { number } = {}
		local head = 1
		for dx = -1, 1 do
			for dz = -1, 1 do
				local g = cell(level, sx + dx, sz + dz)
				local cx, cz = sx + dx - Arena.HALF + 0.5, sz + dz - Arena.HALF + 0.5
				if g ~= nil and Nav.walkable(sweep, ground, n.x, n.y, n.z, cx, g, cz) then
					local k = (sx + dx) * size + sz + dz
					if parent[k] == nil then
						parent[k] = -1
						table.insert(queue, k)
					end
				end
			end
		end
		while head <= #queue do
			local k = queue[head]
			head += 1
			local ix, iz = k // size, k % size
			local x, z = ix - Arena.HALF + 0.5, iz - Arena.HALF + 0.5
			local g = cell(level, ix, iz) :: number
			local target = accept(x, g, z)
			if target ~= nil then
				local path: { { number } } = {}
				local at = k
				while at ~= -1 do
					local px, pz = at // size, at % size
					table.insert(
						path,
						1,
						{ px - Arena.HALF + 0.5, cell(level, px, pz) :: number, pz - Arena.HALF + 0.5 }
					)
					at = parent[at]
				end
				return path, target
			end
			for _, d in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
				local jx, jz = ix + d[1], iz + d[2]
				local nx, nz = jx - Arena.HALF + 0.5, jz - Arena.HALF + 0.5
				local j = jx * size + jz
				if nx >= x0 and nx <= x1 and nz >= z0 and nz <= z1 and parent[j] == nil then
					if cell(level, jx, jz) ~= nil and step(level, k, j) then
						parent[j] = k
						table.insert(queue, j)
					end
				end
			end
		end
		return nil, 0
	end
	-- A walk pulled straight: from node `from`, the corners at which a straight line stops clearing, to node
	-- `target`. Its length, and the corners (not yet nodes).
	local function pull(from: number, path: { { number } }, target: number): (number, { { number } })
		local goal = nodes[target]
		local cx, cy, cz = nodes[from].x, nodes[from].y, nodes[from].z
		local corners: { { number } } = {}
		local length, i = 0, 0
		while true do
			local far = math.sqrt((cx - goal.x) ^ 2 + (cz - goal.z) ^ 2)
			if far <= Nav.REACH and Nav.walkable(sweep, ground, cx, cy, cz, goal.x, goal.y, goal.z) then
				return length + far, corners
			end
			local pick: number? = nil
			for j = #path, i + 1, -1 do
				local p = path[j]
				local d = math.sqrt((cx - p[1]) ^ 2 + (cz - p[3]) ^ 2)
				if d <= Nav.REACH and d > 0.01 and Nav.walkable(sweep, ground, cx, cy, cz, p[1], p[2], p[3]) then
					pick = j
					length += d
					break
				end
			end
			if pick == nil then
				local at = nodes[from]
				error(
					string.format("NavBuild: the walk from (%.1f, %.1f, %.1f) will not pull straight", at.x, at.y, at.z)
				)
			end
			local p = path[pick :: number]
			table.insert(corners, p)
			cx, cy, cz, i = p[1], p[2], p[3], pick :: number
		end
	end
	-- Lay a pulled walk: a node at each corner (one that is already within SNAP of the corner serves, if
	-- the walk still clears through it), linked in a chain from `from` to `target`.
	local function lay(from: number, corners: { { number } }, target: number)
		local level = nodes[from].floor
		local cur = from
		for i, p in corners do
			local c = nodes[cur]
			local after = corners[i + 1]
			local goal = nodes[target]
			local ax, ay, az = goal.x, goal.y, goal.z
			if after ~= nil then
				ax, ay, az = after[1], after[2], after[3]
			end
			local use: number? = nil
			local best = Nav.SNAP
			for _, other in byLevel[level] do
				local m = nodes[other]
				local d = math.sqrt((m.x - p[1]) ^ 2 + (m.z - p[3]) ^ 2)
				if
					other ~= cur
					and other ~= from
					and d < best
					and math.abs(m.y - p[2]) < 0.05
					and Nav.walkable(sweep, ground, c.x, c.y, c.z, m.x, m.y, m.z)
					and Nav.walkable(sweep, ground, m.x, m.y, m.z, ax, ay, az)
				then
					use, best = other, d
				end
			end
			if use ~= nil then
				if after ~= nil then
					after[1], after[2], after[3] = ax, ay, az
				end
			else
				use = add(p[1], p[2], p[3], level, "open")
			end
			local to = use :: number
			if not linked[math.min(cur, to) * 65536 + math.max(cur, to)] then
				link(cur, to, "walk")
			end
			cur = to
			if cur == target then
				return
			end
		end
		if cur ~= target and not linked[math.min(cur, target) * 65536 + math.max(cur, target)] then
			link(cur, target, "walk")
		end
	end

	-- nodes no link reaches
	local hopeless: { [number]: boolean } = {}
	local function mend(): boolean
		local seen = reached()
		for id = 1, #nodes do
			local n = nodes[id]
			if seen[id] or hopeless[id] or n.team ~= 0 then
				continue
			end
			local level = n.floor
			local path, target = walk(id, function(x: number, g: number, z: number): number?
				local best, found = 36, nil
				for _, other in byLevel[level] do
					local m = nodes[other]
					local d = (m.x - x) ^ 2 + (m.z - z) ^ 2
					if seen[other] and d < best and Nav.walkable(sweep, ground, x, g, z, m.x, m.y, m.z) then
						best, found = d, other
					end
				end
				return found
			end, -Arena.HALF, -Arena.HALF, Arena.HALF, Arena.HALF)
			if path == nil then
				hopeless[id] = true
				continue
			end
			local _, corners = pull(id, path, target)
			lay(id, corners, target)
			return true
		end
		return false
	end
	local mending = true
	while mending do
		mending = mend()
	end

	-- nodes near each other that the links join only by a long way round
	do
		local adjacent: { [number]: { { number } } } = {}
		local have = 0
		local function index()
			for i = have + 1, #links do
				local l = links[i]
				adjacent[l.a] = adjacent[l.a] or {}
				adjacent[l.b] = adjacent[l.b] or {}
				table.insert(adjacent[l.a], { l.b, l.cost })
				table.insert(adjacent[l.b], { l.a, l.cost })
			end
			have = #links
		end
		-- how far each node near `a` is along the links, out to `limit`
		local function along(a: number, limit: number): { [number]: number }
			index()
			local cost: { [number]: number } = { [a] = 0 }
			local open = { a }
			while #open > 0 do
				local bi = 1
				for k = 2, #open do
					if cost[open[k]] < cost[open[bi]] then
						bi = k
					end
				end
				local at = open[bi]
				open[bi] = open[#open]
				open[#open] = nil
				for _, e in adjacent[at] or {} do
					local c = cost[at] + e[2]
					if c <= limit and (cost[e[1]] == nil or c < cost[e[1]]) then
						if table.find(open, e[1]) == nil then
							table.insert(open, e[1])
						end
						cost[e[1]] = c
					end
				end
			end
			return cost
		end
		local limit = Nav.REACH * Nav.DETOUR * 2
		for level = 0, Arena.FLOORS - 1 do
			local snapshot = table.clone(byLevel[level])
			for _, a in snapshot do
				local na = nodes[a]
				local cost = along(a, limit)
				for _, b in snapshot do
					local nb = nodes[b]
					if b <= a or math.abs(na.y - nb.y) > Arena.STEP_UP then
						continue
					end
					local d = math.sqrt((na.x - nb.x) ^ 2 + (na.z - nb.z) ^ 2)
					if d > Nav.REACH or d < 0.5 or (cost[b] or math.huge) <= d * Nav.DETOUR then
						continue
					end
					local path, target = walk(
						a,
						function(x: number, g: number, z: number): number?
							if
								(nb.x - x) ^ 2 + (nb.z - z) ^ 2 < 4
								and Nav.walkable(sweep, ground, x, g, z, nb.x, nb.y, nb.z)
							then
								return b
							end
							return nil
						end,
						math.min(na.x, nb.x) - d,
						math.min(na.z, nb.z) - d,
						math.max(na.x, nb.x) + d,
						math.max(na.z, nb.z) + d
					)
					if path ~= nil then
						local length, corners = pull(a, path, target)
						if (cost[b] or math.huge) > length * Nav.DETOUR then
							lay(a, corners, b)
							cost = along(a, limit)
						end
					end
				end
			end
		end
	end

	-- keep what can be walked to from team 1's room, renumbered in the order it was made
	local seen = reached()
	local renumber: { [number]: number } = {}
	local kept: { Node } = {}
	for id, n in nodes do
		if seen[id] then
			local new = #kept + 1
			renumber[id] = new
			n.id = new
			kept[new] = n
		end
	end
	local keptLinks: { Arena.NavLink } = {}
	for _, l in links do
		if renumber[l.a] and renumber[l.b] then
			table.insert(keptLinks, { a = renumber[l.a], b = renumber[l.b], cost = l.cost, kind = l.kind })
		end
	end
	local keptCover: { Arena.Cover } = {}
	for _, c in cover do
		if renumber[c.node] then
			table.insert(keptCover, { node = renumber[c.node], nx = c.nx, nz = c.nz, low = c.low })
		end
	end
	return kept, keptLinks, keptCover
end

-- The navigation of the plan as it stands: what bake_nav writes and the spec holds the baked file to.
function Nav.compute(): ({ Arena.NavNode }, { Arena.NavLink }, { Arena.Cover })
	local plan = ArenaDataPlan.build()
	local sweep, ground = ArenaGrid.new(plan.boxes, plan.ramps)
	return Nav.build(plan, sweep, ground)
end

local KINDS = { open = 1, cover = 2, stair = 3, spawn = 4 }

local function rows(numbers: { number }, per: number): string
	local out: { string } = {}
	local line: { string } = {}
	for i, v in numbers do
		table.insert(line, string.format("%.14g", v))
		if i % per == 0 or i == #numbers then
			table.insert(out, `\t\t"{table.concat(line, " ")}",`)
			line = {}
		end
	end
	return table.concat(out, "\n")
end

-- The text of src/shared/Minigames/Paintball/ArenaDataNavBaked.luau for a graph.
function Nav.text(nodes: { Arena.NavNode }, links: { Arena.NavLink }, cover: { Arena.Cover }): string
	local n: { number } = {}
	for _, node in nodes do
		table.insert(n, node.x)
		table.insert(n, node.y)
		table.insert(n, node.z)
		table.insert(n, node.floor)
		table.insert(n, KINDS[node.kind])
		table.insert(n, node.team)
	end
	local l: { number } = {}
	for _, link in links do
		table.insert(l, link.a)
		table.insert(l, link.b)
		table.insert(l, if link.kind == "stair" then 2 else 1)
	end
	local c: { number } = {}
	for _, spot in cover do
		table.insert(c, spot.node)
		table.insert(c, spot.nx)
		table.insert(c, spot.nz)
		table.insert(c, if spot.low then 1 else 0)
	end
	return table.concat({
		"--!strict",
		"-- ReplicatedStorage.Shared.Minigames.Paintball.ArenaDataNavBaked",
		"-- GENERATED by tools/games/paintball/arena/bake_nav.luau from ArenaDataPlan: do not edit; run that tool",
		"-- after any change to the plan (tests/unit/paintball_arena_nav.spec.luau fails until you do). The arena's",
		"-- navigation graph and cover spots as rows of numbers, read by ArenaData:",
		"--   nodes   six a node: x y z floor kind team (kind 1 open, 2 cover, 3 stair, 4 spawn), in id order",
		"--   links   three a link: a b kind (1 walk, 2 stair)",
		"--   cover   four a spot: node nx nz low (1 or 0)",
		"-- Interface: { nodes = { string }, links = { string }, cover = { string } }",
		"return {",
		"\tnodes = {",
		rows(n, 24),
		"\t},",
		"\tlinks = {",
		rows(l, 30),
		"\t},",
		"\tcover = {",
		rows(c, 32),
		"\t},",
		"}",
		"",
	}, "\n")
end

return Nav
