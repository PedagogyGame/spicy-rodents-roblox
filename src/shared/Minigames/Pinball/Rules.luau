--!strict
-- ReplicatedStorage.Shared.Minigames.Pinball.Rules
-- The three pinball machines in the shape of the Minigame contract (Shared/Minigames/Minigame: def, init,
-- input, result, verbs, turn, skipTurn, view, gone), so the ordinary lobby, turn order, leaving and end card
-- can carry them (checklist PIN-R5: one to four players alternate ball by ball; no computer opponent).
-- A pinball turn is one ball, and it is not decided by one message: the player's machine runs the model live
-- and sends its input log in segments; each segment is replayed here (Replay) and the replay is the game.
-- turn() is the player whose ball is up; it moves on by itself when that ball has drained and its bonus is
-- counted. skipTurn() abandons the ball in play (it is played out dead: the game's "miss").
-- A segment comes in as the verb "log" with the arguments the wire carries, { fromTick, toTick, packed
-- changes, sum? } (InputLog.pack; Minigames/Games rule 1; sum is the player's Replay.sum at toTick, optional),
-- or as "seg" with the segment itself (specs, tools). view().tick is the acknowledgement: the next segment
-- must start there.
-- A "log" that runs past the end of its ball is played to the end of the ball and answered true, "overrun"
-- (the view then shows drift: the sender is sent a clone); one that is ahead of the server's clock is refused
-- "ahead" with nothing played, to be sent in again a moment later.
-- The server's own verbs: "thump" lets one thump on the glass into the log (an animal landed on the cabinet):
-- it is half a nudge that can warn but never tilt, and a second one inside two seconds is refused. "retire"
-- takes a seat out for good (the player walked away or was bitten, C13): the ball in play is played out dead,
-- their later balls are passed over and the score so far is kept; the Session's gone(state, seat) does the
-- same. "clock" { seconds } tells the replay the server's time (Replay.clock), before every "log" and a few
-- times a second besides: a ball whose log has fallen more than Replay.BEHIND_SECONDS behind is taken
-- (Replay.lapse) and the game is marked late. result().fair says whether the game may go on the board.
-- Free play: money is "none"; nothing here knows a credit, a replay award or a match number (PIN-R4).
-- TWO SHAPES of the same rules:
--   * forTable(tableId): one machine's rules; def.game is the table id (pinball_acorn, ...).
--   * game: the registry's ONE game "pinball" (Minigames/Games, Pinball/Spec), whose three stations differ
--     only by `variant`. init() cannot know the station, so the game starts switched off: the station's
--     Table sends the server verb "machine" { variant } (acorn | rodent | space, or a table id) when the
--     Session starts, and from then on it is that machine. CLIENT_VERBS is what its Spec declares.
-- Pure; Lune-tested (tests/unit/pinball_rules.spec.luau).
-- Interface: forTable(tableId) -> Minigame.Rules (cached); game: Minigame.Rules; GAME, CLIENT_VERBS; GAMES
--   (the three table ids); MAX_PLAYERS; replay(state) -> Replay.State? (the replay inside either shape's state);
--   the rules' view(state) is { game, title, variant?, freePlay, phase, up, ball, balls, players = { { score,
--   gone, extraBall, stats } }, status, say, sayValue, saveOn, tilted, warnings, tick, idle, drift, suspect,
--   late, epoch, pace (seconds the ball's log is ahead of the clock) }; before the machine is named,
--   game.view is { game = "pinball", freePlay = true, phase = "off" }

local InputLog = require("./InputLog")
local Machine = require("./Machine")
local Minigame = require("../Minigame")
local Physics = require("./Physics")
local Replay = require("./Replay")
local Tables = require("./Tables")

local Rules = {}

Rules.GAMES = Tables.IDS
Rules.MAX_PLAYERS = Machine.MAX_PLAYERS

local PHASE_NAMES = { "play", "bonus", "over" }

local VARIANT_OF: { [string]: string } = {}
for variant, id in Tables.VARIANTS do
	VARIANT_OF[id] = variant
end

local function build(tableId: string): Minigame.Rules
	local tbl = Tables.need(tableId)
	local rules = {}

	rules.def = {
		game = tableId,
		title = tbl.title,
		class = "shared_table",
		seats = Machine.MAX_PLAYERS,
		-- the player's machine runs the model; the server's replay of the input log is the score of record
		authority = "client_replay",
		money = "none",
	} :: Minigame.Def
	rules.verbs = { log = true, seg = true, thump = true, retire = true, clock = true }
	rules.serverVerbs = { thump = true, retire = true, clock = true }

	function rules.init(seats: number, seed: number): any
		return Replay.new(tableId, seed, seats)
	end

	function rules.input(state: any, seat: number, verb: string, args: { any }?): (boolean, string?)
		local r = state :: Replay.State
		if verb == "log" then
			-- as it travels: fromTick, toTick, the changes packed in a string; and, if the player's machine sends
			-- it, its Replay.sum at toTick (the replay notes a difference as drift; the segment is taken all the same)
			local seg = args and InputLog.unpack(args[1], args[2], args[3])
			if seg == nil then
				return false, "no segment"
			end
			local sum = args and args[4]
			local ok, why = Replay.feed(r, seat, seg, nil, if type(sum) == "number" then sum else nil)
			return ok, why
		elseif verb == "seg" then
			local seg = args and args[1]
			if type(seg) ~= "table" then
				return false, "no segment"
			end
			local ok, why = Replay.feed(r, seat, seg)
			return ok, why
		elseif verb == "clock" then
			-- the server's: its own time, in seconds. A ball whose log has fallen too far behind is taken
			local seconds = args and args[1]
			if type(seconds) ~= "number" or seconds ~= seconds then
				return false, "no clock"
			end
			if Replay.clock(r, seconds) == "behind" then
				Replay.lapse(r)
			end
			return true
		elseif verb == "retire" then
			-- the server's: this seat has gone for good (walked away, bitten); the score so far is kept
			if Replay.over(r) then
				return false, "the game is over"
			end
			Replay.retire(r, seat)
			return true
		elseif verb == "thump" then
			if Replay.over(r) then
				return false, "the game is over"
			end
			if not Replay.grantThump(r) then
				return false, "too soon"
			end
			return true
		end
		return false, "verb"
	end

	function rules.turn(state: any): number?
		local r = state :: Replay.State
		if Replay.over(r) then
			return nil
		end
		return r.m.up
	end

	function rules.skipTurn(state: any)
		Replay.skip(state :: Replay.State)
	end

	-- the Session's own word for "this seat has left for good"
	function rules.gone(state: any, seat: number)
		Replay.retire(state :: Replay.State, seat)
	end

	function rules.result(state: any): Minigame.Result?
		local r = state :: Replay.State
		if not Replay.over(r) then
			return nil
		end
		local m = r.m
		local scores: { [number]: number } = {}
		local best, winner, tie = -1, nil :: number?, false
		for seat = 1, m.players do
			scores[seat] = m.scores[seat]
			if m.scores[seat] > best then
				best, winner, tie = m.scores[seat], seat, false
			elseif m.scores[seat] == best then
				tie = true
			end
		end
		local stats = {}
		for seat = 1, m.players do
			stats[seat] = table.clone(m.stats[seat])
		end
		return {
			done = true,
			scores = scores,
			winner = if tie then nil else winner,
			stats = stats,
			suspect = r.suspect,
			late = r.late,
			fair = Replay.fair(r), -- only a fair game takes a place on the machine's board (HighScores.add)
		}
	end

	function rules.view(state: any): { [string]: any }
		local r = state :: Replay.State
		local m = r.m
		local players = {}
		for seat = 1, m.players do
			players[seat] = {
				score = m.scores[seat],
				gone = m.gone[seat],
				extraBall = m.extras[seat] > 0,
				stats = table.clone(m.stats[seat]),
			}
		end
		local over = m.phase == Machine.PHASE.OVER
		return {
			game = tableId,
			title = tbl.title,
			variant = VARIANT_OF[tableId],
			freePlay = true,
			phase = PHASE_NAMES[m.phase],
			up = if over then nil else m.up,
			ball = m.ball,
			balls = Machine.BALLS,
			players = players,
			status = if over then "GAME OVER" else tbl.sheet.status(m, m.sheets[m.up]),
			say = if m.sayLeft > 0 or over then tbl.sheet.text[m.say] or Machine.TEXT[m.say] else nil,
			sayValue = m.sayValue,
			saveOn = m.saveLeft > 0,
			tilted = m.tilted,
			warnings = m.warnings,
			tick = r.tick,
			idle = Replay.idleSeconds(r),
			drift = r.drift,
			suspect = r.suspect,
			late = r.late,
			epoch = r.epoch,
			pace = Replay.pace(r) / Physics.HZ,
		}
	end

	return rules
end

local CACHE: { [string]: Minigame.Rules } = {}

function Rules.forTable(tableId: string): Minigame.Rules
	local rules = CACHE[tableId]
	if rules == nil then
		rules = build(tableId)
		CACHE[tableId] = rules
	end
	return rules
end

-- ---------------------------------------------------------------------------------------------------------
-- The registry's one game
-- ---------------------------------------------------------------------------------------------------------
Rules.GAME = "pinball"
Rules.CLIENT_VERBS = { "log" }

type Station = {
	seats: number,
	seed: number,
	rules: Minigame.Rules?, -- the machine's own rules, once the station has said which machine it is
	r: Replay.State?,
}

do
	local game = {}

	game.def = {
		game = Rules.GAME,
		title = "Pinball",
		class = "shared_table",
		seats = Machine.MAX_PLAYERS,
		authority = "client_replay",
		money = "none",
	} :: Minigame.Def
	game.verbs = { log = true, seg = true, machine = true, thump = true, retire = true, clock = true }
	game.serverVerbs = { machine = true, thump = true, retire = true, clock = true }

	function game.init(seats: number, seed: number): any
		local st: Station = { seats = seats, seed = seed, rules = nil, r = nil }
		return st
	end

	function game.input(state: any, seat: number, verb: string, args: { any }?): (boolean, string?)
		local st = state :: Station
		if verb == "machine" then
			if st.rules then
				return false, "the machine is already on"
			end
			local id = Tables.forVariant(args and args[1])
			if id == nil then
				return false, "no such machine"
			end
			local rules = Rules.forTable(id)
			st.rules = rules
			st.r = rules.init(st.seats, st.seed)
			return true
		end
		local rules = st.rules
		if rules == nil then
			return false, "the machine is not switched on"
		end
		return rules.input(st.r, seat, verb, args)
	end

	function game.turn(state: any): number?
		local st = state :: Station
		local rules = st.rules
		if rules == nil then
			return 1 -- (the station names its machine through the turn's seat)
		end
		return (rules.turn :: (any) -> number?)(st.r)
	end

	function game.skipTurn(state: any)
		local st = state :: Station
		local rules = st.rules
		if rules and rules.skipTurn then
			rules.skipTurn(st.r)
		end
	end

	function game.gone(state: any, seat: number)
		local st = state :: Station
		local rules = st.rules
		if rules and rules.gone then
			rules.gone(st.r, seat)
		end
	end

	function game.result(state: any): Minigame.Result?
		local st = state :: Station
		local rules = st.rules
		if rules == nil then
			return nil
		end
		return rules.result(st.r)
	end

	function game.view(state: any): { [string]: any }
		local st = state :: Station
		local rules = st.rules
		if rules == nil or rules.view == nil then
			return { game = Rules.GAME, freePlay = true, phase = "off" }
		end
		local view = rules.view(st.r)
		view.table = view.game
		view.game = Rules.GAME
		return view
	end

	Rules.game = game :: Minigame.Rules
end

-- replay(state): the Replay inside a rules state of either shape (nil while the registry's game is off). The
-- station's Table reads it for the cues and the frames (Stream.read) and for fair() at the end.
function Rules.replay(state: any): Replay.State?
	if type(state) ~= "table" then
		return nil
	end
	if state.m ~= nil then
		return state :: Replay.State
	end
	return state.r
end

return Rules
