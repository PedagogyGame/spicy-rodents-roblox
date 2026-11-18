--!strict
-- tools/bake/lounge_classic: bakes THE GILDED ACORN, the 1940s lounge (f3_lounge_classic in data/expansion.json;
-- tools/bake/lounge_classic/Lounge) into build/Expansion_LoungeClassic.rbxm, which the project files map to
-- Workspace.Expansion.LoungeClassic. Its own slot, not the F3 family's single bake (two bakes writing one file
-- would overwrite each other).
-- Usage (repo root): lune run tools/bake/lounge_classic.luau [--out build/Expansion_LoungeClassic.rbxm]
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local Expansion = require("../../generated/Expansion")
local Kit = require("./alley/Kit")
local Lounge = require("./lounge_classic/Lounge")

local VENUE = "f3_lounge_classic"

local out = "build/Expansion_LoungeClassic.rbxm"
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

local venue: any = nil
for _, v in (Expansion :: any).venues do
	if v.id == VENUE then
		venue = v
	end
end
assert(venue, `{VENUE} missing from generated/Expansion`)

local folder = roblox.Instance.new("Folder")
folder.Name = "LoungeClassic"
local kit = Kit.new(roblox, venue.place)
local root = Lounge.build(kit, folder, venue)
local dir = string.match(out, "^(.*)/[^/]+$")
if dir and not fs.isDir(dir) then
	fs.writeDir(dir)
end
fs.writeFile(out, roblox.serializeModel({ folder }))
print(
	`lounge: {venue.id} at ({venue.position.x}, {venue.position.z}) floor {venue.floorY}: {root:GetAttribute("Parts")} parts (cap {Lounge.PART_BUDGET}), {root:GetAttribute(
		"Lights"
	)} lights ({root:GetAttribute("Shadows")} shadowed) -> {out}`
)
