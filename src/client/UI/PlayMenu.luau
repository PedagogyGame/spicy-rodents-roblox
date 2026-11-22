--!strict
-- StarterPlayer.StarterPlayerScripts.Client.UI.PlayMenu
-- The first playable build's screens (owner directive 2026-11-09; HANDOFF §4 owner-facing build rule:
-- say what this is and what to press, show progress while loading, never ignore input silently):
--   * Loading screen: the server's boot stage and progress (ReplicatedStorage BootStage, BootProgress,
--     BootReady, BootError), then this computer's own preparation (the climbing routes), with elapsed
--     seconds; a boot error is shown in red, never a silent screen.
--   * Menu: five big buttons (Spicy Rodent, Squirrel, Townsperson, Police, Doctor) that send
--     PlayNet.Pick; "Back to the game" when you already have a body; M or the Menu button reopens it. Under the
--     buttons, money and reputation together (owner D30: "checkable with money, in paused and or side screen"):
--     "Money  S$3.00   ·   Reputation  Good (0)" (the player attributes Cents and Reputation; standingLine).
--     (Owner D30: Doctor took the Police drone's place: drive the ambulance and bring bite victims in.)
--   * Help panel (top left, always visible): the keys for the current role and device.
--   * Status (top centre): role, health bar for the rodent and squirrels, bites and Power for the rodent.
--   * Banners: big centred messages (RUN OVER!, KICKED OUT!) and short toasts for bites, kicks, refusals.
--   * A bitten player's way to the hospital: a HOSPITAL marker over its door, drawn through everything
--     for as long as they are infected, and the distance and direction on the line under the status
--     (the server publishes the door as the Workspace attribute HospitalDoor). The messages used to
--     say "far west" and "follow the signs": the game has no compass and the town has no signs.
-- Layout (W1 client review): the help panel sits bottom-left and the Menu button bottom-right, clear of
-- the Roblox chat window (top-left) and player list (top-right); the menu, banner and help panel scale
-- down on small laptop screens (UIScale from the viewport, scaleFor); toasts wrap. Error lines name F9
-- (the Developer Console), which works in a live game as well as Studio.
-- Pure part (Lune-tested): CHOICES, helpLines(role, device) -> { string }, statusLine(attrs) -> string,
--   sickLine(attrs, way?) -> string? (a bitten player: what to do, under the status line; `way`
--   { dist, words } adds how far the door is and which way), wayWords(dx, dz, lookX, lookZ) -> string,
--   markerText(dist) -> string, scaleFor(width, height) -> number, standingLine(attrs) -> string; D30, a doctor's call
--   (the player attributes DoctorJob and DoctorCall, written by Server/Boot/Game from Hospital/DoctorService):
--   jobLine(attrs, way?) -> string? (the line under the status, in the hospital's teal), jobMarkerText(job, dist) ->
--   string (BITE VICTIM over the patient, then HOSPITAL over the doors once they are aboard). The call takes the marker
--   from the sick player's HOSPITAL while there is one.
-- Engine part: start() -> Menu { loading(prepare) (yields until ready), open(), close(), isOpen(),
--   setDevice(device?), banner(title, line, seconds?), toast(text, seconds?), untoast(text) (hides the toast if it
--   still shows `text`: the idle notice, cleared by any input) }.
-- No side effects on require.

export type Choice = { id: string, title: string, line: string, color: { number } }

export type Menu = {
	loading: (prepare: (() -> boolean)?) -> boolean,
	open: () -> (),
	close: () -> (),
	isOpen: () -> boolean,
	setDevice: (device: string?) -> (),
	banner: (title: string, line: string, seconds: number?) -> (),
	toast: (text: string, seconds: number?) -> (),
	untoast: (text: string) -> (),
}

local PlayMenu = {}

local InputMap = require("../Input/InputMap")
local Import = require("../Import")
local MoveDiag = Import.shared("Movement/MoveDiag") :: typeof(require("../../shared/Movement/MoveDiag"))
local MoveDiagPanel = require("./MoveDiagPanel")
local MinigameUI = require("./MinigameUI")
local Conduct = Import.shared("Reputation/Conduct") :: typeof(require("../../shared/Reputation/Conduct"))

PlayMenu.CHOICES = table.freeze({
	{
		id = "rodent",
		title = "Spicy Rodent",
		line = "Climb, pounce and bite people. Watch out for cars and kicks.",
		color = { 200, 60, 40 },
	},
	{ id = "squirrel", title = "Squirrel", line = "Run the trees, poles, wires and roofs.", color = { 150, 100, 60 } },
	{
		id = "townsperson",
		title = "Townsperson",
		line = "Walk the town. Kick the rodent with F if it gets close.",
		color = { 70, 120, 170 },
	},
	{
		id = "police",
		title = "Police",
		line = "Your patrol car is parked right next to you: press E to get in.",
		color = { 40, 60, 140 },
	},
	-- owner D30: in the Police drone's place; the hospital's teal (never a red cross on white)
	{
		id = "doctor",
		title = "Doctor",
		line = "Drive the ambulance and bring bite victims to the hospital.",
		color = { 30, 140, 140 },
	},
} :: { Choice })

local CLIMB = {
	"WASD  run (the camera sets the direction)",
	"Shift  sprint",
	"W into a tree, pole or downspout  climb it",
	"A / D  choose the way at a fork",
	"Space  leap   ·   Q  drop   ·   E  grab",
	"G (pad R1, the TRICK button)  mid-jump: a twist and a burst the way you face, then aim the rest of the jump with the mouse",
	"   (pad: right stick; touch: drag from the button) up to 30 degrees either way; up a little further, down sooner",
	"G as you land  a barrel roll that keeps your speed",
}

-- The menu's money and reputation line (the player attributes Cents and Reputation, written by the server).
function PlayMenu.standingLine(attrs: { [string]: any }): string
	local cents, rep = attrs.Cents, attrs.Reputation
	return Conduct.menuLine(if type(cents) == "number" then cents else nil, if type(rep) == "number" then rep else nil)
end

-- The help panel's lines for a role and device (device: nil | "vehicle" | "drone"); `owner`: the place's owner also
-- gets the line for the movement diagnostics panel (UI/MoveDiagPanel, Shared/Movement/MoveDiag.HELP).
function PlayMenu.helpLines(role: string?, device: string?, owner: boolean?): { string }
	if device == "vehicle" then
		return {
			"W  gas   ·   S  brake / reverse",
			"A / D  steer",
			"Space  handbrake",
			"V  inside or outside view",
			"E  get out",
		}
	elseif device == "drone" then
		return {
			"WASD  fly",
			"Space  up   ·   Q or Ctrl  down",
			"Shift  boost",
			"E  land and get out",
		}
	end
	local lines: { string }
	if role == "rodent" then
		lines = table.clone(CLIMB)
		table.insert(lines, "Left click  pounce")
		table.insert(lines, "Touch a person  bite (+100 Power)")
		table.insert(lines, "Ctrl  stalk quietly")
		table.insert(lines, "N  night vision (only the Spicy Rodent has it)")
	elseif role == "squirrel" then
		lines = table.clone(CLIMB)
		table.insert(lines, "Left click  pounce")
	elseif role == "townsperson" or role == "police" or role == "drone" or role == "doctor" then
		lines = {
			"WASD  walk   ·   Shift  sprint",
			"Space  jump",
			"F  kick (hits the rodent or a squirrel in front of you)",
			"E  get into a car or the drone next to you",
			"V  first-person view",
		}
		if role == "doctor" then
			lines[4] = "E  take an ambulance parked on the hospital road"
			table.insert(lines, "A call shows on your screen: drive to the BITE VICTIM marker")
			table.insert(lines, "Stop beside the patient to load them, then stop at the hospital doors")
		end
	else
		lines = { "Pick who to play from the menu" }
	end
	if role ~= nil and device == nil then
		table.insert(lines, "Mouse  look around   ·   wheel  zoom")
		table.insert(lines, "I  invert look up/down   ·   Alt  free the cursor")
	end
	table.insert(lines, "M  menu   ·   Esc > Reset  if you get stuck")
	if owner then
		table.insert(lines, MoveDiag.HELP)
	end
	return lines
end

-- The line under the status for a player whose body the Spicy Rodent bit (the player attribute
-- Infected, written by Server/Boot/Game from the infection service): what is wrong and what to do,
-- on screen for as long as it is true. nil when there is nothing to say.
PlayMenu.SICK = table.freeze({
	infected = "INFECTED  ·  Walk into the hospital to be cured",
	symptoms = "INFECTED, RED EYES  ·  Walk into the hospital to be cured",
	treating = "BEING TREATED  ·  Stay inside the hospital",
}) :: { [string]: string }
-- the same with the way known: the distance and direction take the place of "to be cured"
local SICK_WAY: { [string]: string } = {
	infected = "INFECTED  ·  Walk into the hospital: ",
	symptoms = "INFECTED, RED EYES  ·  Walk into the hospital: ",
}

export type Way = { dist: number, words: string }

-- a distance as a player reads it: whole studs close by, tens further off
local function studs(dist: number): number
	return if dist < 100 then math.floor(dist + 0.5) else math.floor(dist / 10 + 0.5) * 10
end

-- wayWords(dx, dz, lookX, lookZ): where a point (dx, dz) studs away lies for someone looking along
-- (lookX, lookZ), the camera's direction on the ground: "ahead", "to your right", "behind you" or
-- "to your left" (a quarter turn each). Roblox's axes: looking along -Z, +X is to the right.
function PlayMenu.wayWords(dx: number, dz: number, lookX: number, lookZ: number): string
	local turn = math.atan2(lookX * dz - lookZ * dx, lookX * dx + lookZ * dz)
	if math.abs(turn) <= math.pi / 4 then
		return "ahead"
	elseif math.abs(turn) >= 3 * math.pi / 4 then
		return "behind you"
	end
	return if turn > 0 then "to your right" else "to your left"
end

-- markerText(dist): what the marker over the hospital door says.
function PlayMenu.markerText(dist: number): string
	return `HOSPITAL\n{studs(dist)} studs`
end

function PlayMenu.sickLine(attrs: { [string]: any }, way: Way?): string?
	local status = attrs.Infected
	if type(status) ~= "string" then
		return nil
	end
	if way and SICK_WAY[status] then
		return `{SICK_WAY[status]}{studs(way.dist)} studs {way.words}`
	end
	return PlayMenu.SICK[status]
end

-- The status line from player attributes (PlayRole, Bites, Power, PowerStage, Health).
function PlayMenu.statusLine(attrs: { [string]: any }): string
	local role = attrs.PlayRole
	if role == "rodent" then
		return `SPICY RODENT   ·   Bites {attrs.Bites or 0}   ·   Power {attrs.Power or 0} ({attrs.PowerStage or "FERAL"})`
	elseif role == "squirrel" then
		return "SQUIRREL"
	elseif role == "townsperson" then
		return "TOWNSPERSON"
	elseif role == "police" then
		return "POLICE OFFICER"
	elseif role == "drone" then
		return "POLICE DRONE PILOT"
	elseif role == "doctor" then
		return "DOCTOR"
	end
	return "No body yet: pick one from the menu"
end

-- D30: a doctor's call on screen (the player attribute DoctorJob: "called" | "enroute" | "loaded"). `line` is what
-- the line under the status says (the way to the goal follows it), `marker` the word over the goal.
PlayMenu.JOB = table.freeze({
	called = { line = "BITE VICTIM WAITING  ·  Take an ambulance (E) and drive there", marker = "BITE VICTIM" },
	enroute = { line = "BITE VICTIM  ·  Stop beside them to load them", marker = "BITE VICTIM" },
	loaded = { line = "PATIENT ABOARD  ·  Stop at the hospital doors", marker = "HOSPITAL" },
}) :: { [string]: { line: string, marker: string } }

function PlayMenu.jobLine(attrs: { [string]: any }, way: Way?): string?
	local job = attrs.DoctorJob
	local j = if type(job) == "string" then PlayMenu.JOB[job] else nil
	if j == nil then
		return nil
	end
	if way then
		return `{j.line}: {studs(way.dist)} studs {way.words}`
	end
	return j.line
end

function PlayMenu.jobMarkerText(job: string, dist: number): string
	local j = PlayMenu.JOB[job]
	return `{if j then j.marker else "HOSPITAL"}\n{studs(dist)} studs`
end

-- The UI scale for a viewport (pure): 1 on a 1280 x 720 screen or larger, down to 0.6 on a small one.
function PlayMenu.scaleFor(width: number, height: number): number
	return math.clamp(math.min(width / 1100, height / 680), 0.6, 1)
end

-- engine ------------------------------------------------------------------------------------------

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function corner(parent: Instance, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = parent
end

local function text(parent: Instance, props: { [string]: any }): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.TextColor3 = Color3.new(1, 1, 1)
	l.Font = Enum.Font.GothamMedium
	l.TextWrapped = true
	for k, v in props do
		(l :: any)[k] = v
	end
	l.Parent = parent
	return l
end

-- extras.onOptions: the menu's "Stock options" button (bottom right of the panel; Client/UI/StockOptionsUI)
function PlayMenu.start(onPick: (choice: string) -> (), extras: { onOptions: (() -> ())? }?): Menu
	local Players = game:GetService("Players")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local UIS = game:GetService("UserInputService")
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local gui = Instance.new("ScreenGui")
	gui.Name = "SpicyPlay"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 10
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	-- loading screen -----------------------------------------------------------------------------
	local loading = Instance.new("Frame")
	loading.Name = "Loading"
	loading.Size = UDim2.fromScale(1, 1)
	loading.BackgroundColor3 = Color3.fromRGB(34, 48, 36)
	loading.ZIndex = 50
	loading.Parent = gui
	text(loading, {
		Text = "SPICY RODENTS",
		Font = Enum.Font.GothamBlack,
		TextSize = 54,
		TextColor3 = Color3.fromRGB(255, 120, 70),
		Size = UDim2.new(1, -32, 0, 70),
		Position = UDim2.new(0, 16, 0.3, 0),
		ZIndex = 51,
	})
	text(loading, {
		Text = "First playable build: loading the town",
		TextSize = 22,
		Size = UDim2.new(1, -32, 0, 30),
		Position = UDim2.new(0, 16, 0.3, 74),
		ZIndex = 51,
	})
	local barBack = Instance.new("Frame")
	barBack.AnchorPoint = Vector2.new(0.5, 0)
	barBack.Position = UDim2.new(0.5, 0, 0.3, 130)
	barBack.Size = UDim2.new(0.6, 0, 0, 22)
	barBack.BackgroundColor3 = Color3.fromRGB(20, 26, 20)
	barBack.ZIndex = 51
	barBack.Parent = loading
	corner(barBack, 11)
	local bar = Instance.new("Frame")
	bar.Size = UDim2.fromScale(0, 1)
	bar.BackgroundColor3 = Color3.fromRGB(255, 150, 60)
	bar.ZIndex = 52
	bar.Parent = barBack
	corner(bar, 11)
	local stageLabel = text(loading, {
		Text = "Waiting for the server…",
		TextSize = 20,
		Size = UDim2.new(1, -32, 0, 56),
		Position = UDim2.new(0, 16, 0.3, 164),
		ZIndex = 51,
	})
	local elapsedLabel = text(loading, {
		Text = "",
		TextSize = 15,
		TextColor3 = Color3.fromRGB(190, 200, 190),
		Size = UDim2.new(1, -32, 0, 40),
		Position = UDim2.new(0, 16, 0.3, 222),
		ZIndex = 51,
	})

	-- help panel, status, menu button ------------------------------------------------------------
	local help = Instance.new("Frame")
	help.Name = "Help"
	help.AnchorPoint = Vector2.new(0, 1)
	help.Position = UDim2.new(0, 12, 1, -96)
	help.Size = UDim2.fromOffset(340, 40)
	help.AutomaticSize = Enum.AutomaticSize.Y
	help.BackgroundColor3 = Color3.new(0, 0, 0)
	help.BackgroundTransparency = 0.4
	help.Visible = false
	help.Parent = gui
	corner(help, 8)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 10), UDim.new(0, 10)
	pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 8), UDim.new(0, 8)
	pad.Parent = help
	local helpText = text(help, {
		Text = "",
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		RichText = true,
	})

	local status = text(gui, {
		Name = "Status",
		Text = "",
		Font = Enum.Font.GothamBold,
		TextSize = 20,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 52),
		Size = UDim2.new(0.7, 0, 0, 28),
		BackgroundTransparency = 0.45,
		BackgroundColor3 = Color3.new(0, 0, 0),
		Visible = false,
	})
	corner(status, 8)
	-- a bitten player's line, under the status (people have no health bar there)
	local sick = text(gui, {
		Name = "Sick",
		Text = "",
		Font = Enum.Font.GothamBold,
		TextSize = 17,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 84),
		Size = UDim2.new(0.9, 0, 0, 26),
		BackgroundTransparency = 0.25,
		BackgroundColor3 = Color3.fromRGB(120, 10, 10),
		Visible = false,
	})
	corner(sick, 8)
	local sickLimit = Instance.new("UISizeConstraint")
	sickLimit.MaxSize = Vector2.new(740, 26)
	sickLimit.Parent = sick
	-- the marker over the hospital door (shown while this player is infected; see the loop below)
	local marker = Instance.new("BillboardGui")
	marker.Name = "HospitalMarker"
	marker.AlwaysOnTop = true
	marker.LightInfluence = 0
	marker.ResetOnSpawn = false
	marker.Size = UDim2.fromOffset(150, 52)
	marker.Enabled = false
	local markerLabel = text(marker, {
		Text = "HOSPITAL",
		Font = Enum.Font.GothamBlack,
		TextSize = 18,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 0.2,
		BackgroundColor3 = Color3.fromRGB(170, 20, 20),
	})
	corner(markerLabel, 8)
	local markerAnchor = Instance.new("Part")
	markerAnchor.Name = "HospitalMarkerAnchor"
	markerAnchor.Anchored = true
	markerAnchor.CanCollide = false
	markerAnchor.CanQuery = false
	markerAnchor.CanTouch = false
	markerAnchor.Transparency = 1
	markerAnchor.Size = Vector3.new(1, 1, 1)
	marker.Adornee = markerAnchor
	local hpBack = Instance.new("Frame")
	hpBack.AnchorPoint = Vector2.new(0.5, 0)
	hpBack.Position = UDim2.new(0.5, 0, 0, 84)
	hpBack.Size = UDim2.fromOffset(300, 16)
	hpBack.BackgroundColor3 = Color3.fromRGB(40, 10, 10)
	hpBack.Visible = false
	hpBack.Parent = gui
	corner(hpBack, 8)
	local hp = Instance.new("Frame")
	hp.Size = UDim2.fromScale(1, 1)
	hp.BackgroundColor3 = Color3.fromRGB(90, 220, 90)
	hp.Parent = hpBack
	corner(hp, 8)
	local hpText = text(hpBack, {
		Text = "",
		TextSize = 13,
		Font = Enum.Font.GothamBold,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2,
	})

	local menuButton = Instance.new("TextButton")
	menuButton.Name = "MenuButton"
	menuButton.AnchorPoint = Vector2.new(1, 1)
	menuButton.Position = UDim2.new(1, -12, 1, -96)
	menuButton.Size = UDim2.fromOffset(130, 40)
	menuButton.BackgroundColor3 = Color3.fromRGB(255, 140, 60)
	menuButton.TextColor3 = Color3.new(1, 1, 1)
	menuButton.Font = Enum.Font.GothamBold
	menuButton.TextSize = 18
	menuButton.Text = "Menu (M)"
	menuButton.Visible = false
	menuButton.Parent = gui
	corner(menuButton, 10)

	-- banner and toast -----------------------------------------------------------------------------
	local banner = Instance.new("Frame")
	banner.AnchorPoint = Vector2.new(0.5, 0.5)
	banner.Position = UDim2.fromScale(0.5, 0.32)
	banner.Size = UDim2.fromOffset(620, 130)
	banner.BackgroundColor3 = Color3.fromRGB(120, 10, 10)
	banner.BackgroundTransparency = 0.15
	banner.Visible = false
	banner.ZIndex = 40
	banner.Parent = gui
	corner(banner, 14)
	local bannerTitle = text(banner, {
		Font = Enum.Font.GothamBlack,
		TextSize = 56,
		Size = UDim2.new(1, 0, 0, 70),
		Position = UDim2.fromOffset(0, 10),
		ZIndex = 41,
	})
	local bannerLine = text(banner, {
		TextSize = 20,
		Size = UDim2.new(1, -20, 0, 40),
		Position = UDim2.fromOffset(10, 80),
		ZIndex = 41,
	})
	local toast = text(gui, {
		Font = Enum.Font.GothamBold,
		TextSize = 22,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 108),
		Size = UDim2.new(0.9, 0, 0, 36),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 0.3,
		BackgroundColor3 = Color3.fromRGB(40, 20, 10),
		Visible = false,
		ZIndex = 30,
	})
	corner(toast, 10)
	local toastLimit = Instance.new("UISizeConstraint")
	toastLimit.MaxSize = Vector2.new(640, 200)
	toastLimit.Parent = toast
	local statusLimit = Instance.new("UISizeConstraint")
	statusLimit.MaxSize = Vector2.new(560, 28)
	statusLimit.Parent = status

	-- menu -------------------------------------------------------------------------------------------
	local menu = Instance.new("Frame")
	menu.Name = "Menu"
	menu.Size = UDim2.fromScale(1, 1)
	menu.BackgroundColor3 = Color3.new(0, 0, 0)
	menu.BackgroundTransparency = 0.45
	menu.Visible = false
	menu.ZIndex = 20
	menu.Parent = gui
	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(600, 520)
	panel.BackgroundColor3 = Color3.fromRGB(28, 34, 30)
	panel.ZIndex = 21
	panel.Parent = menu
	corner(panel, 16)
	local sizeLimit = Instance.new("UISizeConstraint")
	sizeLimit.MaxSize = Vector2.new(600, 520)
	sizeLimit.Parent = panel
	text(panel, {
		Text = "Who do you want to be?",
		Font = Enum.Font.GothamBlack,
		TextSize = 30,
		Size = UDim2.new(1, 0, 0, 50),
		Position = UDim2.fromOffset(0, 12),
		ZIndex = 22,
	})
	local list = Instance.new("Frame")
	list.BackgroundTransparency = 1
	list.Position = UDim2.fromOffset(24, 70)
	list.Size = UDim2.new(1, -48, 1, -140)
	list.ZIndex = 22
	list.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list
	local buttons: { TextButton } = {}
	for i, c in PlayMenu.CHOICES do
		local b = Instance.new("TextButton")
		b.Name = c.id
		b.LayoutOrder = i
		b.Size = UDim2.new(1, 0, 0, 66)
		b.BackgroundColor3 = rgb(c.color)
		b.AutoButtonColor = true
		b.Modal = true -- frees a first-person mouse while the menu is up
		b.Text = ""
		b.ZIndex = 23
		b.Parent = list
		corner(b, 12)
		text(b, {
			Text = c.title,
			Font = Enum.Font.GothamBlack,
			TextSize = 24,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, -24, 0, 30),
			Position = UDim2.fromOffset(16, 6),
			ZIndex = 24,
		})
		text(b, {
			Text = c.line,
			TextSize = 15,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = Color3.fromRGB(235, 235, 235),
			Size = UDim2.new(1, -24, 0, 22),
			Position = UDim2.fromOffset(16, 38),
			ZIndex = 24,
		})
		table.insert(buttons, b)
	end
	-- money and reputation, checkable here (owner D30), between the buttons and "Back to the game"
	local standing = text(panel, {
		Name = "Standing",
		Text = "",
		TextSize = 16,
		TextColor3 = Color3.fromRGB(235, 235, 220),
		Size = UDim2.new(1, -48, 0, 22),
		Position = UDim2.new(0, 24, 1, -84),
		ZIndex = 22,
	})
	local back = Instance.new("TextButton")
	back.AnchorPoint = Vector2.new(0.5, 1)
	back.Position = UDim2.new(0.5, 0, 1, -14)
	back.Size = UDim2.fromOffset(260, 44)
	back.BackgroundColor3 = Color3.fromRGB(80, 90, 80)
	back.TextColor3 = Color3.new(1, 1, 1)
	back.Font = Enum.Font.GothamBold
	back.TextSize = 18
	back.Text = "Back to the game"
	back.Modal = true -- frees the mouse while the menu is up
	back.ZIndex = 23
	back.Parent = panel
	corner(back, 10)
	-- Spicy Stock Options (owner D30): what they are, buying, and where home is
	local optionsButton: TextButton? = nil
	if extras and extras.onOptions then
		local ob = Instance.new("TextButton")
		ob.Name = "StockOptions"
		ob.AnchorPoint = Vector2.new(1, 1)
		ob.Position = UDim2.new(1, -16, 1, -14)
		ob.Size = UDim2.fromOffset(150, 44)
		ob.BackgroundColor3 = Color3.fromRGB(120, 92, 40)
		ob.TextColor3 = Color3.new(1, 1, 1)
		ob.Font = Enum.Font.GothamBold
		ob.TextSize = 16
		ob.Text = "Stock options"
		ob.Modal = true
		ob.ZIndex = 23
		ob.Parent = panel
		corner(ob, 10)
		optionsButton = ob
	end

	-- scale the fixed-size pieces down on small screens (a laptop browser window)
	local scales: { UIScale } = {}
	for _, target in { panel, banner, help, menuButton, hpBack } :: { GuiObject } do
		local sc = Instance.new("UIScale")
		sc.Parent = target
		table.insert(scales, sc)
	end
	local function rescale()
		local cam = workspace.CurrentCamera
		local v = if cam then cam.ViewportSize else Vector2.new(1280, 720)
		local k = PlayMenu.scaleFor(v.X, v.Y)
		for _, sc in scales do
			sc.Scale = k
		end
	end
	rescale()
	if workspace.CurrentCamera then
		workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
	end

	gui.Parent = playerGui
	marker.Parent = playerGui

	local device: string? = nil
	local isOpen = false
	-- the keys panel starts collapsed to one small line (owner, 2026-11-21: "collapse the black box with the text
	-- explaining the keys"); K or a click on it opens and closes it
	local keysOpen = false
	-- while a minigame's How-to-play card is up the keys panel is put away: the card stands on the same side and
	-- the panel showed through under it (D29); it comes back as it was when the card goes
	local underCard = false
	local toastToken, bannerToken = 0, 0
	local way: Way? = nil -- to the hospital door, while this player is infected (or to a doctor's call, wayJob)
	local wayJob = false -- D30: `way` leads to the doctor's call, not to the cure

	local function attrs(): { [string]: any }
		return player:GetAttributes()
	end
	local isOwner = MoveDiagPanel.isOwner(player) -- (the owner's help has the diagnostics key)

	local function refresh()
		local a = attrs()
		local role = a.PlayRole :: string?
		local lines = PlayMenu.helpLines(role, device, isOwner)
		local title = if device == "vehicle" and role == "doctor"
			then "Driving the ambulance"
			elseif device == "vehicle" then "Driving the patrol car"
			elseif device == "drone" then "Flying the police drone"
			else PlayMenu.statusLine(a)
		if keysOpen then
			helpText.Text = `<b>{title}</b>\n` .. table.concat(lines, "\n") .. "\n<i>K  hide these keys</i>"
			help.Size = UDim2.fromOffset(340, 40)
		else
			helpText.Text = "<b>Keys</b>  (K)"
			help.Size = UDim2.fromOffset(96, 34)
		end
		status.Text = PlayMenu.statusLine(a)
		-- (D30: a doctor's call first, in the hospital's teal; else a bitten player's line, in red)
		local jobText = PlayMenu.jobLine(a, if wayJob then way else nil)
		local sickText = jobText or PlayMenu.sickLine(a, if wayJob then nil else way)
		sick.Text = sickText or ""
		sick.BackgroundColor3 = if jobText then Color3.fromRGB(20, 110, 110) else Color3.fromRGB(120, 10, 10)
		sick.Visible = sickText ~= nil and not isOpen
		local h = a.Health :: number?
		hpBack.Visible = h ~= nil and not isOpen
		if h then
			hp.Size = UDim2.fromScale(math.clamp(h / 100, 0, 1), 1)
			hp.BackgroundColor3 = if h > 50
				then Color3.fromRGB(90, 220, 90)
				elseif h > 25 then Color3.fromRGB(240, 190, 60)
				else Color3.fromRGB(230, 60, 50)
			hpText.Text = `Health {h} / 100`
		end
		back.Visible = role ~= nil
		standing.Text = PlayMenu.standingLine(a)
	end
	player.AttributeChanged:Connect(refresh)

	local function checkCard()
		local shown = MinigameUI.cardShown()
		if shown ~= underCard then
			underCard = shown
			help.Visible = not isOpen and not underCard
		end
	end
	MinigameUI.watchCard(checkCard)

	-- the way to the hospital, four times a second while this player is infected and not yet inside
	task.spawn(function()
		local shown: string? = nil
		while gui.Parent do
			local sickStatus = player:GetAttribute("Infected")
			local door = workspace:GetAttribute("HospitalDoor")
			local job = player:GetAttribute("DoctorJob")
			local call = player:GetAttribute("DoctorCall")
			local cam = workspace.CurrentCamera
			local found: Way? = nil
			-- (D30: a doctor's call is marked first: the patient, then the hospital doors once they are aboard)
			local onJob = type(job) == "string" and typeof(call) == "Vector3"
			local target: Vector3? = if onJob
				then call
				elseif (sickStatus == "infected" or sickStatus == "symptoms") and typeof(door) == "Vector3" then door
				else nil
			if target and cam then
				local body = player.Character
				local root = if body then body.PrimaryPart else nil
				local from = if root then root.Position else cam.CFrame.Position
				local look = cam.CFrame.LookVector
				local dx, dz = target.X - from.X, target.Z - from.Z
				local dist = math.sqrt(dx * dx + dz * dz)
				found = { dist = dist, words = PlayMenu.wayWords(dx, dz, look.X, look.Z) }
				if markerAnchor.Parent == nil then
					markerAnchor.Parent = workspace
				end
				markerAnchor.Position = target + Vector3.new(0, 18, 0)
				markerLabel.Text = if onJob then PlayMenu.jobMarkerText(job, dist) else PlayMenu.markerText(dist)
				markerLabel.BackgroundColor3 = if onJob
					then Color3.fromRGB(20, 120, 120)
					else Color3.fromRGB(170, 20, 20)
			end
			way = found
			wayJob = onJob
			checkCard()
			marker.Enabled = found ~= nil and not isOpen
			local line = if onJob
				then PlayMenu.jobLine({ DoctorJob = job }, found)
				else PlayMenu.sickLine({ Infected = sickStatus }, found)
			if line ~= shown then
				shown = line
				refresh()
			end
			task.wait(0.25)
		end
	end)

	local self: Menu
	local function setOpen(open: boolean)
		isOpen = open
		menu.Visible = open
		help.Visible = not open and not underCard
		status.Visible = not open
		menuButton.Visible = not open
		refresh()
	end

	for i, b in buttons do
		local id = PlayMenu.CHOICES[i].id
		b.Activated:Connect(function()
			self.toast(`Getting your body: {PlayMenu.CHOICES[i].title}…`, 3)
			onPick(id)
		end)
	end
	back.Activated:Connect(function()
		setOpen(false)
	end)
	if optionsButton and extras and extras.onOptions then
		local onOptions = extras.onOptions
		optionsButton.Activated:Connect(function()
			setOpen(false)
			onOptions()
		end)
	end
	menuButton.Activated:Connect(function()
		setOpen(true)
	end)
	-- (a click or a tap on the keys panel toggles it: touch has no K)
	local helpTap = Instance.new("TextButton")
	helpTap.Name = "Toggle"
	helpTap.Text = ""
	helpTap.BackgroundTransparency = 1
	helpTap.Size = UDim2.fromScale(1, 1)
	helpTap.ZIndex = 5
	helpTap.Parent = help
	helpTap.Activated:Connect(function()
		keysOpen = not keysOpen
		refresh()
	end)
	UIS.InputBegan:Connect(function(io: InputObject, processed: boolean)
		if InputMap.ignore(io, processed) then
			return
		end
		if io.KeyCode == Enum.KeyCode.M and not loading.Visible then
			setOpen(not isOpen)
		elseif io.KeyCode == Enum.KeyCode.K and not loading.Visible and not isOpen then
			keysOpen = not keysOpen
			refresh()
		end
	end)

	self = {
		loading = function(prepare: (() -> boolean)?): boolean
			local t0 = os.clock()
			local ready = false
			while true do
				local err = ReplicatedStorage:GetAttribute("BootError")
				local p = (ReplicatedStorage:GetAttribute("BootProgress") :: number?) or 0
				local st = (ReplicatedStorage:GetAttribute("BootStage") :: string?) or "Waiting for the server…"
				bar.Size = UDim2.fromScale(math.clamp(p * 0.9, 0, 1), 1)
				local secs = math.floor(os.clock() - t0)
				if err then
					stageLabel.TextColor3 = Color3.fromRGB(255, 110, 110)
					stageLabel.Text = `{st}\n{string.sub(tostring(err), 1, 200)}`
					elapsedLabel.Text = "Press F9 (Developer Console), open the Server tab and send the red lines."
					return false
				end
				stageLabel.Text = st
				elapsedLabel.Text = if secs < 90
					then `{secs} s   ·   the first start can take up to a minute`
					else `{secs} s   ·   still waiting for the server: if this does not move, press F9 and send the red lines (or leave and rejoin)`
				if ReplicatedStorage:GetAttribute("BootReady") == true then
					ready = true
					break
				end
				task.wait(0.1)
			end
			if ready and prepare then
				local t1 = os.clock()
				while not prepare() and os.clock() - t1 < 45 do
					bar.Size = UDim2.fromScale(0.9 + 0.1 * math.min(1, (os.clock() - t1) / 15), 1)
					stageLabel.Text = "Preparing the climbing routes on this computer"
					elapsedLabel.Text = `{math.floor(os.clock() - t0)} s`
					task.wait(0.1)
				end
			end
			bar.Size = UDim2.fromScale(1, 1)
			stageLabel.Text = "Ready"
			task.wait(0.3)
			loading.Visible = false
			setOpen(true)
			return true
		end,
		open = function()
			setOpen(true)
		end,
		close = function()
			setOpen(false)
		end,
		isOpen = function(): boolean
			return isOpen
		end,
		setDevice = function(d: string?)
			device = d
			refresh()
		end,
		banner = function(t: string, line: string, seconds: number?)
			bannerToken += 1
			local mine = bannerToken
			bannerTitle.Text = t
			bannerLine.Text = line
			banner.Visible = true
			task.delay(seconds or 3, function()
				if bannerToken == mine then
					banner.Visible = false
				end
			end)
		end,
		toast = function(t: string, seconds: number?)
			toastToken += 1
			local mine = toastToken
			toast.Text = t
			toast.Visible = true
			task.delay(seconds or 2.5, function()
				if toastToken == mine then
					toast.Visible = false
				end
			end)
		end,
		untoast = function(t: string)
			if toast.Visible and toast.Text == t then
				toastToken += 1
				toast.Visible = false
			end
		end,
	}
	refresh()
	return self
end

return PlayMenu
