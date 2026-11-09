--!strict
-- tools/bake/attractions: Lune bake of the attraction buildings that are built on their own (brief v2 §13a;
-- BUILD_PLAN §3.17, W3c #15) into build/Attractions.rbxm, mapped to Workspace.Attractions by the default, ci and
-- build project files ($path optional). Today: the bowling alley (Bellwether Bowl) placed by data/attractions.json
-- (studs). The geometry is Shared/Attractions/AlleyLayout's; the server finds the lanes, pins, balls, hoods,
-- scoreboards, dartboard, fortune cabinet, doors and terrain carve boxes by name.
-- Usage (repo root): lune run tools/bake/attractions.luau [--out build/Attractions.rbxm]
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local Kit = require("./alley/Kit")
local Shell = require("./alley/Shell")
local Lanes = require("./alley/Lanes")
local Rooms = require("./alley/Rooms")

local out = "build/Attractions.rbxm"
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
local doc = serde.decode("json", fs.readFile("data/attractions.json"))
local folder = roblox.Instance.new("Folder")
folder.Name = "Attractions"
local parts = 0
for _, a in doc.attractions do
	if a.type ~= "bowling_alley" then
		error(`attractions: no builder for type {a.type}`)
	end
	local place = { x = a.place.x, z = a.place.z, floorY = a.place.floorY, yaw = a.place.yaw }
	local kit = Kit.new(roblox, place)
	local root = roblox.Instance.new("Model")
	root.Name = "BowlingAlley"
	root:SetAttribute("AttractionId", a.id)
	root:SetAttribute("OriginX", place.x)
	root:SetAttribute("OriginZ", place.z)
	root:SetAttribute("FloorY", place.floorY)
	root:SetAttribute("Yaw", place.yaw)
	Shell.build(kit, root, a)
	Lanes.build(kit, root)
	Rooms.build(kit, root)
	root.Parent = folder
	parts += kit.count
end
local bytes = roblox.serializeModel({ folder })
if not fs.isDir("build") then
	fs.writeDir("build")
end
fs.writeFile(out, bytes)
print(
	`attractions: {#doc.attractions} building(s), {parts} parts -> {out} ({#bytes} bytes) in {string.format(
		"%.2f",
		os.clock() - t0
	)} s`
)
