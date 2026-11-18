--!strict
-- tools/compile: data/art/pinball.json -> generated/PinballArt.luau.
-- The owner's finished pinball models (ChatGPT's GLBs, tools/blender/pinball) as the loader (Server/Assets/
-- PinballArt) needs them: the eight Models' asset ids (none until the lead uploads them: then the loader leaves
-- the baked machines as they are), every mesh's frame, centre, size, pivot, colour (or the THEMES key a
-- recolourable material takes), texture fallback and see-through, and each machine's colours from the bake's
-- THEMES (tools/bake/games/Pinball: the one place they are), so the cabinet, the bumpers and the light strip
-- take the machine's own. STUDS, each mesh in its own frame (tools/blender/pinball/export_pinball.py).
-- Invariants: an uploaded Model is Approved; every Model holds the meshes the loader puts in the baked parts'
-- place; no mesh over the engine's 20,000 triangles; a theme key the THEMES have.
-- Interface: compile(ctx) -> Module? (nil when the file is absent)
local fs = require("@lune/fs")
local Bake = require("../../bake/games/Pinball")
local Json = require("./Json")

local PinballArt = {}

PinballArt.MAX_MESH_TRIS = 20000
PinballArt.TAGS = { "flipper", "bumper", "plunger", "gate", "cabinet", "acorn", "rodent", "space" }
-- the meshes the loader needs in each Model (the rest is decoration it places all the same)
PinballArt.NEEDS = {
	flipper = { "Bat", "Tip", "Pin" },
	bumper = { "Body", "Cap" },
	plunger = { "Rod", "Knob" },
	gate = { "Flap" },
	cabinet = { "Glass", "LightStrip", "Body", "Backbox" },
	acorn = { "Board", "Apron", "BackglassArt", "Sling1", "Sling2", "Spinner1" },
	rodent = { "Board", "Apron", "BackglassArt", "Sling1", "Sling2" },
	space = { "Board", "Apron", "BackglassArt", "Sling1", "Sling2" },
}
-- materials drawn as Metal (a word in the material's name)
PinballArt.METAL = { "metal", "chrome", "steel", "wire", "Pivot" }
-- what a machine takes from THEMES (the materials the export marks recolourable)
PinballArt.THEME_KEYS = { "body", "trim", "legs", "glow", "bumper", "cap" }

local function mesh(m: any): any
	local rec: any = { name = m.name, frame = m.frame, at = m.centre, size = m.size, colour = m.colour }
	if m.pivot[1] ~= m.centre[1] or m.pivot[2] ~= m.centre[2] or m.pivot[3] ~= m.centre[3] then
		rec.pivot = m.pivot
	end
	if m.theme then
		rec.theme = m.theme
	end
	if m.texture then
		rec.textured = true
		rec.fallback = m.fallback
	end
	if m.alpha then
		rec.alpha = m.alpha
	end
	for _, word in PinballArt.METAL do
		if string.find(m.material, word, 1, true) then
			rec.metal = true
		end
	end
	rec.tris = m.tris
	return rec
end

function PinballArt.compile(ctx: any): any?
	local rel = "data/art/pinball.json"
	local path = ctx.repo .. "/" .. rel
	if not fs.isFile(path) then
		return nil
	end
	local doc = Json.decodeFile(path)
	local assets, models = {}, {}
	local records = 0
	for _, tag in PinballArt.TAGS do
		local a = doc.assets[tag]
		ctx.invariant(`pinball art: the {tag} Model is in the file`, a ~= nil and doc.models[tag] ~= nil)
		if a == nil or doc.models[tag] == nil then
			continue
		end
		local id = if type(a.assetId) == "string" and a.assetId ~= "" then tonumber(a.assetId) else nil
		if id then
			ctx.invariant(`pinball art: the {tag} Model is Approved`, a.moderation == "Approved")
		end
		assets[tag] = { id = id, displayName = a.displayName, moderation = a.moderation, tris = a.tris }
		local meshes = {}
		local have: { [string]: boolean } = {}
		for _, m in doc.models[tag].meshes do
			ctx.invariant(
				`pinball art {tag} {m.name}: under the engine's triangles`,
				m.tris <= PinballArt.MAX_MESH_TRIS
			)
			ctx.invariant(
				`pinball art {tag} {m.name}: a theme colour THEMES has`,
				m.theme == nil or table.find(PinballArt.THEME_KEYS, m.theme) ~= nil
			)
			have[m.name] = true
			table.insert(meshes, mesh(m))
		end
		for _, name in PinballArt.NEEDS[tag] do
			ctx.invariant(`pinball art: {tag} has {name}`, have[name] == true)
		end
		table.sort(meshes, function(x, y)
			return x.name < y.name
		end)
		records += #meshes
		models[tag] = { frame = doc.models[tag].frame, meshes = meshes }
	end
	local themes = {}
	for variant, th in Bake.THEMES do
		local t = {}
		for _, k in PinballArt.THEME_KEYS do
			t[k] = (th :: any)[k]
		end
		themes[variant] = t
	end
	return {
		name = "PinballArt",
		value = {
			assets = assets,
			bumperRadius = doc.bumperRadius,
			gateHinge = doc.gateHinge,
			themes = themes,
			models = models,
		},
		records = records,
		map = true,
		source = rel,
		header = {
			"STUDS, each mesh's centre (at), size and pivot in its frame (tools/blender/pinball/export_pinball.py). The",
			"owner's pinball Models (loaded at boot by Server/Assets/PinballArt; no id: not uploaded yet), and THEMES.",
		},
	}
end

return PinballArt
