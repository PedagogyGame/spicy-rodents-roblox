--!strict
-- ReplicatedStorage.Shared.Movement.RailWorld
-- Builds (once) the Routes world every rail user shares: Registry over the compiled routes, the
-- SpatialIndex, the Graph with the compiled canopy forks, and the trampoline sites from the
-- registry's trampoline routes (BUILD_PLAN §1.4 Routes/*, §4.4 #3 "squirrels run routes", #5).
-- The server's AI (Server/AI/TownAI) and the client's squirrel controller call `get(data)`.
-- Interface: build(data, groundAt?) -> World; get(data, groundAt?) -> World (cached per data)
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
	buildMs: number,
}

local RailWorld = {}

local cache: { [any]: World } = setmetatable({}, { __mode = "k" }) :: any

function RailWorld.build(data: any, groundAt: ((x: number, z: number) -> number)?): World
	local t0 = os.clock()
	local registry = data:routes()
	local index = SpatialIndex.build(registry)
	local forks = data:forks()
	local graph = Graph.build(registry, index, { forks = if forks and #forks > 0 then forks else nil })
	return {
		registry = registry,
		index = index,
		graph = graph,
		trampolines = Trampoline.sitesFromRegistry(registry, groundAt),
		buildMs = (os.clock() - t0) * 1000,
	}
end

function RailWorld.get(data: any, groundAt: ((x: number, z: number) -> number)?): World
	local w = cache[data]
	if not w then
		w = RailWorld.build(data, groundAt)
		cache[data] = w
	end
	return w
end

return RailWorld
