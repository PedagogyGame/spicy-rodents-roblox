--!strict
-- tools/bake/attractions: Lune bake of the attraction buildings that are built on their own (brief v2 §13a;
-- BUILD_PLAN §3.17, W3c #15) into build/Attractions.rbxm, mapped to Workspace.Attractions by the default, ci and
-- build project files ($path optional). Two kinds of thing come out of it:
--   the bowling alley (Bellwether Bowl) placed by data/attractions.json (studs). The geometry is
--     Shared/Attractions/AlleyLayout's; the server finds the lanes, pins, balls, hoods, scoreboards, dartboard,
--     fortune cabinet, doors and terrain carve boxes by name. The games room's tables and machines are built
--     through the bake registry (tools/bake/GameBakes);
--   the minigames' places on the expansion venues (generated/Expansion.venues; data/expansion.json): for every
--     station a game's Spec lists on a venue (src/shared/Minigames/Games.stations) whose game has a builder in
--     tools/bake/GameBakes, a site Model named after the venue, in the venue's own frame, with that game's
--     furniture in it. (The venues are NOT added to data/attractions.json: the expansion compile check treats
--     every attraction's footprint as an obstacle for venue sites.)
-- Every Model directly under the folder carries Site, OriginX, OriginZ, FloorY and Yaw: the server takes each as
-- a site for minigames (Server/Attractions/AttractionService.sites).
-- Usage (repo root): lune run tools/bake/attractions.luau [--out build/Attractions.rbxm]
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local Expansion = require("../../generated/Expansion")
local Games = require("../../src/shared/Minigames/Games")
local GameBakes = require("./GameBakes")
local Kit = require("./alley/Kit")
local Shell = require("./alley/Shell")
local Lanes = require("./alley/Lanes")
local Rooms = require("./alley/Rooms")
local Ways = require("./Ways")

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

type Place = { x: number, z: number, floorY: number, yaw: number }

-- the buildings of data/attractions.json
local places: { [string]: Place } = {}
for _, a in doc.attractions do
	if a.type ~= "bowling_alley" then
		error(`attractions: no builder for type {a.type}`)
	end
	local place: Place = { x = a.place.x, z = a.place.z, floorY = a.place.floorY, yaw = a.place.yaw }
	places[a.id] = place
	local kit = Kit.new(roblox, place)
	local root = GameBakes.siteModel(roblox, "BowlingAlley", a.id, place)
	Shell.build(kit, root, a)
	Lanes.build(kit, root)
	Rooms.build(kit, root)
	root.Parent = folder
	parts += kit.count
end

-- the minigames' places on the expansion venues: a site per venue some game builds on
local venues: { [string]: any } = {}
for _, v in (Expansion :: any).venues do
	local p = v.place
	if type(p) == "table" and places[v.id] == nil then
		places[v.id] = { x = p.x, z = p.z, floorY = p.floorY, yaw = p.yaw }
		venues[v.id] = v
	end
end
local stations = Games.stations(places)
local onVenues = GameBakes.venueSites(roblox, folder, stations, places, venues)
parts += onVenues.parts

-- the way from the town to each venue built above (tools/bake/Ways): its walk, the new street it meets, a
-- forecourt, the street's lamps and a fingerpost where the street leaves the town road it continues
local builtVenues: { [string]: any } = {}
local labels: { [string]: { string } } = {}
for _, m in folder:GetChildren() do
	local id = m:GetAttribute("Site")
	if type(id) == "string" and venues[id] ~= nil then
		builtVenues[id] = venues[id]
		-- (the name without its note: "WBLW CHANNEL 7 (ABANDONED)" reads "WBLW CHANNEL 7")
		labels[id] = { (string.gsub(venues[id].name, "%s*%b()", "")) }
	end
end
for _, st in stations do
	local l = labels[st.site]
	if l ~= nil and st.joins == nil and table.find(l, string.upper(st.game)) == nil then
		table.insert(l, string.upper(st.game))
	end
end
local ways = Ways.plan(builtVenues, labels)
local wayParts = Ways.build(roblox, folder, ways)
parts += wayParts

local bytes = roblox.serializeModel({ folder })
if not fs.isDir("build") then
	fs.writeDir("build")
end
fs.writeFile(out, bytes)
local built = table.concat(onVenues.built, ", ")
local took = string.format("%.2f", os.clock() - t0)
print(`attractions: {#doc.attractions} building(s), {onVenues.sites} venue site(s) [{built}], {parts} parts`)
print(`attractions: {#ways.ways} way(s) to the venues, {#ways.roads} strips, {wayParts} parts`)
print(`attractions: -> {out} ({#bytes} bytes) in {took} s`)
