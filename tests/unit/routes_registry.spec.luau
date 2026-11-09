--!strict
-- Routes/Registry, SpatialIndex and Graph over the compiled data (spike S3; BUILD_PLAN §6.2 "Routes/*",
-- D8 regression counts). Chunks are the real generated/Routes_*.luau (studs); the harvest JSON files
-- (HTML units) are the oracle for counts, sample counts, islands and end links.
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local Units = require("@shared/Config/Units")
local Registry = require("@shared/Routes/Registry")
local SpatialIndex = require("@shared/Routes/SpatialIndex")
local Graph = require("@shared/Routes/Graph")

local function loaders(): { Registry.Loader }
	return {
		function()
			return require("../../generated/Routes_01") :: any
		end,
		function()
			return require("../../generated/Routes_02") :: any
		end,
		function()
			return require("../../generated/Routes_03") :: any
		end,
		function()
			return require("../../generated/Routes_04") :: any
		end,
	}
end

return function(t)
	local harvest = serde.decode("json", fs.readFile("data/harvest/routes.json")).routes
	local harvestById: { [number]: any } = {}
	for _, r in harvest do
		harvestById[r.id] = r
	end

	t.test("lazy chunk loading: requiring loads nothing; get(id) loads chunks in order", function()
		local reg = Registry.new({ loaders = loaders() })
		t.eq(reg:loadedChunks(), 0)
		local r0 = reg:get(0)
		t.truthy(r0)
		t.eq(reg:loadedChunks(), 1)
		t.eq((r0 :: Registry.Route).kind, "roof")
		local r1331 = reg:get(1331)
		t.truthy(r1331)
		t.eq(reg:loadedChunks(), 4)
		t.eq(reg:get(5000), nil)
		t.eq(#reg:all(), 1332)
	end)

	local reg = Registry.new({ loaders = loaders() })
	local all = reg:all()

	t.test("1,332 routes, kind counts per routes_movement §1.4, ids 0..1331", function()
		t.eq(#all, 1332)
		local counts = reg:kindCounts()
		t.deepEq(counts, {
			roof = 99,
			trunk = 265,
			bridge = 78,
			fence = 12,
			trampoline = 1,
			wire = 150,
			branch = 715,
			lookout = 12,
		})
		for i, route in all do
			t.eq(route.id, i - 1, "ids in order")
		end
	end)

	t.test("sampleCount equals the harvest record for every route (never recomputed from the curve)", function()
		local total = 0
		for _, route in all do
			local h = harvestById[route.id]
			t.eq(route.sampleCount, h.sampleCount, `route {route.id}`)
			t.near(Units.u(route.length), h.length, 1e-9, `route {route.id} length`)
			total += route.sampleCount
		end
		t.eq(total, 81613)
		-- an explicit record field wins over the derivation
		local custom = Registry.fromRecords({
			{
				id = 1,
				name = "x",
				kind = "wire",
				points = { { 0, 0, 0 }, { 10, 0, 0 } },
				length = 10,
				surfaceRadius = 1,
				sampleCount = 77,
			},
		})
		t.eq((custom:get(1) :: Registry.Route).sampleCount, 77)
	end)

	t.test("per-route fields: visualOffset on the 72 apple boughs, center on 91 trunks, flags from names", function()
		local vo, center, excluded, poles, giants = 0, 0, 0, 0, 0
		for _, route in all do
			if route.visualOffset then
				vo += 1
				t.eq(route.kind, "branch")
				t.near(route.visualOffset, Units.st(0.3), 1e-9)
			end
			if route.center then
				center += 1
			end
			if route.flags.autoGrabExcluded then
				excluded += 1
			end
			if route.flags.isPole then
				poles += 1
			end
			if route.flags.isGiant then
				giants += 1
			end
			t.eq(route.flags.treeTravel, Registry.TREE_TRAVEL_KINDS[route.kind] == true)
		end
		t.eq(vo, 72)
		t.eq(center, 91)
		-- /downspout|gutter|ladder/i over the harvest names: 58 trunks, 24 bridges, 30 quay "gutter to ridge" roofs, 3 ladders
		t.eq(excluded, 115, "autoGrabExcluded count (harvest regex over 1,332 names)")
		t.eq(poles, 110, "telephone poles = the 110 utility supports (97 residential + 6 estate + 7 westside)")
		t.eq(giants, 3, "giant trunks")
	end)

	local index = SpatialIndex.build(reg)

	t.test("spatial index: 20-stud cells, 81,613 entries, 3,042 cells (harvest route_index.json)", function()
		t.near(index.cellSize, 20, 1e-9)
		t.eq(index:entryCount(), 81613)
		local routeIndex = serde.decode("json", fs.readFile("data/harvest/route_index.json"))
		t.eq(index:cellCount(), routeIndex.cellCount)
	end)

	t.test("spatial index: nearest() finds the closest sample and honours exclusion and maxDist", function()
		local route = reg:get(220) :: Registry.Route -- BUR OAK trunk, foot near (-34, 0.35, -33) u
		local foot = reg:foot(route)
		local hit = index:nearest(foot.x + 0.5, foot.y, foot.z, Units.st(3.4))
		t.truthy(hit)
		t.eq((hit :: SpatialIndex.Hit).routeId, 220)
		t.near((hit :: SpatialIndex.Hit).t, 0, 1e-9)
		local excluded = index:nearest(foot.x, foot.y, foot.z, Units.st(0.2), 220)
		t.eq(excluded, nil)
		t.eq(index:nearest(1e6, 0, 1e6, 10), nil)
	end)

	local graph = Graph.build(reg, index, { forks = require("../../generated/Forks") :: any })

	t.test("graph: 149 islands, largest 563, 40 singletons, 0 branch-tip auto-links (D8, §3.13 inv. 7)", function()
		t.eq(graph:islandCount(), 149)
		t.eq(graph:largestIsland(), 563)
		t.eq(graph:singletonCount(), 40)
		t.eq(graph.branchTipLinks, 0)
	end)

	t.test("graph: islands equal data/harvest/graph.json exactly", function()
		local g = serde.decode("json", fs.readFile("data/harvest/graph.json"))
		local islands = graph:islands()
		t.eq(#islands, g.islandCount)
		for i, island in g.islands do
			t.deepEq(islands[i], island, `island {i}`)
		end
	end)

	t.test("graph: end links equal data/harvest/graph.json (1,337 ends; to, t, gap within 1e-6 u)", function()
		local g = serde.decode("json", fs.readFile("data/harvest/graph.json"))
		t.eq(graph.endLinkCount, #g.endLinks)
		for _, entry in g.endLinks do
			local links = graph:endLinks(entry.from, entry.atStart)
			t.eq(#links, #entry.links, `route {entry.from} atStart={entry.atStart}`)
			for i, l in entry.links do
				t.eq(links[i].to, l.to, `route {entry.from} link {i}`)
				t.near(links[i].t, l.t, 1e-6)
				t.near(Units.u(links[i].gap), l.gap, 1e-6)
			end
		end
		-- a route without links at an end returns an empty list
		t.eq(#graph:endLinks(0, true), 0)
	end)

	t.test("graph: forks 95 trunks / 770 forks; forkOf, siblings and related()", function()
		local trunks, forks = graph:forkCounts()
		t.eq(trunks, 95)
		t.eq(forks, 770)
		local burOak = graph:forks(220)
		t.truthy(#burOak >= 5)
		for i = 2, #burOak do
			t.truthy(burOak[i].height >= burOak[i - 1].height, "sorted by height")
		end
		local f = graph:forkOf(221) :: Graph.Fork
		t.eq(f.trunk, 220)
		t.truthy(#graph:siblings(221) == #burOak - 1)
		t.truthy(graph:related(220, 221), "trunk-fork")
		t.truthy(graph:related(221, 224), "siblings")
		t.truthy(graph:related(4, 5), "end link ladder -> bridge")
		t.falsy(graph:related(0, 1331), "unrelated")
		t.eq(#graph:transfers(0), 0, "Chili's roof is a singleton")
	end)
end
