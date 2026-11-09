--!strict
-- W1 #11 Map/MapModel: projection (north +Z up, +X on the left as a player facing north sees it),
-- round trip, every lot and road inside the map, district labels, the minimap window and the SVG render.
local Data = require("@shared/Data")
local MapModel = require("@shared/Map/MapModel")
local Minimap = require("@client/Map/Minimap")

return function(t)
	local data = Data.default()
	local map = MapModel.fromData({
		lots = data:lots(),
		roads = data:roads(),
		lotTypes = require("../../generated/LotTypes") :: any,
		extensions = require("../../generated/TerrainExtensions") :: any,
	})

	t.test("projection: +Z is up, +X is left; unproject inverts project", function()
		local u0, v0 = MapModel.project(map, 0, 0)
		local _, vn = MapModel.project(map, 0, 100)
		local ue, _2 = MapModel.project(map, 100, 0)
		t.truthy(vn < v0, "north is up")
		t.truthy(ue < u0, "+X is to the left")
		local x, z = MapModel.unproject(map, MapModel.project(map, 123.5, -456.25))
		t.near(x, 123.5, 1e-9)
		t.near(z, -456.25, 1e-9)
	end)

	t.test("layers: every lot with a footprint and every axis road is on the map", function()
		t.truthy(#map.lots >= 240, `{#map.lots} lots`)
		t.truthy(#map.roads >= 100, `{#map.roads} roads`)
		for _, r in MapModel.layers(map) do
			for _, p in { { r.x0, r.z0 }, { r.x1, r.z1 } } do
				local u, v = MapModel.project(map, p[1], p[2])
				t.truthy(u >= -1e-9 and u <= 1 + 1e-9 and v >= -1e-9 and v <= 1 + 1e-9, `{r.id} inside`)
			end
		end
		local names = {}
		for _, l in MapModel.labels(map) do
			names[l.text] = true
		end
		t.truthy(names["OLD TOWN CORE"] and names["BELLWETHER QUAY"] and names["OFF-ROAD"])
	end)

	t.test("minimap window and SVG render", function()
		local w = MapModel.view(map, 0, 0, 200)
		t.truthy(w.u1 > w.u0 and w.v1 > w.v0)
		-- the minimap layout puts the player at the panel centre and radius studs across half the panel
		local l = Minimap.layout(map, 250, -120, 400, 220)
		local u, v = MapModel.project(map, 250, -120)
		t.near(l.offsetX + u * l.canvasW, 110, 1e-9)
		t.near(l.offsetY + v * l.canvasH, 110, 1e-9)
		t.near(l.canvasW / (map.bounds.maxX - map.bounds.minX), 220 / 800, 1e-12)
		local svg = MapModel.svg(map, { width = 512 })
		t.truthy(string.find(svg, "<svg", 1, true) ~= nil)
		local _, rects = string.gsub(svg, "<rect", "")
		t.truthy(rects > #map.lots + #map.roads, `{rects} rects`)
	end)
end
