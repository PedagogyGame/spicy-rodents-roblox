--!strict
-- tools/bake/bowl_lane: bakes Bowl Lane (xs_bowl_lane in data/expansion.json, its sidewalks, the turning bay, the
-- Alley Walk and the steps walk to the bowling alley; tools/bake/bowl_lane/Street) into build/Expansion_F2.rbxm,
-- which the project files map to Workspace.Expansion.F2 (family F2's single bake).
-- Usage (repo root): lune run tools/bake/bowl_lane.luau [--out build/Expansion_F2.rbxm]
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local Street = require("./bowl_lane/Street")

local out = "build/Expansion_F2.rbxm"
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

local folder = roblox.Instance.new("Folder")
folder.Name = "F2"
local root = Street.build(roblox, folder)
local dir = string.match(out, "^(.*)/[^/]+$")
if dir and not fs.isDir(dir) then
	fs.writeDir(dir)
end
fs.writeFile(out, roblox.serializeModel({ folder }))
print(
	`bowl lane: {root:GetAttribute("Parts")} parts (budget {Street.BUDGET}), {root:GetAttribute("Lights")} lights -> {out}`
)
