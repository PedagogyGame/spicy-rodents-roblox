--!strict
-- Spike S8a helper: does a MeshPart written by Lune (MeshId + TextureID, no physics or mesh-size
-- data, as rbx-dom writes it) load with the right size and collide? Adds Workspace.S8Probe with one
-- MeshPart per CollisionFidelity to a copy of a built place; tools/cloud/tasks/art_probe.luau
-- inspects it after `save_place --place ci`.
--   lune run tools/anim/s8_probe_place.luau build/test.rbxl build/art/s8_probe.rbxl <meshAssetId> <textureAssetId> <sx> <sy> <sz>

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local args = process.args
if #args < 7 then
	print("usage: lune run tools/anim/s8_probe_place.luau <in.rbxl> <out.rbxl> <meshId> <textureId> <sx> <sy> <sz>")
	process.exit(2)
end
local game = roblox.deserializePlace(fs.readFile(args[1]))
local workspace = game:GetService("Workspace")
local size = roblox.Vector3.new(tonumber(args[5]) :: number, tonumber(args[6]) :: number, tonumber(args[7]) :: number)

local folder = roblox.Instance.new("Folder")
folder.Name = "S8Probe"
for i, fidelity in { "Box", "Hull", "Default", "PreciseConvexDecomposition" } do
	local part = roblox.Instance.new("MeshPart")
	part.Name = `Lune{fidelity}`
	part.MeshId = `rbxassetid://{args[3]}`
	part.TextureID = `rbxassetid://{args[4]}`
	part.Size = size
	part.CollisionFidelity = (roblox.Enum.CollisionFidelity :: any)[fidelity]
	part.Anchored = true
	part.CFrame = roblox.CFrame.new(1000 + 20 * i, 500, 1100)
	part.Parent = folder
end
folder.Parent = workspace
fs.writeFile(args[2], roblox.serializePlace(game))
print(`wrote {args[2]} with Workspace.S8Probe ({#folder:GetChildren()} MeshParts)`)
