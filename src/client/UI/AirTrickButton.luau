--!strict
-- StarterPlayer.StarterPlayerScripts.Client.UI.AirTrickButton
-- The air trick's touch button (owner D17, redone D18): on a touch screen a round TRICK button above the stock jump
-- button, shown while the held squirrel is in the air with a press that can still do something (Shared/Movement/
-- SquirrelMotor's doTrick: off the ground and any rail, no pounce's window, no roll already playing: mid-jump the wiggle
-- once a flight, close to a landing the roll). A tap is the same as G or gamepad R1: the Squirrel controller takes it on
-- its next frame (consume). Keeping the finger down and dragging from the button re-aims the jump: drag() gives the
-- finger's offset from where it pressed (pixels, +x right, +y down) while it stays down, and aimOf turns that into the
-- motor's aim (sideways up to the full turn at AIM_PX, up the screen further out, down nearer in). Keyboards and gamepads
-- never see it (their aim is the camera's turn: Controllers/Squirrel.aimOf).
-- Interface: shows(state) -> boolean (pure); aimOf(dx, dy, maxYaw) -> (yaw, reach) (pure); LABEL; AIM_PX;
--   start() -> Handle { set(visible), consume() -> boolean, drag() -> (dx?, dy?), stop() }
-- No side effects on require.

local AirTrickButton = {}

AirTrickButton.LABEL = "TRICK"
-- pixels of drag for the whole re-aim either way
AirTrickButton.AIM_PX = 90

-- Whether a press could do a move now (the motor's doTrick conditions in the air), from the motor's state.
function AirTrickButton.shows(state: { [string]: any }): boolean
	return state.grounded ~= true
		and state.routeId == nil
		and state.bridge == nil
		and (state.attackWindow or 0) <= 0
		and (state.trickKind or 0) ~= 1
end

-- The re-aim a drag of (dx, dy) pixels asks for: (radians either side, -1 in .. 1 out).
function AirTrickButton.aimOf(dx: number, dy: number, maxYaw: number): (number, number)
	local px = AirTrickButton.AIM_PX
	return math.clamp(dx / px, -1, 1) * maxYaw, math.clamp(-dy / px, -1, 1)
end

export type Handle = {
	set: (visible: boolean) -> (),
	consume: () -> boolean,
	drag: () -> (number?, number?),
	stop: () -> (),
}

function AirTrickButton.start(): Handle
	local Players = game:GetService("Players")
	local UIS = game:GetService("UserInputService")
	local pressed = false
	local finger: InputObject? = nil
	local from = Vector2.zero
	local now = Vector2.zero
	local gui = Instance.new("ScreenGui")
	gui.Name = "AirTrickButton"
	gui.ResetOnSpawn = false
	gui.Enabled = false
	local b = Instance.new("TextButton")
	b.Name = "Trick"
	b.Text = AirTrickButton.LABEL
	-- above the stock jump button (bottom right, about 90 px across, its centre ~ 95 px in and 95 px up)
	b.AnchorPoint = Vector2.new(1, 1)
	b.Position = UDim2.new(1, -40, 1, -175)
	b.Size = UDim2.fromOffset(78, 78)
	b.BackgroundColor3 = Color3.fromRGB(40, 34, 30)
	b.BackgroundTransparency = 0.25
	b.TextColor3 = Color3.fromRGB(250, 240, 220)
	b.TextSize = 18
	b.FontFace = Font.fromEnum(Enum.Font.GothamBold)
	b.AutoButtonColor = true
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0.5, 0)
	c.Parent = b
	b.Parent = gui
	local conns = {
		b.InputBegan:Connect(function(input: InputObject)
			if
				input.UserInputType == Enum.UserInputType.Touch
				or input.UserInputType == Enum.UserInputType.MouseButton1
			then
				pressed = true
				finger = input
				from = Vector2.new(input.Position.X, input.Position.Y)
				now = from
			end
		end),
		UIS.TouchMoved:Connect(function(input: InputObject)
			if input == finger then
				now = Vector2.new(input.Position.X, input.Position.Y)
			end
		end),
		UIS.TouchEnded:Connect(function(input: InputObject)
			if input == finger then
				finger = nil
			end
		end),
	}
	gui.Parent = (Players.LocalPlayer :: Player):WaitForChild("PlayerGui")
	return {
		set = function(visible: boolean)
			if gui.Enabled ~= visible then
				gui.Enabled = visible
			end
			if not visible then
				pressed = false
			end
		end,
		consume = function(): boolean
			local was = pressed
			pressed = false
			return was
		end,
		drag = function(): (number?, number?)
			if finger == nil then
				return nil, nil
			end
			return now.X - from.X, now.Y - from.Y
		end,
		stop = function()
			for _, conn in conns do
				conn:Disconnect()
			end
			gui:Destroy()
		end,
	}
end

return AirTrickButton
