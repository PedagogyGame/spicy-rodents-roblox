--!strict
-- ServerScriptService.Server.Actors.Brains.Officer
-- Officer patrol brain, minimal W0 version (spike S5): a foot beat around the station (a rectangle
-- of waypoints walked in a loop, short pause at corners), and a "respond" event that sends the
-- officer to a spot (fender bender, A2). Speeds from hospital_police_infection §8.4 incident
-- officers (2.3 u/s walk, 5.5 u/s chase); the patrol car itself is a device, not this brain.
-- A Directive (Brains/Directive; the bite-to-hospital sequence) overrides the beat while it is set:
-- onEvent({ type = "medical", mode = ... }) sets or clears it.
-- The stakeout (the storm drains, BRIEF_ADDENDUM D8; Server/World/SewerService): an officer who saw the rodent
-- go down a drain runs to the spot beside that grate (`x`, `z`), stands there facing it (`faceX`, `faceZ`)
-- for `secs` from arriving (Tunables sewer.stakeoutSecs), says so on arriving (ctx.emit("stakeout")), then
-- walks back to the beat. Officers never go to the other end. A walk that has not arrived after `giveUp`
-- seconds (default STAKEOUT_GIVE_UP) is dropped. onEvent({ type = "stakeout", ... }) sets it; one for the
-- grate already being watched does not start the watch again (a rodent diving in and out of one grate never
-- pins the officer there); onEvent({ type = "stakeoutEnd" }) ends it at once (the rodent came up in sight:
-- SewerService follows it with a "respond"). A medical directive still comes first.
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
	stakeout: Stakeout?,
}

-- the grate an officer is watching: where to stand and what to face; holdLeft counts down from arrival
type Stakeout = {
	x: number,
	z: number,
	faceX: number,
	faceZ: number,
	secs: number,
	holdLeft: number?, -- nil while walking there
	walkLeft: number, -- seconds left to get there
	mouth: string?,
}

local Officer = {}

local WALK = Units.st(2.3)
local CHASE = Units.st(5.5)
local REACH = Units.st(1.2)
local CORNER_PAUSE = 1.0
Officer.STAKEOUT_REACH = 0.8 -- studs: at the stand point
Officer.STAKEOUT_GIVE_UP = 60 -- s: a walk to the grate that has not arrived by then is dropped

-- the stakeout's step; true while it holds the officer
local function stakeout(self: Brain, dt: number, ctx: Common.Ctx): boolean
	local s = self.stakeout
	if s == nil then
		return false
	end
	local actor = self.actor
	local intent = actor.intent
	if s.holdLeft == nil then
		s.walkLeft -= dt
		local d = Common.dist2d(actor.x, actor.z, s.x, s.z)
		if d <= Officer.STAKEOUT_REACH then
			s.holdLeft = s.secs
			if ctx.emit then
				ctx.emit("stakeout", actor)
			end
		elseif s.walkLeft <= 0 then
			self.stakeout = nil
			return false
		else
			intent.mode = "walk"
			intent.tx, intent.tz = s.x, s.z
			intent.laneAxis = nil
			-- running, slowing over the last few studs so the officer stops on the spot
			intent.speed = math.clamp(d * 3, WALK, CHASE)
			intent.turnRate = 6
			intent.damp = 8
			return true
		end
	end
	local left = (s.holdLeft :: number) - dt
	if left <= 0 then
		self.stakeout = nil
		return false
	end
	s.holdLeft = left
	intent.mode = "stand"
	intent.heading = Common.yawOf(s.faceX - actor.x, s.faceZ - actor.z)
	return true
end

local Methods = {}
Methods.__index = Methods

function Methods.think(self: Brain, dt: number, ctx: Common.Ctx)
	local actor = self.actor
	local intent = actor.intent
	if Directive.think(self.directive, actor, dt, ctx) then
		return
	end
	if stakeout(self, dt, ctx) then
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
		stakeout = if self.stakeout then table.clone(self.stakeout) else nil,
	}
end

function Methods.resume(self: Brain, snapshot: Common.Snapshot)
	self.target = snapshot.target or 1
	self.pause = snapshot.pause or 0
	self.respondUntil = snapshot.respondUntil or 0
	self.respondX = snapshot.respondX or 0
	self.respondZ = snapshot.respondZ or 0
	Directive.restore(self.directive, snapshot.directive)
	self.stakeout = if snapshot.stakeout then table.clone(snapshot.stakeout) else nil
	Common.halt(self.actor) -- no walking on the old intent before the next think
end

function Methods.onEvent(self: Brain, evt: { [string]: any })
	if evt.type == "respond" or evt.type == "gather" then
		self.respondX, self.respondZ = evt.x, evt.z
		self.respondUntil = evt.untilTime
	elseif evt.type == "medical" then
		Directive.set(self.directive, evt)
	elseif evt.type == "stakeoutEnd" then
		self.stakeout = nil
	elseif evt.type == "stakeout" then
		local s = self.stakeout
		if s and evt.mouth ~= nil and s.mouth == evt.mouth then
			return -- already watching that grate: the watch runs its course, it is not renewed
		end
		self.stakeout = {
			x = evt.x,
			z = evt.z,
			faceX = evt.faceX,
			faceZ = evt.faceZ,
			secs = evt.secs,
			holdLeft = nil,
			walkLeft = evt.giveUp or Officer.STAKEOUT_GIVE_UP,
			mouth = evt.mouth,
		}
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
		stakeout = nil,
	}, Methods)
	local prev = points[(start - 2) % 4 + 1]
	actor.x, actor.z = prev[1], prev[2]
	return (self :: any) :: Common.Brain
end

return Officer
