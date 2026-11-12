--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Minigames.Games.Bowling
-- Bowling's client half on the minigame framework (Client/Minigames/ClientGame; brief v2 §13a; HANDOFF §4a):
--   the bowler's controller (BowlingClient: aim, hook, power, the camera behind the ball), told of each throw
--     and of a refused one;
--   what EVERYONE sees: "roll" is one throw's script, played back on the lane's parts by BowlingPlayback
--     whether or not you are in that game, and "rack" is a throw cut short. A damaged script is not played (the
--     server's own copy of the motion shows), but the bowler is told either way: the server HAS counted it;
--   the ten-frame scorecard (two mark boxes a frame, three in the tenth, the running total under them, the
--     bowler up highlighted) and the end card (ranked scores, strikes, spares, misses);
--   the strike and spare calls, and the lane's sound cues (silent until their ids are filled in below).
-- Interface: a ClientGame.ClientGame

local Import = require("../../Import")
local Referee =
	Import.shared("Minigames/Bowling/Referee") :: typeof(require("../../../shared/Minigames/Bowling/Referee"))
local RollScript =
	Import.shared("Minigames/Bowling/RollScript") :: typeof(require("../../../shared/Minigames/Bowling/RollScript"))
local BowlingClient = require("../BowlingClient")
local BowlingPlayback = require("../BowlingPlayback")
local ClientGame = require("../ClientGame")
local MinigameSounds = require("../MinigameSounds")

local function new(ctx: ClientGame.Ctx): ClientGame.Controller
	local bowler = BowlingClient.new(ctx)
	bowler.onMessage = function(self: any, msg: { [string]: any }, watched: any?)
		if msg.kind == "roll" then
			-- (with no script the bowler simply does not ride the camera behind the ball)
			self:onRoll(msg, watched)
		elseif msg.kind == "event" then
			if msg.mark == "X" then
				ctx.sound("strike", 1)
			elseif msg.mark == "/" then
				ctx.sound("spare", 1)
			end
		end
	end
	return bowler
end

-- A bowling throw on ANY lane (you may only be watching): play the server's script on the lane's parts.
local function watch(msg: { [string]: any }, place: ClientGame.Place?): any
	if msg.kind == "roll" then
		local script, why = RollScript.check(msg.script)
		local lane = tonumber(msg.lane)
		if script == nil or lane == nil then
			warn(`MinigameClient: a bowling throw could not be played ({why})`)
		else
			BowlingPlayback.play(place, lane, script, MinigameSounds.play)
		end
		return if lane then script else nil
	elseif msg.kind == "rack" then
		local lane = tonumber(msg.lane)
		if lane and type(msg.mask) == "table" then
			BowlingPlayback.stop(lane, place, msg.mask)
		end
	end
	return nil
end

local function card(frame: Frame, view: { [string]: any }, you: number?, kit: any)
	local C, label, corner = kit.C, kit.label, kit.corner
	local g = view.game
	local seats = view.seats or {}
	local n = math.max(1, #seats)
	frame.Size = UDim2.fromOffset(600, 26 + n * 38)
	frame.Position = UDim2.new(1, -612, 1, -(38 + n * 38))
	local fw = 1 / 13.2
	for f = 1, 10 do
		label(
			frame,
			tostring(f),
			UDim2.new(fw, -2, 0, 18),
			UDim2.new(0.16 + (f - 1) * fw, 0, 0, 4),
			C.CYAN,
			Enum.Font.GothamBold
		)
	end
	label(frame, "TOTAL", UDim2.new(0.08, 0, 0, 18), UDim2.new(0.91, 0, 0, 4), C.CYAN, Enum.Font.GothamBold)
	for s, seat in seats do
		local y = 24 + (s - 1) * 38
		local gs = if g then g.seats[s] else nil
		local up = view.turn == s and view.phase == "playing"
		local row = Instance.new("Frame")
		row.BackgroundColor3 = if up then Color3.fromRGB(28, 96, 104) else Color3.fromRGB(26, 32, 66)
		row.Size = UDim2.new(1, -8, 0, 34)
		row.Position = UDim2.fromOffset(4, y)
		row.Parent = frame
		corner(row, 6)
		local name = seat.name .. (if s == you then " (you)" else "") .. (if seat.gone then " (left)" else "")
		label(
			row,
			name,
			UDim2.fromScale(0.15, 0.8),
			UDim2.fromScale(0.005, 0.1),
			if up then C.GOLD else C.WHITE,
			Enum.Font.GothamBold
		)
		for f = 1, 10 do
			local cell = Instance.new("Frame")
			cell.BackgroundColor3 = Color3.fromRGB(16, 20, 44)
			cell.Size = UDim2.new(fw, -2, 1, -4)
			cell.Position = UDim2.new(0.16 + (f - 1) * fw, 0, 0, 2)
			cell.Parent = row
			local marks = if gs and gs.marks[f] then gs.marks[f] else {}
			local boxes = if f == 10 then 3 else 2
			for b = 1, boxes do
				local m = marks[b] or ""
				label(
					cell,
					m,
					UDim2.fromScale(1 / boxes, 0.5),
					UDim2.fromScale((b - 1) / boxes, 0),
					if m == "X" or m == "/" then C.GOLD else C.WHITE,
					Enum.Font.Code
				)
			end
			label(
				cell,
				tostring(if gs then gs.totals[f] else ""),
				UDim2.fromScale(1, 0.5),
				UDim2.fromScale(0, 0.5),
				C.CYAN,
				Enum.Font.GothamBold
			)
		end
		label(
			row,
			if gs then tostring(gs.total) else "0",
			UDim2.fromScale(0.08, 0.8),
			UDim2.fromScale(0.91, 0.1),
			C.GOLD,
			Enum.Font.FredokaOne
		)
	end
end

-- the end card's columns: heading, the row's field, where it starts and how wide it is (fractions of the card)
local COLS = {
	{ title = "", key = "place", x = 0.02, w = 0.07 },
	{ title = "BOWLER", key = "name", x = 0.1, w = 0.36 },
	{ title = "SCORE", key = "total", x = 0.47, w = 0.13, strong = true },
	{ title = "STRIKES", key = "strikes", x = 0.61, w = 0.13 },
	{ title = "SPARES", key = "spares", x = 0.74, w = 0.12 },
	{ title = "MISSES", key = "misses", x = 0.87, w = 0.12 },
}

local function endCard(view: { [string]: any }, _you: number?): { [string]: any }?
	local sum = Referee.summary(view) :: any
	sum.cols = COLS
	sum.foot = "The lane resets in %d s. Anyone can walk up and start a new game."
	return sum
end

local entry: ClientGame.ClientGame = {
	game = "bowling",
	help = BowlingClient.HELP,
	title = function(msg: { [string]: any }): string
		return `Bowling - {msg.label}`
	end,
	buttons = function(phase: string, _view: { [string]: any }?): { { string } }?
		if phase == "joined" then
			return { { "start", "Start now" }, { "addai", "Add a computer" }, { "leave", "Leave (Q)" } }
		elseif phase == "playing" then
			return { { "leave", "Leave (Q)" } }
		elseif phase == "done" then
			return { { "again", "Play again" }, { "leave", "Leave (Q)" } }
		end
		return nil
	end,
	new = new,
	card = card,
	endCard = endCard,
	kinds = { "roll", "rack" },
	watch = watch,
	sounds = {
		release = "", -- the ball leaves the hand
		roll = "", -- the rumble down the lane (looped until the pins or the pit)
		gutter = "", -- the ball drops into the channel
		pin = "", -- one clatter of pins
		pit = "", -- the ball thumps into the pit
		strike = "", -- the call
		spare = "",
		sweep = "", -- the pinsetter
	},
	words = {
		idle = "You were taken off the lane: two turns in a row went unplayed",
		finished = "That game is over and the lane has reset. Press E at a lane to play again.",
	},
}

return entry
