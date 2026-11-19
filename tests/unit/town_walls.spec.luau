--!strict
-- Nobody walks through a wall (the owner's playtest, 19 November: "one of the characters ran through a wall"). The
-- whole town AI (AI/TownAI: every brain, the real TrafficService, the bite-to-hospital sequence with its runs,
-- crowds, ambulances, walk-ins and walks home, the staff rounds, the police) runs on the real baked town (build/
-- Town.rbxm, the bowling alley and the TV station, the built expansions) with a player biting someone every half a
-- minute, police calls and stakeouts, and bodies a player leaves anywhere a body can stand (tests/lib/WallAudit);
-- every step of every computer-run body on the ground is tested against every colliding part a walker's waist or
-- chest meets. The budget is 0 wall crossings. (A tree's trunk and a prop under WallAudit.PROP across, a
-- telephone pole, are not walls; nothing in the town AI changes by day or night but the yard dogs, run both ways.)
-- Also held here: the lanes the people walk miss every baked wall, the way out of each building with ways inside
-- (the police station's locker room, the corner store's till) is clear in the bake, and World/WalkWay's put-back
-- and ways never pass a building.
-- A longer audit (30 simulated minutes, more seeds): lune run tools/sim/wall_audit.luau.
local fs = require("@lune/fs")
local Data = require("@shared/Data")
local Height = require("@shared/World/Height")
local WalkWay = require("@shared/World/WalkWay")
local StaffRounds = require("@shared/Actors/StaffRounds")
local Nav = require("@server/Actors/Nav")
local Town = require("@shared/World/Town")
local WallAudit = require("@tests/lib/WallAudit")

-- the runs: seed, simulated minutes, whether a player is near (brains think at 10 Hz there; elsewhere at 1 Hz), and
-- whether the duel runs round the rodent and the two nearest officers chase it after each bite (WallAudit's combat
-- and chase). Each run is the same run every time (WallAudit.BUDGET_MS: the think budget is not the clock's).
local RUNS = {
	{ seed = 1, minutes = 8, near = true },
	{ seed = 2, minutes = 8, near = false },
	{ seed = 3, minutes = 8, near = true, combat = true, chase = true },
}

return function(t)
	local data = Data.default()
	local town: WallAudit.Town? = nil
	local function baked(): WallAudit.Town
		if town == nil then
			for _, path in WallAudit.FILES do
				t.truthy(
					fs.isFile(path),
					`{path} (lune run tools/bake/main.luau, attractions.luau, the expansion bakes)`
				)
			end
			town = WallAudit.load()
		end
		return town :: WallAudit.Town
	end

	t.test("the whole town AI for 24 simulated minutes: 0 steps through a wall", function()
		local tw = baked()
		local total = {
			steps = 0,
			bites = 0,
			handBacks = 0,
			responds = 0,
			crowds = 0,
			dispatched = 0,
			walkIns = 0,
			chaseOrders = 0,
			duelWalkSteps = 0,
		}
		for _, run in RUNS do
			local r = WallAudit.run(tw, data, {
				seed = run.seed,
				minutes = run.minutes,
				near = run.near,
				combat = run.combat,
				chase = run.chase,
			})
			t.eq(r.crossings, 0, `seed {run.seed}:\n{WallAudit.format(r)}`)
			total.steps += r.steps
			for k in total do
				if k ~= "steps" then
					total[k] += r.events[k] or 0
				end
			end
		end
		-- (the audit did what it says: the town moved and every kind of walk happened)
		t.truthy(total.steps > 300000, `{total.steps} steps`)
		t.truthy(total.bites >= 25, `{total.bites} bites`)
		t.truthy(total.handBacks >= 60, `{total.handBacks} hand-backs`)
		t.truthy(total.responds >= 10, `{total.responds} police calls`)
		t.truthy(total.dispatched >= 5, `{total.dispatched} ambulances`)
		t.truthy(total.walkIns >= 3, `{total.walkIns} walk-ins`)
		t.truthy(total.chaseOrders >= 100, `{total.chaseOrders} chase orders`)
		t.truthy(total.duelWalkSteps >= 10, `{total.duelWalkSteps} steps walked in the duel`)
	end)

	t.test("the yard dogs keep inside their yards' fences, by day and at night", function()
		local tw = baked()
		for _, night in { false, true } do
			local r = WallAudit.dogs(tw, 5, night)
			t.eq(r.crossings, 0, WallAudit.format(r))
		end
	end)

	t.test("every lane piece the people walk misses every baked wall", function()
		local tw = baked()
		local way = WalkWay.new({ data = data })
		local nav = Nav.build(Town.fromData(data), nil)
		local pieces, bad = 0, {}
		for _, lane in Nav.lanes(nav) do
			for _, piece in WalkWay.splitLane(way, lane) do
				pieces += 1
				local function at(u: number): (number, number)
					if piece.axis == "x" then
						return u, piece.fixed
					end
					return piece.fixed, u
				end
				-- walked end to end in 2-stud steps at the computer's ground (World/Ground over the pavements)
				local u = piece.min
				while u < piece.max do
					local v = math.min(piece.max, u + 2)
					local ax, az = at(u)
					local bx, bz = at(v)
					local part = WallAudit.crossing(tw, ax, Height.at(ax, az), az, bx, Height.at(bx, bz), bz)
					if part and #bad < 10 then
						table.insert(
							bad,
							string.format("%s %.1f..%.1f at %.1f: %s", piece.axis, u, v, piece.fixed, part.path)
						)
					end
					u = v
				end
			end
		end
		t.truthy(pieces > 50, `{pieces} lane pieces`)
		t.eq(#bad, 0, table.concat(bad, "\n"))
	end)

	t.test(
		"the ways out of the police station's locker room and from behind the corner store's till are clear",
		function()
			local tw = baked()
			local function walk(name: string, points: { { number } }, floorAt: (x: number, z: number) -> number)
				for i = 1, #points - 1 do
					local a, b = points[i], points[i + 1]
					local part =
						WallAudit.crossing(tw, a[1], floorAt(a[1], a[2]), a[2], b[1], floorAt(b[1], b[2]), b[2])
					t.eq(part and part.path, nil, `{name}: leg {i}`)
				end
			end
			local station = data:lot("west_police_station")
			t.truthy(station, "the police station")
			local chain = {}
			for _, p in StaffRounds.POLICE_EXIT do
				table.insert(chain, { station.x + p[1], station.z + p[2] })
			end
			local floor = 0.5 -- (the station's floor: Height there)
			walk("police station", chain, function(x: number, z: number): number
				return math.max(Height.at(x, z), floor)
			end)
			-- the round's points to the way's first point
			local sx, sz = station.x + StaffRounds.POLICE.x, station.z + StaffRounds.POLICE.z
			for index = 1, 2 do
				for _, p in StaffRounds.points(sx, sz, index) do
					walk("locker room round to its way", { p, chain[1] }, function(x: number, z: number): number
						return math.max(Height.at(x, z), floor)
					end)
				end
			end
			local venues = StaffRounds.venues(data:module("Expansion"))
			local staffed = 0
			for _, v in venues do
				local post = v.post
				if post and post.exit then
					staffed += 1
					walk(v.id, post.exit, function(x: number, z: number): number
						return StaffRounds.floorAt(venues, x, z) or Height.at(x, z)
					end)
				end
			end
			t.truthy(staffed >= 1, "the corner store's till")
			-- (the baked town is some hundreds of megabytes of solids: let it go for the specs after this one,
			-- whose timings a full heap would slow)
			town = nil
		end
	)

	t.test(
		"WalkWay: a body left in a shell is let go outside it; ways and clear lines never pass a building",
		function()
			local way = WalkWay.new({ data = data })
			-- a house shell (a solid lot): put back outside its walls, on open ground
			local lot = data:lot("outer_home_07")
			t.truthy(lot, "outer_home_07")
			local x, z = WalkWay.putBack(way, lot.x + 3, lot.z - 2)
			t.eq(WalkWay.solidAt(way, x, z), nil, "put back outside the shell")
			t.truthy(
				math.abs(x - lot.x) >= lot.footprint.w / 2 or math.abs(z - lot.z) >= lot.footprint.d / 2,
				"outside"
			)
			-- open ground stays
			local ox, oz = WalkWay.putBack(way, lot.x, lot.z + lot.footprint.d / 2 + 12)
			t.eq(ox, lot.x)
			t.eq(oz, lot.z + lot.footprint.d / 2 + 12)
			-- a way from one side of the house to the other goes round it; the straight line is not clear
			local ax, az = lot.x, lot.z - lot.footprint.d / 2 - 8
			local bx, bz = lot.x, lot.z + lot.footprint.d / 2 + 8
			t.falsy(WalkWay.clear(way, ax, az, bx, bz), "the line through the house")
			local points = WalkWay.find(way, ax, az, bx, bz)
			t.truthy(points and #points >= 2, "a way round")
			local px, pz = ax, az
			for _, p in points or {} do
				t.truthy(WalkWay.clear(way, px, pz, p[1], p[2]), "each leg of the way is clear")
				px, pz = p[1], p[2]
			end
			-- inside a shell there is no way at all
			t.eq((WalkWay.find(way, lot.x, lot.z, bx, bz)), nil, "no way out of a shell")
			-- the police station: in and out by its door, never through its walls
			local station = data:lot("west_police_station")
			local inside = { station.x + StaffRounds.POLICE.x, station.z + StaffRounds.POLICE.z }
			local behind = { station.x, station.z - station.footprint.d / 2 - 10 }
			local out = WalkWay.find(way, inside[1], inside[2], behind[1], behind[2])
			t.truthy(out, "a way out of the locker room")
			local door = way.roomOf[station.id].door
			local passed = false
			for _, p in out or {} do
				if math.abs(p[1] - door[1]) + math.abs(p[2] - door[2]) < 0.6 then
					passed = true
				end
			end
			t.truthy(passed, "out by the front door")
		end
	)
end
