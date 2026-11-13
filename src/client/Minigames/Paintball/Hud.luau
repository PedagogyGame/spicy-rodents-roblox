--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Minigames.Paintball.Hud
-- The paintball HUD (checklist PB-2, PB-7; brief v2 §13: "a match timer, scoreboard and end card"): what a
-- player in the match reads without looking for it, and nothing in the middle of the view but the
-- crosshair. It decides nothing: every frame it shows what SeatCore holds.
--   the crosshair  four arms and a dot; the arms stand wider and dimmer whenever a press would not
--                  leave as a ball this instant (the marker down, reloading, protected, in a spawn
--                  room): the gap is the "not ready" light. The hit marker is an X over it, shown
--                  only when the server said you tagged someone.
--   the top        both scores in the teams' colours either side of the clock, yours underlined
--   the pips       five, at the bottom; a bar that fills through the reload and flashes on a dry click
--   the status     one line under the crosshair, by priority: tagged out (by whom, the count back),
--                  protected, about to be taken off for standing idle, safe in your own room, the last
--                  refusal
--   protected      the moment after a respawn: a border round the whole screen in your team's colour
--                  that breathes, and a bar under the status line that drains with the time left. It is
--                  gone the instant the marker may fire (the marker itself is a ghost until then)
--   tagged         a tick on a ring round the crosshair pointing at where the ball came from, and
--                  paint on the goggles that clears over Tuning.goggleSecs
--   the feed       who tagged whom, top right, a few lines, each a few seconds
--   the briefing   the framework's own How-to-play card is the controls card (shown through the
--                  briefing and, with a keyboard or a gamepad, through a late joiner's first
--                  Tuning.cardSecs; put away when the match is live; H brings it back), the side you
--                  are on, and the count to the start
--   the scoreboard held on G / View / SCORES: both sides, tags and times out; with it a button the
--                  size of a pixel that is Modal, which is what frees a first-person mouse to press
--                  Leave and Change sides
--   the end card   the framework's (ClientGame.endCard); this adds the WBLW bulletin's awards beside it
--   touch          FIRE at the lower right as a plain Frame (it does not sink its touch: a drag that
--                  starts on it still turns the view; Controls reads the touch itself), a second FIRE
--                  on the left, RELOAD, CROUCH, SCORES
-- EVERY SCREEN, FROM A SMALL PHONE TO 4K. The pieces are drawn for a screen of Tuning.hudFitWide by
-- hudFitTall and scaled as one. `layout` below is the whole of that arithmetic, pure, and the spec
-- holds it to a list of real screens: every piece on the screen, none on another, none under a thumb's
-- button. The feed drops under the top bar where the two would meet; the status line moves clear of
-- the FIRE buttons; the scoreboard, the framework's end card and its controls card are fitted to a
-- screen smaller than they are; the bulletin's awards go beside the end card, under it, or nowhere. The
-- crosshair is never scaled DOWN (a thin line stays a whole pixel) and the touch buttons never at all
-- (a thumb is the same size on every phone).
-- Its own ScreenGui ("PaintballHud" under PlayerGui), destroyed by stop().
-- Interface: new(seat, ctx, tuning?) -> Hud { gui, touch, step(dt), stop(), fireRect() -> (x0, y0, x1, y1) };
--   scaleFor(vw, vh, tuning?) -> number; layout(vw, vh, touch, tuning?, rows?) -> Layout (both pure);
--   types Hud, Rect, Layout

local Import = require("../../Import")
local Contract: typeof(require(game.ReplicatedStorage.Shared.Minigames.Paintball.Contract)) =
	Import.shared("Minigames/Paintball/Contract")
local ClientGame = require("../ClientGame")
local SeatCore = require("./SeatCore")
local Tuning = require("./Tuning")

export type Hud = {
	gui: ScreenGui,
	touch: { [string]: GuiObject }, -- FireRight (a Frame), FireLeft, Reload, Crouch, Scores (buttons); empty without touch
	step: (self: Hud, dt: number) -> (),
	stop: (self: Hud) -> (),
	fireRect: (self: Hud) -> (number, number, number, number),
}

export type Rect = { x: number, y: number, w: number, h: number } -- screen pixels, from the top left

-- Where everything goes on a screen of vw by vh (see layout).
export type Layout = {
	scale: number, -- of every piece but the crosshair, the washes over the whole screen and the touch buttons
	aim: number, -- of the crosshair and the hit marker (never under 1)
	phaseY: number, -- the briefing's line: how far down the scaled screen, and how wide
	phaseW: number,
	feedY: number,
	feedW: number,
	statusY: number, -- the status line: how far under the middle of the scaled screen, and how wide
	statusW: number,
	board: number, -- the scoreboard's own fit on the scaled screen (1: as drawn)
	card: number, -- the fit of the framework's end card (1: as the framework draws it)
	help: number, -- and of its controls card
	awards: number, -- the scale of the bulletin's awards; 0: no room for them
	awardsX: number, -- and their top left corner
	awardsY: number,
	rects: { [string]: Rect }, -- every piece where it lands (a spec reads this)
}

local Hud = {}

local R = Contract.Rules
local WHITE = { 245, 245, 245 }
local NAVY = { 16, 20, 44 }
local GOLD = { 255, 214, 92 }
local SLATE = { 50, 56, 90 }
local WARN = { 255, 90, 80 }
local ROWS = R.teamMax
local FIT = "PaintballFit" -- the UIScale this HUD hangs on the framework's cards on a small screen

-- The pieces as drawn, in pixels of the screen they are drawn for.
local TOP_W, TOP_H = 260, 38
local PHASE_W, PHASE_H = 440, 24
local PHASE_NARROW = 300 -- narrower than this and the briefing's line says less, or goes under the SCORES button
local COUNT_W, COUNT_H = 240, 110
local FEED_W, FEED_ROW = 360, 23
local PIPS_W, PIPS_H = 150, 40
local STATUS_W, STATUS_H = 560, 30
local STATUS_BAND = 44 -- the status line with what stands under it (the protection's bar, the briefing's second line)
local STATUS_NARROW = 420 -- narrower than this and the status line says it in fewer words
local SHIELD_W, SHIELD_H = 200, 6
local BOARD_W, BOARD_H = 640, 120 + ROWS * 26
local AWARDS_W, AWARDS_H = 300, 200
-- The framework's own cards (Client/UI/MinigameUI: the summary is 520 wide and 150 + 32 a row tall and
-- stands 20 above the middle; the help card is 340 by 430, 12 in from the left). If the framework
-- changes them the fit is a little off and nothing breaks.
local CARD_W, CARD_HEAD, CARD_ROW, CARD_LIFT = 520, 150, 32, 20
local HELP_W, HELP_H, HELP_X = 340, 430, 12
local TOUCH: { [string]: string } = {
	FireRight = "touchFire",
	FireLeft = "touchFireLeft",
	Reload = "touchReload",
	Crouch = "touchCrouch",
	Scores = "touchScores",
}
-- what a thumb presses, the stock jump button among them: nothing of the HUD may lie under one
local THUMBS = { "FireRight", "FireLeft", "Reload", "Crouch", "Scores", "Jump" }

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function teamRgb(team: number): { number }
	local t = Contract.TEAMS[team]
	return if t then t.color else WHITE
end

local function frame(name: string, parent: Instance, size: UDim2, pos: UDim2, color: { number }?, alpha: number?): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BorderSizePixel = 0
	f.Size = size
	f.Position = pos
	f.BackgroundColor3 = rgb(color or NAVY)
	f.BackgroundTransparency = alpha or 0
	f.Parent = parent
	return f
end

local function label(
	name: string,
	parent: Instance,
	size: UDim2,
	pos: UDim2,
	color: { number }?,
	bold: boolean?
): TextLabel
	local t = Instance.new("TextLabel")
	t.Name = name
	t.BackgroundTransparency = 1
	t.Size = size
	t.Position = pos
	t.Text = ""
	t.TextColor3 = rgb(color or WHITE)
	t.Font = if bold then Enum.Font.GothamBold else Enum.Font.GothamMedium
	t.TextScaled = true
	t.TextStrokeTransparency = 0.5
	t.Parent = parent
	return t
end

local function round(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function scaleOn(parent: Instance): UIScale
	local sc = Instance.new("UIScale")
	sc.Name = FIT
	sc.Parent = parent
	return sc
end

local function clockText(seconds: number): string
	local n = math.max(0, math.ceil(seconds))
	return `{n // 60}:{string.format("%02d", n % 60)}`
end

local function overlap(a: Rect, b: Rect): boolean
	return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

-- How big the HUD is drawn on a screen of vw by vh: 1 on anything from a small laptop to 1080p; smaller
-- on a phone, down to Tuning.hudSmallest; larger past Tuning.hudBigWide by hudBigTall, so that 4K is
-- not a HUD for ants.
function Hud.scaleFor(vw: number, vh: number, tuning: typeof(Tuning.T)?): number
	local tune = tuning or Tuning
	local fit = math.min(vw / tune.hudFitWide, vh / tune.hudFitTall)
	if fit < 1 then
		return math.max(tune.hudSmallest, fit)
	end
	return math.max(1, math.min(vw / tune.hudBigWide, vh / tune.hudBigTall))
end

-- THE LAYOUT, pure: where every piece of the HUD goes on a screen of vw by vh, with or without the
-- touch buttons, and how the framework's cards are fitted (rows: the lines on the end card, sixteen
-- unless told). Everything in `rects` is in screen pixels.
function Hud.layout(vw: number, vh: number, touch: boolean, tuning: typeof(Tuning.T)?, rows: number?): Layout
	local tune = tuning or Tuning
	local s = Hud.scaleFor(vw, vh, tune)
	local w, h = vw / s, vh / s -- the scaled screen the pieces are laid out on
	local cx, cy = w / 2, h / 2
	local rects: { [string]: Rect } = {}
	local function put(name: string, x: number, y: number, pw: number, ph: number): Rect
		local r = { x = x * s, y = y * s, w = pw * s, h = ph * s }
		rects[name] = r
		return r
	end
	if touch then
		for name, key in TOUCH do
			local spec = (tune :: any)[key] :: { number }
			local size = math.min(spec[3], vw, vh)
			rects[name] = {
				x = math.clamp(vw * spec[1] - size / 2, 0, vw - size),
				y = math.clamp(vh * spec[2] - size / 2, 0, vh - size),
				w = size,
				h = size,
			}
		end
		-- (the stock jump button, the PlayerModule's TouchJump, is not this HUD's to move: 70 px on a
		-- small screen, 120 on a large one)
		rects.Jump = if math.min(vw, vh) <= 500
			then { x = vw - 95, y = vh - 90, w = 70, h = 70 }
			else { x = vw - 170, y = vh - 210, w = 120, h = 120 }
	end
	-- The widest strip centred on the screen, `band` tall at `y` down the scaled screen and no wider
	-- than `most`, that is clear of every one of `others`: it stops short of whatever stands beside it.
	local function widest(y: number, band: number, most: number, others: { string }): number
		local top, bottom = y * s, (y + band) * s
		local half = math.min(most, w - 24) / 2
		for _, name in others do
			local o = rects[name]
			if o and o.y < bottom - 1e-6 and top < o.y + o.h - 1e-6 then
				if o.x + o.w <= vw / 2 then
					half = math.min(half, cx - (o.x + o.w) / s - 6)
				elseif o.x >= vw / 2 then
					half = math.min(half, o.x / s - cx - 6)
				else
					half = 0
				end
			end
		end
		return math.max(0, 2 * half)
	end
	local top = put("Top", cx - TOP_W / 2, 8, TOP_W, TOP_H)
	-- (the pips with the reload's word above them)
	local pips = put("Pips", cx - PIPS_W / 2, h - 90, PIPS_W, PIPS_H + 20)
	put("Count", cx - COUNT_W / 2, 0.28 * h - COUNT_H / 2, COUNT_W, COUNT_H)
	-- the briefing's line: under the top bar, as wide as the buttons beside it leave; under the SCORES
	-- button where that would be too narrow to read
	local phaseY = 50
	local phaseW = widest(phaseY, PHASE_H, PHASE_W, THUMBS)
	local scores = rects.Scores
	if phaseW < PHASE_NARROW and scores then
		phaseY = (scores.y + scores.h + 4) / s
		phaseW = widest(phaseY, PHASE_H, PHASE_W, THUMBS)
	end
	phaseW = math.max(phaseW, 160)
	local phase = put("Phase", cx - phaseW / 2, phaseY, phaseW, PHASE_H)
	-- the feed: beside the top bar where it is clear of the bar and of the briefing's line, else under the line
	local feedW = math.min(FEED_W, w - 24)
	local feedH = tune.feedLines * FEED_ROW - 3
	local feedX = w - feedW - 12
	local feed = put("Feed", feedX, 8, feedW, feedH)
	local feedY = 8
	if overlap(feed, top) or overlap(feed, phase) or feedX < cx + TOP_W / 2 + 12 then
		feedY = phaseY + PHASE_H + 4
		put("Feed", feedX, feedY, feedW, feedH)
	end
	-- the status line (with the protection's bar, or the briefing's second line, under it): under the
	-- crosshair, as wide as the thumbs' buttons leave; under the FIRE buttons where that is wider
	local beside = table.clone(THUMBS)
	table.insert(beside, "Pips")
	local statusY = 70
	local statusW = widest(cy + statusY, STATUS_BAND, STATUS_W, beside)
	local left, right = rects.FireLeft, rects.FireRight
	if left and right and statusW < STATUS_W then
		local under = (math.max(left.y + left.h, right.y + right.h) + 4) / s - cy
		local wide = widest(cy + under, STATUS_BAND, STATUS_W, beside)
		if wide > statusW and (cy + under + STATUS_BAND) * s <= pips.y then
			statusY, statusW = under, wide
		end
	end
	statusW = math.max(statusW, 160)
	put("Status", cx - statusW / 2, cy + statusY, statusW, STATUS_BAND)
	-- the scoreboard: in the middle, fitted to a screen smaller than it
	local board = math.min(1, (w - 16) / BOARD_W, (h - 16) / BOARD_H)
	put("Board", cx - BOARD_W * board / 2, cy - BOARD_H * board / 2, BOARD_W * board, BOARD_H * board)
	-- the framework's end card: as the framework draws it where it fits, else fitted and centred
	local cardH = CARD_HEAD + (rows or R.slots) * CARD_ROW
	local card = math.min(1, (vh - 50) / cardH, (vw - 20) / CARD_W)
	local cardRect: Rect = if card < 0.999
		then { x = (vw - CARD_W * card) / 2, y = (vh - cardH * card) / 2, w = CARD_W * card, h = cardH * card }
		else { x = (vw - CARD_W) / 2, y = (vh - cardH) / 2 - CARD_LIFT, w = CARD_W, h = cardH }
	rects.Card = cardRect
	-- its controls card: fitted to a screen shorter than it
	local help = math.min(1, (vh - 16) / HELP_H)
	rects.Help = { x = HELP_X, y = (vh - HELP_H * help) / 2, w = HELP_W * help, h = HELP_H * help }
	-- the bulletin's awards: left of the end card, else under it, else not at all
	local awards = math.min(s, (cardRect.x - 24) / AWARDS_W)
	local awardsX, awardsY = 12, (vh - AWARDS_H * awards) / 2
	if awards < 0.5 then
		local room = vh - (cardRect.y + cardRect.h) - 16
		awards = math.min(s, room / AWARDS_H, (vw - 24) / AWARDS_W)
		awardsX, awardsY = (vw - AWARDS_W * awards) / 2, cardRect.y + cardRect.h + 8
		if awards < 0.5 then
			awards = 0
		end
	end
	if awards > 0 then
		rects.Awards = { x = awardsX, y = awardsY, w = AWARDS_W * awards, h = AWARDS_H * awards }
	end
	return {
		scale = s,
		aim = math.max(1, s),
		phaseY = phaseY,
		phaseW = phaseW,
		feedY = feedY,
		feedW = feedW,
		statusY = statusY,
		statusW = statusW,
		board = board,
		card = card,
		help = help,
		awards = awards,
		awardsX = awardsX,
		awardsY = awardsY,
		rects = rects,
	}
end

function Hud.new(seat: SeatCore.Seat, ctx: ClientGame.Ctx, tuning: typeof(Tuning.T)?): Hud
	local tune = tuning or Tuning
	local UIS = game:GetService("UserInputService")
	local player = game:GetService("Players").LocalPlayer
	local camera = workspace.CurrentCamera
	local touchOn = UIS.TouchEnabled == true
	-- thumbs only (a phone, a tablet): the buttons on the screen are the controls, and say what they do
	local thumbs = touchOn and UIS.KeyboardEnabled ~= true
	local padOnly = not touchOn and UIS.GamepadEnabled == true and UIS.KeyboardEnabled ~= true
	local gui = Instance.new("ScreenGui")
	gui.Name = "PaintballHud"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 19 -- under the framework's own (its buttons and its end card stay on top)
	gui.Parent = player:WaitForChild("PlayerGui")

	local function set(t: TextLabel, text: string)
		if t.Text ~= text then
			t.Text = text
		end
	end
	local function show(g: GuiObject, on: boolean)
		if g.Visible ~= on then
			g.Visible = on
		end
	end

	-- THE SCALED SCREEN: everything but the crosshair, the washes and the touch buttons hangs on it
	local root = frame("Root", gui, UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), NAVY, 1)
	local rootScale = scaleOn(root)

	-- the crosshair and the hit marker
	local cross = frame("Cross", gui, UDim2.fromOffset(2, 2), UDim2.fromScale(0.5, 0.5), WHITE)
	cross.AnchorPoint = Vector2.new(0.5, 0.5)
	local crossScale = scaleOn(cross)
	local arms: { Frame } = {}
	for i = 1, 4 do
		arms[i] = frame(`Arm{i}`, cross, UDim2.fromOffset(2, 2), UDim2.fromOffset(0, 0), WHITE)
	end
	local hit = frame("Hit", gui, UDim2.fromOffset(0, 0), UDim2.fromScale(0.5, 0.5), WHITE, 1)
	local hitScale = scaleOn(hit)
	for i = 1, 4 do
		local a = frame(`X{i}`, hit, UDim2.fromOffset(3, 12), UDim2.fromOffset(0, 0), WHITE)
		local sx, sy = if i % 2 == 1 then 1 else -1, if i <= 2 then 1 else -1
		a.Position = UDim2.fromOffset(sx * 11 - 1, sy * 11 - 6)
		a.Rotation = if sx * sy > 0 then -45 else 45
	end
	hit.Visible = false

	-- the top: score, clock, score
	local top = frame("Top", root, UDim2.fromOffset(TOP_W, TOP_H), UDim2.new(0.5, -TOP_W / 2, 0, 8), NAVY, 0.25)
	round(top, 10)
	local score1 = label("Score1", top, UDim2.fromOffset(70, 30), UDim2.fromOffset(8, 4), teamRgb(1), true)
	local clock = label("Clock", top, UDim2.fromOffset(96, 30), UDim2.fromOffset(82, 4), WHITE, true)
	local score2 = label("Score2", top, UDim2.fromOffset(70, 30), UDim2.fromOffset(182, 4), teamRgb(2), true)
	local mine = frame("Mine", top, UDim2.fromOffset(54, 3), UDim2.fromOffset(16, 33), WHITE)
	local phaseLine =
		label("Phase", root, UDim2.fromOffset(PHASE_W, PHASE_H), UDim2.new(0.5, -PHASE_W / 2, 0, 50), WHITE, true)
	local count = label(
		"Count",
		root,
		UDim2.fromOffset(COUNT_W, COUNT_H),
		UDim2.new(0.5, -COUNT_W / 2, 0.28, -COUNT_H / 2),
		GOLD,
		true
	)

	-- the pips and the reload
	local pips = frame("Pips", root, UDim2.fromOffset(PIPS_W, PIPS_H), UDim2.new(0.5, -PIPS_W / 2, 1, -70), NAVY, 1)
	local pip: { Frame } = {}
	for i = 1, R.magazine do
		pip[i] = frame(`Pip{i}`, pips, UDim2.fromOffset(20, 20), UDim2.fromOffset(8 + (i - 1) * 28, 0), WHITE)
		round(pip[i], 10)
	end
	local reloadBar = frame("ReloadBar", pips, UDim2.fromOffset(134, 6), UDim2.fromOffset(8, 26), SLATE)
	local reloadFill = frame("Fill", reloadBar, UDim2.fromScale(0, 1), UDim2.fromOffset(0, 0), GOLD)
	local reloadText = label("ReloadText", pips, UDim2.fromOffset(134, 16), UDim2.fromOffset(8, -20), GOLD, true)

	-- the status line, the ring's tick, the goggles
	local status =
		label("Status", root, UDim2.fromOffset(STATUS_W, STATUS_H), UDim2.new(0.5, -STATUS_W / 2, 0.5, 70), WHITE, true)
	-- (the briefing's second line stands where the protection's bar will: never both)
	local second = label(
		"Status2",
		root,
		UDim2.fromOffset(STATUS_W, STATUS_BAND - STATUS_H + 2),
		UDim2.new(0.5, -STATUS_W / 2, 0.5, 70 + STATUS_H - 2),
		{ 140, 236, 236 },
		false
	)
	local tick = frame("TaggedFrom", root, UDim2.fromOffset(8, 34), UDim2.new(0.5, -4, 0.5, -17), WHITE)
	tick.Visible = false
	local goggles = frame("Goggles", gui, UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), WHITE, 1)
	goggles.Visible = false
	local blobs: { Frame } = {}
	for i, at in { { 0.22, 0.3, 0.32 }, { 0.6, 0.55, 0.4 }, { 0.72, 0.18, 0.24 }, { 0.38, 0.72, 0.28 } } do
		-- (a blot is a share of the screen's height across, so a phone's goggles are as wet as a monitor's)
		blobs[i] = frame(`Blob{i}`, goggles, UDim2.fromScale(at[3], at[3]), UDim2.fromScale(at[1], at[2]))
		blobs[i].AnchorPoint = Vector2.new(0.5, 0.5)
		blobs[i].SizeConstraint = Enum.SizeConstraint.RelativeYY
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0.5, 0)
		c.Parent = blobs[i]
	end

	-- the respawn's protection: a border and a draining bar
	local shield = frame("Shield", gui, UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), WHITE, 1)
	shield.Visible = false
	local edge = tune.shieldEdge
	local edges: { Frame } = {
		frame("Top", shield, UDim2.new(1, 0, 0, edge), UDim2.fromScale(0, 0), WHITE, 0.5),
		frame("Bottom", shield, UDim2.new(1, 0, 0, edge), UDim2.new(0, 0, 1, -edge), WHITE, 0.5),
		frame("Left", shield, UDim2.new(0, edge, 1, 0), UDim2.fromScale(0, 0), WHITE, 0.5),
		frame("Right", shield, UDim2.new(0, edge, 1, 0), UDim2.new(1, -edge, 0, 0), WHITE, 0.5),
	}
	local shieldBar = frame(
		"ShieldBar",
		shield,
		UDim2.fromOffset(SHIELD_W, SHIELD_H),
		UDim2.new(0.5, -SHIELD_W / 2, 0.5, 70 + STATUS_H + 4),
		SLATE
	)
	local shieldFill = frame("Fill", shieldBar, UDim2.fromScale(1, 1), UDim2.fromOffset(0, 0), WHITE)

	-- the feed
	local feed = frame(
		"Feed",
		root,
		UDim2.fromOffset(FEED_W, tune.feedLines * FEED_ROW - 3),
		UDim2.new(1, -FEED_W - 12, 0, 8),
		NAVY,
		1
	)
	local lines: { TextLabel } = {}
	for i = 1, tune.feedLines do
		lines[i] = label(`Line{i}`, feed, UDim2.new(1, 0, 0, 20), UDim2.fromOffset(0, (i - 1) * FEED_ROW), WHITE, false)
		lines[i].TextXAlignment = Enum.TextXAlignment.Right
	end

	-- the scoreboard
	local board = frame("Board", root, UDim2.fromOffset(BOARD_W, BOARD_H), UDim2.fromScale(0.5, 0.5), NAVY, 0.1)
	board.AnchorPoint = Vector2.new(0.5, 0.5)
	local boardScale = scaleOn(board)
	round(board, 12)
	board.Visible = false
	label("Title", board, UDim2.fromOffset(620, 28), UDim2.fromOffset(10, 8), GOLD, true).Text = "SCOREBOARD"
	local boardHint =
		label("Hint", board, UDim2.fromOffset(620, 20), UDim2.fromOffset(10, 92 + ROWS * 26), { 140, 236, 236 }, false)
	local heads: { TextLabel } = {}
	local rows: { { { name: TextLabel, tags: TextLabel, outs: TextLabel, back: Frame } } } = {}
	for team = 1, 2 do
		local x = 10 + (team - 1) * 315
		heads[team] =
			label(`Head{team}`, board, UDim2.fromOffset(305, 24), UDim2.fromOffset(x, 40), teamRgb(team), true)
		local keys = label(
			`Keys{team}`,
			board,
			UDim2.fromOffset(110, 14),
			UDim2.fromOffset(x + 195, 68),
			{ 140, 236, 236 },
			true
		)
		keys.Text = "TAGS   OUT"
		rows[team] = {}
		for i = 1, ROWS do
			local y = 86 + (i - 1) * 26
			local back =
				frame(`Row{team}_{i}`, board, UDim2.fromOffset(305, 23), UDim2.fromOffset(x, y), { 26, 32, 66 })
			round(back, 5)
			local name = label("Name", back, UDim2.fromOffset(185, 19), UDim2.fromOffset(6, 2), WHITE, false)
			name.TextXAlignment = Enum.TextXAlignment.Left
			rows[team][i] = {
				back = back,
				name = name,
				tags = label("Tags", back, UDim2.fromOffset(46, 19), UDim2.fromOffset(196, 2), GOLD, true),
				outs = label("Outs", back, UDim2.fromOffset(46, 19), UDim2.fromOffset(250, 2), WHITE, false),
			}
		end
	end

	-- the bulletin's awards, beside the framework's end card
	local awards =
		frame("Awards", gui, UDim2.fromOffset(AWARDS_W, AWARDS_H), UDim2.new(0, 12, 0.5, -AWARDS_H / 2), NAVY, 0.1)
	local awardsScale = scaleOn(awards)
	round(awards, 12)
	awards.Visible = false
	label("Channel", awards, UDim2.fromOffset(280, 22), UDim2.fromOffset(10, 8), GOLD, true).Text =
		"WBLW CHANNEL 7 SPORTS"
	local awardLines: { TextLabel } = {}
	for i = 1, 6 do
		awardLines[i] =
			label(`Award{i}`, awards, UDim2.fromOffset(280, 22), UDim2.fromOffset(10, 12 + i * 26), WHITE, false)
		awardLines[i].TextXAlignment = Enum.TextXAlignment.Left
	end

	-- what frees a first-person mouse while there is something to press
	local modal = Instance.new("TextButton")
	modal.Name = "Modal"
	modal.Text = ""
	modal.BackgroundTransparency = 1
	modal.Size = UDim2.fromOffset(1, 1)
	modal.Position = UDim2.fromOffset(0, 0)
	modal.Modal = true
	modal.Visible = false
	modal.Parent = gui

	-- touch
	local touch: { [string]: GuiObject } = {}
	if touchOn then
		local layer = frame("Touch", gui, UDim2.fromScale(1, 1), UDim2.fromScale(0, 0), NAVY, 1)
		local function at(spec: { number }): (UDim2, UDim2)
			return UDim2.fromOffset(spec[3], spec[3]), UDim2.new(spec[1], -spec[3] / 2, spec[2], -spec[3] / 2)
		end
		local size, pos = at(tune.touchFire)
		-- (a Frame, not a button, and not Active: the touch goes on to the camera as a drag)
		local fire = frame("FireRight", layer, size, pos, { 200, 70, 50 }, 0.35)
		fire.Active = false
		round(fire, tune.touchFire[3] // 2)
		label("Text", fire, UDim2.fromScale(1, 0.4), UDim2.fromScale(0, 0.3), WHITE, true).Text = "FIRE"
		touch.FireRight = fire
		for _, item in
			{
				{ "FireLeft", "FIRE", tune.touchFireLeft },
				{ "Reload", "RELOAD", tune.touchReload },
				{ "Crouch", "CROUCH", tune.touchCrouch },
				{ "Scores", "SCORES", tune.touchScores },
			} :: { { any } }
		do
			local b = Instance.new("TextButton")
			b.Name = item[1]
			b.Text = item[2]
			b.Size, b.Position = at(item[3])
			b.BackgroundColor3 = if item[1] == "FireLeft" then rgb({ 200, 70, 50 }) else rgb({ 40, 50, 100 })
			b.BackgroundTransparency = 0.35
			b.TextColor3 = rgb(WHITE)
			b.Font = Enum.Font.GothamBold
			b.TextScaled = true
			b.Parent = layer
			round(b, item[3][3] // 2)
			touch[item[1]] = b
		end
	end

	local hud = { gui = gui, touch = touch } :: Hud
	local lastPhase = ""
	local liveSince: number? = nil
	local opened: number? = nil
	local boardAcc = 1
	local lay: Layout = Hud.layout(tune.hudBigWide, tune.hudBigTall, touchOn, tune, nil)
	local seenW, seenH, seenRows = 0, 0, 0

	-- The screen this HUD is on: its own ScreenGui's size (what is left under Roblox's top bar), which
	-- is the space every position here is in; the camera's viewport where that is not known yet.
	local function screen(): (number, number)
		local size = gui.AbsoluteSize
		if typeof(size) == "Vector2" and size.X > 0 and size.Y > 0 then
			return size.X, size.Y
		end
		local vp = camera.ViewportSize
		return vp.X, vp.Y
	end

	function hud.fireRect(_self: Hud): (number, number, number, number)
		local fire = touch.FireRight
		if fire and typeof(fire.AbsoluteSize) == "Vector2" and fire.AbsoluteSize.X > 0 then
			local p, s = fire.AbsolutePosition, fire.AbsoluteSize
			return p.X, p.Y, p.X + s.X, p.Y + s.Y
		end
		local r = lay.rects.FireRight
		if r == nil then
			return 0, 0, 0, 0
		end
		return r.x, r.y, r.x + r.w, r.y + r.h
	end

	-- One of the framework's cards, fitted to this screen with a UIScale of this HUD's own hung on it
	-- (and standing on `anchor`, so that it shrinks about its middle and stays where it was).
	-- (the framework's cards are everybody's: what was hung on one comes off again, and the card goes
	-- back to `home`, where the framework put it)
	local function unfit(card: any, home: UDim2)
		local had = if card then card:FindFirstChild(FIT) else nil
		if had then
			had:Destroy()
			card.AnchorPoint = Vector2.new(0, 0)
			card.Position = home
		end
	end

	local function fit(card: any, scale: number, anchor: Vector2, pos: UDim2, home: UDim2)
		if scale < 0.999 then
			local sc = card:FindFirstChild(FIT) or scaleOn(card)
			sc.Scale = scale
			card.AnchorPoint = anchor
			card.Position = pos
		else
			unfit(card, home)
		end
	end

	-- where the framework stands its end card (MinigameUI.summary), whatever its height is now
	local function summaryHome(card: any): UDim2
		return UDim2.new(0.5, -card.Size.X.Offset / 2, 0.5, -card.Size.Y.Offset / 2 - CARD_LIFT)
	end
	local HELP_HOME = UDim2.new(0, HELP_X, 0.5, -HELP_H / 2)

	-- The pieces put where this screen wants them (as the HUD opens, and whenever the screen changes: a
	-- phone turned round, a window dragged).
	local function arrange(vw: number, vh: number, cardRows: number)
		seenW, seenH, seenRows = vw, vh, cardRows
		lay = Hud.layout(vw, vh, touchOn, tune, if cardRows > 0 then cardRows else nil)
		local s = lay.scale
		root.Size = UDim2.fromScale(1 / s, 1 / s)
		rootScale.Scale = s
		crossScale.Scale = lay.aim
		hitScale.Scale = lay.aim
		phaseLine.Size = UDim2.fromOffset(lay.phaseW, PHASE_H)
		phaseLine.Position = UDim2.new(0.5, -lay.phaseW / 2, 0, lay.phaseY)
		feed.Size = UDim2.fromOffset(lay.feedW, tune.feedLines * FEED_ROW - 3)
		feed.Position = UDim2.new(1, -lay.feedW - 12, 0, lay.feedY)
		status.Size = UDim2.fromOffset(lay.statusW, STATUS_H)
		status.Position = UDim2.new(0.5, -lay.statusW / 2, 0.5, lay.statusY)
		second.Size = UDim2.fromOffset(lay.statusW, STATUS_BAND - STATUS_H + 2)
		second.Position = UDim2.new(0.5, -lay.statusW / 2, 0.5, lay.statusY + STATUS_H - 2)
		-- (a thumb's button is where the layout says: on the screen even where the screen is an odd one)
		for name, b in touch do
			local r = lay.rects[name]
			if r then
				b.Size = UDim2.fromOffset(r.w, r.h)
				b.Position = UDim2.fromOffset(r.x, r.y)
			end
		end
		-- (the bar is on the unscaled wash, so it is told the scale itself)
		shieldBar.Size = UDim2.fromOffset(SHIELD_W * s, SHIELD_H * s)
		shieldBar.Position = UDim2.new(0.5, -SHIELD_W * s / 2, 0.5, (lay.statusY + STATUS_H + 4) * s)
		boardScale.Scale = lay.board
		awardsScale.Scale = math.max(lay.awards, 0.01)
		awards.Position = UDim2.fromOffset(lay.awardsX, lay.awardsY)
		local ui = ctx.ui
		local help = if ui then ui.helpFrame else nil
		if help then
			fit(help, lay.help, Vector2.new(0, 0.5), UDim2.new(0, HELP_X, 0.5, 0), HELP_HOME)
		end
	end

	local function drawBoard()
		for team = 1, 2 do
			local list = {}
			for _, slot in seat.slots do
				if slot.on and slot.team == team then
					table.insert(list, slot)
				end
			end
			table.sort(list, function(a, b)
				if a.tags ~= b.tags then
					return a.tags > b.tags
				end
				return a.id < b.id
			end)
			local t = Contract.TEAMS[team]
			set(heads[team], `{if t then string.upper(t.name) else ""}   {seat.scores[team] or 0}`)
			for i = 1, ROWS do
				local row = rows[team][i]
				local slot = list[i]
				show(row.back, slot ~= nil)
				if slot then
					local you = slot.id == seat.you
					set(row.name, (seat.names[slot.id] or `Player {slot.id}`) .. (if you then " (you)" else ""))
					set(row.tags, tostring(slot.tags))
					set(row.outs, tostring(slot.outs))
					row.back.BackgroundColor3 = if you then rgb({ 28, 96, 104 }) else rgb({ 26, 32, 66 })
				end
			end
		end
		set(
			boardHint,
			if touchOn
				then "Leave the match and Change sides: the buttons at the lower left"
				else "Leave the match / Change sides: the buttons at the lower left   (gamepad: Y / D-pad up)"
		)
	end

	-- The framework's end card says "Play again" and "Leave (Q)": in a match that starts itself and keeps Q for
	-- nothing, the first is not there to press and the second is plain "Leave" (Y on a gamepad).
	local function dressSummary()
		local ui = ctx.ui
		local card = if ui then ui.summaryFrame else nil
		if card == nil or card.Visible ~= true then
			return
		end
		for _, c in card:GetChildren() do
			if c:IsA("TextButton") then
				if c.Text == "Play again" then
					c.Visible = false
				elseif c.Text == "Leave (Q)" then
					c.Text = if UIS.GamepadEnabled == true and not touchOn
						then "Leave the match  (Y)"
						else "Leave the match"
					c.Position = UDim2.new(0.5, -75, 0, c.Position.Y.Offset)
				end
			end
		end
		-- sixteen lines are taller than a phone: the card is fitted to the screen it is on
		fit(card, lay.card, Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5), summaryHome(card))
	end

	function hud.step(_self: Hud, dt: number)
		local now = seat.now
		local phase = seat.phase
		local ended = phase == "ended"
		local starting = phase == "briefing" and now < seat.endsAt
		local ui = ctx.ui
		local result = seat.result
		local card = if ended and type(result) == "table" then result.card else nil
		local cardRows = if type(card) == "table" and type(card.rows) == "table" then #card.rows else 0
		local vw, vh = screen()
		if vw ~= seenW or vh ~= seenH or (cardRows > 0 and cardRows ~= seenRows) then
			arrange(vw, vh, if cardRows > 0 then cardRows else seenRows)
		end
		-- the framework's own pieces: its empty scorecard is put away; its help card is the controls card
		if ui and ui.card and ui.card.Visible ~= false then
			ui.card.Visible = false
		end
		-- (somebody who joins a match already running reads the card through their first moments. Not
		-- with thumbs only: on a phone the card is a third of the view, lies over the left thumb's FIRE
		-- and is mostly about keys; there the buttons say what they do and the briefing has two lines of
		-- its own, below)
		local openedAt: number = opened or now
		opened = openedAt
		local stage = if starting
			then "briefing"
			elseif ended then "ended"
			elseif now - openedAt < tune.cardSecs then "fresh"
			else "live"
		if stage ~= lastPhase then
			if ui and ui.helpFrame then
				ui.helpFrame.Visible = (stage == "briefing" or stage == "fresh") and not thumbs
			end
			if lastPhase == "briefing" and (stage == "live" or stage == "fresh") then
				liveSince = now
			end
			lastPhase = stage
		end

		-- the crosshair
		local aiming = not seat.out and not ended and not seat.board and phase ~= ""
		show(cross, aiming)
		if aiming then
			local ready = seat:ready(now)
			local gap = if ready then tune.crossGap else tune.crossWide
			local arm = tune.crossArm
			local a = if ready then 0 else 0.5
			arms[1].Position, arms[1].Size = UDim2.fromOffset(gap + 1, 0), UDim2.fromOffset(arm, 2)
			arms[2].Position, arms[2].Size = UDim2.fromOffset(-gap - arm + 1, 0), UDim2.fromOffset(arm, 2)
			arms[3].Position, arms[3].Size = UDim2.fromOffset(0, gap + 1), UDim2.fromOffset(2, arm)
			arms[4].Position, arms[4].Size = UDim2.fromOffset(0, -gap - arm + 1), UDim2.fromOffset(2, arm)
			for _, piece in arms do
				piece.BackgroundTransparency = a
			end
		end
		show(hit, now - seat.hitAt < tune.hitMarkerSecs)

		-- the top
		set(score1, tostring(seat.scores[1] or 0))
		set(score2, tostring(seat.scores[2] or 0))
		mine.Position = UDim2.fromOffset(if seat.team == 2 then 190 else 16, 33)
		show(mine, seat.team ~= 0)
		local left = seat.endsAt - now
		if phase == "briefing" and not starting then
			left += R.matchSecs -- live by the clock; the server's own word is on its way
		end
		set(clock, if ended then "FULL TIME" elseif phase == "" then "" else clockText(left))
		clock.TextColor3 = if not starting and not ended and left <= tune.clockRed then rgb(WARN) else rgb(WHITE)
		local side = Contract.TEAMS[seat.team]
		local briefing = ""
		if starting then
			local name = if side then string.upper(side.name) else "?"
			briefing = if lay.phaseW >= PHASE_NARROW
				then `BRIEFING   You are {name}   The match starts in {math.ceil(left)} s`
				else `You are {name}   {math.ceil(left)} s`
		end
		set(phaseLine, briefing)
		local since = liveSince
		if starting and left <= tune.briefCount then
			set(count, tostring(math.max(1, math.ceil(left))))
			show(count, true)
		elseif since ~= nil and now - since < tune.goSecs then
			set(count, "GO!")
			show(count, true)
		else
			show(count, false)
		end

		-- the pips
		local rounds = seat.mag.rounds
		local team = teamRgb(seat.team)
		for i = 1, R.magazine do
			pip[i].BackgroundColor3 = if i <= rounds then rgb(team) else rgb(SLATE)
		end
		local r = seat:reloading(now)
		show(reloadBar, r ~= nil)
		show(reloadText, r ~= nil)
		if r ~= nil then
			reloadFill.Size = UDim2.fromScale(r, 1)
			set(reloadText, "RELOADING")
			-- a press on an empty marker: the word and the bar flash, with the dry click
			local dry = now - seat.dryAt < tune.dryFlashSecs
			reloadText.TextColor3 = if dry then rgb(WARN) else rgb(GOLD)
			reloadBar.BackgroundColor3 = if dry then rgb(WARN) else rgb(SLATE)
		end
		show(pips, not ended and phase ~= "")

		-- the status line
		-- (where the thumbs' buttons leave it narrow, it says the same in fewer words, at a size that reads)
		local words, under = "", ""
		local short = lay.statusW < STATUS_NARROW
		local safe = if starting then nil else seat:protected(now)
		local idle = seat:idle(now)
		if ended or phase == "" then
			words = "" -- (the end card has the screen; somebody tagged in the last seconds is not counted back)
		elseif seat.out then
			local by = seat.names[seat.outBy] or "someone"
			local n = math.max(1, math.ceil(seat.outUntil - now))
			-- (who it was is in the feed as well, in gold)
			words = if short then `TAGGED OUT   back in {n}` else `TAGGED OUT by {by}   back in {n}`
		elseif starting and thumbs then
			-- the briefing with thumbs only: the two lines a phone's player needs, in place of the card
			words = if short
				then "One hit and you are out"
				else "One hit tags you out. Five shots, then the marker reloads by itself."
			under = if short
				then "Drag on FIRE to keep looking"
				else "Drag on FIRE to keep looking. Push the stick all the way to sprint."
		elseif safe ~= nil then
			words = if short
				then `PROTECTED  {string.format("%.1f", safe)} s`
				else `PROTECTED  {string.format("%.1f", safe)} s   you cannot be hit and cannot fire`
		elseif idle ~= nil then
			local n = math.max(1, math.ceil(idle))
			words = if short
				then `Still there? Move: out in {n} s`
				else `Still there? Move, or you are taken out of the match in {n} s`
		elseif seat.inRoom then
			words = if short then "SAFE in your spawn room" else "SAFE in your spawn room: no firing from here"
		elseif seat.note ~= "" then
			words = seat.note
		end
		if starting and not thumbs and not seat.out then
			under = if padOnly
				then "Hold View: scoreboard. With it, Y leaves and D-pad up changes sides"
				else "Hold G: scoreboard, Leave, Change sides"
		end
		set(status, words)
		set(second, under)

		-- protected: the border breathes in your colour and the bar drains
		show(shield, safe ~= nil)
		if safe ~= nil then
			local paint = rgb(team)
			local a = 0.45 + 0.25 * math.sin(now * tune.shieldPulse * 2 * math.pi)
			for _, piece in edges do
				piece.BackgroundColor3 = paint
				piece.BackgroundTransparency = a
			end
			shieldFill.BackgroundColor3 = paint
			shieldFill.Size = UDim2.fromScale(math.clamp(safe / math.max(seat.feel.protectSecs, 1e-3), 0, 1), 1)
		end

		-- where it came from: a tick on a ring, turned towards the one who tagged you
		local showTick = false
		if seat.out and not ended then
			local from = seat.tagFrom
			if from then
				local dx, dz = from.x - seat.x, from.z - seat.z
				if dx * dx + dz * dz > 1 then
					-- the bearing against the look: 0 ahead, positive to the left (a yaw)
					local bearing = math.atan2(-dx, -dz) - seat.yaw
					local sx, sy = -math.sin(bearing), -math.cos(bearing)
					tick.Position = UDim2.new(0.5, sx * tune.tagRing - 4, 0.5, sy * tune.tagRing - 17)
					tick.Rotation = -math.deg(bearing)
					tick.BackgroundColor3 = rgb(teamRgb(if seat.team == 1 then 2 else 1))
					showTick = true
				end
			end
		end
		show(tick, showTick)
		local wet = (now - seat.goggleAt) / tune.goggleSecs
		show(goggles, wet < 1)
		if wet < 1 then
			local paint = rgb(teamRgb(if seat.team == 1 then 2 else 1))
			for _, b in blobs do
				b.BackgroundColor3 = paint
				b.BackgroundTransparency = 0.15 + 0.85 * wet
			end
		end

		-- the feed
		for i = 1, tune.feedLines do
			local line = seat.feed[i]
			set(lines[i], if line then line.text else "")
			if line then
				lines[i].TextColor3 = if line.mine then rgb(GOLD) else rgb(teamRgb(line.team))
			end
		end

		-- the scoreboard, and the cursor for what is pressed with it
		local boardOn = seat.board and not ended
		show(board, boardOn)
		if boardOn then
			boardAcc += dt
			if boardAcc >= 0.25 then
				boardAcc = 0
				drawBoard()
			end
		else
			boardAcc = 1
		end
		show(modal, boardOn or ended)

		-- the end: the bulletin's awards, and the framework's card dressed
		local list = if type(card) == "table" and type(card.awards) == "table" then card.awards else nil
		show(awards, ended and list ~= nil and #list > 0 and lay.awards > 0)
		if ended then
			if list then
				for i, l in awardLines do
					local award = list[i]
					set(l, if award then `{award.title}: {seat.names[award.id] or "?"}` else "")
				end
			end
			dressSummary()
		end
	end

	function hud.stop(_self: Hud)
		local ui = ctx.ui
		local summary = if ui then ui.summaryFrame else nil
		if summary then
			unfit(summary, summaryHome(summary))
		end
		unfit(if ui then ui.helpFrame else nil, HELP_HOME)
		gui:Destroy()
	end

	return hud
end

return Hud
