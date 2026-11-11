--!strict
-- ReplicatedStorage.Shared.Minigames.Jenga.Rules
-- Giant Jenga as a rules module in the Minigame contract's shape (brief v2 §13a: "a playable four-foot giant
-- Jenga on a deck table"; checklist JEN-R1..R6, JEN-C4). The tower itself is the pure model beside this file
-- (Tower, Stability, Physics, Fall); this module is whose turn it is, what they may do, the clocks, who lost.
--   JEN-R1  54 blocks, 18 levels of three, each across the one below (Tower.new, Layout).
--   JEN-R2  On your turn take one block from below the highest complete level and put it on top, finishing a
--           level of three before starting the next (Tower.legal, Tower.building).
--   JEN-R3  You may tap any block to feel it, and give up on a block you have slid less than a third of its
--           length; beyond that it is yours ("release" is refused, and so is pulling another).
--   JEN-R4  After you place there is a 3 s settle. If the tower falls during your turn or your settle you
--           lose and the game ends; the winner is the last player to have finished a turn.
--   JEN-R5  Up to 4 players in turn. A turn nobody plays (the draw clock or the place clock runs out, or the
--           framework calls skipTurn) is played for you: a loose block, drawn with ordinary care, and the
--           risk is yours. `idle` counts those turns in a row per seat (the framework takes a player off at
--           two).
--   JEN-R6  Solo: how high can you build. The result gives the levels reached and the blocks moved.
--   JEN-C4  45 s to draw, 20 s to place (`clock`), a warning in the last 10 s (`view.warn`).
-- THIS GAME IS NOT ONE INPUT PER TURN. A turn is seconds of live pulling, so besides the players' verbs there
-- is the server's verb "tick" { dt }: the server sends it every heartbeat and the model advances in fixed
-- 1/60 s steps. Computer players and idle turns are played inside those ticks, through the same verbs, at a
-- person's pace, so everybody watches them happen.
-- Players' verbs (all only on your turn):
--   "tap"     { level, slot }                         knock on a block (phase "draw", hand empty)
--   "pull"    { level, slot, along, lateral, push? }  a sample of the drag: where the hand wants the block
--             along its own length (studs from square; the sign is the side it comes out of), how far the
--             hand is off its line, and whether it is pushed from the far end. The first sample grabs it.
--   "release" {}                                      give the block up (less than a third out)
--   "place"   { slot, along, across, speed }          set the block in hand on top: how far off square, and
--             how hard it comes down (0 = gently)
-- Pure; Lune-tested (tests/unit/jenga_rules.spec.luau).
-- Interface: the Minigame.Rules shape (def, init, input, result, verbs, serverVerbs, turn, skipTurn, view)
--   plus advance(state, dt); setComputer(state, seat, skill?); leave(state, seat); frame(state) -> Frame
--   (the 20 Hz stream: turn, phase, clock, the tower's View.frame, the events since the last one);
--   snapshot(state) -> Tower.Snapshot; clock(state) -> (left, total); DRAW_SECS, PLACE_SECS, SETTLE_SECS

local Bots = require("./Bots")
local Fall = require("./Fall")
local Layout = require("./Layout")
local Physics = require("./Physics")
local Tower = require("./Tower")
local View = require("./View")

local Rules = {}

Rules.def = {
	game = "jenga",
	title = "Giant Jenga",
	class = "shared_table",
	seats = Layout.SEATS,
	authority = "server_deterministic", -- the server steps the one tower; clients draw its frames
	money = "none",
}
Rules.verbs = { tap = true, pull = true, release = true, place = true, tick = true }
Rules.serverVerbs = { tick = true }

Rules.DRAW_SECS = 45
Rules.PLACE_SECS = 20
Rules.SETTLE_SECS = 3
Rules.WARN_SECS = 10
Rules.AUTO_SECS = 60 -- a turn being played for someone gets this long
Rules.MAX_TICK = 0.25 -- seconds of catching up in one tick, at most

local DT = Physics.DT

export type Event = { kind: string, a: number, b: number }

export type State = {
	seats: number,
	seed: number,
	tower: Tower.Tower,
	seat: number,
	phase: string, -- "draw" | "place" | "settle" | "over"
	clock: number, -- seconds left in the phase
	time: number,
	acc: number,
	turnIndex: number,
	moves: { number }, -- turns finished, per seat
	idle: { number }, -- idle turns in a row, per seat
	gone: { boolean },
	computer: { [number]: string }, -- seat -> skill
	auto: boolean, -- this turn is being played for the seat
	brain: Bots.Brain?,
	sample: number,
	lastDone: number?, -- the last seat to finish a turn
	total: number, -- turns finished by everyone
	tallest: number, -- the most levels the tower has had
	done: boolean,
	loser: number?,
	winner: number?,
	fallMove: number, -- the move it fell on (1 = the very first)
	fall: Fall.Script?,
	events: { Event },
	lastTap: { [string]: any }?,
	sentKey: number?,
	replay: { any }?, -- frames of a turn that was played out at once (skipTurn)
}

function Rules.init(seats: number, seed: number): State
	local moves, idle, gone = {}, {}, {}
	for i = 1, seats do
		moves[i], idle[i], gone[i] = 0, 0, false
	end
	return {
		seats = seats,
		seed = seed,
		tower = Tower.new(seed),
		seat = 1,
		phase = "draw",
		clock = Rules.DRAW_SECS,
		time = 0,
		acc = 0,
		turnIndex = 1,
		moves = moves,
		idle = idle,
		gone = gone,
		computer = {},
		auto = false,
		brain = nil,
		sample = 0,
		lastDone = nil,
		total = 0,
		tallest = Layout.START_LEVELS,
		done = false,
		loser = nil,
		winner = nil,
		fallMove = 0,
		fall = nil,
		events = {},
		lastTap = nil,
		sentKey = nil,
		replay = nil,
	}
end

local function note(state: State, kind: string, a: number, b: number)
	if #state.events < 256 then
		table.insert(state.events, { kind = kind, a = a, b = b })
	end
end

-- setComputer(seat, skill): a computer player sits in that seat ("easy" | "normal" | "sharp"); nil hands the
-- seat back to a person.
function Rules.setComputer(state: State, seat: number, skill: string?)
	state.computer[seat] = skill :: any
	if seat == state.seat then
		state.brain = nil
	end
end

function Rules.turn(state: State): number?
	return if state.done then nil else state.seat
end

function Rules.clock(state: State): (number, number)
	local total = Rules.DRAW_SECS
	if state.auto then
		total = Rules.AUTO_SECS
	elseif state.phase == "place" then
		total = Rules.PLACE_SECS
	elseif state.phase == "settle" then
		total = Rules.SETTLE_SECS
	end
	return math.max(state.clock, 0), total
end

local function finish(state: State, loser: number?)
	local tw = state.tower
	state.done = true
	state.phase = "over"
	state.loser = loser
	state.fallMove = state.total + 1
	local last = state.lastDone
	state.winner = if loser and last and last ~= loser then last else nil
	if tw.fallen then
		state.fall = Fall.build(tw, state.seed * 17 + state.turnIndex * 31 + 5)
	end
	note(state, "over", loser or 0, state.winner or 0)
end

local function nextSeat(state: State)
	local seat = state.seat
	for _ = 1, state.seats do
		seat = seat % state.seats + 1
		if not state.gone[seat] then
			break
		end
	end
	if state.gone[seat] then
		-- nobody is left at the table
		finish(state, nil)
		return
	end
	state.seat = seat
	state.turnIndex += 1
	state.phase = "draw"
	state.clock = Rules.DRAW_SECS
	state.auto = false
	state.brain = nil
	state.sample = 0
	note(state, "turn", seat, state.turnIndex)
end

local function endTurn(state: State)
	local seat = state.seat
	state.moves[seat] += 1
	state.total += 1
	state.lastDone = seat
	if not state.auto then
		state.idle[seat] = 0
	end
	state.tallest = math.max(state.tallest, #state.tower.levels)
	nextSeat(state)
end

-- The rest of this turn is played for the seat (the clock ran out, or the framework skipped the turn).
local function takeOver(state: State, countIdle: boolean)
	if state.auto then
		state.clock = Rules.AUTO_SECS
		return
	end
	state.auto = true
	state.clock = Rules.AUTO_SECS
	state.brain = Bots.new("idle", state.seed * 13 + state.turnIndex * 101)
	state.sample = 0
	if countIdle and state.computer[state.seat] == nil then
		state.idle[state.seat] += 1
	end
	note(state, "idle", state.seat, state.idle[state.seat])
end

local function isInt(v: any): boolean
	return type(v) == "number" and v == math.floor(v) and v >= 0 and v <= 1000
end

local function isNum(v: any): boolean
	return type(v) == "number" and v == v and math.abs(v) < 1e6
end

-- One input from whoever is playing the turn (a person, a computer player or the idle hand).
local function apply(state: State, verb: string, a: { any }): (boolean, string?)
	local tw = state.tower
	if verb == "tap" then
		if state.phase ~= "draw" then
			return false, "not now"
		end
		if not isInt(a[1]) or not isInt(a[2]) then
			return false, "args"
		end
		if tw.held ~= 0 then
			return false, "you are holding a block"
		end
		local f = Physics.tap(tw, a[1], a[2])
		if not f then
			return false, "no block there"
		end
		state.lastTap =
			{ seat = state.seat, level = a[1], slot = a[2], kind = f.kind, give = f.give, hollow = f.hollow }
		return true
	elseif verb == "pull" then
		if state.phase ~= "draw" then
			return false, "not now"
		end
		if not isInt(a[1]) or not isInt(a[2]) or not isNum(a[3]) or not isNum(a[4]) then
			return false, "args"
		end
		if tw.held ~= 0 then
			local hb = tw.blocks[tw.held]
			if hb.level ~= a[1] or hb.slot ~= a[2] then
				local okGo, whyGo = Physics.letGo(tw)
				if not okGo then
					return false, whyGo
				end
			end
		end
		if tw.held == 0 then
			local ok, why = Physics.grab(tw, a[1], a[2], a[5] == true)
			if not ok then
				return false, why
			end
			note(state, "grab", tw.held, state.seat)
		end
		Physics.drag(tw, a[3], a[4])
		return true
	elseif verb == "release" then
		if state.phase ~= "draw" then
			return false, "not now"
		end
		return Physics.letGo(tw)
	elseif verb == "place" then
		if state.phase ~= "place" then
			return false, "no block in hand"
		end
		if not isInt(a[1]) or not isNum(a[2]) or not isNum(a[3]) or not isNum(a[4]) then
			return false, "args"
		end
		local ok, why = Physics.place(tw, a[1], a[2], a[3], a[4])
		if not ok then
			return false, why
		end
		state.phase = "settle"
		state.clock = Rules.SETTLE_SECS
		return true
	end
	return false, "verb"
end

local function step(state: State)
	local tw = state.tower
	local seat = state.seat
	if state.phase ~= "settle" and (state.auto or state.computer[seat] ~= nil) then
		state.sample -= 1
		if state.sample <= 0 then
			state.sample = View.STEPS
			local brain: Bots.Brain = state.brain
				or Bots.new(state.computer[seat] or "idle", state.seed * 13 + state.turnIndex * 101 + seat)
			state.brain = brain
			local verb, args = Bots.act(brain, tw, state.phase, View.STEPS * DT)
			if verb then
				apply(state, verb, args or {})
			end
		end
	end
	Physics.step(tw)
	state.time += DT
	if #tw.events > 0 then
		for _, e in Tower.drain(tw) do
			note(state, e.kind, e.a, e.b)
		end
	end
	if tw.fallen then
		finish(state, seat)
		return
	end
	if state.phase == "draw" and tw.inHand ~= 0 then
		state.phase = "place"
		state.clock = if state.auto then Rules.AUTO_SECS else Rules.PLACE_SECS
		return
	end
	state.clock -= DT
	if state.clock <= 0 then
		if state.phase == "settle" then
			endTurn(state)
		else
			takeOver(state, true)
		end
	end
end

-- advance(state, dt): the server's clock. The model takes whole 1/60 s steps; what is left over is kept.
function Rules.advance(state: State, dt: number)
	if state.done or dt ~= dt or dt <= 0 then
		return
	end
	state.acc += math.min(dt, Rules.MAX_TICK)
	while state.acc >= DT and not state.done do
		state.acc -= DT
		step(state)
	end
end

function Rules.input(state: State, seat: number, verb: string, args: { any }?): (boolean, string?)
	local a = args or {}
	if verb == "tick" then
		local dt = a[1]
		if type(dt) ~= "number" then
			return false, "args"
		end
		Rules.advance(state, dt)
		return true
	end
	if not Rules.verbs[verb] then
		return false, "verb"
	end
	if state.done then
		return false, "game over"
	end
	if seat ~= state.seat then
		return false, "not your turn"
	end
	if state.computer[seat] ~= nil then
		return false, "a computer player has this seat"
	end
	if state.auto then
		return false, "your turn is being played for you"
	end
	if state.phase == "settle" then
		return false, "wait for the tower to settle"
	end
	return apply(state, verb, a)
end

-- skipTurn: the turn nobody is playing is played out for the seat, here and now (the framework's idle turn or
-- a vacated seat). The frames of that turn are kept in state.replay so the clients can be shown it happening.
function Rules.skipTurn(state: State)
	if state.done then
		return
	end
	local turn = state.turnIndex
	takeOver(state, true)
	local replay = {}
	state.replay = replay
	local guard = 0
	while not state.done and state.turnIndex == turn and guard < 200 * Physics.RATE do
		guard += 1
		step(state)
		if state.tower.step % View.STEPS == 0 and #replay < 2400 then
			table.insert(replay, Rules.frame(state))
		end
	end
	if not state.done and state.turnIndex == turn then
		-- cannot happen (a held block always comes out in the end); never leave the table stuck
		nextSeat(state)
	end
end

-- leave(seat): a player has gone (walked off, was bitten, left the game). The others play on. If it was their
-- turn and they had a block they could not put back, the turn is finished for them; otherwise it passes.
function Rules.leave(state: State, seat: number)
	if state.done or seat < 1 or seat > state.seats or state.gone[seat] then
		return
	end
	state.gone[seat] = true
	state.computer[seat] = nil
	local left = 0
	for i = 1, state.seats do
		if not state.gone[i] then
			left += 1
		end
	end
	if left == 0 then
		finish(state, nil)
		return
	end
	if seat ~= state.seat then
		return
	end
	local tw = state.tower
	if state.phase == "draw" and tw.inHand == 0 then
		if tw.held == 0 or Physics.letGo(tw) then
			nextSeat(state)
			return
		end
	end
	if state.phase ~= "settle" then
		takeOver(state, false)
	end
end

function Rules.result(state: State): { [string]: any }?
	if not state.done then
		return nil
	end
	local scores: { [number]: number } = {}
	for i = 1, state.seats do
		scores[i] = state.moves[i]
	end
	local levels, complete = Tower.levelsOf(state.tower)
	return {
		done = true,
		scores = scores, -- turns each player finished
		winner = state.winner,
		loser = state.loser, -- who knocked it over
		move = state.fallMove, -- on which move of the game
		levels = levels, -- how tall it stood when it went
		complete = complete,
		tallest = state.tallest,
		moved = state.total, -- blocks moved and placed before it fell
		solo = state.seats == 1,
	}
end

-- view(state): the scoreboard (the chalk sign and the HUD): JSON-friendly.
function Rules.view(state: State): { [string]: any }
	local seats = {}
	local order = {}
	for i = 1, state.seats do
		seats[i] = {
			moves = state.moves[i],
			idle = state.idle[i],
			gone = state.gone[i],
			computer = state.computer[i],
		}
		if not state.gone[i] then
			table.insert(order, i)
		end
	end
	local levels, complete = Tower.levelsOf(state.tower)
	local left, total = Rules.clock(state)
	local tw = state.tower
	local held = if tw.held ~= 0 then tw.blocks[tw.held] else nil
	return {
		kind = "jenga",
		seats = seats,
		order = order,
		turn = if state.done then nil else state.seat,
		turnIndex = state.turnIndex,
		phase = state.phase,
		clock = math.ceil(left),
		clockTotal = total,
		warn = not state.done and state.phase ~= "settle" and not state.auto and left <= Rules.WARN_SECS,
		auto = state.auto,
		levels = levels,
		complete = complete,
		tallest = state.tallest,
		moved = state.total,
		holding = held ~= nil,
		committed = held ~= nil and math.abs(held.along) >= Tower.COMMIT,
		inHand = tw.inHand ~= 0,
		done = state.done,
		loser = state.loser,
		winner = state.winner,
		fallMove = if state.done then state.fallMove else nil,
		lastTap = state.lastTap,
	}
end

export type Frame = {
	t: number,
	seat: number,
	phase: string,
	clock: number,
	turnIndex: number,
	tower: View.Frame,
	ev: { Event },
	tap: { [string]: any }?,
}

-- frame(state): the next frame of the stream. It carries the events since the last frame, so call it once per
-- send (20 times a second while anything moves; a quiet tower needs none).
function Rules.frame(state: State): Frame
	local towerFrame = View.frame(state.tower, state.sentKey)
	state.sentKey = towerFrame.key
	local ev = state.events
	state.events = {}
	local tap = state.lastTap
	state.lastTap = nil
	return {
		t = state.time,
		seat = state.seat,
		phase = state.phase,
		clock = math.max(state.clock, 0),
		turnIndex = state.turnIndex,
		tower = towerFrame,
		ev = ev,
		tap = tap,
	}
end

function Rules.snapshot(state: State): Tower.Snapshot
	return Tower.snapshot(state.tower)
end

return Rules
