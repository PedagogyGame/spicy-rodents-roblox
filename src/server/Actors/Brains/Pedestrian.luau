--!strict
-- ServerScriptService.Server.Actors.Brains.Pedestrian
-- Pedestrian brain, minimal W0 version (spike S5): sidewalk-lane walking with goals, the v5.4 spot
-- reaction (flee along the lane for 8 s), traffic-free, plus a "gather" event (fender-bender
-- bystanders). Numbers from humans_actors §4.2-§4.3 (lanes 12.1 u off the road centreline, goal step
-- R(37, 95) u, new goal within 1.7 u, inward beyond +/-225 u, clamp [-260, 260] u; speeds walk
-- R(0.8, 1.6), cyclist R(3.2, 5.2), flee 7.1 u/s) and §5.2 (alert 8, return to walk under 2).
-- The bite-to-hospital sequence (owner 2026-11-10) adds: a Directive (Brains/Directive: down, hidden,
-- route, hold) that overrides everything while it is set; the events "medical" (set or clear the
-- directive), "bitten" and "witness" (run from `threat` along the lane), "alarm" (someone collapsed
-- nearby: a person already running keeps running, nobody else is touched); an optional
-- ctx.emit("spotted", actor, threat) when a spot starts a flee, so the server can let some people
-- say something; and the "rejoin" state: after a directive, a gathering or a player letting go far
-- from the lane, the person adopts the nearest lane and WALKS back onto it (the lane lock damps the
-- cross coordinate at lambda 8, which used to slide a person across the block in half a second).
-- resume() also stops the motor (Common.halt) so the stale lane-locked intent cannot do that slide
-- in the frames before the brain's next think.
-- The duel (Server/Combat/CombatService, Combat/Duel): the event "duel" (mode stand | approach | back, the rodent's x
-- and z, speed, untilTime; or mode "end") has the person face the rodent, close in on it or back away from it until
-- untilTime, then walk back to the lane; a medical order or a gathering is never interrupted by it. A flight in the
-- duel is the ordinary flee ("witness").
-- The overhead watch (Server/Stealth/OverheadService, Stealth/OverheadWatch): the event "overhead" (mode stand | approach
-- | back as the duel's, at the squirrel's x and z, until untilTime; with faceX and faceZ, "approach" walks to x and z
-- and stands there facing them: the service picks the spot, off the road; "hurry": walk on briskly away from x and z
-- along the lane until untilTime, also once back on the lane after a rejoin; "end") is the same standing, closing in or
-- backing away, looking up at a squirrel overhead. It never cuts into a duel's order (the duel's "duel" event does cut
-- into it), a flight, a gathering or a medical order.
-- Interface (BUILD_PLAN §1.4): new(actor, params), think(dt, ctx), suspend() -> snapshot,
-- resume(snapshot), onEvent(evt). Also Pedestrian.defaultLanes() (the v5.4 core lanes in studs).
-- Pure; studs via Config/Units. Perception happens at the brain's own tick (5-10 Hz by LOD, D4).

local Import = require("../../Import")
local Units = Import.shared("Config/Units") :: typeof(require("../../../shared/Config/Units"))
local Tunables = Import.shared("Config/Tunables") :: typeof(require("../../../shared/Config/Tunables"))
local Common = require("./Common")
local Directive = require("./Directive")
local Perception = require("../Perception")

export type Lane = {
	axis: "x" | "z", -- the lane runs along this axis
	fixed: number, -- the other coordinate (studs)
	min: number, -- clamp along the axis (studs)
	max: number,
	inward: number?, -- beyond +/- this the next step is forced inward (studs)
}

export type Params = {
	lanes: { Lane },
	coreLanes: number, -- the first N lanes get 80 % of the picks (L4885)
	speedMin: number, -- studs/s
	speedMax: number,
	rng: () -> number,
	cyclist: boolean?,
}

type Brain = Common.Brain & {
	actor: Common.Actor,
	params: Params,
	lane: Lane,
	goal: number, -- coordinate along the lane axis
	walkSpeed: number,
	state: string, -- walk | flee | gather | rejoin | duel
	directive: Directive.State,
	gatherX: number,
	gatherZ: number,
	gatherUntil: number,
	duel: Duel?, -- an order from Combat/CombatService while the person faces the rodent
	duelSource: string?, -- who gave the order: "duel" (Combat/CombatService) or "overhead" (the overhead watch)
	hurryUntil: number, -- walking on briskly (the overhead watch's "hurry") until then ...
	hurryX: number, -- ... away from here
	hurryZ: number,
	threat: Common.Actor?,
	observer: Perception.Observer,
	target: Perception.Target,
	pctx: Perception.Ctx,
}

-- What Server/Combat/CombatService has the person do while they face the rodent (Combat/Duel's move): stand facing it,
-- close in, or back away from it, at `speed`, until `untilTime` (the service renews it every tick it still holds).
type Duel = { mode: string, x: number, z: number, speed: number, untilTime: number, faceX: number?, faceZ: number? }

local Pedestrian = {}

local GOAL_REACH = Units.st(1.7)
-- v5.4: 7.1 u/s. Owner 2026-11-10: people "a slight bit faster as we make the squirrel slower", and they
-- never tire: 19 st/s outruns a walking squirrel (18) and loses to a sprint burst (33).
local FLEE_SPEED = Units.st(7.6)
local FLEE_CYCLIST = Units.st(8.25)
local FLEE_STEP = Units.st(22)
local SPOT_RADIUS = Units.st(20)
local ALERT_ON_SPOT = 8
local ALERT_WALK_AGAIN = 2
local WALK_TURN = 4 -- rad/s (L7160)
local DAMP_WALK, DAMP_FLEE = 6.8, 10 -- lambda (L7138)
local REJOIN_FAR = 6 -- studs off the lane: further than this the person walks back instead of sliding
local REJOIN_NEAR = 1.5 -- studs: on the lane again
local REJOIN_SPEED = Units.st(1.6)
local QUIET_SPEED = Tunables.get("duel.quietSpeed") -- studs/s: no faster than this a squirrel is creeping
local BRUSH = Tunables.get("duel.brush") -- studs: this near a person feels it whatever it does
local HURRY_SPEED = Units.st(2.6) -- walking on briskly from under a squirrel (6.5 st/s; the walk is 2 to 4)
local HURRY_STEP = Units.st(37) -- how far along the lane the brisk walk heads

-- The v5.4 sidewalk lanes (humans_actors §4.2 table), in studs. 4 core lanes first.
function Pedestrian.defaultLanes(): { Lane }
	local st = Units.st
	local function lane(axis: "x" | "z", fixed: number, min: number, max: number, inward: number?): Lane
		return {
			axis = axis,
			fixed = st(fixed),
			min = st(min),
			max = st(max),
			inward = if inward then st(inward) else nil,
		}
	end
	return {
		lane("x", -12.1, -260, 260, 225),
		lane("x", 12.1, -260, 260, 225),
		lane("z", -12.1, -260, 260, 225),
		lane("z", 12.1, -260, 260, 225),
		lane("x", -161.9, -260, 260, 225),
		lane("x", -186.1, -260, 260, 225),
		lane("x", 158.9, -260, 260, 225),
		lane("x", 183.1, -260, 260, 225),
		lane("z", -167.9, -260, 260, 225),
		lane("z", -192.1, -260, 260, 225),
		lane("z", 165.9, -260, 260, 225),
		lane("z", 190.1, -260, 260, 225),
		lane("x", 326, -205, 112), -- park path
		lane("x", 405, 306, 628), -- cemetery path
		lane("x", 17.4, 390, 651, nil), -- commercial (step R(37,95); forced -1 beyond 615, +1 under 424)
		lane("x", -17.4, 390, 651, nil),
	}
end

local function along(self: Brain): number
	return if self.lane.axis == "x" then self.actor.x else self.actor.z
end

local function pickGoal(self: Brain)
	local rng = self.params.rng
	local lane = self.lane
	local u = along(self)
	local step = Common.range(rng, Units.st(37), Units.st(95))
	local dir = if rng() < 0.5 then -1 else 1
	if lane.inward then
		if u > lane.inward then
			dir = -1
		elseif u < -lane.inward then
			dir = 1
		end
	else
		-- commercial / park / cemetery lanes: turn back near the ends
		local span = lane.max - lane.min
		if u > lane.max - span * 0.14 then
			dir = -1
		elseif u < lane.min + span * 0.13 then
			dir = 1
		end
	end
	self.goal = math.clamp(u + dir * step, lane.min, lane.max)
end

local function setWalkIntent(self: Brain, goalU: number, speed: number, damp: number)
	local intent = self.actor.intent
	local lane = self.lane
	intent.mode = "walk"
	if lane.axis == "x" then
		intent.tx, intent.tz = goalU, lane.fixed
		intent.laneAxis, intent.laneCoord = "x", lane.fixed
	else
		intent.tx, intent.tz = lane.fixed, goalU
		intent.laneAxis, intent.laneCoord = "z", lane.fixed
	end
	intent.speed = speed
	intent.turnRate = WALK_TURN
	intent.damp = damp
end

-- How far the actor is from its lane (studs), and the nearest point on it.
local function offLane(self: Brain): (number, number, number)
	local lane, actor = self.lane, self.actor
	local x, z
	if lane.axis == "x" then
		x, z = math.clamp(actor.x, lane.min, lane.max), lane.fixed
	else
		x, z = lane.fixed, math.clamp(actor.z, lane.min, lane.max)
	end
	return Common.dist2d(actor.x, actor.z, x, z), x, z
end

-- Adopt the lane nearest to where the person now stands; returns how far away it is (studs).
local function adopt(self: Brain): number
	local actor = self.actor
	local best, bestD = self.lane, math.huge
	for _, lane in self.params.lanes do
		local x, z
		if lane.axis == "x" then
			x, z = math.clamp(actor.x, lane.min, lane.max), lane.fixed
		else
			x, z = lane.fixed, math.clamp(actor.z, lane.min, lane.max)
		end
		local d = Common.dist2d(actor.x, actor.z, x, z)
		if d < bestD then
			best, bestD = lane, d
		end
	end
	self.lane = best
	return bestD
end

-- The brisk walk on (the overhead watch's "hurry"): the goal along the lane away from (hurryX, hurryZ).
local function hurryOn(self: Brain)
	local u = along(self)
	local tu = if self.lane.axis == "x" then self.hurryX else self.hurryZ
	local away = if u >= tu then 1 else -1
	self.goal = math.clamp(u + away * HURRY_STEP, self.lane.min, self.lane.max)
end

-- Adopt the nearest lane and walk onto it (state "rejoin"); when the person is on it already, just
-- walk on.
local function reseat(self: Brain)
	local d = adopt(self)
	self.threat = nil
	self.state = if d > REJOIN_NEAR then "rejoin" else "walk"
	pickGoal(self)
end

-- A squirrel creeping (or keeping still) outside a person's view cone, and not brushing them, is not noticed just for
-- being near: the v5.4 predicate's peripheral sense (spotted within 6.8 u = 17 studs whatever the facing) is for one that
-- moves faster than a creep (the stalk, owner playtest 2026-11-19; the duel's own noticing is the same rule:
-- Combat/Duel.notices, Tunables duel.quietSpeed and duel.brush). Actors/Perception.spotted itself is unchanged.
-- `speed` is the squirrel's pace (speedOf: a held body's validated pace, not what its client reports).
local function stalkedUnseen(actor: Common.Actor, threat: Common.Actor, speed: number): boolean
	if speed > QUIET_SPEED then
		return false
	end
	local dx, dz = threat.x - actor.x, threat.z - actor.z
	local d = math.sqrt(dx * dx + dz * dz)
	if d < BRUSH then
		return false
	end
	local dot = (dx * math.sin(actor.yaw) + dz * math.cos(actor.yaw)) / d
	return dot <= Perception.constants.inViewDot
end

-- How fast a squirrel is going: a held one's pace by its validated motor packets (ctx.paceOf), never the velocity its
-- client reports (a client saying 0 would never be loud); anyone else's own speed
local function speedOf(threat: Common.Actor, ctx: Common.Ctx): number
	local f = ctx.paceOf
	local v = if f then f(threat.id) else nil
	return if v ~= nil then v else threat.speed
end

-- Perception at the brain's own tick: the nearest squirrel-species actor that passes spotted() (and is not stalking
-- them unseen: stalkedUnseen).
local function perceive(self: Brain, ctx: Common.Ctx): Common.Actor?
	local actor = self.actor
	local n = ctx.threats:query(actor.x, actor.z, SPOT_RADIUS, ctx.queryBuffer)
	if n == 0 then
		return nil
	end
	local obs = self.observer
	obs.x, obs.y, obs.z, obs.facing = actor.x, actor.y - actor.hip, actor.z, actor.yaw
	self.pctx.time = ctx.now
	local best: Common.Actor? = nil
	local bestD = math.huge
	for i = 1, n do
		local threat = ctx.actorsById[ctx.queryBuffer[i]]
		local speed = if threat then speedOf(threat, ctx) else 0
		if threat and not stalkedUnseen(actor, threat, speed) then
			local t = self.target
			t.x, t.y, t.z = threat.x, threat.y, threat.z
			t.groundY = ctx.groundAt(threat.x, threat.z)
			t.moveSpeed = speed
			t.focus = threat.variant == "spicy" and speed < Units.st(2.5)
			if Perception.spotted(obs, t, self.pctx) then
				local d = Common.dist2d(actor.x, actor.z, threat.x, threat.z)
				if d < bestD then
					bestD, best = d, threat
				end
			end
		end
	end
	return best
end

local Methods = {}
Methods.__index = Methods

function Methods.think(self: Brain, dt: number, ctx: Common.Ctx)
	local actor = self.actor
	actor.alert = math.max(0, actor.alert - dt)
	local cyclist = self.params.cyclist == true

	-- an order from the medical sequence overrides everything (Brains/Directive)
	if Directive.think(self.directive, actor, dt, ctx) then
		return
	end
	if Directive.takeReleased(self.directive) then
		reseat(self)
	end

	if self.state == "gather" then
		if ctx.now >= self.gatherUntil then
			reseat(self) -- back to the lane on foot (state "rejoin"), or straight on when already there
		else
			local intent = actor.intent
			local d = Common.dist2d(actor.x, actor.z, self.gatherX, self.gatherZ)
			if d < Units.st(2.2) then
				intent.mode = "stand"
				intent.heading = Common.yawOf(self.gatherX - actor.x, self.gatherZ - actor.z)
			else
				intent.mode = "walk"
				intent.tx, intent.tz = self.gatherX, self.gatherZ
				intent.laneAxis = nil
				intent.speed = Units.st(1.6)
				intent.turnRate = WALK_TURN
				intent.damp = DAMP_WALK
			end
			return
		end
	end

	if self.state == "duel" then
		local o = self.duel
		if o == nil or ctx.now >= o.untilTime then
			self.duel = nil
			reseat(self) -- the duel is over: back to the lane on foot
		else
			local intent = actor.intent
			local dx, dz = o.x - actor.x, o.z - actor.z
			intent.laneAxis, intent.laneCoord = nil, nil
			intent.turnRate = 10
			intent.damp = DAMP_FLEE
			local fx, fz = o.faceX, o.faceZ
			if o.mode == "approach" and fx and fz and dx * dx + dz * dz < 1 then
				intent.mode = "stand" -- (at the spot it was sent to: facing the squirrel)
				intent.heading = Common.yawOf(fx - actor.x, fz - actor.z)
			elseif o.mode == "approach" and o.speed > 0 then
				intent.mode = "walk"
				intent.tx, intent.tz = o.x, o.z
				intent.speed = o.speed
			elseif o.mode == "back" and o.speed > 0 then
				local d = math.max(1e-6, math.sqrt(dx * dx + dz * dz))
				intent.mode = "walk"
				intent.tx, intent.tz = actor.x - dx / d * 4, actor.z - dz / d * 4
				intent.speed = o.speed
			else
				intent.mode = "stand"
				intent.heading = Common.yawOf(dx, dz)
			end
			return
		end
	end

	if self.state == "rejoin" then
		local d, x, z = offLane(self)
		if d <= REJOIN_NEAR then
			self.state = "walk"
			pickGoal(self)
			if ctx.now < self.hurryUntil then
				hurryOn(self) -- (still hurrying on: away from it, not to a new goal)
			end
		else
			local intent = actor.intent
			intent.mode = "walk"
			intent.tx, intent.tz = x, z
			intent.laneAxis, intent.laneCoord = nil, nil
			intent.speed = math.max(self.walkSpeed, REJOIN_SPEED)
			intent.turnRate = WALK_TURN
			intent.damp = DAMP_WALK
			return
		end
	end

	-- spot reaction (L7068-7078): only when not already alert
	local threat = perceive(self, ctx)
	if threat and actor.alert <= 0 and self.state ~= "flee" then
		self.state = "flee"
		actor.alert = ALERT_ON_SPOT
		self.threat = threat
		if ctx.emit then
			ctx.emit("spotted", actor, threat)
		end
	end

	if self.state == "flee" then
		local t = self.threat
		if actor.alert < ALERT_WALK_AGAIN or not t then
			self.state = "walk"
			self.threat = nil
			self.walkSpeed = if cyclist
				then Units.st(4.2)
				else Common.range(self.params.rng, Units.st(0.9), Units.st(1.8))
			pickGoal(self)
		else
			-- run 22 u further from the squirrel along the lane axis (L7110-7131)
			local u = along(self)
			local tu = if self.lane.axis == "x" then t.x else t.z
			local away = if u >= tu then 1 else -1
			local goalU = math.clamp(u + away * FLEE_STEP, self.lane.min, self.lane.max)
			setWalkIntent(self, goalU, if cyclist then FLEE_CYCLIST else FLEE_SPEED, DAMP_FLEE)
			return
		end
	end

	-- walk: new goal when within 1.7 u (L7134)
	if math.abs(along(self) - self.goal) < GOAL_REACH then
		pickGoal(self)
	end
	local speed = if ctx.now < self.hurryUntil then math.max(self.walkSpeed, HURRY_SPEED) else self.walkSpeed
	setWalkIntent(self, self.goal, speed, DAMP_WALK)
end

function Methods.suspend(self: Brain): Common.Snapshot
	return {
		laneIndex = table.find(self.params.lanes, self.lane) or 1,
		goal = self.goal,
		walkSpeed = self.walkSpeed,
		state = if self.state == "duel" then "walk" else self.state,
		alert = self.actor.alert,
		gatherX = self.gatherX,
		gatherZ = self.gatherZ,
		gatherUntil = self.gatherUntil,
		directive = Directive.snapshot(self.directive),
	}
end

function Methods.resume(self: Brain, snapshot: Common.Snapshot)
	self.lane = self.params.lanes[snapshot.laneIndex] or self.lane
	self.goal = snapshot.goal
	self.walkSpeed = snapshot.walkSpeed
	self.state = snapshot.state
	self.actor.alert = snapshot.alert or 0
	self.gatherX = snapshot.gatherX or 0
	self.gatherZ = snapshot.gatherZ or 0
	self.gatherUntil = snapshot.gatherUntil or 0
	Directive.restore(self.directive, snapshot.directive)
	-- nothing moves the body until the next think: the old intent is locked to the lane the person
	-- was on before the hand-over, and the motor's lane lock would drag them back to it at once
	Common.halt(self.actor)
	-- handed back far from the lane (a player walked the body somewhere): walk to the nearest lane
	if not Directive.active(self.directive) and self.state ~= "gather" and offLane(self) > REJOIN_FAR then
		reseat(self)
	end
end

function Methods.onEvent(self: Brain, evt: { [string]: any })
	if evt.type == "overhead" then
		-- (never into a duel's order, a flight, a gathering, a rejoin or an order from the medical sequence)
		-- (a hurry on reaches someone walking back to the lane, too: they hurry on once there)
		local rejoining = self.state == "rejoin" and evt.mode ~= "hurry"
		if
			Directive.active(self.directive)
			or self.state == "gather"
			or self.state == "flee"
			or rejoining
			or (self.state == "duel" and self.duelSource ~= "overhead")
		then
			return
		end
		if evt.mode == "end" or evt.mode == "hurry" then
			if self.state == "duel" then
				self.duel = nil
				self.duelSource = nil
				reseat(self)
			end
			if evt.mode == "hurry" then
				-- on along the lane, away from it, briskly
				self.hurryUntil = evt.untilTime
				self.hurryX, self.hurryZ = evt.x, evt.z
				hurryOn(self)
			end
			return
		end
		self.state = "duel"
		self.duelSource = "overhead"
		self.duel = {
			mode = evt.mode,
			x = evt.x,
			z = evt.z,
			speed = evt.speed or 0,
			untilTime = evt.untilTime,
			faceX = evt.faceX,
			faceZ = evt.faceZ,
		}
		return
	end
	if evt.type == "duel" then
		-- (an order from the medical sequence comes first: a patient, a bystander or someone walking home is left be)
		if Directive.active(self.directive) or self.state == "gather" then
			return
		end
		if evt.mode == "end" then
			if self.state == "duel" then
				self.duel = nil
				reseat(self)
			end
			return
		end
		self.state = "duel"
		self.duelSource = "duel"
		self.duel = { mode = evt.mode, x = evt.x, z = evt.z, speed = evt.speed or 0, untilTime = evt.untilTime }
		return
	end
	if evt.type == "gather" then
		self.state = "gather"
		self.gatherX, self.gatherZ = evt.x, evt.z
		self.gatherUntil = evt.untilTime
	elseif evt.type == "alarm" then
		-- a new scene keeps the people already running from it on alert >= 7 (L9291-9302). Only them:
		-- here `alert` also blocks the spot reaction (think: `threat and actor.alert <= 0`), so raising
		-- it on someone who is just walking made them ignore the rodent in front of them for 7 s
		if self.state == "flee" then
			self.actor.alert = math.max(self.actor.alert, evt.alert or 7)
		end
	elseif evt.type == "medical" then
		Directive.set(self.directive, evt)
	elseif evt.type == "bitten" or evt.type == "witness" then
		-- run from the biter along the lane (humans_actors §7.1, §7.3). An order in force wins unless
		-- the event says `override` (a cured person bitten again on the walk home drops the walk).
		if evt.threat and (evt.override == true or not Directive.active(self.directive)) then
			if Directive.active(self.directive) then
				Directive.set(self.directive, {})
			end
			Directive.takeReleased(self.directive)
			-- the flee is lane-locked: only someone on (or beside) a lane runs; anyone further off
			-- first walks to the nearest lane
			if adopt(self) <= REJOIN_FAR then
				self.state = "flee"
				self.threat = evt.threat
				self.actor.alert = math.max(self.actor.alert, evt.alert or ALERT_ON_SPOT)
			else
				self.state = "rejoin"
			end
		end
	end
end

function Pedestrian.new(actor: Common.Actor, params: Params): Common.Brain
	local rng = params.rng
	-- 80 % one of the core lanes, 20 % any lane (L4885)
	local laneIndex
	if rng() < 0.8 then
		laneIndex = math.floor(rng() * params.coreLanes) + 1
	else
		laneIndex = math.floor(rng() * #params.lanes) + 1
	end
	local lane = params.lanes[math.clamp(laneIndex, 1, #params.lanes)]
	local self = setmetatable({
		kind = "Pedestrian",
		actor = actor,
		params = params,
		lane = lane,
		goal = 0,
		walkSpeed = Common.range(rng, params.speedMin, params.speedMax),
		state = "walk",
		directive = Directive.new(),
		gatherX = 0,
		gatherZ = 0,
		gatherUntil = 0,
		duel = nil,
		duelSource = nil,
		hurryUntil = 0,
		hurryX = 0,
		hurryZ = 0,
		threat = nil,
		observer = { x = 0, y = 0, z = 0, facing = 0, witnessUntil = 0 },
		target = { x = 0, y = 0, z = 0, groundY = 0, moveSpeed = 0, focus = false, inInterior = false },
		pctx = { time = 0, hotHere = false, concealment = Perception.defaultConcealment() },
	}, Methods)
	-- start on the lane
	if lane.axis == "x" then
		actor.z = lane.fixed
		actor.x = math.clamp(actor.x, lane.min, lane.max)
	else
		actor.x = lane.fixed
		actor.z = math.clamp(actor.z, lane.min, lane.max)
	end
	pickGoal(self :: any)
	return (self :: any) :: Common.Brain
end

return Pedestrian
