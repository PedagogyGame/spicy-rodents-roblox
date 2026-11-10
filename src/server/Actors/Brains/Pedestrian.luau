--!strict
-- ServerScriptService.Server.Actors.Brains.Pedestrian
-- Pedestrian brain, minimal W0 version (spike S5): sidewalk-lane walking with goals, the v5.4 spot
-- reaction (flee along the lane for 8 s), traffic-free, plus a "gather" event (fender-bender
-- bystanders). Numbers from humans_actors §4.2-§4.3 (lanes 12.1 u off the road centreline, goal step
-- R(37, 95) u, new goal within 1.7 u, inward beyond +/-225 u, clamp [-260, 260] u; speeds walk
-- R(0.8, 1.6), cyclist R(3.2, 5.2), flee 7.1 u/s) and §5.2 (alert 8, return to walk under 2).
-- The bite-to-hospital sequence (owner 2026-11-10) adds: a Directive (Brains/Directive: down, hidden,
-- route, hold) that overrides everything while it is set; the events "medical" (set or clear the
-- directive), "bitten" and "witness" (run from `threat` along the lane); an optional
-- ctx.emit("spotted", actor, threat) when a spot starts a flee, so the server can let some people
-- say something; and the "rejoin" state: after a directive, a gathering or a player letting go far
-- from the lane, the person adopts the nearest lane and WALKS back onto it (the lane lock damps the
-- cross coordinate at lambda 8, which used to slide a person across the block in half a second).
-- Interface (BUILD_PLAN §1.4): new(actor, params), think(dt, ctx), suspend() -> snapshot,
-- resume(snapshot), onEvent(evt). Also Pedestrian.defaultLanes() (the v5.4 core lanes in studs).
-- Pure; studs via Config/Units. Perception happens at the brain's own tick (5-10 Hz by LOD, D4).

local Import = require("../../Import")
local Units = Import.shared("Config/Units") :: typeof(require("../../../shared/Config/Units"))
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
	state: string, -- walk | flee | gather | rejoin
	directive: Directive.State,
	gatherX: number,
	gatherZ: number,
	gatherUntil: number,
	threat: Common.Actor?,
	observer: Perception.Observer,
	target: Perception.Target,
	pctx: Perception.Ctx,
}

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

-- Adopt the lane nearest to where the person now stands and walk onto it (state "rejoin"); when
-- they are on their lane already, just walk on.
local function reseat(self: Brain)
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
	self.threat = nil
	self.state = if bestD > REJOIN_NEAR then "rejoin" else "walk"
	pickGoal(self)
end

-- Perception at the brain's own tick: the nearest squirrel-species actor that passes spotted().
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
		if threat then
			local t = self.target
			t.x, t.y, t.z = threat.x, threat.y, threat.z
			t.groundY = ctx.groundAt(threat.x, threat.z)
			t.moveSpeed = threat.speed
			t.focus = threat.variant == "spicy" and threat.speed < Units.st(2.5)
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

	if self.state == "rejoin" then
		local d, x, z = offLane(self)
		if d <= REJOIN_NEAR then
			self.state = "walk"
			pickGoal(self)
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
	setWalkIntent(self, self.goal, self.walkSpeed, DAMP_WALK)
end

function Methods.suspend(self: Brain): Common.Snapshot
	return {
		laneIndex = table.find(self.params.lanes, self.lane) or 1,
		goal = self.goal,
		walkSpeed = self.walkSpeed,
		state = self.state,
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
	-- handed back far from the lane (a player walked the body somewhere): walk to the nearest lane
	if not Directive.active(self.directive) and self.state ~= "gather" and offLane(self) > REJOIN_FAR then
		reseat(self)
	end
end

function Methods.onEvent(self: Brain, evt: { [string]: any })
	if evt.type == "gather" then
		self.state = "gather"
		self.gatherX, self.gatherZ = evt.x, evt.z
		self.gatherUntil = evt.untilTime
	elseif evt.type == "alarm" then
		-- a new crime scene puts every visible human within 72 u on alert >= 7 (L9291-9302)
		self.actor.alert = math.max(self.actor.alert, evt.alert or 7)
	elseif evt.type == "medical" then
		Directive.set(self.directive, evt)
	elseif evt.type == "bitten" or evt.type == "witness" then
		-- run from the biter along the lane (humans_actors §7.1, §7.3); an order in force wins
		if evt.threat and not Directive.active(self.directive) then
			self.state = "flee"
			self.threat = evt.threat
			self.actor.alert = math.max(self.actor.alert, evt.alert or ALERT_ON_SPOT)
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
