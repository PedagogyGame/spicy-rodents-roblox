--!strict
-- StarterPlayer.StarterPlayerScripts.Client.UI.AirTrickButton
-- The air trick's touch button (owner D17): on a touch screen a round TRICK button above the stock jump button, shown
-- only while the held squirrel is in the air with a move left to do (Shared/Movement/SquirrelMotor's rule: off the
-- ground and any rail, no pounce's window, no move playing, fewer than two this flight). A tap is the same as G or
-- gamepad R1: the Squirrel controller takes it on its next frame (consume). Keyboards and gamepads never see it.
-- Interface: shows(state) -> boolean (pure); LABEL; start() -> Handle { set(visible), consume() -> boolean, stop() }
-- No side effects on require.

local AirTrickButton = {}

AirTrickButton.LABEL = "TRICK"

-- Whether a press would do a move now (the motor's doTrick conditions), from the motor's state.
function AirTrickButton.shows(state: { [string]: any }): boolean
	return state.grounded ~= true
		and state.routeId == nil
		and state.bridge == nil
		and (state.attackWindow or 0) <= 0
		and (state.trickTime or 0) <= 0
		and (state.trickKind or 0) < 2
end

export type Handle = {
	set: (visible: boolean) -> (),
	consume: () -> boolean,
	stop: () -> (),
}

function AirTrickButton.start(): Handle
	local Players = game:GetService("Players")
	local pressed = false
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
	local conn = b.MouseButton1Down:Connect(function()
		pressed = true
	end)
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
		stop = function()
			conn:Disconnect()
			gui:Destroy()
		end,
	}
end

return AirTrickButton
