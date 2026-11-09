--!strict
-- ReplicatedStorage.Shared.Movement.SquirrelMotor
-- Squirrel rail/ground motor shared by AI (server) and players (client).
-- Interface (BUILD_PLAN §1.4, D2): new(params), step(state, input, dt, world) -> state, events, serialize, deserialize, envelope
--
-- A port of v5.4's `updatePlayer` (reference/v5_4_game.js L6573-6770) and the launch helpers
-- (leap L5922, Q drop L5672, attemptPounce L6482, jumpVelocity L5915, pounceVelocity L6473,
-- attackHeading L5900, enterRoute L5826, attachRoute L5870) for a squirrel actor, in studs:
--   GROUND  camera-relative WASD, accel 23 / drag 13 (air 4.2 / 1.15), turn 25 (19 in focus),
--           walk 8, sprint 16.8, stalk 1.65 u/s, x1.6 boost; gravity 30 u/s^2; ground snap;
--           swept per-axis wall sliding (0.24 u steps, x0.28 on a blocked axis) through world.blocked
--   ROUTE   RouteMotion.advance at the rail speed, direction held while the key is held, fork
--           auto-take, end-of-route auto switch, transfer easing (routeBridge), body yaw along the
--           tangent; W/S only
--   AIR     ballistic while attackWindow > 0; landing clears committedAirborne
-- Edge actions per frame: leap (Space), drop (Q), grab (E), choose (A/D), pounce (left click).
-- The motor is pure: `step(state, input, dt, world)` mutates and returns `state` plus a list of
-- events, uses only the Routes modules and the `world.groundAt`/`world.blocked` callbacks, and runs
-- under Lune. `serialize`/`deserialize` give the flat snapshot that possession hands over
-- mid-stride (BUILD_PLAN §1.5) and that the client streams to Server/Movement/MoveValidator.
-- Frame timing as v5.4 tick (routes_movement §6): dt capped at 0.08 s, substeps of at most 1/60 s
-- (max 5). Numbers are v5.4 constants (routes_movement §8, §10, §13) with the spec line cited; they
-- are collected in `SquirrelMotor.params` so the Tunables tree can take them over in W1.

local Curve = require("../Routes/Curve")
local Motion = require("../Routes/Motion")
local Registry = require("../Routes/Registry")
local Units = require("../Config/Units")

local SquirrelMotor = {}

export type Vec3 = Curve.Vec3
export type World = Motion.World & {
	-- standable height (studs) at (x, z) for a body whose reference y is refY (World/Ground in W1)
	groundAt: (x: number, z: number, refY: number) -> number,
	-- optional wall test: true when a body of the squirrel radius at (x, z, y) overlaps a collider
	blocked: ((x: number, z: number, y: number) -> boolean)?,
	-- optional world clamp (studs); defaults to the v5.4 rectangle
	clamp: { minX: number, maxX: number, minZ: number, maxZ: number }?,
}

export type Input = {
	fw: number, -- W/S: +1 forward, -1 back (ArrowUp/Down alias)
	side: number, -- D/A: +1 right, -1 left
	sprint: boolean,
	focus: boolean, -- stalk held or toggled
	cameraYaw: number, -- the orbit camera yaw (HTML convention: forward = (-sin, -cos))
	cameraPitch: number,
	leap: boolean, -- Space pressed this frame
	drop: boolean, -- Q pressed this frame
	grab: boolean, -- E pressed this frame
	choose: number, -- A/D pressed this frame: -1 / 0 / +1
	pounce: boolean, -- left click this frame
}

export type Bridge = {
	fx: number,
	fy: number,
	fz: number,
	tx: number,
	ty: number,
	tz: number,
	elapsed: number,
	duration: number,
}

export type State = {
	x: number,
	y: number,
	z: number,
	vx: number,
	vy: number,
	vz: number,
	yaw: number,
	grounded: boolean,
	routeId: number?,
	railT: number,
	railDir: number,
	moveSpeed: number,
	boostRemaining: number,
	cooldown: number,
	attack: number,
	attackWindow: number,
	cameraCommit: number,
	committedAirborne: boolean,
	focus: boolean,
	trunkNormalX: number,
	trunkNormalZ: number,
	routeWasMoving: boolean,
	routeFreeLook: number,
	pendingFork: number?, -- branch id of the chosen fork (pendingFork.branch)
	selectedJunction: number?, -- route id of the A/D junction selection
	bridge: Bridge?,
	clock: number, -- accumulated simulated seconds (packet timestamps)
	alive: boolean,
}

export type Event = { kind: string, routeId: number?, fromRouteId: number?, reason: string? }

-- Snapshot: a flat table of numbers and booleans (no nesting) for remotes, attributes and handoff.
export type Snapshot = { [string]: number | boolean }

local st = Units.st
SquirrelMotor.params = {
	-- ground (routes_movement §8.1-§8.2)
	walk = st(8.0),
	sprint = st(16.8),
	stalk = st(1.65),
	boostMult = 1.6,
	treeTravelMult = 0.6,
	speedSmoothFocus = 11,
	speedSmooth = 17,
	accelGround = 23,
	accelAir = 4.2,
	dragGround = 13,
	dragAir = 1.15,
	turnRate = 25,
	turnRateFocus = 19,
	faceCameraRate = 11,
	gravity = st(30), -- SQUIRREL_GRAVITY (L6472)
	-- walk-in auto-grab (§9.1)
	autoGrabMinSpeed = st(0.45),
	-- leap and pounce (§13; L5915-5921, L6473-6481)
	leapForward = st(16.5),
	leapForwardBoost = st(18.5),
	leapUp = st(12.8),
	dropUp = st(3.3),
	pouncePitchMin = -0.54,
	pouncePitchMax = 0.9,
	pounceSpeedFocus = st(12.4),
	pounceSpeedFast = st(13.5),
	pounceSpeedSlow = st(11.3),
	pounceFastAbove = st(12),
	pounceBoostMult = 1.12,
	pounceUpBase = st(3.45),
	pounceUpPitch = st(2.1),
	pounceCooldown = 0.7,
	pounceAttack = 0.38,
	pounceWindow = 0.78,
	cameraCommitLaunch = 0.52,
	cameraCommitDrop = 0.32,
	cameraCommitLand = 0.35,
	-- transfer heading hold (§10)
	freeLookAfterTransfer = 0.65,
	-- wall sweep (§8.3)
	sweepStep = st(0.24),
	sweepMaxSteps = 18,
	blockedDamp = 0.28,
	-- frame timing (§6)
	frameDtCap = 0.08,
	substep = 1 / 60,
	maxSubsteps = 5,
	-- world clamp (§8.6): x in [-586, 1146], z in [-560, 436] u
	clampMinX = st(-586),
	clampMaxX = st(1146),
	clampMinZ = st(-560),
	clampMaxZ = st(436),
}
local P = SquirrelMotor.params
local C = Motion.C

function SquirrelMotor.new(x: number, y: number, z: number): State
	return {
		x = x,
		y = y,
		z = z,
		vx = 0,
		vy = 0,
		vz = 0,
		yaw = 0,
		grounded = true,
		routeId = nil,
		railT = 0,
		railDir = 1,
		moveSpeed = 0,
		boostRemaining = 0,
		cooldown = 0,
		attack = 0,
		attackWindow = 0,
		cameraCommit = 0,
		committedAirborne = false,
		focus = false,
		trunkNormalX = 0,
		trunkNormalZ = 1,
		routeWasMoving = false,
		routeFreeLook = 0,
		pendingFork = nil,
		selectedJunction = nil,
		bridge = nil,
		clock = 0,
		alive = true,
	}
end

function SquirrelMotor.idleInput(cameraYaw: number?): Input
	return {
		fw = 0,
		side = 0,
		sprint = false,
		focus = false,
		cameraYaw = cameraYaw or math.pi,
		cameraPitch = 0.12,
		leap = false,
		drop = false,
		grab = false,
		choose = 0,
		pounce = false,
	}
end

-- attackHeading() (L5900-5906): straight out from the bark on a trunk, else the body yaw.
function SquirrelMotor.attackHeading(onTrunk: boolean, trunkNormalX: number?, trunkNormalZ: number?, yaw: number): number
	if onTrunk then
		return math.atan2(trunkNormalX or 0, trunkNormalZ or 1)
	end
	return yaw
end

-- jumpVelocity() (L5915-5921), studs/s.
function SquirrelMotor.jumpVelocity(heading: number, boosted: boolean): (number, number, number)
	local forward = if boosted then P.leapForwardBoost else P.leapForward
	return math.sin(heading) * forward, P.leapUp, math.cos(heading) * forward
end

-- pounceVelocity() (L6473-6481), studs/s. moveSpeed in studs/s.
function SquirrelMotor.pounceVelocity(
	pitch: number,
	focus: boolean,
	moveSpeed: number,
	boosted: boolean,
	heading: number
): (number, number, number)
	local p = math.clamp(pitch, P.pouncePitchMin, P.pouncePitchMax)
	local speed = (if focus then P.pounceSpeedFocus elseif moveSpeed > P.pounceFastAbove then P.pounceSpeedFast else P.pounceSpeedSlow)
		* (if boosted then P.pounceBoostMult else 1)
	local vertical = P.pounceUpBase + math.sin(p) * P.pounceUpPitch
	return math.sin(heading) * speed * math.cos(p), vertical, math.cos(heading) * speed * math.cos(p)
end

-- Serialisation --------------------------------------------------------------------------------------

local SCALARS = {
	"x",
	"y",
	"z",
	"vx",
	"vy",
	"vz",
	"yaw",
	"railT",
	"railDir",
	"moveSpeed",
	"boostRemaining",
	"cooldown",
	"attack",
	"attackWindow",
	"cameraCommit",
	"trunkNormalX",
	"trunkNormalZ",
	"routeFreeLook",
	"clock",
}
local FLAGS = { "grounded", "committedAirborne", "focus", "routeWasMoving", "alive" }
local OPTIONAL_IDS = { "routeId", "pendingFork", "selectedJunction" }

function SquirrelMotor.serialize(state: State): Snapshot
	local s: Snapshot = {}
	local anyState = state :: any
	for _, k in SCALARS do
		s[k] = anyState[k]
	end
	for _, k in FLAGS do
		s[k] = anyState[k]
	end
	for _, k in OPTIONAL_IDS do
		local v = anyState[k]
		s[k] = if v == nil then -1 else v
	end
	local b = state.bridge
	s.bridgeActive = b ~= nil
	if b then
		s.bfx, s.bfy, s.bfz = b.fx, b.fy, b.fz
		s.btx, s.bty, s.btz = b.tx, b.ty, b.tz
		s.bElapsed, s.bDuration = b.elapsed, b.duration
	end
	return s
end

function SquirrelMotor.deserialize(s: Snapshot): State
	local state = SquirrelMotor.new(0, 0, 0) :: any
	for _, k in SCALARS do
		local v = s[k]
		if type(v) ~= "number" then
			error(`SquirrelMotor.deserialize: {k} missing`)
		end
		state[k] = v
	end
	for _, k in FLAGS do
		local v = s[k]
		if type(v) ~= "boolean" then
			error(`SquirrelMotor.deserialize: {k} missing`)
		end
		state[k] = v
	end
	for _, k in OPTIONAL_IDS do
		local v = s[k]
		if type(v) ~= "number" then
			error(`SquirrelMotor.deserialize: {k} missing`)
		end
		state[k] = if v < 0 then nil else v
	end
	if s.bridgeActive == true then
		state.bridge = {
			fx = s.bfx :: number,
			fy = s.bfy :: number,
			fz = s.bfz :: number,
			tx = s.btx :: number,
			ty = s.bty :: number,
			tz = s.btz :: number,
			elapsed = s.bElapsed :: number,
			duration = s.bDuration :: number,
		}
	end
	return state :: State
end

function SquirrelMotor.clone(state: State): State
	return SquirrelMotor.deserialize(SquirrelMotor.serialize(state))
end

-- Helpers ---------------------------------------------------------------------------------------------

local function route(world: World, id: number?): Registry.Route?
	if id == nil then
		return nil
	end
	return world.registry:get(id)
end

local function push(events: { Event }, kind: string, routeId: number?, fromRouteId: number?, reason: string?)
	table.insert(events, { kind = kind, routeId = routeId, fromRouteId = fromRouteId, reason = reason })
end

local function clearPendingFork(state: State)
	state.pendingFork = nil
end

-- enterRoute(found) (L5826-5869). Returns false when the transfer is refused.
local function enterRoute(state: State, world: World, spec: Motion.EnterSpec, input: Input, events: { Event}): boolean
	local target = route(world, spec.routeId)
	if not target or spec.t ~= spec.t then
		return false
	end
	local wasOnRoute = state.routeId ~= nil
	local dest = world.registry:pointAt(target, spec.t)
	local gx, gy, gz = dest.x - state.x, dest.y - state.y, dest.z - state.z
	local gap = math.sqrt(gx * gx + gy * gy + gz * gz)
	if wasOnRoute and gap > C.enterMaxGap then
		push(events, "transferRefused", spec.routeId, state.routeId, "gap")
		return false
	end
	local fromRouteId = state.routeId
	if wasOnRoute and gap > C.bridgeMinGap then
		state.bridge = {
			fx = state.x,
			fy = state.y,
			fz = state.z,
			tx = dest.x,
			ty = dest.y,
			tz = dest.z,
			elapsed = 0,
			duration = Motion.bridgeDuration(gap),
		}
	else
		state.bridge = nil
	end
	local approachX, approachZ = state.x, state.z
	state.routeId = target.id
	state.railT = spec.t
	local desired = spec.dir or Motion.directionFromView(world, target, spec.t, input.cameraYaw, state.yaw, 1)
	state.railDir = Motion.inward(spec.t, desired)
	if not state.bridge then
		state.x, state.y, state.z = dest.x, dest.y, dest.z
	end
	state.routeWasMoving = spec.dir ~= nil and input.fw ~= 0
	if wasOnRoute then
		state.routeFreeLook = math.max(state.routeFreeLook, P.freeLookAfterTransfer)
	end
	local heading = Motion.headingAlong(world, target, spec.t, state.railDir)
	if heading then
		state.yaw = heading
	end
	if target.kind == "trunk" then
		local rx, rz = approachX - dest.x, approachZ - dest.z
		local lenSq = rx * rx + rz * rz
		if lenSq > st(1) * st(1) * 0.015 then
			local l = math.sqrt(lenSq)
			state.trunkNormalX, state.trunkNormalZ = rx / l, rz / l
		else
			state.trunkNormalX, state.trunkNormalZ = -math.sin(input.cameraYaw), -math.cos(input.cameraYaw)
		end
	else
		clearPendingFork(state)
	end
	state.selectedJunction = nil
	state.vx, state.vy, state.vz = 0, 0, 0
	state.grounded = false
	state.committedAirborne = false
	push(events, if wasOnRoute then "transfer" else "attach", target.id, fromRouteId)
	return true
end

local function visualPosition(state: State, world: World): Vec3
	local r = route(world, state.routeId)
	if not r then
		return Curve.vec3(state.x, state.y, state.z)
	end
	return Motion.visualPose(world, r, state.railT, Curve.vec3(state.x, state.y, state.z), state.trunkNormalX, state.trunkNormalZ)
end

-- launchFromVisibleRoute (L5891-5897): a leap starts at the visible position, not the centreline.
local function launchFromVisibleRoute(state: State, world: World)
	if state.routeId then
		local v = visualPosition(state, world)
		state.x, state.y, state.z = v.x, v.y, v.z
		clearPendingFork(state)
	end
	state.bridge = nil
end

local function commitToAir(state: State, heading: number)
	state.yaw = heading
	state.cameraCommit = P.cameraCommitLaunch
	state.committedAirborne = true
	state.focus = false
end

local function onTrunk(state: State, world: World): boolean
	local r = route(world, state.routeId)
	return r ~= nil and r.kind == "trunk"
end

-- Edge actions (key handler L5659-5681, leap L5922, attemptPounce L6482) --------------------------------

local function doLeap(state: State, world: World, events: { Event })
	if state.routeId or state.grounded then
		local heading = SquirrelMotor.attackHeading(onTrunk(state, world), state.trunkNormalX, state.trunkNormalZ, state.yaw)
		local vx, vy, vz = SquirrelMotor.jumpVelocity(heading, state.boostRemaining > 0)
		local from = state.routeId
		launchFromVisibleRoute(state, world)
		state.vx, state.vy, state.vz = vx, vy, vz
		state.routeId = nil
		state.grounded = false
		commitToAir(state, heading)
		push(events, "leap", nil, from)
	end
end

local function doDrop(state: State, world: World, events: { Event })
	if state.routeId then
		local from = state.routeId
		launchFromVisibleRoute(state, world)
		clearPendingFork(state)
		state.routeId = nil
		state.vy = P.dropUp
		state.committedAirborne = true
		state.cameraCommit = P.cameraCommitDrop
		push(events, "drop", nil, from)
	end
end

local function doPounce(state: State, world: World, input: Input, events: { Event })
	if state.cooldown > 0 then
		return
	end
	local heading = SquirrelMotor.attackHeading(onTrunk(state, world), state.trunkNormalX, state.trunkNormalZ, state.yaw)
	local vx, vy, vz = SquirrelMotor.pounceVelocity(input.cameraPitch, state.focus, state.moveSpeed, state.boostRemaining > 0, heading)
	local from = state.routeId
	state.cooldown = P.pounceCooldown
	state.attack = P.pounceAttack
	state.attackWindow = P.pounceWindow
	launchFromVisibleRoute(state, world)
	state.vx, state.vy, state.vz = vx, vy, vz
	state.routeId = nil
	state.grounded = false
	commitToAir(state, heading)
	push(events, "pounce", nil, from)
end

local function doChoose(state: State, world: World, input: Input, events: { Event })
	local r = route(world, state.routeId)
	if not r then
		return
	end
	local side = input.choose
	if r.kind == "trunk" then
		local fork = Motion.chooseCanopyFork(world, r, state.railT, state.y, input.cameraYaw, side, state.pendingFork)
		if fork then
			state.pendingFork = fork.branch
			push(events, "forkChosen", fork.branch, r.id)
		else
			clearPendingFork(state)
		end
		return
	end
	if r.kind == "branch" then
		local hop = Motion.sideStepToSibling(world, r, state.railT, input.cameraYaw, side)
		if hop and enterRoute(state, world, hop, input, events) then
			push(events, "branchHop", hop.routeId, r.id)
			return
		end
	end
	local picked = Motion.chooseRouteJunction(world, r, state.railT, state.railDir, input.cameraYaw, state.yaw, side, state.selectedJunction)
	state.selectedJunction = picked
	if picked then
		push(events, "junctionChosen", picked, r.id)
	end
end

-- attachRoute (L5870-5890) after takeSelectedFork (E key order L5666-5670).
local function doGrab(state: State, world: World, input: Input, events: { Event })
	local r = route(world, state.routeId)
	if r then
		-- takeSelectedFork() first (key handler), then attachRoute's rail branch
		if state.pendingFork then
			local fork = world.graph:forkOf(state.pendingFork)
			if fork then
				local spec = Motion.takeFork(fork, r.id, state.y, false)
				if spec then
					clearPendingFork(state)
					if enterRoute(state, world, spec, input, events) then
						push(events, "forkTaken", spec.routeId, r.id)
						return
					end
				end
			end
		end
		local junction = Motion.takeSelectedJunction(world, r, state.railT, state.railDir, input.cameraYaw, state.yaw, state.selectedJunction)
		if junction then
			if enterRoute(state, world, junction, input, events) then
				return
			end
		else
			state.selectedJunction = nil
		end
		if state.pendingFork and r.kind == "trunk" then
			push(events, "hint", nil, nil, "climbCloser")
			return
		end
		local next = Motion.nearestRoute(world, state.x, state.y, state.z, C.eSearch, r.id)
		if next and Motion.canTransfer(next.d, true) then
			enterRoute(state, world, { routeId = next.routeId, t = next.t, d = next.d }, input, events)
		else
			push(events, "hint", nil, nil, "noTransfer")
		end
	else
		local found: Motion.Candidate? = nil
		if state.grounded then
			found = Motion.groundTrunkCandidate(world, state.x, state.y, state.z, C.groundReachE)
		end
		if not found then
			found = Motion.nearestRoute(world, state.x, state.y, state.z, C.airGrab)
		end
		if found then
			enterRoute(state, world, { routeId = found.routeId, t = found.t, d = found.d }, input, events)
		else
			push(events, "hint", nil, nil, "nothingNear")
		end
	end
end

-- Substep ----------------------------------------------------------------------------------------------

-- resolveOutdoorMovement (L6411-6447): swept per-axis sliding against world.blocked.
local function resolveWalls(state: State, world: World, oldX: number, oldZ: number)
	local blocked = world.blocked
	if not blocked then
		return
	end
	local dx, dz = state.x - oldX, state.z - oldZ
	local dist = math.sqrt(dx * dx + dz * dz)
	if dist == 0 then
		return
	end
	local steps = math.clamp(math.ceil(dist / P.sweepStep), 1, P.sweepMaxSteps)
	local sx, sz = dx / steps, dz / steps
	local x, z = oldX, oldZ
	local y = state.y
	for _ = 1, steps do
		local okX = not blocked(x + sx, z, y)
		local okZ = not blocked(x, z + sz, y)
		if okX and okZ then
			if not blocked(x + sx, z + sz, y) then
				x += sx
				z += sz
			else
				-- the diagonal is blocked although each axis is free: slide on one axis
				x += sx
				state.vz *= P.blockedDamp
			end
		elseif okX then
			x += sx
			state.vz *= P.blockedDamp
		elseif okZ then
			z += sz
			state.vx *= P.blockedDamp
		else
			state.vx *= P.blockedDamp
			state.vz *= P.blockedDamp
			break
		end
	end
	state.x, state.z = x, z
end

local function substep(state: State, input: Input, dt: number, world: World, events: { Event })
	local reg = world.registry
	state.cameraCommit = math.max(0, state.cameraCommit - dt)
	local rail = route(world, state.routeId)
	state.focus = input.focus
		and not state.committedAirborne
		and state.cameraCommit == 0
		and not (rail ~= nil and rail.kind == "trunk")
	state.cooldown = math.max(0, state.cooldown - dt)
	state.attack = math.max(0, state.attack - dt)
	state.attackWindow = math.max(0, state.attackWindow - dt)
	state.boostRemaining = math.max(0, state.boostRemaining - dt)

	local fw, side = input.fw, input.side
	local moving = if rail then fw ~= 0 else (fw ~= 0 or side ~= 0)
	local sprint = input.sprint
	local treeTravel = rail ~= nil and rail.flags.treeTravel
	local base = (if state.focus then P.stalk elseif sprint then P.sprint else P.walk)
		* (if state.boostRemaining > 0 and not state.focus then P.boostMult else 1)
		* (if treeTravel then P.treeTravelMult else 1)
	local target = if moving then base else 0
	state.moveSpeed += (target - state.moveSpeed) * (1 - math.exp(-dt * (if state.focus then P.speedSmoothFocus else P.speedSmooth)))

	local oldX, oldY, oldZ = state.x, state.y, state.z

	-- walk-in auto-grab (L6630-6642)
	if not rail and state.grounded and state.attackWindow == 0 and fw > 0 and state.moveSpeed > P.autoGrabMinSpeed then
		local nearby = Motion.groundTrunkCandidate(world, state.x, state.y, state.z, C.walkInReach)
		if Motion.forwardIntoTrunk(world, nearby, state.x, state.z, fw, side, input.cameraYaw) and nearby then
			if enterRoute(state, world, { routeId = nearby.routeId, t = 0, d = nearby.d }, input, events) then
				rail = route(world, state.routeId)
			end
		end
	end

	if rail then
		local rs = rail
		local bridge = state.bridge
		if bridge then
			bridge.elapsed = math.min(bridge.duration, bridge.elapsed + math.min(dt, C.bridgeMaxStep))
			local progress = Motion.ease(bridge.elapsed / bridge.duration)
			state.x = bridge.fx + (bridge.tx - bridge.fx) * progress
			state.y = bridge.fy + (bridge.ty - bridge.fy) * progress
			state.z = bridge.fz + (bridge.tz - bridge.fz) * progress
			state.vx, state.vy, state.vz = 0, 0, 0
			if progress >= 1 then
				state.bridge = nil
			end
		else
			if not state.routeWasMoving and fw ~= 0 then
				state.railDir = Motion.directionFromView(world, rs, state.railT, input.cameraYaw, state.yaw, state.railDir)
			end
			state.routeWasMoving = fw ~= 0
			local railSpeed = Motion.railSpeed(rs.flags.treeTravel, sprint, state.focus, state.boostRemaining > 0)
			local before = state.railT
			state.railT = Motion.advance(state.railT, state.railDir, fw, dt, railSpeed, rs.length)
			-- fork auto-take while holding W (L6676-6686)
			if state.pendingFork and rs.kind == "trunk" then
				local fork = world.graph:forkOf(state.pendingFork)
				if fork and fork.trunk == rs.id and Motion.forkAutoTake(fork, rs, before, state.railT, fw) then
					state.railT = fork.t
					local p = reg:pointAt(rs, state.railT)
					state.x, state.y, state.z = p.x, p.y, p.z
					local spec = Motion.takeFork(fork, rs.id, state.y, true)
					if spec then
						clearPendingFork(state)
						if enterRoute(state, world, spec, input, events) then
							push(events, "forkTaken", spec.routeId, rs.id)
						end
					end
				end
			end
			if state.routeId == rs.id and (state.railT > 1 or state.railT < 0) then
				local atStart = state.railT < 0
				state.railT = math.clamp(state.railT, 0, 1)
				if fw ~= 0 then
					local result = Motion.switchRoute(world, rs, atStart, input.cameraYaw, state.selectedJunction)
					local switched = false
					if result.chosen then
						switched = enterRoute(state, world, result.chosen, input, events)
						if switched then
							push(events, "autoSwitch", result.chosen.routeId, rs.id)
						end
					elseif result.reason == "stall" then
						push(events, "hint", nil, rs.id, "junctionAhead")
					end
					if not switched then
						state.railT = if atStart then 0 else 1
						push(events, "railEnd", rs.id, nil, result.reason)
					end
				end
			end
			local current = route(world, state.routeId) :: Registry.Route
			if current.id ~= rs.id then
				state.railT = math.clamp(state.railT, 0, 1)
			end
			if not state.bridge then
				local p = reg:pointAt(current, state.railT)
				state.x, state.y, state.z = p.x, p.y, p.z
			end
			local tangent = reg:tangentAt(current, state.railT)
			if tangent.x * tangent.x + tangent.y * tangent.y + tangent.z * tangent.z > 0.1
				and math.abs(tangent.x) + math.abs(tangent.z) > C.tangentYawMin
			then
				local sense = if fw ~= 0 then math.sign(fw) * state.railDir else state.railDir
				local angle = math.atan2(sense * tangent.x, sense * tangent.z)
				state.yaw = Motion.turnToward(state.yaw, angle, C.yawRate, dt)
			end
			state.vx, state.vy, state.vz = 0, 0, 0
		end
	else
		state.routeWasMoving = false
		state.selectedJunction = nil
		state.bridge = nil
		local camYaw = input.cameraYaw
		if moving and state.attackWindow == 0 then
			local dx = -math.sin(camYaw) * fw + math.cos(camYaw) * side
			local dz = -math.cos(camYaw) * fw - math.sin(camYaw) * side
			local l = math.sqrt(dx * dx + dz * dz)
			if l > 0 then
				dx, dz = dx / l, dz / l
			end
			local a = 1 - math.exp(-dt * (if state.grounded then P.accelGround else P.accelAir))
			state.vx += (dx * state.moveSpeed - state.vx) * a
			state.vz += (dz * state.moveSpeed - state.vz) * a
			state.yaw = Motion.turnToward(state.yaw, math.atan2(dx, dz), if state.focus then P.turnRateFocus else P.turnRate, dt)
		elseif state.attackWindow == 0 then
			local friction = math.exp(-dt * (if state.grounded then P.dragGround else P.dragAir))
			state.vx *= friction
			state.vz *= friction
		end
		if state.focus and not moving then
			state.yaw = Motion.turnToward(state.yaw, camYaw + math.pi, P.faceCameraRate, dt)
		end
		state.vy -= P.gravity * dt
		state.x += state.vx * dt
		state.y += state.vy * dt
		state.z += state.vz * dt
		resolveWalls(state, world, oldX, oldZ)
		local ground = world.groundAt(state.x, state.z, state.y)
		if state.y <= ground then
			state.y = ground
			state.vy = 0
			if not state.grounded then
				push(events, "land")
			end
			state.grounded = true
			if state.committedAirborne then
				state.committedAirborne = false
				state.cameraCommit = math.max(state.cameraCommit, P.cameraCommitLand)
			end
		else
			state.grounded = false
		end
	end

	state.routeFreeLook = math.max(0, state.routeFreeLook - dt)
	local clamp = world.clamp
	if clamp then
		state.x = math.clamp(state.x, clamp.minX, clamp.maxX)
		state.z = math.clamp(state.z, clamp.minZ, clamp.maxZ)
	else
		state.x = math.clamp(state.x, P.clampMinX, P.clampMaxX)
		state.z = math.clamp(state.z, P.clampMinZ, P.clampMaxZ)
	end
	state.clock += dt
	local _ = oldY
end

-- step(state, input, dt, world) -> state, events. One frame: edge actions in the key-handler order
-- (A/D, E, Q, Space, click), then updatePlayer substeps of <= 1/60 s (dt capped at 0.08 s).
function SquirrelMotor.step(state: State, input: Input, dt: number, world: World): (State, { Event })
	local events: { Event } = {}
	if not state.alive then
		return state, events
	end
	if input.choose ~= 0 and state.routeId then
		doChoose(state, world, input, events)
	end
	if input.grab then
		doGrab(state, world, input, events)
	end
	if input.drop then
		doDrop(state, world, events)
	end
	if input.leap then
		doLeap(state, world, events)
	end
	if input.pounce then
		doPounce(state, world, input, events)
	end
	local frameDt = math.min(dt, P.frameDtCap)
	local steps = math.clamp(math.ceil(frameDt / P.substep - 1e-9), 1, P.maxSubsteps)
	local sub = frameDt / steps
	for _ = 1, steps do
		substep(state, input, sub, world, events)
	end
	return state, events
end

-- substep(state, input, dt, world): one raw integration step with no edge actions (tests, replays).
function SquirrelMotor.substep(state: State, input: Input, dt: number, world: World): (State, { Event })
	local events: { Event } = {}
	substep(state, input, dt, world, events)
	return state, events
end

-- visualPose(state, world): the mesh position (§14) for the current state.
function SquirrelMotor.visualPose(state: State, world: World): Vec3
	return visualPosition(state, world)
end

-- Leap apex (routes_movement §13): v^2 / 2g, continuous.
function SquirrelMotor.leapApex(): number
	return P.leapUp * P.leapUp / (2 * P.gravity)
end

return SquirrelMotor
