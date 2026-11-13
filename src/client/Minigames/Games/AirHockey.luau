--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Minigames.Games.AirHockey
-- Air hockey's client half on the minigame framework (Client/Minigames/ClientGame): the owner's AER / 01 table in
-- the bowling alley's games room.
--   The seated player's controller is Client/Minigames/AirHockey/Controller (the mallet under the hand with no
--     delay; first person or from above).
--   Everyone near the table is sent the referee's stream ("air_hockey") and sees the same match on the same
--     parts: watch() hands each message to Client/Minigames/AirHockey/Rink, which replays it. "air_hockey_seat"
--     is the referee's word to one player that an end is theirs; "air_hockey_rest" says the table has reset.
--   The lobby: Start, the computer's difficulty if nobody takes the other end (his Lounge / Club / Pro), Leave.
--   The scorecard: both ends, who has them and the score; the end card says who won.
--   Sound: named cue points only, no asset ids yet (a strike by its strength, a rail, a post, a goal for and
--     against, a goal seen by a bystander, the serve, the match won and lost).
-- Space is the game's own key (serve; in the lobby it starts, as everywhere), so the framework's is swallowed.
-- Interface: a ClientGame.ClientGame

local Import = require("../../Import")
local Layout =
	Import.shared("Minigames/AirHockey/Layout") :: typeof(require("../../../shared/Minigames/AirHockey/Layout"))
local Rules = Import.shared("Minigames/AirHockey/Rules") :: typeof(require("../../../shared/Minigames/AirHockey/Rules"))
local ClientGame = require("../ClientGame")
local Controller = require("../AirHockey/Controller")
local Rink = require("../AirHockey/Rink")

local MODE_WORDS = { easy = "Lounge (easy)", medium = "Club (medium)", hard = "Pro (hard)" }

-- seat -> the end it plays, from a view (before the match starts: the first seat at Glacier)
local function sideOf(view: { [string]: any }, seat: number): number
	local g = view.game
	local s = g and g.seats and g.seats[seat]
	if s and type(s.side) == "number" then
		return s.side
	end
	return if seat == 1 then 0 else 1
end

local function card(frame: Frame, view: { [string]: any }, you: number?, kit: any)
	local C, label = kit.C, kit.label
	local g = view.game
	local score = (g and g.score) or { 0, 0 }
	frame.Size = UDim2.fromOffset(360, 112)
	frame.Position = UDim2.new(1, -372, 1, -124)
	label(
		frame,
		`AIR HOCKEY   first to {Rules.TO}`,
		UDim2.new(1, -12, 0, 22),
		UDim2.fromOffset(6, 4),
		C.GOLD,
		Enum.Font.FredokaOne
	)
	local names = { [0] = "the computer", [1] = "the computer" }
	if view.phase == "lobby" then
		names = { [0] = "open", [1] = "open" }
	end
	for seat, s in view.seats or {} do
		if not s.gone then
			names[sideOf(view, seat)] = s.name .. (if seat == you then " (you)" else "")
		end
	end
	for side = 0, 1 do
		local y = 30 + side * 38
		label(
			frame,
			string.upper(Layout.SIDE_NAMES[side]),
			UDim2.new(0.26, 0, 0, 30),
			UDim2.fromOffset(6, y),
			if side == 0 then C.CYAN else C.GOLD,
			Enum.Font.GothamBold
		)
		label(frame, names[side], UDim2.new(0.5, 0, 0, 30), UDim2.new(0.27, 0, 0, y), C.WHITE, Enum.Font.GothamBold)
		label(
			frame,
			tostring(score[side + 1] or 0),
			UDim2.new(0.2, 0, 0, 34),
			UDim2.new(0.78, 0, 0, y - 2),
			C.GOLD,
			Enum.Font.FredokaOne
		)
	end
end

local function endCard(view: { [string]: any }, you: number?): { [string]: any }?
	local r = view.result
	if r == nil then
		return nil
	end
	local rows = {}
	for seat, s in view.seats do
		local side = sideOf(view, seat)
		table.insert(rows, {
			seat = seat,
			name = s.name,
			gone = s.gone,
			side = string.upper(Layout.SIDE_NAMES[side]),
			total = r.scores[seat] or 0,
			place = if r.winner == seat then 1 else 2,
		})
	end
	local winner = r.winner and view.seats[r.winner]
	local line = if winner then `{winner.name} wins` else "Full time"
	if you ~= nil then
		line = if r.winner == you then "MATCH WON." else "WELL PLAYED."
	end
	return {
		title = "AIR HOCKEY",
		line = line,
		rows = rows,
		cols = {
			{ title = "", key = "place", x = 0.02, w = 0.07 },
			{ title = "PLAYER", key = "name", x = 0.1, w = 0.45 },
			{ title = "END", key = "side", x = 0.56, w = 0.22 },
			{ title = "GOALS", key = "total", x = 0.8, w = 0.18, strong = true },
		},
		foot = "The table is free again in %d s.",
	}
end

local entry: ClientGame.ClientGame = {
	game = "air_hockey",
	help = Controller.HELP,
	title = function(_msg: { [string]: any }): string
		return "Air hockey"
	end,
	buttons = function(phase: string, view: { [string]: any }?): { { string } }?
		if phase == "joined" or phase == "lobby" then
			local mode = (view and view.mode) or "medium"
			local bar: { { string } } = { { "start", "Start (Space)" } }
			for _, m in Rules.MODES do
				table.insert(bar, { m, (if m == mode then "> " else "") .. MODE_WORDS[m] })
			end
			table.insert(bar, { "leave", "Leave (Q)" })
			return bar
		elseif phase == "done" then
			return { { "again", "Play again" }, { "leave", "Leave (Q)" } }
		end
		-- (while a match is on the controller's own bar is up: View, Leave)
		return nil
	end,
	keys = { Space = "" },
	new = Controller.new,
	card = card,
	cardSig = function(view: { [string]: any }): any
		local g = view.game
		return if g and g.score then `{g.score[1]}-{g.score[2]}` else ""
	end,
	endCard = endCard,
	kinds = { "air_hockey", "air_hockey_seat", "air_hockey_rest" },
	watch = function(msg: { [string]: any }, place: ClientGame.Place?): any
		if type(msg.station) ~= "string" then
			return nil
		end
		if msg.kind == "air_hockey" then
			local rink = Rink.get(msg.station, place)
			Rink.push(rink, msg)
			return rink
		elseif msg.kind == "air_hockey_rest" then
			Rink.rest(Rink.get(msg.station, place))
		end
		return nil
	end,
	sounds = {
		["air_hockey.strike"] = "", -- a mallet meets the puck (volume: how hard)
		["air_hockey.rail"] = "", -- the puck off a rail
		["air_hockey.post"] = "", -- the puck off a goal post
		["air_hockey.serve"] = "", -- the puck is let go
		["air_hockey.goal_for"] = "", -- you scored
		["air_hockey.goal_against"] = "", -- they scored
		["air_hockey.goal"] = "", -- a goal at a table you are watching
		["air_hockey.win"] = "", -- the match is yours
		["air_hockey.lose"] = "", -- the match is theirs
	},
	words = {
		idle = "You were taken off the air hockey table: your game stopped answering",
		finished = "That match is over and the table is free. Press E at either end to play again.",
	},
}

return entry
