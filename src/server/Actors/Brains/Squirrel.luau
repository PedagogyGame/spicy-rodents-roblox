--!strict
-- ServerScriptService.Server.Actors.Brains.Squirrel
-- Squirrel brain, minimal W0 version (spike S5): route running on the rail network. Runs along a
-- route for a while, idles 1-3 s, transfers to a linked route when it passes a link (routes within
-- 1.7 u, routes_movement §3, §11), reverses at an end. Rail speeds walk 7.2 / sprint 12.2 u/s with
-- x0.6 on wood kinds (trunk, branch, bridge, lookout) [routes_movement §10]. The motor
-- (Server/AI/Kinematics) advances `s` every frame; the brain only sets routeId, dir, speed.
-- W1 replaces the polyline data with Shared/Routes (Curve, Registry, Graph, Motion).
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
	routes: { routes: { RouteLike }, byId: (id: number) -> RouteLike? },
	startRoute: number?,
	rng: () -> number,
}

type Brain = Common.Brain & {
	actor: Common.Actor,
	params: Params,
	route: RouteLike,
	idleUntil: number,
	runUntil: number,
	sprint: boolean,
	lastLinkS: number,
}

local Squirrel = {}

local RAIL_WALK = Units.st(7.2)
local RAIL_SPRINT = Units.st(12.2)
local WOOD = { trunk = true, branch = true, bridge = true, lookout = true }
local WOOD_MULT = 0.6
local LINK_REACH = Units.st(1.0)
local TRANSFER_CHANCE = 0.35

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
	if route then
		self.route = route
		local intent = self.actor.intent
		intent.mode = "rail"
		intent.routeId = route.id
		intent.s = snapshot.s
		intent.dir = snapshot.dir
		self.sprint = snapshot.sprint == true
		intent.speed = railSpeed(route, self.sprint)
	end
	self.idleUntil = snapshot.idleUntil or 0
end

function Methods.onEvent(self: Brain, evt: { [string]: any })
	if evt.type == "startle" then
		-- full-sprint flee on rails when chased (BUILD_PLAN §1.4 Squirrel brain)
		self.sprint = true
		self.idleUntil = 0
		self.runUntil = math.huge
		self.actor.intent.speed = railSpeed(self.route, true)
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
