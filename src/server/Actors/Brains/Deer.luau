--!strict
-- ServerScriptService.Server.Actors.Brains.Deer
-- Deer brain, minimal W0 version (spike S5), from wildlife_foraging §11.8 (v4.1 restore):
-- GRAZE/WANDER with the absolute heading sin(phase 0.37 + origin.x) 1.3 (origin.x in HTML units),
-- turn 1.2 rad/s, speed toward 1.25 u/s (lambda 1.3); THREAT when a squirrel-species actor is within
-- 21 u and less than 5 u above the deer's ground: scare 3.4 s, FLEE away at 11.8 u/s (fawn 9.0),
-- turn 5.6, lambda 6; steps are kept within 95 u of the origin (else heading += 0.67 pi, speed 0).
-- Interface: new(actor, params), think, suspend, resume, onEvent. Pure; studs via Config/Units.

local Import = require("../../AI/Import")
local Units = Import.shared("Config/Units") :: typeof(require("../../../shared/Config/Units"))
local Common = require("./Common")

export type Params = { originX: number, originZ: number, fawn: boolean?, phase: number? }

type Brain = Common.Brain & {
	actor: Common.Actor,
	params: Params,
	phase: number,
	scare: number,
	heading: number,
}

local Deer = {}

local GRAZE_SPEED = Units.st(1.25)
local FLEE_SPEED = Units.st(11.8)
local FLEE_FAWN = Units.st(9.0)
local THREAT_RANGE = Units.st(21)
local THREAT_MAX_HEIGHT = Units.st(5)
local LEASH = Units.st(95)

local Methods = {}
Methods.__index = Methods

function Methods.think(self: Brain, dt: number, ctx: Common.Ctx)
	local actor = self.actor
	local intent = actor.intent
	self.phase += dt
	self.scare = math.max(0, self.scare - dt)
	intent.mode = "heading"
	intent.laneAxis = nil

	local threat: Common.Actor? = nil
	local n = ctx.threats:query(actor.x, actor.z, THREAT_RANGE, ctx.queryBuffer)
	local ground = ctx.groundAt(actor.x, actor.z)
	local bestD = math.huge
	for i = 1, n do
		local t = ctx.actorsById[ctx.queryBuffer[i]]
		if t and (t.y - ground) < THREAT_MAX_HEIGHT then
			local d = Common.dist2d(actor.x, actor.z, t.x, t.z)
			if d < bestD then
				bestD, threat = d, t
			end
		end
	end
	if threat then
		self.scare = math.max(self.scare, 3.4)
		self.heading = Common.yawOf(actor.x - threat.x, actor.z - threat.z)
	end

	if self.scare > 0 then
		intent.heading = self.heading
		intent.turnRate = 5.6
		intent.speed = if self.params.fawn then FLEE_FAWN else FLEE_SPEED
		intent.damp = 6
	else
		intent.heading = math.sin(self.phase * 0.37 + Units.u(self.params.originX)) * 1.3
		intent.turnRate = 1.2
		intent.speed = GRAZE_SPEED
		intent.damp = 1.3
	end
	-- leash: beyond 95 u the step is rejected and the heading turns by 0.67 pi
	local dx, dz = actor.x - self.params.originX, actor.z - self.params.originZ
	if dx * dx + dz * dz > LEASH * LEASH then
		self.heading = actor.yaw + 0.67 * math.pi
		intent.heading = Common.yawOf(-dx, -dz)
		intent.turnRate = 5.6
		intent.speed = 0
	end
end

function Methods.suspend(self: Brain): Common.Snapshot
	return { phase = self.phase, scare = self.scare, heading = self.heading }
end

function Methods.resume(self: Brain, snapshot: Common.Snapshot)
	self.phase = snapshot.phase or 0
	self.scare = snapshot.scare or 0
	self.heading = snapshot.heading or 0
end

function Methods.onEvent(self: Brain, evt: { [string]: any })
	if evt.type == "bitten" then
		self.scare = 12
	elseif evt.type == "startle" then
		self.scare = math.max(self.scare, evt.seconds or 3.4)
	end
end

function Deer.new(actor: Common.Actor, params: Params): Common.Brain
	local self = setmetatable({
		kind = "Deer",
		actor = actor,
		params = params,
		phase = params.phase or 0,
		scare = 0,
		heading = 0,
	}, Methods)
	actor.x, actor.z = params.originX, params.originZ
	return (self :: any) :: Common.Brain
end

return Deer
