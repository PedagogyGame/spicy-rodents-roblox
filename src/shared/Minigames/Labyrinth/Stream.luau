--!strict
-- ReplicatedStorage.Shared.Minigames.Labyrinth.Stream
-- What a client draws and hears from. Bowling sends one finished script per throw; the labyrinth is live, so
-- its "script" is the state stream itself: a snapshot to start from and then the input log in pieces. Whoever
-- holds those can step the same Run and gets, tick for tick, the board and marble the player had (LAB-S4).
--   the player    steps Run from the keys, then asks pose() and cues() for what to show and play;
--   a watcher     keeps a Watch: push() each relayed piece, advance() every frame; it plays a moment behind
--                 (BUFFER ticks) so that pieces arriving in bursts still move smoothly, hurries when it has
--                 fallen behind, and simply waits when nothing has come;
--   a ghost       is a Watch loaded with a whole recorded log (the day's record on the clipboard) and no delay.
-- pose() turns a state into things to draw: where the marble is and how high it sits (it sinks as it tips over
-- a rim), the board's two tilts, how far each knob has turned (LAB-C4), and, while a dropped marble is away,
-- how far along its roll home through the box it is. cues() names the sounds of the tick just played, with a
-- loudness and pitch taken from the model (LAB-S3): the click of a wall by how hard it was hit, the wooden
-- rumble by how fast the marble rolls.
-- Pure; Lune-tested (tests/unit/labyrinth_pilot.spec.luau).
-- Interface: BUFFER, HURRY, STALL, CUES; pose(board, run, before?, alpha?) -> Pose; cues(board, run) -> { Cue };
--   rumble(run) -> (volume 0..1, pitch); watch(snapshot or nil, board?, hold?) -> Watch?; push(watch, start,
--   text) -> (ok, why?); advance(watch, dt) -> ticks played (cues gather in watch.cues); ghost(board, hold,
--   log) -> Watch?; boardOf(watch) -> Board

local Boards = require("./Boards")
local Controls = require("./Controls")
local InputLog = require("./InputLog")
local Physics = require("./Physics")
local Run = require("./Run")

local Stream = {}

Stream.BUFFER = 12 -- ticks a watcher stays behind the newest piece (0.2 s)
Stream.HURRY = 45 -- with more than this many ticks waiting, a watcher plays two for one until it has caught up
Stream.STALL = 0.4 -- seconds a watcher waits for a full buffer before playing what it has (the end of a run)
Stream.MAX_WAITING = 1200 -- a watcher never holds more than this (a sender flooding it is cut off)

-- every sound the game makes (MinigameSounds cue names; docs/AUDIO_BUDGET lists them when they are wired)
Stream.CUES = table.freeze({
	start = "labyrinth_start", -- the first key: the clock is running
	roll = "labyrinth_roll", -- the marble's wooden rumble (a loop: see rumble())
	click = "labyrinth_click", -- a wall
	plonk = "labyrinth_plonk", -- down a hole
	home = "labyrinth_home", -- rolling back inside the box to the tray
	back = "labyrinth_back", -- the marble set back on its checkpoint
	number = "labyrinth_number", -- a new number reached
	bell = "labyrinth_bell", -- the reception bell at the finish
	timeout = "labyrinth_timeout",
})

export type Pose = {
	x: number, -- the marble, board frame
	y: number,
	lift: number, -- its centre's height above the board's surface (its radius on the flat, less over a rim)
	shown: boolean, -- on the board (false: down a hole, or in the cup)
	inCup: boolean,
	tiltX: number, -- degrees; + tips the right side down
	tiltY: number, -- + tips the far side down
	knobLeft: number, -- degrees each knob has turned
	knobRight: number,
	speed: number,
	touching: boolean, -- it touched a wall this tick
	home: number, -- 0..1 through the roll home while it is away (0 otherwise)
	fromX: number, -- the hole it went down and the checkpoint it is coming back to
	fromY: number,
	toX: number,
	toY: number,
}
export type Cue = { name: string, volume: number, pitch: number }

function Stream.pose(board: Boards.Board, run: Run.State, before: Run.State?, alpha: number?): Pose
	local m = run.m
	local x, y, tx, ty = m.x, m.y, m.tx, m.ty
	local a = alpha or 1
	if before and a < 1 then
		local b = before.m
		tx = b.tx + (tx - b.tx) * a
		ty = b.ty + (ty - b.ty) * a
		if b.on == 1 and m.on == 1 and run.phase == before.phase then
			x = b.x + (x - b.x) * a
			y = b.y + (y - b.y) * a
		end
	end
	local R = board.marbleR
	local depth = math.min(m.rim, 1) * R
	local knobLeft, knobRight = Controls.knobs(tx, ty)
	local cp = board.checkpoints[run.checkpoint]
	local home, fromX, fromY = 0, cp.x, cp.y
	if run.phase == Run.PHASE.RETURNING then
		home = math.clamp(1 - run.wait / Run.RETURN_TICKS, 0, 1)
		fromX, fromY = board.hx[run.hole], board.hy[run.hole]
	end
	return {
		x = x,
		y = y,
		lift = math.sqrt(R * R - depth * depth),
		shown = m.on == 1,
		inCup = run.phase == Run.PHASE.FINISHED,
		tiltX = tx,
		tiltY = ty,
		knobLeft = knobLeft,
		knobRight = knobRight,
		speed = math.sqrt(m.vx * m.vx + m.vy * m.vy),
		touching = m.touch == 1,
		home = home,
		fromX = fromX,
		fromY = fromY,
		toX = cp.x,
		toY = cp.y,
	}
end

-- The rumble loop's loudness and pitch for the marble as it is now: silent at rest or off the board, louder
-- and higher with speed.
function Stream.rumble(run: Run.State): (number, number)
	local m = run.m
	if m.on == 0 then
		return 0, 1
	end
	local speed = math.sqrt(m.vx * m.vx + m.vy * m.vy)
	if speed < 0.03 then
		return 0, 1
	end
	local share = math.min(speed / 3, 1)
	return 0.15 + 0.85 * share, 0.8 + 0.6 * share
end

local function has(ev: number, bit: number): boolean
	return bit32.band(ev, bit) ~= 0
end

-- The one-shot sounds of the tick just played.
function Stream.cues(_board: Boards.Board, run: Run.State): { Cue }
	local out: { Cue } = {}
	local ev, EV, C = run.ev, Run.EV, Stream.CUES
	if has(ev, EV.START) then
		table.insert(out, { name = C.start, volume = 0.5, pitch = 1 })
	end
	if run.m.hit > 0 then
		local share = math.min(run.m.hit / 3, 1)
		table.insert(out, { name = C.click, volume = 0.2 + 0.8 * share, pitch = 0.9 + 0.3 * share })
	end
	if has(ev, EV.NUMBER) then
		table.insert(out, { name = C.number, volume = 0.4, pitch = 1 })
	end
	if has(ev, EV.FELL) then
		table.insert(out, { name = C.plonk, volume = 1, pitch = 1 })
		table.insert(out, { name = C.home, volume = 0.7, pitch = 1 })
	end
	if has(ev, EV.RETURNED) then
		table.insert(out, { name = C.back, volume = 0.6, pitch = 1 })
	end
	if has(ev, EV.FINISH) then
		table.insert(out, { name = C.plonk, volume = 0.8, pitch = 1.2 })
		table.insert(out, { name = C.bell, volume = 1, pitch = 1 })
	end
	if has(ev, EV.TIMEOUT) then
		table.insert(out, { name = C.timeout, volume = 0.8, pitch = 1 })
	end
	return out
end

export type Watch = {
	level: number,
	run: Run.State,
	before: Run.State, -- the state one tick earlier (pose() blends the two)
	waiting: { number }, -- codes received and not yet played
	head: number, -- the next of them to play
	next: number, -- the tick the next piece must start at
	debt: number, -- seconds of time not yet turned into ticks
	buffer: number,
	hurry: boolean, -- false for a ghost: a recording is played at its own pace
	stalled: number, -- seconds it has waited with less than a buffer in hand
	started: boolean, -- it has begun playing (it waits for BUFFER ticks first)
	cues: { Cue }, -- one-shot sounds since the caller last emptied it
}

-- A watcher of a live run. With a snapshot (what the server sends someone who arrives mid-run) it starts from
-- there; without one it starts a fresh run on `board` with `hold`. nil when the snapshot is not one.
function Stream.watch(snapshot: any, board: Boards.Board?, hold: number?): Watch?
	local run: Run.State?
	if snapshot ~= nil then
		run = Run.restore(snapshot)
	elseif board ~= nil then
		run = Run.new(board, hold)
	end
	if run == nil then
		return nil
	end
	return {
		level = run.level,
		run = run,
		before = Run.copy(run),
		waiting = {},
		head = 1,
		next = run.tick,
		debt = 0,
		buffer = Stream.BUFFER,
		hurry = true,
		stalled = 0,
		started = false,
		cues = {},
	}
end

function Stream.boardOf(w: Watch): Boards.Board
	return Boards.ALL[w.level]
end

-- One relayed piece of the log. It must start where the last one ended.
function Stream.push(w: Watch, start: any, text: any): (boolean, string?)
	if type(start) ~= "number" or start ~= w.next then
		return false, `gap: this watcher is at tick {w.next}`
	end
	local codes = InputLog.decode(text, InputLog.SEGMENT_TICKS)
	if codes == nil then
		return false, "bad segment"
	end
	if #w.waiting - w.head + 1 + #codes > Stream.MAX_WAITING then
		return false, "too far behind"
	end
	if w.head > 256 then
		-- drop what has been played
		local rest: { number } = table.create(#w.waiting - w.head + 1)
		table.move(w.waiting, w.head, #w.waiting, 1, rest)
		w.waiting, w.head = rest, 1
	end
	for _, code in codes do
		table.insert(w.waiting, code)
	end
	w.next += #codes
	return true
end

-- Time passes for a watcher: play the ticks that are due. Returns how many were played.
function Stream.advance(w: Watch, dt: number): number
	local board = Boards.ALL[w.level]
	local left = #w.waiting - w.head + 1
	if not w.started then
		if left <= 0 then
			return 0
		end
		if left < w.buffer then
			-- less than a buffer in hand: wait a little for more, then play what there is (the last ticks of
			-- a run come with nothing after them)
			w.stalled += dt
			if w.stalled < Stream.STALL then
				return 0
			end
		end
		w.started = true
		w.stalled = 0
	end
	w.debt = math.min(w.debt + dt, 0.25)
	local played = 0
	while w.debt >= Physics.TICK do
		w.debt -= Physics.TICK
		local burst = if w.hurry and left > Stream.HURRY then 2 else 1
		for _ = 1, burst do
			if left <= 0 or Run.over(w.run) then
				break
			end
			w.before = Run.copy(w.run)
			Run.step(board, w.run, w.waiting[w.head])
			w.head += 1
			left -= 1
			played += 1
			for _, cue in Stream.cues(board, w.run) do
				table.insert(w.cues, cue)
			end
		end
		if left <= 0 then
			-- nothing more has come: stand still, and buffer again before going on
			w.started = false
			w.debt = 0
			break
		end
	end
	return played
end

-- A recorded run to show beside the live one (the day's record): the whole log at once, no delay.
function Stream.ghost(board: Boards.Board, hold: number, log: any): Watch?
	local codes = InputLog.decode(log, Run.MAX_TICKS)
	if codes == nil then
		return nil
	end
	local w = Stream.watch(nil, board, hold)
	if w == nil then
		return nil
	end
	w.waiting = codes
	w.next = #codes
	w.buffer = 0
	w.hurry = false
	return w
end

return Stream
