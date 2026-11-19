--!strict
-- tests/lib/DuelSim: a duel between the Spicy Rodent and one person on open ground, the person run by the game's own
-- Combat/Duel on Combat/CombatRules' numbers (the server runs the same Guard), the rodent by a script:
--   "sprinter": runs straight at the person at a sprint and pounces from 9 studs, again and again (unskilled);
--   "skilled":  reads the person with a human player's reaction time (0.16 to 0.28 s); goes straight in at anyone not
--               squared up like a vigilante (the stance is visible) and chases a runner down at a sprint; against a
--               vigilante zig-zags in to just outside the reach, backs out of a wind-up, pounces into a flinch or a
--               recovery, feints (when the feint meter allows) or dips into reach to draw a blow. On the click it
--               steers straight at the person through the wind-up (the motor pounces along the body's heading).
-- THE SERVER, as Server/Combat/CombatService runs it: the person thinks ten times a second (the duel's step), a blow is
-- judged against where the server has the rodent then, and a bite is contact along the rodent's move since the last
-- step inside the pounce's window (pounce.window + duel.rewind after the wind-up), judged by Duel.bitePhaseAt against
-- the person as the rodent's player saw them (the link's round trip, up to duel.lagMax back).
-- THE LINK (opts.lag, the round trip in seconds): the sim keeps the server's clock. The rodent's player sees the person
-- half a round trip late, and what it does reaches the server half a round trip later: so the script decides on the
-- person as they were `lag` ago (their stance `lag` + its reaction time ago), and acts at once.
-- THE RODENT'S BODY as the squirrel motor moves it: sprint 33 studs/s on a 4 s meter that refills in 9 s (a winded rodent
-- walks at 18), turning at the motor's 13/s toward where it is going; the pounce 31 studs/s along the body's heading for
-- the window after a 0.12 s wind-up, 0.25 of the meter, a 0.7 s cooldown and a 0.35 s recovery. A blow that lands costs
-- CombatRules.damage, knocks the rodent 6 studs back and gives it rodent.iFrames.
-- THE PERSON moves as the Guard says (closing in, stepping in, backing off, fleeing at 19 studs/s for Duel.FLEE_SECS,
-- the brain's run). There is no door to reach: a duel ends with a bite (the rodent wins), a knock-out, the person out
-- of sight (LOST studs off), or LIMIT seconds with no bite (the rodent loses).
-- Interface: run(opts) -> Result; batch(n, opts) -> Summary
local CombatRules = require("@shared/Combat/CombatRules")
local Duel = require("@shared/Combat/Duel")
local Rng = require("@shared/Util/Rng")

local DuelSim = {}

DuelSim.DT = 1 / 30
DuelSim.SERVER_DT = 0.1 -- the duel's step (Boot/Game)
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
DuelSim.TURN = 13 -- the body's turn rate (SquirrelMotor turnRate)
DuelSim.HOVER = 1.5 -- studs: a skilled rodent hovers this far outside a kick's reach (with the step-in)
DuelSim.LOST = 80 -- studs: a person this far off is out of the rodent's sight

export type Options = {
	temper: CombatRules.Temper,
	rodent: string, -- "sprinter" | "skilled"
	seed: number,
	lag: number?, -- the link's round trip, seconds (default 0)
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

type Seen = { t: number, phase: string, x: number, z: number }

function DuelSim.run(opts: Options): Result
	local P = opts.params or CombatRules.params()
	local rng = Rng.new(opts.seed)
	local rand = function(): number
		return rng.next()
	end
	local temper = opts.temper
	local g = Duel.new(P, opts.seed, temper, CombatRules.nerve(P, opts.seed, temper))
	local boosted = opts.boosted == true
	local lag = opts.lag or 0
	local rewind = math.clamp(lag, 0, P.lagMax)
	local dt = DuelSim.DT
	-- the person at the origin; the rodent comes in from 30 studs at a random bearing, facing them
	local hx, hz = 0, 0
	local a0 = rand() * math.pi * 2
	local rx, rz = math.cos(a0) * 30, math.sin(a0) * 30
	local yaw = math.atan2(-rx, -rz)
	local health = P.maxHealth
	local meter = 1 -- sprint
	local winded = false
	local feintMeter = 1
	local now = 0
	local tell: number? = nil
	local tellFeint = false
	local commitAt: number? = nil -- a pounce wound up, commits then
	local windowUntil = -1 -- the motor's lunge
	local serverUntil = -1 -- the server's window for the bite (the pounce's, widened by duel.rewind)
	local landed = true
	local flying = false
	local pvx, pvz = 0, 0
	local recoverUntil = -1
	local cooldownUntil = -1
	local feintUntil = -1
	local iUntil = -1
	local pounces, feints, hitsTaken = 0, 0, 0
	local history: { CombatRules.Sample } = {}
	local reaction = 0.16 + rand() * 0.12
	local toughLook = temper == "tough"
	local seen: { Seen } = {}
	local weave = 1
	local weaveAt = 0
	local hoverSince: number? = nil
	local dipUntil = -1
	-- the server's step and what it last told the person's body to do
	local serverAcc = DuelSim.SERVER_DT
	local lastX, lastZ = rx, rz
	local move, moveSpeed = "none", 0

	-- what the rodent's player sees: the person `lag` ago (the stance a reaction time before that)
	local function observed(): (string, number, number)
		local wantPhase = now - lag - reaction
		local wantPos = now - lag
		local ph, ox, oz = "idle", hx, hz
		local havePos = false
		for _, s in seen do
			if s.t <= wantPhase then
				ph = s.phase
			end
			if s.t <= wantPos then
				ox, oz = s.x, s.z
				havePos = true
			else
				break
			end
		end
		if not havePos and #seen > 0 then
			ox, oz = seen[1].x, seen[1].z
		end
		return ph, ox, oz
	end

	local function startPounce()
		tell = now
		tellFeint = false
		commitAt = now + P.pounceWindup
		cooldownUntil = now + P.pounceWindup + P.pounceCooldown
		serverUntil = now + P.pounceWindup + P.pounceWindow + P.rewind
		landed = false
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

	local function result(win: boolean, cause: string, landedOn: string?): Result
		return {
			win = win,
			cause = cause,
			secs = now,
			pounces = pounces,
			feints = feints,
			hitsTaken = hitsTaken,
			strikes = g.strikes,
			health = health,
			landedOn = landedOn,
		}
	end

	while now < DuelSim.LIMIT do
		now += dt
		if flying and now >= windowUntil then
			-- the lunge ran out: the rodent recovers
			flying = false
			recoverUntil = now + P.pounceRecovery
		end
		local recovering = now < recoverUntil

		-- the rodent decides, on the person as its player sees them
		local ph, ox, oz = observed()
		local dx, dz = ox - rx, oz - rz
		local d = math.sqrt(dx * dx + dz * dz)
		local ux, uz = dx / math.max(d, 1e-6), dz / math.max(d, 1e-6) -- rodent -> person (as seen)
		local vx, vz = 0, 0
		local sprinting = false
		if commitAt and now >= commitAt then
			-- the motor's pounce: along the body's heading
			commitAt = nil
			windowUntil = now + P.pounceWindow
			local sp = if winded then DuelSim.WALK else DuelSim.POUNCE
			pvx, pvz = math.sin(yaw) * sp, math.cos(yaw) * sp
			meter = math.max(0, meter - DuelSim.POUNCE_COST)
			if meter == 0 then
				winded = true -- (as the motor: a pounce that empties the meter winds the rodent)
			end
			flying = true
		end
		if flying then
			vx, vz = pvx, pvz
		elseif recovering then
			vx, vz = 0, 0
		elseif commitAt then
			-- the wind-up: steering straight at the person
			vx, vz = ux, uz
			sprinting = d > 6
		elseif opts.rodent == "sprinter" then
			sprinting = true
			vx, vz = ux, uz
			if d <= 9 and canPounce() then
				startPounce()
			end
		else
			-- (just outside where a kick reaches with the step-in: a skilled player learns the reach)
			local hover = P.kickReach + P.stepIn[temper] * P.windup[temper] + DuelSim.HOVER
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
		if (opts.rodent == "sprinter" or commitAt) and not flying and not recovering then
			local speed = if winded then DuelSim.WALK elseif sprinting then DuelSim.SPRINT else DuelSim.WALK
			vx, vz = vx * speed, vz * speed
		end
		-- the sprint meter
		if sprinting and not flying and not winded then
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
		if winded and not flying then
			local m = math.sqrt(vx * vx + vz * vz)
			if m > DuelSim.WALK then
				vx, vz = vx / m * DuelSim.WALK, vz / m * DuelSim.WALK
			end
		end
		-- the body turns toward where it goes (not in the air)
		if not flying and vx * vx + vz * vz > 1 then
			local want = math.atan2(vx, vz)
			local diff = (want - yaw + math.pi) % (2 * math.pi) - math.pi
			yaw += diff * (1 - math.exp(-DuelSim.TURN * dt))
		end
		feintMeter = math.min(1, feintMeter + P.feintRefill * dt)
		rx += vx * dt
		rz += vz * dt

		-- the person's body follows the server's last order
		dx, dz = hx - rx, hz - rz
		d = math.sqrt(dx * dx + dz * dz)
		local awayX, awayZ = dx / math.max(d, 1e-6), dz / math.max(d, 1e-6) -- away from the rodent
		if move == "flee" then
			hx += awayX * DuelSim.FLEE * dt
			hz += awayZ * DuelSim.FLEE * dt
		elseif move == "back" then
			hx += awayX * moveSpeed * dt
			hz += awayZ * moveSpeed * dt
		elseif move == "approach" and d > 2 then
			hx -= awayX * moveSpeed * dt
			hz -= awayZ * moveSpeed * dt
		end

		-- the server's step: the person thinks, a blow is judged, then the bite
		serverAcc += dt
		if serverAcc >= DuelSim.SERVER_DT - 1e-9 then
			serverAcc -= DuelSim.SERVER_DT
			dx, dz = hx - rx, hz - rz
			d = math.sqrt(dx * dx + dz * dz)
			awayX, awayZ = dx / math.max(d, 1e-6), dz / math.max(d, 1e-6)
			table.insert(history, { t = now, x = rx, z = rz })
			if #history > 30 then
				table.remove(history, 1)
			end
			local view: Duel.View = {
				now = now,
				dt = DuelSim.SERVER_DT,
				dist = d,
				dy = 0,
				seen = Duel.notices(P, g, d, true),
				tell = tell,
				tellFeint = tellFeint,
				committed = flying,
				recovering = now < recoverUntil,
				zigzag = CombatRules.zigzag(P, history, dx, dz, now),
				boosted = boosted,
			}
			local out = Duel.think(P, g, view, rand)
			move, moveSpeed = out.move, out.speed
			if opts.trace then
				opts.trace(now, d, g.phase, meter, flying)
			end
			if d > DuelSim.LOST then
				return result(false, "escaped")
			end
			if out.strike and out.strike.hit and now >= iUntil then
				health, _ = CombatRules.applyDamage(health, CombatRules.damage(P, out.strike.kind, boosted))
				hitsTaken += 1
				iUntil = now + P.iFrames
				-- knocked back; a pounce is spent
				rx += -awayX * DuelSim.KNOCK
				rz += -awayZ * DuelSim.KNOCK
				lastX, lastZ = rx, rz
				windowUntil = math.min(windowUntil, now)
				flying = false
				commitAt = nil
				landed = true
				recoverUntil = now + P.pounceRecovery
				if health <= 0 then
					return result(false, "knockout")
				end
			end
			-- the bite: contact along the move since the last step, inside the server's window, the lunge launched
			if not landed and now >= serverUntil then
				landed = true
			end
			if not landed and commitAt == nil then
				local cd = Duel.sweep(lastX, lastZ, rx, rz, hx, hz)
				if cd <= P.contact then
					local chance = CombatRules.biteChance(P, temper, Duel.bitePhaseAt(g, now, rewind, tell), boosted)
					landed = true
					windowUntil = math.min(windowUntil, now)
					flying = false
					recoverUntil = now + P.pounceRecovery
					if rand() < chance then
						return result(true, "bite", g.phase)
					end
					Duel.batted(g, now)
					-- batted away: bounced back
					rx -= awayX * 3
					rz -= awayZ * 3
				end
			end
			lastX, lastZ = rx, rz
			table.insert(seen, { t = now, phase = g.phase, x = hx, z = hz })
			if #seen > 20 then
				table.remove(seen, 1)
			end
		end
	end
	return result(false, "time")
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
