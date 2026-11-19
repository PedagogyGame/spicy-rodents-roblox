--!strict
-- ServerScriptService.Server.Combat.CombatService
-- The duel between a player's Spicy Rodent and the town (brief v2 §8 "Combat dynamics", "Vigilantes", "Bite aftermath";
-- owner playtest 2026-11-18), server-authoritative, on Shared/Combat/CombatRules and Combat/Duel. It replaces the first
-- build's bite on contact (Combat/PlayRules.biteVictims) behind Boot/Game's same bite path: a bite is now a bite at the
-- right moment.
-- THE POUNCE. The player's click is the pounce's tell (`rodentAct(id, "pounce")`, the PlayNet "Duel" remote): the
-- client holds the motor's pounce back for pounce.windup (the wind-up, which everyone sees: the body's PounceAt
-- attribute), then the motor launches it (the commit) and its window runs pounce.window, widened by duel.rewind for
-- the link (D20). A bite needs contact in that window (duel.contact studs, the person's root to the rodent's, not
-- through a Combat/Cover wall) AND, when `motorOf` is given, the rodent's own validated motor state showing the pounce
-- (attackWindow): a click with no real pounce bites nobody, and a pounce with no click bites nobody either. After the
-- window, with or without contact, the rodent recovers for pounce.recovery (blows land more surely). One bite a pounce,
-- the nearest person in contact. A feint (`rodentAct(id, "feint")`, F) is a tell with no pounce: it costs
-- duel.feintCost of a feint meter that refills at duel.feintRefill a second, and no pounce follows for feintRecover.
-- THE PEOPLE. Every AI townsperson (Pedestrian, not a rider) and police officer near a player's rodent runs a Combat/Duel
-- Guard: it notices (spot range x its temperament's notice, in view or close), reacts to tells, squares up, strikes,
-- backs off, flinches or flees, and the service turns the Guard's move into the brain's orders (Pedestrian "duel" and
-- "witness" events, Officer "respond") and its stance into the body's Stance attribute (clients draw it; the vigilante's
-- "squared" stance is the visible tell). A blow that lands calls `hurt` (CombatRules.damage; rodent.iFrames between
-- blows); Boot/Game applies the health, the Power and the knock-out as it does for a player's kick. A person a player
-- holds is never ordered: they kick with F on their own timing (`heldKick`: a kick aimed at the rodent raises a leg for
-- HELD_GUARD seconds, no bite lands into it; their kick shares the duel's i-frames, `takeBlow`), and a bite on them is
-- "unaware" otherwise. A person the bite-to-hospital sequence has in hand (Infection/InfectionService:engaged: a case,
-- the crowd, the crew, the walk home) is left out of the duel.
-- THE VIGILANTES. VigilanteRules keeps round(human.vigilanteShare x every human actor) flags, rebalanced once a second, on
-- AI townspeople (the bodies whose brain can take the rodent on); a flagged person is tough and, on sighting the
-- rodent, moves to kick it. `summon(x, z, r)` is the drone's call: flagged people within r head for the spot.
-- THE AFTERMATH. Every bite opens an alert zone (alert.radiusU, alert.ttl) at the victim: in it every person's blows
-- carry the hidden strength boost (alert.kickMult; also for a player's kick: `boost`), everyone swings and kicks more
-- (alert.swingBias), and a bite on anyone in it is multiplied by alert.bitePenalty (close to impossible). NPC officers
-- within alert.policeChaseBlocks blocks (alert.blockLenU) chase the biter while it stays within
-- alert.policeLeashBlocks blocks of the bite, for the zone's life.
-- Step-driven: requiring this module starts nothing; Boot/Game calls step(dt, now) ten times a second. `now` is the
-- duel's own clock (Boot/Game's); the orders to brains are stamped on the town's (world.now), which the brains read.
-- Interface: new(opts) -> Service; :rodentAct(id, verb, now) -> (ok, why?); :step(dt, now);
--   :heldKick(id, now, lookX?, lookZ?) -> aimed; :takeBlow(rodentId, now) -> boolean (a player's kick, with the duel's
--   i-frames); :inAlert(x, z, now) -> boolean; :boost(x, z, now) -> number (the kick multiplier there);
--   :temperOf(id) -> Temper;
--   :isVigilante(id) -> boolean; :summon(x, z, r); :zones() -> { Zone }; :guardOf(id) -> Guard?; :stats();
--   :stop() (every order and stance let go); HELD_GUARD; CHASE_EVERY; SOUNDS (cue name -> id)
-- Ids are TownAI actor ids. Positions in studs.

local Import = require("../Import")
local CombatRules = Import.shared("Combat/CombatRules") :: typeof(require("../../shared/Combat/CombatRules"))
local Duel = Import.shared("Combat/Duel") :: typeof(require("../../shared/Combat/Duel"))
local VigilanteRules = Import.shared("Combat/VigilanteRules") :: typeof(require("../../shared/Combat/VigilanteRules"))
local Cover = Import.shared("Combat/Cover") :: typeof(require("../../shared/Combat/Cover"))
local Colliders = Import.shared("World/Colliders") :: typeof(require("../../shared/World/Colliders"))

-- Exported types do not cross Import (W1 Track A note): the shared ones are restated loosely here.
type Params = any
type Guard = any
type Temper = string
type Sample = { t: number, x: number, z: number }

export type Opts = {
	world: any, -- AI/TownAI.World
	infection: any?, -- Infection/InfectionService (biteable, engaged)
	params: Params?,
	rand: (() -> number)?,
	controllerOf: ((id: number) -> string)?, -- "ai" | "player"; default: world.possessed
	rodents: () -> { number }, -- the player-held Spicy Rodents that can fight now
	-- the rodent's motor as the validator saw it: seconds since its last clean packet, and since the last pounce launch
	-- a clean packet showed (Movement/MovementService:motorOf); nil before any packet
	motorOf: ((id: number) -> Motor?)?,
	-- the link's round trip of the player holding the rodent, seconds (Player:GetNetworkPing): a bite is judged against
	-- the person as that player saw them, up to duel.lagMax back (Combat/Duel.bitePhaseAt); nil: no rewind
	linkOf: ((id: number) -> number?)?,
	setAttr: ((id: number, name: string, value: any) -> ())?,
	notify: ((rodentId: number, payload: { [string]: any }) -> ())?, -- news for the player holding the rodent
	hurt: ((rodentId: number, amount: number, cause: string, byId: number) -> ())?,
	bitten: ((victimId: number, rodentId: number) -> ())?, -- a bite landed: the game's consequences
	covered: ((id: number) -> boolean)?, -- the rodent is out of everyone's sight (a drain, a hollow)
	-- the town's solid lots (World/Colliders): nobody sees, or lands a blow on, the rodent through a building
	-- (default: the bite-to-hospital sequence's own, infection.colliders)
	colliders: any?,
	cue: ((id: number, cue: string) -> ())?, -- a sound by cue name at a body (CombatService.SOUNDS)
}

export type Motor = { age: number, launchAgo: number? }

export type Zone = { x: number, z: number, at: number, untilT: number, biter: number }

type Rodent = {
	id: number,
	tell: number?,
	tellFeint: boolean,
	launchDue: number, -- the motor's pounce is due then (the tell plus the wind-up)
	commitAt: number,
	windowUntil: number,
	recoverUntil: number,
	cooldownUntil: number,
	feintMeter: number,
	feintUntil: number,
	iUntil: number,
	landed: boolean, -- this pounce has made its contact
	history: { Sample },
	lastX: number?, -- where the rodent was at the last step (contact is judged along the move since)
	lastZ: number,
}

type Chase = { zone: Zone, nextAt: number }

local CombatService = {}
CombatService.__index = CombatService

CombatService.HELD_GUARD = 0.3 -- s: a player's kick at the rodent keeps a raised leg this long
CombatService.HELD_AIM = 4 -- studs beyond the kick's reach a player's kick still counts as aimed at the rodent
CombatService.CHASE_EVERY = 0.5 -- s between a chasing officer's new orders
CombatService.ORDER_SECS = 0.6 -- a duel order lasts this long unless renewed
CombatService.REBALANCE_SECS = 1
-- The duel's sounds, by cue name, played at the body (Boot/Game: a Sound named after the cue). The ids are to be
-- chosen from Roblox's licensed library (docs/AUDIO_BUDGET.md); an empty id is silent.
CombatService.SOUNDS = table.freeze({
	["Duel.Windup"] = "", -- the rodent gathers itself to pounce (or feints): a short hiss
	["Duel.Strike"] = "", -- a person's kick or swing comes down: a whoosh
	["Duel.Blow"] = "", -- the blow lands on the rodent: a soft thump and a squeak (no crunch)
	["Duel.Batted"] = "", -- a bite batted away: a slap and a yelp
	["Duel.Squareup"] = "", -- a vigilante squares up: a grunt ("Hey!")
}) :: { [string]: string }

export type Service = typeof(setmetatable(
	{} :: {
		world: any,
		infection: any?,
		P: Params,
		rand: () -> number,
		opts: Opts,
		rods: { [number]: Rodent },
		guards: { [number]: Guard },
		fleeing: { [number]: boolean },
		stances: { [number]: string? },
		flags: { [any]: boolean },
		tempers: { [number]: Temper },
		heldKicks: { [number]: number },
		alerts: { Zone },
		chases: { [number]: Chase },
		rebalanceAt: number,
		_stats: { [string]: number },
	},
	CombatService
))

function CombatService.new(opts: Opts): Service
	local self = setmetatable({
		world = opts.world,
		infection = opts.infection,
		P = opts.params or CombatRules.params(),
		rand = opts.rand or math.random,
		opts = opts,
		rods = {},
		guards = {},
		fleeing = {},
		stances = {},
		flags = {},
		tempers = {},
		heldKicks = {},
		alerts = {},
		chases = {},
		rebalanceAt = -math.huge,
		_stats = {
			pounces = 0,
			feints = 0,
			refused = 0,
			bites = 0,
			batted = 0,
			missed = 0,
			strikes = 0,
			blows = 0,
			zones = 0,
			chases = 0,
			noMotor = 0,
		},
	}, CombatService)
	return self
end

local function controllerOf(self: Service, id: number): string
	local f = self.opts.controllerOf
	if f then
		return f(id)
	end
	return if self.world.possessed[id] then "player" else "ai"
end

local function setAttr(self: Service, id: number, name: string, value: any)
	local f = self.opts.setAttr
	if f then
		f(id, name, value)
	end
end

local function notify(self: Service, id: number, payload: { [string]: any })
	local f = self.opts.notify
	if f then
		f(id, payload)
	end
end

local function cue(self: Service, id: number, name: string)
	local f = self.opts.cue
	if f then
		f(id, name)
	end
end

local function covered(self: Service, id: number): boolean
	local f = self.opts.covered
	if f then
		return f(id)
	end
	return self.world.covered ~= nil and self.world.covered[id] ~= nil
end

-- can the person at `a` see (and reach) the rodent at `rod`: no Combat/Cover housing between them (one inside, one
-- out), no building in the line at chest height
local function inSight(self: Service, a: any, rod: any): boolean
	if Cover.between(a.x, a.y, a.z, rod.x, rod.y, rod.z) then
		return false
	end
	local c = self.opts.colliders or (self.infection and (self.infection :: any).colliders)
	if c == nil then
		return true
	end
	return not Colliders.blocked(c, a.x, a.z, rod.x, rod.z, 1, (a.y - (a.hip or 0)) + 3)
end

local function rodent(self: Service, id: number): Rodent
	local r = self.rods[id]
	if r == nil then
		r = {
			id = id,
			tell = nil,
			tellFeint = false,
			launchDue = -math.huge,
			commitAt = -math.huge,
			windowUntil = -math.huge,
			recoverUntil = -math.huge,
			cooldownUntil = -math.huge,
			feintMeter = 1,
			feintUntil = -math.huge,
			iUntil = -math.huge,
			landed = true,
			history = {},
			lastX = nil,
			lastZ = 0,
		}
		self.rods[id] = r
	end
	return r
end

-- the person's temperament: tough with a vigilante flag; officers are always tough
function CombatService.temperOf(self: Service, id: number): Temper
	local a = self.world.actorsById[id]
	if a and a.post == "police" then
		return "tough"
	end
	if self.flags[id] then
		return "tough"
	end
	local t = self.tempers[id]
	if t == nil then
		t = CombatRules.temperament(id, false, self.P.waryShare)
		self.tempers[id] = t
	end
	return t
end

function CombatService.isVigilante(self: Service, id: number): boolean
	return self.flags[id] == true
end

function CombatService.zones(self: Service): { Zone }
	return self.alerts
end

function CombatService.guardOf(self: Service, id: number): Guard?
	return self.guards[id]
end

function CombatService.stats(self: Service): { [string]: number }
	return table.clone(self._stats)
end

function CombatService.inAlert(self: Service, x: number, z: number, now: number): boolean
	local r2 = self.P.alertRadius * self.P.alertRadius
	for _, zone in self.alerts do
		if now < zone.untilT and (zone.x - x) ^ 2 + (zone.z - z) ^ 2 <= r2 then
			return true
		end
	end
	return false
end

-- the hidden strength boost at a point: alert.kickMult in a zone, 1 elsewhere (a player's kick uses it too)
function CombatService.boost(self: Service, x: number, z: number, now: number): number
	return if self:inAlert(x, z, now) then self.P.kickMult else 1
end

-- The player's click (a pounce's tell) or F (a feint). Refused while the rodent cannot: a pounce or a feint still
-- running, the cooldown, an empty feint meter.
function CombatService.rodentAct(self: Service, id: number, verb: string, now: number): (boolean, string?)
	local P = self.P
	local r = rodent(self, id)
	local busy = now < r.windowUntil or now < r.commitAt or now < r.recoverUntil
	if verb == "pounce" then
		-- (the motor's own rule: a pounce once its cooldown is over, whatever became of the last one; the client clicks
		-- on the motor's cooldown, so a quick retry after a miss is a real pounce, not a lunge the duel ignores)
		if now < r.commitAt or now < r.cooldownUntil or now < r.feintUntil then
			self._stats.refused += 1
			return false, "not yet"
		end
		if not r.landed then
			-- the last pounce is still in its window: this one replaces it, a miss
			self._stats.missed += 1
			notify(self, id, { kind = "duel", what = "missed" })
		end
		r.tell = now
		r.tellFeint = false
		r.commitAt = now + P.pounceWindup
		r.launchDue = r.commitAt
		r.windowUntil = r.commitAt + P.pounceWindow + P.rewind
		r.cooldownUntil = r.commitAt + P.pounceCooldown - P.rewind -- (the motor's own 0.7 s, less the link's slack)
		r.landed = false
		self._stats.pounces += 1
	elseif verb == "feint" then
		if busy or now < r.feintUntil then
			self._stats.refused += 1
			return false, "not yet"
		end
		if r.feintMeter < P.feintCost then
			self._stats.refused += 1
			return false, "winded"
		end
		r.feintMeter -= P.feintCost
		r.tell = now
		r.tellFeint = true
		r.feintUntil = now + P.feintRecover
		self._stats.feints += 1
	else
		return false, "unknown"
	end
	setAttr(self, id, "PounceAt", now) -- the wind-up everyone sees (a feint looks the same)
	cue(self, id, "Duel.Windup")
	return true
end

-- A person a player holds kicked (F), facing (lookX, lookZ) (default: the body's yaw): a raised leg for HELD_GUARD
-- seconds, if the kick was aimed at a rodent in play (in front, within the reach and HELD_AIM): a kick at nothing
-- raises no guard, so mashing F does not make a person bite-proof. True when it counted.
function CombatService.heldKick(self: Service, id: number, now: number, lookX: number?, lookZ: number?): boolean
	local a = self.world.actorsById[id]
	if a == nil then
		return false
	end
	local fx, fz = lookX or math.sin(a.yaw or 0), lookZ or math.cos(a.yaw or 0)
	local fm = math.sqrt(fx * fx + fz * fz)
	if fm < 1e-6 then
		return false
	end
	fx, fz = fx / fm, fz / fm
	local reach = self.P.kickReach + CombatService.HELD_AIM
	for rid in self.rods do
		local rod = self.world.actorsById[rid]
		if rod then
			local dx, dz = rod.x - a.x, rod.z - a.z
			local d = math.sqrt(dx * dx + dz * dz)
			if d <= reach and (d < 1 or (dx * fx + dz * fz) / d >= 0.3) then
				self.heldKicks[id] = now
				return true
			end
		end
	end
	return false
end

-- A player's kick is about to land on the rodent `rodentId`: false while the rodent is inside the duel's i-frames (a
-- blow just landed, from anyone), else the blow counts as the duel's own (its i-frames start, its pounce is spent).
-- A body not in the duel always takes it.
function CombatService.takeBlow(self: Service, rodentId: number, now: number): boolean
	local r = self.rods[rodentId]
	if r == nil then
		return true
	end
	if now < r.iUntil then
		return false
	end
	r.iUntil = now + self.P.iFrames
	r.windowUntil = math.min(r.windowUntil, now)
	r.commitAt = math.min(r.commitAt, now)
	r.landed = true
	r.recoverUntil = now + self.P.pounceRecovery
	return true
end

-- The drone's call: the vigilantes within r of (x, z) head for the spot.
function CombatService.summon(self: Service, x: number, z: number, r: number)
	for id in self.flags do
		local a = self.world.actorsById[id]
		local brain = self.world.brains[id] :: any
		if a and brain and controllerOf(self, id) == "ai" and (a.x - x) ^ 2 + (a.z - z) ^ 2 <= r * r then
			if not (self.infection and self.infection:engaged(id)) then
				brain:onEvent({
					type = "duel",
					mode = "approach",
					x = x,
					z = z,
					speed = self.P.approach,
					untilTime = (self.world.now or 0) + 10,
				})
			end
		end
	end
end

local function setStance(self: Service, id: number, stance: string?)
	if self.stances[id] ~= stance then
		if stance == "squared" and self.stances[id] == nil then
			cue(self, id, "Duel.Squareup")
		end
		self.stances[id] = stance
		setAttr(self, id, "Stance", stance)
	end
end

-- a person leaves the duel: their orders and stance are let go
local function release(self: Service, id: number)
	local g = self.guards[id]
	if g == nil then
		return
	end
	self.guards[id] = nil
	self.fleeing[id] = nil
	setStance(self, id, nil)
	local brain = self.world.brains[id] :: any
	if brain and brain.kind == "Pedestrian" and controllerOf(self, id) == "ai" then
		brain:onEvent({ type = "duel", mode = "end" })
	end
end

local function rebalance(self: Service, now: number)
	if now < self.rebalanceAt then
		return
	end
	self.rebalanceAt = now + CombatService.REBALANCE_SECS
	local all, holders = 0, {}
	for _, a in self.world.actors do
		if a.species == "human" then
			all += 1
			if a.post == "townsperson" then
				table.insert(holders, { id = a.id, ai = controllerOf(self, a.id) == "ai" })
			end
		end
	end
	-- the share is of every human actor; the flags sit on the townspeople (their brain can take the rodent on)
	local want = math.floor(all * self.P.vigilanteShare + 0.5)
	local share = if #holders > 0 then want / #holders else 0
	local before = self.flags
	self.flags = VigilanteRules.rebalance(holders, before, share)
	-- (the share of the holders rounds to the same count: VigilanteRules.target(holders, share) == want)
	for id in before do
		if not self.flags[id] then
			local g = self.guards[id]
			if g then
				release(self, id) -- taken by a player, or the town shrank: the next guard starts afresh
			end
		end
	end
end

-- can this body take part: an AI townsperson (not a rider) or an AI officer, in sight, not in the sequence's hands
local function fighter(self: Service, a: any): boolean
	if a.species ~= "human" or (a.lift or 0) ~= 0 then
		return false
	end
	if a.post ~= "townsperson" and a.post ~= "police" then
		return false
	end
	if controllerOf(self, a.id) ~= "ai" then
		return false
	end
	if self.infection and self.infection:engaged(a.id) then
		return false
	end
	local brain = self.world.brains[a.id] :: any
	if brain == nil or (brain.kind ~= "Pedestrian" and brain.kind ~= "Officer") then
		return false
	end
	if brain.directive and brain.directive.mode ~= nil then
		return false
	end
	return true
end

local function order(self: Service, a: any, rod: any, out: any)
	local brain = self.world.brains[a.id] :: any
	if brain.kind == "Officer" then
		-- an officer closes in and stands over it (Officer "respond" stops a couple of studs short)
		brain:onEvent({
			type = "respond",
			x = rod.x,
			z = rod.z,
			untilTime = (self.world.now or 0) + CombatService.ORDER_SECS,
		})
		return
	end
	if out.move == "flee" then
		if not self.fleeing[a.id] then
			self.fleeing[a.id] = true
			brain:onEvent({ type = "witness", threat = rod, alert = 8 })
		end
		return
	end
	self.fleeing[a.id] = nil
	if out.move == "none" then
		return
	end
	brain:onEvent({
		type = "duel",
		mode = out.move,
		x = rod.x,
		z = rod.z,
		speed = out.speed,
		untilTime = (self.world.now or 0) + CombatService.ORDER_SECS,
	})
end

local function endPounce(self: Service, r: Rodent, now: number)
	r.windowUntil = math.min(r.windowUntil, now)
	r.commitAt = math.min(r.commitAt, now)
	r.landed = true
	r.recoverUntil = now + self.P.pounceRecovery
end

local function openZone(self: Service, x: number, z: number, now: number, biter: number)
	local P = self.P
	local zone: Zone = { x = x, z = z, at = now, untilT = now + P.alertTtl, biter = biter }
	table.insert(self.alerts, zone)
	self._stats.zones += 1
	-- the officers within about two blocks give chase
	local reach = P.chaseBlocks * P.blockLen
	for _, a in self.world.actors do
		local brain = self.world.brains[a.id] :: any
		if a.post == "police" and brain and brain.kind == "Officer" and controllerOf(self, a.id) == "ai" then
			if
				(a.x - x) ^ 2 + (a.z - z) ^ 2 <= reach * reach and not (self.infection and self.infection:engaged(a.id))
			then
				self.chases[a.id] = { zone = zone, nextAt = now }
				self._stats.chases += 1
			end
		end
	end
end

local function stepChases(self: Service, now: number)
	local P = self.P
	local leash = P.leashBlocks * P.blockLen
	for id, c in self.chases do
		local zone = c.zone
		local rod = self.world.actorsById[zone.biter]
		local brain = self.world.brains[id] :: any
		local live = now < zone.untilT and rod ~= nil and brain ~= nil and self.rods[zone.biter] ~= nil
		if live then
			live = (rod.x - zone.x) ^ 2 + (rod.z - zone.z) ^ 2 <= leash * leash
				and not covered(self, zone.biter)
				and controllerOf(self, id) == "ai"
				and not (self.infection and self.infection:engaged(id))
		end
		if not live then
			self.chases[id] = nil
		elseif now >= c.nextAt and self.guards[id] == nil then
			c.nextAt = now + CombatService.CHASE_EVERY
			brain:onEvent({
				type = "respond",
				x = rod.x,
				z = rod.z,
				untilTime = (self.world.now or 0) + CombatService.CHASE_EVERY * 2,
			})
		end
	end
end

-- the people round one rodent: their duels (returns nothing; orders, stances and blows are applied)
local function stepGuards(self: Service, now: number, dt: number, live: { [number]: boolean })
	local P = self.P
	local world = self.world
	local seenReach = math.max(P.engage, P.spotRange * P.notice.tough) + Duel.FLEE_CLEAR
	for _, a in world.actors do
		if a.species ~= "human" then
			continue
		end
		local g = self.guards[a.id]
		if not fighter(self, a) then
			if g then
				release(self, a.id)
			end
			continue
		end
		-- the nearest rodent in play
		local best: any, bestD = nil, math.huge
		for id in live do
			local rod = world.actorsById[id]
			if rod then
				local d = math.sqrt((rod.x - a.x) ^ 2 + (rod.z - a.z) ^ 2)
				if d < bestD then
					best, bestD = rod, d
				end
			end
		end
		local running = g ~= nil and (g.phase == "flee" or (g.phase == "startle" and g.running))
		if best == nil or (bestD > seenReach and not running) then
			if g then
				release(self, a.id)
			end
			continue
		end
		local temper = self:temperOf(a.id)
		if g == nil or g.temper ~= temper then
			if g then
				release(self, a.id)
			end
			g = Duel.new(
				P,
				a.id,
				temper,
				CombatRules.nerve(P, a.id, temper),
				if a.post == "police" then "baton" else "kick"
			)
			self.guards[a.id] = g
		end
		local guard = g :: Guard
		local r = self.rods[best.id] :: Rodent
		local dx, dz = best.x - a.x, best.z - a.z
		local facing = (dx * math.sin(a.yaw) + dz * math.cos(a.yaw)) / math.max(bestD, 1e-6)
		-- (out of sight: in a drain or a hollow, behind a housing's walls or a building)
		local hidden = covered(self, best.id) or not inSight(self, a, best)
		local boosted = self:inAlert(a.x, a.z, now)
		local view: any = {
			now = now,
			dt = dt,
			dist = bestD,
			dy = (best.y - best.hip) - (a.y - a.hip),
			seen = not hidden and Duel.notices(P, guard, bestD, facing >= 0.28),
			tell = if hidden then nil else r.tell,
			tellFeint = r.tellFeint,
			committed = now >= r.commitAt and now < r.windowUntil,
			recovering = now < r.recoverUntil,
			zigzag = CombatRules.zigzag(P, r.history, dx, dz, now),
			boosted = boosted,
		}
		local out = Duel.think(P, guard, view, self.rand)
		if guard.phase == "idle" then
			release(self, a.id)
			continue
		end
		if hidden and out.move == "approach" then
			out.move = "stand" -- (lost sight of it: nobody walks into a wall after it)
		end
		order(self, a, best, out)
		setStance(self, a.id, out.stance)
		local strike = out.strike
		if strike then
			self._stats.strikes += 1
			cue(self, a.id, "Duel.Strike")
			if strike.hit and not hidden and now >= r.iUntil then
				self._stats.blows += 1
				r.iUntil = now + P.iFrames
				endPounce(self, r, now)
				cue(self, best.id, "Duel.Blow")
				local f = self.opts.hurt
				if f then
					f(best.id, CombatRules.damage(P, strike.kind, boosted), strike.kind, a.id)
				end
			elseif bestD <= Duel.reach(P, guard) + 3 then
				notify(self, best.id, { kind = "duel", what = "dodged", by = strike.kind })
			end
		end
	end
end

-- the bite: the nearest person in contact inside the pounce's window
local function stepBites(self: Service, now: number, live: { [number]: boolean })
	local P = self.P
	local world = self.world
	for id in live do
		local r = self.rods[id]
		if r.landed then
			continue
		end
		if now >= r.windowUntil then
			r.landed = true
			r.recoverUntil = now + P.pounceRecovery
			self._stats.missed += 1
			notify(self, id, { kind = "duel", what = "missed" })
			continue
		end
		if now < r.commitAt then
			continue
		end
		local rod = world.actorsById[id]
		if rod == nil then
			continue
		end
		local motorOf = self.opts.motorOf
		if motorOf then
			-- the motor's own pounce, launched when the click said (within the link's slack), still in its window, and
			-- a fresh packet: a click alone bites nobody, and neither does a lunge held back for a better moment
			local m = motorOf(id)
			local launchAt = if m and m.launchAgo then now - m.launchAgo else nil
			local slack = P.rewind + P.launchSlack
			if
				m == nil
				or m.age > P.motorFresh
				or launchAt == nil
				or math.abs(launchAt - r.launchDue) > slack
				or now > launchAt + P.pounceWindow + P.rewind
			then
				self._stats.noMotor += 1
				continue -- the motor has not shown this pounce (yet)
			end
		end
		local ry = rod.y - rod.hip
		local victim: any, vd = nil, P.contact
		-- (along the move since the last step; a jump further than a pounce makes in two steps is a move the server made)
		local fromX, fromZ = rod.x, rod.z
		local lx = r.lastX
		if lx ~= nil and (lx - rod.x) ^ 2 + (r.lastZ - rod.z) ^ 2 <= (P.contact * 3) ^ 2 then
			fromX, fromZ = lx, r.lastZ
		end
		for _, a in world.actors do
			if a.species == "human" and (a.lift or 0) == 0 then
				local d = Duel.sweep(fromX, fromZ, rod.x, rod.z, a.x, a.z)
				local ay = a.y - a.hip
				if
					d <= vd
					and math.abs(ay - ry) <= P.contactHeight
					and (self.infection == nil or self.infection:biteable(a.id))
					and not Cover.between(rod.x, rod.y, rod.z, a.x, a.y, a.z)
				then
					victim, vd = a, d
				end
			end
		end
		if victim == nil then
			continue
		end
		local vid = victim.id
		local held = controllerOf(self, vid) ~= "ai"
		local phase: string
		local temper: Temper
		if held then
			temper = "calm"
			local k = self.heldKicks[vid]
			phase = if k and now - k <= CombatService.HELD_GUARD then "windup" else "unaware"
		else
			temper = self:temperOf(vid)
			local g = self.guards[vid]
			local linkOf = self.opts.linkOf
			local rewind = math.clamp(if linkOf then linkOf(id) or 0 else 0, 0, P.lagMax)
			phase = if g then Duel.bitePhaseAt(g, now, rewind, r.tell) else "unaware"
		end
		local chance = CombatRules.biteChance(P, temper, phase, self:inAlert(victim.x, victim.z, now))
		endPounce(self, r, now)
		if self.rand() < chance then
			self._stats.bites += 1
			release(self, vid)
			openZone(self, victim.x, victim.z, now, id)
			local f = self.opts.bitten
			if f then
				f(vid, id)
			end
		else
			self._stats.batted += 1
			cue(self, vid, "Duel.Batted")
			local g = self.guards[vid]
			if g then
				Duel.batted(g, now)
			end
			notify(self, id, {
				kind = "duel",
				what = "batted",
				phase = phase,
				zone = self:inAlert(victim.x, victim.z, now),
			})
		end
	end
end

function CombatService.step(self: Service, dt: number, now: number)
	local P = self.P
	rebalance(self, now)
	-- the zones run out
	for i = #self.alerts, 1, -1 do
		if now >= self.alerts[i].untilT then
			table.remove(self.alerts, i)
		end
	end
	-- the rodents in play: their history (the zig-zag) and the feint meter
	local live: { [number]: boolean } = {}
	for _, id in self.opts.rodents() do
		local rod = self.world.actorsById[id]
		if rod then
			live[id] = true
			local r = rodent(self, id)
			r.feintMeter = math.min(1, r.feintMeter + P.feintRefill * dt)
			table.insert(r.history, { t = now, x = rod.x, z = rod.z })
			while #r.history > 0 and r.history[1].t < now - P.zigzagSecs - 0.2 do
				table.remove(r.history, 1)
			end
		end
	end
	for id in self.rods do
		if not live[id] then
			self.rods[id] = nil -- (let go, knocked out, or another body: a fresh start next time)
		end
	end
	stepGuards(self, now, dt, live)
	stepBites(self, now, live)
	stepChases(self, now)
	for id in live do
		local rod = self.world.actorsById[id]
		local r = self.rods[id]
		if rod and r then
			r.lastX, r.lastZ = rod.x, rod.z
		end
	end
end

function CombatService.stop(self: Service)
	local ids = {}
	for id in self.guards do
		table.insert(ids, id)
	end
	for _, id in ids do
		release(self, id)
	end
	table.clear(self.chases)
end

return CombatService
