--!strict
-- The bowling alley's layout and its ball-return tunnels (brief v2 §13a: "the ball-return tunnel is a real
-- squirrel route: a squirrel can run the length of it under the lane and pop out at the rack"; BUILD_PLAN W3c
-- #15). data/attractions.json -> generated/Attractions -> the Routes Registry (Shared/Data); the routes sit in
-- the ducts AlleyLayout gives the bake; and a squirrel run through Movement/SquirrelMotor (the same motor the
-- client drives) walks into the vent from the alley, auto-switches into the tunnel, runs under the lane and
-- stops at the hood mouth on the rack, from where Space leaps toward the bowler.
local AlleyLayout = require("@shared/Attractions/AlleyLayout")
local Data = require("@shared/Data")
local Height = require("@shared/World/Height")
local RailWorld = require("@shared/Movement/RailWorld")
local SquirrelMotor = require("@shared/Movement/SquirrelMotor")

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

	t.test("placement: the floor is above the ground under the building; the alley paving above the alley ground", function()
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
		t.truthy(place.floorY + AlleyLayout.ALLEY_Y > alleyWorst, `alley {place.floorY + AlleyLayout.ALLEY_Y} vs {alleyWorst}`)
	end)

	t.test("routes: three vents and three tunnels, in the ducts under each pair, ending on the rack", function()
		t.eq(#mod.routes, 6)
		local reg = data:routes()
		for p = 1, 3 do
			local vent = reg:get(9000 + 2 * p - 1)
			local tunnel = reg:get(9000 + 2 * p)
			t.truthy(vent and tunnel, `pair {p} routes in the registry`)
			if not vent or not tunnel then
				continue
			end
			t.eq(vent.kind, "trunk")
			t.falsy(vent.flags.autoGrabExcluded, "walk-in can take the vent")
			t.eq(tunnel.kind, "bridge")
			t.eq(tunnel.origin, "attraction")
			local px = AlleyLayout.pairX(p)
			-- the vent's foot is on the alley paving outside the rear wall
			local foot = reg:foot(vent)
			local fX, fY, fD = AlleyLayout.toLocal(place, foot.x, foot.y, foot.z)
			t.truthy(fD > AlleyLayout.REAR_WALL_D + AlleyLayout.WALL_T, "foot outside the wall")
			t.near(fY, AlleyLayout.ALLEY_Y, 0.1)
			t.near(fX, px, 1e-3)
			-- every tunnel sample inside the duct (or the riser and the hood)
			local samples = reg:samples(tunnel)
			for _, s in samples do
				local X, Y, D = AlleyLayout.toLocal(place, s.x, s.y, s.z)
				t.truthy(math.abs(X - px) < AlleyLayout.DUCT_W / 2, "inside the duct across")
				if D > AlleyLayout.SHAFT_D1 then
					t.truthy(Y >= AlleyLayout.DUCT_FLOOR - 0.05 and Y < AlleyLayout.PIT_DUCT_CEIL - 1.0, `under the floor at D {D}: Y {Y}`)
				end
			end
			local endP = reg:pointAt(tunnel, 1)
			local _, eY, eD = AlleyLayout.toLocal(place, endP.x, endP.y, endP.z)
			t.truthy(eD < AlleyLayout.HOOD_D1, "pops out of the hood mouth")
			t.truthy(eY > AlleyLayout.RACK_Y - 0.1 and eY < AlleyLayout.HOOD_H, "at rack height")
			t.truthy(tunnel.length > 80, `the run is the length of the lane ({tunnel.length})`)
			-- the vent's end meets the tunnel's start
			local a, b = reg:pointAt(vent, 1), reg:pointAt(tunnel, 0)
			t.truthy(math.abs(a.x - b.x) + math.abs(a.y - b.y) + math.abs(a.z - b.z) < 1e-3)
		end
	end)

	t.test("a squirrel runs it: alley -> vent -> under the lane -> out on the rack; Space leaps at the bowler", function()
		local alleyY = place.floorY + AlleyLayout.ALLEY_Y
		local function groundAt(x: number, z: number, _refY: number?): number
			local _, _, D = AlleyLayout.toLocal(place, x, 0, z)
			if D > AlleyLayout.REAR_WALL_D then
				return alleyY
			end
			return math.max(Height.at(x, z), place.floorY)
		end
		local rail = RailWorld.build(data, function(x: number, z: number): number
			return groundAt(x, z)
		end)
		local world = {
			registry = rail.registry,
			index = rail.index,
			graph = rail.graph,
			trampolines = {},
			groundAt = groundAt,
			blocked = function(_x: number, _z: number, _y: number): boolean
				return false
			end,
			clamp = nil,
		}
		local p = 2
		local px = AlleyLayout.pairX(p)
		local sx, sy, sz = AlleyLayout.toWorld(place, px, AlleyLayout.ALLEY_Y, 88)
		local state = SquirrelMotor.new(sx, sy, sz)
		state.yaw = 0
		-- the camera behind the squirrel looking toward the building: moving "forward" goes to local -D
		local dX, dZ = AlleyLayout.dirToWorld(place, 0, -1)
		local camYaw = math.atan2(-dX, -dZ)
		local seen: { [string]: boolean } = {}
		local routesSeen: { [number]: boolean } = {}
		local frames = 0
		for _ = 1, 60 * 30 do
			frames += 1
			local input = SquirrelMotor.idleInput(camYaw)
			input.fw = 1
			local _, events = SquirrelMotor.step(state, input, 1 / 60, world :: any)
			for _, e in events do
				seen[e.kind] = true
				if e.routeId then
					routesSeen[e.routeId] = true
				end
			end
			if state.routeId == 9000 + 2 * p and state.railT >= 1 then
				break
			end
		end
		t.truthy(routesSeen[9000 + 2 * p - 1], "walked into the vent (walk-in grab)")
		t.truthy(seen.autoSwitch, "switched into the tunnel at the vent's end")
		t.eq(state.routeId, 9000 + 2 * p, "on the tunnel")
		t.near(state.railT, 1, 1e-6)
		local X, Y, D = AlleyLayout.toLocal(place, state.x, state.y, state.z)
		t.truthy(D < AlleyLayout.HOOD_D1 and math.abs(X - px) < 0.5 and Y > 1, `out on the rack ({X}, {Y}, {D})`)
		local seconds = frames / 60
		t.truthy(seconds > 3 and seconds < 20, `the run took {seconds} s`)
		-- pop out: Space leaps along the body's heading (toward the bowlers' end), not back into the hood
		local leap = SquirrelMotor.idleInput(camYaw)
		leap.leap = true
		SquirrelMotor.step(state, leap, 1 / 60, world :: any)
		t.eq(state.routeId, nil)
		local fx = 0
		for _ = 1, 30 do
			SquirrelMotor.step(state, SquirrelMotor.idleInput(camYaw), 1 / 60, world :: any)
		end
		local _, _, D2 = AlleyLayout.toLocal(place, state.x, state.y, state.z)
		t.truthy(D2 < D - 1, `leapt toward the bowlers (D {D} -> {D2})`)
		local _ = fx
	end)
end
