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
--       - the puck: in the far half as late as the far mallet (so a strike at the far end is seen: the puck
--         comes off the mallet that struck it), in this half now (so what this hand strikes is what is seen,
--         and a shot leaves this mallet at its true speed). In between, the moment drawn moves smoothly: past
--         the centre line a puck sent away is drawn slowed (never under SLOW of its speed) until it is as late
--         as the far end; a puck coming back is drawn quickened (FAST: a streak of two or three frames) along
--         the path it really took until it is the present puck, as soon as the referee's word of the strike
--         is here, because the time left to meet it is what matters most. No part of a shot is skipped.
--       - and never a guess: the puck is drawn no further on than the prediction is CERTAIN, which is as far
--         as the far mallet, wherever its hand went, cannot have touched the puck (certain()). Up to there
--         the prediction is the referee's match to be, because everything else in it is this player's own
--         hand and the table.
--     So what is on a player's screen against a person is the referee's match: this end now, the far end a
--     moment ago. One thing is still a guess, because it is no mallet's doing: that the other player has not
--     just served (Space during the countdown). If they have, the puck is found a little way along its serve
--     when the referee's word comes, and it is eased there over EASE seconds, as any correction under the
--     moment drawn would be.
-- Pure (no engine): the client's controller feeds it the clock, the hand and the stream; specs and the netcode
-- measurements (tools/games/air_hockey/netcode.luau) drive it the same way.
-- Interface: new(side) -> Seat; begin(seat, game, from) (the referee's word that this seat's log starts at tick
--   `from` of match `game`); push(seat, msg) (a stream message); aim(seat, x, y) (the hand, model metres);
--   serve(seat); step(seat, now, send, onTick?, onConfirmed?) (now: the shared clock's tick, fractional;
--   send(from, to, strings); onTick(sim, tick, hit, goal) for each newly predicted tick; onConfirmed the same
--   for each tick the referee decided); view(seat) -> (puck x, y, mallet0 x, y, mallet1 x, y) as drawn now;
--   heard(seat, fn) (fn(what, speed) for each contact the drawn puck has just passed: Sim.HIT_*, m/s);
--   relax(seat, dt); Seat.pred / .tick / .replica / .resims / .ready; Seat.puckAt / .farAt (the ticks the puck
--   and the far mallet are drawn at) / .late; EASE; LEAD; SLOW; FAST

local Replica = require("./Replica")
local Sim = require("./Sim")
local Wire = require("./Wire")

local Seat = {}

Seat.EASE = 0.07 -- seconds: the time constant a correction of the drawn puck is eased out over
Seat.SNAP = 0.6 -- metres: a correction larger than this is not eased (the puck was served, or scored)
Seat.LEAD = 480 -- ticks the prediction may run ahead of the referee's last word (2 s: then it waits)
Seat.SLOW = 0.4 -- against a person: a puck going away is drawn at no less than this much of its speed...
Seat.FAST = 6 -- ...and one coming back at no more than this much, while the moment drawn changes
Seat.MARGIN = 2 -- ticks the far end is drawn behind the newest the stream has brought at its latest
Seat.SHRINK = 0.15 -- how fast `late` comes down when the stream is earlier than it was (ticks a tick)
Seat.WINDOW = 72 -- ticks: the stream's lateness is the most it has been over the last one to two of these
Seat.BLEND = 0.25 -- metres past the centre line over which the puck goes from now to as late as the far end
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
	local e = seat.log[tick]
	if e then
		if e[3] and sim.countdown > 0 then
			Sim.serve(sim)
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
	-- the puck: now where this hand can reach it, as late as the far mallet where that one can. Where the
	-- present puck is believed to be says which: past the centre line it is the far end's; on this side of
	-- it, or about to be before a quickened puck could be brought to the present, it is this end's.
	local s = seat.pred
	local far = if seat.side == 0 then 1 else -1
	local q, vq = s.py * far, s.vy * far
	if vq < 0 and s.countdown <= 0 then
		q += vq * Sim.STEP * seat.late / (Seat.FAST - 1)
	end
	local w = math.clamp(q / Seat.BLEND, 0, 1)
	w = w * w * (3 - 2 * w)
	if s.countdown > 0 then
		-- (a puck waiting for its serve is drawn now wherever it lies: this player's own serve is seen at once)
		w = 0
	end
	local want = now - seat.late * w
	-- never a guess: the puck is drawn no further on than the prediction is certain (or than the far mallet
	-- is drawn, where the stream is later than `late` has it)
	local sure = certain(seat, confirmed)
	local cap = math.max(if sure >= seat.tick then now else sure, farWant)
	if math.abs(want - seat.puckAt) > 240 then
		seat.puckAt = math.min(want, cap)
	else
		local next = seat.puckAt + math.clamp(want - seat.puckAt, Seat.SLOW * dt, Seat.FAST * dt)
		seat.puckAt = math.max(seat.puckAt, math.min(next, now, cap))
	end
	-- (and never later than the far end is drawn)
	seat.puckAt = math.max(seat.puckAt, seat.farAt)
end

function Seat.step(
	seat: Seat,
	now: number,
	send: (from: number, to: number, strings: { string }) -> (),
	onTick: ((sim: Sim.State, tick: number, hit: boolean, goal: boolean) -> ())?,
	onConfirmed: ((sim: Sim.State, tick: number, hit: boolean, goal: boolean) -> ())?
)
	local r = seat.replica
	-- where things were drawn, to ease out whatever the referee's word changes under them
	local wasReady = seat.ready
	local bx, by, bfx, bfy = 0, 0, 0, 0
	if wasReady then
		bx, by, bfx, bfy = drawnNow(seat)
	end
	Replica.step(r, nil, function(sim: Sim.State, tick: number, hit: boolean, goal: boolean)
		-- (what the referee decided of a tick replaces what was predicted of it)
		believe(seat, tick, sim)
		if onConfirmed then
			onConfirmed(sim, tick, hit, goal)
		end
	end)
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
	elseif r.mode ~= seat.mode or not predicted(seat, confirmed, r.sim) then
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
	-- the log before the referee's tick is history
	for tick in seat.log do
		if tick <= confirmed and tick <= seat.sentTo then
			seat.log[tick] = nil
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
			if seat.serving and seat.pred.countdown > 0 then
				e = e or { false, false }
				e[3] = true
			end
			seat.serving = false -- (a press with no countdown running is not kept for the next one)
			if e then
				seat.log[tick] = e
			end
		end
		local hits, goals = seat.pred.hitSerial, seat.pred.goalSerial
		advance(seat)
		if onTick and tick > seat.told then
			seat.told = tick
			onTick(seat.pred, tick, seat.pred.hitSerial ~= hits, seat.pred.goalSerial ~= goals)
		end
	end
	if seat.tick < target then
		-- (the match is over on this screen: the last tick is where everything stays)
		seat.frac = 1
	end
	-- the moment that is drawn: the tick the prediction is at, less what is left of it
	moments(seat, seat.tick - 1 + seat.frac, confirmed)
	-- the next segment of the log, once it is long enough (or the match is won on this screen)
	local length = if seat.mode == "2" then Wire.SEGMENT_DUO else Wire.SEGMENT_SOLO
	local upTo = math.min(seat.tick, seat.sentTo + Wire.MAX_SEGMENT)
	if upTo > seat.sentTo and (upTo - seat.sentTo >= length or seat.pred.winner >= 0) then
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
