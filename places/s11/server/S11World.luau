--!strict
-- ServerScriptService.S11.S11World (places/s11 only: the drone far-view test town, OS-1c)
-- Spike S11 (BUILD_PLAN §4.3 S11, D5, D6, D32, F-13): the Lune-baked town (Workspace.Town, SLIM
-- on building lots from Kits) plus the Skyline massing layer and emissive lamp heads
-- (Workspace.S11Layers, Persistent, from places/s11/bake_skyline.luau); at boot, Terrain through
-- WorldGen/TerrainBake: the v5.4 playable rectangle from World/Height, the near bands 2 km south
-- and west, a stand-in ridge to the north with a flat off-road strip beyond it (D32), and a test
-- hill to the east. Off-road marker posts are Atomic models about 1.9 km from the drone console,
-- so they only appear if streaming follows the drone. The drone is a device: a Model with
-- ModelStreamingMode PersistentPerPlayer for its pilot, client-owned, and the pilot's
-- Player.ReplicationFocus while flying; the pilot's body stays anchored at the console.
-- `writeTerrain`, `buildOffroad`, `census` and `makeDrone` run without players (the Luau Execution
-- smoke calls them); `start()` wires players and remotes (the place's Script calls it).
-- Interface: STATION, TARGETS, writeTerrain() -> stats, buildOffroad() -> number, census() -> table,
-- makeDrone(player?) -> Model, start()

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Height = (require :: any)(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("World"):WaitForChild("Height"))
local TerrainBake = (require :: any)(
	ServerScriptService:WaitForChild("Server"):WaitForChild("WorldGen"):WaitForChild("TerrainBake")
)

local S11World = {}

local SPU = Height.STUDS_PER_UNIT
local P = Height.PLAYABLE_U
local MIN_X, MAX_X, MIN_Z, MAX_Z = P.minX * SPU, P.maxX * SPU, P.minZ * SPU, P.maxZ * SPU
local RIDGE_Z = MAX_Z + 400 -- ridge crest
local STRIP_Z0, STRIP_Z1 = MAX_Z + 650, MAX_Z + 1000 -- the off-road strip beyond it
local HILL_X, HILL_Z, HILL_R, HILL_H = MAX_X + 500, -150, 450, 220

S11World.STATION = Vector3.new(700, 0, -100) -- y filled from the terrain at start
S11World.TARGETS = {
	{ name = "Centre", x = 700, z = -100 },
	{ name = "NW corner", x = -1400, z = 1040 },
	{ name = "NE corner", x = 2850, z = 1040 },
	{ name = "SW corner", x = -1400, z = -1210 },
	{ name = "SE corner", x = 2850, z = -1210 },
	{ name = "Off-road strip", x = 700, z = (STRIP_Z0 + STRIP_Z1) / 2 },
	{ name = "Test hill", x = HILL_X, z = HILL_Z },
}

local function smooth(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

local function edgeHeight(x: number, z: number): number
	return Height.at(math.clamp(x, MIN_X, MAX_X), math.clamp(z, MIN_Z, MAX_Z))
end

-- Everything outside the verbatim rectangle (stand-ins until terrain_extensions.json exists).
function S11World.outsideHeight(x: number, z: number): number
	local edge = edgeHeight(x, z)
	if z > MAX_Z then
		-- ridge: rises to +140 st at RIDGE_Z, falls to a flat strip 10 st above the edge
		local up = smooth((z - MAX_Z) / (RIDGE_Z - MAX_Z)) * 140
		local down = smooth((z - RIDGE_Z) / (STRIP_Z0 - RIDGE_Z)) * 130
		return edge + up - down
	end
	if x > MAX_X then
		local d = math.sqrt((x - HILL_X) ^ 2 + (z - HILL_Z) ^ 2)
		return edge + smooth(1 - d / HILL_R) * HILL_H + smooth((x - MAX_X) / 300) * 8
	end
	-- near bands (south and west), as in tests/engine/WorldBuild "bands"
	local d = math.max(MIN_X - x, MIN_Z - z, 0)
	local hills = 130
		+ 70 * math.sin(x * 0.0021 + 0.7) * math.cos(z * 0.0017 - 0.4)
		+ 25 * math.sin(x * 0.011 + z * 0.007)
	return edge + smooth((d - 150) / 900) * hills
end

function S11World.writeTerrain(): { [string]: any }
	local terrain = workspace.Terrain
	local t0 = os.clock()
	local grass, mud, ground = Enum.Material.Grass, Enum.Material.Mud, Enum.Material.Ground
	local stats: { [string]: any } = {}
	stats.town = TerrainBake.write(terrain, {
		rect = { minX = MIN_X, maxX = MAX_X, minZ = MIN_Z, maxZ = MAX_Z },
		heightAt = Height.at,
		waterTopAt = function(x: number, z: number): number?
			return if Height.insideRiverWater(x, z) then Height.WATER_Y else nil
		end,
		materialAt = function(x: number, z: number, _h: number): Enum.Material
			return if Height.insideRiverWater(x, z) then mud else grass
		end,
	})
	local band = 2000
	local outside = S11World.outsideHeight
	stats.west = TerrainBake.write(terrain, {
		rect = { minX = MIN_X - band, maxX = MIN_X, minZ = MIN_Z - band, maxZ = MAX_Z },
		heightAt = outside,
	})
	stats.south = TerrainBake.write(terrain, {
		rect = { minX = MIN_X, maxX = MAX_X + 1000, minZ = MIN_Z - band, maxZ = MIN_Z },
		heightAt = outside,
	})
	stats.north = TerrainBake.write(terrain, {
		rect = { minX = MIN_X - band, maxX = MAX_X + 1000, minZ = MAX_Z, maxZ = STRIP_Z1 },
		heightAt = outside,
		materialAt = function(_x: number, z: number, _h: number): Enum.Material
			return if z >= STRIP_Z0 then ground else grass
		end,
	})
	stats.east = TerrainBake.write(terrain, {
		rect = { minX = MAX_X, maxX = MAX_X + 1000, minZ = MIN_Z, maxZ = MAX_Z },
		heightAt = outside,
	})
	local voxels, chunks = 0, 0
	for _, s in stats do
		voxels += s.voxels
		chunks += s.chunks
	end
	stats.totalSeconds = os.clock() - t0
	stats.totalVoxels = voxels
	stats.totalChunks = chunks
	stats.extent = {
		minX = MIN_X - band,
		maxX = MAX_X + 1000,
		minZ = MIN_Z - band,
		maxZ = STRIP_Z1,
	}
	return stats
end

-- Six orange posts along the off-road strip: Atomic models far from the console.
function S11World.buildOffroad(): number
	local folder = workspace:FindFirstChild("Offroad") or Instance.new("Folder")
	folder.Name = "Offroad"
	folder.Parent = workspace
	local z = (STRIP_Z0 + STRIP_Z1) / 2
	local n = 0
	for x = -500, 2000, 500 do
		local m = Instance.new("Model")
		m.Name = `OffroadMarker_{x}`
		m.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
		local p = Instance.new("Part")
		p.Name = "Post"
		p.Anchored = true
		p.Size = Vector3.new(6, 60, 6)
		p.Material = Enum.Material.Neon
		p.Color = Color3.fromRGB(255, 120, 20)
		p.Position = Vector3.new(x, S11World.outsideHeight(x, z) + 30, z)
		p.Parent = m
		m.PrimaryPart = p
		m.Parent = folder
		n += 1
	end
	return n
end

-- What the place carries (for the smoke): lots, SLIM, Skyline, lamp heads, streaming modes.
function S11World.census(): { [string]: any }
	local out: { [string]: any } = { lots = 0, slim = 0, slimBuildings = 0, buildings = 0, skyline = 0, lampHeads = 0 }
	local town = workspace:FindFirstChild("Town")
	local lots = town and town:FindFirstChild("Lots")
	if lots then
		for _, lot in lots:GetChildren() do
			if lot:IsA("Model") then
				out.lots += 1
				local isBuilding = lot:GetAttribute("Category") == "building"
				if isBuilding then
					out.buildings += 1
				end
				if lot.LevelOfDetail == Enum.ModelLevelOfDetail.SLIM then
					out.slim += 1
					if isBuilding then
						out.slimBuildings += 1
					end
				end
			end
		end
	end
	local layers = workspace:FindFirstChild("S11Layers")
	local sky = layers and layers:FindFirstChild("Skyline") :: Model?
	local lamps = layers and layers:FindFirstChild("LampHeads") :: Model?
	out.skyline = if sky then #sky:GetChildren() else 0
	out.lampHeads = if lamps then #lamps:GetChildren() else 0
	out.skylineMode = if sky then sky.ModelStreamingMode.Name else "missing"
	out.lampMode = if lamps then lamps.ModelStreamingMode.Name else "missing"
	return out
end

-- The test drone. With a real Player: PersistentPerPlayer for that pilot, owned by them.
function S11World.makeDrone(player: Player?, at: Vector3?): Model
	local m = Instance.new("Model")
	m.Name = if player then `Drone_{player.UserId}` else "Drone_test"
	m.ModelStreamingMode = Enum.ModelStreamingMode.PersistentPerPlayer
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(3, 0.6, 3)
	root.Color = Color3.fromRGB(40, 40, 45)
	root.CanCollide = false
	root.CanTouch = false
	root.Parent = m
	m.PrimaryPart = root
	for i, off in { Vector3.new(2, 0.4, 2), Vector3.new(-2, 0.4, 2), Vector3.new(2, 0.4, -2), Vector3.new(-2, 0.4, -2) } do
		local r = Instance.new("Part")
		r.Name = `Rotor{i}`
		r.Size = Vector3.new(1.6, 0.2, 1.6)
		r.Color = Color3.fromRGB(220, 60, 50)
		r.CanCollide = false
		r.CanTouch = false
		r.Massless = true
		r.CFrame = root.CFrame * CFrame.new(off)
		r.Parent = m
		local w = Instance.new("WeldConstraint")
		w.Part0 = root
		w.Part1 = r
		w.Parent = r
	end
	m:PivotTo(CFrame.new(at or (S11World.STATION + Vector3.new(0, 8, 0))))
	m.Parent = workspace
	if player then
		m:AddPersistentPlayer(player)
		root:SetNetworkOwner(player)
		player.ReplicationFocus = root
	end
	return m
end

function S11World.start()
	local stats = S11World.writeTerrain()
	print(`[S11] terrain written in {math.floor(stats.totalSeconds * 10) / 10} s ({stats.totalVoxels} voxels)`)
	S11World.buildOffroad()
	local stationY = Height.at(S11World.STATION.X, S11World.STATION.Z)
	S11World.STATION = Vector3.new(S11World.STATION.X, stationY, S11World.STATION.Z)
	local spawn = workspace:FindFirstChild("Station") :: SpawnLocation?
	if spawn then
		spawn.Position = S11World.STATION + Vector3.new(0, 0.5, 0)
	end
	local console = workspace:FindFirstChild("DroneConsole") :: BasePart?
	if console then
		console.Position = S11World.STATION + Vector3.new(6, 2, 0)
	end
	Lighting.ClockTime = 14

	local net = Instance.new("Folder")
	net.Name = "S11Net"
	local toggle = Instance.new("RemoteEvent")
	toggle.Name = "DroneToggle"
	toggle.Parent = net
	local granted = Instance.new("RemoteEvent")
	granted.Name = "DroneGranted"
	granted.Parent = net
	local night = Instance.new("RemoteEvent")
	night.Name = "NightToggle"
	night.Parent = net
	net.Parent = ReplicatedStorage

	local drones: { [Player]: Model } = {}
	local function land(player: Player)
		local d = drones[player]
		if d then
			drones[player] = nil
			player.ReplicationFocus = nil
			d:Destroy()
		end
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			root.Anchored = false
		end
	end
	toggle.OnServerEvent:Connect(function(player: Player)
		if drones[player] then
			land(player)
			granted:FireClient(player, false)
			return
		end
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			root.Anchored = true -- the pilot stays at the console
		end
		local at = (if root then root.Position else S11World.STATION) + Vector3.new(0, 8, 0)
		drones[player] = S11World.makeDrone(player, at)
		granted:FireClient(player, true)
	end)
	night.OnServerEvent:Connect(function()
		Lighting.ClockTime = if Lighting.ClockTime > 6 and Lighting.ClockTime < 18 then 22 else 14
	end)
	Players.PlayerRemoving:Connect(land)
	print("[S11] drone far-view test ready: press F to fly, N for night")
end

return S11World
