--!strict
-- ReplicatedStorage.Shared.Stealth.RafterWatch
-- The sneak rule of the alley's rafters (BRIEF_ADDENDUM D9: "the squirrel must practice sneaking through those
-- rafters or will be spotted"). People in the lane hall grow suspicious of a squirrel moving over them; creeping
-- (stalk held: Ctrl, C or L2) is all but safe, walking near people is seen in a second or two, running or landing
-- a leap on a beam is seen at once. Pure: the server's service (lane L5) gathers the squirrels on rafter routes and
-- the people in the hall, does the line-of-sight raycasts, steps this at a few hertz and acts on the events; the
-- client's eye meter (lane L6) shows `meter`.
--
-- Everything is in the alley's local frame (Shared/Attractions/AlleyLayout: X across, Y up from the floor, D down
-- the lane); the caller converts.
--
-- THE RULE. Each tick, for every squirrel on a rafter route (AlleyRoof.isRafter) that is not hidden (inside the
-- vent: Routes/Enclosure.hidden), every person in the hall (AlleyRoof.inHall, eye near floor height) who has a line
-- of sight to it (the caller's `canSee`, required) gives a rate of suspicion
--     rate = motion x light x range x view   (per second)
--   motion  still 0; creeping (stalk held, at most C.stalkSpeed) C.stalk; moving C.walk; sprinting or boosted, or
--           faster than C.sprintSpeed, C.sprint
--   light   1 within C.lampReach of a lamp (AlleyRoof.lamps), else C.dark; a lamp right under the squirrel (less
--           than C.lampShade across and C.lampSit below: it sits on the fixture) does not light it
--   range   1 up to C.near, falling straight to 0 at C.far
--   view    1 within C.viewHalfAngle of where the person faces (the angle in 3D, from the eye) and no more than
--           C.lookUp above their eye line, else C.behind: nobody stares straight up
-- A crowd adds only a little: the meter rises at the best person's rate plus C.crowdShare of everyone else's, at
-- most C.crowdCap times the best. A leap landing or catch on a rafter (squirrel.landed) adds C.land x light x range
-- x view at once, combined over the people the same way.
-- The meter (0..1) drops by C.decay per second while the combined rate is under C.quiet. At 1 the squirrel is
-- SPOTTED ("spotted" event, naming the person who saw most and the lane it is over). It stays SEEN (the meter held
-- at 1) while someone still sees it moving faster than a creep, and for C.forget seconds after the last such moment
-- or after it goes into the vent; then "lost": the meter drops to C.lostMeter and for C.calm seconds creeping or
-- keeping still adds nothing (the meter falls at C.decay), so a squirrel creeping on in view is not spotted again
-- at once; one that walks or runs in view is.
-- LINE OF SIGHT (the caller, lane L5): a ray from the person's eye to RafterWatch.aimPoint (the rail point raised by
-- half a body: a ray from below to the rail point itself meets the top face of the chord the squirrel stands on),
-- ignoring that chord's own part, bodies and parts that take no queries.
-- Interface: C; SITUATION, LINES (Speech/Lines "rafters"); new() -> State; rate(squirrel, observer, lamps) ->
--   number (one person, line of sight assumed); step(state, squirrels, observers, lamps?, dt, canSee) -> { Event };
--   meter(state, id) -> (number, boolean); laneOver(X) -> number?; aimPoint(squirrel) -> (X, Y, D)

local AlleyLayout = require("../Attractions/AlleyLayout")
local AlleyRoof = require("../Attractions/AlleyRoof")
local Lines = require("../Speech/Lines")

local RafterWatch = {}

RafterWatch.C = {
	stalk = 0.06, -- per second, creeping: a lit, near, facing person needs about 17 s
	walk = 0.8, -- 1.25 s
	sprint = 2.4, -- 0.42 s
	stalkSpeed = 3.2, -- studs/s: the rail stalk is 3 (Motion.C.railStalk)
	stillSpeed = 0.2,
	sprintSpeed = 24, -- between the rail walk (18) and sprint (30.5)
	land = 1.0, -- a landing on a beam, at once
	lampReach = 3,
	dark = 0.45,
	near = 20,
	far = 70,
	lampShade = 0.8, -- a lamp less than this across under the squirrel ...
	lampSit = 1.0, -- ... and less than this below it is the fixture it sits on: it does not light it
	viewHalfAngle = math.rad(70),
	lookUp = math.rad(60), -- more than this above a person's eye line counts as behind
	behind = 0.35,
	crowdShare = 0.25, -- each other person adds this share of their own rate ...
	crowdCap = 1.5, -- ... and a crowd at most this many times the best person's
	quiet = 0.02,
	decay = 0.12,
	forget = 8,
	lostMeter = 0.5, -- the meter on "lost"
	calm = 10, -- seconds after "lost" in which creeping or keeping still adds nothing
	bodyHalf = 0.85, -- the aim point over the rail (half the 1.7 body)
	eyeY0 = -2, -- a person's eye between these heights above the hall floor counts (people on the floor)
	eyeY1 = 8,
}
local C = RafterWatch.C

-- What people in the hall say when they notice: Speech/Lines' situation "rafters" (SpeechRules paces them).
RafterWatch.SITUATION = "rafters"
RafterWatch.LINES = Lines.of("rafters")

export type Squirrel = {
	id: string,
	routeId: number?, -- the rail it is on (only rafter routes count)
	X: number,
	Y: number,
	D: number,
	speed: number, -- studs per second along the rail
	focus: boolean, -- stalk held
	sprint: boolean, -- sprinting or boosted
	landed: boolean?, -- a leap landing or catch on a rafter this tick
	hidden: boolean?, -- inside the vent (Routes/Enclosure.hidden)
}

export type Observer = {
	id: string,
	X: number,
	Y: number, -- eye height
	D: number,
	faceX: number, -- facing direction in the floor plane (need not be unit)
	faceD: number,
}

export type Track = { meter: number, seen: boolean, forget: number, calm: number }
export type State = { tracks: { [string]: Track }, clock: number }

export type Event = {
	kind: string, -- "spotted" | "lost"
	squirrel: string,
	observer: string?, -- who saw most ("spotted")
	lane: number?, -- the lane it is over, when over one
	X: number?,
	D: number?,
}

function RafterWatch.new(): State
	return { tracks = {}, clock = 0 }
end

local function motion(s: Squirrel): number
	if s.speed < C.stillSpeed then
		return 0
	elseif s.sprint or s.speed > C.sprintSpeed then
		return C.sprint
	elseif s.focus and s.speed <= C.stalkSpeed then
		return C.stalk
	end
	return C.walk
end

local function light(s: Squirrel, lamps: { { number } }): number
	local r2 = C.lampReach * C.lampReach
	for _, l in lamps do
		local dx, dy, dd = l[1] - s.X, l[2] - s.Y, l[3] - s.D
		if dx * dx + dy * dy + dd * dd <= r2 then
			local under = dy < 0 and -dy < C.lampSit and dx * dx + dd * dd < C.lampShade * C.lampShade
			if not under then
				return 1
			end
		end
	end
	return C.dark
end

-- The part of a person's attention a squirrel at this place gets (light x range x view), before its motion.
local function exposure(s: Squirrel, o: Observer, lit: number): number
	local dx, dy, dd = s.X - o.X, s.Y - o.Y, s.D - o.D
	local dist = math.sqrt(dx * dx + dy * dy + dd * dd)
	local range = if dist <= C.near then 1 elseif dist >= C.far then 0 else (C.far - dist) / (C.far - C.near)
	if range <= 0 then
		return 0
	end
	local view = C.behind
	local fl = math.sqrt(o.faceX * o.faceX + o.faceD * o.faceD)
	local hl = math.sqrt(dx * dx + dd * dd)
	if fl > 0 and dist > 0 then
		-- the angle in 3D from the eye: a beam overhead ahead of a person is in view, one straight over them is not
		local cos = (dx * o.faceX + dd * o.faceD) / (dist * fl)
		if cos >= math.cos(C.viewHalfAngle) and math.atan2(dy, hl) <= C.lookUp then
			view = 1
		end
	end
	return lit * range * view
end

local function counts(s: Squirrel): boolean
	return AlleyRoof.isRafter(s.routeId) and s.hidden ~= true
end

local function watching(o: Observer): boolean
	return AlleyRoof.inHall(o.X, o.D) and o.Y >= C.eyeY0 and o.Y <= C.eyeY1
end

-- rate(squirrel, observer, lamps): suspicion per second this one person gives (line of sight assumed).
function RafterWatch.rate(s: Squirrel, o: Observer, lamps: { { number } }?): number
	if not counts(s) or not watching(o) then
		return 0
	end
	return motion(s) * exposure(s, o, light(s, lamps or AlleyRoof.lamps()))
end

-- The lane a point is over (the beds and their gutters), or nil over the aisles.
function RafterWatch.laneOver(X: number): number?
	local half = AlleyLayout.PITCH / 2
	for i = 1, AlleyLayout.LANES do
		if math.abs(X - AlleyLayout.laneX(i)) <= half then
			return i
		end
	end
	return nil
end

-- aimPoint(squirrel): where a line-of-sight ray should aim (the body, not the rail under its feet).
function RafterWatch.aimPoint(s: Squirrel): (number, number, number)
	return s.X, s.Y + C.bodyHalf, s.D
end

-- A crowd: the best person's share plus a part of everyone else's, capped.
local function crowd(sum: number, best: number): number
	return math.min(best + C.crowdShare * (sum - best), C.crowdCap * best)
end

function RafterWatch.meter(state: State, id: string): (number, boolean)
	local tr = state.tracks[id]
	if not tr then
		return 0, false
	end
	return tr.meter, tr.seen
end

-- step(state, squirrels, observers, lamps?, dt, canSee): one tick. Squirrels not in the list are forgotten.
function RafterWatch.step(
	state: State,
	squirrels: { Squirrel },
	observers: { Observer },
	lamps: { { number } }?,
	dt: number,
	canSee: (o: Observer, s: Squirrel) -> boolean
): { Event }
	if type(canSee) ~= "function" then
		error("RafterWatch.step: canSee (the line of sight from a person to the squirrel) is required")
	end
	local events: { Event } = {}
	local lampList = lamps or AlleyRoof.lamps()
	state.clock += dt
	local present: { [string]: boolean } = {}
	for _, s in squirrels do
		present[s.id] = true
		local tr = state.tracks[s.id]
		if not tr then
			tr = { meter = 0, seen = false, forget = 0, calm = 0 }
			state.tracks[s.id] = tr
		end
		local m = motion(s)
		local sum, best, bestAdd, bestId = 0, 0, 0, nil :: string?
		local impulseSum, impulseBest = 0, 0
		local inSight = false
		if counts(s) then
			local lit = light(s, lampList)
			for _, o in observers do
				if not watching(o) or not canSee(o, s) then
					continue
				end
				local e = exposure(s, o, lit)
				if e <= 0 then
					continue
				end
				inSight = true
				local r = m * e
				local imp = if s.landed then C.land * e else 0
				sum += r
				best = math.max(best, r)
				impulseSum += imp
				impulseBest = math.max(impulseBest, imp)
				if r * dt + imp > bestAdd then
					bestAdd, bestId = r * dt + imp, o.id
				end
			end
		end
		local total = if best > 0 then crowd(sum, best) else 0
		local impulse = if impulseBest > 0 then crowd(impulseSum, impulseBest) else 0
		if tr.calm > 0 then
			-- just lost: creeping or keeping still adds nothing for a while
			tr.calm = math.max(0, tr.calm - dt)
			if m <= C.stalk then
				total, impulse = 0, 0
			end
		end
		if tr.seen then
			-- held while someone still sees it moving faster than a creep
			if inSight and m > C.stalk then
				tr.forget = C.forget
			else
				tr.forget -= dt
			end
			if tr.forget <= 0 then
				tr.seen = false
				tr.meter = C.lostMeter
				tr.calm = C.calm
				table.insert(events, { kind = "lost", squirrel = s.id })
			end
		else
			if total < C.quiet and impulse == 0 then
				tr.meter = math.max(0, tr.meter - C.decay * dt)
			else
				tr.meter = math.min(1, tr.meter + total * dt + impulse)
			end
			if tr.meter >= 1 then
				tr.seen = true
				tr.forget = C.forget
				table.insert(events, {
					kind = "spotted",
					squirrel = s.id,
					observer = bestId,
					lane = RafterWatch.laneOver(s.X),
					X = s.X,
					D = s.D,
				})
			end
		end
		if tr.seen then
			tr.meter = 1
		end
	end
	for id, tr in state.tracks do
		if not present[id] then
			-- gone from the rafters' list (left the hall, died): a seen one is lost now
			if tr.seen then
				table.insert(events, { kind = "lost", squirrel = id })
			end
			state.tracks[id] = nil
		end
	end
	return events
end

return RafterWatch
