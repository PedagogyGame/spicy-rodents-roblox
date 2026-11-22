--!strict
-- tools/blender/trees/dump_shapes.luau: the D32 tree shapes (generated/TreeShapes.luau: Shared/World/TreeShapes) as
-- the harvest's JSON shapes, in HTML units, for the Blender trees (shapes.py merges them into treegen's data):
--   lune run tools/blender/trees/dump_shapes.luau [generated/TreeShapes.luau] [build/tree_shapes/shapes.json]
-- Writes the grown boughs of the reshaped trees: routes (id, name, kind, points, surfaceRadius, trunkClearance,
-- length: units), their samples (the game's sampleCount arc-length points, units) and per reshaped trunk the boughs
-- it gains (its canopy forks). The planted copies are not written: they wear their sources' uploaded meshes.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local serde = require("@lune/serde")
local Curve = require("../../../src/shared/Routes/Curve")

local src = process.args[1] or "generated/TreeShapes.luau"
local out = process.args[2] or "build/tree_shapes/shapes.json"
local SPU = 2.5
local compiled = luau.load(fs.readFile(src), { debugName = src })()
local byId: { [number]: any } = {}
for _, r in compiled.routes do
	byId[r.id] = r
end
local function u(v: number): number
	return math.floor(v / SPU * 1e6 + 0.5) / 1e6
end
local routes, samples, forks = {}, {}, {}
for _, tree in compiled.trees do
	if tree.kind == "reshaped" then
		local ids = {}
		for _, id in tree.routes do
			local r = byId[id]
			local pts = {}
			local vecs = {}
			for i, p in r.points do
				pts[i] = { u(p[1]), u(p[2]), u(p[3]) }
				vecs[i] = Curve.vec3(p[1], p[2], p[3])
			end
			table.insert(routes, {
				id = r.id,
				name = r.name,
				kind = r.kind,
				points = pts,
				surfaceRadius = u(r.surfaceRadius),
				trunkClearance = if r.trunkClearance then u(r.trunkClearance) else nil,
				length = u(r.length),
				sampleCount = r.sampleCount,
			})
			local s = {}
			for i, p in Curve.new(vecs):getSpacedPoints(r.sampleCount - 1) do
				s[i] = { u(p.x), u(p.y), u(p.z) }
			end
			table.insert(samples, { r.id, s })
			table.insert(ids, r.id)
		end
		table.insert(forks, { trunk = tree.trunk, label = tree.label, branches = ids })
	end
end
local dir = string.match(out, "^(.*)/[^/]+$")
if dir then
	fs.writeDir(dir)
end
fs.writeFile(
	out,
	serde.encode("json", {
		["$schema"] = "tree shapes for the Blender trees (HTML units)",
		routes = routes,
		samples = samples,
		forks = forks,
	}, true)
)
print(`{#routes} grown boughs on {#forks} trees -> {out}`)
