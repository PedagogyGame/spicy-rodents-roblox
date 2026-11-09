--!strict
-- ServerScriptService.Server.Actors.Brains.Rodent
-- Rodent brain, minimal W0 version (spike S5): the AI spicy rodent wanders around a hide the way
-- v5.4's normal AI squirrels do (wildlife_foraging §2.2): target = hide + (sin(phase 0.83 + i) W,
-- cos(phase 0.63 + 1.3 i) W), W = 8 u, root lerps toward it with min(1, 2 dt), yaw faces the
-- target; phase runs x1.3 when infected. Stalk/pounce/bite are W1 (CombatRules).
-- Interface: new(actor, params), think, suspend, resume, onEvent. Pure; studs via Config/Units.

local Import = require("../../Import")
local Units = Import.shared("Config/Units") :: typeof(require("../../../shared/Config/Units"))
local Common = require("./Common")

export type Params = {
	hideX: number, -- studs
	hideZ: number,
	index: number,
	infected: boolean?,
}

type Brain = Common.Brain & {
	actor: Common.Actor,
	params: Params,
	phase: number,
}

local Rodent = {}

local W = Units.st(8)
local W_INFECTED = Units.st(6)
local LERP_RATE = 2 -- min(1, dt * 2) toward the target

local Methods = {}
Methods.__index = Methods

function Methods.think(self: Brain, dt: number, _ctx: Common.Ctx)
	local actor = self.actor
	local p = self.params
	self.phase += dt * (if p.infected then 1.3 else 1.0)
	local w = if p.infected then W_INFECTED else W
	local i = p.index
	local tx = p.hideX + math.sin(self.phase * 0.83 + i) * w
	local tz = p.hideZ + math.cos(self.phase * 0.63 + i * 1.3) * w
	local intent = actor.intent
	intent.mode = "walk"
	intent.tx, intent.tz = tx, tz
	intent.laneAxis = nil
	-- the lerp min(1, 2 dt) is a speed proportional to distance, capped at the ground walk speed
	local d = Common.dist2d(actor.x, actor.z, tx, tz)
	intent.speed = math.min(Units.st(8.0), d * LERP_RATE)
	intent.turnRate = 12
	intent.damp = 12
end

function Methods.suspend(self: Brain): Common.Snapshot
	return { phase = self.phase }
end

function Methods.resume(self: Brain, snapshot: Common.Snapshot)
	self.phase = snapshot.phase or 0
end

function Methods.onEvent(self: Brain, evt: { [string]: any })
	if evt.type == "infected" then
		self.params.infected = true
		self.phase += 3
	end
end

function Rodent.new(actor: Common.Actor, params: Params): Common.Brain
	local self = setmetatable({
		kind = "Rodent",
		actor = actor,
		params = params,
		phase = params.index * 1.7,
	}, Methods)
	actor.x, actor.z = params.hideX, params.hideZ
	return (self :: any) :: Common.Brain
end

return Rodent
