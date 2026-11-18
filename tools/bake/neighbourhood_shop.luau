--!strict
-- tools/bake/neighbourhood_shop: bakes the shell of the owner's Neighbourhood Shop (f1_neighbourhood_shop in
-- data/expansion.json; tools/bake/neighbourhood_shop/Shop) into build/Expansion_NeighbourhoodShop.rbxm, which
-- the project files map to Workspace.Expansion.NeighbourhoodShop. Its own slot, not one of F1..F4: those are
-- each one family's single bake (the corner store's builder will own F1), and two bakes writing one file
-- would overwrite each other. His interior and roof are not in the file: Server/Assets/ShopArt loads the
-- uploaded Models into the shell at boot.
-- Usage (repo root): lune run tools/bake/neighbourhood_shop.luau [--out build/Expansion_NeighbourhoodShop.rbxm]
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local Expansion = require("../../generated/Expansion")
local ShopArt = require("../../generated/ShopArt")
local Kit = require("./alley/Kit")
local Shop = require("./neighbourhood_shop/Shop")

local out = "build/Expansion_NeighbourhoodShop.rbxm"
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
	if v.id == (ShopArt :: any).venue then
		venue = v
	end
end
assert(venue, "f1_neighbourhood_shop missing from generated/Expansion")

local folder = roblox.Instance.new("Folder")
folder.Name = "NeighbourhoodShop"
local kit = Kit.new(roblox, venue.place)
local root = Shop.build(kit, folder, venue, ShopArt)
local dir = string.match(out, "^(.*)/[^/]+$")
if dir and not fs.isDir(dir) then
	fs.writeDir(dir)
end
fs.writeFile(out, roblox.serializeModel({ folder }))
print(
	`neighbourhood shop: {venue.id} at ({venue.position.x}, {venue.position.z}) floor {venue.floorY}: {root:GetAttribute(
		"Parts"
	)} parts (budget {venue.partBudget}) -> {out}`
)
