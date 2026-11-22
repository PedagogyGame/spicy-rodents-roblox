--!strict
-- StarterPlayerScripts.Client.World.BranchNookClient
-- The held squirrel in the branch nooks (owner D34: "little nooks in the branches ... a little shift from running over
-- the nodules ... stash places off to the side and a little place to hangout, cozy!"; where they are:
-- Shared/World/BranchNooks). Controllers/Squirrel calls it once a frame; everything here is this player's screen:
--   * THE NODULES: BranchFeel's settle of the drawn body as the motor's point runs over a knot (draw(): lift and roll
--     for the root's CFrame; the camera follows the root). The motor never sees it.
--   * THE STASH: in a nook's cup (the motor's point within BranchNooks.C.stashReach of its end) "E  stash" shows and E
--     goes to the knot-hole (PlayNet.Stash with the nook's route id: Server/Foraging/BranchStash puts the nuts carried
--     in, or takes some out) instead of the motor's grab; on a touch screen the hint is a STASH button.
--   * SITTING (the seat rules: Shared/World/SeatRules): stopped in a cup or on a hangout's ledge (BranchNooks
--     seatAt), "R  sit" shows; R (the seat key; a pad's Y) or the SIT button sits the squirrel down: the motor gets no
--     keys (it stands still on its route, which the server's validator takes as it always has), and the drawn body
--     settles onto its haunches facing out of the crook. Getting up is Client/World/SeatGetUp's, as from any seat:
--     R again, Space, a pad's A or Y, a move of the stick or W A S D, or its STAND button (perch() and perchUp() are
--     its hooks); the press that gets it up is not also a leap or a grab (C.swallow), and for SeatRules.GRACE the
--     same key does not sit it down again.
--   * HINTS on the way: on a bough by a nook's or hangout's way in, "E  nook" / "E  hangout"; at the way out of one,
--     "E  back onto the branch" (the motor's own E takes the nearest route: Routes/Motion).
-- Interface: start(opts?) -> stop(); frame(state, f, registry, now?) -> boolean (seated: give the motor no keys; f's
--   grab, leap and the rest are cleared where they were the nook's); draw(state, registry, dt, yaw) -> (lift, roll,
--   drop, pitch, turn); perch() -> Place?; perchUp(now?) -> boolean; press(keyName) -> boolean; tap(which);
--   reset(); use(nooks, fire?); hints(); hintFor(nooks, registry, routeId, t, x, y, z, still) (pure); parseCounts(text);
--   WORDS; C.
-- Engine only inside start and the remote; frame/draw run headless (tests/unit/branch_nooks_client.spec.luau).
-- No side effects on require.

local Import = require("../Import")
local BranchFeel = Import.shared("Movement/BranchFeel") :: typeof(require("../../shared/Movement/BranchFeel"))
local BranchNooks = Import.shared("World/BranchNooks") :: typeof(require("../../shared/World/BranchNooks"))
-- (the exported types do not cross the Import cast)
type Nooks = typeof(BranchNooks.new(nil))
type Place = typeof(BranchNooks.new(nil).places[1])
local Data = Import.shared("Data") :: typeof(require("../../shared/Data"))
local SeatRules = Import.shared("World/SeatRules") :: typeof(require("../../shared/World/SeatRules"))

local BranchNookClient = {}

BranchNookClient.C = table.freeze({
	swallow = 0.2, -- seconds after getting up in which a leap, grab, drop, pounce or trick press is the get-up's own
	sitRate = 7, -- 1/s: how fast the drawn body settles onto its haunches (and back up)
	sitDrop = 0.2, -- studs the drawn body sinks when sat
	sitPitch = 0.42, -- radians nose-up when sat (sitting up)
	entrance = 1.4, -- studs along a bough from a nook's or hangout's way in that its hint shows
	stillFw = 0.05, -- a squirrel this still on its route may sit
	linger = 1.5, -- seconds a way in's hint stays up once passed (on the same bough)
	sitKeys = table.freeze({ R = true, ButtonY = true }), -- the seat keys (SeatRules: R, a pad's Y)
})
local C = BranchNookClient.C

BranchNookClient.WORDS = table.freeze({
	stash = "E  stash",
	sit = "R  sit",
	nook = "E  step into the nook",
	hangout = "E  step onto the ledge",
	back = "E  back onto the branch",
	stashButton = "STASH",
	sitButton = "SIT",
	stashCount = "E  stash (%d inside)",
})
local WORDS = BranchNookClient.WORDS

local nooks: Nooks? = nil
local feel = BranchFeel.new()
local seated: Place? = nil
local satAt, stoodAt, swallowUntil = -math.huge, -math.huge, -math.huge
local sitK = 0
local sitPressed, stashPressed = false, false
local hint: { stash: string?, sit: string?, line: string? } = {}
local lastLine: string?, lineUntil = nil, -math.huge
local stashCounts: { [number]: number } = {}
local fireStash: (routeId: number) -> () = function() end

local function lookup(): Nooks
	local n = nooks
	if n == nil then
		local ok, mod = pcall(function()
			return Data.default():module("BranchNooks")
		end)
		n = BranchNooks.new(if ok then mod :: any else nil)
		nooks = n
	end
	return n :: Nooks
end

-- use(nooks, fire?): another set of places and another way to send a stash press (headless: tests)
function BranchNookClient.use(n: Nooks?, fire: ((routeId: number) -> ())?)
	nooks = n
	if fire then
		fireStash = fire
	end
end

function BranchNookClient.reset()
	feel = BranchFeel.new()
	seated = nil
	satAt, stoodAt, swallowUntil = -math.huge, -math.huge, -math.huge
	sitK = 0
	sitPressed, stashPressed = false, false
	hint = {}
	lastLine, lineUntil = nil, -math.huge
end

-- the stash counts this player has (the server's NutStashes attribute: "route=n,route=n")
function BranchNookClient.parseCounts(text: any): { [number]: number }
	local out: { [number]: number } = {}
	if type(text) ~= "string" then
		return out
	end
	for id, n in string.gmatch(text, "(%d+)=(%d+)") do
		out[tonumber(id) :: number] = tonumber(n) :: number
	end
	return out
end

function BranchNookClient.perch(): Place?
	return seated
end

-- perchUp(): get up (SeatGetUp's hook); false when not sitting, or within SeatRules.REPEAT of sitting down (the same
-- press that sat it down reaches SeatGetUp too)
function BranchNookClient.perchUp(now: number?): boolean
	local t = now or os.clock()
	if seated == nil or t - satAt < SeatRules.REPEAT then
		return false
	end
	seated = nil
	stoodAt = t
	swallowUntil = t + C.swallow
	return true
end

-- press(keyName, now?): a key this module answers (R / a pad's Y: sit); true when it was taken
function BranchNookClient.press(keyName: string): boolean
	if C.sitKeys[keyName] then
		sitPressed = true
		return true
	end
	return false
end

-- tap(which): the touch buttons ("stash" | "sit")
function BranchNookClient.tap(which: string)
	if which == "stash" then
		stashPressed = true
	elseif which == "sit" then
		sitPressed = true
	end
end

-- the hints for a body at its motor state (pure over the places): what E and R would do here
function BranchNookClient.hintFor(
	n: Nooks,
	registry: any,
	routeId: number?,
	railT: number,
	x: number,
	y: number,
	z: number,
	still: boolean
): (Place?, Place?, string?)
	if routeId == nil then
		return nil, nil, nil
	end
	local p = n.place(routeId)
	local stash: Place? = nil
	if p and p.kind == "nook" and p.stash then
		local a = p.at
		local r = BranchNooks.C.stashReach
		if (x - a[1]) ^ 2 + (y - a[2]) ^ 2 + (z - a[3]) ^ 2 <= r * r then
			stash = p
		end
	end
	local sit = if still then n.seatAt(routeId, railT) else nil
	local line: string? = nil
	if p and p.kind ~= "spur" and railT <= 0.08 then
		line = if still then WORDS.back else nil
	elseif p == nil then
		local e = n.entranceNear(registry, routeId, railT, C.entrance)
		if e then
			line = if e.kind == "nook" then WORDS.nook else WORDS.hangout
		end
	end
	return stash, sit, line
end

-- frame(state, f, registry, now?): once a frame before the motor steps (f: the InputMap sample; cleared where a press
-- is the nook's). true while seated: the caller gives the motor no keys
function BranchNookClient.frame(state: any, f: any, registry: any, now: number?): boolean
	local t = now or os.clock()
	local n = lookup()
	if seated and state.routeId ~= (seated :: Place).route then
		seated = nil -- (moved off it: a correction, a teleport, a new body)
	end
	if t < swallowUntil then
		f.leap, f.grab, f.drop, f.pounce, f.trick = false, false, false, false, false
	end
	local still = math.abs(f.fw or 0) < C.stillFw and math.abs(f.side or 0) < C.stillFw and state.routeId ~= nil
	local stash, sit, line = BranchNookClient.hintFor(
		n,
		registry,
		state.routeId,
		state.railT,
		state.x,
		state.y,
		state.z,
		still or seated ~= nil
	)
	-- E in the cup: the knot-hole, not the motor's grab
	if stash and (f.grab or stashPressed) then
		f.grab = false
		fireStash(stash.route)
	end
	stashPressed = false
	-- R (or SIT): sit down where one may, not just after getting up
	if sitPressed and seated == nil and sit and t - stoodAt >= SeatRules.GRACE then
		seated = sit
		satAt = t
	end
	sitPressed = false
	if seated then
		f.leap, f.grab, f.drop, f.pounce, f.trick = false, false, false, false, false
	end
	local count = if stash then stashCounts[stash.route] or 0 else 0
	-- (a way in is passed in a moment at a run: its line stays up for C.linger)
	if line then
		lastLine, lineUntil = line, t + C.linger
	elseif t < lineUntil and state.routeId ~= nil and n.place(state.routeId) == nil then
		line = lastLine
	end
	hint = {
		stash = if stash then (if count > 0 then string.format(WORDS.stashCount, count) else WORDS.stash) else nil,
		sit = if sit and seated == nil then WORDS.sit else nil,
		line = if stash or sit or seated then nil else line,
	}
	return seated ~= nil
end

-- draw(state, registry, dt, yaw): what the drawn body adds this frame: the nodules' lift and roll, and the sitting
-- pose (drop, nose-up pitch, and the turn from `yaw` toward facing out of the crook), eased
function BranchNookClient.draw(
	state: any,
	registry: any,
	dt: number,
	yaw: number
): (number, number, number, number, number)
	local route = if state.routeId then registry:get(state.routeId) else nil
	local lift, roll = BranchFeel.step(feel, route, if route then state.railT else nil, dt)
	local target = if seated then 1 else 0
	sitK += (target - sitK) * (1 - math.exp(-C.sitRate * dt))
	if math.abs(sitK - target) < 1e-3 then
		sitK = target
	end
	local turn = 0
	local p = seated
	if p and sitK > 0 then
		local want = math.atan2(p.out[1], p.out[2])
		turn = math.atan2(math.sin(want - yaw), math.cos(want - yaw)) * sitK
	end
	return lift, roll, C.sitDrop * sitK, C.sitPitch * sitK, turn
end

-- the hint shown now (for the HUD and tests)
function BranchNookClient.hints(): { stash: string?, sit: string?, line: string? }
	return hint
end

-- start(): the remote, the seat keys, the stash counts and the hint buttons. -> stop()
function BranchNookClient.start(opts: { toast: ((text: string, seconds: number?) -> ())? }?): () -> ()
	local toast = if opts then opts.toast else nil
	local Players = game:GetService("Players")
	local UIS = game:GetService("UserInputService")
	local player = Players.LocalPlayer
	local conns: { RBXScriptConnection } = {}
	fireStash = function(routeId: number)
		local net = game:GetService("ReplicatedStorage"):FindFirstChild("PlayNet")
		local r = if net then net:FindFirstChild("Stash") else nil
		if r and r:IsA("RemoteEvent") then
			r:FireServer(routeId)
		elseif toast then
			toast("The stashes are not ready yet", 2)
		end
	end
	local function counts()
		stashCounts = BranchNookClient.parseCounts(player:GetAttribute("NutStashes"))
	end
	counts()
	table.insert(conns, player:GetAttributeChangedSignal("NutStashes"):Connect(counts))
	table.insert(
		conns,
		UIS.InputBegan:Connect(function(io: InputObject, _processed: boolean)
			if UIS:GetFocusedTextBox() ~= nil then
				return
			end
			BranchNookClient.press(io.KeyCode.Name)
		end)
	)
	-- the hint: a small line over the bottom of the screen, two buttons a touch screen can tap
	local screen = Instance.new("ScreenGui")
	screen.Name = "BranchNookHint"
	screen.ResetOnSpawn = false
	local bar = Instance.new("Frame")
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.Position = UDim2.new(0.5, 0, 1, -120)
	bar.Size = UDim2.fromOffset(360, 40)
	bar.BackgroundTransparency = 1
	bar.Parent = screen
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 10)
	layout.Parent = bar
	local function button(name: string, onTap: () -> ()): TextButton
		local b = Instance.new("TextButton")
		b.Name = name
		b.Size = UDim2.fromOffset(170, 38)
		b.BackgroundColor3 = Color3.fromRGB(46, 36, 28)
		b.BackgroundTransparency = 0.2
		b.TextColor3 = Color3.fromRGB(250, 240, 220)
		b.TextSize = 16
		b.Font = Enum.Font.GothamBold
		b.Visible = false
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 8)
		corner.Parent = b
		b.Parent = bar
		table.insert(conns, b.Activated:Connect(onTap))
		return b
	end
	local stashB = button("Stash", function()
		BranchNookClient.tap("stash")
	end)
	local sitB = button("Sit", function()
		BranchNookClient.tap("sit")
	end)
	local lineB = button("Line", function() end)
	lineB.Size = UDim2.fromOffset(240, 38)
	lineB.AutoButtonColor = false
	local okGui = pcall(function()
		screen.Parent = player:WaitForChild("PlayerGui", 10)
	end)
	local shown = ""
	table.insert(
		conns,
		game:GetService("RunService").Heartbeat:Connect(function()
			local h = hint
			local touch = UIS.TouchEnabled and not UIS.KeyboardEnabled
			local key = `{h.stash or ""}|{h.sit or ""}|{h.line or ""}|{touch}`
			if key == shown then
				return
			end
			shown = key
			stashB.Visible = h.stash ~= nil
			stashB.Text = if touch then WORDS.stashButton else h.stash or ""
			sitB.Visible = h.sit ~= nil
			sitB.Text = if touch then WORDS.sitButton else h.sit or ""
			lineB.Visible = h.line ~= nil and not touch
			lineB.Text = h.line or ""
		end)
	)
	local _ = okGui
	return function()
		for _, c in conns do
			c:Disconnect()
		end
		screen:Destroy()
		fireStash = function() end
		BranchNookClient.reset()
	end
end

return BranchNookClient
