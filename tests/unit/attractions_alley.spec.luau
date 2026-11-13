--!strict
-- The bowling alley's layout and its ball returns (brief v2 §13a: "the ball-return tunnel is a real squirrel route: a
-- squirrel can run the length of it under the lane and pop out at the rack"; BUILD_PLAN W3c #15; BRIEF_ADDENDUM D6).
-- data/attractions.json -> generated/Attractions -> the Routes Registry (Shared/Data): one enclosed run per pair of
-- lanes (Shared/Routes/Enclosure, kind "tunnel") from the grille in the alley wall to the hood's mouth over the rack,
-- in the duct AlleyLayout gives the bake. The squirrel running it on the real baked building is in
-- attractions_runthrough.spec.
local AlleyLayout = require("@shared/Attractions/AlleyLayout")
local Data = require("@shared/Data")
local Height = require("@shared/World/Height")
local Enclosure = require("@shared/Routes/Enclosure")

return function(t)
	local data = Data.default()
	local mod = data:module("Attractions") :: any
	local alley = mod.attractions[1]
	local place = alley.place

	t.test("layout: six lanes in three pairs, pins in a triangle, release and rack inside the lane block", function()
		t.eq(AlleyLayout.LANES, 6)
		t.near(AlleyLayout.PITCH, 6.2, 1e-9)
		t.near(AlleyLayout.laneX(1), -15.5, 1e-9)
		t.near(AlleyLayout.laneX(6), 15.5, 1e-9)
		t.near(AlleyLayout.pairX(2), 0, 1e-9)
		t.eq(AlleyLayout.pairOf(3), 2)
		t.eq(AlleyLayout.sideOf(3), -1)
		local spots = AlleyLayout.pinSpots()
		t.eq(#spots, 10)
		-- pin 7 back left, pin 10 back right, the head pin in front
		t.truthy(spots[7][1] < 0 and spots[10][1] > 0 and spots[1][2] == 0)
		for lane = 1, 6 do
			local x, _, d = AlleyLayout.release(lane, 1)
			t.truthy(math.abs(x - AlleyLayout.laneX(lane)) < AlleyLayout.LANE_W / 2, "release on the bed")
			t.truthy(d < AlleyLayout.FOUL_D)
			local rx, ry, rd = AlleyLayout.rackSlot(lane)
			t.near(rx, AlleyLayout.pairX(AlleyLayout.pairOf(lane)), 1e-9)
			t.truthy(rd < AlleyLayout.HOOD_D1 and rd > AlleyLayout.RACK_D1)
			t.truthy(ry > AlleyLayout.RACK_Y)
		end
		-- local <-> world round trip, any yaw
		for _, yaw in { 0, 0.7, -2 } do
			local p = { x = 10, z = -20, floorY = 3, yaw = yaw }
			local x, y, z = AlleyLayout.toWorld(p, 4, 1, 30)
			local X, Y, D = AlleyLayout.toLocal(p, x, y, z)
			t.near(X, 4, 1e-9)
			t.near(Y, 1, 1e-9)
			t.near(D, 30, 1e-9)
		end
		local x0, _, z0 = AlleyLayout.toWorld(place, 0, 0, 0)
		local x1, _, z1 = AlleyLayout.toWorld(place, 0, 0, 10)
		local dx, dz = AlleyLayout.dirToWorld(place, 0, 1)
		t.near((x1 - x0) / 10, dx, 1e-9)
		t.near((z1 - z0) / 10, dz, 1e-9)
	end)

	t.test(
		"placement: the floor is above the ground under the building; the alley paving above the alley ground",
		function()
			local fp = alley.footprint
			local worst, alleyWorst = -math.huge, -math.huge
			for X = AlleyLayout.X0, AlleyLayout.X1, 2 do
				for D = AlleyLayout.FRONT_D, AlleyLayout.REAR_WALL_D, 2 do
					local x, _, z = AlleyLayout.toWorld(place, X, 0, D)
					worst = math.max(worst, Height.at(x, z))
				end
				for D = AlleyLayout.REAR_WALL_D + 1, fp.d1, 2 do
					local x, _, z = AlleyLayout.toWorld(place, X, 0, D)
					alleyWorst = math.max(alleyWorst, Height.at(x, z))
				end
			end
			t.truthy(place.floorY > worst + 0.3, `floor {place.floorY} vs ground {worst}`)
			t.truthy(
				place.floorY + AlleyLayout.ALLEY_Y > alleyWorst,
				`alley {place.floorY + AlleyLayout.ALLEY_Y} vs {alleyWorst}`
			)
		end
	)

	t.test("dartboard: 20 at the top, +x on the thrower's right, round trip through boardFromLocal", function()
		local b = AlleyLayout.board()
		local X, Y, D = AlleyLayout.boardPoint(0, 100)
		t.near(X, b.x, 1e-9)
		t.truthy(Y > b.y, "+y is up")
		-- the thrower stands at the oche facing the board (local +X); their right is forward x up in world axes
		local fx, fz = AlleyLayout.dirToWorld(place, 1, 0)
		local rightX, rightZ = -fz, fx
		local _, _, Dr = AlleyLayout.boardPoint(100, 0)
		local wx0, _, wz0 = AlleyLayout.toWorld(place, b.x, b.y, b.d)
		local wx1, _, wz1 = AlleyLayout.toWorld(place, b.x, b.y, Dr)
		t.truthy((wx1 - wx0) * rightX + (wz1 - wz0) * rightZ > 0, "+x lies to the thrower's right")
		local xmm, ymm = AlleyLayout.boardFromLocal(Y, D)
		t.near(xmm, 0, 1e-6)
		t.near(ymm, 100, 1e-6)
	end)

	t.test("routes: one enclosed run per pair, grille to hood, in the duct, its two mouths and a crawl", function()
		t.eq(#mod.routes, 3)
		local reg = data:routes()
		for p = 1, 3 do
			local run = reg:get(9000 + 2 * p)
			t.truthy(run ~= nil, `pair {p} route in the registry`)
			if not run then
				continue
			end
			t.eq(run.kind, "tunnel")
			t.eq(run.origin, "attraction")
			local spec = run.enclosure :: any
			t.eq(spec.id, `alley.return.{p}`)
			t.falsy(spec.climb)
			t.eq(#spec.mouths, 2)
			t.eq(spec.mouths[1].opens, "ground")
			t.eq(spec.mouths[2].opens, "ledge")
			local px = AlleyLayout.pairX(p)
			-- the grille mouth stands on the alley paving outside the rear wall, and opens toward the alley (+D)
			local foot = reg:foot(run)
			local fX, fY, fD = AlleyLayout.toLocal(place, foot.x, foot.y, foot.z)
			t.truthy(fD > AlleyLayout.REAR_WALL_D + AlleyLayout.WALL_T + 1, "the grille's mouth outside the wall")
			t.near(fY, AlleyLayout.ALLEY_Y, 0.05)
			t.near(fX, px, 1e-3)
			local ox, oz = AlleyLayout.dirToWorld(place, 0, 1)
			t.near(spec.mouths[1].out.x, ox, 1e-6)
			t.near(spec.mouths[1].out.z, oz, 1e-6)
			-- every sample is inside the duct across; from the top of the vent ramp to the riser, under the floor
			for _, s in reg:samples(run) do
				local X, Y, D = AlleyLayout.toLocal(place, s.x, s.y, s.z)
				t.truthy(math.abs(X - px) < AlleyLayout.DUCT_W / 2, "inside the duct across")
				if D > AlleyLayout.SHAFT_D1 and D < AlleyLayout.REAR_WALL_D - 1.6 then
					t.truthy(
						Y >= AlleyLayout.DUCT_FLOOR - 0.05 and Y < AlleyLayout.PIT_DUCT_CEIL - 1.0,
						`under the floor at D {D}: Y {Y}`
					)
				end
			end
			-- the end: the head in the hood's mouth over the rack, the ledge mouth opening toward the bowlers (-D)
			local endP = reg:pointAt(run, 1)
			local _, eY, eD = AlleyLayout.toLocal(place, endP.x, endP.y, endP.z)
			t.truthy(eD < AlleyLayout.HOOD_D1 + 0.2 and eD > AlleyLayout.HOOD_D1 - 0.2, `at the hood's face ({eD})`)
			t.truthy(eY > AlleyLayout.RACK_Y - 0.1 and eY < AlleyLayout.HOOD_H, "at rack height")
			local bx, bz = AlleyLayout.dirToWorld(place, 0, -1)
			t.near(spec.mouths[2].out.x, bx, 1e-6)
			t.near(spec.mouths[2].out.z, bz, 1e-6)
			t.truthy(run.length > 85, `the run is the length of the lane ({run.length})`)
			-- the crawl covers the stretch under the pits (DECK_END .. the pit's back)
			local h, crawl = Enclosure.headroom(spec, 0.22)
			t.truthy(crawl and h >= Enclosure.BODY.crawlHeight)
			for _, D in { AlleyLayout.DECK_END + 0.1, AlleyLayout.PIT_END + 0.2 } do
				local lo, hi = 0, 0.5
				for _ = 1, 50 do
					local mid = (lo + hi) / 2
					local q = reg:pointAt(run, mid)
					local _, _, d = AlleyLayout.toLocal(place, q.x, q.y, q.z)
					if d > D then
						lo = mid
					else
						hi = mid
					end
				end
				local _, inCrawl = Enclosure.headroom(spec, lo)
				t.truthy(inCrawl, `crawl at D {D}`)
			end
		end
	end)
end
