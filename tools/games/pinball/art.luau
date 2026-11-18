--!strict
-- tools/games/pinball/art.luau: the review scene with the owner's finished pinball models on the three machines,
-- for the offline renders (tools/review/render.py with tools/review/art_render.py). The baked machines
-- (build/Attractions.rbxm) go through the game's own loader (Server/Assets/PinballArt.run) with stand-ins for
-- the uploaded Models (each mesh by name and size, from generated/PinballArt), so what is drawn is what the loader
-- does: the baked parts it removes are gone, the colliders it keeps are unseen, and every mesh it puts in is
-- drawn from the very FBX that is uploaded (tools/blender/pinball/export_pinball.py), placed where the loader
-- put it and in the colour (or see-through, or glow) it gave it.
-- Run (repo root, after tools/bake/attractions.luau, tools/review/export.luau and the pinball art export):
--   lune run tools/games/pinball/art.luau [in, default build/review/scene.json]
--     [out, default build/review/pinball_art.json] [fbx dir, default build/art/pinball]
--   lune run tools/games/pinball/views.luau
--   python -I tools/review/render.py --scene build/review/pinball_art.json \
--     --views build/review/pinball_views.json --out build/review/pinball_art
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local AlleyLayout = require("../../../src/shared/Attractions/AlleyLayout")
local Cabinet = require("../../../src/shared/Minigames/Pinball/Cabinet")
local PinballArt = require("../../../src/server/Assets/PinballArt")
local PinballArtData = require("../../../generated/PinballArt")
local addAttractions = require("../../review/attractions_export")

local input = process.args[1] or "build/review/scene.json"
local out = process.args[2] or "build/review/pinball_art.json"
local fbx = process.args[3] or "build/art/pinball"
local MACHINES_RBXM = "build/review/pinball_art_machines.rbxm"
local ENV = {
	CFrame = roblox.CFrame,
	Color3 = roblox.Color3,
	Enum = roblox.Enum,
	Instance = roblox.Instance,
	Vector3 = roblox.Vector3,
}

local function r4(n: number): number
	return math.floor(n * 1e4 + 0.5) / 1e4
end

-- the data as if every Model were uploaded, and a stand-in loader: each mesh a MeshPart by name and size,
-- tagged with where it came from
local data = table.clone(PinballArtData :: any)
data.assets = {}
for i, tag in PinballArt.TAGS do
	data.assets[tag] = { id = i }
end
local function load(id: number): any
	local tag = PinballArt.TAGS[id]
	local m = roblox.Instance.new("Model")
	for _, rec in data.models[tag].meshes do
		local p = roblox.Instance.new("MeshPart")
		p.Name = rec.name
		p.Size = roblox.Vector3.new(rec.size[1], rec.size[2], rec.size[3])
		p:SetAttribute("ArtTag", tag)
		p:SetAttribute("ArtMesh", rec.name)
		p.Parent = m
	end
	return m
end
local function recOf(tag: string, name: string): any
	for _, rec in data.models[tag].meshes do
		if rec.name == name then
			return rec
		end
	end
	error(`{tag} has no {name}`)
end

local root = roblox.deserializeModel(fs.readFile("build/Attractions.rbxm"))[1]
local machines = PinballArt.machines(root)
assert(#machines == 3, `{#machines} pinball machines in build/Attractions.rbxm`)
local report = PinballArt.run(root, { load = load, data = data, env = ENV })
for i, r in report.reports do
	assert(r.failed == nil, `machine {i}: {r.failed}`)
	print(`pinball art: machine {i}: {r.meshes} meshes in, {r.removed} baked parts out, {r.hidden} kept unseen`)
end

-- every mesh the loader put in -> an FBX import at its frame (one per file and frame), dressed as it was dressed
local entries: { any } = {}
local byKey: { [string]: any } = {}
for _, m in machines do
	for _, d in m.model:GetDescendants() do
		if not d:IsA("MeshPart") then
			continue
		end
		local tag, name = d:GetAttribute("ArtTag") :: string, d:GetAttribute("ArtMesh") :: string
		local rec = recOf(tag, name)
		local k = if tag == "bumper" then d.Size.X / rec.size[1] else 1
		local frame = d.CFrame * roblox.CFrame.new(-rec.at[1] * k, -rec.at[2], -rec.at[3] * k)
		local x, y, z = frame.XVector * k, frame.YVector, frame.ZVector * k
		local p = frame.Position
		local rot = { r4(x.X), r4(y.X), r4(z.X), r4(x.Y), r4(y.Y), r4(z.Y), r4(x.Z), r4(y.Z), r4(z.Z) }
		local pos = { r4(p.X), r4(p.Y), r4(p.Z) }
		local key = `{tag} {table.concat(pos, ",")} {table.concat(rot, ",")}`
		local e = byKey[key]
		if e == nil then
			e = {
				file = `{fbx}/{tag}.fbx`,
				pos = pos,
				rot = rot,
				group = "attractions",
				only = {},
				colours = {},
				alpha = {},
				glow = {},
			}
			byKey[key] = e
			table.insert(entries, e)
		end
		table.insert(e.only, name)
		if not rec.textured then
			e.colours[name] = {
				math.floor(d.Color.R * 255 + 0.5),
				math.floor(d.Color.G * 255 + 0.5),
				math.floor(d.Color.B * 255 + 0.5),
			}
		end
		if d.Transparency > 0 then
			e.alpha[name] = r4(d.Transparency)
		end
		if d.Material == roblox.Enum.Material.Neon then
			table.insert(e.glow, name)
		end
	end
end
for _, m in machines do
	for _, d in m.model:GetDescendants() do
		if d:IsA("MeshPart") then
			d:Destroy()
		end
	end
end

-- the scene without the baked machines (their parts, their painted words and lights), then the machines as the
-- loader left them
local scene = serde.decode("json", fs.readFile(input))
local place = machines[1].place
local function onMachine(pos: { number }): boolean
	local X, _, D = AlleyLayout.toLocal(place, pos[1], pos[2], pos[3])
	for index = 1, #AlleyLayout.PINBALLS do
		local px, pd = Cabinet.at(index)
		if math.abs(X - px) < 1.6 and D > pd - 3 and D < pd + 3.2 then
			return true
		end
	end
	return false
end
local kept = {}
for _, p in scene.parts do
	if not string.find(p.p, ".GamesRoom.Pinball", 1, true) then
		table.insert(kept, p)
	end
end
print(`pinball art: {#scene.parts - #kept} baked machine parts taken out of the scene`)
scene.parts = kept
for _, list in { "texts", "lights" } do
	local keep = {}
	for _, x in scene.attractions[list] do
		if not onMachine(x.pos) then
			table.insert(keep, x)
		end
	end
	scene.attractions[list] = keep
end
local folder = roblox.Instance.new("Folder")
folder.Name = root.Name
local site = roblox.Instance.new("Model")
site.Name = machines[1].model.Parent.Parent.Name
site.Parent = folder
local room = roblox.Instance.new("Model")
room.Name = "GamesRoom"
room.Parent = site
for _, m in machines do
	m.model.Parent = room
end
fs.writeFile(MACHINES_RBXM, roblox.serializeModel({ folder }))
addAttractions(scene, MACHINES_RBXM)
scene.art = scene.art or {}
for _, e in entries do
	table.insert(scene.art, e)
end
fs.writeFile(out, serde.encode("json", scene, false))
print(`pinball art: {#entries} FBX placements -> {out}`)
