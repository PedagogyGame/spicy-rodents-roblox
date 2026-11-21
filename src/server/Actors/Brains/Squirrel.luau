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
-- THE ROADS (owner D21, 2026-11-21; Shared/Wildlife/RoadCrossing has the rule and its numbers): with the town's roads
-- given (ctx.road: AI/TownAI.setRoad) a squirrel near a player (the scheduler's near tier: the looking needs its ten
-- thinks a second) on a tree with a crossing now and then comes down its trunk ("down"), runs to the kerb ("toKerb"),
-- stops and looks both ways ("look": waits for a gap in the cars; a fast car that keeps it waiting it may misjudge,
-- once a car, and race: go at the last moment; with no gap for C.patience it goes "back" up its tree), dashes kerb to kerb
-- ("dash": the actor's `crossing` is set, so Boot/Game puts it in the cars' fatal sweep: nothing brakes for it) and runs
-- on to the tree on the other side ("away"), whose trunk it climbs. At most C.atOnce squirrels are on their way at
-- once. Up its tree, a squirrel may also come down for a fast car it could just beat to the kerb, to race it (once a
-- car, C.race). Nothing else is heeded on the way (bait, a startle). Events: "runOver" (Server/Wildlife/RoadSquirrels: a car
-- got it: it lies where it fell, the actor `gone`, until) "comeBack" { routeId, s } (on that tree, as new).
-- Without ctx.road nothing here runs and no dice are thrown.
-- Interface: new(actor, params), think, suspend, resume, onEvent. Pure; studs via Config/Units.

local Import = require("../../Import")
local Units = Import.shared("Config/Units") :: typeof(require("../../../shared/Config/Units"))
local RoadCrossing = Import.shared("Wildlife/RoadCrossing") :: typeof(require("../../../shared/Wildlife/RoadCrossing"))
local Common = require("./Common")

export type RouteLike = {
	id: number,
	kind: string,
	length: number,
	points: { { number } },
	links: { { s: number, to: number, toS: number } },
}

export type Params = {
	-- (AI/RouteAdapter's also carries `index` and `enclosed`: reseat's nearest-first search, never an enclosed run)
	routes: { routes: { RouteLike }, byId: (id: number) -> RouteLike? },
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
	cross: Cross?, -- on its way across a road (THE ROADS)
	crossAt: number, -- its next thought of crossing (0: none yet)
	raceSeen: { [any]: number }, -- the cars it has made its mind up about from its tree, and until when
}

-- A crossing under way: the site (RoadCrossing.Site), the leg, when the leg (and the look) began, how long it looks
-- both ways, the fast cars it has made its mind up about at the kerb, the car it is racing (its id), and the town's
-- roads (its count of squirrels on their way)
type Cross = {
	site: any,
	phase: string, -- down | toKerb | look | dash | away | back
	since: number,
	lookFor: number,
	dare: { [any]: boolean },
	racing: any?,
	road: Common.Road,
	careless: boolean, -- it went on a misjudged car
	pace: number, -- studs/s kerb to kerb (a race is run a little slower: RoadCrossing C.racePace)
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

local CROSS = RoadCrossing.C
local FOOT_AT = 0.6 -- studs along the trunk from its foot that count as there
local SPOT_AT = 0.8 -- studs from a spot on the ground that count as there
local LEG_MAX = 30 -- seconds a leg of a crossing may take before it is given up (a body pushed off its way)
local NO_SITE = 6 -- seconds before a squirrel on a tree with no crossing thinks of one again

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

-- THE ROADS ----------------------------------------------------------------------------------------------------------

-- onto a tree at its foot, climbing
local function climb(self: Brain, routeId: number, s: number)
	local route = self.params.routes.byId(routeId)
	if route == nil then
		return
	end
	self.route = route
	local intent = self.actor.intent
	intent.mode = "rail"
	intent.routeId = route.id
	intent.s = math.clamp(s, 0, route.length)
	intent.dir = if s < route.length / 2 then 1 else -1
	intent.speed = railSpeed(route, false)
	intent.railEnd = false
	self.lastLinkS = intent.s
end

-- the crossing is over (done, given up, or the body taken): the town's count, and the next thought of one
local function endCross(self: Brain, nextAt: number)
	local cross = self.cross
	if cross then
		cross.road.crossing = math.max(0, cross.road.crossing - 1)
	end
	self.cross = nil
	self.actor.crossing = nil
	self.crossAt = nextAt
end

-- run over the ground to a spot; true once there
local function runTo(self: Brain, x: number, z: number, speed: number): boolean
	local actor = self.actor
	if Common.dist2d(actor.x, actor.z, x, z) <= SPOT_AT then
		return true
	end
	local intent = actor.intent
	intent.mode = "walk"
	intent.tx, intent.tz = x, z
	intent.laneAxis, intent.laneCoord = nil, nil
	intent.speed = speed
	intent.turnRate = 14
	intent.damp = 12
	return false
end

local function phase(cross: Cross, name: string, now: number)
	cross.phase = name
	cross.since = now
end

local function crossing(self: Brain, cross: Cross, ctx: Common.Ctx)
	local actor = self.actor
	local intent = actor.intent
	local site = cross.site
	local rng = self.params.rng
	local now = ctx.now
	local every = CROSS.every
	if cross.phase ~= "look" and now - cross.since > LEG_MAX then
		-- (never left standing in the open: back on its own tree)
		climb(self, site.route, site.s)
		endCross(self, now + Common.range(rng, every[1], every[2]))
		return
	end
	if cross.phase == "down" then
		intent.mode = "rail"
		local gap = site.s - intent.s
		if math.abs(gap) <= FOOT_AT then
			phase(cross, "toKerb", now)
		else
			intent.dir = if gap > 0 then 1 else -1
			intent.speed = railSpeed(self.route, false)
			intent.railEnd = false
		end
	elseif cross.phase == "toKerb" then
		if runTo(self, site.kx, site.kz, CROSS.approach) then
			phase(cross, "look", now)
			cross.lookFor = Common.range(rng, CROSS.lookSecs[1], CROSS.lookSecs[2])
		end
	elseif cross.phase == "look" then
		intent.mode = "stand"
		intent.heading = Common.yawOf(site.fx - site.kx, site.fz - site.kz)
		if actor.tier ~= "near" then
			phase(cross, "back", now) -- (nobody near to see it, and too few thinks to look by)
			return
		end
		local cars = cross.road.cars()
		if cross.racing ~= nil then
			-- racing a car it has misjudged: it goes at the last moment (RoadCrossing.dares)
			local t: number?, at: number? = nil, nil
			for _, c in cars do
				if c.id == cross.racing then
					t, at = RoadCrossing.arrival(c, site)
					break
				end
			end
			if t == nil or at == nil then
				cross.racing = nil -- (it has gone by, or turned off: an ordinary look from here)
			elseif RoadCrossing.dares(t, at) then
				cross.careless = true
				local share = CROSS.racePace
				cross.pace = CROSS.pace * (share[1] + (share[2] - share[1]) * rng())
				phase(cross, "dash", now)
			end
		else
			local clear, car, t = RoadCrossing.look(cars, site)
			if clear then
				if now - cross.since >= cross.lookFor then
					phase(cross, "dash", now)
				end
			elseif car and t and t > 0 and RoadCrossing.fast(car) and cross.dare[car.id] == nil then
				local dare = rng() < CROSS.misjudge
				cross.dare[car.id] = dare
				if dare then
					cross.racing = car.id
				end
			end
		end
		if cross.phase == "look" and now - cross.since > CROSS.patience then
			phase(cross, "back", now)
		end
	end
	-- (not an elseif: a look that says go is a dash from this very think, not the next)
	if cross.phase == "dash" then
		actor.crossing = true
		if runTo(self, site.fx, site.fz, cross.pace) then
			actor.crossing = nil
			phase(cross, "away", now)
		end
	elseif cross.phase == "away" then
		if runTo(self, site.bx, site.bz, CROSS.approach) then
			climb(self, site.to, site.toS)
			endCross(self, now + Common.range(rng, every[1], every[2]))
		end
	elseif cross.phase == "back" then
		if runTo(self, site.ax, site.az, CROSS.approach) then
			climb(self, site.route, site.s)
			endCross(self, now + Common.range(rng, every[1], every[2]) / 2)
		end
	end
end

local function setOut(self: Brain, road: Common.Road, site: any, now: number, racing: any?)
	road.crossing += 1
	self.cross = {
		site = site,
		phase = "down",
		since = now,
		lookFor = 0,
		dare = {},
		racing = racing,
		road = road,
		careless = false,
		pace = CROSS.pace,
	}
end

-- a fast car is coming past this tree's crossing, and the squirrel could just beat it to the kerb: now and then (once
-- a car, C.race) it comes down to race it. The car's id, or nil.
local function carToRace(self: Brain, road: Common.Road, site: any, now: number): any?
	local actor = self.actor
	local intent = actor.intent
	local toKerb = math.abs(site.s - intent.s) / railSpeed(self.route, false)
		+ Common.dist2d(site.ax, site.az, site.kx, site.kz) / CROSS.approach
	local seen = self.raceSeen
	for _, car in road.cars() do
		if RoadCrossing.fast(car) and (seen[car.id] or 0) <= now then
			local t = RoadCrossing.arrival(car, site)
			if t and RoadCrossing.races(t, toKerb) then
				seen[car.id] = now + CROSS.raceRest
				if self.params.rng() < CROSS.race then
					return car.id
				end
			end
		end
	end
	return nil
end

-- a thought of crossing: on a tree with a crossing, near a player, with room in the town's count: it sets out
local function thinkOfCrossing(self: Brain, road: Common.Road, ctx: Common.Ctx): boolean
	local rng = self.params.rng
	local now = ctx.now
	if self.crossAt == 0 then
		self.crossAt = now + Common.range(rng, 3, CROSS.every[2])
		return false
	end
	local site = road.sites[self.route.id]
	if site == nil or self.actor.tier ~= "near" or road.crossing >= CROSS.atOnce then
		if now >= self.crossAt then
			self.crossAt = now + NO_SITE
		end
		return false
	end
	if now >= self.crossAt then
		setOut(self, road, site, now, nil)
		return true
	end
	local car = carToRace(self, road, site, now)
	if car ~= nil then
		setOut(self, road, site, now, car)
		return true
	end
	return false
end

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
	if self.actor.gone then
		-- knocked flat on the road: it lies where it fell (Server/Wildlife/RoadSquirrels brings it back)
		intent.mode = "stand"
		intent.speed = 0
		intent.heading = 0
		return
	end
	local road = ctx.road
	if road then
		local cross = self.cross
		if cross == nil and self.bait == nil and thinkOfCrossing(self, road, ctx) then
			cross = self.cross
		end
		if cross then
			self.startled = false
			crossing(self, cross, ctx)
			return
		end
	end
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
	-- (a player took the body on its way across a road: the crossing is theirs to finish)
	endCross(self, 0)
	return { routeId = self.route.id, s = intent.s, dir = intent.dir, sprint = self.sprint, idleUntil = self.idleUntil }
end

function Methods.resume(self: Brain, snapshot: Common.Snapshot)
	local route = self.params.routes.byId(snapshot.routeId)
	local s = snapshot.s
	-- (let go by a player: on the rail nearest where the server held the body, never the old route point)
	local x, y, z = snapshot.x, snapshot.y, snapshot.z
	if type(x) == "number" and type(y) == "number" and type(z) == "number" then
		local near, ns = Squirrel.reseat(self.params.routes :: any, x, y, z, self.params.reach)
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
	if evt.type == "runOver" then
		-- a car got it (Server/Wildlife/RoadSquirrels marks the actor gone): it lies where it fell
		endCross(self, 0)
		self.bait = nil
		self.startled = false
		Common.halt(self.actor)
		return
	elseif evt.type == "comeBack" then
		-- back in town at a tree, as new (the service has put the body there)
		if type(evt.routeId) == "number" then
			climb(self, evt.routeId, if type(evt.s) == "number" then evt.s else 0)
		end
		self.idleUntil = 0
		self.runUntil = 0
		self.crossAt = 0
		return
	end
	if self.cross or self.actor.gone then
		return -- (on its way across a road, or flat on it: bait and frights wait)
	end
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
		cross = nil,
		crossAt = 0,
		raceSeen = {},
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
