--!strict
-- ReplicatedStorage.Shared.Movement.SquirrelMotor
-- Squirrel rail/ground motor shared by AI (server) and players (client).
-- Interface (BUILD_PLAN §1.4, D2): new(params), step(state, input, dt, world) -> state, events, serialize, deserialize, envelope
--   place(state, x, y, z, grounded): the body somewhere else at rest (river recovery, a server teleport)
--
-- A port of v5.4's `updatePlayer` (reference/v5_4_game.js L6573-6770) and the launch helpers
-- (leap L5922, Q drop L5672, attemptPounce L6482, jumpVelocity L5915, pounceVelocity L6473,
-- attackHeading L5900, enterRoute L5826, attachRoute L5870) for a squirrel actor, in studs:
--   GROUND  camera-relative WASD, accel 23 / drag 13 (air 4.2 / 1.15), turn 25 (19 in focus),
--           walk 7.2, sprint 13.2 (v5.4: 8 and 16.8; owner 2026-11-10 "runs a bit too fast"), stalk
--           1.65 u/s, x1.6 boost; sprint is a burst (stamina, below); gravity 30 u/s^2; ground snap;
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
local Trampoline = require("./Trampoline")
local Motion = require("../Routes/Motion")
local Registry = require("../Routes/Registry")
local SpatialIndex = require("../Routes/SpatialIndex")
local Units = require("../Config/Units")

local SquirrelMotor = {}

export type Vec3 = Curve.Vec3
export type World = Motion.World & {
	-- standable height (studs) at (x, z) for a body whose reference y is refY (World/Ground in W1)
	groundAt: (x: number, z: number, refY: number) -> number,
	-- optional wall test: true when a body of the squirrel radius at (x, z, y) overlaps a collider
	blocked: ((x: number, z: number, y: number) -> boolean)?,
	-- optional narrower wall test (the body's core). A body that starts a step already inside `blocked`
	-- (it let go of a downspout on a wall, landed against one) moves by this one until it is clear, so
	-- it can come away from the wall but never pass through it.
	blockedCore: ((x: number, z: number, y: number) -> boolean)?,
	-- optional: the body's box at a given half-width (studs), for the fallback's ratchet (resolveWalls)
	blockedHalf: ((x: number, z: number, y: number, half: number) -> boolean)?,
	-- optional world clamp (studs); defaults to the v5.4 rectangle
	clamp: { minX: number, maxX: number, minZ: number, maxZ: number }?,
	-- optional segment test for validators: does the straight move (x0,z0)->(x1,z1) at height y cross
	-- a wall collider? (Colliders in W1)
	crosses: ((x0: number, z0: number, x1: number, z1: number, y: number) -> boolean)?,
	-- optional trampoline sites (Movement/Trampoline, from the registry's trampoline routes)
	trampolines: { Trampoline.Site }?,
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
	stamina: number, -- sprint meter, 0..1 (the client's own feel; the server only caps speed)
	winded: boolean, -- the meter ran out: no sprint until sprintRecover of it is back
	tireless: boolean?, -- the meter never drains (AI bodies, a later item, tests that replay v5.4 runs)
	railLeap: boolean?, -- in the air from a leap off a rail: it carries as far as v5.4's did
}

export type Event = { kind: string, routeId: number?, fromRouteId: number?, reason: string? }

-- Snapshot: a flat table of numbers and booleans (no nesting) for remotes, attributes and handoff.
export type Snapshot = { [string]: number | boolean }

local st = Units.st
-- v5.4's own ground speeds, kept for the record and for tests that replay v5.4 numbers
SquirrelMotor.V54 = { walk = st(8.0), sprint = st(16.8) }
SquirrelMotor.params = {
	-- ground (routes_movement §8.1-§8.2)
	-- v5.4 ran at 8.0 and 16.8 u/s (SquirrelMotor.V54). Owner 2026-11-10: "the squirrel runs a bit too
	-- fast ... I don't want it to just be fast and getting everybody, as much as I want to encourage the
	-- dynamic of stalking around in trees": a walk no faster than a fleeing person (18 st/s), a sprint
	-- that still catches one (33 st/s) but only in bursts. Rail speeds (Motion.C) are unchanged.
	walk = st(7.2),
	sprint = st(13.2),
	-- sprint bursts: a full meter is sprintSeconds of sprinting; it refills in sprintRefill seconds of
	-- not sprinting, on the ground or on a rail (never in the air, or a hop would pay for itself); once
	-- empty ("winded") sprint is off until sprintRecover of the meter is back. A leap from the ground
	-- costs leapCost and a pounce from the ground pounceCost; winded, neither carries faster than a
	-- walk, so hopping or pounce-chaining is never a way round the meter (review 2026-11-10: chained
	-- pounces held 28 st/s for ever, hops 24 st/s for half a minute). Off a rail both are free and full.
	sprintSeconds = 4,
	sprintRefill = 9,
	sprintRecover = 0.35,
	leapCost = 0.12,
	pounceCost = 0.25,
	leapForwardWinded = st(7.2),
	stalk = st(1.65),
	boostMult = 1.6,
	treeTravelMult = 0.6,
	speedSmoothFocus = 11,
	speedSmooth = 17,
	accelGround = 23,
	accelAir = 4.2,
	dragGround = 13,
	dragAir = 1.15,
	-- v5.4 turned the body at 25/s (19 stalking): 90 % of a turn inside 0.1 s, which read as a snap
	-- (owner 2026-11-10: "the squirrel turns too abruptly, make turning more smooth and agile"). At 13/s
	-- the body swings through the turn in about a fifth of a second; the velocity still answers the keys
	-- at accelGround, so the controls are as quick as before.
	turnRate = 13,
	turnRateFocus = 11,
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
	-- half-widths tried, widest first, by a body that starts a step inside its own box (resolveWalls)
	fitHalves = { 0.9, 0.8, 0.7, 0.6, 0.5, 0.4 },
	blockedDamp = 0.28,
	-- ground glue: the drop a grounded body follows without leaving the ground, per substep: the larger of
	-- glueMin (a kerb, a plate lip) and glueSlope x the horizontal distance moved (a 50-degree slope)
	glueMin = 0.75,
	glueSlope = 1.2,
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
		stamina = 1,
		winded = false,
	}
end

-- Puts the body somewhere else at rest (v5.4 recoverRiverFall L14116-14132, a server teleport): off any
-- rail, no bridge, no pending choice, no velocity; the heading is kept. With `grounded` false it falls
-- from there.
function SquirrelMotor.place(state: State, x: number, y: number, z: number, grounded: boolean)
	state.x, state.y, state.z = x, y, z
	state.vx, state.vy, state.vz = 0, 0, 0
	state.moveSpeed = 0
	state.grounded = grounded
	state.routeId = nil
	state.bridge = nil
	state.pendingFork = nil
	state.selectedJunction = nil
	state.routeWasMoving = false
	state.routeFreeLook = 0
	state.committedAirborne = false
	state.cameraCommit = 0
	state.attackWindow = 0
	state.railLeap = false
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
function SquirrelMotor.attackHeading(
	onTrunk: boolean,
	trunkNormalX: number?,
	trunkNormalZ: number?,
	yaw: number
): number
	if onTrunk then
		return math.atan2(trunkNormalX or 0, trunkNormalZ or 1)
	end
	return yaw
end

-- jumpVelocity() (L5915-5921), studs/s. A winded leap rises as high but carries less far.
function SquirrelMotor.jumpVelocity(heading: number, boosted: boolean, winded: boolean?): (number, number, number)
	local forward = if winded then P.leapForwardWinded elseif boosted then P.leapForwardBoost else P.leapForward
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
	local speed = (
		if focus
			then P.pounceSpeedFocus
			elseif moveSpeed > P.pounceFastAbove then P.pounceSpeedFast
			else P.pounceSpeedSlow
	) * (if boosted then P.pounceBoostMult else 1)
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
	"stamina",
}
local FLAGS = { "grounded", "committedAirborne", "focus", "routeWasMoving", "alive", "winded" }
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
local function enterRoute(state: State, world: World, spec: Motion.EnterSpec, input: Input, events: { Event }): boolean
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
	state.railLeap = false
	push(events, if wasOnRoute then "transfer" else "attach", target.id, fromRouteId)
	return true
end

local function visualPosition(state: State, world: World): Vec3
	local r = route(world, state.routeId)
	if not r then
		return Curve.vec3(state.x, state.y, state.z)
	end
	return Motion.visualPose(
		world,
		r,
		state.railT,
		Curve.vec3(state.x, state.y, state.z),
		state.trunkNormalX,
		state.trunkNormalZ
	)
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
		local heading =
			SquirrelMotor.attackHeading(onTrunk(state, world), state.trunkNormalX, state.trunkNormalZ, state.yaw)
		-- a leap off the ground spends some of the sprint meter, so hopping is not a free sprint; a leap
		-- off a rail is always a full one (the gaps between branches and wires are built for it)
		local tired = false
		if state.routeId == nil and not state.tireless then
			tired = state.winded
			state.stamina = math.max(0, state.stamina - P.leapCost)
			if state.stamina == 0 and not state.winded then
				state.winded = true
				push(events, "winded")
			end
		end
		local vx, vy, vz = SquirrelMotor.jumpVelocity(heading, state.boostRemaining > 0, tired)
		local from = state.routeId
		launchFromVisibleRoute(state, world)
		state.vx, state.vy, state.vz = vx, vy, vz
		state.routeId = nil
		state.grounded = false
		commitToAir(state, heading)
		state.railLeap = from ~= nil
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
	local heading =
		SquirrelMotor.attackHeading(onTrunk(state, world), state.trunkNormalX, state.trunkNormalZ, state.yaw)
	local vx, vy, vz =
		SquirrelMotor.pounceVelocity(input.cameraPitch, state.focus, state.moveSpeed, state.boostRemaining > 0, heading)
	local from = state.routeId
	state.railLeap = false
	if from == nil and not state.tireless then
		-- a pounce off the ground spends the sprint meter; a winded one lunges no faster than a walk
		local tired = state.winded
		state.stamina = math.max(0, state.stamina - P.pounceCost)
		if state.stamina == 0 and not state.winded then
			state.winded = true
			push(events, "winded")
		end
		local h = math.sqrt(vx * vx + vz * vz)
		if tired and h > P.walk then
			vx, vz = vx * P.walk / h, vz * P.walk / h
		end
	end
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
	local picked = Motion.chooseRouteJunction(
		world,
		r,
		state.railT,
		state.railDir,
		input.cameraYaw,
		state.yaw,
		side,
		state.selectedJunction
	)
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
		local junction = Motion.takeSelectedJunction(
			world,
			r,
			state.railT,
			state.railDir,
			input.cameraYaw,
			state.yaw,
			state.selectedJunction
		)
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

-- resolveOutdoorMovement (L6411-6447), line for line: the displacement is swept in steps of <= sweepStep;
-- each step tries X from the current point, then Z from where X left it, and takes the diagonal only when
-- both axes were refused. Velocity is damped once per blocked axis after the sweep (never per step), so a
-- body sliding along a wall keeps its speed along it.
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
	local core = world.blockedCore
	if core and blocked(oldX, oldZ, y) then
		blocked = core
		-- A ratchet: the widest body that is clear where it stands. It slides along and comes away at
		-- that width and never goes deeper, and the width grows back to the whole body as it comes
		-- away. Without it a body that got within a body-width of a wall (it stepped off a roof edge,
		-- was handed over beside one) could then press in to the core and run the wall half sunk.
		local fit = world.blockedHalf
		if fit then
			for _, half in P.fitHalves do
				if not fit(oldX, oldZ, y, half) then
					blocked = function(bx0: number, bz0: number, at: number): boolean
						return fit(bx0, bz0, at, half)
					end
					break
				end
			end
		end
	end
	local bx, bz = false, false
	for _ = 1, steps do
		local px, pz = x, z
		if math.abs(sx) > 1e-7 then
			if not blocked(x + sx, z, y) then
				x += sx
			else
				bx = true
			end
		end
		if math.abs(sz) > 1e-7 then
			if not blocked(x, z + sz, y) then
				z += sz
			else
				bz = true
			end
		end
		if x == px and z == pz and not blocked(px + sx, pz + sz, y) then
			x, z = px + sx, pz + sz
			bx, bz = false, false
		end
	end
	state.x, state.z = x, z
	if bx then
		state.vx *= P.blockedDamp
	end
	if bz then
		state.vz *= P.blockedDamp
	end
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
	-- sprint is a burst: the meter drains while sprinting and moving, refills otherwise
	local sprint = input.sprint and not state.winded and not state.focus
	if state.tireless then
		state.stamina, state.winded = 1, false
		sprint = input.sprint and not state.focus
	elseif sprint and moving then
		state.stamina = math.max(0, state.stamina - dt / P.sprintSeconds)
		if state.stamina == 0 then
			state.winded = true
			sprint = false
			push(events, "winded")
		end
	elseif rail ~= nil or state.grounded then
		state.stamina = math.min(1, state.stamina + dt / P.sprintRefill)
		if state.winded and state.stamina >= P.sprintRecover then
			state.winded = false
		end
	end
	local treeTravel = rail ~= nil and rail.flags.treeTravel
	local base = (if state.focus then P.stalk elseif sprint then P.sprint else P.walk)
		* (if state.boostRemaining > 0 and not state.focus then P.boostMult else 1)
		* (if treeTravel then P.treeTravelMult else 1)
	local target = if moving then base else 0
	state.moveSpeed += (target - state.moveSpeed) * (1 - math.exp(
		-dt * (if state.focus then P.speedSmoothFocus else P.speedSmooth)
	))

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
				state.railDir =
					Motion.directionFromView(world, rs, state.railT, input.cameraYaw, state.yaw, state.railDir)
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
			if
				tangent.x * tangent.x + tangent.y * tangent.y + tangent.z * tangent.z > 0.1
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
			-- a leap off a rail steers toward v5.4's own speeds whatever the meter says: the gaps between
			-- branches, wires and roofs were built for that carry, and the slower ground speeds would
			-- have cut it by a sixth (by two fifths when winded)
			local steer = state.moveSpeed
			if state.railLeap and not state.grounded then
				local v54 = if input.sprint then SquirrelMotor.V54.sprint else SquirrelMotor.V54.walk
				steer = math.max(steer, v54 * (if state.boostRemaining > 0 then P.boostMult else 1))
			end
			state.vx += (dx * steer - state.vx) * a
			state.vz += (dz * steer - state.vz) * a
			state.yaw = Motion.turnToward(
				state.yaw,
				math.atan2(dx, dz),
				if state.focus then P.turnRateFocus else P.turnRate,
				dt
			)
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
		local tramps = world.trampolines
		if tramps and Trampoline.attemptAny(tramps, state :: any, oldY, input.cameraYaw) then
			-- v5.4 L6752: the bounce keeps its vertical impulse and airborne control
			push(events, "bounce")
		elseif state.y <= ground then
			state.y = ground
			state.vy = 0
			if not state.grounded then
				push(events, "land")
			end
			state.grounded = true
			state.railLeap = false
			if state.committedAirborne then
				state.committedAirborne = false
				state.cameraCommit = math.max(state.cameraCommit, P.cameraCommitLand)
			end
		elseif
			state.grounded
			and state.vy <= 0
			and state.y - ground
				<= math.max(P.glueMin, P.glueSlope * math.sqrt((state.x - oldX) ^ 2 + (state.z - oldZ) ^ 2))
		then
			-- Ground glue (owner rule 2026-11-09: "a kinematic body glued to the ground"; a deliberate step
			-- past v5.4, whose body left the ground for a frame on every downhill sample and only its drawn
			-- copy was pinned). A grounded body follows the ground down a slope, a kerb or a plate lip
			-- without becoming airborne: no "land" event, no air acceleration, no fall. Leap, pounce, drop
			-- and the trampoline clear `grounded` or set vy > 0 first, so they stay ballistic; a real ledge
			-- (deeper than the allowance) still drops.
			state.y = ground
			state.vy = 0
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

-- Envelope ----------------------------------------------------------------------------------------------
-- envelope(prev, next, dt, world, boosted) -> violations: is the move from one accepted motor state to
-- the next one an honest client could have produced in `dt` seconds? Shared by the server
-- MoveValidator (verdicts) and, later, by the client (to predict a rejection). Every bound is the
-- motor's own constant times a tolerance plus one substep of slack; `boosted` is the SERVER's knowledge
-- of the chili boost (the packet's boostRemaining is never trusted). Position is checked against the
-- rail, speeds against the per-kind caps, arcs against gravity, launches against jump/pounce, rail
-- changes against the route graph and the transfer gaps, and ground moves against world.crosses.

export type Violation = { code: string, severity: number, detail: string }

SquirrelMotor.envelopeParams = {
	speedTol = 1.15, -- ground and air horizontal speed tolerance (latency, substep rounding)
	railTol = 1.05, -- rail parameter speed tolerance (deterministic advance)
	launchTol = 1.1, -- leap / pounce launch velocities
	posSlack = st(0.05), -- on-rail position agreement (the client runs the same curve)
	gravityEps = 0.03, -- seconds of gravity the vertical speed may deviate by
	maxDt = 0.5, -- larger gaps are resynced, not judged
	forkEnterMaxT = 0.06, -- a fork or sibling hop lands near the bough start (0.018 / 0.03)
	pounceMinInterval = 0.7 / 1.15, -- cooldown with tolerance (launches in the air)
	shortDt = 0.05, -- up to three ticks: nothing can hide between packets; longer gaps relax
}
local E = SquirrelMotor.envelopeParams

local function hypot2(x: number, z: number): number
	return math.sqrt(x * x + z * z)
end

local function add(list: { Violation }, code: string, severity: number, detail: string)
	table.insert(list, { code = code, severity = math.clamp(severity, 0, 1), detail = detail })
end

-- Caps in studs/s.
-- A leap now launches faster than the sprint (41 against 33 st/s; in v5.4 it was just under it), and
-- a landing carries that speed on for a moment, so the cap is the faster of the two.
function SquirrelMotor.groundCap(boosted: boolean): number
	return math.max(
		P.sprint * (if boosted then P.boostMult else 1),
		if boosted then P.leapForwardBoost else P.leapForward
	)
end

function SquirrelMotor.railCap(treeTravel: boolean, boosted: boolean): number
	return Motion.railSpeed(treeTravel, true, false, boosted)
end

function SquirrelMotor.launchCapXZ(boosted: boolean): number
	return math.max(
		if boosted then P.leapForwardBoost else P.leapForward,
		P.pounceSpeedFast * (if boosted then P.pounceBoostMult else 1)
	)
end

-- Returns the violations and whether a launch (leap or pounce) was needed to explain the move.
function SquirrelMotor.envelope(
	prev: State,
	next: State,
	dt: number,
	world: World,
	boosted: boolean
): ({ Violation }, boolean)
	local out: { Violation } = {}
	local launchUsed = false
	if dt <= 0 then
		add(out, "clock", 1, `non-positive dt {dt}`)
		return out, false
	end
	local reg = world.registry
	local prevRoute = route(world, prev.routeId)
	local nextRoute = route(world, next.routeId)
	if next.routeId and not nextRoute then
		add(out, "route", 1, `unknown route {next.routeId}`)
		return out, false
	end
	local groundCap = SquirrelMotor.groundCap(boosted) * E.speedTol
	local launchXZ = SquirrelMotor.launchCapXZ(boosted) * E.launchTol
	local launchUp = P.leapUp * E.launchTol
	local pounceUp = (P.pounceUpBase + P.pounceUpPitch * math.sin(P.pouncePitchMax)) * E.launchTol
	local pounceUpMin = (P.pounceUpBase + P.pounceUpPitch * math.sin(P.pouncePitchMin)) / E.launchTol
	local pounceXZ = P.pounceSpeedFast * (if boosted then P.pounceBoostMult else 1) * E.launchTol

	-- 1. Position agreement with the claimed rail.
	if nextRoute then
		local dest = reg:pointAt(nextRoute, next.railT)
		local b = next.bridge
		if b then
			if hypot2(b.tx - dest.x, b.tz - dest.z) > E.posSlack or math.abs(b.ty - dest.y) > E.posSlack then
				add(out, "railPose", 1, "transfer target off the rail")
			end
			if b.elapsed > b.duration + 1e-9 or b.duration < C.bridgeMin - 1e-9 or b.duration > C.bridgeMax + 1e-9 then
				add(out, "railPose", 1, "transfer easing out of range")
			end
			-- the body lies on the from->to segment at the eased fraction
			local p = Motion.ease(b.elapsed / b.duration)
			local ex, ey, ez = b.fx + (b.tx - b.fx) * p, b.fy + (b.ty - b.fy) * p, b.fz + (b.tz - b.fz) * p
			if hypot2(ex - next.x, ez - next.z) > E.posSlack or math.abs(ey - next.y) > E.posSlack then
				add(out, "railPose", 1, "body off the transfer segment")
			end
		else
			local off = math.sqrt((dest.x - next.x) ^ 2 + (dest.y - next.y) ^ 2 + (dest.z - next.z) ^ 2)
			if off > E.posSlack then
				add(out, "railPose", math.min(1, Units.u(off)), `body {off} st off the rail centreline`)
			end
		end
		if next.railT < -1e-9 or next.railT > 1 + 1e-9 then
			add(out, "railPose", 1, "railT outside [0, 1]")
		end
	end

	-- Could the body have visited a rail between the two packets? Long gaps (loss, reordering) hide
	-- attach/detach pairs, so some checks relax when a route lies within the grab radius of the path.
	local shortGap = dt <= E.shortDt
	local function railWithinReach(): boolean
		local vPrev = math.sqrt(prev.vx ^ 2 + prev.vy ^ 2 + prev.vz ^ 2)
		local reach = C.airGrab + math.max(groundCap, vPrev) * dt + E.posSlack
		return world.index:nearest(prev.x, prev.y, prev.z, reach) ~= nil
			or world.index:nearest(next.x, next.y, next.z, reach) ~= nil
	end

	-- 2. Rail-to-rail: speed along the same route, or a legal transfer.
	if prevRoute and nextRoute then
		local railCap = SquirrelMotor.railCap(prevRoute.flags.treeTravel, boosted)
		if prevRoute.id == nextRoute.id then
			local allowed = railCap * E.railTol * dt + railCap * P.substep
			if not shortGap then
				-- a long gap can hide a leap or drop off this route and a grab back onto it further along
				allowed += C.airGrab + launchXZ * dt
			end
			local moved = math.abs(next.railT - prev.railT) * prevRoute.length
			if moved > allowed then
				add(
					out,
					"railSpeed",
					math.min(1, moved / allowed - 1),
					`{moved} st along the rail in {dt} s (cap {allowed})`
				)
			end
		else
			local dest = if next.bridge
				then Curve.vec3(next.bridge.tx, next.bridge.ty, next.bridge.tz)
				else reg:pointAt(nextRoute, next.railT)
			-- the honest body left the old rail somewhere it could reach within dt: the gap is measured
			-- from the closest point of that reachable stretch (sampled), not from the stale position
			local reachT = railCap * E.railTol * dt / math.max(prevRoute.length, 1e-6)
			local gap = math.huge
			for k = -4, 4 do
				local tt = math.clamp(prev.railT + reachT * k / 4, 0, 1)
				local q = reg:pointAt(prevRoute, tt)
				gap = math.min(gap, math.sqrt((dest.x - q.x) ^ 2 + (dest.y - q.y) ^ 2 + (dest.z - q.z) ^ 2))
			end
			local travel = E.posSlack + railCap * E.railTol * dt / 4 -- between the sampled points
			local graph = world.graph
			local relation = graph:relation(prevRoute.id, nextRoute.id)
			-- a hidden intermediate route B (two transfers inside one long gap) is legal when B passes within
			-- the transfer limit of the stretch of A the body could reach, and the destination lies within
			-- B's own reach of that point (geometry, not just graph relation)
			local twoHop = false
			if relation == nil and not shortGap then
				local mids: { number } = graph:transfers(prevRoute.id)
				for _, atStart in { true, false } do
					for _, l in graph:endLinks(prevRoute.id, atStart) do
						table.insert(mids, l.to)
					end
				end
				local parentFork = graph:forkOf(prevRoute.id)
				if parentFork then
					table.insert(mids, parentFork.trunk)
				end
				for _, f in graph:forks(prevRoute.id) do
					table.insert(mids, f.branch)
				end
				for _, mid in mids do
					local midRelation = graph:relation(mid, nextRoute.id)
					local midRoute = if midRelation then reg:get(mid) else nil
					if midRoute then
						local best: SpatialIndex.Hit? = nil
						for k = -4, 4 do
							local tt = math.clamp(prev.railT + reachT * k / 4, 0, 1)
							local q = reg:pointAt(prevRoute, tt)
							local hit = world.index:nearestOnRoute(mid, q.x, q.y, q.z, C.explicitGap + travel)
							if hit and (best == nil or hit.d < (best :: SpatialIndex.Hit).d) then
								best = hit
							end
						end
						if best then
							local b = best :: SpatialIndex.Hit
							local capB = SquirrelMotor.railCap(midRoute.flags.treeTravel, boosted) * E.railTol * dt
							local d = math.sqrt((dest.x - b.x) ^ 2 + (dest.y - b.y) ^ 2 + (dest.z - b.z) ^ 2)
							local allow = capB
								+ E.posSlack
								+ (
									if midRelation == "linked" or midRelation == "end"
										then C.explicitGap
										else C.enterMaxGap
								)
							if d <= allow then
								twoHop = true
								break
							end
						end
					end
				end
			end
			if gap > C.enterMaxGap + travel + (if twoHop then C.enterMaxGap else 0) then
				add(out, "transfer", 1, `transfer gap {gap} st > 3.15 u (+travel)`)
			elseif relation == "fork" or relation == "sibling" then
				local nextCap = SquirrelMotor.railCap(nextRoute.flags.treeTravel, boosted)
				if next.railT > E.forkEnterMaxT + nextCap * E.railTol * dt / nextRoute.length then
					add(out, "transfer", 1, `{relation} hop landed at t {next.railT}`)
				end
			elseif relation == nil and not twoHop and gap > C.explicitGap + travel then
				add(out, "transfer", 1, `unrelated routes {prevRoute.id} -> {nextRoute.id}, gap {gap} st`)
			end
		end
	end

	-- 3. Off rail onto a rail: the grab radius (3.4 u) plus what the body could have moved first.
	if not prevRoute and nextRoute then
		local dest = reg:pointAt(nextRoute, next.railT)
		local gap = math.sqrt((dest.x - prev.x) ^ 2 + (dest.y - prev.y) ^ 2 + (dest.z - prev.z) ^ 2)
		local vPrev = math.sqrt(prev.vx ^ 2 + prev.vy ^ 2 + prev.vz ^ 2)
		local travel = math.max(groundCap, vPrev, launchXZ) * dt + E.posSlack
		if gap > C.airGrab + travel then
			-- a long gap can hide a first rail B: grabbed within reach of prev, related to the new route,
			-- and the destination within B's own reach (plus the transfer or fork allowance) of that point
			local explained = false
			if not shortGap then
				local graph = world.graph
				for _, mid in graph:neighbours(nextRoute.id) do
					local midRoute = reg:get(mid)
					if midRoute then
						local hit = world.index:nearestOnRoute(mid, prev.x, prev.y, prev.z, C.airGrab + travel)
						if hit then
							local relation = graph:relation(mid, nextRoute.id)
							local capB = SquirrelMotor.railCap(midRoute.flags.treeTravel, boosted) * E.railTol * dt
							local d = math.sqrt((dest.x - hit.x) ^ 2 + (dest.y - hit.y) ^ 2 + (dest.z - hit.z) ^ 2)
							local allow = capB + E.posSlack
							if relation == "fork" then
								allow += C.enterMaxGap + C.forkTakeForced
							elseif relation == "sibling" then
								allow += C.enterMaxGap
							else
								allow += C.explicitGap
							end
							if d <= allow then
								explained = true
								break
							end
						end
					end
				end
			end
			if not explained then
				add(out, "grab", 1, `grabbed a rail {gap} st away (> 3.4 u + travel)`)
			end
		end
	end

	-- 4. Off the rail (leap, drop, pounce, knockback): the launch point is the visible position.
	if prevRoute and not nextRoute then
		local vis = Motion.visualPose(
			world,
			prevRoute,
			prev.railT,
			Curve.vec3(prev.x, prev.y, prev.z),
			prev.trunkNormalX,
			prev.trunkNormalZ
		)
		local railCap = SquirrelMotor.railCap(prevRoute.flags.treeTravel, boosted)
		local launchSpeed = math.sqrt(launchXZ * launchXZ + launchUp * launchUp)
		local allowed = railCap * dt
			+ launchSpeed * dt
			+ Units.st(0.5)
			+ E.posSlack
			+ (if shortGap then 0 else C.airGrab)
		local moved = math.sqrt((next.x - vis.x) ^ 2 + (next.y - vis.y) ^ 2 + (next.z - vis.z) ^ 2)
		if moved > allowed then
			add(out, "teleport", 1, `left the rail {moved} st from the visible position (allowed {allowed})`)
		end
		if hypot2(next.vx, next.vz) > launchXZ then
			add(out, "launch", 1, `horizontal launch {hypot2(next.vx, next.vz)} st/s`)
		end
		if next.vy > launchUp then
			add(out, "launch", 1, `vertical launch {next.vy} st/s`)
		end
	end

	-- 5. Off rail to off rail: ground and air motion.
	if not prevRoute and not nextRoute then
		local vxz = hypot2(next.vx, next.vz)
		local launched = next.vy > prev.vy + P.gravity * 0.5 * P.substep and not next.grounded
		local railPlausible: boolean? = nil
		local function plausible(): boolean
			if railPlausible == nil then
				railPlausible = railWithinReach()
			end
			return railPlausible :: boolean
		end
		if launched then
			launchUsed = true
			-- from the ground or a (possibly hidden) rail: the leap; in the air: only a pounce
			local fromGroundOrRail = prev.grounded or plausible()
			local capUp = if fromGroundOrRail then launchUp else pounceUp
			local capXZ = if fromGroundOrRail then launchXZ else pounceXZ
			if next.vy > capUp then
				add(out, "launch", 1, `vertical launch {next.vy} st/s (cap {capUp})`)
			end
			if vxz > capXZ then
				add(out, "launch", 1, `horizontal launch {vxz} st/s (cap {capXZ})`)
			end
		else
			if vxz > groundCap then
				add(out, "speed", math.min(1, vxz / groundCap - 1), `horizontal speed {vxz} st/s (cap {groundCap})`)
			end
			-- gravity: airborne at both ends and no launch -> vy drops by exactly g*dt (semi-implicit
			-- Euler) unless a rail within reach could have been visited in between
			if not prev.grounded and not next.grounded then
				local expected = prev.vy - P.gravity * dt
				local eps = P.gravity * E.gravityEps
				if math.abs(next.vy - expected) > eps then
					-- a mid-air pounce REPLACES the velocity (vy 2.37..5.09 u, |v_xz| <= 13.5 u x1.12) at any
					-- tick inside the gap, so it can lower a rising vy; a rail visit zeroes and relaunches it
					local pounce = next.vy <= pounceUp
						and next.vy >= pounceUpMin - P.gravity * dt - eps
						and vxz <= pounceXZ
					if pounce then
						launchUsed = true
					elseif not plausible() then
						add(out, "gravity", 1, `vertical speed {next.vy}, expected {expected}`)
					end
				end
			end
		end
		-- horizontal displacement against the fastest plausible speed
		local dxz = hypot2(next.x - prev.x, next.z - prev.z)
		local fastest = math.max(groundCap, if launched then launchXZ else 0, hypot2(prev.vx, prev.vz) * E.speedTol)
		local allowedXZ = fastest * dt + E.posSlack
		if dxz > allowedXZ and not (not shortGap and plausible() and dxz <= allowedXZ + C.airGrab) then
			add(out, "teleport", math.min(1, dxz / allowedXZ - 1), `moved {dxz} st in {dt} s (allowed {allowedXZ})`)
		end
		-- vertical displacement: within what the start and end vertical speeds allow
		local dy = next.y - prev.y
		local upCap = math.max(prev.vy, next.vy, if launched then launchUp else 0, 0) * dt + E.posSlack
		local downCap = math.min(prev.vy, next.vy, 0) * dt - E.posSlack - P.gravity * dt * dt
		if dy > upCap or dy < downCap then
			-- landing snaps to the ground (a step either way); a hidden rail visit climbs or descends
			local landing = next.grounded and math.abs(dy) <= Units.st(1.4)
			local railVisit = not shortGap
				and plausible()
				and math.abs(dy) <= SquirrelMotor.railCap(false, boosted) * dt + C.airGrab
			if not landing and not railVisit then
				add(out, "teleport", 1, `vertical move {dy} st in {dt} s`)
			end
		end
		-- walls: the straight move must not cross a collider
		local crosses = world.crosses
		if crosses and crosses(prev.x, prev.z, next.x, next.z, math.min(prev.y, next.y)) then
			add(out, "wall", 1, "move crosses a wall collider")
		end
	end

	return out, launchUsed
end

return SquirrelMotor
