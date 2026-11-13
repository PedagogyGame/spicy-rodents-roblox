--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Minigames.Games.AirHockey
-- Air hockey's client half on the minigame framework (Client/Minigames/ClientGame): the owner's AER / 01 table in
-- the bowling alley's games room.
--   The seated player's controller is Client/Minigames/AirHockey/Controller (the mallet under the hand with no
--     delay; first person or from above).
--   Everyone near the table is sent the referee's stream ("air_hockey") and sees the same match on the same
--     parts: watch() hands each message to Client/Minigames/AirHockey/Rink, which replays it. "air_hockey_seat"
--     is the referee's word to one player that an end is theirs (or that their log must be sent again from a
--     tick), "air_hockey_press" that the other player pressed their serve button, and "air_hockey_rest" that the
--     table has reset.
--   The lobby: Start, the computer's difficulty if nobody takes the other end (his Lounge / Club / Pro), Leave:
--     the controller's own bar, as every bar is while the game is open.
--   The scorecard: both ends, who has them and the score (a strip in the top corner on a small screen); the end
--     card says who won.
--   Sound: named cue points only, no asset ids yet (a strike by its strength, a rail, a post, a goal for and
--     against, a goal seen by a bystander, the serve, the match won and lost).
-- Space is the game's own key (serve; in the lobby it starts, as everywhere), and so are Q and gamepad B (leave):
-- the framework's are swallowed and the controller sends each once.
-- Interface: a ClientGame.ClientGame; SMALL_CARD is read by the specs through card()

local Import = require("../../Import")
local Layout =
	Import.shared("Minigames/AirHockey/Layout") :: typeof(require("../../../shared/Minigames/AirHockey/Layout"))
local Rules = Import.shared("Minigames/AirHockey/Rules") :: typeof(require("../../../shared/Minigames/AirHockey/Rules"))
local ClientGame = require("../ClientGame")
local Controller = require("../AirHockey/Controller")
local Rink = require("../AirHockey/Rink")

-- the scorecard on a small screen: a strip in the top right corner (pixels; `top` clears the Roblox top bar)
local SMALL_CARD = { w = 216, h = 50, right = 10, top = 44 }

-- seat -> the end it plays, from a view (before the match starts: the first seat at Glacier)
local function sideOf(view: { [string]: any }, seat: number): number
	local g = view.game
	local s = g and g.seats and g.seats[seat]
	if s and type(s.side) == "number" then
		return s.side
	end
	return if seat == 1 then 0 else 1
end

-- The scorecard. On a full screen: both ends, who has them and the score, in the bottom corner. On a touch
-- device or a short screen (Controller.small) the bottom corner is the player's own half of the bed, so the
-- card is a strip in the top corner, clear of the table from either end.
local function card(frame: Frame, view: { [string]: any }, you: number?, kit: any)
	local C, label = kit.C, kit.label
	local g = view.game
	local score = (g and g.score) or { 0, 0 }
	local names = { [0] = "the computer", [1] = "the computer" }
	if view.phase == "lobby" then
		names = { [0] = "open", [1] = "open" }
	end
	for seat, s in view.seats or {} do
		if not s.gone then
			names[sideOf(view, seat)] = s.name .. (if seat == you then " (you)" else "")
		end
	end
	if Controller.small() then
		frame.Size = UDim2.fromOffset(SMALL_CARD.w, SMALL_CARD.h)
		frame.Position = UDim2.new(1, -SMALL_CARD.w - SMALL_CARD.right, 0, SMALL_CARD.top)
		for side = 0, 1 do
			local y = 3 + side * 22
			label(
				frame,
				`{string.upper(Layout.SIDE_NAMES[side])}  {names[side]}`,
				UDim2.new(0.8, -6, 0, 20),
				UDim2.fromOffset(6, y),
				if side == 0 then C.CYAN else C.GOLD,
				Enum.Font.GothamBold
			)
			label(
				frame,
				tostring(score[side + 1] or 0),
				UDim2.new(0.2, -4, 0, 20),
				UDim2.new(0.8, 0, 0, y),
				C.GOLD,
				Enum.Font.FredokaOne
			)
		end
		return
	end
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
	buttons = function(phase: string, _view: { [string]: any }?): { { string } }?
		if phase == "joined" then
			-- (until the table's first word; from then on every bar is the controller's own, so that a button
			-- pressed twice is sent once)
			return { { "leave", "Leave (Q)" } }
		end
		return nil
	end,
	-- Space serves (in the lobby it starts), and Q and gamepad B leave: all three are read by the controller,
	-- which sends each once
	keys = { Space = "", Q = "", ButtonB = "" },
	new = Controller.new,
	card = card,
	cardSig = function(view: { [string]: any }): any
		local g = view.game
		return (if g and g.score then `{g.score[1]}-{g.score[2]}` else "")
			.. (if Controller.small() then " small" else "")
	end,
	endCard = endCard,
	kinds = { "air_hockey", "air_hockey_seat", "air_hockey_press", "air_hockey_rest" },
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
		["air_hockey.serve"] = "", -- the puck is let go (every serve: the countdown running out, or a press)
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
