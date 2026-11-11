--!strict
-- ReplicatedStorage.Shared.Minigames.Labyrinth.Run
-- One run of the labyrinth as a state machine stepped by the player's input, one code a tick (Controls.code).
-- It owns everything that is a RULE and leaves the marble to Physics:
--   LAB-R1  one marble from START to FINISH along the path drawn on the board, past the numbered holes;
--   LAB-R4  the clock starts on the first key press: until then nothing moves and no tick counts;
--   LAB-R2  a marble that drops down a hole rolls home through the box (RETURN_TICKS, the clock keeps running)
--           and comes back, at rest, on the last checkpoint passed; there is no game over;
--   LAB-R3  the result is the time to the finish and the marbles dropped; a run that is abandoned, or that
--           reaches MAX_TICKS (four minutes), counts the highest number reached instead.
-- "Passed" and "reached" are read off the board's own tables: every cell knows how far along the drawn line a
-- marble in it has come (Boards placeAt), and the furthest point ever reached decides the number and the
-- checkpoint. A marble coming back does not lose its number.
-- The state is plain numbers (and the marble's record), so it can be copied, sent and compared: the same board,
-- hold mode and codes give the same state, bit for bit, on any machine (LAB-P6).
-- Pure; Lune-tested (tests/unit/labyrinth_rules.spec.luau, labyrinth_physics.spec.luau).
-- Interface: PHASE, PHASE_NAME, EV, MAX_TICKS, RETURN_TICKS; new(board, hold?) -> State; step(board, s, code);
--   abandon(s); over(s) -> boolean; seconds(s), tenths(s); copy(s); snapshot(s) -> { number };
--   restore(array) -> State?; bytes(s) -> string (every number as its 8 bytes); digest(s) -> 32-bit number;
--   replay(board, hold, codes) -> State

local Boards = require("./Boards")
local Controls = require("./Controls")
local Physics = require("./Physics")

local Run = {}

Run.PHASE = table.freeze({
	READY = 0, -- waiting for the first key; the clock has not started
	ROLLING = 1,
	RETURNING = 2, -- the marble is rolling home inside the box
	FINISHED = 3,
	TIMEOUT = 4,
	ABANDONED = 5,
})
Run.PHASE_NAME = table.freeze({
	[0] = "ready",
	[1] = "rolling",
	[2] = "returning",
	[3] = "finished",
	[4] = "timeout",
	[5] = "abandoned",
})
-- what happened in the last tick (bits of State.ev): for sound cues, banners and the scoreboard
Run.EV = table.freeze({
	START = 1, -- the first key: the clock is running
	FELL = 2, -- down a hole
	RETURNED = 4, -- back on a checkpoint
	NUMBER = 8, -- a new number reached
	CHECKPOINT = 16, -- a new checkpoint passed
	FINISH = 32, -- into the cup
	TIMEOUT = 64,
})
Run.MAX_TICKS = 4 * 60 * 60 -- four minutes
Run.RETURN_TICKS = 108 -- 1.8 s for the plonk, the roll home through the box and the marble's return

export type State = {
	level: number, -- which board (Boards.ALL index), so a snapshot says what it is a snapshot of
	hold: number, -- Physics.HOLD_STAY or HOLD_LEVEL
	phase: number,
	tick: number, -- the clock, in ticks since the first key
	progress: number, -- the furthest point of the path reached
	reached: number, -- the highest hole number reached
	checkpoint: number, -- the last checkpoint passed (index into board.checkpoints)
	drops: number,
	wait: number, -- RETURNING: ticks until the marble is back
	hole: number, -- the hole it last went down (0: none yet)
	ev: number,
	m: Physics.Marble,
}

local PHASE, EV = Run.PHASE, Run.EV

function Run.new(board: Boards.Board, hold: number?): State
	local m = Physics.new(board.start.x, board.start.y)
	m.cell = Boards.cellOf(board, m.x, m.y)
	return {
		level = board.level,
		hold = hold or Physics.HOLD_STAY,
		phase = PHASE.READY,
		tick = 0,
		progress = 1,
		reached = 0,
		checkpoint = 1,
		drops = 0,
		wait = 0,
		hole = 0,
		ev = 0,
		m = m,
	}
end

function Run.over(s: State): boolean
	return s.phase >= PHASE.FINISHED
end

function Run.step(board: Boards.Board, s: State, code: number)
	s.ev = 0
	if s.phase >= PHASE.FINISHED then
		return
	end
	if s.phase == PHASE.READY then
		if code == Controls.NEUTRAL then
			return -- the clock starts on the first key (LAB-R4)
		end
		s.phase = PHASE.ROLLING
		s.ev = EV.START
	end
	local right, forward = Controls.axes(code)
	s.tick += 1
	local m = s.m
	local into = Physics.step(board, m, right, forward, s.hold)
	if s.phase == PHASE.RETURNING then
		s.wait -= 1
		if s.wait <= 0 then
			local cp = board.checkpoints[s.checkpoint]
			Physics.place(m, cp.x, cp.y)
			m.cell = cp.cell
			s.phase = PHASE.ROLLING
			s.ev += EV.RETURNED
		end
	elseif into == board.goal then
		s.phase = PHASE.FINISHED
		s.progress = #board.pathCells
		s.reached = #board.holes
		s.ev += EV.FINISH
		return
	elseif into > 0 then
		s.drops += 1
		s.hole = into
		s.phase = PHASE.RETURNING
		s.wait = Run.RETURN_TICKS
		s.ev += EV.FELL
	else
		local place = board.placeAt[m.cell]
		if place > s.progress then
			s.progress = place
			if board.numberAt[place] > s.reached then
				s.reached = board.numberAt[place]
				s.ev += EV.NUMBER
			end
			if board.checkpointAt[place] > s.checkpoint then
				s.checkpoint = board.checkpointAt[place]
				s.ev += EV.CHECKPOINT
			end
		end
	end
	if s.tick >= Run.MAX_TICKS then
		s.phase = PHASE.TIMEOUT
		s.ev += EV.TIMEOUT
	end
end

-- The player walks away, gives up, or is taken off the table: the run ends where it is.
function Run.abandon(s: State)
	if s.phase < PHASE.FINISHED then
		s.phase = PHASE.ABANDONED
	end
end

function Run.seconds(s: State): number
	return s.tick * Physics.TICK
end

-- the time shown and ranked: tenths of a second, rounded
function Run.tenths(s: State): number
	return math.floor(s.tick / 6 + 0.5)
end

function Run.copy(s: State): State
	local c = table.clone(s)
	c.m = Physics.copy(s.m)
	return c
end

-- The whole state as a flat array of numbers, in a fixed order (what a late watcher is sent to start from).
function Run.snapshot(s: State): { number }
	local m = s.m
	return {
		s.level,
		s.hold,
		s.phase,
		s.tick,
		s.progress,
		s.reached,
		s.checkpoint,
		s.drops,
		s.wait,
		s.hole,
		s.ev,
		m.x,
		m.y,
		m.vx,
		m.vy,
		m.on,
		m.tx,
		m.ty,
		m.wx,
		m.wy,
		m.cx,
		m.cy,
		m.cell,
		m.hit,
		m.rim,
		m.touch,
	}
end

local SNAPSHOT_SIZE = 26

-- A snapshot off the wire back into a state; nil when it is not one (wrong size, not numbers, off the board).
function Run.restore(a: any): State?
	if type(a) ~= "table" or #a ~= SNAPSHOT_SIZE then
		return nil
	end
	for i = 1, SNAPSHOT_SIZE do
		local v = a[i]
		if type(v) ~= "number" or v ~= v or math.abs(v) > 1e6 then
			return nil
		end
	end
	local board = Boards.ALL[a[1]]
	if board == nil or (a[2] ~= Physics.HOLD_STAY and a[2] ~= Physics.HOLD_LEVEL) then
		return nil
	end
	if Run.PHASE_NAME[a[3]] == nil or a[5] < 1 or a[5] > #board.pathCells or a[5] % 1 ~= 0 then
		return nil
	end
	if a[7] < 1 or a[7] > #board.checkpoints or a[7] % 1 ~= 0 or a[10] < 0 or a[10] > #board.holes then
		return nil
	end
	if math.abs(a[12]) > board.w / 2 or math.abs(a[13]) > board.h / 2 then
		return nil
	end
	return {
		level = a[1],
		hold = a[2],
		phase = a[3],
		tick = a[4],
		progress = a[5],
		reached = a[6],
		checkpoint = a[7],
		drops = a[8],
		wait = a[9],
		hole = a[10],
		ev = a[11],
		m = {
			x = a[12],
			y = a[13],
			vx = a[14],
			vy = a[15],
			on = a[16],
			tx = a[17],
			ty = a[18],
			wx = a[19],
			wy = a[20],
			cx = a[21],
			cy = a[22],
			cell = a[23],
			hit = a[24],
			rim = a[25],
			touch = a[26],
		},
	}
end

-- every number of the state as its eight bytes: two runs are the same run exactly when these are equal
function Run.bytes(s: State): string
	local a = Run.snapshot(s)
	local parts: { string } = table.create(#a)
	for i, v in a do
		parts[i] = string.pack("<d", v)
	end
	return table.concat(parts)
end

-- A small checksum of where the run stands (a client sends it with its log; the server compares its own): the
-- positions and tilts to a millionth, folded into 32 bits with whole-number arithmetic only.
function Run.digest(s: State): number
	local m = s.m
	local h = 17
	for _, v in { s.tick, s.phase, s.progress, s.drops, m.x, m.y, m.vx, m.vy, m.tx, m.ty } do
		local q = math.floor(v * 1000000 + 0.5) % 4294967296
		h = (h * 31 + q) % 4294967296
	end
	return h
end

-- A whole log played from the start (stops when the run is over).
function Run.replay(board: Boards.Board, hold: number, codes: { number }): State
	local s = Run.new(board, hold)
	for _, code in codes do
		if s.phase >= PHASE.FINISHED then
			break
		end
		Run.step(board, s, code)
	end
	return s
end

return Run
