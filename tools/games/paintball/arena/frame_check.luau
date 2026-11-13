--!strict
-- A playtest check of the paintball arena's frame cost (checklist PB-15: the arena adds under 1.5 ms a frame
-- beside the full town). It needs a client that draws, so it is NOT a cloud task: start Play in Studio on a place
-- built with build/Attractions.rbxm baked in (with the frame-rate cap off: Studio settings, Rendering, Framerate
-- Manager, so a frame's cost is not hidden under the 60 Hz wait), and paste this into the command bar on the CLIENT.
-- At each eye point it holds the camera still, waits SETTLE seconds and averages the frame time over HOLD seconds,
-- once with the arena's model in Workspace and once with it taken out of this client's world (it is put back at
-- the end; the server never knows). The difference is what the arena costs to draw from there:
--   town      an eye in the town TOWN studs from the building, looking at it (paint and lights off by distance)
--   street    at the lobby's front door, looking up at the tower
--   lobby     at the window onto the atrium
--   atrium    on the atrium's floor, looking up four storeys of galleries
--   gallery   on the second storey's gallery, looking across the atrium
--   corner    in a corner room of the top storey, a wall between the eye and most of the building
-- It reads the engine's own CPU and GPU frame times from Stats where they are offered, and the frame's length
-- otherwise. NOT YET RUN: the session that wrote it (2026-11-13) had no Studio.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")
local Workspace = game:GetService("Workspace")

local SETTLE, HOLD, TOWN = 1.5, 4, 300

local folder = (ReplicatedStorage:WaitForChild("Shared") :: Instance):FindFirstChild("Minigames") :: Instance
local Arena = (require :: any)((folder:FindFirstChild("Paintball") :: Instance):FindFirstChild("Arena"))
local model: Instance? = nil
for _, d in Workspace:GetDescendants() do
	if d:IsA("Model") and d.Name == Arena.MODEL then
		model = d
		break
	end
end
assert(model, `no {Arena.MODEL} in Workspace`)
local parent = (model :: Instance).Parent
local place = Arena.PLACE
local F = Arena.FLOOR_HEIGHT

-- (eye, looked at) in the arena's frame
local VIEWS: { { any } } = {
	{ "town", { 0, 20, Arena.HALF + TOWN }, { 0, 30, 0 } },
	{ "street", { 0, 6, 100 }, { 0, 40, 0 } },
	{ "lobby", { 24, 4.5, 63 }, { 20, 4.5, 0 } },
	{ "atrium", { 2, 4.5, 2 }, { -6, 50, -10 } },
	{ "gallery", { 18, 2 * F + 4.5, 0 }, { -18, 2 * F + 3, 0 } },
	{ "corner", { -50, 4 * F + 4.5, -50 }, { -40, 4 * F + 4, -40 } },
}

local function sample(): (number, number)
	local frames, total, cpu, gpu, n = 0, 0, 0, 0, 0
	local t0 = os.clock()
	while os.clock() - t0 < SETTLE do
		RunService.RenderStepped:Wait()
	end
	t0 = os.clock()
	while os.clock() - t0 < HOLD do
		total += RunService.RenderStepped:Wait()
		frames += 1
		local ok, c = pcall(function()
			return (Stats :: any).RenderCPUFrameTime
		end)
		local ok2, g = pcall(function()
			return (Stats :: any).RenderGPUFrameTime
		end)
		if ok and ok2 and typeof(c) == "number" and typeof(g) == "number" then
			cpu += c
			gpu += g
			n += 1
		end
	end
	if n > 0 then
		return cpu / n, gpu / n
	end
	return total / frames * 1000, 0
end

local camera = Workspace.CurrentCamera
local was = camera.CameraType
camera.CameraType = Enum.CameraType.Scriptable
local report: { string } = {}
for _, v in VIEWS do
	local ex, ey, ez = Arena.toWorld(place, v[2][1], v[2][2], v[2][3])
	local lx, ly, lz = Arena.toWorld(place, v[3][1], v[3][2], v[3][3])
	camera.CFrame = CFrame.lookAt(Vector3.new(ex, ey, ez), Vector3.new(lx, ly, lz))
	local player = Players.LocalPlayer
	if player then
		player:RequestStreamAroundAsync(Vector3.new(ex, ey, ez))
	end
	(model :: Instance).Parent = parent
	local withCpu, withGpu = sample();
	(model :: Instance).Parent = nil
	local withoutCpu, withoutGpu = sample();
	(model :: Instance).Parent = parent
	table.insert(
		report,
		string.format(
			"%-8s cpu %.2f ms (%.2f without the arena: +%.2f)  gpu %.2f ms (%.2f: +%.2f)",
			v[1],
			withCpu,
			withoutCpu,
			withCpu - withoutCpu,
			withGpu,
			withoutGpu,
			withGpu - withoutGpu
		)
	)
end
camera.CameraType = was
print("PaintballArena frame cost (PB-15: under 1.5 ms a frame beside the town)\n" .. table.concat(report, "\n"))
