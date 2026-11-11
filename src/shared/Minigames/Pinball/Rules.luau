--!strict
-- ReplicatedStorage.Shared.Minigames.Pinball.Rules
-- The three pinball machines in the shape of the Minigame contract (Shared/Minigames/Minigame: def, init,
-- input, result, verbs, turn, skipTurn, view), so the ordinary lobby, turn order, leaving and end card can
-- carry them (checklist PIN-R5: one to four players alternate ball by ball; no computer opponent).
-- A pinball turn is one ball, and it is not decided by one message: the player's machine runs the model live
-- and sends its input log in segments (verb "seg"); each segment is replayed here (Replay) and the replay is
-- the game. turn() is the player whose ball is up; it moves on by itself when that ball has drained and its
-- bonus is counted. skipTurn() abandons the ball in play (it is played out dead: the game's "miss").
-- The server's own verb "thump" lets one thump on the glass into the log (an animal landed on the cabinet):
-- it is a nudge that can warn but never tilt. The server's verb "retire" takes a seat out for good (the
-- player walked away or was bitten, C13): the ball in play is played out dead, their later balls are passed
-- over and the score so far is kept.
-- Free play: money is "none"; nothing here knows a credit, a replay award or a match number (PIN-R4).
-- Pure; Lune-tested (tests/unit/pinball_rules.spec.luau).
-- Interface: forTable(tableId) -> Minigame.Rules (cached); GAMES (the three ids); MAX_PLAYERS;
--   the rules' view(state) is { game, title, freePlay, phase, up, ball, balls, players = { { score, extraBall,
--   stats } }, status, say, sayValue, saveOn, tilted, warnings, tick, suspect }

local Machine = require("./Machine")
local Minigame = require("../Minigame")
local Replay = require("./Replay")
local Tables = require("./Tables")

local Rules = {}

Rules.GAMES = Tables.IDS
Rules.MAX_PLAYERS = Machine.MAX_PLAYERS

local PHASE_NAMES = { "play", "bonus", "over" }

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
	rules.verbs = { seg = true, thump = true, retire = true }
	rules.serverVerbs = { thump = true, retire = true }

	function rules.init(seats: number, seed: number): any
		return Replay.new(tableId, seed, seats)
	end

	function rules.input(state: any, seat: number, verb: string, args: { any }?): (boolean, string?)
		local r = state :: Replay.State
		if verb == "seg" then
			local seg = args and args[1]
			if type(seg) ~= "table" then
				return false, "no segment"
			end
			return Replay.feed(r, seat, seg)
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
			Replay.grantThump(r)
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
			suspect = r.suspect,
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

return Rules
