--!strict
-- ReplicatedStorage.Shared.Movement.RailWorld
-- Builds (once) the Routes world every rail user shares: Registry over the compiled routes, the
-- SpatialIndex, the Graph with the compiled canopy forks, and the trampoline sites from the
-- registry's trampoline routes (BUILD_PLAN §1.4 Routes/*, §4.4 #3 "squirrels run routes", #5).
-- The server's AI (Server/AI/TownAI) and the client's squirrel controller call `get(data)`.
-- Interface: build(data, groundAt?, yield?) -> World; get(data, groundAt?, yield?) -> World (cached per data);
--   empty() -> World (no routes: what the squirrel motor runs on while the real one is still building);
--   yielder(budget, wait, clock?) -> Routes/Registry.Yield; BUDGET
-- The build gives frames back (2026-11-22): with 5,103 routes (branch nooks, woods, lamp posts) it takes about 2 s in
-- Lune, longer on a phone, and the client builds it while its loading screen draws. Client/World/ClientWorld passes a
-- `yield` (yielder(BUDGET, task.wait)) that Registry.loadAll, the woods' expansion, SpatialIndex.build and Graph.build
-- call between small steps. The same steps run in the same order, so the world is the same with or without one
-- (tests/unit/rail_world_yield.spec.luau). The server builds it at start, before players act, without one.
-- Pure; studs. No side effects on require.

local Registry = require("../Routes/Registry")
local SpatialIndex = require("../Routes/SpatialIndex")
local Graph = require("../Routes/Graph")
local Trampoline = require("./Trampoline")

export type World = {
	registry: Registry.Registry,
	index: SpatialIndex.SpatialIndex,
	graph: Graph.Graph,
	trampolines: { Trampoline.Site },
	buildMs: number, -- start to finish: with a yield, the frames it gave back included
}

local RailWorld = {}

-- The longest stretch of work between two frames given back (seconds): half a 60 Hz frame, so the loading screen
-- keeps drawing on a phone. A compiled chunk's require is one step and cannot be split (the longest, 10 to 15 ms in
-- Lune).
RailWorld.BUDGET = 0.008

local cache: { [any]: World } = setmetatable({}, { __mode = "k" }) :: any

-- yielder(budget, wait, clock?): a Yield for build() that calls `wait` (task.wait in the engine) once about `budget`
-- seconds of work have passed since the last one. It stops early by the longest gap between two of its calls in this
-- stretch or the one before, so the next step is not the one that runs past the budget (the steps of one loop are
-- alike); by half the budget at most, so one long step (a chunk's require) does not make every call wait a frame.
-- `clock` defaults to os.clock.
function RailWorld.yielder(budget: number, wait: () -> (), clock: (() -> number)?): Registry.Yield
	local now = clock or os.clock
	local resumed = now()
	local last = resumed
	local longest, before = 0, 0 -- the longest gap between two calls in this stretch, and in the one before
	return function()
		local t = now()
		longest = math.max(longest, t - last)
		if t - resumed + math.min(math.max(longest, before), budget / 2) >= budget then
			wait()
			t = now()
			resumed = t
			before, longest = longest, 0
		end
		last = t
	end
end

function RailWorld.build(data: any, groundAt: ((x: number, z: number) -> number)?, yield: Registry.Yield?): World
	local t0 = os.clock()
	local registry = data:routes()
	local index = SpatialIndex.build(registry, nil, yield)
	local forks = data:forks()
	if yield then
		yield()
	end
	local graph = Graph.build(registry, index, { forks = if forks and #forks > 0 then forks else nil, yield = yield })
	return {
		registry = registry,
		index = index,
		graph = graph,
		trampolines = Trampoline.sitesFromRegistry(registry, groundAt),
		buildMs = (os.clock() - t0) * 1000,
	}
end

-- A rail world with no routes: the motor runs its ground, leap and wall code against it unchanged.
function RailWorld.empty(): World
	local registry = Registry.fromRecords({})
	local index = SpatialIndex.build(registry)
	return {
		registry = registry,
		index = index,
		graph = Graph.build(registry, index, nil),
		trampolines = {},
		buildMs = 0,
	}
end

-- get(data, groundAt?, yield?): the world for this data, built once. A yielding build is cached only when complete, so
-- a second caller meanwhile would build its own: the client has one caller (Client/World/ClientWorld).
function RailWorld.get(data: any, groundAt: ((x: number, z: number) -> number)?, yield: Registry.Yield?): World
	local w = cache[data]
	if not w then
		w = RailWorld.build(data, groundAt, yield)
		cache[data] = w
	end
	return w
end

return RailWorld
