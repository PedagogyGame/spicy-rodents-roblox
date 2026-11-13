--!strict
-- StarterPlayer.StarterPlayerScripts.Client.UI.WalletHud
-- The wallet on screen, always: "Wallet  S$3.00" in the bottom-right corner, just above the Menu button, in the
-- HUD's own style (white Gotham on translucent black, as UI/Hud and the status line). The server owns the money
-- (Server/Economy/Credits) and writes it on the Player as attributes; this module only draws them, and redraws
-- the moment one changes (GetAttributeChangedSignal: no polling, no remote):
--   Cents        the balance. Until the server has written it the wallet is not drawn at all.
--   CentsNote    the last change, "seq|delta|why" (written just before Cents; seq counts the account's
--                changes). A change flashes the balance and shows a line above it for NOTE_SECS: "-12c  coffee"
--                (red) or "+5c  work" (green). A client is shown only the LAST value of a frame (the place runs
--                deferred signals and replication carries the last write), so the amount shown is always what
--                the balance really moved by since it was last drawn, and the reason is the note's only when
--                the note accounts for all of it: three spends in one frame read "-67c  a kite and 2 more",
--                never "-67c  a kite"; a spend refunded in the same frame moves nothing and shows nothing.
--   PocketMoney  cents of pocket money given at this join: said for POCKET_SECS when the wallet first shows and
--                whenever more is given: "Pocket money: S$3.00 to spend". (It is given once, so someone who
--                comes back is not told it again.)
--   PassUntil    the game second the paintball pass runs out: while it has time left a line between the two
--                says how much, in in-game days and real minutes, recounted once a second from the day clock
--                (the ReplicatedStorage attributes Server/Boot/DayClock publishes): "Pass: 4.2 days (50 min)".
--                When it runs out while the player watches, the line goes and "Your pass has run out" is said
--                for PASS_OVER_SECS.
-- While a minigame is open (the Player's InMinigame attribute, set by Minigames/MinigameClient) the stack
-- stands higher, clear of that game's scorecard, so the balance is on screen then too. The scorecard is
-- UI/MinigameUI's Frame "Scorecard" in the bottom-right corner, and each game sizes it for itself (bowling
-- grows with the bowlers, darts cricket is 250 tall), so the stack follows the card's own top edge, frame by
-- frame while a game is open.
-- On a touch device (a phone, a tablet: touch and no keyboard) the bottom-right corner is Roblox's jump button,
-- so the stack hangs from the top-right instead, under the status, sickness and toast lines (TOUCH_TOP), and
-- under a minigame's status and warning lines while a game is open (TOUCH_TOP_GAME); the balance is the top
-- line there and the others appear beneath it. Worked out from the modules' own numbers and Roblox's
-- published control sizes, NOT yet seen on a device.
-- While the role menu is open (UI/PlayMenu's Frame "Menu" in the ScreenGui "SpicyPlay") on a screen too narrow
-- to hold the menu's panel and the stack side by side, the stack is hidden: it would lie across the panel.
-- Nothing here can be clicked and nothing here decides anything.
-- No service access at require time (Lune requires this module; everything engine is inside start).
-- Interface: start(opts?) -> WalletHud { gui, balance, pass, note (the labels), refresh(), stop() };
--   balanceText(cents) -> "Wallet  S$3.00"; changeText(delta, why) -> "-12c  coffee"; pocketText(cents);
--   parseNote(text) -> (seq?, delta?, why?); noteText(moved, seqWas, seq?, delta?, why?) -> string? (what to
--   say of a balance that moved; nil: nothing); passText(untilSeconds, nowSeconds, daySeconds) -> string?
--   (nil: no pass to show); bottom(inMinigame, cardTop?) -> pixels from the bottom edge; top(inMinigame) ->
--   pixels from the top edge on a touch device; underMenu(menuOpen, viewportWidth) -> boolean; NOTE_SECS,
--   POCKET_SECS, PASS_OVER_SECS, PASS_OVER, GAP, CARD_GUI, CARD, MENU_GUI, MENU, MENU_PANEL, WIDTH, MARGIN,
--   TOUCH_TOP, TOUCH_TOP_GAME

local Import = require("../Import")
local Wallet = Import.shared("Economy/Wallet") :: typeof(require("../../shared/Economy/Wallet"))

export type Opts = {
	player: any?, -- default Players.LocalPlayer
	now: (() -> number)?, -- game seconds (default: the day clock's attributes and workspace:GetServerTimeNow)
	daySeconds: number?, -- default the ClockRealSecondsPerDay attribute, else 720
	touch: boolean?, -- a touch device (default: UserInputService says touch and no keyboard)
}

export type WalletHud = {
	gui: ScreenGui,
	balance: TextLabel,
	pass: TextLabel,
	note: TextLabel,
	refresh: () -> (),
	stop: () -> (),
}

local WalletHud = {}

WalletHud.NOTE_SECS = 3 -- how long a change stays above the balance
WalletHud.POCKET_SECS = 20 -- how long the pocket money line stays
WalletHud.FLASH_SECS = 0.8
WalletHud.PASS_OVER_SECS = 8 -- how long "Your pass has run out" stays
WalletHud.PASS_OVER = "Your pass has run out"

WalletHud.GAP = 12 -- between a minigame's scorecard and the stack
WalletHud.CARD_GUI = "MinigameUI" -- UI/MinigameUI's ScreenGui under PlayerGui
WalletHud.CARD = "Scorecard" -- and its scorecard Frame
WalletHud.MENU_GUI = "SpicyPlay" -- UI/PlayMenu's ScreenGui under PlayerGui
WalletHud.MENU = "Menu" -- and its role menu (visible while open)
WalletHud.MENU_PANEL = 600 -- the menu's panel is this wide at most, in the middle of the screen
WalletHud.WIDTH = 260 -- the stack's own width
WalletHud.MARGIN = 12 -- from the screen's right edge
-- On a touch device, from the top edge: under UI/PlayMenu's toast (108 + 36) outside a game, and under
-- UI/MinigameUI's warning line (182 + 28) while one is open.
WalletHud.TOUCH_TOP = 150
WalletHud.TOUCH_TOP_GAME = 216

-- How far above the bottom edge the stack ends: just above the Menu button (UI/PlayMenu: 40 tall at -96), or
-- while a minigame is open just above its scorecard, whose top edge is `cardTop` pixels above the bottom
-- (UI/MinigameUI's own is 170 tall at -182, which is what is assumed when the card cannot be read).
function WalletHud.bottom(inMinigame: boolean, cardTop: number?): number
	if not inMinigame then
		return 144
	end
	return math.max(182, cardTop or 182) + WalletHud.GAP
end

-- On a touch device: how far below the top edge the stack begins.
function WalletHud.top(inMinigame: boolean): number
	return if inMinigame then WalletHud.TOUCH_TOP_GAME else WalletHud.TOUCH_TOP
end

-- Is the stack in the role menu's way? The menu's panel sits in the middle; the stack needs its own width and
-- margin clear to the right of it.
function WalletHud.underMenu(menuOpen: boolean, viewportWidth: number): boolean
	return menuOpen and viewportWidth < WalletHud.MENU_PANEL + 2 * (WalletHud.WIDTH + WalletHud.MARGIN)
end

local WHITE = { 255, 255, 255 }
local GAIN = { 120, 230, 120 }
local LOSS = { 255, 130, 110 }
local POCKET_WHY = "pocket money" -- Shared/Economy/Bank.POCKET_WHY

function WalletHud.balanceText(cents: number): string
	return `Wallet  {Wallet.format(cents)}`
end

-- A price as the shops write it under a dollar ("12c"), dollars above ("S$3.00").
local function amount(cents: number): string
	return if cents < 100 then `{cents}c` else Wallet.format(cents)
end

function WalletHud.changeText(delta: number, why: string?): string
	local sign = if delta < 0 then "-" else "+"
	local words = if why and why ~= "" then `  {why}` else ""
	return `{sign}{amount(math.abs(delta))}{words}`
end

function WalletHud.pocketText(cents: number): string
	return `Pocket money: {Wallet.format(cents)} to spend`
end

-- The CentsNote attribute ("7|-12|coffee") as (seq, delta, why); nils when it is not one.
function WalletHud.parseNote(text: any): (number?, number?, string?)
	if type(text) ~= "string" then
		return nil, nil, nil
	end
	local seq, delta, why = string.match(text, "^(%d+)|(%-?%d+)|(.*)$")
	if seq == nil then
		return nil, nil, nil
	end
	return tonumber(seq), tonumber(delta), why
end

-- What to say of a balance that moved by `moved` since it was last drawn, when the account's change count was
-- `seqWas`, given the note that came with it (seq, delta, why: the LAST change only). nil: say nothing here
-- (pocket money has a line of its own).
function WalletHud.noteText(moved: number, seqWas: number, seq: number?, delta: number?, why: string?): string?
	if delta == moved or seq == nil then
		-- the note accounts for all of it (or there is none: say the amount alone)
		if why == POCKET_WHY then
			return nil
		end
		return WalletHud.changeText(moved, if delta == moved then why else nil)
	end
	-- several changes reached the screen as one: the amount is the true total, the reason only the last one's
	local more = seq - seqWas - 1
	if why ~= nil and why ~= "" and delta ~= nil and (delta < 0) == (moved < 0) and more >= 1 then
		return WalletHud.changeText(moved, `{why} and {more} more`)
	end
	return WalletHud.changeText(moved, nil)
end

-- The pass line, or nil when there is no pass with time left.
function WalletHud.passText(untilSeconds: number?, nowSeconds: number, daySeconds: number): string?
	if type(untilSeconds) ~= "number" or not (untilSeconds > nowSeconds) or not (daySeconds > 0) then
		return nil
	end
	local days = (untilSeconds - nowSeconds) / daySeconds
	local minutes = math.max(1, math.ceil(days * daySeconds / 60))
	if days >= 1 then
		return `Pass: {string.format("%.1f", days)} days ({minutes} min)`
	end
	return `Pass: {minutes} min left`
end

function WalletHud.start(opts: Opts?): WalletHud
	local o: Opts = opts or {}
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local RunService = game:GetService("RunService")
	local UIS = game:GetService("UserInputService")
	local player = o.player or game:GetService("Players").LocalPlayer
	local touch = if o.touch ~= nil then o.touch else (UIS.TouchEnabled == true and UIS.KeyboardEnabled ~= true)

	local function now(): number
		if o.now then
			return o.now()
		end
		local epoch = ReplicatedStorage:GetAttribute("ClockEpoch")
		if type(epoch) ~= "number" then
			return 0
		end
		local base = ReplicatedStorage:GetAttribute("ClockBase")
		local rate = ReplicatedStorage:GetAttribute("ClockRate")
		return (if type(base) == "number" then base else 0)
			+ (workspace:GetServerTimeNow() - epoch) * (if type(rate) == "number" then rate else 1)
	end
	local function daySeconds(): number
		local perDay = o.daySeconds or ReplicatedStorage:GetAttribute("ClockRealSecondsPerDay")
		return if type(perDay) == "number" and perDay > 0 then perDay else 720
	end

	local gui = Instance.new("ScreenGui")
	gui.Name = "SpicyWallet"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 11 -- over the menu's dimmed backdrop (10), under a minigame's own screen (20)
	-- the stack grows upwards from just above the Menu button (or a minigame's scorecard: bottom()); on a touch
	-- device it hangs from the top-right and grows downwards (top())
	local stack = Instance.new("Frame")
	stack.Name = "Stack"
	stack.AnchorPoint = Vector2.new(1, if touch then 0 else 1)
	local playerGui = player:WaitForChild("PlayerGui")
	-- the top edge of the minigame scorecard as it is drawn now, in pixels above the bottom (nil: none to read)
	local function cardTop(): number?
		local ui = playerGui:FindFirstChild(WalletHud.CARD_GUI)
		local card: any = ui and ui:FindFirstChild(WalletHud.CARD)
		if card == nil or card.Visible ~= true then
			return nil
		end
		local pos = card.Position
		if typeof(pos) == "UDim2" and pos.Y.Scale == 1 then
			return -pos.Y.Offset
		end
		return nil
	end
	local function menuOpen(): boolean
		local ui = playerGui:FindFirstChild(WalletHud.MENU_GUI)
		local menu: any = ui and ui:FindFirstChild(WalletHud.MENU)
		return menu ~= nil and menu.Visible == true
	end
	local function viewportWidth(): number
		local camera = workspace.CurrentCamera
		return if camera then camera.ViewportSize.X else 1280
	end
	local placedAt: number? = nil
	local function place()
		local inMinigame = player:GetAttribute("InMinigame") ~= nil
		if touch then
			local at = WalletHud.top(inMinigame)
			if at ~= placedAt then
				placedAt = at
				stack.Position = UDim2.new(1, -WalletHud.MARGIN, 0, at)
			end
		else
			local at = WalletHud.bottom(inMinigame, if inMinigame then cardTop() else nil)
			if at ~= placedAt then
				placedAt = at
				stack.Position = UDim2.new(1, -WalletHud.MARGIN, 1, -at)
			end
		end
		local show = not WalletHud.underMenu(menuOpen(), viewportWidth())
		if stack.Visible ~= show then
			stack.Visible = show
		end
	end
	stack.Visible = true
	place()
	stack.Size = UDim2.fromOffset(WalletHud.WIDTH, 100)
	stack.BackgroundTransparency = 1
	stack.Parent = gui
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Vertical
	list.HorizontalAlignment = Enum.HorizontalAlignment.Right
	list.VerticalAlignment = if touch then Enum.VerticalAlignment.Top else Enum.VerticalAlignment.Bottom
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 4)
	list.Parent = stack
	local function line(name: string, order: number, size: number, font: Enum.Font): TextLabel
		local l = Instance.new("TextLabel")
		l.Name = name
		l.LayoutOrder = order
		l.AutomaticSize = Enum.AutomaticSize.X
		l.Size = UDim2.fromOffset(0, size + 12)
		l.BackgroundColor3 = Color3.new(0, 0, 0)
		l.BackgroundTransparency = 0.45
		l.BorderSizePixel = 0
		l.TextColor3 = Color3.new(1, 1, 1)
		l.TextSize = size
		l.Font = font
		l.Text = ""
		l.Visible = false
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 10)
		pad.PaddingRight = UDim.new(0, 10)
		pad.Parent = l
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 8)
		corner.Parent = l
		l.Parent = stack
		return l
	end
	-- (the balance is always the line nearest the edge the stack hangs from: the others come and go beyond it)
	local note = line("Note", if touch then 3 else 1, 15, Enum.Font.GothamMedium)
	local pass = line("Pass", 2, 15, Enum.Font.GothamMedium)
	local balance = line("Balance", if touch then 1 else 3, 20, Enum.Font.GothamBold)
	gui.Parent = playerGui

	local function rgb(c: { number }): Color3
		return Color3.fromRGB(c[1], c[2], c[3])
	end

	local noteToken = 0
	local function say(text: string, color: { number }, seconds: number)
		noteToken += 1
		local mine = noteToken
		note.Text = text
		note.TextColor3 = rgb(color)
		note.Visible = true
		task.delay(seconds, function()
			if noteToken == mine then
				note.Visible = false
			end
		end)
	end
	local flashToken = 0
	local function flash(color: { number })
		flashToken += 1
		local mine = flashToken
		balance.TextColor3 = rgb(color)
		task.delay(WalletHud.FLASH_SECS, function()
			if flashToken == mine then
				balance.TextColor3 = rgb(WHITE)
			end
		end)
	end

	local shown: number? = nil -- the balance as last drawn
	local seqShown = 0 -- the account's change count when it was
	local function drawPass()
		local untilSeconds = player:GetAttribute("PassUntil")
		local text = WalletHud.passText(untilSeconds, now(), daySeconds())
		local was = pass.Visible
		pass.Visible = text ~= nil and shown ~= nil
		if text then
			pass.Text = text
		elseif was and type(untilSeconds) == "number" then
			-- it was counting down a moment ago and the time is up: say so (a door will now turn them away)
			say(WalletHud.PASS_OVER, WHITE, WalletHud.PASS_OVER_SECS)
		end
	end
	local function drawPocket()
		local given = player:GetAttribute("PocketMoney")
		if type(given) == "number" and given > 0 and shown ~= nil then
			say(WalletHud.pocketText(given), WHITE, WalletHud.POCKET_SECS)
		end
	end
	local function drawBalance()
		local cents = player:GetAttribute("Cents")
		if type(cents) ~= "number" then
			return
		end
		local seq, delta, why = WalletHud.parseNote(player:GetAttribute("CentsNote"))
		local was = shown
		shown = cents
		balance.Text = WalletHud.balanceText(cents)
		balance.Visible = true
		if was == nil then
			-- the wallet has just appeared: what there is to say is the pocket money, and the pass
			drawPocket()
			drawPass()
		elseif cents ~= was then
			flash(if cents > was then GAIN else LOSS)
			-- (pocket money has its own line, said by drawPocket when PocketMoney is written)
			local text = WalletHud.noteText(cents - was, seqShown, seq, delta, why)
			if text then
				say(text, if cents > was then GAIN else LOSS, WalletHud.NOTE_SECS)
			end
		end
		seqShown = seq or seqShown
	end

	local conns: { RBXScriptConnection } = {}
	table.insert(conns, player:GetAttributeChangedSignal("Cents"):Connect(drawBalance))
	table.insert(conns, player:GetAttributeChangedSignal("PassUntil"):Connect(drawPass))
	table.insert(conns, player:GetAttributeChangedSignal("PocketMoney"):Connect(drawPocket))
	table.insert(conns, player:GetAttributeChangedSignal("InMinigame"):Connect(place))
	-- the pass counts down: once a second is plenty
	local acc = 0
	table.insert(
		conns,
		RunService.Heartbeat:Connect(function(dt: number)
			place() -- a minigame redraws its scorecard as it likes, and the role menu opens and shuts: stay clear
			acc += dt
			if acc >= 1 then
				acc = 0
				drawPass()
			end
		end)
	)
	drawBalance()

	return {
		gui = gui,
		balance = balance,
		pass = pass,
		note = note,
		refresh = function()
			drawBalance()
			drawPass()
		end,
		stop = function()
			for _, c in conns do
				c:Disconnect()
			end
			gui:Destroy()
		end,
	}
end

return WalletHud
