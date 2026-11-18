--!strict
-- tools/review/neighbourhood_shop: the Neighbourhood Shop in a review scene. The renderer draws parts; the
-- owner's interior and roof are uploaded Models the engine loads at boot (Server/Assets/ShopArt), so the scene
-- also lists the very FBX files that were uploaded (tools/blender/neighbourhood_shop/export_shop.py) with the
-- shop's pivot, and tools/review/art_render.py imports them into the same Blender scene.
-- Usage (repo root, after tools/review/export.luau wrote the town scene):
--   lune run tools/review/neighbourhood_shop.luau [--scene build/review/scene.json] [--out build/review/shop_scene.json]
--     [--rbxm build/Expansion_NeighbourhoodShop.rbxm] [--art build/art/neighbourhood_shop]
-- Then: python -I tools/review/render.py --scene build/review/shop_scene.json
--   --views docs/renders/neighbourhood_shop/views.json --out build/review/shop
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local addAttractions = require("./attractions_export")

local scenePath, out = "build/review/scene.json", "build/review/shop_scene.json"
local rbxm, art = "build/Expansion_NeighbourhoodShop.rbxm", "build/art/neighbourhood_shop"
local i = 1
while i <= #process.args do
	local a, v = process.args[i], process.args[i + 1]
	if a == "--scene" then
		scenePath = v
	elseif a == "--out" then
		out = v
	elseif a == "--rbxm" then
		rbxm = v
	elseif a == "--art" then
		art = v
	else
		error("unknown argument: " .. a)
	end
	i += 2
end
assert(fs.isFile(scenePath), `no {scenePath}: run lune run tools/review/export.luau first`)
assert(fs.isFile(rbxm), `no {rbxm}: run lune run tools/bake/neighbourhood_shop.luau first`)

local scene = serde.decode("json", fs.readFile(scenePath))
-- the town's trees are uploaded meshes the renderer can only draw as their bounding boxes (grey blocks that
-- would hide the street): they are left out of these pictures
local kept, trees = {}, 0
for _, p in scene.parts do
	if string.find(p.p, "%.Props%.Tree_%d+") then
		trees += 1
	else
		table.insert(kept, p)
	end
end
scene.parts = kept
print(`neighbourhood shop: {trees} tree parts left out (drawn as boxes otherwise)`)
-- the shell's parts, lamps, sign text and terrain carve (as the attraction buildings are added)
addAttractions(scene, rbxm)

local root = roblox.deserializeModel(fs.readFile(rbxm))[1]
local model = root:GetChildren()[1]
local pivot = model:GetAttribute("ArtPivot")
local p = pivot.Position
local X, Y, Z = pivot.XVector, pivot.YVector, pivot.ZVector
local rot = { X.X, Y.X, Z.X, X.Y, Y.Y, Z.Y, X.Z, Y.Z, Z.Z }
scene.art = {}
for _, name in { "shop", "roof" } do
	local file = `{art}/{name}.fbx`
	if fs.isFile(file) then
		table.insert(scene.art, { file = file, pos = { p.X, p.Y, p.Z }, rot = rot, group = "attractions" })
	else
		print(`neighbourhood shop: {file} missing (tools/blender/neighbourhood_shop/export_shop.py): drawn without it`)
	end
end
fs.writeFile(out, serde.encode("json", scene, false))
print(`neighbourhood shop: scene with the shell and {#scene.art} art files -> {out}`)
