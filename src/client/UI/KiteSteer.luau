--!strict
-- StarterPlayerScripts.Client.UI.KiteSteer
-- The kite's steering on its flier's screen (Shared/Items/KiteFlight; the server flies it: Server/Items/ItemWorld).
-- While the local player carries the KiteUp attribute (the server sets it when the kite goes up and clears it when
-- it starts down), the feet are planted (the default controls are off, as in a car) and:
--   A / D, the arrow keys, the left stick, or the touch arrows: lean the kite left or right (as the screen shows it:
--     a camera looking back at the flier swaps the sides);
--   W / S, the arrows, the stick, or the touch arrows: let the string out or reel it in.
-- What the keys say is sent to the server (ReplicatedStorage.KiteSteer) when it changes and again every RESEND
-- seconds while held, never more than RATE a second; the server clamps it and settles the kite when it stops.
-- Using the kite again (or putting it away) brings it down and gives the feet back.
-- Interface: start() -> Handle { flying() -> boolean, stop() }; axes(keys, stickX, stickY, touch) -> (x, y);
--   REMOTE; ATTRIBUTE
-- Engine only inside start(); no side effects on require.

local Import = require("../Import")
local KiteFlight = Import.shared("Items/KiteFlight") :: typeof(require("../../shared/Items/KiteFlight"))

local KiteSteer = {}

KiteSteer.REMOTE = "KiteSteer" -- (Server/Items/CornerStore.STEER_REMOTE)
KiteSteer.ATTRIBUTE = "KiteUp" -- (Server/Items/ItemWorld.KITE_ATTRIBUTE)

export type Touch = { left: boolean, right: boolean, up: boolean, down: boolean }

-- The two axes from the held keys (KeyCode names), the left stick (-1 .. 1, +Y up) and the touch arrows: each
-- -1, 0 or 1 (keys win over the stick; both ways held is nothing).
function KiteSteer.axes(keys: { [string]: boolean }, stickX: number, stickY: number, touch: Touch?): (number, number)
	local t = touch or { left = false, right = false, up = false, down = false }
	local function pair(neg: boolean, pos: boolean): number?
		if neg == pos then
			return nil
		end
		return if pos then 1 else -1
	end
	local x = pair(keys.A or keys.Left or t.left, keys.D or keys.Right or t.right)
	local y = pair(keys.S or keys.Down or t.down, keys.W or keys.Up or t.up)
	return x or KiteFlight.digital(stickX), y or KiteFlight.digital(stickY)
end

export type Handle = { flying: () -> boolean, stop: () -> () }

local KEYS = { "A", "D", "W", "S", "Left", "Right", "Up", "Down" }

local function controls(): any?
	local ok, mod = pcall(function()
		local ps = (game:GetService("Players").LocalPlayer :: any).PlayerScripts :: Instance
		return (require :: any)(ps:WaitForChild("PlayerModule", 5)):GetControls()
	end)
	return if ok then mod else nil
end

-- the touch arrows: four buttons at the bottom right, held to steer
local function touchArrows(touch: Touch): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "KiteSteer"
	gui.ResetOnSpawn = false
	local pad = Instance.new("Frame")
	pad.AnchorPoint = Vector2.new(1, 1)
	pad.Position = UDim2.new(1, -24, 1, -150)
	pad.Size = UDim2.fromOffset(180, 180)
	pad.BackgroundTransparency = 1
	pad.Parent = gui
	local function arrow(name: string, text: string, x: number, y: number)
		local b = Instance.new("TextButton")
		b.Name = name
		b.Text = text
		b.Size = UDim2.fromOffset(58, 58)
		b.Position = UDim2.fromOffset(x, y)
		b.BackgroundColor3 = Color3.fromRGB(40, 34, 30)
		b.BackgroundTransparency = 0.25
		b.TextColor3 = Color3.fromRGB(250, 240, 220)
		b.TextSize = 28
		b.FontFace = Font.fromEnum(Enum.Font.GothamBold)
		b.AutoButtonColor = true
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0.5, 0)
		c.Parent = b
		b.Parent = pad
		b.MouseButton1Down:Connect(function()
			(touch :: any)[name] = true
		end)
		b.MouseButton1Up:Connect(function()
			(touch :: any)[name] = false
		end)
		b.MouseLeave:Connect(function()
			(touch :: any)[name] = false
		end)
	end
	arrow("up", "▲", 61, 0)
	arrow("left", "◀", 0, 61)
	arrow("right", "▶", 122, 61)
	arrow("down", "▼", 61, 122)
	gui.Parent = (game:GetService("Players").LocalPlayer :: Player):WaitForChild("PlayerGui")
	return gui
end

function KiteSteer.start(): Handle
	local Players = game:GetService("Players")
	local RunService = game:GetService("RunService")
	local UserInputService = game:GetService("UserInputService")
	local player = Players.LocalPlayer :: Player
	local frame: RBXScriptConnection? = nil
	local gui: ScreenGui? = nil
	local ctl: any? = nil
	local touch: Touch = { left = false, right = false, up = false, down = false }
	local last: { x: number, y: number, at: number } = { x = 0, y = 0, at = -math.huge }

	local function remote(): RemoteEvent?
		local r = game:GetService("ReplicatedStorage"):FindFirstChild(KiteSteer.REMOTE)
		return if r and r:IsA("RemoteEvent") then r else nil
	end

	local function sample(): (number, number)
		if UserInputService:GetFocusedTextBox() ~= nil then
			return 0, 0 -- typing in the chat
		end
		local keys: { [string]: boolean } = {}
		for _, k in KEYS do
			keys[k] = UserInputService:IsKeyDown((Enum.KeyCode :: any)[k])
		end
		local sx, sy = 0, 0
		for _, s in UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1) do
			if s.KeyCode == Enum.KeyCode.Thumbstick1 then
				sx, sy = s.Position.X, s.Position.Y
			end
		end
		local x, y = KiteSteer.axes(keys, sx, sy, touch)
		local cam = workspace.CurrentCamera
		if cam then
			local look = cam.CFrame.LookVector
			x = KiteFlight.screenSide(x, look.X, look.Z)
		end
		return x, y
	end

	local function land()
		if frame then
			frame:Disconnect()
			frame = nil
		end
		if gui then
			gui:Destroy()
			gui = nil
		end
		if ctl then
			ctl:Enable()
			ctl = nil
		end
		touch.left, touch.right, touch.up, touch.down = false, false, false, false
		last = { x = 0, y = 0, at = -math.huge }
	end

	local function fly()
		if frame then
			return
		end
		ctl = controls()
		if ctl then
			ctl:Disable() -- the feet are planted while the kite is steered
		end
		if UserInputService.TouchEnabled then
			gui = touchArrows(touch)
		end
		frame = RunService.Heartbeat:Connect(function()
			local x, y = sample()
			local now = os.clock()
			if KiteFlight.send(last, x, y, now) then
				last = { x = x, y = y, at = now }
				local r = remote()
				if r then
					r:FireServer(x, y)
				end
			end
		end)
	end

	local function update()
		if player:GetAttribute(KiteSteer.ATTRIBUTE) == true then
			fly()
		else
			land()
		end
	end
	local watch = player:GetAttributeChangedSignal(KiteSteer.ATTRIBUTE):Connect(update)
	update()
	return {
		flying = function(): boolean
			return frame ~= nil
		end,
		stop = function()
			watch:Disconnect()
			land()
		end,
	}
end

return KiteSteer
