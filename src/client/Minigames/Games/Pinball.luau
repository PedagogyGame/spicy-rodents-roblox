--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Minigames.Games.Pinball
-- Pinball's client half on the minigame framework (Client/Minigames/ClientGame): the three machines in the
-- bowling alley's games room (ACORN ATTACK, SPICY RODENT, SPACE SQUIRREL; the station's variant).
--   The seated player's controller is Client/Minigames/Pinball/Controller (their ball played on this screen with
--     no delay; the camera over the lockdown bar; keys, mouse, gamepad and touch through Pinball/Hands; the
--     dot-matrix display beside the table).
--   Everyone near a machine is drawn the same game on the same parts: watch() hands every message to
--     Client/Minigames/Pinball/Cabinet ("pinball": a segment of the log the server took; "pinball_sync": the
--     game as the server has it; "pinball_idle": the machine is free, run the attract show; "pinball_over": the
--     board of best scores after a game; "pinball_thump": an animal thumped the glass, for the player up;
--     "pinball_retire": a player who was waiting has gone, passed over from a tick on).
--   The scorecard: the machine, the ball, each player's score with the player up marked; it stands where the
--     table is not (Controller.cardRect: the bottom right corner on a wide screen, a strip in the top right
--     corner on a phone, a tablet or a narrow window). What to shoot for is on the display, not here.
--   The end card: the scores ranked, each player's bumpers, ramps and best bonus; and for this player the place
--     the score took on the machine's board, or a new personal best (the server's state: place, best, newBest).
--   Sound: named cue points only, no asset ids yet: one set per machine, "pinball.<variant>.<cue>" for every
--     Machine.CUE (flip_up, bumper, sling, drain, tilt_warn, jingle, ...) and the reels' clack.
-- Space is the game's own key (the plunger; in the lobby it starts), and so are Q and gamepad B (leaving a game
-- in play takes two presses: Controller): the framework's are swallowed and the controller reads them. The bar
-- carries Leave in every phase. H hides the help card, as everywhere.
-- Interface: a ClientGame.ClientGame

local Import = require("../../Import")
local HighScores =
	Import.shared("Minigames/Pinball/HighScores") :: typeof(require("../../../shared/Minigames/Pinball/HighScores"))
local Machine =
	Import.shared("Minigames/Pinball/Machine") :: typeof(require("../../../shared/Minigames/Pinball/Machine"))
local ClientGame = require("../ClientGame")
local Cabinet = require("../Pinball/Cabinet")
local Controller = require("../Pinball/Controller")

local function place(n: number): string
	local last = n % 10
	local teen = n % 100 >= 11 and n % 100 <= 13
	local suffix = if teen
		then "th"
		elseif last == 1 then "st"
		elseif last == 2 then "nd"
		elseif last == 3 then "rd"
		else "th"
	return `{n}{suffix}`
end

local function card(frame: Frame, view: { [string]: any }, you: number?, kit: any)
	local C, label = kit.C, kit.label
	local g = view.game
	local at = Controller.cardRect()
	frame.Size = UDim2.fromOffset(at.w, at.h)
	if at.fromRight then
		frame.Position = UDim2.new(1, at.x, 1, at.y)
	else
		frame.Position = UDim2.fromOffset(at.x, at.y)
	end
	local title = (g and g.title) or "PINBALL"
	if at.small then
		-- a strip: the machine, the ball, the player up and their score
		label(frame, title, UDim2.new(1, -10, 0, 18), UDim2.fromOffset(5, 3), C.GOLD, Enum.Font.FredokaOne)
		local line = "FREE PLAY"
		if g and g.players then
			local up = g.up or 1
			local p = g.players[up]
			local s = view.seats and view.seats[up]
			line = if g.phase == "over"
				then "GAME OVER"
				else `BALL {g.ball or 1}  {(s and s.name) or `P{up}`}{if up == you then " (you)" else ""}  {HighScores.commas(
					(p and p.score) or 0
				)}`
		end
		label(frame, line, UDim2.new(1, -10, 0, 26), UDim2.fromOffset(5, 23), C.WHITE, Enum.Font.GothamBold)
		return
	end
	label(frame, title, UDim2.new(1, -12, 0, 24), UDim2.fromOffset(6, 4), C.GOLD, Enum.Font.FredokaOne)
	if g == nil or g.players == nil then
		label(frame, "FREE PLAY  ·  1 TO 4 PLAYERS", UDim2.new(1, -12, 0, 20), UDim2.fromOffset(6, 32), C.WHITE)
		return
	end
	local over = g.phase == "over"
	label(
		frame,
		if over then "GAME OVER" else `BALL {g.ball or 1} OF {g.balls or Machine.BALLS}`,
		UDim2.new(1, -12, 0, 18),
		UDim2.fromOffset(6, 30),
		C.CYAN,
		Enum.Font.GothamBold
	)
	for seat, p in g.players do
		local s = view.seats and view.seats[seat]
		local name = (s and s.name) or `Player {seat}`
		local mark = if g.up == seat then "> " else "   "
		local y = 50 + (seat - 1) * 20
		label(
			frame,
			`{mark}{name}{if seat == you then " (you)" else ""}{if p.gone then " (gone)" else ""}`,
			UDim2.new(0.62, -6, 0, 18),
			UDim2.fromOffset(6, y),
			if g.up == seat then C.GOLD else C.WHITE,
			Enum.Font.GothamBold
		)
		label(
			frame,
			HighScores.commas(p.score or 0),
			UDim2.new(0.38, -6, 0, 18),
			UDim2.new(0.62, 0, 0, y),
			C.GOLD,
			Enum.Font.GothamBold
		)
	end
end

-- the end card's words about the board, for this player (over: { place, best, newBest } from the server)
local function endLine(over: { [string]: any }?, title: string): string?
	if over == nil then
		return nil
	end
	local p = tonumber(over.place) or 0
	local words = {}
	if p == 1 then
		table.insert(words, `NEW HIGH SCORE ON {title}!`)
	elseif p > 1 then
		table.insert(words, `{place(p)} on the {title} board`)
	end
	if over.newBest == true then
		table.insert(words, "A NEW PERSONAL BEST")
	elseif type(over.best) == "number" and over.best > 0 then
		table.insert(words, `your best here: {HighScores.commas(over.best)}`)
	end
	if #words == 0 then
		return nil
	end
	return table.concat(words, ".  ")
end

local function endCard(view: { [string]: any }, you: number?): { [string]: any }?
	local r = view.result
	if r == nil or r.scores == nil then
		return nil
	end
	local order = {}
	for seat in view.seats do
		table.insert(order, seat)
	end
	table.sort(order, function(a: number, b: number): boolean
		return (r.scores[a] or 0) > (r.scores[b] or 0)
	end)
	local rows = {}
	for rank, seat in order do
		local s = view.seats[seat]
		local st = (r.stats and r.stats[seat]) or {}
		table.insert(rows, {
			seat = seat,
			name = s.name,
			gone = s.gone,
			place = rank,
			total = HighScores.commas(r.scores[seat] or 0),
			bumpers = tostring(st.bumpers or 0),
			ramps = tostring((st.ramps or 0) + (st.orbits or 0)),
			bonus = HighScores.commas(st.bestBonus or 0),
		})
	end
	local g = view.game
	local title = (g and g.title) or "PINBALL"
	local line = "GAME OVER."
	if you ~= nil and #order > 1 then
		line = if r.winner == you then "YOU WIN." elseif r.winner == nil then "A TIE." else "GAME OVER."
	end
	local c = Controller.current
	local board = endLine(c and c.over, title)
	if board then
		line ..= `  {board}`
	end
	local fairSeat = if you and r.fairSeats then r.fairSeats[you] else r.fair
	if fairSeat == false then
		line ..= "  (out of time with the server: no place on the board)"
	end
	return {
		title = title,
		line = line,
		rows = rows,
		cols = {
			{ title = "", key = "place", x = 0.02, w = 0.06 },
			{ title = "PLAYER", key = "name", x = 0.09, w = 0.3 },
			{ title = "BUMPERS", key = "bumpers", x = 0.4, w = 0.14 },
			{ title = "RAMPS", key = "ramps", x = 0.54, w = 0.11 },
			{ title = "BEST BONUS", key = "bonus", x = 0.65, w = 0.17 },
			{ title = "SCORE", key = "total", x = 0.82, w = 0.17, strong = true },
		},
		foot = "The machine is free again in %d s.",
	}
end

local entry: ClientGame.ClientGame = {
	game = "pinball",
	help = Controller.HELP,
	title = function(msg: { [string]: any }): string
		return msg.label or "Pinball"
	end,
	buttons = function(phase: string, _view: { [string]: any }?): { { string } }?
		if phase == "joined" then
			-- (from the table's first word on, the bar is the controller's own: a button pressed twice goes once)
			return { { "leave", "Leave (Q)" } }
		end
		return nil
	end,
	keys = { Space = "", Q = "", ButtonB = "" },
	new = Controller.new,
	card = card,
	cardSig = function(view: { [string]: any }): any
		local g = view.game
		local c = Controller.current
		local lay = (c and c.lay and c.lay.key) or ""
		if g == nil or g.players == nil then
			return lay
		end
		local s = {}
		for _, p in g.players do
			table.insert(s, tostring(p.score))
		end
		return `{g.ball}:{g.up}:{table.concat(s, ",")}:{lay}`
	end,
	endCard = endCard,
	kinds = { "pinball", "pinball_sync", "pinball_idle", "pinball_over", "pinball_thump", "pinball_retire" },
	watch = function(msg: { [string]: any }, at: ClientGame.Place?): any
		if type(msg.station) ~= "string" then
			return nil
		end
		local cab = Cabinet.get(msg.station, at)
		local kind = msg.kind
		if kind == "pinball" then
			Cabinet.segment(cab, msg)
		elseif kind == "pinball_sync" then
			Cabinet.sync(cab, msg)
		elseif kind == "pinball_idle" then
			Cabinet.idle(cab)
		elseif kind == "pinball_over" then
			Cabinet.over(cab, msg)
		elseif kind == "pinball_retire" then
			Cabinet.retire(cab, msg)
		end
		return cab
	end,
	sounds = Cabinet.SOUNDS,
	words = {
		idle = "You were taken off the pinball machine: your game stopped answering",
		finished = "That pinball game is over and the machine is free. Press E to play again.",
	},
}

return entry
