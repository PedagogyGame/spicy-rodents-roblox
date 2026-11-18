--!strict
-- StarterPlayer.StarterPlayerScripts.Client.UI.MinigameUI
-- The on-screen side of every minigame (brief v2 §15 "every minigame ironed out carefully"; HANDOFF owner rule:
-- always say what you are looking at and what to press). It names no game: it is the widgets every game shares,
-- and each game draws its own scorecard into the card frame from its own file (Client/Minigames/Games/<Game>,
-- through ClientGame.card) with the kit below. The widgets: a How-to-play card with the game's controls (H hides
-- it), a big banner (STRIKE / BUST / your turn), a status line (whose turn, lobby countdown, end card), the
-- scorecard frame, the power / timing meter with its sweet spot, buttons that work by mouse and touch (Leave,
-- Start now, Play again, a lobby's choices) and hold buttons for touch players, the turn clock (it turns red
-- with a plain warning before an idle turn is skipped), a notch indicator (bowling's hook: five pips), a paper
-- card (the fortune teller's), and the end card (ranked rows in the game's own columns, Play again / Leave, the
-- reset countdown). Pure layout: the game controllers (Client/Minigames/*) feed it.
-- Interface: new() -> UI; UI:open(game, title, help: { how: {string}, keys: {string} }); UI:close();
--   UI:banner(text, big?); UI:status(text); UI.card (the scorecard Frame); UI:clearCard();
--   UI:meter(value?, sweet?: {lo, hi}, label?); UI:buttons(list: { {id, text} }, onClick); UI:touch(list, onDown,
--   onUp) (an item whose id is "bowl" or whose third entry is "wide" is the wide main button); UI:paper(title,
--   text, seconds) (seconds <= 0 takes the card away; so do open and close); UI:isOpen(); UI:clock(seconds?,
--   warning?); UI:hook(notch?, notches?);
--   UI:summary(summary?, you?, secondsLeft?, onAgain?, onLeave?): summary = { line, rows = { { seat, name, place,
--   gone, ... } }, title?, cols? = { { title, key, x, w, strong? } } (fractions of the card; key "place" and
--   "name" are drawn as rank and name), foot? (a format with one %d: the seconds left) };
--   kit = { C (palette: NAVY, GOLD, CYAN, WHITE), label(parent, text, size, pos, color?, font?) -> TextLabel,
--   corner(parent, radius), button(parent, text, width) -> TextButton }

local CameraRig = require("../Camera/CameraRig")

local MinigameUI = {}
MinigameUI.__index = MinigameUI

-- colours are built on first use (requiring this module must not touch the engine: Lune loads it)
local RGB: { [string]: { number } } =
	{ NAVY = { 16, 20, 44 }, GOLD = { 255, 214, 92 }, CYAN = { 140, 236, 236 }, WHITE = { 245, 245, 245 } }
local C: { [string]: Color3 } = setmetatable({}, {
	__index = function(t: any, k: string): Color3
		local v = RGB[k]
		local c = Color3.fromRGB(v[1], v[2], v[3])
		rawset(t, k, c)
		return c
	end,
}) :: any

local function corner(parent: Instance, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = parent
end

local function label(
	parent: Instance,
	text: string,
	size: UDim2,
	pos: UDim2,
	color: Color3?,
	font: Enum.Font?
): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = size
	t.Position = pos
	t.Text = text
	t.TextColor3 = color or C.WHITE
	t.Font = font or Enum.Font.GothamMedium
	t.TextScaled = true
	t.TextWrapped = true
	t.Parent = parent
	return t
end

function MinigameUI.new(): any
	local self = setmetatable({}, MinigameUI) :: any
	local player = game:GetService("Players").LocalPlayer
	local gui = Instance.new("ScreenGui")
	gui.Name = "MinigameUI"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.DisplayOrder = 20
	gui.Enabled = false
	gui.Parent = player:WaitForChild("PlayerGui")
	self.gui = gui

	-- how to play (left)
	local help = Instance.new("Frame")
	help.Name = "Help"
	help.BackgroundColor3 = C.NAVY
	help.BackgroundTransparency = 0.12
	help.Size = UDim2.fromOffset(340, 430)
	help.Position = UDim2.new(0, 12, 0.5, -215)
	help.Parent = gui
	corner(help, 12)
	self.helpFrame = help
	self.title = label(help, "", UDim2.new(1, -20, 0, 34), UDim2.fromOffset(10, 8), C.GOLD, Enum.Font.FredokaOne)
	local list = Instance.new("TextLabel")
	list.BackgroundTransparency = 1
	list.Size = UDim2.new(1, -20, 1, -54)
	list.Position = UDim2.fromOffset(10, 46)
	list.TextXAlignment = Enum.TextXAlignment.Left
	list.TextYAlignment = Enum.TextYAlignment.Top
	list.TextWrapped = true
	list.RichText = true
	list.TextSize = 15
	list.Font = Enum.Font.Gotham
	list.TextColor3 = C.WHITE
	list.Text = ""
	list.Parent = help
	self.helpText = list

	-- banner (top centre) and status
	local banner = label(gui, "", UDim2.new(0.6, 0, 0, 64), UDim2.new(0.2, 0, 0, 70), C.GOLD, Enum.Font.FredokaOne)
	banner.TextStrokeTransparency = 0.3
	banner.TextStrokeColor3 = Color3.new(0, 0, 0)
	banner.TextTransparency = 1
	banner.TextStrokeTransparency = 1
	self.bannerLabel = banner
	self.bannerUntil = 0
	local status = Instance.new("TextLabel")
	status.BackgroundColor3 = C.NAVY
	status.BackgroundTransparency = 0.2
	status.Size = UDim2.fromOffset(700, 44)
	status.Position = UDim2.new(0.5, -350, 0, 134)
	status.Font = Enum.Font.GothamBold
	status.TextColor3 = C.CYAN
	status.TextScaled = true
	status.TextWrapped = true -- a long line (the bowler's keys) takes two rows rather than shrinking away
	status.Text = ""
	status.Parent = gui
	corner(status, 10)
	self.statusLabel = status
	-- the turn clock (right of the status line) and its warning (under it)
	local clock = Instance.new("TextLabel")
	clock.Name = "Clock"
	clock.BackgroundColor3 = C.NAVY
	clock.BackgroundTransparency = 0.2
	clock.Size = UDim2.fromOffset(74, 44)
	clock.Position = UDim2.new(0.5, 358, 0, 134)
	clock.Font = Enum.Font.GothamBold
	clock.TextColor3 = C.WHITE
	clock.TextScaled = true
	clock.Text = ""
	clock.Visible = false
	clock.Parent = gui
	corner(clock, 10)
	self.clockLabel = clock
	self.clockShown = ""
	local warnLabel = Instance.new("TextLabel")
	warnLabel.Name = "ClockWarning"
	warnLabel.BackgroundColor3 = Color3.fromRGB(120, 24, 24)
	warnLabel.BackgroundTransparency = 0.15
	warnLabel.Size = UDim2.fromOffset(700, 28)
	warnLabel.Position = UDim2.new(0.5, -350, 0, 182)
	warnLabel.Font = Enum.Font.GothamBold
	warnLabel.TextColor3 = C.WHITE
	warnLabel.TextScaled = true
	warnLabel.Text = ""
	warnLabel.Visible = false
	warnLabel.Parent = gui
	corner(warnLabel, 8)
	self.clockWarning = warnLabel

	-- scorecard (bottom right)
	local card = Instance.new("Frame")
	card.Name = "Scorecard"
	card.BackgroundColor3 = C.NAVY
	card.BackgroundTransparency = 0.1
	card.Size = UDim2.fromOffset(560, 170)
	card.Position = UDim2.new(1, -572, 1, -182)
	card.Parent = gui
	corner(card, 10)
	self.card = card

	-- meter (bottom centre)
	local meter = Instance.new("Frame")
	meter.Name = "Meter"
	meter.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
	meter.Size = UDim2.fromOffset(380, 26)
	meter.Position = UDim2.new(0.5, -190, 1, -260)
	meter.Visible = false
	meter.Parent = gui
	corner(meter, 8)
	local sweet = Instance.new("Frame")
	sweet.BackgroundColor3 = Color3.fromRGB(70, 200, 110)
	sweet.BackgroundTransparency = 0.25
	sweet.BorderSizePixel = 0
	sweet.Visible = false
	sweet.Parent = meter
	local fill = Instance.new("Frame")
	fill.BackgroundColor3 = C.GOLD
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(0, 1)
	fill.Parent = meter
	corner(fill, 8)
	local needle = Instance.new("Frame")
	needle.BackgroundColor3 = C.WHITE
	needle.BorderSizePixel = 0
	needle.Size = UDim2.new(0, 4, 1, 8)
	needle.Position = UDim2.fromOffset(-2, -4)
	needle.Parent = meter
	local meterLabel = label(meter, "", UDim2.new(1, 0, 0, 22), UDim2.fromOffset(0, -26), C.WHITE, Enum.Font.GothamBold)
	self.meterFrame, self.meterFill, self.meterSweet, self.meterNeedle, self.meterLabel =
		meter, fill, sweet, needle, meterLabel

	-- hook indicator (under the meter): pips from full hook left to full hook right
	local hook = Instance.new("Frame")
	hook.Name = "Hook"
	hook.BackgroundColor3 = C.NAVY
	hook.BackgroundTransparency = 0.2
	hook.Size = UDim2.fromOffset(300, 26)
	hook.Position = UDim2.new(0.5, -150, 1, -226)
	hook.Visible = false
	hook.Parent = gui
	corner(hook, 8)
	self.hookFrame = hook
	self.hookLabel = label(hook, "HOOK", UDim2.new(0, 150, 1, -6), UDim2.fromOffset(6, 3), C.CYAN, Enum.Font.GothamBold)
	self.hookLabel.TextXAlignment = Enum.TextXAlignment.Left
	self.hookPips = {} :: { Frame }
	self.hookShown = nil :: number?

	-- the end card (centre): built by summary()
	local over = Instance.new("Frame")
	over.Name = "Summary"
	over.BackgroundColor3 = C.NAVY
	over.BackgroundTransparency = 0.05
	over.Size = UDim2.fromOffset(520, 240)
	over.Position = UDim2.new(0.5, -260, 0.5, -150)
	over.Visible = false
	over.Parent = gui
	corner(over, 14)
	local overStroke = Instance.new("UIStroke")
	overStroke.Color = C.GOLD
	overStroke.Thickness = 2
	overStroke.Parent = over
	self.summaryFrame = over
	self.summarySig = ""
	self.summaryFoot = nil :: TextLabel?

	-- buttons (bottom left)
	local buttons = Instance.new("Frame")
	buttons.BackgroundTransparency = 1
	buttons.Size = UDim2.fromOffset(420, 46)
	buttons.Position = UDim2.new(0, 12, 1, -58)
	buttons.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 8)
	layout.Parent = buttons
	self.buttonBar = buttons
	-- touch controls (above the buttons)
	local touch = Instance.new("Frame")
	touch.BackgroundTransparency = 1
	touch.Size = UDim2.fromOffset(720, 64)
	touch.Position = UDim2.new(0, 12, 1, -132)
	touch.Parent = gui
	local tl = Instance.new("UIListLayout")
	tl.FillDirection = Enum.FillDirection.Horizontal
	tl.Padding = UDim.new(0, 8)
	tl.Parent = touch
	self.touchBar = touch

	-- the fortune card
	local fcard = Instance.new("Frame")
	fcard.Name = "Paper"
	fcard.BackgroundColor3 = Color3.fromRGB(246, 236, 210)
	fcard.Size = UDim2.fromOffset(460, 200)
	fcard.Position = UDim2.new(0.5, -230, 0.5, -60)
	fcard.Visible = false
	fcard.Parent = gui
	corner(fcard, 14)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(150, 110, 60)
	stroke.Thickness = 3
	stroke.Parent = fcard
	self.fortuneTitle = label(
		fcard,
		"",
		UDim2.new(1, -24, 0, 36),
		UDim2.fromOffset(12, 10),
		Color3.fromRGB(110, 40, 120),
		Enum.Font.Fantasy
	)
	self.fortuneText = label(
		fcard,
		"",
		UDim2.new(1, -40, 1, -64),
		UDim2.fromOffset(20, 50),
		Color3.fromRGB(60, 30, 60),
		Enum.Font.Fantasy
	)
	self.fortuneCard = fcard
	self.fortuneUntil = 0

	game:GetService("RunService").RenderStepped:Connect(function()
		local now = os.clock()
		if self.bannerUntil > 0 then
			local left = self.bannerUntil - now
			local a = if left > 0.4 then 0 else math.clamp(1 - left / 0.4, 0, 1)
			banner.TextTransparency = a
			banner.TextStrokeTransparency = 0.3 + 0.7 * a
			if left <= 0 then
				self.bannerUntil = 0
			end
		end
		if self.fortuneUntil > 0 and now > self.fortuneUntil then
			self.fortuneUntil = 0
			fcard.Visible = false
		end
	end)
	return self
end

function MinigameUI.isOpen(self: any): boolean
	return self.gui.Enabled
end

-- Empty the scorecard frame (a game's card function then draws into UI.card).
function MinigameUI.clearCard(self: any)
	for _, c in self.card:GetChildren() do
		if not c:IsA("UICorner") then
			c:Destroy()
		end
	end
end

function MinigameUI.open(self: any, _game: string, title: string, help: { how: { string }, keys: { string } })
	self.gui.Enabled = true
	self.helpFrame.Visible = true
	self.title.Text = title
	local lines = {}
	for _, l in help.how do
		table.insert(lines, l)
	end
	table.insert(lines, "")
	table.insert(lines, "<b>CONTROLS</b>")
	for _, k in help.keys do
		table.insert(lines, k)
	end
	table.insert(lines, "")
	table.insert(lines, "<i>H hides this card</i>")
	self.helpText.Text = table.concat(lines, "\n")
	self:status("")
	self:meter(nil)
	-- (the last game's paper card does not follow the player to the next one)
	self:paper("", "", 0)
	for _, c in self.card:GetChildren() do
		c:Destroy()
	end
	corner(self.card, 10)
	self.card.Visible = true
end

function MinigameUI.close(self: any)
	self.gui.Enabled = false
	self:paper("", "", 0)
	self:meter(nil)
	self:clock(nil)
	self:hook(nil)
	self:summary(nil)
	self:buttons({}, function() end)
	self:touch({}, function() end, function() end)
end

function MinigameUI.toggleHelp(self: any)
	self.helpFrame.Visible = not self.helpFrame.Visible
end

function MinigameUI.banner(self: any, text: string, big: boolean?)
	local b = self.bannerLabel
	b.Text = text
	b.TextColor3 = if big then C.GOLD else C.WHITE
	b.Size = if big then UDim2.new(0.6, 0, 0, 64) else UDim2.new(0.6, 0, 0, 40)
	b.TextTransparency = 0
	b.TextStrokeTransparency = 0.3
	self.bannerUntil = os.clock() + (if big then 2.4 else 1.8)
end

function MinigameUI.status(self: any, text: string)
	self.statusLabel.Text = text
	self.statusLabel.Visible = text ~= ""
end

-- value nil hides it. sweet = { lo, hi } draws the green band.
function MinigameUI.meter(self: any, value: number?, sweet: { number }?, text: string?)
	local m = self.meterFrame
	if value == nil then
		m.Visible = false
		return
	end
	m.Visible = true
	local v = math.clamp(value, 0, 1)
	self.meterFill.Size = UDim2.fromScale(v, 1)
	self.meterNeedle.Position = UDim2.new(v, -2, 0, -4)
	if sweet then
		self.meterSweet.Visible = true
		self.meterSweet.Position = UDim2.fromScale(sweet[1], 0)
		self.meterSweet.Size = UDim2.fromScale(sweet[2] - sweet[1], 1)
	else
		self.meterSweet.Visible = false
	end
	self.meterLabel.Text = text or ""
end

local function makeButton(parent: Instance, text: string, width: number): TextButton
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(0, width, 1, 0)
	b.BackgroundColor3 = Color3.fromRGB(36, 150, 150)
	b.TextColor3 = C.WHITE
	b.Font = Enum.Font.GothamBold
	b.TextScaled = true
	b.Text = text
	b.AutoButtonColor = true
	b.Parent = parent
	corner(b, 10)
	return b
end

-- What a game draws its own card with (Client/Minigames/ClientGame.card): the same palette, labels and corners.
MinigameUI.kit = { C = C, label = label, corner = corner, button = makeButton }

-- buttons({ {id, text} }, onClick(id))
function MinigameUI.buttons(self: any, list: { { string } }, onClick: (id: string) -> ())
	-- buttons need a cursor: the orbit camera gives the mouse back while any are up
	CameraRig.wantCursor("minigame", #list > 0)
	for _, c in self.buttonBar:GetChildren() do
		if c:IsA("TextButton") then
			c:Destroy()
		end
	end
	for _, item in list do
		local b = makeButton(self.buttonBar, item[2], math.max(110, #item[2] * 11))
		if item[1] == "leave" then
			b.BackgroundColor3 = Color3.fromRGB(170, 60, 50)
		end
		b.Activated:Connect(function()
			onClick(item[1])
		end)
	end
end

-- touch({ {id, text} }, onDown(id), onUp(id)): hold buttons for touch players (bowling move / aim / bowl).
function MinigameUI.touch(self: any, list: { { string } }, onDown: (id: string) -> (), onUp: (id: string) -> ())
	for _, c in self.touchBar:GetChildren() do
		if c:IsA("TextButton") then
			c:Destroy()
		end
	end
	local UIS = game:GetService("UserInputService")
	self.touchBar.Visible = UIS.TouchEnabled
	for _, item in list do
		local wide = item[1] == "bowl" or item[3] == "wide"
		local b = makeButton(self.touchBar, item[2], if wide then 150 elseif #item[2] > 3 then 86 else 60)
		b.BackgroundColor3 = Color3.fromRGB(40, 50, 100)
		b.MouseButton1Down:Connect(function()
			onDown(item[1])
		end)
		b.MouseButton1Up:Connect(function()
			onUp(item[1])
		end)
		b.MouseLeave:Connect(function()
			onUp(item[1])
		end)
	end
end

-- The turn clock. seconds nil hides it; under ten seconds it turns red. warning (a sentence) shows under the
-- status line while there is one.
function MinigameUI.clock(self: any, seconds: number?, warning: string?)
	local c = self.clockLabel
	local shown = ""
	if seconds ~= nil then
		local n = math.max(0, math.ceil(seconds))
		shown = `{n // 60}:{string.format("%02d", n % 60)}`
	end
	local key = shown .. "|" .. (warning or "")
	if key == self.clockShown then
		return
	end
	self.clockShown = key
	c.Visible = shown ~= ""
	c.Text = shown
	c.TextColor3 = if seconds ~= nil and seconds <= 10 then Color3.fromRGB(255, 90, 80) else C.WHITE
	self.clockWarning.Visible = warning ~= nil and warning ~= ""
	self.clockWarning.Text = warning or ""
end

-- The hook indicator: notch -notches .. notches (negative = hook left); nil hides it.
function MinigameUI.hook(self: any, notch: number?, notches: number?)
	local frame = self.hookFrame
	if notch == nil then
		if frame.Visible then
			frame.Visible = false
			self.hookShown = nil
		end
		return
	end
	if self.hookShown == notch and frame.Visible then
		return
	end
	self.hookShown = notch
	frame.Visible = true
	local n = notches or 2
	local pips = self.hookPips
	if #pips ~= 2 * n + 1 then
		for _, p in pips do
			p:Destroy()
		end
		table.clear(pips)
		for i = 1, 2 * n + 1 do
			local p = Instance.new("Frame")
			p.BorderSizePixel = 0
			p.Size = UDim2.fromOffset(22, 14)
			p.Position = UDim2.new(1, -(2 * n + 2 - i) * 26 - 4, 0.5, -7)
			p.Parent = frame
			corner(p, 4)
			pips[i] = p
		end
	end
	for i, p in pips do
		local at = i - n - 1
		local lit = at == notch
		p.BackgroundColor3 = if lit
			then (if at == 0 then C.CYAN else Color3.fromRGB(255, 170, 60))
			else Color3.fromRGB(50, 56, 90)
	end
	self.hookLabel.Text = if notch == 0
		then "HOOK: straight"
		else `HOOK: {if math.abs(notch) >= n then "full" else "half"} {if notch < 0 then "left" else "right"}`
end

-- The end card: ranked rows in the game's own columns, who won, and what to press. nil hides it.
type Column = { title: string, key: string, x: number, w: number, strong: boolean? }
local DEFAULT_COLS: { Column } = {
	{ title = "", key = "place", x = 0.02, w = 0.07 },
	{ title = "PLAYER", key = "name", x = 0.1, w = 0.5 },
	{ title = "SCORE", key = "total", x = 0.62, w = 0.3, strong = true },
}
local DEFAULT_FOOT = "The table resets in %d s. Anyone can walk up and start a new game."

function MinigameUI.summary(
	self: any,
	sum: { [string]: any }?,
	you: number?,
	secondsLeft: number?,
	onAgain: (() -> ())?,
	onLeave: (() -> ())?
)
	local frame = self.summaryFrame
	if sum == nil then
		if frame.Visible then
			frame.Visible = false
			self.summarySig = ""
		end
		return
	end
	self.summaryAgain, self.summaryLeave = onAgain, onLeave
	local cols: { Column } = sum.cols or DEFAULT_COLS
	local parts = { tostring(you), tostring(sum.line) }
	for _, r in sum.rows do
		local cells = { tostring(r.seat), tostring(r.gone) }
		for _, c in cols do
			table.insert(cells, tostring(r[c.key]))
		end
		table.insert(parts, table.concat(cells, ":"))
	end
	local sig = table.concat(parts, "|")
	if sig ~= self.summarySig then
		self.summarySig = sig
		for _, c in frame:GetChildren() do
			if c:IsA("GuiObject") then
				c:Destroy()
			end
		end
		local rows = sum.rows
		local h = 150 + #rows * 32
		frame.Size = UDim2.fromOffset(520, h)
		frame.Position = UDim2.new(0.5, -260, 0.5, -h / 2 - 20)
		label(
			frame,
			tostring(sum.title or "GAME OVER"),
			UDim2.new(1, -20, 0, 30),
			UDim2.fromOffset(10, 8),
			C.GOLD,
			Enum.Font.FredokaOne
		)
		label(
			frame,
			tostring(sum.line),
			UDim2.new(1, -20, 0, 26),
			UDim2.fromOffset(10, 40),
			C.WHITE,
			Enum.Font.GothamBold
		)
		-- the card's columns: heading, where it starts and how wide it is (fractions of the card)
		for _, c in cols do
			label(frame, c.title, UDim2.new(c.w, 0, 0, 16), UDim2.new(c.x, 0, 0, 72), C.CYAN, Enum.Font.GothamBold)
		end
		for i, r in rows do
			local y = 92 + (i - 1) * 32
			local mine = r.seat == you
			local row = Instance.new("Frame")
			row.BackgroundColor3 = if mine then Color3.fromRGB(28, 96, 104) else Color3.fromRGB(26, 32, 66)
			row.Size = UDim2.new(1, -16, 0, 28)
			row.Position = UDim2.fromOffset(8, y)
			row.Parent = frame
			corner(row, 6)
			local name = tostring(r.name) .. (if mine then " (you)" else "") .. (if r.gone then " (left)" else "")
			for _, c in cols do
				local cell = if c.key == "place"
					then `{r.place}.`
					elseif c.key == "name" then name
					else tostring(r[c.key])
				label(
					row,
					cell,
					UDim2.fromScale(c.w, 0.8),
					UDim2.fromScale(c.x, 0.1),
					if c.strong then C.GOLD else C.WHITE,
					if c.strong then Enum.Font.FredokaOne else Enum.Font.GothamBold
				)
			end
		end
		local by = 98 + #rows * 32
		local again = makeButton(frame, "Play again", 150)
		again.Size = UDim2.fromOffset(150, 34)
		again.Position = UDim2.new(0.5, -160, 0, by)
		again.Activated:Connect(function()
			if self.summaryAgain then
				self.summaryAgain()
			end
		end)
		local leave = makeButton(frame, "Leave (Q)", 150)
		leave.Size = UDim2.fromOffset(150, 34)
		leave.Position = UDim2.new(0.5, 10, 0, by)
		leave.BackgroundColor3 = Color3.fromRGB(170, 60, 50)
		leave.Activated:Connect(function()
			if self.summaryLeave then
				self.summaryLeave()
			end
		end)
		self.summaryFoot =
			label(frame, "", UDim2.new(1, -20, 0, 16), UDim2.fromOffset(10, by + 38), C.CYAN, Enum.Font.Gotham)
	end
	frame.Visible = true
	local foot = self.summaryFoot :: TextLabel?
	if foot then
		foot.Text = string.format(tostring(sum.foot or DEFAULT_FOOT), math.max(0, math.ceil(secondsLeft or 0)))
	end
end

-- A printed paper card in the middle of the screen for a while (the fortune teller's). (It was a method named
-- `card`, which the scorecard frame of the same name hid: calling it failed. `paper` is its working name.)
-- seconds <= 0 takes the card away now. Opening or closing the UI takes it away too: a card never outlives the
-- game it was dealt in.
function MinigameUI.paper(self: any, title: string, text: string, seconds: number)
	if seconds <= 0 then
		self.fortuneCard.Visible = false
		self.fortuneUntil = 0
		return
	end
	self.fortuneTitle.Text = title
	self.fortuneText.Text = text
	self.fortuneCard.Visible = true
	self.fortuneUntil = os.clock() + seconds
end

return MinigameUI
