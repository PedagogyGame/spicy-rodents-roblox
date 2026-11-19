--!strict
-- StarterPlayer.StarterPlayerScripts.Client.UI.NutMeter
-- The nut meter (owner D16 #22; brief v2 §7), on screen while the player is a squirrel: a small pill in the HUD's own
-- style (white Gotham on translucent black, as UI/PlayMenu's status line and UI/Hud) beside the squirrel's health
-- bar at the top centre (on a phone, the top-left corner):
--   an acorn and "3/9"     the nuts its squirrel carries of the most it can (amber when its paws are full)
--   "H4" and a bar         the hollow tree it holds and how full that is (a tick at 70 %, the claim line), or, while
--                          it is inside a claimable hollow, that hollow's (grey when it is another squirrel's)
--   a hint line            what to do next, in a few words (gone once there is nothing to say)
--   "+1"                   beside the count for a moment at each nut picked up; "stored 9" when nuts go into a tree
-- The server decides everything (Server/Boot/Game writes the Player attributes NutsCarried, NutsMax, NutTree,
-- NutTreeName, NutStore and NutInside, "H4|0.45|free" (or yours, taken), from Foraging/ForageService and HollowService);
-- this only draws them, the moment one changes. Nothing here can be clicked.
-- Where: right of the health bar (UI/PlayMenu's 300-wide bar at the top centre, 84 down) on a screen wide enough
-- for both (WIDE, 752 pixels), else in the top-left corner just under Roblox's top bar, above the status line (52
-- down, 70 % of the width in the middle): on a 667 x 375 phone that is 12..222 across and 8..52 down, clear of the
-- status, the health bar, the toasts (108 down), the wallet (top right on touch, from 150 down: UI/WalletHud) and the
-- thumbstick and jump button (the bottom corners). Worked out from the modules' numbers, not yet seen on a device.
-- Interface: look(attrs) -> Look (pure: attrs is a table of those attributes); flash(was, now, inside) -> string?
--   (pure: what to show beside the count when the carried count moves); place(viewportWidth) -> (anchorX,
--   scaleX, offsetX, offsetY) (pure); WIDTH, HEIGHT, WIDE, CLAIM, PICK_SOUND; start(opts?) -> Handle { gui, stop() }
-- No service access at require time.

local NutMeter = {}

-- the pick-up's tick, heard by the picker only (a Sound under the meter's gui; nothing replicated): a stand-in from
-- the licensed library already in the game (Items.Click, Flashlight Switch 13, ProSoundEffects), quiet, until a nut
-- sound is picked (docs/AUDIO_BUDGET.md "Nuts")
NutMeter.PICK_SOUND = { id = "rbxassetid://9114481274", volume = 0.35, speed = 1.3 }
NutMeter.WIDTH = 210
NutMeter.HEIGHT = 44 -- with the hint line; 26 without
NutMeter.CLAIM = 0.7 -- the tick on the bar (Tunables forage.ownThreshold)
NutMeter.BAR_GAP = 8 -- between the health bar's right end and the pill
NutMeter.HP_HALF = 150 -- UI/PlayMenu's health bar is 300 wide at the centre
NutMeter.WIDE = 2 * (NutMeter.HP_HALF + NutMeter.BAR_GAP + NutMeter.WIDTH + 8) -- 752: room beside the bar

local WHITE = { 255, 255, 255 }
local AMBER = { 255, 190, 70 }
local STORE = { 214, 150, 72 } -- the bar: a nut brown-gold
local GREY = { 150, 150, 150 }

export type Look = {
	visible: boolean,
	count: string, -- "3/9"
	countColor: { number },
	tree: string, -- "H4", or "" (no bar)
	fill: number, -- 0..1
	fillColor: { number },
	percent: string, -- "62%"
	hint: string?, -- the second line; nil: none
}

local function num(v: any): number?
	return if type(v) == "number" and v == v then v else nil
end

local function str(v: any): string
	return if type(v) == "string" then v else ""
end

-- inside: "H4|0.45|free" -> ("H4", 0.45, "free"); nil when not one
local function parseInside(v: any): (string?, number?, string?)
	local id, m, state = string.match(str(v), "^([^|]+)|([^|]+)|(%a+)$")
	local meter = tonumber(m)
	if id == nil or meter == nil then
		return nil, nil, nil
	end
	return id, math.clamp(meter, 0, 1), state
end

function NutMeter.look(attrs: { [string]: any }): Look
	local max = num(attrs.NutsMax)
	if max == nil then
		return {
			visible = false,
			count = "",
			countColor = WHITE,
			tree = "",
			fill = 0,
			fillColor = STORE,
			percent = "",
			hint = nil,
		}
	end
	local carried = math.max(0, math.floor(num(attrs.NutsCarried) or 0))
	local full = carried >= max
	local look: Look = {
		visible = true,
		count = `{carried}/{max}`,
		countColor = if full then AMBER else WHITE,
		tree = "",
		fill = 0,
		fillColor = STORE,
		percent = "",
		hint = nil,
	}
	local inId, inMeter, inState = parseInside(attrs.NutInside)
	local own = str(attrs.NutTree)
	if inId and inMeter then
		look.tree, look.fill = inId, inMeter
		look.fillColor = if inState == "taken" then GREY else STORE
		look.hint = if inState == "yours"
			then "Your tree: nuts go in"
			elseif inState == "taken" then "Not yours: you keep your nuts"
			else "Nobody's: fill to 70% to claim"
	elseif own ~= "" then
		look.tree, look.fill = own, math.clamp(num(attrs.NutStore) or 0, 0, 1)
		look.hint = if carried > 0 then `Take them home to {own}` else nil
	else
		look.hint = if carried > 0 then "Run them into a hollow tree" else "Find nuts: oaks, yards, the park"
	end
	if look.tree ~= "" then
		look.percent = `{math.floor(look.fill * 100 + 0.5)}%`
	end
	if full and look.hint == nil then
		look.hint = "Your paws are full"
	end
	return look
end

-- flash(was, now, inside): beside the count when the carried count moves: "+1" for each nut picked up, "stored 9" as
-- nuts go into a tree; nothing when it drops for another reason (knocked out: the death message says so)
function NutMeter.flash(was: number?, now: number?, inside: any): string?
	if was == nil or now == nil or was == now then
		return nil
	end
	if now > was then
		return `+{now - was}`
	end
	if parseInside(inside) then
		return `stored {was - now}`
	end
	return nil
end

-- place(viewportWidth): where the pill goes: right of the health bar when the screen is wide enough, else in the top
-- left corner (anchor x, the x scale, x offset, y offset from the top)
function NutMeter.place(width: number): (number, number, number, number)
	if width >= NutMeter.WIDE then
		return 0, 0.5, NutMeter.HP_HALF + NutMeter.BAR_GAP, 82
	end
	return 0, 0, 12, 8
end

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

export type Handle = { gui: ScreenGui, stop: () -> () }
export type Opts = { player: Instance?, parent: Instance? }

local ATTRS = { "NutsCarried", "NutsMax", "NutTree", "NutTreeName", "NutStore", "NutInside" }

function NutMeter.start(opts: Opts?): Handle
	local o: Opts = opts or {}
	local player = o.player or (game:GetService("Players").LocalPlayer :: Instance)
	local gui = Instance.new("ScreenGui")
	gui.Name = "NutMeter"
	gui.ResetOnSpawn = false
	gui.Enabled = false
	gui.DisplayOrder = -1 -- (under the menu's toasts and banners where they cross)
	local pill = Instance.new("Frame")
	pill.Name = "Pill"
	pill.Size = UDim2.fromOffset(NutMeter.WIDTH, NutMeter.HEIGHT)
	pill.BackgroundColor3 = Color3.new(0, 0, 0)
	pill.BackgroundTransparency = 0.45
	pill.BorderSizePixel = 0
	pill.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = pill
	local function frame(name: string, size: UDim2, pos: UDim2, color: { number }, parent: Instance): Frame
		local f = Instance.new("Frame")
		f.Name = name
		f.Size = size
		f.Position = pos
		f.BackgroundColor3 = rgb(color)
		f.BorderSizePixel = 0
		f.Parent = parent
		return f
	end
	local function label(name: string, size: UDim2, pos: UDim2, textSize: number, bold: boolean): TextLabel
		local l = Instance.new("TextLabel")
		l.Name = name
		l.Size = size
		l.Position = pos
		l.BackgroundTransparency = 1
		l.TextColor3 = Color3.new(1, 1, 1)
		l.TextSize = textSize
		l.Font = if bold then Enum.Font.GothamBold else Enum.Font.GothamMedium
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.Text = ""
		l.Parent = pill
		return l
	end
	-- the acorn: a round nut under a darker cap
	local nut = frame("Nut", UDim2.fromOffset(12, 13), UDim2.fromOffset(10, 8), { 176, 116, 62 }, pill)
	local nutRound = Instance.new("UICorner")
	nutRound.CornerRadius = UDim.new(0.5, 0)
	nutRound.Parent = nut
	local cap = frame("Cap", UDim2.fromOffset(14, 6), UDim2.fromOffset(9, 5), { 104, 74, 46 }, pill)
	local capRound = Instance.new("UICorner")
	capRound.CornerRadius = UDim.new(0, 3)
	capRound.Parent = cap
	local count = label("Count", UDim2.fromOffset(52, 22), UDim2.fromOffset(30, 2), 16, true)
	local plus = label("Flash", UDim2.fromOffset(60, 22), UDim2.fromOffset(30, 2), 13, true)
	plus.TextColor3 = rgb(AMBER)
	plus.Visible = false
	local tree = label("Tree", UDim2.fromOffset(32, 22), UDim2.fromOffset(84, 2), 13, true)
	local barBack = frame("Bar", UDim2.fromOffset(62, 8), UDim2.fromOffset(116, 9), { 40, 32, 26 }, pill)
	local barRound = Instance.new("UICorner")
	barRound.CornerRadius = UDim.new(0, 4)
	barRound.Parent = barBack
	local fill = frame("Fill", UDim2.fromScale(0, 1), UDim2.fromScale(0, 0), STORE, barBack)
	local fillRound = Instance.new("UICorner")
	fillRound.CornerRadius = UDim.new(0, 4)
	fillRound.Parent = fill
	local tick = frame("Claim", UDim2.new(0, 2, 1, 4), UDim2.new(NutMeter.CLAIM, -1, 0, -2), WHITE, barBack)
	tick.ZIndex = 2
	local percent = label("Percent", UDim2.fromOffset(32, 22), UDim2.fromOffset(182, 2), 12, false)
	local hint = label("Hint", UDim2.new(1, -20, 0, 16), UDim2.fromOffset(10, 24), 11, false)
	hint.TextTruncate = Enum.TextTruncate.AtEnd
	gui.Parent = o.parent or player:WaitForChild("PlayerGui")

	local tickSound = Instance.new("Sound")
	tickSound.Name = "Nuts.Pick"
	tickSound.SoundId = NutMeter.PICK_SOUND.id
	tickSound.Volume = NutMeter.PICK_SOUND.volume
	tickSound.PlaybackSpeed = NutMeter.PICK_SOUND.speed
	tickSound.Parent = gui

	local camera = workspace.CurrentCamera
	local function placeIt()
		local w = if camera then camera.ViewportSize.X else 1280
		local ax, sx, ox, oy = NutMeter.place(w)
		pill.AnchorPoint = Vector2.new(ax, 0)
		pill.Position = UDim2.new(sx, ox, 0, oy)
	end

	local lastCarried: number? = nil
	local flashToken = 0
	local function draw()
		local attrs: { [string]: any } = {}
		for _, k in ATTRS do
			attrs[k] = player:GetAttribute(k)
		end
		local look = NutMeter.look(attrs)
		gui.Enabled = look.visible
		local carried = num(attrs.NutsCarried)
		local said = NutMeter.flash(lastCarried, carried, attrs.NutInside)
		lastCarried = if look.visible then carried else nil
		if not look.visible then
			return
		end
		placeIt()
		count.Text = look.count
		count.TextColor3 = rgb(look.countColor)
		local hasTree = look.tree ~= ""
		tree.Visible, barBack.Visible, percent.Visible = hasTree, hasTree, hasTree
		tree.Text = look.tree
		percent.Text = look.percent
		fill.Size = UDim2.fromScale(look.fill, 1)
		fill.BackgroundColor3 = rgb(look.fillColor)
		hint.Text = look.hint or ""
		hint.Visible = look.hint ~= nil
		pill.Size = UDim2.fromOffset(NutMeter.WIDTH, if look.hint then NutMeter.HEIGHT else 26)
		if said then
			flashToken += 1
			local mine = flashToken
			plus.Text = said
			plus.Position = UDim2.fromOffset(30 + #look.count * 9 + 6, 2) -- (16 px bold digits: about 9 wide)
			plus.Visible = true
			if string.sub(said, 1, 1) == "+" then
				tickSound:Play()
			end
			task.delay(1.2, function()
				if flashToken == mine then
					plus.Visible = false
				end
			end)
		end
	end
	local conns = {}
	for _, k in ATTRS do
		table.insert(conns, player:GetAttributeChangedSignal(k):Connect(draw))
	end
	if camera and (camera :: any).GetPropertyChangedSignal then -- (a window resized, a phone turned)
		table.insert(conns, camera:GetPropertyChangedSignal("ViewportSize"):Connect(placeIt))
	end
	draw()
	return {
		gui = gui,
		stop = function()
			for _, c in conns do
				c:Disconnect()
			end
			gui:Destroy()
		end,
	}
end

return NutMeter
