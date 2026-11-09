--!strict
-- StarterPlayer.StarterPlayerScripts.S11Client (places/s11 only): the OS-1c drone HUD.
-- F flies or lands the test drone, N toggles night; the HUD shows height above the ground and
-- above sea level, the distance from the pilot's body, and the distance to each place the
-- checklist asks the owner to look at (the centre, the four corners, the off-road strip, the hill).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local client = script.Parent:WaitForChild("Client")
local Drone = (require :: any)(client:WaitForChild("Controllers"):WaitForChild("Drone"))
local net = ReplicatedStorage:WaitForChild("S11Net")
local toggle = net:WaitForChild("DroneToggle") :: RemoteEvent
local granted = net:WaitForChild("DroneGranted") :: RemoteEvent
local night = net:WaitForChild("NightToggle") :: RemoteEvent
local player = Players.LocalPlayer :: Player

local TARGETS = {
	{ "Centre", 700, -100 },
	{ "NW corner", -1400, 1040 },
	{ "NE corner", 2850, 1040 },
	{ "SW corner", -1400, -1210 },
	{ "SE corner", 2850, -1210 },
	{ "Off-road strip", 700, 1932 },
	{ "Test hill", 3375, -150 },
}

local stop: (() -> ())? = nil
local drone: Model? = nil

granted.OnClientEvent:Connect(function(flying: boolean)
	if stop then
		stop()
		stop = nil
	end
	drone = nil
	local camera = workspace.CurrentCamera
	if not flying then
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			camera.CameraSubject = humanoid
		end
		return
	end
	-- PersistentPerPlayer: the drone replicates to its pilot regardless of distance
	local m = workspace:WaitForChild(`Drone_{player.UserId}`, 10) :: Model?
	if m then
		drone = m
		stop = Drone.start(m)
	end
end)

UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.F then
		toggle:FireServer()
	elseif input.KeyCode == Enum.KeyCode.N then
		night:FireServer()
	end
end)

local gui = Instance.new("ScreenGui")
gui.Name = "S11Hud"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")
local text = Instance.new("TextLabel")
text.Size = UDim2.fromOffset(330, 250)
text.Position = UDim2.fromOffset(12, 60)
text.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
text.BackgroundTransparency = 0.2
text.TextColor3 = Color3.new(1, 1, 1)
text.Font = Enum.Font.Code
text.TextSize = 15
text.TextXAlignment = Enum.TextXAlignment.Left
text.TextYAlignment = Enum.TextYAlignment.Top
text.Parent = gui

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Include
params.FilterDescendantsInstances = { workspace.Terrain }

while true do
	local lines = { "S11 drone test   F: fly / land   N: night / day" }
	local m = drone
	local root = m and m.PrimaryPart
	if root then
		local p = root.Position
		local hit = workspace:Raycast(p, Vector3.new(0, -3000, 0), params)
		local above = if hit then math.floor(p.Y - hit.Position.Y) else -1
		table.insert(lines, `Height above ground: {above} st   (sea level: {math.floor(p.Y)})`)
		local body = player.Character and player.Character.PrimaryPart
		if body then
			table.insert(lines, `Distance from your body: {math.floor((p - body.Position).Magnitude)} st`)
		end
		table.insert(lines, "Distances (fly to each, look around):")
		for _, t in TARGETS do
			local d = math.floor(Vector3.new(p.X - t[2], 0, p.Z - t[3]).Magnitude)
			table.insert(lines, `  {t[1]}: {d} st{if d < 250 then "  <- here" else ""}`)
		end
	else
		table.insert(lines, "Press F to fly the drone.")
	end
	text.Text = table.concat(lines, "\n")
	task.wait(0.2)
end
