--!strict
-- ReplicatedStorage.Shared.Minigames.Pinball.Shots
-- A table's shot book: what can be hit from each flipper, and how exact the timing has to be. This is the
-- number a pinball table is designed by. A shot worth building a rule on must be makeable by timing alone, and
-- a player's screen shows 60 frames a second (four ticks each), so a main shot needs a window of two frames or
-- more; a window of a tick or two is luck.
-- The book is measured, not declared: for each flipper a ball is cradled on the raised flipper, let go, and
-- the flipper is pressed after every possible delay in turn. Each trial plays on until the ball has hit
-- something (or come back down) and notes what it reached: a ramp made, a kick-out hole, a target, a lane, a
-- spinner, a bumper. A run of delays one after the other that all reach the same thing is that shot's window.
-- The calibrate tool prints the book; the specs hold each table's main shots to a fair window; the WIZARD
-- computer player (Bot) aims by it, as a good player aims by what they have learnt of a machine.
-- What a shot reaches is named by a key: Machine.key(event code, element number), the event being the one the
-- physics reports (Physics.EV: RAIL_OUT for a ramp made, SAUCER, STANDUP, DROP, ROLLOVER, SPINNER, BUMPER).
-- Pure (a book is a pure function of the table; it is worked out once per table and kept).
-- Lune-tested (tests/unit/pinball_shots.spec.luau).
-- Interface: book(table) -> Book; best(book, key, flipper?) -> Window?; name(table, key) -> string;
--   FAIR_TICKS; types Book, Window, Trial

local Det = require("./Det")
local Machine = require("./Machine")
local Physics = require("./Physics")

local Shots = {}

Shots.FAIR_TICKS = 8 -- two frames of a 60 Hz screen: a window this wide can be hit by timing
Shots.FIRST_DELAY = 30
Shots.LAST_DELAY = 300
Shots.HOLD_TICKS = 40 -- how long a trial keeps the button down
Shots.FLIGHT_TICKS = 840 -- a trial is over after this long whatever happened

export type Trial = {
	delay: number, -- ticks from letting the cradled ball go to pressing the button
	along: number, -- where the ball was on the flipper when the button went down (0 pivot, 1 tip)
	speed: number, -- how fast it left
	angle: number, -- degrees from straight up the table, + across the table (0 / 0 when it never left)
	keys: { number }, -- what it reached, in order
}
export type Window = {
	key: number,
	flipper: number,
	from: number, -- first and last delay of the run
	to: number,
	ticks: number, -- the width of the window
	along: number, -- where the ball is on the flipper in the middle of the window: the spot to flip at
	speed: number,
	angle: number,
}
export type Book = {
	id: string,
	trials: { { Trial } }, -- per flipper
	windows: { { [number]: Window } }, -- per flipper: the widest window for each key
	keys: { number }, -- every key some flipper can reach, widest window first
}

local EV = Physics.EV
local BTN = Machine.BTN
local FREE = Physics.FREE
local key = Machine.key

-- the events that say a shot arrived somewhere, and whether the ball flies on afterwards
local REACH: { [number]: boolean } = {
	[EV.ROLLOVER] = true, -- a switch in the floor: the ball rolls on
	[EV.SPINNER] = true,
	[EV.BUMPER] = false,
	[EV.STANDUP] = false,
	[EV.DROP] = false,
	[EV.SAUCER] = false,
}

local BOOKS: { [string]: Book } = {}

-- A machine with one ball asleep in the cradle of flipper i, the flipper held up.
local function cradled(tbl: Machine.Table, i: number): Machine.State?
	local c = tbl.c
	local button = if c.fbtn[i] == 1 then BTN.LEFT else BTN.RIGHT
	local m = Machine.new(tbl, 7, 1)
	local lane = tbl.def.sensors[if c.fbtn[i] == 1 then tbl.ix.sensor.inlane_l else tbl.ix.sensor.inlane_r]
	local ball = m.phys.balls[1]
	ball.x = (lane.x1 + lane.x2) / 2
	ball.y = lane.y1 + 0.2
	m.launched = true
	local out: { number } = {}
	for _ = 1, 2400 do
		Machine.step(tbl, m, button, out)
		local b = m.phys.balls[1]
		if b == nil then
			return nil
		elseif b.asleep then
			return m
		end
	end
	return nil
end

local function trial(tbl: Machine.Table, base: Machine.State, i: number, delay: number): Trial?
	local c = tbl.c
	local m = Machine.clone(base)
	local phys = m.phys
	local out: { number } = {}
	for _ = 1, delay do
		Machine.step(tbl, m, 0, out)
	end
	local b = phys.balls[1]
	if b == nil or m.phase ~= Machine.PHASE.PLAY then
		return nil
	end
	local rest = c.frest[i]
	local along = ((b.x - c.fpx[i]) * c.fmir[i] * Det.cos(rest) + (b.y - c.fpy[i]) * Det.sin(rest)) / c.flen[i]
	local tr: Trial = { delay = delay, along = along, speed = 0, angle = 0 / 0, keys = {} }
	local ev: { number } = {}
	local line = c.fpy[i] + 0.4
	-- the physics is stepped directly from here on, so that its own events can be read
	for k = 1, Shots.FLIGHT_TICKS do
		table.clear(ev)
		local held = k <= Shots.HOLD_TICKS
		Physics.step(c, phys, held and c.fbtn[i] == 1, held and c.fbtn[i] == 2, ev)
		for e = 1, #ev, 4 do
			local code, ref, value = ev[e], ev[e + 1], ev[e + 2]
			if code == EV.RAIL_OUT then
				if value == 1 then
					table.insert(tr.keys, key(code, ref))
				end
				return tr
			elseif code == EV.DRAIN or code == EV.SLING then
				return tr
			elseif REACH[code] ~= nil then
				local kk = key(code, ref)
				if table.find(tr.keys, kk) == nil then
					table.insert(tr.keys, kk)
				end
				if not REACH[code] then
					return tr
				end
			end
		end
		if b.mode == FREE then
			if tr.angle ~= tr.angle then
				if b.y > line and b.vy > 0 then
					tr.angle = math.deg(math.atan2(b.vx * c.fmir[i], b.vy))
					tr.speed = math.sqrt(b.vx * b.vx + b.vy * b.vy)
				elseif k > Shots.HOLD_TICKS + 60 then
					return tr -- it never left the flipper
				end
			elseif b.y < line and b.vy < 0 then
				return tr -- back down at the flippers
			end
		end
	end
	return tr
end

-- book(table): measure the table. About half a second of work per table, once.
function Shots.book(tbl: Machine.Table): Book
	local known = BOOKS[tbl.id]
	if known then
		return known
	end
	local book: Book = { id = tbl.id, trials = {}, windows = {}, keys = {} }
	for i = 1, tbl.c.nFlip do
		local trials: { Trial } = {}
		local windows: { [number]: Window } = {}
		book.trials[i] = trials
		book.windows[i] = windows
		local base = cradled(tbl, i)
		if base == nil then
			continue
		end
		for delay = Shots.FIRST_DELAY, Shots.LAST_DELAY do
			local tr = trial(tbl, base, i, delay)
			if tr == nil or tr.along > 1.08 then
				break
			end
			table.insert(trials, tr)
		end
		-- runs: for each key, the longest run of trials one after the other that reached it
		local runFrom: { [number]: number } = {}
		local function close(kk: number, from: number, to: number)
			local ticks = to - from + 1
			local have = windows[kk]
			if have == nil or ticks > have.ticks then
				local mid = trials[(from + to) // 2]
				windows[kk] = {
					key = kk,
					flipper = i,
					from = trials[from].delay,
					to = trials[to].delay,
					ticks = ticks,
					along = mid.along,
					speed = mid.speed,
					angle = mid.angle,
				}
			end
		end
		for n, tr in trials do
			for _, kk in tr.keys do
				if runFrom[kk] == nil then
					runFrom[kk] = n
				end
			end
			for kk, from in runFrom do
				if table.find(tr.keys, kk) == nil then
					close(kk, from, n - 1)
					runFrom[kk] = nil
				end
			end
		end
		for kk, from in runFrom do
			close(kk, from, #trials)
		end
	end
	local widest: { [number]: number } = {}
	for i = 1, tbl.c.nFlip do
		for kk, w in book.windows[i] do
			if widest[kk] == nil then
				table.insert(book.keys, kk)
				widest[kk] = w.ticks
			elseif w.ticks > widest[kk] then
				widest[kk] = w.ticks
			end
		end
	end
	table.sort(book.keys, function(a, b)
		if widest[a] ~= widest[b] then
			return widest[a] > widest[b]
		end
		return a < b
	end)
	BOOKS[tbl.id] = book
	return book
end

-- best(book, key, flipper): the window for a key from one flipper, or (no flipper given) from whichever
-- flipper has the wider one.
function Shots.best(book: Book, kk: number, flipper: number?): Window?
	if flipper then
		return book.windows[flipper][kk]
	end
	local best: Window? = nil
	for i = 1, #book.windows do
		local w = book.windows[i][kk]
		if w and (best == nil or w.ticks > best.ticks) then
			best = w
		end
	end
	return best
end

-- name(table, key): what a key is called on this table ("wire", "bite", "acorn_a", "bumper_2", ...).
function Shots.name(tbl: Machine.Table, kk: number): string
	local code, ref = kk // 1000, kk % 1000
	local def = tbl.def
	if code == EV.RAIL_OUT then
		return def.rails[ref].id
	elseif code == EV.SAUCER then
		return def.saucers[ref].id
	elseif code == EV.STANDUP or code == EV.DROP then
		return def.targets[ref].id
	elseif code == EV.ROLLOVER or code == EV.SPINNER then
		return def.sensors[ref].id
	elseif code == EV.BUMPER then
		return def.bumpers[ref].id
	end
	return `{code}:{ref}`
end

return Shots
