--!strict
-- ReplicatedStorage.Shared.Minigames.Session
-- One table, lane or cabinet's session on the Minigame framework (BUILD_PLAN §1.1 rule 13, §3.16, D28): seats,
-- a short lobby so friends can join (or Space to start at once; a one-seat game starts on the spot), turn
-- order from the rules module, a turn clock (a turn left idle is played out as a miss; two in a row and the
-- player is taken off the table), players who walk away mid-game (their turns are played out as misses so
-- everyone else's game still finishes), the end card and "play again". Anyone may walk up and join while the
-- lobby is open; one player is enough. The rules module owns the game itself (Minigame.Rules plus turn(),
-- view(), skipTurn()); the server's MinigameService owns the engine side. Pure; Lune-tested
-- (tests/unit/minigames_session.spec.luau). Keys are opaque player handles (Player or a test stub).
-- The end of a game is announced exactly once, as a "done" event from step(), however it ended (the last
-- input through apply(), a skipped turn, a timeout).
-- Games that are not turn-based (Minigames/Games: flow "live", "solo", "match") use the same session with the
-- rules' optional hooks: step(state, dt) advances the game on every Session.step (a rally's ball, a machine, a
-- match clock; the game may end there); with no turn() any seated player's input is taken, and opts.idleSeconds
-- takes a seat off after that long without an accepted input (computer players, keys with ai = true, never
-- idle out); gone(state, seat) tells the rules a seat left or was taken off; def.lateJoin lets a seat be taken
-- (or a vacated one retaken) while the game is on, told to the rules by join(state, seat); applyAs sends a
-- server verb for a named seat when there is no turn to resolve it from.
-- Interface: new(rules, opts) -> Session; join(s, key, name, now) -> (ok, why?, seat?); leave(s, key, now)
--   -> seat?; start(s, now) -> (ok, why?); apply(s, key, verb, args, now) -> (ok, why?); applyAs(s, seat, verb,
--   args, now) -> (ok, why?); step(s, now, busy?) -> { Event }; seatOf(s, key) -> seat?; turnKey(s) -> key?;
--   again(s, now) -> (ok, why?); view(s, now) -> table; touch(s, now); reset(s)

local Minigame = require("./Minigame")

export type Opts = {
	lobbySeconds: number?, -- 0 = start on the first join
	turnSeconds: number?, -- idle turn clock (nil = none)
	doneSeconds: number?, -- end card before the table resets
	idleSeconds: number?, -- with nobody's turn: a seat with no accepted input for this long is taken off (nil = never)
	maxTimeouts: number?,
	seed: number?,
}

export type Event = { kind: string, seat: number?, key: any?, why: string? }

export type Session = {
	rules: any,
	opts: Opts,
	phase: "idle" | "lobby" | "playing" | "done",
	seats: { any }, -- seat -> key
	names: { string },
	gone: { [number]: boolean },
	timeouts: { [number]: number },
	lobbyEnds: number,
	doneEnds: number,
	turnStarted: number,
	game: Minigame.Game?,
	games: number,
	lastTurn: number?,
	result: { [string]: any }?,
	pendingMode: string?,
	doneTold: boolean, -- the "done" event has gone out for this game
	active: { [number]: number }, -- seat -> when its last input was accepted (the idle clock of a game without turns)
	steppedAt: number, -- when the rules' step() last ran
}

local Session = {}

Session.DEFAULTS = { lobbySeconds = 10, turnSeconds = 45, doneSeconds = 25, maxTimeouts = 2 }

local function opt(s: Session, k: string): number
	local v = (s.opts :: any)[k]
	if v == nil then
		return (Session.DEFAULTS :: any)[k]
	end
	return v
end

function Session.new(rules: any, opts: Opts?): Session
	assert(Minigame.check(rules))
	return {
		rules = rules,
		opts = opts or {},
		phase = "idle",
		seats = {},
		names = {},
		gone = {},
		timeouts = {},
		lobbyEnds = 0,
		doneEnds = 0,
		turnStarted = 0,
		game = nil,
		games = 0,
		lastTurn = nil,
		result = nil,
		pendingMode = nil,
		doneTold = false,
		active = {},
		steppedAt = 0,
	}
end

function Session.reset(s: Session)
	s.phase = "idle"
	table.clear(s.seats)
	table.clear(s.names)
	table.clear(s.gone)
	table.clear(s.timeouts)
	s.game = nil
	s.lastTurn = nil
	s.result = nil
	s.pendingMode = nil
	s.doneTold = false
	table.clear(s.active)
end

function Session.seatOf(s: Session, key: any): number?
	for i, k in s.seats do
		if k == key and not s.gone[i] then
			return i
		end
	end
	return nil
end

function Session.turn(s: Session): number?
	local g = s.game
	if s.phase ~= "playing" or g == nil then
		return nil
	end
	-- (every game so far takes turns; one that does not has nobody's turn)
	local turn = g.rules.turn
	return if turn then turn(g.state) else nil
end

function Session.turnKey(s: Session): any?
	local seat = Session.turn(s)
	return if seat then s.seats[seat] else nil
end

function Session.touch(s: Session, now: number)
	s.turnStarted = now
end

function Session.start(s: Session, now: number): (boolean, string?)
	if s.phase ~= "lobby" then
		return false, if s.phase == "playing" then "already playing" else "nobody seated"
	end
	if #s.seats == 0 then
		return false, "nobody seated"
	end
	s.games += 1
	local seed = (s.opts.seed or 1) * 7919 + s.games * 104729
	s.game = Minigame.start(s.rules, #s.seats, seed)
	if s.pendingMode and s.rules.verbs.mode then
		Minigame.input(s.game :: Minigame.Game, 1, "mode", { s.pendingMode })
	end
	s.phase = "playing"
	s.turnStarted = now
	s.lastTurn = nil
	s.result = nil
	s.doneTold = false
	table.clear(s.timeouts)
	table.clear(s.active)
	for i = 1, #s.seats do
		s.active[i] = now
	end
	s.steppedAt = now
	return true
end

-- join: a seat in the lobby (or the idle table, which opens the lobby). One-seat games start at once.
function Session.join(s: Session, key: any, name: string, now: number): (boolean, string?, number?)
	local existing = Session.seatOf(s, key)
	if existing then
		return true, "already seated", existing
	end
	if s.phase == "playing" then
		local g = s.game
		if g == nil or not s.rules.def.lateJoin then
			return false, "a game is in progress: wait for it to finish or try another table"
		end
		-- a game that takes players while it is on: a vacated seat first, then a new one
		local vacated: number? = nil
		for i = 1, #s.seats do
			if s.gone[i] then
				vacated = i
				break
			end
		end
		if vacated == nil and #s.seats >= s.rules.def.seats then
			return false, "the table is full"
		end
		local late: number = vacated or (#s.seats + 1)
		s.seats[late] = key
		s.names[late] = name
		s.gone[late] = nil
		s.timeouts[late] = 0
		s.active[late] = now
		g.seats = #s.seats
		local seatJoined = g.rules.join
		if seatJoined then
			seatJoined(g.state, late)
		end
		return true, nil, late
	end
	if s.phase == "done" then
		-- the end card is up: a newcomer starts a fresh table
		Session.reset(s)
	end
	if #s.seats >= s.rules.def.seats then
		return false, "the table is full"
	end
	table.insert(s.seats, key)
	table.insert(s.names, name)
	local seat = #s.seats
	if s.phase == "idle" then
		s.phase = "lobby"
		s.lobbyEnds = now + opt(s, "lobbySeconds")
	end
	if s.rules.def.seats == 1 or opt(s, "lobbySeconds") <= 0 then
		Session.start(s, now)
	end
	return true, nil, seat
end

local function anyoneLeft(s: Session): boolean
	for i = 1, #s.seats do
		if not s.gone[i] then
			return true
		end
	end
	return false
end

-- A seat has gone while the game is on: the rules hear of it (a rally is forfeited, a team is a player short).
local function tellGone(s: Session, seat: number)
	local g = s.game
	if s.phase == "playing" and g and g.rules.gone then
		g.rules.gone(g.state, seat)
	end
end

-- leave: off the table. In the lobby the seat is removed; mid-game it is marked gone and its turns are
-- played out as misses. At the end card it is marked gone too, never removed: the finished game's sheets and
-- result are numbered by the seats that played it, so moving the others up would put the leaver's score
-- under the next player's name. Returns the seat that was left (nil if not seated).
function Session.leave(s: Session, key: any, _now: number): number?
	local seat = Session.seatOf(s, key)
	if seat == nil then
		return nil
	end
	if s.phase == "lobby" then
		table.remove(s.seats, seat)
		table.remove(s.names, seat)
		-- seats after it move up one (the gone flags follow them)
		local gone = {}
		for i, g in s.gone do
			if i < seat then
				gone[i] = g
			elseif i > seat then
				gone[i - 1] = g
			end
		end
		s.gone = gone
		if not anyoneLeft(s) then
			Session.reset(s)
		end
	else
		s.gone[seat] = true
		tellGone(s, seat)
		if not anyoneLeft(s) then
			Session.reset(s)
		end
	end
	return seat
end

local function finishIfDone(s: Session, now: number): boolean
	local g = s.game
	if g == nil then
		return false
	end
	local r = Minigame.result(g)
	if r then
		s.phase = "done"
		s.result = r
		s.doneEnds = now + opt(s, "doneSeconds")
		return true
	end
	return false
end

-- Play out the turns of seats that have gone (and nothing else).
local function skipGone(s: Session, now: number, events: { Event })
	local guard = 0
	while s.phase == "playing" and guard < 200 do
		guard += 1
		local seat = Session.turn(s)
		if seat == nil or not s.gone[seat] then
			break
		end
		local g = s.game :: Minigame.Game
		local skip = g.rules.skipTurn
		if skip == nil then
			break -- a game with turns and no way to skip one: nothing more can be done here
		end
		skip(g.state)
		table.insert(events, { kind = "skipped", seat = seat, why = "left" })
		finishIfDone(s, now)
	end
end

-- apply: a validated input from a seated player (or the server's own verbs, key = "server").
function Session.apply(s: Session, key: any, verb: string, args: { any }?, now: number): (boolean, string?)
	local g = s.game
	if verb == "mode" and s.phase == "lobby" then
		if Session.seatOf(s, key) == nil then
			return false, "not seated"
		end
		local m = if args then tostring(args[1]) else ""
		local modes = s.rules.MODES
		if type(modes) ~= "table" or table.find(modes, m) == nil then
			return false, "mode"
		end
		s.pendingMode = m
		return true
	end
	if s.phase ~= "playing" or g == nil then
		return false, "no game in progress"
	end
	local seat: number?
	if key == "server" then
		seat = Session.turn(s)
	else
		seat = Session.seatOf(s, key)
	end
	if seat == nil then
		return false, "not seated"
	end
	local ok, why = Minigame.input(g, seat, verb, args)
	if ok then
		s.turnStarted = now
		s.timeouts[seat] = 0
		s.active[seat] = now
		finishIfDone(s, now)
	end
	return ok, why
end

-- applyAs: a server verb for a named seat (a game without turns has no turn to resolve "server" from). It is
-- the server's own doing, so nobody's idle clock is touched.
function Session.applyAs(s: Session, seat: number, verb: string, args: { any }?, now: number): (boolean, string?)
	local g = s.game
	if s.phase ~= "playing" or g == nil then
		return false, "no game in progress"
	end
	local ok, why = Minigame.input(g, seat, verb, args)
	if ok then
		finishIfDone(s, now)
	end
	return ok, why
end

-- step: lobby countdown, turn clock, the end card. Returns what happened.
function Session.step(s: Session, now: number, busy: boolean?): { Event }
	local events: { Event } = {}
	if s.phase == "lobby" and now >= s.lobbyEnds then
		if Session.start(s, now) then
			table.insert(events, { kind = "start" })
		end
	end
	if s.phase == "playing" then
		-- a game that moves between inputs (a rally, a machine, a match clock) advances here, and may end here
		local live = s.game :: Minigame.Game
		local advance = live.rules.step
		if advance then
			advance(live.state, math.max(0, now - s.steppedAt))
			finishIfDone(s, now)
		end
		s.steppedAt = now
	end
	if s.phase == "playing" then
		skipGone(s, now, events)
		local tsec: number = s.opts.turnSeconds or Session.DEFAULTS.turnSeconds
		local seat = Session.turn(s)
		if busy then
			s.turnStarted = now
		elseif seat and tsec > 0 and now - s.turnStarted > tsec then
			local g = s.game :: Minigame.Game
			local skip = g.rules.skipTurn
			if skip then
				skip(g.state)
			end
			s.timeouts[seat] = (s.timeouts[seat] or 0) + 1
			s.turnStarted = now
			table.insert(events, { kind = "timeout", seat = seat, key = s.seats[seat] })
			if s.timeouts[seat] >= opt(s, "maxTimeouts") then
				local key = s.seats[seat]
				s.gone[seat] = true
				tellGone(s, seat)
				table.insert(events, { kind = "removed", seat = seat, key = key, why = "idle" })
				if not anyoneLeft(s) then
					Session.reset(s)
					table.insert(events, { kind = "reset" })
					return events
				end
			end
			finishIfDone(s, now)
			skipGone(s, now, events)
		end
		-- nobody's turn (a live game): each seat has its own idle clock, if the game asks for one
		local idle = s.opts.idleSeconds
		if seat == nil and idle ~= nil and idle > 0 and s.phase == "playing" then
			for i, key in s.seats do
				if s.gone[i] or (type(key) == "table" and key.ai == true) then
					continue
				end
				if busy then
					s.active[i] = now
				elseif now - (s.active[i] or now) > idle then
					s.gone[i] = true
					tellGone(s, i)
					table.insert(events, { kind = "removed", seat = i, key = key, why = "idle" })
				end
			end
			if not anyoneLeft(s) then
				Session.reset(s)
				table.insert(events, { kind = "reset" })
				return events
			end
			finishIfDone(s, now)
		end
		local t = Session.turn(s)
		if t ~= s.lastTurn and s.phase == "playing" then
			s.lastTurn = t
			s.turnStarted = now
			if t then
				table.insert(events, { kind = "turn", seat = t, key = s.seats[t] })
			end
		end
		if s.phase == "playing" then
			finishIfDone(s, now)
		end
	end
	if s.phase == "done" then
		-- however the game ended (an input through apply, a skip, a timeout): said once
		if not s.doneTold then
			s.doneTold = true
			table.insert(events, { kind = "done" })
		end
		if now >= s.doneEnds then
			Session.reset(s)
			table.insert(events, { kind = "reset" })
		end
	end
	return events
end

-- again: the same players (those still seated) start a new game from the end card.
function Session.again(s: Session, now: number): (boolean, string?)
	if s.phase ~= "done" then
		return false, "not finished"
	end
	local keys, names = {}, {}
	for i, k in s.seats do
		if not s.gone[i] then
			table.insert(keys, k)
			table.insert(names, s.names[i])
		end
	end
	local mode = s.result and s.result.mode
	Session.reset(s)
	if #keys == 0 then
		return false, "nobody seated"
	end
	s.seats = keys
	s.names = names
	s.phase = "lobby"
	s.pendingMode = if type(mode) == "string" then mode else nil
	return Session.start(s, now)
end

-- view: what clients and the scoreboards draw.
function Session.view(s: Session, now: number): { [string]: any }
	local g = s.game
	local seats = {}
	for i, name in s.names do
		seats[i] = { name = name, gone = s.gone[i] == true }
	end
	return {
		phase = s.phase,
		seats = seats,
		maxSeats = s.rules.def.seats,
		lobbyLeft = if s.phase == "lobby" then math.max(0, math.ceil(s.lobbyEnds - now)) else nil,
		doneLeft = if s.phase == "done" then math.max(0, math.ceil(s.doneEnds - now)) else nil,
		turn = Session.turn(s),
		turnLeft = if s.phase == "playing"
			then math.max(0, math.ceil((s.opts.turnSeconds or Session.DEFAULTS.turnSeconds) - (now - s.turnStarted)))
			else nil,
		game = if g and g.rules.view then g.rules.view(g.state) else nil,
		result = s.result,
		mode = s.pendingMode,
	}
end

return Session
