--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Minigames.Games.Paintball
-- Paintball's client half on the minigame framework (Client/Minigames/ClientGame; brief v2 §13, §14):
-- what the framework is told about the game, with the game itself in Client/Minigames/Paintball/
-- (PaintballClient: the show anyone near sees, and the seat of a player in the match).
-- OWNED BY THE CLIENT LANE (its line in Client/Minigames/ClientGames exists).
-- What is fixed by the paintball contract and must stay as it is here:
--   keys     Q and gamepad B are swallowed: leaving a match is a deliberate Leave (a button shown
--            with the scoreboard, in the briefing and at the end card; on a gamepad, Y while the
--            scoreboard is held), and gamepad B crouches. Every other key is the controller's own to
--            read (PaintballClient, "the controls, per device", fixes which).
--   kinds    Wire.EVERYONE_KINDS: "paintball_watch" and "paintball_unwatch" reach `watch` whether or
--            not the player is seated; that is how the show starts for somebody in the lobby.
--   buttons  none while playing (the bar must be empty for the mouse to stay the look; the seat
--            puts Leave and Change sides up itself with ctx.setButtons while the scoreboard is
--            shown and during the briefing: ids "leave" and "side", which the framework sends as
--            those verbs); Leave in the briefing's first moment and at the end card. No "Play
--            again": the next match starts by itself.
--   endCard  from view.result (Contract.Result): the framework's end card, counting down to the
--            next match, headed as the WBLW Channel 7 sports bulletin: the winner's line, then every
--            player's (side, tags, times out, aim), most tags first. The bulletin's awards are drawn
--            beside it by the seat's own HUD (Client/Minigames/Paintball/Hud), which also takes the
--            framework card's "Play again" away (the next match starts by itself).
--   sounds   the cues of PB-8 and four more of the lane's own (the magazine full again, the match
--            going live, back from being tagged out, full time), every id empty until the licensed
--            sounds are chosen.
-- Interface: a ClientGame.ClientGame

local Import = require("../../Import")
local Contract: typeof(require(game.ReplicatedStorage.Shared.Minigames.Paintball.Contract)) =
	Import.shared("Minigames/Paintball/Contract")
local Wire: typeof(require(game.ReplicatedStorage.Shared.Minigames.Paintball.Wire)) =
	Import.shared("Minigames/Paintball/Wire")
local PaintballClient = require("../Paintball/PaintballClient")
local ClientGame = require("../ClientGame")

type Result = typeof(Contract.T.Result)

local LEAVE = { "leave", "Leave the match" }

local function buttons(phase: string, _view: { [string]: any }?): { { string } }?
	if phase == "playing" then
		return nil -- the seat's own: empty, or Leave while the scoreboard is held
	end
	return { LEAVE }
end

local function endCard(view: { [string]: any }, _you: number?): { [string]: any }?
	local result = view.result :: Result?
	if type(result) ~= "table" or type(result.card) ~= "table" then
		return nil
	end
	local card = result.card
	local seats = view.seats or {}
	local rows = {}
	for _, row in card.rows do
		local seat = seats[row.id]
		local team = Contract.TEAMS[row.team]
		table.insert(rows, {
			seat = row.id,
			name = if seat then seat.name else "?",
			gone = seat ~= nil and seat.gone == true,
			place = if card.winner == 0 or card.winner == row.team then 1 else 2,
			side = if team then team.name else "",
			tags = row.tags,
			outs = row.outs,
			accuracy = `{math.floor(row.accuracy * 100 + 0.5)}%`,
		})
	end
	return {
		title = "WBLW 7 SPORTS  ·  FULL TIME",
		line = result.text,
		rows = rows,
		cols = {
			{ title = "", key = "place", x = 0.02, w = 0.06 },
			{ title = "PLAYER", key = "name", x = 0.09, w = 0.37 },
			{ title = "SIDE", key = "side", x = 0.47, w = 0.14 },
			{ title = "TAGS", key = "tags", x = 0.62, w = 0.1, strong = true },
			{ title = "OUT", key = "outs", x = 0.73, w = 0.1 },
			{ title = "AIM", key = "accuracy", x = 0.84, w = 0.14 },
		},
		foot = "The next match starts in %d s.",
	}
end

local Game: ClientGame.ClientGame = {
	game = "paintball",
	help = {
		how = {
			"Two teams, orange against teal. One hit and you are tagged out for a few seconds.",
			"The ball takes time to arrive and drops a little: lead a runner, aim a touch high at range.",
			"Five shots, then the marker reloads by itself.",
			"In your own spawn room you cannot be hit and cannot fire. The other team's is shut to you.",
		},
		keys = {
			"Mouse  look    Left button  fire    R  reload",
			"Shift  sprint (the marker lowers)    C / Left Ctrl  crouch",
			"Hold G  scoreboard, Leave, Change sides",
			"Gamepad: R2 fire, X reload, L3 sprint, B crouch; hold View for the scoreboard (Y leaves)",
			"Touch: FIRE (drag on it to keep looking), RELOAD, CROUCH, SCORES; hold the stick fully forward to sprint",
		},
	},
	keys = { Q = "", ButtonB = "" },
	buttons = buttons,
	kinds = table.clone(Wire.EVERYONE_KINDS),
	watch = function(msg: { [string]: any }, place: ClientGame.Place?): any
		return PaintballClient.watch(msg, place)
	end,
	new = function(ctx: ClientGame.Ctx): ClientGame.Controller
		return PaintballClient.new(ctx)
	end,
	endCard = endCard,
	-- PLACEHOLDERS until the owner chooses the licensed set (docs/AUDIO_BUDGET.md, "Paintball"): sounds that ship
	-- with every Roblox client (rbxasset://sounds/...), so nothing is uploaded and the fire, the hits and the dry
	-- click can be judged at the playtest. The classic Paintball Gun gear's own pop is the marker's. Each file is
	-- to be checked in Studio (a missing one is silent and the Output says it failed to load: pick another).
	sounds = {
		["paintball.fire"] = "rbxasset://sounds/paintball.wav", -- your marker's pop
		["paintball.fire_far"] = "rbxasset://sounds/paintball.wav", -- another marker, placed in space (quieter, muffled by floors)
		["paintball.splat"] = "rbxasset://sounds/splat.wav", -- a ball bursting on a wall, a floor or a body
		["paintball.tag"] = "rbxasset://sounds/electronicpingshort.wav", -- YOU tagged someone
		["paintball.tagged"] = "rbxasset://sounds/uuhhh.mp3", -- you were tagged
		["paintball.reload"] = "rbxasset://sounds/switch.wav", -- the rattle
		["paintball.dry"] = "rbxasset://sounds/clickfast.wav", -- a click with nothing to fire
		-- (no single footstep ships with the client: the stock ones are loops. The body's own stock footsteps are
		-- heard meanwhile; the owner's set brings the loud sprint and the silent crouch)
		["paintball.step"] = "", -- footsteps (running loud, crouching silent)
		["paintball.ready"] = "rbxasset://sounds/button.wav", -- the reload is done: the magazine is full again
		["paintball.go"] = "rbxasset://sounds/electronicpingshort.wav", -- the briefing is over: the match is live
		["paintball.back"] = "rbxasset://sounds/action_get_up.mp3", -- you are back from being tagged out
		["paintball.over"] = "rbxasset://sounds/victory.wav", -- full time: the match is over
	},
	words = { finished = "The match is over. Press E at the arena door to play again." },
}

return Game
