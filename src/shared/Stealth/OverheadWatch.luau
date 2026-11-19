--!strict
-- ReplicatedStorage.Shared.Stealth.OverheadWatch
-- People in town notice a squirrel stalking above them (owner playtest 2026-11-19: "i would like ... awareness and
-- discussion and chatter, if i (spicy rodent) am prowling and stalking from above on a powerline or branch etc."). The
-- alley's rafters have their own watch (Stealth/RafterWatch: one meter a squirrel, the hall's lamps and raycasts); this
-- is the same idea for the town's above-ground routes (wires, fences, branches, roof edges, bridges), with a meter for
-- each PERSON, because a street is many people each seeing it or not, and their reactions come in stages.
-- Pure: Server/Stealth/OverheadService gathers the squirrels overhead and the people near them (the spatial grid),
-- works out each person's best `rate` and `exposure`, steps this at a few hertz and acts on the events.
--
-- THE RATE. For one person and one squirrel overhead (the caller says it is on an above-ground route, or in the air
-- off one, and nothing solid is between them):
--     rate = motion x range x view x over x cover   (per second)
--   motion  still 0; creeping (no faster than C.stalkSpeed: the rail stalk is 3, the ground stalk 4.1) C.stalk;
--           moving C.walk; sprinting (or faster than C.sprintSpeed) C.sprint
--   range   1 within C.near studs (eye to squirrel), falling straight to 0 at C.far
--   view    1 inside the person's view cone (C.viewHalfAngle either side of where they face, the v5.4 cone) and no more
--           than C.lookUp above their eye line (nobody stares straight up); else C.behind. A squirrel moving faster than
--           a creep within C.hear studs is heard (a wire twangs, a branch rustles): at least C.heard, whatever the facing
--   over    C.overMult when it is close over them (within C.overhead studs level), else 1
--   cover   C.canopy on a branch or a trunk (the leaves), else 1
-- A landing off a leap on a route near them (squirrel.landed) adds C.land x range x max(view, C.heard) x over x cover
-- to the meter at once.
-- THE METER (0..1, one per person, on the squirrel they rate highest) rises by the rate a second (an impulse at once),
-- and while the rate is under C.quiet falls by C.decay a second. Creeping is slow and never a sure thing: a person who
-- faces a squirrel creeping 10 studs off needs C.spot / C.stalk = 20 s; one walking over them is seen in about 2 s.
-- THE STAGES, always in this order (a jump past several in one tick gives every event between, in order):
--   glance  (meter C.glance)  the head turns up to it for C.glanceSecs ("glance")
--   look    (meter C.look)    they stop and look up at it ("look")
--   spot    (meter 1)         they point it out and say so ("spot"); the service picks a neighbour to tell
--                             (tell(): the neighbour is raised to "look" and answers C.replyDelay later, "reply")
--   wary    (C.waryAfter after "spot", while still in sight) step back from under it, keep watching, hurry on or call
--           others over; a tough person waits below ("wary")
-- A spotted squirrel stays spotted while the person still has it in sight (exposure over C.sight); C.forget seconds
-- after the last such moment it is "lost" ("where'd it go?"): the meter falls to C.lostMeter and for C.calm seconds a
-- creep adds nothing (so a squirrel creeping on is not spotted again at once). A glance or look that empties back
-- under C.away ends with "away" (they look down again).
-- Interface: C; new() -> State; motion(squirrel) -> number; rate(squirrel, observer) -> (rate, impulse, exposure);
--   step(state, now, dt, seen) -> { Event } (seen: person id -> their best Seen this tick; anyone not in it saw
--   nothing); tell(state, now, from, to, squirrel) -> boolean; stageOf(state, person) -> (stage, squirrel?);
--   spotted(state, person, squirrel) -> boolean; meterOf(state, squirrel) -> (meter, seen); forget(state, person);
--   STAGES
-- Positions in studs (world frame), the person's eye; ids are whatever the caller uses. No side effects on require.

local RafterWatch = require("./RafterWatch")

local OverheadWatch = {}

OverheadWatch.C = {
	stalk = 0.05, -- per second, creeping: 20 s of a near person's full attention
	walk = 0.55, -- about 2 s
	sprint = 1.5, -- under a second
	stalkSpeed = RafterWatch.C.stalkSpeed, -- studs/s: the same creep line as the rafters (8; rail stalk 3, walk 18)
	stillSpeed = 0.2,
	sprintSpeed = 24,
	land = 0.4, -- a landing nearby, at once
	near = 14, -- studs, eye to squirrel
	far = 45,
	viewHalfAngle = math.acos(0.28), -- the v5.4 view cone (Actors/Perception inViewDot 0.28: about 74 degrees)
	lookUp = math.rad(65), -- more than this above a person's eye line counts as behind
	behind = 0.15,
	hear = 16, -- studs: a squirrel moving faster than a creep this near is heard whatever the facing
	heard = 0.5,
	overhead = 8, -- studs level: "close over them"
	overMult = 1.4,
	canopy = 0.35,
	quiet = 0.02,
	decay = 0.1,
	glance = 0.3,
	look = 0.6,
	spot = 1,
	away = 0.18, -- a glance or a look that empties back under this is over
	glanceSecs = 1.5,
	waryAfter = 2.5,
	replyDelay = 1.6,
	sight = 0.05, -- exposure that still counts as having it in sight (a spotted one)
	forget = 5,
	lostMeter = 0.35,
	calm = 8,
}
local C = OverheadWatch.C

OverheadWatch.STAGES = table.freeze({ "none", "glance", "look", "spot" })

export type Squirrel = {
	id: any,
	x: number,
	y: number,
	z: number,
	speed: number, -- studs/s (the fastest stretch since the last tick: Stealth/Pace)
	sprint: boolean?, -- sprinting or boosted
	canopy: boolean?, -- on a branch or a trunk (or in the air off one): the leaves hide it
	landed: boolean?, -- a leap's landing on a route this tick
}

export type Observer = {
	id: any,
	x: number,
	y: number, -- eye height
	z: number,
	faceX: number, -- facing in the ground plane (need not be unit)
	faceZ: number,
}

-- One person's best squirrel this tick (the caller picks the highest rate; OverheadWatch.rate).
export type Seen = { squirrel: any, rate: number, impulse: number, exposure: number, creep: boolean? }

export type Event = {
	kind: string, -- "glance" | "look" | "spot" | "reply" | "wary" | "lost" | "away"
	person: any,
	squirrel: any,
	other: any?, -- "reply": the one who told them
}

type Track = {
	squirrel: any,
	meter: number,
	stage: number, -- 1 none, 2 glance, 3 look, 4 spot
	glanceUntil: number,
	spotAt: number,
	sightAt: number, -- the last time it had the squirrel in sight
	wary: boolean,
	calmUntil: number,
	replyAt: number?,
	replyTo: any?,
}

export type State = { tracks: { [any]: Track } }

function OverheadWatch.new(): State
	return { tracks = {} }
end

-- The motion term of a squirrel (per second, before range, view, over and cover).
function OverheadWatch.motion(s: Squirrel): number
	if s.speed < C.stillSpeed then
		return 0
	elseif s.sprint or s.speed > C.sprintSpeed then
		return C.sprint
	elseif s.speed <= C.stalkSpeed then
		return C.stalk
	end
	return C.walk
end

-- rate(squirrel, observer): this person's suspicion a second (line of sight assumed: the caller's), the impulse a
-- landing adds at once, and the exposure (range x view x over x cover: how much of it they have in sight).
function OverheadWatch.rate(s: Squirrel, o: Observer): (number, number, number)
	local dx, dy, dz = s.x - o.x, s.y - o.y, s.z - o.z
	local level = math.sqrt(dx * dx + dz * dz)
	local dist = math.sqrt(level * level + dy * dy)
	local range = if dist <= C.near then 1 elseif dist >= C.far then 0 else (C.far - dist) / (C.far - C.near)
	if range <= 0 then
		return 0, 0, 0
	end
	local view = C.behind
	local fl = math.sqrt(o.faceX * o.faceX + o.faceZ * o.faceZ)
	if fl > 0 and level > 0 then
		local cos = (dx * o.faceX + dz * o.faceZ) / (level * fl)
		if cos >= math.cos(C.viewHalfAngle) and math.atan2(dy, level) <= C.lookUp then
			view = 1
		end
	end
	local loud = s.speed > C.stalkSpeed and dist <= C.hear
	if loud then
		view = math.max(view, C.heard)
	end
	local over = if level <= C.overhead then C.overMult else 1
	local cover = if s.canopy then C.canopy else 1
	local exposure = range * view * over * cover
	local impulse = 0
	if s.landed then
		local heard = if dist <= C.hear then C.heard else 0
		impulse = C.land * range * math.max(view, heard) * over * cover
	end
	return OverheadWatch.motion(s) * exposure, impulse, exposure
end

local function track(state: State, person: any, squirrel: any): Track
	local tr = state.tracks[person]
	if tr == nil then
		tr = {
			squirrel = squirrel,
			meter = 0,
			stage = 1,
			glanceUntil = 0,
			spotAt = 0,
			sightAt = -math.huge,
			wary = false,
			calmUntil = -math.huge,
			replyAt = nil,
			replyTo = nil,
		}
		state.tracks[person] = tr
	end
	return tr
end

local KINDS = { "glance", "look", "spot" }
local LEVELS = { C.glance, C.look, C.spot }

-- step(state, now, dt, seen): one tick. `seen[person]` is that person's best squirrel this tick (nil: they saw none).
function OverheadWatch.step(state: State, now: number, dt: number, seen: { [any]: Seen }): { Event }
	local events: { Event } = {}
	-- everyone with a track, and everyone who saw something
	for person, s in seen do
		local tr = state.tracks[person]
		if tr == nil and (s.rate > 0 or s.impulse > 0) then
			track(state, person, s.squirrel)
		elseif tr and tr.squirrel ~= s.squirrel and tr.stage < 4 then
			-- (a glance moves to the squirrel they now rate higher; a spotted one is watched until lost)
			tr.squirrel = s.squirrel
		end
	end
	for person, tr in state.tracks do
		local s = seen[person]
		if s and s.squirrel ~= tr.squirrel then
			s = nil -- (they are watching another one)
		end
		local rate = if s then s.rate else 0
		local impulse = if s then s.impulse else 0
		if s and s.creep and now < tr.calmUntil then
			rate, impulse = 0, 0 -- just lost: a creep adds nothing for a while
		end
		local inSight = s ~= nil and s.exposure >= C.sight
		if inSight then
			tr.sightAt = now
		end
		if tr.stage == 4 then
			-- spotted: held while in sight; wary a while after; lost once out of sight long enough
			tr.meter = 1
			if not tr.wary and inSight and now - tr.spotAt >= C.waryAfter then
				tr.wary = true
				table.insert(events, { kind = "wary", person = person, squirrel = tr.squirrel })
			end
			if now - tr.sightAt >= C.forget then
				tr.stage = 1
				tr.wary = false
				tr.meter = C.lostMeter
				tr.calmUntil = now + C.calm
				table.insert(events, { kind = "lost", person = person, squirrel = tr.squirrel })
			end
		else
			if rate < C.quiet and impulse == 0 then
				tr.meter = math.max(0, tr.meter - C.decay * dt)
			else
				tr.meter = math.min(1, tr.meter + rate * dt + impulse)
			end
			-- every stage crossed, in order
			for k = tr.stage, 3 do
				if tr.meter >= LEVELS[k] - 1e-9 then
					tr.stage = k + 1
					if k == 1 then
						tr.glanceUntil = now + C.glanceSecs
					elseif k == 3 then
						tr.spotAt = now
						tr.sightAt = now
						tr.meter = 1
					end
					table.insert(events, { kind = KINDS[k], person = person, squirrel = tr.squirrel })
				else
					break
				end
			end
			if (tr.stage == 2 or tr.stage == 3) and tr.meter < C.away then
				tr.stage = 1
				table.insert(events, { kind = "away", person = person, squirrel = tr.squirrel })
			end
		end
		-- the answer of someone they were told by
		if tr.replyAt ~= nil and now >= tr.replyAt then
			table.insert(events, { kind = "reply", person = person, squirrel = tr.squirrel, other = tr.replyTo })
			tr.replyAt = nil
			tr.replyTo = nil
		end
		if tr.stage == 1 and tr.meter <= 0 and tr.replyAt == nil and now >= tr.calmUntil then
			state.tracks[person] = nil
		end
	end
	return events
end

-- tell(state, now, from, to, squirrel): `from` points it out to `to`: they look up at it at once (at least "look")
-- and answer C.replyDelay later (a "reply" event). False when `to` has already spotted it or is answering someone.
function OverheadWatch.tell(state: State, now: number, from: any, to: any, squirrel: any): boolean
	local tr = state.tracks[to]
	if tr and (tr.stage == 4 or tr.replyAt ~= nil) then
		return false
	end
	tr = track(state, to, squirrel)
	tr.squirrel = squirrel
	tr.meter = math.max(tr.meter, C.look)
	tr.calmUntil = -math.huge
	if tr.stage < 3 then
		if tr.stage < 2 then
			tr.glanceUntil = now + C.glanceSecs
		end
		tr.stage = 3
	end
	tr.sightAt = now
	tr.replyAt = now + C.replyDelay
	tr.replyTo = from
	return true
end

-- stageOf(state, person): "none" | "glance" | "look" | "spot", and the squirrel. A glance over (C.glanceSecs) with the
-- meter still under "look" reads "none": they looked away again.
function OverheadWatch.stageOf(state: State, person: any, now: number?): (string, any?)
	local tr = state.tracks[person]
	if tr == nil then
		return "none", nil
	end
	if tr.stage == 2 and now ~= nil and now >= tr.glanceUntil then
		return "none", tr.squirrel
	end
	return OverheadWatch.STAGES[tr.stage], tr.squirrel
end

-- spotted(state, person, squirrel): this person has pointed that squirrel out and still has it in mind.
function OverheadWatch.spotted(state: State, person: any, squirrel: any): boolean
	local tr = state.tracks[person]
	return tr ~= nil and tr.stage == 4 and tr.squirrel == squirrel
end

-- meterOf(state, squirrel): the highest meter of anyone watching it, and whether anyone has spotted it (the
-- squirrel's own player's eye: Client/UI/SneakMeter).
function OverheadWatch.meterOf(state: State, squirrel: any): (number, boolean)
	local best, seen = 0, false
	for _, tr in state.tracks do
		if tr.squirrel == squirrel then
			best = math.max(best, tr.meter)
			if tr.stage == 4 then
				seen = true
			end
		end
	end
	return best, seen
end

-- forget(state, person): drop a person's track (their body was taken by a player, or left the world).
function OverheadWatch.forget(state: State, person: any)
	state.tracks[person] = nil
end

return OverheadWatch
