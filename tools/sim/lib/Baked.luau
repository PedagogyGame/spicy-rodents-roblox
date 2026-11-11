--!strict
-- tools/sim/lib/Baked: the ground a player actually sees, as the bake builds it. The game's analytic
-- ground (World/Ground over World/Town) says a road is the terrain plus a small offset; the baked town
-- is different: every road is a chain of flat parts (worldgen/Plan.road: straight segments of at most
-- 40 studs, level ACROSS the road's whole width at the height of its centre line), the lots add ground
-- plates, slabs and decks, and the terrain voxels are written from World/Height. The top of that pile
-- under a point is worldgen/Surface.at over the same plans Bake.plans makes (lots and roads; props,
-- lamps and the skyline are not ground). Built once per process.
-- Interface: get() -> { at: (x, z, maxY?) -> (y, onPart), plans: { BuildPlan } }

local Height = require("@shared/World/Height")
local Bake = require("@worldgen/Bake")
local Plan = require("@worldgen/Plan")
local Surface = require("@worldgen/Surface")

local Baked = {}

export type World = { at: (x: number, z: number, maxY: number?) -> (number, boolean), plans: { any } }

local cached: World? = nil

-- get(): needs World/Height configured as the game configures it (Replay.run does that first).
function Baked.get(): World
	local w = cached
	if w then
		return w
	end
	local data = Bake.data()
	local parents = Plan.containment(data.lots)
	local plans = {}
	for _, lot in data.lots do
		table.insert(plans, Plan.plan(lot, lot.type, { parentId = parents[lot.id] }))
	end
	Plan.attachSlabs(plans)
	for _, road in data.roads do
		table.insert(plans, Plan.road(road, data.roads))
	end
	local surface = Surface.new(plans, Height.at)
	local built: World = {
		at = function(x: number, z: number, maxY: number?): (number, boolean)
			return Surface.at(surface, x, z, maxY)
		end,
		plans = plans,
	}
	cached = built
	return built
end

return Baked
