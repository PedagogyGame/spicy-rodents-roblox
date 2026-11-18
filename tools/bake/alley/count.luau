--!strict
-- tools/bake/alley/count: the alley bake's parts per model (two levels deep), for budgeting.
-- Usage (repo root): lune run tools/bake/alley/count.luau [model]
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local Kit = require("./Kit")
local Alley = require("./Alley")

local a = serde.decode("json", fs.readFile("data/attractions.json")).attractions[1]
local kit = Kit.new(roblox, a.place)
local root = roblox.Instance.new("Model")
Alley.build(kit, root, a)
local only = process.args[1]
local function count(inst: any): number
	local n = if inst:IsA("BasePart") then 1 else 0
	for _, d in inst:GetDescendants() do
		if d:IsA("BasePart") then
			n += 1
		end
	end
	return n
end
print(`the alley: {kit.count} parts`)
for _, top in root:GetChildren() do
	if only == nil or top.Name == only then
		print(`  {top.Name} {count(top)}`)
		if only then
			for _, c in top:GetChildren() do
				print(`    {c.Name} {count(c)}`)
			end
		end
	end
end
