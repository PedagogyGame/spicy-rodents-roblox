--!strict
-- ReplicatedStorage.Shared.Combat.CombatRules
-- The numbers and the sums of the duel between the Spicy Rodent and a person (brief v2 §8 "Combat dynamics",
-- "Vigilantes", "Bite aftermath"; owner playtest 2026-11-18: tough people "extra aggressive and extra successful in
-- landing blows against you, and extra resistant of being bitten. Still possible, but harder"). Combat/Duel runs one
-- person's side of a duel on these; Server/Combat/CombatService applies it to the town.
-- Temperaments: every person is calm, wary or tough, fixed by their id (a hash: the same person is the same every
-- server); the tough ones are the vigilantes (Combat/VigilanteRules keeps them at human.vigilanteShare of the town).
-- A tough person notices sooner, strikes more often and more surely, winds up quicker, recovers quicker, has a
-- narrower reaction window and a smaller chance to be bitten in it, reads more feints, and never flees.
-- The bite: a pounce lands or not by the person's phase at the moment of contact:
--   unaware                        pounce.chanceUnaware x biteUnaware
--   open (the reaction window, a flinch, a recovery)                  biteOpen
--   runner (running away: at the heels)                                biteRunner
--   guard (a raised arm: backing away, squared up)                    biteGuard (brief: it does not land)
--   windup or strike (a raised leg or arm, a kick)                    0
-- and near a fresh bite every chance is multiplied by alert.bitePenalty (close to impossible).
-- A strike lands on a rodent in reach with strikeHit, plus recoveryHit on a rodent recovering from a pounce, counterHit
-- on the counter to a read feint, boostHit near a fresh bite, less zigzagMiss x the rodent's zig-zag (none while the
-- rodent is committed to a pounce: a lunge that meets a kick is hit, D-28).
-- Damage: a kick rodent.kick (55), a swing duel.swingDamage, a baton duel.batonDamage; x alert.kickMult near a fresh
-- bite (the hidden strength boost, below the one-kick line), x rodent.defenderMult for a house defender.
-- Interface: params() -> Params (Tunables now; a copy the duel simulation may change); hash(id) -> [0, 1);
--   temperament(id, vigilante) -> Temper; nerve(params, id, temper) -> number; weights(params, temper, nerve,
--   boosted, startled) -> { [Response]: number }; pick(weights, r) -> Response; biteChance(params, temper, phase,
--   inZone) -> number; strikeChance(params, temper, ctx) -> number; damage(params, kind, boosted, defender?) -> number;
--   applyDamage(health, amount) -> (health, dead); zigzag(params, history, dirX, dirZ, now) -> number in [0, 1];
--   RESPONSES, PHASES
-- Pure; studs and seconds. No side effects on require.

local Tunables = require("../Config/Tunables")

export type Temper = "calm" | "wary" | "tough"
export type Response = "flee" | "back" | "flinch" | "swing" | "kick"
-- what the person is doing, for a bite at that moment
export type BitePhase = "unaware" | "open" | "runner" | "guard" | "windup"
export type Sample = { t: number, x: number, z: number }

export type Params = {
	waryShare: number,
	notice: { [string]: number },
	react: { [string]: number },
	windup: { [string]: number },
	recover: { [string]: number },
	flinchSecs: number,
	backSecs: number,
	stepIn: { [string]: number },
	strikeHit: { [string]: number },
	biteUnaware: { [string]: number },
	biteOpen: { [string]: number },
	biteGuard: { [string]: number },
	biteRunner: { [string]: number },
	readFeint: { [string]: number },
	strikeRate: { [string]: number },
	entryStrike: { [string]: number },
	guardUp: { [string]: number },
	respond: { [string]: { [string]: number } },
	nerveJitter: number,
	engage: number,
	threat: number,
	kickReach: number,
	swingReach: number,
	swingDamage: number,
	swingWindupMult: number,
	batonDamage: number,
	recoveryHit: number,
	counterHit: number,
	counterWindupMult: number,
	counterLunge: number,
	boostHit: number,
	zigzagMiss: number,
	zigzagSecs: number,
	zigzagRate: number,
	zigzagLateral: number,
	feintCost: number,
	feintRefill: number,
	feintRecover: number,
	approach: number,
	backSpeed: number,
	contact: number,
	contactHeight: number,
	rewind: number,
	-- from the other branches
	chanceUnaware: number,
	pounceWindup: number,
	pounceWindow: number,
	pounceRecovery: number,
	pounceCooldown: number,
	kick: number,
	defenderMult: number,
	iFrames: number,
	maxHealth: number,
	kickMult: number,
	swingBias: number,
	bitePenalty: number,
	alertRadius: number,
	alertTtl: number,
	blockLen: number,
	chaseBlocks: number,
	leashBlocks: number,
	spotRange: number,
	vigilanteShare: number,
}

local CombatRules = {}

local RESPONSES: { Response } = { "flee", "back", "flinch", "swing", "kick" }
local TEMPERS: { Temper } = { "calm", "wary", "tough" }
CombatRules.RESPONSES = table.freeze(RESPONSES)
CombatRules.TEMPERS = table.freeze(TEMPERS)

function CombatRules.params(): Params
	local g = Tunables.get
	local p: { [string]: any } = {}
	for _, k in
		{
			"waryShare",
			"notice",
			"react",
			"windup",
			"recover",
			"flinchSecs",
			"backSecs",
			"stepIn",
			"strikeHit",
			"biteUnaware",
			"biteOpen",
			"biteGuard",
			"biteRunner",
			"readFeint",
			"strikeRate",
			"entryStrike",
			"guardUp",
			"respond",
			"nerveJitter",
			"engage",
			"threat",
			"kickReach",
			"swingReach",
			"swingDamage",
			"swingWindupMult",
			"batonDamage",
			"recoveryHit",
			"counterHit",
			"counterWindupMult",
			"counterLunge",
			"boostHit",
			"zigzagMiss",
			"zigzagSecs",
			"zigzagRate",
			"zigzagLateral",
			"feintCost",
			"feintRefill",
			"feintRecover",
			"approach",
			"backSpeed",
			"contact",
			"contactHeight",
			"rewind",
		}
	do
		p[k] = g("duel." .. k)
	end
	p.chanceUnaware = g("pounce.chanceUnaware")
	p.pounceWindup = g("pounce.windup")
	p.pounceWindow = g("pounce.window")
	p.pounceRecovery = g("pounce.recovery")
	p.pounceCooldown = g("pounce.cooldown")
	p.kick = g("rodent.kick")
	p.defenderMult = g("rodent.defenderMult")
	p.iFrames = g("rodent.iFrames")
	p.maxHealth = g("rodent.maxHealth")
	p.kickMult = g("alert.kickMult")
	p.swingBias = g("alert.swingBias")
	p.bitePenalty = g("alert.bitePenalty")
	p.alertRadius = g("alert.radiusU")
	p.alertTtl = g("alert.ttl")
	p.blockLen = g("alert.blockLenU")
	p.chaseBlocks = g("alert.policeChaseBlocks")
	p.leashBlocks = g("alert.policeLeashBlocks")
	p.spotRange = g("human.spotRange")
	p.vigilanteShare = g("human.vigilanteShare")
	return (p :: any) :: Params
end

-- A stable number in [0, 1) for an id (a number or a string): the same person draws the same every server.
function CombatRules.hash(id: any): number
	local s = tostring(id)
	local h = 2166136261
	for i = 1, #s do
		h = bit32.bxor(h, string.byte(s, i))
		h = (h * 16777619) % 4294967296
	end
	-- one more mix so neighbouring ids spread
	h = bit32.bxor(h, bit32.rshift(h, 13))
	h = (h * 1274126177) % 4294967296
	h = bit32.bxor(h, bit32.rshift(h, 16))
	return h / 4294967296
end

-- calm or wary by the id; tough when the person carries a vigilante flag
function CombatRules.temperament(id: any, vigilante: boolean, waryShare: number?): Temper
	if vigilante then
		return "tough"
	end
	local share = waryShare or Tunables.get("duel.waryShare")
	return if CombatRules.hash(`temper:{tostring(id)}`) < share then "wary" else "calm"
end

local NERVE: { [string]: number } = { calm = 0.25, wary = 0.5, tough = 1 }

-- How much fight a person has, 0 to 1 (the temperament's, give or take nerveJitter by the id).
function CombatRules.nerve(params: Params, id: any, temper: Temper): number
	local j = (CombatRules.hash(`nerve:{tostring(id)}`) * 2 - 1) * params.nerveJitter
	return math.clamp(NERVE[temper] + j, 0, 1)
end

-- The response weights for a person who just saw a pounce coming (or the rodent close in): the temperament's, the
-- fight in them scaled by nerve, a startled person (just noticed) flinches more, and near a fresh bite everybody
-- swings and kicks swingBias times as readily (the hidden boost). Vigilantes never flee.
function CombatRules.weights(
	params: Params,
	temper: Temper,
	nerve: number,
	boosted: boolean,
	startled: boolean
): { [string]: number }
	local base = params.respond[temper]
	local fight = 0.5 + nerve
	local out: { [string]: number } = {}
	for _, r in CombatRules.RESPONSES do
		local w = base[r] or 0
		if r == "swing" or r == "kick" then
			w *= fight * (if boosted then params.swingBias else 1)
		elseif r == "flee" then
			w *= (1.5 - nerve)
		elseif r == "flinch" and startled then
			w *= 2
		end
		out[r] = if temper == "tough" and r == "flee" then 0 else w
	end
	return out
end

-- The response the weights give for a uniform draw r in [0, 1).
function CombatRules.pick(weights: { [string]: number }, r: number): Response
	local total = 0
	for _, k in RESPONSES do
		total += weights[k] or 0
	end
	if total <= 0 then
		return "back"
	end
	local x = r * total
	for _, k in RESPONSES do
		x -= weights[k] or 0
		if x < 0 then
			return k :: Response
		end
	end
	return RESPONSES[#RESPONSES]
end

-- The chance a bite lands on a person in this phase (inZone: near a fresh bite).
function CombatRules.biteChance(params: Params, temper: Temper, phase: BitePhase, inZone: boolean): number
	local c
	if phase == "unaware" then
		c = params.chanceUnaware * params.biteUnaware[temper]
	elseif phase == "open" then
		c = params.biteOpen[temper]
	elseif phase == "runner" then
		c = params.biteRunner[temper]
	elseif phase == "guard" then
		c = params.biteGuard[temper]
	else
		c = 0
	end
	if inZone then
		c *= params.bitePenalty
	end
	return math.clamp(c, 0, 1)
end

export type StrikeCtx = {
	zigzag: number, -- the rodent's zig-zag, 0 to 1
	committed: boolean, -- the rodent is mid-pounce (no zig-zag counts)
	recovering: boolean, -- the rodent is recovering from a pounce
	counter: boolean, -- the counter to a read feint
	boosted: boolean, -- near a fresh bite
}

-- The chance a strike lands on a rodent in reach.
function CombatRules.strikeChance(params: Params, temper: Temper, ctx: StrikeCtx): number
	local c = params.strikeHit[temper]
	if ctx.recovering then
		c += params.recoveryHit
	end
	if ctx.counter then
		c += params.counterHit
	end
	if ctx.boosted then
		c += params.boostHit
	end
	if not ctx.committed then
		c -= params.zigzagMiss * math.clamp(ctx.zigzag, 0, 1)
	end
	return math.clamp(c, 0, 0.97)
end

-- The damage of a blow: "kick" | "swing" | "baton"; boosted near a fresh bite; a house defender hits harder.
function CombatRules.damage(params: Params, kind: string, boosted: boolean, defender: boolean?): number
	local d = if kind == "swing" then params.swingDamage elseif kind == "baton" then params.batonDamage else params.kick
	if boosted then
		d *= params.kickMult
	end
	if defender then
		d *= params.defenderMult
	end
	return d
end

-- New health after `amount` (never below 0) and whether it is a knock-out.
function CombatRules.applyDamage(health: number, amount: number): (number, boolean)
	local h = math.max(0, health - amount)
	return h, h <= 0
end

-- The rodent's zig-zag, 0 to 1: reversals of its sideways movement (across the line to the person, dirX/dirZ) faster
-- than zigzagLateral, over the last zigzagSecs, against zigzagRate a second. history: the rodent's positions, oldest
-- first. A straight run, a slow weave or a stand-still is 0.
function CombatRules.zigzag(params: Params, history: { Sample }, dirX: number, dirZ: number, now: number): number
	local dl = math.sqrt(dirX * dirX + dirZ * dirZ)
	if dl < 1e-6 or #history < 3 then
		return 0
	end
	local nx, nz = -dirZ / dl, dirX / dl -- sideways
	local from = now - params.zigzagSecs
	local lastSign = 0
	local reversals = 0
	for i = 2, #history do
		local a, b = history[i - 1], history[i]
		if b.t >= from and b.t > a.t then
			local lateral = ((b.x - a.x) * nx + (b.z - a.z) * nz) / (b.t - a.t)
			if math.abs(lateral) >= params.zigzagLateral then
				local sign = if lateral > 0 then 1 else -1
				if lastSign ~= 0 and sign ~= lastSign then
					reversals += 1
				end
				lastSign = sign
			end
		end
	end
	return math.clamp(reversals / (params.zigzagRate * params.zigzagSecs), 0, 1)
end

return CombatRules
