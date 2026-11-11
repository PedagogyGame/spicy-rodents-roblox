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
export type World = { people: { Person }?, squirrels: { Squirrel }? }

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

function TrafficService.new(opts: Opts): TrafficService
	local lanes = LaneMath.load(opts.lanes)
	local unified = LaneMath.unify(lanes, opts.roads, opts.lanes)
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
		local v = AICarMotor.new(e, lane, { at = e.at, cruise = cruise, wait = e.wait, offset = e.offset })
		v.y = self.heightAt(v.x, v.z) + st(0.04)
		table.insert(self.vehicles, v)
		self.byId[v.id] = v
	end
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
-- Each call is one send: a jump made since the last call is flagged in this one and then forgotten.
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
-- with the server clock `now` (the caller's clock AFTER this frame) as their stamp.
function TrafficService.frame(
	self: TrafficService,
	dt: number,
	now: number,
	world: World?,
	net: any?
): { SweptCollision.Hit }
	local hits = self:step(dt, world)
	if net then
		local records = self.sender:frame(dt, now, self)
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

-- dispatchResponder(dest, opts?): the first idle responder drives to dest {x, z} (studs). Returns the
-- vehicle or nil when all three are busy.
-- With opts.route the trip is exactly those road points (the medical sequence passes MedicalRoute's
-- shortest road path, every leg on asphalt). Without it the trip is the trunk plus an L to dest, the
-- W1 stand-in: that L leaves the roads for most destinations, so real dispatches pass a route.
function TrafficService.dispatchResponder(self: TrafficService, dest: { number }, opts: DispatchOpts?): Vehicle?
	local rec = self.records.responder_ambulance_trunk
	for _, v in self.vehicles do
		if v.class == "responder" and v.phase == "idle" then
			local pts: { { number } }
			if opts and opts.route and #opts.route >= 2 then
				pts = opts.route
			else
				pts = table.clone(rec.path.points)
				local last = pts[#pts]
				table.insert(pts, { dest[1], last[2] })
				table.insert(pts, { dest[1], dest[2] })
			end
			local route = LaneMath.makeRoute(`responder_{v.id}`, pts, v.lane.speeds)
			AICarMotor.dispatch(v, route, ctxFor(self, {}), if opts and opts.hold then true else nil)
			self.jumped[v.id] = true -- it appears on the drive (dispatched between two ticks)
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

-- responderHome(): where the responders park (the trunk's first point, on the hospital drive).
function TrafficService.responderHome(self: TrafficService): { number }?
	local rec = self.records.responder_ambulance_trunk
	local first = rec and rec.path and rec.path.points and rec.path.points[1]
	return if first then { first[1], first[2] } else nil
end

-- dispatchIncident(scene): both incident cars from the station to the scene {x, z} (traffic.md §5.10).
function TrafficService.dispatchIncident(self: TrafficService, scene: { number }): number
	local rec = self.records.incident_police_route
	local n = 0
	for _, v in self.vehicles do
		if v.class == "incident" and v.phase == "idle" then
			local car = if v.id % 2 == 0 then 0 else 1
			local start = rec.path.resolved_start[car + 1]
			local route =
				LaneMath.makeRoute(`incident_{v.id}`, LaneMath.incidentRoute(car, start, scene), v.lane.speeds)
			AICarMotor.dispatch(v, route, ctxFor(self, {}))
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
