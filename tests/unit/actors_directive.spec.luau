--!strict
-- Brains/Directive and the brains that obey it (the bite-to-hospital sequence, owner 2026-11-10): a
-- downed person stays down whatever runs past, a routed person walks the waypoints in order with no
-- lane lock, a hidden one keeps its place, orders survive a possession hand-over, Staff and Officer
-- obey the same orders, a person coming back from an order WALKS to the lane instead of sliding, a
-- bitten person runs, and a spot is reported exactly once.
local Units = require("@shared/Config/Units")
local Common = require("@server/Actors/Brains/Common")
local Directive = require("@server/Actors/Brains/Directive")
local Pedestrian = require("@server/Actors/Brains/Pedestrian")
local Staff = require("@server/Actors/Brains/Staff")
local Officer = require("@server/Actors/Brains/Officer")
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

local function pedestrian(x: number, z: number): (Common.Actor, any)
	local actor = Common.newActor(1, "human", "townsperson", "Pedestrian", x, z, 2.5)
	local brain = Pedestrian.new(actor, {
		lanes = Pedestrian.defaultLanes(),
		coreLanes = 1, -- lane 1: along x at z = -12.1 u (-30.25 studs)
		speedMin = Units.st(1),
		speedMax = Units.st(1),
		rng = lcg(2),
	})
	return actor, brain
end

-- think at `hz`, motor at 60 Hz, for `secs`; `each(frame)` runs after every motor step
local function run(
	actor: Common.Actor,
	brain: any,
	c: Common.Ctx,
	secs: number,
	hz: number,
	each: ((dt: number) -> ())?
)
	local acc = 1 -- think on the first frame
	for _ = 1, math.floor(secs * 60 + 0.5) do
		c.now += 1 / 60
		acc += hz / 60
		if acc >= 1 then
			acc -= 1
			brain:think(1 / hz, c)
		end
		Kinematics.step(actor, 1 / 60, c)
		if each then
			each(1 / 60)
		end
	end
end

-- a sprinting squirrel 5 u in front of the human, in plain sight
local function loudSquirrel(
	human: Common.Actor,
	grid: Perception.Grid,
	byId: { [number]: Common.Actor },
	variant: string
): Common.Actor
	human.yaw = math.pi / 2
	local squirrel = Common.newActor(2, "squirrel", variant, "Squirrel", human.x + Units.st(5), human.z, 0.9)
	squirrel.y = 0.5
	squirrel.speed = Units.st(16.8)
	byId[2] = squirrel
	grid:set(2, squirrel.x, squirrel.z)
	return squirrel
end

return function(t)
	t.test("down: a patient on the ground does not move for 60 s, even with a squirrel right there", function()
		local grid = Perception.newGrid(40)
		local byId: { [number]: Common.Actor } = {}
		local human, brain = pedestrian(0, -30.25)
		local c = ctx(grid, byId)
		brain:think(0.1, c)
		loudSquirrel(human, grid, byId, "spicy")
		brain:onEvent({ type = "medical", mode = "down" })
		local x0, z0, yaw0 = human.x, human.z, human.yaw
		run(human, brain, c, 60, 10)
		t.eq(human.x, x0)
		t.eq(human.z, z0)
		t.eq(human.yaw, yaw0, "and does not turn")
		t.eq(human.intent.mode, "stand")
		t.truthy(brain.state ~= "flee", "a downed person does not flee")
		t.truthy(human.speed < 0.01)
		-- without the order the same squirrel sends them running (the order is what holds them)
		brain:onEvent({ type = "medical" })
		human.alert = 0
		run(human, brain, c, 1, 10)
		t.eq(brain.state, "flee")
		t.truthy(math.abs(human.x - x0) > 3, "ran")
	end)

	t.test("route: the waypoints in order at the given speed, no lane lock, then back to the lane on foot", function()
		local human, brain = pedestrian(0, -30.25)
		local c = ctx()
		brain:think(0.1, c)
		local points = { { 40, -30.25 }, { 40, 60 }, { 120, 60 } }
		brain:onEvent({ type = "medical", mode = "route", points = points, speed = 11 })
		local reached = {}
		local maxStep = 0
		local px, pz = human.x, human.z
		run(human, brain, c, 40, 10, function()
			for i, p in points do
				if not reached[i] and Common.dist2d(human.x, human.z, p[1], p[2]) < 2.1 then
					reached[i] = c.now
				end
			end
			maxStep = math.max(maxStep, Common.dist2d(human.x, human.z, px, pz))
			px, pz = human.x, human.z
		end)
		t.truthy(reached[1] and reached[2] and reached[3], "all three waypoints")
		t.truthy(reached[1] < reached[2] and reached[2] < reached[3], "in order")
		-- 40 + 90.25 + 80 studs at 11 studs/s is about 19 s (plus the turns)
		t.truthy(reached[3] > 17 and reached[3] < 24, `finished at {reached[3]} s`)
		t.truthy(maxStep <= 11 / 60 + 1e-6, `never faster than the order's speed ({maxStep * 60} studs/s)`)
		-- the order is over: the person adopts the nearest lane and walks onto it (no slide)
		t.truthy(not Directive.active(brain.directive))
		t.truthy(brain.state == "rejoin" or brain.state == "walk")
		local lane = brain.lane
		local worst = 0
		px, pz = human.x, human.z
		run(human, brain, c, 60, 10, function()
			worst = math.max(worst, Common.dist2d(human.x, human.z, px, pz))
			px, pz = human.x, human.z
		end)
		t.truthy(worst * 60 <= 5, `walked back at {worst * 60} studs/s (a slide would be far faster)`)
		t.eq(brain.state, "walk")
		local cross = if brain.lane.axis == "x" then human.z else human.x
		t.near(cross, brain.lane.fixed, 0.5, "on a lane again")
		t.truthy(lane ~= nil)
	end)

	t.test("route with after = stand: waits at the end for the next order; stagger slows the pace", function()
		local human, brain = pedestrian(0, -30.25)
		local c = ctx()
		brain:think(0.1, c)
		brain:onEvent({ type = "medical", mode = "route", points = { { 30, -30.25 } }, speed = 10, after = "stand" })
		run(human, brain, c, 8, 10)
		t.truthy(brain.directive.done)
		t.truthy(Directive.active(brain.directive), "still under orders")
		t.near(human.x, 30, 2.1, "within reach of the last waypoint")
		t.eq(human.intent.mode, "stand")
		-- a thinking rate of 1 Hz (a far body) still walks the same route
		local far, farBrain = pedestrian(0, -30.25)
		local c2 = ctx()
		farBrain:onEvent({ type = "medical", mode = "route", points = { { 20, -30.25 }, { 20, 10 } }, speed = 10 })
		run(far, farBrain, c2, 12, 1)
		t.truthy(not Directive.active(farBrain.directive), "finished at 1 Hz")
		-- stagger: the same 60 studs take clearly longer
		local sick, sickBrain = pedestrian(0, -30.25)
		local c3 = ctx()
		sickBrain:onEvent({
			type = "medical",
			mode = "route",
			points = { { 60, -30.25 } },
			speed = 10,
			stagger = true,
			after = "stand",
		})
		run(sick, sickBrain, c3, 6.5, 10)
		t.truthy(sick.x < 55, `a sick walker is slower ({sick.x} studs in 6.5 s)`)
		run(sick, sickBrain, c3, 10, 10)
		t.near(sick.x, 60, 2.1, "and still arrives")
	end)

	t.test(
		"hidden and hold: a hidden patient keeps its place; a bystander walks to a spot and faces the victim",
		function()
			local human, brain = pedestrian(0, -30.25)
			local c = ctx()
			brain:onEvent({ type = "medical", mode = "hidden" })
			run(human, brain, c, 20, 10)
			t.eq(human.x, 0)
			t.eq(human.z, -30.25)
			brain:onEvent({ type = "medical", mode = "hold", x = 25, z = -10, faceX = 25, faceZ = 30, speed = 8 })
			t.truthy(not brain.directive.done)
			run(human, brain, c, 10, 10)
			t.truthy(brain.directive.done, "reached the spot")
			t.truthy(Common.dist2d(human.x, human.z, 25, -10) < 2.1)
			t.eq(human.intent.mode, "stand")
			t.near(human.yaw, 0, 0.05, "facing +z, toward the victim")
			local seq = brain.directive.seq
			brain:onEvent({ type = "medical" })
			t.truthy(brain.directive.seq > seq, "every order has its own number")
			t.truthy(Directive.takeReleased(brain.directive))
			t.truthy(not Directive.takeReleased(brain.directive), "reported once")
		end
	)

	t.test("orders survive a possession hand-over (suspend and resume)", function()
		local human, brain = pedestrian(0, -30.25)
		local c = ctx()
		brain:onEvent({
			type = "medical",
			mode = "route",
			points = { { 50, -30.25 }, { 50, 40 } },
			speed = 9,
			after = "stand",
		})
		run(human, brain, c, 3, 10)
		local snap = brain:suspend()
		t.eq(snap.directive.mode, "route")
		brain:onEvent({ type = "medical" }) -- something clears it while suspended
		brain:resume(snap)
		t.truthy(Directive.active(brain.directive))
		run(human, brain, c, 20, 10)
		t.truthy(brain.directive.done)
		t.truthy(Common.dist2d(human.x, human.z, 50, 40) < 2.1)
		-- handed back far from the lane with no order: walks to the nearest lane, no slide
		local other, otherBrain = pedestrian(0, -30.25)
		local s2 = otherBrain:suspend()
		other.x, other.z = 200, 300
		otherBrain:resume(s2)
		t.eq(otherBrain.state, "rejoin")
		local c2 = ctx()
		local worst, px, pz = 0, other.x, other.z
		run(other, otherBrain, c2, 5, 10, function()
			worst = math.max(worst, Common.dist2d(other.x, other.z, px, pz))
			px, pz = other.x, other.z
		end)
		t.truthy(worst * 60 <= 5, `{worst * 60} studs/s`)
	end)

	t.test(
		"a body handed back off its lane stands still until its brain thinks (no slide on the old intent)",
		function()
			-- the brain of a far body thinks once a second: for that second only the motor runs, on
			-- whatever intent is left. Before the hand-over the person was walking, locked to their lane.
			for _, off in { 60, -200 } do
				local human, brain = pedestrian(0, -30.25)
				local c = ctx()
				run(human, brain, c, 2, 10)
				t.eq(human.intent.laneAxis, "x", "walking, locked to the lane")
				local snap = brain:suspend()
				human.x, human.z = human.x + 15, -30.25 + off -- the player walked the body away
				human.speed = 0
				brain:resume(snap)
				local x0, z0 = human.x, human.z
				local worst = 0
				for _ = 1, 60 do
					c.now += 1 / 60
					local px, pz = human.x, human.z
					Kinematics.step(human, 1 / 60, c) -- the motor alone: no think
					worst = math.max(worst, Common.dist2d(human.x, human.z, px, pz) * 60)
				end
				local moved = Common.dist2d(human.x, human.z, x0, z0)
				t.truthy(moved < 1, `handed back {off} studs off the lane: moved {moved} studs before the first think`)
				t.truthy(worst < 5, `{worst} studs/s on the first frames`)
				t.eq(human.intent.laneAxis, nil, "the old lane lock is gone")
				-- and then walks to the nearest lane as before
				run(human, brain, c, 3, 10)
				t.truthy(brain.state == "rejoin" or brain.state == "walk")
			end
			-- staff and officers stand too: no step toward the waypoint they were heading for
			local actor = Common.newActor(1, "human", "police", "Staff", 0, 0, 2.5)
			local staff = Staff.new(actor, { stationX = 100, stationZ = 200, index = 3 }) :: any
			local c = ctx()
			run(actor, staff, c, 3, 10)
			local snap = staff:suspend()
			actor.x, actor.z = actor.x + 80, actor.z - 40
			actor.speed = 0
			staff:resume(snap)
			local x0, z0 = actor.x, actor.z
			for _ = 1, 60 do
				Kinematics.step(actor, 1 / 60, c)
			end
			t.near(Common.dist2d(actor.x, actor.z, x0, z0), 0, 1e-6, "a handed-back staff member waits for its brain")
		end
	)

	t.test("staff and officers obey the same orders and go back to their rounds", function()
		for _, make in
			{
				function(a: Common.Actor): any
					return Staff.new(a, { stationX = 100, stationZ = 200, index = 3 })
				end,
				function(a: Common.Actor): any
					return Officer.new(a, { stationX = -750, stationZ = 725, index = 2 })
				end,
			}
		do
			local actor = Common.newActor(1, "human", "police", "Staff", 0, 0, 2.5)
			local brain = make(actor)
			local c = ctx()
			brain:think(0.1, c)
			local x0, z0 = actor.x, actor.z
			brain:onEvent({ type = "medical", mode = "down" })
			run(actor, brain, c, 30, 10)
			t.eq(actor.x, x0, `{brain.kind} stays down`)
			t.eq(actor.z, z0)
			brain:onEvent({
				type = "medical",
				mode = "route",
				points = { { x0 + 30, z0 }, { x0 + 30, z0 + 30 } },
				speed = 10,
				after = "stand",
			})
			run(actor, brain, c, 10, 10)
			t.truthy(Common.dist2d(actor.x, actor.z, x0 + 30, z0 + 30) < 2.1, `{brain.kind} walked the route`)
			local snap = brain:suspend()
			t.eq(snap.directive.mode, "route")
			brain:resume(snap)
			brain:onEvent({ type = "medical" })
			local moved0 = actor.moved
			run(actor, brain, c, 20, 10)
			t.truthy(actor.moved - moved0 > 5, `{brain.kind} is back on its rounds`)
		end
	end)

	t.test("a spot is reported once; a bitten person and a witness run from the biter", function()
		local grid = Perception.newGrid(40)
		local byId: { [number]: Common.Actor } = {}
		local human, brain = pedestrian(0, -30.25)
		local c = ctx(grid, byId)
		local events = {}
		c.emit = function(kind: string, actor: Common.Actor, other: Common.Actor?)
			table.insert(events, { kind = kind, id = actor.id, other = if other then other.id else nil })
		end
		brain:think(0.1, c)
		t.eq(#events, 0, "nothing to see yet")
		local squirrel = loudSquirrel(human, grid, byId, "spicy")
		for _ = 1, 50 do
			c.now += 0.1
			brain:think(0.1, c)
		end
		t.eq(#events, 1, "one report for one spot, however long they stare")
		t.deepEq(events[1], { kind = "spotted", id = 1, other = 2 })
		-- after calming down, the same squirrel is a new spot
		grid:remove(2)
		c.now += 10
		brain:think(10, c)
		t.eq(brain.state, "walk")
		human.yaw = math.pi / 2
		squirrel.x = human.x + Units.st(5)
		grid:set(2, squirrel.x, squirrel.z)
		brain:think(0.1, c)
		t.eq(#events, 2)
		-- a brain with no sink works as before
		local quiet, quietBrain = pedestrian(0, -30.25)
		local c2 = ctx(grid, byId)
		quietBrain:think(0.1, c2)
		quiet.yaw = math.pi / 2
		squirrel.x = quiet.x + Units.st(5)
		grid:set(2, squirrel.x, squirrel.z)
		quietBrain:think(0.1, c2)
		t.eq(quietBrain.state, "flee")
		-- bitten: runs from the biter along the lane, alert 8; an order in force wins
		local victim, victimBrain = pedestrian(0, -30.25)
		local c3 = ctx()
		victimBrain:think(0.1, c3)
		local biter = Common.newActor(3, "squirrel", "spicy", "Rodent", victim.x + 4, victim.z, 0.9)
		victimBrain:onEvent({ type = "bitten", threat = biter })
		t.eq(victimBrain.state, "flee")
		t.near(victim.alert, 8, 1e-9)
		victimBrain:think(0.1, c3)
		t.truthy(victim.intent.tx < victim.x, "away from the biter")
		t.near(victim.intent.speed, Units.st(7.6))
		victimBrain:onEvent({ type = "medical", mode = "down" })
		victimBrain:onEvent({ type = "witness", threat = biter, alert = 10 })
		victimBrain:think(0.1, c3)
		t.eq(victim.intent.mode, "stand", "a patient on the ground does not get up to run")
	end)

	t.test("an alarm (someone collapsed nearby) keeps a runner running and blinds nobody", function()
		-- a walker who hears the alarm still sees the rodent in front of them at once (the alarm used
		-- to raise `alert`, which also switches the spot reaction off: 7 s of strolling past it)
		local grid = Perception.newGrid(40)
		local byId: { [number]: Common.Actor } = {}
		local human, brain = pedestrian(0, -30.25)
		local c = ctx(grid, byId)
		local spotted = 0
		c.emit = function(kind: string)
			if kind == "spotted" then
				spotted += 1
			end
		end
		brain:think(0.1, c)
		brain:onEvent({ type = "alarm", alert = 7 })
		t.eq(human.alert, 0, "a walker's alert is left alone")
		loudSquirrel(human, grid, byId, "spicy")
		local secs = 0
		while secs < 3 and brain.state ~= "flee" do
			c.now += 0.1
			secs += 0.1
			brain:think(0.1, c)
		end
		t.eq(brain.state, "flee")
		t.truthy(secs <= 1, `fled {secs} s after the rodent came into view`)
		t.eq(spotted, 1, "and the spot was reported (somebody may say a line)")
		-- someone already running keeps running for the 7 s
		human.alert = 2.5
		brain:onEvent({ type = "alarm", alert = 7 })
		t.eq(human.alert, 7)
		brain:onEvent({ type = "alarm", alert = 3 })
		t.eq(human.alert, 7, "never lowered")
	end)
end
