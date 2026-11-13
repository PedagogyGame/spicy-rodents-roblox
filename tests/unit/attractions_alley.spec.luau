--!strict
-- The bowling alley's layout and its ball-return tunnels (brief v2 §13a: "the ball-return tunnel is a real
-- squirrel route: a squirrel can run the length of it under the lane and pop out at the rack"; BUILD_PLAN W3c
-- #15). data/attractions.json -> generated/Attractions -> the Routes Registry (Shared/Data); the routes sit in
-- the ducts AlleyLayout gives the bake; and a squirrel run through Movement/SquirrelMotor (the same motor the
-- client drives) walks into the vent from the alley, auto-switches into the tunnel, runs under the lane and
-- stops at the hood mouth on the rack, from where Space leaps toward the bowler.
-- And the eighteen-lane floor plan (brief addendum D4, D5): the rooms, the openings, the games room's tables and
-- their clear floor, the staff posts and routes, the floors a body stands on, the backstage's anchor and the
-- ground kept for it. (That the BAKE follows the plan is tests/unit/attractions_alley_bake.spec.luau.)
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

	t.test(
		"layout: eighteen lanes in nine pairs, lanes 1 to 6 where the six-lane house had them, pins in a triangle",
		function()
			t.eq(AlleyLayout.LANES, 18)
			t.eq(AlleyLayout.PAIRS, 9)
			t.near(AlleyLayout.PITCH, 6.2, 1e-9)
			-- the six-lane house was centred on X 0: lane i stood at (i - 3.5) pitches
			for lane = 1, 6 do
				t.near(AlleyLayout.laneX(lane), (lane - 3.5) * 6.2, 1e-9)
			end
			t.near(AlleyLayout.laneX(18), 15.5 + 12 * 6.2, 1e-9)
			t.near(AlleyLayout.pairX(2), 0, 1e-9)
			t.near(AlleyLayout.pairX(9), 86.8, 1e-9)
			t.eq(AlleyLayout.pairOf(3), 2)
			t.eq(AlleyLayout.pairOf(18), 9)
			t.eq(AlleyLayout.sideOf(3), -1)
			t.near(AlleyLayout.LANE_BLOCK_X0, -18.6, 1e-9)
			t.near(AlleyLayout.LANE_BLOCK_X1, 93, 1e-9)
			-- every down-lane number is the six-lane house's
			t.eq(AlleyLayout.APPROACH_D, -15)
			t.eq(AlleyLayout.FOUL_D, 0)
			t.eq(AlleyLayout.HEAD_D, 56)
			t.eq(AlleyLayout.MACHINE_D1, 66.5)
			t.eq(AlleyLayout.REAR_WALL_D, 80.8)
			local spots = AlleyLayout.pinSpots()
			t.eq(#spots, 10)
			-- pin 7 back left, pin 10 back right, the head pin in front
			t.truthy(spots[7][1] < 0 and spots[10][1] > 0 and spots[1][2] == 0)
			for lane = 1, AlleyLayout.LANES do
				local x, _, d = AlleyLayout.release(lane, 1)
				t.truthy(math.abs(x - AlleyLayout.laneX(lane)) < AlleyLayout.LANE_W / 2, "release on the bed")
				t.truthy(d < AlleyLayout.FOUL_D)
				local rx, ry, rd = AlleyLayout.rackSlot(lane)
				t.near(rx, AlleyLayout.pairX(AlleyLayout.pairOf(lane)), 1e-9)
				t.truthy(rd < AlleyLayout.HOOD_D1 and rd > AlleyLayout.RACK_D1)
				t.truthy(ry > AlleyLayout.RACK_Y)
				t.truthy(x > AlleyLayout.LANE_BLOCK_X0 and x < AlleyLayout.LANE_BLOCK_X1)
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
			-- the placement is the six-lane house's: lane 1's foul line is where it always was in the world
			t.eq(place.x, 1300)
			t.eq(place.z, -420)
			t.eq(place.floorY, 16.5)
			t.eq(place.yaw, 0)
		end
	)

	t.test(
		"placement: the floor is above the ground under the building except where the plan cuts it; the alley paving above the alley ground",
		function()
			local function cut(X: number, D: number): AlleyLayout.Cut?
				for _, c in AlleyLayout.SITE_CUTS do
					if X >= c.x0 and X <= c.x1 and D >= c.d0 and D <= c.d1 then
						return c
					end
				end
				return nil
			end
			local worst, worstCut = -math.huge, -math.huge
			local function under(X: number, D: number)
				local x, _, z = AlleyLayout.toWorld(place, X, 0, D)
				local h = Height.at(x, z)
				local c = cut(X, D)
				if c then
					worstCut = math.max(worstCut, h)
					-- the cut reaches from under the floor slab to well above the ground it removes
					t.truthy(c.y0 < 0 and place.floorY + c.y1 > h + 3, `cut {c.id} over ground {h}`)
				else
					worst = math.max(worst, h)
				end
			end
			-- the hall (front wall to rear wall) and the games wing
			for X = AlleyLayout.X0, AlleyLayout.HALL_X1, 1 do
				for D = AlleyLayout.FRONT_D, AlleyLayout.REAR_WALL_D, 1 do
					under(X, D)
				end
			end
			for X = AlleyLayout.HALL_X1, AlleyLayout.X1, 1 do
				for D = AlleyLayout.GAME_ROOM_D0, AlleyLayout.GAME_ROOM_D1, 1 do
					under(X, D)
				end
			end
			-- the boot terrain's voxels can stand up to a stud above the computed height: outside the cut the
			-- floor clears it by more than that
			t.truthy(place.floorY > worst + 1.0, `floor {place.floorY} vs ground {worst} outside the cut`)
			t.truthy(worstCut > place.floorY - 1.0, `the cut is where the ground is high ({worstCut})`)
			local zone = AlleyLayout.zone("rear_alley")
			local alleyWorst = -math.huge
			for X = zone.x0, zone.x1, 1 do
				for D = zone.d0, zone.d1, 1 do
					local x, _, z = AlleyLayout.toWorld(place, X, 0, D)
					alleyWorst = math.max(alleyWorst, Height.at(x, z))
				end
			end
			t.truthy(
				place.floorY + AlleyLayout.ALLEY_Y > alleyWorst,
				`alley {place.floorY + AlleyLayout.ALLEY_Y} vs {alleyWorst}`
			)
		end
	)

	t.test("the plan: rooms inside the walls, none overlapping, every opening on a wall its two rooms share", function()
		local L = AlleyLayout
		local ids: { [string]: boolean } = {}
		for _, z in L.ZONES do
			t.falsy(ids[z.id], `two zones called {z.id}`)
			ids[z.id] = true
			t.truthy(z.x1 > z.x0 and z.d1 > z.d0, z.id)
			if not z.outside then
				local inHall = z.x0 >= L.X0 and z.x1 <= L.HALL_X1 and z.d0 >= L.FRONT_D and z.d1 <= L.REAR_WALL_D
				local inWing = z.x0 >= L.HALL_X1 and z.x1 <= L.X1 and z.d0 >= L.GAME_ROOM_D0 and z.d1 <= L.GAME_ROOM_D1
				t.truthy(inHall or inWing, `{z.id} is inside the walls`)
			end
		end
		for i, a in L.ZONES do
			for j = i + 1, #L.ZONES do
				local b = L.ZONES[j]
				local overlap = math.min(a.x1, b.x1) - math.max(a.x0, b.x0) > 0.01
					and math.min(a.d1, b.d1) - math.max(a.d0, b.d0) > 0.01
				t.falsy(overlap, `{a.id} overlaps {b.id}`)
			end
		end
		-- the rooms the owner asked for, by name, with room in them
		for _, want in
			{ { "ball_shop", 20, 15 }, { "gift_shop", 20, 15 }, { "shoe_rental", 14, 15 }, { "snack_bar", 24, 15 } }
		do
			local z = L.zone(want[1])
			t.truthy(z.x1 - z.x0 >= want[2] and z.d1 - z.d0 >= want[3], `{z.id} is {z.x1 - z.x0} x {z.d1 - z.d0}`)
		end
		-- the games room is at least twice the six-lane house's 30 x 78
		local g = L.zone("games_room")
		t.truthy((g.x1 - g.x0) * (g.d1 - g.d0) >= 2 * 30 * 78 * 0.98, `games room {g.x1 - g.x0} x {g.d1 - g.d0}`)
		-- openings: each joins two zones across one wall line and is wide enough for a person
		local slack = L.WALL_T + L.PARTITION_T + 0.01
		local seen: { [string]: boolean } = {}
		for _, o in L.OPENINGS do
			t.falsy(seen[o.id], `two openings called {o.id}`)
			seen[o.id] = true
			t.truthy(o.b - o.a >= 3.39, `{o.id} is {o.b - o.a} wide`)
			t.truthy(o.head >= 7 and o.head <= L.CEILING_Y, `{o.id} head {o.head}`)
			t.eq(#o.between, 2)
			local sides = 0
			for _, id in o.between do
				local z = L.zone(id)
				local lo, hi, a0, a1
				if o.axis == "x" then
					lo, hi, a0, a1 = z.d0, z.d1, z.x0, z.x1
				else
					lo, hi, a0, a1 = z.x0, z.x1, z.d0, z.d1
				end
				t.truthy(o.a >= a0 - 0.01 and o.b <= a1 + 0.01, `{o.id} lies within {id} along the wall`)
				local touches = math.abs(lo - o.at) <= slack or math.abs(hi - o.at) <= slack
				t.truthy(touches, `{id} has an edge on {o.id}'s wall line`)
				sides += if (lo + hi) / 2 < o.at then -1 else 1
			end
			t.eq(sides, 0, `{o.id}'s two rooms are on opposite sides of its wall`)
		end
		-- the main doors are on the Alley Walk's line (data/expansion.json xpath_alley_walk, x 1322)
		local ent = L.opening("entrance")
		local ex = AlleyLayout.toWorld(place, (ent.a + ent.b) / 2, 0, ent.at)
		t.near(ex, 1322, 1e-6)
	end)

	t.test("the games room: every table has its own clear floor, off the walls and the doorways", function()
		local L = AlleyLayout
		local g = L.zone("games_room")
		local list = L.standing()
		local want = { "pool_1", "pool_2", "bumper_pool", "pinball", "darts", "fortune", "air_hockey" }
		for _, id in want do
			local found = false
			for _, s in list do
				found = found or s.id == id
			end
			t.truthy(found, `standing room for {id}`)
		end
		for i, a in list do
			t.truthy(
				a.x0 >= g.x0 - 0.01 and a.x1 <= g.x1 + 0.01 and a.d0 >= g.d0 - 0.01 and a.d1 <= g.d1 + 0.01,
				`{a.id} inside the room`
			)
			for j = i + 1, #list do
				local b = list[j]
				local overlap = math.min(a.x1, b.x1) - math.max(a.x0, b.x0) > 0.01
					and math.min(a.d1, b.d1) - math.max(a.d0, b.d0) > 0.01
				t.falsy(overlap, `{a.id} overlaps {b.id}`)
			end
			-- four studs of floor inside each opening of the partition stay free
			for _, o in L.OPENINGS do
				if o.axis == "d" and o.at == L.GAME_ROOM_X0 then
					local blocksDoor = a.x0 < g.x0 + 4 and math.min(a.d1, o.b) - math.max(a.d0, o.a) > 0.01
					t.falsy(blocksDoor, `{a.id} stands in {o.id}`)
				end
			end
		end
		-- the air hockey table: a constant its game reads (x, d: the middle of the bed; yaw: its long axis from +X)
		local ah = L.AIR_HOCKEY
		t.truthy(type(ah.x) == "number" and type(ah.d) == "number" and type(ah.yaw) == "number")
		t.near(L.AIR_HOCKEY_SIZE.across, 6.2, 1e-9)
		t.near(L.AIR_HOCKEY_SIZE.along, 11.5, 1e-9)
		-- the dartboard is beside the pool tables (on their wall, within a table's length of the nearer one) and
		-- the fortune teller has a corner
		local b = L.board()
		local nearest = math.huge
		for _, p in L.POOL_TABLES do
			nearest = math.min(nearest, math.abs(p.d - b.d))
			t.truthy(L.X1 - p.x < 20, "the pool tables are on the dartboard's side of the room")
		end
		t.truthy(nearest < 26, `dartboard {nearest} from the nearer pool table`)
		t.truthy(
			L.X1 - L.FORTUNE.x < 5 and L.GAME_ROOM_D1 - L.FORTUNE.d < 5,
			"the fortune teller is in the back corner"
		)
		-- the pinball machines back onto the front wall
		t.near(L.PINBALL_D - L.GAME_ROOM_D0, 3.4, 1e-9)
		t.eq(#L.PINBALLS, 3)
	end)

	t.test(
		"staff: every post is on a floor, in its room and off the games' floor; every route walks on floors",
		function()
			local L = AlleyLayout
			local posts = table.clone(L.POSTS)
			for lane = 1, L.LANES do
				table.insert(posts, L.machinePost(lane))
				table.insert(posts, L.approachPost(lane))
			end
			local seen: { [string]: boolean } = {}
			for _, p in posts do
				t.falsy(seen[p.id], `two posts called {p.id}`)
				seen[p.id] = true
				local z = L.zone(p.zone)
				t.truthy(p.x > z.x0 and p.x < z.x1 and p.d > z.d0 and p.d < z.d1, `{p.id} is in {p.zone}`)
				local y = L.floorAt(p.x, p.d)
				t.truthy(y ~= nil, `{p.id} is on a floor`)
				if y and p.id ~= "stoop" then
					t.near(y, z.y or 0, 1e-6, `{p.id} stands at its room's floor height`)
				end
				for _, s in L.standing() do
					t.falsy(p.x > s.x0 and p.x < s.x1 and p.d > s.d0 and p.d < s.d1, `{p.id} stands in {s.id}'s floor`)
				end
			end
			-- a post for each thing the owner asked for
			for _, id in { "shoe_desk", "ball_counter", "gift_counter", "snack_till", "greeter", "bench", "cans" } do
				t.truthy(L.post(id) ~= nil)
			end
			local legs = 0
			for id in L.ROUTES do
				local r = L.route(id)
				t.truthy(#r >= 2, id)
				for i, p in r do
					t.truthy(L.floorAt(p[1], p[2]) ~= nil, `route {id} point {i} is on a floor`)
					t.near(p[3], L.floorAt(p[1], p[2]) :: number, 1e-9)
					legs += if i > 1 then 1 else 0
				end
			end
			t.truthy(legs >= 40, `{legs} legs of walking route`)
			-- floors: the hall at 0, the rear alley below it, the stoop steps and the entrance ramp between
			t.eq(L.floorAt(0, -30), 0)
			t.eq(L.floorAt(120, 0), 0)
			t.eq(L.floorAt(0, 95), L.ALLEY_Y)
			t.eq(L.floorAt(-22.5, 83), 0)
			local mid =
				L.floorAt(-22.5, L.REAR_WALL_D + L.WALL_T + L.STOOP.depth + L.STOOP.steps * L.STOOP.tread / 2) :: number
			t.truthy(mid < 0 and mid > L.ALLEY_Y)
			local ramp = L.floorAt(22, L.RAMP.d0 + 0.01) :: number
			t.near(ramp, L.RAMP.y0, 0.01)
			t.eq(L.floorAt(-200, 0), nil)
		end
	)

	t.test("the backstage: anchor at the lane tails, scale from the pitch, its ground kept free in the data", function()
		local L = AlleyLayout
		local bs = L.BACKSTAGE
		t.eq(bs.anchorName, "ServiceFrontCenter")
		t.near(bs.scale, 6.2 / 5.714286, 1e-9)
		t.near(bs.scale, 1.085, 1e-4)
		t.eq(bs.bays, 18)
		t.eq(bs.returns, 9)
		-- the anchor: on the floor, at the middle of the eighteen lanes, on the customers' side of the pins
		t.near(bs.anchor.x, (L.laneX(1) + L.laneX(18)) / 2, 1e-9)
		t.eq(bs.anchor.y, 0)
		t.truthy(bs.anchor.d > 40 and bs.anchor.d < L.HEAD_D, "the lane tails end before the head pin")
		-- eighteen authored bays at the authored pitch, scaled, land on our eighteen lanes
		for lane = 1, L.LANES do
			local authored = (lane - 9.5) * bs.authoredPitch
			t.near(bs.anchor.x + authored * bs.scale, L.laneX(lane), 1e-6)
		end
		-- about 205 x 136 studs at our scale, the lofts higher than the hall's ceiling
		t.near(bs.size.x, 205.4, 0.1)
		t.near(bs.size.d, 135.6, 0.1)
		t.truthy(bs.loftY > L.CEILING_Y)
		local rs = bs.reserve
		t.truthy(rs.x1 - rs.x0 >= bs.size.x and rs.d1 - rs.d0 >= bs.size.d - 1e-9)
		t.truthy(rs.x0 <= bs.anchor.x - bs.size.x / 2 + 1e-9, "room for the outline centred on the anchor")
		t.truthy(rs.x1 >= L.LANE_BLOCK_X0 + bs.size.x - 6.01, "room for the outline flush with lane 1")
		t.eq(rs.d0, bs.anchor.d)
		-- data/attractions.json keeps that ground free (the expansion compiler reads it from there)
		local kept = alley.reserve
		t.truthy(kept ~= nil, "the reserve is in the data")
		t.near(kept.x0, rs.x0, 0.01)
		t.near(kept.x1, rs.x1, 0.01)
		t.near(kept.d0, rs.d0, 0.01)
		t.near(kept.d1, rs.d1, 0.01)
		-- the interim back module: everything behind the pinsetters, inside the footprint
		t.eq(bs.interimFrom, L.MACHINE_D1)
		local it, fp = bs.interim, alley.footprint
		t.eq(it.d0, bs.interimFrom)
		t.truthy(it.x0 >= fp.x0 and it.x1 <= fp.x1 and it.d1 <= fp.d1)
	end)

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

	t.test("routes: nine vents and nine tunnels, in the ducts under each pair, ending on the rack", function()
		t.eq(#mod.routes, 2 * AlleyLayout.PAIRS)
		local reg = data:routes()
		for p = 1, AlleyLayout.PAIRS do
			local vent = reg:get(9000 + 2 * p - 1)
			local tunnel = reg:get(9000 + 2 * p)
			t.truthy(vent and tunnel, `pair {p} routes in the registry`)
			if not vent or not tunnel then
				continue
			end
			-- the server finds a pair's tunnel by the record's own field (Server/Attractions/AttractionService)
			t.eq(alley.routes[2 * p - 1].pair, p)
			t.eq(alley.routes[2 * p].pair, p)
			t.eq(alley.routes[2 * p].id, 9000 + 2 * p)
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
					t.truthy(
						Y >= AlleyLayout.DUCT_FLOOR - 0.05 and Y < AlleyLayout.PIT_DUCT_CEIL - 1.0,
						`under the floor at D {D}: Y {Y}`
					)
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

	t.test(
		"a squirrel runs it: alley -> vent -> under the lane -> out on the rack; Space leaps at the bowler",
		function()
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
			-- (the middle pair of the six-lane house, and the far pair of the eighteen)
			for _, p in { 2, 9 } do
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
				t.truthy(
					D < AlleyLayout.HOOD_D1 and math.abs(X - px) < 0.5 and Y > 1,
					`out on the rack ({X}, {Y}, {D})`
				)
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
			end
		end
	)
end
