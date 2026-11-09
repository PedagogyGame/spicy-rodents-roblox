--!strict
-- tests/cheat/TestWorld: the headless world the S3 motor, validator and cheat harness run in
-- (Lune and the RailSpike engine task). Routes come from the compiled generated/ chunks (or any record
-- list); the ground is v5.4's flat core (terrain 0 within 104 u of the origin, routes_movement §8.4:
-- standing height = surface + 0.18 u) and the wall colliders are a few axis-aligned boxes placed where
-- the cheat harness needs them. World/Ground and Colliders replace both callbacks in W1.
local Graph = require("@shared/Routes/Graph")
local Registry = require("@shared/Routes/Registry")
local SpatialIndex = require("@shared/Routes/SpatialIndex")
local SquirrelMotor = require("@shared/Movement/SquirrelMotor")
local Units = require("@shared/Config/Units")

local TestWorld = {}

export type Box = { minX: number, maxX: number, minZ: number, maxZ: number, top: number }

export type World = SquirrelMotor.World & {
	boxes: { Box },
	groundHeight: number,
	radius: number,
}

TestWorld.STAND_HEIGHT = Units.st(0.18) -- getGroundAt: surface + 0.18 u (L6228)
TestWorld.RADIUS = Units.st(0.32) -- outdoorBlocked r (L6327)

-- blockedBy(boxes, radius)(x, z, y): true when the squirrel disc overlaps a box below its top
-- (outdoorBlocked step 3/4: inside w/2 + r, d/2 + r and y < top - 0.35 u).
function TestWorld.blockedBy(boxes: { Box }, radius: number): (number, number, number) -> boolean
	local margin = Units.st(0.35)
	return function(x: number, z: number, y: number): boolean
		for _, b in boxes do
			if
				x > b.minX - radius
				and x < b.maxX + radius
				and z > b.minZ - radius
				and z < b.maxZ + radius
				and y < b.top - margin
			then
				return true
			end
		end
		return false
	end
end

-- segmentCrossesBox(boxes, x0, z0, x1, z1, y): the validator's wall-pass test: does the straight
-- move cross a box (either endpoint inside, or the segment intersects the rectangle)?
function TestWorld.segmentCrossesBox(boxes: { Box }, x0: number, z0: number, x1: number, z1: number, y: number): boolean
	for _, b in boxes do
		if y < b.top then
			-- Liang-Barsky clip of the segment against the rectangle
			local dx, dz = x1 - x0, z1 - z0
			local t0, t1 = 0, 1
			local ok = true
			for _, pq in { { -dx, x0 - b.minX }, { dx, b.maxX - x0 }, { -dz, z0 - b.minZ }, { dz, b.maxZ - z0 } } do
				local p, q = pq[1], pq[2]
				if p == 0 then
					if q < 0 then
						ok = false
						break
					end
				else
					local r = q / p
					if p < 0 then
						if r > t1 then
							ok = false
							break
						elseif r > t0 then
							t0 = r
						end
					else
						if r < t0 then
							ok = false
							break
						elseif r < t1 then
							t1 = r
						end
					end
				end
			end
			if ok then
				return true
			end
		end
	end
	return false
end

-- build(opts): routes from loaders (default: the four generated chunks) + forks (default generated),
-- flat ground, optional boxes.
function TestWorld.build(opts: {
	loaders: { Registry.Loader }?,
	forks: { Graph.ForkRecord }?,
	boxes: { Box }?,
	groundHeight: number?,
}?): World
	local o = opts or {}
	local loaders = o.loaders
		or {
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
	local registry = Registry.new({ loaders = loaders })
	local index = SpatialIndex.build(registry)
	local forks = o.forks or (require("../../generated/Forks") :: any)
	local graph = Graph.build(registry, index, { forks = forks })
	local boxes = o.boxes or {}
	local groundHeight = (o.groundHeight or 0) + TestWorld.STAND_HEIGHT
	local world: World = {
		registry = registry,
		index = index,
		graph = graph,
		boxes = boxes,
		groundHeight = groundHeight,
		radius = TestWorld.RADIUS,
		groundAt = function(_x: number, _z: number, _refY: number): number
			return groundHeight
		end,
		blocked = TestWorld.blockedBy(boxes, TestWorld.RADIUS),
		clamp = nil,
		_trunkFeet = nil,
	}
	return world
end

return TestWorld
