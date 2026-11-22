--!strict
-- ReplicatedStorage.Shared.Rides.LookoutLife
-- How the people at the top of the sky lift move (owner D30, 2026-11-22: "the npcs at the top of the skylift dont
-- move!"). Why they did not: the Lookout (venue f3_hilltop) is a box the town's way on foot keeps every walker out
-- of (World/WalkWay.BAKED_VENUES: its top is an area no bridge joins), so the town's brains can never walk there;
-- Rides/SkyLiftService held its host as a statue by the lectern and put every townsperson on an outing straight
-- from the cabin onto a chair, and back. This module is the Lookout's own way on foot, which the service walks
-- held bodies along (kinematic, like every person in town): the host's round, and the visitors' walk from the
-- arrival platform to a table or the terrace's view and back to the boarding platform.
--   * NODES: points in the venue's frame (X across, D into the building, Y over its floor at 116; AlleyLayout's
--     toWorld), on the lift hall's arrival platform and back walkway (floor + 1.5), the dining room's two aisles
--     (in front of and behind the four tables), the terrace's two rows (by the building and by the rail), the
--     telescope and the views over the town. EDGES join them; every edge is a straight walk clear of everything
--     the bake stands there (tests/unit/lookout_life.spec bakes tools/bake/lookout and tools/bake/skylift/Summit
--     in memory and walks every edge with a body's width).
--   * route(from, to) -> { node id } (shortest, both ends included).
--   * HOST: the host's round, looping: greets at the lectern by the door, sees to a table, collects at the
--     counter, goes out to the terrace's tables and back. Each stop holds a few seconds facing its work.
--   * The chairs a visitor may take: the aisle-side chair of each table (APPROACH: table id and side -> the row
--     node it is reached from); seat(place, table, side) -> the chair's world point and its facing.
--   * plan(place, kind, opts) -> { Point } a visitor's walk (the stops' holds and facings in it), and
--     walker(points, speed, loop?) / advance(walker, dt) -> where the body is: world x, y (the surface it is on),
--     z, the Roblox yaw it faces, its speed now (0 while it holds a stop) and the stop's act.
-- Pure; studs. No side effects on require.

local AlleyLayout = require("../Attractions/AlleyLayout")

local LookoutLife = {}

LookoutLife.HOST_SPEED = 6.5 -- studs a second: an unhurried walk (Client/Animation: "walk" under 9)
LookoutLife.VISITOR_SPEED = 5.5
LookoutLife.STAND = 2.0 -- studs behind a chair's back a visitor stands before sitting down and after getting up
LookoutLife.PLATFORM = 1.5 -- the lift hall's platforms and walkway over the floor (Shared/Rides/SkyLift.PLATFORM_HEIGHT)

local P = LookoutLife.PLATFORM

-- stylua: ignore start
LookoutLife.NODES = table.freeze({
	-- the lift hall: along the arrival platform (inside its screen, clear of the bullwheel gantry's column),
	-- to the hall door; round the back walkway to the boarding platform behind its gate
	hall_platform = { -23.5, 5, P }, hall_back = { -23.5, 19, P }, hall_walk = { -23.5, 22.6, P },
	board_walk = { -47, 22.6, P }, board_queue = { -47, 17.5, P },
	hall_edge = { -20.4, 19, P }, -- (the platform's edge in the hall door: a step down to the dining room's floor)
	-- the dining room: in through the hall door, past the fireside corner
	hall_door = { -17.5, 19, 0 }, fireside = { -12, 19, 0 },
	-- the aisle behind the tables (D 8) and the one in front of them (D -4)
	b_m12 = { -12, 8, 0 }, b_m6 = { -6, 8, 0 }, b_1 = { 1, 8, 0 }, b_8 = { 8, 8, 0 }, b_15 = { 15, 8, 0 },
	b_22 = { 22, 8, 0 }, b_29 = { 29, 8, 0 }, b_36 = { 36, 8, 0 }, b_43 = { 43, 8, 0 },
	f_m12 = { -12, -4, 0 }, f_m6 = { -6, -4, 0 }, f_1 = { 1, -4, 0 }, f_8 = { 8, -4, 0 }, f_15 = { 15, -4, 0 },
	f_22 = { 22, -4, 0 }, f_29 = { 29, -4, 0 }, f_36 = { 36, -4, 0 }, f_43 = { 43, -4, 0 },
	-- the host's lectern by the terrace door, and the door itself
	lectern = { 15, -18, 0 }, door_in = { 15, -21.5, 0 },
	-- the terrace: the row by the building (D -29) and the row by the rail (D -41.8), the telescope, the views
	t_m18 = { -18, -29, 0 }, t_m6 = { -6, -29, 0 }, t_1 = { 1, -29, 0 }, t_8 = { 8, -29, 0 }, t_15 = { 15, -29, 0 },
	t_22 = { 22, -29, 0 }, t_29 = { 29, -29, 0 }, t_36 = { 36, -29, 0 }, t_43 = { 43, -29, 0 },
	r_m18 = { -18, -41.8, 0 }, r_m6 = { -6, -41.8, 0 }, r_1 = { 1, -41.8, 0 }, r_8 = { 8, -41.8, 0 },
	telescope = { 15, -41.6, 0 },
	r_22 = { 22, -41.8, 0 }, r_29 = { 29, -41.8, 0 }, r_36 = { 36, -41.8, 0 }, r_43 = { 43, -41.8, 0 },
	view_m6 = { -6, -44.6, 0 }, view_1 = { 1, -44.6, 0 }, view_29 = { 29, -44.6, 0 }, view_43 = { 43, -44.6, 0 },
} :: { [string]: { number } })

local EDGES: { { string } } = {
	{ "hall_platform", "hall_back" }, { "hall_back", "hall_walk" }, { "hall_walk", "board_walk" },
	{ "board_walk", "board_queue" }, { "hall_back", "hall_edge" }, { "hall_edge", "hall_door" }, { "hall_door", "fireside" }, { "fireside", "b_m12" },
	{ "b_m12", "f_m12" }, { "b_1", "f_1" }, { "b_15", "f_15" }, { "b_29", "f_29" }, { "b_43", "f_43" },
	{ "f_15", "lectern" }, { "lectern", "door_in" }, { "door_in", "t_15" },
	{ "t_m18", "r_m18" }, { "t_1", "r_1" }, { "t_15", "telescope" }, { "t_29", "r_29" }, { "t_43", "r_43" },
	{ "r_m6", "view_m6" }, { "r_1", "view_1" }, { "r_29", "view_29" }, { "r_43", "view_43" },
}
-- stylua: ignore end
for _, row in
	{
		{ "b_m12", "b_m6", "b_1", "b_8", "b_15", "b_22", "b_29", "b_36", "b_43" },
		{ "f_m12", "f_m6", "f_1", "f_8", "f_15", "f_22", "f_29", "f_36", "f_43" },
		{ "t_m18", "t_m6", "t_1", "t_8", "t_15", "t_22", "t_29", "t_36", "t_43" },
		{ "r_m18", "r_m6", "r_1", "r_8", "telescope", "r_22", "r_29", "r_36", "r_43" },
	}
do
	for i = 1, #row - 1 do
		table.insert(EDGES, { row[i], row[i + 1] })
	end
end
LookoutLife.EDGES = table.freeze(EDGES)

-- The tables (the venue's anchors, as tools/bake/lookout table4 seats them: a chair 2.7 out on each side) and the
-- row node from which each one's aisle-side chairs are reached: "front" is the chair on the table's -D side.
-- stylua: ignore
LookoutLife.TABLES = table.freeze({
	table_1 = { -6, 2 }, table_2 = { 8, 2 }, table_3 = { 22, 2 }, table_4 = { 36, 2 },
	terrace_1 = { -6, -36 }, terrace_2 = { 8, -36 }, terrace_3 = { 22, -36 }, terrace_4 = { 36, -36 },
} :: { [string]: { number } })
LookoutLife.CHAIR_OUT = 2.7
-- stylua: ignore
LookoutLife.APPROACH = table.freeze({
	table_1 = { front = "f_m6", back = "b_m6" }, table_2 = { front = "f_8", back = "b_8" },
	table_3 = { front = "f_22", back = "b_22" }, table_4 = { front = "f_36", back = "b_36" },
	terrace_1 = { front = "r_m6", back = "t_m6" }, terrace_2 = { front = "r_8", back = "t_8" },
	terrace_3 = { front = "r_22", back = "t_22" }, terrace_4 = { front = "r_36", back = "t_36" },
} :: { [string]: { front: string, back: string } })

export type Stop = { node: string, hold: number, act: string?, look: { number }? } -- look: a local {X, D} to face
-- The host's round (it loops): the lectern by the door, a dining table, the counter, the terrace's tables.
-- stylua: ignore
LookoutLife.HOST = table.freeze({
	{ node = "lectern", hold = 12, act = "greet", look = { 15, -25 } },
	{ node = "f_m6", hold = 5, act = "serve", look = { -6, 2 } },
	{ node = "b_22", hold = 5, act = "serve", look = { 22, 2 } },
	{ node = "b_36", hold = 8, act = "serve", look = { 36, 12 } }, -- at the counter
	{ node = "t_8", hold = 5, act = "serve", look = { 8, -36 } },
	{ node = "r_29", hold = 5, act = "serve", look = { 29, -36 } },
	{ node = "t_43", hold = 4, act = "watch", look = { 43, -46 } },
} :: { Stop })
-- What a visitor who does not sit down does: the telescope, then the view from the rail.
-- stylua: ignore
LookoutLife.STROLL = table.freeze({
	{ node = "telescope", hold = 14, act = "look", look = { 15, -44 } },
	{ node = "view_1", hold = 12, act = "look", look = { 1, -60 } },
	{ node = "view_29", hold = 10, act = "look", look = { 29, -60 } },
} :: { Stop })

export type Point = {
	x: number,
	y: number,
	z: number,
	hold: number?, -- seconds standing here
	act: string?,
	yaw: number?, -- the Roblox yaw to face while holding (nil: as it walked in)
	sit: boolean?, -- (a visitor's chair: the service seats the body here)
}

local function dist(a: { number }, b: { number }): number
	return math.sqrt((a[1] - b[1]) ^ 2 + (a[2] - b[2]) ^ 2)
end

local adjacency: { [string]: { string } }? = nil
local function neighbours(): { [string]: { string } }
	if adjacency == nil then
		local adj: { [string]: { string } } = {}
		for id in LookoutLife.NODES do
			adj[id] = {}
		end
		for _, e in LookoutLife.EDGES do
			table.insert(adj[e[1]], e[2])
			table.insert(adj[e[2]], e[1])
		end
		adjacency = adj
	end
	return adjacency :: { [string]: { string } }
end

-- The shortest way between two nodes (Dijkstra over a few dozen nodes), both ends included; nil when none.
function LookoutLife.route(from: string, to: string): { string }?
	local N = LookoutLife.NODES
	assert(N[from] and N[to], `LookoutLife.route: unknown node {from} or {to}`)
	local best: { [string]: number } = { [from] = 0 }
	local prev: { [string]: string } = {}
	local done: { [string]: boolean } = {}
	local adj = neighbours()
	while true do
		local at, d = nil :: string?, math.huge
		for id, v in best do
			if not done[id] and v < d then
				at, d = id, v
			end
		end
		if at == nil then
			return nil
		end
		local here = at :: string
		if here == to then
			break
		end
		done[here] = true
		for _, nb in adj[here] do
			local v = d + dist(N[here], N[nb])
			if best[nb] == nil or v < best[nb] then
				best[nb], prev[nb] = v, here
			end
		end
	end
	local out = { to }
	local at = to
	while at ~= from do
		at = prev[at]
		table.insert(out, 1, at)
	end
	return out
end

-- A local point in the world: x, y (the surface), z.
function LookoutLife.toWorld(place: AlleyLayout.Place, X: number, D: number, Y: number): (number, number, number)
	return AlleyLayout.toWorld(place, X, Y, D)
end

-- The Roblox yaw that faces from local (X0, D0) toward local (X1, D1) (CFrame.Angles(0, yaw, 0) looks along it).
function LookoutLife.yawToward(place: AlleyLayout.Place, X0: number, D0: number, X1: number, D1: number): number
	local dx, dz = AlleyLayout.dirToWorld(place, X1 - X0, D1 - D0)
	return math.atan2(-dx, -dz)
end

local function nodePoint(place: AlleyLayout.Place, id: string): Point
	local n = LookoutLife.NODES[id]
	local x, y, z = LookoutLife.toWorld(place, n[1], n[2], n[3])
	return { x = x, y = y, z = z }
end

-- Append the walk from node `from` to node `to` (without `from` itself) to `out`.
local function walkTo(place: AlleyLayout.Place, out: { Point }, from: string, to: string)
	local r = LookoutLife.route(from, to)
	assert(r, `LookoutLife: no way from {from} to {to}`)
	for i = 2, #r do
		table.insert(out, nodePoint(place, r[i]))
	end
end

local function holdAt(place: AlleyLayout.Place, out: { Point }, s: Stop)
	local last = out[#out]
	last.hold, last.act = s.hold, s.act
	if s.look then
		local n = LookoutLife.NODES[s.node]
		last.yaw = LookoutLife.yawToward(place, n[1], n[2], s.look[1], s.look[2])
	end
end

-- The host's round as world points, starting and ending at the lectern (a walker loops it).
function LookoutLife.hostRound(place: AlleyLayout.Place): { Point }
	local stops = LookoutLife.HOST
	local out = { nodePoint(place, stops[1].node) }
	holdAt(place, out, stops[1])
	for i = 2, #stops do
		walkTo(place, out, stops[i - 1].node, stops[i].node)
		holdAt(place, out, stops[i])
	end
	walkTo(place, out, stops[#stops].node, stops[1].node)
	table.remove(out) -- (the lectern again: the loop's first point)
	return out
end

-- A chair at one of the tables: its world point at floor level, the yaw that faces the table, and the point a
-- visitor stands at behind it (STAND behind its back, toward the aisle it is reached from).
function LookoutLife.chair(place: AlleyLayout.Place, tableId: string, side: string): (Point, number, Point, string)
	local tbl = LookoutLife.TABLES[tableId]
	local ap = LookoutLife.APPROACH[tableId]
	assert(tbl and ap, `LookoutLife.chair: unknown table {tableId}`)
	local dir = if side == "front" then -1 else 1
	local cX, cD = tbl[1], tbl[2] + dir * LookoutLife.CHAIR_OUT
	local node = if side == "front" then ap.front else ap.back
	local sX, sD = cX, cD + dir * LookoutLife.STAND
	local x, y, z = LookoutLife.toWorld(place, cX, cD, 0)
	local sx, sy, sz = LookoutLife.toWorld(place, sX, sD, 0)
	return { x = x, y = y, z = z },
		LookoutLife.yawToward(place, cX, cD, tbl[1], tbl[2]),
		{ x = sx, y = sy, z = sz },
		node
end

export type PlanOpts = {
	from: { number }?, -- the world x, y, z it starts at (the arrival platform's spot); default the platform node
	tableId: string?, -- a diner: the table and side ("front" | "back") of its chair
	side: string?,
	dine: number?, -- seconds seated
	strollFrom: number?, -- a stroller: the first of STROLL's stops it makes (it makes them all, in turn)
}

-- A visitor's walk: from the arrival platform to its chair (sits there `dine` seconds) or round the STROLL stops,
-- then to the boarding platform's queue behind the gate (its last point, where it waits for a cabin down).
function LookoutLife.plan(place: AlleyLayout.Place, opts: PlanOpts): { Point }
	local out: { Point } = {}
	if opts.from then
		local f = opts.from
		table.insert(out, { x = f[1], y = f[2], z = f[3] })
	end
	table.insert(out, nodePoint(place, "hall_platform"))
	local at = "hall_platform"
	if opts.tableId then
		local seat, yaw, stand, node = LookoutLife.chair(place, opts.tableId, opts.side or "front")
		walkTo(place, out, at, node)
		table.insert(out, stand)
		table.insert(
			out,
			{ x = seat.x, y = seat.y, z = seat.z, hold = opts.dine or 0, act = "dine", yaw = yaw, sit = true }
		)
		table.insert(out, { x = stand.x, y = stand.y, z = stand.z })
		table.insert(out, nodePoint(place, node))
		at = node
	else
		local n = #LookoutLife.STROLL
		local first = opts.strollFrom or 1
		for k = 0, n - 1 do
			local s = LookoutLife.STROLL[(first - 1 + k) % n + 1]
			walkTo(place, out, at, s.node)
			holdAt(place, out, s)
			at = s.node
		end
	end
	walkTo(place, out, at, "board_queue")
	local q = out[#out]
	local bw = LookoutLife.NODES.board_walk
	local bq = LookoutLife.NODES.board_queue
	q.yaw = LookoutLife.yawToward(place, bq[1], bq[2], bq[1], bq[2] - (bw[2] - bq[2])) -- facing the gate
	q.act = "queue"
	return out
end

export type Walker = {
	points: { Point },
	speed: number,
	loop: boolean,
	i: number, -- the point it is at or walking from
	along: number, -- studs along the leg from point i to point i + 1
	held: number, -- seconds held at point i
	yaw: number,
	done: boolean, -- (not a loop) at its last point
}

function LookoutLife.walker(points: { Point }, speed: number, loop: boolean?): Walker
	assert(#points >= 1, "LookoutLife.walker: no points")
	return {
		points = points,
		speed = speed,
		loop = loop == true,
		i = 1,
		along = 0,
		held = 0,
		yaw = points[1].yaw or 0,
		done = #points == 1 and loop ~= true,
	}
end

-- Move the walker on by dt seconds. Returns x, y, z, yaw, speed now (0 holding), the act of the stop it holds
-- (nil walking), and the point it holds (nil walking).
function LookoutLife.advance(w: Walker, dt: number): (number, number, number, number, number, string?, Point?)
	local pts = w.points
	local n = #pts
	local budget = math.max(0, dt)
	local guard = 0
	while guard < 4 * n + 4 do
		guard += 1
		local p = pts[w.i]
		local hold = p.hold or 0
		if w.along == 0 and w.held < hold then
			local wait = math.min(hold - w.held, budget)
			w.held += wait
			budget -= wait
			if p.yaw then
				w.yaw = p.yaw
			end
			if w.held < hold or budget <= 0 then
				return p.x, p.y, p.z, w.yaw, 0, p.act, p
			end
		end
		local j = w.i + 1
		if j > n then
			if not w.loop then
				w.done = true
				if p.yaw then
					w.yaw = p.yaw
				end
				return p.x, p.y, p.z, w.yaw, 0, p.act, p
			end
			j = 1
		end
		local q = pts[j]
		local dx, dy, dz = q.x - p.x, q.y - p.y, q.z - p.z
		local len = math.sqrt(dx * dx + dz * dz)
		if len > 1e-6 then
			w.yaw = math.atan2(-dx, -dz)
		end
		local step = w.speed * budget
		if w.along + step < len then
			w.along += step
			local f = w.along / len
			return p.x + dx * f, p.y + dy * f, p.z + dz * f, w.yaw, w.speed, nil, nil
		end
		-- reached q: spend what is left of the budget there
		budget -= if w.speed > 0 then (len - w.along) / w.speed else budget
		w.i, w.along, w.held = j, 0, 0
		if budget <= 1e-9 and (q.hold or 0) <= 0 and not (j == n and not w.loop) then
			return q.x, q.y, q.z, w.yaw, w.speed, nil, nil
		end
	end
	local p = pts[w.i]
	return p.x, p.y, p.z, w.yaw, 0, p.act, p
end

return LookoutLife
