--!strict
-- StarterPlayer.StarterPlayerScripts.Client.UI.StockOptionsUI
-- The Spicy Stock Options screen (owner D30; Server/Economy/StockOptions decides everything, this only shows and asks).
-- Two ways in, one screen:
--   * the menu (M): "Stock options" asks the server for the player's view; the screen says plainly what options are
--     (play money for this game only, no value outside it, 1 option = S$1, withdrawn at home, S$100 per server, the
--     withdrawn dollars stay on that server), what is saved, what is left to withdraw here, where home is, and has
--     a "Buy with Robux" button (the server opens Roblox's purchase window) and "Show my home" (a HOME marker over
--     the house for a minute: there is no compass);
--   * E at the home computer: the server sends the same view for the computer, with amounts to withdraw.
-- The server's sentences ("said") show on the screen's own line as well as the usual notice.
-- Pure part (Lune-tested): lines(view) -> { string }, amounts(view) -> { number }, priceLine(view) -> string.
-- Engine part: start(remote) -> UI { open(), close(), isOpen() }.
-- No side effects on require.

local Import = require("../Import")
local PlayerHomes = Import.shared("World/PlayerHomes") :: typeof(require("../../shared/World/PlayerHomes"))

local StockOptionsUI = {}

StockOptionsUI.CHOICES = table.freeze({ 5, 10, 25, 50 }) -- the withdraw buttons, S$ (and "the most I can")
StockOptionsUI.MARK_SECONDS = 60 -- how long "Show my home" keeps the marker up

export type View = { [string]: any }
export type UI = { open: () -> (), close: () -> (), isOpen: () -> boolean }

-- What one purchase costs and gives, in plain words.
function StockOptionsUI.priceLine(view: View): string
	local per = view.perRobux or 4
	local price = view.price
	if type(price) == "number" and price > 0 then
		return `One purchase: {price} Robux for {price * per} options.`
	end
	return `{per} options for each Robux (the Roblox window shows the price).`
end

-- The status lines under the explanation.
function StockOptionsUI.lines(view: View): { string }
	local out: { string } = {}
	if view.enabled == false then
		table.insert(out, "Spicy Stock Options are closed for now.")
	end
	if view.loaded and type(view.held) == "number" then
		table.insert(out, `Your options: {view.held} (saved)`)
	else
		table.insert(out, "Your saved options are still loading.")
	end
	table.insert(out, `Withdrawn on this server: S${view.withdrawnHere or 0} of S${view.cap or 100}`)
	if type(view.homeName) == "string" then
		local verb = if view.where == "computer" then "This is your home computer in" else "Your home:"
		table.insert(out, `{verb} {view.homeName}`)
	else
		table.insert(out, "You get a home when you first walk the town as a person.")
	end
	if view.where ~= "computer" then
		table.insert(out, StockOptionsUI.priceLine(view))
	end
	return out
end

-- The amounts the computer offers: the fixed choices that fit, and the most there is (once).
function StockOptionsUI.amounts(view: View): { number }
	local most = math.min(tonumber(view.capLeft) or 0, tonumber(view.held) or 0)
	most = math.max(0, math.floor(most))
	local out: { number } = {}
	if not view.loaded or view.enabled == false or most < 1 then
		return out
	end
	for _, n in StockOptionsUI.CHOICES do
		if n < most then
			table.insert(out, n)
		end
	end
	table.insert(out, most)
	return out
end

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

function StockOptionsUI.start(remote: RemoteEvent): UI
	local Players = game:GetService("Players")
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local gui = Instance.new("ScreenGui")
	gui.Name = "SpicyStockOptions"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 15 -- over the menu (10) and the wallet (11), under a minigame's own screen (20)
	gui.Enabled = false
	-- (scrolls: a phone held sideways is short)
	local panel = Instance.new("ScrollingFrame")
	panel.CanvasSize = UDim2.new()
	panel.AutomaticCanvasSize = Enum.AutomaticSize.Y
	panel.ScrollingDirection = Enum.ScrollingDirection.Y
	panel.ScrollBarThickness = 6
	panel.BorderSizePixel = 0
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromScale(0.92, 0.86)
	panel.BackgroundColor3 = Color3.fromRGB(30, 34, 46)
	panel.Parent = gui
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(560, 560)
	limit.Parent = panel
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0, 14)
	round.Parent = panel
	local pad = Instance.new("UIPadding")
	for _, side in { "PaddingTop", "PaddingBottom", "PaddingLeft", "PaddingRight" } do
		(pad :: any)[side] = UDim.new(0, 14)
	end
	pad.Parent = panel
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 8)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = panel

	local order = 0
	local function label(size: number, bold: boolean, color: { number }?): TextLabel
		order += 1
		local l = Instance.new("TextLabel")
		l.LayoutOrder = order
		l.BackgroundTransparency = 1
		l.Size = UDim2.fromScale(1, 0)
		l.AutomaticSize = Enum.AutomaticSize.Y
		l.TextWrapped = true
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.Font = if bold then Enum.Font.GothamBold else Enum.Font.Gotham
		l.TextSize = size
		l.TextColor3 = rgb(color or { 235, 235, 235 })
		l.Text = ""
		l.Parent = panel
		return l
	end
	local title = label(24, true, { 255, 214, 120 })
	title.Text = "Spicy Stock Options"
	local about = label(14, false, { 205, 210, 220 })
	local status = label(16, true)
	local said = label(15, false, { 255, 226, 150 })

	order += 1
	local row = Instance.new("Frame")
	row.LayoutOrder = order
	row.BackgroundTransparency = 1
	row.Size = UDim2.fromScale(1, 0)
	row.AutomaticSize = Enum.AutomaticSize.Y
	row.Parent = panel
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(160, 42)
	grid.CellPadding = UDim2.fromOffset(8, 8)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = row

	gui.Parent = playerGui

	-- the HOME marker over the house (Show my home)
	local marker = Instance.new("BillboardGui")
	marker.Name = "HomeMarker"
	marker.AlwaysOnTop = true
	marker.Size = UDim2.fromOffset(120, 34)
	marker.LightInfluence = 0
	marker.Enabled = false
	local markerText = Instance.new("TextLabel")
	markerText.Size = UDim2.fromScale(1, 1)
	markerText.BackgroundColor3 = Color3.fromRGB(30, 34, 46)
	markerText.BackgroundTransparency = 0.2
	markerText.TextColor3 = Color3.fromRGB(255, 214, 120)
	markerText.Font = Enum.Font.GothamBlack
	markerText.TextSize = 18
	markerText.Text = "HOME"
	markerText.Parent = marker
	local markerAnchor = Instance.new("Attachment")
	markerAnchor.Name = "HomeMarkerPoint"
	marker.Adornee = markerAnchor
	marker.Parent = playerGui
	local markToken = 0
	local function markHome()
		local h = PlayerHomes.lot(PlayerHomes.homeOf(player) or "")
		if h == nil then
			said.Text = "You get a home when you first walk the town as a person."
			return
		end
		markerAnchor.Parent = workspace.Terrain
		markerAnchor.Position = Vector3.new(h.x, h.computer[2] + 22, h.z)
		marker.Enabled = true
		markToken += 1
		local mine = markToken
		said.Text = `{h.name} is marked HOME for a minute.`
		task.delay(StockOptionsUI.MARK_SECONDS, function()
			if markToken == mine then
				marker.Enabled = false
			end
		end)
	end

	local buttons: { GuiObject } = {}
	local function clearButtons()
		for _, b in buttons do
			b:Destroy()
		end
		table.clear(buttons)
	end
	local function button(text: string, color: { number }, n: number, fn: () -> ())
		local b = Instance.new("TextButton")
		b.LayoutOrder = n
		b.BackgroundColor3 = rgb(color)
		b.TextColor3 = Color3.new(1, 1, 1)
		b.Font = Enum.Font.GothamBold
		b.TextSize = 16
		b.TextWrapped = true
		b.Text = text
		b.Modal = true -- frees a first-person mouse while the screen is up
		b.AutoButtonColor = true
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 10)
		c.Parent = b
		b.Parent = row
		b.Activated:Connect(fn)
		table.insert(buttons, b)
	end

	local isOpen = false
	local self: UI
	local function show(view: View)
		about.Text = table.concat(view.about or {}, "\n")
		status.Text = table.concat(StockOptionsUI.lines(view), "\n")
		clearButtons()
		if view.where == "computer" then
			local amounts = StockOptionsUI.amounts(view)
			for i, n in amounts do
				local last = i == #amounts
				button(
					if last and #amounts > 1 then `All I can: S${n}` else `Withdraw S${n}`,
					{ 60, 130, 80 },
					i,
					function()
						said.Text = "Withdrawing…"
						remote:FireServer("withdraw", n)
					end
				)
			end
			if #amounts == 0 and view.loaded and (view.capLeft or 0) > 0 then
				said.Text = "You have no options to withdraw. Buy them from the menu (M)."
			end
		else
			if view.enabled ~= false then
				button("Buy with Robux", { 70, 110, 170 }, 1, function()
					remote:FireServer("buy")
				end)
			end
			button("Show my home", { 90, 100, 90 }, 2, markHome)
		end
		button("Close", { 80, 80, 90 }, 99, function()
			self.close()
		end)
		gui.Enabled = true
		isOpen = true
	end

	remote.OnClientEvent:Connect(function(payload: any)
		if type(payload) ~= "table" then
			return
		end
		if payload.kind == "view" then
			show(payload)
		elseif payload.kind == "said" and type(payload.text) == "string" then
			said.Text = payload.text
		end
	end)

	self = {
		open = function()
			said.Text = ""
			remote:FireServer("open")
		end,
		close = function()
			gui.Enabled = false
			isOpen = false
			said.Text = ""
		end,
		isOpen = function(): boolean
			return isOpen
		end,
	}
	return self
end

return StockOptionsUI
