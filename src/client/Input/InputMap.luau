--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Input.InputMap
-- Bindings per role and the per-frame input sample every controller reads (BUILD_PLAN §1.4
-- Input/InputMap, §4.4 #5). Movement comes from the default PlayerModule's ControlModule move vector
-- (keyboard WASD/arrows, gamepad stick and the touch thumbstick alike), so mobile works with no extra
-- UI; verbs are edge-triggered keys, buttons and gamepad buttons. Tab and Esc stay reserved
-- [squirrel_abilities §26]. The tilt labyrinth's fixed bindings are recorded in LABYRINTH and never
-- remapped [brief v2 §13a].
-- Pure part: BINDINGS, LABYRINTH, HINTS(role), fromMoveVector(x, z). Engine part: start() -> Sampler
-- with sample(cameraYaw) -> Frame (edges cleared on read) and stop(); typing(), ignore(io, processed),
-- setCharacterControls(on).
-- Robustness (W1 client review): the default ControlModule binds WASD and Space through
-- ContextActionService, so those keys arrive with gameProcessed = true; keyboard input is therefore
-- accepted unless the player is typing (chat bar or a TextBox) or the Roblox menu is open, and held
-- keys are polled with IsKeyDown. Movement reads the ControlModule vector (touch, gamepad), then the
-- keyboard, then the left stick, so it keeps working while the ControlModule is disabled (vehicles and
-- the drone disable it so the seated or standing body does not walk or jump).
-- No side effects on require (services are looked up inside start()).

export type Frame = {
	fw: number, -- +1 forward
	side: number, -- +1 right
	up: number, -- drone: +1 up, -1 down
	sprint: boolean,
	focus: boolean, -- stalk (held)
	cameraYaw: number,
	leap: boolean, -- edges below are true for one sample only
	drop: boolean,
	grab: boolean,
	choose: number,
	pounce: boolean,
	jump: boolean,
	interact: boolean, -- enter / exit a vehicle
	toggleView: boolean, -- first-person toggle (V)
	handbrake: boolean, -- held
}

export type Sampler = {
	sample: (self: Sampler, cameraYaw: number) -> Frame,
	stop: (self: Sampler) -> (),
	lastInputAt: number,
}

local InputMap = {}

-- KeyCode names per verb (keyboard), and gamepad alternatives.
InputMap.BINDINGS = table.freeze({
	sprint = { "LeftShift", "RightShift", "ButtonL3" },
	focus = { "LeftControl", "C", "ButtonL2" },
	leap = { "Space", "ButtonA" },
	jump = { "Space", "ButtonA" },
	drop = { "Q", "ButtonB" },
	grab = { "E", "ButtonX" },
	chooseLeft = { "A", "Left", "DPadLeft" },
	chooseRight = { "D", "Right", "DPadRight" },
	pounce = { "MouseButton1", "ButtonR2" },
	interact = { "E", "ButtonY" },
	kick = { "F", "ButtonX" },
	toggleView = { "V", "ButtonR3" },
	up = { "Space", "ButtonA" },
	down = { "LeftControl", "Q", "ButtonB" },
	handbrake = { "Space", "ButtonA" },
})

InputMap.RESERVED = table.freeze({ "Tab", "Escape" })

-- Tilt labyrinth (brief v2 §13a): W/S tilt forward and back; Up and Down arrows tilt right and left,
-- Up is right. Fixed; never remapped.
InputMap.LABYRINTH = table.freeze({ forward = "W", back = "S", right = "Up", left = "Down" })

-- On-screen hints per controller (the owner-facing rule: always say what to press).
function InputMap.HINTS(role: string): string
	if role == "human" then
		return "WASD move · Shift run · Space jump · F kick · E get in a vehicle · V first person"
	elseif role == "squirrel" then
		return "WASD run · Shift sprint · Space leap · E grab a branch · Q drop · A/D pick a route · Ctrl stalk"
	elseif role == "quadruped" then
		return "WASD move · Shift run · Space jump"
	elseif role == "vehicle" then
		return "W/S drive and brake · A/D steer · Space handbrake · V view · E get out"
	elseif role == "drone" then
		return "WASD fly · Space up · Ctrl/Q down · Shift boost · E land"
	end
	return "Waiting for a body…"
end

-- ControlModule move vector (x right, z back) to the motors' fw/side.
function InputMap.fromMoveVector(x: number, z: number): (number, number)
	local fw, side = -z, x
	if math.abs(fw) < 0.15 then
		fw = 0
	end
	if math.abs(side) < 0.15 then
		side = 0
	end
	return math.clamp(fw, -1, 1), math.clamp(side, -1, 1)
end

-- engine helpers ------------------------------------------------------------------------------------

-- True while the player types in the chat bar or any TextBox (keys then belong to the text).
function InputMap.typing(): boolean
	local UIS = game:GetService("UserInputService")
	if UIS:GetFocusedTextBox() ~= nil then
		return true
	end
	local ok, focused = pcall(function()
		local cfg = game:GetService("TextChatService"):FindFirstChildOfClass("ChatInputBarConfiguration")
		return cfg ~= nil and (cfg :: any).IsFocused == true
	end)
	return ok and focused == true
end

-- Whether a gameplay key handler should skip this input. Keyboard keys count even when
-- gameProcessed (the ControlModule's ContextActionService bindings mark WASD and Space processed)
-- unless the player is typing or the Roblox menu is open; mouse, touch and gamepad input respect
-- gameProcessed (a click on a button is not a pounce).
function InputMap.ignore(io: InputObject, processed: boolean): boolean
	if InputMap.typing() then
		return true
	end
	local ok, menuOpen = pcall(function()
		return game:GetService("GuiService").MenuIsOpen
	end)
	if ok and menuOpen then
		return true
	end
	if io.UserInputType == Enum.UserInputType.Keyboard then
		return false
	end
	return processed
end

local controlsCache: any = nil
local function playerControls(timeout: number): any?
	if controlsCache then
		return controlsCache
	end
	local ok, mod = pcall(function()
		local ps = game:GetService("Players").LocalPlayer:WaitForChild("PlayerScripts", timeout)
		local pm = ps and ps:WaitForChild("PlayerModule", timeout)
		return if pm then (require :: any)(pm):GetControls() else nil
	end)
	if ok and mod then
		controlsCache = mod
	end
	return controlsCache
end

-- Enable or disable the default character controls (Humanoid walking and jumping). Bodies driven by
-- our own motors in a vehicle or the drone switch them off; a person on foot switches them on.
function InputMap.setCharacterControls(on: boolean)
	task.spawn(function()
		local c = playerControls(10)
		if c then
			pcall(function()
				if on then
					c:Enable()
				else
					c:Disable()
				end
			end)
		end
	end)
end

local KEY_FW = { "W", "Up" }
local KEY_BACK = { "S", "Down" }
local KEY_RIGHT = { "D", "Right" }
local KEY_LEFT = { "A", "Left" }

function InputMap.start(): Sampler
	local UserInputService = game:GetService("UserInputService")

	local controls: any = nil
	task.spawn(function()
		controls = playerControls(10)
	end)
	-- keyboard KeyCodes by name (MouseButton1 and gamepad names are not polled)
	local keyCodes: { [string]: Enum.KeyCode } = {}
	for _, item in Enum.KeyCode:GetEnumItems() do
		local v = item.Value
		if v >= 8 and v < 1000 then
			keyCodes[item.Name] = item
		end
	end
	local function keyDown(names: { string }): boolean
		for _, n in names do
			local code = keyCodes[n]
			if code and UserInputService:IsKeyDown(code) then
				return true
			end
		end
		return false
	end
	local function stick(): (number, number)
		local ok, x, y = pcall(function()
			for _, io in UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1) do
				if io.KeyCode == Enum.KeyCode.Thumbstick1 then
					return io.Position.X, io.Position.Y
				end
			end
			return 0, 0
		end)
		if ok then
			return x, y
		end
		return 0, 0
	end

	local nameSets: { [string]: { [string]: boolean } } = {}
	local bindings: { [string]: { string } } = InputMap.BINDINGS :: any
	for verb, names in bindings do
		local set: { [string]: boolean } = {}
		for _, n in names do
			set[n] = true
		end
		nameSets[verb] = set
	end
	local held: { [string]: boolean } = {}
	local edges: { [string]: boolean } = {}

	local self: Sampler
	local function codeName(input: InputObject): string
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			return "MouseButton1"
		end
		return input.KeyCode.Name
	end
	local began = UserInputService.InputBegan:Connect(function(input, processed)
		if InputMap.ignore(input, processed) then
			return
		end
		local n = codeName(input)
		held[n] = true
		self.lastInputAt = os.clock()
		for verb, set in nameSets do
			if set[n] then
				edges[verb] = true
			end
		end
	end)
	local ended = UserInputService.InputEnded:Connect(function(input)
		held[codeName(input)] = nil
	end)

	local typingNow = false
	local function isHeld(verb: string): boolean
		for n in nameSets[verb] do
			if held[n] then
				return true
			end
			-- poll the keyboard too: a key pressed while gameProcessed or before this sampler started
			local code = if typingNow then nil else keyCodes[n]
			if code and UserInputService:IsKeyDown(code) then
				return true
			end
		end
		return false
	end

	self = {
		lastInputAt = os.clock(),
		sample = function(s: Sampler, cameraYaw: number): Frame
			typingNow = InputMap.typing()
			local fw, side = 0, 0
			if controls then
				local ok, mv = pcall(function()
					return controls:GetMoveVector()
				end)
				if ok and typeof(mv) == "Vector3" then
					fw, side = InputMap.fromMoveVector(mv.X, mv.Z)
				end
			end
			if fw == 0 and side == 0 and not typingNow then
				fw = (if keyDown(KEY_FW) then 1 else 0) - (if keyDown(KEY_BACK) then 1 else 0)
				side = (if keyDown(KEY_RIGHT) then 1 else 0) - (if keyDown(KEY_LEFT) then 1 else 0)
			end
			if fw == 0 and side == 0 then
				local x, y = stick()
				fw, side = InputMap.fromMoveVector(x, -y)
			end
			if fw ~= 0 or side ~= 0 then
				s.lastInputAt = os.clock()
			end
			local f: Frame = {
				fw = fw,
				side = side,
				up = (if isHeld("up") then 1 else 0) - (if isHeld("down") then 1 else 0),
				sprint = isHeld("sprint"),
				focus = isHeld("focus"),
				cameraYaw = cameraYaw,
				leap = edges.leap == true,
				drop = edges.drop == true,
				grab = edges.grab == true,
				choose = (if edges.chooseRight then 1 else 0) - (if edges.chooseLeft then 1 else 0),
				pounce = edges.pounce == true,
				jump = edges.jump == true,
				interact = edges.interact == true,
				toggleView = edges.toggleView == true,
				handbrake = isHeld("handbrake"),
			}
			table.clear(edges)
			return f
		end,
		stop = function(_s: Sampler)
			began:Disconnect()
			ended:Disconnect()
		end,
	}
	return self
end

return InputMap
