--!strict
-- tools/bake/alley/StreetFront: what the alley's front on Bowl Lane lacked once the lane was built (the street is
-- tools/bake/bowl_lane; the canopy, the doors, the signs over each stretch of the front and the pylon are Shell's
-- and Forecourt's): in the strip of lawn between the front wall and the lane, inside the footprint, clear of the
-- landing, the ramp, the pylon and the lamp posts, each piece standing on the ground where it is (the site falls
-- about 6 studs from the west end of the front to the east):
--   BikeRack    a concrete pad east of the ramp's foot, four steel hoops and one bicycle parked in them;
--   Bench       two benches facing the street, one each side of the entrance, with a litter bin beside each;
--   Planter     brick planters with shrubs along the front wall under the ball shop's, the gift shop's and the
--               snack bar's windows.
-- Plain parts, mild. Interface: build(kit, root) -> nothing; BUDGET

local AlleyLayout = require("../../../src/shared/Attractions/AlleyLayout")
local Height = require("../../../src/shared/World/Height")
local Shell = require("./Shell")

local StreetFront = {}

StreetFront.BUDGET = 70

local L = AlleyLayout
local C = Shell.C
local STEEL = { 70, 74, 80 }
local BIKE = { 190, 40, 40 }
local SHRUB = { 64, 112, 52 }

-- the ground's height under a local point, local Y (the terrain under the front lawn)
local function groundY(kit: any, X: number, D: number): number
	local p = kit:cf(X, 0, D).Position
	return Height.at(p.X, p.Z) - p.Y
end

-- the highest and lowest ground over a local rectangle (its corners and middle)
local function span(kit: any, x0: number, x1: number, d0: number, d1: number): (number, number)
	local lo, hi = math.huge, -math.huge
	for _, x in { x0, (x0 + x1) / 2, x1 } do
		for _, d in { d0, (d0 + d1) / 2, d1 } do
			local g = groundY(kit, x, d)
			lo, hi = math.min(lo, g), math.max(hi, g)
		end
	end
	return lo, hi
end

local function bikeRack(kit: any, root: any)
	local m = kit:model(root, "BikeRack")
	local x0, x1, d0, d1 = 34, 41.5, -80.5, -77.2
	local lo, hi = span(kit, x0, x1, d0, d1)
	local top = hi + 0.15
	kit:box(m, "Pad", x0, x1, lo - 0.4, top, d0, d1, C.concrete, "Concrete")
	-- four hoops across the pad (each two uprights and a top bar), a bike's length apart from the front edge
	for k = 0, 3 do
		local x = x0 + 1.2 + k * 1.7
		local da, db = d0 + 0.9, d0 + 2.4
		for _, d in { da, db } do
			kit:box(m, "HoopPost", x - 0.08, x + 0.08, top, top + 2.4, d - 0.08, d + 0.08, STEEL, "Metal")
		end
		kit:box(m, "HoopTop", x - 0.08, x + 0.08, top + 2.4, top + 2.56, da - 0.08, db + 0.08, STEEL, "Metal")
	end
	-- a bicycle in the second hoop, its front wheel toward the building
	local bx = x0 + 1.2 + 1.7 + 0.35
	local r = 1.05
	local back, front = d0 - 0.2 + r, d0 - 0.2 + r + 3.3
	for _, d in { back, front } do
		kit:cyl(m, "Wheel", bx, top + r, d, 0.14, r * 2, "X", { 30, 30, 32 }, "Rubber", { collide = false })
	end
	local seatY, barY = top + 2.6, top + 2.9
	kit:rod(m, "Frame", bx, top + r, back, bx, seatY - 0.2, back + 1.1, 0.14, BIKE, "Metal")
	kit:rod(m, "FrameTop", bx, seatY - 0.3, back + 1.1, bx, barY - 0.3, front - 0.4, 0.14, BIKE, "Metal")
	kit:rod(m, "FrameDown", bx, top + r + 0.1, back + 1.6, bx, barY - 0.3, front - 0.4, 0.14, BIKE, "Metal")
	kit:rod(m, "Fork", bx, barY, front - 0.4, bx, top + r, front, 0.12, STEEL, "Metal")
	kit:box(m, "Saddle", bx - 0.18, bx + 0.18, seatY - 0.2, seatY, back + 0.8, back + 1.5, { 30, 30, 32 }, "Leather", {
		collide = false,
	})
	kit:box(m, "Handlebar", bx - 0.7, bx + 0.7, barY, barY + 0.1, front - 0.5, front - 0.35, STEEL, "Metal", {
		collide = false,
	})
end

local function benches(kit: any, root: any)
	for i, bench in L.STREET_BENCHES do
		local m = kit:model(root, `Bench{i}`)
		local x0, x1 = bench[1], bench[2]
		local d0, d1 = L.STREET_BENCH_D[1], L.STREET_BENCH_D[2] -- the seat (its back toward the building)
		local _, hi = span(kit, x0, x1, d0, d1)
		local seat = hi + 1.5
		for _, x in { x0 + 0.5, x1 - 0.5 } do
			kit:box(m, "Leg", x - 0.15, x + 0.15, hi - 0.4, seat, d0 + 0.2, d1, STEEL, "Metal")
		end
		kit:box(m, "Seat", x0, x1, seat, seat + 0.2, d0, d1, { 120, 82, 50 }, "Wood")
		kit:box(m, "Back", x0, x1, seat + 0.4, seat + 1.6, d1 - 0.15, d1, { 120, 82, 50 }, "Wood")
		-- the litter bin on the side away from the entrance
		local bxx = if i == 1 then x0 - 1.2 else x1 + 1.2
		local g = groundY(kit, bxx, (d0 + d1) / 2)
		kit:cyl(m, "Bin", bxx, g + 1.2, (d0 + d1) / 2, 2.4, 1.3, "Y", { 40, 70, 60 }, "Metal")
		kit:cyl(m, "BinLid", bxx, g + 2.5, (d0 + d1) / 2, 0.2, 1.4, "Y", STEEL, "Metal", { collide = false })
	end
end

local function planters(kit: any, root: any)
	local m = kit:model(root, "Planters")
	local front = L.FRONT_D - L.WALL_T -- the front wall's outer face
	local d0, d1 = front - 2.4, front - 0.1
	for _, run in { { -21, -7 }, { 41, 53 }, { 60, 72 }, { 74, 86 } } do
		local x0, x1 = run[1], run[2]
		local lo, hi = span(kit, x0, x1, d0, d1)
		local top = hi + 1.1
		kit:box(m, "Planter", x0, x1, lo - 0.3, top, d0, d1, C.brickDark, "Brick")
		kit:box(
			m,
			"PlanterSoil",
			x0 + 0.15,
			x1 - 0.15,
			top - 0.05,
			top + 0.05,
			d0 + 0.15,
			d1 - 0.15,
			{ 70, 52, 36 },
			"Ground",
			{
				collide = false,
			}
		)
		for k = 0, 1 do
			local x = x0 + (x1 - x0) * (0.25 + k * 0.5)
			kit:ball(m, "Shrub", x, top + 0.6, (d0 + d1) / 2, 1.8, SHRUB, "Grass", { collide = false })
		end
	end
end

function StreetFront.build(kit: any, root: any)
	local before = kit.count
	local m = kit:model(root, "StreetFront")
	bikeRack(kit, m)
	benches(kit, m)
	planters(kit, m)
	m:SetAttribute("Parts", kit.count - before)
end

return StreetFront
