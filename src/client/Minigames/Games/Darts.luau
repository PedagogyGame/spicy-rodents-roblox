--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Minigames.Games.Darts
-- Darts' client half on the minigame framework (Client/Minigames/ClientGame; brief v2 §13a): the thrower's
-- controller (DartsClient: the mouse aims, the timing meter throws; it puts up its own lobby and turn buttons),
-- the banner for each dart ("dart": big for a checkout, a win or a bust), and the scorecard: 501's remaining
-- score and this turn's darts, or the cricket marks grid.
-- Interface: a ClientGame.ClientGame

local ClientGame = require("../ClientGame")
local DartsClient = require("../DartsClient")

local function new(ctx: ClientGame.Ctx): ClientGame.Controller
	local thrower = DartsClient.new(ctx)
	thrower.onMessage = function(_self: any, msg: { [string]: any }, _watched: any?)
		if msg.kind == "dart" then
			ctx.ui:banner(tostring(msg.text), msg.event == "checkout" or msg.event == "win" or msg.event == "bust")
		end
	end
	return thrower
end

local CRICKET = { "20", "19", "18", "17", "16", "15", "25" }
local function cricketMark(n: number): string
	return if n <= 0 then "" elseif n == 1 then "/" elseif n == 2 then "X" else "(X)"
end

local function card(frame: Frame, view: { [string]: any }, you: number?, kit: any)
	local C, label = kit.C, kit.label
	local g = view.game
	local seats = view.seats or {}
	local n = math.max(1, #seats)
	local mode = (g and g.mode) or view.mode or "501"
	if mode == "cricket" then
		frame.Size = UDim2.fromOffset(120 + n * 110, 250)
		frame.Position = UDim2.new(1, -(132 + n * 110), 1, -262)
		label(frame, "CRICKET", UDim2.fromOffset(110, 24), UDim2.fromOffset(6, 4), C.GOLD, Enum.Font.FredokaOne)
		for i, seat in seats do
			local x = 116 + (i - 1) * 110
			local up = view.turn == i
			label(
				frame,
				seat.name .. (if i == you then "*" else ""),
				UDim2.fromOffset(104, 22),
				UDim2.fromOffset(x, 4),
				if up then C.GOLD else C.WHITE,
				Enum.Font.GothamBold
			)
			for r, lab in CRICKET do
				local m = if g then g.seats[i].marks[lab] or 0 else 0
				label(
					frame,
					cricketMark(m),
					UDim2.fromOffset(104, 22),
					UDim2.fromOffset(x, 4 + r * 26),
					C.WHITE,
					Enum.Font.GothamBold
				)
			end
			label(
				frame,
				if g then tostring(g.seats[i].score) else "0",
				UDim2.fromOffset(104, 24),
				UDim2.fromOffset(x, 214),
				C.GOLD,
				Enum.Font.FredokaOne
			)
		end
		for r, lab in CRICKET do
			label(
				frame,
				if lab == "25" then "BULL" else lab,
				UDim2.fromOffset(90, 22),
				UDim2.fromOffset(10, 4 + r * 26),
				C.CYAN,
				Enum.Font.GothamBold
			)
		end
	else
		frame.Size = UDim2.fromOffset(420, 34 + n * 40)
		frame.Position = UDim2.new(1, -432, 1, -(46 + n * 40))
		label(
			frame,
			"501  (finish on a double)",
			UDim2.new(1, -12, 0, 24),
			UDim2.fromOffset(6, 4),
			C.GOLD,
			Enum.Font.FredokaOne
		)
		for i, seat in seats do
			local y = 32 + (i - 1) * 40
			local gs = if g then g.seats[i] else nil
			local up = view.turn == i
			label(
				frame,
				(if up then "> " else "") .. seat.name .. (if i == you then " (you)" else ""),
				UDim2.new(0.42, 0, 0, 30),
				UDim2.fromOffset(6, y),
				if up then C.GOLD else C.WHITE,
				Enum.Font.GothamBold
			)
			label(
				frame,
				if gs then tostring(gs.score) else "501",
				UDim2.new(0.22, 0, 0, 34),
				UDim2.new(0.44, 0, 0, y - 2),
				C.GOLD,
				Enum.Font.FredokaOne
			)
			label(
				frame,
				if gs and gs.darts then table.concat(gs.darts, "  ") else "",
				UDim2.new(0.32, 0, 0, 26),
				UDim2.new(0.67, 0, 0, y + 2),
				C.CYAN,
				Enum.Font.GothamBold
			)
		end
	end
end

local entry: ClientGame.ClientGame = {
	game = "darts",
	help = DartsClient.HELP,
	title = function(_msg: { [string]: any }): string
		return "Darts"
	end,
	-- (in the lobby and on a turn the controller puts up its own buttons)
	buttons = function(phase: string, _view: { [string]: any }?): { { string } }?
		if phase == "joined" then
			return {
				{ "501", "501" },
				{ "cricket", "Cricket" },
				{ "addai", "+ Computer" },
				{ "start", "Start" },
				{ "leave", "Leave (Q)" },
			}
		elseif phase == "done" then
			return { { "again", "Play again" }, { "leave", "Leave (Q)" } }
		end
		return nil
	end,
	new = new,
	card = card,
	cardSig = function(view: { [string]: any }): any
		return view.game and view.game.mode
	end,
}

return entry
