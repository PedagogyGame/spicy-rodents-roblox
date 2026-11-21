--!strict
-- ServerScriptService.Server.Actors.Brains.Pedestrian
-- Pedestrian brain, minimal W0 version (spike S5): sidewalk-lane walking with goals, the v5.4 spot
-- reaction (flee along the lane for 8 s) to the squirrels people fear (Actors/Species.feared: the Spicy Rodent and the
-- infected; an ordinary squirrel, a player's or the computer's, is walked past: owner D21), traffic-free, plus a
-- "gather" event (fender-bender bystanders). Numbers from humans_actors §4.2-§4.3 (lanes 12.1 u off the road centreline, goal step
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
-- in the frames before the brain's next think. The walk back onto a lane and the walk to a gathering go by the
-- town's way (ctx.way: World/WalkWay through Common.toward), never straight through a house; the lanes themselves
-- are pieces of pavement that miss every building (AI/TownAI splits them with WalkWay.splitLane).
-- The duel (Server/Combat/CombatService, Combat/Duel): the event "duel" (mode stand | approach | back, the rodent's x
-- and z, speed, untilTime; or mode "end") has the person face the rodent, close in on it or back away from it until
-- untilTime, then walk back to the lane; a medical order or a gathering is never interrupted by it. A flight in the
-- duel is the ordinary flee ("witness"). Closing in goes by the town's way (Common.toward: round a fence or a house,
-- never over it; with no way there the person stands facing it); backing away only along a clear line (straight
-- away, else aslant, else sideways; with none the person holds their ground facing it).
-- A rejoin or a gathering with no way (Common.stuck: no way found twice, and no player to see the body) ends with the
-- person put on their lane, out of sight: nobody is left standing for good across the river or out in the fields.
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
local Species = Import.shared("Actors/Species") :: typeof(require("../../../shared/Actors/Species"))
local Common = require("./Common")
local Directive = require("./Directive")
local Perception = require("../Perception")

export type Lane = {
	axis: "x" | "z", -- the lane runs along this axis
	fixed: number, -- the other coordinate (studs)
	min: number, -- clamp along the axis (studs)
	max: number,
	inward: number?, -- beyond +/- this the next step is forced inward (studs)
	-- the poles and tree trunks standing on the lane (World/WalkWay.dodges): { u along it, the step aside }
	dodges: { { number } }?,
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
	leg: Common.Leg, -- the town's way back onto the lane (rejoin) or over to a gathering
	laneTryAt: number, -- when a rejoin with no way to its lane may try another lane
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
local REJOIN_TRY = 300 -- studs: the lanes a rejoin with no way to its own may try instead
local QUIET_SPEED = Tunables.get("duel.quietSpeed") -- studs/s: no faster than this a squirrel is creeping
local BRUSH = Tunables.get("duel.brush") -- studs: this near a person feels it whatever it does
local HURRY_SPEED = Units.st(2.6) -- walking on briskly from under a squirrel (6.5 st/s; the walk is 2 to 4)
local HURRY_STEP = Units.st(37) -- how far along the lane the brisk walk heads
local BACK_STEP = 4 -- studs: how far ahead a step back from the rodent heads (renewed every think)
local DODGE_BEFORE, DODGE_AFTER = 3, 3 -- studs before and after a post on the lane its step aside is held

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
	-- a pole or a tree trunk on the lane ahead (or just passed): stepped round, the lane lock aside of it (one think
	-- ahead too: a far body thinks once a second)
	local coord = lane.fixed
	local dodges = lane.dodges
	if dodges then
		local u = if lane.axis == "x" then self.actor.x else self.actor.z
		local dir = if goalU >= u then 1 else -1
		for _, p in dodges do
			local ahead = (p[1] - u) * dir
			if ahead > -DODGE_AFTER and ahead < DODGE_BEFORE + speed then
				coord = lane.fixed + p[2]
				break
			end
		end
	end
	if lane.axis == "x" then
		intent.tx, intent.tz = goalU, coord
		intent.laneAxis, intent.laneCoord = "x", coord
	else
		intent.tx, intent.tz = coord, goalU
		intent.laneAxis, intent.laneCoord = "z", coord
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

-- A step back from the rodent (dx, dz from the person to it): BACK_STEP straight away when that line is clear (the
-- town's ctx.clear), else aslant, else to a side; nil when every one runs into something (a wall behind, the kerb's
-- fence beside: the person holds their ground).
local function backStep(actor: Common.Actor, ctx: Common.Ctx, dx: number, dz: number): (number?, number?)
	local d = math.max(1e-6, math.sqrt(dx * dx + dz * dz))
	local ux, uz = -dx / d, -dz / d -- away from it
	local clear = ctx.clear
	if clear == nil then
		return actor.x + ux * BACK_STEP, actor.z + uz * BACK_STEP
	end
	local s = math.sqrt(0.5)
	for _, dir in
		{
			{ ux, uz },
			{ (ux - uz) * s, (uz + ux) * s },
			{ (ux + uz) * s, (uz - ux) * s },
			{ -uz, ux },
			{ uz, -ux },
		}
	do
		local tx, tz = actor.x + dir[1] * BACK_STEP, actor.z + dir[2] * BACK_STEP
		if clear(actor.x, actor.z, tx, tz) then
			return tx, tz
		end
	end
	return nil, nil
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

-- Perception at the brain's own tick: the nearest feared squirrel (Species.feared: the Spicy Rodent or an infected one;
-- an ordinary squirrel is nobody's fright, however near, fast or loud: owner D21) that passes spotted() (and is not
-- stalking them unseen: stalkedUnseen).
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
		local speed = if threat and Species.feared(threat) then speedOf(threat, ctx) else 0
		if threat and Species.feared(threat) and not stalkedUnseen(actor, threat, speed) then
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
				local tx, tz = Common.toward(self.leg, actor, ctx, self.gatherX, self.gatherZ)
				if tx == nil or tz == nil then
					intent.mode = "stand"
					if Common.stuck(self.leg, actor, ctx) then
						self.gatherUntil = ctx.now -- (no way to the scene: back to the lane instead)
					end
					return
				end
				intent.mode = "walk"
				intent.tx, intent.tz = tx, tz
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
				-- by the town's way (round a fence, never over it); with none, facing it where they stand
				local tx, tz = Common.toward(self.leg, actor, ctx, o.x, o.z)
				if tx and tz then
					intent.mode = "walk"
					intent.tx, intent.tz = tx, tz
					intent.speed = o.speed
				else
					intent.mode = "stand"
					intent.heading = Common.yawOf(dx, dz)
				end
			elseif o.mode == "back" and o.speed > 0 then
				local tx, tz = backStep(actor, ctx, dx, dz)
				if tx and tz then
					intent.mode = "walk"
					intent.tx, intent.tz = tx, tz
					intent.speed = o.speed
				else
					intent.mode = "stand" -- (a wall behind and on both sides: they hold their ground)
					intent.heading = Common.yawOf(dx, dz)
				end
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
			-- by the town's way (from a back yard, a shop floor, the hospital: never through the walls between), to
			-- the lane point it set out for (the nearest one moves as the person walks)
			local leg, lane = self.leg, self.lane
			if leg.points ~= nil then
				local u, c = if lane.axis == "x" then leg.tx else leg.tz, if lane.axis == "x" then leg.tz else leg.tx
				if math.abs(c - lane.fixed) < 0.01 and u >= lane.min and u <= lane.max then
					x, z = leg.tx, leg.tz
				end
			end
			local tx, tz = Common.toward(leg, actor, ctx, x, z)
			if tx == nil or tz == nil then
				if Common.stuck(leg, actor, ctx) then
					-- no way at all, and nobody to see: on the lane, out of sight
					Common.place(leg, actor, ctx, x, z)
					self.state = "walk"
					pickGoal(self)
					return
				end
				-- no way to the nearest lane (in a fenced yard): another lane nearby next time, a while later
				intent.mode = "stand"
				if ctx.now >= self.laneTryAt then
					self.laneTryAt = ctx.now + Common.LEG_RETRY * 2 ^ math.min(leg.misses, 4)
					local near = {}
					for _, l in self.params.lanes do
						local lx = if l.axis == "x" then math.clamp(actor.x, l.min, l.max) else l.fixed
						local lz = if l.axis == "x" then l.fixed else math.clamp(actor.z, l.min, l.max)
						if l ~= lane and Common.dist2d(actor.x, actor.z, lx, lz) < REJOIN_TRY then
							table.insert(near, l)
						end
					end
					if #near > 0 then
						self.lane = near[math.floor(self.params.rng() * #near) + 1]
					end
				end
				return
			end
			intent.mode = "walk"
			intent.tx, intent.tz = tx, tz
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
	Common.forget(self.leg)
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
		leg = Common.newLeg(),
		laneTryAt = 0,
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
