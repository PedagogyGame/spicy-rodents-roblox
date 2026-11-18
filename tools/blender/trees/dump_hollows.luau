--!strict
-- tools/blender/trees/dump_hollows.luau: a compiled hollow-trees module (generated/HollowTrees.luau, from the
-- hollow trees' branch or the main line once they land) as JSON for check_hollows.py.
--   lune run tools/blender/trees/dump_hollows.luau <HollowTrees.luau> <out.json>
-- Writes per hollow with a trunk: its id, trunk route, foot and every shell piece (role, shape, centre, the
-- frame's right and up, size). Studs, world space.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local serde = require("@lune/serde")

local src, out = process.args[1], process.args[2]
assert(src and out, "usage: dump_hollows.luau <HollowTrees.luau> <out.json>")
local compiled = luau.load(fs.readFile(src), { debugName = src })()
local rows = {}
for _, h in compiled.hollows do
	if h.trunk then
		table.insert(rows, { id = h.id, trunk = h.trunk, foot = { h.x, h.y, h.z }, parts = h.parts })
	end
end
fs.writeFile(out, serde.encode("json", { hollows = rows }, true))
print(`{#rows} hollows with a trunk -> {out}`)
