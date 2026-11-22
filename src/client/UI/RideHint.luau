--!strict
-- StarterPlayer.StarterPlayerScripts.Client.UI.RideHint
-- The small prompt by the town's shared little vehicles (owner D29: 3 golf carts, 2 mopeds, 5 electric scooters any
-- person may ride; Server/Actors/DeviceService marks them with the model attribute Shared). While this player is on foot
-- in a person's body, the nearest free one within REACH studs shows a little label over it: "E  ride" on a keyboard
-- ("Y  ride" on a gamepad: the same E as every vehicle, Possession/PossessionClient sends it); on a touch screen the label
-- is a RIDE button, and while riding one a GET OFF button sits above the jump button: a tap is the same E. Nothing for
-- a squirrel, the rodent, the other vehicles, or one someone is riding. Looked for four times a second (the ten models
-- in workspace.Vehicles; no per-frame work); one BillboardGui and one ScreenGui, made once.
-- Interface: REACH; pick(x, z, rides) -> index? (pure); words(kind, touch, pad) -> string (pure);
--   start(opts { request: () -> (), state: () -> State }) -> stop()
-- No side effects on require.

local Import = require("../Import")
local SharedRides = Import.shared("Vehicles/SharedRides") :: typeof(require("../../shared/Vehicles/SharedRides"))

local RideHint = {}

RideHint.REACH = 14 -- studs (the server takes E for the nearest vehicle within 16)
RideHint.EVERY = 0.25 -- seconds between looks

export type Candidate = { x: number, z: number, free: boolean }
export type State = { onFoot: boolean, riding: boolean, at: Vector3? }

-- pick(x, z, rides): the nearest free shared vehicle within REACH of (x, z), by its index in `rides`.
function RideHint.pick(x: number, z: number, rides: { Candidate }): number?
	local best, bestD = nil, RideHint.REACH * RideHint.REACH
	for i, r in rides do
		local d = (r.x - x) ^ 2 + (r.z - z) ^ 2
		if r.free and d <= bestD then
			best, bestD = i, d
		end
	end
	return best
end

-- words(kind, touch, pad): the label over it.
function RideHint.words(kind: string?, touch: boolean, pad: boolean): string
	if touch then
		return "RIDE"
	end
	local what = if kind then SharedRides.NAMES[kind] else nil
	return `{if pad then "Y" else "E"}  ride{if what then " the " .. what else ""}`
end

function RideHint.start(opts: { request: () -> (), state: () -> State }): () -> ()
	local Players = game:GetService("Players")
	local RunService = game:GetService("RunService")
	local UIS = game:GetService("UserInputService")
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui", 10)
	if playerGui == nil then
		return function() end
	end
	local touch = UIS.TouchEnabled and not UIS.KeyboardEnabled

	local hint = Instance.new("BillboardGui")
	hint.Name = "RideHint"
	hint.ResetOnSpawn = false
	hint.AlwaysOnTop = true
	hint.Size = UDim2.fromOffset(if touch then 96 else 150, if touch then 44 else 30)
	hint.StudsOffsetWorldSpace = Vector3.new(0, 2.5, 0)
	hint.MaxDistance = RideHint.REACH * 2
	hint.Active = touch
	hint.Enabled = false
	local label = Instance.new(if touch then "TextButton" else "TextLabel") :: any
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = Color3.fromRGB(32, 30, 40)
	label.BackgroundTransparency = 0.25
	label.TextColor3 = Color3.fromRGB(250, 244, 228)
	label.TextSize = if touch then 18 else 15
	label.FontFace = Font.fromEnum(Enum.Font.GothamBold)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = label
	label.Parent = hint
	hint.Parent = playerGui

	-- on a touch screen, while riding: GET OFF above the stock jump button
	local screen = Instance.new("ScreenGui")
	screen.Name = "RideOff"
	screen.ResetOnSpawn = false
	screen.Enabled = false
	local off = Instance.new("TextButton")
	off.Text = "GET OFF"
	off.AnchorPoint = Vector2.new(1, 1)
	off.Position = UDim2.new(1, -30, 1, -175)
	off.Size = UDim2.fromOffset(96, 44)
	off.BackgroundColor3 = Color3.fromRGB(32, 30, 40)
	off.BackgroundTransparency = 0.25
	off.TextColor3 = Color3.fromRGB(250, 244, 228)
	off.TextSize = 16
	off.FontFace = Font.fromEnum(Enum.Font.GothamBold)
	local c2 = Instance.new("UICorner")
	c2.CornerRadius = UDim.new(0, 8)
	c2.Parent = off
	off.Parent = screen
	screen.Parent = if touch then playerGui else nil

	local conns: { RBXScriptConnection } = {}
	if touch then
		table.insert(conns, (label :: TextButton).Activated:Connect(opts.request))
		table.insert(conns, off.Activated:Connect(opts.request))
	end

	local acc = 0
	local candidates: { Candidate } = {}
	local models: { Model } = {}
	table.insert(
		conns,
		RunService.Heartbeat:Connect(function(dt: number)
			acc += dt
			if acc < RideHint.EVERY then
				return
			end
			acc = 0
			local s = opts.state()
			screen.Enabled = touch and s.riding
			local at = s.at
			if not s.onFoot or at == nil then
				hint.Enabled = false
				return
			end
			table.clear(candidates)
			table.clear(models)
			local folder = workspace:FindFirstChild("Vehicles")
			if folder then
				for _, m in folder:GetChildren() do
					local root = if m:IsA("Model") and m:GetAttribute("Shared") == true then m.PrimaryPart else nil
					if root then
						local seat = m:FindFirstChild("DriverSeat")
						local free = not (seat and seat:IsA("Seat") and seat.Occupant ~= nil)
						table.insert(candidates, { x = root.Position.X, z = root.Position.Z, free = free })
						table.insert(models, m :: Model)
					end
				end
			end
			local i = RideHint.pick(at.X, at.Z, candidates)
			if i == nil then
				hint.Enabled = false
				return
			end
			local m = models[i]
			local pad = UIS:GetLastInputType() == Enum.UserInputType.Gamepad1
			label.Text = RideHint.words(m:GetAttribute("VehicleKind") :: string?, touch, pad)
			hint.Adornee = m.PrimaryPart :: BasePart
			hint.Enabled = true
		end)
	)
	return function()
		for _, c in conns do
			c:Disconnect()
		end
		hint:Destroy()
		screen:Destroy()
	end
end

return RideHint
