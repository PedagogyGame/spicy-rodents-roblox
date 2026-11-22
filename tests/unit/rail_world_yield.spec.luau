--!strict
-- The rail world gives frames back while it builds (2026-11-22: 5,103 routes, about 2 s of work in Lune; the client
-- built it in one stretch and its loading screen froze for that long, several seconds on a phone). Movement/RailWorld
-- takes a `yield` that Registry.loadAll, the woods' expansion (Data, World/TreeShapes), SpatialIndex.build and
-- Graph.build call between small steps; Client/World/ClientWorld passes RailWorld.yielder(BUDGET, task.wait).
--   * the same world: built with a yield, the routes, the index, the graph (islands, transfers, end links, forks) and
--     the trampolines are exactly those of the build without one, and lookups answer the same;
--   * the stretches: the yield is called thousands of times and gives a frame back hundreds of times; no stretch of
--     work between two frames is longer than a 60 Hz frame and most are within RailWorld.BUDGET (Lune's own clock;
--     the compiled chunks are required by the first build, as the engine caches a ModuleScript's result: a chunk's
--     require is one step the build cannot split);
--   * the yielder itself on a made-up clock: it waits before the budget runs out, by the longest recent step, and one
--     long step does not make every later call wait;
--   * a chunk joins the registry whole: a reader that loads chunks while a load is yielding leaves no duplicate or
--     reordered route.
local Data = require("@shared/Data")
local Height = require("@shared/World/Height")
local RailWorld = require("@shared/Movement/RailWorld")
local Registry = require("@shared/Routes/Registry")
local Trampoline = require("@shared/Movement/Trampoline")

local FRAME = 1 / 60

return function(t)
	-- the reference: the world every rail user shares (built without a yield; it also requires every compiled chunk)
	local data = Data.default()
	local ref = RailWorld.get(data, Height.at)

	-- the same data read afresh (its own registry, woods and forks), built with a yield whose wait only takes notes
	local stretches: { number } = {}
	local calls, waits = 0, 0
	local mark = os.clock()
	local inner = RailWorld.yielder(RailWorld.BUDGET, function()
		waits += 1
		table.insert(stretches, os.clock() - mark)
		mark = os.clock()
	end)
	local fresh = Data.new(data._load)
	local built = RailWorld.build(fresh, Height.at, function()
		calls += 1
		inner()
	end)
	table.insert(stretches, os.clock() - mark)

	t.test("with a yield the world is the same: routes, index, graph, trampolines", function()
		local a, b = ref.registry:all(), built.registry:all()
		t.eq(#b, #a, "routes")
		t.truthy(#a > 5000, "the whole town's routes")
		for i, r in a do
			t.eq(b[i].id, r.id, `route {i}`)
			t.eq(b[i].sampleCount, r.sampleCount, `route {r.id} samples`)
		end
		t.eq(built.index:entryCount(), ref.index:entryCount(), "index entries")
		t.eq(built.index:cellCount(), ref.index:cellCount(), "index cells")
		local g, h = ref.graph, built.graph
		t.eq(h:islandCount(), g:islandCount(), "islands")
		t.eq(h:largestIsland(), g:largestIsland(), "largest island")
		t.eq(h:singletonCount(), g:singletonCount(), "singletons")
		t.eq(h.endLinkCount, g.endLinkCount, "ends with a link")
		t.eq(h.branchTipLinks, g.branchTipLinks, "branch tips with a link")
		local gt, gf = g:forkCounts()
		local ht, hf = h:forkCounts()
		t.eq(ht, gt, "trunks with forks")
		t.eq(hf, gf, "forks")
		t.deepEq(h:islands(), g:islands(), "islands, in order")
		for _, r in a do
			t.deepEq(h:transfers(r.id), g:transfers(r.id), `transfers of {r.id}`)
			t.deepEq(h:endLinks(r.id, true), g:endLinks(r.id, true), `end links at the start of {r.id}`)
			t.deepEq(h:endLinks(r.id, false), g:endLinks(r.id, false), `end links at the end of {r.id}`)
			t.deepEq(h:forks(r.id), g:forks(r.id), `forks of {r.id}`)
		end
		-- (the shared world caches the ground of whichever spec built it first: the sites are compared on this one's)
		local sites = Trampoline.sitesFromRegistry(ref.registry, Height.at)
		t.eq(#built.trampolines, #sites, "trampolines")
		t.deepEq(built.trampolines, sites, "trampoline sites")
	end)

	t.test("with a yield the lookups answer the same (a sample of every 25th route)", function()
		local a = ref.registry:all()
		for i = 1, #a, 25 do
			local r = a[i]
			local mine = built.registry:get(r.id) :: Registry.Route
			t.deepEq(built.registry:samples(mine), ref.registry:samples(r), `samples of {r.id}`)
			local p = ref.registry:pointAt(r, 0.5)
			local x, y, z = p.x + 0.7, p.y + 0.4, p.z - 0.5
			t.deepEq(built.index:nearest(x, y, z, 6), ref.index:nearest(x, y, z, 6), `nearest by {r.id}`)
			t.deepEq(
				built.index:nearestOnRoute(r.id, x, y, z, 6),
				ref.index:nearestOnRoute(r.id, x, y, z, 6),
				`nearest on {r.id}`
			)
			t.eq(built.graph:islandOf(r.id), ref.graph:islandOf(r.id), `island of {r.id}`)
		end
	end)

	t.test("the yield is called often and no stretch between frames is longer than a frame", function()
		table.sort(stretches)
		local worst = stretches[#stretches]
		local median = stretches[(#stretches + 1) // 2]
		print(
			string.format(
				"    rail world with a yield: %d calls, %d frames given back, stretches median %.1f ms, worst %.1f ms (budget %.0f ms); %.0f ms in all",
				calls,
				waits,
				median * 1000,
				worst * 1000,
				RailWorld.BUDGET * 1000,
				built.buildMs
			)
		)
		t.truthy(calls > 10000, `the yield called {calls} times`)
		t.truthy(waits > 50, `{waits} frames given back`)
		t.truthy(median <= RailWorld.BUDGET, `median stretch {median * 1000} ms within the budget`)
		t.truthy(worst <= FRAME, `the longest stretch {worst * 1000} ms within a 60 Hz frame (re-run alone under load)`)
	end)

	t.test("yielder: waits before the budget runs out, by the longest recent step", function()
		local now = 0
		local starts: { number } = {}
		local resumedAt = 0
		local y = RailWorld.yielder(0.008, function()
			table.insert(starts, now - resumedAt)
			resumedAt = now
		end, function(): number
			return now
		end)
		-- steady steps of 1 ms: a frame given back after 7 ms of work, never 8 or more
		for _ = 1, 100 do
			now += 0.001
			y()
		end
		t.truthy(#starts >= 12, `{#starts} waits over 100 ms of 1 ms steps`)
		for i, s in starts do
			t.truthy(s < 0.008 + 1e-9, `stretch {i}: {s * 1000} ms`)
		end
		-- one long step (a chunk's require, 20 ms) is waited out after, and the steps after it are not each a frame
		local before = #starts
		now += 0.02
		y()
		t.eq(#starts, before + 1, "the long step ends in a wait")
		for _ = 1, 40 do
			now += 0.001
			y()
		end
		local after = #starts - before - 1
		t.truthy(after >= 4 and after <= 10, `{after} waits over the next 40 ms of 1 ms steps`)
	end)

	t.test("a chunk joins the registry whole: a reader in the middle of a yielding load", function()
		local function chunk(first: number, n: number): { Registry.RouteRecord }
			local out: { Registry.RouteRecord } = {}
			for i = 0, n - 1 do
				local x = (first + i) * 10
				table.insert(out, {
					id = first + i,
					name = `test {first + i}`,
					kind = "wire",
					points = { { x, 5, 0 }, { x + 4, 5, 0 } },
					length = 4,
					surfaceRadius = 0.2,
				})
			end
			return out
		end
		local reg: Registry.Registry
		local readerRan = false
		reg = Registry.new({
			loaders = {
				function()
					return chunk(1, 3)
				end,
				function()
					return chunk(4, 3)
				end,
				function()
					return chunk(7, 2)
				end,
			},
		})
		-- the yield reads the registry (as a client script could while the build waits a frame): the first time, all
		-- the chunks load under the yielding load's feet
		local all = reg:loadAll(function()
			if not readerRan then
				readerRan = true
				t.eq(#reg:all(), 8, "the reader sees every chunk")
			end
		end)
		t.truthy(readerRan, "the reader ran during the load")
		t.eq(#all, 8, "no route twice")
		for i, r in all do
			t.eq(r.id, i, `route {i} in order`)
		end
		t.eq(reg:loadedChunks(), 3, "every chunk loaded once")
	end)
end
