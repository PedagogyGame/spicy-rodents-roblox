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
--     ticks), and the difference in where the puck and the far mallet are drawn is eased out over EASE seconds
--     instead of jumping. The player's own mallet is never moved by a correction of the other's hand.
-- Pure (no engine): the client's controller feeds it the clock, the hand and the stream; specs and the netcode
-- measurements (tools/games/air_hockey/netcode.luau) drive it the same way.
-- Interface: new(side) -> Seat; begin(seat, game, from) (the referee's word that this seat's log starts at tick
--   `from` of match `game`); push(seat, msg) (a stream message); aim(seat, x, y) (the hand, model metres);
--   serve(seat); step(seat, now, send, onTick?, onConfirmed?) (now: the shared clock's tick, fractional;
--   send(from, to, strings); onTick(sim, tick, hit, goal) for each newly predicted tick; onConfirmed the same
--   for each tick the referee decided); view(seat) -> (puck x, y, mallet0 x, y, mallet1 x, y) as drawn now;
--   relax(seat, dt); Seat.pred / .tick / .replica / .resims / .ready; EASE; LEAD

local Replica = require("./Replica")
local Sim = require("./Sim")
local Wire = require("./Wire")

local Seat = {}

Seat.EASE = 0.07 -- seconds: the time constant a correction of the drawn puck is eased out over
Seat.SNAP = 0.6 -- metres: a correction larger than this is not eased (the puck was served, or scored)
Seat.LEAD = 480 -- ticks the prediction may run ahead of the referee's last word (2 s: then it waits)
local CAP = 1024 -- ticks of past predictions kept
local WIDTH = #Wire.STATE

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

local function remember(seat: Seat)
	local slot = seat.tick % CAP
	seat.histTick[slot + 1] = seat.tick
	local s = seat.pred :: any
	local base = slot * WIDTH
	local hist = seat.hist
	for i, k in Wire.STATE do
		hist[base + i] = s[k]
	end
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
-- prediction had got to. What is drawn does not jump: the difference is carried in the eased offsets.
local function rebuild(seat: Seat, ease: boolean)
	local r = seat.replica
	local was = seat.tick
	local px, py = seat.pred.px, seat.pred.py
	local ox, oy
	if seat.side == 0 then
		ox, oy = seat.pred.p1x, seat.pred.p1y
	else
		ox, oy = seat.pred.p0x, seat.pred.p0y
	end
	Sim.copy(seat.pred, r.sim)
	seat.tick = r.tick
	seat.mode = r.mode
	remember(seat)
	keep(seat)
	while seat.tick < was and seat.pred.winner < 0 do
		advance(seat)
	end
	if ease and seat.tick == was then
		local nx, ny
		if seat.side == 0 then
			nx, ny = seat.pred.p1x, seat.pred.p1y
		else
			nx, ny = seat.pred.p0x, seat.pred.p0y
		end
		seat.ex += px - seat.pred.px
		seat.ey += py - seat.pred.py
		seat.ox += ox - nx
		seat.oy += oy - ny
		if seat.ex * seat.ex + seat.ey * seat.ey > Seat.SNAP * Seat.SNAP then
			seat.ex, seat.ey = 0, 0
		end
	else
		seat.ex, seat.ey, seat.ox, seat.oy = 0, 0, 0, 0
	end
end

function Seat.step(
	seat: Seat,
	now: number,
	send: (from: number, to: number, strings: { string }) -> (),
	onTick: ((sim: Sim.State, tick: number, hit: boolean, goal: boolean) -> ())?,
	onConfirmed: ((sim: Sim.State, tick: number, hit: boolean, goal: boolean) -> ())?
)
	local r = seat.replica
	Replica.step(r, nil, onConfirmed)
	if seat.from == nil or r.game == nil or r.game ~= seat.game then
		return
	end
	local confirmed = r.tick
	if not seat.ready then
		-- the first state of this match: predict from it
		seat.ready = true
		seat.jumps = r.jumps
		rebuild(seat, false)
		seat.told = seat.tick
	elseif r.jumps ~= seat.jumps or confirmed > seat.tick then
		-- the referee is somewhere this prediction is not (a gap in the stream, or it is ahead of us)
		seat.jumps = r.jumps
		rebuild(seat, false)
		seat.told = math.max(seat.told, seat.tick)
		-- (the referee may hold another aim for this mallet than the hand's: the hand is logged afresh)
		seat.lastX, seat.lastY = nil, nil
	elseif r.mode ~= seat.mode or not predicted(seat, confirmed, r.sim) then
		seat.resims += 1
		rebuild(seat, true)
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

-- Where everything is drawn now: the moment of the clock, between the last whole tick and the next (both
-- predicted), the puck and the far mallet with whatever correction is still easing out. (puck x, y, Glacier's mallet x, y, Ember's mallet x, y)
function Seat.view(seat: Seat): (number, number, number, number, number, number)
	local p, s, f = seat.prev, seat.pred, seat.frac
	local px = p[1] + (s.px - p[1]) * f + seat.ex
	local py = p[2] + (s.py - p[2]) * f + seat.ey
	local ax, ay = p[3] + (s.p0x - p[3]) * f, p[4] + (s.p0y - p[4]) * f
	local bx, by = p[5] + (s.p1x - p[5]) * f, p[6] + (s.p1y - p[6]) * f
	-- (a puck that is put back on its spot within this tick is not slid there from the goal: it is at whichever
	-- end of the tick the clock is nearer)
	if math.abs(s.px - p[1]) + math.abs(s.py - p[2]) > 0.2 then
		if f < 0.5 then
			px, py = p[1] + seat.ex, p[2] + seat.ey
		else
			px, py = s.px + seat.ex, s.py + seat.ey
		end
	end
	if seat.side == 0 then
		bx, by = bx + seat.ox, by + seat.oy
	else
		ax, ay = ax + seat.ox, ay + seat.oy
	end
	return px, py, ax, ay, bx, by
end

return Seat
