--!strict
-- tools/bake/sewers: Lune bake of the storm drains (BRIEF_ADDENDUM D8: "a few underground pipes that the squirrel
-- can run through ... just basic sewers") into build/Sewers.rbxm, mapped to Workspace.Sewers by the default, ci and
-- build project files ($path optional). The town bake is full, so the drains are their own bake. Built only from
-- the compiled layout (Shared/World/SewerLayout over generated/Sewers: lune run tools/compile/main.luau compile) and
-- the owner's uploaded modules (data/art/sewer_modules.json: tools/blender/sewers). tools/bake/sewers/Build says
-- what is in it; the terrain is carved at boot by the server lane from SewerLayout.carveBoxes(), not here.
-- Usage (repo root): lune run tools/bake/sewers.luau [--out build/Sewers.rbxm]
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local Build = require("./sewers/Build")
local SewerLayout = require("../../src/shared/World/SewerLayout")

local out = "build/Sewers.rbxm"
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
local layout = SewerLayout.new(require("../../generated/Sewers") :: any)
local art = if fs.isFile("data/art/sewer_modules.json")
	then serde.decode("json", fs.readFile("data/art/sewer_modules.json"))
	else nil
local root, report = Build.build(roblox, layout, art)
local bytes = roblox.serializeModel({ root })
if not fs.isDir("build") then
	fs.writeDir("build")
end
fs.writeFile(out, bytes)
local per = {}
for id, n in report.pipes do
	table.insert(per, `{id} {n}`)
end
table.sort(per)
print(
	`sewers: {report.parts} parts ({table.concat(per, ", ")}), {report.slots} art slots, {report.lamps} lamps, `
		.. `{report.cues} sound cue points`
		.. (if art then "" else " (no data/art/sewer_modules.json: slots without asset ids)")
)
print(`sewers: -> {out} ({#bytes} bytes) in {string.format("%.2f", os.clock() - t0)} s`)
