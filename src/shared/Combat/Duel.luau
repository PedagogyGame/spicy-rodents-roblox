--!strict
-- ReplicatedStorage.Shared.Combat.Duel
-- One person's side of a duel with the Spicy Rodent (brief v2 §8 "Combat dynamics"), on Combat/CombatRules' numbers.
-- Server/Combat/CombatService runs one Guard per AI person near a player's rodent; the duel simulation
-- (tests/lib/DuelSim) runs the same Guard against scripted rodents, so the balance it proves is the game's.
-- The person's phases:
--   idle      has not seen the rodent (a bite is "unaware")
--   ready     squared up: a tough person closes to striking range, the others stand their ground; an arm is up
--             ("guard"); strikes at a rodent coming into reach (entryStrike: a straight run is readable) and now and
--             then at one that stays there (strikeRate a second)
--   startle   a pounce's tell was just seen: the reaction window until react[temper] after the tell, then the response
--             picked at the tell (CombatRules.weights: flee, back, flinch, swing, kick) takes over. The window is open
--             unless the person was squared up with the arm already up (guardUp[temper]; a tough person always is)
--   flinch    open for flinchSecs, then ready
--   back      backing away with an arm up for backSecs, then ready
--   windup    a raised leg or arm (no bite lands), stepping in at stepIn; then the strike, then recover
--   recover   open for recover[temper], then ready
--   flee      runs (never a tough person); a bite at the heels is "runner"
-- A feint is a tell with no pounce after it: read (readFeint) the person counters at once, a quicker wind-up with a
-- longer reach and counterHit (the brief's "free hit"); not read, they react to it as to a real pounce, and a swing at
-- nothing leaves them open.
-- Interface: new(params, id, temper, nerve, weapon?) -> Guard; notices(params, g, dist, inView) -> boolean;
--   think(params, g, view, rand) -> Out; bitePhase(g, now) -> CombatRules.BitePhase; batted(g, now) (a bite failed on
--   them: back to ready unless striking); reach(params, g) -> studs; PHASES
-- Pure; studs and seconds. No side effects on require.

local CombatRules = require("./CombatRules")

type Params = CombatRules.Params

export type Phase = "idle" | "ready" | "startle" | "flinch" | "back" | "windup" | "recover" | "flee"

export type Guard = {
	id: any,
	temper: CombatRules.Temper,
	nerve: number,
	weapon: string, -- "kick" (and "swing"), or "baton" (an officer)
	aware: boolean,
	awareAt: number,
	phase: Phase,
	untilT: number, -- the phase ends
	reactAt: number, -- startle: the response takes over
	pending: CombatRules.Response?,
	strike: string?, -- the blow being wound up: kick | swing | baton
	counter: boolean,
	lastTell: number?,
	guarded: boolean, -- startle: the arm was already up when the tell came
	running: boolean, -- startle: the tell came at their back while they ran
	inReach: boolean, -- the rodent was within striking range last tick
	fleeFrom: number, -- when the flight began
	strikes: number,
	hits: number,
}

-- What the person sees this tick (CombatService from the town, DuelSim from its own world).
export type View = {
	now: number,
	dt: number,
	dist: number, -- studs, flat, to the rodent
	dy: number?, -- the rodent's height over the person's feet
	seen: boolean, -- noticed (Duel.notices, or the town's perception)
	tell: number?, -- when the rodent's latest tell (a pounce's wind-up, or a feint) began
	tellFeint: boolean?, -- that tell is a feint
	committed: boolean, -- the rodent is mid-pounce
	recovering: boolean, -- the rodent is recovering from a pounce
	zigzag: number, -- 0 to 1
	boosted: boolean, -- near a fresh bite: the hidden strength boost
}

export type Strike = { kind: string, hit: boolean, counter: boolean, chance: number }

export type Out = {
	move: "none" | "stand" | "approach" | "back" | "flee", -- what the body does
	speed: number, -- studs/s for approach and back
	strike: Strike?, -- a blow came down this tick
	reacted: CombatRules.Response?, -- the response that took over this tick
	read: boolean, -- a feint was read this tick
	stance: string?, -- the visible stance: nil | "squared" | "windup" | "guard" | "flinch"
}

local Duel = {}

Duel.PHASES = table.freeze({ "idle", "ready", "startle", "flinch", "back", "windup", "recover", "flee" })
Duel.FLEE_SECS = 8 -- a flight lasts this long at most
Duel.FLEE_CLEAR = 15 -- studs beyond engage: far enough, the flight ends
Duel.STARTLED_SECS = 0.8 -- a calm or wary person who noticed the rodent this recently is caught unready

function Duel.new(params: Params, id: any, temper: CombatRules.Temper, nerve: number, weapon: string?): Guard
	local _ = params
	return {
		id = id,
		temper = temper,
		nerve = nerve,
		weapon = weapon or "kick",
		aware = false,
		awareAt = 0,
		phase = "idle",
		untilT = 0,
		reactAt = 0,
		pending = nil,
		strike = nil,
		counter = false,
		lastTell = nil,
		guarded = false,
		running = false,
		inReach = false,
		fleeFrom = 0,
		strikes = 0,
		hits = 0,
	}
end

-- Does the person notice the rodent at this distance: within the spot range times their temperament's notice, in
-- view, or close enough to hear and feel (v5.4: under 6.8 u = 17 studs whatever the facing).
function Duel.notices(params: Params, g: Guard, dist: number, inView: boolean): boolean
	return dist <= params.spotRange * params.notice[g.temper] and (inView or dist < 17)
end

-- The reach of the blow being wound up (studs).
function Duel.reach(params: Params, g: Guard): number
	local r = if g.strike == "swing" then params.swingReach else params.kickReach
	if g.counter then
		r += params.counterLunge
	end
	return r
end

local function windupSecs(params: Params, g: Guard): number
	local w = params.windup[g.temper]
	if g.strike == "swing" then
		w *= params.swingWindupMult
	end
	if g.counter then
		w *= params.counterWindupMult
	end
	return w
end

local function startStrike(params: Params, g: Guard, now: number, kind: string, counter: boolean)
	g.phase = "windup"
	g.strike = if g.weapon == "baton" then "baton" else kind
	g.counter = counter
	g.untilT = now + windupSecs(params, g)
end

local function ready(g: Guard)
	g.phase = "ready"
	g.strike = nil
	g.counter = false
	g.pending = nil
end

local function apply(params: Params, g: Guard, r: CombatRules.Response, now: number)
	if r == "flee" then
		if not (g.phase == "startle" and g.running) then
			g.fleeFrom = now -- (a runner who keeps running keeps the flight's clock)
		end
		g.phase = "flee"
	elseif r == "back" then
		g.phase = "back"
		g.untilT = now + params.backSecs
	elseif r == "flinch" then
		g.phase = "flinch"
		g.untilT = now + params.flinchSecs
	else
		startStrike(params, g, now, r, false)
	end
end

local function stanceOf(g: Guard): string?
	if g.phase == "windup" then
		return "windup"
	elseif g.phase == "flinch" or g.phase == "startle" then
		return "flinch"
	elseif g.phase == "back" then
		return "guard"
	elseif g.phase == "ready" or g.phase == "recover" then
		return if g.temper == "tough" then "squared" else "guard"
	end
	return nil
end

function Duel.think(params: Params, g: Guard, view: View, rand: () -> number): Out
	local now = view.now
	local out: Out = { move = "none", speed = 0, strike = nil, reacted = nil, read = false, stance = nil }
	-- noticing, and letting go
	if not g.aware then
		if view.seen and view.dist <= params.engage then
			g.aware = true
			g.awareAt = now
			ready(g)
			-- first sight: a calm or wary person may run at once; a tough one squares up
			local w = CombatRules.weights(params, g.temper, g.nerve, view.boosted, true)
			if
				rand()
				< (w.flee or 0) / math.max(1e-6, (w.flee or 0) + (w.back or 0) + (w.swing or 0) + (w.kick or 0))
			then
				apply(params, g, "flee", now)
			end
		else
			return out
		end
	elseif view.dist > params.engage + Duel.FLEE_CLEAR and g.phase ~= "windup" then
		-- the rodent has gone: back to the day
		g.aware = false
		g.phase = "idle"
		g.lastTell = nil
		return out
	end

	-- a tell: the reaction (a feint is countered when it is read)
	local tell = view.tell
	if tell ~= nil and tell ~= g.lastTell then
		g.lastTell = tell
		-- (a runner hears the lunge behind them too: they may keep running, or turn on it)
		local free = g.phase == "ready" or g.phase == "back" or g.phase == "flinch" or g.phase == "flee"
		if free and view.dist <= params.threat then
			if view.tellFeint and rand() < params.readFeint[g.temper] then
				out.read = true
				startStrike(params, g, now, "kick", true)
			else
				-- (a vigilante is never caught unready: it squares up the moment it sees the rodent)
				local startled = g.temper ~= "tough" and now - g.awareAt < Duel.STARTLED_SECS
				local w = CombatRules.weights(params, g.temper, g.nerve, view.boosted, startled)
				g.pending = CombatRules.pick(w, rand())
				-- squared up, the arm may be up already; caught moving (backing off, flinching) or just noticing, it is not
				g.guarded = g.phase == "ready" and not startled and rand() < params.guardUp[g.temper]
				g.running = g.phase == "flee"
				g.phase = "startle"
				g.reactAt = math.max(now, tell + params.react[g.temper])
			end
		end
	end

	-- the phases run out
	if g.phase == "startle" and now >= g.reactAt then
		local r = g.pending or "back"
		g.pending = nil
		apply(params, g, r, now)
		out.reacted = r
	end
	if g.phase == "windup" and now >= g.untilT then
		local reach = Duel.reach(params, g)
		local chance = CombatRules.strikeChance(params, g.temper, {
			zigzag = view.zigzag,
			committed = view.committed,
			recovering = view.recovering,
			counter = g.counter,
			boosted = view.boosted,
		})
		local inReach = view.dist <= reach and math.abs(view.dy or 0) <= params.contactHeight
		local hit = inReach and rand() < chance
		g.strikes += 1
		if hit then
			g.hits += 1
		end
		out.strike =
			{ kind = g.strike or "kick", hit = hit, counter = g.counter, chance = if inReach then chance else 0 }
		g.phase = "recover"
		g.untilT = now + params.recover[g.temper]
		g.strike = nil
		g.counter = false
	elseif (g.phase == "flinch" or g.phase == "back" or g.phase == "recover") and now >= g.untilT then
		ready(g)
	elseif g.phase == "flee" then
		if now - g.fleeFrom >= Duel.FLEE_SECS or view.dist > params.engage + Duel.FLEE_CLEAR then
			if g.temper == "tough" then
				ready(g)
			else
				g.aware = false
				g.phase = "idle"
				return out
			end
		end
	end

	-- unprompted: a person squared up strikes at a rodent coming into reach (by the reach the step-in will give),
	-- and now and then at one that stays there
	local reachNow = params.kickReach + params.stepIn[g.temper] * params.windup[g.temper]
	local inReach = view.dist <= reachNow
	if g.phase == "ready" and inReach then
		local boost = if view.boosted then params.swingBias else 1
		local p = if g.inReach
			then params.strikeRate[g.temper] * boost * view.dt
			else math.min(1, params.entryStrike[g.temper] * boost)
		if rand() < p then
			startStrike(params, g, now, if rand() < 0.4 then "swing" else "kick", false)
		end
	end
	g.inReach = inReach

	-- what the body does
	if g.phase == "flee" or (g.phase == "startle" and g.running) then
		out.move = "flee"
	elseif g.phase == "back" then
		out.move, out.speed = "back", params.backSpeed
	elseif g.phase == "windup" then
		out.move, out.speed = "approach", params.stepIn[g.temper]
	elseif g.phase == "ready" and g.temper == "tough" and view.dist > params.kickReach * 0.9 then
		out.move, out.speed = "approach", params.approach
	else
		out.move = "stand"
	end
	out.stance = stanceOf(g)
	return out
end

-- How a bite would meet this person now.
function Duel.bitePhase(g: Guard, now: number): CombatRules.BitePhase
	if not g.aware or g.phase == "idle" then
		return "unaware"
	end
	local p = g.phase
	if p == "startle" then
		if g.running then
			return if now < g.reactAt then "runner" else "guard"
		end
		return if now < g.reactAt and not g.guarded then "open" else "guard"
	elseif p == "flinch" or p == "recover" then
		return "open"
	elseif p == "flee" then
		return "runner"
	elseif p == "windup" then
		return "windup"
	end
	return "guard"
end

-- A bite failed on this person ("Batted away"): they square up again unless a blow is on its way or they are running.
function Duel.batted(g: Guard, now: number)
	if g.phase == "startle" and g.running then
		g.phase = "flee" -- (shaken off, and still running)
	elseif g.phase ~= "windup" and g.phase ~= "flee" then
		ready(g)
	end
	g.aware = true
	if g.awareAt == 0 then
		g.awareAt = now
	end
end

return Duel
