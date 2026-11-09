--!strict
-- tools/compile: data/art/tree_meshes.json -> generated/TreeArt.luau.
-- The 95 Blender tree models (tools/blender/trees; uploaded and Approved, data/art/trees.json) as the
-- bake needs them: per trunk route, the model's world pivot and its MeshParts (mesh content id, size,
-- centre relative to the pivot, PBR map content ids). tree_meshes.json is harvested from the uploaded
-- assets in the engine (tools/blender/trees/harvest_meshes.py), so sizes and offsets are the engine's.
-- STUDS, Roblox axes. Invariants: one record per trunk route, every part has a mesh and a colour map,
-- no part is rotated or rescaled (size == meshSize).
-- Interface: compile(ctx) -> Module? (nil when the file is absent)
local fs = require("@lune/fs")
local Json = require("./Json")

local TreeArt = {}

local function content(s: any): string?
	if type(s) ~= "string" or s == "" or s == "nil" then
		return nil
	end
	return s
end

function TreeArt.compile(ctx: any): any?
	local rel = "data/art/tree_meshes.json"
	local path = ctx.repo .. "/" .. rel
	if not fs.isFile(path) then
		return nil
	end
	local doc = Json.decodeFile(path)
	local trees = {}
	local seen: { [number]: boolean } = {}
	for _, t in doc.trees do
		ctx.invariant("tree art: one model per trunk route " .. t.trunkRoute, not seen[t.trunkRoute])
		seen[t.trunkRoute] = true
		local parts = {}
		for _, p in t.parts do
			local what = `tree art {t.trunkRoute} {p.name}`
			ctx.invariant(what .. ": has a mesh", content(p.meshId) ~= nil)
			ctx.invariant(what .. ": has a colour map", content(p.surface and p.surface.colorMap) ~= nil)
			ctx.invariant(
				what .. ": unrotated and unscaled",
				p.rot[1] == 0
					and p.rot[2] == 0
					and p.rot[3] == 0
					and p.size[1] == p.meshSize[1]
					and p.size[2] == p.meshSize[2]
					and p.size[3] == p.meshSize[3]
			)
			table.insert(parts, {
				name = p.name,
				meshId = p.meshId,
				size = p.size,
				offset = p.offset,
				colorMap = content(p.surface.colorMap),
				normalMap = content(p.surface.normalMap),
				roughnessMap = content(p.surface.roughnessMap),
				alphaMode = p.surface.alphaMode,
				color = p.color,
				material = p.material,
				doubleSided = p.doubleSided,
			})
		end
		table.sort(parts, function(a, b)
			return a.name < b.name
		end)
		table.insert(trees, {
			trunkRoute = t.trunkRoute,
			label = t.label,
			assetId = t.assetId,
			pivot = t.pivot,
			parts = parts,
		})
	end
	table.sort(trees, function(a, b)
		return a.trunkRoute < b.trunkRoute
	end)
	ctx.compare("tree art models (data/art/tree_meshes.json)", #trees, #trees)
	return {
		name = "TreeArt",
		value = trees,
		records = #trees,
		source = rel,
		header = {
			"STUDS, Roblox axes. One record per tree trunk route: the Blender model's world pivot and its MeshParts",
			"(part centre = pivot + offset; no rotation). WorldGen/Builders/Trees places them; Factory authors the MeshParts.",
		},
	}
end

return TreeArt
