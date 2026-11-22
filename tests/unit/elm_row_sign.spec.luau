--!strict
-- Owner D32 (2026-11-22, with a screenshot): the two-storey building by the bowling alley signed "CORNER SHOPS" had "a
-- misleading title on it, change the name of that building to something innocuous" (Pepper's Corner Store is the real
-- shop, elsewhere). It reads ELM ROW OFFICES: in the town's lots (its fascia), in the expansion plan's two records of
-- it, and in the W1 seed the lots' signs came from; nothing in the town's data still says CORNER SHOPS.
local Lots = require("../../generated/Lots")
local Expansion = require("../../generated/Expansion")
local fs = require("@lune/fs")

local NAME = "ELM ROW OFFICES"

return function(t)
	t.test("D32: the building's fascia reads ELM ROW OFFICES (east_corner_shops)", function()
		local found = nil
		for _, lot in Lots :: any do
			if lot.id == "east_corner_shops" then
				found = lot
			end
		end
		t.truthy(found, "the lot")
		t.eq(found.params.sign, NAME)
	end)

	t.test("D32: the expansion plan names it the same; no lot sign or venue name says CORNER SHOPS", function()
		local named = 0
		for _, v in (Expansion :: any).venues do
			t.falsy(v.name == "CORNER SHOPS", v.id)
			if v.id == "f1_up_corner_shops" then
				t.eq(v.name, NAME)
				named += 1
			end
		end
		t.eq(named, 1, "the upgrade record")
		for _, b in (Expansion :: any).foodBaseline do
			t.falsy(string.find(b.name, "CORNER SHOPS", 1, true), b.lot)
			if b.lot == "east_corner_shops" then
				t.truthy(string.find(b.name, NAME, 1, true), b.name)
			end
		end
		for _, lot in Lots :: any do
			local sign = lot.params and lot.params.sign
			if type(sign) == "string" then
				t.falsy(string.find(string.upper(sign), "CORNER SHOP", 1, true), lot.id)
			end
		end
	end)

	t.test("D32: the W1 seed (the lots' signs' source) agrees", function()
		local seed = fs.readFile("tools/compile/w1_seed.luau")
		t.truthy(string.find(seed, `east_corner_shops = "{NAME}"`, 1, true), "w1_seed SIGNS")
		t.falsy(string.find(seed, '"CORNER SHOPS"', 1, true), "the old name")
	end)
end
