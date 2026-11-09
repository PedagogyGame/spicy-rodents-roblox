--!strict
-- StarterPlayer.StarterPlayerScripts.S2Client (places/s2 only): the owner's possession test UI.
-- Starts the client possession stack (AnimationDriver over every body, PossessionClient with the
-- camera and controllers, Reset routed to recovery) and a debug panel: take a walking person,
-- take a running squirrel, swap, release, bubble fallback, plus the numbers OS-1a reads off
-- (handoff gap, request-to-control, input-to-move, server AI resume, resets routed).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local client = script.Parent:WaitForChild("Client")
local AnimationDriver = (require :: any)(client:WaitForChild("Animation"):WaitForChild("AnimationDriver"))
local PossessionClient = (require :: any)(client:WaitForChild("Possession"):WaitForChild("PossessionClient"))

local bodies = workspace:WaitForChild("Bodies")
AnimationDriver.start({ container = bodies })
local pc = PossessionClient.start({
	bodies = bodies,
	overview = { position = Vector3.new(0, 70, 130), lookAt = Vector3.zero },
})
local debugRemote = ReplicatedStorage:WaitForChild("PossessionNet"):WaitForChild("S2Debug") :: RemoteEvent

-- Bubble fallback: if the default bubble does not show over a non-Humanoid body, the panel's
-- toggle draws one with TextChatService:DisplayBubble on that body's Head.
TextChatService.MessageReceived:Connect(function(message: TextChatMessage)
	if not workspace:GetAttribute("BubbleFallback") then
		return
	end
	local source = message.TextSource
	local sender = source and Players:GetPlayerByUserId(source.UserId)
	local character = sender and sender.Character
	if character and character:FindFirstChildOfClass("Humanoid") == nil then
		local head = character:FindFirstChild("Head")
		if head then
			TextChatService:DisplayBubble(head :: BasePart, message.Text)
		end
	end
end)

-- panel
local gui = Instance.new("ScreenGui")
gui.Name = "S2Panel"
gui.ResetOnSpawn = false
gui.Parent = (Players.LocalPlayer :: Player):WaitForChild("PlayerGui")
local frame = Instance.new("Frame")
frame.Size = UDim2.fromOffset(250, 330)
frame.Position = UDim2.fromOffset(12, 60)
frame.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
frame.BackgroundTransparency = 0.15
frame.Parent = gui
local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 4)
layout.Parent = frame
local pad = Instance.new("UIPadding")
pad.PaddingLeft = UDim.new(0, 8)
pad.PaddingTop = UDim.new(0, 8)
pad.PaddingRight = UDim.new(0, 8)
pad.Parent = frame

local order = 0
local function label(text: string): TextLabel
	order += 1
	local l = Instance.new("TextLabel")
	l.LayoutOrder = order
	l.Size = UDim2.new(1, 0, 0, 18)
	l.BackgroundTransparency = 1
	l.TextColor3 = Color3.new(1, 1, 1)
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Font = Enum.Font.Gotham
	l.TextSize = 14
	l.Text = text
	l.Parent = frame
	return l
end
local function button(text: string, cmd: string): TextButton
	order += 1
	local b = Instance.new("TextButton")
	b.LayoutOrder = order
	b.Size = UDim2.new(1, 0, 0, 28)
	b.BackgroundColor3 = Color3.fromRGB(70, 110, 200)
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Font = Enum.Font.GothamBold
	b.TextSize = 14
	b.Text = text
	b.Parent = frame
	b.Activated:Connect(function()
		pc.markRequest()
		debugRemote:FireServer(cmd)
	end)
	return b
end

label("S2 possession test").Font = Enum.Font.GothamBold
button("1. Take a walking person", "human")
button("2. Take a running squirrel", "squirrel")
button("3. Swap (person <-> squirrel)", "swap")
button("4. Release (back to AI)", "release")
local bubbleButton = button("Bubble fallback: off", "bubble")
local driving = label("Driving: nothing")
local gap = label("Handoff gap: -")
local control = label("Request -> control: -")
local input = label("Input -> move: -")
local resume = label("AI resumed after release: -")
local resets = label("Resets routed: 0")

local function fmt(v: any, unit: string): string
	return if type(v) == "number" then `{math.floor(v * 100 + 0.5) / 100} {unit}` else "-"
end

task.spawn(function()
	while true do
		local m = pc.metrics
		driving.Text = `Driving: {m.actorId or "nothing"}`
		gap.Text = `Handoff gap: {fmt(m.gap, "st")}`
		control.Text = `Request -> control: {fmt(m.requestToControlMs, "ms")}`
		input.Text = `Input -> move: {fmt(m.inputToMoveMs, "ms")}`
		resume.Text = `AI resumed after release: {fmt(workspace:GetAttribute("S2LastResumeMs"), "ms")}`
		resets.Text = `Resets routed: {m.resets}`
		bubbleButton.Text = `Bubble fallback: {if workspace:GetAttribute("BubbleFallback") then "on" else "off"}`
		task.wait(0.25)
	end
end)
