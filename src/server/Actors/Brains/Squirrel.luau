--!strict
-- ServerScriptService.Server.Actors.Brains.Squirrel
-- Squirrel brain, minimal W0 version (spike S5): route running on the rail network. Runs along a
-- route for a while, idles 1-3 s, transfers to a linked route when it passes a link (routes within
-- 1.7 u, routes_movement §3, §11), reverses at an end. Rail speeds walk 7.2 / sprint 12.2 u/s with
-- x0.6 on wood kinds (trunk, branch, bridge, lookout) [routes_movement §10]. The motor
-- (Server/AI/Kinematics) advances `s` every frame; the brain only sets routeId, dir, speed.
-- W1 replaces the polyline data with Shared/Routes (Curve, Registry, Graph, Motion).
-- Events: "startle" { x?, z? } (a full-sprint flee for 3-6 s; given where the fright is, along its route away from it),
-- "bait" { x, z, untilTime } (a pile of peanuts or bird seed near its
-- route: it goes to the route's nearest point and stays there until untilTime or a startle).
-- Interface: new(actor, params), think, suspend, resume, onEvent. Pure; studs via Config/Units.

local Import = require("../../Import")
local Units = Import.shared("Config/Units") :: typeof(require("../../../shared/Config/Units"))
local Common = require("./Common")

export type RouteLike = {
	id: number,
	kind: string,
	length: number,
	points: { { number } },
	links: { { s: number, to: number, toS: number } },
}

export type Params = {
	routes: {
		routes: { RouteLike },
		byId: (id: number) -> RouteLike?,
		index: any?, -- (Shared/Routes/SpatialIndex over the routes: reseat's nearest-first search)
		enclosed: ((id: number) -> boolean)?, -- (an enclosed run: reseat never puts the body in one)
	},
	startRoute: number?,
	rng: () -> number,
	-- the server's own rays: nothing (no wall, no floor, roof or ceiling) between two places (reseat; nil: not asked)
	reach: ((x0: number, y0: number, z0: number, x1: number, y1: number, z1: number) -> boolean)?,
}

type Brain = Common.Brain & {
	actor: Common.Actor,
	params: Params,
	route: RouteLike,
	idleUntil: number,
	runUntil: number,
	sprint: boolean,
	lastLinkS: number,
	bait: { s: number, untilTime: number }?, -- a pile of peanuts near the route: go to its nearest point and stay
	startled: boolean, -- a startle not yet timed (onEvent has no clock: the next think gives the flee its end)
}

local Squirrel = {}

local RAIL_WALK = Units.st(7.2)
local RAIL_SPRINT = Units.st(12.2)
local WOOD = { trunk = true, branch = true, bridge = true, lookout = true }
local WOOD_MULT = 0.6
local LINK_REACH = Units.st(1.0)
local TRANSFER_CHANCE = 0.35

local BAIT_REACH = 16 -- studs: a pile further than this from the route is not worth leaving it for
local BAIT_AT = 1.0 -- studs: close enough to nibble
local FLEE_SECS = { 3, 6 } -- a startle's sprint, then the usual pause and an ordinary run

-- The distance along a route of its point nearest to (x, z), and how far that point is.
local function nearestS(route: RouteLike, x: number, z: number): (number, number)
	local bestS, bestD = 0, math.huge
	local s = 0
	local pts = route.points
	for i = 1, #pts - 1 do
		local a, b = pts[i], pts[i + 1]
		local ex, ez = b[1] - a[1], b[3] - a[3]
		local len = math.sqrt(ex * ex + ez * ez + (b[2] - a[2]) ^ 2)
		local l2 = ex * ex + ez * ez
		local u = if l2 > 1e-9 then math.clamp(((x - a[1]) * ex + (z - a[3]) * ez) / l2, 0, 1) else 0
		local px, pz = a[1] + ex * u, a[3] + ez * u
		local d = math.sqrt((x - px) ^ 2 + (z - pz) ^ 2)
		if d < bestD then
			bestD, bestS = d, s + len * u
		end
		s += len
	end
	-- (the polyline's length can differ a little from the route's own: scale onto it)
	if s > 0 then
		bestS = bestS * route.length / s
	end
	return bestS, bestD
end

-- nearest3(route, x, y, z) -> (s, d): the distance along a route of its point nearest to (x, y, z) in space, and how far
local function nearest3(route: RouteLike, x: number, y: number, z: number): (number, number)
	local bestS, bestD = 0, math.huge
	local s = 0
	local pts = route.points
	for i = 1, #pts - 1 do
		local a, b = pts[i], pts[i + 1]
		local ex, ey, ez = b[1] - a[1], b[2] - a[2], b[3] - a[3]
		local l2 = ex * ex + ey * ey + ez * ez
		local len = math.sqrt(l2)
		local u = if l2 > 1e-9 then math.clamp(((x - a[1]) * ex + (y - a[2]) * ey + (z - a[3]) * ez) / l2, 0, 1) else 0
		local d = math.sqrt((x - a[1] - ex * u) ^ 2 + (y - a[2] - ey * u) ^ 2 + (z - a[3] - ez * u) ^ 2)
		if d < bestD then
			bestD, bestS = d, s + len * u
		end
		s += len
	end
	if s > 0 then
		bestS = bestS * route.length / s
	end
	return bestS, bestD
end

-- Squirrel.reseat(routes, x, y, z, reach?) -> (route, s)?: the rail a player let the body go nearest (validator round 8:
-- a release puts a plain squirrel back where the server held it, not on the route point it was taken from). Round 9 (the
-- round-8 review's LOW): only a rail the body could have gone to from there: never an enclosed run (a storm drain under
-- the street, a hollow: entered only at a mouth), and with `reach` (the server's rays) nothing between, nearest first;
-- by the routes' spatial index (routes.index) within RESEAT_RADII, widened only when nothing is found; a scan of
-- every route only with no index. With nothing reachable near, the nearest open rail found (no recall to where the
-- body was taken)
local RESEAT_RADII = { 8, 24, 64 } -- studs
local RESEAT_TRIED = 4 -- candidates asked of `reach` in all (one route each, nearest first: its cost bounded)
function Squirrel.reseat(
	routes: {
		routes: { RouteLike },
		index: any?,
		enclosed: ((id: number) -> boolean)?,
		byId: (id: number) -> RouteLike?,
	},
	x: number,
	y: number,
	z: number,
	reach: ((x0: number, y0: number, z0: number, x1: number, y1: number, z1: number) -> boolean)?
): (RouteLike?, number)
	local enclosed = routes.enclosed
	local index = routes.index
	if index == nil then
		local best, bestS, bestD = nil, 0, math.huge
		for _, r in routes.routes do
			if enclosed and enclosed(r.id) then
				continue
			end
			local s, d = nearest3(r, x, y, z)
			if d < bestD then
				best, bestS, bestD = r, s, d
			end
		end
		return best, bestS
	end
	local fallback: RouteLike?, fallbackS = nil, 0
	local asked: { [number]: boolean } = {}
	local function accept(id: number, _t: number): boolean
		return not asked[id] and not (enclosed and enclosed(id))
	end
	local tries = 0
	for _, radius in RESEAT_RADII do
		-- (the nearest sample of a route not asked yet within the radius: the index's own nearest, nearest first)
		while true do
			local hit = index:nearest(x, y, z, radius, nil, accept)
			if hit == nil then
				break
			end
			local route = routes.byId(hit.routeId)
			asked[hit.routeId] = true
			if route == nil then
				continue
			end
			local s = hit.t * route.length
			if fallback == nil then
				fallback, fallbackS = route, s
			end
			if reach == nil or reach(x, y, z, hit.x, hit.y, hit.z) then
				return route, s
			end
			tries += 1
			if tries >= RESEAT_TRIED then
				return fallback, fallbackS
			end
		end
	end
	return fallback, fallbackS
end

local function railSpeed(route: RouteLike, sprint: boolean): number
	local base = if sprint then RAIL_SPRINT else RAIL_WALK
	return if WOOD[route.kind] then base * WOOD_MULT else base
end

local Methods = {}
Methods.__index = Methods

local function startRun(self: Brain, ctx: Common.Ctx)
	local rng = self.params.rng
	self.sprint = rng() < 0.3
	self.runUntil = ctx.now + Common.range(rng, 3, 9)
	local intent = self.actor.intent
	intent.mode = "rail"
	intent.speed = railSpeed(self.route, self.sprint)
end

function Methods.think(self: Brain, _dt: number, ctx: Common.Ctx)
	local intent = self.actor.intent
	local rng = self.params.rng
	if self.startled then
		self.startled = false
		self.runUntil = ctx.now + Common.range(rng, FLEE_SECS[1], FLEE_SECS[2])
	end
	-- bait: along the route to the point nearest the pile, then nibbling there until it is gone
	local bait = self.bait
	if bait then
		if ctx.now >= bait.untilTime then
			self.bait = nil
		else
			intent.mode = "rail"
			local gap = bait.s - intent.s
			if math.abs(gap) <= BAIT_AT then
				intent.speed = 0
			else
				intent.dir = if gap > 0 then 1 else -1
				intent.speed = railSpeed(self.route, false)
			end
			return
		end
	end
	if ctx.now < self.idleUntil then
		intent.mode = "rail"
		intent.speed = 0
		return
	end
	if intent.railEnd then
		-- end of the route: take a link at this end if there is one (the v5.4 auto-switch,
		-- routes_movement §11.1), else reverse
		intent.railEnd = false
		local atEnd = intent.s
		local taken = false
		for _, link in self.route.links do
			if math.abs(link.s - atEnd) < LINK_REACH then
				local to = self.params.routes.byId(link.to)
				if to then
					self.route = to
					intent.routeId = to.id
					intent.s = math.clamp(link.toS, 0, to.length)
					intent.dir = if link.toS < to.length / 2 then 1 else -1
					intent.speed = railSpeed(to, self.sprint)
					self.lastLinkS = intent.s
					taken = true
					break
				end
			end
		end
		if not taken then
			intent.dir = -intent.dir
			intent.s = math.clamp(intent.s, 0, self.route.length)
		end
	end
	-- a link we already rolled becomes eligible again once we have moved away from it
	if self.lastLinkS ~= -math.huge and math.abs(intent.s - self.lastLinkS) > LINK_REACH * 2 then
		self.lastLinkS = -math.huge
	end
	if ctx.now >= self.runUntil then
		if intent.speed > 0 then
			-- pause 1-3 s, then run again
			self.idleUntil = ctx.now + Common.range(rng, 1, 3)
			intent.speed = 0
			return
		end
		startRun(self, ctx)
	end
	-- transfer at a link we are passing
	for _, link in self.route.links do
		if math.abs(link.s - intent.s) < LINK_REACH and self.lastLinkS == -math.huge then
			if rng() < TRANSFER_CHANCE then
				local to = self.params.routes.byId(link.to)
				if to then
					self.route = to
					intent.routeId = to.id
					intent.s = math.clamp(link.toS, 0, to.length)
					intent.dir = if rng() < 0.5 then 1 else -1
					intent.speed = railSpeed(to, self.sprint)
					self.lastLinkS = intent.s
					return
				end
			end
			self.lastLinkS = link.s
			break
		end
	end
end

function Methods.suspend(self: Brain): Common.Snapshot
	local intent = self.actor.intent
	return { routeId = self.route.id, s = intent.s, dir = intent.dir, sprint = self.sprint, idleUntil = self.idleUntil }
end

function Methods.resume(self: Brain, snapshot: Common.Snapshot)
	local route = self.params.routes.byId(snapshot.routeId)
	local s = snapshot.s
	-- (let go by a player: on the rail nearest where the server held the body, never the old route point)
	local x, y, z = snapshot.x, snapshot.y, snapshot.z
	if type(x) == "number" and type(y) == "number" and type(z) == "number" then
		local near, ns = Squirrel.reseat(self.params.routes, x, y, z, self.params.reach)
		if near then
			route, s = near, ns
		end
	end
	if route then
		self.route = route
		local intent = self.actor.intent
		intent.mode = "rail"
		intent.routeId = route.id
		intent.s = s
		intent.dir = snapshot.dir
		self.sprint = snapshot.sprint == true
		intent.speed = railSpeed(route, self.sprint)
	end
	self.idleUntil = snapshot.idleUntil or 0
end

function Methods.onEvent(self: Brain, evt: { [string]: any })
	if evt.type == "bait" and type(evt.x) == "number" and type(evt.z) == "number" then
		local s, d = nearestS(self.route, evt.x, evt.z)
		if d <= BAIT_REACH then
			self.bait = { s = s, untilTime = evt.untilTime or 0 }
		end
	elseif evt.type == "startle" then
		self.bait = nil
		-- full-sprint flee on rails when chased (BUILD_PLAN §1.4 Squirrel brain), for FLEE_SECS (timed by the next
		-- think); then it pauses and its next run rolls its pace afresh (startRun)
		self.sprint = true
		self.idleUntil = 0
		self.startled = true
		local intent = self.actor.intent
		intent.speed = railSpeed(self.route, true)
		if type(evt.x) == "number" and type(evt.z) == "number" then
			local s = nearestS(self.route, evt.x, evt.z)
			if s ~= intent.s then
				intent.dir = if intent.s > s then 1 else -1
			end
		end
	end
end

function Squirrel.new(actor: Common.Actor, params: Params): Common.Brain
	local routes = params.routes.routes
	local route = (if params.startRoute then params.routes.byId(params.startRoute) else nil)
		or routes[math.floor(params.rng() * #routes) + 1]
	local self = setmetatable({
		kind = "Squirrel",
		actor = actor,
		params = params,
		route = route,
		idleUntil = 0,
		runUntil = 0,
		sprint = false,
		lastLinkS = -math.huge,
		startled = false,
	}, Methods)
	local intent = actor.intent
	intent.mode = "rail"
	intent.routeId = route.id
	intent.s = params.rng() * route.length
	intent.dir = if params.rng() < 0.5 then 1 else -1
	intent.speed = railSpeed(route, false)
	intent.railEnd = false
	local p = route.points[1]
	actor.x, actor.y, actor.z = p[1], p[2], p[3]
	return (self :: any) :: Common.Brain
end

return Squirrel
