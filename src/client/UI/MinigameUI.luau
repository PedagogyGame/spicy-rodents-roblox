--!strict
-- StarterPlayer.StarterPlayerScripts.Client.UI.MinigameUI
-- The on-screen side of every minigame (brief v2 §15 "every minigame ironed out carefully"; HANDOFF owner rule:
-- always say what you are looking at and what to press): a How-to-play card with the game's controls (H hides
-- it), a big banner for STRIKE / BUST / your turn, a status line (whose turn, lobby countdown, end card), the
-- scorecard (bowling's ten-frame sheet, darts' 501 or cricket marks), the power / timing meter with its sweet
-- spot, and buttons that work by mouse and touch (Leave, Start now, Play again, 501 / Cricket, and the bowling
-- touch controls). Pure layout: the game controllers (Client/Minigames/*) feed it.
-- Interface: new() -> UI; UI:open(game, title, help: { how: {string}, keys: {string} }); UI:close();
--   UI:banner(text, big?); UI:status(text); UI:scoreBowling(view, you); UI:scoreDarts(view, you);
--   UI:meter(value?, sweet?: {lo, hi}, label?); UI:buttons(list: { {id, text} }, onClick); UI:touch(list, onDown,
--   onUp); UI:card(title, text, seconds); UI:isOpen()

local MinigameUI = {}
MinigameUI.__index = MinigameUI

local NAVY = Color3.fromRGB(16, 20, 44)
local GOLD = Color3.fromRGB(255, 214, 92)
local CYAN = Color3.fromRGB(140, 236, 236)
local WHITE = Color3.fromRGB(245, 245, 245)

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
	t.TextColor3 = color or WHITE
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
	help.BackgroundColor3 = NAVY
	help.BackgroundTransparency = 0.12
	help.Size = UDim2.fromOffset(300, 300)
	help.Position = UDim2.new(0, 12, 0.5, -150)
	help.Parent = gui
	corner(help, 12)
	self.helpFrame = help
	self.title = label(help, "", UDim2.new(1, -20, 0, 34), UDim2.fromOffset(10, 8), GOLD, Enum.Font.FredokaOne)
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
	list.TextColor3 = WHITE
	list.Text = ""
	list.Parent = help
	self.helpText = list

	-- banner (top centre) and status
	local banner = label(gui, "", UDim2.new(0.6, 0, 0, 64), UDim2.new(0.2, 0, 0, 70), GOLD, Enum.Font.FredokaOne)
	banner.TextStrokeTransparency = 0.3
	banner.TextStrokeColor3 = Color3.new(0, 0, 0)
	banner.TextTransparency = 1
	banner.TextStrokeTransparency = 1
	self.bannerLabel = banner
	self.bannerUntil = 0
	local status = Instance.new("TextLabel")
	status.BackgroundColor3 = NAVY
	status.BackgroundTransparency = 0.2
	status.Size = UDim2.fromOffset(520, 34)
	status.Position = UDim2.new(0.5, -260, 0, 138)
	status.Font = Enum.Font.GothamBold
	status.TextColor3 = CYAN
	status.TextScaled = true
	status.Text = ""
	status.Parent = gui
	corner(status, 10)
	self.statusLabel = status

	-- scorecard (bottom right)
	local card = Instance.new("Frame")
	card.Name = "Scorecard"
	card.BackgroundColor3 = NAVY
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
	fill.BackgroundColor3 = GOLD
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(0, 1)
	fill.Parent = meter
	corner(fill, 8)
	local needle = Instance.new("Frame")
	needle.BackgroundColor3 = WHITE
	needle.BorderSizePixel = 0
	needle.Size = UDim2.new(0, 4, 1, 8)
	needle.Position = UDim2.fromOffset(-2, -4)
	needle.Parent = meter
	local meterLabel = label(meter, "", UDim2.new(1, 0, 0, 22), UDim2.fromOffset(0, -26), WHITE, Enum.Font.GothamBold)
	self.meterFrame, self.meterFill, self.meterSweet, self.meterNeedle, self.meterLabel =
		meter, fill, sweet, needle, meterLabel

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
	touch.Size = UDim2.fromOffset(420, 64)
	touch.Position = UDim2.new(0, 12, 1, -132)
	touch.Parent = gui
	local tl = Instance.new("UIListLayout")
	tl.FillDirection = Enum.FillDirection.Horizontal
	tl.Padding = UDim.new(0, 8)
	tl.Parent = touch
	self.touchBar = touch

	-- the fortune card
	local fcard = Instance.new("Frame")
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
	for _, c in self.card:GetChildren() do
		c:Destroy()
	end
	corner(self.card, 10)
	self.card.Visible = true
end

function MinigameUI.close(self: any)
	self.gui.Enabled = false
	self:meter(nil)
	self:buttons({}, function() end)
	self:touch({}, function() end, function() end)
end

function MinigameUI.toggleHelp(self: any)
	self.helpFrame.Visible = not self.helpFrame.Visible
end

function MinigameUI.banner(self: any, text: string, big: boolean?)
	local b = self.bannerLabel
	b.Text = text
	b.TextColor3 = if big then GOLD else WHITE
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
	b.TextColor3 = WHITE
	b.Font = Enum.Font.GothamBold
	b.TextScaled = true
	b.Text = text
	b.AutoButtonColor = true
	b.Parent = parent
	corner(b, 10)
	return b
end

-- buttons({ {id, text} }, onClick(id))
function MinigameUI.buttons(self: any, list: { { string } }, onClick: (id: string) -> ())
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
		local b = makeButton(self.touchBar, item[2], if item[1] == "bowl" then 150 else 64)
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

function MinigameUI.card(self: any, title: string, text: string, seconds: number)
	self.fortuneTitle.Text = title
	self.fortuneText.Text = text
	self.fortuneCard.Visible = true
	self.fortuneUntil = os.clock() + seconds
end

-- Scorecards --------------------------------------------------------------------------------------------------
local function clearCard(self: any)
	for _, c in self.card:GetChildren() do
		if not c:IsA("UICorner") then
			c:Destroy()
		end
	end
end

function MinigameUI.scoreBowling(self: any, view: { [string]: any }, you: number?)
	clearCard(self)
	local g = view.game
	local seats = view.seats or {}
	local n = math.max(1, #seats)
	self.card.Size = UDim2.fromOffset(600, 26 + n * 38)
	self.card.Position = UDim2.new(1, -612, 1, -(38 + n * 38))
	local fw = 1 / 13.2
	for f = 1, 10 do
		label(
			self.card,
			tostring(f),
			UDim2.new(fw, -2, 0, 18),
			UDim2.new(0.16 + (f - 1) * fw, 0, 0, 4),
			CYAN,
			Enum.Font.GothamBold
		)
	end
	label(self.card, "TOTAL", UDim2.new(0.08, 0, 0, 18), UDim2.new(0.91, 0, 0, 4), CYAN, Enum.Font.GothamBold)
	for s, seat in seats do
		local y = 24 + (s - 1) * 38
		local gs = if g then g.seats[s] else nil
		local up = view.turn == s and view.phase == "playing"
		local row = Instance.new("Frame")
		row.BackgroundColor3 = if up then Color3.fromRGB(28, 96, 104) else Color3.fromRGB(26, 32, 66)
		row.Size = UDim2.new(1, -8, 0, 34)
		row.Position = UDim2.fromOffset(4, y)
		row.Parent = self.card
		corner(row, 6)
		local name = seat.name .. (if s == you then " (you)" else "") .. (if seat.gone then " (left)" else "")
		label(
			row,
			name,
			UDim2.fromScale(0.15, 0.8),
			UDim2.fromScale(0.005, 0.1),
			if up then GOLD else WHITE,
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
					if m == "X" or m == "/" then GOLD else WHITE,
					Enum.Font.Code
				)
			end
			label(
				cell,
				tostring(if gs then gs.totals[f] else ""),
				UDim2.fromScale(1, 0.5),
				UDim2.fromScale(0, 0.5),
				CYAN,
				Enum.Font.GothamBold
			)
		end
		label(
			row,
			if gs then tostring(gs.total) else "0",
			UDim2.fromScale(0.08, 0.8),
			UDim2.fromScale(0.91, 0.1),
			GOLD,
			Enum.Font.FredokaOne
		)
	end
end

local CRICKET = { "20", "19", "18", "17", "16", "15", "25" }
local function cricketMark(n: number): string
	return if n <= 0 then "" elseif n == 1 then "/" elseif n == 2 then "X" else "(X)"
end

function MinigameUI.scoreDarts(self: any, view: { [string]: any }, you: number?)
	clearCard(self)
	local g = view.game
	local seats = view.seats or {}
	local n = math.max(1, #seats)
	local mode = (g and g.mode) or view.mode or "501"
	if mode == "cricket" then
		self.card.Size = UDim2.fromOffset(120 + n * 110, 250)
		self.card.Position = UDim2.new(1, -(132 + n * 110), 1, -262)
		label(self.card, "CRICKET", UDim2.fromOffset(110, 24), UDim2.fromOffset(6, 4), GOLD, Enum.Font.FredokaOne)
		for i, seat in seats do
			local x = 116 + (i - 1) * 110
			local up = view.turn == i
			label(
				self.card,
				seat.name .. (if i == you then "*" else ""),
				UDim2.fromOffset(104, 22),
				UDim2.fromOffset(x, 4),
				if up then GOLD else WHITE,
				Enum.Font.GothamBold
			)
			for r, lab in CRICKET do
				local m = if g then g.seats[i].marks[lab] or 0 else 0
				label(
					self.card,
					cricketMark(m),
					UDim2.fromOffset(104, 22),
					UDim2.fromOffset(x, 4 + r * 26),
					WHITE,
					Enum.Font.GothamBold
				)
			end
			label(
				self.card,
				if g then tostring(g.seats[i].score) else "0",
				UDim2.fromOffset(104, 24),
				UDim2.fromOffset(x, 214),
				GOLD,
				Enum.Font.FredokaOne
			)
		end
		for r, lab in CRICKET do
			label(
				self.card,
				if lab == "25" then "BULL" else lab,
				UDim2.fromOffset(90, 22),
				UDim2.fromOffset(10, 4 + r * 26),
				CYAN,
				Enum.Font.GothamBold
			)
		end
	else
		self.card.Size = UDim2.fromOffset(420, 34 + n * 40)
		self.card.Position = UDim2.new(1, -432, 1, -(46 + n * 40))
		label(
			self.card,
			"501  (finish on a double)",
			UDim2.new(1, -12, 0, 24),
			UDim2.fromOffset(6, 4),
			GOLD,
			Enum.Font.FredokaOne
		)
		for i, seat in seats do
			local y = 32 + (i - 1) * 40
			local gs = if g then g.seats[i] else nil
			local up = view.turn == i
			label(
				self.card,
				(if up then "> " else "") .. seat.name .. (if i == you then " (you)" else ""),
				UDim2.new(0.42, 0, 0, 30),
				UDim2.fromOffset(6, y),
				if up then GOLD else WHITE,
				Enum.Font.GothamBold
			)
			label(
				self.card,
				if gs then tostring(gs.score) else "501",
				UDim2.new(0.22, 0, 0, 34),
				UDim2.new(0.44, 0, 0, y - 2),
				GOLD,
				Enum.Font.FredokaOne
			)
			label(
				self.card,
				if gs and gs.darts then table.concat(gs.darts, "  ") else "",
				UDim2.new(0.32, 0, 0, 26),
				UDim2.new(0.67, 0, 0, y + 2),
				CYAN,
				Enum.Font.GothamBold
			)
		end
	end
end

return MinigameUI
