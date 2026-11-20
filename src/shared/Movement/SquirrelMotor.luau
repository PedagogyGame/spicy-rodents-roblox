--!strict
-- ReplicatedStorage.Shared.Movement.SquirrelMotor
-- Squirrel rail/ground motor shared by AI (server) and players (client).
-- Interface (BUILD_PLAN §1.4, D2): new(params), step(state, input, dt, world) -> state, events, serialize, deserialize, envelope
--   speedBound(u, s, goal, grounded, t, hold?, floor?): the most the motor's speed step covers (the server's meter)
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
-- Edge actions per frame: leap (Space), drop (Q), grab (E), choose (A/D), pounce (left click), trick (G).
-- AIR TRICK (owner D17, redone by D18): one button. Pressed as the body lands (in the air with touchdown at most
-- trickLand s away, or on the ground at most trickLandGrace s after touchdown) it is a BARREL ROLL (trickRoll s): on the
-- ground the roll carries the speed it landed with, neither steered nor slowed, and adds none. Pressed mid-jump (off the
-- ground and any rail, no pounce's window, touchdown further off) it is the TWITCH-AND-WIGGLE (trickWiggle s), once a
-- flight, and from that moment the flight is RE-AIMED by Input.aimYaw / Input.aimReach (the camera's turn since the
-- press: Controllers/Squirrel): the horizontal velocity turned up to trickAimYaw either side (its speed kept), and the
-- carry lengthened or shortened by aimReach in [-1, 1]: out (> 0) scales the horizontal speed by up to 1 + trickReach,
-- the reach fixed at the press by trickReachAt (best at the apex: never more than trickOut, 9 %, of the whole jump on
-- flat ground), in (< 0) by down to 1 - trickIn and adds up to trickDown of downward speed (a higher jump comes in
-- further). Both move toward the input at a bounded rate (trickYawRate, trickReachRate); the state keeps what has been
-- applied (aimYaw, aimReach), which the packet carries, so the server undoes exactly that (envelope 0c). A wiggle with
-- meter left costs trickCost of it. trickKind: 0 none, 1 roll, 2 wiggle (this flight); trickTime: seconds of the move
-- left. Movement/AirTrick draws it.
-- GRAB-LEAP COOLDOWN (owner D18): E in the air grabs nothing until grabLeapCooldown s after a leap off a rail, so a
-- grab-leap (E+Space) follows the last one no sooner: a macro's E+Space every second frame chains at a person's pace (a
-- person's every sixth frame, and every honest climb, never meet it).
-- ENCLOSED RUNS (Routes/Enclosure; kind "tunnel": the ball return, a hollow tree's inside): got into only at a mouth,
-- moving into it (walking, falling, leaping or pouncing: the flight's swept path counts and going in ends the
-- attack), eased like a transfer (a hatch mouth, a storm drain's grate, takes only E from a body standing at it, never
-- a walk or a flight); inside and away from a mouth Space, Q and a click do nothing (hint "noRoom") and
-- E, A/D and the end-of-route switch never pass the wall; at a mouth they launch from outside its face
-- (Motion.launchPoint) along its `out` (a mouth's `hop` makes Space and a click a short hop; Q pushes out); an end
-- mouth lets the body out as it says (step out on the ground: "emerge", and that mouth does not take the body back
-- while the key it came out on is still held and it stays by the mouth: holding S after backing out leaves it outside;
-- stop with the head out: "lip", where a view turned round with W held turns back; run on along its link), an end
-- without one takes its authored end link,
-- else stops ("railEnd" once per arrival); A/D picks an authored fork or part-way link ahead, taken as W passes it
-- ("forkTaken" / "mouthLink"), E takes one within reach or steps out of a part-way opening ("emerge"). Every one of
-- these applies only to routes that carry `enclosure`: every other route behaves exactly as before.
-- The motor is pure: `step(state, input, dt, world)` mutates and returns `state` plus a list of
-- events, uses only the Routes modules and the `world.groundAt`/`world.blocked` callbacks, and runs
-- under Lune. `serialize`/`deserialize` give the flat snapshot that possession hands over
-- mid-stride (BUILD_PLAN §1.5) and that the client streams to Server/Movement/MoveValidator.
-- Frame timing as v5.4 tick (routes_movement §6): dt capped at 0.08 s, substeps of at most 1/60 s
-- (max 5). Numbers are v5.4 constants (routes_movement §8, §10, §13) with the spec line cited; they
-- are collected in `SquirrelMotor.params` so the Tunables tree can take them over in W1.

local Curve = require("../Routes/Curve")
local Enclosure = require("../Routes/Enclosure")
local Trampoline = require("./Trampoline")
local Motion = require("../Routes/Motion")
local Registry = require("../Routes/Registry")
local SpatialIndex = require("../Routes/SpatialIndex")
local SquirrelWire = require("./SquirrelWire")
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
	-- optional: told where each wall sweep starts (feet), before the wall tests of that sweep; a world may then leave
	-- out a moving wall the body is already inside (a car that came over it: Traffic/Solid.squirrelWorld)
	wallsFrom: ((x: number, z: number, y: number) -> ())?,
	-- optional segment test for validators: does the straight move (x0,z0)->(x1,z1) at height y cross
	-- a wall collider? (Colliders in W1). yHigh: the higher end's feet; rise: how far over it the arc could reach; endY:
	-- the feet at (x1, z1), where the rise counts only as high as that end is open above (ValidatorWorld.crosses)
	crosses: ((
		x0: number,
		z0: number,
		x1: number,
		z1: number,
		y: number,
		yHigh: number?,
		rise: number?,
		endY: number?
	) -> boolean)?,
	-- optional, for validators: the longest line `crosses` judges (studs), and the same test chord by chord for a longer
	-- one (Server/Movement/ValidatorWorld.crossesLong)
	maxChord: number?,
	crossesLong: ((
		x0: number,
		z0: number,
		x1: number,
		z1: number,
		y: number,
		yHigh: number?,
		rise: number?,
		endY: number?
	) -> boolean)?,
	-- optional, for validators: a long line through a wall has a way round a corner, two legs via a corner one of which
	-- is clear (Server/Movement/ValidatorWorld.around); none is a wall, not a corner rounded unseen
	around: ((
		x0: number,
		z0: number,
		x1: number,
		z1: number,
		y: number,
		yHigh: number?,
		rise: number?,
		endY: number?,
		path: number?
	) -> boolean)?,
	-- ... asked only for a line no longer than this (studs; a longer one is "too long to tell": true)
	aroundMax: number?,
	-- optional floor test for validators: is there something to stand on under feet at (x, y, z)?
	floorBelow: ((x: number, y: number, z: number) -> boolean)?,
	-- optional, for validators: is there ground within `depth` under feet at (x, y, z)? (else groundAt is asked)
	landable: ((x: number, y: number, z: number, depth: number) -> boolean)?,
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
	trick: boolean?, -- the air trick's button pressed this frame (G, gamepad R1, the touch button)
	-- the re-aim wanted while a wiggle's aim is live (radians either side; -1 in .. +1 out): the camera's turn since the
	-- press, or a drag from the touch button (nil: hold what is applied)
	aimYaw: number?,
	aimReach: number?,
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
	-- the enclosed run the body last stepped out of on the ground, the end (0 or 1) and the fw it came out on: that
	-- mouth does not take it back until fw changes or it is P.emergeClear from the mouth (nil: no such run)
	emergedFrom: number?,
	emergedEnd: number,
	emergedFw: number,
	selectedJunction: number?, -- route id of the A/D junction selection
	bridge: Bridge?,
	clock: number, -- accumulated simulated seconds (packet timestamps)
	alive: boolean,
	stamina: number, -- sprint meter, 0..1 (the client's own feel; the server only caps speed)
	winded: boolean, -- the meter ran out: no sprint until sprintRecover of it is back
	tireless: boolean?, -- the meter never drains (AI bodies, a later item, tests that replay v5.4 runs)
	railLeap: boolean?, -- in the air from a leap off a rail: it carries as far as v5.4's did
	-- the rail a leap left and where (while that leap is in the air): it lands on a branch or wire its
	-- flight lines up with (Motion.airCatch)
	airFromRoute: number?,
	airX: number?,
	airY: number?,
	airZ: number?,
	-- the air trick: the last move of this flight (0 none, 1 the barrel roll, 2 the twitch-and-wiggle) and the seconds
	-- of it left (0: none playing); both 0 on the ground and on a rail
	trickKind: number,
	trickTime: number,
	-- the re-aim applied this flight (radians; -1 .. 1) and the most the press allowed out (trickReachAt); 0 off the air
	aimYaw: number,
	aimReach: number,
	trickReach: number,
	-- seconds since the body last left or touched its footing (the ground or a rail): its time in the air, or on the
	-- ground since its landing
	footAgo: number,
	-- studs across since the body last left its footing (0 on it): the flight's carry so far
	airDist: number,
	-- seconds before E grabs in the air again after a leap off a rail (grabLeapCooldown)
	railLeapWait: number,
	-- seconds before a leap off this rail carries in full again (chainRest): set when the body came onto it from a leap
	-- off a rail, 0 otherwise
	chainWait: number,
	-- the carry of the leap off a rail in the air now (1, or chainCarry for one that followed another): what the air
	-- steers toward scales with it
	leapScale: number,
	-- 1 while in the air after leaving a rail (a leap, a drop or a pounce off it), 0 otherwise
	offRail: number,
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
	-- costs leapCost and a pounce from the ground pounceCost; winded, a pounce lunges no faster than a
	-- walk and a leap carries leapForwardWinded, so pounce-chaining is never a way round the meter and
	-- hopping is only a little one (review 2026-11-10: chained pounces held 28 st/s for ever, hops 24
	-- st/s for half a minute). Off a rail both are free and full.
	sprintSeconds = 4,
	sprintRefill = 9,
	sprintRecover = 0.35,
	leapCost = 0.12,
	pounceCost = 0.25,
	-- owner D17 (2026-11-20, "slight advantage even if there is empty meter, but not the same"): a winded
	-- leap carries 27.5 st/s (it was a walk's 18), so hopping on an empty meter keeps 6-14 % over the walk
	-- (hop on landing 20.5 st/s against the walk's 17.9) and stays under hopping with meter (24.1 at the
	-- same cadence); the air still steers it toward the walk, so the carry fades as before
	leapForwardWinded = st(11),
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
	-- the fastest a body falls (studs/s; reached after two seconds of free fall, 150 studs: higher than any rail or roof
	-- in the town, so no honest fall meets it). The envelope holds every claimed fall to it
	terminalFall = st(60),
	-- walk-in auto-grab (§9.1)
	autoGrabMinSpeed = st(0.45),
	-- out of an enclosed run's ground mouth: that mouth takes the body back once it is this far (studs, level) from it
	-- or the forward key changes (holding S after backing out of a hollow must not pin it at the hole)
	emergeClear = 3,
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
	-- the air trick (owner D17; redone D18, 2026-11-20): how long each move plays (s); the roll's windows round a
	-- landing (s before touchdown, s after); the re-aim's limits: either side (rad), out (the most a jump lengthens, a
	-- fraction of its whole carry on flat ground; the out scale's own ceiling, reached at the apex with half the flight
	-- left), in (the horizontal scale's fall, the downward speed added, st/s), and its rates (rad/s; reach a second); a
	-- wiggle's meter cost (of a full meter)
	trickRoll = 0.45,
	trickWiggle = 0.5,
	trickLand = 0.15,
	trickLandGrace = 0.1,
	trickAimYaw = math.rad(30),
	trickOut = 0.09,
	trickOutPeak = 0.25,
	trickIn = 0.15,
	trickDown = st(6),
	trickYawRate = 4,
	trickReachRate = 6,
	trickCost = 0.1,
	-- owner D18 ("go ahead with grab and jump cooldowns"): seconds after a leap off a rail before E grabs in the air again.
	-- Measured at 60 fps, W and sprint held, E+Space every n frames in the air (st/s along the parapet 1075 / the avenue
	-- cable 660 / up trunk 604):
	--   no cooldown   n=2 47.3 / 49.9 / 30.7   n=3 35.7 / 49.9 / 30.3   n=6 (a person's) 41.6 / 41.6 / 28.7
	--   0.065 s       n=2 39.4 / 37.5 / 29.7   n=3 41.6 / 41.6 / 28.7   n=6 41.6 / 41.6 / 28.7 (unchanged)
	-- Just under four frames: a macro's grabs wait to every fourth frame (n=2) or sixth (n=3), about a person's pace, and
	-- a person's chain (every sixth frame) and every rhythm of four frames or more never meet it. Longer is worse: 0.08 s
	-- turns a 4-frame rhythm into an 8-frame one, which the validator's trunk climb flags at 4 packets a second (an
	-- 8-frame E+Space up trunk 604 does so with no cooldown too: validator_r16's honest climb, the climb rules' to judge);
	-- 0.25 s held a person's every-sixth-frame grabs back too. A first try refused the leap off the rail instead: the
	-- macro then sat on the rail between a one-frame hop and the next grab, which short gaps judge at the rail's pace
	-- (validator_r16: 17 railSpeed flags)
	grabLeapCooldown = 0.065,
	-- owner D19 (chains along a rail and climbs up a trunk at a balanced, fun pace, not a sprint and a half): a leap off a
	-- rail the body came onto from another leap off a rail, less than chainRest s before, carries chainCarry of a leap
	-- across (what the air steers toward with it) and chainLift of its rise. A leap from rest, or after a moment on the
	-- rail, is a full one: every gap between branches is crossed as before. Measured at 60 fps, W and sprint held
	-- (st/s along the parapet 1075 / the avenue cable 660 / up trunk 604; Space held, E+Space every 6 / 3 / 2 frames):
	--   before       Space 41.4 / 41.4 / -   E+Space 41.6 / 41.6 / 28.7, 41.6 / 41.6 / 28.7, 39.4 / 37.5 / 29.7
	--   chained      Space 29.7 / 29.8 / -   E+Space 28.0 / 28.2 / 25.0, 28.0 / 28.2 / 25.0, 28.0 / 25.0 / 27.0
	-- (movement_rail_pace asserts the bands: along a rail 24-32, up a trunk 24-28, a macro about a person's)
	chainCarry = 0.69,
	chainLift = 0.88,
	chainRest = 0.25,
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
		emergedFrom = nil,
		emergedEnd = 0,
		emergedFw = 0,
		bridge = nil,
		clock = 0,
		alive = true,
		stamina = 1,
		winded = false,
		trickKind = 0,
		trickTime = 0,
		aimYaw = 0,
		aimReach = 0,
		trickReach = 0,
		footAgo = 10, -- (a new body has stood a while: no landing's roll)
		airDist = 0,
		railLeapWait = 0,
		chainWait = 0,
		leapScale = 1,
		offRail = 0,
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
	state.emergedFrom = nil
	state.routeWasMoving = false
	state.routeFreeLook = 0
	state.committedAirborne = false
	state.cameraCommit = 0
	state.attackWindow = 0
	state.railLeap = false
	state.airFromRoute = nil
	state.trickKind, state.trickTime = 0, 0
	state.aimYaw, state.aimReach, state.trickReach = 0, 0, 0
	state.footAgo, state.airDist = if grounded then 10 else 0, 0
	state.chainWait, state.leapScale, state.offRail = 0, 1, 0
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
		trick = false,
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
	"emergedEnd",
	"emergedFw",
}
local FLAGS = { "grounded", "committedAirborne", "focus", "routeWasMoving", "alive", "winded" }
local OPTIONAL_IDS = { "routeId", "pendingFork", "selectedJunction", "emergedFrom" }
-- (numbers a snapshot from before the air trick lacks: 0 when absent; the wire always carries them)
-- (aimYaw, aimReach on the wire too; trickReach, footAgo, airDist, railLeapWait, chainWait, leapScale the client's
-- own: a handover or clone keeps them)
local LATER_SCALARS = {
	"trickKind",
	"trickTime",
	"aimYaw",
	"aimReach",
	"trickReach",
	"footAgo",
	"airDist",
	"railLeapWait",
	"chainWait",
	"leapScale",
	"offRail",
}

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
	for _, k in LATER_SCALARS do
		s[k] = anyState[k] or 0
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
	for _, k in LATER_SCALARS do
		local v = s[k]
		state[k] = if type(v) == "number" then v else 0
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

-- enterRoute(found) (L5826-5869). Returns false when the transfer is refused. `ease` eases the body onto the rail from
-- off the rails too (an enclosed run's mouth: Enclosure rule 1), as a rail-to-rail transfer always is.
local function enterRoute(
	state: State,
	world: World,
	spec: Motion.EnterSpec,
	input: Input,
	events: { Event },
	ease: boolean?
): boolean
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
	if (wasOnRoute or ease == true) and gap > C.bridgeMinGap then
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
	-- (come onto it from a leap off a rail: the next leap off it within chainRest is a chained one; owner D19)
	if not wasOnRoute then
		state.chainWait = if state.offRail == 1 and not state.grounded then P.chainRest else 0
	end
	state.offRail = 0
	state.vx, state.vy, state.vz = 0, 0, 0
	state.grounded = false
	state.committedAirborne = false
	state.railLeap = false
	state.airFromRoute = nil
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

-- On an enclosed run a launch (Space, Q, a click) is allowed only at a mouth, and goes out along it (Enclosure
-- rules 2 and 3). Returns whether the launch may happen and, at a mouth, the mouth and its route. Off an enclosed
-- run: (true, nil, nil), and the caller does exactly what it always did. A mouth whose `out` has no level heading
-- (a data error Motion.enclosureErrors reports) launches nothing: never along the body's stale facing.
local function launchGate(state: State, world: World, events: { Event }): (boolean, Enclosure.Mouth?, Registry.Route?)
	local r = route(world, state.routeId)
	local spec = if r then r.enclosure else nil
	if not r or not spec then
		return true, nil, nil
	end
	local m = Enclosure.mouthAt(spec, r.length, state.railT)
	if not m or Motion.outLevel(world, r, m) == nil then
		push(events, "hint", nil, r.id, "noRoom")
		return false, nil, nil
	end
	return true, m, r
end

-- out of a mouth (Enclosure rule 3): the body leaves the rail at the launch point outside the opening's face
-- (Motion.launchPoint), never from inside the shell; returns the heading out (level `out`).
local function leaveMouth(state: State, world: World, r: Registry.Route, m: Enclosure.Mouth): (number, number, number)
	local p = Motion.launchPoint(world, r, m)
	local ox, oz = Motion.outLevel(world, r, m)
	local hx, hz = ox or math.sin(state.yaw), oz or math.cos(state.yaw)
	clearPendingFork(state)
	state.bridge = nil
	state.selectedJunction = nil
	state.x, state.y, state.z = p.x, p.y, p.z
	return math.atan2(hx, hz), hx, hz
end

-- take an enclosure's authored link (an end link or a mouth's link): the same key keeps going (dir x sign(fw)). A
-- link that cannot be taken (no such route, or farther than a transfer reaches: a data error Motion.enclosureErrors
-- reports) is not tried, so it never refuses once a frame.
local function takeLink(state: State, world: World, link: Enclosure.Link, input: Input, events: { Event }): boolean
	local target = route(world, link.route)
	if not target then
		return false
	end
	local dest = world.registry:pointAt(target, link.t)
	if math.sqrt((dest.x - state.x) ^ 2 + (dest.y - state.y) ^ 2 + (dest.z - state.z) ^ 2) > C.enterMaxGap then
		return false
	end
	local sense = if input.fw < 0 then -1 else 1
	if not enterRoute(state, world, { routeId = link.route, t = link.t, dir = link.dir * sense }, input, events) then
		return false
	end
	state.railDir = link.dir * sense
	state.routeWasMoving = input.fw ~= 0
	local heading = Motion.headingAlong(world, target, link.t, link.dir)
	if heading then
		state.yaw = heading
	end
	return true
end

-- Edge actions (key handler L5659-5681, leap L5922, attemptPounce L6482) --------------------------------

local function doLeap(state: State, world: World, events: { Event })
	if state.routeId or state.grounded then
		local allowed, mouth, mouthRoute = launchGate(state, world, events)
		if not allowed then
			return
		end
		local outHeading: number? = nil
		local hx, hz = 0, 0
		if mouth and mouthRoute then
			outHeading, hx, hz = leaveMouth(state, world, mouthRoute, mouth)
		end
		local heading = outHeading
			or SquirrelMotor.attackHeading(onTrunk(state, world), state.trunkNormalX, state.trunkNormalZ, state.yaw)
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
		local hop = if mouth then mouth.hop else nil
		if mouth and hop then
			-- a mouth's short hop (the pop out at the rack) instead of a full leap
			vx, vy, vz = hx * hop, mouth.hopUp, hz * hop
		end
		local from = state.routeId
		-- (a leap off a rail that follows another: chainCarry across, chainLift up; owner D19)
		local scale = 1
		if from ~= nil and not (mouth and hop) and state.chainWait > 0 then
			scale = P.chainCarry
			vx, vy, vz = vx * scale, vy * P.chainLift, vz * scale
		end
		state.leapScale = scale
		state.chainWait = 0
		if not mouth then
			launchFromVisibleRoute(state, world)
		end
		state.vx, state.vy, state.vz = vx, vy, vz
		state.routeId = nil
		state.grounded = false
		commitToAir(state, heading)
		state.railLeap = from ~= nil
		state.airFromRoute = from
		if from ~= nil then
			state.railLeapWait = P.grabLeapCooldown
			state.offRail = 1
		end
		state.airX, state.airY, state.airZ = state.x, state.y, state.z
		push(events, "leap", nil, from)
	end
end

local function doDrop(state: State, world: World, events: { Event })
	if state.routeId then
		local allowed, mouth, mouthRoute = launchGate(state, world, events)
		if not allowed then
			return
		end
		local from = state.routeId
		if mouth and mouthRoute then
			-- out of the opening's face with a small push out along it, so the drop clears the shell
			local _, hx, hz = leaveMouth(state, world, mouthRoute, mouth)
			state.vx, state.vz = hx * Enclosure.C.dropPush, hz * Enclosure.C.dropPush
		else
			launchFromVisibleRoute(state, world)
		end
		clearPendingFork(state)
		state.routeId = nil
		state.airFromRoute = nil
		state.offRail = 1
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
	local allowed, mouth, mouthRoute = launchGate(state, world, events)
	if not allowed then
		return
	end
	local outHeading: number? = nil
	local hx, hz = 0, 0
	if mouth and mouthRoute then
		outHeading, hx, hz = leaveMouth(state, world, mouthRoute, mouth)
	end
	local heading = outHeading
		or SquirrelMotor.attackHeading(onTrunk(state, world), state.trunkNormalX, state.trunkNormalZ, state.yaw)
	local vx, vy, vz =
		SquirrelMotor.pounceVelocity(input.cameraPitch, state.focus, state.moveSpeed, state.boostRemaining > 0, heading)
	local hop = if mouth then mouth.hop else nil
	if mouth and hop then
		vx, vy, vz = hx * hop, mouth.hopUp, hz * hop
	end
	local from = state.routeId
	state.railLeap = false
	state.airFromRoute = nil -- a pounce is aimed at prey: it never catches a branch on the way
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
	-- (a pounce is aimed: it ends the move, its re-aim and a roll's carry; a new flight of its own)
	state.trickKind, state.trickTime = 0, 0
	state.aimYaw, state.aimReach, state.trickReach = 0, 0, 0
	if not mouth then
		launchFromVisibleRoute(state, world)
	end
	state.vx, state.vy, state.vz = vx, vy, vz
	state.routeId = nil
	state.grounded = false
	state.offRail = if from ~= nil then 1 else 0
	commitToAir(state, heading)
	push(events, "pounce", nil, from)
end

local function doChoose(state: State, world: World, input: Input, events: { Event })
	local r = route(world, state.routeId)
	if not r then
		return
	end
	local side = input.choose
	if r.enclosure then
		-- an enclosed run: only its authored ways off part-way along (forks, part-way link mouths), never a junction
		-- guessed across the wall; W carries the body onto the chosen one as it passes, E takes it. The pick is kept
		-- until it is passed; the same key again with no other way on that side drops it ("junctionCleared": the run
		-- goes straight on), and a press with nothing in reach leaves the pick as it was
		local current = state.selectedJunction
		local e = Motion.chooseExit(world, r, state.railT, state.railDir, input.cameraYaw, side, current)
		if e and e.route == current then
			state.selectedJunction = nil
			push(events, "junctionCleared", e.route, r.id)
		elseif e then
			state.selectedJunction = e.route
			push(events, "junctionChosen", e.route, r.id)
		end
		return
	end
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
		local enc = r.enclosure
		if enc then
			-- at a mouth of an enclosed run that links outside (a knothole onto a bough), E takes the link (the one
			-- A/D selected, else the first)
			local m = Enclosure.mouthAt(enc, r.length, state.railT)
			if m and #m.links > 0 then
				local pick = m.links[1]
				for _, l in m.links do
					if l.route == state.selectedJunction then
						pick = l
					end
				end
				if takeLink(state, world, pick, input, events) then
					push(events, "mouthLink", pick.route, r.id)
					return
				end
			end
			-- an authored fork within reach (the selected one first, else the nearest)
			local best: Enclosure.Exit? = nil
			local bestGap = math.huge
			for _, e in Enclosure.exits(enc, r.length) do
				local gap = math.abs(e.t - state.railT) * r.length
				if e.mouth == nil and gap <= Enclosure.C.linkWindow then
					local rank = if e.route == state.selectedJunction then -1 else gap
					if rank < bestGap then
						best, bestGap = e, rank
					end
				end
			end
			if best then
				local fork = best :: Enclosure.Exit
				if takeLink(state, world, { route = fork.route, t = fork.toT, dir = fork.dir }, input, events) then
					push(events, "forkTaken", fork.route, r.id)
					return
				end
			end
			-- a part-way opening onto the ground, a ledge or the air: E steps out through it
			if m and m.t > 0 and m.t < 1 and m.opens ~= "link" and Motion.outLevel(world, r, m) ~= nil then
				local _, hx, hz = leaveMouth(state, world, r, m)
				state.routeId = nil
				state.airFromRoute = nil
				state.railLeap = false
				state.grounded = false
				state.vx, state.vy, state.vz = hx * Enclosure.C.dropPush, 0, hz * Enclosure.C.dropPush
				push(events, "emerge", nil, r.id)
				return
			end
		end
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
		elseif r.enclosure == nil then
			-- (on an enclosed run the pick is an authored exit's, taken at it: a stray E on the way keeps it)
			state.selectedJunction = nil
		end
		if state.pendingFork and r.kind == "trunk" then
			push(events, "hint", nil, nil, "climbCloser")
			return
		end
		local next = Motion.nearestRoute(
			world,
			state.x,
			state.y,
			state.z,
			C.eSearch,
			r.id,
			Motion.transferFilter(world, r, state.railT)
		)
		if next and Motion.canTransfer(next.d, true) then
			enterRoute(state, world, { routeId = next.routeId, t = next.t, d = next.d }, input, events)
		else
			push(events, "hint", nil, nil, "noTransfer")
		end
	else
		-- facing into an enclosed run's mouth within its reach, or standing at a hatch: in through the mouth (Enclosure
		-- rule 1)
		local mouth = Motion.mouthEntry(
			world,
			state.x,
			state.y,
			state.z,
			math.sin(state.yaw),
			math.cos(state.yaw),
			state.grounded
		)
		if mouth and enterRoute(state, world, mouth, input, events, true) then
			push(events, "enter", mouth.routeId)
			return
		end
		local found: Motion.Candidate? = nil
		if state.grounded then
			found = Motion.groundTrunkCandidate(world, state.x, state.y, state.z, C.groundReachE)
		elseif state.railLeapWait > 0 then
			return -- (the grab-and-jump cooldown: no grab in the air this soon after a leap off a rail)
		end
		if not found then
			found = Motion.nearestRoute(world, state.x, state.y, state.z, C.airGrab, nil, Motion.openOnly(world))
		end
		if found then
			enterRoute(state, world, { routeId = found.routeId, t = found.t, d = found.d }, input, events)
		else
			push(events, "hint", nil, nil, "nothingNear")
		end
	end
end

-- SquirrelMotor.landingIn(x, y, z, vx, vy, vz, world): the seconds until feet at (x, y, z) falling at vy and moving
-- across at (vx, vz) meet the ground: one look under the body, one where that time takes it (pure; two groundAt calls).
-- math.huge when the arc never comes down to it.
function SquirrelMotor.landingIn(
	x: number,
	y: number,
	z: number,
	vx: number,
	vy: number,
	vz: number,
	world: World
): number
	local g = P.gravity
	local function fall(gy: number): number
		local disc = vy * vy + 2 * g * (y - gy)
		if disc < 0 then
			return math.huge
		end
		return math.max(0, (vy + math.sqrt(disc)) / g)
	end
	local t = fall(world.groundAt(x, z, y))
	if t < math.huge then
		t = fall(world.groundAt(x + vx * t, z + vz * t, y))
	end
	return t
end

-- SquirrelMotor.trickReachAt(airTime, carried, rest): how far out a wiggle pressed `airTime` s into a flight that has
-- carried `carried` studs across and has about `rest` studs to go (its speed across for the time to its landing) may
-- scale the horizontal speed (the scale's top, 1 + this). Timing: it grows to trickOutPeak at a leap's apex (leapUp /
-- gravity in), none at the takeoff; and never more than trickOut of the whole carry: the rest scaled adds reach x rest
-- against carried + rest. The air steers toward the same scale (reaim), so the rest is that same flight scaled; a flight
-- slows across (the air's drag and steering), so its true rest is no longer than the estimate and the lengthening no
-- more than trickOut. The server, knowing no landing, takes the timing's bound alone (rest 0). Pure.
function SquirrelMotor.trickReachAt(airTime: number, carried: number, rest: number): number
	local timing = P.trickOutPeak * math.clamp(airTime / (P.leapUp / P.gravity), 0, 1)
	local whole = if rest > 1e-3 then P.trickOut * (1 + math.max(carried, 0) / rest) else math.huge
	return math.clamp(math.min(timing, whole), 0, P.trickOutPeak)
end

-- the horizontal scale a re-aim of `e` (-1 in .. 1 out) gives with out-reach `reach`, and the vertical speed it adds
-- (st/s: 0 out, down to -trickDown in). Pure.
function SquirrelMotor.aimScale(e: number, reach: number): number
	return if e >= 0 then 1 + reach * e else 1 + P.trickIn * e
end
function SquirrelMotor.aimDown(e: number): number
	return P.trickDown * math.min(e, 0)
end

-- SquirrelMotor.reaim(state, wantYaw, wantReach, dt): one step of the re-aim toward what is wanted (nil: as applied),
-- at most trickYawRate / trickReachRate x dt: the velocity turned by the yaw's change (speed kept), its horizontal part
-- scaled and its vertical speed given the reach's change (aimScale, aimDown); the applied aim kept on the state.
function SquirrelMotor.reaim(state: State, wantYaw: number?, wantReach: number?, dt: number)
	local ty = math.clamp(wantYaw or state.aimYaw, -P.trickAimYaw, P.trickAimYaw)
	local te = math.clamp(wantReach or state.aimReach, -1, 1)
	local ny = state.aimYaw + math.clamp(ty - state.aimYaw, -P.trickYawRate * dt, P.trickYawRate * dt)
	local ne = state.aimReach + math.clamp(te - state.aimReach, -P.trickReachRate * dt, P.trickReachRate * dt)
	local d = ny - state.aimYaw
	if d ~= 0 then
		-- (the heading atan2(vx, vz) grows by d)
		local c, s = math.cos(d), math.sin(d)
		state.vx, state.vz = state.vx * c + state.vz * s, state.vz * c - state.vx * s
	end
	if ne ~= state.aimReach then
		local k = SquirrelMotor.aimScale(ne, state.trickReach)
			/ SquirrelMotor.aimScale(state.aimReach, state.trickReach)
		state.vx *= k
		state.vz *= k
		state.vy += SquirrelMotor.aimDown(ne) - SquirrelMotor.aimDown(state.aimReach)
	end
	state.aimYaw, state.aimReach = ny, ne
end

-- SquirrelMotor.freshMove(prev, next, kind): `next` claims a move of `kind` pressed after `prev` (a new one, not the one
-- `prev` had playing): its press, dated by its time left, later than `prev`'s (a move's time runs down with the clock, so
-- the same move has no more left than `prev`'s less the gap). Pure; the envelope and the validator's meter use it.
function SquirrelMotor.freshMove(prev: State, next: State, kind: number): boolean
	local nt = next.trickTime or 0
	if next.trickKind ~= kind or nt <= 0 then
		return false
	end
	if prev.trickKind ~= kind then
		return true
	end
	return nt > (prev.trickTime or 0) - (next.clock - prev.clock) + 1e-4
end

-- SquirrelMotor.unaim(s, toYaw, toReach): a copy of `s` with its velocity as a re-aim at (toYaw, toReach) would have
-- left it: the step reaim takes undone (the turn back, the scale back at the most a press may reach, the vertical
-- speed given back). Pure; the envelope judges a re-aimed flight by it (0c).
function SquirrelMotor.unaim(s: State, toYaw: number, toReach: number): State
	local c = table.clone(s)
	local k = SquirrelMotor.aimScale(toReach, P.trickOutPeak) / SquirrelMotor.aimScale(s.aimReach, P.trickOutPeak)
	local d = toYaw - s.aimYaw
	local cs, sn = math.cos(d), math.sin(d)
	local vx, vz = s.vx * k, s.vz * k
	c.vx, c.vz = vx * cs + vz * sn, vz * cs - vx * sn
	c.vy = s.vy + SquirrelMotor.aimDown(toReach) - SquirrelMotor.aimDown(s.aimReach)
	return c
end

-- The air trick's button (owner D18): on the ground just after a landing, or in the air with touchdown close, the
-- barrel roll; in the air further from it, once a flight, the wiggle and the re-aim from then on (its reach fixed now,
-- a trickCost of the meter when there is any). Not on a rail or a transfer, nor in a pounce's window, nor in a roll.
local function doTrick(state: State, world: World, events: { Event })
	if state.routeId ~= nil or state.bridge ~= nil or state.attackWindow > 0 or state.trickKind == 1 then
		return
	end
	local roll = false
	if state.grounded then
		roll = state.footAgo <= P.trickLandGrace
	else
		local landIn = SquirrelMotor.landingIn(state.x, state.y, state.z, state.vx, state.vy, state.vz, world)
		if state.vy <= 0 and landIn <= P.trickLand then
			roll = true
		elseif state.trickKind == 0 then
			state.trickKind, state.trickTime = 2, P.trickWiggle
			state.aimYaw, state.aimReach = 0, 0
			local across = math.sqrt(state.vx * state.vx + state.vz * state.vz)
			state.trickReach = SquirrelMotor.trickReachAt(state.footAgo, state.airDist, across * landIn)
			if not state.tireless and state.stamina > 0 then
				state.stamina = math.max(0, state.stamina - P.trickCost)
				if state.stamina == 0 and not state.winded then
					state.winded = true
					push(events, "winded")
				end
			end
			push(events, "trick", nil, nil, "wiggle")
		end
	end
	if roll then
		state.trickKind, state.trickTime = 1, P.trickRoll
		push(events, "trick", nil, nil, "roll")
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
	local from = world.wallsFrom
	if from then
		from(oldX, oldZ, y)
	end
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

-- A leap off a rail lands on the branch or wire its flight lines up with: another rail once the body is
-- clear of the launch point, the rail it left only further along and on the way down. A drop (Q) and a
-- pounce are meant to reach the ground or the prey and catch nothing.
local function catchRail(state: State, world: World, input: Input, events: { Event })
	local from = state.airFromRoute
	local ax, ay, az = state.airX, state.airY, state.airZ
	if from == nil or ax == nil or ay == nil or az == nil then
		return
	end
	local travelled = math.sqrt((state.x - ax) ^ 2 + (state.y - ay) ^ 2 + (state.z - az) ^ 2)
	if travelled < C.airCatchClear then
		return
	end
	local own = travelled >= C.airCatchOwn and state.vy < 0
	local found = Motion.airCatch(world, state.x, state.y, state.z, C.airCatch, if own then nil else from)
	if found and enterRoute(state, world, { routeId = found.routeId, t = found.t, d = found.d }, input, events) then
		push(events, "catch", found.routeId, from)
	end
end

local function substep(state: State, input: Input, dt: number, world: World, events: { Event }, footFrom: boolean?)
	local reg = world.registry
	local wasFoot = if footFrom ~= nil then footFrom else (state.grounded or state.routeId ~= nil)
	state.railLeapWait = math.max(0, state.railLeapWait - dt)
	if state.routeId ~= nil then
		state.chainWait = math.max(0, state.chainWait - dt)
	elseif state.grounded then
		state.offRail = 0
	end
	state.cameraCommit = math.max(0, state.cameraCommit - dt)
	if state.routeId == nil and not state.grounded and state.airFromRoute ~= nil then
		catchRail(state, world, input, events)
	end
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

	-- into an enclosed run through a mouth (Enclosure rule 1): moving into it within its reach, on the ground or in
	-- the air (a leap or a pounce too: going in ends the attack); eased onto the rail. Nothing happens here in a
	-- world without enclosed runs.
	local wasGrounded = state.grounded
	local lockedMouth: number? = nil
	if state.emergedFrom ~= nil then
		local er = route(world, state.emergedFrom)
		local clear = rail ~= nil or er == nil or math.sign(fw) ~= state.emergedFw
		if not clear and er then
			local p = reg:pointAt(er, state.emergedEnd)
			clear = (state.x - p.x) ^ 2 + (state.z - p.z) ^ 2 > P.emergeClear * P.emergeClear
		end
		if clear then
			state.emergedFrom = nil
		else
			lockedMouth = state.emergedFrom
		end
	end
	if not rail then
		local mvx, mvz = 0, 0
		if state.grounded and state.attackWindow == 0 then
			if moving and state.moveSpeed > P.autoGrabMinSpeed then
				mvx = -math.sin(input.cameraYaw) * fw + math.cos(input.cameraYaw) * side
				mvz = -math.cos(input.cameraYaw) * fw - math.sin(input.cameraYaw) * side
			end
		else
			mvx, mvz = state.vx, state.vz
		end
		if mvx ~= 0 or mvz ~= 0 then
			local mouth = Motion.mouthEntry(world, state.x, state.y, state.z, mvx, mvz)
			if mouth and mouth.routeId ~= lockedMouth and enterRoute(state, world, mouth, input, events, true) then
				state.attackWindow, state.attack = 0, 0
				push(events, "enter", mouth.routeId)
				rail = route(world, state.routeId)
			end
		end
	end

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
			local railSpeed = Motion.routeSpeed(rs, sprint, state.focus, state.boostRemaining > 0)
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
			-- an enclosed run's exit picked with A/D: taken as the body passes it with W or S held
			local encSpec = rs.enclosure
			local picked = state.selectedJunction
			if encSpec and picked and fw ~= 0 and state.routeId == rs.id and before ~= state.railT then
				for _, e in Enclosure.exits(encSpec, rs.length) do
					if e.route == picked and (before - e.t) * (state.railT - e.t) <= 0 then
						state.railT = e.t
						local p = reg:pointAt(rs, e.t)
						state.x, state.y, state.z = p.x, p.y, p.z
						if takeLink(state, world, { route = e.route, t = e.toT, dir = e.dir }, input, events) then
							push(events, if e.mouth then "mouthLink" else "forkTaken", e.route, rs.id)
						end
						break
					end
				end
			end
			local emergedAt: number? = nil
			if state.routeId == rs.id and (state.railT >= 1 or state.railT <= 0) and rs.enclosure and fw ~= 0 then
				-- the end of an enclosed run (reached, or pressed against): its mouth or its authored link says what
				-- comes next (rules 3, 4); `arrived` only on the substep that got there
				local atStart = state.railT <= 0
				local arrived = if atStart then before > 0 else before < 1
				state.railT = math.clamp(state.railT, 0, 1)
				if fw ~= 0 then
					local spec = rs.enclosure :: Enclosure.Spec
					local m = Enclosure.endMouth(spec, rs.length, atStart)
					local link = Enclosure.endLink(spec, atStart)
					local lox, loz = nil, nil
					if m then
						lox, loz = Motion.outLevel(world, rs, m)
					end
					if m and m.opens == "ground" and lox and loz then
						-- step out onto the ground on its feet, still running, heading out of the mouth
						local ox, oz = lox, loz
						clearPendingFork(state)
						state.routeId = nil
						state.bridge = nil
						state.selectedJunction = nil
						state.routeWasMoving = false
						state.grounded = true
						state.committedAirborne = false
						state.railLeap = false
						state.airFromRoute = nil
						state.yaw = math.atan2(ox, oz)
						state.vx, state.vy, state.vz = ox * state.moveSpeed, 0, oz * state.moveSpeed
						emergedAt = if atStart then 0 else 1
						state.emergedFrom, state.emergedEnd, state.emergedFw =
							rs.id, if atStart then 0 else 1, math.sign(fw)
						push(events, "emerge", nil, rs.id)
					elseif m and m.opens == "link" and #m.links > 0 then
						if takeLink(state, world, m.links[1], input, events) then
							push(events, "autoSwitch", m.links[1].route, rs.id)
						elseif arrived then
							push(events, "railEnd", rs.id, nil, "link")
						end
					elseif m and m.opens ~= "link" then
						-- a ledge or a hole in the air: stop with the head out; Space, a click or Q goes out. Stopped
						-- here, a view turned round with W still held turns back at once (the lip is a stop)
						if arrived then
							push(events, "lip", rs.id, nil, m.opens)
						end
						state.routeWasMoving = false
					elseif link then
						if takeLink(state, world, link, input, events) then
							push(events, "autoSwitch", link.route, rs.id)
						else
							if arrived then
								push(events, "railEnd", rs.id, nil, "link")
							end
							state.routeWasMoving = false
						end
					else
						if arrived then
							push(events, "railEnd", rs.id, nil, "none")
						end
						state.routeWasMoving = false
					end
				end
			elseif state.routeId == rs.id and (state.railT > 1 or state.railT < 0) then
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
			if emergedAt then
				-- out of the mouth: on the ground at the route's end, running (the ground takes over next substep)
				local p = reg:pointAt(rs, emergedAt)
				state.x, state.y, state.z = p.x, p.y, p.z
			else
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
		end
	else
		state.routeWasMoving = false
		state.selectedJunction = nil
		state.bridge = nil
		local camYaw = input.cameraYaw
		-- (a barrel roll on the ground carries the speed it landed with: neither steered nor slowed, as a pounce's window)
		local rolling = state.grounded and state.trickKind == 1 and state.trickTime > 0
		if moving and state.attackWindow == 0 and not rolling then
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
				steer = math.max(steer, v54 * (if state.boostRemaining > 0 then P.boostMult else 1) * state.leapScale)
			end
			if state.aimReach ~= 0 and not state.grounded then
				-- (the air trick's re-aim scales what the air steers toward as it scaled the speed: the flight's rest is the
				-- same flight, that much longer or shorter)
				steer *= SquirrelMotor.aimScale(state.aimReach, state.trickReach)
			end
			state.vx += (dx * steer - state.vx) * a
			state.vz += (dz * steer - state.vz) * a
			state.yaw = Motion.turnToward(
				state.yaw,
				math.atan2(dx, dz),
				if state.focus then P.turnRateFocus else P.turnRate,
				dt
			)
		elseif state.attackWindow == 0 and not rolling then
			local friction = math.exp(-dt * (if state.grounded then P.dragGround else P.dragAir))
			state.vx *= friction
			state.vz *= friction
		end
		if state.trickKind == 2 and not state.grounded and state.attackWindow == 0 then
			-- (the air trick's re-aim, live from the wiggle's press to the landing)
			SquirrelMotor.reaim(state, input.aimYaw, input.aimReach, dt)
		end
		if state.focus and not moving then
			state.yaw = Motion.turnToward(state.yaw, camYaw + math.pi, P.faceCameraRate, dt)
		end
		state.vy = math.max(state.vy - P.gravity * dt, -P.terminalFall)
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
			state.airFromRoute = nil
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
		-- a flight (a fall, a leap, a pounce) through a mouth's disc during this substep: in through it (Enclosure
		-- rule 1, judged on the swept path so a fast flight is not missed); going in ends the attack
		if not wasGrounded then
			local mouth = Motion.mouthEntrySwept(world, oldX, oldY, oldZ, state.x, state.y, state.z, state.vx, state.vz)
			if mouth and enterRoute(state, world, mouth, input, events, true) then
				state.attackWindow, state.attack = 0, 0
				push(events, "enter", mouth.routeId)
			end
		end
	end

	state.routeFreeLook = math.max(0, state.routeFreeLook - dt)
	-- the air trick: the footing's clock; leaving the ground ends a roll's carry; a rail ends every move; a landing ends
	-- the flight's wiggle and its re-aim, while a roll plays on along the ground
	local foot = state.grounded or state.routeId ~= nil
	state.airDist = if foot then 0 else state.airDist + math.sqrt((state.x - oldX) ^ 2 + (state.z - oldZ) ^ 2)
	if foot ~= wasFoot then
		state.footAgo = 0
		if not foot and state.trickKind == 1 then
			state.trickKind, state.trickTime = 0, 0
		end
	else
		state.footAgo = math.min(state.footAgo + dt, 10)
	end
	if foot then
		state.aimYaw, state.aimReach, state.trickReach = 0, 0, 0
		if state.routeId ~= nil or state.trickKind == 2 then
			state.trickKind, state.trickTime = 0, 0
		end
	end
	state.trickTime = math.max(0, state.trickTime - dt)
	if foot and state.trickTime <= 0 then
		state.trickKind = 0
	end
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
-- (A/D, E, Q, Space, click, the trick), then updatePlayer substeps of <= 1/60 s (dt capped at 0.08 s).
function SquirrelMotor.step(state: State, input: Input, dt: number, world: World): (State, { Event })
	local events: { Event } = {}
	if not state.alive then
		return state, events
	end
	local footFrom = state.grounded or state.routeId ~= nil
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
	if input.trick then
		doTrick(state, world, events)
	end
	local frameDt = math.min(dt, P.frameDtCap)
	local steps = math.clamp(math.ceil(frameDt / P.substep - 1e-9), 1, P.maxSubsteps)
	local sub = frameDt / steps
	for i = 1, steps do
		-- (the first substep knows the footing the frame began on: a leap's takeoff starts the flight's clock)
		substep(state, input, sub, world, events, if i == 1 then footFrom else nil)
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
-- changes against the route graph and the transfer gaps, and ground moves against world.crosses. Enclosed runs
-- (Routes/Enclosure) add one check, only where a move touches one ("enclosure"): a body gets on only within reach
-- of a mouth that opens to the outside (a hatch: from its lid at a sprint's pace and within its rise), gets off only
-- at a mouth, and changes rail across the wall only where a mouth's links say (an authored link is a declared
-- junction, whatever gap the Graph sees). Vertical speed (the combat re-review, 2026-11-19): off the rails a body on
-- the ground has none and no fall passes P.terminalFall; every launch ends at a speed gravity could bring a launch
-- down to in the gap, rises what that launch can reach ((u^2 - v^2) / 2g), and in the air only the motor's pounce
-- launches, recognised by its window (the window rose to what it is a moment after a pounce, the body flies as that
-- pounce: pounceAgo); a plain arc rises no more than the mean of its end speeds; the wall test's rise is a launch's
-- apex at most. Round 3 (2026-11-19: no allowance sized from a number only the client claimed): a landing hidden in a
-- gap is timed from the validator's own vertical speed and ends on the floor a ray finds, or a leap over it in the time
-- left (landedIn); a rail visit hidden in a gap explains a rise only from a rail high enough (railHigh); leaving a rail
-- is wall-tested from the launch point; a long line chord by chord; a pounce slower than a lunge met a wall where the
-- server's own two places say; and the envelope returns what it judged (Judged) for the validator's baseline.

export type Violation = { code: string, severity: number, detail: string }

SquirrelMotor.envelopeParams = {
	speedTol = 1.15, -- ground and air horizontal speed tolerance (latency, substep rounding)
	railTol = 1.05, -- rail parameter speed tolerance (deterministic advance)
	launchTol = 1.1, -- leap / pounce launch velocities
	posSlack = st(0.05), -- on-rail position agreement (the client runs the same curve)
	gravityEps = 0.03, -- seconds of gravity the vertical speed may deviate by
	maxDt = 0.5, -- larger gaps are resynced, not judged
	forkEnterMaxT = 0.06, -- a fork or sibling hop lands near the bough start (0.018 / 0.03)
	pounceMinInterval = 0.7 / 1.15, -- cooldown with tolerance (between two pounces, on the ground or in the air)
	shortDt = 0.05, -- up to three ticks: nothing can hide between packets; longer gaps relax
	-- seconds: a packet's dt within this of a threshold is at it (the clocks are sums of floats: three 1/60 s frames make
	-- 0.05000000000000004, and a packet of the motor's own three frames was a long gap: validator round 16, the round-15
	-- review's LOW 2)
	dtEps = 1e-6,
	-- seconds: the longest gap the grab search steps (a launch in the air is free only off a grab the motor's own step
	-- explains): two of the longest packets the client's own send rule makes (a short frame that sends nothing and the
	-- next, capped, that does), one of them lost (validator round 15, the round-14 review's MEDIUM 2: 0.1 s charged an
	-- honest grab-leap in a 0.13 s packet; on a lossy, jittery link one lost packet hid as many, and their leapCost ran
	-- the server's meter empty under a full client one)
	grabSimDt = 2 * (SquirrelWire.SEND_EVERY + P.frameDtCap),
	-- the grab search's reach and work for one packet (validator round 15, the round-14 review's MEDIUM 3): the rail
	-- samples gathered once round the body's own arc, a grab and grabReach further (studs: a later grab's reach), and at
	-- most grabWork sample visits over the gather and every grab's scan; a pattern past either explains nothing (fail
	-- safe: "not grasped", charged, never a violation of its own); each further grab tried from the grabBeam patterns
	-- nearest the end at most)
	grabReach = st(3.4),
	grabWork = 2500,
	grabBeam = 12,
	-- studs: a route's sample spacing when the registry has not the route (its own is length / (sampleCount - 1), at
	-- most a third of an HTML unit: Curve.sampleSteps); the grab search's band along a rail (validator round 16)
	sampleSpacing = st(1 / 3),
	groundVy = 0.5, -- studs/s: a body on the ground off the rails has no vertical speed (the motor's is exactly 0)
	-- studs: how far over the floor the server's rays find the client may stand (its ground plates are up to 0.3 over
	-- the colliding surface): a landing hidden in a gap ends no higher than this over the floor it came down on
	floorSlack = st(0.2),
	-- a pounce slower than a lunge met a wall: within wallAhead (studs) along the move the server saw, or along its heading
	-- when it moved that way, when it moved at least wallMoved; a body that hardly moved touches it (wallTouch along its
	-- heading: the body's half-width and a bit)
	wallAhead = 3,
	wallMoved = 0.25,
	wallTouch = 1.5,
	-- the packet's own fields (fieldCheck): how far from 1 the trunk normal's length may be (the motor's is a unit
	-- vector to f32 rounding), the longest chili rush (Tunables chili.chiliRushCap) and the longest a click's copy
	-- rides in the packets (Movement/SquirrelWire)
	normalTol = 0.01,
	boostMax = 90,
	clickCopy = SquirrelWire.CLICK_COPY,
}
local E = SquirrelMotor.envelopeParams
-- (how far over the motor's own speeds a modelled step may go: its substeps of other lengths, rounding)
local C_STEP = 1.02

-- the grab search's scratch, reused by every envelope (each runs to its end before another starts): the samples a packet
-- gathers (id, t, x, y, z, height bin) and the same in order of height, the bins' starts and fills, a grab's band
local GS = {
	id = {} :: { number },
	t = {} :: { number },
	x = {} :: { number },
	y = {} :: { number },
	z = {} :: { number },
	b = {} :: { number },
	sid = {} :: { number },
	st = {} :: { number },
	sx = {} :: { number },
	sy = {} :: { number },
	sz = {} :: { number },
	start = {} :: { number },
	fill = {} :: { number },
	band = {} :: { number },
}

-- drawnOf(world, route): how far the drawn pose (Motion.visualPose) lies off a route's samples, the most across (at its
-- start, where a trunk is widest and a bough's clearance off its trunk most) and the lift (a bough's, a wire's: the same
-- all along), kept per route (the grab search asks it of every sample a grab may take)
local drawnCache: { [any]: { across: number, lift: number } } = setmetatable({}, { __mode = "k" }) :: any
local function drawnOf(world: World, r: Registry.Route): { across: number, lift: number }
	local d = drawnCache[r]
	if d == nil then
		local w = Motion.visualPose(world, r, 0, Curve.vec3(0, 0, 0), 1, 0)
		d = { across = math.sqrt(w.x * w.x + w.z * w.z), lift = math.max(0, w.y) }
		drawnCache[r] = d
	end
	return d :: { across: number, lift: number }
end

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

-- runCap(boosted): the fastest the body runs on the ground (a sprint, the chili rush's), no leap's carry: a way round a
-- corner is run (validator round 10: the budget of a way round, world.around)
function SquirrelMotor.runCap(boosted: boolean): number
	return P.sprint * (if boosted then P.boostMult else 1)
end

function SquirrelMotor.railCap(treeTravel: boolean, boosted: boolean): number
	return Motion.railSpeed(treeTravel, true, false, boosted)
end

-- routeCap(route, boosted): the cap on a given route, its own pace included (Motion.routeSpeed: a storm drain's pipe
-- runs at Tunables sewer.speedMult, every other route at 1). Every rail bound of the envelope uses it.
function SquirrelMotor.routeCap(r: Registry.Route, boosted: boolean): number
	return Motion.routeSpeed(r, true, false, boosted)
end

function SquirrelMotor.launchCapXZ(boosted: boolean): number
	return math.max(
		if boosted then P.leapForwardBoost else P.leapForward,
		P.pounceSpeedFast * (if boosted then P.pounceBoostMult else 1)
	)
end

-- speedBound(u, s, goal, grounded, t, hold?, floor?) -> (studs, u', s'): the most a body covers across in t seconds by
-- the motor's own speed step (substep, off the rails; validator round 12: the server's sprint meter and air bound follow
-- it), from a horizontal speed of at most u and a moveSpeed of at most s whose goal is `goal` (the walk, the sprint):
-- moveSpeed eases toward the goal at speedSmooth, and the velocity toward moveSpeed at accelGround / accelAir, or, when it
-- leaves more, coasts under dragGround / dragAir (no key held); the first `hold` seconds it keeps its speed (a pounce's
-- window: neither steered nor dragged); a leap off a rail steers toward at least `floor` (v5.4's own speeds). Stepped at
-- the motor's substep, each step's distance no less than the motor's own steps of any length cover. Returns the bound's u and s after.
function SquirrelMotor.speedBound(
	u: number,
	s: number,
	goal: number,
	grounded: boolean,
	t: number,
	hold: number?,
	floor: number?
): (number, number, number)
	local accel = if grounded then P.accelGround else P.accelAir
	local drag = if grounded then P.dragGround else P.dragAir
	local h = P.substep
	local ks, ka, kd = 1 - math.exp(-h * P.speedSmooth), 1 - math.exp(-h * accel), math.exp(-h * drag)
	local d = 0
	local left = math.max(t, 0)
	local held = math.min(math.max(hold or 0, 0), left)
	-- (the window: the velocity as it is, moveSpeed easing on)
	d += u * held
	left -= held
	s += (goal - s) * (1 - math.exp(-held * P.speedSmooth))
	local lo = floor or 0
	while left > 1e-9 do
		local step = math.min(h, left)
		if step < h then
			ks, ka, kd = 1 - math.exp(-step * P.speedSmooth), 1 - math.exp(-step * accel), math.exp(-step * drag)
		end
		s += (goal - s) * ks
		local u1 = math.max(u + (math.max(s, lo) - u) * ka, u * kd)
		-- (the motor moves by the new speed; slowing, the mean of the two, which no length of substep exceeds)
		d += math.max(u1, (u + u1) / 2) * step
		left -= step
		local settled = math.abs(u1 - u) < 1e-4 and math.abs(goal - s) < 1e-4
		u = u1
		if settled then
			-- (settled: the rest at that pace, whatever the gap's length)
			d += u * left
			break
		end
	end
	return d, u, s
end

-- What the envelope judged of `next`, for the validator's own baseline (the round-3 review: every number a later
-- packet is judged by is the server's own or one a check has bounded, never one only the client claimed):
--   vy: the vertical speed to keep (0 on the ground or a rail; gravity's after a plain arc, so the slack each packet
--       may claim never adds up to a slower fall; else the claim held to the bounds it was judged against);
--   xz: the most horizontal speed to keep (the cap the packet was judged against; 0 on a rail);
--   y: after a plain arc, the height to keep: no higher than the arc (nil: the packet's own);
--   landed: the body came down on a floor inside the gap and walked off its edge (on the ground, for the sprint meter);
--   longWall: the straight line was too long for the short wall test and a chord of it went through a wall (the
--       validator weighs it as a gap's: one may be a corner rounded unseen);
--   cornered: ... and a way round a corner is clear (world.around asked, the line within world.aroundMax: not "too long
--       to tell"; validator round 10);
--   charge: a launch the motor's sprint meter pays for (validator round 11, the round-10 review's HIGH): "leap" (leapCost)
--       or "pounce" (pounceCost) off the ground, or a pounce in the air; nil for none, or one off a rail the server has the
--       body on (seen, or a grab the motor's own step from the last packet explains: validator round 14) or a
--       trampoline's bounce, which are free. A launch a long gap's rail visit only explains (a rail near) is charged.
--   railLaunch: the launch is off a rail the server has the body on, as for `charge` (validator round 13: the motor's
--       railLeap, a free flight; round 14: never a rail merely near; a bounce alone is none).
-- (grab: the client clock of the last hidden grab a short gap's move was explained by: envelope's lastGrab next time;
-- grabFrom: that explanation's first grab, its client clock, the sample's place across and how far the grab's snap
-- reached from where the body was: the validator's air bound starts there, validator round 15; grabRoute: the route its
-- last grab took, the one the free flight leaves)
export type Judged = {
	vy: number,
	xz: number,
	y: number?,
	landed: boolean,
	longWall: boolean,
	cornered: boolean?,
	charge: string?,
	railLaunch: boolean?,
	grab: number?,
	grabFrom: { clock: number, x: number, z: number, reach: number }?,
	grabRoute: number?,
	-- the grab search explained the move with chained leaps only (owner D19): the most across they carry, the speed kept
	chainXZ: number?,
	-- the move was explained only by a wiggle pressed inside the gap (envelope 0c): the meter's trickCost is due
	trickHidden: boolean?,
}

-- The motor packet, field by field (validator round 5: the round-4 review's worst hole came from a field nobody checked,
-- the trunk normal): what bounds every field of Shared/Movement/SquirrelWire, so that no number the validator or the
-- duel reads is the client's word alone. fieldCheck judges the ranges, enums and lengths here on every packet (the
-- baseline included); the envelope judges each field's consistency with the last packet; MoveValidator and
-- MovementService the sequence, the epoch and the clock. A spec holds every wire field to an entry here.
SquirrelMotor.FIELD_BOUNDS = table.freeze({
	seq = "rises (MoveValidator: an older or repeated one is dropped); |seq| < MAX_MAGNITUDE",
	epoch = "equals the epoch the server last gave (MovementService: else dropped as stale)",
	flags = "a byte of bits, each one of the booleans below (the wire reads them so)",
	grounded = "boolean (a wire bit); on the ground no vertical speed (envelope 0b), a floor under the feet (MoveValidator)",
	committedAirborne = "boolean (a wire bit); read by no judgement",
	focus = "boolean (a wire bit); read by no judgement",
	routeWasMoving = "boolean (a wire bit); read by no judgement",
	alive = "boolean (a wire bit); read by no judgement",
	winded = "boolean (a wire bit); read by no judgement (the server keeps its own sprint meter)",
	bridgeActive = "boolean (a wire bit); only on a rail (fieldCheck)",
	railDir = "enum -1 or 1 (the wire keeps the sign only)",
	x = "against the last packet: rail speed, transfer, grab, launch, speed and teleport bounds, walls (envelope)",
	y = "against the last packet: gravity, launch rise, landing, climb and floor (envelope, MoveValidator)",
	z = "as x",
	railT = "[0, 1], and on a rail the body at that point or on its transfer (fieldCheck, every packet); its pace (envelope 2)",
	clock = "rises (dt > 0), never ahead of the arrivals (MoveValidator's clock check); a gap over maxDt is a hop",
	vx = "horizontal speed within the fastest cap on any packet (fieldCheck), each move's own cap off a rail (envelope)",
	vy = "within [-terminal, a trampoline's bounce] on any packet (fieldCheck); 0 on the ground, gravity, launch bounds (envelope)",
	vz = "as vx",
	yaw = "any finite angle: read only through sin and cos (the slow pounce's heading)",
	moveSpeed = "[0, sprint x boost] (fieldCheck); read by no judgement",
	boostRemaining = "[0, boostMax] (fieldCheck); never trusted (the server's boostOf)",
	cooldown = "[0, pounceCooldown] (fieldCheck); the pounce rate is judged by the window's dates",
	attack = "[0, pounceAttack] (fieldCheck)",
	attackWindow = "[0, pounceWindow] (fieldCheck); a pounce's date only as the window's fall within the gap (envelope)",
	cameraCommit = "[0, the longest commit] (fieldCheck)",
	trunkNormalX = "the trunk normal is a unit vector, |n| within normalTol of 1 (fieldCheck; Motion.visualPose also normalises it)",
	trunkNormalZ = "as trunkNormalX",
	routeFreeLook = "[0, freeLookAfterTransfer] (fieldCheck)",
	stamina = "[0, 1] (fieldCheck); the server keeps its own meter",
	emergedEnd = "enum 0 or 1 (fieldCheck)",
	emergedFw = "[-1, 1] (fieldCheck)",
	routeId = "-1 or a route of the world, the body where its railT says (fieldCheck, every packet)",
	pendingFork = "-1 or a route of the world (fieldCheck)",
	selectedJunction = "-1 or a route of the world (fieldCheck)",
	emergedFrom = "-1 or a route of the world (fieldCheck)",
	bfx = "the transfer's start within a transfer's reach of its target (fieldCheck; an enclosed run's mouth: envelope 0), within reach of the last packet when new, and new only on a change of rail (envelope 1)",
	bfy = "as bfx",
	bfz = "as bfx",
	btx = "the transfer's target on the rail at railT (envelope 1)",
	bty = "as btx",
	btz = "as btx",
	bElapsed = "[0, bDuration] (fieldCheck); new: no more than the gap, else on from the last packet's by the gap (envelope 1)",
	bDuration = "Motion.bridgeDuration of the transfer's own length (fieldCheck)",
	clickSeq = "0 (none) or 1..255, a click counted once, the newer only (MovementService.clickNew)",
	clickAgo = "[0, SquirrelWire.CLICK_COPY], 0 with no click (fieldCheck); the click dated as the remote's (clickAt)",
	trickKind = "enum 0, 1 or 2; never on a rail, a wiggle (2) only in the air (fieldCheck); a fresh one dates the server's meter charge and the roll's carry (MoveValidator._stamina, once a flight by the server's own footing); a wiggle's flight may be re-aimed (envelope 0c, 5)",
	trickTime = "[0, the move's own length] (trickRoll, trickWiggle), 0 with no move (fieldCheck); dates a roll's carry (MoveValidator._stamina)",
	aimYaw = "[-trickAimYaw, trickAimYaw], 0 on the ground, a rail or with no move (fieldCheck); moves at most trickYawRate x dt and only in a wiggle's flight, undone before the move is judged (envelope 0c)",
	aimReach = "[-1, 1], 0 on the ground, a rail or with no move (fieldCheck); moves at most trickReachRate x dt, only in a wiggle's flight, undone at the most a press reaches (envelope 0c); the server's air bound scales by its own reach (MoveValidator._stamina)",
})

-- poseAgreement(world, r, railT, x, y, z, b, out): a packet on rail `r` is where its rail parameter says (validator
-- round 6, the round-5 review's CRITICAL: a packet the envelope did not judge kept any railT, and the next one was
-- judged by it alone): the body within posSlack of the centreline at railT, or, in a transfer, the transfer's target
-- there, its easing in range and the body on its segment at the eased fraction. One pointAt. The drawn pose (a unit
-- trunk normal) is the only place off the centreline, and it is the server's own (Motion.visualPose).
local function poseAgreement(
	world: World,
	r: Registry.Route,
	railT: number,
	x: number,
	y: number,
	z: number,
	b: Bridge?,
	out: { Violation }
)
	local dest = world.registry:pointAt(r, math.clamp(railT, 0, 1))
	if b then
		if hypot2(b.tx - dest.x, b.tz - dest.z) > E.posSlack or math.abs(b.ty - dest.y) > E.posSlack then
			add(out, "railPose", 1, "transfer target off the rail")
		end
		if
			b.elapsed > b.duration + 1e-9
			or b.elapsed < -1e-6
			or b.duration < C.bridgeMin - 1e-9
			or b.duration > C.bridgeMax + 1e-9
		then
			add(out, "railPose", 1, "transfer easing out of range")
			return
		end
		local p = Motion.ease(b.elapsed / b.duration)
		local ex, ey, ez = b.fx + (b.tx - b.fx) * p, b.fy + (b.ty - b.fy) * p, b.fz + (b.tz - b.fz) * p
		if hypot2(ex - x, ez - z) > E.posSlack or math.abs(ey - y) > E.posSlack then
			add(out, "railPose", 1, "body off the transfer segment")
		end
	else
		local off = math.sqrt((dest.x - x) ^ 2 + (dest.y - y) ^ 2 + (dest.z - z) ^ 2)
		if off > E.posSlack then
			add(out, "railPose", math.min(1, Units.u(off)), `body {off} st off the rail centreline at t {railT}`)
		end
	end
end

-- fieldCheck(snapshot, world) -> violations: the ranges, enums and lengths of FIELD_BOUNDS for one packet as it came
-- off the wire (SquirrelWire.fromRecord's snapshot, numbers already finite: SquirrelWire.sane), any packet, judged or
-- not. Arithmetic, one registry look-up per id, and on a rail one pointAt (the pose agreement: poseAgreement).
function SquirrelMotor.fieldCheck(s: { [string]: any }, world: World): { Violation }
	local out: { Violation } = {}
	local function range(k: string, lo: number, hi: number)
		local v = s[k]
		if type(v) ~= "number" or v < lo - 1e-4 or v > hi + 1e-4 then
			add(out, "field", 1, `{k} {v} outside [{lo}, {hi}]`)
		end
	end
	for _, k in { "grounded", "committedAirborne", "focus", "routeWasMoving", "alive", "winded" } do
		if type(s[k]) ~= "boolean" then
			add(out, "field", 1, `{k} is no boolean`)
		end
	end
	if s.railDir ~= 1 and s.railDir ~= -1 then
		add(out, "field", 1, `railDir {s.railDir}`)
	end
	range("railT", 0, 1)
	-- (the fastest any way of moving goes with the chili rush on, a trampoline's push on top; the envelope holds each
	-- move to its own)
	local trampUp = (Trampoline.C.baseVy + Trampoline.C.maxCount * Trampoline.C.perBounceVy) * E.launchTol
	local hv = hypot2(tonumber(s.vx) or math.huge, tonumber(s.vz) or math.huge)
	local hMax = math.max(SquirrelMotor.groundCap(true) * E.speedTol, SquirrelMotor.launchCapXZ(true) * E.launchTol)
		+ Trampoline.C.push * E.launchTol
	if hv > hMax then
		add(out, "field", 1, `horizontal speed {hv}`)
	end
	range("vy", -P.terminalFall - P.gravity * E.gravityEps, math.max(P.leapUp * E.launchTol, trampUp))
	range("moveSpeed", 0, P.sprint * P.boostMult)
	range("boostRemaining", 0, E.boostMax)
	range("cooldown", 0, P.pounceCooldown)
	range("attack", 0, P.pounceAttack)
	range("attackWindow", 0, P.pounceWindow)
	range("cameraCommit", 0, math.max(P.cameraCommitLaunch, P.cameraCommitDrop, P.cameraCommitLand))
	range("routeFreeLook", 0, P.freeLookAfterTransfer)
	range("stamina", 0, 1)
	range("emergedFw", -1, 1)
	if s.emergedEnd ~= 0 and s.emergedEnd ~= 1 then
		add(out, "field", 1, `emergedEnd {s.emergedEnd}`)
	end
	-- (the client's own number in a drawn pose: the round-4 review moved the launch point 600 studs by a long normal)
	local nl = hypot2(tonumber(s.trunkNormalX) or 0, tonumber(s.trunkNormalZ) or 0)
	if math.abs(nl - 1) > E.normalTol then
		add(out, "railPose", 1, `trunk normal {nl} long`)
	end
	local reg = world.registry
	for _, k in { "pendingFork", "selectedJunction", "emergedFrom" } do
		local id = s[k]
		if id ~= -1 and (type(id) ~= "number" or reg:get(id) == nil) then
			add(out, "field", 1, `{k} {id}: no such route`)
		end
	end
	-- the rail it claims: -1, or a route of the world where its x, y, z are (every packet: the first, after a silence,
	-- at the gate; the round-5 review's CRITICAL)
	local rid = s.routeId
	local onRoute: Registry.Route? = nil
	if rid ~= -1 then
		onRoute = if type(rid) == "number" then reg:get(rid) else nil
		if onRoute == nil then
			add(out, "route", 1, `routeId {rid}: no such route`)
		end
	end
	if onRoute and type(s.railT) == "number" then
		local b: Bridge? = nil
		if s.bridgeActive == true then
			b = {
				fx = s.bfx,
				fy = s.bfy,
				fz = s.bfz,
				tx = s.btx,
				ty = s.bty,
				tz = s.btz,
				elapsed = s.bElapsed,
				duration = s.bDuration,
			}
		end
		poseAgreement(world, onRoute, s.railT, s.x, s.y, s.z, b, out)
	end
	if s.bridgeActive == true then
		if type(s.routeId) ~= "number" or s.routeId < 0 then
			add(out, "railPose", 1, "a transfer off any rail")
		end
		local gap = math.sqrt(
			((s.btx :: number) - (s.bfx :: number)) ^ 2
				+ ((s.bty :: number) - (s.bfy :: number)) ^ 2
				+ ((s.btz :: number) - (s.bfz :: number)) ^ 2
		)
		-- (a transfer starts where the body was: within a transfer's reach of its target; into an enclosed run at a mouth,
		-- whose reach the envelope's section 0 judges from the last packet)
		local r = if type(s.routeId) == "number" then reg:get(s.routeId) else nil
		if not (r and r.enclosure) and gap > C.enterMaxGap + E.posSlack then
			add(out, "railPose", 1, `a transfer {gap} st long`)
		end
		if math.abs((s.bDuration :: number) - Motion.bridgeDuration(gap)) > 1e-3 then
			add(out, "railPose", 1, `transfer easing {s.bDuration} s for {gap} st`)
		end
		-- (its easing in [0, bDuration] and the body on it: poseAgreement below)
	end
	-- the air trick: a move, its time within its length, and only in the air (the motor ends both on a landing or a rail)
	-- (a snapshot from before the trick has neither field: none, deserialize's reading; the wire always carries both)
	-- (owner D18: a roll plays on along the ground; a re-aim only in the air, in a flight with a move)
	local tk = s.trickKind
	local old = tk == nil and s.trickTime == nil
	local onRail = type(rid) == "number" and rid ~= -1
	if not old and tk ~= 0 and tk ~= 1 and tk ~= 2 then
		add(out, "field", 1, `trickKind {tk}`)
	elseif not old then
		range("trickTime", 0, if tk == 1 then P.trickRoll elseif tk == 2 then P.trickWiggle else 0)
		if tk ~= 0 and onRail then
			add(out, "field", 1, `trickKind {tk} on a rail`)
		elseif tk == 2 and s.grounded == true then
			add(out, "field", 1, "a wiggle on the ground")
		end
	end
	if s.aimYaw ~= nil or s.aimReach ~= nil then
		range("aimYaw", -P.trickAimYaw, P.trickAimYaw)
		range("aimReach", -1, 1)
		local still = s.grounded == true or onRail or tk == nil or tk == 0
		if still and ((s.aimYaw or 0) ~= 0 or (s.aimReach or 0) ~= 0) then
			add(out, "field", 1, "a re-aim off the air or with no move")
		end
	end
	local seq = s.clickSeq
	if seq ~= nil then
		if type(seq) ~= "number" or seq < 0 or seq > 255 or seq ~= math.floor(seq) then
			add(out, "field", 1, `clickSeq {seq}`)
		end
		range("clickAgo", 0, if seq == 0 then 0 else E.clickCopy)
	end
	return out
end

-- Returns the violations; whether a launch (leap, pounce, a step off a rail) was needed to explain the move; how long
-- before `next` the motor's pounce launched when the move holds one (a pounce-shaped launch the window dates; nil
-- otherwise); and what it judged of `next` (Judged).
-- (the re-aim the envelope in progress undid (0c): the most it moves the body across a second for each second of speed
-- had, and up or down, st/s; read by the grab search's arc. Set by envelope round envelopeCore, 0 otherwise)
local gapAim = { across = 0, up = 0 }

local function envelopeCore(
	prev: State,
	next: State,
	dt: number,
	world: World,
	boosted: boolean,
	lastGrab: number?,
	chained: boolean?
): ({ Violation }, boolean, number?, Judged)
	local out: { Violation } = {}
	local launchUsed = false
	local judged: Judged = { vy = next.vy, xz = math.huge, landed = false, longWall = false }
	if dt <= 0 then
		add(out, "clock", 1, `non-positive dt {dt}`)
		return out, false, nil, judged
	end
	local reg = world.registry
	local prevRoute = route(world, prev.routeId)
	local nextRoute = route(world, next.routeId)
	if next.routeId and not nextRoute then
		add(out, "route", 1, `unknown route {next.routeId}`)
		return out, false, nil, judged
	end
	local groundCap = SquirrelMotor.groundCap(boosted) * E.speedTol
	local launchXZ = SquirrelMotor.launchCapXZ(boosted) * E.launchTol

	-- 0. Enclosed runs: in and out only at a mouth, across the wall only where a mouth says.
	local prevEnc = if prevRoute then prevRoute.enclosure else nil
	local nextEnc = if nextRoute then nextRoute.enclosure else nil
	local authored = false
	if prevEnc or nextEnc then
		-- how far along a rail the body could have run between the packets
		local function along(r: Registry.Route): number
			local cap = SquirrelMotor.routeCap(r, boosted)
			return cap * E.railTol * dt + cap * P.substep + E.posSlack
		end
		-- one time budget for a move through a mouth: the time to reach it off the rails plus the time along the rail
		-- from it, each at its own cap, within the gap and one substep (never each part in full)
		local budget = dt + P.substep
		local vPrevXZ = hypot2(prev.vx, prev.vz)
		local offCap = math.max(groundCap, launchXZ, vPrevXZ * E.speedTol)
		local vertical = math.max(P.leapUp * E.launchTol, math.abs(prev.vy), math.abs(next.vy)) * dt
			+ 0.5 * P.gravity * dt * dt
			+ E.posSlack
		local function railTime(r: Registry.Route, fromT: number, toT: number, window: number): number
			local cap = SquirrelMotor.routeCap(r, boosted) * E.railTol
			return math.max(0, math.abs(toT - fromT) * r.length - window - E.posSlack) / cap
		end
		-- the least an honest path off the rails covers between a point and a mouth (level): to within `reach` of
		-- the mouth point, and out of its inside (half a body past the mouth plane at most)
		local function offDistance(
			mx: number,
			mz: number,
			ox: number?,
			oz: number?,
			x: number,
			z: number,
			reach: number
		)
			local level = hypot2(x - mx, z - mz)
			local need = math.max(0, level - reach)
			if ox and oz then
				local depth = -((x - mx) * ox + (z - mz) * oz)
				need = math.max(need, depth - Enclosure.C.behind)
			end
			return math.max(0, need - E.posSlack)
		end
		-- a hatch takes only E from a body standing on it: reached at the pace it was already moving or a sprint's (a
		-- leap's over a long gap, which can hide one and its landing), from within the mouth's rise of its height give
		-- or take the fall the gap allows (no launch inside the gap)
		local sprintCap = P.sprint * (if boosted then P.boostMult else 1) * E.speedTol
		local hatchCap = math.max(if dt > E.shortDt + E.dtEps then groundCap else sprintCap, vPrevXZ * E.speedTol)
		local hatchVertical = math.max(math.abs(prev.vy), math.abs(next.vy)) * dt
			+ 0.5 * P.gravity * dt * dt
			+ E.posSlack
		if nextRoute and nextEnc and not prevRoute then
			local ok = false
			for _, m in nextEnc.mouths do
				if m.opens == "link" then
					continue
				end
				local p = reg:pointAt(nextRoute, m.t)
				local ox, oz = Motion.outLevel(world, nextRoute, m)
				-- a hatch with a lid is reached anywhere on it (Motion.intoMouth)
				local offLid = Enclosure.offHatch(m, prev.x, prev.z)
				local need = if offLid
					then math.max(0, offLid - Enclosure.C.hatchMargin - E.posSlack)
					else offDistance(p.x, p.z, ox, oz, prev.x, prev.z, m.reach)
				local tOff = need / (if m.hatch then hatchCap else offCap)
				local tRail = railTime(nextRoute, m.t, next.railT, 0)
				local rise = m.rise + (if m.hatch then hatchVertical else vertical)
				if tOff + tRail <= budget and math.abs(p.y - prev.y) <= rise then
					ok = true
					break
				end
			end
			if not ok then
				add(out, "enclosure", 1, `got onto enclosed route {nextRoute.id} away from its mouths`)
			end
		elseif prevRoute and prevEnc and not nextRoute then
			local ok = false
			for _, m in prevEnc.mouths do
				local tRail = railTime(prevRoute, prev.railT, m.t, m.window)
				local p = reg:pointAt(prevRoute, m.t)
				local lp = Motion.launchPoint(world, prevRoute, m)
				local ox, oz = Motion.outLevel(world, prevRoute, m)
				-- out at the mouth's end (a ground mouth's step out) or its launch point; outside it after a short gap
				local from = math.min(hypot2(next.x - p.x, next.z - p.z), hypot2(next.x - lp.x, next.z - lp.z))
				local depth = if ox and oz then -((next.x - p.x) * ox + (next.z - p.z) * oz) else 0
				local need = math.max(0, from - E.posSlack, depth - Enclosure.C.behind - E.posSlack)
				local outside = dt > E.shortDt + E.dtEps or depth <= Enclosure.C.behind + E.posSlack
				local vy = math.min(math.abs(next.y - p.y), math.abs(next.y - lp.y))
				if outside and tRail + need / offCap <= budget and vy <= m.rise + m.depth + vertical then
					ok = true
					break
				end
			end
			if not ok then
				add(out, "enclosure", 1, `left enclosed route {prevRoute.id} away from its mouths (t {prev.railT})`)
			end
		elseif prevRoute and nextRoute and prevRoute.id ~= nextRoute.id then
			-- an authored connection (an end link, a fork, a mouth's link): a declared junction
			authored = Enclosure.linked(prevRoute, nextRoute)
			local allowed =
				Enclosure.allows(prevRoute, prev.railT, nextRoute, next.railT, along(prevRoute), along(nextRoute))
			if not allowed and dt > E.shortDt + E.dtEps then
				-- a late packet can hide two authored hops (a bough, the knothole's shaft, the floor below): through a
				-- route either record names, connected to both (the transfer gap check below still bounds the distance)
				local mids = Enclosure.neighbours(prevRoute)
				for _, id in Enclosure.neighbours(nextRoute) do
					table.insert(mids, id)
				end
				for _, id in mids do
					local mid = reg:get(id)
					if
						mid
						and mid.id ~= prevRoute.id
						and mid.id ~= nextRoute.id
						and Enclosure.allows(prevRoute, prev.railT, mid, 0.5, along(prevRoute), mid.length)
						and Enclosure.allows(mid, 0.5, nextRoute, next.railT, mid.length, along(nextRoute))
					then
						allowed, authored = true, true
						break
					end
				end
			end
			if not allowed then
				add(out, "enclosure", 1, `crossed the wall from route {prevRoute.id} to route {nextRoute.id}`)
			end
		end
	end
	local launchUp = P.leapUp * E.launchTol
	local pounceUp = (P.pounceUpBase + P.pounceUpPitch * math.sin(P.pouncePitchMax)) * E.launchTol
	local pounceUpMin = (P.pounceUpBase + P.pounceUpPitch * math.sin(P.pouncePitchMin)) / E.launchTol
	local pounceXZ = P.pounceSpeedFast * (if boosted then P.pounceBoostMult else 1) * E.launchTol
	-- the slowest a pounce lunges across (a slow one at the steepest pitch, or a winded one at a walk), with tolerance
	local pounceMinXZ = math.min(P.walk, P.pounceSpeedSlow * math.cos(P.pouncePitchMax)) / E.launchTol
	local gEps = P.gravity * E.gravityEps
	-- studs: how far a grab's point may lie from the true nearest point of a rail (half the index's sample spacing:
	-- Curve.sampleSteps, three a unit; Motion.nearestRoute takes the nearest sample)
	local samplePad = Units.st(1 / 6)
	-- climbThenLaunch(cap, n): the most a body rises in the gap climbing a rail at `cap` (studs/s up) for part of it and
	-- for the rest in `n` launches one after the other (a leap off the rail and a grab back, n times): the time shared,
	-- never each in full (the greedy adversary of round 5 climbed a trunk at the run's pace and a leap's on top)
	local function climbThenLaunch(cap: number, n: number): number
		local t2 = math.clamp(n * (launchUp - cap) / P.gravity, 0, dt)
		return cap * (dt - t2) + launchUp * t2 - P.gravity * t2 * t2 / (2 * n)
	end

	-- 0b. Vertical speed off the rails, whatever the move: on the ground there is none (the motor's is exactly 0), and
	-- no fall is faster than the motor's terminal speed. Every bound below that reads a vertical speed reads a judged one.
	if not nextRoute then
		if next.grounded and math.abs(next.vy) > E.groundVy then
			add(out, "gravity", 1, `vertical speed {next.vy} on the ground`)
		end
		if next.vy < -P.terminalFall - gEps then
			add(out, "gravity", 1, `falling at {-next.vy} st/s (terminal {P.terminalFall})`)
		end
	end

	-- pounceAgo(fromRoute) -> seconds?: the move holds a pounce launched that long before `next` (a pounce-shaped launch:
	-- the motor's window rose to what it is a moment after a pounce inside the gap, and the body flies as a pounce
	-- launched then would: its vertical speed back then within a pounce's, its speed across a lunge's). The window falls
	-- by each substep from the launch, as the vertical speed does by gravity, so the launch's own vertical speed is the
	-- one now plus gravity times the window's fall. A hop, a leap or a fall claiming a window is no pounce. `fromRoute`:
	-- the rail it left (an enclosed run's mouth with a `hop` makes a click a short hop: any lift up to its own)
	local function pounceAgo(fromRoute: Registry.Route?): number?
		if nextRoute or next.grounded or next.attackWindow <= prev.attackWindow + 1e-3 then
			return nil
		end
		local ago = P.pounceWindow - next.attackWindow
		if ago < -1e-3 or ago > dt + 1e-3 then
			return nil
		end
		ago = math.clamp(ago, 0, dt)
		local u = next.vy + P.gravity * ago
		local vxz = hypot2(next.vx, next.vz)
		local enc = if fromRoute then fromRoute.enclosure else nil
		if enc then
			local hopUp = 0
			for _, m in enc.mouths do
				hopUp = math.max(hopUp, m.hopUp or 0)
			end
			return if u >= -gEps
					and u <= math.max(pounceUp, hopUp * E.launchTol) + gEps
					and vxz <= launchXZ
				then ago
				else nil
		end
		if u < pounceUpMin - gEps or u > pounceUp + gEps or vxz > pounceXZ then
			return nil
		end
		if vxz < pounceMinXZ then
			-- (slower than any lunge: only one that met a wall, which takes the speed off it substep by substep, the body
			-- sliding along it. The heading is the client's word (the round-3 review: any wall within reach of it would
			-- do), so the server's own two places judge it: a body that moved went toward where it faces, and the wall
			-- is within E.wallAhead ahead of it along that heading or along the move; one that hardly moved touches the
			-- wall (E.wallTouch along its heading): no more than an honest point-blank pounce)
			local crosses = world.crosses
			if crosses == nil then
				return nil
			end
			local hx, hz = math.sin(next.yaw), math.cos(next.yaw)
			local mx, mz = next.x - prev.x, next.z - prev.z
			local m = hypot2(mx, mz)
			-- (the body is a box, not a point: a wall's corner it presses can lie off the centre line, so the lines either
			-- side at its half-width count too; found by the air trick's honest runs, 2026-11-20: a winded pounce into a
			-- house's corner, the centre line passing 0.2 st clear of it)
			local half = P.fitHalves[1]
			local function wallAt(dx: number, dz: number, r: number): boolean
				for _, side in { 0, half, -half } do
					local ox, oz = next.x - dz * side, next.z + dx * side
					if crosses(ox, oz, ox + dx * r, oz + dz * r, next.y, next.y, 0) then
						return true
					end
				end
				return false
			end
			local met
			if m < E.wallMoved then
				met = wallAt(hx, hz, E.wallTouch)
			else
				met = wallAt(mx / m, mz / m, E.wallAhead) or (mx * hx + mz * hz >= 0 and wallAt(hx, hz, E.wallAhead))
			end
			if not met then
				return nil
			end
		end
		return ago
	end
	local pounce: number? = nil

	-- 1. Position agreement with the claimed rail (poseAgreement: fieldCheck asks it of every packet, judged or not), and
	-- a transfer's start and easing against the last packet.
	if nextRoute then
		poseAgreement(world, nextRoute, next.railT, next.x, next.y, next.z, next.bridge, out)
		local b = next.bridge
		if b then
			-- (the transfer's start and its easing are the client's numbers: the start is where the body was when it began,
			-- inside the gap and within its reach of the last packet, and the easing runs on by the gap's time, so a body
			-- kept at a transfer's start floats beside a rail no longer than a transfer lasts)
			local pb = prev.bridge
			local same = pb ~= nil
				and math.abs(pb.fx - b.fx) + math.abs(pb.fy - b.fy) + math.abs(pb.fz - b.fz) < 1e-3
				and math.abs(pb.tx - b.tx) + math.abs(pb.ty - b.ty) + math.abs(pb.tz - b.tz) < 1e-3
			if same then
				local pe = (pb :: Bridge).elapsed
				if b.elapsed < pe - 1e-6 or b.elapsed > pe + dt + P.substep then
					add(out, "railPose", 1, `transfer easing {pe} -> {b.elapsed} in {dt} s`)
				end
			else
				if b.elapsed > dt + P.substep then
					add(out, "railPose", 1, `a new transfer {b.elapsed} s along after a {dt} s gap`)
				end
				-- (a transfer begins on a change of rail; onto the rail it was on only back in through an enclosed run's
				-- mouth, which a long gap can hide: else a new one every packet kept the body a transfer's reach off it)
				local enclosed = nextRoute.enclosure ~= nil
				if prevRoute and prevRoute.id == nextRoute.id and (dt <= E.shortDt + E.dtEps or not enclosed) then
					add(out, "railPose", 1, `a new transfer onto the rail it was on, route {nextRoute.id}`)
				end
				local vPrev = math.sqrt(prev.vx ^ 2 + prev.vy ^ 2 + prev.vz ^ 2)
				local pace = math.max(
					groundCap,
					launchXZ,
					vPrev,
					if prevRoute then SquirrelMotor.routeCap(prevRoute, boosted) * E.railTol else 0
				)
				local reach = pace * (dt + P.substep) + E.posSlack
				local from = math.sqrt((b.fx - prev.x) ^ 2 + (b.fy - prev.y) ^ 2 + (b.fz - prev.z) ^ 2)
				if prevRoute and from > reach then
					-- (a leap starts at the drawn pose)
					local w = visualPosition(prev, world)
					from = math.min(from, math.sqrt((b.fx - w.x) ^ 2 + (b.fy - w.y) ^ 2 + (b.fz - w.z) ^ 2))
				end
				if from > reach then
					add(out, "railPose", 1, `a transfer from {from} st away from the last packet in {dt} s`)
				end
			end
		end
		if next.railT < -1e-9 or next.railT > 1 + 1e-9 then
			add(out, "railPose", 1, "railT outside [0, 1]")
		end
	end

	-- Could the body have visited a rail between the two packets? Long gaps (loss, reordering) hide
	-- attach/detach pairs, so some checks relax when a route lies within the grab radius of the path.
	local shortGap = dt <= E.shortDt + E.dtEps
	-- (a rail within a grab and the gap's run across of the straight path, at its ends and points along it no further
	-- apart than that reach: a fall is long, not wide; the round-4 review: a reach sized by the 3-D speed made a falling
	-- body 67 st/s sideways)
	local function railWithinReach(): boolean
		local reach = C.airGrab + math.max(groundCap, hypot2(prev.vx, prev.vz)) * dt + E.posSlack
		local len = math.sqrt((next.x - prev.x) ^ 2 + (next.y - prev.y) ^ 2 + (next.z - prev.z) ^ 2)
		local n = math.clamp(math.ceil(len / reach), 1, 6)
		for i = 0, n do
			local a = i / n
			local x, y, z =
				prev.x + (next.x - prev.x) * a, prev.y + (next.y - prev.y) * a, prev.z + (next.z - prev.z) * a
			if world.index:nearest(x, y, z, reach) ~= nil then
				return true
			end
		end
		return false
	end

	-- wallTest(fx, fy, fz, rise, straight): the straight move from (fx, fy, fz) to `next` must not cross a wall collider,
	-- over the higher end by `rise` at most (a leap over a fence is no wall), and only as high as `next` is open above
	-- (ValidatorWorld.crosses: no leap into a house under its roof). A line longer than the short test judges
	-- (the world's maxChord) is judged chord by chord (crossesLong): a crossing is a wall when the move was `straight`
	-- (a flight inside a short gap rounds no corner) or no way round a corner is clear (world.around), else weighed by
	-- the validator as a gap's (judged.longWall: a corner rounded unseen)
	local function wallTest(fx: number, fy: number, fz: number, rise: number, straight: boolean)
		local crosses = world.crosses
		if crosses == nil then
			return
		end
		local lo, hi = math.min(fy, next.y), math.max(fy, next.y)
		if crosses(fx, fz, next.x, next.z, lo, hi, rise, next.y) then
			add(out, "wall", 1, "move crosses a wall collider")
			return
		end
		local chord, long = world.maxChord, world.crossesLong
		if
			chord
			and long
			and hypot2(next.x - fx, next.z - fz) > chord
			and long(fx, fz, next.x, next.z, lo, hi, rise, next.y)
		then
			-- (validator round 9, the round-8 review's MEDIUM: a long line through a wall was always weighed a third and
			-- kept; now only when a corner rounded unseen explains it, ValidatorWorld.around: else a whole flag)
			local round = world.around
			-- (no way round longer than the body could have run in the gap: a leap goes straight; validator round 10)
			local path = SquirrelMotor.runCap(boosted) * dt + 1 + 2 * E.posSlack
			if straight or (round ~= nil and not round(fx, fz, next.x, next.z, lo, hi, rise, next.y, path)) then
				add(out, "wall", 1, "move crosses a wall collider")
			else
				judged.longWall = true
				judged.cornered = round ~= nil and hypot2(next.x - fx, next.z - fz) <= (world.aroundMax or 0)
			end
		end
	end

	-- 2. Rail-to-rail: speed along the same route, or a legal transfer.
	if prevRoute and nextRoute then
		local railCap = SquirrelMotor.routeCap(prevRoute, boosted)
		if prevRoute.id == nextRoute.id then
			local allowed = railCap * E.railTol * dt + railCap * P.substep
			local moved = math.abs(next.railT - prev.railT) * prevRoute.length
			if moved > allowed and not shortGap then
				-- a long gap can hide a leap or drop off this route and a grab back onto it further along: the faster of
				-- running on it and a leap along it (a grab lands at the rail's nearest point, so it adds nothing along
				-- the rail: the round-4 review ran 3 to 7 times a wire's pace with the grab radius added every packet),
				-- judged by the straight chord between the two rail points (a leap cuts a bend), from the drawn pose a
				-- leap starts at: across no faster than that, up no more than the run's climb and a launch rises in the
				-- gap, down no more than the run and a fall from rest
				local a, b = reg:pointAt(prevRoute, prev.railT), reg:pointAt(prevRoute, next.railT)
				local w = visualPosition(prev, world)
				local offset = hypot2(w.x - a.x, w.z - a.z)
				local across = hypot2(b.x - a.x, b.z - a.z)
				local runUp = railCap * E.railTol * dt
				local rise = b.y - a.y
				if
					across
						<= math.max(railCap * E.railTol, launchXZ) * dt + railCap * P.substep + offset + E.posSlack
					and rise <= climbThenLaunch(railCap * E.railTol, 1) + E.posSlack
					and -rise <= runUp + 0.5 * P.gravity * dt * dt + E.posSlack
				then
					allowed = moved
				end
			end
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
			-- (a gap of half the longest judged, a loss burst, can hide a leap off that stretch onto the new rail, as a leap
			-- along one rail above: across no further than a launch carries in the gap, up no more than the run's climb and
			-- a launch rises; validator round 10: an honest transfer through a loss burst of half a second was a whole
			-- flag. A packet or two lost, never: the transfer limits stand there. Validator round 15, the round-14 review's
			-- LOW a: the run to a point and the leap from it share the gap, the leap only the time the run leaves)
			local long = dt >= E.maxDt / 2 - E.dtEps
			local riseCap = climbThenLaunch(railCap * E.railTol, 1) + E.posSlack
			local gap = math.huge
			local leapt = false
			for k = -4, 4 do
				local tt = math.clamp(prev.railT + reachT * k / 4, 0, 1)
				local q = reg:pointAt(prevRoute, tt)
				local d = math.sqrt((dest.x - q.x) ^ 2 + (dest.y - q.y) ^ 2 + (dest.z - q.z) ^ 2)
				local byLeap = long and dest.y - q.y <= riseCap
				if byLeap then
					d = math.max(0, d - launchXZ * dt * (1 - math.abs(k) / 4))
				end
				if d < gap then
					gap, leapt = d, byLeap
				end
			end
			local travel = E.posSlack + railCap * E.railTol * dt / 4 -- between the sampled points
			-- (a hidden intermediate route's reach, below: the leap's whole carry, as before)
			local hopTravel = travel + (if leapt then launchXZ * dt else 0)
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
							local hit = world.index:nearestOnRoute(mid, q.x, q.y, q.z, C.explicitGap + hopTravel)
							if hit and (best == nil or hit.d < (best :: SpatialIndex.Hit).d) then
								best = hit
							end
						end
						if best then
							local b = best :: SpatialIndex.Hit
							local capB = SquirrelMotor.routeCap(midRoute, boosted) * E.railTol * dt
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
				local nextCap = SquirrelMotor.routeCap(nextRoute, boosted)
				if next.railT > E.forkEnterMaxT + nextCap * E.railTol * dt / nextRoute.length then
					add(out, "transfer", 1, `{relation} hop landed at t {next.railT}`)
				end
			elseif relation == nil and not twoHop and not authored and gap > C.explicitGap + travel then
				add(out, "transfer", 1, `unrelated routes {prevRoute.id} -> {nextRoute.id}, gap {gap} st`)
			end
		end
	end

	-- 3. Off rail onto a rail: the grab radius (3.4 u) plus what the body could have moved first.
	if not prevRoute and nextRoute then
		local dest = reg:pointAt(nextRoute, next.railT)
		local gap = math.sqrt((dest.x - prev.x) ^ 2 + (dest.y - prev.y) ^ 2 + (dest.z - prev.z) ^ 2)
		-- (where the body could be when it grabbed: across at the fastest it goes, up what a launch or its own speed rises,
		-- down what it falls in the gap; the round-4 review: a reach sized by the 3-D speed let a falling body grab 67
		-- st/s sideways)
		-- (in the air at the speed it has, or a pounce's; on the ground, or a floor or rail met in a long gap, a sprint's or
		-- a leap's)
		-- (up: a launch only from something to push off: the ground, or in a long gap a floor it could have come down on
		-- or another rail it could have touched; else in the air only the motor's pounce, or the speed it already has.
		-- The round-5 review: a full launch from anywhere in the air. A touch of this same rail in the gap is no push: its
		-- grab is the one judged here. Across likewise: a sprint's or a leap's from a push, else the speed it has or a
		-- pounce's)
		local vPrevXZ = hypot2(prev.vx, prev.vz)
		local fast = math.max(groundCap, launchXZ, vPrevXZ) * dt + E.posSlack
		local pushOff = prev.grounded
		if not pushOff and not shortGap then
			local fallBy = math.max(0, -prev.vy) * dt + 0.5 * P.gravity * dt * dt + E.posSlack
			local landable = world.landable
			pushOff = (landable ~= nil and landable(prev.x, prev.y, prev.z, fallBy))
				or world.index:nearest(prev.x, prev.y, prev.z, C.airGrab + fast, nextRoute.id) ~= nil
		end
		local travel = if pushOff then fast else math.max(pounceXZ, vPrevXZ) * dt + E.posSlack
		local up = math.max(if pushOff then launchUp else pounceUp, prev.vy)
		local tRise = math.min(dt, up / P.gravity)
		local rise = up * tRise - 0.5 * P.gravity * tRise * tRise + E.posSlack
		local fall = math.max(0, -prev.vy) * dt + 0.5 * P.gravity * dt * dt + E.posSlack
		local dy = dest.y - prev.y
		local outside = math.sqrt(
			math.max(0, hypot2(dest.x - prev.x, dest.z - prev.z) - travel) ^ 2 + math.max(0, dy - rise, -dy - fall) ^ 2
		)
		-- along the rail (the round-5 review's HIGH: a grab's reach counted along the rail too, so touching a trunk or a
		-- wire every other packet ran it at 2 to 6 times its pace): a grab lands at the rail's NEAREST point to the body
		-- (Motion.nearestRoute: straight across a trunk at the body's own height, square to a wire), so along the rail's
		-- tangent at the grab point it is no further from `prev` than the body could get in the gap (the reachable region's
		-- span along the tangent: across at `travel`, up or down by `rise` or `fall`), or than a run along it after the
		-- grab. The grab point is the nearest of the index's samples (samplePad), and at a rail's end the nearest point is
		-- the end itself (any direction): no along test there
		local alongOk = true
		local alongBy = ""
		local tan = reg:tangentAt(nextRoute, math.clamp(next.railT, 0, 1))
		local tl = math.sqrt(tan.x * tan.x + tan.y * tan.y + tan.z * tan.z)
		local endPad = (2 * samplePad + E.posSlack) / math.max(nextRoute.length, 1e-6)
		if tl > 1e-6 and next.railT > endPad and next.railT < 1 - endPad then
			local tx, ty, tz = tan.x / tl, tan.y / tl, tan.z / tl
			local along = (dest.x - prev.x) * tx + (dest.y - prev.y) * ty + (dest.z - prev.z) * tz
			if along < 0 then
				along, tx, ty, tz = -along, -tx, -ty, -tz
			end
			local span = travel * hypot2(tx, tz) + (if ty > 0 then rise * ty else -fall * ty)
			local cap = SquirrelMotor.routeCap(nextRoute, boosted)
			local run = cap * E.railTol * dt + cap * P.substep
			alongOk = along <= math.max(span, run) + samplePad
			if not alongOk then
				alongBy = string.format(
					"%.2f st along (reach %.2f) in %.3f s, t %.3f of %s %d, from %s",
					along,
					math.max(span, run) + samplePad,
					dt,
					next.railT,
					nextRoute.kind,
					nextRoute.id,
					if prev.grounded then "the ground" else string.format("the air (vy %.1f)", prev.vy)
				)
			end
		end
		if not alongOk and (prev.grounded or pushOff) and nextRoute.kind == "trunk" then
			-- (from the ground, E or a walk into it takes a trunk at its foot, t 0 (Motion.groundTrunkCandidate): the foot
			-- within its reach of where the body could stand, a step up or down, and the run up from it)
			local foot = reg:foot(nextRoute)
			local cap = SquirrelMotor.routeCap(nextRoute, boosted)
			local run = cap * E.railTol * dt + cap * P.substep
			alongOk = next.railT * nextRoute.length <= run + samplePad
				and hypot2(foot.x - prev.x, foot.z - prev.z) <= C.groundReachE + travel
				and math.abs(foot.y - prev.y) <= C.maxRise + rise + fall
		end
		if outside > C.airGrab or not alongOk then
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
							local capB = SquirrelMotor.routeCap(midRoute, boosted) * E.railTol * dt
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
				add(
					out,
					"grab",
					1,
					if alongOk
						then `grabbed a rail {gap} st away (> 3.4 u + travel)`
						else `grabbed a rail further along it than the body could reach: {alongBy}`
				)
			end
		end
	end

	-- 4. Off the rail (leap, drop, pounce, a step out of a mouth): from a launch point, judged across and up apart (the
	-- round-4 review: a sphere round the drawn pose let a body leave a trunk's top 43 studs straight up, or cross 40
	-- studs level toward another tree). The launch points: the drawn pose at each point of the stretch of rail the body
	-- could run in the gap (an open rail), or the drawn pose and each mouth's launch point (an enclosed run: section 0
	-- holds it to its mouths). Across: no further from the nearest than a launch flies in the gap. Up: over the highest no
	-- more than a launch ending at the speed `next` shows rises ((u^2 - v^2) / 2g, u no more than gravity takes in the
	-- gap above v, never above the launch); down: under the lowest no more than a fall from rest in the gap (every way off
	-- a rail leaves at 0 or more). A long gap may hide a visit to a rail: only one near `next`, high enough that a launch
	-- off it explains `next`, and reachable from the launch points by a launch and a grab (railVisit; the grab's reach
	-- only onto another rail: on the same one it lands at the nearest point)
	-- (a move off the rail the launch points (and in a long gap the rail-visit geometry) do not explain: "teleport", unless
	-- in a gap of up to grabSimDt the motor's own leap off the rail and its grabs inside the gap explain it: section 5's
	-- grab search, seeded with the leap)
	local leftOver: { string } = {}
	if prevRoute and not nextRoute then
		launchUsed = true
		judged.railLaunch = true
		local railCap = SquirrelMotor.routeCap(prevRoute, boosted)
		local prevSpec = prevRoute.enclosure
		local points: { Vec3 } = {}
		-- (the time the body took to get to each launch point: running along an open rail's stretch, the rest of the gap
		-- is the launch's. The round-5 review's wire touches ran the stretch and flew the whole gap besides)
		local times: { number } = {}
		if prevSpec then
			table.insert(points, visualPosition(prev, world))
			table.insert(times, 0)
			for _, m in prevSpec.mouths do
				table.insert(points, Motion.launchPoint(world, prevRoute, m))
				table.insert(times, 0)
			end
		else
			local reachT = railCap * E.railTol * dt / math.max(prevRoute.length, 1e-6)
			for k = -4, 4 do
				local tt = math.clamp(prev.railT + reachT * k / 4, 0, 1)
				table.insert(times, dt * math.abs(k) / 4)
				table.insert(
					points,
					Motion.visualPose(
						world,
						prevRoute,
						tt,
						reg:pointAt(prevRoute, tt),
						prev.trunkNormalX,
						prev.trunkNormalZ
					)
				)
			end
		end
		local nearXZ, near = math.huge, points[1]
		local topY, lowY = -math.huge, math.huge
		for _, p in points do
			local d = hypot2(next.x - p.x, next.z - p.z)
			if d < nearXZ then
				nearXZ, near = d, p
			end
			topY, lowY = math.max(topY, p.y), math.min(lowY, p.y)
		end
		local hopUp = launchUp
		for _, m in (if prevSpec then prevSpec.mouths else {}) :: { Enclosure.Mouth } do
			hopUp = math.max(hopUp, (m.hopUp or 0) * E.launchTol)
		end
		-- (a launch's rise in the gap: up at the launch speed, no higher than its apex)
		local tUp = math.min(dt, hopUp / P.gravity)
		local riseInDt = hopUp * tUp - 0.5 * P.gravity * tUp * tUp
		local v = next.vy
		local u = math.min(hopUp, v + P.gravity * dt + gEps)
		local riseNext = math.max(0, (u * u - v * v) / (2 * P.gravity))
		local step = if next.grounded then Units.st(1.4) else 0 -- (landing snaps to the ground, a step either way)
		-- launched(tau): the rise of a launch that lasted `tau`, the end of the gap: it ends at `next`'s vertical speed
		-- give or take gEps, began no faster than hopUp, and rose tau * (its end speed + g tau / 2). Never longer than the
		-- gap (the round-5 review's touches took gEps as more time: a launch 60 % longer than a short gap)
		local function launched(tau: number): number
			local w = math.min(v + gEps, hopUp - P.gravity * tau)
			return math.max(0, tau * (w + 0.5 * P.gravity * tau))
		end
		local allowXZ = launchXZ * dt + Units.st(0.5) + E.posSlack
		local allowDown = 0.5 * P.gravity * dt * dt + gEps * dt + step + E.posSlack
		-- (across from a launch point: what the launch flies in the time left after running there; the run is no faster
		-- than the flight, so a point between two is covered by the nearer one)
		local fly = math.max(launchXZ, railCap * E.railTol)
		local function flightLeft(k: number): number
			return fly * (dt - times[k]) + Units.st(0.5) + E.posSlack
		end
		local overXZ = true
		for k, p in points do
			if hypot2(next.x - p.x, next.z - p.z) <= flightLeft(k) then
				overXZ = false
				break
			end
		end
		local overUp
		if prevSpec then
			-- (out of a mouth: over its launch point)
			overUp = next.y - topY > riseNext + step + E.posSlack
		else
			-- (off an open rail: up the rail for part of the gap and the launch for the rest, the time shared: the
			-- rise is convex in the launch's time, so the most is all climb, or the launch from when it could reach
			-- its speed cap at `next`'s speed, the climb before it)
			local ref = visualPosition(prev, world).y
			local capT = railCap * E.railTol
			local function climb(time: number): number
				return math.min(topY - ref, capT * time)
			end
			local most = 0
			local tStar = math.clamp((hopUp - v - gEps) / P.gravity, 0, dt)
			for _, tau in { 0, dt, tStar, dt * 0.25, dt * 0.5, dt * 0.75 } do
				most = math.max(most, climb(dt - tau) + launched(tau))
			end
			overUp = next.y - ref > most + step + E.posSlack
		end
		-- a ledge the launch came down on and launched from again (Space held: the client's ground probe lifts the feet onto
		-- a surface a step over them, so a rafter's beam over a light rail is a floor a leap reaches in a frame): the floor
		-- a ray finds under `next` (in any gap; it explains the rise, not the distance). The two launches share the gap
		-- (validator round 6, the round-5 review's LOW: each took the whole of it): landed at t1, the floor is no higher
		-- than the climb and the first launch reach by t1 and a step (fTop), no lower than the second launch, ending at
		-- `next`'s speed in the time left, explains `next` (fLow). Both rise with t1, and their gap is concave in it, so the
		-- floors that do lie between fLow at the first t1 where the two meet and fTop at the last: arithmetic over t1,
		-- then the one ray
		local landable = world.landable
		if overUp and not overXZ and landable then
			local base = if prevSpec then topY else visualPosition(prev, world).y
			local capT = if prevSpec then 0 else railCap * E.railTol
			local head = topY - base
			local function reachBy(t1: number): number
				local best = 0
				local tStar = math.clamp((hopUp - capT) / P.gravity, 0, t1)
				for _, tau in { 0, t1, tStar, math.clamp(t1 - head / math.max(capT, 1e-6), 0, t1) } do
					local tu = math.min(tau, hopUp / P.gravity)
					best = math.max(best, math.min(head, capT * (t1 - tau)) + hopUp * tu - 0.5 * P.gravity * tu * tu)
				end
				return base + best + Units.st(1.4) + E.floorSlack
			end
			local lowest, highest = math.huge, -math.huge
			local samples = 16
			for i = 0, samples do
				local t1 = dt * i / samples
				local fTop = reachBy(t1)
				local fLow = next.y - launched(dt - t1) - E.floorSlack - E.posSlack
				if fLow <= fTop then
					lowest, highest = math.min(lowest, fLow), math.max(highest, fTop)
				end
			end
			if lowest <= highest and landable(next.x, highest, next.z, highest - lowest) then
				overUp = false
			end
		end
		if (overXZ or overUp) and not shortGap then
			-- railVisit: in a long gap, a rail sample S near `next` the body could have grabbed after a launch from a
			-- launch point and left again to be where `next` is (the grab's reach only onto another rail: on the same one
			-- it lands at the nearest point), reached by a launch and off it by another, the gap's time shared between the
			-- climb and the two
			-- (up: the climb, a launch, the grab and a second launch that ends at `next`'s vertical speed, the time shared)
			local capT = railCap * E.railTol
			local visitUp = 0
			for _, tau in { 0, dt * 0.25, dt * 0.5, dt * 0.75, dt } do
				local rest = dt - tau
				local t1 = math.clamp((launchUp - capT) / P.gravity, 0, rest)
				visitUp =
					math.max(visitUp, capT * (rest - t1) + launchUp * t1 - 0.5 * P.gravity * t1 * t1 + launched(tau))
			end
			local reach = C.airGrab + launchXZ * dt + E.posSlack
			local vis = visualPosition(prev, world)
			local index = world.index :: any
			local found = false
			index:forEachNear(
				next.x,
				next.y,
				next.z,
				math.ceil(reach / (index.cellSize or 20)),
				function(id: number, sampleT: number, sx: number, sy: number, sz: number): boolean?
					local toNext = hypot2(sx - next.x, sz - next.z)
					if toNext > reach or sy < next.y - riseNext - C.visualBranchLift - E.posSlack then
						return nil
					end
					local same = id == prevRoute.id
					local grab = if same then 0 else C.airGrab
					local r = reg:get(id)
					if r == nil or sy > topY + riseInDt + grab + E.posSlack then
						return nil
					end
					-- (the way off it leaves from its drawn pose: no further off the sample than its offset, no higher
					-- than its lift; the round-5 review counted a second grab there)
					local w = Motion.visualPose(world, r, sampleT, Curve.vec3(sx, sy, sz), 1, 0)
					local drawn = math.sqrt((w.x - sx) ^ 2 + (w.y - sy) ^ 2 + (w.z - sz) ^ 2)
					if next.y - vis.y > visitUp + grab + math.max(0, w.y - sy) + E.posSlack then
						return nil
					end
					-- (onto another rail a grab's reach; back onto the one it left, at the nearest point to the body: no
					-- way along it but the flight's and the run's, so only the legs along its tangent count)
					local tx, tz = 0, 0
					if same then
						local tan = reg:tangentAt(r, sampleT)
						local tl = math.sqrt(tan.x * tan.x + tan.y * tan.y + tan.z * tan.z)
						if tl > 1e-6 then
							tx, tz = tan.x / tl, tan.z / tl
						end
					end
					for k, p in points do
						local first = if same
							then math.abs((sx - p.x) * tx + (sz - p.z) * tz)
							else hypot2(sx - p.x, sz - p.z)
						if first + toNext <= flightLeft(k) + grab + drawn + samplePad then
							found = true
							return true
						end
					end
					return nil
				end
			)
			if found then
				overXZ, overUp = false, false
			end
		end
		if overXZ then
			table.insert(leftOver, `left the rail {nearXZ} st across from the launch point (allowed {allowXZ})`)
		end
		if overUp then
			table.insert(leftOver, `left the rail {next.y - topY} st over its stretch in {dt} s`)
		end
		if lowY - next.y > allowDown then
			add(out, "teleport", 1, `left the rail {lowY - next.y} st down in {dt} s (allowed {allowDown})`)
		end
		if hypot2(next.vx, next.vz) > launchXZ then
			add(out, "launch", 1, `horizontal launch {hypot2(next.vx, next.vz)} st/s`)
		end
		if next.vy > launchUp then
			add(out, "launch", 1, `vertical launch {next.vy} st/s`)
		end
		-- every way off a rail (a leap, a pounce, a drop, a step out of a mouth) leaves it at a vertical speed of 0 or
		-- more: by the end of the gap gravity has taken at most the gap's worth of it (a fall claimed off a rail is none)
		if not next.grounded and next.vy < -P.gravity * dt - gEps then
			add(out, "launch", 1, `left the rail falling at {-next.vy} st/s in {dt} s`)
		end
		-- walls (the round-3 review: a step off a trunk landed beyond a garden wall): the straight line from the launch
		-- point nearest to where it came down, as off the rails (section 5), over the higher end by what a launch rises in
		-- the gap (the round-4 review: a whole leap's apex at any gap stepped through the wall of a house 6 studs up a
		-- trunk beside it), and none where the far end is under a roof (ValidatorWorld: open sky). A body still in the air
		-- within two short gaps made one flight from the launch point: a straight line, a crossing a wall whatever its
		-- length (no time to come down, round a corner and launch again)
		wallTest(near.x, near.y, near.z, riseInDt, shortGap or (not next.grounded and dt <= 2 * E.shortDt + E.dtEps))
		pounce = pounceAgo(prevRoute)
		if pounce ~= nil then
			-- (the motor's pounce off a rail is free, but its flight is the pounce's, no rail leap's: validator round 15,
			-- the round-14 review's LOW d)
			judged.railLaunch = nil
		end
		judged.vy = if next.grounded then 0 else math.clamp(next.vy, -P.gravity * dt - gEps, launchUp)
		judged.xz = launchXZ
	end

	-- 5. Off rail to off rail: ground and air motion. (Its grab search also judges a gap off a rail: section 4's
	-- leftOver)
	local arcVy: number? = nil
	if not nextRoute then
		local vxz = hypot2(next.vx, next.vz)
		if not prevRoute then
			pounce = pounceAgo(nil)
		end
		-- a launch: the vertical speed rose, or a pounce the window dates (it replaces the velocity, so it may lower it)
		local launched = not prevRoute
			and not next.grounded
			and (next.vy > prev.vy + P.gravity * 0.5 * P.substep or pounce ~= nil)
		-- hidden(): a short gap (at most three motor frames) explained by grabs it hides, as the motor makes them
		-- (validator round 7: "any sample within a grab" let a sample 8.5 st over the body beside a trunk carry it 135 st
		-- up in 0.37 s): E in the air takes the NEAREST open rail sample within a grab of the body (Motion.nearestRoute)
		-- and Space leaps off it in the same frame, at most once per two motor frames (lastGrab: the clock of the last
		-- one, the validator's; E and Space every second frame is how the honest motor climbs a trunk, 29 st/s). Every
		-- pattern of grabs the gap's frames allow is stepped as the motor steps (the body on its own arc, a grab snapping
		-- it to the nearest sample's drawn pose and leaping at the launch's speed); `next` is explained when it is within
		-- posSlack under the highest a pattern reaches, over a leap off the lowest sample its grab can have taken, and
		-- across within the leap's flight from the sample (validator round 15, the round-14 review's MEDIUM 4: the grab's
		-- snap onto the rail is the motor's, no teleport); of those the fewest grabs, the earliest last grab, the highest
		local frames = math.max(1, math.ceil(dt / P.substep - 1e-6))
		-- (grasped(): the same search over a gap of up to grabSimDt: validator round 14, the round-13 review's HIGH 1: a
		-- launch in the air is free only off a rail the server itself puts the body on, and for a launch the motor's own
		-- grab stepped from the last accepted place is that; ten packets a second is how a phone at ten frames sends the
		-- motor's honest leap-and-regrab climb. Round 15, the round-14 review's MEDIUM 3: one gather of the samples the
		-- grabs can reach, the patterns' grabs scanned over that small list, fewest grabs first, within E.grabWork)
		local hiddenMemo: boolean? = nil
		local searchSpent = false -- (the search stopped at its work, or past grabSimDt: it judged nothing)
		local function search(): boolean
			if hiddenMemo ~= nil then
				return hiddenMemo
			end
			hiddenMemo = false
			searchSpent = true
			if dt > math.max(E.shortDt, E.grabSimDt) + E.dtEps then
				return false
			end
			local index = world.index :: any
			local accept = Motion.openOnly(world)
			local h, g = P.substep, P.gravity
			-- (the motor's grab-and-jump cooldown after a seed's leap off the rail, owner D18: its first grab no sooner than
			-- grabLeapCooldown after the leap, in whole steps rounded down (a frame's own length is the client's); not yet
			-- between the air's grab-leaps, where it snapped honest climbs on uneven frames)
			local seedWait = math.max(1, math.floor(P.grabLeapCooldown / h + 1e-6))
			-- the body's own arc from `prev`, no grab, frame by frame (entry f + 1: after f frames), and how far across the
			-- air's steering can have taken it off that arc. The motor's air step per frame either steers the velocity
			-- toward a heading at moveSpeed (accelAir) or lets it coast (dragAir), or in a pounce's window keeps it: the
			-- speed it had fades by between the two rates and the steering adds at most its own speed for the rest, never
			-- past the faster of the two speeds (validator round 15: a reach growing with the speed had and the steering
			-- both, any way, let a crafted grab-leap chain along a long rail run 44 st/s where the motor's own runs 41)
			local v0 = hypot2(prev.vx, prev.vz)
			-- (the air trick's re-aim, owner D18: the gap's own re-aim (0c: the claimed change, held to the motor's rates)
			-- turns the speed had by at most its turn and scales it by at most its scale, and pushes it down or up by at most
			-- its vertical speed's change: no further than v0 x tau x aimAcross + aimUp x tau from where it would be)
			local aimAcross, aimUp = gapAim.across, gapAim.up
			-- (the air steers toward moveSpeed, a sprint's at most, or v5.4's sprint in a rail leap's flight)
			local steerTo = math.max(P.sprint * (if boosted then P.boostMult else 1), SquirrelMotor.V54.sprint)
			-- (a grab's leap across: the motor's own leap off a rail, steered toward v5.4's sprint at most, a hair over for
			-- its substeps)
			local leapXZ = math.max(if boosted then P.leapForwardBoost else P.leapForward, steerTo) * C_STEP
			-- (`prev`'s own flight: a chained leap's steers toward a sprint or v5.4's sprint at chainCarry; owner D19)
			local arcSteer = if chained
				then math.max(
					P.sprint * (if boosted then P.boostMult else 1),
					SquirrelMotor.V54.sprint * (if boosted then P.boostMult else 1) * P.chainCarry
				)
				else steerTo
			-- (a chained grab-leap, owner D19: the motor's leap off a rail it came onto from another leap off a rail, a
			-- moment before (every grab in the air from such a flight, so every later grab here, and a first one when
			-- `prev`'s flight is the server's own rail launch: `chained`): chainCarry across, steered toward a sprint or
			-- v5.4's sprint at that carry, and chainLift up)
			local boostM = if boosted then P.boostMult else 1
			-- (its speed across `tau` s after the leap: from chainCarry of a leap, steered at accelAir toward the faster of a
			-- sprint and v5.4's sprint at that carry; a hair over for the substeps)
			local chainLaunch = (if boosted then P.leapForwardBoost else P.leapForward) * P.chainCarry
			local chainSteer = math.max(P.sprint * boostM, SquirrelMotor.V54.sprint * boostM * P.chainCarry)
			local function chainAt(tau: number): number
				return math.max(
					chainLaunch,
					chainLaunch + (chainSteer - chainLaunch) * (1 - math.exp(-P.accelAir * tau))
				) * C_STEP
			end
			local chainXZ = chainAt(math.max(E.grabSimDt, dt))
			local chainUp = launchUp * P.chainLift
			local anyFull = false -- (an explanation with a full leap after a grab: no chained cap kept)
			local ax, ay, az, ar = { prev.x }, { prev.y }, { prev.z }, { 0 }
			-- (how far across from `prev` the body can be after each frame of its own arc: owner D19, a pattern's reach
			-- from `prev` is that to its first grab and its leaps' flights after)
			local reach0 = { 0 }
			local lox, loy, loz, hix, hiy, hiz = prev.x, prev.y, prev.z, prev.x, prev.y, prev.z
			-- (off a rail, section 4's gap: the motor's leap off it at the start of frame j, from its drawn pose at a
			-- point of the stretch it ran in the frames before: within seedR[j] across of the drawn pose at `prev`, between
			-- seedLow[j] and seedTop[j] high. The arc's entries then only bound the gather: the lowest launch point and each
			-- frame the highest a leap at the first frame reaches, as far across as the latest launch and its flight allow;
			-- validator round 17, the round-16 review's MEDIUM 1a. The leap's vertical speed is the motor's own, leapUp:
			-- the server's, no claim. Out of an enclosed run's mouth, none: section 0's)
			local leftRoute = prevRoute
			if leftRoute and leftRoute.enclosure then
				return false
			end
			local vis = if leftRoute then visualPosition(prev, world) else nil
			local seedR, seedTop, seedLow = {}, {}, {}
			if leftRoute and vis then
				local cap = SquirrelMotor.routeCap(leftRoute, boosted)
				local len = math.max(leftRoute.length, 1e-6)
				for j = 1, frames do
					local run = cap * E.railTol * (j - 1) * h + E.posSlack
					local top, low, across = -math.huge, math.huge, 0
					for k = -4, 4 do
						local tt = math.clamp(prev.railT + run / len * k / 4, 0, 1)
						local w = Motion.visualPose(
							world,
							leftRoute,
							tt,
							reg:pointAt(leftRoute, tt),
							prev.trunkNormalX,
							prev.trunkNormalZ
						)
						top, low = math.max(top, w.y), math.min(low, w.y)
						across = math.max(across, hypot2(w.x - vis.x, w.z - vis.z))
					end
					seedR[j], seedTop[j], seedLow[j] = across + run / 4 + E.posSlack, top, low
				end
				local wide = seedR[frames] + leapXZ * frames * h
				ax[1], ay[1], az[1], ar[1] = vis.x, seedLow[frames], vis.z, wide
				for f = 1, frames do
					ax[f + 1], ay[f + 1], az[f + 1], ar[f + 1] = vis.x, seedTop[frames] + launchUp * f * h, vis.z, wide
				end
				lox, loy, loz = math.min(lox, vis.x), math.min(loy, ay[1]), math.min(loz, vis.z)
				hix, hiy, hiz = math.max(hix, vis.x), math.max(hiy, ay[frames + 1]), math.max(hiz, vis.z)
			else
				local ux, uz = if v0 > 1e-6 then prev.vx / v0 else 0, if v0 > 1e-6 then prev.vz / v0 else 0
				local held = math.max(prev.attackWindow, 0)
				local fa, fd = 1 - (1 - math.exp(-h * P.accelAir)), math.exp(-h * P.dragAir)
				local ka, kd = 1, 1 -- (what is left of the speed had, steered every frame or coasting every frame)
				local ta, td, th = 0, 0, 0 -- (the time it has carried the speed had, each way; the time held)
				local y, vy = prev.y, prev.vy
				for f = 1, frames do
					vy = math.max(vy - g * h, -P.terminalFall)
					y += vy * h
					if th + h <= held + 1e-9 then
						th += h
					else
						ka, kd = ka * fa, kd * fd
						ta, td = ta + ka * h, td + kd * h
					end
					local t = f * h
					local steer = arcSteer * (t - th - ta)
					local lo = v0 * (th + ta) - steer
					local hi = math.min(v0 * (th + td) + steer, math.max(v0, arcSteer) * t)
					local lat = steer
					local mid = (lo + hi) / 2
					local x, z = prev.x + ux * mid, prev.z + uz * mid
					local r = math.max((hi - lo) / 2, lat) + (v0 * aimAcross + aimUp) * t
					ax[f + 1], ay[f + 1], az[f + 1], ar[f + 1] = x, y, z, r
					reach0[f + 1] = hypot2(x - prev.x, z - prev.z) + r
					lox, loy, loz = math.min(lox, x), math.min(loy, y), math.min(loz, z)
					hix, hiy, hiz = math.max(hix, x), math.max(hiy, y), math.max(hiz, z)
				end
			end
			-- the gather, once: every open sample within R1 of the arc's middle (a first grab's whole reach from any point of
			-- the arc, its band of samples nearest to some place the steering allows included), from the index's cells that
			-- box it, a cell at a time; within grabReach more (a later grab's) from the cells round those only when a
			-- second grab is searched. Kept in order of height (a stud a bin), so a grab scans only the heights its nearest
			-- sample and its band can be at
			local cx, cy, cz = (lox + hix) / 2, (loy + hiy) / 2, (loz + hiz) / 2
			local R1 = 0
			for f = 1, frames + 1 do
				local d = math.sqrt((ax[f] - cx) ^ 2 + (ay[f] - cy) ^ 2 + (az[f] - cz) ^ 2)
				R1 = math.max(R1, d + ar[f])
			end
			R1 += C.airGrab + E.posSlack
			local Rg = R1 + 2 * ar[frames + 1] + E.grabReach
			local held = R1 -- (the radius round the middle the gather holds whole)
			local yLo = cy - Rg
			local bins = math.max(1, math.ceil(2 * Rg))
			local n, work = 0, 0
			local cs = index.cellSize or 20
			local cellAt = index.cell
			-- (an enclosed run is no grab's: Motion.openOnly, by route)
			local open: { [number]: boolean } = {}
			local gId, gT, gX, gY, gZ, gB = GS.id, GS.t, GS.x, GS.y, GS.z, GS.b
			local sId, sT, sX, sY, sZ, start, fill = GS.sid, GS.st, GS.sx, GS.sy, GS.sz, GS.start, GS.fill
			-- gather(R): the samples within R of the middle, from the cells that meet that ball, into sId, sX, sY, sZ in
			-- order of height, bin b's (a stud each, up from yLo) from start[b] to start[b + 1] - 1
			local function cellsFor(R: number): ({ any }, number)
				local cells, total = {}, 0
				for i = math.floor((cx - R) / cs), math.floor((cx + R) / cs) do
					local ex = math.max(0, i * cs - cx, cx - (i + 1) * cs)
					for j = math.floor((cy - R) / cs), math.floor((cy + R) / cs) do
						local ey = math.max(0, j * cs - cy, cy - (j + 1) * cs)
						for k = math.floor((cz - R) / cs), math.floor((cz + R) / cs) do
							local ez = math.max(0, k * cs - cz, cz - (k + 1) * cs)
							if ex * ex + ey * ey + ez * ez > R * R then
								continue
							end
							local cell = if cellAt then cellAt(index, i, j, k) else nil
							if cellAt == nil then
								-- (an index without cell access: each cell's entries copied by its own walk)
								local c = { ids = {}, ts = {}, xs = {}, ys = {}, zs = {}, n = 0 }
								index:forEachNear(
									(i + 0.5) * cs,
									(j + 0.5) * cs,
									(k + 0.5) * cs,
									0,
									function(id: number, tt: number, x: number, y: number, z: number): boolean?
										c.n += 1
										c.ids[c.n], c.ts[c.n], c.xs[c.n], c.ys[c.n], c.zs[c.n] = id, tt, x, y, z
										return nil
									end
								)
								cell = c
							end
							if cell then
								table.insert(cells, cell)
								total += cell.n
							end
						end
					end
				end
				return cells, total
			end
			local function gather(cells: { any }, R: number)
				for b = 1, bins do
					fill[b] = 0
				end
				n = 0
				local mx, my, mz, r2, y0, last = cx, cy, cz, R * R, yLo, bins - 1
				local lastId, lastOk = -1, false
				for _, cell in cells do
					local ids, ts, xs, ys, zs = cell.ids, cell.ts, cell.xs, cell.ys, cell.zs
					work += cell.n
					for e = 1, cell.n do
						local x, y, z = xs[e], ys[e], zs[e]
						local dx, dy, dz = x - mx, y - my, z - mz
						if dx * dx + dy * dy + dz * dz <= r2 then
							local id = ids[e]
							if id ~= lastId then
								local ok = open[id]
								if ok == nil then
									ok = accept == nil or accept(id, ts[e])
									open[id] = ok
								end
								lastId, lastOk = id, ok :: boolean
							end
							if lastOk then
								n += 1
								local b = math.floor(y - y0)
								b = (if b < 0 then 0 elseif b > last then last else b) + 1
								gId[n], gT[n], gX[n], gY[n], gZ[n], gB[n] = id, ts[e], x, y, z, b
								fill[b] += 1
							end
						end
					end
				end
				start[1] = 1
				for b = 1, bins do
					start[b + 1] = start[b] + fill[b]
					fill[b] = start[b]
				end
				for e = 1, n do
					local b = gB[e]
					local at = fill[b]
					fill[b] = at + 1
					sId[at], sT[at], sX[at], sY[at], sZ[at] = gId[e], gT[e], gX[e], gY[e], gZ[e]
				end
				work += n
			end
			-- (the cells' entries totalled first: past the work before any grab, fail safe, as the ring's: validator round
			-- 16, the round-15 review's LOW 3, a denser crown walked whatever the first gather's cells held)
			do
				local cells, total = cellsFor(R1)
				if total > E.grabWork then
					return false
				end
				gather(cells, R1)
			end
			searchSpent = false
			local outerDone = false
			-- (the ring out to Rg, once, when the work allows it: false when it does not)
			local function gatherOuter(): boolean
				outerDone = true
				local cells, total = cellsFor(Rg)
				if work + total > E.grabWork then
					return false
				end
				gather(cells, Rg)
				held = Rg
				return true
			end
			local incomplete = false -- (the last grab's band reached past what the gather holds)
			local over = false -- (the work ran out)
			local function binOf(y: number): number
				return math.clamp(math.floor(y - yLo), 0, bins - 1) + 1
			end
			-- grab(x, y, z, r): the motor's grab from somewhere within r across of (x, y, z), the height known: the nearest
			-- sample N, and every sample S that is the nearest to some such place (the band: along N's own stretch of
			-- route within r across and a sample's spacing of N; any other within the bisector test
			-- |S - c|^2 - |N - c|^2 <= 2 r |S - N| across, c the place modelled). Returns where the leap leaves from across (N, the highest's drawn offset)
			-- and its height (the highest's drawn pose), the lowest sample (a leap off it ends no lower: validator round
			-- 14), how far across the grab's snap took the body (N's distance across and the drawn pose's offset), and
			-- how far across the body may be off where the leap leaves (the band's spread off N, their own drawn poses, a
			-- trunk's heading in doubt; validator round 16, the round-15 review's MEDIUM 1: from the band's highest with
			-- the whole band as its doubt, a later grab carried the body half a band forward a grab); nil when nothing is
			-- within a grab, when the gather does not hold all of N's band, or past the work (fail safe)
			local band = GS.band
			local grabbedId, grabbedT = 0, 0 -- (the route and place of the last grab's highest sample)
			-- (the last grab's snap across, a first grab's bound: the motor takes any sample S of the band, nearest to where
			-- the body is, within r across of the place modelled and at its height (the arc's own), so no further from it
			-- than N is (d + r): across, sqrt((d + r)^2 - (S's height off the body's)^2), and S's drawn offset. Not N's
			-- distance across (one nearer in 3-D can lie further across: validator round 17, the round-16 review's MEDIUM 1b),
			-- nor N's 3-D distance (a grab from over a rail is mostly down, and that drop let a crafted chain along a rail
			-- claiming the air trick's swing run 3 % faster). snap3: N's 3-D distance and the drawn offset, for a grab from a
			-- place whose height is only the highest (a leap off a rail's))
			local snapAcross, snap3 = 0, 0
			-- (owner D19, tighter: the leave point's own distance from `prev`, the band's furthest member and its drawn
			-- offset, less what the arc covers before the grab (vmax per frame); a later grab's snap adds half a sample's
			-- spacing, the motor's grab of the nearest sample ahead of where its flight has carried it)
			local leaveFar = 0
			-- (a trunk's bark the last grab leaves from: its nearest sample across and the drawn pose's offset off it, 0 for
			-- any other route)
			local barkX, barkZ, bark = 0, 0, 0
			local function grab(
				x: number,
				y: number,
				z: number,
				r: number
			): (number?, number, number, number, number, number)
				incomplete = false
				local X, Y, Z, S = sX, sY, sZ, start
				local reach = C.airGrab + r + E.posSlack
				local best2, bi = reach * reach, 0
				local b0 = binOf(y)
				local seen = 0
				-- (nearest: the bins up from the body's, then down, each while it can hold a nearer sample)
				for b = b0, bins do
					local dy = yLo + (b - 1) - y
					if b > b0 and dy * dy >= best2 then
						break
					end
					for e = S[b], S[b + 1] - 1 do
						local ex, ey, ez = X[e] - x, Y[e] - y, Z[e] - z
						local d2 = ex * ex + ey * ey + ez * ez
						if d2 < best2 then
							best2, bi = d2, e
						end
					end
					seen += S[b + 1] - S[b] + 1
				end
				for b = b0 - 1, 1, -1 do
					local dy = y - (yLo + b)
					if dy * dy >= best2 then
						break
					end
					for e = S[b], S[b + 1] - 1 do
						local ex, ey, ez = X[e] - x, Y[e] - y, Z[e] - z
						local d2 = ex * ex + ey * ey + ez * ez
						if d2 < best2 then
							best2, bi = d2, e
						end
					end
					seen += S[b + 1] - S[b] + 1
				end
				work += seen
				if bi == 0 then
					return nil, 0, 0, 0, 0, 0
				end
				local d = math.sqrt(best2)
				local twoR = 2 * r
				local w = d + twoR
				if math.sqrt((x - cx) ^ 2 + (y - cy) ^ 2 + (z - cz) ^ 2) + w > held then
					incomplete = true
					return nil, 0, 0, 0, 0, 0
				end
				-- (the band, within d + 2r: its highest and lowest, then how far across its members lie off N)
				local nx, nz = X[bi], Z[bi]
				local top, topY = bi, Y[bi]
				local lowY = topY
				-- (the highest drawn: a sample's height and its route's lift, so where a trunk and a bough meet the bough's
				-- lift is kept whichever sample is N; validator round 17)
				local function liftOf(id: number): number
					local it = reg:get(id)
					return if it then drawnOf(world, it).lift else 0
				end
				local topDrawn = topY + liftOf(sId[bi])
				local w2 = w * w + 1e-9
				local nb = 0
				local bLo, b1 = binOf(y - w), binOf(y + w)
				if work + S[b1 + 1] - S[bLo] > E.grabWork then
					-- (past the work: fail safe)
					over = true
					return nil, 0, 0, 0, 0, 0
				end
				-- (a sample S of N's own route along the same stretch, its arc no longer than the chord between them and a
				-- sample's spacing: a place within r across of the one modelled lies along the stretch within r of it (the
				-- horizontal part of the stretch's direction, `across / chord`, of r) and takes as its nearest a sample
				-- within half a spacing of that, N within half a spacing of the place modelled: S is in the band when
				-- |S - N| is within that, a spacing and posSlack (`pad`); up a trunk a place across takes the same
				-- height, so N and its neighbours. Validator round 16, the round-15 review's MEDIUM 1: the bisector test
				-- against N alone took samples 2r along a rail, and a crafted grab-leap chain ran the governor's ceiling.
				-- (Half a spacing off the place modelled instead of N snapped an honest grab-leap spam on a jittery link
				-- once more in the tree fuzz.) Another route, or the same one doubled back, keeps the bisector test, a
				-- micro-stud's rounding over it: where routes meet their samples coincide but for the float sums of their
				-- curves, and the motor's grab takes any of them (validator round 17, the round-16 review's MEDIUM 1c: N a
				-- bough's end, the motor the trunk's top at the same point, drawn 1.5 st across)
				local idN, tN = sId[bi], sT[bi]
				local routeN = reg:get(idN)
				local lenN = if routeN then routeN.length else 0
				local spacing = if routeN then lenN / math.max(1, routeN.sampleCount - 1) else E.sampleSpacing
				local pad = spacing + E.posSlack
				local nyN = Y[bi]
				for b = bLo, b1 do
					for e = S[b], S[b + 1] - 1 do
						local ex, ey, ez = X[e] - x, Y[e] - y, Z[e] - z
						local d2 = ex * ex + ey * ey + ez * ez
						if d2 <= w2 then
							local ux, uz, uy = X[e] - nx, Z[e] - nz, Y[e] - nyN
							local across = math.sqrt(ux * ux + uz * uz)
							local taken
							if e == bi then
								taken = true
							else
								local chord = math.sqrt(ux * ux + uz * uz + uy * uy)
								if sId[e] == idN and math.abs(sT[e] - tN) * lenN <= chord + spacing then
									taken = chord * chord <= r * across + pad * chord
								else
									taken = d2 - best2 <= twoR * across + 1e-6
								end
							end
							if taken then
								nb += 1
								band[nb] = e
								local sy = Y[e]
								local drawnY = sy + (if sId[e] == sId[top] then topDrawn - topY else liftOf(sId[e]))
								if drawnY > topDrawn then
									top, topY, topDrawn = e, sy, drawnY
								end
								if sy < lowY then
									lowY = sy
								end
							end
						end
					end
				end
				work += S[b1 + 1] - S[bLo] + nb
				-- (the leap leaves from the highest's drawn pose: off a trunk toward where the body came from (enterRoute's
				-- trunk normal), so within r of the place modelled, the farther the less its heading is in doubt; a bough's
				-- clearance off its trunk is its own)
				local tx, tz = X[top], Z[top]
				local topId = sId[top]
				local grabbed = reg:get(topId)
				local px, pz, lift, doubt, m = tx, tz, 0, 0, 0
				if grabbed then
					local ux, uz = x - tx, z - tz
					local l = math.sqrt(ux * ux + uz * uz)
					local drawn = Motion.visualPose(
						world,
						grabbed,
						sT[top],
						Curve.vec3(tx, topY, tz),
						if l > 1e-6 then ux / l else 0,
						if l > 1e-6 then uz / l else 1
					)
					px, pz, lift = drawn.x, drawn.z, math.max(0, drawn.y - topY)
					m = hypot2(px - tx, pz - tz)
					if grabbed.kind == "trunk" and not grabbed.flags.fixedSurfaceZ then
						local clear = l - r - st(0.13)
						doubt = if clear > 1e-6 then math.min(2 * m, m * r / clear) else 2 * m
					end
				end
				barkX, barkZ = X[bi], Z[bi]
				bark = if grabbed and grabbed.kind == "trunk" and not grabbed.flags.fixedSurfaceZ then m else 0
				-- (the band's others across off N; one on another route than the highest's, its own drawn pose off it as
				-- well)
				local spread, lastId, lastOff = 0, -1, 0
				local across, dr2 = 0, (d + r) ^ 2
				local far = 0
				for k = 1, nb do
					local e = band[k]
					local id = sId[e]
					if id ~= lastId then
						local other = reg:get(id)
						lastId = id
						lastOff = if id == topId then 0 elseif other then drawnOf(world, other).across + m else m
					end
					local ux, uz = X[e] - X[bi], Z[e] - Z[bi]
					spread = math.max(spread, math.sqrt(ux * ux + uz * uz) + lastOff)
					local off = if id == topId then m else lastOff
					across = math.max(across, math.sqrt(math.max(0, dr2 - (Y[e] - y) ^ 2)) + off)
					far = math.max(far, hypot2(X[e] - prev.x, Z[e] - prev.z) + off)
				end
				grabbedId, grabbedT = topId, sT[top]
				local hd = math.sqrt((X[bi] - x) ^ 2 + (Z[bi] - z) ^ 2)
				snap3, snapAcross, leaveFar = d + m, across, far
				return px + (X[bi] - tx), topY + lift, pz + (Z[bi] - tz), lowY, hd + m, spread + doubt
			end
			-- the explanation kept: its last grab's clock (the earliest), the highest end, and its first grab (where the air
			-- bound starts)
			local bestLast, bestTop = math.huge, -math.huge
			local bestFrom: { clock: number, x: number, z: number, reach: number }? = nil
			local bestRoute: number? = nil
			-- (a pattern after a grab and the leap's first frame: `f` frames stepped, the body at x, z within r across,
			-- y its height, vy, `drop` how much lower a leap off the lowest sample of its grab starts, `last` the grab's clock,
			-- bx, bz and bark the grabbed trunk's sample and drawn offset, 0 off a trunk)
			type Pattern = {
				f: number,
				x: number,
				y: number,
				z: number,
				vy: number,
				r: number,
				drop: number,
				last: number,
				route: number,
				snap: number,
				bx: number,
				bz: number,
				bark: number,
				from: { clock: number, x: number, z: number, reach: number },
				seed: boolean?, -- (a leap off the rail `prev` is on: its next grab is the first)
				lx: number, -- (the leap in the air now: its rate across, a full leap's or a chained one's)
				base: number, -- (how far across from `prev` the body can be at its first grab or leap, and that time)
				t1: number,
				full: boolean, -- (a full leap after some grab of the pattern)
			}
			local function finish(s: Pattern)
				local y, vy, r = s.y, s.vy, s.r
				for _ = s.f + 1, frames do
					vy = math.max(vy - g * h, -P.terminalFall)
					y += vy * h
					r += s.lx * h
				end
				-- (a grab's leap: `next` no lower than one off the lowest sample it can have taken, at the motor's own leap
				-- speed, a stud and the slack under: validator round 14, the round-13 review's HIGH 1, a body 4 st under a
				-- bough "grabbed" it every 0.1 s packet; across within its flight from the sample: round 15)
				local floorY = y - s.drop - (launchUp - P.leapUp) * dt - st(0.4) - E.posSlack
				-- (and from `prev`, across no further than the fastest the air or a leap carries in the gap and the grabs'
				-- snaps onto their samples: validator round 15. Off a trunk the leap leaves its bark straight out (the
				-- motor's attackHeading) and the air in a gap of grabSimDt cannot steer it back in: `next` no nearer the
				-- grabbed sample across than the drawn pose, a stud's slack; validator round 16, a crafted climb inside a
				-- big trunk's bark took the nearest sample a trunk's lean denies the motor)
				if
					next.y <= y + E.posSlack
					and next.y >= floorY
					and hypot2(next.x - s.x, next.z - s.z) <= r + E.posSlack
					and hypot2(next.x - prev.x, next.z - prev.z) <= s.base + s.snap + (if s.full
						then leapXZ
						else chainXZ) * (dt - s.t1) + E.posSlack
					and hypot2(next.x - s.bx, next.z - s.bz) >= s.bark - st(0.4) - E.posSlack
				then
					if s.last < bestLast then
						bestLast, bestFrom, bestRoute = s.last, s.from, s.route
					end
					bestTop = math.max(bestTop, y)
					anyFull = anyFull or s.full
				end
			end
			local function leap(
				f: number,
				at: number,
				gx: number,
				gy: number,
				gz: number,
				lowY: number,
				spread: number,
				snap: number,
				from: { clock: number, x: number, z: number, reach: number },
				chain: boolean,
				full: boolean,
				base: number,
				t1: number
			): Pattern
				local up, lx = if chain then chainUp else launchUp, if chain then chainXZ else leapXZ
				return {
					f = f + 1,
					x = gx,
					y = gy + up * h,
					z = gz,
					vy = up,
					r = spread + lx * h,
					lx = lx,
					base = base,
					t1 = t1,
					full = full or not chain,
					drop = gy - lowY,
					last = at,
					route = grabbedId,
					snap = snap,
					bx = barkX,
					bz = barkZ,
					bark = bark,
					from = from,
				}
			end
			-- (a grab, and when its band reaches past the first gather the ring round it, gathered once if the work allows;
			-- fail safe past the work: `spent`)
			local spent = false
			local function grabWide(
				x: number,
				y: number,
				z: number,
				r: number
			): (number?, number, number, number, number, number)
				local gx, gy, gz, lowY, d, spread = grab(x, y, z, r)
				if gx == nil and incomplete and not outerDone then
					if gatherOuter() then
						gx, gy, gz, lowY, d, spread = grab(x, y, z, r)
					else
						spent = true
					end
				end
				spent = spent or over
				return gx, gy, gz, lowY, d, spread
			end
			-- one grab: from the arc, at any frame two after the last grab the validator knows of, the earliest that explains
			-- `next` kept
			local level: { Pattern } = {}
			if leftRoute and vis then
				-- (off a rail: the leaps off it, a frame each, their grabs at the next level)
				for j = 1, frames - 1 do
					table.insert(level, {
						f = j - 1,
						x = vis.x,
						y = seedTop[j],
						z = vis.z,
						vy = P.leapUp,
						r = seedR[j],
						drop = seedTop[j] - seedLow[j],
						last = prev.clock,
						route = leftRoute.id,
						snap = seedR[j] + hypot2(vis.x - prev.x, vis.z - prev.z),
						bx = 0,
						bz = 0,
						bark = 0,
						from = { clock = prev.clock + (j - 1) * h, x = vis.x, z = vis.z, reach = seedR[j] },
						seed = true,
						lx = leapXZ,
						base = 0,
						t1 = 0,
						full = true,
					})
				end
			else
				for f = 0, frames - 1 do
					local at = prev.clock + (f + 1) * h
					if lastGrab == nil or at - lastGrab >= 2 * h - 1e-6 then
						if work > E.grabWork then
							spent = true
							break
						end
						local gx, gy, gz, lowY, d, spread = grabWide(ax[f + 1], ay[f + 1], az[f + 1], ar[f + 1])
						if spent then
							break
						end
						if gx then
							local s = leap(
								f,
								at,
								gx,
								gy,
								gz,
								lowY,
								spread,
								math.min(snapAcross, math.max(0, leaveFar - reach0[f + 1])),
								{ clock = at, x = gx, z = gz, reach = d + 2 * ar[f + 1] + spread },
								chained == true,
								false,
								reach0[f + 1],
								f * h
							)
							finish(s)
							if bestFrom then
								break
							end
							table.insert(level, s)
						end
					end
				end
			end
			-- more grabs, a level at a time while none explains `next` and the work allows (fail safe past it)
			while bestFrom == nil and #level > 0 and not spent do
				-- (the patterns nearest `next` first, at most grabBeam of them: a pattern explains `next` only by ending
				-- near it; the rest are left, fail safe)
				if #level > E.grabBeam then
					table.sort(level, function(a: Pattern, b: Pattern): boolean
						local da = math.sqrt((a.x - next.x) ^ 2 + (a.y - next.y) ^ 2 + (a.z - next.z) ^ 2) - a.r
						local db = math.sqrt((b.x - next.x) ^ 2 + (b.y - next.y) ^ 2 + (b.z - next.z) ^ 2) - b.r
						return da < db
					end)
					for k = #level, E.grabBeam + 1, -1 do
						level[k] = nil
					end
				end
				local deeper: { Pattern } = {}
				-- (patterns whose last grab took the same sample on the same frame go on as one, its doubt the most of
				-- theirs: the same futures, so the patterns grow no faster than the frames and the samples)
				local same: { [number]: Pattern } = {}
				for _, s in level do
					local y, vy, r = s.y, s.vy, s.r
					for f = s.f, frames - 1 do
						if f > s.f and (not s.seed or f >= s.f + seedWait) then
							if work > E.grabWork then
								spent = true
								break
							end
							local gx, gy, gz, lowY, d, spread = grabWide(s.x, y, s.z, r)
							if spent then
								break
							end
							if gx then
								local more = leap(
									f,
									prev.clock + (f + 1) * h,
									gx,
									gy,
									gz,
									lowY,
									spread,
									s.snap + (if s.seed then snap3 else d + E.sampleSpacing / 2),
									s.from,
									true,
									s.full,
									s.base,
									s.t1
								)
								local key = (f * 131072 + grabbedId) * 65536 + math.floor(grabbedT * 65535 + 0.5)
								local was = same[key]
								if was then
									was.r, was.drop = math.max(was.r, more.r), math.max(was.drop, more.drop)
									was.snap = math.max(was.snap, more.snap)
									was.lx, was.full = math.max(was.lx, more.lx), was.full or more.full
									finish(was)
								else
									same[key] = more
									finish(more)
									table.insert(deeper, more)
								end
							end
						end
						vy = math.max(vy - g * h, -P.terminalFall)
						y += vy * h
						r += s.lx * h
					end
					if spent then
						break
					end
				end
				level = deeper
			end
			searchSpent = spent and bestFrom == nil
			if bestFrom then
				hiddenMemo = true
				judged.grab = bestLast
				judged.grabFrom = bestFrom
				judged.grabRoute = bestRoute
				judged.y = math.min(judged.y or next.y, bestTop)
				judged.chainXZ = if anyFull then nil else chainAt(next.clock - bestLast)
			end
			return hiddenMemo :: boolean
		end
		local function hidden(): boolean
			return shortGap and search()
		end
		local function grasped(): boolean
			return dt <= E.grabSimDt + E.dtEps and search()
		end
		local railPlausible: boolean? = nil
		local function plausible(): boolean
			if railPlausible == nil then
				railPlausible = railWithinReach()
			end
			return railPlausible :: boolean
		end
		-- railHigh(): a rail visit hidden in the gap that explains a rise needs a rail near where `next` is, no lower than
		-- a leap off it ending at the speed `next` shows rises in the gap (round 4's greedy adversary: "a rail within
		-- reach" alone let a client at 2 packets a second climb 24 studs a packet beside a trunk, to 115 studs)
		local railHighMemo: boolean? = nil
		local function railHigh(): boolean
			if railHighMemo == nil then
				local v = next.vy
				local u = math.min(launchUp, v + P.gravity * dt + gEps)
				local minY = next.y - math.max(0, (u * u - v * v) / (2 * P.gravity)) - E.posSlack
				-- (across: a grab and the gap's run at the horizontal speed kept; up: no more than a grab and a fall
				-- from rest over `next`)
				local reach = C.airGrab + math.max(groundCap, hypot2(prev.vx, prev.vz)) * dt + E.posSlack
				local maxY = next.y + C.airGrab + 0.5 * P.gravity * dt * dt + E.posSlack
				local found = false
				local index = world.index :: any
				index:forEachNear(
					next.x,
					next.y,
					next.z,
					math.ceil(math.max(reach, maxY - minY) / (index.cellSize or 20)),
					function(_id: number, _t: number, sx: number, sy: number, sz: number): boolean?
						if sy >= minY and sy <= maxY and hypot2(sx - next.x, sz - next.z) <= reach then
							found = true
							return true
						end
						return nil
					end
				)
				railHighMemo = found
			end
			return railHighMemo :: boolean
		end
		-- (a rail visit hidden in a gap longer than shortDt: up to grabSimDt the grab search's verdict, the geometry only
		-- where the search ran past its work; longer, the geometry (plausible() and railHigh() below). Validator round 16,
		-- the round-15 review's LOW 2: a packet a hair over 0.05 s, or of 0.06-0.25 s, climbed a trunk at the
		-- governor's vertical bound by the geometry alone, a rise each packet with no grab the motor could make)
		local railHighMemoV: boolean? = nil
		local function longVisit(): boolean
			if railHighMemoV == nil then
				local v = false
				if dt <= E.grabSimDt + E.dtEps and search() then
					v = true
				elseif dt > E.grabSimDt + E.dtEps or searchSpent then
					v = plausible() and railHigh()
				end
				railHighMemoV = v
			end
			return railHighMemoV :: boolean
		end
		-- (the most the body can fall in the gap from where it was: a floor that near may have taken it inside the gap;
		-- prev.vy is the validator's own, never a speed only the client claimed: Judged)
		local fallReach = math.max(0, -prev.vy) * dt + 0.5 * P.gravity * dt * dt + E.posSlack
		-- landedIn(leapt): could the body have come down on a floor inside the gap and be where `next` has it after?
		-- (The round-3 review: a hover claimed a fall onto a floor every other packet, and leapt from the hover.) From
		-- `prev` at its judged vertical speed the body falls onto a floor F no lower than gravity takes it in the gap (it
		-- may rise to its apex first); the time left after that landing is all it has: off the floor's edge (`leapt`
		-- false) it ends no higher than the floor (E.floorSlack: the client's own may be a little over the server's),
		-- leapt from it no higher than a leap ending at the speed `next` shows rises in the time left, ((u^2 - v^2) / 2g,
		-- u at most v + g * left). A higher floor leaves more time, so the lowest floor that explains `next` is found by
		-- arithmetic, and one ray (under prev, else under next) asks whether a floor lies between it and the top. A body
		-- standing at `prev` landed on its own floor (the vertical bounds below hold it to it). `from`: the body left
		-- `prev` at that vertical speed instead (a whole leap hidden before the launch seen: it came down on a ledge)
		local function landedIn(leapt: boolean, from: number?): boolean
			if prev.grounded and from == nil then
				return true
			end
			local g = P.gravity
			local vy0 = from or prev.vy
			local top = prev.y + math.max(vy0, 0) ^ 2 / (2 * g)
			local bottom = prev.y + vy0 * dt - 0.5 * g * dt * dt - E.posSlack
			local v = next.vy
			-- the highest `next` can be after a landing on F
			local function reach(f: number): number
				if not leapt then
					return f + E.floorSlack
				end
				local d = prev.y - (f + E.floorSlack) -- (the client's floor may be that much over the server's)
				local tf = (vy0 + math.sqrt(math.max(0, vy0 * vy0 + 2 * g * d))) / g
				local left = dt - tf + E.gravityEps
				if left < 0 then
					return -math.huge
				end
				local u = math.min(launchUp, v + g * left + gEps)
				return f + E.floorSlack + math.max(0, (u * u - v * v) / (2 * g))
			end
			if reach(top) < next.y then
				return false
			end
			local lo = bottom
			if reach(lo) < next.y then
				local hi = top
				for _ = 1, 12 do
					local mid = (lo + hi) / 2
					if reach(mid) >= next.y then
						hi = mid
					else
						lo = mid
					end
				end
				lo = hi
			end
			local landable = world.landable
			if landable then
				local depth = top - lo
				return landable(prev.x, top, prev.z, depth) or landable(next.x, top, next.z, depth)
			end
			local f = math.max(world.groundAt(prev.x, prev.z, top), world.groundAt(next.x, next.z, top))
			return f >= lo - 1e-6 and f <= top + 1e-6
		end
		-- a trampoline's bed (Movement/Trampoline) the body could have come down on inside the gap bounces it higher than a
		-- leap, and pushes it on
		local trampUp = (Trampoline.C.baseVy + Trampoline.C.maxCount * Trampoline.C.perBounceVy) * E.launchTol
		local tramp = false
		local tramps = world.trampolines
		if tramps and #tramps > 0 then
			local reach = Trampoline.C.radius + hypot2(prev.vx, prev.vz) * dt + E.posSlack
			local over = math.max(prev.vy, 0) ^ 2 / (2 * P.gravity) -- (it may rise first, then fall onto it)
			for _, site in tramps do
				if
					(
						hypot2(prev.x - site.x, prev.z - site.z) <= reach
						or hypot2(next.x - site.x, next.z - site.z) <= reach
					)
					and prev.y + over - (site.surface + Trampoline.C.bedAbove) <= fallReach + P.gravity * dt * dt
				then
					tramp = true
					break
				end
			end
		end
		if prevRoute then
			-- (section 4: a gap off the rail the launch points do not explain is, up to grabSimDt, the motor's leap off it
			-- and its grabs inside the gap, or a teleport; validator round 17, the round-16 review's MEDIUM 1a: a packet that
			-- left a bough and grabbed again inside three frames had no hidden grab; at 0.08-0.1 s packets the same off the
			-- climb's first trunk)
			if #leftOver > 0 and not grasped() then
				for _, why in leftOver do
					add(out, "teleport", 1, why)
				end
			end
		else
			local fromGroundOrRail = false
			local capUp = launchUp
			local capXZ = groundCap
			if launched then
				launchUsed = true
				-- from the ground or a (possibly hidden) rail: the leap; in the air: only a pounce. A body falling onto
				-- the ground within the gap may have landed and leapt again in it (Space held through a landing), no higher
				-- than that leap rises over that floor in the time left (landedIn)
				local function railVisit(): boolean
					return if shortGap then hidden() else longVisit()
				end
				local offGround = landedIn(true)
				fromGroundOrRail = offGround or railVisit()
				-- (what the meter pays: a launch off the ground, or a pounce anywhere off a rail, as the motor's doLeap and
				-- doPounce charge; none for a bounce. Validator round 14, the round-13 review's HIGH 1: a rail launch is free
				-- only where the server itself puts the body on the rail: in a short gap the motor's own grab stepped from the
				-- last accepted place (hidden()); a long gap's visit (a rail near the line and over `next`) explains the launch
				-- but earns nothing: a leap off the ground, charged, its flight no free one)
				if not tramp and (prev.grounded or not grasped()) then
					judged.charge = if pounce ~= nil then "pounce" else "leap"
				elseif not prev.grounded and grasped() and pounce == nil then
					-- (a pounce off the rail is free but no rail leap's flight: validator round 15, the round-14 review's LOW d)
					judged.railLaunch = true
				end
				capUp = if fromGroundOrRail then launchUp else pounceUp
				capXZ = if fromGroundOrRail then launchXZ else pounceXZ
				if tramp then
					capUp = math.max(capUp, trampUp)
					capXZ = math.max(capXZ, hypot2(prev.vx, prev.vz) * E.speedTol + Trampoline.C.push * E.launchTol)
				end
				if next.vy > capUp then
					add(out, "launch", 1, `vertical launch {next.vy} st/s (cap {capUp})`)
				end
				if vxz > capXZ then
					add(out, "launch", 1, `horizontal launch {vxz} st/s (cap {capXZ})`)
				end
				-- every launch (a leap, a pounce, a drop, a bounce) starts going up: by the end of the gap gravity has taken at
				-- most the gap's worth of it (a launch claimed on a fall is a fall)
				if next.vy < -P.gravity * dt - gEps then
					add(out, "launch", 1, `a launch ending at vy {next.vy} in {dt} s`)
				end
				-- with nothing within reach to push off, only the motor's pounce launches, and it shows in the window
				if not fromGroundOrRail and not tramp and pounce == nil then
					add(out, "launch", 1, `a launch in the air (vy {prev.vy} -> {next.vy}) that is no pounce`)
				end
			else
				if vxz > groundCap then
					add(out, "speed", math.min(1, vxz / groundCap - 1), `horizontal speed {vxz} st/s (cap {groundCap})`)
				end
				-- gravity: airborne at both ends and no launch -> vy drops by exactly g*dt (semi-implicit
				-- Euler, down to the terminal speed) unless a rail within reach could have been visited in between
				if not prev.grounded and not next.grounded then
					local expected = math.max(prev.vy - P.gravity * dt, -P.terminalFall)
					if math.abs(next.vy - expected) <= gEps then
						-- a plain arc: the height follows the vertical speed between the two (a body that claims to fall but
						-- keeps its height is flying), unless a rail it could have visited in between explains it. Stepped
						-- semi-implicitly (and held at the terminal speed), an arc rises a little less than the mean of its end
						-- speeds times the gap, rising or falling: no more than that, never a floor at 0 (a falling arc may
						-- not rise at all)
						local hi = (prev.vy + next.vy) / 2 * dt + E.posSlack + gEps * dt
						local lo = math.min(prev.vy, next.vy) * dt - E.posSlack - gEps * dt
						local dy = next.y - prev.y
						local function visited(): boolean
							return if shortGap then hidden() else longVisit()
						end
						if (dy > hi and not visited()) or (dy < lo and not plausible()) then
							add(out, "gravity", 1, `rose {dy} st in {dt} s on an arc from vy {prev.vy} to {next.vy}`)
						end
						arcVy = expected
						-- (and its height, when the arc explained it: no higher than the arc itself, so the slack each packet
						-- may take never adds up to a slower fall or a higher apex; round 4: a greedy adversary rose a leap's
						-- apex and the slack of every packet on the way up)
						if dy <= hi then
							judged.y = math.min(next.y, prev.y + (prev.vy + next.vy) / 2 * dt + 1e-3)
						end
					elseif next.vy >= -P.gravity * dt - gEps and next.vy <= gEps and landedIn(false) then
						-- (a body that came down on something inside the gap and went off its edge falls from rest, from no
						-- higher than that floor)
						judged.landed = true
					elseif not (if shortGap then hidden() else longVisit()) then
						-- (a pounce is a launch above; a rail visit zeroes the speed and relaunches it)
						add(out, "gravity", 1, `vertical speed {next.vy}, expected {expected}`)
					end
				end
			end
			-- horizontal displacement against the fastest plausible speed
			local dxz = hypot2(next.x - prev.x, next.z - prev.z)
			local fastest = math.max(groundCap, if launched then launchXZ else 0, hypot2(prev.vx, prev.vz) * E.speedTol)
			local allowedXZ = fastest * dt + E.posSlack
			-- (a launch the grab search explains is across where the motor's grab and leap put it: validator round 15, the
			-- round-14 review's MEDIUM 4, E+Space beside a rail was a "teleport" by the grab's snap onto it)
			if
				dxz > allowedXZ
				and not (not shortGap and plausible() and dxz <= allowedXZ + C.airGrab)
				and not (launched and grasped())
			then
				add(out, "teleport", math.min(1, dxz / allowedXZ - 1), `moved {dxz} st in {dt} s (allowed {allowedXZ})`)
			end
			-- vertical displacement: within what the start and end vertical speeds allow
			local dy = next.y - prev.y
			-- (rising at the higher end speed, no higher than its own apex: gravity takes it)
			local up = math.max(prev.vy, next.vy, 0)
			local upCap = math.min(up * dt, up * up / (2 * P.gravity)) + E.posSlack
			if launched then
				-- a launch inside the gap rises what the body rose before it at its earlier speed and what the launch, ending
				-- at the speed it shows, rose after it: (u^2 - v^2) / 2g, u the launch's own speed (the pounce's, which the
				-- window dates; else no more than gravity takes in the gap above the speed now, and never above the cap). A
				-- long gap may hide a landing before it, or from the ground a whole leap onto a ledge (ledge to ledge): only
				-- where landedIn finds that floor, and in the time the fall or the leap onto it left. (Not the launch speed
				-- over the gap for every launch: a launch every packet climbed at a leap's speed for as long as it liked; nor
				-- a whole apex added to every launch from the ground: round 4's greedy adversary claimed two leaps' height in
				-- one packet every half second, from flat ground onto a 14-stud roof)
				local v = math.max(next.vy, 0)
				local u =
					math.min(capUp, if pounce then next.vy + P.gravity * pounce else next.vy + P.gravity * dt + gEps)
				local rise = if u > v then (u * u - v * v) / (2 * P.gravity) else 0
				-- (before the launch, rising at its judged speed: no higher than that speed's own apex; round 4: the speed
				-- over the whole gap let a launch every packet off a rail "within reach" claim 30 st/s and climb 17 st a packet)
				local up0 = math.max(prev.vy, 0)
				local before = math.min(up0 * dt, up0 * up0 / (2 * P.gravity))
				if pounce and prev.grounded then
					-- (a pounce in the air after a leap off the ground inside the gap: the leap rose for the time before it)
					local t1 = math.min(math.max(0, dt - pounce) + E.gravityEps, launchUp / P.gravity)
					rise += launchUp * t1 - 0.5 * P.gravity * t1 * t1
				end
				upCap = before + rise + E.posSlack
				if
					dy > upCap
					and fromGroundOrRail
					and not shortGap
					and (if prev.grounded then landedIn(true, launchUp) else landedIn(true))
				then
					upCap = dy
				end
				if dy > upCap and fromGroundOrRail and not shortGap and longVisit() then
					-- (a rail within reach: a leap may have caught it inside the gap and the launch seen be the drop off it,
					-- the grab having carried the body up to the rail; in a short gap the grab is the motor's own: hidden)
					upCap = before + math.max(rise, launchUp * dt) + E.posSlack
				end
			end
			-- (a launch off the ground inside the gap may show no vertical speed by the end of it: a ground pounce's low hop,
			-- 9 st/s up, has all but stopped rising 0.12 s later, so a packet late by a little jitter saw neither the launch's
			-- speed nor a landing; the duel pounces every second, and one in about thirty was snapped. Such a gap holds a
			-- launch only if the end speed is one gravity could have brought a launch down to inside the gap, and the rise
			-- is what that launch, ending at that speed, could make: (u^2 - v^2) / 2g, u the launch speed. It counts as the
			-- launch, so the next packet cannot claim a second one stacked on it from a "ground" far below)
			if not launched and prev.grounded and not next.grounded and dy > upCap then
				if next.vy >= -P.gravity * dt - gEps then
					local u = math.min(launchUp, next.vy + P.gravity * dt + gEps)
					local rise = (u * u - next.vy * next.vy) / (2 * P.gravity)
					if u > 0 and dy <= rise + E.posSlack then
						upCap = dy
						launchUsed = true
						judged.charge = "leap"
					end
				end
			end
			local downCap = math.min(prev.vy, next.vy, 0) * dt - E.posSlack - P.gravity * dt * dt
			if prev.grounded then
				-- (the ground glue carried a grounded body down each frame before it left the ground: off a bough's round
				-- cylinder, down a kerb; validator round 7, a walk along a bough after a drop)
				-- (validator round 8, the round-7 review's LOW: never more than a body that kept the ground could follow down
				-- in the gap: the ground's slope over the distance moved, and one kerb; a frame's allowance each was 22.5 st
				-- beyond gravity in a 0.5 s gap)
				downCap -= math.min(
					frames * math.max(P.glueMin, P.glueSlope * groundCap * P.substep),
					P.glueMin + P.glueSlope * hypot2(next.x - prev.x, next.z - prev.z)
				)
			end
			if dy > upCap or dy < downCap then
				-- landing snaps to the ground (a step either way); a hidden rail visit climbs or descends
				local landing = next.grounded and math.abs(dy) <= Units.st(1.4)
				local railVisit = not shortGap
					and plausible()
					and math.abs(dy) <= SquirrelMotor.railCap(false, boosted) * dt + C.airGrab
					and (dy <= 0 or longVisit())
				if not landing and not railVisit and (dy > 0 or launched) and hidden() then
					-- (a short gap hides a grab and a leap all the same, as the motor makes them: hidden; down too, a grab's snap
					-- onto a lower sample: validator round 15)
					railVisit = true
				end
				if not landing and not railVisit then
					add(out, "teleport", 1, `vertical move {dy} st in {dt} s`)
				end
			end
			-- walls: the straight move must not cross a collider
			-- (with the higher end and how far over it the arc could have risen, so a leap over a fence is no wall: never
			-- higher than the highest launch here reaches, whatever speeds the packets claim)
			local apexUp = if tramp then math.max(launchUp, trampUp) else launchUp
			local rise =
				math.min(math.max(prev.vy, 0) ^ 2 / (2 * P.gravity) + launchUp * dt, apexUp * apexUp / (2 * P.gravity))
			wallTest(prev.x, prev.y, prev.z, rise, false)
			-- what the validator keeps: no vertical speed on the ground, gravity's after a plain arc, else the claim within
			-- the bounds it was judged against (every way into the air leaves at 0 or more: a fall the gap cannot explain is
			-- none); the horizontal cap it was judged against
			-- (a packet the grab search explained with no launch seen, the motor's grab-leap chain sent in phase with its
			-- grabs: each packet ends a frame after a leap, at the vertical speed of the last. A launch off the rail the
			-- search grabbed all the same, free, for the meter and the speed kept, its flight from the first grab, when the
			-- vertical speed is a leap's at the search's last grab, gravity since; validator round 17, the round-16
			-- review's LOW 3)
			local grabAt = judged.grab
			if
				grabAt
				and not launched
				and not prev.grounded
				and pounce == nil
				-- (a chained leap's rise, chainLift of a leap's: owner D19)
				and next.vy >= P.leapUp * P.chainLift - P.gravity * (next.clock - grabAt) - gEps
			then
				launchUsed = true
				judged.railLaunch = true
			end
			if next.grounded then
				judged.vy = 0
			elseif arcVy then
				judged.vy = arcVy :: number
			else
				judged.vy = math.clamp(next.vy, -P.gravity * dt - gEps, math.max(capUp, prev.vy, 0))
			end
			-- (a move the grab search explained with chained leaps only keeps no more across than they carry: owner D19)
			judged.xz = if judged.chainXZ then math.min(capXZ, judged.chainXZ :: number) else capXZ
		end
	end
	if nextRoute then
		-- (on a rail the motor's velocity is zero: the rail's own pace is judged by its parameter)
		judged.vy, judged.xz = 0, 0
	end

	return out, launchUsed, pounce, judged
end

-- 0c. The air trick's re-aim (owner D18). The motor turns and scales a wiggle's flight by what it applies (aimYaw,
-- aimReach on the packet: SquirrelMotor.reaim), each at a bounded rate. A re-aim moves only in a wiggle's flight (`prev`'s,
-- or a fresh one `next` claims, from none) and no faster than its rates over the gap and a substep. The move is then judged
-- as the flight it would have been with the gap's re-aim undone (unaim: the turn back, the scale back at the most a press
-- reaches, the vertical speed given back; each commutes with gravity, so the arc's checks hold as they are): a re-aim is
-- worth nothing to the envelope, and what it may carry further is the server's air bound's (MoveValidator._stamina, by the
-- server's own reach). The judged vertical speed and cap are handed back re-aimed, for the next packet's baseline.
function SquirrelMotor.envelope(
	prev: State,
	next: State,
	dt: number,
	world: World,
	boosted: boolean,
	lastGrab: number?,
	chained: boolean?
): ({ Violation }, boolean, number?, Judged)
	local pYaw, pReach = prev.aimYaw or 0, prev.aimReach or 0
	-- (a re-aim from none: a wiggle pressed in the gap, or a roll in the air the gap's flight came to after its wiggle
	-- (a roll `prev` was not in the middle of a wiggle's flight for: a new flight, `prev` having rolled or done nothing))
	local fromNone = SquirrelMotor.freshMove(prev, next, 2)
		or (SquirrelMotor.freshMove(prev, next, 1) and prev.trickKind ~= 2)
	if fromNone then
		pYaw, pReach = 0, 0
	end
	local nYaw, nReach = next.aimYaw or 0, next.aimReach or 0
	local trick: { Violation } = {}
	local judgedNext = next
	-- (on its footing, or with no move, a body has no re-aim (fieldCheck): the flight ended in the gap)
	local inFlight = not next.grounded and next.routeId == nil and next.trickKind ~= 0
	if inFlight and (nYaw ~= pYaw or nReach ~= pReach) then
		if prev.trickKind ~= 2 and next.trickKind ~= 2 and not fromNone then
			add(trick, "trick", 1, "a re-aim with no wiggle")
		end
		local span = math.max(dt, 0) + P.substep
		if
			math.abs(nYaw - pYaw) > P.trickYawRate * span + 1e-4
			or math.abs(nReach - pReach) > P.trickReachRate * span + 1e-4
		then
			add(trick, "trick", 1, `re-aimed {nYaw - pYaw} rad and {nReach - pReach} in {dt} s`)
		end
		judgedNext = SquirrelMotor.unaim(next, pYaw, pReach)
		-- (the height: the re-aim's vertical speed may have changed anywhere in the gap, so the body lies up to its change
		-- x dt off the unaimed arc, that way only: the part of `next`'s height off the arc that way is taken off)
		local up = judgedNext.vy - next.vy -- (what was undone: the re-aim gave next.vy - judgedNext.vy)
		local give = -up * dt
		local arcY = prev.y + (prev.vy + judgedNext.vy) / 2 * dt
		local off = math.clamp(next.y - arcY, math.min(0, give), math.max(0, give))
		judgedNext.y = next.y - off
		gapAim.across = math.abs(nYaw - pYaw)
			+ math.max(
				0,
				SquirrelMotor.aimScale(nReach, P.trickOutPeak) / SquirrelMotor.aimScale(pReach, P.trickOutPeak) - 1
			)
		gapAim.up = math.abs(up)
	end
	local out, used, pounce, judged = envelopeCore(prev, judgedNext, dt, world, boosted, lastGrab, chained)
	gapAim.across, gapAim.up = 0, 0
	if
		#out > 0
		and not inFlight
		and prev.trickKind ~= 1
		and not prev.grounded
		and prev.routeId == nil
		and prev.attackWindow <= 0
	then
		-- (the flight `prev` was in ended in the gap (a landing, a rail, a pounce, or a new flight after a hidden
		-- landing), and a wiggle's re-aim may have run in it: `prev`'s own, or one pressed in the gap (once a flight: none
		-- yet at `prev`), down to full in or back to none, so the arc from `prev` came down sooner or later than the
		-- server's. The move is judged from `prev` with its vertical speed given that push, each way, and the first a
		-- clean judgement takes stands; found by the honest lossy runs: a wiggle, a pull-in, a landing and a leap hidden
		-- in a 0.4 s loss. Costs an envelope or two, only on a packet that already has a violation)
		-- (no more than the re-aim's own rate brings in the gap: trickDown x trickReachRate x dt at most)
		local r = math.min(pReach, 0)
		local most = P.trickDown * math.min(1, P.trickReachRate * dt)
		local down = math.max(SquirrelMotor.aimDown(-1) - SquirrelMotor.aimDown(r), -most)
		local up = math.min(-SquirrelMotor.aimDown(r), most)
		for _, extra in { down, up } do
			if extra ~= 0 then
				local p2 = table.clone(prev)
				p2.vy += extra
				local o2, u2, po2, j2 = envelopeCore(p2, judgedNext, dt, world, boosted, lastGrab, chained)
				if #o2 == 0 then
					out, used, pounce, judged = o2, u2, po2, j2
					-- (a wiggle the gap hid, `prev` having none: the server's meter pays for it as for one it saw)
					judged.trickHidden = prev.trickKind == 0
					break
				end
			end
		end
	end
	for _, v in trick do
		table.insert(out, v)
	end
	if judgedNext ~= next then
		judged.vy += next.vy - judgedNext.vy
		local y = judged.y
		if y then
			judged.y = y + (next.y - judgedNext.y)
		end
		if nReach > pReach then
			judged.xz *= SquirrelMotor.aimScale(nReach, P.trickOutPeak) / SquirrelMotor.aimScale(pReach, P.trickOutPeak)
		end
	end
	return out, used, pounce, judged
end

return SquirrelMotor
