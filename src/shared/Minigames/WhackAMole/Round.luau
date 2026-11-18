--!strict
-- ReplicatedStorage.Shared.Minigames.WhackAMole.Round
-- One round of whack-a-mole, the owner's rules (docs/reference/whack_a_mole: Play_Whack_A_Mole.html and
-- source/play_whack_a_mole.py), as a pure seeded model the server keeps and every screen draws from.
--   Five holes; a 45-second round after a three-second count-in (READY, then GO: the count-in is ours, so nobody
--   is caught by the first mole while the camera is still moving).
--   +10 for a hit, -2 for a miss, never below zero. One hit per rise: a second strike on a mole already hit, as
--   it drops, changes nothing (his "a double tap on the same falling mole never scores twice or penalises twice").
--   A mole can be hit once it is more than 22 % of the way up and until 45 % of the fall time before it starts
--   to drop; a strike on a hole with nothing to hit there is a miss.
--   His pacing (the browser version, which plays faster and fuller than the Blender one): the first try at
--   0.3 s, then one every 0.76 s less 0.42 s over the round plus up to 0.19 s at random; a mole stays up 1.55 s
--   less 0.6 s over the round plus up to 0.22 s; one mole at a time for the first 35 % of the round, two after;
--   never the same hole twice running when another is free; it rises in 0.17 s (easing out) and drops in 0.21 s;
--   a hit mole drops at once; at TIME every mole still up drops (his finish() clears the deck; ours drops them
--   in FALL from where they were, so nothing stands up after the end). (Blender's play script: one at a time,
--   0.13 s up, 0.14 s down; not used.)
-- WHO DECIDES. The server keeps the Round and is the score of record. A strike comes in with the time the
-- player struck, on the clock both sides share, as round seconds (the Table turns the client's stamp into them),
-- and is judged at that moment of the round, so a player 150 ms away scores what they saw. It is refused (no
-- score either way) if it is stamped before GO ("early"), after the end ("time is up"), later than the server's
-- own round time plus AHEAD ("ahead": nobody strikes in the future), more than MAX_LAG behind it ("late"), before
-- the previous strike, or sooner than MIN_GAP after it ("too fast": one mallet).
-- Moles are decided LEAD seconds before they rise, from what the server knows then, so every screen can draw
-- them rising on time. A hit that arrives later never changes a decision already made (it only ever frees a
-- hole sooner, so a decision made without it is still possible); the round is the same on every replay of the
-- same strikes in the same order.
-- Times are round seconds: 0 is GO, negative is the count-in. Pure; Lune-tested (tests/unit/whack_round.spec.luau).
-- Interface: constants READY, SECONDS, RISE, FALL, FIRST, HITTABLE, LATE_CUT, HIT, MISS, LEAD, GRACE, MAX_LAG,
--   AHEAD, MIN_GAP, HOLES; new(seed) -> State; advance(state, dt) (the clock, and the moles decided up to
--   now + LEAD); strike(state, hole, t) -> (ok, why?, outcome?) (outcome: { kind = "hit" | "miss" | "again",
--   hole, t, id?, from? }, also kept as state.last); height(rise, t) -> 0..1; hittable(rise, t) -> bool; at(state, hole, t) -> Rise?
--   (the rise that is in that hole at t); left(state) -> seconds; over(state) -> bool; stop(state);
--   progress(t) -> 0..1; rateOf(state) -> hits / strikes (0..1); types Rise, State

local Rng = require("../../Util/Rng")

local Round = {}

Round.READY = 3 -- seconds of count-in before GO
Round.SECONDS = 45
Round.RISE = 0.17
Round.FALL = 0.21
Round.FIRST = 0.3 -- the first try at a mole, after GO
Round.HITTABLE = 0.22 -- how far up a mole must be to be hit (of the whole pop)
Round.LATE_CUT = Round.FALL * 0.45 -- a mole about to drop is no longer there to hit this long before it drops
Round.HIT = 10
Round.MISS = 2
Round.LEAD = 0.25 -- moles are decided this far ahead of their rise
Round.GRACE = 0.4 -- the round's result waits this long after the end for strikes still on their way
Round.MAX_LAG = 0.5 -- a strike stamped further behind the server's round time than this is refused
Round.AHEAD = 0.1 -- a strike may be stamped this far after the server's round time (clocks are not one)
Round.MIN_GAP = 0.1 -- the least time between two strikes: one mallet
Round.HOLES = 5

export type Rise = {
	id: number, -- 1, 2, 3 ... in the order decided
	hole: number,
	at: number, -- round seconds it starts to rise
	dur: number, -- seconds from the start of its rise to the bottom of its drop, unhit
	hitAt: number?, -- when it was hit
	from: number?, -- how far up it was when hit (0..1): it drops from there
}

export type Outcome = { kind: string, hole: number, t: number, id: number?, from: number? }

export type State = {
	now: number, -- round seconds (the server's clock)
	rng: Rng.Rng,
	nextTry: number, -- the next try at a mole (round seconds)
	rises: { Rise }, -- every mole decided, in order
	byHole: { { Rise } }, -- the same, hole by hole
	lastHole: number, -- the hole of the last mole decided (0: none yet)
	score: number,
	hits: number,
	misses: number,
	strikes: number, -- strikes judged (hits + misses + strikes on a mole already hit)
	lastStrike: number, -- round seconds of the last strike taken
	stopped: boolean, -- the player went: the round is over where it stands
	last: Outcome?, -- what the last strike taken did
}

function Round.progress(t: number): number
	return math.clamp(t / Round.SECONDS, 0, 1)
end

-- When the rise leaves its hole empty again: the end of its drop, or the end of the drop after a hit.
local function ends(r: Rise): number
	local hit = r.hitAt
	if hit ~= nil then
		return hit + Round.FALL
	end
	return r.at + r.dur
end

-- the height before the end of the round is taken into account
local function raw(r: Rise, t: number): number
	local age = t - r.at
	if age <= 0 or t >= ends(r) then
		return 0
	end
	local hit = r.hitAt
	if hit ~= nil and t >= hit then
		local k = (t - hit) / Round.FALL
		local from = r.from or 1
		return from * (1 - k) * (1 - k)
	end
	if age < Round.RISE then
		local k = 1 - age / Round.RISE
		return 1 - k * k * k
	end
	local dropAt = r.dur - Round.FALL
	if age > dropAt then
		local k = (age - dropAt) / Round.FALL
		return math.max(0, 1 - k * k)
	end
	return 1
end

-- height(rise, t): how far up the mole is at round time t, 0 (down) to 1 (up the whole pop). After the end of
-- the round it drops from where it was then, in FALL, as a hit mole does (or sooner, if it was dropping anyway).
function Round.height(r: Rise, t: number): number
	local h = raw(r, t)
	if t <= Round.SECONDS or h <= 0 then
		return h
	end
	local k = (t - Round.SECONDS) / Round.FALL
	if k >= 1 then
		return 0
	end
	return math.min(h, raw(r, Round.SECONDS) * (1 - k) * (1 - k))
end

-- hittable(rise, t): the owner's test (up more than HITTABLE, and not about to drop), and not hit yet.
function Round.hittable(r: Rise, t: number): boolean
	if r.hitAt ~= nil then
		return false
	end
	local age = t - r.at
	return age >= 0 and age < r.dur - Round.LATE_CUT and Round.height(r, t) > Round.HITTABLE
end

-- at(state, hole, t): the mole that is in that hole at t (the last one decided that has begun to rise by then
-- and not yet gone), or nil.
function Round.at(s: State, hole: number, t: number): Rise?
	local list = s.byHole[hole]
	if list == nil then
		return nil
	end
	for i = #list, 1, -1 do
		local r = list[i]
		if r.at <= t then
			return if t < ends(r) then r else nil
		end
	end
	return nil
end

function Round.new(seed: number): State
	local byHole = {}
	for i = 1, Round.HOLES do
		byHole[i] = {}
	end
	return {
		now = -Round.READY,
		rng = Rng.new(seed),
		nextTry = Round.FIRST,
		rises = {},
		byHole = byHole,
		lastHole = 0,
		score = 0,
		hits = 0,
		misses = 0,
		strikes = 0,
		lastStrike = -math.huge,
		stopped = false,
		last = nil,
	}
end

-- One try at a mole at round time T (his spawn()): at most one up before 35 % of the round, two after; a free
-- hole, not the last one if another is free.
local function try(s: State, T: number)
	local p = Round.progress(T)
	local limit = if p < 0.35 then 1 else 2
	local active = 0
	local free: { number } = {}
	for hole = 1, Round.HOLES do
		local r = Round.at(s, hole, T)
		if r == nil then
			table.insert(free, hole)
		elseif r.hitAt == nil then
			active += 1
		end
	end
	if active >= limit or #free == 0 then
		return
	end
	local pool = free
	if #free > 1 then
		local other = {}
		for _, h in free do
			if h ~= s.lastHole then
				table.insert(other, h)
			end
		end
		if #other > 0 then
			pool = other
		end
	end
	local hole = pool[math.floor(s.rng.next() * #pool) + 1]
	local dur = 1.55 - p * 0.6 + s.rng.next() * 0.22
	local rise: Rise = { id = #s.rises + 1, hole = hole, at = T, dur = dur }
	table.insert(s.rises, rise)
	table.insert(s.byHole[hole], rise)
	s.lastHole = hole
end

-- advance(state, dt): the server's clock moves on, and every try up to now + LEAD is made.
function Round.advance(s: State, dt: number)
	if s.stopped then
		return
	end
	s.now += math.max(0, dt)
	local horizon = s.now + Round.LEAD
	while s.nextTry <= horizon and s.nextTry < Round.SECONDS do
		local T = s.nextTry
		try(s, T)
		s.nextTry = T + 0.76 - Round.progress(T) * 0.42 + s.rng.next() * 0.19
	end
end

-- strike(state, hole, t): the player struck that hole at round time t. Returns whether it was taken and, if it
-- was not, why; if it was, what it did (see the header).
function Round.strike(s: State, hole: any, t: any): (boolean, string?, Outcome?)
	if type(hole) ~= "number" or hole ~= hole or hole % 1 ~= 0 or hole < 1 or hole > Round.HOLES then
		return false, "no such hole"
	end
	if type(t) ~= "number" or t ~= t or t == math.huge or t == -math.huge then
		return false, "no time"
	end
	if s.stopped or t >= Round.SECONDS then
		return false, "time is up"
	end
	if t < 0 then
		return false, "early"
	end
	if t > s.now + Round.AHEAD then
		return false, "ahead"
	end
	if t < s.now - Round.MAX_LAG then
		return false, "late"
	end
	if t < s.lastStrike then
		return false, "out of order"
	end
	if t < s.lastStrike + Round.MIN_GAP then
		return false, "too fast"
	end
	s.lastStrike = t
	s.strikes += 1
	local r = Round.at(s, hole, t)
	local hitAt = r and r.hitAt
	if r and hitAt and hitAt <= t then
		-- the mole is already dropping from a hit: nothing scores twice and nothing is lost
		s.last = { kind = "again", hole = hole, t = t, id = r.id }
		return true, nil, s.last
	end
	if r and Round.hittable(r, t) then
		local from = Round.height(r, t)
		r.hitAt = t
		r.from = from
		s.score += Round.HIT
		s.hits += 1
		s.last = { kind = "hit", hole = hole, t = t, id = r.id, from = from }
		return true, nil, s.last
	end
	s.score = math.max(0, s.score - Round.MISS)
	s.misses += 1
	s.last = { kind = "miss", hole = hole, t = t, id = if r then r.id else nil }
	return true, nil, s.last
end

function Round.left(s: State): number
	return math.clamp(Round.SECONDS - s.now, 0, Round.SECONDS)
end

-- over: the round has run (and the strikes still on their way have had GRACE to arrive), or the player went.
function Round.over(s: State): boolean
	return s.stopped or s.now >= Round.SECONDS + Round.GRACE
end

function Round.stop(s: State)
	s.stopped = true
end

-- how many strikes were hits (0..1), for the end card
function Round.rateOf(s: State): number
	local judged = s.hits + s.misses
	return if judged > 0 then s.hits / judged else 0
end

return Round
