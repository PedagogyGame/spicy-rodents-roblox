--!strict
-- tools/review/lounge_classic: THE GILDED ACORN (the 1940s lounge) in a review scene: the town scene plus the
-- lounge's bake (parts, lamps, sign text, terrain carve), as the attraction buildings are added.
-- Usage (repo root, after tools/review/export.luau wrote the town scene and tools/bake/lounge_classic.luau ran):
--   lune run tools/review/lounge_classic.luau [--scene build/review/scene.json] [--out build/review/lounge_scene.json]
--     [--rbxm build/Expansion_LoungeClassic.rbxm] [--cutaway] [--art build/art/lounge_classic]
--   --cutaway leaves out the lounge's ceiling, roof and everything else higher than CUT above the floor, for the
--   view from above into the room. --art draws the Blender pieces (tools/blender/lounge_classic/model.py: the very
--   FBX publish.py uploads, drawn by tools/review/art_render.py) and leaves out the baked parts they replace, as
--   Server/Assets/LoungeArt does in the engine once the Model has an id.
-- Then: python -I tools/review/render.py --scene build/review/lounge_scene.json
--   --views docs/renders/lounge_classic/views.json --out build/review/lounge
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local addAttractions = require("./attractions_export")

local scenePath, out, rbxm =
	"build/review/scene.json", "build/review/lounge_scene.json", "build/Expansion_LoungeClassic.rbxm"
local cutaway = false
local artDir: string? = nil
local CUT = 12.1 -- studs above the floor (the crown moulding's foot is 12.2)
local i = 1
while i <= #process.args do
	local a, v = process.args[i], process.args[i + 1]
	if a == "--scene" then
		scenePath = v
	elseif a == "--out" then
		out = v
	elseif a == "--rbxm" then
		rbxm = v
	elseif a == "--cutaway" then
		cutaway = true
		i -= 1
	elseif a == "--art" then
		artDir = v
	else
		error("unknown argument: " .. a)
	end
	i += 2
end
assert(fs.isFile(scenePath), `no {scenePath}: run lune run tools/review/export.luau first`)
assert(fs.isFile(rbxm), `no {rbxm}: run lune run tools/bake/lounge_classic.luau first`)

local scene = serde.decode("json", fs.readFile(scenePath))
-- the town's trees are uploaded meshes the renderer can only draw as their bounding boxes: left out
local kept = {}
for _, p in scene.parts do
	if not string.find(p.p, "%.Props%.Tree_%d+") then
		table.insert(kept, p)
	end
end
scene.parts = kept
addAttractions(scene, rbxm)
if artDir then
	local manifest = serde.decode("json", fs.readFile(`{artDir}/manifest.json`))
	local hide: { [string]: boolean } = {}
	for _, n in manifest.replaces do
		hide[`f3_lounge_classic.Interior.{n}`] = true
	end
	local kept2 = {}
	for _, p in scene.parts do
		local tail = string.match(p.p, "(f3_lounge_classic%.Interior%.[^%.]+)$")
		if not (tail and hide[tail]) then
			table.insert(kept2, p)
		end
	end
	scene.parts = kept2
	local colours = {}
	for _, piece in manifest.pieces do
		colours[piece.name] = piece.colour
	end
	scene.art = {
		{
			file = `{artDir}/{manifest.fbx}`,
			pos = { 1487, 9.5, -362 }, -- the venue's floor centre (yaw 0)
			rot = { 1, 0, 0, 0, 1, 0, 0, 0, 1 },
			group = "attractions",
			colours = colours,
		},
	}
end
if cutaway then
	local floorY = 9.5 -- f3_lounge_classic's floor (generated/Expansion)
	local cut = {}
	for _, p in scene.parts do
		if not (string.find(p.p, "f3_lounge_classic", 1, true) and p.pos[2] > floorY + CUT) then
			table.insert(cut, p)
		end
	end
	scene.parts = cut
end
fs.writeFile(out, serde.encode("json", scene, false))
print(`lounge: scene with the lounge -> {out}`)
