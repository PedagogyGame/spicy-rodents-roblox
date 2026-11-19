--!strict
-- ServerScriptService.Server.Actors.Brains.Staff
-- Staff circuit brain, minimal W0 version (spike S5): hospital staff, ambulance crews, attraction
-- staff and the precinct guard walk a short loop of local waypoints around a station and pause at
-- each (hospital_police_infection §5.3: advance within 0.75 u, pause 0.24 s staff / 0.48 patients;
-- the patient circuit shape station -> +(dir 2.6, -0.65) -> +(dir 2.1, -2.8) -> +(0, -2.0), start index
-- i % 4, initial pause 0.4 + (i % 3) 0.3). Pace 1.4 u/s is a W0 tunable (the spec names none).
-- A Directive (Brains/Directive; the bite-to-hospital sequence) overrides the circuit while it is set:
-- onEvent({ type = "medical", mode = ... }) sets or clears it; "bitten" needs no handling here (the
-- service sends a bitten staff member running with a short route).
-- WORK STOPS (the bowling alley's employees, Shared/Attractions/AlleyStaff): `stops` replaces the circuit with a
-- loop of world points, each with its own `hold` (seconds of work there; 0: walk straight on), `act` (what the work
-- is: the actor's `task` while holding, which the runtime writes as the body's Task attribute) and `yaw` (the way
-- to face while working). The loop starts at the first stop. `way` (the alley's Shared/Attractions/AlleyWalk) is how
-- the employee gets back to the loop from anywhere else: let go by a player on the lawn, at the end of a bitten run,
-- back from the hospital, they walk that way (by the doors and the alley's routes) to the nearest leg's end, never
-- straight through the walls; let go at the stop they were working at, they carry on with the work.
-- Off the round (more than OFF_ROUND from its legs: let go by a player, the end of a run, back from the hospital)
-- every member of staff walks back by the town's way (ctx.way: World/WalkWay through Common.toward, by the doors of
-- the buildings they work in), never straight through a wall; with no way they wait, and with none found twice and no
-- player to see the body (Common.stuck) they are put on the round, out of sight. The round's own legs are clear (the
-- bake keeps them so) and are walked straight.
-- Interface: new(actor, params), think, suspend, resume, rejoin, onEvent. Pure; studs via Config/Units.

local Import = require("../../Import")
local Units = Import.shared("Config/Units") :: typeof(require("../../../shared/Config/Units"))
local StaffRounds = Import.shared("Actors/StaffRounds") :: typeof(require("../../../shared/Actors/StaffRounds"))
local Common = require("./Common")
local Directive = require("./Directive")

export type Params = {
	stationX: number, -- studs
	stationZ: number,
	index: number, -- staff member index (circuit direction and phase)
	patient: boolean?,
	circuit: { { number } }?, -- optional explicit local circuit (studs offsets)
	stops: { Stop }?, -- optional work loop (world studs): replaces the circuit
	way: ((x0: number, z0: number, x1: number, z1: number) -> { { number } })?, -- the way back to the loop
}

export type Stop = { x: number, z: number, hold: number, act: string?, yaw: number? }

type Brain = Common.Brain & {
	actor: Common.Actor,
	params: Params,
	points: { { number } }, -- absolute (x, z)
	stops: { Stop }?,
	target: number,
	pause: number,
	directive: Directive.State,
	back: { { number } }?, -- the way back to the loop being walked (work stops with a `way`)
	backAt: number,
	leg: Common.Leg, -- the town's way back to the round from off it
}

local Staff = {}

local REACH = Units.st(0.75)
local OFF_ROUND = 2 -- studs from the round's legs: further off, the way back is the town's (never straight)
local PAUSE_STAFF, PAUSE_PATIENT = 0.24, 0.48
local PACE = Units.st(1.4)

local Methods = {}
Methods.__index = Methods

-- how far (x, z) is from the closed loop of the round's points
local function offRound(points: { { number } }, x: number, z: number): number
	local best = math.huge
	local n = #points
	for i = 1, n do
		local p, q = points[i], points[i % n + 1]
		local ex, ez = q[1] - p[1], q[2] - p[2]
		local l2 = ex * ex + ez * ez
		local t = if l2 > 0 then math.clamp(((x - p[1]) * ex + (z - p[2]) * ez) / l2, 0, 1) else 0
		best = math.min(best, Common.dist2d(x, z, p[1] + ex * t, p[2] + ez * t))
	end
	return best
end

-- Back to the work loop from where the body stands now (work stops only): still at the stop being worked, the
-- work goes on (its act and facing); otherwise on to the end of the nearest leg, by the `way` when there is one
-- and the body is off the loop.
local function rejoin(self: Brain)
	local stops = self.stops
	if stops == nil then
		return
	end
	local actor = self.actor
	local n = #stops
	self.back = nil
	if self.pause > 0 then
		local s = stops[(self.target - 2) % n + 1] -- the stop being worked (the target is the next one)
		if s.hold > 0 and Common.dist2d(actor.x, actor.z, s.x, s.z) < REACH then
			actor.task = s.act
			actor.intent.heading = if s.yaw and s.yaw ~= 0 then s.yaw else 1e-6
			return
		end
		self.pause = 0
	end
	local best, bestD = self.target, math.huge
	for i = 1, n do
		local a, b = stops[i], stops[i % n + 1]
		local ex, ez = b.x - a.x, b.z - a.z
		local l2 = ex * ex + ez * ez
		local t = if l2 > 0 then math.clamp(((actor.x - a.x) * ex + (actor.z - a.z) * ez) / l2, 0, 1) else 0
		local d = Common.dist2d(actor.x, actor.z, a.x + ex * t, a.z + ez * t)
		if d < bestD then
			best, bestD = i % n + 1, d
		end
	end
	self.target = best
	local way = self.params.way
	if way and bestD >= REACH then
		local goal = stops[best]
		self.back = way(actor.x, actor.z, goal.x, goal.z)
		self.backAt = 1
	end
end

function Methods.think(self: Brain, dt: number, ctx: Common.Ctx)
	local actor = self.actor
	local intent = actor.intent
	if Directive.think(self.directive, actor, dt, ctx) then
		actor.task = nil
		return
	end
	if Directive.takeReleased(self.directive) then
		rejoin(self) -- an order ended (a bitten run, the walk back from the hospital): back to the loop
	end
	local back = self.back
	if back then
		local q = back[self.backAt]
		while q and Common.dist2d(actor.x, actor.z, q[1], q[2]) < REACH do
			self.backAt += 1
			q = back[self.backAt]
		end
		if q then
			actor.task = nil
			intent.mode = "walk"
			intent.tx, intent.tz = q[1], q[2]
			intent.laneAxis = nil
			intent.speed = PACE
			intent.turnRate = 6
			intent.damp = 8
			return
		end
		self.back = nil
	end
	local p = self.points[self.target]
	local d = Common.dist2d(actor.x, actor.z, p[1], p[2])
	if self.pause > 0 then
		self.pause = math.max(0, self.pause - dt)
		intent.mode = "stand"
		if self.pause == 0 then
			actor.task = nil
		end
		return
	end
	if d < REACH then
		local stop = self.stops and self.stops[self.target]
		self.target = self.target % #self.points + 1
		intent.mode = "stand"
		if stop then
			if stop.hold > 0 then
				-- at work: face the work (a heading of exactly 0 means "keep facing" to the motor)
				self.pause = stop.hold
				actor.task = stop.act
				intent.heading = if stop.yaw and stop.yaw ~= 0 then stop.yaw else 1e-6
			else
				intent.mode = "walk" -- a waypoint: straight on to the next
				self:think(0, ctx)
			end
			return
		end
		self.pause = if self.params.patient then PAUSE_PATIENT else PAUSE_STAFF
		return
	end
	actor.task = nil
	local tx, tz = p[1], p[2]
	if offRound(self.points, actor.x, actor.z) > OFF_ROUND then
		-- off the round (let go by a player somewhere, the end of a run, back from the hospital): the town's way
		local wx, wz = Common.toward(self.leg, actor, ctx, tx, tz)
		if wx == nil or wz == nil then
			intent.mode = "stand"
			if Common.stuck(self.leg, actor, ctx) then
				Common.place(self.leg, actor, ctx, tx, tz) -- (out of sight: on the round)
			end
			return
		end
		tx, tz = wx, wz
	end
	intent.mode = "walk"
	intent.tx, intent.tz = tx, tz
	intent.laneAxis = nil
	intent.speed = PACE
	intent.turnRate = 6
	intent.damp = 8
end

function Methods.suspend(self: Brain): Common.Snapshot
	self.actor.task = nil
	self.back = nil
	return { target = self.target, pause = self.pause, directive = Directive.snapshot(self.directive) }
end

function Methods.resume(self: Brain, snapshot: Common.Snapshot)
	self.target = snapshot.target or 1
	self.pause = snapshot.pause or 0
	Directive.restore(self.directive, snapshot.directive)
	Common.halt(self.actor) -- no walking on the old intent before the next think
	Common.forget(self.leg)
	rejoin(self)
end

Methods.rejoin = rejoin

function Methods.onEvent(self: Brain, evt: { [string]: any })
	if evt.type == "pause" then
		self.pause = math.max(self.pause, evt.seconds or 1)
	elseif evt.type == "medical" then
		Directive.set(self.directive, evt)
	end
end

function Staff.new(actor: Common.Actor, params: Params): Common.Brain
	local i = params.index
	local points = {}
	local localCircuit = params.circuit
	if params.stops then
		for _, s in params.stops do
			table.insert(points, { s.x, s.z })
		end
	elseif localCircuit then
		for _, lp in localCircuit do
			table.insert(points, { params.stationX + lp[1], params.stationZ + lp[2] })
		end
	else
		-- the v5.4 circuit (Shared/Actors/StaffRounds: the bake keeps an indoor one clear of furniture)
		points = StaffRounds.points(params.stationX, params.stationZ, i)
	end
	local start = if params.stops then 1 else (i % #points) + 1
	local self = setmetatable({
		kind = "Staff",
		actor = actor,
		params = params,
		points = points,
		stops = params.stops,
		target = start,
		pause = 0.4 + (i % 3) * 0.3,
		directive = Directive.new(),
		back = nil,
		backAt = 1,
		leg = Common.newLeg(),
	}, Methods)
	actor.x, actor.z = points[start][1], points[start][2]
	return (self :: any) :: Common.Brain
end

return Staff
