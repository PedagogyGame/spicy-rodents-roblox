--!strict
-- ServerScriptService.Server.AI.Scenario
-- The S5 / S19 synthetic worst case as a pure, steppable world (BUILD_PLAN §4.3 S5, S19; D4): N AI
-- humans on posts (Pedestrian, Staff, Officer brains), non-Humanoid riders, squirrels running the
-- spike route subset, one AI rodent, deer, a fox, vehicle proxies on the v5.4 lanes at 30 Hz, two
-- fender-bender events, and moving focus points standing in for 49 players. Runs under Lune (the
-- liveness test) and inside the Luau Execution task (tests/engine/AIScale) which adds puppets.
-- Interface: build(opts) -> World, stepFrame(world, dt) -> FrameMetrics, liveness(world) -> Report
-- Pure; studs via Config/Units. The frame order mirrors §1.3: brains -> AI motors -> traffic.

local Units = require("../../shared/Config/Units")
local Species = require("../../shared/Actors/Species")
local Population = require("../../shared/Actors/Population")
local Common = require("../Actors/Brains/Common")
local BrainScheduler = require("../Actors/BrainScheduler")
local Perception = require("../Actors/Perception")
local Pedestrian = require("../Actors/Brains/Pedestrian")
local Staff = require("../Actors/Brains/Staff")
local Officer = require("../Actors/Brains/Officer")
local SquirrelBrain = require("../Actors/Brains/Squirrel")
local Rodent = require("../Actors/Brains/Rodent")
local Fox = require("../Actors/Brains/Fox")
local Deer = require("../Actors/Brains/Deer")
local Kinematics = require("./Kinematics")
local SpikeRoutes = require("./SpikeRoutes")

export type Opts = {
	humans: number?, -- AI human bodies (default: the S5 config's 72)
	riders: number?,
	squirrels: number?,
	deer: number?,
	fox: number?,
	vehicles: number?,
	fenderBenders: number?,
	players: number?, -- moving focus points
	seed: number?,
	allNear: boolean?, -- force the Near tier for every brain (upper bound)
	budgetMs: number?,
}

export type Vehicle = {
	id: number,
	x: number,
	y: number,
	z: number,
	yaw: number,
	axis: "x" | "z",
	fixed: number,
	dir: number,
	speed: number, -- studs/s (0 = parked)
	min: number,
	max: number,
	width: number,
	length: number,
	height: number,
	rig: any?,
}

export type FocusPoint = { x: number, z: number, axis: "x" | "z", dir: number, speed: number, min: number, max: number }

export type FrameMetrics = {
	brainMs: number,
	motorMs: number,
	trafficMs: number,
	gridMs: number,
	totalMs: number,
	ticked: number,
	deferred: number,
}

export type World = {
	opts: Opts,
	actors: { Common.Actor },
	actorsById: { [number]: Common.Actor },
	brains: { [number]: Common.Brain },
	vehicles: { Vehicle },
	focus: { FocusPoint },
	scheduler: BrainScheduler.Scheduler,
	grid: Perception.Grid,
	ctx: Common.Ctx,
	rng: () -> number,
	now: number,
	frame: number,
	trafficAccumulator: number,
	events: { { x: number, z: number, untilTime: number } },
	counts: { [string]: number },
}

local Scenario = {}

-- World clamp (humans_actors §5.2 11), studs.
Scenario.BOUNDS = { minX = Units.st(-265), maxX = Units.st(671), minZ = Units.st(-241), maxZ = Units.st(436) }

-- Landmarks in HTML units: hospital (-356, 353) [humans_actors §4.4], police station westside
-- (worldgen; the spike uses (-300, 290) as a stand-in), the v5.4 AI squirrel hides and the fox
-- and deer origins [wildlife_foraging §2.1, §11.8, §11.9].
local HOSPITAL = { x = -356, z = 353 }
local STATION = { x = -300, z = 290 }
local HIDES = { { -74, -71 }, { 84, 70 }, { -196, 97 }, { 217, -111 }, { -105, 321 }, { 103, 409 }, { 414, 332 } }
local DEER_ORIGINS = { { 117, 365 }, { 145, 385 }, { 187, 320 }, { -204, 353 }, { 137, 366 }, { 160, 340 } }
local FOX_ORIGIN = { 65, 313 }
local SHOPS =
	{ { 450, 30 }, { 520, -30 }, { 600, 40 }, { 60, -200 }, { -150, 180 }, { 300, 320 }, { 500, 110 }, { 420, -80 } }

-- mulberry32 (the v5.4 rng, L80-89), so scenarios repeat exactly across Lune and the engine.
local function mulberry32(seed: number): () -> number
	local a = seed % 4294967296
	return function(): number
		a = (a + 0x6D2B79F5) % 4294967296
		local t = a
		t = (bit32.bxor(t, bit32.rshift(t, 15)) * bit32.bor(t, 1)) % 4294967296
		t = bit32.bxor(t, (t + (bit32.bxor(t, bit32.rshift(t, 7)) * bit32.bor(t, 61)) % 4294967296) % 4294967296)
		return (bit32.bxor(t, bit32.rshift(t, 14)) % 4294967296) / 4294967296
	end
end

-- A cheap undulating ground so the motor's groundAt costs about what World/Height will.
local function groundAt(x: number, z: number): number
	return 0.6 * math.sin(x * 0.004) * math.cos(z * 0.0035)
end

local LANES = Pedestrian.defaultLanes()

-- Vehicle lanes (traffic §4 table): residential N-S at x = +/-5.4, the E-W grid roads, the boulevard.
local VEHICLE_LANES = {
	{ axis = "z", fixed = -5.4, dir = 1, min = -260, max = 260 },
	{ axis = "z", fixed = 5.4, dir = -1, min = -260, max = 260 },
	{ axis = "x", fixed = -5.6, dir = 1, min = -260, max = 260 },
	{ axis = "x", fixed = 5.6, dir = -1, min = -260, max = 260 },
	{ axis = "x", fixed = -174 - 5.4, dir = 1, min = -260, max = 260 },
	{ axis = "x", fixed = -174 + 5.4, dir = -1, min = -260, max = 260 },
	{ axis = "x", fixed = 171 - 5.4, dir = 1, min = -260, max = 260 },
	{ axis = "x", fixed = 171 + 5.4, dir = -1, min = -260, max = 260 },
	{ axis = "z", fixed = -180 - 5.4, dir = 1, min = -260, max = 260 },
	{ axis = "z", fixed = -180 + 5.4, dir = -1, min = -260, max = 260 },
	{ axis = "z", fixed = 178 - 5.4, dir = 1, min = -260, max = 260 },
	{ axis = "z", fixed = 178 + 5.4, dir = -1, min = -260, max = 260 },
	{ axis = "x", fixed = -5.6, dir = 1, min = 280, max = 660 },
	{ axis = "x", fixed = 5.6, dir = -1, min = 280, max = 660 },
}

local function postCounts(humans: number): { { post: string, count: number } }
	-- the S5 config's proportions, scaled to the requested human count; the protected floors never shrink
	local cfg = Population.spikeS5()
	local fixed = 0
	local list = {}
	for _, post in cfg.posts do
		if post.protected then
			fixed += post.standing
		end
	end
	local flexible = math.max(0, humans - fixed)
	local flexTotal = 0
	for _, post in cfg.posts do
		if not post.protected then
			flexTotal += post.standing
		end
	end
	local assigned = 0
	for _, post in cfg.posts do
		local n
		if post.protected then
			n = post.standing
		else
			n = math.floor(flexible * post.standing / flexTotal)
		end
		assigned += n
		table.insert(list, { post = post.id, count = n })
	end
	-- remainder to townspeople
	list[1].count += humans - assigned
	return list
end

function Scenario.build(opts: Opts): World
	local rng = mulberry32(opts.seed or 1)
	local humans = opts.humans or 72
	local riders = opts.riders or 8
	local squirrelCount = opts.squirrels or 14
	local deerCount = opts.deer or 6
	local foxCount = opts.fox or 1
	local vehicleCount = opts.vehicles or 45
	local fenderBenders = opts.fenderBenders or 2
	local players = opts.players or 49

	local params = table.clone(BrainScheduler.DEFAULTS)
	params.budgetMs = opts.budgetMs or params.budgetMs
	local scheduler = BrainScheduler.new(params)
	if opts.allNear then
		scheduler.forceTier = "near"
	end
	local grid = Perception.newGrid(Units.st(16))
	local actors: { Common.Actor } = {}
	local actorsById: { [number]: Common.Actor } = {}
	local brains: { [number]: Common.Brain } = {}
	local ctx: Common.Ctx = {
		now = 0,
		rng = rng,
		groundAt = groundAt,
		threats = grid,
		actorsById = actorsById,
		bounds = Scenario.BOUNDS,
		routes = SpikeRoutes,
		queryBuffer = table.create(32),
	}
	local nextId = 0
	local counts: { [string]: number } = {}
	local function add(species: string, variant: string, brainKind: string, hip: number): Common.Actor
		nextId += 1
		local x = Common.range(rng, Scenario.BOUNDS.minX, Scenario.BOUNDS.maxX)
		local z = Common.range(rng, Scenario.BOUNDS.minZ, Scenario.BOUNDS.maxZ)
		local actor = Common.newActor(nextId, species, variant, brainKind, x, z, hip)
		table.insert(actors, actor)
		actorsById[nextId] = actor
		counts[brainKind] = (counts[brainKind] or 0) + 1
		return actor
	end
	local function register(actor: Common.Actor, brain: Common.Brain)
		brains[actor.id] = brain
		scheduler:register(actor.id, brain, actor, 0)
	end

	local humanDef = Species.def("human")
	local pedParams: Pedestrian.Params = {
		lanes = LANES,
		coreLanes = 4,
		speedMin = Units.st(0.8),
		speedMax = Units.st(1.6),
		rng = rng,
	}
	local riderParams: Pedestrian.Params = {
		lanes = LANES,
		coreLanes = 4,
		speedMin = Units.st(3.2),
		speedMax = Units.st(5.2),
		rng = rng,
		cyclist = true,
	}
	-- humans by post
	local staffIndex, officerIndex, shopIndex = 0, 0, 0
	for _, entry in postCounts(humans) do
		for _ = 1, entry.count do
			local post = entry.post
			if post == "hospitalStaff" or post == "ambulanceCrew" then
				local actor = add("human", post, "Staff", humanDef.hipHeight)
				actor.post = post
				staffIndex += 1
				local ox = if post == "ambulanceCrew" then 18 else (staffIndex % 4) * 6 - 9
				register(
					actor,
					Staff.new(actor, {
						stationX = Units.st(HOSPITAL.x + ox),
						stationZ = Units.st(HOSPITAL.z + (staffIndex % 3) * 5 - 5),
						index = staffIndex,
					})
				)
			elseif post == "police" then
				local actor = add("human", post, "Officer", humanDef.hipHeight)
				actor.post = post
				officerIndex += 1
				if officerIndex <= 6 then
					register(
						actor,
						Officer.new(
							actor,
							{ stationX = Units.st(STATION.x), stationZ = Units.st(STATION.z), index = officerIndex }
						)
					)
				else
					-- guard and car crew: short circuits at the station
					actor.brainKind = "Staff"
					counts.Officer -= 1
					counts.Staff = (counts.Staff or 0) + 1
					register(
						actor,
						Staff.new(
							actor,
							{
								stationX = Units.st(STATION.x + 4),
								stationZ = Units.st(STATION.z - 6),
								index = officerIndex,
							}
						)
					)
				end
			elseif post == "shopWorker" or post == "attractionStaff" then
				local actor = add("human", post, "Staff", humanDef.hipHeight)
				actor.post = post
				shopIndex += 1
				local shop = SHOPS[(shopIndex - 1) % #SHOPS + 1]
				register(
					actor,
					Staff.new(actor, { stationX = Units.st(shop[1]), stationZ = Units.st(shop[2]), index = shopIndex })
				)
			else
				local actor = add("human", post, "Pedestrian", humanDef.hipHeight)
				actor.post = post
				register(actor, Pedestrian.new(actor, pedParams))
			end
		end
	end
	for _ = 1, riders do
		local actor = add("human", "rider", "Pedestrian", humanDef.hipHeight)
		actor.post = "rider"
		register(actor, Pedestrian.new(actor, riderParams))
	end
	local squirrelDef = Species.def("squirrel")
	for i = 1, squirrelCount do
		local actor = add("squirrel", "normal", "Squirrel", squirrelDef.hipHeight)
		register(
			actor,
			SquirrelBrain.new(
				actor,
				{
					routes = SpikeRoutes,
					rng = rng,
					startRoute = SpikeRoutes.routes[(i * 7) % #SpikeRoutes.routes + 1].id,
				}
			)
		)
	end
	do
		local hide = HIDES[1]
		local actor = add("squirrel", "spicy", "Rodent", squirrelDef.hipHeight)
		register(actor, Rodent.new(actor, { hideX = Units.st(hide[1]), hideZ = Units.st(hide[2]), index = 0 }))
	end
	local deerDef = Species.def("deer")
	for i = 1, deerCount do
		local o = DEER_ORIGINS[(i - 1) % #DEER_ORIGINS + 1]
		local fawn = i == 5
		local actor = add(
			"deer",
			if fawn then "fawn" else (if i % 3 == 0 then "buck" else "doe"),
			"Deer",
			deerDef.hipHeight * (if fawn then Species.FAWN_SCALE else 1)
		)
		register(
			actor,
			Deer.new(actor, { originX = Units.st(o[1]), originZ = Units.st(o[2]), fawn = fawn, phase = rng() * 9 })
		)
	end
	local foxDef = Species.def("fox")
	for _ = 1, foxCount do
		local actor = add("fox", "fox", "Fox", foxDef.hipHeight)
		register(actor, Fox.new(actor, { originX = Units.st(FOX_ORIGIN[1]), originZ = Units.st(FOX_ORIGIN[2]) }))
	end

	-- vehicle proxies: sedans on the lanes, R(6.5, 9.5) u/s; the first 2 x 2 are the fender benders
	local vehicles: { Vehicle } = {}
	local events = {}
	for i = 1, vehicleCount do
		local lane = VEHICLE_LANES[(i - 1) % #VEHICLE_LANES + 1]
		local u = Common.range(rng, lane.min, lane.max)
		local v: Vehicle = {
			id = i,
			x = if lane.axis == "x" then Units.st(u) else Units.st(lane.fixed),
			y = 0,
			z = if lane.axis == "z" then Units.st(u) else Units.st(lane.fixed),
			yaw = if lane.axis == "x"
				then (if lane.dir > 0 then math.pi / 2 else -math.pi / 2)
				else (if lane.dir > 0 then 0 else math.pi),
			axis = lane.axis,
			fixed = Units.st(lane.fixed),
			dir = lane.dir,
			speed = Units.st(Common.range(rng, 6.5, 9.5)),
			min = Units.st(lane.min),
			max = Units.st(lane.max),
			width = Units.st(2.35),
			length = Units.st(4.45),
			height = Units.st(2.04),
			rig = nil,
		}
		table.insert(vehicles, v)
	end
	for e = 1, fenderBenders do
		local a, b = vehicles[2 * e - 1], vehicles[2 * e]
		if a and b then
			a.speed, b.speed = 0, 0
			b.x, b.z = a.x + Units.st(1.2), a.z + Units.st(4.0)
			b.yaw = a.yaw + 0.35
			table.insert(events, { x = a.x, z = a.z, untilTime = 600 })
		end
	end

	-- focus points: 49 "players" walking the lanes
	local focus: { FocusPoint } = {}
	for i = 1, players do
		local lane = LANES[(i - 1) % #LANES + 1]
		local u = Common.range(rng, lane.min, lane.max)
		table.insert(focus, {
			x = if lane.axis == "x" then u else lane.fixed,
			z = if lane.axis == "z" then u else lane.fixed,
			axis = lane.axis,
			dir = if rng() < 0.5 then 1 else -1,
			speed = Units.st(Common.range(rng, 1.0, 3.0)),
			min = lane.min,
			max = lane.max,
		})
	end
	scheduler:setFocus(function()
		return (focus :: any) :: { BrainScheduler.Focus }
	end)

	local world: World = {
		opts = opts,
		actors = actors,
		actorsById = actorsById,
		brains = brains,
		vehicles = vehicles,
		focus = focus,
		scheduler = scheduler,
		grid = grid,
		ctx = ctx,
		rng = rng,
		now = 0,
		frame = 0,
		trafficAccumulator = 0,
		events = events,
		counts = counts,
	}
	-- seed the threat grid and send the fender-bender gather events
	for _, actor in actors do
		if actor.species == "squirrel" then
			grid:set(actor.id, actor.x, actor.z)
		end
	end
	for _, evt in events do
		local sent = 0
		for _, actor in actors do
			if actor.species == "human" and sent < 3 then
				local brain = brains[actor.id]
				if actor.brainKind == "Pedestrian" or (actor.brainKind == "Officer" and sent == 2) then
					brain:onEvent({
						type = "gather",
						x = evt.x + Units.st(2),
						z = evt.z + Units.st(1.5),
						untilTime = evt.untilTime,
					})
					sent += 1
				end
			end
		end
	end
	return world
end

local function stepVehicles(world: World, dt: number)
	for _, v in world.vehicles do
		if v.speed > 0 then
			if v.axis == "x" then
				v.x += v.dir * v.speed * dt
				if v.x > v.max then
					v.x = v.min
				elseif v.x < v.min then
					v.x = v.max
				end
			else
				v.z += v.dir * v.speed * dt
				if v.z > v.max then
					v.z = v.min
				elseif v.z < v.min then
					v.z = v.max
				end
			end
			v.y = groundAt(v.x, v.z) + Units.st(0.04)
		end
	end
end

local function stepFocus(world: World, dt: number)
	for _, f in world.focus do
		if f.axis == "x" then
			f.x += f.dir * f.speed * dt
			if f.x > f.max or f.x < f.min then
				f.dir = -f.dir
				f.x = math.clamp(f.x, f.min, f.max)
			end
		else
			f.z += f.dir * f.speed * dt
			if f.z > f.max or f.z < f.min then
				f.dir = -f.dir
				f.z = math.clamp(f.z, f.min, f.max)
			end
		end
	end
end

-- One 60 Hz server frame: brains (budgeted, LOD), AI motors for every actor, the threat grid,
-- vehicles at 30 Hz. Returns the phase timings in ms.
function Scenario.stepFrame(world: World, dt: number): FrameMetrics
	local t0 = os.clock()
	world.frame += 1
	world.now += dt
	local ctx = world.ctx
	ctx.now = world.now
	stepFocus(world, dt)

	local frame = world.scheduler:step(dt, world.now, ctx)
	local t1 = os.clock()

	for _, actor in world.actors do
		Kinematics.step(actor, dt, ctx)
	end
	local t2 = os.clock()

	local grid = world.grid
	for _, actor in world.actors do
		if actor.species == "squirrel" then
			grid:set(actor.id, actor.x, actor.z)
		end
	end
	local t3 = os.clock()

	world.trafficAccumulator += dt
	if world.trafficAccumulator >= 1 / 30 - 1e-9 then
		stepVehicles(world, world.trafficAccumulator)
		world.trafficAccumulator = 0
	end
	local t4 = os.clock()

	return {
		brainMs = (t1 - t0) * 1000,
		motorMs = (t2 - t1) * 1000,
		gridMs = (t3 - t2) * 1000,
		trafficMs = (t4 - t3) * 1000,
		totalMs = (t4 - t0) * 1000,
		ticked = frame.ticked,
		deferred = frame.deferred,
	}
end

export type Liveness = {
	ok: boolean,
	actors: number,
	stuck: { number }, -- ids that moved less than 1 stud over the run
	nan: number,
	outside: number,
	byKind: { [string]: number },
}

-- Every actor moved, no NaN, nobody outside the clamp (SimFull liveness, BUILD_PLAN §6.5).
function Scenario.liveness(world: World): Liveness
	local stuck, nan, outside = {}, 0, 0
	for _, actor in world.actors do
		if actor.x ~= actor.x or actor.y ~= actor.y or actor.z ~= actor.z then
			nan += 1
		end
		if actor.moved < 1 then
			table.insert(stuck, actor.id)
		end
		local b = Scenario.BOUNDS
		if
			actor.intent.mode ~= "rail"
			and (
				actor.x < b.minX - 1e-6
				or actor.x > b.maxX + 1e-6
				or actor.z < b.minZ - 1e-6
				or actor.z > b.maxZ + 1e-6
			)
		then
			outside += 1
		end
	end
	return {
		ok = #stuck == 0 and nan == 0 and outside == 0,
		actors = #world.actors,
		stuck = stuck,
		nan = nan,
		outside = outside,
		byKind = table.clone(world.counts),
	}
end

return Scenario
