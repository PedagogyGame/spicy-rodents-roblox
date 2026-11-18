--!strict
-- tools/review/corner_store: Pepper's Corner Store in a review scene. tools/review/export.luau already draws every
-- build/Expansion_F*.rbxm (the store is build/Expansion_F1.rbxm, tools/bake/corner_store.luau); this leaves out
-- the town's trees (uploaded meshes the renderer can only draw as grey boxes) and writes a second scene with the
-- store's roof, ceiling and parapet sign taken off, for the picture from above.
-- Usage (repo root, after tools/bake/corner_store.luau and tools/review/export.luau):
--   lune run tools/review/corner_store.luau [--scene build/review/scene.json] [--out build/review/store_scene.json]
--     [--cutaway build/review/store_cutaway.json]
-- Then: python -I tools/review/render.py --scene build/review/store_scene.json
--   --views docs/renders/corner_store/views.json --out build/review/store (and the cutaway scene with --set above)
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local scenePath, out, cutaway =
	"build/review/scene.json", "build/review/store_scene.json", "build/review/store_cutaway.json"
local i = 1
while i <= #process.args do
	local a, v = process.args[i], process.args[i + 1]
	if a == "--scene" then
		scenePath = v
	elseif a == "--out" then
		out = v
	elseif a == "--cutaway" then
		cutaway = v
	else
		error("unknown argument: " .. a)
	end
	i += 2
end
assert(fs.isFile(scenePath), `no {scenePath}: run lune run tools/review/export.luau first`)

local scene = serde.decode("json", fs.readFile(scenePath))
local kept, trees, store = {}, 0, 0
for _, p in scene.parts do
	if string.find(p.p, "%.Props%.Tree_%d+") then
		trees += 1
	else
		if string.find(p.p, "f1_corner_store", 1, true) then
			store += 1
		end
		table.insert(kept, p)
	end
end
assert(store > 0, "the store is not in the scene: run lune run tools/bake/corner_store.luau, then export.luau")
scene.parts = kept
fs.writeFile(out, serde.encode("json", scene, false))
print(`corner store: {store} store parts, {trees} tree parts left out -> {out}`)

-- the cutaway: no roof, ceiling, sign board or anything of the shell above the ceiling's underside
local CUT = { "Shell.Roof", "Shell.Ceiling", "Shell.SignBoard", "Shell.Canopy" }
local open = {}
local cut = 0
for _, p in kept do
	local drop = false
	if string.find(p.p, "f1_corner_store", 1, true) then
		for _, c in CUT do
			if string.find(p.p, c, 1, true) then
				drop = true
			end
		end
		-- the walls' parts above the ceiling (the parapet) go too: a part starting above floor + 11
		if string.find(p.p, ".Shell.", 1, true) and p.pos[2] - p.size[2] / 2 > 14.1 + 10.5 then
			drop = true
		end
	end
	if drop then
		cut += 1
	else
		table.insert(open, p)
	end
end
scene.parts = open
local texts = {}
for _, t in (scene.attractions and scene.attractions.texts or {}) :: { any } do
	if t.text ~= "PEPPER'S CORNER STORE" then
		table.insert(texts, t)
	end
end
if scene.attractions then
	scene.attractions.texts = texts
end
fs.writeFile(cutaway, serde.encode("json", scene, false))
print(`corner store: cutaway without {cut} roof and parapet parts -> {cutaway}`)
