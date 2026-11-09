--!strict
-- places/s11/bake_skyline.luau (Lune): the S11 far-view test layers from the baked town.
-- Reads build/Town.rbxm (`lune run tools/bake/main.luau` first) and writes build/s11_skyline.rbxm:
--   Skyline  (Model, ModelStreamingMode Persistent): one massing box per building and structure lot
--            (the lot's greybox extruded to its kit height; D5 Skyline layer), no collision.
--   LampHeads (Model, Persistent): a Neon head every third road segment, 2 st beyond the road edge
--            and 16 st up (D30/S17 "emissive heads on the Skyline layer"), Neon reads at night.
-- Prints the counts and the footprint so docs/spikes/S11.md can quote them.
-- Usage (repo root): lune run places/s11/bake_skyline.luau [build/Town.rbxm] [build/s11_skyline.rbxm]
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local Instance = roblox.Instance
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local Color3 = roblox.Color3
local Enum = roblox.Enum

local input = process.args[1] or "build/Town.rbxm"
local output = process.args[2] or "build/s11_skyline.rbxm"
local town = roblox.deserializeModel(fs.readFile(input))[1]
local lots = town:FindFirstChild("Lots") or error("Town.Lots missing")
local roads = town:FindFirstChild("Roads") or error("Town.Roads missing")

local root = Instance.new("Folder")
root.Name = "S11Layers"
local skyline = Instance.new("Model")
skyline.Name = "Skyline"
skyline.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
skyline.Parent = root
local lamps = Instance.new("Model")
lamps.Name = "LampHeads"
lamps.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
lamps.Parent = root

local function box(name: string, cf: any, size: any, color: any, material: any, parent: any)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material
	p.Parent = parent
	return p
end

local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
local function extend(x: number, z: number)
	minX, maxX = math.min(minX, x), math.max(maxX, x)
	minZ, maxZ = math.min(minZ, z), math.max(maxZ, z)
end

local massing = 0
for _, lot in lots:GetChildren() do
	local cat = lot:GetAttribute("Category")
	local grey = lot:FindFirstChild("Greybox")
	if grey and (cat == "building" or cat == "structure") then
		local size = grey.Size
		local cf = grey.CFrame
		-- 0.5 st inset so the massing never z-fights the real greybox when both are streamed in
		box(
			lot.Name,
			cf,
			Vector3.new(math.max(1, size.X - 0.5), math.max(1, size.Y - 0.25), math.max(1, size.Z - 0.5)),
			if cat == "building" then Color3.fromRGB(176, 168, 156) else Color3.fromRGB(150, 140, 128),
			Enum.Material.SmoothPlastic,
			skyline
		)
		massing += 1
		extend(cf.Position.X - size.X / 2, cf.Position.Z - size.Z / 2)
		extend(cf.Position.X + size.X / 2, cf.Position.Z + size.Z / 2)
	end
end

local heads = 0
for _, road in roads:GetChildren() do
	local i = 0
	for _, seg in road:GetChildren() do
		if seg:IsA("BasePart") then
			i += 1
			extend(seg.CFrame.Position.X, seg.CFrame.Position.Z)
			if i % 3 == 1 then
				local cf = seg.CFrame
				local side = seg.Size.X / 2 + 2
				local pos = (cf * CFrame.new(side, 16, 0)).Position
				box(
					`Lamp{heads + 1}`,
					CFrame.new(pos),
					Vector3.new(1.2, 0.6, 1.2),
					Color3.fromRGB(255, 214, 140),
					Enum.Material.Neon,
					lamps
				)
				heads += 1
			end
		end
	end
end

fs.writeFile(output, roblox.serializeModel({ root }))
print(
	`s11 skyline: {massing} massing boxes, {heads} lamp heads; town extent x {math.floor(minX)}..{math.floor(maxX)} z {math.floor(
		minZ
	)}..{math.floor(maxZ)} st ({math.floor(maxX - minX)} x {math.floor(maxZ - minZ)}) -> {output}`
)
