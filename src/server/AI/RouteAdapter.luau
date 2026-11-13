--!strict
-- ServerScriptService.Server.AI.RouteAdapter
-- Presents the real Routes world (Shared/Routes Registry + Graph, from Shared/Movement/RailWorld)
-- in the RouteLike shape the minimal Squirrel brain and HumanAIMotor's rail mode read (BUILD_PLAN
-- §4.4 #3 "squirrels run routes"; replaces the S5 spike's hard-coded SpikeRoutes subset, which stays
-- for the S5/S19 scenarios). A RouteLike is { id, kind, length, points = { {x, y, z} }, links =
-- { { s, to, toS } } }: points are the harvested samples (sampleCount from the record, rule 3),
-- length is the polyline's arc length, links are the Graph's transfer pairs (any sample pair within
-- 1.7 u, routes_movement §3) at their closest sample pair. Links are computed on first use per route. A link into or
-- out of an enclosed run (Shared/Routes/Enclosure: the ball return, a hollow tree) is kept only where the enclosure's
-- rules allow it at that pair (Enclosure.allows: a mouth that names the other route, or one enclosure), so a brain
-- never steps through a wall; with no enclosed routes every link is as before.
-- Interface: new(railWorld) -> Adapter { routes, byId(id), count }
-- Pure; studs. No side effects on require.

local Import = require("../Import")
local Enclosure = Import.shared("Routes/Enclosure") :: typeof(require("../../shared/Routes/Enclosure"))

export type Link = { s: number, to: number, toS: number }
export type RouteLike = { id: number, kind: string, length: number, points: { { number } }, links: { Link } }
export type Adapter = {
	routes: { RouteLike },
	byId: (id: number) -> RouteLike?,
	count: number,
}

local RouteAdapter = {}

local function cumulative(points: { { number } }): { number }
	local cum = { 0 }
	for i = 2, #points do
		local a, b = points[i - 1], points[i]
		local dx, dy, dz = b[1] - a[1], b[2] - a[2], b[3] - a[3]
		cum[i] = cum[i - 1] + math.sqrt(dx * dx + dy * dy + dz * dz)
	end
	return cum
end

function RouteAdapter.new(rail: any): Adapter
	local registry = rail.registry
	local graph = rail.graph
	local byId: { [number]: RouteLike } = {}
	local cums: { [number]: { number } } = {}
	local list: { RouteLike } = {}

	local function linksOf(self: any): { Link }
		local id = self.id
		local out: { Link } = {}
		local pa = self.points
		local ca = cums[id]
		for _, other in graph:transfers(id) do
			local ob = byId[other]
			if ob then
				local pb = ob.points
				local best, bi, bj = math.huge, 1, 1
				for i = 1, #pa do
					local a = pa[i]
					for j = 1, #pb do
						local b = pb[j]
						local dx, dy, dz = a[1] - b[1], a[2] - b[2], a[3] - b[3]
						local d = dx * dx + dy * dy + dz * dz
						if d < best then
							best, bi, bj = d, i, j
						end
					end
				end
				local ra, rb = registry:get(id), registry:get(other)
				local walled = ra and rb and (ra.enclosure or rb.enclosure)
				if
					not walled
					or Enclosure.allows(
						ra :: any,
						(bi - 1) / math.max(#pa - 1, 1),
						rb :: any,
						(bj - 1) / math.max(#pb - 1, 1)
					)
				then
					table.insert(out, { s = ca[bi], to = other, toS = cums[other][bj] })
				end
			end
		end
		table.sort(out, function(a, b)
			return a.s < b.s
		end)
		rawset(self, "links", out)
		return out
	end
	local meta = {
		__index = function(self: any, k: string): any
			if k == "links" then
				return linksOf(self)
			end
			return nil
		end,
	}

	for _, route in registry:all() do
		local pts = {}
		for i, p in registry:samples(route) do
			pts[i] = { p.x, p.y, p.z }
		end
		if #pts < 2 then
			continue
		end
		local cum = cumulative(pts)
		cums[route.id] = cum
		local r = setmetatable({ id = route.id, kind = route.kind, length = cum[#cum], points = pts }, meta)
		local like = (r :: any) :: RouteLike
		byId[route.id] = like
		table.insert(list, like)
	end
	return {
		routes = list,
		byId = function(id: number): RouteLike?
			return byId[id]
		end,
		count = #list,
	}
end

return RouteAdapter
