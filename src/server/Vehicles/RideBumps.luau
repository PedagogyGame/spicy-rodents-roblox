--!strict
-- ServerScriptService.Server.Vehicles.RideBumps
-- The town's shared little vehicles and the people and squirrels in their way (owner D29: "prepare most carefully, the
-- dynamics, physics and scene of being hit by a ..."; the lead's reading: people dodge an oncoming one; one that is hit
-- is knocked aside, stumbles or falls and gets back up; mild, no gore). The rules and numbers are Shared/Vehicles/
-- SharedRides'; this service applies them to the town, the way the other people services do (Wildlife/TownSquirrels):
-- the computer's people are kinematic and moved here through their brain's order (Brains/Directive, the same
-- "medical" order every human brain takes: `hold` to step aside, `down` to lie still, cleared to walk on), a body a
-- player holds is moved by its own client (opts.knockHeld: Boot/Game writes the body's Knock attributes, which
-- Client/Controllers/Human turns into the tumble; a player's squirrel is put aside the bowling alley's way and dazed).
--   * DODGE. A townsperson, a member of staff or an officer the computer walks who is in the way of a moving shared
--     vehicle (SharedRides.oncoming) steps or hops aside, square to its way, to the side they are on (SharedRides.
--     dodgeTo, only along a clear line: World/WalkWay through the town's ctx.clear; the other side if that one is
--     not clear), faces it a moment and walks on; the arms come up (Gesture "flinch") and now and then a startled
--     word (Speech/Lines "rideClose"). SharedRides.C.dodgeChance of them do: the rest freeze, and may be bumped.
--   * BUMPED. A person it meets (SharedRides.hit) is knocked aside along its way and to their side (SharedRides.knock:
--     a short slide, along a clear line only); from SharedRides.C.fallSpeed they fall and stay down a moment (the
--     body's Tumble "down": Client/Animation/AnimationDriver sits them on the ground as a patient sits, legs out),
--     slower they stagger (Gesture "flinch"); then up and on their way (the order is cleared: Brains/Pedestrian walks
--     back to its lane). A word of surprise (Speech/Lines "bumped"). Never killed, never a patient, no police, no crowd,
--     nothing left on the ground. The rider feels it (opts.bump: the vehicle slows). Once per person per
--     SharedRides.C.cooldown seconds.
--   * SQUIRRELS. A player's squirrel or the rodent it meets is knocked aside the same mild way (opts.knockHeld) and
--     never run over (the traffic's fatal sweep is the AI fleet's: Traffic/TrafficService never sees a player's
--     vehicle). The computer's squirrels in its way skitter off along their rails (Brains/Squirrel "startle").
-- People another service has in hand (opts.busy: a patient, the crowd, the duel, the overhead watch; a person whose
-- brain already has an order, someone fleeing or in a crowd), a rider on a bicycle and anyone hidden are left alone:
-- at most the arms come up. Places are the AI world's (a held squirrel's is its validated place, never its root).
-- Costs: a frame with no shared vehicle moving does one call to opts.rides; each moving one looks at the actors within
-- REACH of it (two compares for the rest of the town): with every shared vehicle moving about 1,000 cheap compares a
-- frame (stats().lastMs, peakMs).
-- Interface: new(opts) -> Service; :step(dt); :stats() -> Stats; :stop() (every order, Tumble and Gesture it set is
--   taken back). Ids are TownAI actor ids; studs. Step-driven: requiring this module starts nothing.

local Import = require("../Import")
local SharedRides = Import.shared("Vehicles/SharedRides") :: typeof(require("../../shared/Vehicles/SharedRides"))
local SpeechRules = Import.shared("Speech/SpeechRules") :: typeof(require("../../shared/Speech/SpeechRules"))
local Common = require("../Actors/Brains/Common")
local Directive = require("../Actors/Brains/Directive")

-- A shared vehicle being ridden, as Boot/Game reads it each frame (SharedRides.Ride and its device id)
-- (exported types do not cross Import: Shared/Vehicles/SharedRides.Ride and .Knock restated)
export type Ride = {
	id: string,
	kind: string,
	x: number,
	z: number,
	floor: number,
	yaw: number,
	vx: number,
	vz: number,
}
export type Knock = { dx: number, dz: number, fall: boolean, secs: number }

export type Opts = {
	world: any, -- AI/TownAI.World
	rides: () -> { Ride },
	speech: any?, -- the town's one Speech/SpeechRules state (nil: nobody says anything)
	busy: ((id: number) -> boolean)?,
	aboard: ((id: number) -> boolean)?, -- a body a player holds that is aboard a vehicle (never in one's way)
	setAttr: ((id: number, name: string, value: any) -> ())?,
	-- a body a player holds was bumped by a `kind`: knock it on its own client (a person) or put it aside (a squirrel);
	-- the knock's slide is already cut short of any wall
	knockHeld: ((id: number, knock: Knock, squirrel: boolean, kind: string) -> ())?,
	bump: ((rideId: string) -> ())?, -- the rider feels it
	serverTime: (() -> number)?,
	rand: (() -> number)?,
}

export type Stats = {
	dodges: number, -- people who stepped aside
	froze: number, -- people in the way who did not
	knocks: number, -- people bumped (fell or staggered)
	falls: number,
	squirrels: number, -- squirrels bumped aside or skittering off
	lastMs: number,
	peakMs: number,
}

-- An order this service gave a person: when it ends, the order's number on their brain (cleared only if still ours),
-- and a knock's slide
type Order = {
	upAt: number,
	seq: number,
	fromX: number,
	fromZ: number,
	toX: number,
	toZ: number,
	t0: number,
	tumble: boolean,
}

local RideBumps = {}
RideBumps.__index = RideBumps

RideBumps.REACH = 40 -- studs round a moving shared vehicle its people and squirrels are looked at
RideBumps.FLINCH_SECS = 0.6

local C = SharedRides.C

function RideBumps.new(opts: Opts)
	return setmetatable({
		opts = opts,
		world = opts.world,
		rand = opts.rand or math.random,
		knockBook = SharedRides.newBook(),
		dodgeBook = SharedRides.newBook(),
		orders = {} :: { [number]: Order },
		flinch = {} :: { [number]: number },
		_stats = { dodges = 0, froze = 0, knocks = 0, falls = 0, squirrels = 0, lastMs = 0, peakMs = 0 } :: Stats,
	}, RideBumps)
end

local function setAttr(self: any, id: number, name: string, value: any)
	local f = self.opts.setAttr
	if f then
		f(id, name, value)
	end
end

local function flinch(self: any, id: number)
	setAttr(self, id, "Gesture", "flinch")
	self.flinch[id] = self.world.now + RideBumps.FLINCH_SECS
end

local function say(self: any, id: number, situation: string)
	local speech = self.opts.speech
	local a = self.world.actorsById[id]
	if speech == nil or a == nil then
		return
	end
	local t = self.world.now
	local line = SpeechRules.request(speech, t, id, situation, self.rand, { x = a.x, z = a.z })
	if line == nil then
		return
	end
	setAttr(self, id, SpeechRules.ATTR.Say, line)
	local st = self.opts.serverTime
	setAttr(self, id, SpeechRules.ATTR.SayAt, if st then st() else t)
end

-- a person the computer walks, in sight, free for an order of ours: nobody another service has in hand, no rider
local function free(self: any, a: any): boolean
	if (a.lift or 0) ~= 0 or self.world.possessed[a.id] or self.orders[a.id] then
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
	if brain.params and brain.params.cyclist == true then
		return false -- (a rider rides on)
	end
	if brain.state == "flee" or brain.state == "gather" or brain.state == "duel" then
		return false
	end
	if brain.directive and Directive.active(brain.directive) then
		return false -- (a patient, a bystander, someone walked home: the medical sequence's)
	end
	local busy = self.opts.busy
	return not (busy and busy(a.id))
end

-- give the person an order now (the brain may think as rarely as its LOD tier: the intent is written at once too)
local function order(self: any, a: any, evt: { [string]: any }): number
	local brain = self.world.brains[a.id] :: any
	brain:onEvent(evt)
	Common.halt(a)
	Directive.think(brain.directive, a, 0, self.world.ctx)
	return brain.directive.seq
end

-- clear our order (only if it is still ours: another service may have given one since)
local function release(self: any, id: number, o: Order)
	local brain = self.world.brains[id] :: any
	if brain and brain.directive and brain.directive.seq == o.seq then
		brain:onEvent({ type = "medical" })
	end
	if o.tumble then
		setAttr(self, id, "Tumble", nil)
	end
end

-- the farthest of the whole way, half of it or none that is a clear line from (x, z)
local function clearTo(self: any, x: number, z: number, tx: number, tz: number): (number, number)
	local clear = self.world.ctx.clear
	if clear == nil or clear(x, z, tx, tz) then
		return tx, tz
	end
	local hx, hz = (x + tx) / 2, (z + tz) / 2
	if clear(x, z, hx, hz) then
		return hx, hz
	end
	return x, z
end

local function dodge(self: any, a: any, ride: Ride, side: number)
	local now = self.world.now
	if not free(self, a) or not SharedRides.allow(self.dodgeBook, a.id, now, C.dodgeRest) then
		return
	end
	if self.rand() >= C.dodgeChance then
		-- frozen to the spot: the arms up, and it may bump them
		flinch(self, a.id)
		self._stats.froze += 1
		return
	end
	local clear = self.world.ctx.clear
	local sign = SharedRides.dodgeSide(side, self.rand)
	local tx, tz = SharedRides.dodgeTo(ride, a.x, a.z, C.personR, sign)
	if clear and not clear(a.x, a.z, tx, tz) then
		sign = -sign
		tx, tz = SharedRides.dodgeTo(ride, a.x, a.z, C.personR, sign)
		if not clear(a.x, a.z, tx, tz) then
			flinch(self, a.id) -- (nowhere to go)
			self._stats.froze += 1
			return
		end
	end
	local seq = order(
		self,
		a,
		{ type = "medical", mode = "hold", x = tx, z = tz, speed = C.dodgeSpeed, faceX = ride.x, faceZ = ride.z }
	)
	self.orders[a.id] = {
		upAt = now + C.dodgeSecs,
		seq = seq,
		fromX = a.x,
		fromZ = a.z,
		toX = a.x,
		toZ = a.z,
		t0 = now,
		tumble = false,
	}
	flinch(self, a.id)
	self._stats.dodges += 1
	if self.rand() < C.lineChance then
		say(self, a.id, "rideClose")
	end
end

-- a knock for a body a player holds, its slide cut short of any wall, handed to Boot/Game
local function knockHeld(self: any, a: any, ride: Ride, squirrel: boolean): Knock
	local k = SharedRides.knock(ride, a.x, a.z)
	local tx, tz = clearTo(self, a.x, a.z, a.x + k.dx, a.z + k.dz)
	k.dx, k.dz = tx - a.x, tz - a.z
	local held = self.opts.knockHeld
	if held then
		held(a.id, k, squirrel, ride.kind)
	end
	return k
end

local function bumpPerson(self: any, a: any, ride: Ride)
	local now = self.world.now
	if not SharedRides.allow(self.knockBook, a.id, now, C.cooldown) then
		return
	end
	local bump = self.opts.bump
	if self.world.possessed[a.id] then
		local k = knockHeld(self, a, ride, false)
		self._stats.knocks += 1
		if k.fall then
			self._stats.falls += 1
		end
		if bump then
			bump(ride.id)
		end
		return
	end
	local mine = self.orders[a.id]
	if mine then
		-- (bumped mid-dodge: the dodge gives way to the knock)
		self.orders[a.id] = nil
		release(self, a.id, mine)
	end
	if not free(self, a) then
		flinch(self, a.id) -- (another service's: the arms up, no more)
		return
	end
	if bump then
		bump(ride.id)
	end
	local k = SharedRides.knock(ride, a.x, a.z)
	local tx, tz = clearTo(self, a.x, a.z, a.x + k.dx, a.z + k.dz)
	local seq = order(self, a, { type = "medical", mode = "down", faceX = ride.x, faceZ = ride.z })
	self.orders[a.id] =
		{ upAt = now + k.secs, seq = seq, fromX = a.x, fromZ = a.z, toX = tx, toZ = tz, t0 = now, tumble = k.fall }
	if k.fall then
		setAttr(self, a.id, "Tumble", "down")
		self._stats.falls += 1
	else
		flinch(self, a.id)
	end
	self._stats.knocks += 1
	say(self, a.id, "bumped")
end

local function bumpSquirrel(self: any, a: any, ride: Ride, hit: boolean)
	local now = self.world.now
	if self.world.possessed[a.id] then
		-- (only a hit counts for a player's: they skitter by themselves)
		if hit and SharedRides.allow(self.knockBook, a.id, now, C.cooldown) then
			knockHeld(self, a, ride, true)
			self._stats.squirrels += 1
			local bump = self.opts.bump
			if bump then
				bump(ride.id)
			end
		end
		return
	end
	-- the computer's skitter off along their rails (one on its dash across a road runs on regardless)
	if SharedRides.allow(self.dodgeBook, a.id, now, C.dodgeRest) then
		local brain = self.world.brains[a.id]
		if brain then
			brain:onEvent({ type = "startle", x = ride.x, z = ride.z })
		end
		self._stats.squirrels += 1
	end
end

local function look(self: any, ride: Ride)
	local world = self.world
	local R = RideBumps.REACH
	local aboard = self.opts.aboard
	for _, a in world.actors do
		if math.abs(a.x - ride.x) > R or math.abs(a.z - ride.z) > R or (a.lift or 0) ~= 0 then
			continue
		end
		if world.possessed[a.id] and aboard and aboard(a.id) then
			continue -- (the rider, or a driver passing by)
		end
		local feet = a.y - a.hip
		if a.species == "human" then
			if SharedRides.hit(ride, a.x, a.z, feet, C.personR) then
				bumpPerson(self, a, ride)
			elseif not world.possessed[a.id] and math.abs(feet - ride.floor) <= C.reachUp then
				if SharedRides.oncoming(ride, a.x, a.z, C.personR) then
					local _, side = SharedRides.frame(ride, a.x, a.z)
					dodge(self, a, ride, side)
				end
			end
		elseif (a.species == "squirrel" or a.species == "rodent") and a.gone ~= true then
			if SharedRides.hit(ride, a.x, a.z, feet, C.squirrelR) then
				bumpSquirrel(self, a, ride, true)
			elseif
				not world.possessed[a.id]
				and math.abs(feet - ride.floor) <= C.reachUp
				and SharedRides.oncoming(ride, a.x, a.z, C.squirrelR)
			then
				bumpSquirrel(self, a, ride, false)
			end
		end
	end
end

function RideBumps.step(self: any, _dt: number)
	local t0 = os.clock()
	local world = self.world
	local now = world.now
	for id, untilTime in self.flinch do
		if now >= untilTime then
			self.flinch[id] = nil
			setAttr(self, id, "Gesture", nil)
		end
	end
	for id, o in self.orders do
		local a = world.actorsById[id]
		if a == nil or world.possessed[id] then
			-- (taken by a player mid-knock: theirs now, and the order is cleared so the brain does not keep it for when
			-- they let go: AI/TownAI.resume snapshots the brain as it is then)
			self.orders[id] = nil
			release(self, id, o)
			continue
		end
		if o.toX ~= o.fromX or o.toZ ~= o.fromZ then
			-- the knock's slide, easing out
			local u = math.clamp((now - o.t0) / C.slideSecs, 0, 1)
			local e = 1 - (1 - u) * (1 - u)
			a.x = o.fromX + (o.toX - o.fromX) * e
			a.z = o.fromZ + (o.toZ - o.fromZ) * e
			a.y = world.ctx.groundAt(a.x, a.z) + a.hip
			if u >= 1 then
				o.fromX, o.fromZ = o.toX, o.toZ
			end
		end
		if now >= o.upAt then
			self.orders[id] = nil
			release(self, id, o)
		end
	end
	for _, ride in self.opts.rides() do
		local speed = math.sqrt(ride.vx * ride.vx + ride.vz * ride.vz)
		if speed >= C.minSpeed then
			look(self, ride)
		end
	end
	local ms = (os.clock() - t0) * 1000
	self._stats.lastMs = ms
	self._stats.peakMs = math.max(self._stats.peakMs, ms)
end

function RideBumps.stats(self: any): Stats
	return table.clone(self._stats)
end

function RideBumps.stop(self: any)
	for id, o in self.orders do
		release(self, id, o)
	end
	for id in self.flinch do
		setAttr(self, id, "Gesture", nil)
	end
	table.clear(self.orders)
	table.clear(self.flinch)
end

return RideBumps
