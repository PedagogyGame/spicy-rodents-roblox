--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Animation.Liveliness
-- The life a clip cannot give (owner 2026-11-11, of the squirrel seen from behind: "rigid, unalive").
-- A clip plays the same way whatever the body is doing; an animal answers its own movement. This is a
-- layer of small joint offsets on top of whatever clip a hero squirrel (or the Spicy Rodent) is playing,
-- made from how its root moves:
--   * a turn: the spine bends into it while the pelvis counter-turns (a C about the middle of the body, so
--     the paws stay near where the clip put them), the shoulders bank into it more the faster the body
--     goes, the head turns into it first and stays level, and the tail is left behind: it keeps pointing
--     where the body came from, the bend runs from its root to its tip, and it springs back past the
--     middle when the turn ends;
--   * a stop: the body dips nose-down over its fore paws (which fold to stay on the ground), the back
--     rounds, the tail is thrown up and over and settles with an overshoot; a start does the reverse, less;
--   * a leap: the body pitches along its flight (nose up rising, nose down falling), the back stretches on
--     the way up, the tail trails the fall; the landing squashes it (the root drops, all four legs fold,
--     the back rounds) and the tail whips down and recovers;
--   * a slope or a kerb: the body pitches with the ground it is running over;
--   * at speed the tail streams: a ripple runs down it, wider the faster the body goes;
--   * breathing, which quickens after a sprint and when out of fumes;
--   * standing still, the ordinary squirrel flicks an ear, flicks its tail tip, flags its tail and glances
--     about. The Spicy Rodent has its own twitches (Animation/Creep) and gets none of these; the two layers
--     are joint offsets that add (onto), and twitch() says how much of a head jerk shows while it runs.
-- Unlike Creep this has state: every answer is a damped spring, so it lags, overshoots and settles. The
-- springs are solved exactly over substeps of a fixed length and what comes in is taken in a straight
-- line between frames, so the motion does not depend on the frame rate. Every angle is bounded (LIMIT): no
-- input can fold the body. Nothing here moves the body: it never feeds back into the motor.
-- Pure Luau (no engine; Lune-tested). Angles are radians on the rig's own axes (bones rest unrotated: +X
-- right, +Y up, -Z ahead): rx + lifts the nose of a bone that points ahead and lowers a tail segment, ry +
-- turns to the left, rz + rolls the left side down.
-- Interface: new(seed, rig?) -> State; observe(state, sample, dt) -> Input (the root's pose -> rates);
--   step(state, input, dt) -> Pose; frame(state, sample, dt) -> Pose? (observe then step; nil when far);
--   onto(layers, pose) -> layers (adds a pose onto another layer's); twitch(state) -> 0..1;
--   Pose = { [bone] = { rx, ry, rz } or { rx, ry, rz, tx, ty, tz } } (only Root carries an offset, studs:
--   Bone.Transform = clip pose * CFrame.new(tx, ty, tz) * CFrame.Angles(rx, ry, rz)); P, LIMIT, RANGE.

local Liveliness = {}

-- What a driver reads off a body each frame: the root's pose as CFrame:ToOrientation() gives it.
export type Sample = {
	x: number,
	y: number,
	z: number,
	pitch: number, -- nose up
	yaw: number, -- + to the left
	roll: number, -- + left side down
	speed: number, -- studs/s the animation is told (the motor's own speed for a held body)
	mode: string, -- "ground" | "trunk" | "rail" | "air"
	stalk: boolean?,
	winded: boolean?, -- out of fumes
	coarse: boolean?, -- the pose arrives in steps (a body the server moves): everything is smoothed longer
	time: number?, -- the server's clock: the idle flicks are the same on every client
	far: boolean?, -- too far from the camera to see any of this
}

export type Input = {
	speed: number, -- studs/s the animation is told
	pace: number?, -- studs/s the body is seen to move over its surface (speed, when not given)
	yawRate: number, -- rad/s, + to the left
	vy: number, -- studs/s, + up
	mode: string,
	pitch: number?, -- the drawn root's nose-up pitch and roll: the head stays level against them, and a
	roll: number?, -- body standing on end (on a trunk) does not answer turns
	landed: number?, -- it landed this frame, this fast (studs/s); found from mode and vy when not given
	stalk: boolean?,
	winded: boolean?,
	coarse: boolean?,
	time: number?,
}

export type Pose = { [string]: { number } }

export type State = {
	seed: number,
	calm: boolean, -- the ordinary squirrel: idle flicks and a resting breath (the rodent has Creep's)
	live: boolean,
	clock: number,
	-- observe: the last root pose
	seen: boolean,
	ox: number,
	oy: number,
	oz: number,
	oyaw: number,
	input: Input,
	-- the last raw input (inputs are taken in a straight line across the substeps of a frame)
	inYaw: number,
	inPace: number,
	inVy: number,
	mode: string,
	-- smoothed input
	w: number, -- yaw rate
	wHead: number, -- yaw rate, smoothed less (the head goes first)
	pace: number,
	accel: number, -- studs/s^2 along the heading
	vy: number,
	speed: number, -- told speed, smoothed (twitch, effort)
	-- springs: value and velocity
	bend: number,
	bendV: number,
	head: number,
	headV: number,
	lean: number,
	leanV: number,
	tilt: number,
	tiltV: number,
	flight: number,
	flightV: number,
	dip: number,
	dipV: number,
	heave: number,
	heaveV: number,
	arch: number,
	archV: number,
	-- the tail: per segment, what reaches it of the turn and of the lift, and its two springs
	tailTurn: { number },
	tailLift: { number },
	tailYaw: { number },
	tailYawV: { number },
	tailPitch: { number },
	tailPitchV: { number },
	-- slow things
	air: number, -- 0 on a surface .. 1 in the air (eased)
	still: number, -- 0 moving .. 1 standing (eased): how much of the idle flicks shows
	effort: number, -- 0 rested .. 1 out of breath
	breath: number, -- phase, radians
	ripple: number, -- phase, radians
	-- output: one array per bone, reused
	bones: { [string]: { number } },
	pose: Pose,
}

Liveliness.RANGE = 90 -- studs from the camera: beyond this a squirrel is a few pixels and gets none of it

-- Tuning (studs, seconds, radians). `omega` is a spring's natural frequency in rad/s and `zeta` its
-- damping (1 = no overshoot); `gain` turns what drives it into its target and `max` is where that target
-- levels off (softly: max * tanh(x / max)).
Liveliness.P = {
	rate = 240, -- substeps per second
	maxDt = 0.1, -- a longer frame is taken as this (a hitch never throws the springs)
	teleport = 200, -- studs/s: a root that moves faster than this was put there, it did not travel
	sprint = 33, -- studs/s: "a sprint" below (SquirrelMotor.params.sprint)
	-- seconds of smoothing of what comes in: { a body drawn every frame, a body the server moves in steps }
	smooth = {
		yaw = { 0.04, 0.22 },
		head = { 0.018, 0.22 },
		pace = { 0.03, 0.2 },
		accel = { 0.05, 0.25 },
		vy = { 0.04, 0.2 },
	},
	-- a turn (yaw rate, rad/s). A quarter turn of the mouse in 0.3 s is 5.1 rad/s at its peak.
	turn = {
		-- nose-up pitch (rad) from which the answer to a turn fades, and where it is gone (on a trunk)
		levelFrom = 0.5,
		levelTo = 1.1,
		bend = { gain = 0.1, max = 0.55, omega = 22, zeta = 0.7 }, -- chest against pelvis, about Y
		hips = 0.35, -- the share of the bend the pelvis takes, the other way
		share = { 0.2, 0.25, 0.3, 0.25 }, -- Spine1, Spine2, Spine3, Chest
		head = { gain = 0.07, max = 0.34, omega = 38, zeta = 0.8 }, -- neck and head, on top of the chest
		-- the shoulders' bank on top of the drawn body's lean; `slow` is the share of it at a standstill
		lean = { gain = 0.03, max = 0.22, omega = 16, zeta = 0.65, slow = 0.35 },
		keepLevel = 0.8, -- the share of the body's roll the head takes back
	},
	-- speeding up and slowing down (studs/s^2 along the heading). A stop from a sprint peaks near -200.
	brake = {
		dip = { gain = 0.0009, down = 0.17, up = 0.06, omega = 14, zeta = 0.33 }, -- root pitch, nose down
		arch = { gain = 0.0017, max = 0.3, omega = 16, zeta = 0.45 }, -- the back rounds
		heave = { gain = 0.00028, max = 0.05 }, -- and the body sinks, studs
		headLevel = 0.7, -- the share of the dip the head takes back
		rail = 0.6, -- how much of it shows on a branch or a wire, and on a trunk
		trunk = 0.3,
	},
	-- the ground under a running body: the root pitches with the slope it is seen to climb or descend
	tilt = {
		share = 0.85, -- of the slope
		max = 0.45,
		minPace = 6, -- studs/s under which a slope is read as if at this pace (a creep does not rear)
		omega = 14,
		zeta = 0.9,
	},
	-- the flight of a leap: the root pitches along it, nose up rising and nose down falling
	flight = {
		share = 0.5, -- of the flight's angle
		max = 0.32,
		minPace = 10,
		omega = 20,
		zeta = 0.8,
		headLevel = 0.5, -- the share the head takes back (it looks where it is going)
	},
	-- a landing (impact, studs/s; a full leap comes down at 31, the pounce's hop at 7)
	land = {
		cap = 40,
		heave = 0.1, -- studs/s of sink per studs/s of impact
		arch = 0.09, -- rad/s of rounding per studs/s
		tail = 0.05, -- rad/s the tail is thrown down, per studs/s
		omega = 16, -- (the drawn body is still easing down for a tenth of a second after the motor lands)
		zeta = 0.45,
		min = -0.14, -- the lowest the root is pushed, studs
		max = 0.04,
		stretch = 0.14, -- the back hollows by this while rising at 30 studs/s
	},
	-- the tail. Segment 1 is at the hips. `pass` is the time a movement of the root takes to reach the
	-- next segment (the bend runs down the tail).
	tail = {
		pass = 0.02,
		omegaRoot = 12, -- side to side: it catches up a quarter of a second late and swings once past
		omegaTip = 7,
		liftOmegaRoot = 11, -- up and down: a throw hangs and comes back past rest
		liftOmegaTip = 7,
		zeta = 0.25,
		-- left behind in a turn: seconds of lag per segment at the root and at the tip (the angle is the
		-- lag times the yaw rate), and where a segment stops
		lagRoot = 0.011,
		lagTip = 0.024,
		yawMax = 0.2,
		-- thrown up by braking (rad over the whole tail per studs/s^2), dragged low by a start
		brake = 0.0065,
		brakeMax = 1.0,
		start = 0.0008,
		startMax = 0.16,
		-- in the air it trails: a little low behind a rise, high behind a fall (rad over the whole tail
		-- per studs/s, and at most)
		rise = 0.006,
		riseMax = 0.16,
		fall = 0.014,
		fallMax = 0.4,
		liftShare = { 0.3, 0.22, 0.15, 0.11, 0.08, 0.06, 0.05, 0.03 },
		-- the ripple of a tail streaming at speed: rad per segment at the tip at a sprint, its frequency
		-- (Hz) at rest and at a sprint, the phase from one segment to the next, and its share in pitch
		ripple = 0.075,
		rippleFrom = 8, -- studs/s: no ripple below
		rippleHz = { 2.1, 3.3 },
		rippleStep = 0.75,
		ripplePitch = 0.45,
	},
	-- breathing: a calm breath and a pant (Hz; radians of rise of the back), how long a sprint takes to
	-- leave it out of breath and how long it takes to get it back (s), and how much shows at a run
	breath = {
		calmHz = 1.15,
		pantHz = 3.4,
		calm = 0.014,
		pant = 0.06,
		tire = 3.2,
		recover = 7,
		windedRate = 2.5, -- 1/s toward out of breath while winded
		sprintAbove = 26, -- studs/s
		runShare = 0.35,
		runFrom = 2,
		runTo = 14,
		heave = 0.012, -- studs the body rises with a pant
	},
	-- standing still (the ordinary squirrel): seconds per slot and the chance that it happens in one
	idle = {
		still = 0.6, -- studs/s under which it stands
		settle = 1.6, -- 1/s the flicks come in after a stop
		leave = 9, -- 1/s they go when it moves
		ear = { every = 1.7, chance = 0.5 },
		tip = { every = 2.3, chance = 0.55 }, -- the tail tip
		flag = { every = 6.1, chance = 0.4 }, -- a burst of tail flagging
		glance = { every = 3.7, chance = 0.5 }, -- a quick look to one side, held
	},
	-- the Spicy Rodent's head jerks while it runs: all of one up to `from` studs/s (a run), `least` of one at `to`
	twitch = { from = 18, to = 33, least = 0.5 },
	-- legs: radians about X of Upper, Lower, Foot and Toe per stud a paw must come up toward the body to
	-- stay on the ground (measured on the built rig at its standing pose; the sum is 0, so the sole stays
	-- flat), and how far a paw is folded or let down at most
	fold = {
		fore = { -3.1, 5.0, 2.5, -4.4 },
		hind = { -0.04, -0.89, 2.77, -1.84 },
		max = 0.14,
		min = -0.03,
		dead = 0.003, -- studs under which the legs are left alone
		rate = 14, -- 1/s the legs take the ground again after a landing
		-- studs a paw goes down per radian of nose-up pitch of the root, the pelvis and the four spine
		-- bones (the rig's own lengths: the fore paws are 0.585 ahead of the hind toes, which are under
		-- the root)
		foreRoot = 0.585,
		foreHips = 0.985,
		foreSpine = { 0.765, 0.545, 0.345, 0.145 },
		hindHips = 0.4,
	},
}

-- What no input can exceed, per bone: { rx, ry, rz } (and the root's drop and rise, studs).
Liveliness.LIMIT = {
	root = { 0.45, 0, 0 },
	rootDown = 0.15,
	rootUp = 0.05,
	hips = { 0.2, 0.2, 0 },
	spine = { 0.14, 0.17, 0.07 },
	neck = { 0.25, 0.36, 0.24 },
	ear = { 0.5, 0, 0.5 },
	tail = { 0.5, 0.3, 0 }, -- a tail segment is raised by at most the first, and lowered by tailDown
	tailDown = 0.24,
	leg = { 0.7, 0, 0 },
}

local P = Liveliness.P
local LIMIT = Liveliness.LIMIT
local TAIL = 8
local SPINE = { "Spine1", "Spine2", "Spine3", "Chest" }
local LEGS = {
	{ "FrontL_Upper", "FrontL_Lower", "FrontL_Foot", "FrontL_Toe" },
	{ "FrontR_Upper", "FrontR_Lower", "FrontR_Foot", "FrontR_Toe" },
	{ "BackL_Upper", "BackL_Lower", "BackL_Foot", "BackL_Toe" },
	{ "BackR_Upper", "BackR_Lower", "BackR_Foot", "BackR_Toe" },
}
local BREATH = { 0, 0.6, 0.4, -1 } -- the share of a breath each spine bone takes (they sum to 0)
local TAILS: { string } = {}
for i = 1, TAIL do
	TAILS[i] = `Tail{i}`
end

local function zeros(n: number): { number }
	return table.create(n, 0)
end

-- scratch: the tail segments' spring coefficients and lags for the frame being solved
local SA, SB, SC, SD, LAG = zeros(TAIL), zeros(TAIL), zeros(TAIL), zeros(TAIL), zeros(TAIL)
local PA, PB, PC, PD = zeros(TAIL), zeros(TAIL), zeros(TAIL), zeros(TAIL)

function Liveliness.new(seed: number, rig: string?): State
	return {
		seed = seed,
		calm = rig ~= "rodent",
		live = false,
		clock = 0,
		seen = false,
		ox = 0,
		oy = 0,
		oz = 0,
		oyaw = 0,
		input = { speed = 0, yawRate = 0, vy = 0, mode = "ground" },
		inYaw = 0,
		inPace = 0,
		inVy = 0,
		mode = "ground",
		w = 0,
		wHead = 0,
		pace = 0,
		accel = 0,
		vy = 0,
		speed = 0,
		bend = 0,
		bendV = 0,
		head = 0,
		headV = 0,
		lean = 0,
		leanV = 0,
		tilt = 0,
		tiltV = 0,
		flight = 0,
		flightV = 0,
		dip = 0,
		dipV = 0,
		heave = 0,
		heaveV = 0,
		arch = 0,
		archV = 0,
		tailTurn = zeros(TAIL),
		tailLift = zeros(TAIL),
		tailYaw = zeros(TAIL),
		tailYawV = zeros(TAIL),
		tailPitch = zeros(TAIL),
		tailPitchV = zeros(TAIL),
		air = 0,
		still = 0,
		effort = 0,
		breath = seed % 6.283,
		ripple = (seed * 1.7) % 6.283,
		bones = {},
		pose = {},
	}
end

-- A hash of (slot, salt, seed) in [0, 1) (Animation/Creep's).
local function rnd(slot: number, salt: number, seed: number): number
	local x = math.sin(slot * 127.1 + salt * 311.7 + seed * 74.7) * 43758.5453
	return x - math.floor(x)
end

local function smooth(a: number, b: number, x: number): number
	local k = math.clamp((x - a) / (b - a), 0, 1)
	return k * k * (3 - 2 * k)
end

-- x, levelling off at +-max
local function soft(x: number, max: number): number
	return max * math.tanh(x / max)
end

-- 0 outside [a, a + d]; inside, up in `rise` seconds, held, down in `fall` seconds.
local function held(t: number, a: number, d: number, rise: number, fall: number): number
	local u = t - a
	if u <= 0 or u >= d then
		return 0
	end
	if u < rise then
		return smooth(0, rise, u)
	elseif u > d - fall then
		return smooth(0, fall, d - u)
	end
	return 1
end

-- The movement of one kind in the slot that holds time t: when it starts and how long it lasts, and two
-- of the slot's own random numbers; nil when nothing happens in this slot.
local function slotOf(
	t: number,
	seed: number,
	kind: { every: number, chance: number },
	salt: number,
	minLen: number,
	maxLen: number
): (number?, number, number, number)
	local slot = math.floor(t / kind.every)
	if rnd(slot, salt, seed) >= kind.chance then
		return nil, 0, 0, 0
	end
	local length = minLen + (maxLen - minLen) * rnd(slot, salt + 1, seed)
	local start = slot * kind.every + rnd(slot, salt + 2, seed) * math.max(kind.every - length, 0)
	return start, length, rnd(slot, salt + 3, seed), rnd(slot, salt + 4, seed)
end

-- A damped spring toward a target that holds still for h seconds, solved exactly:
--   x' = target + a * (x - target) + b * v;  v' = c * (x - target) + d * v
local function spring(omega: number, zeta: number, h: number): (number, number, number, number)
	local e = math.exp(-zeta * omega * h)
	if zeta >= 1 then
		e = math.exp(-omega * h)
		return e * (1 + omega * h), e * h, -e * omega * omega * h, e * (1 - omega * h)
	end
	local wd = omega * math.sqrt(1 - zeta * zeta)
	local c, s = math.cos(wd * h), math.sin(wd * h)
	local k = zeta * omega / wd
	return e * (c + k * s), e * s / wd, -e * omega * omega * s / wd, e * (c - k * s)
end

local function wrap(a: number): number
	return math.atan2(math.sin(a), math.cos(a))
end

-- The rates step() wants, from the root's pose this frame and last: how fast it turns, climbs and covers
-- its surface. A root that was put somewhere (a teleport, a recovery, a body that comes back into view)
-- has no rate that frame.
function Liveliness.observe(st: State, s: Sample, dt: number): Input
	local input = st.input
	local yawRate, vy, pace = 0, 0, s.speed
	if st.seen and dt > 0 then
		local dx, dy, dz = s.x - st.ox, s.y - st.oy, s.z - st.oz
		local moved = math.sqrt(dx * dx + dy * dy + dz * dz)
		if moved <= P.teleport * dt then
			yawRate = wrap(s.yaw - st.oyaw) / dt
			vy = dy / dt
			-- over the ground, the distance covered along it; on a trunk or a rail, along that
			pace = (if s.mode == "ground" or s.mode == "air" then math.sqrt(dx * dx + dz * dz) else moved) / dt
		else
			st.live = false -- the springs start again from rest
		end
	end
	st.seen = true
	st.ox, st.oy, st.oz, st.oyaw = s.x, s.y, s.z, s.yaw
	input.speed = s.speed
	input.pace = pace
	input.yawRate = yawRate
	input.vy = vy
	input.mode = s.mode
	input.pitch = s.pitch
	input.roll = s.roll
	input.landed = nil
	input.stalk = s.stalk
	input.winded = s.winded
	input.coarse = s.coarse
	input.time = s.time
	return input
end

local function rest(st: State, input: Input)
	st.live = true
	st.inYaw, st.inPace, st.inVy = input.yawRate, input.pace or input.speed, input.vy
	st.mode = input.mode
	st.w, st.wHead, st.pace, st.accel, st.vy = input.yawRate, input.yawRate, st.inPace, 0, input.vy
	st.speed = input.speed
	st.bend, st.bendV, st.head, st.headV, st.lean, st.leanV = 0, 0, 0, 0, 0, 0
	st.tilt, st.tiltV, st.flight, st.flightV, st.dip, st.dipV = 0, 0, 0, 0, 0, 0
	st.heave, st.heaveV, st.arch, st.archV = 0, 0, 0, 0
	for i = 1, TAIL do
		st.tailTurn[i], st.tailLift[i] = 0, 0
		st.tailYaw[i], st.tailYawV[i], st.tailPitch[i], st.tailPitchV[i] = 0, 0, 0, 0
	end
	st.air = if input.mode == "air" then 1 else 0
end

local function set(st: State, name: string, limit: { number }, rx: number, ry: number, rz: number): { number }
	local b = st.bones[name]
	if b == nil then
		b = { 0, 0, 0 }
		st.bones[name] = b
	end
	b[1] = math.clamp(rx, -limit[1], limit[1])
	b[2] = math.clamp(ry, -limit[2], limit[2])
	b[3] = math.clamp(rz, -limit[3], limit[3])
	st.pose[name] = b
	return b
end

-- One frame: the joint offsets for a body that moves as `input` says, dt seconds after the last call.
-- The table returned is the state's own (read it, do not keep it).
function Liveliness.step(st: State, input: Input, dt: number): Pose
	if dt <= 0 then
		return st.pose
	end
	dt = math.min(dt, P.maxDt)
	if input.yawRate ~= input.yawRate or input.vy ~= input.vy or input.speed ~= input.speed then
		return st.pose -- (a root with no pose this frame)
	end
	if not st.live then
		rest(st, input)
	end
	st.clock += dt
	local mode = input.mode
	local coarse = if input.coarse then 2 else 1
	local S = P.smooth
	local rawPace = input.pace or input.speed

	-- a landing: the body comes down and the surface stops it
	local landed = input.landed
	if landed == nil and st.mode == "air" and mode ~= "air" then
		landed = math.max(-st.vy, 0)
	end
	if landed and landed > 0 then
		local hit = math.min(landed, P.land.cap)
		st.heaveV -= hit * P.land.heave
		st.archV += hit * P.land.arch
		for i = 1, TAIL do
			st.tailPitchV[i] += hit * P.land.tail * P.tail.liftShare[i] * TAIL
		end
	end
	-- a change of mode is sharp (a leap leaves the ground at once): what comes in is not eased across it
	if st.mode ~= mode then
		st.inYaw, st.inPace, st.inVy = input.yawRate, rawPace, input.vy
	end
	st.mode = mode

	-- how much of each answer this body gives: a body standing on end does not answer turns; braking
	-- shows less on a rail and little on a trunk; in the air nothing is braced against a surface
	local level = 1 - smooth(P.turn.levelFrom, P.turn.levelTo, math.abs(input.pitch or 0))
	local onGround = mode == "ground"
	local inAir = mode == "air"
	local braced = if onGround then 1 elseif mode == "rail" then P.brake.rail elseif inAir then 0 else P.brake.trunk
	local leanSpeed = P.turn.lean.slow + (1 - P.turn.lean.slow) * math.clamp(rawPace / P.sprint, 0, 1.2)
	local settled = (1 - st.air) * (1 - st.air)

	local streamingWas = smooth(P.tail.rippleFrom, P.sprint, st.pace)
	local n = math.clamp(math.ceil(dt * P.rate - 1e-9), 1, math.ceil(P.maxDt * P.rate))
	local h = dt / n
	local kYaw = 1 - math.exp(-h / S.yaw[coarse])
	local kHead = 1 - math.exp(-h / S.head[coarse])
	local kPace = 1 - math.exp(-h / S.pace[coarse])
	local kAccel = 1 - math.exp(-h / S.accel[coarse])
	local kVy = 1 - math.exp(-h / S.vy[coarse])
	local kPass = 1 - math.exp(-h / P.tail.pass)
	local T, B, K = P.turn, P.brake, P.tail
	local ba, bb, bc, bd = spring(T.bend.omega, T.bend.zeta, h)
	local ha, hb, hc, hd = spring(T.head.omega, T.head.zeta, h)
	local la, lb, lc, ld = spring(T.lean.omega, T.lean.zeta, h)
	local ta, tb, tc, td = spring(P.tilt.omega, P.tilt.zeta, h)
	local fa, fb, fc, fd = spring(P.flight.omega, P.flight.zeta, h)
	local da, db, dc, dd = spring(B.dip.omega, B.dip.zeta, h)
	local va, vb, vc, vd = spring(P.land.omega, P.land.zeta, h)
	local aa, ab, ac, ad = spring(B.arch.omega, B.arch.zeta, h)
	for i = 1, TAIL do
		local f = (i - 1) / (TAIL - 1)
		SA[i], SB[i], SC[i], SD[i] = spring(K.omegaRoot + (K.omegaTip - K.omegaRoot) * f, K.zeta, h)
		PA[i], PB[i], PC[i], PD[i] = spring(K.liftOmegaRoot + (K.liftOmegaTip - K.liftOmegaRoot) * f, K.zeta, h)
		LAG[i] = K.lagRoot + (K.lagTip - K.lagRoot) * f
	end
	local yaw0, pace0, vy0 = st.inYaw, st.inPace, st.inVy
	local tailYaw, tailYawV, tailPitch, tailPitchV = st.tailYaw, st.tailYawV, st.tailPitch, st.tailPitchV
	local tailTurn, tailLift = st.tailTurn, st.tailLift

	for j = 1, n do
		local u = j / n
		local yawRate = yaw0 + (input.yawRate - yaw0) * u
		local paceIn = pace0 + (rawPace - pace0) * u
		local vyIn = vy0 + (input.vy - vy0) * u
		-- what comes in, smoothed
		st.w += (yawRate - st.w) * kYaw
		st.wHead += (yawRate - st.wHead) * kHead
		local before = st.pace
		st.pace += (paceIn - st.pace) * kPace
		st.accel += ((st.pace - before) / h - st.accel) * kAccel
		st.vy += (vyIn - st.vy) * kVy
		local w = st.w * level
		local accel = st.accel * braced
		local slowing = math.max(-accel, 0)

		-- the turn
		local x = st.bend - soft(T.bend.gain * w, T.bend.max)
		st.bend, st.bendV = st.bend - x + ba * x + bb * st.bendV, bc * x + bd * st.bendV
		x = st.head - soft(T.head.gain * st.wHead * level, T.head.max)
		st.head, st.headV = st.head - x + ha * x + hb * st.headV, hc * x + hd * st.headV
		x = st.lean - soft(T.lean.gain * w * leanSpeed, T.lean.max)
		st.lean, st.leanV = st.lean - x + la * x + lb * st.leanV, lc * x + ld * st.leanV

		-- along its path: the slope under it (not while a landing is still arriving), or its flight
		local slope, flight = 0, 0
		if inAir then
			flight = math.clamp(
				P.flight.share * math.atan2(st.vy, math.max(st.pace, P.flight.minPace)),
				-P.flight.max,
				P.flight.max
			)
		elseif onGround then
			slope = settled
				* math.clamp(
					P.tilt.share * math.atan2(st.vy, math.max(st.pace, P.tilt.minPace)),
					-P.tilt.max,
					P.tilt.max
				)
		end
		x = st.tilt - slope
		st.tilt, st.tiltV = st.tilt - x + ta * x + tb * st.tiltV, tc * x + td * st.tiltV
		x = st.flight - flight
		st.flight, st.flightV = st.flight - x + fa * x + fb * st.flightV, fc * x + fd * st.flightV

		-- braking and starting
		x = st.dip - math.clamp(B.dip.gain * accel, -B.dip.down, B.dip.up)
		st.dip, st.dipV = st.dip - x + da * x + db * st.dipV, dc * x + dd * st.dipV
		x = st.heave + soft(B.heave.gain * slowing, B.heave.max)
		st.heave, st.heaveV = st.heave - x + va * x + vb * st.heaveV, vc * x + vd * st.heaveV
		local stretch = if inAir then P.land.stretch * math.clamp(st.vy / 30, 0, 1) else 0
		x = st.arch - (soft(B.arch.gain * slowing, B.arch.max) - stretch)
		st.arch, st.archV = st.arch - x + aa * x + ab * st.archV, ac * x + ad * st.archV

		-- the tail: what the root does reaches segment after segment, and each answers on its own spring
		local lift = if accel < 0 then soft(K.brake * slowing, K.brakeMax) else -math.min(K.start * accel, K.startMax)
		if inAir then
			lift += if st.vy > 0 then -math.min(K.rise * st.vy, K.riseMax) else math.min(-K.fall * st.vy, K.fallMax)
		end
		local turnIn, liftIn = w, lift
		for i = 1, TAIL do
			tailTurn[i] += (turnIn - tailTurn[i]) * kPass
			tailLift[i] += (liftIn - tailLift[i]) * kPass
			turnIn, liftIn = tailTurn[i], tailLift[i]
			local sa, sb, sc, sd = SA[i], SB[i], SC[i], SD[i]
			x = tailYaw[i] + soft(LAG[i] * turnIn, K.yawMax)
			tailYaw[i], tailYawV[i] = tailYaw[i] - x + sa * x + sb * tailYawV[i], sc * x + sd * tailYawV[i]
			x = tailPitch[i] + liftIn * K.liftShare[i] -- (a raised segment has a negative rx)
			tailPitch[i], tailPitchV[i] =
				tailPitch[i] - x + PA[i] * x + PB[i] * tailPitchV[i], PC[i] * x + PD[i] * tailPitchV[i]
		end
	end
	st.inYaw, st.inPace, st.inVy = input.yawRate, rawPace, input.vy
	st.heave = math.clamp(st.heave, P.land.min, P.land.max)

	-- slow things, once a frame (each is an exact exponential or a straight line in time)
	st.speed += (input.speed - st.speed) * (1 - math.exp(-dt / 0.1))
	st.air += ((if inAir then 1 else 0) - st.air) * (1 - math.exp(-dt * P.fold.rate))
	local standing = input.speed < P.idle.still and rawPace < P.idle.still * 3 and not inAir
	st.still = if standing
		then st.still + (1 - st.still) * (1 - math.exp(-dt * P.idle.settle))
		else st.still * math.exp(-dt * P.idle.leave)
	local Br = P.breath
	local effortWas = st.effort
	if input.winded then
		st.effort += (1 - st.effort) * (1 - math.exp(-dt * Br.windedRate))
	elseif input.speed > Br.sprintAbove then
		st.effort = math.min(1, st.effort + dt / Br.tire)
	else
		st.effort = math.max(0, st.effort - dt / Br.recover)
	end
	-- (the phases move at the mean of the frame's two rates, so they do not depend on its length)
	local effort = 0.5 * (effortWas + st.effort)
	st.breath = (st.breath + dt * 2 * math.pi * (Br.calmHz + (Br.pantHz - Br.calmHz) * effort)) % (2 * math.pi)
	local streaming = smooth(K.rippleFrom, P.sprint, st.pace)
	local stream = 0.5 * (streamingWas + streaming)
	st.ripple = (st.ripple + dt * 2 * math.pi * (K.rippleHz[1] + (K.rippleHz[2] - K.rippleHz[1]) * stream))
		% (200 * math.pi)

	-- the pose --------------------------------------------------------------------------------------------
	table.clear(st.pose)
	local bend, lean, arch, tilt = st.bend, st.lean, st.arch, st.tilt
	-- what pitches the body over its own paws: the dip of a stop and what is left of a flight's pitch
	local dip = st.dip + st.flight
	-- breathing: the back rises behind the shoulders, the chest takes it back (the fore paws stay), the
	-- head and the root of the tail nod with a pant
	local shows = 1 - (1 - Br.runShare) * smooth(Br.runFrom, Br.runTo, st.pace)
	local depth = ((if st.calm then Br.calm else 0) + (Br.pant - (if st.calm then Br.calm else 0)) * st.effort) * shows
	local breath = depth * (math.sin(st.breath) + 0.25 * math.sin(2 * st.breath))
	local pant = breath * st.effort
	local rise = st.heave + Br.heave * st.effort * shows * math.sin(st.breath)

	local root = set(st, "Root", LIMIT.root, tilt + dip, 0, 0)
	root[4], root[5], root[6] = 0, math.clamp(rise, -LIMIT.rootDown, LIMIT.rootUp), 0
	local hipsPitch = 0.5 * arch
	set(st, "Hips", LIMIT.hips, hipsPitch, -T.hips * bend, 0)
	local chestPitch = hipsPitch
	local foreDown = P.fold.foreRoot * dip + P.fold.foreHips * hipsPitch
	for i, name in SPINE do
		local b = set(st, name, LIMIT.spine, -0.25 * arch + BREATH[i] * breath, bend * T.share[i], lean * 0.25)
		chestPitch += b[1]
		foreDown += P.fold.foreSpine[i] * b[1]
	end

	-- the head: into the turn ahead of the chest; level against the body's roll, the dip and the flight
	local glanceYaw, glancePitch = 0, 0
	local earL, earR = 0, 0
	local still = if st.calm then st.still else 0
	local tm = input.time or st.clock
	if still > 0.01 then
		local start, length, a, b = slotOf(tm, st.seed, P.idle.glance, 60, 0.5, 1.7)
		if start then
			local k = held(tm, start, length, 0.09, 0.14) * still
			glanceYaw = (if a < 0.5 then -1 else 1) * (0.16 + 0.2 * b) * k * (if input.stalk then 0.5 else 1)
			glancePitch = (a * 2 - 1) * 0.07 * k
		end
		start, length, a = slotOf(tm, st.seed, P.idle.ear, 70, 0.09, 0.15)
		if start then
			local k = held(tm, start, length, 0.03, 0.05) * still
			if a < 0.5 then
				earL = k
			else
				earR = k
			end
		end
	end
	local roll = ((input.roll or 0) * level + lean) * T.keepLevel
	local nod = -B.headLevel * (st.dip + chestPitch) - P.flight.headLevel * st.flight + glancePitch - 0.3 * pant
	local look = st.head + glanceYaw
	set(st, "Neck", LIMIT.neck, 0.4 * nod, 0.4 * look, -0.4 * roll)
	set(st, "Head", LIMIT.neck, 0.6 * nod, 0.6 * look, -0.6 * roll)
	if earL > 0 then
		set(st, "EarL", LIMIT.ear, -0.2 * earL, 0, 0.42 * earL)
	end
	if earR > 0 then
		set(st, "EarR", LIMIT.ear, -0.2 * earR, 0, -0.42 * earR)
	end

	-- the tail: the springs, the ripple of a tail streaming at speed, and the idle flicks
	local tipStart, tipSign, flagStart, flagLen = nil :: number?, 1, nil :: number?, 0
	if still > 0.01 then
		local start, _, a = slotOf(tm, st.seed, P.idle.tip, 80, 0.3, 0.3)
		tipStart, tipSign = start, if a < 0.5 then -1 else 1
		if not input.stalk then
			flagStart, flagLen = slotOf(tm, st.seed, P.idle.flag, 90, 0.55, 0.8)
		end
	end
	for i = 1, TAIL do
		local f = i / TAIL
		local grow = f * math.sqrt(f)
		local phase = st.ripple - K.rippleStep * i
		local wave = K.ripple * streaming * grow
		local rx = tailPitch[i] + wave * K.ripplePitch * math.sin(phase * 1.31 + st.seed)
		local ry = tailYaw[i] + wave * (math.sin(phase) + 0.4 * math.sin(phase * 1.62 + st.seed))
		if i == 1 then
			rx += 0.5 * pant
		end
		if tipStart and i >= 5 then
			-- a flick of the tip: a kink that runs out through the last segments
			local u = (tm - tipStart - (i - 5) * 0.03) / 0.16
			if u > 0 and u < 1 then
				local k = (0.1 + 0.06 * (i - 5)) * math.sin(math.pi * u) * still
				ry += tipSign * k
				rx -= 0.5 * k
			end
		end
		if flagStart and i <= 4 then
			-- flagging: the whole tail beats forward and back a few times from its root
			local since = tm - flagStart
			local k = held(tm, flagStart, flagLen, 0.08, 0.2) * still
			rx -= k * (0.17 - 0.035 * (i - 1)) * math.sin(since * 2 * math.pi * 5.2 - 0.5 * (i - 1))
		end
		local b = set(st, TAILS[i], LIMIT.tail, math.min(rx, LIMIT.tailDown), ry, 0)
		b[1] = math.min(b[1], LIMIT.tailDown)
	end

	-- the legs keep the paws on the surface: whatever the offsets above do to the height of the shoulders
	-- and hips over it, the legs fold (or let down) by as much. Not in the air.
	local grounded = 1 - st.air
	local F = P.fold
	local fore = math.clamp(-(root[5] + foreDown) * grounded, F.min, F.max)
	local hind = math.clamp(-(root[5] + F.hindHips * hipsPitch) * grounded, F.min, F.max)
	fore -= math.clamp(fore, -F.dead, F.dead)
	hind -= math.clamp(hind, -F.dead, F.dead)
	for i, leg in LEGS do
		local s = if i <= 2 then fore else hind
		if s ~= 0 then
			local k = if i <= 2 then F.fore else F.hind
			-- the sole stays flat: the toes take back the pitch the body above them was given
			local flat = -(dip + (if i <= 2 then chestPitch else hipsPitch)) * grounded
			for j, name in leg do
				set(st, name, LIMIT.leg, k[j] * s + (if j == 4 then flat else 0), 0, 0)
			end
		end
	end
	return st.pose
end

-- observe, then step: what a driver calls with the root's pose each frame. A body too far to be seen gets
-- nothing (nil), and starts from rest when it comes near again.
function Liveliness.frame(st: State, s: Sample, dt: number): Pose?
	if s.far then
		st.seen, st.live, st.accel = false, false, 0
		return nil
	end
	return Liveliness.step(st, Liveliness.observe(st, s, dt), dt)
end

-- How much of one of the Spicy Rodent's head jerks (Animation/Creep's snap) shows now: all of it standing,
-- stalking and at a walk, less at a sprint, where the head is already thrown about by the run.
function Liveliness.twitch(st: State): number
	local W = P.twitch
	return 1 - (1 - W.least) * smooth(W.from, W.to, st.speed)
end

-- Add a pose onto another layer's joint offsets ({ [bone] = { rx, ry, rz } }, changed in place and
-- returned; the pose itself when there is nothing under it). Small angles on the same axes add.
function Liveliness.onto(layers: Pose, pose: Pose?): Pose
	if pose == nil then
		return layers
	end
	if next(layers) == nil then
		return pose
	end
	for name, r in pose do
		local under = layers[name]
		if under == nil then
			layers[name] = table.clone(r)
		else
			for k, v in r do
				under[k] = (under[k] or 0) + v
			end
		end
	end
	return layers
end

return Liveliness
