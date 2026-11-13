--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Minigames.Games.Pinball
-- Pinball's client half on the minigame framework (Client/Minigames/ClientGame): the three machines in the
-- bowling alley's games room (ACORN ATTACK, SPICY RODENT, SPACE SQUIRREL; the station's variant).
--   The seated player's controller is Client/Minigames/Pinball/Controller (their ball played on this screen with
--     no delay; the camera over the lockdown bar; keys, mouse, gamepad and touch through Pinball/Hands).
--   Everyone near a machine is drawn the same game on the same parts: watch() hands every message to
--     Client/Minigames/Pinball/Cabinet ("pinball": a segment of the log the server took; "pinball_sync": the
--     game as the server has it; "pinball_idle": the machine is free, run the attract show; "pinball_over": the
--     board of best scores after a game; "pinball_thump": an animal thumped the glass, for the player up).
--   The scorecard: the machine, the ball, each player's score with the player up marked, and what to shoot for;
--     the end card: the scores ranked, and each player's bumpers, ramps and targets.
--   Sound: named cue points only, no asset ids yet: one set per machine, "pinball.<variant>.<cue>" for every
--     Machine.CUE (flip_up, bumper, sling, drain, tilt_warn, jingle, ...) and the reels' clack.
-- Space is the game's own key (the plunger; in the lobby it starts): the framework's is swallowed and the
-- controller reads it. Q and gamepad B leave and H hides the help card, as everywhere.
-- Interface: a ClientGame.ClientGame

local Import = require("../../Import")
local HighScores =
	Import.shared("Minigames/Pinball/HighScores") :: typeof(require("../../../shared/Minigames/Pinball/HighScores"))
local Machine =
	Import.shared("Minigames/Pinball/Machine") :: typeof(require("../../../shared/Minigames/Pinball/Machine"))
local ClientGame = require("../ClientGame")
local Cabinet = require("../Pinball/Cabinet")
local Controller = require("../Pinball/Controller")

local function card(frame: Frame, view: { [string]: any }, you: number?, kit: any)
	local C, label = kit.C, kit.label
	local g = view.game
	frame.Size = UDim2.fromOffset(330, 150)
	frame.Position = UDim2.new(1, -342, 1, -162)
	local title = (g and g.title) or "PINBALL"
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
	for place, seat in order do
		local s = view.seats[seat]
		local st = (r.stats and r.stats[seat]) or {}
		table.insert(rows, {
			seat = seat,
			name = s.name,
			gone = s.gone,
			place = place,
			total = HighScores.commas(r.scores[seat] or 0),
			bumpers = tostring(st.bumpers or 0),
			ramps = tostring((st.ramps or 0) + (st.orbits or 0)),
			targets = tostring(st.targets or 0),
		})
	end
	local g = view.game
	local line = "GAME OVER"
	if you ~= nil and #order > 1 then
		line = if r.winner == you then "YOU WIN." elseif r.winner == nil then "A TIE." else "GAME OVER."
	end
	if r.fair == false then
		line ..= "  (out of time with the server: no place on the board)"
	end
	return {
		title = (g and g.title) or "PINBALL",
		line = line,
		rows = rows,
		cols = {
			{ title = "", key = "place", x = 0.02, w = 0.06 },
			{ title = "PLAYER", key = "name", x = 0.09, w = 0.33 },
			{ title = "BUMPERS", key = "bumpers", x = 0.43, w = 0.14 },
			{ title = "RAMPS", key = "ramps", x = 0.57, w = 0.12 },
			{ title = "TARGETS", key = "targets", x = 0.69, w = 0.13 },
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
	keys = { Space = "" },
	new = Controller.new,
	card = card,
	cardSig = function(view: { [string]: any }): any
		local g = view.game
		if g == nil or g.players == nil then
			return ""
		end
		local s = {}
		for _, p in g.players do
			table.insert(s, tostring(p.score))
		end
		return `{g.ball}:{g.up}:{table.concat(s, ",")}`
	end,
	endCard = endCard,
	kinds = { "pinball", "pinball_sync", "pinball_idle", "pinball_over", "pinball_thump", "pinball_retire" },
	watch = function(msg: { [string]: any }, place: ClientGame.Place?): any
		if type(msg.station) ~= "string" then
			return nil
		end
		local cab = Cabinet.get(msg.station, place)
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
