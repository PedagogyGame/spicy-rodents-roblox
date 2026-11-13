--!strict
-- tools/bake/lookout/bake_alone: bakes THE LOOKOUT (f3_hilltop) on its own, for a look before the lift's own
-- entry (tools/bake/skylift.luau, which calls Lookout.build into build/Expansion_F4.rbxm) is there.
-- Usage (repo root): lune run tools/bake/lookout/bake_alone.luau [--out build/Lookout_alone.rbxm] [--review]
--   --review also adds the Lookout to build/Attractions.rbxm (replacing an earlier copy) so tools/review/export
--   puts it in the review scene; re-run `lune run tools/bake/attractions.luau` afterwards to restore the file.
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local Expansion = require("../../../generated/Expansion")
local Kit = require("../alley/Kit")
local Lookout = require("./Lookout")

local out = "build/Lookout_alone.rbxm"
local review = false
local i = 1
while i <= #process.args do
	local a = process.args[i]
	if a == "--out" then
		out = process.args[i + 1]
		i += 1
	elseif a == "--review" then
		review = true
	else
		error("unknown argument: " .. a)
	end
	i += 1
end

local venue: any = nil
for _, v in (Expansion :: any).venues do
	if v.id == "f3_hilltop" then
		venue = v
	end
end
assert(venue, "f3_hilltop missing from generated/Expansion")

local folder = roblox.Instance.new("Folder")
folder.Name = "F4"
local kit = Kit.new(roblox, venue.place)
local root = Lookout.build(kit, folder, venue)
if not fs.isDir("build") then
	fs.writeDir("build")
end
fs.writeFile(out, roblox.serializeModel({ folder }))
local sky = folder:FindFirstChild(`{venue.id}_Skyline`)
print(
	`lookout: {venue.id}: {root:GetAttribute("Parts")} parts, skyline {sky and sky:GetAttribute("Parts")} parts; steps run {Lookout.STEPS.run} st -> {out}`
)

if review then
	local path = "build/Attractions.rbxm"
	assert(fs.isFile(path), "run lune run tools/bake/attractions.luau first")
	local att = roblox.deserializeModel(fs.readFile(path))[1]
	for _, c in att:GetChildren() do
		if string.sub(c.Name, 1, #venue.id) == venue.id then
			c:Destroy()
		end
	end
	for _, c in folder:GetChildren() do
		c.Parent = att
	end
	fs.writeFile(path, roblox.serializeModel({ att }))
	print(`lookout: added to {path} for the review scene`)
end
