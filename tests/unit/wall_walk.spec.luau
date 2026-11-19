--!strict
-- Nobody walks through a wall: the cases (the no-wall-walk review of feat/no-wall-walk merged onto the duel; each case
-- names what went wrong and holds it fixed; tests/unit/town_walls.spec walks the whole town on the bake).
--   back       the duel's "back away" walks only along a clear line (World/WalkWay.clear): straight away, aslant or
--              sideways; with none the person holds their ground (it walked 4 studs straight away every think, into
--              the house behind a person on the sidewalk)
--   approach   the duel's "close in" goes by the town's way (Brains/Common.toward): round a garden wall or a fence
--              the person can see the rodent over, never over it
--   chase      an officer chasing a rodent on the far bank of the river crosses by the bridge (World/WalkWay's bridge:
--              a building with a door at each end, a FootPath link between them; the AI's ground is the deck), with
--              at most one way search a second however often the chase re-orders (the way's end follows the rodent
--              while the line to it is clear)
--   nowhere    a spot in an area no way reaches (FootPath's connected areas, labelled at build): every search returns
--              at once, and the failed search's wait holds while the spot moves about near where it was
--   duel cost  two officers re-ordered ten times a second (Combat/CombatService's duel orders) round a house: at most
--              one search a second each; the worst search's time is printed
--   margin     from a spot just inside a house's wall, no straight line through the house is clear
--   rounds     every staff round misses every baked wall (a guard)
--   audit      the long audit's two runs that crossed a wall on the merged tree (the clock tower's plinth, the quay's
--              embankment wall: both WalkWay boxes now)
--   far        a body left on the east bank, or out past the old path-finder's bounds, walks back within two minutes
--              with a player watching it (the bridge, the town AI's bounds, partial ways for a long walk)
--   stuck      a body nobody sees that has no way at all (the top of the Lookout) is put back on its own ground
--   standoff   an ambulance turning with a lorry close behind it drives on (AICarMotor.routeGap: a vehicle behind
--              the centre is never in front)
--   fencetop   a rodent on a fence rail is seen by the duel (sight is the buildings, not the fences a walker cannot
--              pass)
--   alleyfront WalkWay.clear never calls clear a line into the bowling alley's baked front (an end inside a
--              building with ways' box, outside its ways, is in a wall)
--   repeatable the audit's run gives the same report twice (WallAudit.run's think budget is fixed: BUDGET_MS)
--   covered    every baked wall a walker's waist meets lies inside a WalkWay box (WallAudit.uncovered: no luck needed)
--   props      the poles and tree trunks standing on a lane are stepped round (Brains/Pedestrian's lane dodges)
-- Bakes first: lune run tools/bake/main.luau, attractions.luau and the expansion bakes (as tools/ci.sh).
local Data = require("@shared/Data")
local WalkWay = require("@shared/World/WalkWay")
local Colliders = require("@shared/World/Colliders")
local Height = require("@shared/World/Height")
local TownAI = require("@server/AI/TownAI")
local WallAudit = require("@tests/lib/WallAudit")
local TrafficService = require("@server/Traffic/TrafficService")
local BiteRig = require("@tests/lib/BiteRig")
local LaneMath = require("@shared/Traffic/LaneMath")

local DT = 1 / 30

return function(t)
	local data = Data.default()
	local town: WallAudit.Town? = nil
	local function baked(): WallAudit.Town
		if town == nil then
			town = WallAudit.load()
		end
		return town :: WallAudit.Town
	end

	-- a townsperson brain to drive by hand, and its lanes
	local function person(world: any): (any, any)
		for _, a in world.actors do
			local b = world.brains[a.id] :: any
			if a.post == "townsperson" and b and b.kind == "Pedestrian" then
				return a, b
			end
		end
		error("no townsperson")
	end

	-- step the town with `a` near a player (its brain thinks at the near rate), `each` before every frame; returns the
	-- walls of the baked town the body walked through and whether it entered a solid lot box
	local function walk(world: any, a: any, secs: number, each: (now: number) -> ()): ({ string }, boolean)
		TownAI.setFocus(world, function()
			return { { x = a.x, z = a.z } }
		end)
		local tw = baked()
		local crossed, entered = {}, false
		for _ = 1, math.floor(secs / DT) do
			each(world.now)
			local ax, ay, az = a.x, a.y - a.hip, a.z
			TownAI.stepFrame(world, DT)
			local part = WallAudit.crossing(tw, ax, ay, az, a.x, a.y - a.hip, a.z)
			if part and #crossed < 3 then
				table.insert(crossed, string.format("(%.1f, %.1f) -> (%.1f, %.1f) %s", ax, az, a.x, a.z, part.path))
			end
			entered = entered or WalkWay.solidAt(world.way, a.x, a.z) ~= nil
		end
		return crossed, entered
	end

	-- sidewalk lane pieces that run along a solid lot's face, 1.5 to 10 studs out, with the street beyond
	local function lanesAlongHouses(
		world: any,
		lanes: { any }
	): { { box: any, x: number, z: number, rx: number, rz: number } }
		local out = {}
		for _, lane in lanes do
			local ax = lane.axis == "x"
			local minX, maxX = if ax then lane.min else lane.fixed - 12, if ax then lane.max else lane.fixed + 12
			local minZ, maxZ = if ax then lane.fixed - 12 else lane.min, if ax then lane.fixed + 12 else lane.max
			for _, b in Colliders.query(world.way.colliders, minX, minZ, maxX, maxZ) do
				-- (across the lane: the box's centre and half depth that way; along it: its centre)
				local across, half, along =
					if ax then b.cz else b.cx, if ax then b.hd else b.hw, if ax then b.cx else b.cz
				local gap = math.abs(lane.fixed - across) - half
				if
					gap > 1.5
					and gap < 10
					and (if ax then b.hw else b.hd) > 4
					and along > lane.min + 3
					and along < lane.max - 3
					and WalkWay.solidAt(world.way, b.cx, b.cz) ~= nil
					and b.eave - b.y0 > 6
				then
					local side = if lane.fixed > across then 1 else -1
					local x, z = if ax then along else lane.fixed, if ax then lane.fixed else along
					table.insert(out, {
						box = b,
						x = x,
						z = z,
						rx = if ax then x else x + side * 6,
						rz = if ax then z + side * 6 else z,
					})
				end
			end
		end
		return out
	end

	t.test("back: a person backing away from the rodent in the street never walks into the house behind", function()
		local world = TownAI.build({ data = data, seed = 1, squirrels = 0, deer = 0, fox = 0 })
		local a, brain = person(world)
		local spots = lanesAlongHouses(world, brain.params.lanes)
		t.truthy(#spots >= 3, `{#spots} sidewalk pieces along a house front`)
		local bad, tried = {}, 0
		for i = 1, math.min(#spots, 6) do
			local s = spots[math.floor((i - 1) * #spots / 6) + 1]
			-- on the lane before the house's middle; the rodent 6 studs out in the street
			TownAI.suspend(world, a.id)
			TownAI.resume(world, a.id, s.x, Height.at(s.x, s.z) + a.hip, s.z)
			local rx, rz = s.rx, s.rz
			tried += 1
			-- (Combat/CombatService renews the order every tick it holds: ORDER_SECS 0.6, ten times a second)
			local crossed, entered = walk(world, a, 3, function(now: number)
				brain:onEvent({ type = "duel", mode = "back", x = rx, z = rz, speed = 4, untilTime = now + 0.6 })
			end)
			if #crossed > 0 or entered then
				table.insert(
					bad,
					string.format(
						"%s at (%.0f, %.0f): %s%s",
						s.box.id,
						s.x,
						s.z,
						if entered then "inside the lot's box; " else "",
						table.concat(crossed, "; ")
					)
				)
			end
		end
		t.eq(#bad, 0, `{#bad} of {tried} backed into the house:\n{table.concat(bad, "\n")}`)
	end)

	t.test("approach: a person closing on the rodent over a low garden wall or fence goes round it", function()
		local world = TownAI.build({ data = data, seed = 1, squirrels = 0, deer = 0, fox = 0 })
		local a, brain = person(world)
		local way = world.way
		-- fence pieces (WalkWay.addFences) a walker cannot pass that do not block the duel's sight line (Colliders
		-- .blocked at the person's feet + 3: CombatService's inSight)
		local found = {}
		for _, b in way.colliders.boxes do
			if string.sub(b.id, 1, 6) == "fence_" and b.eave - b.y0 >= WalkWay.LOW and b.eave < b.y0 + 3 then
				local long = if b.hw > b.hd then "x" else "z"
				local nx, nz = if long == "x" then 0 else 1, if long == "x" then 1 else 0
				local ax, az = b.cx - nx * 5, b.cz - nz * 5
				local rx, rz = b.cx + nx * 5, b.cz + nz * 5
				if
					WalkWay.solidAt(way, ax, az) == nil
					and WalkWay.roomAt(way, ax, az) == nil
					and not Colliders.blocked(way.colliders, ax, az, rx, rz, 1, Height.at(ax, az) + 3)
					and not WalkWay.clear(way, ax, az, rx, rz)
				then
					table.insert(found, { ax, az, rx, rz, b.id })
				end
			end
		end
		print(`      {#found} fence pieces seen over but not walked through`)
		t.truthy(#found > 0, "a low fence the duel sees the rodent over")
		local bad = {}
		for i = 1, math.min(#found, 6) do
			local f = found[math.floor((i - 1) * #found / 6) + 1]
			TownAI.suspend(world, a.id)
			TownAI.resume(world, a.id, f[1], Height.at(f[1], f[2]) + a.hip, f[2])
			local crossed = walk(world, a, 3, function(now: number)
				brain:onEvent({ type = "duel", mode = "approach", x = f[3], z = f[4], speed = 5, untilTime = now + 0.6 })
			end)
			if #crossed > 0 then
				table.insert(bad, `{f[5]}: {table.concat(crossed, "; ")}`)
			end
		end
		t.eq(#bad, 0, table.concat(bad, "\n"))
	end)

	-- the town's way searches the brains make (ctx.way), counted and timed
	local function countWays(world: any): { calls: number, none: number, ms: number, worst: number }
		local ctx = world.ctx :: any
		local inner = ctx.way
		local c = { calls = 0, none = 0, ms = 0, worst = 0 }
		ctx.way = function(x0: number, z0: number, x1: number, z1: number): any
			local t0 = os.clock()
			local out, partial = inner(x0, z0, x1, z1)
			local d = (os.clock() - t0) * 1000
			c.calls += 1
			c.none += if out == nil then 1 else 0
			c.ms += d
			c.worst = math.max(c.worst, d)
			return out, partial
		end
		return c
	end

	local function officer(world: any): (any, any)
		for _, a in world.actors do
			local b = world.brains[a.id] :: any
			if b and b.kind == "Officer" then
				return a, b
			end
		end
		error("no officer")
	end

	-- open ground along z from x0 toward x1 (2 studs at a time)
	local function open(world: any, x0: number, x1: number, z: number): number
		for x = x0, x1, if x1 > x0 then 2 else -2 do
			if
				WalkWay.solidAt(world.way, x, z) == nil
				and WalkWay.roomAt(world.way, x, z) == nil
				and WalkWay.clear(world.way, x, z, x + 0.5, z)
			then
				return x
			end
		end
		error("no open ground")
	end

	t.test(
		"chase: an officer chasing a rodent on the far bank crosses by the bridge, one search a second at most",
		function()
			local world = TownAI.build({ data = data, seed = 1, squirrels = 0, deer = 0, fox = 0 })
			local c = countWays(world)
			local cop, brain = officer(world)
			-- the officer on the west bank, the rodent running about on the east bank
			local wz, ez = 150, 150
			local wx, ex = open(world, 1960, 1700, wz), open(world, 2290, 2600, ez)
			t.truthy(WalkWay.find(world.way, wx, wz, ex, ez) ~= nil, "a way over the river, by the bridge")
			TownAI.suspend(world, cop.id)
			TownAI.resume(world, cop.id, wx, Height.at(wx, wz) + cop.hip, wz)
			local nextAt = 0
			local crossedAt: number? = nil
			local walls = walk(world, cop, 90, function(now: number)
				-- CombatService.stepChases: every CHASE_EVERY (0.5 s), where the rodent is now (it runs 8 studs a second)
				if now >= nextAt then
					nextAt = now + 0.5
					brain:onEvent({ type = "respond", x = ex + 8 * now % 40, z = ez, untilTime = now + 1 })
				end
				if crossedAt == nil and cop.x > WalkWay.BRIDGE.x1 then
					crossedAt = now
				end
			end)
			print(
				string.format(
					"      90 s: over the bridge at %s s; %d way searches (%d found none), %.0f ms in all, worst %.2f ms",
					if crossedAt then string.format("%.0f", crossedAt) else "never",
					c.calls,
					c.none,
					c.ms,
					c.worst
				)
			)
			t.truthy(crossedAt ~= nil, `the officer crossed the river (at ({cop.x}, {cop.z}))`)
			t.eq(#walls, 0, table.concat(walls, "\n"))
			t.truthy(c.calls <= 90, `{c.calls} searches in 90 s`)
		end
	)

	-- the town's open ground is one area but for a few closed in (walled all round): the middle of the biggest such
	local function closedIn(world: any): (number, number, number)
		local foot = world.way.foot
		local sizes, cellOf = {}, {}
		local main, mainN = nil, 0
		for iz, row in foot.rows :: any do
			for i, a in row.area do
				local n = row.ends[i] - row.starts[i] + 1
				sizes[a] = (sizes[a] or 0) + n
				cellOf[a] = cellOf[a] or { (row.starts[i] + row.ends[i]) // 2, iz }
				if sizes[a] > mainN then
					main, mainN = a, sizes[a]
				end
			end
		end
		local spot, best = nil, 0
		for a, n in sizes do
			if a ~= main and n > best then
				spot, best = cellOf[a], n
			end
		end
		assert(spot, "an area closed in")
		return spot[1] * foot.cell, spot[2] * foot.cell, best
	end

	t.test("nowhere: a spot no way reaches costs a quick search per wait, however it moves near there", function()
		local world = TownAI.build({ data = data, seed = 1, squirrels = 0, deer = 0, fox = 0 })
		local c = countWays(world)
		local cop, brain = officer(world)
		local foot = world.way.foot
		local sx, sz, best = closedIn(world)
		print(string.format("      an area of %d cells closed in at (%.0f, %.0f)", best, sx, sz))
		t.eq((WalkWay.find(world.way, cop.x, cop.z, sx, sz)), nil, "no way in")
		local nextAt = 0
		walk(world, cop, 30, function(now: number)
			-- (a chase's orders, ten a second, the spot wandering a few studs)
			if now >= nextAt then
				nextAt = now + 0.1
				brain:onEvent({ type = "respond", x = sx + 3 * math.sin(now), z = sz, untilTime = now + 1 })
			end
		end)
		print(string.format("      30 s: %d way searches, %d found none, worst %.3f ms", c.calls, c.none, c.worst))
		-- (a failed search waits 4 s, doubling: 4 in 30 s; each returns at once, without opening a cell)
		t.truthy(c.calls <= 5, `{c.calls} searches in 30 s`)
		t.truthy(foot.early >= c.calls, `{foot.early} searches returned at once`)
	end)

	t.test(
		"duel cost: two officers re-ordered ten times a second round a house search once a second at most",
		function()
			local world = TownAI.build({ data = data, seed = 1, squirrels = 0, deer = 0, fox = 0 })
			local c = countWays(world)
			local lot = data:lot("outer_home_07")
			local b = nil
			for _, box in world.way.colliders.boxes do
				if box.id == lot.id then
					b = box
				end
			end
			assert(b, "the house's box")
			-- the officers on the house's south side, the rodent running round its north side out of their line
			local cops = {}
			for _, a in world.actors do
				local brain = world.brains[a.id] :: any
				if brain and brain.kind == "Officer" and #cops < 2 then
					local x = b.cx + (#cops - 0.5) * 6
					local z = b.cz - b.hd - 6
					TownAI.suspend(world, a.id)
					TownAI.resume(world, a.id, x, Height.at(x, z) + a.hip, z)
					table.insert(cops, { a = a, brain = brain })
				end
			end
			local r = math.max(b.hw, b.hd) + 8
			local nextAt = 0
			local walls = walk(world, cops[1].a, 30, function(now: number)
				if now >= nextAt then
					nextAt = now + 0.1 -- (CombatService's order(): an officer in a duel, every tick it holds)
					local ang = math.pi * 0.25 + 0.5 * math.sin(now * 0.4) * math.pi * 0.5
					local x, z = b.cx + math.cos(ang) * r, b.cz + math.sin(ang) * r
					for _, o in cops do
						o.brain:onEvent({ type = "respond", x = x, z = z, untilTime = now + 0.6 })
					end
				end
			end)
			print(
				string.format(
					"      30 s, 2 officers: %d way searches (%.1f a second), %d found none, %.1f ms in all, worst %.2f ms",
					c.calls,
					c.calls / 30,
					c.none,
					c.ms,
					c.worst
				)
			)
			t.truthy(c.calls <= 62, `{c.calls} searches in 30 s by 2 officers`)
			t.eq(#walls, 0, table.concat(walls, "\n"))
		end
	)

	t.test("margin: no straight line from just inside a house's wall through the house is clear", function()
		local way = WalkWay.new({ data = data })
		local lot = data:lot("outer_home_07")
		local b = nil
		for _, box in way.colliders.boxes do
			if box.id == lot.id then
				b = box
			end
		end
		assert(b, "the lot's box")
		-- 0.1 studs inside its south wall, to a spot 5 studs beyond its north wall
		local x0, z0 = b.cx, b.cz - b.hd + 0.1
		local x1, z1 = b.cx, b.cz + b.hd + 5
		t.eq(WalkWay.solidAt(way, x0, z0), nil, "(not solid: within MARGIN of the wall)")
		t.falsy(WalkWay.clear(way, x0, z0, x1, z1), "the line through the whole house")
		-- and a body let go there is not left there
		local px, pz = WalkWay.putBack(way, x0, z0)
		t.falsy(px == x0 and pz == z0 and WalkWay.clear(way, px, pz, x1, z1), "put back where that line is clear")
	end)

	t.test("rounds: every staff round (the shop workers' new pavement rounds too) misses every baked wall", function()
		local world = TownAI.build({ data = data, seed = 1, squirrels = 0, deer = 0, fox = 0 })
		local tw = baked()
		local bad, rounds = {}, 0
		for _, a in world.actors do
			local b = world.brains[a.id] :: any
			if b and b.kind == "Staff" and b.points and #b.points >= 2 then
				rounds += 1
				local pts = b.points
				for i = 1, #pts do
					local p, q = pts[i], pts[i % #pts + 1]
					local len = math.sqrt((q[1] - p[1]) ^ 2 + (q[2] - p[2]) ^ 2)
					local n = math.max(1, math.ceil(len / 2))
					for k = 0, n - 1 do
						local ax, az = p[1] + (q[1] - p[1]) * k / n, p[2] + (q[2] - p[2]) * k / n
						local bx, bz = p[1] + (q[1] - p[1]) * (k + 1) / n, p[2] + (q[2] - p[2]) * (k + 1) / n
						local fa, fb = world.ctx.groundAt(ax, az), world.ctx.groundAt(bx, bz)
						local part = WallAudit.crossing(tw, ax, fa, az, bx, fb, bz)
						local inside = WallAudit.inside(tw, ax, fa, az)
						if (part or inside) and #bad < 12 then
							table.insert(
								bad,
								string.format(
									"#%d %s leg %d (%.1f, %.1f): %s",
									a.id,
									a.post,
									i,
									ax,
									az,
									(part or inside :: any).path
								)
							)
							break
						end
					end
				end
			end
		end
		t.truthy(rounds > 20, `{rounds} rounds`)
		t.eq(#bad, 0, table.concat(bad, "\n"))
	end)

	t.test(
		"audit: the long audit's runs that crossed a wall on the merged tree (tools/sim/wall_audit --seeds 1,2)",
		function()
			local tw = baked()
			-- seed 1 far: a shop worker's round in front of a quay shop through the clock tower's plinth (t 428)
			local r1 = WallAudit.run(tw, data, { seed = 1, minutes = 7.3, near = false })
			-- seed 2 near: a rejoin along the river's south edge through the quay wall (t 838)
			local r2 = WallAudit.run(tw, data, { seed = 2, minutes = 14.1, near = true })
			t.eq(r1.crossings + r2.crossings, 0, `{WallAudit.format(r1)}\n{WallAudit.format(r2)}`)
		end
	)

	t.test(
		"far: a body left on the east bank or out past the path-finder's bounds walks back within two minutes",
		function()
			local world = TownAI.build({ data = data, seed = 1, squirrels = 0, deer = 0, fox = 0 })
			local a, brain = person(world)
			local stuck = {}
			-- (the east bank by the quay and the galleria: the way round the river is 1,500 to 3,300 studs, past the
			-- brains' search budget TownAI.WAY_NODES; out in the countryside past Height.worldClamp the path-finder has no
			-- cells at all)
			for _, s in { { 2575, -7 }, { 2494, -67 }, { 4016, -1804 }, { 451, -2747 } } do
				TownAI.suspend(world, a.id)
				TownAI.resume(world, a.id, s[1], Height.at(s[1], s[2]) + a.hip, s[2])
				local moved = 0
				local px, pz = a.x, a.z
				walk(world, a, 120, function()
					moved += math.sqrt((a.x - px) ^ 2 + (a.z - pz) ^ 2)
					px, pz = a.x, a.z
				end)
				if moved < 20 then
					table.insert(
						stuck,
						string.format("(%d, %d): walked %.1f studs in 120 s (%s)", s[1], s[2], moved, brain.state)
					)
				end
			end
			t.eq(#stuck, 0, table.concat(stuck, "\n"))
		end
	)

	t.test("standoff: an ambulance turning with a lorry close behind it drives on", function()
		local traffic =
			TrafficService.new({ lanes = data:lanes(), roads = data:roads(), heightAt = Height.at, seed = 7 })
		-- the route at be30746 (from the bay: the hospital road, the trunk west, down x -445 and east along z 5), and
		-- the moment it stood: 1176.59 studs along it, turning left at (-445, 5); the dump truck 9 studs behind it
		local amb = traffic:dispatchResponder(
			{ 212.979, 0 },
			{ hold = true, route = { { -890, 707.5 }, { -450, 707.5 }, { -450, 0 }, { 212.979, 0 } } }
		)
		assert(amb, "a responder")
		-- (its trip at be30746 turned at x -440 and stood at (-437.7, 9.5) with the truck in the lane beside the
		-- corner; here the corner is at x -450 so that the ambulance stands where it stood)
		-- (as it stood at be30746: heading 2.258 rad, half way round the corner)
		local bestS, bestD = 0, math.huge
		for k = 0, 600 do
			local q = LaneMath.pointAt(amb.route, 1150 + k * 0.1, 1)
			local d = math.abs(q.yaw - 2.2583) + (if q.z < 30 then 0 else 100)
			if d < bestD then
				bestS, bestD = 1150 + k * 0.1, d
			end
		end
		amb.s, amb.speed, amb.dir = bestS, 0, 1
		local truck = nil
		for _, v in traffic.vehicles do
			if v.kind == "dump_truck" then
				truck = v
			end
		end
		assert(truck, "the dump truck")
		truck.lane = traffic.lanes["res_west_ns_x-180_northbound~back"]
		assert(truck.lane, "its lane")
		truck.s, truck.dir, truck.speed, truck.visible = 606.2715, -1, 0, true
		traffic:step(1 / 30, { people = {} })
		print(
			string.format("      ambulance at (%.1f, %.1f), the truck at (%.1f, %.1f)", amb.x, amb.z, truck.x, truck.z)
		)
		local s0 = amb.s
		-- (TrafficService.step takes at most 0.25 s a call: ten seconds is 300 ticks)
		for _ = 1, 300 do
			traffic:step(1 / 30, { people = {} })
		end
		t.truthy(amb.s > s0 + 20, `the ambulance drove {amb.s - s0} studs in 10 s (the truck {truck.speed} st/s)`)
	end)

	t.test("fencetop: a rodent on a fence rail 4 studs from a tough person is seen by the duel", function()
		local rig = BiteRig.new({
			seed = 2,
			duelRand = function(): number
				return 0
			end,
		})
		rig.step(5)
		rig.holdRodent()
		local tough = nil
		for _, a in rig.world.actors do
			if a.post == "townsperson" and rig.combat:temperOf(a.id) == "tough" then
				tough = a
				break
			end
		end
		assert(tough, "a tough townsperson")
		-- fence_11's piece by (-207.5, -101.5): a rail 5.25 studs up, running along z
		local fx, fz, top = -207.5, -101.483, 5.25
		local px, pz = fx + 4, fz
		rig.put(tough.id, px, pz, math.atan2(fx - px, 0))
		rig.hold(tough.id)
		rig.let(tough.id)
		rig.put(rig.rodent, fx, fz)
		local rod = rig.world.actorsById[rig.rodent]
		rod.y = top + rod.hip
		rig.step(1)
		local g = rig.combat.guards[tough.id]
		t.truthy(g ~= nil, "the tough person squares up to the rodent on the rail")
	end)

	t.test("alleyfront: WalkWay.clear never calls clear a line into the bowling alley's baked front", function()
		local tw = baked()
		local way = WalkWay.new({ data = data })
		local bad = {}
		-- the crew member's run at t 249 (seed 1, near) and its walk back, and the same line moved along the front
		for _, seg in
			{
				{ 1322, -334.5, 1346.8, -351.4 },
				{ 1346.8, -351.4, 1337.3, -347.0 },
				{ 1312, -334.5, 1336.8, -351.4 },
				{ 1332, -334.5, 1356.8, -351.4 },
			}
		do
			local ax, az, bx, bz = seg[1], seg[2], seg[3], seg[4]
			local part = WallAudit.crossing(tw, ax, Height.at(ax, az), az, bx, Height.at(bx, bz), bz)
			if part and WalkWay.clear(way, ax, az, bx, bz) then
				table.insert(
					bad,
					string.format("(%.1f, %.1f) -> (%.1f, %.1f): clear, but %s", ax, az, bx, bz, part.path)
				)
			end
		end
		t.eq(#bad, 0, table.concat(bad, "\n"))
	end)

	t.test("repeatable: the audit's run gives the same report twice (a fixed think budget, not the clock's)", function()
		local tw = baked()
		local a = WallAudit.run(tw, data, { seed = 1, minutes = 3, near = true })
		local b = WallAudit.run(tw, data, { seed = 1, minutes = 3, near = true })
		t.eq(a.steps, b.steps, "the same steps")
		t.eq(a.crossings, b.crossings, "the same crossings")
	end)

	t.test("stuck: a body nobody sees with no way at all (ground walled all round) is put back on its lane", function()
		local world = TownAI.build({ data = data, seed = 1, squirrels = 0, deer = 0, fox = 0 })
		local a, brain = person(world)
		local sx, sz = closedIn(world)
		local lane = brain.params.lanes[1]
		local lx, lz =
			if lane.axis == "x" then lane.min else lane.fixed, if lane.axis == "x" then lane.fixed else lane.min
		t.eq((WalkWay.find(world.way, sx, sz, lx, lz)), nil, "no way down from there")
		TownAI.suspend(world, a.id)
		TownAI.resume(world, a.id, sx, Height.at(sx, sz) + a.hip, sz)
		-- nobody near: the only player is far off
		TownAI.setFocus(world, function()
			return { { x = 1e5, z = 1e5 } }
		end)
		for _ = 1, math.floor(60 / DT) do
			TownAI.stepFrame(world, DT)
		end
		local moved = math.sqrt((a.x - sx) ^ 2 + (a.z - sz) ^ 2)
		local onLane = false
		for _, l in brain.params.lanes do
			local u, c = if l.axis == "x" then a.x else a.z, if l.axis == "x" then a.z else a.x
			if math.abs(c - l.fixed) < 2 and u >= l.min - 1 and u <= l.max + 1 then
				onLane = true
			end
		end
		print(string.format("      from (%.0f, %.0f): now at (%.0f, %.0f), %s", sx, sz, a.x, a.z, brain.state))
		t.truthy(moved > 50 and onLane, `still {moved} studs from there, on a lane: {onLane}`)
	end)

	t.test("covered: every baked wall a walker's waist meets lies inside a WalkWay box (static)", function()
		local tw = baked()
		local world = TownAI.build({ data = data, seed = 1, squirrels = 0, deer = 0, fox = 0 })
		local gaps = WallAudit.uncovered(tw, world.way, world.ctx.groundAt)
		local bad, known = {}, 0
		for _, g in gaps do
			-- (Lookout Hill's trail terrace, its benches and its seeded boulders: tools/bake/skylift/Approach lays
			-- them by its own seeded dressing and survey of the hill, which the server does not repeat at boot)
			if string.sub(g.part.path, 1, 17) == "xs_lift_approach." then
				known += 1
			else
				table.insert(bad, string.format("%s at (%.1f, %.1f) y %.1f", g.part.path, g.x, g.z, g.y))
			end
		end
		print(`      {#gaps} walls outside every WalkWay box, {known} of them on Lookout Hill's trail and dressing`)
		t.eq(#bad, 0, table.concat(bad, "\n"))
	end)

	t.test("props: the poles and tree trunks standing on a lane are stepped round", function()
		local tw = baked()
		local world = TownAI.build({ data = data, seed = 1, squirrels = 0, deer = 0, fox = 0 })
		local a, brain = person(world)
		local tried, bad = 0, {}
		for _, lane in brain.params.lanes do
			for _, p in lane.dodges or {} do
				for _, dir in { 1, -1 } do
					local u0 = math.clamp(p[1] - dir * 12, lane.min, lane.max)
					local u1 = math.clamp(p[1] + dir * 12, lane.min, lane.max)
					if math.abs(u1 - u0) < 8 then
						continue
					end
					tried += 1
					local x, z =
						if lane.axis == "x" then u0 else lane.fixed, if lane.axis == "x" then lane.fixed else u0
					TownAI.suspend(world, a.id)
					TownAI.resume(world, a.id, x, Height.at(x, z) + a.hip, z)
					brain.lane, brain.state, brain.goal, brain.walkSpeed = lane, "walk", u1, 4
					local soft = {}
					TownAI.setFocus(world, function()
						return { { x = a.x, z = a.z } }
					end)
					for _ = 1, math.floor(8 / DT) do
						local ax, ay, az = a.x, a.y - a.hip, a.z
						TownAI.stepFrame(world, DT)
						local part = WallAudit.softCrossing(tw, ax, ay, az, a.x, a.y - a.hip, a.z)
						if part and #soft < 2 then
							table.insert(soft, part.path)
						end
						if (if lane.axis == "x" then a.x else a.z) * dir >= u1 * dir - 1 then
							break
						end
					end
					if #soft > 0 then
						table.insert(
							bad,
							string.format(
								"lane %s %.1f by u %.1f: %s",
								lane.axis,
								lane.fixed,
								p[1],
								table.concat(soft, ", ")
							)
						)
					end
				end
			end
		end
		print(`      {tried} walks past a post on a lane`)
		t.truthy(tried >= 3, `{tried} walks`)
		t.eq(#bad, 0, table.concat(bad, "\n"))
	end)
end
