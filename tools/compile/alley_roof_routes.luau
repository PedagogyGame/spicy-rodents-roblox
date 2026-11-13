--!strict
-- tools/compile/alley_roof_routes: writes the bowling alley's roof run (Shared/Attractions/AlleyRoof: the yard
-- annex and the routes 9101..9140) into data/attractions.json, so the file the compiler reads and AlleyRoof never
-- disagree (tests/unit/attractions_roofvent.spec.luau holds them equal). Everything else in the file is kept as it is
-- written: the alley's own routes stay, any earlier roof routes are replaced, the annex list is written before
-- "routes" (or replaced). Run it after changing AlleyRoof, then compile:
--   lune run tools/compile/alley_roof_routes.luau && lune run tools/compile/main.luau compile
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local Json = require("./lib/Json")
local AlleyRoof = require("../../src/shared/Attractions/AlleyRoof")

local PATH = "data/attractions.json"
local KEY_ORDER = {
	"id",
	"name",
	"kind",
	"surfaceRadius",
	"visualOffset",
	"flags",
	"autoGrabExcluded",
	"isPole",
	"isGiant",
	"fixedSurfaceZ",
	"treeTravel",
	"points",
	"enclosure",
	"hidden",
	"width",
	"height",
	"mouths",
	"t",
	"opens",
	"out",
	"links",
	"route",
	"dir",
	"note",
	"x0",
	"x1",
	"d0",
	"d1",
	"for",
}

-- `value` as JSON, every line indented by `pad`.
local function block(value: any, pad: string): string
	local text = Json.encode(value, { keyOrder = KEY_ORDER })
	text = string.gsub(text, "\n$", "")
	return pad .. string.gsub(text, "\n", "\n" .. pad)
end

local text = fs.readFile(PATH)
local doc = serde.decode("json", text)
local alley = doc.attractions[1]
assert(
	alley and alley.id == "bowling_alley" and #doc.attractions == 1,
	"data/attractions.json: one attraction, the alley"
)

-- the routes array is the alley's last key: everything from the first roof route (or the array's end) is rewritten
local tail = "\n      ]\n    }\n  ]\n}\n"
assert(string.sub(text, -#tail) == tail, "data/attractions.json ends with the alley's routes")
local cut = string.find(text, '\n        {\n          "id": 91%d%d,', 1)
local head = if cut then string.sub(text, 1, cut - 2) else string.sub(text, 1, #text - #tail)

local items = {}
for _, r in AlleyRoof.routes() do
	table.insert(items, block(r, "        "))
end
local out = head .. ",\n" .. table.concat(items, ",\n") .. tail

-- the annex list, just before "routes"
local annex = table.clone(AlleyRoof.ANNEX) :: any
local annexText = '      "annexes": [\n' .. block(annex, "        ") .. "\n      ],\n"
local a0 = string.find(out, '      "annexes": [', 1, true)
local r0 = string.find(out, '      "routes": [', 1, true)
assert(r0, "the routes key")
if a0 then
	out = string.sub(out, 1, a0 - 1) .. annexText .. string.sub(out, r0)
else
	out = string.sub(out, 1, r0 - 1) .. annexText .. string.sub(out, r0)
end

-- the result must decode, and keep the alley's own routes as they were
local back = serde.decode("json", out).attractions[1]
local own = 0
for _, r in back.routes do
	if r.id < 9100 then
		own += 1
	end
end
local before = 0
for _, r in alley.routes do
	if r.id < 9100 then
		before += 1
	end
end
assert(own == before, "the alley's own routes are kept")
fs.writeFile(PATH, out)
print(`{PATH}: the yard annex and {#items} roof routes ({own} of the alley's own kept)`)
