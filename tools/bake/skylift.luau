--!strict
-- tools/bake/skylift: Lune bake of the sky lift, its approach and the Lookout into build/Expansion_F4.rbxm, mapped to
-- Workspace.Expansion.F4 by the default, ci and build project files ($path optional; the rbxm is gitignored, like
-- the alley's: run this before an owner build). What is inside: tools/bake/skylift/Bake.luau's header.
-- The Lookout (f3_hilltop) is built by tools/bake/lookout/Lookout.luau's build(kit, parent, venue) when that file
-- exists; until then a plinth stub stands in for it.
-- Usage (repo root): lune run tools/bake/skylift.luau [--out build/Expansion_F4.rbxm]
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local Bake = require("./skylift/Bake")

local out = "build/Expansion_F4.rbxm"
local i = 1
while i <= #process.args do
	local a = process.args[i]
	if a == "--out" then
		out = process.args[i + 1]
		i += 1
	else
		error("unknown argument: " .. a)
	end
	i += 1
end

local t0 = os.clock()
local folder, report = Bake.build(roblox)
local names = {}
for name in report.models do
	table.insert(names, name)
end
table.sort(names)
for _, name in names do
	print(`skylift: {name}: {report.models[name]} parts`)
end
local bytes = roblox.serializeModel({ folder })
local dir = string.match(out, "^(.*)/[^/]+$")
if dir and not fs.isDir(dir) then
	fs.writeDir(dir)
end
fs.writeFile(out, bytes)
local took = string.format("%.2f", os.clock() - t0)
print(`skylift: F4 {report.total} parts (the Lookout: {report.lookout}) -> {out} ({#bytes} bytes) in {took} s`)
