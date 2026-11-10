--!strict
-- Minimal brains and the S5 scenario under Lune (BUILD_PLAN §4.3 S5; §6.5 SimFull liveness):
-- each brain writes a sane intent and round-trips suspend/resume; the Pedestrian spots a loud
-- squirrel and flees along its lane; the synthetic worst case runs 30 simulated seconds with every
-- actor alive, no NaN, nobody outside the clamp, and reports its pure-Luau ms per frame.
local Units = require("@shared/Config/Units")
local Common = require("@server/Actors/Brains/Common")
local Pedestrian = require("@server/Actors/Brains/Pedestrian")
local Staff = require("@server/Actors/Brains/Staff")
local Officer = require("@server/Actors/Brains/Officer")
local Squirrel = require("@server/Actors/Brains/Squirrel")
local Rodent = require("@server/Actors/Brains/Rodent")
local Fox = require("@server/Actors/Brains/Fox")
local Deer = require("@server/Actors/Brains/Deer")
local Perception = require("@server/Actors/Perception")
local Kinematics = require("@server/AI/Kinematics")
local Scenario = require("@server/AI/Scenario")
local SpikeRoutes = require("@server/AI/SpikeRoutes")

local function lcg(seed: number): () -> number
	local s = seed
	return function(): number
		s = (s * 1103515245 + 12345) % 2147483648
		return s / 2147483648
	end
end

local function ctx(grid: Perception.Grid?, actorsById: { [number]: Common.Actor }?): Common.Ctx
	return {
		now = 0,
		rng = lcg(9),
		groundAt = function()
			return 0
		end,
		threats = (grid or Perception.newGrid(40)) :: any,
		actorsById = actorsById or {},
		bounds = Scenario.BOUNDS,
		routes = SpikeRoutes,
		queryBuffer = {},
	}
end

return function(t)
	t.test("pedestrian: starts on a lane, walks toward a goal on it, lane lock holds", function()
		local rng = lcg(1)
		local actor = Common.newActor(1, "human", "townsperson", "Pedestrian", 50, 50, 2.5)
		local brain = Pedestrian.new(actor, {
			lanes = Pedestrian.defaultLanes(),
			coreLanes = 4,
			speedMin = Units.st(0.8),
			speedMax = Units.st(1.6),
			rng = rng,
		})
		local c = ctx()
		brain:think(0.1, c)
		t.eq(actor.intent.mode, "walk")
		t.truthy(actor.intent.laneAxis ~= nil)
		local start = { actor.x, actor.z }
		for _ = 1, 600 do
			Kinematics.step(actor, 1 / 60, c)
		end
		t.truthy(Common.dist2d(actor.x, actor.z, start[1], start[2]) > 5, "walked")
		if actor.intent.laneAxis == "x" then
			t.near(actor.z, actor.intent.laneCoord :: number, 0.05)
		else
			t.near(actor.x, actor.intent.laneCoord :: number, 0.05)
		end
		local snap = brain:suspend()
		brain:resume(snap)
		t.eq(brain:suspend().goal, snap.goal)
	end)

	t.test("pedestrian: a loud squirrel 5 u ahead is spotted; the human flees along the lane and calms down", function()
		local rng = lcg(2)
		local grid = Perception.newGrid(40)
		local byId: { [number]: Common.Actor } = {}
		local human = Common.newActor(1, "human", "townsperson", "Pedestrian", 0, -30.25, 2.5)
		local brain = Pedestrian.new(human, {
			lanes = Pedestrian.defaultLanes(),
			coreLanes = 1,
			speedMin = Units.st(1),
			speedMax = Units.st(1),
			rng = rng,
		})
		local c = ctx(grid, byId)
		brain:think(0.1, c)
		-- face +x along lane 1 (z = -12.1 u) and put a sprinting squirrel 5 u ahead at ground level
		human.yaw = math.pi / 2
		local squirrel = Common.newActor(2, "squirrel", "normal", "Squirrel", human.x + Units.st(5), human.z, 0.9)
		squirrel.y = 0.5
		squirrel.speed = Units.st(16.8)
		byId[2] = squirrel
		grid:set(2, squirrel.x, squirrel.z)
		brain:think(0.1, c)
		t.eq(brain.state, "flee")
		t.near(human.alert, 8, 1e-9)
		t.near(human.intent.speed, Units.st(7.6))
		t.truthy(human.intent.tx < human.x, "flees away from the squirrel along -x")
		-- without the squirrel the alert decays and the walk resumes under 2 s of alert
		grid:remove(2)
		byId[2] = nil
		c.now = 7
		brain:think(6.5, c)
		t.eq(brain.state, "walk")
		brain:onEvent({ type = "gather", x = 100, z = 100, untilTime = 60 })
		c.now = 8
		brain:think(1, c)
		t.eq(human.intent.tx, 100)
	end)

	t.test("staff: circuit of 4 points around the station, pauses, advances, round-trips", function()
		local actor = Common.newActor(1, "human", "hospitalStaff", "Staff", 0, 0, 2.5)
		local brain = Staff.new(actor, { stationX = 100, stationZ = 200, index = 3 })
		local c = ctx()
		t.near(Common.dist2d(actor.x, actor.z, 100, 200), 0, 10, "starts on the circuit")
		local targets = {}
		for i = 1, 1200 do
			c.now = i / 10
			brain:think(0.1, c)
			for _ = 1, 6 do
				Kinematics.step(actor, 1 / 60, c)
			end
			targets[brain.target] = true
		end
		local visited = 0
		for _ in targets do
			visited += 1
		end
		t.eq(visited, 4, "all four waypoints visited in 2 minutes")
		local snap = brain:suspend()
		brain:resume({ target = 2, pause = 0.5 })
		t.eq(brain.target, 2)
		brain:resume(snap)
	end)

	t.test("officer: patrols a beat and responds to a fender bender", function()
		local actor = Common.newActor(1, "human", "police", "Officer", 0, 0, 2.5)
		local brain = Officer.new(actor, { stationX = -750, stationZ = 725, index = 2 })
		local c = ctx()
		brain:think(0.1, c)
		t.eq(actor.intent.mode, "walk")
		t.near(actor.intent.speed, Units.st(2.3))
		brain:onEvent({ type = "respond", x = -700, z = 700, untilTime = 30 })
		c.now = 1
		brain:think(0.1, c)
		t.near(actor.intent.speed, Units.st(5.5))
		t.eq(actor.intent.tx, -700)
	end)

	t.test("squirrel: runs a route, reverses at the end, transfers at links, round-trips mid-stride", function()
		local rng = lcg(4)
		local actor = Common.newActor(1, "squirrel", "normal", "Squirrel", 0, 0, 0.9)
		local brain = Squirrel.new(actor, { routes = SpikeRoutes, rng = rng, startRoute = SpikeRoutes.routes[1].id })
		local c = ctx()
		local routesSeen = { [actor.intent.routeId] = true }
		local reversed = false
		local lastDir = actor.intent.dir
		for i = 1, 3600 do
			c.now = i / 60
			if i % 6 == 0 then
				brain:think(0.1, c)
			end
			Kinematics.step(actor, 1 / 60, c)
			routesSeen[actor.intent.routeId] = true
			if actor.intent.dir ~= lastDir then
				reversed = true
				lastDir = actor.intent.dir
			end
			t.truthy(actor.x == actor.x and actor.y == actor.y, "no NaN")
		end
		local n = 0
		for _ in routesSeen do
			n += 1
		end
		t.truthy(n >= 2, `visited {n} routes in 60 s`)
		t.truthy(reversed or n >= 3, "reversed at an end or transferred twice")
		t.truthy(actor.moved > 50, `moved {actor.moved} studs`)
		local snap = brain:suspend()
		local actor2 = Common.newActor(2, "squirrel", "normal", "Squirrel", 0, 0, 0.9)
		local brain2 = Squirrel.new(actor2, { routes = SpikeRoutes, rng = lcg(5) })
		brain2:resume(snap)
		t.eq(actor2.intent.routeId, actor.intent.routeId)
		t.near(actor2.intent.s, actor.intent.s)
		t.eq(actor2.intent.dir, actor.intent.dir)
	end)

	t.test("rodent wanders around its hide within W = 8 u; fox roams within its leash; deer graze and flee", function()
		local c = ctx()
		local rodent = Common.newActor(1, "squirrel", "spicy", "Rodent", 0, 0, 0.9)
		local rb = Rodent.new(rodent, { hideX = 100, hideZ = 100, index = 0 })
		local maxD = 0
		for i = 1, 1800 do
			c.now = i / 60
			if i % 6 == 0 then
				rb:think(0.1, c)
			end
			Kinematics.step(rodent, 1 / 60, c)
			maxD = math.max(maxD, Common.dist2d(rodent.x, rodent.z, 100, 100))
		end
		t.truthy(maxD > Units.st(2) and maxD <= Units.st(8) * 1.5 + 1, `rodent wander radius {maxD}`)

		local fox = Common.newActor(2, "fox", "fox", "Fox", 0, 0, 1.9)
		local fb = Fox.new(fox, { originX = 0, originZ = 0 })
		local maxFox = 0
		for i = 1, 7200 do
			c.now = i / 60
			if i % 6 == 0 then
				fb:think(0.1, c)
			end
			Kinematics.step(fox, 1 / 60, c)
			maxFox = math.max(maxFox, Common.dist2d(fox.x, fox.z, 0, 0))
		end
		t.truthy(fox.moved > 100, "fox roamed")
		t.truthy(maxFox < Units.st(115) + 20, `fox stayed near its leash ({maxFox})`)

		local grid = Perception.newGrid(40)
		local byId: { [number]: Common.Actor } = {}
		local cd = ctx(grid, byId)
		local deer = Common.newActor(3, "deer", "doe", "Deer", 0, 0, 4.4)
		local db = Deer.new(deer, { originX = 500, originZ = 500 })
		db:think(0.1, cd)
		t.near(deer.intent.speed, Units.st(1.25), 1e-9, "grazing speed")
		local threat = Common.newActor(4, "squirrel", "spicy", "Rodent", 520, 500, 0.9)
		threat.y = 0.9
		byId[4] = threat
		grid:set(4, threat.x, threat.z)
		db:think(0.1, cd)
		t.near(deer.intent.speed, Units.st(11.8), 1e-9, "flee speed")
		local away = Common.yawOf(deer.x - threat.x, deer.z - threat.z)
		t.near(Common.angleDelta(deer.intent.heading, away), 0, 1e-9)
		local fawn = Common.newActor(5, "deer", "fawn", "Deer", 0, 0, 2.4)
		local fawnBrain = Deer.new(fawn, { originX = 500, originZ = 500, fawn = true })
		fawnBrain:think(0.1, cd)
		t.near(fawn.intent.speed, Units.st(9.0), 1e-9, "fawn flee speed")
	end)

	t.test(
		"S5 scenario: 72 humans, 8 riders, 14 squirrels + rodent, 6 deer, 1 fox, 45 vehicles, 2 fender benders",
		function()
			local world = Scenario.build({ seed = 7 })
			t.eq(#world.actors, 72 + 8 + 14 + 1 + 6 + 1)
			t.eq(#world.vehicles, 45)
			t.eq(#world.focus, 49)
			t.eq(#world.events, 2)
			t.eq(world.vehicles[1].speed, 0, "fender-bender car is stopped")
			t.eq(world.counts.Squirrel, 14)
			t.eq(world.counts.Rodent, 1)
			t.eq(world.counts.Deer, 6)
			t.eq(world.counts.Fox, 1)
			t.eq(world.counts.Officer, 6)
			t.eq((world.counts.Pedestrian or 0) + (world.counts.Staff or 0) + world.counts.Officer, 80)
		end
	)

	t.test("S5 scenario: 30 simulated seconds at 60 Hz: liveness holds, pure-Luau cost reported", function()
		local world = Scenario.build({ seed = 7 })
		local frames = 1800
		local sum, maxMs = 0, 0
		for _ = 1, frames do
			local m = Scenario.stepFrame(world, 1 / 60)
			sum += m.totalMs
			maxMs = math.max(maxMs, m.totalMs)
		end
		local live = Scenario.liveness(world)
		t.truthy(live.ok, `stuck {#live.stuck} nan {live.nan} outside {live.outside}`)
		local m = world.scheduler:metrics()
		t.eq(m.deferredTotal, 0, "nothing deferred at the 4 ms budget")
		t.truthy(m.tiers.near + m.tiers.mid + m.tiers.far == #world.actors)
		print(
			string.format(
				"      [S5 Lune] avg %.3f ms/frame, max %.3f ms, %.0f ticks/s, tiers %d/%d/%d",
				sum / frames,
				maxMs,
				m.ticksPerSecond,
				m.tiers.near,
				m.tiers.mid,
				m.tiers.far
			)
		)
		t.truthy(sum / frames < 4, `pure-Luau frame cost {sum / frames} ms`)
	end)

	t.test("S5 scenario: the allNear upper bound and the 90-human S19 case also hold under Lune", function()
		for _, opts in { { seed = 3, allNear = true }, { seed = 3, humans = 90 } } do
			local world = Scenario.build(opts)
			local sum = 0
			for _ = 1, 600 do
				sum += Scenario.stepFrame(world, 1 / 60).totalMs
			end
			t.truthy(Scenario.liveness(world).ok)
			t.truthy(sum / 600 < 4, `{sum / 600} ms`)
		end
	end)
end
