--!strict
-- tests/lib/DuelSim: a duel between the Spicy Rodent and one person on open ground, the person run by the game's own
-- Combat/Duel on Combat/CombatRules' numbers (the server runs the same Guard), the rodent by a script:
--   "sprinter": runs straight at the person at a sprint and pounces from 9 studs, again and again (unskilled);
--   "skilled":  reads the person with a human player's reaction time (0.16 to 0.28 s); goes straight in at anyone not
--               squared up like a vigilante (the stance is visible) and chases a runner down at a sprint; against a
--               vigilante zig-zags in to just outside the reach, backs out of a wind-up, pounces into a flinch or a
--               recovery, feints (when the feint meter allows) or dips into reach to draw a blow.
-- The rodent's body as the squirrel motor moves it: sprint 33 studs/s on a 4 s meter that refills in 9 s (a winded
-- rodent walks at 18), the pounce 31 studs/s for the 0.78 s window after a 0.12 s wind-up, 0.25 of the meter, a 0.7 s
-- cooldown and a 0.35 s recovery; a bite lands at 3.5 studs by Duel.bitePhase and CombatRules.biteChance. A blow that
-- lands costs CombatRules.damage, knocks the rodent 6 studs back and gives it rodent.iFrames. The person moves as the
-- Guard says (closing in, stepping in, backing off, fleeing at 19 studs/s).
-- A duel ends with a bite (the rodent wins), a knock-out, a person who got away (40 studs off, or still running after
-- 6 s: a door, in a town of houses), or 45 s with no bite (the rodent loses).
-- Interface: run(opts) -> Result; batch(n, opts) -> Summary
local CombatRules = require("@shared/Combat/CombatRules")
local Duel = require("@shared/Combat/Duel")
local Rng = require("@shared/Util/Rng")

local DuelSim = {}

DuelSim.DT = 1 / 30
DuelSim.LIMIT = 45
DuelSim.SPRINT = 33
DuelSim.WALK = 18
DuelSim.POUNCE = 31
DuelSim.FLEE = 19
DuelSim.SPRINT_SECS = 4
DuelSim.REFILL_SECS = 9
DuelSim.POUNCE_COST = 0.25
DuelSim.RECOVER = 0.35 -- winded until this much of the meter is back (SquirrelMotor sprintRecover)
DuelSim.KNOCK = 6
DuelSim.ESCAPE = 40 -- studs: a person running from the rodent this far off has got away
DuelSim.SAFE_SECS = 6 -- seconds: a person who keeps running this long reaches a door (the town's houses) and is safe

export type Options = {
	temper: CombatRules.Temper,
	rodent: string, -- "sprinter" | "skilled"
	seed: number,
	boosted: boolean?, -- near a fresh bite
	params: CombatRules.Params?,
	trace: ((now: number, dist: number, phase: string, meter: number, flying: boolean) -> ())?,
}

export type Result = {
	win: boolean,
	cause: string, -- bite | knockout | escaped | time
	secs: number,
	pounces: number,
	feints: number,
	hitsTaken: number,
	strikes: number,
	health: number,
	landedOn: string?, -- the person's phase when the bite landed
}

export type Summary = {
	n: number,
	wins: number,
	rate: number,
	knockouts: number,
	escapes: number,
	timeouts: number,
	meanSecs: number,
	pounces: number, -- mean per duel
	feints: number,
	hitsTaken: number,
	landedOn: { [string]: number }, -- wins by the person's phase at the bite
}

function DuelSim.run(opts: Options): Result
	local P = opts.params or CombatRules.params()
	local rng = Rng.new(opts.seed)
	local rand = function(): number
		return rng.next()
	end
	local temper = opts.temper
	local g = Duel.new(P, opts.seed, temper, CombatRules.nerve(P, opts.seed, temper))
	local boosted = opts.boosted == true
	local dt = DuelSim.DT
	-- the person at the origin; the rodent comes in from 30 studs at a random bearing
	local hx, hz = 0, 0
	local a0 = rand() * math.pi * 2
	local rx, rz = math.cos(a0) * 30, math.sin(a0) * 30
	local health = P.maxHealth
	local meter = 1 -- sprint
	local winded = false
	local feintMeter = 1
	local now = 0
	local tell: number? = nil
	local tellFeint = false
	local commitAt: number? = nil -- a pounce wound up, commits then
	local windowUntil = -1
	local flying = false
	local pvx, pvz = 0, 0
	local recoverUntil = -1
	local cooldownUntil = -1
	local feintUntil = -1
	local iUntil = -1
	local pounces, feints, hitsTaken = 0, 0, 0
	local history: { CombatRules.Sample } = {}
	local sampleAcc = 0
	-- the rodent's eyes: the person's phase as it was a reaction time ago
	local reaction = 0.16 + rand() * 0.12
	local toughLook = temper == "tough"
	local seen: { { t: number, phase: string } } = {}
	local weave = 1
	local weaveAt = 0
	local hoverSince: number? = nil
	local dipUntil = -1

	local function observed(): string
		local want = now - reaction
		local ph = "idle"
		for _, s in seen do
			if s.t <= want then
				ph = s.phase
			else
				break
			end
		end
		return ph
	end

	local function startPounce()
		tell = now
		tellFeint = false
		commitAt = now + P.pounceWindup
		cooldownUntil = now + P.pounceWindup + P.pounceCooldown
		pounces += 1
	end

	local function startFeint()
		tell = now
		tellFeint = true
		feintMeter -= P.feintCost
		feintUntil = now + P.feintRecover
		feints += 1
	end

	local function canPounce(): boolean
		return commitAt == nil and not flying and now >= recoverUntil and now >= cooldownUntil and now >= feintUntil
	end

	while now < DuelSim.LIMIT do
		now += dt
		local dx, dz = hx - rx, hz - rz
		local d = math.sqrt(dx * dx + dz * dz)
		local ux, uz = dx / math.max(d, 1e-6), dz / math.max(d, 1e-6) -- rodent -> person
		if flying and now >= windowUntil then
			-- the window ran out with no contact: the rodent recovers
			flying = false
			recoverUntil = now + P.pounceRecovery
		end
		local inPounce = flying
		local recovering = now < recoverUntil

		-- the rodent decides (a pounce in flight or being wound up is committed)
		local vx, vz = 0, 0
		local sprinting = false
		if commitAt and now >= commitAt then
			commitAt = nil
			windowUntil = now + P.pounceWindow
			local sp = if winded then DuelSim.WALK else DuelSim.POUNCE
			pvx, pvz = ux * sp, uz * sp
			meter = math.max(0, meter - DuelSim.POUNCE_COST)
			if meter == 0 then
				winded = true -- (as the motor: a pounce that empties the meter winds the rodent)
			end
			inPounce = true
			flying = true
		end
		if inPounce then
			vx, vz = pvx, pvz
		elseif recovering then
			vx, vz = 0, 0
		elseif opts.rodent == "sprinter" then
			sprinting = true
			vx, vz = ux, uz
			if d <= 9 and canPounce() then
				startPounce()
			end
		else
			local ph = observed()
			local hover = P.kickReach + 2.2
			local tx, tz = 0, 0 -- the wanted direction (unit-ish), then the weave across it
			local weaving = true
			if now >= weaveAt then
				weave = -weave
				weaveAt = now + 0.25 + rand() * 0.15
			end
			-- (the vigilante's stance is visible: a person not squared up like one is taken head on)
			local soft = ph == "ready" and not toughLook
			if
				soft
				or ph == "idle"
				or ph == "flee"
				or ph == "back"
				or ph == "flinch"
				or ph == "startle"
				or ph == "recover"
			then
				-- not squared up (unaware, running, backing off, caught in a reaction): straight in
				tx, tz = ux, uz
				sprinting = ph == "flee" or d > 6
				weaving = ph ~= "flee" and d > 12
				if d <= 11 and canPounce() then
					startPounce()
				end
				hoverSince = nil
			elseif ph == "windup" then
				tx, tz = -ux, -uz -- out of reach
				sprinting = true
				hoverSince = nil
			elseif d > hover + 4 then
				tx, tz = ux, uz
				sprinting = d > hover + 8
				hoverSince = nil
			elseif now < dipUntil then
				tx, tz = ux, uz -- dipping into reach to draw a blow
				weaving = false
			else
				-- hovering just outside the reach, weaving; after a moment a feint, or a dip in
				local k = math.clamp((d - hover) / 2, -1, 1)
				tx, tz = ux * k, uz * k
				hoverSince = hoverSince or now
				if now - (hoverSince :: number) > 0.6 and canPounce() then
					hoverSince = now
					if feintMeter >= P.feintCost then
						startFeint()
					else
						dipUntil = now + 0.15
					end
				end
			end
			-- the weave: across the line to the person
			local lx, lz = -uz * weave, ux * weave
			local speed = if sprinting then DuelSim.SPRINT else DuelSim.WALK
			if weaving then
				vx, vz = tx * 0.55 + lx * 0.83, tz * 0.55 + lz * 0.83
			else
				vx, vz = tx, tz
			end
			local m = math.sqrt(vx * vx + vz * vz)
			if m > 1e-6 then
				vx, vz = vx / m * speed, vz / m * speed
			end
		end
		if opts.rodent == "sprinter" and not inPounce and not recovering then
			local speed = if winded then DuelSim.WALK else DuelSim.SPRINT
			vx, vz = vx * speed, vz * speed
		end
		-- the sprint meter
		if sprinting and not inPounce and not winded then
			meter -= dt / DuelSim.SPRINT_SECS
			if meter <= 0 then
				meter = 0
				winded = true
			end
		else
			meter = math.min(1, meter + dt / DuelSim.REFILL_SECS)
			if winded and meter >= DuelSim.RECOVER then
				winded = false
			end
		end
		if winded and not inPounce then
			local m = math.sqrt(vx * vx + vz * vz)
			if m > DuelSim.WALK then
				vx, vz = vx / m * DuelSim.WALK, vz / m * DuelSim.WALK
			end
		end
		feintMeter = math.min(1, feintMeter + P.feintRefill * dt)
		rx += vx * dt
		rz += vz * dt
		sampleAcc += dt
		if sampleAcc >= 0.1 then
			sampleAcc = 0
			table.insert(history, { t = now, x = rx, z = rz })
			if #history > 30 then
				table.remove(history, 1)
			end
		end

		-- the person
		dx, dz = hx - rx, hz - rz
		d = math.sqrt(dx * dx + dz * dz)
		local view: Duel.View = {
			now = now,
			dt = dt,
			dist = d,
			dy = 0,
			seen = Duel.notices(P, g, d, true),
			tell = tell,
			tellFeint = tellFeint,
			committed = inPounce,
			recovering = recovering,
			zigzag = CombatRules.zigzag(P, history, dx, dz, now),
			boosted = boosted,
		}
		local out = Duel.think(P, g, view, rand)
		if opts.trace then
			opts.trace(now, d, g.phase, meter, flying)
		end
		local running = g.phase == "flee" or (g.phase == "startle" and g.running)
		if running and (d > DuelSim.ESCAPE or now - g.fleeFrom >= DuelSim.SAFE_SECS) then
			-- got away: the rodent lost this one
			return {
				win = false,
				cause = "escaped",
				secs = now,
				pounces = pounces,
				feints = feints,
				hitsTaken = hitsTaken,
				strikes = g.strikes,
				health = health,
			}
		end
		table.insert(seen, { t = now, phase = g.phase })
		if #seen > 40 then
			table.remove(seen, 1)
		end
		local awayX, awayZ = dx / math.max(d, 1e-6), dz / math.max(d, 1e-6) -- away from the rodent
		if out.move == "flee" then
			hx += awayX * DuelSim.FLEE * dt
			hz += awayZ * DuelSim.FLEE * dt
		elseif out.move == "back" then
			hx += awayX * out.speed * dt
			hz += awayZ * out.speed * dt
		elseif out.move == "approach" and d > 2 then
			hx -= awayX * out.speed * dt
			hz -= awayZ * out.speed * dt
		end
		if out.strike and out.strike.hit and now >= iUntil then
			health, _ = CombatRules.applyDamage(health, CombatRules.damage(P, out.strike.kind, boosted))
			hitsTaken += 1
			iUntil = now + P.iFrames
			-- knocked back; a pounce is spent
			rx += -awayX * DuelSim.KNOCK
			rz += -awayZ * DuelSim.KNOCK
			windowUntil = math.min(windowUntil, now)
			flying = false
			commitAt = nil
			recoverUntil = now + P.pounceRecovery
			if health <= 0 then
				return {
					win = false,
					cause = "knockout",
					secs = now,
					pounces = pounces,
					feints = feints,
					hitsTaken = hitsTaken,
					strikes = g.strikes,
					health = 0,
				}
			end
		end

		-- the bite: contact inside the pounce's window
		dx, dz = hx - rx, hz - rz
		d = math.sqrt(dx * dx + dz * dz)
		if flying and d <= P.contact then
			local chance = CombatRules.biteChance(P, temper, Duel.bitePhase(g, now), boosted)
			windowUntil = now
			flying = false
			recoverUntil = now + P.pounceRecovery
			if rand() < chance then
				return {
					win = true,
					cause = "bite",
					landedOn = g.phase,
					secs = now,
					pounces = pounces,
					feints = feints,
					hitsTaken = hitsTaken,
					strikes = g.strikes,
					health = health,
				}
			end
			Duel.batted(g, now)
			-- batted away: bounced back
			rx -= ux * 3
			rz -= uz * 3
		end
	end
	return {
		win = false,
		cause = "time",
		secs = now,
		pounces = pounces,
		feints = feints,
		hitsTaken = hitsTaken,
		strikes = g.strikes,
		health = health,
	}
end

function DuelSim.batch(n: number, opts: Options): Summary
	local s: Summary = {
		n = n,
		wins = 0,
		rate = 0,
		knockouts = 0,
		escapes = 0,
		timeouts = 0,
		meanSecs = 0,
		pounces = 0,
		feints = 0,
		hitsTaken = 0,
		landedOn = {},
	}
	for i = 1, n do
		local o = table.clone(opts)
		o.seed = opts.seed * 1000 + i
		local r = DuelSim.run(o)
		if r.win then
			s.wins += 1
			local k = r.landedOn or "?"
			s.landedOn[k] = (s.landedOn[k] or 0) + 1
		elseif r.cause == "knockout" then
			s.knockouts += 1
		elseif r.cause == "escaped" then
			s.escapes += 1
		else
			s.timeouts += 1
		end
		s.meanSecs += r.secs / n
		s.pounces += r.pounces / n
		s.feints += r.feints / n
		s.hitsTaken += r.hitsTaken / n
	end
	s.rate = s.wins / n
	return s
end

return DuelSim
