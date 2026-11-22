--!strict
-- tools/blender/trees/dump_woods.luau: the D34 woods kinds' climbing templates (Shared/World/TreeShapes.grow over
-- data/woods.json kinds) for the Blender woods (grove.py builds each kind's model round exactly these routes):
--   lune run tools/blender/trees/dump_woods.luau [build/woods/templates.json]
-- Per kind: label, species, family, model height and crown (studs, scale 1), and its routes round the foot at the
-- origin (Roblox axes, studs): k (0 the trunk), kind, points, surfaceRadius, visualOffset (a bough's feet lift),
-- sampleCount, and the fork of each bough (t on the trunk, the trunk sample's height).
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local TreeShapes = require("../../../src/shared/World/TreeShapes")

local out = process.args[1] or "build/woods/templates.json"
local doc = serde.decode("json", fs.readFile("data/woods.json"))
local kinds = {}
local names = {}
for id in doc.kinds do
	table.insert(names, id)
end
table.sort(names)
for _, id in names do
	local k = doc.kinds[id]
	local tpl = TreeShapes.grow(k.climb)
	local routes = {}
	for _, r in tpl.routes do
		table.insert(routes, {
			k = r.k,
			kind = r.kind,
			points = r.points,
			surfaceRadius = r.surfaceRadius,
			visualOffset = r.visualOffset,
			sampleCount = r.sampleCount,
			length = r.length,
		})
	end
	local forks = {}
	for _, f in tpl.forks do
		table.insert(forks, { branch = f.branch, t = f.t, height = f.height })
	end
	table.insert(kinds, {
		id = id,
		label = k.label,
		species = k.species,
		family = k.family,
		height = k.height,
		crown = k.crown,
		routes = routes,
		forks = forks,
	})
end
local dir = string.match(out, "^(.*)/[^/]+$")
if dir then
	fs.writeDir(dir)
end
fs.writeFile(out, serde.encode("json", { ["$schema"] = "woods templates (studs, Roblox axes)", kinds = kinds }, true))
print(`{#kinds} woods kinds -> {out}`)
