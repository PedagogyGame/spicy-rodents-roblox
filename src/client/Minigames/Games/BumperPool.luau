--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Minigames.Games.BumperPool
-- Bumper pool's client half on the minigame framework (Client/Minigames/ClientGame; brief v2 §13a): the bumper
-- pool table in the bowling alley's games room. Built on pool's own client pieces, read and never copied:
--   the shooter's controller is Pool/CueController (aim line and ghost ball, the cue drawn back for power, the
--     tip, walking round the table, the top view), given what is bumper pool's own below: there is no cue
--     ball, you strike one of YOUR five (the marked one first; click another, or R, 1 to 5, the D-pad), in
--     the opening only your marked ball; in the opening both players strike (the first seat, then the
--     second: the service hands a turn game's input only to the seat whose turn it is) and the table plays
--     the two strikes together when the second is in; the cue first points at your cup, or in the opening at the bank off
--     the cushion on your right;
--   what EVERYONE sees: "bumper_pool_shot" is one shot's script (Shared/Minigames/Pool/Wire), played back on
--     the table's balls by Pool/Playback whether or not you are in that game (the opening's two strokes
--     together); "bumper_pool_rack" lays the balls out;
--   the scorecard (each side's colour, balls sunk of five, whether the marked ball is down, whose shot) and
--     the end card (who won and how, sunk, shots, banks);
--   the sound cue points (silent until their ids are filled in below).
-- Interface: a ClientGame.ClientGame

local Import = require("../../Import")
local BumperPool =
	Import.shared("Minigames/Pool/BumperPool") :: typeof(require("../../../shared/Minigames/Pool/BumperPool"))
local Computer = Import.shared("Minigames/Pool/Computer") :: typeof(require("../../../shared/Minigames/Pool/Computer"))
local Cue = Import.shared("Minigames/Pool/Cue") :: typeof(require("../../../shared/Minigames/Pool/Cue"))
local Furniture =
	Import.shared("Minigames/Pool/Furniture") :: typeof(require("../../../shared/Minigames/Pool/Furniture"))
local Games = Import.shared("Minigames/Games") :: typeof(require("../../../shared/Minigames/Games"))
local Tables = Import.shared("Minigames/Pool/Tables") :: typeof(require("../../../shared/Minigames/Pool/Tables"))
local Wire = Import.shared("Minigames/Pool/Wire") :: typeof(require("../../../shared/Minigames/Pool/Wire"))
local Words = Import.shared("Minigames/Pool/Words") :: typeof(require("../../../shared/Minigames/Pool/Words"))
local ClientGame = require("../ClientGame")
local MinigameSounds = require("../MinigameSounds")
local CueController = require("../Pool/CueController")
local Playback = require("../Pool/Playback")

local TABLE = Tables.bumper()
local SIDE_WORDS = { "red", "white" }

local function namesOf(view: { [string]: any }): { string }
	local names: { string } = {}
	for i, seat in view.seats or {} do
		names[i] = seat.name
	end
	return names
end

local function waitingFor(g: { [string]: any }, seat: number?): boolean
	return seat ~= nil and type(g.waiting) == "table" and table.find(g.waiting, seat) ~= nil
end

-- My balls on the table (id order, the marked one first if it is up), from the view's flat list.
local function upOf(g: { [string]: any }, seat: number): { number }
	local out: { number } = {}
	local flat = g.balls or {}
	for k = 1, #flat - 2, 3 do
		local id = flat[k]
		if BumperPool.sideOf(id) == seat then
			table.insert(out, id)
		end
	end
	table.sort(out)
	return out
end

-- Where the cue first points: straight at my cup, or in the opening at the bank off the cushion on my right
-- (the mirror of the cup in that cushion's line, a ball's width inside it).
local function aimFor(g: { [string]: any }, you: number, spots: { CueController.Spot }, ball: number): number
	local s: CueController.Spot? = nil
	for _, sp in spots do
		if sp.id == ball then
			s = sp
		end
	end
	if s == nil then
		return 0
	end
	local cup = TABLE.holes[BumperPool.cupOf(you)]
	local tx, tz = cup.x, cup.z
	if g.phase == "opening" then
		local line = TABLE.halfW - TABLE.ballR
		local wall = if you == 1 then line else -line
		tx = 2 * wall - cup.x
	end
	return Cue.angleOf(tx - s.x, tz - s.z)
end

local mode: CueController.Game = {
	game = "bumper_pool",
	table = TABLE,
	-- (the opening's two strikes are taken one after the other: the service hands a turn game's inputs only to
	-- the seat whose turn it is, so the second player strikes once the first has, and the table plays both)
	mine = function(view: { [string]: any }, you: number?): boolean
		return you ~= nil and view.turn == you and view.game ~= nil
	end,
	strikeable = function(g: { [string]: any }, you: number): { number }
		if g.phase == "opening" then
			local opener = g.openers and g.openers[you]
			return if opener then { opener } else {}
		end
		return upOf(g, you)
	end,
	inHand = function(_g: { [string]: any }): string
		return "none"
	end,
	mustCall = function(_g: { [string]: any }, _you: number): boolean
		return false
	end,
	called = function(_g: { [string]: any }): number
		return 0
	end,
	canPlace = function(_g: { [string]: any }, _spots: { CueController.Spot }, _x: number, _z: number): boolean
		return false
	end,
	firstAim = aimFor,
	args = function(ball: number, angle: number, power: number, tipX: number, tipY: number, _pocket: number): { any }
		return { ball, angle, power, tipX, tipY }
	end,
	say = function(view: { [string]: any }, you: number?, phase: string): string
		local g = view.game
		local names = namesOf(view)
		if view.phase == "lobby" then
			return `Starting in {view.lobbyLeft or 0}: Space starts now. Add a computer opponent, wait for a second player, or play alone for practice.`
		elseif view.phase == "done" then
			return `{if g then Words.bumperEnd(g, names) else "Game over."} Play again or Leave (Q).`
		elseif g == nil or view.phase ~= "playing" then
			return ""
		end
		local last = Words.bumper(g, names)
		local lead = if last then last .. " " else ""
		local colour = if you then SIDE_WORDS[you] else ""
		if g.phase == "opening" then
			if waitingFor(g, you) and view.turn ~= you then
				return `{names[view.turn or 0] or "?"} strikes their opening shot first; then you strike yours, and the table plays the two together.`
			elseif waitingFor(g, you) then
				if phase == "sent" or phase == "watch" then
					return "Your opening shot is in."
				end
				return `{lead}The opening: bank your marked {colour} ball off the cushion on your RIGHT toward your cup. Both of you strike; the table plays the two together.`
			end
			local others: { string } = {}
			for _, s in g.waiting or {} do
				table.insert(others, names[s] or "?")
			end
			return `Your opening shot is in: waiting for {table.concat(others, " and ")} to strike.`
		end
		if not waitingFor(g, you) then
			local who = names[view.turn or 0] or "?"
			return `{lead}{who} is at the table. Walk round and watch; T is the top view.`
		elseif phase == "sent" or phase == "watch" then
			return "Your shot is on its way."
		end
		local seat = you or 1
		local sunk = (g.sunk and g.sunk[seat]) or 0
		local first = if g.markedDown and g.markedDown[seat]
			then ""
			else " The marked ball first, or your opponent drops two!"
		return `{lead}Your shot ({colour}): {sunk} of 5 down. Pick a ball (click it, R, or 1 to 5).{first}`
	end,
}

local function new(ctx: ClientGame.Ctx): ClientGame.Controller
	return CueController.new(ctx, mode)
end

local function cue(name: string, volume: number)
	MinigameSounds.play(`bumper_pool.{name}`, volume)
end

-- A shot at the bumper pool table (you may only be watching): play the server's script on its balls.
local function watch(msg: { [string]: any }, place: ClientGame.Place?): any
	if place == nil or type(msg.station) ~= "string" then
		return nil
	end
	local site = if type(msg.site) == "string" then msg.site else "bowling_alley"
	local def = Games.station(msg.station, { [site] = place }) :: any
	if def == nil then
		return nil
	end
	if msg.kind == "bumper_pool_shot" then
		local script, why = Wire.decode(msg.text)
		if script == nil then
			warn(`MinigameClient: a bumper pool shot could not be played ({why})`)
			return nil
		end
		Playback.play(place, def, script, { lead = msg.lead, onCue = cue })
		return script
	elseif msg.kind == "bumper_pool_rack" then
		Playback.stop(def.id)
		if type(msg.balls) == "table" then
			Playback.set(
				place,
				def,
				TABLE,
				msg.balls,
				if type(msg.away) == "table" then msg.away else nil,
				msg.fresh == true
			)
		end
	end
	return nil
end

-- A ball as a disc in its colour; the marked one carries a dot of the other colour.
local function ballChip(parent: Instance, kit: any, id: number, x: number, y: number, size: number, down: boolean)
	local rgb = Furniture.ballColor("bumper", id)
	local chip = Instance.new("Frame")
	chip.Name = `Ball{id}`
	chip.Size = UDim2.fromOffset(size, size)
	chip.Position = UDim2.fromOffset(x, y)
	chip.BackgroundColor3 = Color3.fromRGB(rgb[1], rgb[2], rgb[3])
	chip.BackgroundTransparency = if down then 0 else 0.75
	chip.BorderSizePixel = 0
	chip.Parent = parent
	kit.corner(chip, size)
	if id == 1 or id == 6 then
		local other = Furniture.ballColor("bumper", if id == 1 then 6 else 1)
		local dot = Instance.new("Frame")
		dot.Name = "Mark"
		dot.Size = UDim2.fromScale(0.4, 0.4)
		dot.Position = UDim2.fromScale(0.3, 0.3)
		dot.BackgroundColor3 = Color3.fromRGB(other[1], other[2], other[3])
		dot.BackgroundTransparency = chip.BackgroundTransparency
		dot.BorderSizePixel = 0
		dot.Parent = chip
		kit.corner(dot, size * 0.4)
	end
end

local function card(frame: Frame, view: { [string]: any }, you: number?, kit: any)
	local C, label, corner = kit.C, kit.label, kit.corner
	local g = view.game
	local seats = view.seats or {}
	local n = math.max(1, #seats)
	frame.Size = UDim2.fromOffset(500, 30 + n * 44)
	frame.Position = UDim2.new(1, -512, 1, -(42 + n * 44))
	local head = "BUMPER POOL"
	if g and g.phase == "opening" then
		head ..= "  -  the opening: both strike the marked ball"
	end
	label(frame, head, UDim2.new(1, -16, 0, 18), UDim2.fromOffset(8, 5), C.CYAN, Enum.Font.GothamBold)
	for s, seat in seats do
		local turn = view.phase == "playing" and g ~= nil and waitingFor(g, s)
		local row = Instance.new("Frame")
		row.Name = `Seat{s}`
		row.BackgroundColor3 = if turn then Color3.fromRGB(28, 96, 104) else Color3.fromRGB(26, 32, 66)
		row.Size = UDim2.new(1, -8, 0, 40)
		row.Position = UDim2.fromOffset(4, 26 + (s - 1) * 44)
		row.BorderSizePixel = 0
		row.Parent = frame
		corner(row, 6)
		local name = seat.name .. (if s == you then " (you)" else "") .. (if seat.gone then " (left)" else "")
		label(
			row,
			name,
			UDim2.fromScale(0.36, 0.5),
			UDim2.fromScale(0.014, 0.04),
			if turn then C.GOLD else C.WHITE,
			Enum.Font.GothamBold
		)
		local sunk = (g and g.sunk and g.sunk[s]) or 0
		local marked = g and g.markedDown and g.markedDown[s]
		local line = `{SIDE_WORDS[s] or ""}: {sunk} of 5 down` .. (if marked then "" else ", marked ball up")
		label(row, line, UDim2.fromScale(0.36, 0.42), UDim2.fromScale(0.014, 0.54), C.CYAN, Enum.Font.GothamMedium)
		-- the side's five: bright once they are down
		local up: { [number]: boolean } = {}
		if g then
			for _, id in upOf(g, s) do
				up[id] = true
			end
		end
		for k = 1, 5 do
			local id = (s - 1) * 5 + k
			ballChip(row, kit, id, 196 + (k - 1) * 40, 4, 32, g ~= nil and not up[id])
		end
	end
end

local function cardSig(view: { [string]: any }): any
	local g = view.game
	if g == nil then
		return false
	end
	return { g.sunk, g.markedDown, g.phase, g.waiting, g.balls and #g.balls }
end

local COLS = {
	{ title = "", key = "place", x = 0.02, w = 0.07 },
	{ title = "PLAYER", key = "name", x = 0.1, w = 0.4 },
	{ title = "SUNK", key = "sunk", x = 0.52, w = 0.14, strong = true },
	{ title = "SHOTS", key = "shots", x = 0.68, w = 0.14 },
	{ title = "BANKS", key = "banks", x = 0.84, w = 0.14 },
}

local function endCard(view: { [string]: any }, _you: number?): { [string]: any }?
	local g = view.game
	local r = view.result
	if g == nil or r == nil then
		return nil
	end
	local rows: { { [string]: any } } = {}
	for s, seat in view.seats or {} do
		table.insert(rows, {
			seat = s,
			name = seat.name,
			gone = seat.gone == true,
			place = if r.winner == nil or r.winner == s then 1 else 2,
			sunk = `{(r.scores and r.scores[s]) or 0} / 5`,
			shots = (r.shots and r.shots[s]) or 0,
			banks = (r.banks and r.banks[s]) or 0,
		})
	end
	table.sort(rows, function(a, b)
		if a.place ~= b.place then
			return a.place < b.place
		end
		return a.seat < b.seat
	end)
	return {
		title = "Bumper pool",
		line = Words.bumperEnd(g, namesOf(view)),
		rows = rows,
		cols = COLS,
		foot = "The balls go back on their spots in %d s. Anyone can walk up and start a new game.",
	}
end

local LEVEL_WORDS = { "easy", "medium", "hard" }
local lobbyButtons: { { string } } = { { "start", "Start now" } }
for _, p in Computer.BUMPER_PLAYERS do
	table.insert(lobbyButtons, { `addai:{p.name}`, `+ {p.name} ({LEVEL_WORDS[p.level] or "computer"})` })
end
table.insert(lobbyButtons, { "leave", "Leave (Q)" })

local entry: ClientGame.ClientGame = {
	game = "bumper_pool",
	help = {
		how = {
			"Bumper pool: five balls each (red or white), shot into the cup at the far end, round twelve rubber bumpers. No cue ball: you strike your own balls.",
			"The opening: both players strike their marked ball at once, banked off the cushion on their right. Whoever sinks it, or lies nearer their cup, shoots next.",
			"Sink your marked ball first. Sink one of your own and you shoot again. Another of yours before the marked one, or one of yours in your opponent's cup: they drop two of theirs in.",
			"First with all five down wins; your last ball in the wrong cup loses.",
		},
		keys = {
			"Click one of your balls, or R / 1 to 5: the ball to strike",
			"Drag, or A / D  turn the aim (Shift: fine)",
			"Pull the bar down and let go, or hold Space: power",
			"Drag the red dot, or W / S / Z / X: spin (C centres)",
			"T  top view (click the cloth to point the cue)",
			"V  walk round the table, V again to take the shot",
			"Q  leave the table",
			"Gamepad: left stick aims (L1 / R1 fine), right stick spin, hold and let go R2; D-pad picks the ball; Y top view, X walk",
			"Touch: tap your ball, drag to aim, drag the red dot, HOLD TO SHOOT",
		},
	},
	title = function(msg: { [string]: any }): string
		return `Bumper pool - {msg.label}`
	end,
	buttons = function(phase: string, _view: { [string]: any }?): { { string } }?
		if phase == "joined" or phase == "lobby" then
			return lobbyButtons
		elseif phase == "playing" then
			return { { "leave", "Leave (Q)" } }
		elseif phase == "done" then
			return { { "again", "Play again" }, { "leave", "Leave (Q)" } }
		end
		return nil
	end,
	new = new,
	card = card,
	cardSig = cardSig,
	endCard = endCard,
	kinds = { "bumper_pool_shot", "bumper_pool_rack" },
	watch = watch,
	sounds = {
		["bumper_pool.chalk"] = "", -- a turn begins: the cue is chalked
		["bumper_pool.strike"] = "", -- the tip meets the ball (volume by power)
		["bumper_pool.click"] = "", -- ball on ball (volume by closing speed; a burst is one click)
		["bumper_pool.crack"] = "", -- (eight-ball's break; never heard here)
		["bumper_pool.cushion"] = "", -- a ball off a cushion
		["bumper_pool.jaw"] = "", -- (eight-ball's pocket jaws; never heard here)
		["bumper_pool.post"] = "", -- the rubber thock of a ball off a bumper
		["bumper_pool.rim"] = "", -- a ball skipping over or lipping out of a cup
		["bumper_pool.drop"] = "", -- a ball dropping into a cup
		["bumper_pool.home"] = "", -- a sunk ball arriving in its side's tray
	},
	words = {
		idle = "You were taken off the bumper pool table: two shots in a row went unplayed",
		finished = "That game is over and the balls are back on their spots. Press E at the table to play.",
	},
}

return entry
