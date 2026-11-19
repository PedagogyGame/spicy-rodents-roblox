--!strict
-- ServerScriptService.Server.AI.TownAI
-- The town's AI population on the real data (BUILD_PLAN §1.5, §4.4 #3; the S5 Scenario's structure
-- on generated/ instead of synthetic lanes and routes): humans per data/population.json posts
-- (townspeople walk the sidewalk lanes from World/Town via Actors/Nav; shop workers keep shop
-- circuits, the first of them behind a built venue's counter (Actors/StaffRounds.venues: Pepper's Corner
-- Store's shopkeeper, on the store's floor); hospital staff walk the ward rounds and the desk post of Infection/HospitalLayout, indoors
-- on lanes the bake keeps clear; the ambulance crew walks a circuit at the ambulance bay; 6 officers
-- patrol from west_police_station, the guard and car crew hold the station's locker room),
-- the novelty riders (the mime, the five kids) as cyclists on the lanes (the two motorcyclists ride the traffic's
-- motorcycles, Traffic/Fleet ids 8 and 11, drawn by Traffic/Ghost: not here as well), squirrels running the 1,332 harvested
-- routes (Routes/Registry + Graph through AI/RouteAdapter), the AI rodent wandering and stalking
-- from a v5.4 hide, the fox roaming and 6 deer grazing at their v5.4 origins. Ground is
-- World/Ground over Town pavement (walkers never take roofs). Steppable and pure: Lune runs the
-- SimFull-style liveness test; Server/Actors/ActorsRuntime adds bodies and possession in the engine.
-- NOBODY WALKS THROUGH A WALL (the owner's playtest, 19 November): the people are kinematic, so every walk that is
-- not a lane or a round (both clear of every building) goes by the town's way on foot (World/WalkWay, `world.way`;
-- the brains ask it through ctx.way and ctx.clear): round the buildings and fences, in and out of the hospital, the
-- police station, the corner store and the bowling alley by their doors. The lanes are the sidewalk strips cut where
-- a building, a shelter or a fence stands on them; a shop worker's round is on the pavement before the shop's front;
-- a body a player lets go inside a shell is taken at the nearest spot outside it (resume: WalkWay.putBack). The way
-- covers the whole of the AI's bounds and crosses the river by the Quay's bridge (the AI's ground is its deck there);
-- a search that runs out of budget gives the way as far as it got (the brain asks again from its end); a body nobody
-- can see (ctx.seen: no player within SEEN with no building between) that has found no way twice is put on its own
-- ground (Brains/Common.stuck). The poles and tree trunks standing on a lane are stepped round (WalkWay.dodges).
-- tests/unit/town_walls.spec (tests/lib/WallAudit) walks the whole town on the baked one with a budget of 0.
-- Brains report what the services care about through ctx.emit (a person spotting a squirrel):
-- the events queue up in world.events (the newest MAX_EVENTS) until drainEvents takes them, and each
-- one is also handed at once to every listener (listen), so a service that needs to hear them does not
-- race the one that drains the queue.
-- COVER (the storm drains, BRIEF_ADDENDUM D8; Server/World/SewerService adds one with addCover, and any
-- later refuge, such as the hollow trees, adds its own): a squirrel-species actor a cover hides (`under(x,
-- y, z)` names a space; the first cover added that names one wins) is taken out of the threat grid, so
-- every brain that looks for squirrels through it (people spotting, the fox hunting, the deer startling)
-- loses it, unseen and unheard, as in v5.4. A change is an event, "covered" (with `space`) or
-- "uncovered". A body let go while hidden is put back where that cover says (`surface`: the drain's
-- mouth) before the AI takes it. Removing one cover leaves the others; with none nothing changes.
-- Interface: build(opts) -> World; stepFrame(world, dt) -> FrameMetrics; liveness(world) -> Liveness;
--   counts(world) -> { [species]: n }; actorsOf(world, predicate) -> { Actor }; setFocus(world, fn);
--   drainEvents(world) -> { Event }; suspend(world, id); resume(world, id, x, y, z, yaw?);
--   listen(world, fn) -> unlisten; addCover(world, cover) -> remove; covered(world, id) -> space?
-- Pure; studs. Nothing runs until stepFrame is called (rule 4).

local Import = require("../Import")
local Units = Import.shared("Config/Units") :: typeof(require("../../shared/Config/Units"))
local Species = Import.shared("Actors/Species") :: typeof(require("../../shared/Actors/Species"))
local Population = Import.shared("Actors/Population") :: typeof(require("../../shared/Actors/Population"))
local Height = Import.shared("World/Height") :: typeof(require("../../shared/World/Height"))
local Ground = Import.shared("World/Ground") :: typeof(require("../../shared/World/Ground"))
local Town = Import.shared("World/Town") :: typeof(require("../../shared/World/Town"))
local RailWorld = Import.shared("Movement/RailWorld") :: typeof(require("../../shared/Movement/RailWorld"))
local HumanAIMotor = Import.shared("Movement/HumanAIMotor") :: typeof(require("../../shared/Movement/HumanAIMotor"))
local HospitalLayout =
	Import.shared("Infection/HospitalLayout") :: typeof(require("../../shared/Infection/HospitalLayout"))
local StaffRounds = Import.shared("Actors/StaffRounds") :: typeof(require("../../shared/Actors/StaffRounds"))
local AlleyStaff = Import.shared("Attractions/AlleyStaff") :: typeof(require("../../shared/Attractions/AlleyStaff"))
local Tunables = Import.shared("Config/Tunables") :: typeof(require("../../shared/Config/Tunables"))
local WalkWay = Import.shared("World/WalkWay") :: typeof(require("../../shared/World/WalkWay"))
local Colliders = Import.shared("World/Colliders") :: typeof(require("../../shared/World/Colliders"))
local Common = require("../Actors/Brains/Common")
local BrainScheduler = require("../Actors/BrainScheduler")
local Perception = require("../Actors/Perception")
local Nav = require("../Actors/Nav")
local Pedestrian = require("../Actors/Brains/Pedestrian")
local Staff = require("../Actors/Brains/Staff")
local Officer = require("../Actors/Brains/Officer")
local SquirrelBrain = require("../Actors/Brains/Squirrel")
local Rodent = require("../Actors/Brains/Rodent")
local Fox = require("../Actors/Brains/Fox")
local Deer = require("../Actors/Brains/Deer")
local RouteAdapter = require("./RouteAdapter")

export type Opts = {
	data: any, -- Shared/Data
	phase: string?, -- "frb" (default) | "w3c"
	seed: number?,
	humans: number?, -- override the standing human count (scales the street posts)
	squirrels: number?,
	deer: number?,
	fox: number?,
	riders: number?,
	budgetMs: number?,
	rail: any?, -- a prebuilt RailWorld (tests share one)
}

export type FrameMetrics = { brainMs: number, motorMs: number, gridMs: number, totalMs: number, ticked: number }

export type Event = { kind: string, id: number, other: number?, t: number, space: string? }

-- What hides a squirrel (the storm drains). under: the space whose volume holds the point (world studs, the
-- actor's own y), nil in the open. surface: where a body let go at that point is put (ground-level y, and the
-- yaw to face), nil to leave it where it is.
export type Cover = {
	-- the space hiding a body at (x, y, z); `actor` is the squirrel judged (nil for a body being let go)
	under: (x: number, y: number, z: number, actor: Common.Actor?) -> string?,
	surface: ((x: number, y: number, z: number) -> (number?, number?, number?, number?))?,
}

export type World = {
	opts: Opts,
	config: any, -- Actors/Population.Config
	actors: { Common.Actor },
	actorsById: { [number]: Common.Actor },
	brains: { [number]: Common.Brain },
	scheduler: BrainScheduler.Scheduler,
	grid: Perception.Grid,
	ctx: Common.Ctx,
	nav: Nav.Nav,
	town: any, -- World/Town.Town
	rail: any,
	routes: RouteAdapter.Adapter,
	now: number,
	frame: number,
	counts: { [string]: number },
	possessed: { [number]: boolean }, -- actor ids driven by players (their brains are suspended)
	nextId: number,
	events: { Event }, -- what the brains reported since the last drainEvents
	listeners: { (ev: Event) -> () }, -- told of every event as it is emitted
	covers: { Cover }, -- what hides squirrels (addCover), in the order added
	covered: { [number]: string? }, -- squirrel-species actor id -> the space hiding it (refreshed every frame)
	way: any, -- World/WalkWay.Way: the town's way on foot (every walk that is not a lane or a round goes by it)
}

local TownAI = {}

TownAI.MAX_EVENTS = 256 -- nobody draining (a test, a place without the services) never grows the list
TownAI.WAY_NODES = 1000 -- cells a brain's way search may open (World/FootPath): a brain thinks inside a frame
-- studs: a player further off than this does not see a body (ctx.seen: a body nobody sees that has no way is put on
-- its own ground, Brains/Common.stuck), nor one with a building between at EYE over its ground
TownAI.SEEN = 250
TownAI.EYE = 5

local st = Units.st
-- v5.4 landmarks (HTML units), as in the S5 scenario: AI squirrel hides, deer and fox origins
-- [wildlife_foraging §2.1, §11.8, §11.9].
local HIDES = { { -74, -71 }, { 84, 70 }, { -196, 97 }, { 217, -111 }, { -105, 321 }, { 103, 409 }, { 414, 332 } }
local DEER_ORIGINS = { { 117, 365 }, { 145, 385 }, { 187, 320 }, { -204, 353 }, { 137, 366 }, { 160, 340 } }
local FOX_ORIGIN = { 65, 313 }

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

local function lotPos(data: any, id: string, fallbackU: { number }): (number, number)
	local lot = data:lot(id)
	if lot then
		return lot.x, lot.z
	end
	return st(fallbackU[1]), st(fallbackU[2])
end

local FACING = { ["+Z"] = { 0, 1 }, ["-Z"] = { 0, -1 }, ["+X"] = { 1, 0 }, ["-X"] = { -1, 0 } }
TownAI.FRONT = 4 -- studs in front of a building's front wall where its outdoor staff's round starts

-- the spot `out` studs in front of a lot's front wall (its `facing`; +Z when it names none)
local function frontOf(lot: any, out: number): (number, number)
	local f = FACING[lot.facing or "+Z"] or FACING["+Z"]
	local fp = lot.footprint or { w = 0, d = 0 }
	local half = if f[1] ~= 0 then fp.w / 2 else fp.d / 2
	return lot.x + f[1] * (half + out), lot.z + f[2] * (half + out)
end

-- shop lots for the shop rota: buildings whose type names a shop, store, cafe or restaurant. A shop is a solid
-- box (nobody walks in): its worker's round is in front of it, on the pavement before its front wall.
local function shopSites(data: any, way: any): { { number } }
	local out = {}
	for _, lot in data:lots() do
		local t = lot.type
		if
			string.find(t, "shop", 1, true)
			or string.find(t, "store", 1, true)
			or string.find(t, "cafe", 1, true)
			or string.find(t, "restaurant", 1, true)
			or string.find(t, "bakery", 1, true)
		then
			local x, z = frontOf(lot, TownAI.FRONT)
			local f = FACING[lot.facing or "+Z"] or FACING["+Z"]
			local fx, fz = f[1], f[2]
			-- a shop inside a bigger building (the galleria's): in front of that building's nearest wall
			local px, pz, nx, nz = WalkWay.putBack(way, x, z)
			if nx ~= 0 or nz ~= 0 then
				x, z, fx, fz = px, pz, nx, nz
			end
			table.insert(out, { x, z, lot.x * lot.x + lot.z * lot.z, fx, fz })
		end
	end
	table.sort(out, function(a, b)
		return a[3] < b[3]
	end)
	return out
end

-- emit: queue an event (the newest MAX_EVENTS are kept) and tell every listener now.
function TownAI.emit(world: World, ev: Event)
	local events = world.events
	if #events >= TownAI.MAX_EVENTS then
		table.remove(events, 1)
	end
	table.insert(events, ev)
	for _, fn in table.clone(world.listeners) do
		fn(ev)
	end
end

-- the threat grid for one squirrel-species actor: out of it while the cover hides it, and an event when that
-- changes
local function placeThreat(world: World, actor: Common.Actor)
	local space = nil
	for _, cover in world.covers do
		space = cover.under(actor.x, actor.y, actor.z, actor)
		if space then
			break
		end
	end
	local was = world.covered[actor.id]
	if space ~= was then
		world.covered[actor.id] = space
		if space then
			TownAI.emit(world, { kind = "covered", id = actor.id, t = world.now, space = space })
		else
			TownAI.emit(world, { kind = "uncovered", id = actor.id, t = world.now, space = was })
		end
	end
	if space then
		world.grid:remove(actor.id)
	else
		world.grid:set(actor.id, actor.x, actor.z)
	end
end

function TownAI.build(opts: Opts): World
	local data = opts.data
	local rng = mulberry32(opts.seed or 1)
	local config = Population.fromData(data:population(), opts.phase)
	local town = Town.fromData(data)
	local nav = Nav.build(town, data:module("Interiors") :: any)
	local okLayout, layout = pcall(HospitalLayout.fromData, data, Tunables.get("hospital.beds"))
	local clampU = Height.worldClamp()
	local bounds = { minX = st(clampU.minX), maxX = st(clampU.maxX), minZ = st(clampU.minZ), maxZ = st(clampU.maxZ) }
	-- (the way on foot over the same bounds: a body a player leaves anywhere in them has a way back)
	local way = WalkWay.new({ data = data, hospital = if okLayout then layout else nil, bounds = bounds })
	local ground = Ground.world({ town = town })
	local rail = opts.rail or RailWorld.get(data, Height.at)
	local routes = RouteAdapter.new(rail)

	local params = table.clone(BrainScheduler.DEFAULTS)
	params.budgetMs = opts.budgetMs or params.budgetMs
	local scheduler = BrainScheduler.new(params)
	local grid = Perception.newGrid(st(16))
	local actors: { Common.Actor } = {}
	local actorsById: { [number]: Common.Actor } = {}
	local brains: { [number]: Common.Brain } = {}
	-- the built expansion venues' floors (indoors, above the ground) and their counters' staff posts
	local venues = StaffRounds.venues(data:module("Expansion"))
	-- the bowling alley (generated/Attractions): its floor inside its walls, and its employees (AlleyStaff)
	local alley = AlleyStaff.placeOf(data)
	local ctx: Common.Ctx = {
		now = 0,
		rng = rng,
		groundAt = function(x: number, z: number): number
			local inside = if alley then AlleyStaff.floorAt(alley, x, z) else nil
			if inside then
				return inside
			end
			local y = ground.groundAt(x, z, Height.at(x, z) + 1)
			-- the river bridge's ramps and deck (World/WalkWay walks people over it): its height, wherever it stands
			local deck = Height.riverDeckAt(x, z)
			if deck and deck > y then
				y = deck
			end
			local floor = StaffRounds.floorAt(venues, x, z)
			return if floor and floor > y then floor else y
		end,
		threats = grid,
		actorsById = actorsById,
		bounds = bounds,
		routes = routes,
		queryBuffer = table.create(32),
		way = function(x0: number, z0: number, x1: number, z1: number): ({ { number } }?, boolean?)
			-- (out of budget, the way as far as it got: the brain walks it and asks again from there)
			local points, _, partial =
				WalkWay.find(way, x0, z0, x1, z1, { maxNodes = TownAI.WAY_NODES, partial = true })
			return points, partial
		end,
		clear = function(x0: number, z0: number, x1: number, z1: number): boolean
			return WalkWay.clear(way, x0, z0, x1, z1)
		end,
	}
	local world: World = {
		opts = opts,
		config = config,
		actors = actors,
		actorsById = actorsById,
		brains = brains,
		scheduler = scheduler,
		grid = grid,
		ctx = ctx,
		nav = nav,
		town = town,
		rail = rail,
		routes = routes,
		now = 0,
		frame = 0,
		counts = {},
		possessed = {},
		nextId = 0,
		events = {},
		listeners = {},
		covers = {},
		covered = {},
		way = way,
	}
	-- can a player see (x, z)? One within SEEN, with no building or fence between at eye height
	ctx.seen = function(x: number, z: number): boolean
		local eye = ctx.groundAt(x, z) + TownAI.EYE
		for _, f in (scheduler :: any).focus :: { BrainScheduler.Focus } do
			if
				(f.x - x) ^ 2 + (f.z - z) ^ 2 < TownAI.SEEN * TownAI.SEEN
				and not Colliders.blocked(way.colliders, f.x, f.z, x, z, 1, eye)
			then
				return true
			end
		end
		return false
	end
	ctx.emit = function(kind: string, actor: Common.Actor, other: Common.Actor?)
		TownAI.emit(world, { kind = kind, id = actor.id, other = if other then other.id else nil, t = world.now })
	end
	local counts = world.counts

	local function add(
		species: string,
		variant: string,
		brainKind: string,
		hip: number,
		x: number,
		z: number
	): Common.Actor
		world.nextId += 1
		local id = world.nextId
		local actor = Common.newActor(id, species, variant, brainKind, x, z, hip)
		actor.y = ctx.groundAt(x, z) + hip
		table.insert(actors, actor)
		actorsById[id] = actor
		counts[species] = (counts[species] or 0) + 1
		return actor
	end
	local function register(actor: Common.Actor, brain: Common.Brain)
		-- (a brain may seat the body somewhere else: its first step is not a jump up or down to there)
		actor.y = ctx.groundAt(actor.x, actor.z) + actor.hip
		brains[actor.id] = brain
		scheduler:register(actor.id, brain, actor, 0)
	end

	-- the sidewalk lanes, in the pieces that miss every building, shelter and fence standing on them
	local lanes = {}
	for _, lane in Nav.lanes(nav) do
		for _, piece in WalkWay.splitLane(way, lane) do
			table.insert(lanes, piece)
		end
	end
	-- the poles and tree trunks standing on them: stepped round (Brains/Pedestrian), never a cut in the lane
	local posts = WalkWay.posts(data)
	for _, lane in lanes do
		lane.dodges = WalkWay.dodges(posts, lane)
	end
	table.sort(lanes, function(a, b) -- (as Nav.lanes: the core lanes, nearest the middle and longest, first)
		local ca, cb = math.abs(a.fixed), math.abs(b.fixed)
		if ca ~= cb then
			return ca < cb
		end
		return a.max - a.min > b.max - b.min
	end)
	local pedParams: Pedestrian.Params = {
		lanes = lanes,
		coreLanes = math.min(4, #lanes),
		speedMin = st(0.8),
		speedMax = st(1.6),
		rng = rng,
	}
	local riderParams: Pedestrian.Params = {
		lanes = lanes,
		coreLanes = math.min(4, #lanes),
		speedMin = st(3.2),
		speedMax = st(5.2),
		rng = rng,
		cyclist = true,
	}
	local function laneSpot(i: number): (number, number)
		local lane = lanes[(i - 1) % #lanes + 1]
		local u = lane.min + (lane.max - lane.min) * rng()
		if lane.axis == "x" then
			return u, lane.fixed
		end
		return lane.fixed, u
	end

	local hipH = Species.def("human").hipHeight
	local hx, hz = lotPos(data, "hospital_main", { -356, 353 })
	local bx, bz = lotPos(data, "hosp_ambulance_bay", { -340, 330 })
	local px, pz = lotPos(data, "west_police_station", { -510, -107 })
	-- the hospital's posts: the round behind the reception desk and the rounds of the wards
	local deskRound: any = nil
	local wardRounds: { any } = {}
	if okLayout and layout then
		for _, round in layout.posts do
			if round.room == "reception" then
				deskRound = round
			else
				table.insert(wardRounds, round)
			end
		end
	end
	local shops = shopSites(data, way)
	local counters: { { x: number, z: number, round: { { number } } } } = {}
	for _, v in venues do
		if v.post then
			table.insert(counters, v.post)
		end
	end
	local scale = 1
	if opts.humans then
		local standing = 0
		for _, p in config.posts do
			standing += p.standing
		end
		scale = opts.humans / math.max(1, standing)
	end
	local idx = 0
	for _, post in config.posts do
		local n = if (post :: any).protected then post.standing else math.floor(post.standing * scale + 0.5)
		for k = 1, n do
			idx += 1
			local id = post.id
			local actor: Common.Actor
			if id == "hospital_staff" and #wardRounds > 0 then
				-- indoors, on the lanes the bake keeps clear (Infection/HospitalLayout): the first works
				-- behind the reception desk, the rest walk the rounds at the foot of the ward beds
				local round = if k == 1 and deskRound then deskRound else wardRounds[(k - 2) % #wardRounds + 1]
				local first = round.points[1]
				local circuit = {}
				for _, p in round.points do
					table.insert(circuit, { p[1] - first[1], p[2] - first[2] })
				end
				actor = add("human", id, "Staff", hipH, first[1], first[2])
				register(
					actor,
					Staff.new(actor, { stationX = first[1], stationZ = first[2], index = k, circuit = circuit })
				)
			elseif id == "hospital_staff" or id == "ambulance_crew" then
				local cx, cz = if id == "ambulance_crew" then bx else hx, if id == "ambulance_crew" then bz else hz
				actor = add("human", id, "Staff", hipH, cx + ((k % 4) - 1.5) * 6, cz + ((k % 3) - 1) * 6)
				register(actor, Staff.new(actor, { stationX = cx, stationZ = cz, index = k }))
			elseif id == "police" then
				local officers = (post :: any).officerFloor or 6
				if k <= officers then
					-- the beat is about the station's front (the building itself is walked into by its door)
					local sx, sz = px, pz
					local station = data:lot("west_police_station")
					if station then
						sx, sz = frontOf(station, TownAI.FRONT)
					end
					actor = add("human", id, "Officer", hipH, sx + k * 3, sz)
					register(
						actor,
						Officer.new(actor, {
							stationX = sx,
							stationZ = sz,
							index = k,
							settle = function(x: number, z: number): (number, number)
								local cx, cz = WalkWay.putBack(way, x, z)
								return cx, cz
							end,
						})
					)
				else
					-- the guard and the car crew: in the locker room (Actors/StaffRounds.POLICE: the bake
					-- keeps their round clear)
					local sx, sz = px + StaffRounds.POLICE.x, pz + StaffRounds.POLICE.z
					actor = add("human", id, "Staff", hipH, sx, sz)
					register(actor, Staff.new(actor, { stationX = sx, stationZ = sz, index = k }))
				end
			elseif id == "shop_worker" and k <= #counters then
				-- the first shop workers keep the built venues' counters (Pepper's Corner Store's shopkeeper)
				local desk = counters[k]
				actor = add("human", id, "Staff", hipH, desk.x, desk.z)
				register(
					actor,
					Staff.new(actor, { stationX = desk.x, stationZ = desk.z, index = k, circuit = desk.round })
				)
			elseif id == "attraction_staff" and alley and k <= #AlleyStaff.EMPLOYEES then
				-- the first attraction staff are the bowling alley's employees, each on their own work loop
				local job = AlleyStaff.EMPLOYEES[k]
				local stops = AlleyStaff.shift(alley, job)
				actor = add("human", id, "Staff", hipH, stops[1].x, stops[1].z)
				actor.job = job.id
				register(
					actor,
					Staff.new(actor, {
						stationX = stops[1].x,
						stationZ = stops[1].z,
						index = k,
						stops = stops,
						-- (in the alley by its own ways; from anywhere else by the town's, in by its main doors)
						way = function(x0: number, z0: number, x1: number, z1: number): { { number } }
							return WalkWay.find(way, x0, z0, x1, z1, { maxNodes = TownAI.WAY_NODES }) or {}
						end,
					})
				)
			elseif id == "shop_worker" or id == "attraction_staff" then
				local shop = if #shops > 0 then shops[(k - 1) % #shops + 1] else { 0, 0, 0, 0, 1 }
				-- the v5.4 circuit turned to face out from the shop's front (its back leg away from the wall)
				local fx, fz = shop[4], shop[5]
				local circuit = {}
				for _, p in StaffRounds.points(0, 0, k) do
					table.insert(circuit, { -fz * p[1] - fx * p[2], fx * p[1] - fz * p[2] })
				end
				actor = add("human", id, "Staff", hipH, shop[1], shop[2])
				register(
					actor,
					Staff.new(actor, { stationX = shop[1], stationZ = shop[2], index = k, circuit = circuit })
				)
			else
				local x, z = laneSpot(idx)
				actor = add("human", id, "Pedestrian", hipH, x, z)
				register(actor, Pedestrian.new(actor, pedParams))
			end
			actor.post = id
		end
	end
	local nh = data:population().nonHumanoid or {}
	-- population.json's two motorcyclists are Morgan and Alex on the traffic's motorcycles (BUILD_PLAN D-2: road users
	-- in the fatal fleet), so only the novelty riders take the lanes: one of each person in town at once
	local riders = opts.riders or nh.noveltyRiders or 6
	for i = 1, riders do
		local x, z = laneSpot(i * 7)
		local actor = add("human", "rider", "Pedestrian", hipH, x, z)
		actor.post = "rider"
		actor.ride = i -- RidePuppet.RIDERS: the mime, then the five kids
		register(actor, Pedestrian.new(actor, riderParams))
	end

	local sqDef = Species.def("squirrel")
	local candidates = {}
	for _, r in routes.routes do
		if r.kind ~= "trampoline" and r.length > 20 then
			table.insert(candidates, r)
		end
	end
	local nSq = opts.squirrels or config.squirrelFloat.max
	for i = 1, nSq do
		local r = candidates[(i * 97) % #candidates + 1]
		local p = r.points[1]
		local actor = add("squirrel", "normal", "Squirrel", sqDef.hipHeight, p[1], p[3])
		register(actor, SquirrelBrain.new(actor, { routes = routes :: any, rng = rng, startRoute = r.id }))
	end
	do
		local hide = HIDES[1]
		local actor = add("squirrel", "spicy", "Rodent", sqDef.hipHeight, st(hide[1]), st(hide[2]))
		register(actor, Rodent.new(actor, { hideX = st(hide[1]), hideZ = st(hide[2]), index = 0 }))
	end
	local deerDef = Species.def("deer")
	for i = 1, opts.deer or config.deerBodies do
		local o = DEER_ORIGINS[(i - 1) % #DEER_ORIGINS + 1]
		local fawn = i == 5
		local actor = add(
			"deer",
			if fawn then "fawn" elseif i % 3 == 0 then "buck" else "doe",
			"Deer",
			deerDef.hipHeight * (if fawn then Species.FAWN_SCALE else 1),
			st(o[1]),
			st(o[2])
		)
		register(actor, Deer.new(actor, { originX = st(o[1]), originZ = st(o[2]), fawn = fawn, phase = rng() * 9 }))
	end
	for _ = 1, opts.fox or 1 do
		local actor = add("fox", "fox", "Fox", Species.def("fox").hipHeight, st(FOX_ORIGIN[1]), st(FOX_ORIGIN[2]))
		register(actor, Fox.new(actor, { originX = st(FOX_ORIGIN[1]), originZ = st(FOX_ORIGIN[2]) }))
	end
	for _, actor in actors do
		if actor.species == "squirrel" then
			placeThreat(world, actor)
		end
	end
	scheduler:setFocus(function()
		return {}
	end)
	return world
end

function TownAI.setFocus(world: World, fn: () -> { BrainScheduler.Focus })
	world.scheduler:setFocus(fn)
end

-- listen: fn(ev) is called with every event as it is emitted (inside stepFrame, after the brains that
-- emit it have thought). Returns the call that stops it.
function TownAI.listen(world: World, fn: (ev: Event) -> ()): () -> ()
	table.insert(world.listeners, fn)
	return function()
		local i = table.find(world.listeners, fn)
		if i then
			table.remove(world.listeners, i)
		end
	end
end

-- setCover: what hides a squirrel from now on (nil: nothing does; every hidden actor is in the open again).
-- addCover: something that hides squirrels from now on (a refuge: the storm drains, a hollow tree). Returns the
-- call that takes it away again; the others stay, and the bodies only it hid are in the open from the next frame.
function TownAI.addCover(world: World, cover: Cover): () -> ()
	table.insert(world.covers, cover)
	return function()
		local i = table.find(world.covers, cover)
		if i then
			table.remove(world.covers, i)
		end
		-- the next frame names what the others still hide ("uncovered" for the rest)
	end
end

-- covered: the space hiding actor `id` as of the last frame, nil when it is in the open.
function TownAI.covered(world: World, id: number): string?
	return world.covered[id]
end

-- One 60 Hz server frame: brains (budgeted, LOD), AI motors for every AI-driven actor, threat grid.
function TownAI.stepFrame(world: World, dt: number): FrameMetrics
	local t0 = os.clock()
	world.frame += 1
	world.now += dt
	local ctx = world.ctx
	ctx.now = world.now
	local frame = world.scheduler:step(dt, world.now, ctx)
	local t1 = os.clock()
	local possessed = world.possessed
	for _, actor in world.actors do
		if not possessed[actor.id] then
			HumanAIMotor.step(actor :: any, dt, ctx :: any)
		end
	end
	local t2 = os.clock()
	for _, actor in world.actors do
		if actor.species == "squirrel" then
			placeThreat(world, actor)
		end
	end
	local t3 = os.clock()
	return {
		brainMs = (t1 - t0) * 1000,
		motorMs = (t2 - t1) * 1000,
		gridMs = (t3 - t2) * 1000,
		totalMs = (t3 - t0) * 1000,
		ticked = frame.ticked,
	}
end

-- Possession hooks: the body leaves the AI (brain suspended, motor skipped) and comes back.
function TownAI.suspend(world: World, id: number): { [string]: any }
	world.possessed[id] = true
	world.scheduler:unregister(id)
	local brain = world.brains[id]
	local snap = brain:suspend()
	local motion = HumanAIMotor.serialize(world.actorsById[id] :: any)
	motion.brain = snap
	return motion
end

function TownAI.resume(world: World, id: number, x: number, y: number, z: number, yaw: number?)
	local actor = world.actorsById[id]
	world.possessed[id] = nil
	-- let go inside a building nobody walks in (a house shell, a shop: a player found a way in), the computer takes
	-- the body at the nearest spot outside its walls, where its way on foot starts; inside one with ways (the
	-- hospital, the police station, the corner store) but away from them, at the nearest point on them
	-- (World/WalkWay.putBack)
	if actor.species == "human" then
		local px, pz = WalkWay.putBack(world.way, x, z)
		if px ~= x or pz ~= z then
			x, z = px, pz
			y = world.ctx.groundAt(x, z) + actor.hip
		end
	end
	-- let go where the cover hides it (down a drain): the AI takes it at the way out
	for _, cover in world.covers do
		if cover.under(x, y, z) then
			if cover.surface then
				local sx, sy, sz, syaw = cover.surface(x, y, z)
				if sx and sy and sz then
					x, y, z = sx, sy + actor.hip, sz
					yaw = syaw or yaw
				end
			end
			break
		end
	end
	actor.x, actor.y, actor.z = x, y, z
	if yaw then
		actor.yaw = yaw
	end
	actor.speed = 0
	local brain = world.brains[id]
	local snap = brain:suspend()
	-- re-enter from where the player left the body; rail brains keep their route and re-seat on it
	snap.x, snap.y, snap.z = x, y - actor.hip, z
	brain:resume(snap)
	world.scheduler:register(id, brain, actor, world.now)
end

-- drainEvents: what the brains reported since the last call (oldest first); the queue is emptied.
function TownAI.drainEvents(world: World): { Event }
	local events = world.events
	world.events = {}
	return events
end

function TownAI.counts(world: World): { [string]: number }
	return table.clone(world.counts)
end

function TownAI.actorsOf(world: World, pred: (a: Common.Actor) -> boolean): { Common.Actor }
	local out = {}
	for _, a in world.actors do
		if pred(a) then
			table.insert(out, a)
		end
	end
	return out
end

export type Liveness = {
	ok: boolean,
	actors: number,
	stuck: { number },
	nan: number,
	outside: number,
	bySpecies: { [string]: number },
}

function TownAI.liveness(world: World): Liveness
	local stuck, nan, outside = {}, 0, 0
	local b = world.ctx.bounds
	for _, actor in world.actors do
		if actor.x ~= actor.x or actor.y ~= actor.y or actor.z ~= actor.z then
			nan += 1
		end
		if actor.moved < 1 and not world.possessed[actor.id] then
			table.insert(stuck, actor.id)
		end
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
		bySpecies = table.clone(world.counts),
	}
end

return TownAI
