--!strict
-- ReplicatedStorage.Shared.Traffic.AICarMotor
-- The AI car motor: one fleet vehicle on its lane, per behaviour class, with yielding, stop control and
-- teleport flags (BUILD_PLAN §4.4 W1 #9, D9; traffic.md §5, §6, §13). Movement/CarMotor is the player
-- kinematic car (Track A #5); this is the lane layer the server fleet runs.
-- Interface: new(entry, lane, opts) -> Vehicle; step(v, ctx, dt) -> events; dispatch(v, route, ctx, held?);
--            release(v); body(v) -> LaneMath.Body; CLASSES; VIS_HEIGHT
--
-- Behaviour classes port v5.4 movers (studs; the HTML constants x 2.5):
--   sedan    updateCars (§5.1): exponential speed (accel 1.3, brake 9), the people corridor (lateral 3.3,
--            along -3.5..16), trafficVehicleAhead (9 + 0.65 v, half width 1.2), the 3.1 hard stop, wrap.
--   heavy    updateHeavyTraffic (§5.5): approach (3.2 up, 10 down), seesHazard 10 + tVA 11, wrap.
--   van      the ice cream FSM (§5.3): stops at 0.16 and 0.59 of the loop, dwell 5.8 + (n mod 3).
--   trolley  the trolley FSM (§5.4): the schedule, braking profile, dwell 2.3 / 4.2, fixed yaw.
--   patrol   the patrol beat (§5.7) ping-pong; obeys traffic law and yields like heavy (brief v2 §15 dec 14).
--   motorcycle (§5.12): appears after a wait, rides to the lane end, hides; not fatal; hard stop only.
--   legacy_ambulance (§5.8): wait 18, drive, stop dead within 5 of a person, park 16, wait 145.
--   responder / incident (§5.9, §5.10): hidden until `dispatch`; out, on scene, back in reverse.
--            A trip dispatched with `held` stays on scene until `release` (the medical sequence loads
--            its patient first); without it the scene timer runs as in v5.4.
--   event (§5.11): the 2400 s living-event glide (fatal even at a crawl).
-- Rebuild fixes (traffic.md §11-§13): squirrels are in every yielding class's hazard set with RELATIVE
-- visibility (squirrel y - vehicle base y < 4.76 u, not the absolute 4.8); opposing vehicles are excluded
-- from the same-lane tests (the trolley deadlock, §6.1); emergency classes keep at least the hard stop
-- for people. A wrap, an appearance and a dispatch set `teleported` for that tick (SweptCollision skips it).
-- The emergency classes' hard stop has a limit (owner playtest review 2026-11-11: one player standing on
-- the hospital drive held all three ambulances for as long as they stood there, and every patient in
-- town waited out the timeout): after BLOCK_PATIENCE seconds stopped for a person the vehicle edges
-- on at BLOCK_CRAWL. Vehicles never hurt people (only held squirrels are in the fatal sweep).

local Control = require("./Control")
local Boxes = require("./Boxes")
local LaneMath = require("./LaneMath")
local Units = require("../Config/Units")

local st = Units.st

export type Person = {
	x: number,
	y: number,
	z: number,
	kind: string, -- "human" | "squirrel"
	visible: boolean?,
	hospital: boolean?,
	injured: boolean?,
}

export type Vehicle = {
	id: number,
	name: string,
	kind: string,
	class: string,
	lane: LaneMath.Lane,
	route: LaneMath.Lane?, -- a dispatched route (responder, incident) replaces the lane while active
	s: number,
	dir: number,
	speed: number,
	cruise: number,
	box: Boxes.Box,
	visible: boolean,
	phase: string,
	timer: number,
	n: number, -- deliveries / schedule index / runs
	offset: number,
	spawnS: number,
	x: number,
	y: number,
	z: number,
	yaw: number,
	teleported: boolean,
	stop: Control.State,
	moving: boolean, -- expected to be moving this tick (stuck detection)
	held: boolean?, -- a dispatched trip waits on scene until released
	home: LaneMath.Lane, -- the lane it started on (a rider's kerb bay is beside it; `lane` changes at a turn)
	side: number?, -- studs to the right of its lane line (a rider at the kerb, pulling out or in)
	away: boolean?, -- a rider that has left its home lane on this ride (its next pass of the bay ends it)
	blocked: number?, -- seconds an emergency vehicle has been stopped for a person in its way
}

export type Ctx = {
	now: number,
	people: { Person },
	bodies: { LaneMath.Body },
	heightAt: (x: number, z: number) -> number,
	rand: () -> number,
	stops: { [string]: { Control.StopLine } }?,
	rates: { rollingStop: number }?,
	sceneSecs: number?,
}

local AICarMotor = {}

AICarMotor.VIS_HEIGHT = st(4.76) -- traffic.md §13: relative squirrel visibility
AICarMotor.CLASSES =
	{ "sedan", "heavy", "van", "trolley", "patrol", "motorcycle", "legacy_ambulance", "responder", "incident", "event" }

local BASE_LIFT = st(0.04) -- y = terrain + 0.04 (§5.1)
local R_HUMAN, R_SQUIRREL = st(0.4), st(0.56)
local TROLLEY_SCHEDULE = { 310, 465, 616, 657, 616, 465, 310, 283 } -- §5.4, HTML x
local VAN_STOPS = { 0.16, 0.59 } -- §5.3, fraction of the loop

AICarMotor.BLOCK_PATIENCE = 4 -- s an emergency vehicle waits for a person in its way before edging on
AICarMotor.BLOCK_CRAWL = st(2) -- studs/s while it edges past them

export type Opts = { at: number?, cruise: number?, wait: number?, offset: number? }

function AICarMotor.new(
	e: { id: number, name: string, kind: string, class: string },
	lane: LaneMath.Lane,
	opts: Opts?
): Vehicle
	local o: Opts = opts or {}
	local dir = if lane.dir == 0 then 1 else lane.dir
	local s = 0
	if o.at and lane.shape == "straight" then
		local along = st(o.at)
		local probe = LaneMath.pointAt(lane, 0, dir)
		local x = if lane.axis == "x" then along else probe.x
		local z = if lane.axis == "z" then along else probe.z
		s = LaneMath.arcOf(lane, x, z, dir)
	end
	local hidden = e.class == "legacy_ambulance"
		or e.class == "responder"
		or e.class == "incident"
		or e.class == "event"
	local v: Vehicle = {
		id = e.id,
		name = e.name,
		kind = e.kind,
		class = e.class,
		lane = lane,
		route = nil,
		s = s,
		dir = dir,
		speed = 0,
		cruise = o.cruise or 0,
		box = Boxes.get(e.kind),
		visible = not hidden,
		phase = if hidden or e.class == "motorcycle" then "idle" else "drive",
		home = lane,
		timer = o.wait or 0,
		n = 0,
		offset = o.offset or 0,
		spawnS = s,
		x = 0,
		y = 0,
		z = 0,
		yaw = 0,
		teleported = false,
		stop = Control.newState(),
		moving = false,
	}
	if e.class == "trolley" then
		v.phase = "drive"
		v.n = 1
	elseif e.class == "heavy" then
		v.speed = st(5) -- initial speed 5 (§9)
	end
	local p = LaneMath.pointAt(lane, s, dir)
	v.x, v.z, v.yaw = p.x, p.z, if e.class == "trolley" then math.pi / 2 else p.yaw
	if e.class == "motorcycle" and lane.kerb then
		-- parked at the kerb beside its spawn point (stepClass.motorcycle)
		local side = math.abs(lane.kerb - (lane.coord :: number))
		v.x += -math.cos(p.yaw) * side
		v.z += math.sin(p.yaw) * side
		v.side = side
	end
	return v
end

-- The classes that answer calls: they have right of way over the lane classes (below).
local EMERGENCY: { [string]: boolean } = { responder = true, incident = true, legacy_ambulance = true }

function AICarMotor.body(v: Vehicle): LaneMath.Body
	return {
		x = v.x,
		z = v.z,
		yaw = v.yaw,
		width = v.box.width,
		length = v.box.length,
		visible = v.visible,
		id = v.id,
		emergency = EMERGENCY[v.class],
		speed = v.speed,
	}
end

-- gapAhead(v, fx, fz, range, halfWidth, others) -> studs: the free road between v's nose and the tail of
-- the nearest body in the corridor ahead (LaneMath.vehicleAhead's corridor), math.huge when none.
local function gapAhead(
	v: Vehicle,
	fx: number,
	fz: number,
	range: number,
	halfWidth: number,
	others: { LaneMath.Body }
): number
	local best = math.huge
	local margin = 0.2 * Units.STUDS_PER_UNIT
	for _, b in others do
		if b.visible ~= false and b.id ~= v.id then
			local dx, dz = b.x - v.x, b.z - v.z
			local along = dx * fx + dz * fz
			local across = math.abs(dx * fz - dz * fx)
			local psi = b.yaw
			local otherAlong = math.abs(math.sin(psi) * fx + math.cos(psi) * fz) * b.length / 2
				+ math.abs(math.cos(psi) * fx - math.sin(psi) * fz) * b.width / 2
			if along > 0 and along < range + otherAlong and across < halfWidth + b.width / 2 + margin then
				best = math.min(best, along - otherAlong - v.box.length / 2)
			end
		end
	end
	return best
end

-- mergeConflict(v, ctx, horizon) -> boolean: will a moving vehicle that is crossing v's path (not
-- following it, not oncoming) come within a car length of v in the next `horizon` seconds, both keeping
-- their headings and speeds? The ice cream van's U-turns cross the residential street and merge into its
-- far lane: without this it cut in front of southbound cars too close for them to stop.
local function mergeConflict(v: Vehicle, ctx: Ctx, horizon: number): boolean
	local fx, fz = math.sin(v.yaw), math.cos(v.yaw)
	local vx, vz = fx * v.speed, fz * v.speed
	for _, b in ctx.bodies do
		local bs = b.speed or 0
		if b.visible ~= false and b.id ~= v.id and bs > 0.5 then
			local bx, bz = math.sin(b.yaw), math.cos(b.yaw)
			local px, pz = b.x - v.x, b.z - v.z
			-- (one behind v is following it round the same turn: that one brakes for v, not v for it)
			if math.abs(bx * fx + bz * fz) < 0.95 and px * fx + pz * fz > -v.box.length / 2 then
				local wx, wz = bx * bs - vx, bz * bs - vz
				local w2 = wx * wx + wz * wz
				local t = if w2 > 1e-9 then math.clamp(-(px * wx + pz * wz) / w2, 0, horizon) else 0
				local cx, cz = px + wx * t, pz + wz * t
				local r = (v.box.length + b.length) / 2
				if cx * cx + cz * cz < r * r then
					return true
				end
			end
		end
	end
	return false
end

-- inPath(a, b, gap): is b's box in a's way: in front of a's nose by at most `gap` (or already level with
-- it) and across a's width, with b's extents projected on a's heading whatever b's own heading (a car
-- crossing a's path is as much in the way as one ahead of it in a's lane).
local PATH_MARGIN = st(0.2)
local function inPath(a: LaneMath.Body, b: LaneMath.Body, gap: number): boolean
	local fx, fz = math.sin(a.yaw), math.cos(a.yaw)
	local dx, dz = b.x - a.x, b.z - a.z
	local along = dx * fx + dz * fz
	if along <= 0 then
		return false
	end
	local across = math.abs(dx * fz - dz * fx)
	local ux, uz = math.sin(b.yaw), math.cos(b.yaw)
	local bAlong = math.abs(ux * fx + uz * fz) * b.length / 2 + math.abs(uz * fx - ux * fz) * b.width / 2
	local bAcross = math.abs(ux * fz - uz * fx) * b.length / 2 + math.abs(uz * fz + ux * fx) * b.width / 2
	return along - bAlong < a.length / 2 + gap and across < a.width / 2 + bAcross + PATH_MARGIN
end

local function approach(v: number, goal: number, amount: number): number
	if v < goal then
		return math.min(goal, v + amount)
	end
	return math.max(goal, v - amount)
end

local function shortest(a: number): number
	return math.atan2(math.sin(a), math.cos(a))
end

-- How close in front of an emergency vehicle's nose another vehicle counts as in its way (PRIORITY_GAP);
-- how near the end of its route a held-up emergency vehicle counts as there (ARRIVE_QUEUED).
local PRIORITY_GAP = st(4)
local ARRIVE_QUEUED = st(30)

-- The lane classes also brake for traffic crossing their lane (below); the crossing classes do not.
local CROSSING_YIELD: { [string]: boolean } = { sedan = true, heavy = true, motorcycle = true }

-- Which bodies a vehicle brakes for when they are in its corridor:
--   * every player's vehicle, whatever its heading (a car parked across the lane is still in the way; a
--     player's car never waits for the fleet, so no deadlock);
--   * fleet vehicles heading its way (dot > 0.3; v5.4 counted only these: opposing traffic excluded, §6.1,
--     the trolley deadlock);
--   * an emergency vehicle crossing or entering its path (right of way), unless this vehicle is already
--     in the emergency vehicle's own way: then it keeps going to clear it, and the emergency vehicle waits
--     (drivePolyline). Without this the ambulances and incident cars, which yield to no vehicle in v5.4,
--     and the lane traffic drove through each other wherever a call route crosses a street;
--   * for the lane classes (sedan, heavy, motorcycle), other traffic crossing the lane (dot > -0.3, still
--     not opposing): the ice cream van merging across the residential street at the end of each loop,
--     the patrol car in its U-turn. The crossing classes themselves (van, patrol, trolley) keep v5.4's
--     rule and wait for a gap instead (mergeConflict), so two vehicles never wait for each other.
local function bracesFor(v: Vehicle, b: LaneMath.Body, fx: number, fz: number): boolean
	if b.player == true then
		return true
	end
	local dot = math.sin(b.yaw) * fx + math.cos(b.yaw) * fz
	if dot > 0.3 then
		return true
	end
	if b.emergency == true then
		return not inPath(b, AICarMotor.body(v), PRIORITY_GAP)
	end
	return CROSSING_YIELD[v.class] == true and dot > -0.3
end

-- The players' vehicles among the bodies.
local function playerCars(ctx: Ctx): { LaneMath.Body }
	local out = {}
	for _, b in ctx.bodies do
		if b.player then
			table.insert(out, b)
		end
	end
	return out
end

-- Is a player's vehicle in the corridor ahead within `gap` studs of v's nose? (the classes that yield to
-- no vehicle in v5.4, motorcycles and the emergency routes, still must not drive through one)
local function playerCarAhead(v: Vehicle, ctx: Ctx, gap: number): boolean
	local cars = playerCars(ctx)
	if #cars == 0 then
		return false
	end
	local fx, fz = math.sin(v.yaw), math.cos(v.yaw)
	return LaneMath.vehicleAhead(AICarMotor.body(v), fx, fz, v.box.length / 2 + gap, v.box.width / 2, cars)
end

-- Hazards for a yielding class: people (humans visible, not hospital, not injured; squirrels visible
-- relative to the vehicle base) and the vehicles it braces for (bracesFor).
local function hazards(v: Vehicle, ctx: Ctx, fx: number, fz: number, withVehicles: boolean): { LaneMath.Hazard }
	local out: { LaneMath.Hazard } = {}
	for _, p in ctx.people do
		if p.visible ~= false and not p.hospital and not p.injured then
			if p.kind == "squirrel" then
				if p.y - v.y < AICarMotor.VIS_HEIGHT then
					table.insert(out, { x = p.x, z = p.z, r = R_SQUIRREL })
				end
			else
				table.insert(out, { x = p.x, z = p.z, r = R_HUMAN })
			end
		end
	end
	if withVehicles then
		for _, b in ctx.bodies do
			if b.visible ~= false and b.id ~= v.id then
				if bracesFor(v, b, fx, fz) then
					table.insert(out, { x = b.x, z = b.z, r = b.width / 2 })
				end
			end
		end
	end
	return out
end

local function sameWay(v: Vehicle, ctx: Ctx, fx: number, fz: number): { LaneMath.Body }
	local out = {}
	for _, b in ctx.bodies do
		if b.id ~= v.id then
			if bracesFor(v, b, fx, fz) then
				table.insert(out, b)
			end
		end
	end
	return out
end

-- Any visible person (humans; the sedan rule has no hospital filter) within r of (x, z)?
local function personNear(ctx: Ctx, x: number, z: number, r: number, skipHospital: boolean): boolean
	for _, p in ctx.people do
		if p.visible ~= false and p.kind ~= "squirrel" and not (skipHospital and p.hospital) then
			if (p.x - x) ^ 2 + (p.z - z) ^ 2 < r * r then
				return true
			end
		end
	end
	return false
end

-- The junction box is clear of people and of other moving vehicles.
local function junctionClear(v: Vehicle, ctx: Ctx, line: Control.StopLine?): boolean
	if not line then
		return true
	end
	local cx, cz, r = line.at[1], line.at[2], line.radius
	for _, p in ctx.people do
		if p.visible ~= false and (p.x - cx) ^ 2 + (p.z - cz) ^ 2 < r * r then
			return false
		end
	end
	for _, b in ctx.bodies do
		if b.visible ~= false and b.id ~= v.id and not (b.player and (b.speed or 0) < 0.5) then
			if (b.x - cx) ^ 2 + (b.z - cz) ^ 2 < r * r then
				return false
			end
		end
	end
	return true
end

local function place(v: Vehicle, ctx: Ctx, lane: LaneMath.Lane, keepYaw: number?)
	local p = LaneMath.pointAt(lane, v.s, v.dir)
	v.x, v.z = p.x, p.z
	v.yaw = keepYaw or p.yaw
	v.y = ctx.heightAt(v.x, v.z) + BASE_LIFT
end

-- Is the spot (x, z) free of every other visible vehicle, with SPOT_REACH between the boxes along their
-- lengths? A wrap or an appearance onto an occupied spot put one car inside another.
local SPOT_REACH = st(2)
local function spotClear(v: Vehicle, ctx: Ctx, x: number, z: number): boolean
	for _, b in ctx.bodies do
		if b.visible ~= false and b.id ~= v.id then
			local r = (v.box.length + b.length) / 2 + SPOT_REACH
			if (b.x - x) ^ 2 + (b.z - z) ^ 2 < r * r then
				return false
			end
		end
	end
	return true
end

-- The fleet's bodies are last tick's; a vehicle that appears or wraps updates its own at once, so a
-- vehicle stepped later in the same tick does not wrap or appear on top of it.
local function syncBody(v: Vehicle, ctx: Ctx)
	for _, b in ctx.bodies do
		if b.id == v.id then
			b.x, b.z, b.yaw, b.visible = v.x, v.z, v.yaw, v.visible
			return
		end
	end
end

local function appear(v: Vehicle, ctx: Ctx, lane: LaneMath.Lane, s: number)
	v.s = s
	v.visible = true
	v.teleported = true
	place(v, ctx, lane)
	syncBody(v, ctx)
end

local function stopCap(v: Vehicle, ctx: Ctx, decel: number, dt: number, events: { string })
	local lines = if ctx.stops then ctx.stops[v.lane.id] else nil
	if not lines then
		return math.huge
	end
	local line = v.stop.line
	local clear = v.stop.phase ~= "waiting" or junctionClear(v, ctx, line)
	local roll = if v.stop.phase == "free" then ctx.rand() else 1
	local cap, ev = Control.step(v.stop, lines, v.s, v.dir, v.speed, decel, dt, clear, roll, ctx.rates)
	if ev then
		table.insert(events, ev)
	end
	return cap
end

-- Lane motion. At the end of its lane a vehicle turns round: a U-turn (phase "uturn", `timer` = studs into
-- it) onto the other side of the road, then on along the other direction: the other side of a ping-pong
-- lane (the patrol beat; LaneMath.pingPong measures s in each direction's own frame) or a one-way lane's
-- `returnLane` (LaneMath.link). v5.4 wrapped one-way traffic to the lane's start instead, a car vanishing
-- at one end of the street and another appearing at the other, in plain view; only a lane with no way
-- back (none in the game's data) still does.
local function advanceLane(v: Vehicle, ctx: Ctx, dt: number, events: { string })
	local lane = v.lane
	local arc = LaneMath.uturnLength(lane, v.dir)
	if v.phase == "uturn" then
		local d = v.timer + v.speed * dt
		if d < arc then
			v.timer = d
			local p = LaneMath.uturnPoint(lane, v.dir, d)
			v.x, v.z, v.yaw = p.x, p.z, p.yaw
			v.y = ctx.heightAt(v.x, v.z) + BASE_LIFT
			return
		end
		v.phase, v.timer = "drive", 0
		local back = lane.returnLane
		if back then
			v.lane, v.dir = back, back.dir
		else
			v.dir = -v.dir
		end
		v.s = math.min(d - arc, v.lane.length)
		table.insert(events, "turn")
		v.stop = Control.newState()
	elseif arc > 0 then
		local n = v.s + math.abs(v.speed) * dt
		if n > lane.length then
			v.s = lane.length
			v.phase, v.timer = "uturn", n - lane.length
			local p = LaneMath.uturnPoint(lane, v.dir, v.timer)
			v.x, v.z, v.yaw = p.x, p.z, p.yaw
			v.y = ctx.heightAt(v.x, v.z) + BASE_LIFT
			return
		end
		v.s = n
	elseif lane.dir == 0 then
		local s, d, turned = LaneMath.pingPong(lane, v.s, v.dir, v.speed, dt)
		v.s, v.dir = s, d
		if turned then
			table.insert(events, "turn")
			v.stop = Control.newState()
		end
	else
		local s, wrapped = LaneMath.advance(lane, v.s, v.speed, dt)
		v.s = s
		if wrapped then
			v.stop = Control.newState()
			table.insert(events, "wrap")
			local p = LaneMath.pointAt(lane, s, v.dir)
			if not spotClear(v, ctx, p.x, p.z) then
				-- the lane's start is taken: off the map until it is free (AICarMotor.step)
				v.phase, v.visible = "queued", false
				place(v, ctx, lane)
				syncBody(v, ctx)
				return
			end
			v.teleported = true
			place(v, ctx, lane)
			syncBody(v, ctx)
			return
		end
	end
	place(v, ctx, v.lane)
end

local UTURN_SPEED = st(5) -- 12.5 st/s round a 13.5 st U-turn: 0.9 rad/s of steering
local UTURN_SPEED_HEAVY = st(4) -- the RVs and dump trucks take it at 10 st/s
local UTURN_BRAKE = st(4) -- braking into it, gentler than the 10 u/s2 hazard stop
local TURN_LOOK = st(14) -- how far along the turn a vehicle looks for one ahead of it
local TURN_GAP = st(2) -- and the free road it keeps to it

-- poseAhead(v, d): where v's centre is d studs further on: along its lane, round the U-turn at its end
-- and on along the lane it comes back by.
local function poseAhead(v: Vehicle, d: number): (number, number, number)
	local lane = v.lane
	local arc = LaneMath.uturnLength(lane, v.dir)
	local into = if v.phase == "uturn" then v.timer + d else v.s + d - lane.length
	local p: LaneMath.Pose
	if into <= 0 then
		p = LaneMath.pointAt(lane, v.s + d, v.dir)
	elseif into < arc then
		p = LaneMath.uturnPoint(lane, v.dir, into)
	else
		local back = lane.returnLane
		p = if back then LaneMath.pointAt(back, into - arc, back.dir) else LaneMath.pointAt(lane, into - arc, -v.dir)
	end
	return p.x, p.z, p.yaw
end

-- pathGap(v, ctx, reach) -> studs: the free road in front of v's nose along the path it is about to
-- drive (poseAhead), up to `reach`; math.huge when nothing stands on it. The corridor tests look straight
-- ahead, which in a turn is not where the vehicle goes: a sedan following a dump truck round the end of
-- the boulevard drove into its tail. Oncoming vehicles are not counted (they pass on their own side).
local PATH_STEP = st(1)
local function pathGap(v: Vehicle, ctx: Ctx, reach: number): number
	local half = v.box.width / 2
	local nose = (v.box.length - v.box.width) / 2
	local d = PATH_STEP
	while d <= reach + nose do
		local x, z, yaw = poseAhead(v, d)
		local fx, fz = math.sin(yaw), math.cos(yaw)
		for _, b in ctx.bodies do
			if b.visible ~= false and b.id ~= v.id then
				-- b as a capsule along its heading
				local ux, uz = math.sin(b.yaw), math.cos(b.yaw)
				local hl = math.max(0, (b.length - b.width) / 2)
				local dx, dz = x - b.x, z - b.z
				local t = math.clamp(dx * ux + dz * uz, -hl, hl)
				local cx, cz = dx - ux * t, dz - uz * t
				local r = half + b.width / 2 + PATH_MARGIN
				if cx * cx + cz * cz < r * r and ux * fx + uz * fz > -0.3 then
					return math.max(0, d - nose - PATH_MARGIN)
				end
			end
		end
		d += PATH_STEP
	end
	return math.huge
end

-- turnLimit(v, ctx): the speed a vehicle may have this tick because of the U-turn at the end of its lane
-- (math.huge on a lane without one): it brakes into the turn and takes it slowly; it waits at its
-- mouth, or in it, while a vehicle is crossing its way (the patrol car turns across the oncoming lane
-- in the middle of the boulevard); and at the end of a street it keeps behind the vehicle ahead of it
-- on the turn (pathGap).
local function turnLimit(v: Vehicle, ctx: Ctx): number
	if LaneMath.uturnLength(v.lane, v.dir) <= 0 then
		return math.huge
	end
	local toEnd = if v.phase == "uturn" then 0 else math.max(0, v.lane.length - v.s)
	local top = if v.class == "heavy" then UTURN_SPEED_HEAVY else UTURN_SPEED
	if (v.phase == "uturn" or toEnd < st(6)) and mergeConflict(v, ctx, 2) then
		return 0
	end
	local limit = math.sqrt(top * top + 2 * UTURN_BRAKE * toEnd)
	if v.lane.returnLane and toEnd < TURN_LOOK then
		limit = math.min(limit, math.max(0, (pathGap(v, ctx, TURN_LOOK) - TURN_GAP) * 1.2))
	end
	return limit
end

local stepClass: { [string]: (Vehicle, Ctx, number, { string }) -> () } = {}

local SEDAN_GAP = st(2) -- 5 st between a standing sedan and the tail of what it stopped behind
local SEDAN_FOLLOW = 1.2 -- desired speed per stud of free road beyond SEDAN_GAP (1/s): 19 st back at 17 st/s
local SEDAN_BRAKE = st(16) -- 40 st/s2: the hardest it brakes for a vehicle (for a person it stops as before)

stepClass.sedan = function(v, ctx, dt, events)
	local fx, fz = math.sin(v.yaw), math.cos(v.yaw)
	local danger = false
	for _, h in hazards(v, ctx, fx, fz, false) do
		local dx, dz = h.x - v.x, h.z - v.z
		local along = dx * fx + dz * fz
		if math.abs(dx * fz - dz * fx) < st(3.3) and along > -st(3.5) and along < st(16) then
			danger = true
			break
		end
	end
	-- A vehicle ahead (v5.4: any within 9 u + 0.65 v set the desired speed to 0, and braking shortened that
	-- look-ahead until the leader dropped out of it: the sedan lurched up to anything slower, braking and
	-- pulling away on alternate ticks). The desired speed now eases down with the free road to the leader,
	-- so the sedan settles behind it at its speed, SEDAN_GAP back when both stand.
	local follow = math.huge
	if not danger then
		local reach = st(9) + 0.65 * v.speed
		local gap = gapAhead(v, fx, fz, reach, st(1.2), sameWay(v, ctx, fx, fz))
		follow = math.max(0, (gap - SEDAN_GAP) * SEDAN_FOLLOW)
	end
	local cap = math.min(stopCap(v, ctx, st(9), dt, events), turnLimit(v, ctx), follow)
	local desired = if danger then 0 else math.min(v.cruise, cap)
	local rate = if desired < v.speed then 9 else 1.3
	local step = (desired - v.speed) * (1 - math.exp(-dt * rate))
	if not danger then
		step = math.max(step, -SEDAN_BRAKE * dt) -- behind a vehicle it brakes like a car, not like a wall
	end
	v.speed += step
	if v.speed < 1e-3 and desired == 0 then
		v.speed = 0
	end
	-- hard stop: any visible human within 3.1 of the next position (no hospital filter, §5.1 step 4)
	local nx, nz = v.x + fx * v.speed * dt, v.z + fz * v.speed * dt
	if personNear(ctx, nx, nz, st(3.1), false) then
		v.speed = 0
		if v.phase ~= "uturn" then
			place(v, ctx, v.lane)
		end
		return
	end
	advanceLane(v, ctx, dt, events)
end

local function yielding(
	v: Vehicle,
	ctx: Ctx,
	dt: number,
	events: { string },
	range: number,
	tva: number,
	up: number,
	down: number,
	limit: number?
)
	local fx, fz = math.sin(v.yaw), math.cos(v.yaw)
	local hw = v.box.width / 2
	local danger = LaneMath.seesHazard(v.x, v.z, fx, fz, range, hw, hazards(v, ctx, fx, fz, true)) ~= nil
		or LaneMath.vehicleAhead(AICarMotor.body(v), fx, fz, tva, hw, sameWay(v, ctx, fx, fz))
	local cap = math.min(stopCap(v, ctx, down, dt, events), limit or math.huge)
	local desired = if danger then 0 else math.min(v.cruise, cap)
	v.speed = approach(v.speed, desired, (if desired < v.speed then down else up) * dt)
	advanceLane(v, ctx, dt, events)
end

stepClass.heavy = function(v, ctx, dt, events)
	yielding(v, ctx, dt, events, st(10), st(11), st(3.2), st(10), turnLimit(v, ctx))
end

stepClass.patrol = function(v, ctx, dt, events)
	yielding(v, ctx, dt, events, st(10), st(11), st(3.2), st(10), turnLimit(v, ctx))
end

stepClass.van = function(v, ctx, dt, events)
	local lane = v.lane
	if v.phase == "dwell" then
		v.timer -= dt
		v.speed = 0
		if v.timer <= 0 then
			v.phase = "drive"
		end
	else
		local L = lane.length
		local target = VAN_STOPS[(v.n % #VAN_STOPS) + 1] * L
		local dist = (target - v.s) % L
		local fx, fz = math.sin(v.yaw), math.cos(v.yaw)
		local danger = LaneMath.seesHazard(v.x, v.z, fx, fz, st(7.7), st(1.85), hazards(v, ctx, fx, fz, true)) ~= nil
			or mergeConflict(v, ctx, 2)
		local desired = if danger then 0 else math.min(v.cruise, math.sqrt(2 * st(5.0) * dist))
		v.speed = approach(v.speed, desired, (if desired < v.speed then st(11) else st(4.5)) * dt)
		-- arrive when this tick's step reaches the stop: the braking profile brings the van in at a crawl
		-- (it used to snap the last 0.35 u + one step, a 1 st hop from 11 st/s to a dead stop)
		if not danger and dist <= math.max(st(0.01), v.speed * dt) then
			v.s = target
			v.speed = 0
			v.phase = "dwell"
			v.timer = 5.8 + (v.n % 3)
			v.n += 1
			table.insert(events, "delivery")
		else
			v.s = (v.s + v.speed * dt) % L
		end
	end
	local p = LaneMath.pointAt(lane, v.s, 1)
	v.x, v.z = p.x, p.z
	v.y = ctx.heightAt(v.x, v.z) + st(0.07)
	v.yaw += shortest(p.yaw - v.yaw) * math.min(1, dt * 5.4)
end

stepClass.trolley = function(v, ctx, dt, events)
	local lane = v.lane
	if v.phase == "dwell" then
		v.timer -= dt
		v.speed = 0
		if v.timer <= 0 then
			v.phase = "drive"
		end
	else
		local destX = st(TROLLEY_SCHEDULE[v.n])
		local x = v.x
		local delta = destX - x
		local d = if delta < 0 then -1 else 1
		local danger = LaneMath.seesHazard(x, v.z, d, 0, st(11), st(1.85), hazards(v, ctx, d, 0, true)) ~= nil
		local cap = math.min(v.cruise, math.sqrt(2 * st(6.2) * math.abs(delta)))
		local desired = if danger then 0 else cap
		v.speed = approach(v.speed, desired, (if desired < v.speed then st(12) else st(4.6)) * dt)
		x += math.min(math.abs(delta), v.speed * dt) * d
		-- arrive when the profile has brought it in (it used to snap the last 0.25 u: from about 5 st/s
		-- the trolley lurched forward at 20 st/s for one tick and stopped dead)
		if not danger and math.abs(destX - x) < st(0.01) then
			x = destX
			v.speed = 0
			v.phase = "dwell"
			local hx = TROLLEY_SCHEDULE[v.n]
			v.timer = if hx == 283 or hx == 657 then 2.3 else 4.2
			v.n = (v.n % #TROLLEY_SCHEDULE) + 1
			table.insert(events, "bell")
		end
		v.dir = d
		v.s = LaneMath.arcOf(lane, x, v.z, 1)
		v.x = x
	end
	v.y = ctx.heightAt(v.x, v.z) + BASE_LIFT
	v.yaw = math.pi / 2 -- the body never rotates (§5.4)
end

-- A rider between rides stands parked at the kerb beside its spawn point; a ride pulls out from the kerb,
-- goes once round its street (to the end, back along the other side, and round again) and pulls in where
-- it started. v5.4's riders appeared in the middle of the boulevard at full speed and vanished at its
-- end (§5.12): a pop in and a pop out in plain view every minute.
local BAY_RUN = st(16) -- 40 st of road to pull out from the kerb or in to it
local RIDER_ACCEL = st(4)
local RIDER_BRAKE = st(8)

local function smooth(u: number): number
	local c = math.clamp(u, 0, 1)
	return c * c * (3 - 2 * c)
end

-- shift(v, ctx, side, slope): v, placed on its lane line, moved `side` studs to its right and turned along
-- a path whose distance from the line changes by `slope` per stud driven.
local function shift(v: Vehicle, ctx: Ctx, side: number, slope: number)
	local fx, fz = math.sin(v.yaw), math.cos(v.yaw)
	local rx, rz = -fz, fx
	v.x += rx * side
	v.z += rz * side
	v.yaw = math.atan2(fx + rx * slope, fz + rz * slope)
	v.y = ctx.heightAt(v.x, v.z) + BASE_LIFT
	v.side = side
end

-- May a rider pull out? Nothing is beside the bay, in the stretch it crosses to its lane, or about to be
-- (three seconds of anything moving along there, whichever way: the trolley runs between the eastbound
-- lane and its kerb).
local function kerbClear(v: Vehicle, ctx: Ctx, bay: number): boolean
	local lane = v.home
	local p = LaneMath.pointAt(lane, v.spawnS, lane.dir)
	local fx, fz = math.sin(p.yaw), math.cos(p.yaw)
	local rx, rz = -fz, fx
	for _, b in ctx.bodies do
		if b.visible ~= false and b.id ~= v.id then
			local dx, dz = b.x - p.x, b.z - p.z
			local along, across = dx * fx + dz * fz, dx * rx + dz * rz
			local reach = b.length / 2 + 3 * (b.speed or 0)
			if
				across > -(b.width / 2 + st(1.5))
				and across < bay + b.width / 2
				and along > -(reach + st(6))
				and along < BAY_RUN + st(4) + reach
			then
				return false
			end
		end
	end
	return true
end

-- bayPath(v, bay) -> side, slope: how far to the right of its lane line a rider is beside its bay, and
-- how that changes per stud of lane: pulling out (the first BAY_RUN of a ride), pulling in (the last),
-- 0 anywhere else.
local function bayPath(v: Vehicle, bay: number): (number, number)
	if v.lane ~= v.home or v.phase == "uturn" then
		return 0, 0
	end
	if not v.away then
		local u = (v.s - v.spawnS) / BAY_RUN
		if u < 1 then
			return bay * (1 - smooth(u)), -bay * 6 * math.max(u, 0) * (1 - u) / BAY_RUN
		end
	else
		local u = 1 - (v.spawnS - v.s) / BAY_RUN
		if u > 0 and u <= 1 then
			return bay * smooth(u), bay * 6 * u * (1 - u) / BAY_RUN
		end
	end
	return 0, 0
end

stepClass.motorcycle = function(v, ctx, dt, events)
	local home = v.home
	local bay = if home.kerb then math.abs(home.kerb - (home.coord :: number)) else 0
	if v.phase == "idle" then
		v.visible, v.speed = true, 0
		v.lane, v.dir, v.s = home, if home.dir == 0 then 1 else home.dir, v.spawnS
		place(v, ctx, home)
		shift(v, ctx, bay, 0)
		v.timer -= dt
		if v.timer <= 0 and kerbClear(v, ctx, bay) then
			v.phase, v.away = "ride", false
			table.insert(events, "pullout")
		end
		return
	end
	local fx, fz = math.sin(v.yaw), math.cos(v.yaw)
	-- the home stretch: back on its own lane after a turn at each end, the bay ahead
	local toBay = math.huge
	if v.away and v.lane == home and v.phase ~= "uturn" and v.s <= v.spawnS then
		toBay = v.spawnS - v.s
	end
	if personNear(ctx, v.x + fx * st(2), v.z + fz * st(2), st(2), true) or playerCarAhead(v, ctx, st(2)) then
		v.speed = 0
	else
		-- follows the vehicle ahead (v5.4's riders stopped only for people, so they rode straight through
		-- every slower car on the boulevard): its speed eases down with the gap, so it settles behind a
		-- slower car at that car's speed instead of braking hard and pulling away again
		local gap = gapAhead(v, fx, fz, st(24), st(1.2), sameWay(v, ctx, fx, fz))
		local desired = math.min(
			v.cruise,
			math.max(0, (gap - st(2)) * 1.2),
			turnLimit(v, ctx),
			math.sqrt(2 * RIDER_ACCEL * toBay) + st(0.2)
		)
		v.speed = approach(v.speed, desired, (if desired < v.speed then RIDER_BRAKE else RIDER_ACCEL) * dt)
	end
	if toBay <= math.max(st(0.02), v.speed * dt) then
		-- in at the kerb
		v.phase, v.speed, v.away = "idle", 0, false
		v.n += 1
		v.timer = 53 + 22 * (v.id % 2) -- §5.12 wait 53 + 22 i
		v.s = v.spawnS
		place(v, ctx, home)
		shift(v, ctx, bay, 0)
		table.insert(events, "park")
		return
	end
	-- (slanting across to or from the kerb it covers less of the lane's length for the same ground)
	local _, slant = bayPath(v, bay)
	advanceLane(v, ctx, dt / math.sqrt(1 + slant * slant), events)
	if v.lane ~= home then
		v.away = true
	end
	local side, slope = bayPath(v, bay)
	if side ~= 0 then
		shift(v, ctx, side, slope)
	else
		v.side = 0
	end
end

local POLY_ACCEL = st(5) -- 12.5 st/s2 pulling away
local TURN_SPEED = st(2.4) -- 6 st/s round the 5 st U-turn at the scene (POLY_OFFSET): 1.2 rad/s
local POLY_BRAKE = st(6) -- 15 st/s2 into a corner or the end of the route
local CORNER_LATERAL = st(10) -- 25 st/s2 round a corner: 22 st/s through a 20 st one
local FOLLOW_BRAKE = st(3) -- 7.5 st/s2 coming up behind a vehicle: half of POLY_BRAKE, so it can be held

-- fleetInWay(v, ctx, gap): an emergency vehicle's right of way ends at a vehicle already in its way
-- (inPath): one ahead in its lane, or a lane vehicle still crossing in front of it (those that have not
-- reached its path wait for it: bracesFor). Oncoming traffic is never in the way (its own lane). Two
-- emergency vehicles crossing: the higher id waits, so they never wait for each other. Returns the body.
local function fleetInWay(v: Vehicle, ctx: Ctx, gap: number): LaneMath.Body?
	local me = AICarMotor.body(v)
	local fx, fz = math.sin(v.yaw), math.cos(v.yaw)
	for _, b in ctx.bodies do
		if b.visible == false or b.id == v.id or b.player then
			continue
		end
		local dot = math.sin(b.yaw) * fx + math.cos(b.yaw) * fz
		if dot < -0.3 then
			continue
		end
		if b.emergency and dot <= 0.3 and (b.id :: number) > v.id then
			continue -- a crossing emergency vehicle with a higher id waits for this one
		end
		if inPath(me, b, gap) then
			return b
		end
	end
	return nil
end

-- What an emergency vehicle slows down behind: fleet vehicles heading its way and players' vehicles
-- (never a crossing emergency vehicle: fleetInWay decides which of the two waits).
local function leaders(v: Vehicle, ctx: Ctx, fx: number, fz: number): { LaneMath.Body }
	local out = {}
	for _, b in ctx.bodies do
		if b.id ~= v.id and (b.player == true or math.sin(b.yaw) * fx + math.cos(b.yaw) * fz > 0.3) then
			table.insert(out, b)
		end
	end
	return out
end

-- polyline drive shared by the emergency classes: hard stop for people within r; returns true at the end.
-- The stop is not for ever: someone who stays in the way is waited for BLOCK_PATIENCE seconds, then
-- the vehicle edges on at a crawl until they are behind it. The count runs down again at the same
-- rate once the way is clear, so stepping in and out of the way does not start the wait afresh.
local function drivePolyline(
	v: Vehicle,
	ctx: Ctx,
	lane: LaneMath.Lane,
	speed: number,
	stopR: number,
	dt: number
): boolean
	local fx, fz = math.sin(v.yaw), math.cos(v.yaw)
	local len = LaneMath.length(lane, v.dir)
	local blocked = v.blocked or 0
	local inWay = personNear(ctx, v.x + fx * stopR * 0.5, v.z + fz * stopR * 0.5, stopR, true)
	if inWay then
		blocked = math.min(blocked + dt, AICarMotor.BLOCK_PATIENCE + 2)
	else
		blocked = math.max(0, blocked - dt)
	end
	v.blocked = blocked
	-- a vehicle already in its way (fleetInWay): one crossing in front of its nose is stopped for at once,
	-- as is a player's car right in front of it; one ahead in its own lane is slowed down behind (below)
	local queued = fleetInWay(v, ctx, PRIORITY_GAP)
	local crossing = queued ~= nil and math.sin(queued.yaw) * fx + math.cos(queued.yaw) * fz <= 0.3
	if (inWay and blocked <= AICarMotor.BLOCK_PATIENCE) or crossing or playerCarAhead(v, ctx, st(1.2)) then
		v.speed = 0 -- the hard stop stays instant (traffic.md §5.8)
	else
		-- pulls away, slows for each corner and brakes to a stop at the end (it used to run at full speed
		-- from the first tick to the last: 0 to 31 st/s and back in one tick), and keeps behind a
		-- vehicle ahead: it looks as far as it needs to stop (a player's car standing in the lane, the
		-- other incident car parked on the same line) and follows a moving one at its speed
		local reach = st(6) + v.speed * v.speed / (2 * FOLLOW_BRAKE)
		local room = math.max(0, gapAhead(v, fx, fz, reach, v.box.width / 2, leaders(v, ctx, fx, fz)) - st(2))
		local cap = math.min(
			if inWay then math.min(speed, AICarMotor.BLOCK_CRAWL) else speed, -- edging past someone
			LaneMath.cornerCap(lane, v.dir, v.s, CORNER_LATERAL, POLY_BRAKE),
			math.max(math.sqrt(2 * POLY_BRAKE * math.max(0, len - v.s)), st(0.4)),
			room * 1.2,
			math.sqrt(2 * FOLLOW_BRAKE * room)
		)
		v.speed = approach(v.speed, cap, (if cap < v.speed then POLY_BRAKE else POLY_ACCEL) * dt)
	end
	v.s = math.min(len, v.s + v.speed * dt)
	place(v, ctx, lane)
	-- brought to a stand near the end of its route by another emergency vehicle standing there (the
	-- incident cars' routes end one behind the other in the same lane, the second car's spot beyond the
	-- first's): it has arrived where it stands, instead of waiting out the other's hold or driving
	-- through it
	local parkedAhead = queued ~= nil and queued.emergency == true and (queued.speed or 0) < 0.5
	return v.s >= len - 1e-6 or (parkedAhead and v.speed < 0.5 and len - v.s < ARRIVE_QUEUED)
end

stepClass.legacy_ambulance = function(v, ctx, dt, events)
	if v.phase == "idle" then
		v.visible = false
		v.timer -= dt
		if v.timer <= 0 then
			v.phase = "drive"
			v.dir = 1
			appear(v, ctx, v.lane, 0)
			table.insert(events, "appear")
		end
		return
	end
	if v.phase == "park" then
		v.speed = 0
		v.timer -= dt
		if v.timer <= 0 then
			v.phase, v.timer, v.visible = "idle", 145, false
			table.insert(events, "hide")
		end
		return
	end
	local lane = v.lane
	local lastLeg = v.s > LaneMath.length(lane) - st(32)
	local speed = if lastLeg
		then (lane.speeds.ambulance_drive or st(10.625))
		else (lane.speeds.ambulance_arterial or st(12.5))
	if drivePolyline(v, ctx, lane, speed, st(5), dt) then
		v.phase, v.timer = "park", 16
		table.insert(events, "park")
	end
end

-- dispatch(v, route, ctx, held?): start a responder or incident trip on `route` (a polyline Lane).
-- With `held` the vehicle stays on scene until `release` instead of leaving on the scene timer.
function AICarMotor.dispatch(v: Vehicle, route: LaneMath.Lane, ctx: Ctx, held: boolean?)
	v.route = route
	v.dir = 1
	v.phase = "out"
	v.timer = 0
	v.blocked = 0
	v.held = if held then true else nil -- nil: the plain scene timer; false (after release): leave at once
	appear(v, ctx, route, 0)
end

-- release(v): a held trip may leave: at once when it is on scene, on arrival when still on the way.
function AICarMotor.release(v: Vehicle)
	v.held = false
	if v.phase == "hold" then
		v.timer = 0
	end
end

local function trip(
	v: Vehicle,
	ctx: Ctx,
	dt: number,
	events: { string },
	outSpeed: number,
	backSpeed: number,
	holdSecs: number
)
	local route = v.route
	if v.phase == "idle" or not route then
		v.visible = false
		v.speed = 0
		return
	end
	if v.phase == "hold" then
		v.speed = 0
		if not v.held then
			v.timer -= dt
			if v.timer <= 0 then
				v.phase, v.timer = "turn", 0
			end
		end
		place(v, ctx, route)
		return
	end
	if v.phase == "turn" then
		-- a U-turn onto the return side of the road (it used to flip round on the spot and jump 15 st
		-- sideways to the return path's start): a half circle of POLY_OFFSET from the end of the route
		local r = LaneMath.POLY_OFFSET
		v.speed = approach(v.speed, TURN_SPEED, POLY_ACCEL * dt)
		local d = v.timer + v.speed * dt
		if d >= math.pi * r then
			v.phase, v.dir, v.s, v.timer = "back", -1, math.min(d - math.pi * r, LaneMath.length(route, -1)), 0
			place(v, ctx, route)
			return
		end
		v.timer = d
		local e = LaneMath.pointAt(route, LaneMath.length(route, 1), 1)
		local p = LaneMath.halfTurn(e.x, e.z, e.yaw, r, d)
		v.x, v.z, v.yaw = p.x, p.z, p.yaw
		v.y = ctx.heightAt(v.x, v.z) + BASE_LIFT
		return
	end
	local done = drivePolyline(v, ctx, route, if v.phase == "out" then outSpeed else backSpeed, st(3.1), dt)
	if done and v.phase == "out" then
		-- a held trip waits for release (timer 0 then); one released on the way turns straight round
		v.phase, v.timer = "hold", if v.held == nil then holdSecs else 0
		table.insert(events, "arrived")
	elseif done then
		v.phase, v.route, v.visible, v.held = "idle", nil, false, nil
		table.insert(events, "home")
	end
end

stepClass.responder = function(v, ctx, dt, events)
	local sp = v.lane.speeds
	trip(v, ctx, dt, events, sp.outbound or st(24), sp["return"] or st(25), ctx.sceneSecs or 30)
end

stepClass.incident = function(v, ctx, dt, events)
	trip(v, ctx, dt, events, v.lane.speeds.police_car or st(23), v.lane.speeds.police_car or st(23), 48)
end

stepClass.event = function(v, ctx, dt, events)
	local phase = (ctx.now - v.offset) % 2400
	local t: number? = nil
	if phase < 600 then
		t = math.min(1, phase / 48)
	elseif phase < 650 then
		t = 1 - (phase - 600) / 50
	end
	if t == nil then
		if v.visible then
			table.insert(events, "hide")
		end
		v.visible, v.speed = false, 0
		return
	end
	if not v.visible then
		v.visible = true
		v.teleported = true
		table.insert(events, "appear")
	end
	local lane = v.lane
	local s = (t :: number) * lane.length
	v.speed = math.abs(s - v.s) / math.max(dt, 1e-6)
	v.s = s
	place(v, ctx, lane, math.pi) -- yaw PI throughout (§5.11)
end

-- step(v, ctx, dt) -> events. Sets v.teleported for this tick (cleared at the start of every step).
function AICarMotor.step(v: Vehicle, ctx: Ctx, dt: number): { string }
	v.teleported = false
	local events = {}
	if v.phase == "queued" then
		-- a wrap waiting for its lane's start to clear
		if spotClear(v, ctx, v.x, v.z) then
			v.phase = "drive"
			appear(v, ctx, v.lane, v.s)
			table.insert(events, "appear")
		end
		v.moving = false
		return events
	end
	local fn = stepClass[v.class] or error(`AICarMotor: unknown class {v.class}`)
	local px, pz = v.x, v.z
	fn(v, ctx, dt, events)
	v.moving = v.visible and (math.abs(v.x - px) + math.abs(v.z - pz)) > 1e-4
	return events
end

return AICarMotor
