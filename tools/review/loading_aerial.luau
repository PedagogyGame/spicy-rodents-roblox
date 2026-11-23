--!strict
-- tools/review/loading_aerial: the town scene for the loading screen's aerial picture (owner D39), with the real tree
-- art. export.luau draws a MeshPart as its bounding box, so the town's trees (Town.Props.Tree_*: the route-true trees'
-- uploaded meshes) would be grey and green blocks, and the D34 woods are not in the bake at all (Server/Assets/WoodsArt
-- puts them in at boot). This takes them out of the scene and lists the FBX files they were uploaded from instead,
-- placed as the engine places them, for tools/review/art_render.py:
--   * a town tree: its v2 Model (tools/blender/trees/build_trees.py --fbx, the same mesh digests as
--     data/art/trees_v2.json) pivoted onto its root (trees_v2 `pivot`, unrotated: Server/Assets/TreeArt.swap); a
--     planted copy (D32: a trunk route with no tree of its own, wearing a source tree's uploaded meshes, ArtAsset) wears
--     its source's Model moved as the bake moved the source's baked bark onto it;
--   * a woods tree: its kind's Model (tools/blender/trees/grove.py --fbx) at its foot, turned by its yaw and scaled
--     (WoodsArt.build: CFrame.new(x, y, z) * CFrame.Angles(0, yaw, 0), every part's offset and size times scale).
-- A tree whose FBX is missing keeps its boxes (with a note), so a partial build still renders.
-- Usage (repo root, after the bakes and lune run tools/review/export.luau):
--   lune run tools/review/loading_aerial.luau [--scene build/review/scene.json] [--out build/review/aerial_scene.json]
--     [--trees build/art/trees_v2] [--woods build/art/woods]
-- Then: python -I tools/review/render.py --scene build/review/aerial_scene.json --views docs/renders/loading/views.json
--   --out build/review/loading
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local scenePath, out = "build/review/scene.json", "build/review/aerial_scene.json"
local treeDir, woodsDir = "build/art/trees_v2", "build/art/woods"
local i = 1
while i <= #process.args do
	local a, v = process.args[i], process.args[i + 1]
	if a == "--scene" then
		scenePath = v
	elseif a == "--out" then
		out = v
	elseif a == "--trees" then
		treeDir = v
	elseif a == "--woods" then
		woodsDir = v
	else
		error("unknown argument: " .. a)
	end
	i += 2
end
assert(fs.isFile(scenePath), `no {scenePath}: run lune run tools/review/export.luau first`)

local scene = serde.decode("json", fs.readFile(scenePath))
local v2 = serde.decode("json", fs.readFile("data/art/trees_v2.json")).trees
local v1 = serde.decode("json", fs.readFile("data/art/trees.json")).trees
local byTrunk, byAsset = {}, {}
for _, t in v2 do
	byTrunk[t.trunkRoute] = t
end
for _, t in v1 do
	if t.assetId then
		byAsset[t.assetId] = t.index
	end
end

local IDENTITY = { 1, 0, 0, 0, 1, 0, 0, 0, 1 }
local function rotOf(cf: any): { number }
	local x, y, z = cf.XVector, cf.YVector, cf.ZVector
	return { x.X, y.X, z.X, x.Y, y.Y, z.Y, x.Z, y.Z, z.Z }
end

-- the baked town's trees: trunk route -> its Model (for a planted copy's bark and its source's)
local town = roblox.deserializeModel(fs.readFile("build/Town.rbxm"))[1]
local baked = {}
for _, m in (town:FindFirstChild("Props") :: any):GetChildren() do
	local n = tonumber(string.match(m.Name, "^Tree_(%d+)$"))
	if n then
		baked[n] = m
	end
end

scene.art = scene.art or {}
local swapped: { [string]: boolean } = {}
local notes = { trees = 0, copies = 0, woods = 0, missing = 0 }
for trunk, m in baked do
	local t = byTrunk[trunk]
	local entry = nil
	if t then
		local file = string.format("%s/tree_%03d.fbx", treeDir, t.index)
		if fs.isFile(file) then
			entry = { file = file, pos = t.pivot, rot = IDENTITY, group = "trees" }
			notes.trees += 1
		end
	else
		-- a planted copy: the source's Model, moved as the bake moved the source's bark onto this tree
		local src = byAsset[tostring(m:GetAttribute("ArtAsset"))]
		local st = if src then v2[src + 1] else nil
		local srcModel = if st then baked[st.trunkRoute] else nil
		local file = if st then string.format("%s/tree_%03d.fbx", treeDir, st.index) else ""
		if st and srcModel and fs.isFile(file) then
			local a, b = (m :: any):FindFirstChild("Bark"), (srcModel :: any):FindFirstChild("Bark")
			local move = a.CFrame * b.CFrame:Inverse()
			local cf = move * roblox.CFrame.new(st.pivot[1], st.pivot[2], st.pivot[3])
			local p = cf.Position
			entry = { file = file, pos = { p.X, p.Y, p.Z }, rot = rotOf(cf), group = "trees" }
			notes.copies += 1
		end
	end
	if entry then
		table.insert(scene.art, entry)
		swapped[`Tree_{trunk}`] = true
	else
		notes.missing += 1
		print(`loading aerial: Tree_{trunk} has no FBX here: drawn as its boxes`)
	end
end

local kept = {}
for _, p in scene.parts do
	local name = string.match(p.p, "%.Props%.(Tree_%d+)%.")
	if not (name and swapped[name] and p.s == "Box") then
		table.insert(kept, p)
	end
end
scene.parts = kept

-- the woods (generated/TreeShapes `woods`: kind, foot, yaw, scale)
local shapes = luau.load(fs.readFile("generated/TreeShapes.luau"), { debugName = "TreeShapes" })()
for _, w in (shapes.woods and shapes.woods.trees) or {} do
	local file = `{woodsDir}/{w.kind}.fbx`
	if fs.isFile(file) then
		local c, s, k = math.cos(w.yaw), math.sin(w.yaw), w.scale
		-- CFrame.Angles(0, yaw, 0) times the uniform scale, row-major
		local rot = { c * k, 0, s * k, 0, k, 0, -s * k, 0, c * k }
		table.insert(scene.art, { file = file, pos = { w.x, w.y, w.z }, rot = rot, group = "trees" })
		notes.woods += 1
	else
		notes.missing += 1
	end
end

fs.writeFile(out, serde.encode("json", scene, false))
print(
	`loading aerial: {notes.trees} town trees, {notes.copies} planted copies, {notes.woods} woods trees as FBX art; `
		.. `{notes.missing} without an FBX -> {out}`
)
