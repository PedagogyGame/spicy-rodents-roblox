--!strict
-- tools/bake/editor_ground: a coarse grass skin under the town so Studio's EDITOR view is not a town
-- floating in the sky. Terrain only exists once the server writes it at boot (S6/D6); the server
-- destroys Workspace.EditorGround right after that (src/server/Boot/Game.luau), so this never
-- affects play. Non-colliding, non-queryable, one Part per 60-stud cell following World/Height.
-- Usage (repo root): lune run tools/bake/editor_ground.luau [--out build/EditorGround.rbxm]
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local Height = require("../../src/shared/World/Height")
local okExt, ext = pcall(require, "../../generated/TerrainExtensions")
if okExt then
	Height.configure(ext)
end

local out = "build/EditorGround.rbxm"
if process.args[1] == "--out" and process.args[2] then
	out = process.args[2]
end

local Instance, Vector3, Color3, Enum = roblox.Instance, roblox.Vector3, roblox.Color3, roblox.Enum
local CELL = 60 -- studs
local THICK = 6
local SINK = 0.6 -- top sits just below the true ground so lots never look buried
local clamp = Height.worldClamp()

local folder = Instance.new("Folder")
folder.Name = "EditorGround"
local count = 0
local x = clamp.minX
while x < clamp.maxX do
	local z = clamp.minZ
	while z < clamp.maxZ do
		local cx, cz = x + CELL / 2, z + CELL / 2
		-- the lowest of five samples keeps the skin under every lot in the cell
		local h = math.min(
			Height.at(cx, cz),
			Height.at(x + 2, z + 2),
			Height.at(x + CELL - 2, z + 2),
			Height.at(x + 2, z + CELL - 2),
			Height.at(x + CELL - 2, z + CELL - 2)
		)
		local water = Height.insideRiverWaterU(cx / 2.5, cz / 2.5)
		local p = Instance.new("Part")
		p.Name = "G"
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Locked = true
		p.Size = Vector3.new(CELL, THICK, CELL)
		p.Position = Vector3.new(cx, h - SINK - THICK / 2, cz)
		if water then
			p.Material = Enum.Material.Glass
			p.Color = Color3.fromRGB(64, 112, 120)
			p.Transparency = 0.2
		else
			p.Material = Enum.Material.Grass
			p.Color = Color3.fromRGB(106, 127, 63)
		end
		p.Parent = folder
		count += 1
		z += CELL
	end
	x += CELL
end
if not fs.isDir("build") then
	fs.writeDir("build")
end
fs.writeFile(out, roblox.serializeModel({ folder }))
print(
	`editor ground: {count} cells of {CELL} studs over x {clamp.minX}..{clamp.maxX} z {clamp.minZ}..{clamp.maxZ} -> {out}`
)
