--!strict
-- ServerScriptService.Server.Stealth.OverheadService
-- The town's people notice, and talk about, a squirrel stalking above them (owner playtest 2026-11-19: "i would like
-- ... awareness and discussion and chatter, if i (spicy rodent) am prowling and stalking from above on a powerline or
-- branch etc."), on Stealth/OverheadWatch's rule. The alley's rafters keep their own watch (Attractions/RafterService):
-- a squirrel that one watches (`exclude`) is left to it.
-- Stepped from the game's step (Boot/Game) every frame; it works at TICK (5 Hz):
--   * the squirrels: the Spicy Rodent (a player's or the AI's) and the infected squirrels (Infection/InfectionService
--     :feared(): not one down a drain or in a hollow) that are OVERHEAD: at least C.minHeight over the ground on an
--     above-ground route (ABOVE: wires, fences, branches, bridges, roofs, the lookouts) or standing on anything else up
--     there (TOP: a truck's roof, a wall top: the motor stands on any colliding top, its packet names no route and says
--     it is grounded), or in the air off one for up to C.airGrace (a leap between them; its first tick back on one is a
--     landing). A leap from the ground (its top is about 7 studs) is neither. The route is the motor's (a held rodent:
--     `motorOf`, the validator's last clean packet; the AI: its rail intent); with no word on it the height alone
--     decides. So nothing over a person's head is left out: the duel leaves anything higher than duel.overheadY over a
--     person's feet to this watch (Combat/Duel.notices). A held body's speed is the fastest tenth of a second since the last tick (Stealth/Pace,
--     sampled every frame: tapping W is walking, as on the rafters); the AI's is its motor's. On a branch or a trunk the
--     leaves cover it (OverheadWatch C.canopy).
--   * the people: every AI townsperson, member of staff and officer (Pedestrian, Staff, Officer brains; not a patient,
--     not a body a player holds) within OverheadWatch.C.far of a squirrel overhead, found through a spatial grid
--     (Actors/Perception's) rebuilt only on a tick with a squirrel overhead. Each rates their best squirrel
--     (OverheadWatch.rate, their eye EYE_OVER_ROOT over the root, facing their yaw). Nothing solid between: no building
--     at eye height on the line to it (World/Colliders, the last C.edgeSlack studs at the squirrel's end left out, so a
--     squirrel on a roof's edge shows and one in the middle of the roof does not) and no Combat/Cover housing.
--   * the reactions, in OverheadWatch's stages (the body's Gaze is the point their head turns to, Client/Render/GazeView;
--     Gesture "point" raises the arm, Client/Render/StanceView):
--       glance  the head turns up to it;
--       look    they stop and look up (Pedestrian "overhead" stand; a member of staff pauses); at a creep, either may
--               come with a murmur ("overheadUneasy": "Did you hear something?");
--       spot    they point and say an "overhead" line, and tell the nearest person within C.tellRadius who has not
--               seen it: that one looks up at once and answers ("overheadReply") a moment later: the two-person
--               exchange (OverheadWatch.tell);
--       wary    by temperament (Combat/CombatService:temperOf when the duel runs): a vigilante or an officer waits below
--               it (closes in under it and stands there, C.waitSecs); a wary person keeps watching and calls others over
--               (an "overheadWary" line, and tells another neighbour); a calm one steps back from under it, then hurries
--               on along the lane;
--       lost    "where'd it go?" ("overheadLost"); away: the head turns back.
--     Nobody starts a fight here: the duel (Combat/CombatService) does that when the rodent comes down, and a person who
--     spotted it overhead meets it aware (`spotted`, CombatService opts.overhead).
--   * the chatter caps: one line a person every speech.actorCooldownS (12 s) and the town-wide window (3 lines in 5 s)
--     of its own Speech/SpeechRules state, and Speech/AreaPace: at most C.areaMax lines inside C.areaRadius studs in
--     any C.areaWindow seconds (an opener needs room for its answer too; the answer is forced so an exchange is never cut
--     in half). No line twice running (SpeechRules: not one of the last three said).
--   * the rodent's own player sees an eye (Client/UI/SneakMeter, the rafters' meter): `cue(rodentId, meter, seen)`, the
--     highest meter of anyone watching it and whether anyone has spotted it; (nil, nil) once it is not overhead.
-- Costs: no work at all on a tick with no squirrel overhead (the people's grid is not even built); with one, the grid of
-- the town's people (one set per person) and a few people near it rated, a building check each. stats().lastMs, peakMs
-- and busyMs say what the ticks took (tests/unit/overhead_service.spec.luau holds them under a budget with 60+ people).
-- Interface: TICK; C; EYE_OVER_ROOT; ABOVE; CANOPY; TOP; new(opts) -> Service; :step(dt); :spotted(personId, squirrelId) ->
--   boolean; :stageOf(personId) -> string; :overhead() -> { [id]: Overhead } (last tick's); :stats(); :stop()
-- Ids are TownAI actor ids. Positions in studs. No side effects on require.

local Import = require("../Import")
local OverheadWatch = Import.shared("Stealth/OverheadWatch") :: typeof(require("../../shared/Stealth/OverheadWatch"))
local Pace = Import.shared("Stealth/Pace") :: typeof(require("../../shared/Stealth/Pace"))
local SpeechRules = Import.shared("Speech/SpeechRules") :: typeof(require("../../shared/Speech/SpeechRules"))
local AreaPace = Import.shared("Speech/AreaPace") :: typeof(require("../../shared/Speech/AreaPace"))
local CombatRules = Import.shared("Combat/CombatRules") :: typeof(require("../../shared/Combat/CombatRules"))
local Cover = Import.shared("Combat/Cover") :: typeof(require("../../shared/Combat/Cover"))
local Colliders = Import.shared("World/Colliders") :: typeof(require("../../shared/World/Colliders"))
local Perception = require("../Actors/Perception")

local OverheadService = {}
OverheadService.__index = OverheadService

OverheadService.TICK = 0.2
OverheadService.EYE_OVER_ROOT = 1.6 -- a person's eye over their root (Attractions/RafterService's)
-- the route kinds that are off the ground (Routes/Registry kinds; "trunk" counts once it is high enough: a tree)
OverheadService.ABOVE = table.freeze({
	wire = true,
	fence = true,
	branch = true,
	bridge = true,
	roof = true,
	lookout = true,
	trunk = true,
}) :: { [string]: boolean }
OverheadService.CANOPY = table.freeze({ branch = true, trunk = true }) :: { [string]: boolean }
OverheadService.TOP = "top" -- the kind of a squirrel standing up high on no route (a vehicle's roof, a wall top)

OverheadService.C = {
	minHeight = 6, -- studs, feet over the ground: lower than this is the ground's perception (Actors/Perception)
	airGrace = 1.5, -- seconds in the air off a route that still count (a leap)
	bodyUp = 0.8, -- the squirrel's middle over its feet (what people look at)
	edgeSlack = 3, -- studs at the squirrel's end of the sight line not checked for buildings (a roof's edge)
	sightPad = 1.5, -- the sight line's half width against the buildings
	tellRadius = 25, -- studs: the neighbour told is this near the one who points (across a pavement and a lane)
	lookSecs = 2.5, -- stop and look up this long
	pointSecs = 2.5, -- the pointing arm
	waitSecs = 8, -- a vigilante or an officer waits below this long
	watchSecs = 4, -- a wary person keeps watching this long
	backSecs = 1.5, -- a calm person steps back from under it ...
	backSpeed = 5,
	hurrySecs = 8, -- ... then hurries on this long
	closeSpeed = 6, -- studs/s a vigilante closes in under it
	-- a person's Gaze (a replicated attribute) is written again only once the squirrel has moved more than gazeAngle off
	-- the way it was written, seen from their eye, and at most every gazeEvery seconds (a new squirrel, or none, at once):
	-- the client's neck eases between (Client/Render/GazeView). Network: 2 writes a second a person at most
	gazeAngle = math.rad(6),
	gazeEvery = 0.5,
	areaRadius = AreaPace.DEFAULTS.radius,
	areaWindow = AreaPace.DEFAULTS.window,
	areaMax = AreaPace.DEFAULTS.max,
}
local C = OverheadService.C

export type Opts = {
	world: any, -- AI/TownAI.World
	infection: any?, -- Infection/InfectionService (feared, engaged, isInfected, colliders)
	combat: any?, -- Combat/CombatService (temperOf, isVigilante)
	colliders: any?, -- World/Colliders (default infection.colliders)
	groundAt: ((x: number, z: number) -> number)?, -- default world.ctx.groundAt
	-- the held squirrel's validated motor (Movement/MovementService:motorOf): its route and whether it stands on
	-- something; nil when it has sent nothing
	motorOf: ((id: number) -> { routeId: number?, grounded: boolean? }?)?,
	exclude: ((id: number) -> boolean)?, -- a squirrel another watch has (the alley's rafters)
	setAttr: ((id: number, name: string, value: any) -> ())?, -- Say, SayAt, Gesture on a person's body
	gaze: ((id: number, x: number?, y: number?, z: number?) -> ())?, -- the point a person's head turns to (nil: none)
	cue: ((id: number, meter: number?, seen: boolean?) -> ())?, -- the rodent's own eye (held rodents only)
	serverTime: (() -> number)?, -- SayAt's clock (workspace:GetServerTimeNow)
	rand: (() -> number)?,
	speech: any?, -- a Speech/SpeechRules.State on the town's clock (default its own)
}

-- A squirrel overhead this tick (Stealth/OverheadWatch's Squirrel, written out: types do not cross Import, and the
-- route's kind and whether a player holds it).
export type Overhead = {
	id: any,
	x: number,
	y: number,
	z: number,
	speed: number,
	sprint: boolean?,
	canopy: boolean?,
	landed: boolean?,
	kind: string?,
	held: boolean,
}
type Event = { kind: string, person: any, squirrel: any, other: any? }
type Seen = { squirrel: any, rate: number, impulse: number, exposure: number, creep: boolean? }
type Observer = { id: any, x: number, y: number, z: number, faceX: number, faceZ: number }

type Sense = { lastOn: number, kind: string?, air: boolean }
type Gazed = { x: number, y: number, z: number, at: number, squirrel: any }

export type Stats = {
	ticks: number,
	busyTicks: number, -- ticks with a squirrel overhead
	rated: number, -- person-squirrel pairs rated
	glances: number,
	looks: number,
	spots: number,
	exchanges: number,
	uneasy: number, -- murmurs at a creep
	replies: number,
	wary: number,
	lost: number,
	lines: number,
	refused: number, -- lines the caps held back
	gazeWrites: number, -- Gaze attribute writes (each one replicates to every player)
	lastMs: number,
	peakMs: number,
	busyMs: number, -- all the ticks with a squirrel overhead, added up (busyMs / busyTicks: the mean)
}

local function clock(): number
	return os.clock()
end

function OverheadService.new(opts: Opts): any
	local world = opts.world
	local self = setmetatable({
		world = world,
		opts = opts,
		infection = opts.infection,
		combat = opts.combat,
		colliders = opts.colliders or (opts.infection and (opts.infection :: any).colliders),
		groundAt = opts.groundAt or world.ctx.groundAt,
		rand = opts.rand or math.random,
		speech = opts.speech or SpeechRules.new(),
		area = AreaPace.new({ radius = C.areaRadius, window = C.areaWindow, max = C.areaMax }),
		watch = OverheadWatch.new(),
		pace = Pace.new(),
		sense = {} :: { [number]: Sense },
		above = {} :: { [number]: Overhead }, -- last tick's squirrels overhead
		people = Perception.newGrid(16),
		inGrid = {} :: { [number]: boolean },
		buffer = {} :: { number },
		gazes = {} :: { [number]: Gazed }, -- person -> the point last written
		gazeWrites = 0, -- Gaze attribute writes (stats: the network's cost)
		gestures = {} :: { [number]: number }, -- person -> when the pointing arm comes down
		hurry = {} :: { [number]: { x: number, z: number, at: number } }, -- a calm person's hurry after backing off
		cued = {} :: { [number]: { meter: number?, seen: boolean? } },
		acc = 0,
		_stats = {
			ticks = 0,
			busyTicks = 0,
			rated = 0,
			glances = 0,
			looks = 0,
			spots = 0,
			exchanges = 0,
			uneasy = 0,
			replies = 0,
			wary = 0,
			lost = 0,
			lines = 0,
			refused = 0,
			gazeWrites = 0,
			lastMs = 0,
			peakMs = 0,
			busyMs = 0,
		} :: Stats,
	}, OverheadService)
	return self
end

local function now(self: any): number
	return self.world.now or 0
end

local function setAttr(self: any, id: number, name: string, value: any)
	local f = self.opts.setAttr
	if f then
		f(id, name, value)
	end
end

local function held(self: any, id: number): boolean
	return self.world.possessed[id] == true
end

-- the route a squirrel is on (nil: none, or no word), whether anything was known about it, and whether it stands on
-- something (a held squirrel's motor: grounded)
local function routeOf(self: any, a: any): (number?, boolean, boolean)
	if held(self, a.id) then
		local f = self.opts.motorOf
		local m = if f then f(a.id) else nil
		if m == nil then
			return nil, false, false
		end
		local r = m.routeId
		return if type(r) == "number" and r >= 0 then r else nil, true, m.grounded == true
	end
	local intent = a.intent
	if intent and intent.mode == "rail" then
		return intent.routeId, true, false
	end
	return nil, true, false
end

local function kindOf(self: any, routeId: number?): string?
	if routeId == nil then
		return nil
	end
	local routes = self.world.routes
	local r = if routes and routes.byId then routes.byId(routeId) else nil
	return if r then r.kind else nil
end

-- the squirrels overhead this tick
local function gather(self: any, t: number): { Overhead }
	local out: { Overhead } = {}
	local list: { any }
	if self.infection then
		list = self.infection:feared()
	else
		list = {}
		for _, a in self.world.actors do
			if a.species == "squirrel" and (a.variant == "spicy" or a.infected == true) and (a.lift or 0) == 0 then
				if self.world.covered == nil or self.world.covered[a.id] == nil then
					table.insert(list, a)
				end
			end
		end
	end
	local present: { [number]: boolean } = {}
	local exclude = self.opts.exclude
	for _, a in list do
		if exclude and exclude(a.id) then
			continue
		end
		local feet = a.y - a.hip
		local h = feet - self.groundAt(a.x, a.z)
		local routeId, known, grounded = routeOf(self, a)
		local kind = kindOf(self, routeId)
		if routeId == nil and grounded then
			kind = OverheadService.TOP -- (standing up high on no route)
		end
		local s = self.sense[a.id]
		local high = h >= C.minHeight
		local onRoute = high
			and (if known then kind == OverheadService.TOP or (kind ~= nil and OverheadService.ABOVE[kind] == true) else true)
		local inAir = not onRoute and high and routeId == nil and s ~= nil and t - s.lastOn <= C.airGrace
		local isHeld = held(self, a.id)
		local peak = if isHeld then Pace.take(self.pace, a.id) else nil
		if not (onRoute or inAir) then
			self.sense[a.id] = nil
			continue
		end
		present[a.id] = true
		local landed = onRoute and s ~= nil and s.air
		if onRoute then
			self.sense[a.id] = { lastOn = t, kind = kind, air = false }
		else
			(s :: Sense).air = true
		end
		local k = if onRoute then kind else (s :: Sense).kind
		local speed = peak or a.speed or 0
		local o: Overhead = {
			id = a.id,
			x = a.x,
			y = feet + C.bodyUp,
			z = a.z,
			speed = speed,
			sprint = false,
			canopy = k ~= nil and OverheadService.CANOPY[k] == true,
			landed = landed,
			kind = k,
			held = isHeld,
		}
		table.insert(out, o)
	end
	for id in self.sense do
		if not present[id] then
			self.sense[id] = nil
		end
	end
	return out
end

-- can this person take part (and be ordered): an AI person of the town, not a patient
local function person(self: any, a: any): boolean
	if a.species ~= "human" or (a.lift or 0) ~= 0 or held(self, a.id) then
		return false
	end
	local brain = self.world.brains[a.id]
	if brain == nil then
		return false
	end
	local k = brain.kind
	if k ~= "Pedestrian" and k ~= "Staff" and k ~= "Officer" then
		return false
	end
	if self.infection and self.infection:isInfected(a.id) then
		return false
	end
	return true
end

-- may this person be moved (not in the bite-to-hospital sequence's hands: the crowd only looks and talks)
local function free(self: any, id: number): boolean
	return not (self.infection and self.infection:engaged(id))
end

local function rebuildPeople(self: any)
	local grid = self.people
	local seen: { [number]: boolean } = {}
	for _, a in self.world.actors do
		if person(self, a) then
			grid:set(a.id, a.x, a.z)
			seen[a.id] = true
		end
	end
	for id in self.inGrid do
		if not seen[id] then
			grid:remove(id)
			OverheadWatch.forget(self.watch, id)
		end
	end
	self.inGrid = seen
end

local function eyeOf(a: any): number
	return a.y + OverheadService.EYE_OVER_ROOT
end

-- nothing solid between the person's eye and the squirrel
local function clear(self: any, a: any, s: Overhead): boolean
	local ey = eyeOf(a)
	if Cover.between(a.x, ey, a.z, s.x, s.y, s.z) then
		return false
	end
	local c = self.colliders
	if c == nil then
		return true
	end
	local dx, dz = s.x - a.x, s.z - a.z
	local d = math.sqrt(dx * dx + dz * dz)
	if d <= C.edgeSlack then
		return true
	end
	local k = (d - C.edgeSlack) / d
	return not Colliders.blocked(c, a.x, a.z, a.x + dx * k, a.z + dz * k, C.sightPad, ey)
end

-- a line from this person, under the caps; true when said
local function say(self: any, id: number, situation: string, force: boolean?, need: number?): boolean
	local a = self.world.actorsById[id]
	if a == nil then
		return false
	end
	local t = now(self)
	if not force and not AreaPace.allow(self.area, t, a.x, a.z, need) then
		self._stats.refused += 1
		return false
	end
	local line = SpeechRules.request(self.speech, t, id, situation, self.rand, { force = force })
	if line == nil then
		self._stats.refused += 1
		return false
	end
	AreaPace.note(self.area, t, a.x, a.z)
	setAttr(self, id, SpeechRules.ATTR.Say, line)
	local st = self.opts.serverTime
	setAttr(self, id, SpeechRules.ATTR.SayAt, if st then st() else t)
	self._stats.lines += 1
	return true
end

-- an order to the person's brain (never to one the bite-to-hospital sequence has)
local function order(self: any, id: number, mode: string, s: Overhead, secs: number, speed: number?)
	if not free(self, id) then
		return
	end
	local brain = self.world.brains[id] :: any
	if brain == nil then
		return
	end
	local untilTime = now(self) + secs
	if brain.kind == "Pedestrian" then
		brain:onEvent({ type = "overhead", mode = mode, x = s.x, z = s.z, speed = speed or 0, untilTime = untilTime })
	elseif brain.kind == "Staff" then
		if mode == "stand" then
			brain:onEvent({ type = "pause", seconds = secs })
		end
	elseif brain.kind == "Officer" then
		if mode == "approach" then
			brain:onEvent({ type = "respond", x = s.x, z = s.z, untilTime = untilTime })
		end
	end
end

local function temperOf(self: any, id: number): string
	local a = self.world.actorsById[id]
	if a and a.post == "police" then
		return "tough"
	end
	if self.combat then
		return self.combat:temperOf(id)
	end
	return CombatRules.temperament(id, false)
end

-- the nearest person within C.tellRadius of `id` who has not spotted it and is not answering someone
local function neighbour(self: any, id: number): number?
	local a = self.world.actorsById[id]
	if a == nil then
		return nil
	end
	local n = self.people:query(a.x, a.z, C.tellRadius, self.buffer)
	local best, bestD = nil, math.huge
	for i = 1, n do
		local other = self.buffer[i]
		if other ~= id then
			local tr = self.watch.tracks[other]
			if tr == nil or (tr.stage < 4 and tr.replyAt == nil) then
				local b = self.world.actorsById[other]
				local d = (b.x - a.x) ^ 2 + (b.z - a.z) ^ 2
				if d < bestD then
					best, bestD = other, d
				end
			end
		end
	end
	return best
end

-- the point a person's head turns to (nil: none), written under the C.gazeAngle / C.gazeEvery threshold
local function gaze(self: any, id: number, s: Overhead?)
	local f = self.opts.gaze
	if s == nil then
		if self.gazes[id] ~= nil then
			self.gazes[id] = nil
			self._stats.gazeWrites += 1
			if f then
				f(id, nil, nil, nil)
			end
		end
		return
	end
	local g = self.gazes[id]
	local t = now(self)
	if g and g.squirrel == s.id then
		if t - g.at < C.gazeEvery then
			return
		end
		-- (the angle between the way it was written and the way it is now, from their eye)
		local a = self.world.actorsById[id]
		if a then
			local ex, ey, ez = a.x, eyeOf(a), a.z
			local ux, uy, uz = g.x - ex, g.y - ey, g.z - ez
			local vx, vy, vz = s.x - ex, s.y - ey, s.z - ez
			local lu = math.sqrt(ux * ux + uy * uy + uz * uz)
			local lv = math.sqrt(vx * vx + vy * vy + vz * vz)
			if lu > 1e-6 and lv > 1e-6 then
				local cos = math.clamp((ux * vx + uy * vy + uz * vz) / (lu * lv), -1, 1)
				if math.acos(cos) <= C.gazeAngle then
					return
				end
			end
		end
	end
	local x, y, z = math.floor(s.x * 2 + 0.5) / 2, math.floor(s.y * 2 + 0.5) / 2, math.floor(s.z * 2 + 0.5) / 2
	self.gazes[id] = { x = x, y = y, z = z, at = t, squirrel = s.id }
	self._stats.gazeWrites += 1
	if f then
		f(id, x, y, z)
	end
end

local function point(self: any, id: number)
	self.gestures[id] = now(self) + C.pointSecs
	setAttr(self, id, "Gesture", "point")
end

-- a creep that made them glance or look up: a murmur ("Did you hear something?"), under the caps
local function uneasy(self: any, id: number, s: Overhead)
	if s.speed <= OverheadWatch.C.stalkSpeed and say(self, id, "overheadUneasy") then
		self._stats.uneasy += 1
	end
end

-- one event of the watch, acted on
local function act(self: any, e: Event, byId: { [number]: Overhead })
	local id = e.person :: number
	local s = byId[e.squirrel :: number] or self.above[e.squirrel :: number]
	local st = self._stats
	local kind = e.kind
	if kind == "glance" then
		st.glances += 1
		if s then
			gaze(self, id, s)
			uneasy(self, id, s)
		end
	elseif kind == "look" then
		st.looks += 1
		if s then
			gaze(self, id, s)
			order(self, id, "stand", s, C.lookSecs)
			uneasy(self, id, s)
		end
	elseif kind == "spot" then
		st.spots += 1
		if s == nil then
			return
		end
		gaze(self, id, s)
		point(self, id)
		order(self, id, "stand", s, C.pointSecs)
		-- the two-person exchange: room for the answer too
		if say(self, id, "overhead", false, 2) then
			local other = neighbour(self, id)
			if other and OverheadWatch.tell(self.watch, now(self), id, other, s.id) then
				st.exchanges += 1
				gaze(self, other, s)
				order(self, other, "stand", s, C.lookSecs)
			end
		end
	elseif kind == "reply" then
		st.replies += 1
		say(self, id, "overheadReply", true)
	elseif kind == "wary" then
		st.wary += 1
		if s == nil then
			return
		end
		local temper = temperOf(self, id)
		if temper == "tough" then
			-- waits below it (a vigilante, an officer): close in under it and stand there
			order(self, id, "approach", s, C.waitSecs, C.closeSpeed)
			say(self, id, "overheadWary")
		elseif temper == "wary" then
			-- keeps watching, and calls the others over
			order(self, id, "stand", s, C.watchSecs)
			if say(self, id, "overheadWary") then
				local other = neighbour(self, id)
				if other and OverheadWatch.tell(self.watch, now(self), id, other, s.id) then
					st.exchanges += 1
					gaze(self, other, s)
				end
			end
		else
			-- steps back from under it, then hurries on
			order(self, id, "back", s, C.backSecs, C.backSpeed)
			self.hurry[id] = { x = s.x, z = s.z, at = now(self) + C.backSecs }
		end
	elseif kind == "lost" then
		st.lost += 1
		gaze(self, id, nil)
		say(self, id, "overheadLost")
	elseif kind == "away" then
		gaze(self, id, nil)
	end
end

-- step(dt): every frame (a held squirrel overhead is sampled); a tick every TICK seconds
function OverheadService.step(self: any, dt: number)
	self.acc += dt
	for id, o in self.above do
		if o.held then
			local a = self.world.actorsById[id]
			if a then
				Pace.sample(self.pace, id, a.x, a.y, a.z, dt)
			end
		end
	end
	if self.acc < OverheadService.TICK then
		return
	end
	local tickDt = self.acc
	self.acc = 0
	self:_tick(tickDt)
end

function OverheadService._tick(self: any, dt: number)
	local t0 = clock()
	local st = self._stats
	st.ticks += 1
	local t = now(self)
	local above = gather(self, t)
	local byId: { [number]: Overhead } = {}
	for _, s in above do
		byId[s.id :: number] = s
	end
	for id in self.above do
		if byId[id] == nil then
			Pace.forget(self.pace, id)
		end
	end
	self.above = byId
	local seen: { [any]: Seen } = {}
	if #above > 0 then
		st.busyTicks += 1
		rebuildPeople(self)
		local actors = self.world.actorsById
		local stalk = OverheadWatch.C.stalkSpeed
		for _, s in above do
			local n = self.people:query(s.x, s.z, OverheadWatch.C.far, self.buffer)
			for i = 1, n do
				local a = actors[self.buffer[i]]
				if a == nil then
					continue
				end
				local obs: Observer = {
					id = a.id,
					x = a.x,
					y = eyeOf(a),
					z = a.z,
					faceX = math.sin(a.yaw),
					faceZ = math.cos(a.yaw),
				}
				local r, imp, e = OverheadWatch.rate(s, obs)
				st.rated += 1
				if e <= 0 then
					continue
				end
				local best = seen[a.id]
				if best and best.rate >= r then
					continue
				end
				if not clear(self, a, s) then
					continue
				end
				seen[a.id] = { squirrel = s.id, rate = r, impulse = imp, exposure = e, creep = s.speed <= stalk }
			end
		end
	end
	for _, e in OverheadWatch.step(self.watch, t, dt, seen) do
		act(self, e, byId)
	end
	-- the heads: up at the squirrel while glancing (for the glance's time), looking or spotted
	for id, tr in self.watch.tracks do
		local stage = OverheadWatch.stageOf(self.watch, id, t)
		local s = byId[tr.squirrel]
		if stage ~= "none" and s then
			gaze(self, id, s)
		elseif stage == "none" or tr.stage < 4 then
			gaze(self, id, nil)
		end
	end
	for id in self.gazes do
		if self.watch.tracks[id] == nil then
			gaze(self, id, nil)
		end
	end
	for id, untilT in self.gestures do
		if t >= untilT then
			self.gestures[id] = nil
			setAttr(self, id, "Gesture", nil)
		end
	end
	for id, h in self.hurry do
		if t >= h.at then
			self.hurry[id] = nil
			local brain = self.world.brains[id] :: any
			if brain and brain.kind == "Pedestrian" and free(self, id) then
				brain:onEvent({ type = "overhead", mode = "hurry", x = h.x, z = h.z, untilTime = t + C.hurrySecs })
			end
		end
	end
	-- the rodent's own eye
	local cue = self.opts.cue
	if cue then
		local want: { [number]: { meter: number?, seen: boolean? } } = {}
		for id, s in byId do
			if s.held then
				local m, seenIt = OverheadWatch.meterOf(self.watch, id)
				want[id] = { meter = math.floor(m * 100 + 0.5) / 100, seen = seenIt }
			end
		end
		for id in self.cued do
			if want[id] == nil then
				want[id] = { meter = nil, seen = nil }
			end
		end
		for id, w in want do
			local had = self.cued[id]
			if had == nil or had.meter ~= w.meter or had.seen ~= w.seen then
				cue(id, w.meter, w.seen)
			end
			self.cued[id] = if w.meter == nil then nil else w
		end
	end
	local ms = (clock() - t0) * 1000
	st.lastMs = ms
	st.peakMs = math.max(st.peakMs, ms)
	if #above > 0 then
		st.busyMs += ms
	end
end

-- spotted(personId, squirrelId): that person has pointed the squirrel out above them (Combat/Duel.notices: aware)
function OverheadService.spotted(self: any, personId: number, squirrelId: number): boolean
	return OverheadWatch.spotted(self.watch, personId, squirrelId)
end

function OverheadService.stageOf(self: any, personId: number): string
	return (OverheadWatch.stageOf(self.watch, personId, now(self)))
end

function OverheadService.overhead(self: any): { [number]: Overhead }
	return self.above
end

function OverheadService.stats(self: any): Stats
	return table.clone(self._stats)
end

-- stop(): every head, arm and eye let go
function OverheadService.stop(self: any)
	for id in table.clone(self.gazes) :: { [number]: any } do
		gaze(self, id, nil)
	end
	for id in self.gestures do
		setAttr(self, id, "Gesture", nil)
	end
	table.clear(self.gestures)
	local cue = self.opts.cue
	if cue then
		for id in self.cued do
			cue(id, nil, nil)
		end
	end
	table.clear(self.cued)
	self.watch = OverheadWatch.new()
end

return OverheadService
