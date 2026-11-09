--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Input.InputMap
-- Bindings per role and the per-frame input sample every controller reads (BUILD_PLAN §1.4
-- Input/InputMap, §4.4 #5). Movement comes from the default PlayerModule's ControlModule move vector
-- (keyboard WASD/arrows, gamepad stick and the touch thumbstick alike), so mobile works with no extra
-- UI; verbs are edge-triggered keys, buttons and gamepad buttons. Tab and Esc stay reserved
-- [squirrel_abilities §26]. The tilt labyrinth's fixed bindings are recorded in LABYRINTH and never
-- remapped [brief v2 §13a].
-- Pure part: BINDINGS, LABYRINTH, HINTS(role), fromMoveVector(x, z). Engine part: start() -> Sampler
-- with sample(cameraYaw) -> Frame (edges cleared on read) and stop().
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

function InputMap.start(): Sampler
	local Players = game:GetService("Players")
	local UserInputService = game:GetService("UserInputService")

	local controls: any = nil
	task.spawn(function()
		local ps = Players.LocalPlayer:WaitForChild("PlayerScripts")
		local pm = ps:WaitForChild("PlayerModule", 10)
		if pm then
			local ok, mod = pcall(require, pm :: ModuleScript)
			if ok and mod and mod.GetControls then
				controls = mod:GetControls()
			end
		end
	end)

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
		if processed then
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

	local function isHeld(verb: string): boolean
		for n in nameSets[verb] do
			if held[n] then
				return true
			end
		end
		return false
	end

	self = {
		lastInputAt = os.clock(),
		sample = function(s: Sampler, cameraYaw: number): Frame
			local fw, side = 0, 0
			if controls then
				local mv = controls:GetMoveVector()
				fw, side = InputMap.fromMoveVector(mv.X, mv.Z)
			else
				fw = (if held.W or held.Up then 1 else 0) - (if held.S or held.Down then 1 else 0)
				side = (if held.D or held.Right then 1 else 0) - (if held.A or held.Left then 1 else 0)
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
