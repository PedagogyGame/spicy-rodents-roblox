--!strict
-- Shared/World/RoadSurface: the roads as the bake draws them, which the traffic ghosts are seated on.
--   * its tops are the baked road parts' tops (worldgen/Plan.road through worldgen/Surface), so a car
--     drawn on `ground` stands on the asphalt a player sees
--   * the kinds' offsets are worldgen/Kits.ROAD's
--   * a wide road follows the ground across its width as well as along it, and where two roads cross,
--     neither stands proud of the other by more than a kerb
--   * `rideAt` is the top inside a part and continuous over the seams between parts
local Data = require("@shared/Data")
local Height = require("@shared/World/Height")
local RoadSurface = require("@shared/World/RoadSurface")
local Plan = require("@worldgen/Plan")
local Kits = require("@worldgen/Kits")
local Surface = require("@worldgen/Surface")

return function(t)
	local data = Data.default()

	local function withTerrain(fn: () -> ())
		Height.configure(data:module("TerrainExtensions"))
		local ok, err = pcall(fn)
		Height.configure(nil)
		if not ok then
			error(err, 0)
		end
	end

	t.test("the kinds' offsets and solidity are worldgen/Kits.ROAD's", function()
		for kind, look in Kits.ROAD do
			t.eq(RoadSurface.OFFSET_U[kind], look.offsetU, kind)
			t.eq(RoadSurface.SOLID[kind], look.canCollide, kind)
		end
	end)

	t.test("topAt is the top of the baked road parts (Plan.road through worldgen/Surface)", function()
		withTerrain(function()
			local roads = data:roads()
			local plans = {}
			for _, road in roads do
				table.insert(plans, Plan.road(road, roads))
			end
			local baked = Surface.new(plans, function(_x: number, _z: number): number
				return -1000
			end)
			local shared = RoadSurface.new(roads)
			-- along every solid road, across its width, away from its ends
			local checked, worst = 0, 0
			for _, road in roads do
				if not RoadSurface.SOLID[road.kind] then
					continue
				end
				local x0, z0, x1, z1 = RoadSurface.endpoints(road)
				local len = math.sqrt((x1 - x0) ^ 2 + (z1 - z0) ^ 2)
				local ux, uz = (x1 - x0) / len, (z1 - z0) / len
				for k = 1, 9 do
					local a = len * (k / 10)
					for _, f in { -0.4, 0, 0.4 } do
						local x = x0 + ux * a - uz * f * road.width
						local z = z0 + uz * a + ux * f * road.width
						local ground = (RoadSurface.groundAt(x, z))
						local want, onPart = Surface.at(baked, x, z, ground + RoadSurface.MAX_ABOVE)
						local got = RoadSurface.topAt(shared, x, z, ground + RoadSurface.MAX_ABOVE)
						if onPart then
							t.truthy(got, `{road.id} at {x}, {z}`)
							worst = math.max(worst, math.abs((got :: number) - want))
							checked += 1
						end
					end
				end
			end
			t.truthy(checked > 2000, `checked {checked}`)
			t.near(worst, 0, 0.02, "the shared tops are the baked ones")
		end)
	end)

	t.test("the drawn roads follow the ground across their width: no road stands a kerb proud", function()
		withTerrain(function()
			local roads = data:roads()
			local shared = RoadSurface.new(roads)
			-- the commercial boulevard (65 st) and the cross street (72.5 st) where they cross, and the
			-- boulevard's eastbound lanes: level across, these stood 2.9 and 1.5 st off the terrain
			local worst = 0
			for x = 760, 1700, 2 do
				for _, z in { -16.4, -11.7, 11.7, 16.4, 22 } do
					local ground = Height.at(x, z)
					local top = RoadSurface.topAt(shared, x, z, ground + RoadSurface.MAX_ABOVE)
					if top then
						worst = math.max(worst, math.abs(top - ground))
					end
				end
			end
			t.truthy(worst < 0.45, `the boulevard's drawn top is at most {worst} st off the terrain`)
		end)
	end)

	t.test("rideAt is the top inside a part and continuous across the seams", function()
		withTerrain(function()
			local roads = data:roads()
			local shared = RoadSurface.new(roads)
			local ride = RoadSurface.ground(shared, Height.at)
			-- inside a segment, far from its edges: exactly the top
			-- (the boulevard runs 617.5..1702.5 in 55 segments: the middle of its 23rd)
			local x, z = 617.5 + (1702.5 - 617.5) / 55 * 22.5, 14
			local top = RoadSurface.topAt(shared, x, z, Height.at(x, z) + RoadSurface.MAX_ABOVE) :: number
			t.near(ride(x, z), top, 1e-9)
			-- along the boulevard's lanes (seams every 20 st, the cross street's edges): no step
			local worstStep = 0
			for _, lane in { -14, 14 } do
				local prev = ride(700, lane)
				for i = 1, 5000 do
					local px = 700 + i * 0.2
					local y = ride(px, lane)
					worstStep = math.max(worstStep, math.abs(y - prev))
					prev = y
				end
			end
			t.truthy(worstStep < 0.06, `largest change over 0.2 st: {worstStep}`)
		end)
	end)
end
