--!strict
-- ReplicatedStorage.Shared.Minigames.MinigameRules.Darts
-- The dartboard beside the pool tables (brief v2 §13a: "mouse sets the aim point, a timing meter sets power,
-- slight wobble so it is a skill rather than a click; scores 501 and cricket"; BUILD_PLAN §3.16 darts:
-- authority "server_deterministic"). A throw is resolved here, not by physics: the client reports the aim
-- point it showed (mouse point plus the visible wobble) and where the timing meter stopped; the server adds
-- a seeded scatter that grows with the timing error (too soft drops the dart low, too hard throws it high)
-- and scores the landing point on a regulation board. Three darts a turn, up to 4 players.
--   501:     start at 501, finish exactly on zero with a double (the bull counts as a double); a bust (below
--            zero, one left, or zero without a double) puts the score back to where the turn started and
--            ends the turn. 20 rounds at most; then the lowest score left wins.
--   cricket: 15-20 and the bull; three marks close a number; extra marks score while any rival still has it
--            open; win by closing everything with at least as many points as every rival. 20 rounds at most.
-- Pure; Lune-tested (tests/unit/minigames_darts.spec.luau). Board units: millimetres from the bull, +x
-- right and +y up as the thrower sees it.
-- Interface: the Minigame.Rules shape (verbs "throw", "mode") plus turn(state), view(state),
--   scoreAt(x, y) -> Hit, resolve(rng, aimX, aimY, timing) -> (x, y), wobble(t) -> (dx, dy), ORDER, RADII

local Rng = require("../../Util/Rng")

local Darts = {}

Darts.def = {
	game = "darts",
	title = "Darts",
	class = "shared_table",
	seats = 4,
	authority = "server_deterministic",
	money = "none",
}
Darts.verbs = { throw = true, mode = true }
Darts.MODES = { "501", "cricket" }
Darts.DARTS_PER_TURN = 3
Darts.MAX_ROUNDS = 20

-- Regulation board (mm): clockwise from the top.
Darts.ORDER = { 20, 1, 18, 4, 13, 6, 10, 15, 2, 17, 3, 19, 7, 16, 8, 11, 14, 9, 12, 5 }
Darts.RADII = {
	bull = 6.35,
	outerBull = 15.9,
	tripleIn = 99,
	tripleOut = 107,
	doubleIn = 162,
	doubleOut = 170,
	board = 225, -- the black surround the dart can stick in (scores nothing)
}
Darts.CRICKET = { 20, 19, 18, 17, 16, 15, 25 }

-- Scatter: the timing meter's sweet spot is 0.5 (half the bar); the throw's spread and its vertical miss
-- grow with the distance from it. Base spread is the steadiest hand.
Darts.SWEET = 0.5
Darts.SWEET_HALF = 0.06 -- inside this band the throw is as good as it gets
Darts.BASE_SIGMA = 3.5 -- mm
Darts.SIGMA_PER_ERROR = 55 -- mm of spread per unit of timing error beyond the band
Darts.DROP_PER_ERROR = 140 -- mm of vertical miss per unit of timing error (soft = low, hard = high)
Darts.WOBBLE_MM = 9 -- the visible wobble of the aim (client draws it; the server trusts the drawn point)
Darts.MAX_AIM = 260 -- mm: aim points beyond the board are clamped (bounds check)

export type Hit = { ring: string, number: number, mult: number, points: number }

-- scoreAt(x, y): where a dart at (x, y) mm scores.
function Darts.scoreAt(x: number, y: number): Hit
	local r = math.sqrt(x * x + y * y)
	local R = Darts.RADII
	if r <= R.bull then
		return { ring = "bull", number = 25, mult = 2, points = 50 }
	elseif r <= R.outerBull then
		return { ring = "outer_bull", number = 25, mult = 1, points = 25 }
	elseif r > R.doubleOut then
		return { ring = "miss", number = 0, mult = 0, points = 0 }
	end
	-- angle clockwise from straight up, 20 centred on 0
	local a = math.deg(math.atan2(x, y)) -- 0 = up, +90 = right
	if a < 0 then
		a += 360
	end
	local idx = math.floor(((a + 9) % 360) / 18) + 1
	local n = Darts.ORDER[idx]
	local mult = 1
	local ring = "single"
	if r >= R.tripleIn and r <= R.tripleOut then
		mult, ring = 3, "triple"
	elseif r >= R.doubleIn then
		mult, ring = 2, "double"
	end
	return { ring = ring, number = n, mult = mult, points = n * mult }
end

-- Standard normal from the seeded stream (Box-Muller).
local function gauss(rng: Rng.Rng): number
	local u = math.max(rng.next(), 1e-9)
	local v = rng.next()
	return math.sqrt(-2 * math.log(u)) * math.cos(2 * math.pi * v)
end

-- resolve(rng, aimX, aimY, timing): the landing point (mm) for a throw at the shown aim point with the
-- meter stopped at `timing` (0..1).
function Darts.resolve(rng: Rng.Rng, aimX: number, aimY: number, timing: number): (number, number)
	local t = math.clamp(timing, 0, 1)
	local err = math.max(0, math.abs(t - Darts.SWEET) - Darts.SWEET_HALF)
	local sigma = Darts.BASE_SIGMA + Darts.SIGMA_PER_ERROR * err
	local drop = Darts.DROP_PER_ERROR * err * (if t < Darts.SWEET then -1 else 1)
	local ax = math.clamp(aimX, -Darts.MAX_AIM, Darts.MAX_AIM)
	local ay = math.clamp(aimY, -Darts.MAX_AIM, Darts.MAX_AIM)
	return ax + gauss(rng) * sigma, ay + drop + gauss(rng) * sigma
end

-- wobble(t): the hand's slight drift the client draws on the aim reticle (mm), a slow Lissajous so it can
-- be timed. Pure so the client and tests agree.
function Darts.wobble(t: number): (number, number)
	local w = Darts.WOBBLE_MM
	return w * math.sin(t * 2.1) * 0.8 + w * 0.2 * math.sin(t * 5.3), w * math.sin(t * 1.7 + 0.6) * 0.9
end

-- The meter: a ping-pong bar 0 -> 1 -> 0 over PERIOD seconds since the charge started.
Darts.METER_PERIOD = 1.3
function Darts.meter(elapsed: number): number
	local p = (elapsed / Darts.METER_PERIOD) % 2
	return if p <= 1 then p else 2 - p
end

export type Seat = {
	score: number, -- 501: remaining; cricket: points
	marks: { [number]: number }, -- cricket marks per number (15..20, 25)
	turnStart: number, -- 501: remaining at the start of the turn
	darts: { { x: number, y: number, label: string, points: number } }, -- this turn's darts
	history: { number }, -- 501: points scored per completed turn
}

export type State = {
	seats: number,
	mode: string,
	rng: Rng.Rng,
	seat: number,
	dart: number, -- 1..3 within the turn
	round: number,
	started: boolean, -- the first dart locks the mode
	done: boolean,
	winner: number?,
	players: { Seat },
	lastHit: { [string]: any }?,
}

local function newSeat(mode: string): Seat
	local marks: { [number]: number } = {}
	for _, n in Darts.CRICKET do
		marks[n] = 0
	end
	return {
		score = if mode == "501" then 501 else 0,
		marks = marks,
		turnStart = 501,
		darts = {},
		history = {},
	}
end

function Darts.init(seats: number, seed: number): State
	local players = {}
	for i = 1, seats do
		players[i] = newSeat("501")
	end
	return {
		seats = seats,
		mode = "501",
		rng = Rng.new(seed),
		seat = 1,
		dart = 1,
		round = 1,
		started = false,
		done = false,
		winner = nil,
		players = players,
		lastHit = nil,
	}
end

function Darts.setMode(state: State, mode: string): (boolean, string?)
	if state.started then
		return false, "the game has started"
	end
	if mode ~= "501" and mode ~= "cricket" then
		return false, "mode"
	end
	state.mode = mode
	for i = 1, state.seats do
		state.players[i] = newSeat(mode)
	end
	return true
end

function Darts.turn(state: State): number?
	return if state.done then nil else state.seat
end

local function label(h: Hit): string
	if h.ring == "miss" then
		return "MISS"
	elseif h.ring == "bull" then
		return "BULL"
	elseif h.ring == "outer_bull" then
		return "25"
	elseif h.mult == 3 then
		return `T{h.number}`
	elseif h.mult == 2 then
		return `D{h.number}`
	end
	return tostring(h.number)
end
Darts.label = label

local function cricketClosedAll(p: Seat): boolean
	for _, n in Darts.CRICKET do
		if p.marks[n] < 3 then
			return false
		end
	end
	return true
end

local function endTurn(state: State)
	local p = state.players[state.seat]
	if state.mode == "501" then
		table.insert(p.history, p.turnStart - p.score)
	end
	state.dart = 1
	state.seat += 1
	if state.seat > state.seats then
		state.seat = 1
		state.round += 1
		if state.round > Darts.MAX_ROUNDS then
			state.done = true
			-- out of rounds: 501 lowest remaining wins; cricket most points, then most marks
			local best, winner, tie = math.huge, nil :: number?, false
			for i = 1, state.seats do
				local q = state.players[i]
				local key
				if state.mode == "501" then
					key = q.score
				else
					local m = 0
					for _, n in Darts.CRICKET do
						m += math.min(3, q.marks[n])
					end
					key = -(q.score * 100 + m)
				end
				if key < best then
					best, winner, tie = key, i, false
				elseif key == best then
					tie = true
				end
			end
			state.winner = if tie then nil else winner
		end
	end
	local nxt = state.players[state.seat]
	nxt.turnStart = nxt.score
	nxt.darts = {}
end

-- applyHit(state, hit): score one dart for the current seat; returns a short event word.
function Darts.applyHit(state: State, hit: Hit): string
	local seat = state.seat
	local p = state.players[seat]
	local event = "scored"
	if state.mode == "501" then
		local left = p.score - hit.points
		local isDouble = hit.mult == 2 -- D1-D20 and the bull
		if left < 0 or left == 1 or (left == 0 and not isDouble) then
			p.score = p.turnStart
			event = "bust"
		elseif left == 0 then
			p.score = 0
			event = "checkout"
			state.done = true
			state.winner = seat
		else
			p.score = left
		end
	else
		local n = hit.number
		if p.marks[n] ~= nil and hit.mult > 0 then
			local before = p.marks[n]
			local after = before + hit.mult
			p.marks[n] = after
			local extra = after - math.max(3, before)
			if extra > 0 then
				local open = false
				for i = 1, state.seats do
					if i ~= seat and state.players[i].marks[n] < 3 then
						open = true
					end
				end
				if open then
					p.score += extra * n
				end
			end
			if before < 3 and after >= 3 then
				event = "closed"
			end
		else
			event = "nothing"
		end
		if cricketClosedAll(p) then
			local lead = true
			for i = 1, state.seats do
				if i ~= seat and state.players[i].score > p.score then
					lead = false
				end
			end
			if lead then
				state.done = true
				state.winner = seat
				event = "win"
			end
		end
	end
	return event
end

-- throwAt(state, x, y): land a dart at (x, y) mm for the current seat (scripted throws and the resolved
-- throw both come through here). Returns the hit and the event.
function Darts.throwAt(state: State, x: number, y: number): (Hit, string)
	state.started = true
	local hit = Darts.scoreAt(x, y)
	local seat = state.seat
	local p = state.players[seat]
	local event = Darts.applyHit(state, hit)
	table.insert(p.darts, { x = x, y = y, label = label(hit), points = hit.points })
	state.lastHit = { seat = seat, x = x, y = y, label = label(hit), points = hit.points, event = event }
	if state.done then
		return hit, event
	end
	if event == "bust" or state.dart >= Darts.DARTS_PER_TURN then
		endTurn(state)
	else
		state.dart += 1
	end
	return hit, event
end

-- skipTurn: the rest of the current turn as misses (an idle turn or a player who walked away).
function Darts.skipTurn(state: State)
	local seat, round = state.seat, state.round
	local guard = 0
	while not state.done and state.seat == seat and state.round == round and guard < 4 do
		Darts.throwAt(state, 999, 999)
		guard += 1
	end
end

-- input: "throw" { aimX, aimY, timing } (server resolves the scatter) or "throwAt" handled by the service
-- for scripted landings; "mode" { "501" | "cricket" } before the first dart.
function Darts.input(state: State, seat: number, verb: string, args: { any }?): (boolean, string?)
	local a = args or {}
	if verb == "mode" then
		return Darts.setMode(state, tostring(a[1]))
	end
	if verb ~= "throw" then
		return false, "verb"
	end
	if state.done then
		return false, "game over"
	end
	if seat ~= state.seat then
		return false, "not your turn"
	end
	local ax, ay, timing = a[1], a[2], a[3]
	if type(ax) ~= "number" or type(ay) ~= "number" or type(timing) ~= "number" then
		return false, "args"
	end
	if ax ~= ax or ay ~= ay or timing ~= timing then
		return false, "args"
	end
	local x, y = Darts.resolve(state.rng, ax, ay, timing)
	Darts.throwAt(state, x, y)
	return true
end

function Darts.result(state: State): { [string]: any }?
	if not state.done then
		return nil
	end
	local scores: { [number]: number } = {}
	for i = 1, state.seats do
		scores[i] = state.players[i].score
	end
	return { done = true, scores = scores, winner = state.winner, mode = state.mode }
end

function Darts.view(state: State): { [string]: any }
	local seats = {}
	for i = 1, state.seats do
		local p = state.players[i]
		local marks = {}
		for _, n in Darts.CRICKET do
			marks[tostring(n)] = p.marks[n]
		end
		local darts = {}
		for k, d in p.darts do
			darts[k] = d.label
		end
		seats[i] = { score = p.score, marks = marks, darts = darts, turnStart = p.turnStart }
	end
	return {
		kind = "darts",
		mode = state.mode,
		seats = seats,
		turn = if state.done then nil else state.seat,
		dart = state.dart,
		round = state.round,
		maxRounds = Darts.MAX_ROUNDS,
		done = state.done,
		winner = state.winner,
		lastHit = state.lastHit,
		started = state.started,
	}
end

return Darts
