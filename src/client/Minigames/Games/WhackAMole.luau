--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Minigames.Games.WhackAMole
-- Whack-a-mole's client half on the minigame framework (Client/Minigames/ClientGame): the owner's cabinet in the
-- bowling alley's games room.
--   The seated player's controller is Client/Minigames/WhackAMole/Controller (the camera over the deck; click or
--     tap a mole, keys 1-5, the gamepad's D-pad and shoulder buttons; the mallet swings at once).
--   Everyone near the cabinet is drawn the same round on the same parts: watch() hands every message to
--     Client/Minigames/WhackAMole/Cabinet (whack_round, whack_rise, whack_hit, whack_over, whack_idle), which
--     moves the moles and the mallet and writes the SCORE, TIME and status windows on the sign.
--   The card: how to play in one sentence (for the device in hand), the score and the time left. The end card:
--     the score, hits, misses and how many strikes hit, with the place it took on the cabinet's board or a new
--     personal best (the server's state: place, best, newBest).
--   Sound: named cue points only, no asset ids yet (Cabinet.SOUNDS: "whack_a_mole.<cue>").
-- The bar is the framework's own (Leave in every phase, Play again at the end).
-- Interface: a ClientGame.ClientGame

local Import = require("../../Import")
local Round =
	Import.shared("Minigames/WhackAMole/Round") :: typeof(require("../../../shared/Minigames/WhackAMole/Round"))
local ClientGame = require("../ClientGame")
local Cabinet = require("../WhackAMole/Cabinet")
local Controller = require("../WhackAMole/Controller")

local function howLine(): string
	local UIS = game:GetService("UserInputService")
	if UIS.GamepadEnabled and not UIS.KeyboardEnabled then
		return "D-pad left/up/right: back row 1 2 3.  LB / RB: front row 4 5."
	elseif UIS.TouchEnabled and not UIS.KeyboardEnabled then
		return "Tap each mole as it pops up."
	end
	return "Click each mole as it pops up, or press 1 to 5."
end

local function card(frame: Frame, view: { [string]: any }, _you: number?, kit: any)
	local C, label = kit.C, kit.label
	local g = view.game or {}
	frame.Size = UDim2.fromOffset(300, 92)
	frame.Position = UDim2.new(1, -312, 1, -104)
	label(
		frame,
		"WHACK-A-MOLE  ·  FREE PLAY",
		UDim2.new(1, -12, 0, 22),
		UDim2.fromOffset(6, 4),
		C.GOLD,
		Enum.Font.FredokaOne
	)
	label(frame, howLine(), UDim2.new(1, -12, 0, 18), UDim2.fromOffset(6, 28), C.WHITE)
	local left = tonumber(g.left) or Round.SECONDS
	local ready = tonumber(g.ready) or 0
	local time = if ready > 0 then `READY {math.ceil(ready)}` else `TIME {math.ceil(left)}`
	label(
		frame,
		`SCORE {g.score or 0}    {time}`,
		UDim2.new(1, -12, 0, 30),
		UDim2.fromOffset(6, 52),
		C.CYAN,
		Enum.Font.GothamBold
	)
end

local function endCard(view: { [string]: any }, _you: number?): { [string]: any }?
	local r = view.result
	if r == nil or r.scores == nil then
		return nil
	end
	local score = r.scores[1] or 0
	local hits, misses = r.hits or 0, r.misses or 0
	local judged = hits + misses
	local seat = view.seats and view.seats[1]
	local line = `TIME!  {score} points.`
	local c = Controller.current
	local mine = c and c.over
	if mine then
		local place = tonumber(mine.place) or 0
		if place == 1 then
			line ..= "  THE TOP OF THE BOARD!"
		elseif place > 1 then
			line ..= `  Number {place} on the cabinet's board.`
		end
		if mine.newBest == true then
			line ..= "  A new personal best."
		elseif type(mine.best) == "number" and mine.best > score then
			line ..= `  Your best: {mine.best}.`
		end
	end
	return {
		title = "WHACK-A-MOLE",
		line = line,
		rows = {
			{
				seat = 1,
				name = (seat and seat.name) or "You",
				gone = seat and seat.gone,
				place = 1,
				hits = tostring(hits),
				misses = tostring(misses),
				rate = if judged > 0 then `{math.floor(hits / judged * 100 + 0.5)}%` else "-",
				total = tostring(score),
			},
		},
		cols = {
			{ title = "PLAYER", key = "name", x = 0.02, w = 0.36 },
			{ title = "HITS", key = "hits", x = 0.4, w = 0.14 },
			{ title = "MISSES", key = "misses", x = 0.54, w = 0.14 },
			{ title = "ON TARGET", key = "rate", x = 0.68, w = 0.15 },
			{ title = "SCORE", key = "total", x = 0.84, w = 0.15, strong = true },
		},
		foot = "The cabinet is free again in %d s.",
	}
end

local entry: ClientGame.ClientGame = {
	game = "whack_a_mole",
	help = Controller.HELP,
	title = function(_msg: { [string]: any }): string
		return "Whack-a-Mole"
	end,
	new = Controller.new,
	card = card,
	cardSig = function(view: { [string]: any }): any
		local g = view.game or {}
		return `{g.score or 0}:{math.ceil(tonumber(g.left) or 0)}:{math.ceil(tonumber(g.ready) or 0)}`
	end,
	endCard = endCard,
	kinds = { "whack_round", "whack_rise", "whack_hit", "whack_over", "whack_idle" },
	watch = function(msg: { [string]: any }, at: ClientGame.Place?): any
		if type(msg.station) ~= "string" then
			return nil
		end
		local cab = Cabinet.get(msg.station, at)
		local kind = msg.kind
		if kind == "whack_round" then
			Cabinet.round(cab, msg)
		elseif kind == "whack_rise" then
			Cabinet.rise(cab, msg)
		elseif kind == "whack_hit" then
			Cabinet.hit(cab, msg)
		elseif kind == "whack_over" then
			Cabinet.over(cab, msg)
			local c = Controller.current
			if c and c.cab == cab and type(msg.place) == "number" then
				c.over = { place = msg.place, best = msg.best, newBest = msg.newBest }
			end
		elseif kind == "whack_idle" then
			Cabinet.idle(cab, msg)
		end
		return cab
	end,
	sounds = Cabinet.SOUNDS,
	words = {
		idle = "You were taken off the whack-a-mole: nothing was struck for a while",
		finished = "That round is over and the cabinet is free. Press E to play again.",
	},
}

return entry
