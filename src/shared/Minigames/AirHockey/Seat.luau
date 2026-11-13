--!strict
-- ReplicatedStorage.Shared.Minigames.AirHockey.Seat
-- A player's own end of the match: THE FEEL. Air hockey is ruined by a mallet that lags the hand or a puck that
-- stutters, so a seated player never waits for the server to see their own hand:
--   * the hand's target is quantised (Wire.snap) and given, at once, to the player's OWN copy of the simulation
--     (`pred`), which is stepped to the present tick of the shared clock every frame. The mallet on their screen
--     is that simulation's mallet: no delay at all, and exactly the mallet the referee will step when the log
--     arrives, because both are given the same numbers on the same ticks;
--   * what the hand did goes into a log by tick, sent on in segments (Wire: ten or fifteen messages a second);
--   * the referee's stream comes back a moment later and is replayed exactly (Replica). The state it gives for
--     tick c is compared with what this seat predicted for tick c (a ring of past predictions). Against the
--     computer they are always the same, to the last bit: nothing is ever corrected, and the player has the
--     owner's single-player game. Against a person they differ when the other hand did something this seat
--     could not know yet (its mallet is predicted to keep going where it was last aimed): then the prediction
--     is rebuilt from the referee's state by replaying this player's own logged inputs on top of it (a few dozen
--     ticks). The player's own mallet is never moved by a correction of the other's hand.
--   * AGAINST A PERSON, WHAT IS DRAWN IS NOT ALL ONE MOMENT. Nobody can know what the other hand is doing now:
--     a guess of it drawn as fact is a far mallet that twitches and a puck that bounces off nothing and then
--     jumps. So the far end of the table is drawn a little in the past, from what the referee has decided, and
--     this end in the present, from the prediction:
--       - this player's own mallet: now, always;
--       - the far mallet: the referee's, as late as the stream is (`late`, a slow envelope of the gap between
--         the clock and the newest tick decided: one round trip and a segment). It is the other player's real
--         hand, smooth, a moment ago: never a guess;
--       - the puck: as late as it MUST be and no later, and THE PRESENT PUCK WHERE THIS MALLET CAN MEET IT.
--         Where the far mallet could have touched it since the referee last saw that mallet, the puck has to
--         be drawn late enough for the referee's word to be here: as late as the far mallet where the two
--         touch, less and less with distance from that mallet (a mallet is no faster than 3.5 m/s), not at
--         all beyond its reach (need()). Everywhere else it may be drawn now. So the moment drawn has to fall
--         behind the clock while a shot travels to the far mallet and catch up as the puck comes back:
--           GOING AWAY the falling behind is spread over the whole trip, never taken at one place: every frame
--           the puck's path is looked along (what is believed of it, and LOOK ticks beyond the present) for
--           the place that will ask the most lateness for the time left to reach it, and the puck is drawn at
--           the one steady rate that just gets there. A shot is drawn a little slower from the mallet that
--           struck it, all the way (about three quarters of its speed on a good line); it never stops.
--           COMING BACK the catching up starts the moment the referee's word of the strike is here, wherever
--           the puck is then drawn, and is over by the time the puck is MEET in front of this player's mallet
--           (or at the centre line, if the mallet is further forward than that): from there on what is drawn
--           is the present puck, so a strike lands where it is seen to land. Where there is time it is gentle
--           (no faster than RATE_MAX, never drawn quicker than DRAWN_MAX, the last of it eased over LAND);
--           where there is not (a hard shot on a slow line is in this half before its word is) it is as fast
--           as it takes, FAST at the most. The lateness is one round trip and a segment whatever is done with
--           it: it can be shown as a puck that arrives late at the mallet, or as a puck that hurries across
--           the far half, and the second is chosen because the first makes a player miss what they see.
--         No part of a shot is skipped: the drawn puck passes through every place the real one did.
--       - and never a guess: the puck is drawn no further on than the prediction is CERTAIN, which is as far
--         as the far mallet, wherever its hand went, cannot have touched the puck (certain()). Up to there
--         the prediction is the referee's match to be, because everything else in it is this player's own
--         hand and the table.
--     So what is on a player's screen against a person is the referee's match: this end now, the far end a
--     moment ago. The other player's serve button is no mallet's doing, and it is not guessed either: between
--     two people a press lets the puck go Sim.SERVE_LEAD later, and the table passes the press on at once
--     (pressed()), so this screen knows of it before the puck moves (on a line slower than about 180 ms each
--     way the word comes after the puck has left: it is then found a little way along its serve and eased
--     there over EASE seconds, as any correction under the moment drawn would be).
-- Pure (no engine): the client's controller feeds it the clock, the hand and the stream; specs and the netcode
-- measurements (tools/games/air_hockey/netcode.luau) drive it the same way.
-- Interface: new(side) -> Seat; begin(seat, game, from) (the referee's word that this seat's log starts at tick
--   `from` of match `game`); resume(seat, from) (its word that a segment was lost: the log is sent again from
--   there); pressed(seat, tick) (its word that the other player pressed their serve button on that tick);
--   push(seat, msg) (a stream message); aim(seat, x, y) (the hand, model metres);
--   serve(seat); step(seat, now, send, onTick?, onConfirmed?) (now: the shared clock's tick, fractional;
--   send(from, to, strings); onTick(sim, tick, hit, goal, served) for each newly predicted tick; onConfirmed
--   the same for each tick the referee decided); view(seat) -> (puck x, y, mallet0 x, y, mallet1 x, y) as drawn now;
--   heard(seat, fn) (fn(what, speed) for each contact the drawn puck has just passed: Sim.HIT_*, m/s);
--   relax(seat, dt); Seat.pred / .tick / .replica / .resims / .ready; Seat.puckAt / .farAt (the ticks the puck
--   and the far mallet are drawn at) / .late / .held (frames the puck was slowed into the edge of what is
--   certain); EASE; LEAD; RATE_MAX; DRAWN_MAX; MEET; FAST; LAND; LAND_RATE; LOOK; PAD; BRAKE

local Replica = require("./Replica")
local Sim = require("./Sim")
local Wire = require("./Wire")

local Seat = {}

Seat.EASE = 0.07 -- seconds: the time constant a correction of the drawn puck is eased out over
Seat.SNAP = 0.6 -- metres: a correction larger than this is not eased (the puck was served, or scored)
Seat.LEAD = 480 -- ticks the prediction may run ahead of the referee's last word (2 s: then it waits)
Seat.RATE_MAX = 2 -- against a person, where there is time: the moment the puck is drawn at runs no faster than this...
Seat.DRAWN_MAX = 1.45 * Sim.MAX_SPEED -- ...and never so fast that the puck is drawn quicker than this (m/s)
Seat.MEET = 0.15 -- metres in front of this player's mallet: from there on the puck drawn is the present puck...
Seat.FAST = 4 -- ...whatever rate it takes to be that in time, up to this much against the clock
Seat.LAND = 4 -- ticks: the last of a gentle catch-up is eased (the rate falls over about this much lateness...
Seat.LAND_RATE = 0.5 -- ...to no less than this above the clock's, until the puck drawn is the present puck)
Seat.LOOK = 96 -- ticks beyond the present the puck's path is looked along for where it will have to be late
Seat.PAD = 2 -- ticks of lateness asked for beyond what is strictly needed
Seat.MARGIN = 2 -- ticks the far end is drawn behind the newest the stream has brought at its latest
Seat.SHRINK = 0.15 -- how fast `late` comes down when the stream is earlier than it was (ticks a tick)
Seat.WINDOW = 72 -- ticks: the stream's lateness is the most it has been over the last one to two of these
Seat.BRAKE = 6 -- ticks: a puck that reaches the edge of what is certain is slowed into it over about this much
local CAP = 1024 -- ticks of past predictions kept
local WIDTH = #Wire.STATE
-- numbers kept for each tick to draw from: puck x, y, far mallet x, y, hitSerial, hitWhat, hitSpeed, and 1 while
-- the puck waits for its serve
local DRAWN = 8

export type Seat = {
	side: number,
	replica: Replica.Replica,
	pred: Sim.State,
	tick: number, -- the tick `pred` is at
	frac: number, -- how far into the next tick the clock is (for drawing between ticks)
	ready: boolean, -- the log has a start and there is a state to predict from
	game: number?,
	from: number?,
	sentTo: number,
	log: { [number]: any }, -- this hand's events by tick, from the last one the referee confirmed
	wantX: number?, -- the hand's target, quantised, not yet given to a tick
	wantY: number?,
	lastX: number?,
	lastY: number?,
	serving: boolean,
	hist: { number },
	histTick: { number },
	mode: string,
	jumps: number,
	resims: number, -- times the prediction was rebuilt from the referee's state
	told: number, -- the last tick onTick was called for
	prev: { number }, -- the drawn positions one tick before `pred`
	ex: number, -- the puck's eased correction (drawn = predicted + this)
	ey: number,
	ox: number, -- the far mallet's
	oy: number,
	-- against a person: what is believed of each tick (the referee's word where it has come, the prediction
	-- beyond it), and the moments the far end is drawn at
	drawn: { number },
	drawnTick: { number },
	late: number, -- ticks the far end is drawn behind the clock
	puckAt: number, -- the tick the puck is drawn at (fractional)
	farAt: number, -- and the far mallet
	clock: number, -- the clock at the last step
	gapNow: number, -- the most the stream has been behind the clock since gapSince, and in the stretch before
	gapBefore: number,
	gapSince: number,
	heardTo: number, -- contacts up to this tick have been sounded
	held: number, -- frames on which the edge of what is certain kept the puck's moment from running on
	headWas: number, -- the newest tick the stream had brought at the last step, and the clock when it last grew
	wordAt: number,
	flush: boolean, -- the log holds a serve that has not been sent: the next segment goes at once
	theirs: { [number]: boolean }, -- ticks on which the other player pressed their serve button (the table's word)
	stale: boolean, -- such a word came for a tick already predicted: the prediction is rebuilt
}

function Seat.new(side: number): Seat
	return {
		side = side,
		replica = Replica.new(),
		pred = Sim.new(),
		tick = 0,
		frac = 0,
		ready = false,
		game = nil,
		from = nil,
		sentTo = 0,
		log = {},
		wantX = nil,
		wantY = nil,
		lastX = nil,
		lastY = nil,
		serving = false,
		hist = table.create(CAP * WIDTH, 0),
		histTick = table.create(CAP, -1),
		mode = "",
		jumps = 0,
		resims = 0,
		told = 0,
		prev = { 0, 0, 0, 0, 0, 0 },
		ex = 0,
		ey = 0,
		ox = 0,
		oy = 0,
		drawn = table.create(CAP * DRAWN, 0),
		drawnTick = table.create(CAP, -1),
		late = 0,
		puckAt = 0,
		farAt = 0,
		clock = 0,
		gapNow = 0,
		gapBefore = 0,
		gapSince = 0,
		heardTo = 0,
		held = 0,
		headWas = -1,
		wordAt = 0,
		flush = false,
		theirs = {},
		stale = false,
	}
end

function Seat.begin(seat: Seat, game: number, from: number)
	seat.game = game
	seat.from = from
	seat.sentTo = from
	seat.ready = false
	table.clear(seat.log)
	seat.lastX, seat.lastY = nil, nil
end

-- The referee's word that it has this hand's log only up to tick `from` (a segment was lost on the way): the
-- log is sent again from there, in one segment, at the next step. Every event the referee has not decided is
-- still held here, so nothing of the hand is lost and nothing on this screen changes.
function Seat.resume(seat: Seat, from: number)
	if seat.from == nil or from % 1 ~= 0 or from < 0 then
		return
	end
	seat.sentTo = math.min(from, seat.tick)
	seat.flush = true
end

-- The table's word that the OTHER player pressed their serve button on tick `tick` (it is passed on the moment
-- their log brings it, before the referee has played that tick). The press cuts the countdown to
-- Sim.SERVE_LEAD, so this screen knows when the puck will leave before it does. It is the other player's own
-- deed, not a guess; should the referee not have taken it after all, its stream says so and the prediction is
-- rebuilt as for anything else.
function Seat.pressed(seat: Seat, tick: number)
	if tick % 1 ~= 0 or tick <= seat.replica.tick then
		return
	end
	seat.theirs[tick] = true
	if tick <= seat.tick then
		seat.stale = true
	end
end

function Seat.push(seat: Seat, msg: any): boolean
	return Replica.push(seat.replica, msg)
end

function Seat.aim(seat: Seat, x: number, y: number)
	if x == x and y == y then
		seat.wantX, seat.wantY = Wire.quantise(seat.side, x, y)
	end
end

function Seat.serve(seat: Seat)
	seat.serving = true
end

-- What is believed of a tick, to draw from: the referee's state of it, or the prediction's.
local function believe(seat: Seat, tick: number, s: Sim.State)
	local slot = tick % CAP
	seat.drawnTick[slot + 1] = tick
	local base = slot * DRAWN
	local d = seat.drawn
	d[base + 1], d[base + 2] = s.px, s.py
	if seat.side == 0 then
		d[base + 3], d[base + 4] = s.p1x, s.p1y
	else
		d[base + 3], d[base + 4] = s.p0x, s.p0y
	end
	d[base + 5], d[base + 6], d[base + 7] = s.hitSerial, s.hitWhat, s.hitSpeed
	d[base + 8] = if s.countdown > 0 then 1 else 0
end

local function remember(seat: Seat)
	local slot = seat.tick % CAP
	seat.histTick[slot + 1] = seat.tick
	local s = seat.pred :: any
	local base = slot * WIDTH
	local hist = seat.hist
	for i, k in Wire.STATE do
		hist[base + i] = s[k]
	end
	believe(seat, seat.tick, seat.pred)
end

-- The puck (which = 1) or the far mallet (which = 3) as believed at a moment between ticks (nil: that tick is
-- not held).
local function believed(seat: Seat, at: number, which: number): (number?, number?)
	local t0 = math.floor(at)
	local f = at - t0
	local s0, s1 = t0 % CAP, (t0 + 1) % CAP
	if seat.drawnTick[s0 + 1] ~= t0 then
		return nil, nil
	end
	local d = seat.drawn
	local ax, ay = d[s0 * DRAWN + which], d[s0 * DRAWN + which + 1]
	if f <= 0 or seat.drawnTick[s1 + 1] ~= t0 + 1 then
		return ax, ay
	end
	local bx, by = d[s1 * DRAWN + which], d[s1 * DRAWN + which + 1]
	if which == 1 and math.abs(bx - ax) + math.abs(by - ay) > 0.2 then
		-- (a puck put back on its spot within this tick is not slid there from the goal)
		if f < 0.5 then
			return ax, ay
		end
		return bx, by
	end
	return ax + (bx - ax) * f, ay + (by - ay) * f
end

local function predicted(seat: Seat, tick: number, sim: Sim.State): boolean
	local slot = tick % CAP
	if seat.histTick[slot + 1] ~= tick then
		return false
	end
	local s = sim :: any
	local base = slot * WIDTH
	local hist = seat.hist
	for i, k in Wire.STATE do
		if hist[base + i] ~= s[k] then
			return false
		end
	end
	return true
end

local function keep(seat: Seat)
	local p, s = seat.prev, seat.pred
	p[1], p[2], p[3], p[4], p[5], p[6] = s.px, s.py, s.p0x, s.p0y, s.p1x, s.p1y
end

-- One tick of the prediction: this hand's event for the tick (if any), the other side as the mode says.
local function advance(seat: Seat)
	local sim = seat.pred
	local tick = seat.tick + 1
	if seat.theirs[tick] and seat.mode == "2" then
		Sim.press(sim, false)
	end
	local e = seat.log[tick]
	if e then
		if e[3] then
			Sim.press(sim, seat.mode ~= "2")
		end
		if e[1] then
			local x, y = Wire.target(seat.side, e[1], e[2])
			Sim.setTarget(sim, seat.side, x, y)
		end
	end
	keep(seat)
	if seat.mode == "2" then
		-- the other hand is not known yet: its mallet keeps going where it was last aimed
		Sim.play(sim, 0, false)
		if sim.winner >= 0 then
			-- A seventh goal that is only predicted does not end anything: the other hand may have saved it. The
			-- puck stays where it went in, the score shows, and both mallets stay alive (and this hand goes on
			-- being logged) until the referee's word comes: a match that is really won arrives with its winner.
			sim.winner = -1
			sim.countdown = math.huge
		end
	else
		Sim.play(sim, seat.side, true)
	end
	seat.tick = tick
	remember(seat)
end

-- The prediction rebuilt on the referee's state: its tick, then this hand's own log replayed up to where the
-- prediction had got to.
local function rebuild(seat: Seat)
	local r = seat.replica
	local was = seat.tick
	Sim.copy(seat.pred, r.sim)
	seat.tick = r.tick
	seat.mode = r.mode
	remember(seat)
	keep(seat)
	while seat.tick < was and seat.pred.winner < 0 do
		advance(seat)
	end
end

-- Where the puck and the far mallet are drawn, before any eased correction: against the computer the present
-- moment (between the last whole tick and the next, both predicted, which there is the referee's match);
-- against a person the moments `puckAt` and `farAt` of what is believed.
local function drawnNow(seat: Seat): (number, number, number, number)
	local p, s, f = seat.prev, seat.pred, seat.frac
	local px, py = p[1] + (s.px - p[1]) * f, p[2] + (s.py - p[2]) * f
	if math.abs(s.px - p[1]) + math.abs(s.py - p[2]) > 0.2 then
		-- (a puck that is put back on its spot within this tick is not slid there from the goal: it is at
		-- whichever end of the tick the clock is nearer)
		if f < 0.5 then
			px, py = p[1], p[2]
		else
			px, py = s.px, s.py
		end
	end
	local fx, fy
	if seat.side == 0 then
		fx, fy = p[5] + (s.p1x - p[5]) * f, p[6] + (s.p1y - p[6]) * f
	else
		fx, fy = p[3] + (s.p0x - p[3]) * f, p[4] + (s.p0y - p[4]) * f
	end
	if seat.mode == "2" then
		local bx, by = believed(seat, seat.puckAt, 1)
		if bx and by then
			px, py = bx, by
		end
		local mx, my = believed(seat, seat.farAt, 3)
		if mx and my then
			fx, fy = mx, my
		end
	end
	return px, py, fx, fy
end

-- How far past the referee's last word the prediction is CERTAIN: the newest tick up to which the far mallet,
-- wherever its hand has gone since (it is kept to its half and to its speed), cannot have touched the puck.
-- Up to there the predicted puck is the referee's puck to be; beyond it, it is a guess.
-- (a contact is looked for at the ends of ticks: the reach is padded by what the puck travels within one)
local REACH = Sim.PUCK_RADIUS + Sim.PADDLE_RADIUS + 0.004 + Sim.MAX_SPEED * Sim.STEP
local function certain(seat: Seat, confirmed: number): number
	local r = seat.replica.sim
	local far = if seat.side == 0 then 1 else -1
	local fx, fy = r.p1x, r.p1y
	if seat.side ~= 0 then
		fx, fy = r.p0x, r.p0y
	end
	local d = seat.drawn
	local limitX = Sim.HALF_WIDTH - Sim.PADDLE_RADIUS
	local tick = confirmed
	while tick < seat.tick do
		local slot = (tick + 1) % CAP
		if seat.drawnTick[slot + 1] ~= tick + 1 then
			break
		end
		if d[slot * DRAWN + 8] == 1 then
			-- (a puck waiting for its serve is touched by nothing)
			tick += 1
			continue
		end
		local px, py = d[slot * DRAWN + 1], d[slot * DRAWN + 2]
		local before = tick % CAP
		if
			seat.drawnTick[before + 1] == tick
			and d[slot * DRAWN + 5] ~= d[before * DRAWN + 5]
			and d[slot * DRAWN + 6] == Sim.HIT_MALLET + (1 - seat.side)
		then
			break -- (the prediction itself has the far mallet strike here: a guess)
		end
		-- the nearest the far mallet's centre could be to the puck, in its own half...
		local q = py * far
		local nx = math.clamp(px, -limitX, limitX)
		local nq = math.clamp(q, Sim.PADDLE_RADIUS, Sim.HALF_LENGTH - Sim.PADDLE_RADIUS)
		local gx, gq = px - nx, q - nq
		if gx * gx + gq * gq <= REACH * REACH then
			-- ...and whether it can have got there since the referee last saw it
			local dx, dy = px - fx, py - fy
			local reach = REACH + Sim.HUMAN_SPEED * Sim.STEP * (tick + 2 - confirmed)
			if dx * dx + dy * dy <= reach * reach then
				break
			end
		end
		tick += 1
	end
	return tick
end

-- How late (ticks behind the clock) a puck at this place must be drawn for the referee's word of the far mallet
-- to be here: the far mallet, last seen by the referee at (mx, my), is no faster than a hand, so it can have
-- touched a puck `dist` away only if as many ticks have gone by as it takes to cover the gap. `late` at the
-- mallet's own reach, a tick less for every 14.6 mm beyond it, nothing where no mallet of that end can come.
-- (the same rule as certain(), which is the hard edge under it)
local STRIDE = Sim.HUMAN_SPEED * Sim.STEP
local function need(seat: Seat, px: number, py: number, mx: number, my: number, late: number): number
	local far = if seat.side == 0 then 1 else -1
	local q = py * far
	local limitX = Sim.HALF_WIDTH - Sim.PADDLE_RADIUS
	local nx = math.clamp(px, -limitX, limitX)
	local nq = math.clamp(q, Sim.PADDLE_RADIUS, Sim.HALF_LENGTH - Sim.PADDLE_RADIUS)
	local gx, gq = px - nx, q - nq
	if gx * gx + gq * gq > REACH * REACH then
		return 0
	end
	local dx, dy = px - mx, py - my
	local dist = math.sqrt(dx * dx + dy * dy)
	return math.clamp(late - (dist - REACH) / STRIDE + Seat.PAD, 0, late)
end

-- The moments the far end is drawn at move on with the clock (against a person; see the header).
local function moments(seat: Seat, now: number, confirmed: number)
	local dt = math.clamp(now - seat.clock, 0, 240)
	seat.clock = now
	if seat.mode ~= "2" then
		seat.late = 0
		seat.puckAt, seat.farAt = now, now
		return
	end
	-- how late the stream is: the most the clock has been ahead of the newest tick decided in the last half
	-- second or so (that gap is a saw-tooth: it grows between two stream messages and drops when one comes).
	-- `late` goes up to it at once and comes down to it gently (a hiccup is not paid for for long).
	local gap = math.max(now - confirmed, 0) + Seat.MARGIN
	seat.gapNow = math.max(seat.gapNow, gap)
	if now - seat.gapSince > Seat.WINDOW or now < seat.gapSince then
		seat.gapBefore, seat.gapNow, seat.gapSince = seat.gapNow, gap, now
	end
	local most = math.max(seat.gapNow, seat.gapBefore)
	seat.late = math.min(math.max(most, seat.late - Seat.SHRINK * dt), Seat.LEAD)
	-- the far mallet: as late as that, and steadily (it never stands still or runs to make up for a hiccup)
	local farWant = now - seat.late
	if math.abs(farWant - seat.farAt) > 240 then
		seat.farAt = farWant
	else
		seat.farAt = math.min(seat.farAt + math.clamp(farWant - seat.farAt, 0.5 * dt, 1.5 * dt), now)
	end
	-- The puck (see the header). How late it must be drawn at each place of its path ahead, and the one steady
	-- rate that gets it late enough for the most demanding of them in the time left; where none asks for
	-- more than it has, or it is on its way to this player's mallet, it catches up.
	local s = seat.pred
	local r = seat.replica.sim
	local late = seat.late
	local mx, my = r.p1x, r.p1y
	if seat.side ~= 0 then
		mx, my = r.p0x, r.p0y
	end
	local at = seat.puckAt
	if math.abs(now - at) > 240 then
		at = now
	end
	local behind = now - at
	local first = math.floor(at) + 1
	local d = seat.drawn
	-- the steepest climb asked of the lateness (ticks of lateness a tick of the puck's own time): over what is
	-- believed of the puck from the moment drawn to the present...
	local slope = -math.huge
	local waiting = false
	local struck = false -- this player's own mallet has struck the puck between the moment drawn and now
	local myHit = Sim.HIT_MALLET + seat.side
	local hits = d[((first - 1) % CAP) * DRAWN + 5]
	for tick = first, seat.tick do
		local slot = tick % CAP
		if seat.drawnTick[slot + 1] ~= tick then
			break
		end
		local base = slot * DRAWN
		if d[base + 8] == 1 then
			-- (from here the puck waits for its serve: nothing is asked of it, and nothing after is looked at)
			waiting = tick == first
			break
		end
		if d[base + 5] ~= hits then
			hits = d[base + 5]
			struck = struck or d[base + 6] == myHit
		end
		-- (a place that asks for nothing asks nothing of the rate either)
		local wanted = need(seat, d[base + 1], d[base + 2], mx, my, late)
		if wanted > 0 then
			local ask = (wanted - behind) / math.max(tick - at, 1)
			if ask > slope then
				slope = ask
			end
		end
	end
	-- ...and along the way it is going, beyond the present (a straight run off the side rails; an end turns it).
	-- Only a puck going away is looked ahead for: one coming to this player is wanted as it is, now.
	local farward = if seat.side == 0 then s.vy > 0 else s.vy < 0
	if s.countdown <= 0 and s.winner < 0 and farward then
		local px, py, vx, vy = s.px, s.py, s.vx * Sim.STEP, s.vy * Sim.STEP
		local endY = Sim.HALF_LENGTH - Sim.PUCK_RADIUS
		for k = 4, Seat.LOOK, 4 do
			local y = py + vy * k
			if y > endY then
				y = 2 * endY - y
			elseif y < -endY then
				y = -2 * endY - y
			end
			local x = Sim.fold(px + vx * k, Sim.HALF_WIDTH - Sim.PUCK_RADIUS)
			local wanted = need(seat, x, y, mx, my, late)
			if wanted > 0 then
				local ask = (wanted - behind) / math.max(seat.tick + k - at, 1)
				if ask > slope then
					slope = ask
				end
			end
		end
	end
	-- never a guess: the puck is drawn no further on than the prediction is certain (or than the far mallet
	-- is drawn, where the stream is later than `late` has it)
	local sure = certain(seat, confirmed)
	local cap = math.max(if sure >= seat.tick then now else sure, farWant)
	-- how soon the puck must be the present puck: before this player's mallet can meet it (see the header)
	local mine = if seat.side == 0 then -1 else 1
	local own = (if seat.side == 0 then s.p0y else s.p1y) * mine
	local into = s.py * mine -- how far into this player's half the present puck is (metres; negative: the far half)
	local line = math.max(own - Seat.MEET, 0)
	local coming = s.vy * mine * Sim.STEP -- metres a tick toward this player's end
	local due = math.huge -- ticks until the present puck is where it must be drawn as it is
	if s.countdown > 0 or s.winner >= 0 or sure < seat.tick then
		-- (nothing is due while the puck waits, or while where it is now is only a guess)
		due = math.huge
	elseif struck or (into >= line and coming > 0) then
		due = 0
	elseif coming > 0 then
		due = (line - into) / coming
	end
	local rate: number
	if waiting then
		-- (a puck waiting for its serve is drawn now wherever it lies: this player's own serve is seen at once)
		at = math.min(now, cap)
		rate = 1
	elseif slope > 0 and due == math.huge then
		rate = 1 / (1 + slope)
	else
		-- Nothing ahead asks for more lateness than it has (or the puck is on its way to this player's mallet,
		-- which comes first): it catches up. Gently where there is time: no faster than RATE_MAX, never drawn
		-- quicker than DRAWN_MAX, the last of it eased. As fast as it takes where there is not: at the one
		-- steady rate that makes it the present puck by the time this mallet can meet it (FAST at the most).
		rate = 1 + math.min(Seat.RATE_MAX - 1, math.max(behind / Seat.LAND, Seat.LAND_RATE))
		local slot = math.floor(at) % CAP
		local after = (math.floor(at) + 1) % CAP
		if seat.drawnTick[slot + 1] == math.floor(at) and seat.drawnTick[after + 1] == math.floor(at) + 1 then
			local dx = d[after * DRAWN + 1] - d[slot * DRAWN + 1]
			local dy = d[after * DRAWN + 2] - d[slot * DRAWN + 2]
			local speed = math.sqrt(dx * dx + dy * dy) / Sim.STEP
			if speed * rate > Seat.DRAWN_MAX then
				rate = math.max(1, Seat.DRAWN_MAX / speed)
			end
		end
		if due < math.huge then
			rate = math.max(rate, math.min(1 + behind / math.max(due, 0.5 * dt), Seat.FAST))
		end
		-- (and no faster than keeps it late enough at every place between the moment drawn and now)
		if slope > -1 and due == math.huge then
			rate = math.min(rate, 1 / (1 + slope))
		end
	end
	local next = at + rate * dt
	-- the edge of what is certain: slowed into it, never run into it (and never past it)
	local room = cap - at
	if cap < now and rate * dt > room then
		seat.held += 1
		next = at + math.max(math.min(room, room * dt / Seat.BRAKE), 0)
	end
	next = math.min(next, now, cap)
	seat.puckAt = math.max(seat.puckAt, next)
	if math.abs(now - seat.puckAt) > 240 then
		seat.puckAt = math.min(now, cap)
	end
	-- (and never later than the far end is drawn)
	seat.puckAt = math.max(seat.puckAt, seat.farAt)
end

function Seat.step(
	seat: Seat,
	now: number,
	send: (from: number, to: number, strings: { string }) -> (),
	onTick: ((sim: Sim.State, tick: number, hit: boolean, goal: boolean, served: boolean) -> ())?,
	onConfirmed: ((sim: Sim.State, tick: number, hit: boolean, goal: boolean, served: boolean) -> ())?
)
	local r = seat.replica
	-- where things were drawn, to ease out whatever the referee's word changes under them
	local wasReady = seat.ready
	local bx, by, bfx, bfy = 0, 0, 0, 0
	if wasReady then
		bx, by, bfx, bfy = drawnNow(seat)
	end
	Replica.step(r, nil, function(sim: Sim.State, tick: number, hit: boolean, goal: boolean, served: boolean)
		-- (what the referee decided of a tick replaces what was predicted of it)
		believe(seat, tick, sim)
		if onConfirmed then
			onConfirmed(sim, tick, hit, goal, served)
		end
	end)
	if r.head ~= seat.headWas then
		seat.headWas, seat.wordAt = r.head, now
	end
	if seat.from == nil or r.game == nil or r.game ~= seat.game then
		return
	end
	local confirmed = r.tick
	local snapped = false
	if not seat.ready then
		-- the first state of this match: predict from it
		seat.ready = true
		seat.jumps = r.jumps
		rebuild(seat)
		seat.told = seat.tick
		snapped = true
	elseif r.jumps ~= seat.jumps or confirmed > seat.tick then
		-- the referee is somewhere this prediction is not (a gap in the stream, or it is ahead of us)
		seat.jumps = r.jumps
		rebuild(seat)
		seat.told = math.max(seat.told, seat.tick)
		-- (the referee may hold another aim for this mallet than the hand's: the hand is logged afresh)
		seat.lastX, seat.lastY = nil, nil
		snapped = true
	elseif r.mode ~= seat.mode or seat.stale or not predicted(seat, confirmed, r.sim) then
		seat.resims += 1
		local mode = seat.mode
		rebuild(seat)
		if mode ~= seat.mode then
			-- (the other end changed hands: the moments drawn start afresh)
			seat.puckAt, seat.farAt, seat.late = seat.clock, seat.clock, 0
		end
	end
	if snapped then
		seat.ex, seat.ey, seat.ox, seat.oy = 0, 0, 0, 0
		seat.puckAt, seat.farAt, seat.late, seat.clock = now, now, 0, now
		seat.gapNow, seat.gapBefore, seat.gapSince = 0, 0, now
		seat.heardTo = seat.tick
	elseif wasReady then
		local ax, ay, afx, afy = drawnNow(seat)
		seat.ex += bx - ax
		seat.ey += by - ay
		seat.ox += bfx - afx
		seat.oy += bfy - afy
		if seat.ex * seat.ex + seat.ey * seat.ey > Seat.SNAP * Seat.SNAP then
			-- (the puck was served, or scored: nobody slides it there)
			seat.ex, seat.ey = 0, 0
		end
		if seat.ox * seat.ox + seat.oy * seat.oy > Seat.SNAP * Seat.SNAP then
			seat.ox, seat.oy = 0, 0
		end
	end
	seat.stale = false
	-- the log before the referee's tick is history
	for tick in seat.log do
		if tick <= confirmed and tick <= seat.sentTo then
			seat.log[tick] = nil
		end
	end
	for tick in seat.theirs do
		if tick <= confirmed then
			seat.theirs[tick] = nil
		end
	end
	-- to the tick the clock is in the middle of: the screen shows the moment `now` itself, between the last
	-- whole tick and the one the hand is steering (nothing is drawn a tick late)
	local target: number = math.min(math.floor(now) + 1, confirmed + Seat.LEAD)
	seat.frac = math.clamp(now - (target - 1), 0, 1)
	local first = true
	while seat.tick < target and seat.pred.winner < 0 do
		local tick = seat.tick + 1
		if first and tick > seat.sentTo then
			-- the hand, as it is this frame, goes in on the first tick of the frame
			first = false
			local e: any = nil
			if seat.wantX ~= nil and (seat.wantX ~= seat.lastX or seat.wantY ~= seat.lastY) then
				e = { seat.wantX :: any, seat.wantY :: any }
				seat.lastX, seat.lastY = seat.wantX, seat.wantY
			end
			-- (a serve button counts while the puck waits; between two people only until one has been pressed)
			local waiting = seat.pred.countdown
			if seat.serving and waiting > 0 and (seat.mode ~= "2" or waiting > Sim.SERVE_LEAD) then
				e = e or { false, false }
				e[3] = true
				seat.flush = true
			end
			seat.serving = false -- (a press with no countdown running is not kept for the next one)
			if e then
				seat.log[tick] = e
			end
		end
		local hits, goals, waiting = seat.pred.hitSerial, seat.pred.goalSerial, seat.pred.countdown
		advance(seat)
		if onTick and tick > seat.told then
			seat.told = tick
			onTick(
				seat.pred,
				tick,
				seat.pred.hitSerial ~= hits,
				seat.pred.goalSerial ~= goals,
				waiting > 0 and waiting ~= math.huge and seat.pred.countdown <= 0
			)
		end
	end
	if seat.tick < target then
		-- (the match is over on this screen: the last tick is where everything stays)
		seat.frac = 1
	end
	-- the moment that is drawn: the tick the prediction is at, less what is left of it
	moments(seat, seat.tick - 1 + seat.frac, confirmed)
	-- the next segment of the log, once it is long enough (or the match is won on this screen)
	-- (a serve goes at once: the other screen must hear of it before the puck leaves. While nothing comes back
	-- from the server the segments are long: a stalled line is not handed dozens of messages to deliver at once)
	local length = if seat.mode == "2" then Wire.SEGMENT_DUO else Wire.SEGMENT_SOLO
	if now - seat.wordAt > Wire.QUIET then
		length = Wire.SEGMENT_QUIET
	end
	local upTo = math.min(seat.tick, seat.sentTo + Wire.MAX_SEGMENT)
	if upTo > seat.sentTo and (upTo - seat.sentTo >= length or seat.pred.winner >= 0 or seat.flush) then
		seat.flush = false
		local events: { [number]: any } = {}
		for tick, e in seat.log do
			if tick > seat.sentTo and tick <= upTo then
				events[tick] = e
			end
		end
		send(seat.sentTo, upTo, Wire.pack(events, seat.sentTo))
		seat.sentTo = upTo
	end
end

-- The eased corrections die away (call once a frame).
function Seat.relax(seat: Seat, dt: number)
	local k = math.exp(-dt / Seat.EASE)
	seat.ex *= k
	seat.ey *= k
	seat.ox *= k
	seat.oy *= k
end

-- Where everything is drawn now (puck x, y, Glacier's mallet x, y, Ember's mallet x, y): this player's own
-- mallet at the moment of the clock, between the last whole tick and the next; the puck and the far mallet as
-- the header says, with whatever correction is still easing out.
function Seat.view(seat: Seat): (number, number, number, number, number, number)
	local p, s, f = seat.prev, seat.pred, seat.frac
	local px, py, fx, fy = drawnNow(seat)
	px, py, fx, fy = px + seat.ex, py + seat.ey, fx + seat.ox, fy + seat.oy
	if seat.side == 0 then
		return px, py, p[3] + (s.p0x - p[3]) * f, p[4] + (s.p0y - p[4]) * f, fx, fy
	end
	return px, py, fx, fy, p[5] + (s.p1x - p[5]) * f, p[6] + (s.p1y - p[6]) * f
end

-- The contacts the drawn puck has passed since the last call: fn(what, speed) for each (Sim.HIT_RAIL, HIT_POST,
-- HIT_MALLET + side; metres a second along the normal). A contact is heard when it is seen.
function Seat.heard(seat: Seat, fn: (what: number, speed: number) -> ())
	local at = if seat.mode == "2" then seat.puckAt else seat.tick - 1 + seat.frac
	local upTo = math.min(math.floor(at), seat.tick)
	if upTo - seat.heardTo > 240 then
		seat.heardTo = upTo - 240
	end
	local d = seat.drawn
	while seat.heardTo < upTo do
		local tick = seat.heardTo + 1
		local s0, s1 = seat.heardTo % CAP, tick % CAP
		if
			seat.drawnTick[s0 + 1] == seat.heardTo
			and seat.drawnTick[s1 + 1] == tick
			and d[s1 * DRAWN + 5] ~= d[s0 * DRAWN + 5]
		then
			fn(d[s1 * DRAWN + 6], d[s1 * DRAWN + 7])
		end
		seat.heardTo = tick
	end
end

return Seat
