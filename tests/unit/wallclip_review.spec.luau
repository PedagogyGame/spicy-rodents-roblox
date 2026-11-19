--!strict
-- Review of feat/no-wall-walk (cab30a1) merged onto w0-foundation 2343c1c: failing cases only (each states what
-- holds when it is fixed).
--   back      the combat duel's "back" order (Brains/Pedestrian state "duel") walks the person 4 studs straight
--             away from the rodent every think, by no way and no clear test: a person on a sidewalk lane with the
--             rodent in the street backs into the house behind them (the duel landed after the branch was cut, so
--             the branch's audit never ran it)
--   approach  the duel's "approach" walks straight at the rodent; CombatService only holds it back when a
--             building box blocks the sight line at the person's feet + 3, so a wall or fence a walker cannot pass
--             but can see over (LOW 1.5 to 3 studs tall) is walked through
--   chase     Common.toward asks for a new way whenever the spot moves more than 0.5 studs, before it looks at the
--             failed search's back-off: an officer chasing the rodent across the river (CombatService re-orders a
--             chase every 0.5 s and an officer in a duel every 0.1 s) runs a failing FootPath search, the dearest
--             kind, on every order
--   margin    WalkWay.clear skips a whole box when an end is inside its walls, and WalkWay.solidAt only counts a
--             point MARGIN (0.2) inside them: from a spot 0.1 studs inside a house's box the straight line through
--             the whole house is "clear"
--   standoff  (task item 4; not walls) an ambulance turning left off the west residential street onto the z = 5 road
--             stands for good with a dump truck following 9 studs behind it: AICarMotor's routeGap samples the
--             route from 1 stud ahead of the ambulance's centre, not its nose, and counts any body heading within
--             72 degrees of the route there whose capsule comes within both half widths + 0.5 studs (7.6 for a
--             truck 8.4 wide); mid-turn the follower's front end is 3 studs from those points, so room = 0; the
--             truck brakes for the emergency vehicle in front of it (bracesFor). Neither moves until the case is
--             given up (155 s in infection_service's "no way to walk" case at be30746, victim by (300, 300))
--   rounds    (holds on the merged tree; kept as a guard) every Staff brain's round, the shop workers' new pavement
--             rounds included, misses every baked wall
--   audit     tools/sim/wall_audit --seeds 1,2 --minutes 30 crossed 3 walls on the merged tree: a shop worker walking
--             back to its quay round through the clock tower's plinth (the baked plinth stands past the lot's
--             footprint, the only box WalkWay has for it) and a rejoin along the river's south edge through the quay
--             wall (quay_willow_river is a "plate": no box; the river's closed box ends at the wall)
--   far       a body left on the east bank (the quay, the galleria: the way round the river is 1,500 to 3,300 studs,
--             past TownAI.WAY_NODES) or out past Height.worldClamp (inside TownAI's bounds, where a player can leave
--             it; the path-finder has no cells there) never walks again: no way, back-off to 64 s, forever
-- Bakes first: lune run tools/bake/main.luau, attractions.luau and the expansion bakes (as tools/ci.sh).
local Data = require("@shared/Data")
local WalkWay = require("@shared/World/WalkWay")
local Colliders = require("@shared/World/Colliders")
local Height = require("@shared/World/Height")
local TownAI = require("@server/AI/TownAI")
local WallAudit = require("@tests/lib/WallAudit")
local TrafficService = require("@server/Traffic/TrafficService")
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

	t.test("chase: an officer re-ordered after a rodent it has no way to does not search on every order", function()
		local world = TownAI.build({ data = data, seed = 1, squirrels = 0, deer = 0, fox = 0 })
		local ctx = world.ctx :: any
		local inner = ctx.way
		local calls, none, ms, worst = 0, 0, 0, 0
		ctx.way = function(x0: number, z0: number, x1: number, z1: number): any
			local t0 = os.clock()
			local out = inner(x0, z0, x1, z1)
			local d = (os.clock() - t0) * 1000
			calls += 1
			none += if out == nil then 1 else 0
			ms += d
			worst = math.max(worst, d)
			return out
		end
		local cop, brain = nil, nil
		for _, a in world.actors do
			local b = world.brains[a.id] :: any
			if b and b.kind == "Officer" then
				cop, brain = a, b
				break
			end
		end
		assert(cop and brain, "an officer")
		-- the officer on the west bank, the rodent running about on the east bank (no walker crosses the river)
		local function open(x0: number, x1: number, z: number): number
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
		local wz, ez = 300, 300
		local wx, ex = open(1960, 1700, wz), open(2290, 2600, ez)
		t.eq((WalkWay.find(world.way, wx, wz, ex, ez)), nil, "no way over the river on foot")
		TownAI.suspend(world, cop.id)
		TownAI.resume(world, cop.id, wx, Height.at(wx, wz) + cop.hip, wz)
		local nextAt = 0
		walk(world, cop, 30, function(now: number)
			-- CombatService.stepChases: every CHASE_EVERY (0.5 s), where the rodent is now (it runs 8 studs a second)
			if now >= nextAt then
				nextAt = now + 0.5
				brain:onEvent({ type = "respond", x = ex + 8 * now % 40, z = ez, untilTime = now + 1 })
			end
		end)
		print(
			string.format(
				"      30 s: %d way searches, %d found none, %.0f ms in all, worst %.1f ms",
				calls,
				none,
				ms,
				worst
			)
		)
		-- (a failed search backs off 4 s doubling to 64 s: 4 or 5 in 30 s)
		t.truthy(calls <= 6, `{calls} searches in 30 s`)
	end)

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
		traffic:step(10, { people = {} })
		t.truthy(amb.s > s0 + 20, `the ambulance drove {amb.s - s0} studs in 10 s (the truck {truck.speed} st/s)`)
	end)
end
