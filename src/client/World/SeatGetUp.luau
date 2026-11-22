--!strict
-- StarterPlayerScripts.Client.World.SeatGetUp
-- Getting up from a seat (owner D32, THE GILDED ACORN: sitting down "traps you and you can't actually leave... make
-- sure that when we're sitting down, we can get back up with another button push"). A seat a person may get up from
-- carries Shared/World/SeatRules.STAND_ATTRIBUTE (the lounge's 33, which also carry LoungeClassic.SEAT_ATTRIBUTE; a
-- lawn chair). While the body this player holds sits on one, any of these asks the server to stand it up
-- (PlayNet.StandUp: Server/World/SeatStand, the lounge's seats through Server/Attractions/LoungeService):
--   * a stand key (SeatRules.KEYS: R, the lounge's seat key, pressed again; Space; the gamepad's A or Y), whatever
--     else took the press (a prompt, the jump), but not while a text box has the keys;
--   * moving (W, A, S, D, the stick, the touch thumbstick: Shared/Attractions/LoungeClassic.standUp);
--   * the STAND button shown while seated ("R  stand up" on a keyboard, "Y  stand up" on a gamepad: a click or a tap).
-- The client also sets Humanoid.Jump (the engine's own way off a Seat) in case the server's answer is slow. Asked at
-- most once every SeatRules.REPEAT seconds; once seated, the player is told how to get up (a toast, once per sitting).
-- A vehicle's seat or the sky lift's (no stand spot) is left alone: E gets out of a vehicle.
-- Interface: start(ctx) -> Handle { step(), press(keyName) -> boolean, stop() }; ctx = { current: () -> Model?,
--   heartbeat: boolean? (default true: step on RunService.Heartbeat), move: (() -> Vector3)? (default: the
--   PlayerModule's move vector), request: (() -> ())? (default: PlayNet.StandUp:FireServer()), toast: ((text) ->
--   ())?, now: (() -> number)? (default os.clock), gui: boolean? (default true: the STAND button), keys: boolean?
--   (default true: listen to UserInputService), perch: (() -> any?)?, perchUp: (() -> boolean)? }; seated(body) ->
--   Seat? (a seat its Humanoid sits on that it may get up from); WORDS
-- A squirrel sat in a branch nook or on a hangout's ledge (owner D34: World/BranchNookClient; a squirrel has no
-- Humanoid) is seated the same way: ctx.perch() is its place while it sits, and getting up (the same keys, a move, the
-- STAND button) calls ctx.perchUp() instead of asking the server: its sitting is its own screen's.
-- Engine only inside the functions; no side effects on require.

local Import = require("../Import")
local LoungeClassic =
	Import.shared("Attractions/LoungeClassic") :: typeof(require("../../shared/Attractions/LoungeClassic"))
local SeatRules = Import.shared("World/SeatRules") :: typeof(require("../../shared/World/SeatRules"))

local SeatGetUp = {}

export type Handle = { step: () -> boolean, press: (keyName: string) -> boolean, stop: () -> () }

SeatGetUp.WORDS = table.freeze({
	seated = "Seated. R, Space or a step gets you up.",
	button = "STAND",
	key = "R  stand up",
	pad = "Y  stand up",
})

local function moveVector(): () -> Vector3
	local ctl: any = nil
	return function(): Vector3
		if ctl == nil then
			pcall(function()
				local ps = (game:GetService("Players").LocalPlayer :: any).PlayerScripts :: Instance
				local pm = ps:FindFirstChild("PlayerModule")
				ctl = if pm then (require :: any)(pm):GetControls() else nil
			end)
		end
		local ok, v = pcall(function()
			return ctl:GetMoveVector()
		end)
		return if ok and typeof(v) == "Vector3" then v else Vector3.zero
	end
end

local function fireRemote()
	local net = game:GetService("ReplicatedStorage"):FindFirstChild("PlayNet")
	local r = if net then net:FindFirstChild(SeatRules.REMOTE) else nil
	if r and r:IsA("RemoteEvent") then
		r:FireServer()
	end
end

-- The seat this body sits on, when it is one a person may get up from (a stand spot, or a lounge seat).
function SeatGetUp.seated(body: Model?): any?
	local hum = if body then body:FindFirstChildOfClass("Humanoid") else nil
	local seat = if hum then hum.SeatPart else nil
	if seat == nil then
		return nil
	end
	if
		seat:GetAttribute(SeatRules.STAND_ATTRIBUTE) ~= nil
		or seat:GetAttribute(LoungeClassic.SEAT_ATTRIBUTE) ~= nil
	then
		return seat
	end
	return nil
end

-- The STAND button: above the touch screen's jump button, the keys' words on a keyboard or a gamepad.
local function button(onPress: () -> ()): (Instance?, TextButton?, { RBXScriptConnection })
	local player = game:GetService("Players").LocalPlayer
	local playerGui = if player then player:FindFirstChildOfClass("PlayerGui") else nil
	if playerGui == nil then
		return nil, nil, {}
	end
	local screen = Instance.new("ScreenGui")
	screen.Name = "SeatStand"
	screen.ResetOnSpawn = false
	screen.Enabled = false
	local b = Instance.new("TextButton")
	b.Name = "Stand"
	b.Text = SeatGetUp.WORDS.button
	b.AnchorPoint = Vector2.new(1, 1)
	b.Position = UDim2.new(1, -30, 1, -175)
	b.Size = UDim2.fromOffset(120, 44)
	b.BackgroundColor3 = Color3.fromRGB(32, 30, 40)
	b.BackgroundTransparency = 0.25
	b.TextColor3 = Color3.fromRGB(250, 244, 228)
	b.TextSize = 16
	b.Font = Enum.Font.GothamBold
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = b
	b.Parent = screen
	screen.Parent = playerGui
	return screen, b, { b.Activated:Connect(onPress) }
end

function SeatGetUp.start(ctx: {
	current: () -> Model?,
	heartbeat: boolean?,
	move: (() -> Vector3)?,
	request: (() -> ())?,
	toast: ((text: string) -> ())?,
	now: (() -> number)?,
	gui: boolean?,
	keys: boolean?,
	perch: (() -> any?)?,
	perchUp: (() -> boolean)?,
}): Handle
	local move: () -> Vector3 = if ctx.move then ctx.move else moveVector()
	local request: () -> () = ctx.request or fireRemote
	local now: () -> number = ctx.now or os.clock
	local UIS = game:GetService("UserInputService")
	local asked = -math.huge
	local told: any = nil -- the seat the player was last told about (once per sitting)
	local conns: { RBXScriptConnection } = {}

	-- a seat one may get up from, or the branch nook a squirrel sits in (ctx.perch)
	local function seatOf(body: Model?): any?
		local seat = SeatGetUp.seated(body)
		if seat == nil and ctx.perch then
			return ctx.perch()
		end
		return seat
	end

	-- ask to get up (true: asked now; false: seated nowhere one may get up from, or asked a moment ago)
	local function getUp(): boolean
		local body = ctx.current()
		local seat = seatOf(body)
		if seat == nil then
			return false
		end
		if SeatGetUp.seated(body) == nil and ctx.perchUp then
			-- (a squirrel in a branch nook: up on its own screen, no server; never a Humanoid's jump)
			return ctx.perchUp()
		end
		local t = now()
		if t - asked < SeatRules.REPEAT then
			return false
		end
		asked = t
		request()
		local hum = (body :: Model):FindFirstChildOfClass("Humanoid")
		if hum then
			hum.Jump = true -- (the engine's own way off a Seat, as the jump key)
		end
		return true
	end

	local screen, label: TextButton?
	if ctx.gui ~= false then
		local made
		screen, label, made = button(function()
			getUp()
		end)
		for _, c in made do
			table.insert(conns, c)
		end
	end

	-- one look a frame: seated somewhere one may get up from? the button, the toast once, and a move gets up
	local function step(): boolean
		local body = ctx.current()
		local seat = seatOf(body)
		if screen then
			(screen :: any).Enabled = seat ~= nil
		end
		if seat == nil then
			told = nil
			return false
		end
		if told ~= seat then
			told = seat
			if ctx.toast then
				ctx.toast(SeatGetUp.WORDS.seated)
			end
			if label then
				local touch = UIS.TouchEnabled and not UIS.KeyboardEnabled
				local okPad, last = pcall(function()
					return UIS:GetLastInputType()
				end)
				local pad = okPad and last == Enum.UserInputType.Gamepad1
				label.Text = if touch
					then SeatGetUp.WORDS.button
					elseif pad then SeatGetUp.WORDS.pad
					else SeatGetUp.WORDS.key
			end
		end
		local v = move()
		if LoungeClassic.standUp(v.X, v.Z, false) then
			return getUp()
		end
		return false
	end

	-- a key press (KeyCode name): a stand key gets a seated person up
	local function press(keyName: string): boolean
		if not SeatRules.standKey(keyName) then
			return false
		end
		return getUp()
	end

	if ctx.keys ~= false then
		table.insert(
			conns,
			UIS.InputBegan:Connect(function(io: InputObject, _processed: boolean)
				-- (whatever took the press: the seat prompt's R, the jump's Space; never while typing)
				if UIS:GetFocusedTextBox() ~= nil then
					return
				end
				press(io.KeyCode.Name)
			end)
		)
	end
	if ctx.heartbeat ~= false then
		table.insert(
			conns,
			game:GetService("RunService").Heartbeat:Connect(function()
				step()
			end)
		)
	end
	return {
		step = step,
		press = press,
		stop = function()
			for _, c in conns do
				c:Disconnect()
			end
			if screen then
				screen:Destroy()
			end
		end,
	}
end

return SeatGetUp
