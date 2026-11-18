--!strict
-- tools/bake/corner_store: bakes Pepper's Corner Store (f1_corner_store in data/expansion.json;
-- tools/bake/corner_store/Store) into build/Expansion_F1.rbxm, which the project files map to
-- Workspace.Expansion.F1 (family F1's single bake; the owner's Neighbourhood Shop has its own slot).
-- Usage (repo root): lune run tools/bake/corner_store.luau [--out build/Expansion_F1.rbxm]
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local Expansion = require("../../generated/Expansion")
local Kit = require("./alley/Kit")
local Store = require("./corner_store/Store")
local Height = require("../../src/shared/World/Height")
local AlleyLayout = require("../../src/shared/Attractions/AlleyLayout")

local out = "build/Expansion_F1.rbxm"
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
	if v.id == "f1_corner_store" then
		venue = v
	end
end
assert(venue, "f1_corner_store missing from generated/Expansion")

-- the ground's height below the floor at a local point (for the steps outside each door)
local function groundAt(x: number, d: number): number
	local wx, _, wz = AlleyLayout.toWorld(venue.place, x, 0, d)
	return Height.at(wx, wz) - venue.floorY
end

local folder = roblox.Instance.new("Folder")
folder.Name = "F1"
local kit = Kit.new(roblox, venue.place)
local root = Store.build(kit, folder, venue, groundAt)
local dir = string.match(out, "^(.*)/[^/]+$")
if dir and not fs.isDir(dir) then
	fs.writeDir(dir)
end
fs.writeFile(out, roblox.serializeModel({ folder }))
print(
	`corner store: {venue.id} at ({venue.position.x}, {venue.position.z}) floor {venue.floorY}: {root:GetAttribute(
		"Parts"
	)} parts (budget {venue.partBudget}) -> {out}`
)
