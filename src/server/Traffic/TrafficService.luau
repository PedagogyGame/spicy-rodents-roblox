--!strict
-- ServerScriptService.Server.Traffic.TrafficService
-- The AI fleet on its lanes: fixed-tick simulation, the fatal test, the pose stream (BUILD_PLAN §4.4
-- W1 #9, D9, §1.6 VehiclePoses; traffic.md §5, §8, §13).
-- Interface: new(opts) -> TrafficService; :step(dt, world) -> { Hit }; :poses() -> { VehiclePose };
--            :poseRecords() -> stream records; :frame(dt, now, world, net?) -> { Hit } (one server frame:
--            step, then the pose stream's send through Traffic/PoseStream);
--            :dispatchResponder(dest, opts?); :releaseResponder(v); :responderIdle() -> n;
--            :responderHome() -> {x, z}; :dispatchIncident(scene); :markTeleported(actorId) (HANDOFF
--            rule 12); :stats(); :kinds(); RunOver (Util/Signal); :start(ctx) (engine only: a Heartbeat
--            loop over `frame`; never called on require).
--
-- Pure and steppable: `step(dt, world)` runs whole 1/tickHz ticks (Tunables traffic.tickHz, default 30)
-- and carries the remainder. Each tick: (1) every vehicle's AICarMotor steps against the people and the
-- previous tick's fleet bodies; (2) every squirrel actor's move this tick is swept against every visible,
-- moving vehicle's move with the exact Shared/Traffic/Swept maths (Server/Traffic/SweptCollision); hits
-- fire RunOver(actorId, vehicle). Lanes are the compiled records with handedness unified (drive on the
-- right), stop lines from Traffic/Control at the existing sign sites, the fleet from Traffic/Fleet.
-- Vehicles are server state only; clients render ghosts from `poseRecords()` (Traffic/Ghost).
-- A vehicle's `teleported` flag lasts one tick (1/30 s) and the stream sends every other tick, so the
-- service remembers every jump until the next `poseRecords()` carries it: a wrap, an appearance or a
-- responder turning round at a scene is never drawn as a slide across the road.

local Import = require("../Import")
local AICarMotor = Import.shared("Traffic/AICarMotor") :: typeof(require("../../shared/Traffic/AICarMotor"))
local Control = Import.shared("Traffic/Control") :: typeof(require("../../shared/Traffic/Control"))
local Fleet = Import.shared("Traffic/Fleet") :: typeof(require("../../shared/Traffic/Fleet"))
local Ghost = Import.shared("Traffic/Ghost") :: typeof(require("../../shared/Traffic/Ghost"))
local LaneMath = Import.shared("Traffic/LaneMath") :: typeof(require("../../shared/Traffic/LaneMath"))
local MedicalRoute = Import.shared("Infection/MedicalRoute") :: typeof(require("../../shared/Infection/MedicalRoute"))
local PoseStream = Import.shared("Traffic/PoseStream") :: typeof(require("../../shared/Traffic/PoseStream"))
local Signal = Import.shared("Util/Signal") :: typeof(require("../../shared/Util/Signal"))
local Units = Import.shared("Config/Units") :: typeof(require("../../shared/Config/Units"))
local SweptCollision = require("./SweptCollision")

-- Exported types do not cross Import (W1 Track A note): the shared types are restated loosely here.
type Person =
	{ x: number, y: number, z: number, kind: string, visible: boolean?, hospital: boolean?, injured: boolean? }
type Vehicle = any
type Lane = any
type Entry = any
type ControlData = any
type StopLine = any
type Ctx = any
type Signal = any

local st = Units.st

export type Squirrel = { id: any, x: number, y: number, z: number, teleported: boolean? }
-- A player's vehicle (Server/Actors/DeviceService: parked or driven), studs and HTML yaw. The fleet brakes
-- and queues for it like for a fleet vehicle (traffic.md §12, addendum A1: "AI cars must treat player cars
-- as fleet members in trafficVehicleAhead"); clients draw fleet ghosts without collision, so without this
-- the AI drove straight through a player's car.
export type PlayerCar = { id: any, x: number, z: number, yaw: number, width: number, length: number, speed: number? }
export type World = { people: { Person }?, squirrels: { Squirrel }?, cars: { PlayerCar }? }

export type Stats = {
	ticks: number,
	ms: number, -- total simulation ms (os.clock)
	maxTickMs: number,
	hits: number,
	stuck: { [number]: number }, -- longest continuous seconds a vehicle that should move did not
	events: { [string]: number },
	violations: { [string]: number },
}

local TrafficService = {}
TrafficService.__index = TrafficService

export type Opts = {
	lanes: { any }, -- generated/Lanes records
	roads: { any }, -- generated/Roads records
	heightAt: ((x: number, z: number) -> number)?,
	seed: number?,
	tickHz: number?,
	entries: { Entry }?,
	control: ControlData?,
	sceneSecs: number?,
	posesHz: number?, -- pose sends a second (Traffic/PoseStream.HZ)
}

export type TrafficService = typeof(setmetatable(
	{} :: {
		lanes: { [string]: Lane },
		records: { [string]: any },
		vehicles: { Vehicle },
		byId: { [number]: Vehicle },
		entries: { Entry },
		sender: any, -- Traffic/PoseStream.Sender (exported types do not cross Import)
		prev: { [number]: { x: number, y: number, z: number, yaw: number, visible: boolean } },
		prevActors: { [any]: { x: number, y: number, z: number } },
		swept: SweptCollision.SweptCollision,
		jumped: { [number]: boolean }, -- vehicles that teleported since the last poseRecords()
		graph: any, -- the road centrelines and their joins (Infection/MedicalRoute.build over opts.roads)
		-- where each emergency vehicle stands parked: the point of the road's centreline abeam its bay,
		-- the heading of the road there, and how far to the right of the centreline the bay is
		bays: { [number]: { cx: number, cz: number, fx: number, fz: number, kerb: number } },
		home: { number }?, -- where the responders' trips are routed from (the junction beside their bays)
		stops: { [string]: { StopLine } },
		control: ControlData,
		heightAt: (x: number, z: number) -> number,
		tick: number,
		acc: number,
		now: number,
		rngState: number,
		sceneSecs: number,
		_stuckRun: { [number]: number },
		_stats: Stats,
		RunOver: Signal,
		unified: { string },
		-- an observer called at the end of every simulation tick (the headless replay records the true
		-- state from it); nil in the game
		onTick: ((self: any) -> ())?,
	},
	TrafficService
))

-- mulberry32 (v5.4's generator; Util/Rng has the bit-exact one, this keeps the service self-contained)
local function nextRand(self: TrafficService): number
	self.rngState = (self.rngState + 0x6D2B79F5) % 4294967296
	local t = self.rngState
	t = bit32.bxor(t, bit32.rshift(t, 15))
	t = (t * bit32.bor(t, 1)) % 4294967296
	t = bit32.bxor(t, (t + ((bit32.bxor(t, bit32.rshift(t, 7)) * bit32.bor(t, 61)) % 4294967296)) % 4294967296)
	return bit32.bxor(t, bit32.rshift(t, 14)) / 4294967296
end

-- An incident car's pad at the station {x, z} in studs (the record gives it in v5.4 units).
local function incidentStart(self: TrafficService, v: Vehicle): { number }
	local starts = self.records.incident_police_route.path.resolved_start
	local p = starts[(if v.id % 2 == 0 then 0 else 1) + 1]
	return { st(p[1]), st(p[2]) }
end

-- generated/Roads records as the strips MedicalRoute reads (as World/Town.fromData makes them)
local function stripsOf(roads: { any }): { any }
	local strips = {}
	for _, r in roads do
		if (r.axis == "x" or r.axis == "z") and r.coord and r.width and r.start and r["end"] then
			table.insert(strips, {
				id = r.id,
				kind = r.kind,
				axis = r.axis,
				coord = r.coord,
				min = math.min(r.start, r["end"]),
				max = math.max(r.start, r["end"]),
				half = r.width * 0.5,
			})
		end
	end
	return strips
end

-- Where the emergency vehicles stand between calls, in view (they used to be hidden, and popped into
-- existence on the hospital drive when called and out of it on their return).
-- The ambulances park along the kerb of the hospital road: the responder trunk's second point is where
-- the hospital drive meets that road (`home`: their trips are routed from there), its third gives the
-- road's direction; the three responders' bays are behind the junction on the right-hand kerb, BAY_GAP
-- apart, and the arterial ambulance's is beyond it. The incident cars park on their pads at the station.
local BAY_FIRST = st(13.6) -- 34 st from the junction back to the first responder bay
local BAY_GAP = st(15.2) -- 38 st from bay to bay: room to pull out past the ambulance in front
local BAY_BEYOND = st(16.8) -- 42 st from the junction on to the arterial ambulance's bay
local BAY_INSET = st(1.4) -- the bay's line is 3.5 st inside the road's edge
local BAY_HOP = st(18) -- a call too close behind the bay to drive to: it pulls out this far and stands
local function parkEmergency(self: TrafficService, roads: { any })
	local trunk = self.records.responder_ambulance_trunk
	local pts = trunk and trunk.path and trunk.path.points
	if pts and #pts >= 3 then
		local hx, hz = pts[2][1], pts[2][2]
		local dx, dz = pts[3][1] - hx, pts[3][2] - hz
		local len = math.sqrt(dx * dx + dz * dz)
		local fx, fz = dx / len, dz / len
		-- half the width of the road the bays are on
		local half = st(6)
		for _, s in stripsOf(roads) do
			local along, across = if s.axis == "z" then hz else hx, if s.axis == "z" then hx else hz
			local runs = if s.axis == "z" then math.abs(fz) > 0.9 else math.abs(fx) > 0.9
			if
				s.kind == "asphalt"
				and runs
				and math.abs(across - s.coord) < 1e-6
				and along >= s.min
				and along <= s.max
			then
				half = s.half
			end
		end
		local kerb = half - BAY_INSET
		self.home = { hx, hz }
		local k = 0
		for _, v in self.vehicles do
			local along: number? = nil
			if v.class == "responder" then
				along = -(BAY_FIRST + BAY_GAP * k)
				k += 1
			elseif v.class == "legacy_ambulance" then
				along = BAY_BEYOND
			end
			if along then
				local bay = { cx = hx + fx * along, cz = hz + fz * along, fx = fx, fz = fz, kerb = kerb }
				self.bays[v.id] = bay
				v.x, v.z, v.yaw = bay.cx - fz * kerb, bay.cz + fx * kerb, math.atan2(fx, fz)
				v.y = self.heightAt(v.x, v.z) + st(0.04)
				if v.class == "legacy_ambulance" then
					-- its round: from its bay along the arterial to its far end (the record's first point)
					local far = v.lane.poly and self.records[v.lane.id] and self.records[v.lane.id].path.points[1]
					if far then
						v.tour = LaneMath.bayRoute(
							`tour_{v.id}`,
							{ { bay.cx, bay.cz }, { far[1], far[2] } },
							kerb,
							v.lane.speeds
						)
					end
				end
			end
		end
	end
	-- the incident cars: on their pads, facing the way they leave
	local rec = self.records.incident_police_route
	local starts = rec and rec.path and rec.path.resolved_start
	if starts then
		for _, v in self.vehicles do
			if v.class == "incident" then
				local p = incidentStart(self, v)
				local line = LaneMath.offsetRight({ p, { p[1] + 10, p[2] } }, LaneMath.POLY_OFFSET)
				v.x, v.z, v.yaw = line[1][1], line[1][2], math.pi / 2
				v.y = self.heightAt(v.x, v.z) + st(0.04)
			end
		end
	end
end

function TrafficService.new(opts: Opts): TrafficService
	local lanes = LaneMath.load(opts.lanes)
	local unified = LaneMath.unify(lanes, opts.roads, opts.lanes)
	LaneMath.link(lanes, opts.roads, opts.lanes) -- a way back at the end of every one-way street
	local records = {}
	for _, r in opts.lanes do
		records[r.id] = r
	end
	local control = opts.control or Control.DEFAULT
	local self = setmetatable({
		lanes = lanes,
		records = records,
		vehicles = {},
		byId = {},
		entries = opts.entries or Fleet.ENTRIES,
		sender = PoseStream.newSender(opts.posesHz),
		prev = {},
		prevActors = {},
		swept = SweptCollision.new(),
		jumped = {},
		graph = MedicalRoute.build(stripsOf(opts.roads)),
		bays = {},
		home = nil :: { number }?,
		stops = Control.resolve(control, lanes),
		control = control,
		heightAt = opts.heightAt or function(_x: number, _z: number): number
			return 0
		end,
		tick = 1 / (opts.tickHz or 30),
		acc = 0,
		now = 0,
		rngState = (opts.seed or 5401) % 4294967296,
		sceneSecs = opts.sceneSecs or 30,
		_stuckRun = {},
		_stats = { ticks = 0, ms = 0, maxTickMs = 0, hits = 0, stuck = {}, events = {}, violations = {} },
		RunOver = Signal.new(),
		unified = unified,
		onTick = nil :: ((self: any) -> ())?,
	}, TrafficService)
	for _, e in self.entries do
		local lane = lanes[e.lane] or error(`TrafficService: fleet entry {e.id} names missing lane {e.lane}`)
		local cruise = 0
		if e.speedKey then
			local range = lane.speedRanges and lane.speedRanges[e.speedKey]
			if range then
				cruise = range[1] + (range[2] - range[1]) * nextRand(self)
			else
				cruise = lane.speeds[e.speedKey] or 0
			end
		end
		if e.class == "van" then
			cruise = st(7.6)
		elseif e.class == "trolley" then
			cruise = st(10.7)
		end
		if e.class == "motorcycle" and not lane.kerb and lane.returnLane and lane.returnLane.kerb then
			-- a rider parks at the kerb between rides, and this lane's kerb is across the trolley's rails:
			-- it parks level with its spawn point on the other side of the road
			lane = lane.returnLane
		end
		local v = AICarMotor.new(e, lane, { at = e.at, cruise = cruise, wait = e.wait, offset = e.offset })
		v.y = self.heightAt(v.x, v.z) + st(0.04)
		table.insert(self.vehicles, v)
		self.byId[v.id] = v
	end
	parkEmergency(self, opts.roads)
	return self
end

local function ctxFor(self: TrafficService, world: World): Ctx
	local people: { Person } = {}
	for _, p in (world.people or {}) :: { Person } do
		table.insert(people, p)
	end
	for _, s in (world.squirrels or {}) :: { Squirrel } do
		table.insert(people, { x = s.x, y = s.y, z = s.z, kind = "squirrel", visible = true })
	end
	local bodies = table.create(#self.vehicles)
	for _, v in self.vehicles do
		table.insert(bodies, AICarMotor.body(v))
	end
	for _, c in (world.cars or {}) :: { PlayerCar } do
		table.insert(bodies, {
			x = c.x,
			z = c.z,
			yaw = c.yaw,
			width = c.width,
			length = c.length,
			visible = true,
			id = `player:{c.id}`,
			player = true,
			speed = c.speed or 0,
		})
	end
	return {
		now = self.now,
		people = people,
		bodies = bodies,
		heightAt = self.heightAt,
		rand = function(): number
			return nextRand(self)
		end,
		stops = self.stops,
		rates = self.control.violationRates,
		sceneSecs = self.sceneSecs,
	}
end

-- markTeleported(actorId): the actor's previous pose is invalid next tick (rule 12 seam).
function TrafficService.markTeleported(self: TrafficService, actorId: any)
	self.swept:markTeleported(actorId)
	self.prevActors[actorId] = nil
end

local function oneTick(self: TrafficService, world: World): { SweptCollision.Hit }
	local t0 = os.clock()
	local dt = self.tick
	self.now += dt
	for _, v in self.vehicles do
		self.prev[v.id] = { x = v.x, y = v.y, z = v.z, yaw = v.yaw, visible = v.visible }
	end
	local ctx = ctxFor(self, world)
	local stats = self._stats
	for _, v in self.vehicles do
		local wasStopped = v.phase
		local events = AICarMotor.step(v, ctx, dt)
		for _, ev in events do
			stats.events[ev] = (stats.events[ev] or 0) + 1
			if ev == "rollingStop" then
				stats.violations.rollingStop = (stats.violations.rollingStop or 0) + 1
			end
		end
		if v.teleported then
			self.jumped[v.id] = true
		end
		-- stuck: visible, in a driving phase, not dwelling or waiting at a stop line, and not moving
		local driving = v.visible
			and (v.phase == "drive" or v.phase == "ride" or v.phase == "out" or v.phase == "back")
			and v.stop.phase ~= "waiting"
			and wasStopped ~= "dwell"
		if driving and not v.moving then
			local run = (self._stuckRun[v.id] or 0) + dt
			self._stuckRun[v.id] = run
			stats.stuck[v.id] = math.max(stats.stuck[v.id] or 0, run)
		else
			self._stuckRun[v.id] = 0
		end
	end
	-- the fatal test
	local actors: { SweptCollision.ActorPose } = {}
	for _, s in (world.squirrels or {}) :: { Squirrel } do
		local p = self.prevActors[s.id]
		table.insert(actors, {
			id = s.id,
			x = s.x,
			y = s.y,
			z = s.z,
			prevX = if p then p.x else s.x,
			prevY = if p then p.y else s.y,
			prevZ = if p then p.z else s.z,
			teleported = s.teleported or p == nil,
		})
		self.prevActors[s.id] = { x = s.x, y = s.y, z = s.z }
	end
	local hits: { SweptCollision.Hit } = {}
	if #actors > 0 then
		hits = self.swept:step(actors, self:poses(), dt)
		for _, h in hits do
			stats.hits += 1
			self.RunOver:fire(h.actorId, self.byId[h.vehicleId :: number])
		end
	end
	local ms = (os.clock() - t0) * 1000
	stats.ticks += 1
	stats.ms += ms
	stats.maxTickMs = math.max(stats.maxTickMs, ms)
	if self.onTick then
		self.onTick(self)
	end
	return hits
end

-- step(dt, world) -> hits: run every whole tick in dt (plus the carried remainder).
function TrafficService.step(self: TrafficService, dt: number, world: World?): { SweptCollision.Hit }
	local w = world or {}
	self.acc += math.min(dt, 0.25)
	local all = {}
	while self.acc >= self.tick - 1e-9 do
		self.acc -= self.tick
		for _, h in oneTick(self, w) do
			table.insert(all, h)
		end
	end
	return all
end

-- poses(): the fleet as SweptCollision.VehiclePose (previous tick -> this tick).
function TrafficService.poses(self: TrafficService): { SweptCollision.VehiclePose }
	local out = table.create(#self.vehicles)
	for _, v in self.vehicles do
		local p = self.prev[v.id] or { x = v.x, y = v.y, z = v.z, yaw = v.yaw, visible = v.visible }
		table.insert(out, {
			id = v.id,
			kind = v.kind,
			x = v.x,
			y = v.y,
			z = v.z,
			yaw = v.yaw,
			prevX = p.x,
			prevY = p.y,
			prevZ = p.z,
			prevYaw = p.yaw,
			visible = v.visible,
			prevVisible = p.visible,
			teleported = v.teleported,
			label = v.name,
		})
	end
	return out
end

-- poseRecords(): the VehiclePoses stream records (Traffic/Ghost encoding; Net:stream sends them).
-- Each call is one send: a jump made since the last call is flagged in this one and then forgotten, so
-- a wrap on a tick between two sends (30 Hz ticks, 15 Hz sends) still snaps on every client instead of
-- streaking across town. A client that loses that one send sees a jump no car could drive and snaps
-- all the same (Traffic/Ghost).
function TrafficService.poseRecords(self: TrafficService): { { [string]: number } }
	local out = table.create(#self.vehicles)
	local jumped = self.jumped
	self.jumped = {}
	for _, v in self.vehicles do
		table.insert(
			out,
			Ghost.encode({
				id = v.id,
				x = v.x,
				z = v.z,
				yaw = v.yaw,
				speed = v.speed,
				visible = v.visible,
				beacons = v.class == "responder" or v.class == "incident" or v.class == "legacy_ambulance",
				teleported = v.teleported or jumped[v.id] == true,
				stopped = v.speed < 0.05,
			})
		)
	end
	return out
end

-- frame(dt, now, world, net?) -> hits: one server frame of traffic, exactly what Server/Boot/Game runs on
-- every Heartbeat and what the headless replay (tools/sim) runs: the simulation steps its whole ticks,
-- then, when `net` is given and Traffic/PoseStream's sender says a send is due, the pose records go out
-- stamped with the instant their state belongs to: the server clock `now` (the caller's clock AFTER this
-- frame) less the part of a tick not yet simulated.
function TrafficService.frame(
	self: TrafficService,
	dt: number,
	now: number,
	world: World?,
	net: any?
): { SweptCollision.Hit }
	local hits = self:step(dt, world)
	if net then
		-- the records hold the state of the last whole tick, which is `acc` (the remainder not yet
		-- simulated) older than the frame clock: stamp that instant, or a send that carries one tick
		-- fewer than its neighbours is drawn as the car dragging, then surging (tools/sim live_server)
		local records = self.sender:frame(dt, now - self.acc, self)
		if records then
			net:stream(nil, PoseStream.REMOTE, records)
		end
	end
	return hits
end

-- kinds(): id -> {kind, color} for the client ghost renderer (this service's own fleet entries).
function TrafficService.kinds(self: TrafficService): { [number]: { kind: string, color: string? } }
	local out = {}
	for _, e in self.entries do
		if self.byId[e.id] then
			out[e.id] = { kind = e.kind, color = e.color }
		end
	end
	return out
end

export type DispatchOpts = {
	route: { { number } }?, -- the whole trip as road points in studs (Infection/MedicalRoute.trip)
	hold: boolean?, -- stay on scene until releaseResponder (the patient is loaded first)
}

-- The road trip (centreline points) a responder drives from its bay. `trip` is the caller's, routed from
-- `responderHome()` (the junction beside the bays), or nil: then it is the shortest way by road to the
-- point of the roads nearest `dest`. A call the bay cannot drive forwards to (it lies behind the bay on
-- the hospital road, or right beside it) is answered by pulling out BAY_HOP and standing there.
local function tripFromBay(self: TrafficService, bay: any, dest: { number }, trip: { { number } }?): { { number } }
	local c1 = { bay.cx, bay.cz }
	local function ahead(p: { number }): number
		return (p[1] - c1[1]) * bay.fx + (p[2] - c1[2]) * bay.fz
	end
	local pts: { { number } }? = nil
	if trip and #trip >= 2 then
		local home, second = trip[1], trip[2]
		if (second[1] - home[1]) * bay.fx + (second[2] - home[2]) * bay.fz >= -1e-6 then
			-- on from the junction, or off it to one side: the bay's road leads there
			local onward: { { number } } = { c1 }
			for i, p in trip do
				if i > 1 or ahead(p) > 1 then
					table.insert(onward, { p[1], p[2] })
				end
			end
			pts = onward
		else
			pts = { c1, { trip[#trip][1], trip[#trip][2] } } -- back along the bay's own road
		end
	else
		local stage = MedicalRoute.stage(self.graph, dest[1], dest[2])
		pts = if stage then MedicalRoute.trip(self.graph, c1, stage) else nil
	end
	if pts == nil or #pts < 2 or ahead(pts[2]) < LaneMath.BAY_NEED then
		return { c1, { c1[1] + bay.fx * BAY_HOP, c1[2] + bay.fz * BAY_HOP } }
	end
	return pts
end

-- dispatchResponder(dest, opts?): the first idle responder drives to dest {x, z} (studs). Returns the
-- vehicle or nil when all three are busy.
-- With opts.route the trip is those road points (the medical sequence passes MedicalRoute's shortest road
-- path from `responderHome()`, every leg on asphalt); without it the service routes it by road itself
-- (the W1 stand-in drove the trunk and then an L across the house blocks). Either way the responder
-- pulls out of its own kerbside bay to start it and pulls back in at the end (LaneMath.bayRoute).
function TrafficService.dispatchResponder(self: TrafficService, dest: { number }, opts: DispatchOpts?): Vehicle?
	for _, v in self.vehicles do
		if v.class == "responder" and v.phase == "idle" then
			local held = if opts and opts.hold then true else nil
			local bay = self.bays[v.id]
			local route
			if bay then
				local centre = tripFromBay(self, bay, dest, if opts then opts.route else nil)
				route = LaneMath.bayRoute(`responder_{v.id}`, centre, bay.kerb, v.lane.speeds)
			else
				-- no hospital road in this service's data (a spec's own lanes): the route as given
				local pts = if opts and opts.route and #opts.route >= 2 then opts.route else { { v.x, v.z }, dest }
				route = LaneMath.makeRoute(`responder_{v.id}`, pts, v.lane.speeds)
			end
			AICarMotor.dispatch(v, route, ctxFor(self, {}), held)
			if v.teleported then
				self.jumped[v.id] = true -- (dispatched between two ticks: the flag must reach the next send)
			end
			return v
		end
	end
	return nil
end

-- releaseResponder(v): a held responder may drive home (at once on scene, on arrival otherwise).
function TrafficService.releaseResponder(_self: TrafficService, v: Vehicle)
	if v and (v.class == "responder" or v.class == "incident") then
		AICarMotor.release(v)
	end
end

-- responderIdle(): how many responders are parked and free.
function TrafficService.responderIdle(self: TrafficService): number
	local n = 0
	for _, v in self.vehicles do
		if v.class == "responder" and v.phase == "idle" then
			n += 1
		end
	end
	return n
end

-- responderHome(): where the responders' trips start from, as road routing sees it: the junction of the
-- hospital drive and the hospital road, beside their bays (the trunk's second point).
function TrafficService.responderHome(self: TrafficService): { number }?
	local home = self.home
	return if home then { home[1], home[2] } else nil
end

-- dispatchIncident(scene): both incident cars from the station to the scene {x, z} (traffic.md §5.10).
-- From its pad a car drives straight to the nearest road (the station has no drive in the town's data:
-- that first stretch is open ground, with no building on it) and from there by road to the point of
-- the roads nearest the scene. v5.4's route ran x = -300 u and then straight across the blocks to the
-- scene, through whatever stood there.
function TrafficService.dispatchIncident(self: TrafficService, scene: { number }): number
	local n = 0
	for _, v in self.vehicles do
		if v.class == "incident" and v.phase == "idle" then
			local start = incidentStart(self, v)
			local pts = { start }
			local join = MedicalRoute.stage(self.graph, start[1], start[2])
			local stage = MedicalRoute.stage(self.graph, scene[1], scene[2])
			if join and stage then
				table.insert(pts, { join.x, join.z })
				local trip = MedicalRoute.trip(self.graph, { join.x, join.z }, stage)
				for i = 2, if trip then #trip else 0 do
					table.insert(pts, (trip :: { { number } })[i])
				end
			else
				table.insert(pts, { scene[1], scene[2] })
			end
			local route = LaneMath.makeRoute(`incident_{v.id}`, pts, v.lane.speeds)
			AICarMotor.dispatch(v, route, ctxFor(self, {}))
			if v.teleported then
				self.jumped[v.id] = true
			end
			n += 1
		end
	end
	return n
end

function TrafficService.stats(self: TrafficService): Stats
	return self._stats
end

-- Engine binder: Heartbeat drives `frame` with the world from `ctx.world()` and its own clock (each dt
-- clamped to PoseStream.MAX_FRAME_DT, as Server/Boot/Game does); the poses stream through `ctx.net`.
-- Returns a disconnect function. Server/Boot/Game does not use it: it calls `frame` from its own step.
function TrafficService.start(
	self: TrafficService,
	ctx: { world: () -> World, net: any?, onHit: ((hit: any) -> ())? }
): () -> ()
	local RunService = game:GetService("RunService")
	local now = 0
	local conn = RunService.Heartbeat:Connect(function(frameDt: number)
		local dt = math.min(frameDt, PoseStream.MAX_FRAME_DT)
		now += dt
		local hits = self:frame(dt, now, ctx.world(), ctx.net)
		if ctx.onHit then
			for _, h in hits do
				ctx.onHit(h)
			end
		end
	end)
	return function()
		conn:Disconnect()
	end
end

return TrafficService
