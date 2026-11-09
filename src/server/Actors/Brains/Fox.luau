--!strict
-- ServerScriptService.Server.Actors.Brains.Fox
-- Fox brain, minimal W0 version (spike S5), from wildlife_foraging §11.9 (v4.1 restore): ROAM with
-- an absolute heading oscillation sin(phase 0.58) 0.85, turn rate 1.5 rad/s, speed 2.0 u/s, leash
-- 115 u from the origin; HUNT when a squirrel-species target is valid (height above ground < 2.5 u)
-- within 24 u: heading at the target, turn 7, speed 8.8 u/s. Warning, lunge and stun are W1.
-- Interface: new(actor, params), think, suspend, resume, onEvent. Pure; studs via Config/Units.

local Import = require("../../Import")
local Units = Import.shared("Config/Units") :: typeof(require("../../../shared/Config/Units"))
local Common = require("./Common")

export type Params = { originX: number, originZ: number }

type Brain = Common.Brain & {
	actor: Common.Actor,
	params: Params,
	phase: number,
	stun: number,
}

local Fox = {}

local ROAM_SPEED = Units.st(2.0)
local HUNT_SPEED = Units.st(8.8)
local HUNT_RANGE = Units.st(24)
local TARGET_MAX_HEIGHT = Units.st(2.5)
local LEASH = Units.st(115)

local Methods = {}
Methods.__index = Methods

function Methods.think(self: Brain, dt: number, ctx: Common.Ctx)
	local actor = self.actor
	local intent = actor.intent
	self.phase += dt
	self.stun = math.max(0, self.stun - dt)
	intent.mode = "heading"
	intent.laneAxis = nil

	-- HUNT: nearest valid squirrel-species target within 24 u
	local target: Common.Actor? = nil
	if self.stun <= 0 then
		local n = ctx.threats:query(actor.x, actor.z, HUNT_RANGE, ctx.queryBuffer)
		local bestD = math.huge
		for i = 1, n do
			local t = ctx.actorsById[ctx.queryBuffer[i]]
			if t and (t.y - ctx.groundAt(t.x, t.z)) < TARGET_MAX_HEIGHT then
				local d = Common.dist2d(actor.x, actor.z, t.x, t.z)
				if d < bestD then
					bestD, target = d, t
				end
			end
		end
	end
	if target then
		intent.heading = Common.yawOf(target.x - actor.x, target.z - actor.z)
		intent.turnRate = 7
		intent.speed = HUNT_SPEED
		intent.damp = 6
	else
		intent.heading = math.sin(self.phase * 0.58) * 0.85
		intent.turnRate = 1.5
		intent.speed = ROAM_SPEED
		intent.damp = 3
	end
	-- leash: beyond 115 u the fox stays put (v4.1 rejects the step; here it turns home)
	local dx, dz = actor.x - self.params.originX, actor.z - self.params.originZ
	if dx * dx + dz * dz > LEASH * LEASH then
		intent.heading = Common.yawOf(-dx, -dz)
		intent.turnRate = 7
	end
end

function Methods.suspend(self: Brain): Common.Snapshot
	return { phase = self.phase, stun = self.stun }
end

function Methods.resume(self: Brain, snapshot: Common.Snapshot)
	self.phase = snapshot.phase or 0
	self.stun = snapshot.stun or 0
end

function Methods.onEvent(self: Brain, evt: { [string]: any })
	if evt.type == "surprised" then
		self.stun = 9
	end
end

function Fox.new(actor: Common.Actor, params: Params): Common.Brain
	local self = setmetatable({
		kind = "Fox",
		actor = actor,
		params = params,
		phase = 0,
		stun = 0,
	}, Methods)
	actor.x, actor.z = params.originX, params.originZ
	return (self :: any) :: Common.Brain
end

return Fox
