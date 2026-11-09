--!strict
-- Shared/Data over generated/ (BUILD_PLAN §1.4, §4.4 #1): counts equal the compiler's Index, lookups by
-- id, the route registry through the accessor, and modules the compiler has not produced yet read as
-- empty and are reported.
local Data = require("@shared/Data")

return function(t)
	t.test("default instance reads generated/ with the Index counts", function()
		local d = Data.default()
		local idx = d:index()
		t.eq(#d:lots(), idx.modules.Lots.count)
		t.eq(#d:lanes(), idx.modules.Lanes.count)
		t.eq(#d:roads(), idx.modules.Roads.count)
		t.eq(#d:cast(), idx.modules.Cast.count)
		-- the harvested chunks plus the attraction routes (data/attractions.json: the bowling alley tunnels)
		local attractions = (d:module("Attractions") :: any).routes
		local extra = if attractions then #attractions else 0
		t.eq(d:routes():count(), idx.modules.Routes.count + extra)
		t.eq(d:bakeHash(), idx.harvestPin.sha256)
		t.truthy(Data.default() == d)
	end)

	t.test("lookups by id", function()
		local d = Data.default()
		local lot = d:lot("galleria_building")
		t.truthy(lot ~= nil)
		t.eq(lot.type, "mall")
		t.eq(d:lot("no_such_lot"), nil)
	end)

	t.test("missing modules are empty and listed (Track B adds modules as it compiles them)", function()
		local d = Data.default()
		t.eq(#d:module("NoSuchModule"), 0)
		t.falsy(d:has("NoSuchModule"))
		t.truthy(table.find(d:missing(), "NoSuchModule") ~= nil)
		for name in d:index().modules do
			t.truthy(d:has(name), name)
		end
	end)

	t.test("a custom loader: chunks concatenate in order", function()
		local mods = {
			Index = { modules = { Things = { count = 3, chunks = { "T1", "T2" } } } },
			T1 = { { id = "a" }, { id = "b" } },
			T2 = { { id = "c" } },
		}
		local d = Data.new(function(name)
			return (mods :: any)[name]
		end)
		local all = d:module("Things")
		t.eq(#all, 3)
		t.eq(all[3].id, "c")
		t.eq(d:byId("Things", "b").id, "b")
		t.eq(d:routes():count(), 0)
		t.truthy(table.find(d:missing(), "Routes") ~= nil)
	end)
end
