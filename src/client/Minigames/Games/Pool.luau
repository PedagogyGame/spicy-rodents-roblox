--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Minigames.Games.Pool
-- Pool's client half on the minigame framework (Client/Minigames/ClientGame; brief v2 §13a): eight-ball on the
-- two tables in the bowling alley's games room.
--   the shooter's controller is Pool/CueController (aim line and ghost ball, the cue drawn back for power, the
--     tip for spin, the ball in hand, calling the 8's pocket, walking round the table), given what is
--     eight-ball's own below: the cue ball is what is struck, where it may be set down (the rules' own check,
--     Shared/Minigames/Pool/Tables), which ball the cue first points at, and what the status line says;
--   what EVERYONE sees: "pool_shot" is one shot's script (Shared/Minigames/Pool/Wire), played back on the
--     table's balls by Pool/Playback whether or not you are in that game; "pool_rack" lays the balls out (a
--     new rack, a shot that did not count). A damaged script is not played: the server's own balls show;
--   the scorecard (each player's group and the balls of it still up, the 8, whose shot it is, the ball in
--     hand, the called pocket) and the end card (who won and how, balls potted, best run, shots, fouls);
--   the sound cue points (silent until their ids are filled in below).
-- Interface: a ClientGame.ClientGame

local Import = require("../../Import")
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

local TABLE = Tables.eightBall()

local function namesOf(view: { [string]: any }): { string }
	local names: { string } = {}
	for i, seat in view.seats or {} do
		names[i] = seat.name
	end
	return names
end

-- The balls a seat may hit first, from the rules' view (EightBall.legal, read off what the clients are sent).
local function legalFor(g: { [string]: any }, seat: number): { [number]: boolean }
	local out: { [number]: boolean } = {}
	local mine = g.groups and g.groups[seat]
	local eight = g.onEight == true and g.turn == seat
	for _, b in g.onTable or {} do
		local ok: boolean
		if not g.broken then
			ok = true
		elseif mine ~= "solids" and mine ~= "stripes" then
			ok = b ~= 8
		elseif eight then
			ok = b == 8
		else
			ok = (mine == "solids") == (b < 8) and b ~= 8
		end
		out[b] = ok
	end
	return out
end

local mode: CueController.Game = {
	game = "pool",
	table = TABLE,
	mine = function(view: { [string]: any }, you: number?): boolean
		return you ~= nil and view.turn == you
	end,
	strikeable = function(_g: { [string]: any }, _you: number): { number }
		return { 0 }
	end,
	inHand = function(g: { [string]: any }): string
		return if g.inHand == "kitchen" or g.inHand == "anywhere" then g.inHand else "none"
	end,
	mustCall = function(g: { [string]: any }, you: number): boolean
		return g.onEight == true and g.turn == you
	end,
	called = function(g: { [string]: any }): number
		return tonumber(g.called) or 0
	end,
	canPlace = function(g: { [string]: any }, spots: { CueController.Spot }, x: number, z: number): boolean
		if g.inHand == "kitchen" and not Tables.inKitchen(TABLE, z) then
			return false
		end
		return (g.inHand == "kitchen" or g.inHand == "anywhere") and Tables.canPlace(TABLE, x, z, spots, 0)
	end,
	-- the cue first points at the nearest ball the seat may hit (straight up the table if there is none)
	firstAim = function(g: { [string]: any }, you: number, spots: { CueController.Spot }, _ball: number): number
		local cue: CueController.Spot? = nil
		for _, s in spots do
			if s.id == 0 then
				cue = s
			end
		end
		if cue == nil then
			return 0
		end
		local legal = legalFor(g, you)
		local best: CueController.Spot? = nil
		local bestD = math.huge
		for _, s in spots do
			if s.id ~= 0 and legal[s.id] then
				local d = (s.x - cue.x) ^ 2 + (s.z - cue.z) ^ 2
				if d < bestD then
					best, bestD = s, d
				end
			end
		end
		return if best then Cue.angleOf(best.x - cue.x, best.z - cue.z) else 0
	end,
	args = function(_ball: number, angle: number, power: number, tipX: number, tipY: number, pocket: number): { any }
		return if pocket > 0 then { angle, power, tipX, tipY, pocket } else { angle, power, tipX, tipY }
	end,
	say = function(view: { [string]: any }, you: number?, phase: string): string
		local g = view.game
		local names = namesOf(view)
		if view.phase == "lobby" then
			return `Starting in {view.lobbyLeft or 0}: Space starts now. Add a computer opponent, wait for a second player, or play alone for practice.`
		elseif view.phase == "done" then
			return `{if g then Words.eightBallEnd(g, names) else "Game over."} Play again or Leave (Q).`
		elseif g == nil or view.phase ~= "playing" then
			return ""
		end
		-- what the last shot came to stays on the line: a foul is read here long after its banner has gone
		local last = Words.eightBall(g, names, nil)
		local lead = if last then last .. " " else ""
		if view.turn ~= you then
			local who = names[view.turn or 0] or "?"
			local on = if view.turn then Words.group(g, view.turn) else ""
			return `{lead}{who} is at the table ({on}). Walk round and watch; T is the top view.`
		elseif phase == "sent" or phase == "watch" then
			return "Your shot is on its way."
		end
		local what: string
		if not g.broken then
			what = "Your break."
		elseif g.onEight then
			what = if (tonumber(g.called) or 0) > 0
				then `Your shot at the 8, called for {Words.pocket(g.called)}.`
				else "Your shot at the 8: call a pocket first (click it, or press 1 to 6)."
		elseif g.open then
			what = "Your shot: the table is open (the first ball you pot gives you solids or stripes)."
		else
			local left = (you and g.left and g.left[you]) or 0
			what = `Your shot: {Words.group(g, you or 1)}, {left} left.`
		end
		return lead .. what
	end,
}

local function new(ctx: ClientGame.Ctx): ClientGame.Controller
	return CueController.new(ctx, mode)
end

local function cue(name: string, volume: number)
	MinigameSounds.play(`pool.{name}`, volume)
end

-- A shot at ANY pool table (you may only be watching): play the server's script on that table's balls.
local function watch(msg: { [string]: any }, place: ClientGame.Place?): any
	if place == nil or type(msg.station) ~= "string" then
		return nil
	end
	local site = if type(msg.site) == "string" then msg.site else "bowling_alley"
	local def = Games.station(msg.station, { [site] = place }) :: any
	if def == nil then
		return nil
	end
	if msg.kind == "pool_shot" then
		local script, why = Wire.decode(msg.text)
		if script == nil then
			warn(`MinigameClient: a pool shot could not be played ({why})`)
			return nil
		end
		-- (a replay of the winning shot is the same script on a slower clock)
		Playback.play(place, def, script, {
			lead = msg.lead,
			onCue = cue,
			speed = if msg.replay == true then msg.speed else nil,
		})
		return script
	elseif msg.kind == "pool_rack" then
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

-- A ball as a disc with its number, as it is painted (a striped ball: white with a coloured middle).
local function ballChip(parent: Instance, kit: any, id: number, x: number, y: number, size: number, up: boolean)
	local rgb, striped = Furniture.ballColor("eightball", id)
	local colour = Color3.fromRGB(rgb[1], rgb[2], rgb[3])
	local chip = Instance.new("Frame")
	chip.Name = `Ball{id}`
	chip.Size = UDim2.fromOffset(size, size)
	chip.Position = UDim2.fromOffset(x, y)
	chip.BackgroundColor3 = if striped then Color3.fromRGB(244, 242, 232) else colour
	chip.BackgroundTransparency = if up then 0 else 0.8
	chip.BorderSizePixel = 0
	chip.Parent = parent
	kit.corner(chip, size)
	if striped then
		local band = Instance.new("Frame")
		band.Size = UDim2.fromScale(1, 0.5)
		band.Position = UDim2.fromScale(0, 0.25)
		band.BackgroundColor3 = colour
		band.BackgroundTransparency = if up then 0 else 0.8
		band.BorderSizePixel = 0
		band.Parent = chip
	end
	local text =
		kit.label(chip, tostring(id), UDim2.fromScale(0.7, 0.7), UDim2.fromScale(0.15, 0.15), nil, Enum.Font.GothamBold)
	text.TextColor3 = if id == 1 or id == 9 then Color3.fromRGB(20, 20, 20) else Color3.fromRGB(255, 255, 255)
	text.TextStrokeTransparency = 0.4
	text.TextTransparency = if up then 0 else 0.6
end

local function card(frame: Frame, view: { [string]: any }, you: number?, kit: any)
	local C, label, corner = kit.C, kit.label, kit.corner
	local g = view.game
	local seats = view.seats or {}
	local n = math.max(1, #seats)
	frame.Size = UDim2.fromOffset(560, 30 + n * 44)
	frame.Position = UDim2.new(1, -572, 1, -(42 + n * 44))
	local up: { [number]: boolean } = {}
	for _, b in (g and g.onTable) or {} do
		up[b] = true
	end
	local head = "EIGHT-BALL"
	if g and g.inHand == "kitchen" then
		head ..= "  -  ball in hand behind the head string"
	elseif g and g.inHand == "anywhere" then
		head ..= "  -  ball in hand"
	end
	if g and (tonumber(g.called) or 0) > 0 then
		head ..= `  -  the 8 is called for {Words.pocket(g.called)}`
	end
	label(frame, head, UDim2.new(1, -16, 0, 18), UDim2.fromOffset(8, 5), C.CYAN, Enum.Font.GothamBold)
	for s, seat in seats do
		local turn = view.turn == s and view.phase == "playing"
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
			UDim2.fromScale(0.3, 0.5),
			UDim2.fromScale(0.012, 0.04),
			if turn then C.GOLD else C.WHITE,
			Enum.Font.GothamBold
		)
		local group = if g then Words.group(g, s) else "open table"
		local left = (g and g.left and g.left[s]) or 7
		local line = if group == "open table" then "open table" else `{group}: {left} left`
		if g and g.bestRun and (g.bestRun[s] or 0) > 0 then
			line ..= `  (best run {g.bestRun[s]})`
		end
		label(row, line, UDim2.fromScale(0.3, 0.42), UDim2.fromScale(0.012, 0.54), C.CYAN, Enum.Font.GothamMedium)
		-- the seat's own balls (all fifteen while the table is open), and the 8
		local ids: { number } = {}
		if group == "solids" then
			ids = { 1, 2, 3, 4, 5, 6, 7 }
		elseif group == "stripes" then
			ids = { 9, 10, 11, 12, 13, 14, 15 }
		end
		for k, id in ids do
			ballChip(row, kit, id, 182 + (k - 1) * 40, 4, 32, up[id] == true)
		end
		if #ids > 0 then
			ballChip(row, kit, 8, 182 + 7 * 40 + 14, 4, 32, up[8] == true)
		end
	end
end

local function cardSig(view: { [string]: any }): any
	local g = view.game
	if g == nil then
		return false
	end
	return { g.groups, g.onTable, g.inHand, g.called or 0, g.bestRun, g.left }
end

-- the end card's columns: heading, the row's field, where it starts and how wide it is (fractions of the card)
local COLS = {
	{ title = "", key = "place", x = 0.02, w = 0.07 },
	{ title = "PLAYER", key = "name", x = 0.1, w = 0.34 },
	{ title = "POTTED", key = "potted", x = 0.45, w = 0.13, strong = true },
	{ title = "BEST RUN", key = "bestRun", x = 0.59, w = 0.14 },
	{ title = "SHOTS", key = "shots", x = 0.74, w = 0.12 },
	{ title = "FOULS", key = "fouls", x = 0.87, w = 0.12 },
}

local function endCard(view: { [string]: any }, _you: number?): { [string]: any }?
	local g = view.game
	local r = view.result
	if g == nil or r == nil then
		return nil
	end
	local names = namesOf(view)
	local rows: { { [string]: any } } = {}
	for s, seat in view.seats or {} do
		table.insert(rows, {
			seat = s,
			name = seat.name,
			gone = seat.gone == true,
			place = if r.winner == nil then 1 elseif r.winner == s then 1 else 2,
			potted = (r.scores and r.scores[s]) or 0,
			bestRun = (r.bestRun and r.bestRun[s]) or 0,
			shots = (r.shots and r.shots[s]) or 0,
			fouls = (r.fouls and r.fouls[s]) or 0,
		})
	end
	table.sort(rows, function(a, b)
		if a.place ~= b.place then
			return a.place < b.place
		end
		return a.seat < b.seat
	end)
	return {
		title = "Eight-ball",
		line = Words.eightBallEnd(g, names),
		rows = rows,
		cols = COLS,
		foot = "The table is racked again in %d s. Anyone can walk up and start a new game.",
	}
end

local LEVEL_WORDS = { "easy", "medium", "hard" }
local lobbyButtons: { { string } } = { { "start", "Start now" } }
for _, p in Computer.POOL_PLAYERS do
	table.insert(lobbyButtons, { `addai:{p.name}`, `+ {p.name} ({LEVEL_WORDS[p.level] or "computer"})` })
end
table.insert(lobbyButtons, { "leave", "Leave (Q)" })

local entry: ClientGame.ClientGame = {
	game = "pool",
	help = {
		how = {
			"Eight-ball: break the rack, then pot all of your group (solids 1-7 or stripes 9-15) and then the 8 in a pocket you call.",
			"Pot one of your own and you shoot again. A foul (the cue ball goes in, hits nothing or the wrong ball first, or no ball reaches a cushion) gives the other player the cue ball in hand.",
			"The 8 too early, or in the wrong pocket, loses the game.",
		},
		keys = {
			"Drag, or A / D  turn the aim (Shift: fine)",
			"Pull the bar down and let go, or hold Space: power",
			"Drag the red dot, or W / S / Z / X: spin (C centres)",
			"T  top view (click the cloth to point the cue)",
			"V  walk round the table, V again to take the shot",
			"Ball in hand: drag the cue ball, then Space",
			"On the 8: click a pocket to call it (or 1 to 6)",
			"Q  leave the table",
			"Gamepad: left stick aims (L1 / R1 fine), right stick spin, hold and let go R2; Y top view, X walk; D-pad moves the ball in hand (A sets it) and picks the 8's pocket",
			"Touch: drag to aim, drag the red dot, HOLD TO SHOOT; drag the cue ball in hand, then DONE; tap a pocket to call it",
		},
	},
	title = function(msg: { [string]: any }): string
		return `Pool - {msg.label}`
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
	kinds = { "pool_shot", "pool_rack" },
	watch = watch,
	sounds = {
		["pool.chalk"] = "", -- a turn begins: the cue is chalked
		["pool.strike"] = "", -- the tip meets the ball (volume by power)
		["pool.click"] = "", -- ball on ball (volume by closing speed; a burst is one click)
		["pool.crack"] = "", -- the break opening a full rack
		["pool.cushion"] = "", -- a ball off a cushion
		["pool.jaw"] = "", -- a ball rattling in a pocket's jaws
		["pool.post"] = "", -- (bumper pool's rubber; never heard here)
		["pool.rim"] = "", -- a ball lipping out
		["pool.drop"] = "", -- a ball dropping into a pocket
		["pool.home"] = "", -- a potted ball arriving in the tray
	},
	words = {
		idle = "You were taken off the pool table: two shots in a row went unplayed",
		finished = "That game is over and the table is racked again. Press E at a pool table to play.",
	},
}

return entry
