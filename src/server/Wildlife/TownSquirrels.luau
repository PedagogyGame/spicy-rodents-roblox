--!strict
-- ServerScriptService.Server.Wildlife.TownSquirrels
-- The town's people and the ORDINARY squirrels (owner D21, 2026-11-21: "the regular squirrel should not be ran away
-- from by npcs, unless it jumps right on them or at them"). An ordinary squirrel is any squirrel that is not feared
-- (Actors/Species.feared: not the Spicy Rodent, not infected), a player's or the computer's. Nobody runs from one,
-- backs away, raises an alarm or calls anyone, whatever it does on its feet or over their heads (Brains/Pedestrian's
-- spot reaction, the bite-to-hospital sequence's crowd, the overhead watch and the duel are all for the feared ones).
-- What is left is here:
--   * JUMPED AT. A player's ordinary squirrel that leaps right on a person, or at them (Shared/Wildlife/JumpedAt: the
--     rule and its distances), makes that person start: a couple of quick steps away from it (a walker: Brains/Pedestrian
--     "jumpedAt"; a member of staff pauses; a rider and an officer keep going), the arms up for a moment (the body's
--     Gesture "flinch": Client/Render/StanceView) and a yelp (Speech/Lines "jumpedAt"). Then they carry on. No alert,
--     no report, no police, no crowd, and the caps keep it small (JumpedAt.allow: once a person every 20 s, three
--     people a squirrel in any 10 s). The leap is the server's own: the body is in the air while its last accepted
--     motor packet says it is off its feet and off every rail (opts.airborne: Movement/MovementService.motorOf), and
--     its launch, its places in the air and its landing are the places the server holds for it (the AI world's record
--     of a held squirrel, fed from Movement/MovementService.heldPlace: invariant D), never its root. The computer's
--     squirrels keep to their rails and never leap at anyone.
--   * A GLANCE AND A WORD. Now and then someone with an ordinary squirrel on the ground before them turns their head
--     to it for a moment (the body's Gaze, Client/Render/GazeView) and may say something friendly (Speech/Lines
--     "squirrelNear"), under the town's one speech pacing (Speech/SpeechRules: a person's cooldown, the town's window,
--     the cap by place) and this service's own (C.glance*). They keep walking their way.
-- People another service has in hand (opts.busy: a patient or the crowd of the bite-to-hospital sequence, someone in
-- the duel, someone watching the rodent overhead), anyone a player holds, and anyone hidden are left alone.
-- Costs: a frame with no player's ordinary squirrel in the air does two table lookups a held squirrel; a leap rates the
-- people within C.reach of its launch (found once, at the launch) each time the held place moves; the glance looks
-- once a second, and only when an ordinary squirrel is low to the ground (stats().lastMs, peakMs).
-- Interface: C; new(opts) -> Service; :step(dt); :stats(); :stop() (every Gesture and Gaze it set is taken back);
--   airborne(snapshot, age) -> boolean? (pure: a motor packet's word on the leap, for opts.airborne)
-- Ids are TownAI actor ids. Studs. Step-driven: requiring this module starts nothing.

local Import = require("../Import")
local JumpedAt = Import.shared("Wildlife/JumpedAt") :: typeof(require("../../shared/Wildlife/JumpedAt"))
local Species = Import.shared("Actors/Species") :: typeof(require("../../shared/Actors/Species"))
local SpeechRules = Import.shared("Speech/SpeechRules") :: typeof(require("../../shared/Speech/SpeechRules"))

export type Opts = {
	world: any, -- AI/TownAI.World
	speech: any?, -- the town's one Speech/SpeechRules state (nil: nobody says anything)
	-- is this squirrel in the air (off its feet and off every rail) by the server's last accepted word on it? nil: no
	-- word (nobody holds it, no packet yet, a stale one): nothing of it is judged
	airborne: (id: number) -> boolean?,
	busy: ((personId: number) -> boolean)?,
	setAttr: ((id: number, name: string, value: any) -> ())?,
	-- the point a person's head turns to (the body's Gaze: a Vector3 in the engine), or none
	gaze: ((id: number, x: number?, y: number?, z: number?) -> ())?,
	serverTime: (() -> number)?, -- SayAt's clock (default: the town's)
	rand: (() -> number)?,
}

export type Stats = {
	leaps: number, -- leaps followed
	starts: number, -- people who started at one
	glances: number,
	words: number,
	lastMs: number,
	peakMs: number,
}

type Leap = { flight: any, people: { number }, done: { [number]: boolean } }

local TownSquirrels = {}
TownSquirrels.__index = TownSquirrels

TownSquirrels.C = table.freeze({
	reach = 45, -- studs round a launch the people a leap may reach are looked for in
	backSecs = 0.6, -- a walker's quick steps away ...
	backSpeed = 6, -- ... at this pace (about 3.5 studs in all)
	flinchSecs = 0.8, -- the arms up
	-- the glance: once every glanceEvery seconds, a person with an ordinary squirrel within glanceRadius, in view and
	-- no higher than glanceHeight over the ground, turns their head to it with chance glanceChance, for glanceSecs,
	-- and not again for glanceRest seconds; one glance in wordShare comes with a word (if the town's pacing has room)
	fresh = 0.5, -- seconds: a motor packet older than this says nothing about a leap (airborne)
	glanceEvery = 1,
	glanceRadius = 12,
	glanceHeight = 4,
	glanceChance = 0.3,
	glanceSecs = 1.5,
	glanceRest = 12,
	glanceView = 0.28, -- the view cone's dot (Actors/Perception's)
	wordShare = 0.25,
	wordRest = 45, -- seconds before the same person has another friendly word
	eye = 1.2, -- studs over a squirrel's feet a head turns to
})

local C = TownSquirrels.C

-- airborne(snapshot, age): what a held squirrel's last accepted motor packet (Movement/MovementService.motorOf: its
-- snapshot, and how many seconds ago it came in) says of a leap: in the air when it stands on nothing and is on no
-- rail. nil with no packet or one older than C.fresh (a silent client says nothing). Pure
function TownSquirrels.airborne(snapshot: { [string]: any }?, age: number?): boolean?
	if snapshot == nil or age == nil or age > C.fresh then
		return nil
	end
	local route = snapshot.routeId
	return snapshot.grounded ~= true and not (type(route) == "number" and route >= 0)
end

function TownSquirrels.new(opts: Opts)
	return setmetatable({
		opts = opts,
		world = opts.world,
		rand = opts.rand or math.random,
		book = JumpedAt.newBook(),
		leaps = {} :: { [number]: Leap },
		ground = {} :: { [number]: { number } }, -- a held squirrel's last place on its feet
		flinch = {} :: { [number]: number }, -- person -> when the arms come down
		gaze = {} :: { [number]: number }, -- person -> when the head turns back
		glanceAt = {} :: { [number]: number }, -- person -> no glance before
		wordAt = {} :: { [number]: number }, -- person -> no friendly word before
		acc = 0,
		_stats = { leaps = 0, starts = 0, glances = 0, words = 0, lastMs = 0, peakMs = 0 } :: Stats,
	}, TownSquirrels)
end

local function setAttr(self: any, id: number, name: string, value: any)
	local f = self.opts.setAttr
	if f then
		f(id, name, value)
	end
end

local function gaze(self: any, id: number, x: number?, y: number?, z: number?)
	local f = self.opts.gaze
	if f then
		f(id, x, y, z)
	end
end

-- a townsperson, a member of staff or an officer the computer walks, in sight, in nobody else's hands
local function person(self: any, a: any): boolean
	if a.species ~= "human" or (a.lift or 0) ~= 0 or self.world.possessed[a.id] then
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
	-- (someone running from the rodent or standing in a crowd has other things on their mind)
	if brain.state == "flee" or brain.state == "gather" then
		return false
	end
	local busy = self.opts.busy
	return not (busy and busy(a.id))
end

-- an ordinary squirrel in the open (not the Spicy Rodent, not infected, not down a drain or in a hollow, not one
-- taken off the road: Wildlife/RoadSquirrels)
local function ordinary(self: any, a: any): boolean
	return a.species == "squirrel"
		and not Species.feared(a)
		and a.gone ~= true
		and (a.lift or 0) == 0
		and self.world.covered[a.id] == nil
end

local function say(self: any, id: number, situation: string, force: boolean): boolean
	local speech = self.opts.speech
	local a = self.world.actorsById[id]
	if speech == nil or a == nil then
		return false
	end
	local t = self.world.now
	local line = SpeechRules.request(speech, t, id, situation, self.rand, { force = force, x = a.x, z = a.z })
	if line == nil then
		return false
	end
	setAttr(self, id, SpeechRules.ATTR.Say, line)
	local st = self.opts.serverTime
	setAttr(self, id, SpeechRules.ATTR.SayAt, if st then st() else t)
	return true
end

-- a person starts at the squirrel that jumped on them or at them
local function start(self: any, p: any, s: any)
	local now = self.world.now
	if not person(self, p) or not JumpedAt.allow(self.book, p.id, s.id, now) then
		return
	end
	local brain = self.world.brains[p.id] :: any
	if brain.kind == "Pedestrian" then
		brain:onEvent({ type = "jumpedAt", x = s.x, z = s.z, speed = C.backSpeed, untilTime = now + C.backSecs })
	elseif brain.kind == "Staff" then
		brain:onEvent({ type = "pause", seconds = C.backSecs })
	end
	setAttr(self, p.id, "Gesture", "flinch")
	self.flinch[p.id] = now + C.flinchSecs
	say(self, p.id, "jumpedAt", true)
	self._stats.starts += 1
end

-- the leaps of the players' ordinary squirrels, every frame
local function follow(self: any)
	local world = self.world
	local airborne = self.opts.airborne
	for id in world.possessed do
		local s = world.actorsById[id]
		if s == nil or s.species ~= "squirrel" then
			continue
		end
		local air = if ordinary(self, s) then airborne(id) else nil
		local leap = self.leaps[id]
		if air == nil then
			self.leaps[id] = nil
			self.ground[id] = nil
			continue
		end
		local x, y, z = s.x, s.y - s.hip, s.z
		if air then
			if leap == nil then
				-- the launch: the last place it stood (the first place in the air when there is none)
				local g = self.ground[id]
				local flight = JumpedAt.launch(if g then g[1] else x, if g then g[2] else y, if g then g[3] else z)
				local people = {}
				for _, a in world.actors do
					if a.species == "human" and (a.x - flight.x0) ^ 2 + (a.z - flight.z0) ^ 2 <= C.reach * C.reach then
						table.insert(people, a.id)
					end
				end
				leap = { flight = flight, people = people, done = {} }
				self.leaps[id] = leap
				self._stats.leaps += 1
			end
			local f = leap.flight
			if x ~= f.x or y ~= f.y or z ~= f.z then
				for _, pid in leap.people do
					local p = world.actorsById[pid]
					if p and not leap.done[pid] and JumpedAt.passes(f, x, y, z, p.x, p.y - p.hip, p.z) then
						leap.done[pid] = true
						start(self, p, s)
					end
				end
				JumpedAt.advance(f, x, y, z)
			end
		else
			if leap then
				-- the landing
				local f = leap.flight
				for _, pid in leap.people do
					local p = world.actorsById[pid]
					if p and not leap.done[pid] then
						local feet = p.y - p.hip
						if
							JumpedAt.passes(f, x, y, z, p.x, feet, p.z) or JumpedAt.lands(f, x, y, z, p.x, feet, p.z)
						then
							start(self, p, s)
						end
					end
				end
				self.leaps[id] = nil
			end
			local g = self.ground[id]
			if g == nil then
				g = { x, y, z }
				self.ground[id] = g
			else
				g[1], g[2], g[3] = x, y, z
			end
		end
	end
	-- (a body let go: its leap is nobody's)
	for id in self.leaps do
		if not world.possessed[id] then
			self.leaps[id] = nil
			self.ground[id] = nil
		end
	end
end

-- a glance, and now and then a friendly word, for an ordinary squirrel on the ground near someone
local function glances(self: any)
	local world = self.world
	local now = world.now
	local low: { any } = {}
	for _, a in world.actors do
		if ordinary(self, a) and (a.y - a.hip) - world.ctx.groundAt(a.x, a.z) <= C.glanceHeight then
			table.insert(low, a)
		end
	end
	if #low == 0 then
		return
	end
	local r2 = C.glanceRadius * C.glanceRadius
	for _, p in world.actors do
		if p.species ~= "human" or (self.glanceAt[p.id] or 0) > now then
			continue
		end
		local best, bestD = nil, r2
		for _, s in low do
			local dx, dz = s.x - p.x, s.z - p.z
			local d = dx * dx + dz * dz
			if d <= bestD and d > 1e-6 then
				local dot = (dx * math.sin(p.yaw) + dz * math.cos(p.yaw)) / math.sqrt(d)
				if dot > C.glanceView then
					best, bestD = s, d
				end
			end
		end
		if best == nil or not person(self, p) then
			continue
		end
		-- (the dice are thrown only for someone with a squirrel before them: the rest of the town costs nothing)
		self.glanceAt[p.id] = now + C.glanceEvery
		if self.rand() >= C.glanceChance then
			continue
		end
		self.glanceAt[p.id] = now + C.glanceRest
		self.gaze[p.id] = now + C.glanceSecs
		gaze(self, p.id, best.x, best.y - best.hip + C.eye, best.z)
		self._stats.glances += 1
		if (self.wordAt[p.id] or 0) <= now and self.rand() < C.wordShare then
			if say(self, p.id, "squirrelNear", false) then
				self.wordAt[p.id] = now + C.wordRest
				self._stats.words += 1
			end
		end
	end
end

function TownSquirrels.step(self: any, dt: number)
	local t0 = os.clock()
	local now = self.world.now
	for id, untilTime in self.flinch do
		if now >= untilTime then
			self.flinch[id] = nil
			setAttr(self, id, "Gesture", nil)
		end
	end
	for id, untilTime in self.gaze do
		if now >= untilTime then
			self.gaze[id] = nil
			gaze(self, id, nil, nil, nil)
		end
	end
	follow(self)
	self.acc += dt
	if self.acc >= C.glanceEvery then
		self.acc = 0
		glances(self)
	end
	local ms = (os.clock() - t0) * 1000
	self._stats.lastMs = ms
	self._stats.peakMs = math.max(self._stats.peakMs, ms)
end

function TownSquirrels.stats(self: any): Stats
	return table.clone(self._stats)
end

function TownSquirrels.stop(self: any)
	for id in self.flinch do
		setAttr(self, id, "Gesture", nil)
	end
	for id in self.gaze do
		gaze(self, id, nil, nil, nil)
	end
	table.clear(self.flinch)
	table.clear(self.gaze)
	table.clear(self.leaps)
end

return TownSquirrels
