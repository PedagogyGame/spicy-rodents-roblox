--!strict
-- tests/lib/WoodsWorld: the town as WorldGen/WoodsPlan sees it, for the woods' placement tool
-- (tools/blender/trees/place_woods.luau) and the spec that holds every placement to the same rule
-- (tests/unit/woods.spec.luau). Built from Bake.data() and Bake.plans() (the town bake's own plans), generated/Expansion
-- (streets, pads, paths, venues, zones, the sky lift's cable), World/Colliders, Shared/Foraging/NutSpots, the
-- telephone wires (the routes the bake draws as wires) and every route tree (the bake's Tree_ plans with their crowns'
-- reach measured from their parts, and the D35 climbs: the Lookout Hill conifers, the sky lift's oaks and orchard).
--   WoodsWorld.new() -> Ctx { world, data, plans, routeTrees = { {x, z, reach, label} }, climbs }
-- Pure Lune; studs. Configures World/Height with the terrain extensions (as the bake does) and leaves it so.
local Bake = require("@worldgen/Bake")
local Colliders = require("@shared/World/Colliders")
local Data = require("@shared/Data")
local Height = require("@shared/World/Height")
local Kits = require("@worldgen/Kits")
local NutSpots = require("@shared/Foraging/NutSpots")
local RouteProps = require("@worldgen/Builders/RouteProps")
local WoodsPlan = require("@worldgen/WoodsPlan")

local WoodsWorld = {}

export type Ctx = {
	world: WoodsPlan.World,
	data: any,
	plans: { any },
	routeTrees: { { number | string } },
}

function WoodsWorld.new(): Ctx
	Height.configure(require("../../generated/TerrainExtensions") :: any)
	local data = Bake.data()
	local plans = Bake.plans(data)
	local d = Data.default()
	local reg = d:routes()
	-- every route tree the bake draws, with the reach of its parts round its foot
	local routeTrees: { { number | string } } = {}
	for _, p in plans do
		if p.kind == "props" and p.category == "tree" then
			local r = reg:get(p.attributes.TrunkRoute)
			if r then
				local f = r.points[1]
				local reach = 8
				for _, s in p.parts do
					local h = math.max(s.sx, s.sy, s.sz) / 2
					reach = math.max(reach, math.abs(s.cx - f.x) + h * 0.7, math.abs(s.cz - f.z) + h * 0.7)
				end
				table.insert(routeTrees, { f.x, f.z, math.min(reach, 60), p.attributes.Name or p.id })
			end
		end
	end
	-- the D35 climbs (trees other bakes draw): their crowns
	local woods = d:woods()
	local compiled = d:module("TreeShapes") :: any
	if compiled and compiled.woods then
		for _, cl in compiled.woods.climbs do
			table.insert(routeTrees, { cl.x, cl.z, cl.reach or 8, cl.label })
		end
	end
	local wires: { { { number } } } = {}
	for _, r in data.routes or {} do
		if RouteProps.classify(r :: any, Kits.routeProps) == "wire" then
			local line = {}
			for _, p in r.points do
				table.insert(line, { p[1], p[3] })
			end
			table.insert(wires, line)
		end
	end
	local ex = d:module("Expansion") :: any
	local rides: { { { number } } } = {}
	for _, r in ex.rides or {} do
		local line = {}
		for _, q in r.points or {} do
			if type(q) == "table" and #q >= 3 then
				table.insert(line, { q[1], q[3] })
			end
		end
		if #line >= 2 then
			table.insert(rides, line)
		end
	end
	local world = WoodsPlan.build(data, plans, Height.at, {
		expansion = ex,
		colliders = Colliders.fromData(d).boxes,
		-- (the spots under the woods' own nut trees came after them)
		nutSpots = (function(): any
			local out = {}
			for _, s in NutSpots.SPOTS do
				if not string.find(s.near, " woods ", 1, true) then
					table.insert(out, s)
				end
			end
			return out
		end)(),
		trees = routeTrees :: any,
		wires = wires,
		rides = rides,
		clamp = Height.worldClamp(),
		insideWater = Height.insideRiverWater,
	})
	local _ = woods
	return { world = world, data = d, plans = plans, routeTrees = routeTrees }
end

return WoodsWorld
