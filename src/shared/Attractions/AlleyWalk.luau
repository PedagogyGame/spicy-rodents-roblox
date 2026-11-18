--!strict
-- ReplicatedStorage.Shared.Attractions.AlleyWalk
-- The way on foot between two points in and round the bowling alley, never through a wall, a counter or across a
-- lane: the alley's own HospitalLayout.walk. People here are kinematic (nothing stops a walker at a wall), so an
-- employee let go by a player, a bitten employee's walk out to the hospital and the walk back to work all need a
-- way that goes by the doors. tests/unit/alley_walk.spec.luau walks a body along it through the baked building.
--   * The graph: every leg of AlleyLayout.ROUTES (but the bin run) and of every employee's loop (Shared/Attractions/AlleyStaff; the
--     bake's walk test and the staff spec hold all of them clear), split where one leg's end lies on another, plus
--     the ramp from the walk outside the main doors (OUTSIDE) up to the landing.
--   * Joining it from a point inside: straight to the nearest leg in the same room (ZONES; behind the settees
--     counts as the concourse), as HospitalLayout.walk joins its lanes: that one short hop is the only part of a
--     way the bake does not keep clear (it may brush a stool or a table's corner in the room the body stands in). From a point on the lanes (a player cannot get there: the LaneGuard), straight
--     back down the lane to the mop line behind the approaches.
--   * From a point outside the building: round the building's outline (the hall, the wing, the forecourt and the
--     rear stoop as one box, grown by MARGIN) by its corners, to the walk outside the main doors (OUTSIDE): the
--     rear exit's push-bar doors are shut, so the bin run is no way in or out. The rear alley counts as outside.
-- Interface: way(place, x0, z0, x1, z1) -> { {x, z} } (world studs: the points after the start, ending at the
--   goal); outside(place) -> (x, z) (the spot on the walk in front of the main doors: where a walk in from the
--   town ends and a walk out begins); localWay(X0, D0, X1, D1) -> { {X, D} } (the same in the alley's frame);
--   OUTSIDE, MARGIN
-- Pure; studs. No side effects on require (the graph is built on the first call).

local AlleyLayout = require("./AlleyLayout")
local AlleyStaff = require("./AlleyStaff")

local L = AlleyLayout

local AlleyWalk = {}

AlleyWalk.MARGIN = 3 -- studs the way round the building keeps from its outline
-- the walk in front of the main doors, below the ramp's foot (the steps walk from Bowl Lane meets it)
AlleyWalk.OUTSIDE = { x = (L.RAMP.x0 + L.RAMP.x1) / 2, d = L.RAMP.d0 - AlleyWalk.MARGIN - 0.5 }

local ON_LEG = 0.05 -- studs: a leg's end this close to another leg splits it there

-- the outline a way outside goes round: the hall and the wing, the forecourt (its planters and the ramp) and the
-- rear exit's stoop and its steps, as one box in the alley's frame
local BOX = {
	x0 = L.STOOP.x0,
	x1 = L.X1 + L.WALL_T,
	d0 = L.RAMP.d0,
	d1 = L.REAR_WALL_D + L.WALL_T + L.STOOP.depth + L.STOOP.steps * L.STOOP.tread,
}

type Graph = { nodes: { { number } }, links: { { { number } } }, legs: { { number } } }
local graph: Graph? = nil

local function build(): Graph
	local nodes: { { number } } = {}
	local index: { [string]: number } = {}
	local function node(X: number, D: number): number
		local key = string.format("%.2f,%.2f", X, D)
		local i = index[key]
		if i == nil then
			table.insert(nodes, { X, D })
			i = #nodes
			index[key] = i
		end
		return i
	end
	local raw: { { number } } = {} -- legs as node pairs
	local function leg(a: { number }, b: { number })
		local i, j = node(a[1], a[2]), node(b[1], b[2])
		if i ~= j then
			table.insert(raw, { i, j })
		end
	end
	for id, r in L.ROUTES do
		if id == "bins" then
			continue -- out through the push-bar doors: they are shut (the way out is by the main doors)
		end
		for k = 1, #r - 1 do
			leg(r[k], r[k + 1])
		end
	end
	for _, e in AlleyStaff.EMPLOYEES do
		local n = #e.stops
		for k = 1, n do
			local a, b = e.stops[k], e.stops[k % n + 1]
			leg({ a.x, a.d }, { b.x, b.d })
		end
	end
	local welcome = L.ROUTES.welcome[1]
	leg({ AlleyWalk.OUTSIDE.x, AlleyWalk.OUTSIDE.d }, welcome)
	-- split every leg at the nodes that lie on it (a route that meets another part way along)
	local legs: { { number } } = {}
	for _, l in raw do
		local a, b = nodes[l[1]], nodes[l[2]]
		local ex, ed = b[1] - a[1], b[2] - a[2]
		local len2 = ex * ex + ed * ed
		local cuts: { { number } } = {}
		for i, p in nodes do
			if i ~= l[1] and i ~= l[2] then
				local t = ((p[1] - a[1]) * ex + (p[2] - a[2]) * ed) / len2
				if t > 0 and t < 1 then
					local dx, dd = a[1] + ex * t - p[1], a[2] + ed * t - p[2]
					if dx * dx + dd * dd < ON_LEG * ON_LEG then
						table.insert(cuts, { t, i })
					end
				end
			end
		end
		table.sort(cuts, function(u, v)
			return u[1] < v[1]
		end)
		local from = l[1]
		for _, c in cuts do
			table.insert(legs, { from, c[2] })
			from = c[2]
		end
		table.insert(legs, { from, l[2] })
	end
	local links: { { { number } } } = {}
	for i = 1, #nodes do
		links[i] = {}
	end
	local seen: { [string]: boolean } = {}
	local unique: { { number } } = {}
	for _, l in legs do
		local i, j = math.min(l[1], l[2]), math.max(l[1], l[2])
		local key = `{i},{j}`
		if not seen[key] then
			seen[key] = true
			table.insert(unique, { i, j })
			local a, b = nodes[i], nodes[j]
			local len = math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2)
			table.insert(links[i], { j, len })
			table.insert(links[j], { i, len })
		end
	end
	return { nodes = nodes, links = links, legs = unique }
end

local function theGraph(): Graph
	local g = graph
	if g then
		return g
	end
	local built = build()
	graph = built
	return built
end

local function dist(ax: number, ad: number, bx: number, bd: number): number
	return math.sqrt((bx - ax) ^ 2 + (bd - ad) ^ 2)
end

-- the room a point is in (the first zone that holds it; of the outdoor ones only the forecourt), or nil
local function zoneAt(X: number, D: number): AlleyLayout.Zone?
	for _, z: AlleyLayout.Zone in L.ZONES do
		local id: string = z.id
		local outdoor = z.outside == true and id ~= "forecourt"
		if outdoor then
			continue
		end
		if X >= z.x0 and X <= z.x1 and D >= z.d0 and D <= z.d1 then
			if id == "settees" and D < L.SETTEE_D - 2.75 then
				return L.zone("concourse") -- behind the settees' backs: on the concourse's side of them
			end
			return z
		end
	end
	return nil
end

local function inZone(z: AlleyLayout.Zone, X: number, D: number): boolean
	local g = 0.01
	return X >= z.x0 - g and X <= z.x1 + g and D >= z.d0 - g and D <= z.d1 + g
end

-- An attachment: the graph is joined at node `node` after walking `points` (in the alley's frame) at a cost of `cost`.
type Attach = { node: number, cost: number, points: { { number } } }
-- A leg joined part way: the point on it and the leg.
type Foot = { X: number, D: number, leg: { number }, off: number }

type Rect = { x0: number, x1: number, d0: number, d1: number }

-- does the segment cross the rectangle grown by `grow`? (Liang-Barsky)
local function crosses(r: Rect, ax: number, ad: number, bx: number, bd: number, grow: number): boolean
	local x0, x1, d0, d1 = r.x0 - grow, r.x1 + grow, r.d0 - grow, r.d1 + grow
	local t0, t1 = 0, 1
	local dx, dd = bx - ax, bd - ad
	for _, c in { { -dx, ax - x0 }, { dx, x1 - ax }, { -dd, ad - d0 }, { dd, d1 - ad } } do
		local p, q = c[1], c[2]
		if math.abs(p) < 1e-9 then
			if q < 0 then
				return false
			end
		else
			local t = q / p
			if p < 0 then
				t0 = math.max(t0, t)
			else
				t1 = math.min(t1, t)
			end
			if t0 > t1 then
				return false
			end
		end
	end
	return true
end

-- what stands on the games room's floor that the plan knows of (the pool tables, the air hockey table, the
-- room's fixtures): a hop onto the graph goes round them when another leg allows
local TABLES: { Rect }? = nil
local function tables(): { Rect }
	local out = TABLES
	if out then
		return out
	end
	do
		local list: { Rect } = {}
		for _, t in L.POOL_TABLES do
			table.insert(list, { x0 = t.x - 3.4, x1 = t.x + 3.4, d0 = t.d - 6.1, d1 = t.d + 6.1 })
		end
		local ah, size = L.AIR_HOCKEY, L.AIR_HOCKEY_SIZE
		local alongX = math.abs(math.cos(ah.yaw)) > 0.5
		local hx = if alongX then size.along / 2 else size.across / 2
		local hd = if alongX then size.across / 2 else size.along / 2
		table.insert(list, { x0 = ah.x - hx, x1 = ah.x + hx, d0 = ah.d - hd, d1 = ah.d + hd })
		for _, f in L.GAMES_FIXTURES do
			table.insert(list, { x0 = f.x0, x1 = f.x1, d0 = f.d0, d1 = f.d1 })
		end
		TABLES = list
		return list
	end
end

local BODY = 0.9 -- studs: half a person's width

local function hopClear(X: number, D: number, px: number, pd: number): boolean
	for _, r in tables() do
		if crosses(r, X, D, px, pd, BODY) then
			return false
		end
	end
	return true
end

-- where a point inside joins the graph: the nearest point of a leg in its room that the hop there reaches without
-- crossing a table the plan knows of (the nearest one when every hop does; any leg when its room has none)
local function footOf(g: Graph, X: number, D: number): Foot
	local z = zoneAt(X, D)
	if z and z.id == "lanes" then
		-- on a lane (or among its machines): straight back down it to the line behind the approaches
		local f = footOf(g, X, AlleyStaff.APPROACH_MOP)
		f.off = dist(X, D, f.X, f.D)
		return f
	end
	local inRoom: { Foot } = {}
	local bestAny: Foot? = nil
	for _, l in g.legs do
		local a, b = g.nodes[l[1]], g.nodes[l[2]]
		local ex, ed = b[1] - a[1], b[2] - a[2]
		local t = math.clamp(((X - a[1]) * ex + (D - a[2]) * ed) / (ex * ex + ed * ed), 0, 1)
		for _, u in { t, 0, 1 } do
			local px, pd = a[1] + ex * u, a[2] + ed * u
			local f = { X = px, D = pd, leg = l, off = dist(X, D, px, pd) }
			if bestAny == nil or f.off < bestAny.off then
				bestAny = f
			end
			if z and inZone(z, px, pd) then
				table.insert(inRoom, f)
			end
		end
	end
	table.sort(inRoom, function(u, v)
		return u.off < v.off
	end)
	for _, f in inRoom do
		if hopClear(X, D, f.X, f.D) then
			return f
		end
	end
	return (inRoom[1] or bestAny) :: Foot
end

local function inBox(X: number, D: number, grow: number): boolean
	return X > BOX.x0 - grow and X < BOX.x1 + grow and D > BOX.d0 - grow and D < BOX.d1 + grow
end

-- the way outside from (X, D) to (tx, td) round the box: straight, or by one corner, or by two neighbouring ones
local function round(X: number, D: number, tx: number, td: number): { { number } }
	local function blocked(ax: number, ad: number, bx: number, bd: number, grow: number): boolean
		return crosses(BOX, ax, ad, bx, bd, grow)
	end
	local m = AlleyWalk.MARGIN
	local test = m - 0.5
	local corners = {
		{ BOX.x0 - m, BOX.d0 - m },
		{ BOX.x1 + m, BOX.d0 - m },
		{ BOX.x1 + m, BOX.d1 + m },
		{ BOX.x0 - m, BOX.d1 + m },
	}
	if not blocked(X, D, tx, td, test) then
		return { { tx, td } }
	end
	local best, bestLen = nil, math.huge
	for i, c in corners do
		if not blocked(X, D, c[1], c[2], test) then
			if not blocked(c[1], c[2], tx, td, test) then
				local len = dist(X, D, c[1], c[2]) + dist(c[1], c[2], tx, td)
				if len < bestLen then
					best, bestLen = { c, { tx, td } }, len
				end
			end
			for _, step in { 1, -1 } do
				local c2 = corners[(i - 1 + step) % 4 + 1]
				if not blocked(c2[1], c2[2], tx, td, test) then
					local len = dist(X, D, c[1], c[2]) + dist(c[1], c[2], c2[1], c2[2]) + dist(c2[1], c2[2], tx, td)
					if len < bestLen then
						best, bestLen = { c, c2, { tx, td } }, len
					end
				end
			end
		end
	end
	return best or { { tx, td } }
end

local function length(X: number, D: number, points: { { number } }): number
	local n, px, pd = 0, X, D
	for _, p in points do
		n += dist(px, pd, p[1], p[2])
		px, pd = p[1], p[2]
	end
	return n
end

-- the ways a point joins the graph (each ending on a node), and the foot on a leg when it joins part way
local function attach(g: Graph, X: number, D: number): ({ Attach }, Foot?)
	if AlleyStaff.insideLocal(X, D) or zoneAt(X, D) ~= nil then
		local f = footOf(g, X, D)
		local out = {}
		for _, i in f.leg do
			local n = g.nodes[i]
			table.insert(out, {
				node = i,
				cost = f.off + dist(f.X, f.D, n[1], n[2]),
				points = { { f.X, f.D }, { n[1], n[2] } },
			})
		end
		return out, f
	end
	-- outside: off the box first when the point is in it (behind the wing), then round it to a door
	local pre: { { number } } = {}
	local sx, sd = X, D
	local m = AlleyWalk.MARGIN
	if inBox(X, D, m - 0.5) then
		local outs = {
			{ BOX.x0 - m, D },
			{ BOX.x1 + m, D },
			{ X, BOX.d0 - m },
			{ X, BOX.d1 + m },
		}
		table.sort(outs, function(u, v)
			return dist(X, D, u[1], u[2]) < dist(X, D, v[1], v[2])
		end)
		sx, sd = outs[1][1], outs[1][2]
		table.insert(pre, { sx, sd })
	end
	local door = AlleyWalk.OUTSIDE
	local i = 1
	for k, n in g.nodes do
		if math.abs(n[1] - door.x) + math.abs(n[2] - door.d) < 0.01 then
			i = k
		end
	end
	local points = table.clone(pre)
	for _, p in round(sx, sd, door.x, door.d) do
		table.insert(points, p)
	end
	return { { node = i, cost = length(X, D, points), points = points } }, nil
end

local function reversed(points: { { number } }, from: { number }?): { { number } }
	-- the points of a way walked backwards, from its last point's predecessor back to `from`
	local out = {}
	for k = #points - 1, 1, -1 do
		table.insert(out, points[k])
	end
	if from then
		table.insert(out, from)
	end
	return out
end

-- localWay(X0, D0, X1, D1): the way in the alley's frame (the points after the start, the goal last)
function AlleyWalk.localWay(X0: number, D0: number, X1: number, D1: number): { { number } }
	local g = theGraph()
	local starts, sf = attach(g, X0, D0)
	local goals, gf = attach(g, X1, D1)
	local out: { { number } } = {}
	local function push(p: { number })
		local last = out[#out]
		local lx, ld = if last then last[1] else X0, if last then last[2] else D0
		if math.abs(lx - p[1]) + math.abs(ld - p[2]) > 0.05 then
			table.insert(out, { p[1], p[2] })
		end
	end
	-- both join the same leg: along it
	local direct = math.huge
	if sf and gf and sf.leg == gf.leg then
		direct = sf.off + dist(sf.X, sf.D, gf.X, gf.D) + gf.off
	end
	local n = #g.nodes
	local d: { number } = table.create(n, math.huge)
	local prev: { number } = table.create(n, 0)
	local via: { Attach? } = {}
	local done: { boolean } = table.create(n, false)
	for _, s in starts do
		if s.cost < d[s.node] then
			d[s.node] = s.cost
			via[s.node] = s
		end
	end
	for _ = 1, n do
		local u, best = 0, math.huge
		for i = 1, n do
			if not done[i] and d[i] < best then
				u, best = i, d[i]
			end
		end
		if u == 0 then
			break
		end
		done[u] = true
		for _, e in g.links[u] do
			if best + e[2] < d[e[1]] then
				d[e[1]] = best + e[2]
				prev[e[1]] = u
				via[e[1]] = nil
			end
		end
	end
	local goal: Attach? = nil
	local total = math.huge
	for _, a in goals do
		if d[a.node] + a.cost < total then
			goal, total = a, d[a.node] + a.cost
		end
	end
	if goal == nil or direct <= total then
		if sf and gf then
			push({ sf.X, sf.D })
			push({ gf.X, gf.D })
		end
		push({ X1, D1 })
		return out
	end
	local chain: { number } = {}
	local at = goal.node
	while at ~= 0 do
		table.insert(chain, 1, at)
		if via[at] then
			break
		end
		at = prev[at]
	end
	local first = via[chain[1]] :: Attach
	for _, p in first.points do
		push(p)
	end
	for _, i in chain do
		push(g.nodes[i])
	end
	for _, p in reversed(goal.points, { X1, D1 }) do
		push(p)
	end
	return out
end

-- way(place, x0, z0, x1, z1): the same in world studs
function AlleyWalk.way(place: AlleyLayout.Place, x0: number, z0: number, x1: number, z1: number): { { number } }
	local X0, _, D0 = L.toLocal(place, x0, 0, z0)
	local X1, _, D1 = L.toLocal(place, x1, 0, z1)
	local out = {}
	for _, p in AlleyWalk.localWay(X0, D0, X1, D1) do
		local x, _, z = L.toWorld(place, p[1], 0, p[2])
		table.insert(out, { x, z })
	end
	return out
end

-- the spot on the walk in front of the main doors, in world studs
function AlleyWalk.outside(place: AlleyLayout.Place): (number, number)
	local x, _, z = L.toWorld(place, AlleyWalk.OUTSIDE.x, 0, AlleyWalk.OUTSIDE.d)
	return x, z
end

return AlleyWalk
