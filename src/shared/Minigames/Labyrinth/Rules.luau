--!strict
-- ReplicatedStorage.Shared.Minigames.Labyrinth.Rules
-- The tilt marble labyrinth as a Minigame.Rules module (brief v2 §13a; the waiting-room table at the doctor's
-- office). One player at a time, no stakes, no money, no computer opponent: you play against the clock and
-- the clipboard of best times (Clipboard). The owner's controls are fixed and live in Controls.
-- Authority "client_sim_server_replay" (C1): the player's machine runs Run/Physics live from the keys, so the
-- board answers in the same frame, and sends its input log in pieces (verb "tilt" { "seg", start tick, text,
-- digest? }). The server holds its own Run and steps it through every piece as it arrives; that replica, not
-- anything the client says about the marble, is the run of record: its finish is the result, its state is what
-- watchers are sent, and a client whose digest disagrees is told to take the server's state (view.diverged).
--   LAB-R1  one marble from START to FINISH along the drawn path past the numbered holes
--   LAB-R2  a hole sends the marble home to the last checkpoint passed; the clock keeps running
--   LAB-R3  result: time and marbles dropped; abandoned or timed out (4 min): the highest number reached
--   LAB-R4  the clock starts on the first key (the log has no ticks before it)
-- "mode" { board, hold? } picks the board (1..#Boards.ALL or its id) and, while the owner is deciding question
-- D1, how the knobs behave when let go ("stay" or "level"); only before the first key.
-- "clock" { seconds } is the server's own verb: its wall clock, sent with each piece and about once a second.
-- A run is played in real time; one whose log falls more than SLACK seconds behind or ahead of the server's
-- clock still counts for the player but is marked not fair and stays off the clipboard.
-- What this game needs from the framework that a turn game does not is listed in NEEDS.
-- Pure; Lune-tested (tests/unit/labyrinth_rules.spec.luau).
-- Interface: the Minigame.Rules shape (def, verbs, serverVerbs, init, input, result, turn, skipTurn, view) plus
--   NEEDS, SLACK, HOLDS, TEXT; snapshot(state) -> { number } (for a watcher who arrives mid-run);
--   boardOf(state); line(state) -> the status line; clockText(tenths) -> "m:ss.t"

local Boards = require("./Boards")
local InputLog = require("./InputLog")
local Physics = require("./Physics")
local Run = require("./Run")

local Rules = {}

Rules.def = {
	game = "tilt_labyrinth",
	title = "Tilt Labyrinth",
	class = "no_stakes",
	seats = 1,
	authority = "client_sim_server_replay",
	money = "none",
}
Rules.verbs = { tilt = true, mode = true, clock = true }
Rules.serverVerbs = { clock = true }
Rules.HOLDS = table.freeze({ stay = Physics.HOLD_STAY, level = Physics.HOLD_LEVEL }) :: { [string]: number }
Rules.SLACK = 5 -- seconds a log may trail or lead the server's clock and still be a fair time

-- The game's own words, for the prompt, the banners and the animal rule (LAB-S1, C4, C12): one place, so
-- the server and the client say the same thing.
Rules.TEXT = table.freeze({
	prompt = "Play the labyrinth",
	inUse = "In use by %s",
	refused = "The labyrinth is for people.",
	dropped = "Plonk. Down hole %d.",
	back = "Back on the board.",
	finished = "Home in %s.",
	shooed = "Shoo! Paws off the labyrinth.", -- to the player when an animal climbs on the table
	shooedAnimal = "You are shooed off the table. The marble does not care.", -- to the animal
	bitten = "You were bitten: the run is over.",
	receptionist = "Dr. Maple will see you eventually.",
})

-- What the shared framework must offer for this game (it is not a turn game):
Rules.NEEDS = table.freeze({
	"a run phase with no turn clock: turn(state) is seat 1 from the first key to the finish; the only clocks are "
		.. "the run's own four minutes (Run.MAX_TICKS) and the lobby's idle clock before the first key",
	"the player's client steps Run itself every 1/60 s and sends verb 'tilt' { 'seg', start, text, digest } about "
		.. "five times a second (InputLog.writer); the service must pass those args through untouched, and return "
		.. "a refusal's reason to the client (on 'gap: the server is at tick N' it rewinds its writer to N)",
	"before each forwarded 'tilt', and about once a second, the service sends the server verb 'clock' { seconds }",
	"each accepted piece is relayed to everyone watching the table as it arrives (start, text), and a watcher "
		.. "who arrives mid-run is first sent Rules.snapshot(state); they draw with Stream",
	"when view.diverged is true the service sends the player Rules.snapshot(state) and the client restores it",
	"leaving, a bite or two idle lobby clocks call skipTurn(state), which abandons the run with its number",
})

export type State = {
	board: number,
	run: Run.State,
	serverNow: number?, -- the server's clock, seconds (nil until it has spoken)
	serverStart: number?, -- what that clock said when the run's own clock started
	fair: boolean,
	diverged: boolean,
}

local HOLD_NAME = { [Physics.HOLD_STAY] = "stay", [Physics.HOLD_LEVEL] = "level" }

function Rules.init(_seats: number, _seed: number): State
	return {
		board = 1,
		run = Run.new(Boards.ALL[1]),
		serverNow = nil,
		serverStart = nil,
		fair = true,
		diverged = false,
	}
end

function Rules.boardOf(state: State): Boards.Board
	return Boards.ALL[state.board]
end

local function checkPace(state: State)
	local now, start = state.serverNow, state.serverStart
	if now == nil or start == nil or Run.over(state.run) then
		return
	end
	local behind = (now - start) - Run.seconds(state.run)
	if math.abs(behind) > Rules.SLACK then
		state.fair = false
	end
end

function Rules.input(state: State, seat: number, verb: string, args: { any }?): (boolean, string?)
	if seat ~= 1 then
		return false, "one player at a time"
	end
	local a = args or {}
	if verb == "clock" then
		local seconds = a[1]
		if type(seconds) ~= "number" or seconds ~= seconds then
			return false, "clock"
		end
		state.serverNow = seconds
		checkPace(state)
		return true
	end
	local run = state.run
	if Run.over(run) then
		return false, "this run is over: play again"
	end
	if verb == "mode" then
		if run.phase ~= Run.PHASE.READY then
			return false, "the board cannot be changed once the marble is rolling"
		end
		local which = a[1]
		local board = if type(which) == "string" or type(which) == "number" then Boards.get(which) else nil
		if board == nil then
			return false, "no such board"
		end
		local hold = run.hold
		if a[2] ~= nil then
			local named = if type(a[2]) == "string" then Rules.HOLDS[a[2]] else nil
			if named == nil then
				return false, "hold is stay or level"
			end
			hold = named
		end
		state.board = board.level
		state.run = Run.new(board, hold)
		return true
	elseif verb == "tilt" then
		local what = a[1]
		if what == "giveup" then
			Run.abandon(run)
			return true
		elseif what ~= "seg" then
			return false, "tilt what?"
		end
		local start, text, digest = a[2], a[3], a[4]
		if type(start) ~= "number" or start ~= run.tick then
			-- a piece was lost or came twice: say where the server is so the client can send from there
			return false, `gap: the server is at tick {run.tick}`
		end
		if type(text) ~= "string" or #text > InputLog.SEGMENT_CHARS then
			return false, "bad segment"
		end
		local codes = InputLog.decode(text, InputLog.SEGMENT_TICKS)
		if codes == nil then
			return false, "bad segment"
		end
		local board = Boards.ALL[state.board]
		for _, code in codes do
			if Run.over(run) then
				break
			end
			Run.step(board, run, code)
		end
		if state.serverStart == nil and state.serverNow ~= nil and run.tick > 0 then
			-- the server's clock when the player's first key went down (time before it is not the run's)
			state.serverStart = state.serverNow - Run.seconds(run)
		end
		if type(digest) == "number" and not Run.over(run) and digest ~= Run.digest(run) then
			state.diverged = true
		elseif digest ~= nil then
			state.diverged = false
		end
		checkPace(state)
		return true
	end
	return false, "verb"
end

function Rules.turn(state: State): number?
	return if Run.over(state.run) then nil else 1
end

-- an idle lobby clock, a walk-away, a bite: the run ends where it stands (LAB-R3)
function Rules.skipTurn(state: State)
	Run.abandon(state.run)
end

function Rules.result(state: State): { [string]: any }?
	local run = state.run
	if not Run.over(run) then
		return nil
	end
	local board = Boards.ALL[state.board]
	local finished = run.phase == Run.PHASE.FINISHED
	local tenths = Run.tenths(run)
	return {
		done = true,
		scores = { if finished then tenths else 0 },
		winner = if finished then 1 else nil,
		finished = finished,
		why = Run.PHASE_NAME[run.phase],
		tenths = tenths,
		seconds = tenths / 10,
		drops = run.drops,
		reached = run.reached,
		of = #board.holes,
		board = board.id,
		boardName = board.name,
		hold = HOLD_NAME[run.hold],
		fair = state.fair,
	}
end

-- "m:ss.t" for the clock, the end card and the clipboard
function Rules.clockText(tenths: number): string
	local whole = math.floor(tenths / 10)
	return string.format("%d:%02d.%d", whole // 60, whole % 60, tenths % 10)
end

-- The status line: always what to do, or what just happened, in the game's own words (C4).
function Rules.line(state: State): string
	local run = state.run
	local board = Boards.ALL[state.board]
	local phase = run.phase
	local clock = Rules.clockText(Run.tenths(run))
	if phase == Run.PHASE.READY then
		return `{board.name}. Tilt the board to start the clock: W, S, Up arrow or Down arrow.`
	elseif phase == Run.PHASE.ROLLING then
		return `{clock}  Hole {run.reached} of {#board.holes}.  Marbles dropped: {run.drops}.`
	elseif phase == Run.PHASE.RETURNING then
		local cp = board.checkpoints[run.checkpoint]
		local where = if cp.n == 0 then "the start" else `checkpoint {cp.n}`
		return `{clock}  Down hole {board.holes[run.hole].n}. The marble is rolling home to {where}.`
	elseif phase == Run.PHASE.FINISHED then
		local dropped = if run.drops == 1 then "1 marble dropped" else `{run.drops} marbles dropped`
		return `Home in {clock} with {dropped}.`
	elseif phase == Run.PHASE.TIMEOUT then
		return `Four minutes are up. You reached hole {run.reached} of {#board.holes}.`
	end
	return `You stopped at hole {run.reached} of {#board.holes}.`
end

function Rules.view(state: State): { [string]: any }
	local run = state.run
	local board = Boards.ALL[state.board]
	local tenths = Run.tenths(run)
	return {
		board = board.id,
		boardName = board.name,
		level = board.level,
		hold = HOLD_NAME[run.hold],
		phase = Run.PHASE_NAME[run.phase],
		tick = run.tick,
		tenths = tenths,
		clock = Rules.clockText(tenths),
		drops = run.drops,
		reached = run.reached,
		of = #board.holes,
		checkpoint = board.checkpoints[run.checkpoint].n,
		fair = state.fair,
		diverged = state.diverged,
		digest = Run.digest(run),
		line = Rules.line(state),
	}
end

-- the server's run as a flat array of numbers: what a late watcher (or a client that diverged) starts from
function Rules.snapshot(state: State): { number }
	return Run.snapshot(state.run)
end

return Rules
