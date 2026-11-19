--!strict
-- ReplicatedStorage.Shared.Combat.Duel
-- One person's side of a duel with the Spicy Rodent (brief v2 §8 "Combat dynamics"), on Combat/CombatRules' numbers.
-- Server/Combat/CombatService runs one Guard per AI person near a player's rodent; the duel simulation
-- (tests/lib/DuelSim) runs the same Guard against scripted rodents, so the balance it proves is the game's.
-- The person's phases:
--   idle      has not seen the rodent (a bite is "unaware")
--   ready     squared up: a tough person closes to striking range, the others stand their ground; an arm is up
--             ("guard"); strikes at a rodent coming into reach (entryStrike: a straight run is readable) and now and
--             then at one that stays there (strikeRate a second). A vigilante's stance ("squared", the tell) shows only
--             once it is provoked (it struck, or was set on) or the server shows it (`shown`); until then it looks
--             like anyone's ("guard")
--   startle   a pounce's tell was just seen: the reaction window until react[temper] after the tell, then the response
--             picked at the tell (CombatRules.weights: flee, back, flinch, swing, kick) takes over. The window is open
--             unless the person was squared up with the arm already up (guardUp[temper]; a tough person always is)
--   flinch    open for flinchSecs, then ready
--   back      backing away with an arm up for backSecs, then ready
--   windup    a raised leg or arm (no bite lands), stepping in at stepIn; then the strike, then recover
--   recover   open for recover[temper] (whiffRecover[temper] after a blow at nothing: the rodent out of reach), then
--             ready
--   flee      runs (never a tough person) for FLEE_SECS, as the brain's flight along the lane lasts; a bite at the
--             heels is "runner". A person still with the rodent close when the flight ends stays on their guard
-- A STALK FOUND OUT (owner: stalking "still possible, but harder"): a calm or wary person who first notices the rodent
-- within params.threat while it creeps (view.sneaking: it got right up to them), or hears the wind-up of a pounce they had not seen coming
-- (params.tellHeard, one roll a tell), cries out and turns on it as a scene does (Duel.rally) and is ALARMED for the rest
-- of the duel: blows as near a fresh bite (more swings, surer hits, never the bite penalty) and the arm always up when
-- squared up; so does one an unaware bite failed on. A person who saw it coming from further off is not alarmed.
-- A feint is a tell with no pounce after it: read (readFeint) the person counters at once, a quicker wind-up with a
-- longer reach and counterHit (the brief's "free hit"); not read, they react to it as to a real pounce, and a swing at
-- nothing leaves them open.
-- THE LINK. The rodent's player sees a person as they were a round trip ago (the server's word on its way down, the
-- pounce on its way up): a bite is judged against the person as the player saw them (bitePhaseAt: the trail of the
-- last TRAIL_SECS), except the reaction to that very pounce's tell, which runs on the server's clock (a slow link
-- buys no longer reaction window).
-- Interface: new(params, id, temper, nerve, weapon?) -> Guard; notices(params, g, sight) -> boolean;
--   think(params, g, view, rand) -> Out; bitePhase(g, now) -> CombatRules.BitePhase;
--   bitePhaseAt(g, now, rewind, tell?) -> CombatRules.BitePhase; batted(g, now) (a bite failed on them: back to ready
--   unless striking); rally(params, g, now, mode) (the scene turns on the rodent); reach(params, g) -> studs; sweep(ax, az, bx, bz, px, pz) -> studs; PHASES; FLEE_SECS; TRAIL_SECS
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
	rallyUntil: number, -- turned on the rodent (a bite, a group set on) until then: closes in, strikes on reaching it
	provoked: boolean, -- it has struck at the rodent or been set on by it: a vigilante's stance shows from then on
	alarmed: boolean, -- caught it sneaking up on them: on edge for the rest of the duel (blows as near a fresh bite)
	shown: boolean, -- a vigilante shown however it is (Server/Combat/CombatService: the town 40 % bitten)
	strikes: number,
	hits: number,
	trail: { Sample }, -- how a bite would have met them, think by think (the last TRAIL_SECS)
}

-- One think's record: the bite phase then, and the tell it was the reaction window of (if it was one).
export type Sample = { t: number, phase: CombatRules.BitePhase, tell: number? }

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
	sneaking: boolean?, -- the rodent moves no faster than a creep (params.quietSpeed): found close, it was stalking them
}

-- What the person can tell of the rodent, for noticing it (Duel.notices).
export type Sight = {
	dist: number, -- studs, flat
	dy: number?, -- the rodent's height over the person's feet
	inView: boolean, -- inside their view cone (the v5.4 cone: facing . direction > 0.28)
	speed: number?, -- the rodent's flat speed, studs/s (nil: moving)
	lunging: boolean?, -- in a pounce's wind-up or lunge
	spottedOverhead: boolean?, -- they have pointed it out above them (Stealth/OverheadWatch)
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
Duel.FLEE_SECS = 6 -- a flight lasts this long (Brains/Pedestrian: alert 8 falling to 2, running along the lane)
Duel.TRAIL_SECS = 0.5 -- how far back a bite may be judged (the link's round trip, duel.lagMax, is less)
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
		rallyUntil = 0,
		provoked = false,
		alarmed = false,
		shown = false,
		strikes = 0,
		hits = 0,
		trail = {},
	}
end

-- Does the person notice the rodent (the town's perception, so a stalk is a real play; combat review 19 Nov: "a person
-- notices the rodent within 17 studs whatever way they face"):
--   * it is pointed out overhead (Stealth/OverheadWatch: they have spotted it on a wire or a branch above them);
--   * higher over their feet than params.overheadY the duel does not see it at all (the overhead watch does);
--   * seen: in their view cone and within the spot range times their temperament's notice;
--   * heard: moving faster than a creep (params.quietSpeed) within params.hear times their notice, whatever the facing;
--   * felt: within params.brush of a rodent that is not pouncing.
-- (The pounce itself, its wind-up and lunge, is too quick to turn round for: noticing it is what the reaction window to
-- its tell is about, for a person already aware.) A creeping or still rodent behind a person, or one dropping from
-- above behind them, goes unnoticed until it brushes them. `speed` nil reads as moving (heard). (Duel.think adds one
-- last chance: a person who has not noticed it may hear the pounce's wind-up within params.threat and turn at the last
-- moment, params.tellHeard by temperament, caught unready.)
function Duel.notices(params: Params, g: Guard, sight: Sight): boolean
	if sight.spottedOverhead then
		return true
	end
	if (sight.dy or 0) > params.overheadY then
		return false
	end
	local notice = params.notice[g.temper]
	if sight.inView and sight.dist <= params.spotRange * notice then
		return true
	end
	if sight.lunging then
		return false
	end
	if sight.dist < params.brush then
		return true
	end
	local loud = sight.speed == nil or sight.speed > params.quietSpeed
	return loud and sight.dist <= params.hear * notice
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
	g.provoked = true
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
		-- (a vigilante looks like anyone else until provoked: owner 2026-11-19, "keep them hidden until provoked")
		local tough = g.temper == "tough" and (g.provoked or g.shown)
		return if tough or g.rallyUntil > 0 then "squared" else "guard"
	end
	return nil
end

local function record(g: Guard, now: number)
	local trail = g.trail
	table.insert(
		trail,
		{ t = now, phase = Duel.bitePhase(g, now), tell = if g.phase == "startle" then g.lastTell else nil }
	)
	while #trail > 1 and trail[1].t < now - Duel.TRAIL_SECS do
		table.remove(trail, 1)
	end
end

local function think(params: Params, g: Guard, view: View, rand: () -> number): Out
	local now = view.now
	local boosted = view.boosted or g.alarmed
	local out: Out = { move = "none", speed = 0, strike = nil, reacted = nil, read = false, stance = nil }
	-- noticing, and letting go
	-- (a vigilante takes the rodent on from as far as it sees it: "on sighting ... they move to kick it")
	local far = if g.temper == "tough"
		then math.max(params.engage, params.spotRange * params.notice.tough) + Duel.FLEE_CLEAR
		else params.engage + Duel.FLEE_CLEAR
	if not g.aware then
		if view.seen and (view.dist <= params.engage or g.temper == "tough") then
			g.aware = true
			g.awareAt = now
			ready(g)
			-- first sight: a calm or wary person may run at once; a tough one squares up
			local w = CombatRules.weights(params, g.temper, g.nerve, boosted, true)
			if view.sneaking == true and view.dist <= params.threat and g.temper ~= "tough" then
				-- found right beside them (a stalk discovered late): they cry out and turn on it as a scene does, and stay on
				-- edge for the rest of the duel (g.alarmed)
				g.alarmed = true
				Duel.rally(params, g, now, CombatRules.rallyPick(params, g.temper, g.nerve, boosted, rand()))
			elseif
				rand()
				< (w.flee or 0) / math.max(1e-6, (w.flee or 0) + (w.back or 0) + (w.swing or 0) + (w.kick or 0))
			then
				apply(params, g, "flee", now)
			end
		elseif view.tell ~= nil and view.tell ~= g.lastTell and view.dist <= params.threat then
			-- the wind-up's hiss right behind them: one roll a tell and person (params.tellHeard) to turn at the last moment (alarmed,
			-- as above); else the pounce meets them unaware
			-- (the roll is the person's and the tell's own, not the dice's: the server lets an idle person's Guard go
			-- between its steps, and a tell is rolled for once however many steps its wind-up spans)
			if CombatRules.hash(`heard:{tostring(g.id)}:{view.tell}`) < params.tellHeard[g.temper] then
				-- (turned round by it, they cry out and turn on it as a scene does: Duel.rally)
				g.alarmed = true
				Duel.rally(params, g, now, CombatRules.rallyPick(params, g.temper, g.nerve, boosted, rand()))
			else
				g.lastTell = view.tell
				return out
			end
		else
			return out
		end
	elseif
		view.dist > far
		and g.phase ~= "windup"
		and g.phase ~= "flee"
		and not (g.phase == "startle" and g.running)
	then
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
			g.provoked = true -- (set on: a pounce, or a feint, at them)
			if view.tellFeint and rand() < params.readFeint[g.temper] then
				out.read = true
				startStrike(params, g, now, "kick", true)
			else
				-- (a vigilante is never caught unready: it squares up the moment it sees the rodent)
				local startled = g.temper ~= "tough" and now - g.awareAt < Duel.STARTLED_SECS
				local w = CombatRules.weights(params, g.temper, g.nerve, boosted, startled)
				g.pending = CombatRules.pick(w, rand())
				-- squared up, the arm may be up already; caught moving (backing off, flinching) or just noticing, it is not
				g.guarded = g.phase == "ready" and not startled and (rand() < params.guardUp[g.temper] or g.alarmed)
				g.running = g.phase == "flee"
				g.phase = "startle"
				g.reactAt = math.max(now, tell + params.react[g.temper])
			end
		end
	end

	-- the phases run out
	if g.phase == "startle" and now >= g.reactAt then
		local r: CombatRules.Response = g.pending or "back"
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
			boosted = boosted,
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
		-- (a blow at nothing, the rodent out of reach, leaves them overbalanced longer than one it dodged up close)
		g.untilT = now + (if inReach then params.recover[g.temper] else params.whiffRecover[g.temper])
		g.strike = nil
		g.counter = false
	elseif (g.phase == "flinch" or g.phase == "back" or g.phase == "recover") and now >= g.untilT then
		ready(g)
	elseif g.phase == "flee" then
		-- (the flight runs its course: the brain's run along the lane does, however far the rodent falls behind)
		if now - g.fleeFrom >= Duel.FLEE_SECS or (g.temper == "tough" and view.dist > far) then
			if g.temper == "tough" or view.dist <= params.engage then
				ready(g) -- (the rodent is still at their heels: they turn and face it)
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
	local charging = g.phase == "ready" and now < g.rallyUntil
	if g.rallyUntil > 0 and now >= g.rallyUntil then
		g.rallyUntil = 0
	end
	if g.phase == "ready" and inReach then
		local boost = if boosted then params.swingBias else 1
		-- (one who turned on the rodent strikes the moment it is in reach)
		local p = if charging
			then 1
			elseif g.inReach then params.strikeRate[g.temper] * boost * view.dt
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
	elseif g.phase == "ready" and (g.temper == "tough" or charging) and view.dist > params.kickReach * 0.9 then
		out.move, out.speed = "approach", params.approach
	else
		out.move = "stand"
	end
	out.stance = stanceOf(g)
	return out
end

function Duel.think(params: Params, g: Guard, view: View, rand: () -> number): Out
	local out = think(params, g, view, rand)
	record(g, view.now)
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

-- How a bite would meet this person as the rodent's player saw them `rewind` seconds ago (the link's round trip): the
-- phase at the think nearest then; the reaction window to the pounce whose tell is `tell` is the server's own (now).
function Duel.bitePhaseAt(g: Guard, now: number, rewind: number, tell: number?): CombatRules.BitePhase
	if rewind <= 0 then
		return Duel.bitePhase(g, now)
	end
	-- (the think nearest that moment; between two, the later: the duel steps a tenth at a time, and a rounding that
	-- always went back would give the rodent a whole step more than the link took)
	local at = now - rewind
	local found: Sample? = nil
	local best = math.huge
	for _, s in g.trail do
		local off = math.abs(s.t - at)
		if off <= best + 1e-6 then
			found, best = s, off
		end
	end
	if found == nil or (tell ~= nil and found.tell == tell) then
		return Duel.bitePhase(g, now)
	end
	return found.phase
end

-- The closest a body moving from (ax, az) to (bx, bz) came to (px, pz): a pounce at 31 studs/s moves three studs a
-- duel step, so contact is judged along the move, not at its end.
function Duel.sweep(ax: number, az: number, bx: number, bz: number, px: number, pz: number): number
	local dx, dz = bx - ax, bz - az
	local len2 = dx * dx + dz * dz
	local k = if len2 > 1e-9 then math.clamp(((px - ax) * dx + (pz - az) * dz) / len2, 0, 1) else 0
	local cx, cz = ax + dx * k, az + dz * k
	return math.sqrt((px - cx) ^ 2 + (pz - cz) ^ 2)
end

-- The scene turns on the rodent (a bite they saw, the rodent setting on their group): `mode` "attack" squares them up
-- and sends them at it, striking as soon as it is in reach, for params.rallySecs; "back" backs them off with an arm up
-- (they shout); "flee" runs. Whatever they were doing, they are aware of it now and not caught unready.
function Duel.rally(params: Params, g: Guard, now: number, mode: string)
	g.aware = true
	g.awareAt = now - Duel.STARTLED_SECS
	g.pending = nil
	if mode == "attack" then
		g.provoked = true
		if g.phase ~= "windup" then
			ready(g)
		end
		g.rallyUntil = now + params.rallySecs
	elseif mode == "flee" and g.temper ~= "tough" then
		apply(params, g, "flee", now)
	else
		g.phase = "back"
		g.untilT = now + params.backSecs
	end
end

-- A bite failed on this person ("Batted away"): they square up again unless a blow is on its way or they are running.
function Duel.batted(g: Guard, now: number)
	g.provoked = true
	if not g.aware or g.phase == "idle" then
		g.alarmed = true -- (it was on them before they knew: on edge from now on)
	end
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
