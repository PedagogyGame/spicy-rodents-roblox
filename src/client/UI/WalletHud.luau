--!strict
-- StarterPlayer.StarterPlayerScripts.Client.UI.WalletHud
-- The wallet on screen, always: "Wallet  S$3.00" in the bottom-right corner, just above the Menu button, in the
-- HUD's own style (white Gotham on translucent black, as UI/Hud and the status line). The server owns the money
-- (Server/Economy/Credits) and writes it on the Player as attributes; this module only draws them, and redraws
-- the moment one changes (GetAttributeChangedSignal: no polling, no remote):
--   Cents        the balance. Until the server has written it the wallet is not drawn at all.
--   CentsWhy     the reason of the last change (written just before Cents): a change flashes the balance and
--                shows a line above it for NOTE_SECS: "-12c  coffee" (red) or "+5c  mowing a lawn" (green).
--   PocketMoney  cents of pocket money given at this join: said for POCKET_SECS when the wallet first shows and
--                whenever more is given: "Pocket money: S$3.00 to spend".
--   PassUntil    the game second the paintball pass runs out: while it has time left a line between the two
--                says how much, in in-game days and real minutes, recounted once a second from the day clock
--                (the ReplicatedStorage attributes Server/Boot/DayClock publishes): "Pass: 4.2 days (50 min)".
-- While a minigame is open (the Player's InMinigame attribute, set by Minigames/MinigameClient) the stack
-- stands higher, clear of that game's scorecard (UI/MinigameUI: bottom right, 170 tall), so the balance is on
-- screen then too.
-- Nothing here can be clicked and nothing here decides anything.
-- No service access at require time (Lune requires this module; everything engine is inside start).
-- Interface: start(opts?) -> WalletHud { gui, balance, pass, note (the labels), refresh(), stop() };
--   balanceText(cents) -> "Wallet  S$3.00"; changeText(delta, why) -> "-12c  coffee"; pocketText(cents);
--   passText(untilSeconds, nowSeconds, daySeconds) -> string? (nil: no pass to show); bottom(inMinigame) ->
--   pixels from the bottom edge; NOTE_SECS, POCKET_SECS

local Import = require("../Import")
local Wallet = Import.shared("Economy/Wallet") :: typeof(require("../../shared/Economy/Wallet"))

export type Opts = {
	player: any?, -- default Players.LocalPlayer
	now: (() -> number)?, -- game seconds (default: the day clock's attributes and workspace:GetServerTimeNow)
	daySeconds: number?, -- default the ClockRealSecondsPerDay attribute, else 720
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

-- How far above the bottom edge the stack ends: just above the Menu button (UI/PlayMenu: 40 tall at -96), or
-- just above a minigame's scorecard (UI/MinigameUI: 170 tall at -182) while one is open.
function WalletHud.bottom(inMinigame: boolean): number
	return if inMinigame then 194 else 144
end

local WHITE = { 255, 255, 255 }
local GAIN = { 120, 230, 120 }
local LOSS = { 255, 130, 110 }

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
	local player = o.player or game:GetService("Players").LocalPlayer

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
	-- the stack grows upwards from just above the Menu button (or a minigame's scorecard: bottom())
	local stack = Instance.new("Frame")
	stack.Name = "Stack"
	stack.AnchorPoint = Vector2.new(1, 1)
	local function place()
		stack.Position = UDim2.new(1, -12, 1, -WalletHud.bottom(player:GetAttribute("InMinigame") ~= nil))
	end
	place()
	stack.Size = UDim2.fromOffset(260, 100)
	stack.BackgroundTransparency = 1
	stack.Parent = gui
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Vertical
	list.HorizontalAlignment = Enum.HorizontalAlignment.Right
	list.VerticalAlignment = Enum.VerticalAlignment.Bottom
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
	local note = line("Note", 1, 15, Enum.Font.GothamMedium)
	local pass = line("Pass", 2, 15, Enum.Font.GothamMedium)
	local balance = line("Balance", 3, 20, Enum.Font.GothamBold)
	gui.Parent = player:WaitForChild("PlayerGui")

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
	local function drawPass()
		local text = WalletHud.passText(player:GetAttribute("PassUntil"), now(), daySeconds())
		pass.Visible = text ~= nil and shown ~= nil
		if text then
			pass.Text = text
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
		local was = shown
		shown = cents
		balance.Text = WalletHud.balanceText(cents)
		balance.Visible = true
		if was == nil then
			-- the wallet has just appeared: what there is to say is the pocket money, and the pass
			drawPocket()
			drawPass()
		elseif cents ~= was then
			local why = player:GetAttribute("CentsWhy")
			flash(if cents > was then GAIN else LOSS)
			-- (pocket money has its own line, said by drawPocket when PocketMoney is written)
			if why ~= "pocket money" then
				say(
					WalletHud.changeText(cents - was, if type(why) == "string" then why else nil),
					if cents > was then GAIN else LOSS,
					WalletHud.NOTE_SECS
				)
			end
		end
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
