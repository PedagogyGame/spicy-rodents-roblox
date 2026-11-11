--!strict
-- StarterPlayer.StarterPlayerScripts.Client.UI.SpeechBubbles
-- The speech bubbles over townspeople's heads (owner 2026-11-10: "make sure some of the people say,
-- oh my god, its one of those squirrels again, and various other phrases of concern"). The server
-- picks the line and when (Speech/SpeechRules) and writes two attributes on the body, Say then SayAt
-- (the server clock); this module draws a BillboardGui above the head for speech.showSecs from SayAt,
-- visible within speech.rangeSt (about 80 studs).
--   * One attribute-changed connection per body (on SayAt only: Say is read from that handler, so
--     the pair is always consistent), made when the body streams in and dropped when it leaves.
--   * A body that streams in carrying a line shows only what is left of it; a stale line (an old
--     stamp) is not shown at all.
--   * Bubbles are pooled: POOL BillboardGuis under PlayerGui, made once; when all are in use the one
--     that has been up longest is taken over.
-- No service access at require time (Lune requires this module; everything engine is inside start).
-- Interface: start(opts) -> stop(); slotFor(slots, now) -> index (pure); sizeFor(text) -> (width,
--   height) in pixels (pure); POOL, OFFSET

local Import = require("../Import")
local SpeechRules = Import.shared("Speech/SpeechRules") :: typeof(require("../../shared/Speech/SpeechRules"))
local Tunables = Import.shared("Config/Tunables") :: typeof(require("../../shared/Config/Tunables"))

export type Opts = {
	bodies: Instance, -- the folder whose child Models are bodies (workspace.Bodies)
	range: number?, -- studs (default speech.rangeSt)
	showSecs: number?, -- default speech.showSecs
	pool: number?, -- bubbles on screen at once (default POOL)
}

-- a slot of the pool: `expires` is the os.clock time its bubble comes down (0 = free)
export type Slot = { expires: number, since: number, body: any? }

local SpeechBubbles = {}

SpeechBubbles.POOL = 8
SpeechBubbles.OFFSET = 3.4 -- studs above the head's centre

local CHAR_PX = 8.6 -- average glyph width at the bubble's text size
local LINE_PX = 21
local MAX_WIDTH = 250 -- v5.4's bubbles were at most 230 px wide
local MIN_WIDTH = 70
local PAD = 18

-- slotFor(slots, now): the slot a new bubble takes: the first free one, else the one that has been up
-- longest (its speaker has had most of their say).
function SpeechBubbles.slotFor(slots: { Slot }, now: number): number
	local oldest, oldestSince = 1, math.huge
	for i, s in slots do
		if s.expires <= now then
			return i
		end
		if s.since < oldestSince then
			oldest, oldestSince = i, s.since
		end
	end
	return oldest
end

-- sizeFor(text): the bubble's pixel size: one line up to MAX_WIDTH, then it wraps (three lines at most
-- for the 60-character lines of Speech/Lines).
function SpeechBubbles.sizeFor(text: string): (number, number)
	local full = #text * CHAR_PX
	local inner = MAX_WIDTH - PAD
	local lines = math.clamp(math.ceil(full / inner), 1, 3)
	local width = if lines == 1 then math.max(MIN_WIDTH, math.ceil(full) + PAD) else MAX_WIDTH
	return width, lines * LINE_PX + 12
end

-- start(opts): draws the bubbles until the returned function is called.
function SpeechBubbles.start(opts: Opts): () -> ()
	local Players = game:GetService("Players")
	local RunService = game:GetService("RunService")
	local range = opts.range or Tunables.get("speech.rangeSt")
	local showSecs = opts.showSecs or Tunables.get("speech.showSecs")
	local poolSize = opts.pool or SpeechBubbles.POOL

	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	local holder = Instance.new("Folder")
	holder.Name = "SpeechBubbles"
	holder.Parent = playerGui

	local slots: { Slot } = {}
	local guis: { BillboardGui } = {}
	local labels: { TextLabel } = {}
	for i = 1, poolSize do
		local gui = Instance.new("BillboardGui")
		gui.Name = `Bubble{i}`
		gui.ResetOnSpawn = false
		gui.Enabled = false
		gui.AlwaysOnTop = true
		gui.LightInfluence = 0
		gui.MaxDistance = range
		gui.StudsOffsetWorldSpace = Vector3.new(0, SpeechBubbles.OFFSET, 0)
		gui.Size = UDim2.fromOffset(MAX_WIDTH, LINE_PX + 12)
		local label = Instance.new("TextLabel")
		label.Name = "Line"
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundColor3 = Color3.fromRGB(252, 248, 236) -- v5.4's cream card
		label.BackgroundTransparency = 0.05
		label.TextColor3 = Color3.fromRGB(34, 30, 28)
		label.Font = Enum.Font.GothamBold
		label.TextSize = 16
		label.TextWrapped = true
		label.Text = ""
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 10)
		corner.Parent = label
		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(60, 52, 46)
		stroke.Thickness = 1.5
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = label
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 8)
		pad.PaddingRight = UDim.new(0, 8)
		pad.Parent = label
		label.Parent = gui
		gui.Parent = holder
		slots[i] = { expires = 0, since = 0, body = nil }
		guis[i] = gui
		labels[i] = label
	end

	local function free(i: number)
		local s = slots[i]
		s.expires, s.body = 0, nil
		guis[i].Enabled = false
		-- clearing an Adornee is allowed by the engine; the type definitions say it is never nil
		guis[i].Adornee = nil :: any
	end

	local function show(body: Model)
		local text = body:GetAttribute(SpeechRules.ATTR.Say)
		local sayAt = body:GetAttribute(SpeechRules.ATTR.SayAt)
		if type(text) ~= "string" or text == "" or type(sayAt) ~= "number" then
			return
		end
		local left = SpeechRules.remaining(workspace:GetServerTimeNow(), sayAt, showSecs)
		if left <= 0 then
			return
		end
		local anchor = body:FindFirstChild("Head") or body.PrimaryPart
		if anchor == nil or not anchor:IsA("BasePart") then
			return
		end
		local now = os.clock()
		local index: number? = nil
		for i, s in slots do
			if s.body == body then
				index = i -- the same person speaking again keeps their bubble
				break
			end
		end
		local i = index or SpeechBubbles.slotFor(slots, now)
		local w, h = SpeechBubbles.sizeFor(text)
		labels[i].Text = text
		guis[i].Size = UDim2.fromOffset(w, h)
		guis[i].Adornee = anchor
		guis[i].Enabled = true
		slots[i].body = body
		slots[i].since = now
		slots[i].expires = now + left
	end

	local conns: { [Instance]: RBXScriptConnection } = {}
	local function add(child: Instance)
		if not child:IsA("Model") or conns[child] then
			return
		end
		local body = child :: Model
		conns[child] = body:GetAttributeChangedSignal(SpeechRules.ATTR.SayAt):Connect(function()
			show(body)
		end)
		show(body) -- a body that streams in mid-sentence shows what is left of the line
	end
	local function remove(child: Instance)
		local c = conns[child]
		if c then
			c:Disconnect()
			conns[child] = nil
		end
		for i, s in slots do
			if s.body == child then
				free(i)
			end
		end
	end

	local top: { RBXScriptConnection } = {}
	table.insert(top, opts.bodies.ChildAdded:Connect(add))
	table.insert(top, opts.bodies.ChildRemoved:Connect(remove))
	for _, child in opts.bodies:GetChildren() do
		add(child)
	end
	local acc = 0
	table.insert(
		top,
		RunService.Heartbeat:Connect(function(dt: number)
			acc += dt
			if acc < 0.1 then
				return
			end
			acc = 0
			local now = os.clock()
			for i, s in slots do
				if s.body ~= nil and s.expires <= now then
					free(i)
				end
			end
		end)
	)

	return function()
		for _, c in top do
			c:Disconnect()
		end
		for _, c in conns do
			c:Disconnect()
		end
		table.clear(conns)
		holder:Destroy()
	end
end

return SpeechBubbles
