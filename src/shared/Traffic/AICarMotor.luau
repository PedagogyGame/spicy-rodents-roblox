--!strict
-- ReplicatedStorage.Shared.Traffic.AICarMotor
-- The AI car motor: one fleet vehicle on its lane, per behaviour class, with yielding, stop control and
-- teleport flags (BUILD_PLAN §4.4 W1 #9, D9; traffic.md §5, §6, §13). Movement/CarMotor is the player
-- kinematic car (Track A #5); this is the lane layer the server fleet runs.
-- Interface: new(entry, lane, opts) -> Vehicle; step(v, ctx, dt) -> events; dispatch(v, route, opts);
--            body(v) -> LaneMath.Body; CLASSES; VIS_HEIGHT
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
--   event (§5.11): the 2400 s living-event glide (fatal even at a crawl).
-- Rebuild fixes (traffic.md §11-§13): squirrels are in every yielding class's hazard set with RELATIVE
-- visibility (squirrel y - vehicle base y < 4.76 u, not the absolute 4.8); opposing vehicles are excluded
-- from the same-lane tests (the trolley deadlock, §6.1); emergency classes keep at least the hard stop
-- for people. A wrap, an appearance and a dispatch set `teleported` for that tick (SweptCollision skips it).

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
	local hidden = e.class == "motorcycle"
		or e.class == "legacy_ambulance"
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
		phase = if hidden then "idle" else "drive",
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

-- Which bodies a lane vehicle brakes for: fleet vehicles heading its way (opposing traffic excluded, §6.1,
-- the trolley deadlock); every player's vehicle in its path whatever its heading (a car parked across the
-- lane is still in the way; a player's car never waits for the fleet, so no deadlock); and an emergency
-- vehicle crossing or entering its path (right of way), unless this vehicle is already in the emergency
-- vehicle's own way: then it keeps going to clear it, and the emergency vehicle waits (drivePolyline).
-- Without this the ambulances and incident cars, which yield to no vehicle in v5.4, and the lane traffic
-- drove through each other wherever a call route crosses a street.
local function bracesFor(v: Vehicle, b: LaneMath.Body, fx: number, fz: number): boolean
	if b.player == true or math.sin(b.yaw) * fx + math.cos(b.yaw) * fz > 0.3 then
		return true
	end
	return b.emergency == true and not inPath(b, AICarMotor.body(v), PRIORITY_GAP)
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

local function appear(v: Vehicle, ctx: Ctx, lane: LaneMath.Lane, s: number)
	v.s = s
	v.visible = true
	v.teleported = true
	place(v, ctx, lane)
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

-- one-way lane motion with the wrap teleport
local function advanceLane(v: Vehicle, ctx: Ctx, dt: number, events: { string })
	local lane = v.lane
	if v.class == "patrol" then
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
			v.teleported = true
			v.stop = Control.newState()
			table.insert(events, "wrap")
		end
	end
	place(v, ctx, lane)
end

local stepClass: { [string]: (Vehicle, Ctx, number, { string }) -> () } = {}

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
	if not danger then
		danger =
			LaneMath.vehicleAhead(AICarMotor.body(v), fx, fz, st(9) + 0.65 * v.speed, st(1.2), sameWay(v, ctx, fx, fz))
	end
	local cap = stopCap(v, ctx, st(9), dt, events)
	local desired = if danger then 0 else math.min(v.cruise, cap)
	local rate = if desired < v.speed then 9 else 1.3
	v.speed += (desired - v.speed) * (1 - math.exp(-dt * rate))
	if v.speed < 1e-3 and desired == 0 then
		v.speed = 0
	end
	-- hard stop: any visible human within 3.1 of the next position (no hospital filter, §5.1 step 4)
	local nx, nz = v.x + fx * v.speed * dt, v.z + fz * v.speed * dt
	if personNear(ctx, nx, nz, st(3.1), false) then
		v.speed = 0
		place(v, ctx, v.lane)
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
	down: number
)
	local fx, fz = math.sin(v.yaw), math.cos(v.yaw)
	local hw = v.box.width / 2
	local danger = LaneMath.seesHazard(v.x, v.z, fx, fz, range, hw, hazards(v, ctx, fx, fz, true)) ~= nil
		or LaneMath.vehicleAhead(AICarMotor.body(v), fx, fz, tva, hw, sameWay(v, ctx, fx, fz))
	local cap = stopCap(v, ctx, down, dt, events)
	local desired = if danger then 0 else math.min(v.cruise, cap)
	v.speed = approach(v.speed, desired, (if desired < v.speed then down else up) * dt)
	advanceLane(v, ctx, dt, events)
end

stepClass.heavy = function(v, ctx, dt, events)
	yielding(v, ctx, dt, events, st(10), st(11), st(3.2), st(10))
end

stepClass.patrol = function(v, ctx, dt, events)
	yielding(v, ctx, dt, events, st(10), st(11), st(3.2), st(10))
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
		local desired = if danger then 0 else math.min(v.cruise, math.sqrt(2 * st(5.0) * dist))
		v.speed = approach(v.speed, desired, (if desired < v.speed then st(11) else st(4.5)) * dt)
		if not danger and dist <= math.max(st(0.35), v.speed * dt + st(0.35)) then
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
		if not danger and math.abs(destX - x) < st(0.25) then
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

stepClass.motorcycle = function(v, ctx, dt, events)
	if v.phase == "idle" then
		v.visible = false
		v.timer -= dt
		if v.timer <= 0 then
			v.phase = "ride"
			v.speed = v.cruise
			appear(v, ctx, v.lane, v.spawnS)
			table.insert(events, "appear")
		end
		return
	end
	local fx, fz = math.sin(v.yaw), math.cos(v.yaw)
	if personNear(ctx, v.x + fx * st(2), v.z + fz * st(2), st(2), true) or playerCarAhead(v, ctx, st(2)) then
		v.speed = 0
	else
		v.speed = v.cruise
	end
	local s = v.s + v.speed * dt
	if s >= v.lane.length - st(3) then
		v.phase = "idle"
		v.visible = false
		v.n += 1
		v.timer = 53 + 22 * (v.id % 2) -- §5.12 wait 53 + 22 i
		table.insert(events, "despawn")
		return
	end
	v.s = s
	place(v, ctx, v.lane)
end

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

-- polyline drive shared by the emergency classes: hard stop for people within r; returns true at the end
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
	local queued = fleetInWay(v, ctx, PRIORITY_GAP)
	if
		personNear(ctx, v.x + fx * stopR * 0.5, v.z + fz * stopR * 0.5, stopR, true)
		or playerCarAhead(v, ctx, stopR)
		or queued ~= nil
	then
		v.speed = 0
	else
		v.speed = speed
	end
	v.s = math.min(len, v.s + v.speed * dt)
	place(v, ctx, lane)
	-- held up near the end of its route by another emergency vehicle standing there (the incident cars'
	-- routes end one behind the other in the same lane, the second car's spot beyond the first's): it has
	-- arrived where it stands, instead of waiting out the other's hold or driving through it
	local parkedAhead = queued ~= nil and queued.emergency == true and (queued.speed or 0) < 0.5
	return v.s >= len - 1e-6 or (parkedAhead and len - v.s < ARRIVE_QUEUED)
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

-- dispatch(v, route, opts): start a responder or incident trip on `route` (a polyline Lane).
function AICarMotor.dispatch(v: Vehicle, route: LaneMath.Lane, ctx: Ctx)
	v.route = route
	v.dir = 1
	v.phase = "out"
	v.timer = 0
	appear(v, ctx, route, 0)
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
		v.timer -= dt
		if v.timer <= 0 then
			v.phase, v.dir, v.s = "back", -1, 0
		end
		place(v, ctx, route)
		return
	end
	local done = drivePolyline(v, ctx, route, if v.phase == "out" then outSpeed else backSpeed, st(3.1), dt)
	if done and v.phase == "out" then
		v.phase, v.timer = "hold", holdSecs
		table.insert(events, "arrived")
	elseif done then
		v.phase, v.route, v.visible = "idle", nil, false
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
	local fn = stepClass[v.class] or error(`AICarMotor: unknown class {v.class}`)
	local px, pz = v.x, v.z
	fn(v, ctx, dt, events)
	v.moving = v.visible and (math.abs(v.x - px) + math.abs(v.z - pz)) > 1e-4
	return events
end

return AICarMotor
