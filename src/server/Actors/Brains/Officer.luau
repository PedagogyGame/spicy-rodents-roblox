--!strict
-- ServerScriptService.Server.Actors.Brains.Officer
-- Officer patrol brain, minimal W0 version (spike S5): a foot beat around the station (a rectangle
-- of waypoints walked in a loop, short pause at corners), and a "respond" event that sends the
-- officer to a spot (fender bender, A2). Speeds from hospital_police_infection §8.4 incident
-- officers (2.3 u/s walk, 5.5 u/s chase); the patrol car itself is a device, not this brain.
-- A Directive (Brains/Directive; the bite-to-hospital sequence) overrides the beat while it is set:
-- onEvent({ type = "medical", mode = ... }) sets or clears it.
-- Interface: new(actor, params), think, suspend, resume, onEvent. Pure; studs via Config/Units.

local Import = require("../../Import")
local Units = Import.shared("Config/Units") :: typeof(require("../../../shared/Config/Units"))
local Common = require("./Common")
local Directive = require("./Directive")

export type Params = {
	stationX: number,
	stationZ: number,
	index: number,
	beatHalfX: number?, -- studs; default 30 u
	beatHalfZ: number?,
}

type Brain = Common.Brain & {
	actor: Common.Actor,
	params: Params,
	points: { { number } },
	target: number,
	pause: number,
	respondX: number,
	respondZ: number,
	respondUntil: number,
	directive: Directive.State,
}

local Officer = {}

local WALK = Units.st(2.3)
local CHASE = Units.st(5.5)
local REACH = Units.st(1.2)
local CORNER_PAUSE = 1.0

local Methods = {}
Methods.__index = Methods

function Methods.think(self: Brain, dt: number, ctx: Common.Ctx)
	local actor = self.actor
	local intent = actor.intent
	if Directive.think(self.directive, actor, dt, ctx) then
		return
	end
	if ctx.now < self.respondUntil then
		local d = Common.dist2d(actor.x, actor.z, self.respondX, self.respondZ)
		if d < Units.st(2.5) then
			intent.mode = "stand"
			intent.heading = Common.yawOf(self.respondX - actor.x, self.respondZ - actor.z)
		else
			intent.mode = "walk"
			intent.tx, intent.tz = self.respondX, self.respondZ
			intent.laneAxis = nil
			intent.speed = CHASE
			intent.turnRate = 6
			intent.damp = 8
		end
		return
	end
	if self.pause > 0 then
		self.pause = math.max(0, self.pause - dt)
		intent.mode = "stand"
		return
	end
	local p = self.points[self.target]
	if Common.dist2d(actor.x, actor.z, p[1], p[2]) < REACH then
		self.target = self.target % #self.points + 1
		self.pause = CORNER_PAUSE
		intent.mode = "stand"
		return
	end
	intent.mode = "walk"
	intent.tx, intent.tz = p[1], p[2]
	intent.laneAxis = nil
	intent.speed = WALK
	intent.turnRate = 4
	intent.damp = 6.8
end

function Methods.suspend(self: Brain): Common.Snapshot
	return {
		target = self.target,
		pause = self.pause,
		respondUntil = self.respondUntil,
		respondX = self.respondX,
		respondZ = self.respondZ,
		directive = Directive.snapshot(self.directive),
	}
end

function Methods.resume(self: Brain, snapshot: Common.Snapshot)
	self.target = snapshot.target or 1
	self.pause = snapshot.pause or 0
	self.respondUntil = snapshot.respondUntil or 0
	self.respondX = snapshot.respondX or 0
	self.respondZ = snapshot.respondZ or 0
	Directive.restore(self.directive, snapshot.directive)
end

function Methods.onEvent(self: Brain, evt: { [string]: any })
	if evt.type == "respond" or evt.type == "gather" then
		self.respondX, self.respondZ = evt.x, evt.z
		self.respondUntil = evt.untilTime
	elseif evt.type == "medical" then
		Directive.set(self.directive, evt)
	end
end

function Officer.new(actor: Common.Actor, params: Params): Common.Brain
	local hx = params.beatHalfX or Units.st(30)
	local hz = params.beatHalfZ or Units.st(30)
	-- staggered rectangles so 6 officers do not walk in a conga line
	local k = 1 + (params.index % 3) * 0.5
	local sx, sz = params.stationX, params.stationZ
	local points = {
		{ sx - hx * k, sz - hz * k },
		{ sx + hx * k, sz - hz * k },
		{ sx + hx * k, sz + hz * k },
		{ sx - hx * k, sz + hz * k },
	}
	local start = (params.index % 4) + 1
	local self = setmetatable({
		kind = "Officer",
		actor = actor,
		params = params,
		points = points,
		target = start,
		pause = 0,
		respondX = 0,
		respondZ = 0,
		respondUntil = 0,
		directive = Directive.new(),
	}, Methods)
	local prev = points[(start - 2) % 4 + 1]
	actor.x, actor.z = prev[1], prev[2]
	return (self :: any) :: Common.Brain
end

return Officer
