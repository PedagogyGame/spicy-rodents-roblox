--!strict
-- Who sees what under the alley's raised roof (BRIEF_ADDENDUM D9; the map's Q4: walking near people gets you seen in
-- a second or two), on the alley baked in memory by its own bake code (tests/lib/BakedWorld.bakeAlley) with the line
-- of sight Server/Attractions/RafterService draws (a ray from the eye to each of RafterWatch.aimPoints, the body and
-- the top of the head, in its collision group RafterService.SIGHT_GROUP; what the ray hits is Roblox's rule,
-- Shared/World/CollisionGroups.rayHits: a colliding part takes queries whatever its CanQuery says; a hit within
-- RafterService.C.beamSlack of the aim is the beam under the squirrel), stepped at the service's 5 Hz by
-- Stealth/RafterSense and Stealth/RafterWatch:
--   * the trusses right over the approaches (9121 at D -10.5, 9122 at D -1.5): a bowler under one sees only the
--     plate's underside, but people on the settees behind see over its edge, so walking there is seen in seconds;
--   * the middle trusses: the bowlers see a walk, and a creep the length of the hall gets on a long way first;
--   * the invisible walls do not hide the rafters: the lanes' LaneGuard boxes (9 studs tall at the foul line, in
--     front of every bowler) stop a ray in the Default group, and the sight ray passes them.
local AlleyLayout = require("@shared/Attractions/AlleyLayout")
local AlleyRoof = require("@shared/Attractions/AlleyRoof")
local RafterSense = require("@shared/Stealth/RafterSense")
local RafterWatch = require("@shared/Stealth/RafterWatch")
local RafterService = require("@server/Attractions/RafterService")
local CollisionGroups = require("@shared/World/CollisionGroups")
local BakedWorld = require("@tests/lib/BakedWorld")

local TICK = RafterService.TICK

return function(t)
	local baked, place = BakedWorld.bakeAlley()

	-- the line of sight with a ray in collision group `group` (the service's, unless a case says otherwise)
	local function sightIn(group: string): (o: RafterWatch.Observer, s: RafterWatch.Squirrel) -> boolean
		local function hits(q: any): boolean
			return CollisionGroups.rayHits(group, q.collide, q.query, q.group)
		end
		return function(o: RafterWatch.Observer, s: RafterWatch.Squirrel): boolean
			local ex, ey, ez = AlleyLayout.toWorld(place, o.X, o.Y, o.D)
			for _, a in RafterWatch.aimPoints(s) do
				local wx, wy, wz = AlleyLayout.toWorld(place, a[1], a[2], a[3])
				local dx, dy, dz = wx - ex, wy - ey, wz - ez
				local hit = baked.raycast(ex, ey, ez, dx, dy, dz, hits)
				if hit == nil or (1 - hit) * math.sqrt(dx * dx + dy * dy + dz * dz) <= RafterService.C.beamSlack then
					return true
				end
			end
			return false
		end
	end
	local canSee = sightIn(RafterService.SIGHT_GROUP)

	-- people facing the pins: the computer bowlers on the approaches of the given lanes (RafterService.BOWLER_EYE),
	-- or people on the settees (eye 5.0 over the floor, AlleyLayout.SETTEE_D) at the given X
	local function bowlers(lanes: { number }): { RafterWatch.Observer }
		local out = {}
		local e = RafterService.BOWLER_EYE
		for _, lane in lanes do
			table.insert(
				out,
				{ id = `bowler {lane}`, X = AlleyLayout.laneX(lane), Y = e.y, D = e.d, faceX = 0, faceD = 1 }
			)
		end
		return out
	end
	local function settees(xs: { number }): { RafterWatch.Observer }
		local out = {}
		for _, x in xs do
			table.insert(out, { id = `settee {x}`, X = x, Y = 5.0, D = AlleyLayout.SETTEE_D, faceX = 0, faceD = 1 })
		end
		return out
	end

	-- A squirrel running the chord at D `d` from the east aisle to the west at `speed`: when it is spotted (nil:
	-- never) and the fraction of ticks anyone could see it.
	local function run(
		d: number,
		speed: number,
		people: { RafterWatch.Observer },
		sight: ((o: RafterWatch.Observer, s: RafterWatch.Squirrel) -> boolean)?
	): (number?, number)
		local see = sight or canSee
		local sense, watch = RafterSense.new(), RafterWatch.new()
		local X, clock, ticks, inView = 96, 0, 0, 0
		while X > AlleyRoof.CHORD.x0 do
			local s = RafterSense.sense(sense, "sq", X, AlleyRoof.CHORD.y1, d, TICK)
			if s then
				ticks += 1
				for _, o in people do
					if see(o, s) then
						inView += 1
						break
					end
				end
				for _, e in RafterWatch.step(watch, { s }, people, nil, TICK, see) do
					if e.kind == "spotted" then
						return clock, inView / ticks
					end
				end
			end
			X -= speed * TICK
			clock += TICK
		end
		return nil, inView / math.max(1, ticks)
	end

	local everyLane = {}
	for lane = 1, AlleyLayout.LANES do
		table.insert(everyLane, lane)
	end
	local sixSettees = { -10, 10, 30, 50, 70, 90 }

	t.test("the trusses over the approaches: hidden from the bowlers under them, seen from the settees", function()
		for _, d in { -10.5, -1.5 } do
			local _, bowlersSee = run(d, 18, bowlers(everyLane))
			t.eq(bowlersSee, 0, `D {d}: right under the plate, a bowler sees only its underside`)
			local walked, setteesSee = run(d, 18, settees(sixSettees))
			t.truthy(setteesSee > 0.9, `D {d}: in view of the settees {setteesSee} of the way`)
			t.truthy(walked ~= nil and walked <= 3, `D {d}: walking past the settees, spotted after {walked} s`)
			local sprinted = run(d, 30.5, settees(sixSettees))
			t.truthy(sprinted ~= nil and sprinted <= 1.5, `D {d}: sprinting, spotted after {sprinted} s`)
			local crept = run(d, 3, settees(sixSettees))
			t.truthy(crept == nil or crept >= 15, `D {d}: creeping, spotted after {crept} s`)
			print(
				`      D {d}: walking spotted from the settees after {walked} s, sprinting {sprinted} s, creeping {crept} s`
			)
		end
	end)

	t.test("the middle trusses: the bowlers see a walk; a creep gets most of the way along", function()
		for _, d in { 7.5, 16.5, 25.5 } do
			local walked = run(d, 18, bowlers(everyLane))
			t.truthy(walked ~= nil and walked <= 3, `D {d}: walking past eighteen bowlers, spotted after {walked} s`)
			local crept = run(d, 3, bowlers(everyLane))
			t.truthy(crept == nil or crept >= 15, `D {d}: creeping, spotted after {crept} s`)
		end
	end)

	t.test("the lanes' invisible guards do not hide the rafters from the bowlers", function()
		local inDefault = sightIn(CollisionGroups.DEFAULT)
		for _, d in { 16.5, 25.5, 34.5, 43.5, 52.5 } do
			local _, guarded = run(d, 18, bowlers(everyLane), inDefault)
			t.eq(guarded, 0, `D {d}: a ray in the Default group stops at the LaneGuard boxes`)
			local _, seen = run(d, 18, bowlers(everyLane))
			t.truthy(seen > 0.9, `D {d}: the sight ray passes them: in view {seen} of the way`)
		end
		for _, g in { CollisionGroups.LANE_GUARD, CollisionGroups.PEOPLE_FENCE, CollisionGroups.SQUIRREL_FENCE } do
			t.eq(
				CollisionGroups.rayHits(RafterService.SIGHT_GROUP, true, false, g),
				false,
				`{g} lets the sight through`
			)
		end
		t.eq(CollisionGroups.rayHits(RafterService.SIGHT_GROUP, true, true, CollisionGroups.DEFAULT), true)
	end)
end
