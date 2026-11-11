--!strict
-- ServerScriptService.Server.Infection.InfectionService
-- The bite-to-hospital sequence on the live town (owner 2026-11-10: "a person bit just ran away,
-- there should be an ambulance come and a crowd gather sometimes, sometimes the symptoms should show
-- up a bit later, but it should always be that they have to go to the hospital to get cured"), and
-- the worried things townspeople say. This is the glue: every decision is made by a pure, Lune-tested
-- module and applied here to the kinematic town.
--   Infection/InfectionRules  one case's state machine (facts in, effects out)
--   Infection/MedicalRoute    the ambulance's stop and road trip; the walk-in tail
--   Infection/Bystanders      who gathers and where they stand
--   Infection/HospitalLayout  the door, the intake, the beds
--   World/FootPath            the way on foot round the buildings, off the pavements
--   Hospital/HospitalService  beds, the queue, the treatment timer
--   Speech/SpeechRules        which line, and whether the person speaks at all
-- What it does to the town: orders to brains through `brain:onEvent({ type = "medical", ... })`
-- (Brains/Directive: down, hidden, route, hold), positions of hidden or carried people written on the
-- TownAI actors (kinematic: the runtime's BulkMoveTo shows them), a responder dispatched on a road
-- route and held on scene until the patient is aboard (Traffic/TrafficService; the responders are
-- fleet vehicles, so they reach the clients in the same pose stream as every other car), and three
-- replicated attributes per body, written only when they change:
--   Med    nil | "symptomatic" | "down" | "carried" | "transit" | "treated"  (Client/Render/
--          MedicalView draws it; nothing is written while a case incubates, so a client cannot read
--          who is infected)
--   Say, SayAt   the line and its server time (Client/UI/SpeechBubbles draws the bubble)
-- A body a player holds is never ordered about, moved or hidden; its player is told what is happening
-- and what to do through `notify`, and `statusOf` is the same for a line that stays on screen.
-- Killing the rodent cures nobody (no call exists for it).
--
-- NOBODY GETS STUCK. Every wait in a case ends on a clock (InfectionRules), and here:
--   * Walking is never the only way. A walk in follows the pavements (the sidewalk graph) and, where
--     they do not reach, goes across the open ground round the buildings (World/FootPath); with no
--     way at all the person collapses and an ambulance comes. The crew walks round buildings the same
--     way; when it cannot reach the patient (too far from any road, across the river) the patient is
--     taken in out of sight. The walk home is the same again, and a walk that overruns ends at home.
--   * An ambulance belongs to a record only for its own trip. A patient whose ambulance is called
--     off goes back to the head of the queue; one nobody comes for is taken in after the timeout.
--   * A player who ends up holding a patient gets the person back on their feet (the rules' standUp);
--     the ambulance, the crew, the crowd and the bed are let go (`standDown`).
--   * A body that leaves the world (no actor, no brain) keeps its case: everything round it is let
--     go, the case waits, and when the body is back the person is on their feet with the symptoms.
--   * A fault while stepping one case is that case's alone: it is stood down, put back on its feet
--     and tried again later; the other cases, the queue and the hospital carry on. `shutdown` lets
--     every body go (the boot loop calls it if it has to switch the service off).
-- In every one of these the person stays infected: the hospital is the only cure.
-- Step-driven: requiring this module starts nothing; Boot/Game calls step(dt) from its own loop.
-- Interface: new(opts) -> Service; :bite(victimId, biterId?) -> boolean (a new infection began);
--   :onSpotted(observerId, threatId); :step(dt); :isInfected(id); :biteable(id); :stateOf(id) ->
--   string?; :statusOf(id) -> string? (for the player holding `id`); :townPercent(); :trafficFlags(id)
--   -> boolean; :cases() -> { [id]: Case }; :walkRoute(x, z) -> ({ {x, z} }?, length);
--   :sidewalkRoute(x, z) -> ({ {x, z} }?, length) (the pavements only); :shutdown(); :stats();
--   TOASTS; TICK; SINK
-- Ids are TownAI actor ids. Positions in studs.

local Import = require("../Import")
local InfectionRules =
	Import.shared("Infection/InfectionRules") :: typeof(require("../../shared/Infection/InfectionRules"))
local MedicalRoute = Import.shared("Infection/MedicalRoute") :: typeof(require("../../shared/Infection/MedicalRoute"))
local Bystanders = Import.shared("Infection/Bystanders") :: typeof(require("../../shared/Infection/Bystanders"))
local HospitalLayout =
	Import.shared("Infection/HospitalLayout") :: typeof(require("../../shared/Infection/HospitalLayout"))
local SpeechRules = Import.shared("Speech/SpeechRules") :: typeof(require("../../shared/Speech/SpeechRules"))
local Tunables = Import.shared("Config/Tunables") :: typeof(require("../../shared/Config/Tunables"))
local Colliders = Import.shared("World/Colliders") :: typeof(require("../../shared/World/Colliders"))
local FootPath = Import.shared("World/FootPath") :: typeof(require("../../shared/World/FootPath"))
local Ground = Import.shared("World/Ground") :: typeof(require("../../shared/World/Ground"))
local Height = Import.shared("World/Height") :: typeof(require("../../shared/World/Height"))
local HospitalService = require("../Hospital/HospitalService")
local Nav = require("../Actors/Nav")
local TownAI = require("../AI/TownAI")

export type Opts = {
	world: any, -- AI/TownAI.World
	traffic: any, -- Traffic/TrafficService
	data: any, -- Shared/Data (the hospital layout and the building boxes)
	rand: (() -> number)?, -- uniform [0, 1); default math.random
	params: any?, -- Infection/InfectionRules.Params override (tests)
	controllerOf: ((id: number) -> string)?, -- "ai" | "player"; default: world.possessed
	setAttr: ((id: number, name: string, value: any) -> ())?, -- replicate an attribute on the body
	setPossessable: ((id: number, possessable: boolean) -> ())?,
	notify: ((id: number, payload: { [string]: any }) -> ())?, -- a message for the player holding `id`
	serverTime: (() -> number)?, -- the clock clients share (workspace:GetServerTimeNow)
	onFault: ((where: string, err: any) -> ())?, -- a part of a step failed (it was contained)
}

type Record = {
	id: number,
	case: any, -- InfectionRules.Case
	inputs: any, -- InfectionRules.Inputs (reused)
	biter: number?,
	home: { number }, -- where the person was bitten (a townsperson walks back there when cured)
	amb: string, -- none | queued | assigned | returning
	vehicle: any?, -- the responder on this patient's call (only while the trip is this record's)
	trip: any?, -- that trip's route: a vehicle on any other route is no longer this record's
	virtual: boolean, -- the stop is the ambulance's own parking spot: nothing drives
	stage: any?, -- MedicalRoute.Stage
	crew: number?, -- the crew member out for this patient (aboard from the dispatch on)
	crewPlanned: boolean, -- the crew's walk has been worked out for this arrival
	crewSecs: number, -- seconds of that walk (0: the crew stays aboard)
	crewPath: { { number } }?, -- its waypoints, the patient last
	crewFrom: { number }?, -- where it starts (the stop on the road)
	crewLen: number, -- studs
	route: { { number } }?, -- the walk-in route chosen at the symptomatic step
	routeLen: number?,
	toBed: boolean, -- a walk-in on the way to the bed (not yet posed as a patient)
	med: string?, -- the Med attribute as last written
	possessable: boolean,
	gone: boolean, -- the body is out of the world: the case waits
	faults: number, -- times this case's step failed
}

type Scene = {
	victim: number,
	x: number,
	z: number,
	bystanders: { { id: number, sayAt: number, said: boolean } },
}

local InfectionService = {}
InfectionService.__index = InfectionService

InfectionService.TICK = 0.2 -- s: the cases are advanced five times a second
InfectionService.SINK = -40 -- studs: a hidden patient's body is drawn this far under the ground
InfectionService.GROUNDS = 60 -- studs round the hospital's footprint that count as "at the hospital"
InfectionService.SPOT_SPEAK = 0.65 -- share of spotters whose line is a "spotting" one (else "fleeing")
InfectionService.FLEE_SPEED = 19 -- studs/s: a bitten staff member's run, the pedestrians' flee pace (7.6 u/s)
InfectionService.CROWD_CANDIDATES = 8 -- the nearest people asked to a scene, at most
InfectionService.CROWD_DETOUR = 60 -- studs a bystander will walk round a building, beyond the straight line
InfectionService.HOME_SNAP = 45 -- studs: a townsperson's walk home ends on the pavement this near the bite
InfectionService.RETRY_SECS = 20 -- a case whose step failed tries again after this, times its failures
InfectionService.CREW_WALK_SECS = 12 -- the crew walks this long to a patient; anything further it runs
InfectionService.AWAY_SECS = 2 -- a cured person with no way home on foot is out of sight this long, then home

-- What a player holding a body is told (on screen, plain words, what to do).
InfectionService.TOASTS = table.freeze({
	bitten = "The Spicy Rodent bit you! You are infected. Only the hospital can cure you: walk in through its front doors (far west of town, follow the HOSPITAL signs).",
	bittenAgain = "The Spicy Rodent bit you again! You are still infected: only the hospital (far west of town) can cure you.",
	infected = "You are infected: the Spicy Rodent bit this person. Only the hospital can cure you: walk in through its front doors (far west of town, follow the HOSPITAL signs).",
	symptoms = "Your eyes have gone red and you feel dizzy. Walk to the hospital (far west of town) and stay inside for 30 seconds to be cured.",
	treating = "The nurses are treating you. Stay inside the hospital for 30 seconds.",
	leftEarly = "You left before the treatment was finished. Go back inside the hospital.",
	cured = "CURED! You are healthy again.",
	-- for the rodent's player, about a victim
	victimDown = "The person you bit has collapsed. An ambulance is on its way.",
	victimSick = "Someone you bit earlier is showing symptoms: red eyes, a stagger.",
	victimCured = "The hospital cured one of your victims.",
}) :: { [string]: string }

export type Service = typeof(setmetatable(
	{} :: {
		world: any,
		traffic: any,
		layout: any?,
		roads: any,
		colliders: any,
		foot: any, -- World/FootPath.Finder
		tail: { { number } }?,
		home: { number }?,
		hospital: HospitalService.Hospital,
		speech: any,
		params: any,
		rand: () -> number,
		controllerOf: (id: number) -> string,
		setAttr: (id: number, name: string, value: any) -> (),
		setPossessable: (id: number, possessable: boolean) -> (),
		notify: (id: number, payload: { [string]: any }) -> (),
		serverTime: () -> number,
		onFault: (where: string, err: any) -> (),
		now: number,
		acc: number,
		records: { [number]: Record },
		order: { number }, -- case ids, oldest first (a stable order for the dice)
		queue: { number }, -- patients waiting for a responder
		scenes: { [number]: Scene },
		busy: { [number]: number }, -- bystander or crew id -> the victim they are with
		-- cured people on their way home (`away`: no way on foot, out of sight until they are there)
		leaving: { [number]: { home: { number }, deadline: number, away: boolean } },
		crewIds: { number },
		tun: { [string]: any },
		_stats: { [string]: number },
	},
	InfectionService
))

function InfectionService.new(opts: Opts): Service
	local world = opts.world
	local layout = HospitalLayout.fromData(opts.data, Tunables.get("hospital.beds"))
	local strips = world.town.strips
	local colliders = Colliders.fromData(opts.data)
	local crewIds = {}
	for _, a in world.actors do
		if a.species == "human" and a.post == "ambulance_crew" then
			table.insert(crewIds, a.id)
		end
	end
	local river = Height.RIVER
	local S = Height.STUDS_PER_UNIT
	local self = setmetatable({
		world = world,
		traffic = opts.traffic,
		layout = layout,
		roads = MedicalRoute.build(strips),
		colliders = colliders,
		-- nobody walks through the river, or over its bridge (the AI motor does not know the deck)
		foot = FootPath.new({
			colliders = colliders,
			bounds = Height.worldClamp(),
			isBlocked = function(x: number, z: number): boolean
				return Ground.surfaceKind(x, z) ~= "terrain"
			end,
			blockedBox = {
				minX = river.startX * S,
				maxX = river.endX * S,
				minZ = river.zMin * S,
				maxZ = river.zMax * S,
			},
		}),
		tail = if layout then MedicalRoute.walkTail(strips, layout.entrance) else nil,
		home = if opts.traffic then opts.traffic:responderHome() else nil,
		hospital = HospitalService.new({
			beds = if layout then math.max(1, #layout.beds) else 1,
			treatSecs = Tunables.get("hospital.treatSecs"),
		}),
		speech = SpeechRules.new(),
		params = opts.params or InfectionRules.defaults(),
		rand = opts.rand or math.random,
		controllerOf = opts.controllerOf or function(id: number): string
			return if world.possessed[id] then "player" else "ai"
		end,
		setAttr = opts.setAttr or function() end,
		setPossessable = opts.setPossessable or function() end,
		notify = opts.notify or function() end,
		serverTime = opts.serverTime or function(): number
			return world.now
		end,
		onFault = opts.onFault or function() end,
		now = 0,
		acc = 0,
		records = {},
		order = {},
		queue = {},
		scenes = {},
		busy = {},
		leaving = {},
		crewIds = crewIds,
		tun = {
			walkInSpeed = Tunables.get("infection.walkInSpeed"),
			crewSpeed = Tunables.get("infection.crewSpeed"),
			crewRunSpeed = Tunables.get("infection.crewRunSpeed"),
			crowdChance = Tunables.get("infection.crowdChance"),
			bystanders = Tunables.get("infection.bystanders"),
			bystanderRadius = Tunables.get("infection.bystanderRadius"),
			bystanderRing = Tunables.get("infection.bystanderRing"),
			bystanderSpeed = Tunables.get("infection.bystanderSpeed"),
			witnessRadius = Tunables.get("infection.witnessRadius"),
			admitRadius = Tunables.get("hospital.admitRadius"),
			dischargeSpeed = Tunables.get("hospital.dischargeSpeed"),
		},
		_stats = {
			bites = 0,
			cases = 0,
			cured = 0,
			dispatched = 0,
			abandoned = 0,
			crowds = 0,
			lines = 0,
			walkIns = 0,
			stoodDown = 0,
			faults = 0,
		},
	}, InfectionService)
	return self
end

-- small helpers ----------------------------------------------------------------------------------

local function actorOf(self: Service, id: number): any?
	return self.world.actorsById[id]
end

local function isAI(self: Service, id: number): boolean
	return self.controllerOf(id) == "ai"
end

-- an order to a brain (Brains/Directive). A body a player holds only ever gets its orders cleared.
local function order(self: Service, id: number, evt: { [string]: any })
	local brain = self.world.brains[id]
	if brain == nil then
		return
	end
	if evt.mode ~= nil and not isAI(self, id) then
		return
	end
	evt.type = "medical"
	brain:onEvent(evt)
	if evt.mode ~= nil then
		-- a brain far from every player thinks once a second: the order takes hold now, not then
		brain:think(0, self.world.ctx)
	end
end

local function directiveDone(self: Service, id: number): boolean
	local brain = self.world.brains[id] :: any
	local d = brain and brain.directive
	return d == nil or d.mode == nil or d.done == true
end

-- move an AI body (kinematic: the runtime draws it there next frame)
local function place(self: Service, id: number, x: number, z: number)
	local a = actorOf(self, id)
	if a and isAI(self, id) then
		a.x, a.z = x, z
		a.y = self.world.ctx.groundAt(x, z) + a.hip
		a.speed = 0
	end
end

local function sink(self: Service, id: number, hidden: boolean)
	local a = actorOf(self, id)
	if a then
		a.lift = if hidden then InfectionService.SINK else nil
	end
end

local function clearLine(self: Service, x0: number, z0: number, x1: number, z1: number): boolean
	if math.abs(x1 - x0) + math.abs(z1 - z0) < 0.5 then
		return true
	end
	return not Colliders.blocked(self.colliders, x0, z0, x1, z1, 1, Height.at(x0, z0) + 3)
end

local function say(self: Service, id: number, situation: string, force: boolean?): boolean
	local line = SpeechRules.request(self.speech, self.now, id, situation, self.rand, { force = force })
	if line == nil then
		return false
	end
	self.setAttr(id, SpeechRules.ATTR.Say, line)
	self.setAttr(id, SpeechRules.ATTR.SayAt, self.serverTime())
	self._stats.lines += 1
	return true
end

local function toast(self: Service, id: number?, key: string)
	if id == nil then
		return
	end
	self.notify(id, { kind = "med", key = key, text = InfectionService.TOASTS[key], secs = 7 })
end

-- a part of a step that fails is reported and contained: the rest of the step still runs
local function guard(self: Service, where: string, fn: (...any) -> (), ...: any): boolean
	local ok, err = pcall(fn, ...)
	if not ok then
		self._stats.faults += 1
		self.onFault(where, err)
	end
	return ok
end

-- a copy of `points` whose walk stops `short` studs before its last point (`sx, sz` is where the
-- walk starts): the crew stops beside the patient, the patient beside the ambulance
local function stopShort(sx: number, sz: number, points: { { number } }, short: number): { { number } }
	local out = table.clone(points)
	local n = #out
	local last = out[n]
	local prev = out[n - 1] or { sx, sz }
	local dx, dz = last[1] - prev[1], last[2] - prev[2]
	local len = math.sqrt(dx * dx + dz * dz)
	if len > short + 0.5 then
		out[n] = { last[1] - dx / len * short, last[2] - dz / len * short }
	elseif n > 1 then
		out[n] = nil -- the last leg is shorter than the gap: stop at the corner before it
	else
		out[n] = { (last[1] + prev[1]) / 2, (last[2] + prev[2]) / 2 }
	end
	return out
end

-- the walk-in route ------------------------------------------------------------------------------

local function pushPoint(points: { { number } }, x: number, z: number)
	local last = points[#points]
	if last and math.abs(last[1] - x) + math.abs(last[2] - z) < 0.75 then
		return
	end
	table.insert(points, { x, z })
end

-- sidewalkRoute(x, z): the way to the hospital door along the pavements, or nil when they do not
-- lead there from (x, z): along the person's own sidewalk to its nearest junction, the sidewalk graph
-- to the north end of the westside sidewalk, then MedicalRoute's tail. Every leg but the step through
-- the door is checked against the building boxes (kinematic people do not collide: a blocked leg
-- would be a walk through a house). On the hospital's grounds the route is straight to the door.
function InfectionService.sidewalkRoute(self: Service, x: number, z: number): ({ { number } }?, number)
	local layout = self.layout
	if layout == nil then
		return nil, 0
	end
	local points: { { number } } = {}
	if HospitalLayout.contains(layout, x, z, InfectionService.GROUNDS) then
		local out = layout.outside
		if clearLine(self, x, z, out[1], out[2]) then
			pushPoint(points, out[1], out[2])
		elseif clearLine(self, x, z, x, out[2]) and clearLine(self, x, out[2], out[1], out[2]) then
			pushPoint(points, x, out[2])
			pushPoint(points, out[1], out[2])
		else
			return nil, 0
		end
		pushPoint(points, layout.entrance[1], layout.entrance[2])
		return points, MedicalRoute.length(points)
	end
	local tail = self.tail
	local nav = self.world.nav
	if tail == nil or nav == nil then
		return nil, 0
	end
	-- the sidewalk strip the person is on (or nearest to)
	local bestI, bestD, px, pz = nil, math.huge, x, z
	for i, s in nav.strips do
		local sx, sz
		if s.axis == "z" then
			sx, sz = s.coord, math.clamp(z, s.min, s.max)
		else
			sx, sz = math.clamp(x, s.min, s.max), s.coord
		end
		local d = (sx - x) ^ 2 + (sz - z) ^ 2
		if d < bestD then
			bestI, bestD, px, pz = i, d, sx, sz
		end
	end
	if bestI == nil or not clearLine(self, x, z, px, pz) then
		return nil, 0
	end
	-- the best of that strip's junctions to start the graph search from
	local goal = tail[1]
	local bestPath, bestLen = nil, math.huge
	for _, nodeId in nav.stripNodes[bestI] do
		local n = nav.nodes[nodeId]
		local path = Nav.path(nav, n.x, n.z, goal[1], goal[2])
		if path then
			local len = math.abs(n.x - px) + math.abs(n.z - pz) + MedicalRoute.length(path)
			if len < bestLen - 1e-6 then
				bestPath, bestLen = path, len
			end
		end
	end
	if bestPath == nil then
		return nil, 0
	end
	-- Nav.path ends at the node nearest the goal: the route only works if that IS the goal
	local last = bestPath[#bestPath - 1] or bestPath[#bestPath]
	if math.abs(last[1] - goal[1]) + math.abs(last[2] - goal[2]) > 1 then
		return nil, 0
	end
	pushPoint(points, px, pz)
	for _, p in bestPath do
		pushPoint(points, p[1], p[2])
	end
	for _, p in tail do
		pushPoint(points, p[1], p[2])
	end
	local fx, fz = x, z
	for i, p in points do
		if i < #points and not clearLine(self, fx, fz, p[1], p[2]) then
			return nil, 0
		end
		fx, fz = p[1], p[2]
	end
	return points, MedicalRoute.length(points) + math.sqrt(bestD)
end

-- walkRoute(x, z): the way on foot from (x, z) to the hospital door, or nil when there is none:
-- along the pavements where they lead there (sidewalkRoute), else across the open ground round the
-- buildings to the spot in front of the door (World/FootPath: the police yard, the shop floors, the
-- drives and the pavements the sidewalk graph does not join up).
function InfectionService.walkRoute(self: Service, x: number, z: number): ({ { number } }?, number)
	local layout = self.layout
	if layout == nil then
		return nil, 0
	end
	if HospitalLayout.contains(layout, x, z) then
		return { { layout.reception[1], layout.reception[2] } }, 1
	end
	local points, len = self:sidewalkRoute(x, z)
	if points then
		return points, len
	end
	local out, door = layout.outside, layout.entrance
	local way, wayLen = FootPath.find(self.foot, x, z, out[1], out[2], { maxLength = self.params.walkInMaxDist })
	if way == nil then
		return nil, 0
	end
	table.insert(way, { door[1], door[2] })
	return way, wayLen + math.sqrt((door[1] - out[1]) ^ 2 + (door[2] - out[2]) ^ 2)
end

-- scenes -----------------------------------------------------------------------------------------

local function releaseBystander(self: Service, id: number)
	if self.busy[id] ~= nil then
		self.busy[id] = nil
		order(self, id, {})
	end
end

local function closeScene(self: Service, victim: number)
	local scene = self.scenes[victim]
	if scene == nil then
		return
	end
	self.scenes[victim] = nil
	for _, b in scene.bystanders do
		releaseBystander(self, b.id)
	end
end

-- the crew member's job is over: back at the ambulance bay (they rode home), or, with `stay`, let go
-- where they stand (a paramedic bitten at the scene becomes a patient there)
local function freeCrew(self: Service, rec: Record, stay: boolean?)
	local id = rec.crew
	rec.crewPlanned = false
	rec.crewPath = nil
	rec.crewFrom = nil
	if id == nil then
		return
	end
	rec.crew = nil
	self.busy[id] = nil
	sink(self, id, false)
	if not stay then
		local brain = self.world.brains[id] :: any
		local station = brain and brain.points and brain.points[1]
		if station then
			place(self, id, station[1], station[2])
		end
	end
	order(self, id, {})
	self.setPossessable(id, true)
end

-- a crew member for this call: one who is free, on their feet and not a patient. With `aboard` they
-- ride out in the ambulance (out of sight from the bay until they step out at the scene); for a
-- patient beside the bay itself they just walk over.
local function callCrew(self: Service, rec: Record, aboard: boolean)
	if rec.crew ~= nil then
		return
	end
	for _, id in self.crewIds do
		if
			self.busy[id] == nil
			and self.records[id] == nil
			and self.leaving[id] == nil
			and isAI(self, id)
			and actorOf(self, id) ~= nil
			and self.world.brains[id] ~= nil
		then
			rec.crew = id
			self.busy[id] = rec.id
			self.setPossessable(id, false)
			if aboard then
				order(self, id, { mode = "hidden" })
				sink(self, id, true)
			end
			return
		end
	end
end

-- the collapse: the patient sits where they are, the people round them are alarmed, some come over
local function openScene(self: Service, rec: Record)
	local a = actorOf(self, rec.id)
	if a == nil then
		return
	end
	local biter = if rec.biter then actorOf(self, rec.biter) else nil
	order(
		self,
		rec.id,
		{ mode = "down", faceX = if biter then biter.x else nil, faceZ = if biter then biter.z else nil }
	)
	rec.stage = MedicalRoute.stage(self.roads, a.x, a.z)
	local scene: Scene = { victim = rec.id, x = a.x, z = a.z, bystanders = {} }
	self.scenes[rec.id] = scene
	local radius = self.tun.bystanderRadius
	local candidates = {}
	for _, o in self.world.actors do
		if o.species == "human" and o.id ~= rec.id then
			local d2 = (o.x - a.x) ^ 2 + (o.z - a.z) ^ 2
			if d2 <= radius * radius and isAI(self, o.id) then
				-- humans_actors §7.2: a new scene puts everyone within 72 u on alert
				local brain = self.world.brains[o.id]
				if brain then
					brain:onEvent({ type = "alarm", alert = 7 })
				end
				table.insert(candidates, {
					id = o.id,
					x = o.x,
					z = o.z,
					eligible = (o.post == "townsperson" or o.post == "shop_worker")
						and (o.lift or 0) == 0
						and self.records[o.id] == nil
						and self.busy[o.id] == nil
						and self.leaving[o.id] == nil,
				})
			end
		end
	end
	local chosen, want = Bystanders.select(scene, candidates, self.rand, {
		chance = self.tun.crowdChance,
		min = self.tun.bystanders[1],
		max = self.tun.bystanders[2],
		radius = radius,
	})
	if want == 0 or #chosen == 0 then
		return
	end
	local colliders, roads = self.colliders, self.roads
	local spots = Bystanders.spots(scene, want, function(x: number, z: number): boolean
		return Colliders.pointIn(colliders, x, z, Height.at(x, z) + 3, 3) == nil
			and not MedicalRoute.onRoad(roads, x, z, 4)
	end, self.tun.bystanderRing)
	local people = {}
	for i, id in chosen do
		if i > InfectionService.CROWD_CANDIDATES then
			break
		end
		local o = actorOf(self, id)
		if o then
			table.insert(people, { id = id, x = o.x, z = o.z })
		end
	end
	-- each comes by the straight line when it is clear, else round the building in the way (a short
	-- detour only); someone with no way over is replaced by the next nearest
	local detour = InfectionService.CROWD_DETOUR
	local placed = Bystanders.assign(people, spots, function(p: any, x: number, z: number): { { number } }?
		if clearLine(self, p.x, p.z, x, z) then
			return { { x, z } }
		end
		local direct = math.sqrt((x - p.x) ^ 2 + (z - p.z) ^ 2)
		return (FootPath.find(self.foot, p.x, p.z, x, z, { maxLength = direct + detour, maxNodes = 400 }))
	end, want, self.tun.bystanders[1])
	for i, p in placed do
		self.busy[p.id] = rec.id
		local path = p.path :: { { number } }
		if #path <= 1 then
			order(self, p.id, {
				mode = "hold",
				x = p.x,
				z = p.z,
				faceX = a.x,
				faceZ = a.z,
				speed = self.tun.bystanderSpeed,
			})
		else
			order(self, p.id, {
				mode = "route",
				points = path,
				speed = self.tun.bystanderSpeed,
				after = "stand",
				faceX = a.x,
				faceZ = a.z,
			})
		end
		table.insert(scene.bystanders, {
			id = p.id,
			sayAt = self.now + Bystanders.SAY_FIRST + Bystanders.SAY_EACH * (i - 1),
			said = false,
		})
	end
	if #placed > 0 then
		self._stats.crowds += 1
	end
end

local function stepScenes(self: Service)
	for _, scene in self.scenes do
		for i = #scene.bystanders, 1, -1 do
			local b = scene.bystanders[i]
			if not isAI(self, b.id) or self.busy[b.id] ~= scene.victim then
				-- a player took the body, or it was bitten itself: it is no longer part of the crowd
				if self.busy[b.id] == scene.victim then
					self.busy[b.id] = nil
					order(self, b.id, {})
				end
				table.remove(scene.bystanders, i)
			elseif not b.said and self.now >= b.sayAt then
				local o = actorOf(self, b.id)
				local near = o ~= nil and (o.x - scene.x) ^ 2 + (o.z - scene.z) ^ 2 < 60 * 60
				-- the town-wide limit may make them wait their turn; after half a minute they let it go
				if (near and say(self, b.id, "bystander", false)) or self.now >= b.sayAt + 30 then
					b.said = true
				end
			end
		end
	end
end

-- the ambulance ----------------------------------------------------------------------------------

-- Is the record's responder still on the trip this record sent it on? A responder that has parked,
-- or been sent out again for someone else, drives a different route (or none).
local function onTrip(rec: Record): boolean
	local v = rec.vehicle
	return v ~= nil and rec.trip ~= nil and v.route == rec.trip and v.phase ~= "idle"
end

-- The record lets go of its ambulance. The vehicle is only released while it is still out on this
-- record's call: after the patient is loaded it has been released already, and by the time the case
-- closes it may be parked or on its way to the next patient (releasing it then sent it home empty
-- and left that patient on the pavement).
local function dropAmbulance(self: Service, rec: Record)
	local i = table.find(self.queue, rec.id)
	if i then
		table.remove(self.queue, i)
	end
	if rec.amb == "assigned" and onTrip(rec) then
		self.traffic:releaseResponder(rec.vehicle)
	end
	rec.vehicle = nil
	rec.trip = nil
	rec.virtual = false
	rec.amb = "none"
end

local function ambulanceFact(rec: Record): string
	if rec.amb == "assigned" then
		if rec.virtual then
			return "arrived"
		end
		local v = rec.vehicle
		if v == nil or not onTrip(rec) then
			return "none"
		end
		return if v.phase == "hold" then "arrived" else "assigned"
	elseif rec.amb == "returning" then
		if rec.virtual or not onTrip(rec) then
			return "home"
		end
		return "returning"
	end
	return rec.amb
end

-- The ambulance that was coming is no longer coming for this patient (something else let it go, so
-- it turns round at the scene, or it is on another route): a patient still waiting goes back to the
-- head of the queue (and the crew that rode out is back at the bay); one the crew is already working
-- on is carried to the roadside and taken in.
local function checkAmbulance(self: Service, rec: Record)
	if rec.amb ~= "assigned" or rec.virtual then
		return
	end
	local v = rec.vehicle
	if v ~= nil and onTrip(rec) and v.held == true then
		return
	end
	rec.vehicle = nil
	rec.trip = nil
	local state = rec.case.state
	if state == "scene" or state == "enroute" then
		freeCrew(self, rec)
		rec.amb = "queued"
		if table.find(self.queue, rec.id) == nil then
			table.insert(self.queue, 1, rec.id)
		end
	else
		rec.amb = "none"
	end
end

local function stepQueue(self: Service)
	while #self.queue > 0 do
		local id = self.queue[1]
		local rec = self.records[id]
		if rec == nil or rec.stage == nil or rec.amb ~= "queued" then
			table.remove(self.queue, 1)
			continue
		end
		local home = self.home
		local trip = if home then MedicalRoute.trip(self.roads, home, rec.stage) else nil
		if trip == nil then
			-- the patient is beside the ambulance's own parking spot: nothing to drive
			rec.virtual = true
			rec.amb = "assigned"
			callCrew(self, rec, false)
			table.remove(self.queue, 1)
			continue
		end
		local v = self.traffic:dispatchResponder({ rec.stage.x, rec.stage.z }, { route = trip, hold = true })
		if v == nil then
			break -- all three are out: the patient keeps their place in the queue
		end
		rec.vehicle = v
		rec.trip = v.route
		rec.amb = "assigned"
		self._stats.dispatched += 1
		callCrew(self, rec, true)
		table.remove(self.queue, 1)
	end
end

-- The crew member's walk from the ambulance to the patient: its seconds, or 0 when the patient is
-- loaded where they sit (they are right beside the ambulance, no crew rode out, or there is no way
-- to them on foot within the crew's reach: across the river, or too far from any road). The walk
-- goes round buildings (World/FootPath). The first CREW_WALK_SECS of it are at a walk and the rest
-- at a run: the ambulance is held on scene for the walk there and back, and with three ambulances
-- in town a slow walk to a far patient leaves the next patients waiting on the pavement.
local function crewTime(self: Service, rec: Record): number
	if rec.crewPlanned then
		return rec.crewSecs
	end
	rec.crewPlanned = true
	rec.crewSecs = 0
	rec.crewPath = nil
	local a, stage, crew = actorOf(self, rec.id), rec.stage, rec.crew
	local c = if crew then actorOf(self, crew) else nil
	if a == nil or stage == nil or c == nil then
		return 0
	end
	local fx, fz = stage.x, stage.z
	if rec.virtual then
		fx, fz = c.x, c.z -- nothing drove: the crew member walks over from where they stand
	end
	if math.sqrt((a.x - fx) ^ 2 + (a.z - fz) ^ 2) < 6 then
		return 0
	end
	local reach = self.tun.crewRunSpeed * self.params.crewMaxSecs
	local path, len = FootPath.find(self.foot, fx, fz, a.x, a.z, { maxLength = reach })
	if path == nil then
		return 0
	end
	rec.crewPath, rec.crewFrom, rec.crewLen = path, { fx, fz }, len
	local walk, run = self.tun.crewSpeed, self.tun.crewRunSpeed
	local secs = len / walk
	if secs > InfectionService.CREW_WALK_SECS then
		secs = InfectionService.CREW_WALK_SECS + (len - InfectionService.CREW_WALK_SECS * walk) / run
	end
	rec.crewSecs = math.clamp(secs, 3, self.params.crewMaxSecs)
	return rec.crewSecs
end

-- the patient leaves the scene out of sight: sunk, moved to the hospital's intake, the ambulance let go
local function hidePatient(self: Service, rec: Record)
	closeScene(self, rec.id)
	order(self, rec.id, { mode = "hidden" })
	sink(self, rec.id, true)
	local layout = self.layout
	if layout then
		place(self, rec.id, layout.intake[1], layout.intake[2])
	end
	if rec.crew then
		-- the crew member rides back with the patient (out of sight until the ambulance is home)
		order(self, rec.crew, { mode = "hidden" })
		sink(self, rec.crew, true)
	end
end

-- Everything that is being done for this patient stops: the crowd goes, the ambulance is let go (or
-- the request dropped), the crew is free, the bed is free, the body is in sight and under no order.
-- The case itself is untouched (the caller decides what the person does next).
local function standDown(self: Service, rec: Record)
	closeScene(self, rec.id)
	dropAmbulance(self, rec)
	freeCrew(self, rec)
	self.hospital:discharge(rec.id)
	sink(self, rec.id, false)
	rec.toBed = false
	rec.stage = nil
	rec.route, rec.routeLen = nil, nil
	order(self, rec.id, {})
	self._stats.stoodDown += 1
end

-- effects ----------------------------------------------------------------------------------------

local function flee(self: Service, rec: Record)
	local a = actorOf(self, rec.id)
	local biter = if rec.biter then actorOf(self, rec.biter) else nil
	if a == nil or biter == nil or not isAI(self, rec.id) then
		return
	end
	local brain = self.world.brains[rec.id] :: any
	if brain == nil then
		return
	end
	if rec.case.state == "walkin" then
		return -- bitten again on the way to the hospital: they shout and keep walking in
	end
	if brain.kind == "Pedestrian" then
		brain:onEvent({ type = "bitten", threat = biter, override = true })
		return
	end
	-- staff and officers have no lane to run along: a short clear run away from the biter
	local dx, dz = a.x - biter.x, a.z - biter.z
	local m = math.sqrt(dx * dx + dz * dz)
	if m < 0.01 then
		dx, dz, m = 1, 0, 1
	end
	dx, dz = dx / m, dz / m
	for _, turn in { 0, 0.6, -0.6, 1.2, -1.2 } do
		local c, s = math.cos(turn), math.sin(turn)
		local tx, tz = a.x + (dx * c - dz * s) * 30, a.z + (dx * s + dz * c) * 30
		if clearLine(self, a.x, a.z, tx, tz) then
			order(self, rec.id, { mode = "route", points = { { tx, tz } }, speed = InfectionService.FLEE_SPEED })
			return
		end
	end
end

-- Where a cured person goes: the hospital's own people, the crews, officers and shop staff back to
-- their post (the first point of their round), a townsperson back to where they were bitten (to the
-- pavement beside it when there is one, so the walk ends on their lane).
local function homeOf(self: Service, rec: Record): (number, number)
	local brain = self.world.brains[rec.id] :: any
	if brain and brain.kind ~= "Pedestrian" then
		local post = brain.points and brain.points[1]
		if post then
			return post[1], post[2]
		end
		return rec.home[1], rec.home[2]
	end
	local hx, hz = rec.home[1], rec.home[2]
	local nav = self.world.nav
	local bx, bz, bestD = hx, hz, InfectionService.HOME_SNAP ^ 2
	if nav then
		for _, s in nav.strips do
			local sx, sz
			if s.axis == "z" then
				sx, sz = s.coord, math.clamp(hz, s.min, s.max)
			else
				sx, sz = math.clamp(hx, s.min, s.max), s.coord
			end
			local d = (sx - hx) ^ 2 + (sz - hz) ^ 2
			if d < bestD then
				bx, bz, bestD = sx, sz, d
			end
		end
	end
	return bx, bz
end

-- The walk from a bed to (hx, hz): out through the ward door and the front door, then the way a
-- walk-in comes, backwards (the pavements), or across the open ground round the buildings. nil when
-- there is no way on foot (beyond the river; a search over its budget).
local function wayHome(self: Service, layout: any, bed: any, hx: number, hz: number): ({ { number } }?, number)
	if HospitalLayout.contains(layout, hx, hz) then
		-- the hospital's own people: back to work through the ward door and reception
		local points = { { bed.door[1], bed.door[2] }, { layout.reception[1], layout.reception[2] }, { hx, hz } }
		return points, MedicalRoute.length(points)
	end
	local points = HospitalLayout.pathOut(layout, bed)
	local out = layout.outside
	local back = self:sidewalkRoute(hx, hz)
	if back then
		for i = #back - 1, 1, -1 do
			table.insert(points, back[i])
		end
		table.insert(points, { hx, hz })
	else
		local way = FootPath.find(self.foot, out[1], out[2], hx, hz, { maxLength = self.params.walkInMaxDist })
		if way == nil then
			return nil, 0
		end
		for _, p in way do
			table.insert(points, p)
		end
	end
	return points, MedicalRoute.length(points)
end

local function apply(self: Service, rec: Record, effect: any)
	local kind = effect.kind
	local id = rec.id
	if kind == "flee" then
		flee(self, rec)
	elseif kind == "say" then
		if effect.situation == "crew" then
			if rec.crew then
				say(self, rec.crew, "crew", true)
			end
		else
			say(self, id, effect.situation, effect.force)
			if effect.situation == "symptoms" and effect.force then
				toast(self, rec.biter, "victimSick")
			end
		end
	elseif kind == "toast" then
		toast(self, id, effect.key)
	elseif kind == "collapse" then
		openScene(self, rec)
		toast(self, rec.biter, "victimDown")
	elseif kind == "call" then
		rec.amb = "queued"
		if table.find(self.queue, id) == nil then
			table.insert(self.queue, id)
		end
	elseif kind == "crewOut" then
		-- the crew member steps out of the ambulance on the patient's side and walks over
		local a, crew, path, from = actorOf(self, id), rec.crew, rec.crewPath, rec.crewFrom
		if a and crew and path and from then
			sink(self, crew, false)
			if not rec.virtual then
				local first = path[1]
				local dx, dz = first[1] - from[1], first[2] - from[2]
				local m = math.max(0.01, math.sqrt(dx * dx + dz * dz))
				local out = math.min(5, m)
				place(self, crew, from[1] + dx / m * out, from[2] + dz / m * out)
			end
			order(self, crew, {
				mode = "route",
				points = stopShort(from[1], from[2], path, 4),
				speed = rec.crewLen / math.max(1, rec.crewSecs),
				after = "stand",
				faceX = a.x,
				faceZ = a.z,
			})
		end
	elseif kind == "carry" then
		-- the patient is helped to the ambulance beside the crew member, both at the crew's pace,
		-- back the way the crew came (Med "carried": on their feet, not posed sitting while they move)
		local a, crew, path, from = actorOf(self, id), rec.crew, rec.crewPath, rec.crewFrom
		closeScene(self, id)
		if a and path and from then
			local back: { { number } } = {}
			for i = #path - 1, 1, -1 do
				table.insert(back, path[i])
			end
			table.insert(back, { from[1], from[2] })
			local speed = rec.crewLen / math.max(1, rec.crewSecs)
			order(self, id, {
				mode = "route",
				points = stopShort(a.x, a.z, back, 5),
				speed = speed,
				after = "stand",
			})
			if crew then
				order(self, crew, {
					mode = "route",
					points = stopShort(a.x, a.z, back, 9),
					speed = speed,
					after = "stand",
				})
			end
		end
	elseif kind == "load" then
		hidePatient(self, rec)
		if rec.amb == "assigned" and onTrip(rec) then
			self.traffic:releaseResponder(rec.vehicle)
		end
		rec.amb = "returning"
	elseif kind == "abandon" then
		self._stats.abandoned += 1
		hidePatient(self, rec)
		dropAmbulance(self, rec)
		freeCrew(self, rec)
	elseif kind == "standDown" then
		standDown(self, rec)
	elseif kind == "walkIn" then
		if rec.route then
			self._stats.walkIns += 1
			order(
				self,
				id,
				{ mode = "route", points = rec.route, speed = self.tun.walkInSpeed, stagger = true, after = "stand" }
			)
		end
	elseif kind == "resume" then
		order(self, id, {})
	elseif kind == "arrive" then
		self.hospital:admit(id, self.now)
		if effect.by == "walk" and self.layout then
			local r = self.layout.reception
			order(
				self,
				id,
				{ mode = "route", points = { { r[1], r[2] } }, speed = self.tun.walkInSpeed, after = "stand" }
			)
		end
	elseif kind == "bed" then
		local layout = self.layout
		local bed = layout and layout.beds[self.hospital:bedOf(id) or 0]
		if layout and bed then
			if rec.case.arrival == "ambulance" then
				sink(self, id, false)
				place(self, id, bed.x, bed.z)
				order(self, id, { mode = "down", faceX = bed.door[1], faceZ = bed.door[2] })
			else
				rec.toBed = true
				local a = actorOf(self, id)
				local points = HospitalLayout.pathIn(layout, bed)
				if a and HospitalLayout.contains(layout, a.x, a.z) then
					table.remove(points, 1) -- already through the door
				end
				order(self, id, { mode = "route", points = points, speed = self.tun.walkInSpeed, after = "stand" })
			end
		else
			sink(self, id, false)
		end
	elseif kind == "cure" then
		local a = actorOf(self, id)
		if a then
			a.infected = nil
		end
		self._stats.cured += 1
		toast(self, rec.biter, "victimCured")
	elseif kind == "discharge" then
		local layout = self.layout
		local bed = layout and layout.beds[self.hospital:bedOf(id) or 0]
		self.hospital:discharge(id)
		sink(self, id, false)
		if layout and bed and isAI(self, id) then
			local hx, hz = homeOf(self, rec)
			local points, len = wayHome(self, layout, bed, hx, hz)
			if points then
				order(self, id, { mode = "route", points = points, speed = self.tun.dischargeSpeed, after = "stand" })
				-- a walk that overruns (it never should) ends at home all the same
				self.leaving[id] = {
					home = { hx, hz },
					deadline = self.now + len / self.tun.dischargeSpeed * 1.5 + 60,
					away = false,
				}
			else
				-- no way home on foot (beyond the river): out of sight from the bed, and home a moment
				-- later; never walked out to the front door to vanish there in plain view
				order(self, id, { mode = "hidden" })
				sink(self, id, true)
				self.setPossessable(id, false)
				self.leaving[id] = { home = { hx, hz }, deadline = self.now + InfectionService.AWAY_SECS, away = true }
			end
		else
			order(self, id, {})
		end
	end
end

-- the Med attribute and the possessable flag follow the case, written only on change
local function publish(self: Service, rec: Record)
	local med = InfectionRules.tell(rec.case)
	if rec.toBed and med == "treated" then
		med = "symptomatic" -- a walk-in is posed as a patient once they reach the bed
	end
	if med ~= rec.med then
		rec.med = med
		self.setAttr(rec.id, "Med", med)
	end
	local possessable = InfectionRules.possessable(rec.case)
	if possessable ~= rec.possessable then
		rec.possessable = possessable
		self.setPossessable(rec.id, possessable)
	end
end

local function remove(self: Service, rec: Record)
	closeScene(self, rec.id)
	dropAmbulance(self, rec)
	freeCrew(self, rec)
	self.records[rec.id] = nil
	local i = table.find(self.order, rec.id)
	if i then
		table.remove(self.order, i)
	end
	if rec.med ~= nil then
		self.setAttr(rec.id, "Med", nil)
	end
	if not rec.possessable then
		self.setPossessable(rec.id, true)
	end
end

local function factsFor(self: Service, rec: Record): any
	local inputs = rec.inputs
	local a = actorOf(self, rec.id)
	local layout = self.layout
	local case = rec.case
	inputs.controller = self.controllerOf(rec.id)
	if a and layout then
		inputs.nearHospital = HospitalLayout.contains(layout, a.x, a.z, InfectionService.GROUNDS)
		inputs.atEntrance = HospitalLayout.contains(layout, a.x, a.z)
			or HospitalLayout.nearEntrance(layout, a.x, a.z, self.tun.admitRadius)
	else
		inputs.nearHospital, inputs.atEntrance = false, false
	end
	-- the walk-in route is worked out once, at the moment the symptomatic person decides
	inputs.routeLen = nil
	local deciding = (case.state == "symptomatic" and self.now >= case.untilT)
		or (case.state == "treated" and case.selfTreat) -- let go by a player inside the hospital
	if deciding and inputs.controller == "ai" and a then
		local route, len = self:walkRoute(a.x, a.z)
		rec.route, rec.routeLen = route, if route then len else nil
		inputs.routeLen = rec.routeLen
	end
	inputs.ambulance = ambulanceFact(rec)
	if inputs.ambulance == "arrived" and (case.state == "scene" or case.state == "enroute") then
		inputs.crewSecs = crewTime(self, rec)
	end
	inputs.hospital = self.hospital:stateOf(rec.id)
	return inputs
end

local function stepCase(self: Service, rec: Record)
	local a = actorOf(self, rec.id)
	if a == nil or self.world.brains[rec.id] == nil then
		-- the body is out of the world: everything round the case is let go and the case waits. When
		-- the body is back the person is on their feet, infected, with the symptoms showing.
		if not rec.gone then
			rec.gone = true
			standDown(self, rec)
			if InfectionRules.isPatient(rec.case) or rec.case.state == "walkin" then
				InfectionRules.standUp(rec.case, self.now)
			end
		end
		return
	end
	if rec.gone then
		rec.gone = false
		a.infected = true
	end
	checkAmbulance(self, rec)
	local inputs = factsFor(self, rec)
	local effects = InfectionRules.advance(rec.case, self.now, inputs, self.rand, self.params)
	for _, e in effects do
		apply(self, rec, e)
	end
	-- a walk-in who has reached the bed sits down as a patient
	if rec.toBed and directiveDone(self, rec.id) then
		rec.toBed = false
		local bed = self.layout and self.layout.beds[self.hospital:bedOf(rec.id) or 0]
		if bed and rec.case.state == "treated" then
			place(self, rec.id, bed.x, bed.z)
			order(self, rec.id, { mode = "down", faceX = bed.door[1], faceZ = bed.door[2] })
		end
	end
	-- the ambulance is parked again: the crew member is back at the bay, and the record forgets the
	-- vehicle (it may go out for someone else from now on)
	if rec.amb == "returning" and ambulanceFact(rec) == "home" then
		freeCrew(self, rec)
		rec.vehicle = nil
		rec.trip = nil
		rec.virtual = false
		rec.amb = "none"
	end
	-- a patient the case says is in the hospital's care is always on the hospital's list (it never
	-- should be otherwise): a case must not wait for a bed nobody is keeping for it
	local state = rec.case.state
	if
		(state == "admitted" or (state == "treated" and not rec.case.selfTreat))
		and self.hospital:stateOf(rec.id) == "none"
	then
		self.hospital:admit(rec.id, self.now)
	end
	publish(self, rec)
	if InfectionRules.closed(rec.case) then
		remove(self, rec)
	end
end

-- A case whose step failed: whatever was half done is undone and the person is put back on their
-- feet, still infected, to go through it again a little later (longer after every failure). Each
-- part is on its own so a second failure cannot stop the next part.
local function recover(self: Service, rec: Record)
	rec.faults += 1
	if InfectionRules.closed(rec.case) or not InfectionRules.isInfected(rec.case) then
		pcall(remove, self, rec) -- the cure had happened: only the tidying up failed
		return
	end
	pcall(standDown, self, rec)
	pcall(function()
		InfectionRules.standUp(rec.case, self.now)
		rec.case.untilT = self.now + InfectionService.RETRY_SECS * rec.faults
	end)
	pcall(publish, self, rec)
end

-- a cured person is back in their own life: in sight, under no order, anyone's to play
local function arrived(self: Service, id: number, away: boolean)
	self.leaving[id] = nil
	if away then
		sink(self, id, false)
		self.setPossessable(id, true)
	end
	order(self, id, {})
end

-- cured people on their way home: when the walk is done (or its time is up) they are home
local function stepLeaving(self: Service)
	for id, l in self.leaving do
		if not isAI(self, id) or actorOf(self, id) == nil then
			arrived(self, id, l.away)
		elseif l.away then
			if self.now >= l.deadline then
				place(self, id, l.home[1], l.home[2])
				arrived(self, id, true)
			end
		elseif directiveDone(self, id) or self.now >= l.deadline then
			if not directiveDone(self, id) then
				place(self, id, l.home[1], l.home[2])
			end
			arrived(self, id, false)
		end
	end
end

-- public -----------------------------------------------------------------------------------------

-- bite(victimId, biterId?): the rodent bit this person. True when a new infection began (false for
-- a second bite on someone already infected, who just runs and shouts again, and for a patient).
function InfectionService.bite(self: Service, victimId: number, biterId: number?): boolean
	local a = actorOf(self, victimId)
	if a == nil or a.species ~= "human" then
		return false
	end
	self._stats.bites += 1
	local existing = self.records[victimId]
	if existing then
		existing.biter = biterId or existing.biter
		for _, e in InfectionRules.rebite(existing.case, self.now, self.controllerOf(victimId)) do
			apply(self, existing, e)
		end
		return false
	end
	-- whatever the person was doing for someone else's scene, or on the way home, ends here
	if self.leaving[victimId] then
		self.leaving[victimId] = nil
		local brain = self.world.brains[victimId] :: any
		if brain and brain.kind ~= "Pedestrian" then
			order(self, victimId, {}) -- (a Pedestrian drops the walk home itself when it flees)
		end
	end
	if self.busy[victimId] ~= nil then
		for _, rec in self.records do
			if rec.crew == victimId then
				freeCrew(self, rec, true)
			end
		end
		releaseBystander(self, victimId)
	end
	local layout = self.layout
	local inputs = {
		controller = self.controllerOf(victimId),
		nearHospital = layout ~= nil and HospitalLayout.contains(layout, a.x, a.z, InfectionService.GROUNDS),
	}
	local case, effects = InfectionRules.newCase(victimId, self.now, inputs, self.rand, self.params)
	local rec: Record = {
		id = victimId,
		case = case,
		inputs = inputs,
		biter = biterId,
		home = { a.x, a.z },
		amb = "none",
		vehicle = nil,
		trip = nil,
		virtual = false,
		stage = nil,
		crew = nil,
		crewPlanned = false,
		crewSecs = 0,
		crewPath = nil,
		crewFrom = nil,
		crewLen = 0,
		route = nil,
		routeLen = nil,
		toBed = false,
		med = nil,
		possessable = true,
		gone = false,
		faults = 0,
	}
	self.records[victimId] = rec
	table.insert(self.order, victimId)
	a.infected = true
	self._stats.cases += 1
	for _, e in effects do
		apply(self, rec, e)
	end
	-- witnesses (humans_actors §7.3): people close by run; the nearest few say what they saw
	local biter = if biterId then actorOf(self, biterId) else nil
	if biter then
		local r = self.tun.witnessRadius
		local near = {}
		for _, o in self.world.actors do
			if o.species == "human" and o.id ~= victimId and self.records[o.id] == nil and self.busy[o.id] == nil then
				local d2 = (o.x - a.x) ^ 2 + (o.z - a.z) ^ 2
				if d2 <= r * r and isAI(self, o.id) then
					table.insert(near, { id = o.id, d = d2 })
				end
			end
		end
		table.sort(near, function(p, q)
			if p.d ~= q.d then
				return p.d < q.d
			end
			return p.id < q.id
		end)
		for i, w in near do
			local brain = self.world.brains[w.id] :: any
			if brain and brain.kind == "Pedestrian" and self.leaving[w.id] == nil then
				brain:onEvent({ type = "witness", threat = biter, alert = 10 })
			end
			if i <= 3 then
				say(self, w.id, "witness", false)
			end
		end
	end
	publish(self, rec)
	return true
end

-- onSpotted: a townsperson just saw a squirrel and started to run. Only the Spicy Rodent and infected
-- squirrels are "one of those squirrels"; an ordinary squirrel gets no comment.
function InfectionService.onSpotted(self: Service, observerId: number, threatId: number?)
	local threat = if threatId then actorOf(self, threatId) else nil
	if threat == nil or not (threat.variant == "spicy" or threat.infected == true) then
		return
	end
	if not isAI(self, observerId) or self.busy[observerId] ~= nil then
		return
	end
	local rec = self.records[observerId]
	if rec and InfectionRules.tell(rec.case) ~= nil then
		return -- a patient has other things to say
	end
	say(self, observerId, if self.rand() < InfectionService.SPOT_SPEAK then "spotting" else "fleeing", false)
end

-- step(dt): called every frame by the boot loop; the work happens every TICK seconds. Each part of
-- the tick is contained: a fault in one case, or in the queue, does not stop the others.
function InfectionService.step(self: Service, dt: number)
	self.acc += dt
	if self.acc < InfectionService.TICK then
		return
	end
	self.now += self.acc
	self.acc = 0
	guard(self, "spotted", function()
		for _, ev in TownAI.drainEvents(self.world) do
			if ev.kind == "spotted" then
				self:onSpotted(ev.id, ev.other)
			end
		end
	end)
	for _, id in table.clone(self.order) do
		local rec = self.records[id]
		if rec and not guard(self, "case", stepCase, self, rec) then
			recover(self, rec)
		end
	end
	guard(self, "queue", stepQueue, self)
	guard(self, "hospital", function()
		self.hospital:step(self.now)
	end)
	guard(self, "scenes", stepScenes, self)
	guard(self, "leaving", stepLeaving, self)
end

-- shutdown(): the service is being switched off: every body is let go where it is (in sight, under
-- no order, possessable), every ambulance released, every list emptied. Nobody is cured by it.
function InfectionService.shutdown(self: Service)
	for _, id in table.clone(self.order) do
		local rec = self.records[id]
		if rec then
			pcall(standDown, self, rec)
			pcall(remove, self, rec)
		end
	end
	for id in table.clone(self.busy) do
		self.busy[id] = nil
		pcall(sink, self, id, false)
		pcall(order, self, id, {})
		pcall(self.setPossessable, id, true)
	end
	for id, l in table.clone(self.leaving) do
		pcall(arrived, self, id, l.away)
	end
	table.clear(self.records)
	table.clear(self.order)
	table.clear(self.queue)
	table.clear(self.scenes)
end

function InfectionService.isInfected(self: Service, id: number): boolean
	local rec = self.records[id]
	return rec ~= nil and InfectionRules.isInfected(rec.case)
end

-- biteable: may the rodent bite this person now? Not a patient on the ground, in transit or in a bed.
function InfectionService.biteable(self: Service, id: number): boolean
	local rec = self.records[id]
	if rec then
		return InfectionRules.biteable(rec.case)
	end
	local a = actorOf(self, id)
	return a ~= nil and a.species == "human" and (a.lift or 0) == 0
end

function InfectionService.stateOf(self: Service, id: number): string?
	local rec = self.records[id]
	return if rec then rec.case.state else nil
end

-- statusOf: what the status line of the player holding this body should say ("infected",
-- "symptoms", "treating"); nil for a body no player holds, or one that is not infected.
function InfectionService.statusOf(self: Service, id: number): string?
	local rec = self.records[id]
	if rec == nil or self.controllerOf(id) ~= "player" then
		return nil
	end
	return InfectionRules.status(rec.case)
end

-- townPercent: infected humans over all humans, in percent.
function InfectionService.townPercent(self: Service): number
	local humans = 0
	for _, a in self.world.actors do
		if a.species == "human" then
			humans += 1
		end
	end
	return InfectionRules.townPercent(#self.order, humans)
end

-- trafficFlags: true for people the emergency vehicles must not stop for: AICarMotor's `hospital`
-- flag, which in v5.4 marks the hospital's own people (staff, the ambulance crew, who work on the
-- very drive the responders start from) and anyone at a scene (the patient on the ground, the crowd
-- round them, the crew at work).
function InfectionService.trafficFlags(self: Service, id: number): boolean
	if self.busy[id] ~= nil then
		return true
	end
	local a = actorOf(self, id)
	if a and (a.post == "hospital_staff" or a.post == "ambulance_crew") then
		return true
	end
	local rec = self.records[id]
	return rec ~= nil and (InfectionRules.atScene(rec.case) or rec.case.state == "transit")
end

function InfectionService.cases(self: Service): { [number]: any }
	local out = {}
	for id, rec in self.records do
		out[id] = rec.case
	end
	return out
end

function InfectionService.stats(self: Service): { [string]: number }
	return self._stats
end

return InfectionService
