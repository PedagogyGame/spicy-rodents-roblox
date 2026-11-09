--!strict
-- ReplicatedStorage.Shared.Minigames.MinigameRules.Bowling
-- Ten-pin bowling on the Minigame contract (BUILD_PLAN §3.16; brief v2 §13a "fully playable lanes ... working
-- scoreboards"): up to 4 bowlers take whole frames in turn; ten frames each; the tenth frame gives a third
-- ball after a strike or a spare. The pinfall itself comes from the lane's physics (Server/Minigames/
-- BowlingLane: the server owns the ball and every pin, D28); this module only counts it, so the verb
-- "roll" is a SERVER verb (clients send "release" to the lane, never a pin count).
-- Pure; Lune-tested (tests/unit/minigames_bowling.spec.luau).
-- Interface: the Minigame.Rules shape plus turn(state) -> seat?, view(state) -> table (scoreboard),
--   score(rolls) -> { frame totals or false }, marks(rolls) -> { box strings }, total(rolls) -> number,
--   rackFor(state) -> "full" | "keep" (what the pinsetter sets before the next ball), standing(state) -> pins

local Bowling = {}

Bowling.def = {
	game = "bowling",
	title = "Bowling",
	class = "shared_table",
	seats = 4,
	authority = "server", -- the server owns the ball and the pins for every roll (D28; see BowlingLane)
	money = "none",
}
Bowling.verbs = { roll = true }
Bowling.serverVerbs = { roll = true }
Bowling.FRAMES = 10
Bowling.PINS = 10

export type State = {
	seats: number,
	rolls: { { number } }, -- per seat: every ball in order (pin counts)
	frameOf: { number }, -- per seat: the frame being bowled (1..10, 11 = finished)
	ballOf: { number }, -- per seat: ball within that frame (1..3)
	pinsUp: number, -- pins standing for the next ball
	seat: number, -- whose turn
	done: boolean,
	lastEvent: string?,
}

function Bowling.init(seats: number, _seed: number): State
	local rolls, frameOf, ballOf = {}, {}, {}
	for i = 1, seats do
		rolls[i] = {}
		frameOf[i] = 1
		ballOf[i] = 1
	end
	return {
		seats = seats,
		rolls = rolls,
		frameOf = frameOf,
		ballOf = ballOf,
		pinsUp = Bowling.PINS,
		seat = 1,
		done = false,
		lastEvent = nil,
	}
end

-- Split a seat's roll list into frames: { { r1, r2?, r3? } x up to 10 }.
function Bowling.frames(rolls: { number }): { { number } }
	local frames: { { number } } = {}
	local i = 1
	for f = 1, Bowling.FRAMES do
		if i > #rolls then
			break
		end
		if f < Bowling.FRAMES then
			if rolls[i] == Bowling.PINS then
				frames[f] = { rolls[i] }
				i += 1
			else
				local fr = { rolls[i] }
				if rolls[i + 1] ~= nil then
					table.insert(fr, rolls[i + 1])
				end
				frames[f] = fr
				i += 2
			end
		else
			local fr = {}
			for k = i, math.min(#rolls, i + 2) do
				table.insert(fr, rolls[k])
			end
			frames[f] = fr
			i += 3
		end
	end
	return frames
end

-- Cumulative score per frame; false where the frame cannot be scored yet (a strike or spare waiting on
-- the balls that follow it, or a frame still being bowled).
function Bowling.score(rolls: { number }): { number | false }
	local out: { number | false } = {}
	local total = 0
	local i = 1
	for f = 1, Bowling.FRAMES do
		local a = rolls[i]
		if a == nil then
			break
		end
		local b, c = rolls[i + 1], rolls[i + 2]
		local frameScore: number? = nil
		if f < Bowling.FRAMES then
			if a == Bowling.PINS then
				if b ~= nil and c ~= nil then
					frameScore = 10 + b + c
				end
				i += 1
			else
				if b ~= nil then
					if a + b == Bowling.PINS then
						if c ~= nil then
							frameScore = 10 + c
						end
					else
						frameScore = a + b
					end
				end
				i += 2
			end
		else
			-- tenth: two balls, or three after a strike or a spare
			if b ~= nil then
				if a == Bowling.PINS or a + b == Bowling.PINS then
					if c ~= nil then
						frameScore = a + b + c
					end
				else
					frameScore = a + b
				end
			end
		end
		if frameScore == nil then
			out[f] = false
			-- later frames cannot have a running total either
			for g = f + 1, Bowling.FRAMES do
				if Bowling.frames(rolls)[g] then
					out[g] = false
				end
			end
			break
		end
		total += frameScore
		out[f] = total
	end
	return out
end

-- The running total: the last scorable frame's cumulative score (0 before any).
function Bowling.total(rolls: { number }): number
	local best = 0
	for _, v in Bowling.score(rolls) do
		if v then
			best = v
		end
	end
	return best
end

-- The final score, counting every ball even if bonuses are pending (used for a player who left).
function Bowling.marks(rolls: { number }): { { string } }
	local out: { { string } } = {}
	for f, fr in Bowling.frames(rolls) do
		local boxes: { string } = {}
		if f < Bowling.FRAMES then
			local a, b = fr[1], fr[2]
			if a == Bowling.PINS then
				boxes = { "", "X" }
			else
				boxes[1] = if a == 0 then "-" else tostring(a)
				if b ~= nil then
					boxes[2] = if a + b == Bowling.PINS then "/" elseif b == 0 then "-" else tostring(b)
				end
			end
		else
			-- tenth frame: each box against a fresh or a partial rack
			local fresh = true
			local prev = 0
			for k = 1, #fr do
				local v = fr[k]
				local s
				if fresh and v == Bowling.PINS then
					s = "X"
					fresh = true
					prev = 0
				elseif not fresh and prev + v == Bowling.PINS then
					s = "/"
					fresh = true
					prev = 0
				else
					s = if v == 0 then "-" else tostring(v)
					if fresh then
						fresh = false
						prev = v
					else
						fresh = true
						prev = 0
					end
				end
				boxes[k] = s
			end
		end
		out[f] = boxes
	end
	return out
end

local function seatFinished(state: State, seat: number): boolean
	return state.frameOf[seat] > Bowling.FRAMES
end

-- Whose turn it is (nil when the game is over).
function Bowling.turn(state: State): number?
	if state.done then
		return nil
	end
	return state.seat
end

function Bowling.standing(state: State): number
	return state.pinsUp
end

local function nextSeat(state: State)
	for step = 1, state.seats do
		local s = (state.seat - 1 + step) % state.seats + 1
		if not seatFinished(state, s) then
			state.seat = s
			return
		end
	end
	state.done = true
end

-- roll(state, seat, pins): count one ball. Returns the event name:
--   "strike" | "spare" | "open" (frame over, next bowler) | "next" (another ball in this frame) |
--   "gameover"; and the rack the pinsetter must set: "full" (all ten) or "keep" (sweep the deadwood).
function Bowling.roll(state: State, seat: number, pins: number): (string, string)
	local frame = state.frameOf[seat]
	local ball = state.ballOf[seat]
	local before = state.pinsUp
	table.insert(state.rolls[seat], pins)
	local event, rack = "next", "keep"
	local frameOver = false
	if frame < Bowling.FRAMES then
		if ball == 1 and pins == Bowling.PINS then
			event, frameOver = "strike", true
		elseif ball == 2 then
			event = if pins == before then "spare" else "open"
			frameOver = true
		else
			state.pinsUp = before - pins
			state.ballOf[seat] = 2
		end
	else
		-- the tenth
		local fr = Bowling.frames(state.rolls[seat])[Bowling.FRAMES]
		local a, b = fr[1], fr[2]
		if ball == 1 then
			if pins == Bowling.PINS then
				event, rack = "strike", "full"
				state.pinsUp = Bowling.PINS
			else
				state.pinsUp = before - pins
			end
			state.ballOf[seat] = 2
		elseif ball == 2 then
			if a == Bowling.PINS or a + b == Bowling.PINS then
				-- a third ball
				if pins == before then
					event = if a == Bowling.PINS then "strike" else "spare"
					rack = "full"
					state.pinsUp = Bowling.PINS
				else
					state.pinsUp = before - pins
				end
				state.ballOf[seat] = 3
			else
				event, frameOver = "open", true
			end
		else
			event = if pins == before and before == Bowling.PINS then "strike"
				elseif pins == before then "spare"
				else "open"
			frameOver = true
		end
	end
	if frameOver then
		state.frameOf[seat] = frame + 1
		state.ballOf[seat] = 1
		state.pinsUp = Bowling.PINS
		rack = "full"
		nextSeat(state)
		if state.done then
			event = "gameover"
		end
	end
	state.lastEvent = event
	return event, rack
end

-- skipTurn: play out the current seat's frame as misses (an idle turn or a player who walked away).
function Bowling.skipTurn(state: State)
	local seat = state.seat
	local frame = state.frameOf[seat]
	local guard = 0
	while not state.done and state.seat == seat and state.frameOf[seat] == frame and guard < 4 do
		Bowling.roll(state, seat, 0)
		guard += 1
	end
end

-- What the pinsetter sets before the next ball: "full" for a new frame (or a fresh tenth-frame rack).
function Bowling.rackFor(state: State): string
	return if state.pinsUp == Bowling.PINS then "full" else "keep"
end

function Bowling.input(state: State, seat: number, verb: string, args: { any }?): (boolean, string?)
	if verb ~= "roll" then
		return false, "verb"
	end
	if state.done then
		return false, "game over"
	end
	if seat ~= state.seat then
		return false, "not your turn"
	end
	local pins = if args then args[1] else nil
	if type(pins) ~= "number" or pins ~= math.floor(pins) or pins < 0 or pins > state.pinsUp then
		return false, "pins"
	end
	Bowling.roll(state, seat, pins)
	return true
end

function Bowling.result(state: State): { [string]: any }?
	local scores: { [number]: number } = {}
	local best, winner, tie = -1, nil :: number?, false
	for s = 1, state.seats do
		local t = Bowling.total(state.rolls[s])
		scores[s] = t
		if t > best then
			best, winner, tie = t, s, false
		elseif t == best then
			tie = true
		end
	end
	if not state.done then
		return nil
	end
	return { done = true, scores = scores, winner = if tie then nil else winner }
end

-- JSON-friendly scoreboard for clients and the overhead monitors.
function Bowling.view(state: State): { [string]: any }
	local seats = {}
	for s = 1, state.seats do
		local rolls = state.rolls[s]
		local cum = Bowling.score(rolls)
		local totals = {}
		for f = 1, Bowling.FRAMES do
			local v = cum[f]
			totals[f] = if v then v else ""
		end
		seats[s] = {
			marks = Bowling.marks(rolls),
			totals = totals,
			total = Bowling.total(rolls),
			frame = math.min(state.frameOf[s], Bowling.FRAMES),
			ball = state.ballOf[s],
			finished = state.frameOf[s] > Bowling.FRAMES,
		}
	end
	return {
		kind = "bowling",
		seats = seats,
		turn = if state.done then nil else state.seat,
		pinsUp = state.pinsUp,
		done = state.done,
		lastEvent = state.lastEvent,
	}
end

return Bowling
