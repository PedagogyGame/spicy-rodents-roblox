--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Animation.AnimationDriver
-- D3: animation is local on every client. Each client creates its own Animator on every body it
-- can see (so no track ever replicates), picks the clip from what the body is doing, and keeps the
-- track running across a possession handoff: the same rule animates an AI body, another player's
-- body and one's own, so "mid-stride" is continuous by construction (BUILD_PLAN §1.5 step 5).
-- Humans: Roblox's own default R15 animations (the stock Animate script's idle 507766388, walk
-- 507777826, run 507767714, jump 507765000, fall 507767968; public, owned by Roblox, referenced not
-- uploaded; a seated driver plays the stock sit 2506281703) chosen by speed, the walk/run rate
-- scaled to the speed so feet do not slide.
-- Four-legged bodies (squirrel, Spicy Rodent, fox, deer): the procedural gait (Animation/Gait) on
-- their RigSpec Motor6Ds (leg swing, knee bend, body bob, head nod, tail sway) set every Stepped.
-- Speed is the body's observed speed (smoothed; horizontal for humans, 3D for animals so climbing
-- animates), which works the same for anchored AI bodies moved by the server and for client-owned
-- bodies. For AI bodies the server's `ClipT0` attribute aligns the clip phase across clients when a
-- track starts.
-- Visual root (owner playtest 2026-11-09: bodies bounced up and down and stood half in the grass):
-- the visible body hangs off the root through the Motor6D named Root, so its C0 carries a client-only
-- vertical offset and the root itself (the gameplay position the server sees) never moves.
--   * Height smoothing (settle): a critically damped follower with limited velocity feed-forward
--     tracks the rendered root height (read in RenderStepped, after physics), so slopes and climbs
--     are followed without lag while ground-sampling steps, kerbs, jitter and replication steps are
--     eased out; it rises faster than it settles, so feet do not hang in a kerb for long.
--   * Ground contact: AI bodies (anchored roots, placed on World/Height's analytic ground by the
--     server) standing near the terrain are lifted or lowered onto what is really under their feet: a
--     short downward ray from just above the feet, a few times a second, against collidable town parts
--     and the voxel terrain (whose surface can sit up to about a stud above the analytic height).
--     Possessed bodies stand on their own motor's raycast ground or Humanoid, so they get smoothing
--     only (people none); squirrels up trees and on roofs keep their route heights.
--   * Kinematic bodies (Controllers/KinematicPose: the held squirrel) draw their own eased pose, so
--     nothing is layered on it: no height smoothing, no probe; the stride phase advances at the motor's
--     cadence and the swing follows the motor's speed, never the observed displacement. Whatever
--     offset the body carried as an AI decays at v5.4's 23/s, the same rate the controller's drawn point
--     eases onto its own ground, so a possession hands over without a step.
-- Patients (owner 2026-11-10, the bite-to-hospital sequence): the server writes a Med attribute on a
-- bitten body (Server/Infection/InfectionService). An AI body with Med "down" (collapsed at a scene)
-- or "treated" (in a hospital bed) plays the stock sit clip and is lowered through the same
-- visual-root offset: sitting on the ground, or on the cot (Infection/HospitalLayout.BED.top above
-- the floor). The stock sit is a chair sit (knees bent, shins straight down), which on the ground put
-- everything below the knee under the pavement and on a cot through the mattress: the knees and
-- ankles are straightened after the Animator has written them (Stepped), so the legs lie flat in
-- front of the patient. A patient walked to the ambulance ("carried") keeps the usual walk. Someone
-- with the symptoms ("symptomatic") staggers: the visible body sways about the soles. A body a player
-- holds is never posed. Render/MedicalView draws the rest of the attribute (red eyes, hiding).
-- Walk or run: with one threshold a body moving at about that speed (a cured person walking home at
-- 9 studs/s, the ambulance crew at 8.6) flipped between the two clips many times a second, each flip
-- restarting a 0.2 s cross-fade: the observed speed ripples with the replication steps. The choice
-- now has a band (gaitClip) and its own slower speed (pace).
-- No side effects on require.
-- A sculpted hero squirrel (Server/Assets/HeroArt, attribute Hero) plays its own authored clips (owner
-- 2026-11-10: the run looked "rigid, unalive": the procedural gait only swings the legs under a stiff body,
-- while the authored run is a bounding gallop with the spine stretching and gathering and the tail
-- streaming and waving). heroClip picks the clip from what the body is doing (the kinematic controller's
-- mode for a held body; the root's attitude and speed for the others) and heroRate keeps the cycle in
-- step with the motor's stride. If a clip cannot be loaded the body falls back to the procedural gait.
-- Interface: start(opts) -> Driver; Driver.stop(); DEFAULT_CLIPS; newSettle(); settle(state, y, dt) (pure);
--   clipSpeed(speed, nominal?) -> playback speed (pure); gaitJoints(model) -> joints, tailCount;
--   heroClip(mode, speed, stalk, action?, was?, braking?) -> clip name (pure); heroRate(name, speed,
--   cadence?, length, airSeconds?) -> playback speed (pure); heroStart(name, action?) -> seconds (pure);
--   heroBraking(speed, slowing) -> boolean (pure); heroSettle(name, time, length, speed, slowing, rate) ->
--   playback speed (pure);
--   heroTracks(tracks, current, want, track, loop, rate, startAt?) -> clip now playing; HERO. The
--   Spicy Rodent's hero body also gets Animation/Creep's twitches on top:
--   heroLayers(rig, t, seed, live?) -> { [bone]: { rx, ry, rz } } (pure); creepSeed(name) -> seed (pure).
--   Every hero body near the camera also gets Animation/Liveliness (how it answers its own movement):
--   liveSample(cf, speed, mode, kin?, time, far) -> Liveliness.Sample (pure).
--   medPose(med, footDrop) -> { clip, drop, flat } (pure); gaitClip(current, pace, runAbove?) -> "walk" |
--   "run" (pure); pace(prev, inst, dt) -> studs/s (pure); sway(med, t, seed) -> roll, pitch (pure);
--   FLAT_JOINTS

local Gait = require("./Gait")
local Creep = require("./Creep")
local Liveliness = require("./Liveliness")
local KinematicPose = require("../Controllers/KinematicPose")
local Import = require("../Import")
local PossessionState =
	Import.shared("Actors/PossessionState") :: typeof(require("../../shared/Actors/PossessionState"))
local Height = Import.shared("World/Height") :: typeof(require("../../shared/World/Height"))
local HeroAssets = Import.shared("Actors/HeroAssets") :: typeof(require("../../shared/Actors/HeroAssets"))
local HospitalLayout =
	Import.shared("Infection/HospitalLayout") :: typeof(require("../../shared/Infection/HospitalLayout"))

export type ClipSet = {
	idle: string?,
	walk: string?,
	run: string?,
	jump: string?,
	fall: string?,
	sit: string?,
	nominalRun: number?,
	nominalWalk: number?,
}

export type Opts = {
	container: Instance, -- the folder whose child Models are bodies
	clips: { [string]: ClipSet }?, -- by Species attribute
	walkAbove: number?, -- studs/s (default 0.4)
	runAbove: number?, -- studs/s (default 9)
}

export type Driver = {
	stop: () -> (),
	bodies: () -> number,
}

-- `motor` is a Motor6D on a part-built puppet and a Bone on a skinned hero model: both carry Transform
type Joint = { motor: any, kind: string, leg: string?, index: number? }

type Entry = {
	body: Model,
	root: BasePart,
	animator: Animator?,
	humanoid: Humanoid?, -- seated in a car (SeatPart set): the sit clip, not a run at car speed
	species: string,
	tracks: { [string]: AnimationTrack },
	current: string?,
	lastPos: Vector3,
	speed: number,
	vy: number,
	-- procedural gait (animals)
	gait: Gait.Params?,
	joints: { Joint },
	tailN: number,
	phase: number,
	-- visual root: the Root Motor6D's C0, or the root-side Attachment of a Root AnimationConstraint
	rootJoint: Motor6D?,
	rootAttach: Attachment?,
	baseC0: CFrame,
	footDrop: number, -- studs from the root down to the soles at rest
	settle: Settle,
	fix: number, -- studs, the ground-contact correction now (eased)
	fixTarget: number,
	nextProbe: number,
	anchored: boolean,
	applied: number,
	kin: boolean, -- a kinematic controller drew this body last frame
	hero: { [string]: HeroAssets.Clip }?, -- a sculpted hero rig playing its authored clips
	mode: string, -- what a hero body is doing (heroClip's mode), for Animation/Liveliness
	-- what is layered on a hero's clips (heroLayers: Animation/Liveliness, and the Spicy Rodent's
	-- Animation/Creep): the bones by name, what the clip last gave each and what was last written to it
	-- (so an offset is never applied twice)
	creep: {
		seed: number,
		rig: string,
		live: Liveliness.State,
		bones: { [string]: any },
		base: { [any]: CFrame },
		wrote: { [any]: CFrame },
	}?,
	med: any, -- the body's Med attribute (a patient's pose)
	medConn: RBXScriptConnection?,
	drop: number, -- studs the pose lowers the body by, now (eased)
	pace: number, -- studs/s, smoothed more slowly than `speed`: only picks walk or run
	legs: { any }, -- the knee and ankle joints a sitting patient's legs are straightened at
	lean: number, -- 0..1: how much of the stagger sway is on (eased)
	roll: number, -- rad the visible body leans by now (about the soles)
	pitch: number,
}

-- The visual-height follower's state (AnimationDriver.newSettle): the visual height and velocity, and
-- rings of the last root heights (with their times) and short-baseline velocities.
export type Settle = {
	y: number,
	v: number,
	live: boolean,
	clock: number,
	hy: { number },
	ht: { number },
	head: number,
	vel: { number },
	vi: number,
}

local AnimationDriver = {}

-- Visual root tuning (studs, seconds, rad/s).
AnimationDriver.RISE = 30 -- omega while the visual body is below the root (catch up fast)
AnimationDriver.FALL = 12 -- omega while it is above (settle smoothly)
AnimationDriver.MAX_LAG = 0.6 -- the visual body never strays further than this from the root
AnimationDriver.SNAP = 6 -- a jump bigger than this in one frame is a teleport: no easing
AnimationDriver.PROBE_EVERY = 0.25
AnimationDriver.PROBE_RANGE = 320 -- only bodies this close to the camera are probed
AnimationDriver.PROBE_UP = 1.6 -- the ray starts this far above the soles (starts inside a hedge: ignored)
AnimationDriver.FIX_MIN = -0.75
AnimationDriver.FIX_MAX = 1.4
AnimationDriver.CLEARANCE = 0.04 -- soles rest this much above the surface found
AnimationDriver.NEAR_GROUND = 2 -- only soles this close to the terrain are probed (not squirrels up trees)
AnimationDriver.KIN_RATE = 23 -- 1/s: a kinematic body sheds its carried offset at v5.4's visual easing rate
AnimationDriver.SIT_SEAT = 1.35 -- studs from an R15 root down to what the sit clip sits on
AnimationDriver.POSE_RATE = 6 -- 1/s: how fast a patient sinks into (or rises out of) the pose
AnimationDriver.RUN_BAND = 1.5 -- studs/s either side of runAbove in which the walk or run clip is kept
AnimationDriver.PACE_TAU = 0.3 -- s: the smoothing of the speed that picks walk or run
AnimationDriver.SWAY_RATE = 3 -- 1/s: how fast the stagger comes on and goes
-- the R15 joints straightened on a sitting patient (Motor6Ds, or AnimationConstraints on newer rigs)
AnimationDriver.FLAT_JOINTS = table.freeze({ "LeftKnee", "RightKnee", "LeftAnkle", "RightAnkle" })

local SHORT, BASE, MEDIAN_N = 3, 12, 7 -- frames: short and long velocity baselines; median window
local scratch: { number } = table.create(MEDIAN_N, 0)

function AnimationDriver.newSettle(): Settle
	return {
		y = 0,
		v = 0,
		live = false,
		clock = 0,
		hy = table.create(BASE + 1, 0),
		ht = table.create(BASE + 1, 0),
		head = 1,
		vel = table.create(MEDIAN_N, 0),
		vi = 1,
	}
end

-- settle(state, y, dt): one frame of the visual-height follower towards the rendered root height y;
-- returns the offset (visual - root) to apply. Pure (Lune-tested; tuned against simulated slopes,
-- kerbs, drops, ground-sampling jitter, the squirrel motor's downhill hop seen through BodyDriver's
-- one-frame extrapolation, and network-update staircases). A critically damped spring (faster while
-- the body is below the root) with velocity feed-forward, so slopes and trunk climbs are followed
-- without lag; the feed-forward is minmod(median of 3-frame velocities, 12-frame velocity): a
-- one-frame step or a back-and-forth jitter feeds nothing forward, so it is eased, not overshot.
function AnimationDriver.settle(st: Settle, y: number, dt: number): number
	local ring = BASE + 1
	if not st.live or dt <= 0 or math.abs(y - st.y) > AnimationDriver.SNAP then
		st.y, st.v, st.live = y, 0, true
		for i = 1, ring do
			st.hy[i], st.ht[i] = y, st.clock
		end
		for i = 1, MEDIAN_N do
			st.vel[i] = 0
		end
		return 0
	end
	st.clock += dt
	st.head = st.head % ring + 1
	st.hy[st.head], st.ht[st.head] = y, st.clock
	local s = (st.head - 1 - SHORT) % ring + 1
	local b = (st.head - 1 - BASE) % ring + 1
	local ds, db = st.clock - st.ht[s], st.clock - st.ht[b]
	st.vi = st.vi % MEDIAN_N + 1
	st.vel[st.vi] = if ds > 0 then (y - st.hy[s]) / ds else 0
	table.move(st.vel, 1, MEDIAN_N, 1, scratch)
	table.sort(scratch)
	local short = scratch[(MEDIAN_N + 1) // 2]
	local long = if db > 0 then (y - st.hy[b]) / db else 0
	local rv = if short * long > 0 then (if math.abs(short) < math.abs(long) then short else long) else 0
	-- the target moves at rv through the frame; semi-implicit substeps (stable for any frame time)
	local w = if st.y < y then AnimationDriver.RISE else AnimationDriver.FALL
	local span = math.min(dt, 0.1)
	local n = math.clamp(math.ceil(span * 480), 1, 48)
	local h = span / n
	local yv, v = st.y, st.v
	for j = 1, n do
		local target = y - rv * (span - j * h)
		v += (w * w * (target - yv) + 2 * w * (rv - v)) * h
		yv += v * h
	end
	local off = math.clamp(yv - y, -AnimationDriver.MAX_LAG, AnimationDriver.MAX_LAG)
	st.y, st.v = y + off, v
	return off
end

-- Roblox's stock R15 animations (public, owned by Roblox: the default Animate script's IDs). The
-- animals use the procedural Gait (the S7 test clip 92005834447457 stays for the clip pipeline only).
-- start() falls back to this table, so it must exist: without it every body's add() and the whole
-- per-frame step throw (tests/unit/anim_gait.spec.luau pins it).
AnimationDriver.DEFAULT_CLIPS = {
	human = {
		idle = "rbxassetid://507766388",
		walk = "rbxassetid://507777826",
		run = "rbxassetid://507767714",
		jump = "rbxassetid://507765000",
		fall = "rbxassetid://507767968",
		sit = "rbxassetid://2506281703", -- the stock R15 Animate sit
		-- The stock R15 walk and run are authored for Roblox's default 16 st/s: Roblox's own Animate
		-- script plays them at speed / 16. This said 6 for the walk, so a townsperson strolling at 2 to
		-- 4 st/s cycled their legs nearly three times too fast (owner 2026-11-10: "people wandering
		-- around who seem to sort of always be running in place").
		nominalWalk = 16,
		nominalRun = 16,
	},
} :: { [string]: ClipSet }

-- medPose(med, footDrop): how an AI body with this Med attribute is posed: the clip to play (nil =
-- the usual choice by speed), how far the visible body is lowered (studs), and whether the legs are
-- laid flat (FLAT_JOINTS straightened). `footDrop` is the body's root height above its soles. A
-- collapsed person sits on the ground; a patient in a bed sits up on the cot; both with their legs
-- out in front of them. Anything else (symptomatic, walked to the ambulance, in transit, healthy)
-- keeps its usual animation.
function AnimationDriver.medPose(med: any, footDrop: number): { clip: string?, drop: number, flat: boolean }
	if med == "down" then
		return { clip = "sit", drop = math.max(0, footDrop - AnimationDriver.SIT_SEAT), flat = true }
	elseif med == "treated" then
		return {
			clip = "sit",
			drop = math.max(0, footDrop - AnimationDriver.SIT_SEAT - HospitalLayout.BED.top),
			flat = true,
		}
	end
	return { clip = nil, drop = 0, flat = false }
end

-- gaitClip(current, pace, runAbove?): walk or run for a body moving at `pace` studs/s, given the clip
-- it plays now: run from RUN_BAND above the threshold, walk from RUN_BAND below it, and in between
-- whatever is playing already (anything but "run" counts as walking).
function AnimationDriver.gaitClip(current: string?, pace: number, runAbove: number?): string
	local mid = runAbove or 9
	if pace >= mid + AnimationDriver.RUN_BAND then
		return "run"
	elseif pace < mid - AnimationDriver.RUN_BAND then
		return "walk"
	end
	return if current == "run" then "run" else "walk"
end

-- pace(prev, inst, dt): the speed that picks walk or run, one frame on: `inst` (this frame's observed
-- speed) smoothed over PACE_TAU. A body whose position arrives 10 to 20 times a second is seen to
-- move in steps; over 0.3 s the ripple that leaves is narrower than the band.
function AnimationDriver.pace(prev: number, inst: number, dt: number): number
	return prev + (inst - prev) * math.min(1, dt / AnimationDriver.PACE_TAU)
end

-- sway(med, t, seed): the stagger of someone with the symptoms: how far the visible body leans to
-- the side (roll) and forward (pitch), in radians, at time t. A slow side-to-side sway with a quicker
-- wobble on it, about four degrees at most; `seed` keeps two people out of step. 0, 0 for anyone else.
function AnimationDriver.sway(med: any, t: number, seed: number): (number, number)
	if med ~= "symptomatic" then
		return 0, 0
	end
	local roll = 0.05 * math.sin(t * 4.7 + seed) + 0.02 * math.sin(t * 9.4 + seed * 2.3)
	local pitch = 0.03 * math.sin(t * 3.1 + seed * 1.7)
	return roll, pitch
end

-- Playback speed of a walk or run clip authored for `nominal` st/s on a body moving at `speed`: the
-- feet keep pace with the ground. The floor is low (a slow stroll is a slow cycle, never legs that
-- run under a body that barely moves); other clips play at their own speed.
function AnimationDriver.clipSpeed(speed: number, nominal: number?): number
	if nominal == nil or nominal <= 0 then
		return 1
	end
	return math.clamp(speed / nominal, 0.1, 2.5)
end

-- Which authored clip a hero squirrel shows: `mode` is "ground" | "trunk" | "rail" | "air", `speed` in
-- studs/s, `stalk` whether it is creeping.
AnimationDriver.HERO = {
	still = 0.5, -- studs/s under which it stands (or hangs on a trunk)
	runAbove = 9, -- studs/s: a walk below, the bounding run above
	-- studs travelled per clip cycle when no motor cadence is known (v5.4: one bound per 5.5 studs). The
	-- clips are authored to these (tools/blender/heroes/clips_squirrel.py, its *_TRAVEL numbers): a planted
	-- paw goes back under the body at exactly this much a cycle, so it stays where it was put. Wire is two
	-- small bounds a cycle (6.9 studs: at the rail's 18 studs/s that is the fastest the clip may play)
	stride = { Run = 5.5, Walk = 2.4, Climb = 3.6, Wire = 6.9, Stalk = 2.2 } :: { [string]: number },
	minRate = 0.3,
	maxRate = 2.6, -- faster than this the legs blur into noise
	fade = 0.15, -- seconds: one clip's track fades out and the next fades in over this
	refade = 0.1, -- a looping clip found stopped is started again over this
	holdEnd = 0.06, -- a one-shot is frozen this close to its end
	-- the one-shots that carry a body through the air, by the seconds into each at which the body leaves
	-- the surface and at which it comes down (the clips' Commit and Recover markers), and where a fall
	-- that was not a jump comes into it. The body is launched at once, so the clip starts at `launch`
	-- (its crouch belongs on the ground) and is paced to reach `land` as the body does; a longer fall is
	-- held there, reaching for the ground.
	air = {
		Leap = { launch = 5 / 30, land = 19 / 30, fall = 14 / 30 },
		Pounce = { launch = 0.4, land = 0.7, fall = 0.55 },
	} :: { [string]: { launch: number, land: number, fall: number } },
	landRate = 1.6, -- a one-shot left for another clip (a landing) runs through its last keys at this rate as it fades
	-- studs/s^2 of slowing from which a run is stopping (heroBraking): it keeps to Run, not Walk, until it
	-- stands. A stop dies away, so under runAbove the bar falls with the speed
	brake = 40,
	-- where a run that is stopping ends its last bound (heroSettle): `at` seconds into Run, the hind feet
	-- planted under the body and the fore paws just lifted, from where the cross to Idle only sets the
	-- fore paws down. A run found up to `slack` seconds past that is held; any other is taken there at
	-- up to `rate` (from mid-flight that reaches the fore paws' landing, which also stands down cleanly)
	settle = { at = 0.17, slack = 0.04, rate = 1.8 },
}

-- Whether a body moving at `speed` and losing `slowing` studs/s of it each second is stopping (and not
-- easing off to a slower pace): HERO.brake at the run's slowest or faster, and in proportion below it (a
-- body let go loses a fixed share of its speed each moment, so its slowing falls away with its speed).
-- `slowing` is the motor's own for a held body (the fall of the speed the animation is told, frame to
-- frame) and Animation/Liveliness's reading of the root for the others: that one is smoothed against the
-- server's steps and trails the drawn body, which let a stop from an ordinary run reach the walk's speed
-- before it read as a stop, and the Walk clip flashed on the way down.
function AnimationDriver.heroBraking(speed: number, slowing: number): boolean
	local H = AnimationDriver.HERO
	return slowing > H.brake * math.clamp(speed / H.runAbove, 0, 1)
end

-- `action` is how a body in the air left its surface ("leap" | "pounce"; nil: it fell); `was` the clip it
-- played last frame and `braking` whether it is stopping (heroBraking): a run that is stopping keeps to
-- its run until it stands, the walk is for a body that ambles.
function AnimationDriver.heroClip(
	mode: string,
	speed: number,
	stalk: boolean,
	action: string?,
	was: string?,
	braking: boolean?
): string
	local H = AnimationDriver.HERO
	if mode == "air" then
		return if action == "pounce" then "Pounce" else "Leap"
	elseif mode == "trunk" then
		return "Climb"
	elseif speed < H.still then
		-- a stalk that stops holds its creep where it is (heroRate), it does not stand up
		return if stalk and mode == "ground" then "Stalk" else "Idle"
	elseif mode == "rail" then
		return "Wire"
	elseif stalk then
		return "Stalk"
	end
	return if speed < H.runAbove and not (was == "Run" and braking) then "Walk" else "Run"
end

-- Playback speed for clip `name` of `length` seconds on a body moving at `speed`: one clip cycle per
-- stride. `cadence` (rad/s of stride phase, from the kinematic motor) wins when it is known. A body
-- hanging still on a trunk holds its climb pose, and a stalk that has stopped its creep (0); Idle plays at
-- its own speed; a leap or a pounce goes from its take-off to its landing in the `airSeconds` the motor
-- expects the body to stay up (at its own speed when that is not known: a fall).
function AnimationDriver.heroRate(
	name: string,
	speed: number,
	cadence: number?,
	length: number,
	airSeconds: number?
): number
	local H = AnimationDriver.HERO
	local air = H.air[name]
	if air then
		return if airSeconds and airSeconds > 0
			then math.clamp((air.land - air.launch) / airSeconds, H.minRate, H.maxRate)
			else 1
	end
	if name == "Idle" then
		return 1
	end
	if (name == "Climb" or name == "Stalk") and speed < H.still then
		return 0
	end
	local stride = H.stride[name] or 5.5
	local cyclesPerSecond = if cadence
			and cadence > 0
			and name == "Run"
		then cadence / (2 * math.pi)
		else math.max(speed, 0) / stride
	return math.clamp(cyclesPerSecond * length, H.minRate, H.maxRate)
end

-- Where a clip starts, seconds into it: a leap or a pounce at its take-off (the body is already in the
-- air), a fall that nothing launched (`action` nil) further in; any other clip at its beginning.
function AnimationDriver.heroStart(name: string, action: string?): number
	local air = AnimationDriver.HERO.air[name]
	return if air == nil then 0 elseif action then air.launch else air.fall
end

-- The playback speed of a run that is stopping (heroBraking of its `speed` and `slowing`, and under
-- HERO.runAbove): `rate` (heroRate) for anything else. `time` is the seconds into the clip.
-- A stopping body is caught anywhere in its bound; left to its cadence the clip all but freezes there,
-- half the time in flight, and the cross to Idle then hangs it in the air and pushes its stretched legs
-- a quarter of a stud through the ground on the way down. Instead the bound is finished: the clip is
-- paced to reach HERO.settle.at as the body comes to stand (its speed dies away as an exponential, so
-- that is speed / slowing * ln(speed / still) seconds from now), and held there.
function AnimationDriver.heroSettle(
	name: string,
	time: number,
	length: number,
	speed: number,
	slowing: number,
	rate: number
): number
	local H = AnimationDriver.HERO
	if name ~= "Run" or speed >= H.runAbove or length <= 0 or not AnimationDriver.heroBraking(speed, slowing) then
		return rate
	end
	local S = H.settle
	local left = (S.at - time) % length -- seconds of clip to go
	if left > length - S.slack or left < 1e-3 then
		return 0
	end
	local seconds = math.max(speed, H.still) / slowing * math.log(math.max(speed / H.still, 1))
	return if seconds * S.rate <= left then S.rate else left / seconds
end

-- One frame of a hero body's clip tracks: `want` (heroClip) becomes the clip that plays, at `rate`
-- (heroRate), from `startAt` seconds into it (heroStart; its beginning when not given). `tracks` holds
-- the body's loaded tracks by clip name, `current` is the clip it played last frame, `t` is the track of
-- `want`, `loop` whether that clip loops. A change of clip crosses over in HERO.fade seconds, and a
-- one-shot that is left (a leap, on landing) runs through its last keys as it fades, while a gait left
-- for Idle is held where it is (the body stands: its legs do not run on under it); a one-shot that has
-- reached its end is frozen there, and one that carries a body through the air where it comes down (a long
-- fall holds the reach). Returns the clip now playing. It only calls Play, Stop and AdjustSpeed, reads
-- IsPlaying, Looped, TimePosition and Length and sets TimePosition, so the offline motion preview
-- (tools/review/motion) runs this same function on stand-in tracks.
function AnimationDriver.heroTracks(
	tracks: { [string]: any },
	current: string?,
	want: string,
	t: any,
	loop: boolean,
	rate: number,
	startAt: number?
): string
	local H = AnimationDriver.HERO
	if want ~= current then
		for name, old in tracks do
			if name ~= want and old.IsPlaying then
				if not old.Looped then
					old:AdjustSpeed(H.landRate)
				elseif want == "Idle" then
					old:AdjustSpeed(0)
				end
				old:Stop(H.fade)
			end
		end
		t:Play(H.fade)
		if startAt and startAt > 0 then
			t.TimePosition = startAt
		end
	elseif not t.IsPlaying and loop then
		t:Play(H.refade)
	end
	local air = H.air[want]
	if not loop and t.Length > 0 and t.TimePosition >= (if air then air.land else t.Length - H.holdEnd) then
		t:AdjustSpeed(0) -- hold the pose (a long fall after a leap)
	else
		t:AdjustSpeed(rate)
	end
	return want
end

-- The seed of a rodent body's twitches (Animation/Creep), from its name: the same on every client.
function AnimationDriver.creepSeed(name: string): number
	return (#name * 7.31) % 97
end

-- The joint rotations a hero body gets on top of its clip at server time `t`, as
-- { [boneName] = { rx, ry, rz } }: radians on the rig's own axes, each multiplied onto what the clip gave
-- that bone as CFrame.Angles(rx, ry, rz) (the Root may carry three more numbers, an offset in studs:
-- CFrame.new(tx, ty, tz) * CFrame.Angles(rx, ry, rz)). `rig` is the body's RigSpec attribute. The Spicy
-- Rodent ("rodent") has Animation/Creep's twitches; `live`, when given, is the body's Animation/Liveliness
-- state after this frame's step, and its pose is added on top (the two are offsets on the same axes).
-- Pure: the driver below applies exactly this, and the offline motion preview
-- (tools/review/motion_path.luau) reads it, so both show the same thing; a new layer belongs here.
function AnimationDriver.heroLayers(
	rig: string,
	t: number,
	seed: number,
	live: Liveliness.State?
): { [string]: { number } }
	local out: { [string]: { number } } = {}
	if rig ~= "rodent" then
		return if live then Liveliness.onto(out, live.pose) else out
	end
	-- (at a sprint a head jerk shows less: the run already throws the head about)
	local pose = Creep.pose(t, seed, if live then Liveliness.twitch(live) else 1)
	out.Head = { pose.head.pitch, pose.head.yaw, pose.head.roll }
	out.Jaw = { -pose.jaw, 0, 0 } -- the jaw opens about -X (the authored bite)
	out.EarL = { 0, 0, pose.earL }
	out.EarR = { 0, 0, -pose.earR }
	for i, yaw in pose.tail do
		if yaw ~= 0 then
			out[`Tail{i}`] = { 0, yaw, 0 }
		end
	end
	-- the breath and the shudder are the back's (and the shudder the head's too): the bones before and
	-- after take the breath back (by the rig's own lengths the chest ends level and at its height) and
	-- the chest takes the shudder back, so the fore paws it carries stay where they stand (within 0.02
	-- studs; they were shoved a third of a stud); the neck takes the shudder up again. The shudder rolls
	-- the bone behind the chest: the nearer the roll is to where it is taken back, the less it carries
	-- the chest sideways.
	out.Spine1 = { -0.645 * pose.chest, 0, 0 }
	out.Spine2 = { pose.chest, 0, 0 }
	out.Chest = { -0.355 * pose.chest, 0, -3 * pose.spine }
	if pose.spine ~= 0 then
		out.Spine3 = { 0, 0, 3 * pose.spine }
		out.Neck = { 0, 0, 3 * pose.spine }
	end
	return if live then Liveliness.onto(out, live.pose) else out
end

-- What Animation/Liveliness is told about a hero body this frame: its root's pose (`cf`, a CFrame), the
-- speed the animation is told, heroClip's mode, the kinematic controller's pose when the body is held
-- (else the pose arrives in the server's steps), the server's clock, and whether it is too far from the
-- camera to matter. Pure: the offline motion preview builds the same sample.
function AnimationDriver.liveSample(
	cf: any,
	speed: number,
	mode: string,
	kin: KinematicPose.Pose?,
	time: number,
	far: boolean
): Liveliness.Sample
	local pitch, yaw, roll = cf:ToOrientation()
	return {
		x = cf.X,
		y = cf.Y,
		z = cf.Z,
		pitch = pitch,
		yaw = yaw,
		roll = roll,
		speed = speed,
		mode = mode,
		stalk = kin ~= nil and kin.stalk == true,
		winded = kin ~= nil and kin.winded == true,
		coarse = kin == nil,
		time = time,
		far = far,
	}
end

-- The joints the gait drives, by RigSpec bone name: Motor6Ds on a part-built puppet, Bones on a skinned
-- hero model (Server/Assets/HeroArt). The names and the axes are the same on both (the hero's bones rest
-- with no rotation), so one pose serves either. A hero's region Motor6Ds (BodyMotor6D, ...) match no name.
function AnimationDriver.gaitJoints(model: Instance): ({ Joint }, number)
	local joints: { Joint } = {}
	local tailN = 0
	for _, d in model:GetDescendants() do
		if d:IsA("Motor6D") or d:IsA("Bone") then
			local name = d.Name
			local leg, seg = string.match(name, "^(%a+[LR])_(%a+)$")
			local tail = string.match(name, "^Tail(%d+)$")
			if leg and (seg == "Upper" or seg == "Lower") then
				table.insert(joints, { motor = d, kind = seg :: string, leg = leg } :: Joint)
			elseif tail then
				local i = tonumber(tail) :: number
				tailN = math.max(tailN, i)
				table.insert(joints, { motor = d, kind = "Tail" :: string, index = i } :: Joint)
			elseif name == "Head" or name == "Root" then
				table.insert(joints, { motor = d, kind = name :: string } :: Joint)
			end
		end
	end
	return joints, tailN
end

-- The joint named Root that hangs the visible body off the root part (animals: RootPart -> Pelvis;
-- R15: HumanoidRootPart -> LowerTorso): a Motor6D, or on stock R15s built with the avatar joint
-- upgrade an AnimationConstraint, whose root-side Attachment is moved instead of C0. On a skinned hero
-- model it is the Root Bone (a Bone is an Attachment: moving it moves the whole skin).
local function rootJointOf(model: Model, root: BasePart): (Motor6D?, Attachment?)
	for _, d in model:GetDescendants() do
		if d.Name ~= "Root" then
			continue
		end
		if d:IsA("Motor6D") and d.Part0 == root then
			return d, nil
		elseif d:IsA("Bone") then
			return nil, d
		elseif d:IsA("AnimationConstraint") then
			for _, a in { d.Attachment0, d.Attachment1 } do
				if a and a.Parent == root then
					return nil, a
				end
			end
		end
	end
	return nil, nil
end

-- Studs from the root's centre down to the soles: the puppet's HipHeight attribute (the root's
-- height above the ground), else the model's bounding box at rest.
local function footDropOf(model: Model, root: BasePart): number
	local hip = model:GetAttribute("HipHeight")
	if type(hip) == "number" and model:FindFirstChildOfClass("Humanoid") == nil then
		return hip
	end
	local cf, size = model:GetBoundingBox()
	return root.Position.Y - (cf.Position.Y - size.Y / 2)
end

local function ensureAnimator(body: Model): Animator?
	local host: Instance? = body:FindFirstChildOfClass("Humanoid")
	if host == nil then
		host = body:FindFirstChildOfClass("AnimationController")
		if host == nil then
			local ac = Instance.new("AnimationController")
			ac.Parent = body
			host = ac
		end
	end
	local hostInst = host :: Instance
	local existing = hostInst:FindFirstChildOfClass("Animator")
	if existing then
		return existing
	end
	local animator = Instance.new("Animator")
	animator.Parent = hostInst -- created on this client: never replicates (D3)
	return animator
end

function AnimationDriver.start(opts: Opts): Driver
	local RunService = game:GetService("RunService")
	local clips = opts.clips or AnimationDriver.DEFAULT_CLIPS
	local walkAbove = opts.walkAbove or 0.4
	local runAbove = opts.runAbove or 9
	local entries: { [Model]: Entry } = {}
	local count = 0

	local function track(e: Entry, name: string): AnimationTrack?
		local t = e.tracks[name]
		if t then
			return t
		end
		local set = clips[e.species]
		local heroClip = if e.hero then e.hero[name] else nil
		local id = if heroClip then heroClip.id else set and (set :: any)[name]
		if type(id) ~= "string" then
			return nil
		end
		local anim = Instance.new("Animation")
		anim.AnimationId = id
		local animator = e.animator
		if animator == nil then
			return nil
		end
		local ok, loaded = pcall(function()
			return animator:LoadAnimation(anim)
		end)
		if not ok then
			warn(`AnimationDriver: cannot load {id}: {loaded}`)
			return nil
		end
		local lt = loaded :: AnimationTrack
		lt.Looped = if heroClip then heroClip.loop else name ~= "jump"
		lt.Priority = if name == "idle" then Enum.AnimationPriority.Idle else Enum.AnimationPriority.Movement
		e.tracks[name] = lt
		return lt
	end

	local function add(child: Instance)
		if not child:IsA("Model") or entries[child] then
			return
		end
		local model = child :: Model
		local root = model.PrimaryPart
		if root == nil then
			return
		end
		local sp = model:GetAttribute(PossessionState.ATTR.Species)
		local species = if type(sp) == "string" then sp else "human"
		local gait: Gait.Params? = nil
		local joints: { Joint } = {}
		local tailN = 0
		local animator: Animator? = nil
		local hero: { [string]: HeroAssets.Clip }? = nil
		if Gait.PROCEDURAL[species] and clips[species] == nil then
			local hip = model:GetAttribute("HipHeight")
			gait = Gait.params(species, if type(hip) == "number" then hip else nil)
			joints, tailN = AnimationDriver.gaitJoints(model)
			if model:GetAttribute("Hero") == true and HeroAssets.CLIPS[species] then
				-- the sculpted rig plays its authored clips; the gait above stays as the fallback
				animator = ensureAnimator(model)
				if animator then
					hero = HeroAssets.CLIPS[species]
				end
			end
		else
			animator = ensureAnimator(model)
			if animator == nil then
				return
			end
		end
		local rootJoint, rootAttach = rootJointOf(model, root)
		local medConn = model:GetAttributeChangedSignal("Med"):Connect(function()
			local e = entries[model]
			if e then
				e.med = model:GetAttribute("Med")
			end
		end)
		entries[model] = {
			body = model,
			root = root,
			animator = animator,
			humanoid = model:FindFirstChildOfClass("Humanoid"),
			species = species,
			tracks = {},
			current = nil,
			lastPos = root.Position,
			speed = 0,
			vy = 0,
			gait = gait,
			joints = joints,
			tailN = tailN,
			phase = (#model.Name * 0.37) % (2 * math.pi),
			rootJoint = rootJoint,
			rootAttach = rootAttach,
			baseC0 = if rootJoint then rootJoint.C0 elseif rootAttach then rootAttach.CFrame else CFrame.identity,
			footDrop = footDropOf(model, root),
			settle = AnimationDriver.newSettle(),
			fix = 0,
			fixTarget = 0,
			nextProbe = os.clock() + ((#model.Name * 0.173) % 1) * AnimationDriver.PROBE_EVERY,
			anchored = root.Anchored,
			applied = 0,
			kin = false,
			hero = hero,
			mode = "ground",
			creep = nil,
			med = model:GetAttribute("Med"),
			medConn = medConn,
			drop = 0,
			pace = 0,
			legs = {},
			lean = 0,
			roll = 0,
			pitch = 0,
		}
		if animator and gait == nil then
			local legs = entries[model].legs
			for _, d in model:GetDescendants() do
				if
					(d:IsA("Motor6D") or d:IsA("AnimationConstraint"))
					and table.find(AnimationDriver.FLAT_JOINTS, d.Name) ~= nil
				then
					table.insert(legs, d)
				end
			end
		end
		if hero then
			local bones: { [string]: any } = {}
			for _, d in model:GetDescendants() do
				if d:IsA("Bone") then
					bones[d.Name] = d
				end
			end
			local seed = AnimationDriver.creepSeed(model.Name)
			local rig = if model:GetAttribute("RigSpec") == "rodent" then "rodent" else "squirrel"
			entries[model].creep =
				{ seed = seed, rig = rig, live = Liveliness.new(seed, rig), bones = bones, base = {}, wrote = {} }
		end
		count += 1
	end

	local function remove(child: Instance)
		local e = entries[child :: any]
		if e then
			if e.medConn then
				e.medConn:Disconnect()
			end
			for _, t in e.tracks do
				t:Stop(0)
			end
			for _, j in e.joints do
				j.motor.Transform = CFrame.identity
			end
			if e.applied ~= 0 or e.roll ~= 0 or e.pitch ~= 0 then
				local rj, ra = e.rootJoint, e.rootAttach
				if rj then
					rj.C0 = e.baseC0
				elseif ra then
					ra.CFrame = e.baseC0
				end
			end
			entries[child :: any] = nil
			count -= 1
		end
	end

	local function choose(e: Entry): string
		local set: ClipSet = clips[e.species] or {}
		local hum = e.humanoid
		if set.sit and hum and hum.SeatPart ~= nil then
			return "sit"
		end
		-- a patient (AI bodies only: a held body keeps its own animation)
		if e.med ~= nil and e.root.Anchored then
			local clip = AnimationDriver.medPose(e.med, e.footDrop).clip
			if clip and (set :: any)[clip] then
				return clip
			end
		end
		if set.jump and e.vy > 6 then
			return "jump"
		elseif set.fall and e.vy < -10 then
			return "fall"
		end
		if e.speed < walkAbove then
			return if set.idle then "idle" elseif set.run then "hold" else "none"
		end
		if set.walk and set.run then
			return AnimationDriver.gaitClip(e.current, e.pace, runAbove)
		end
		return if set.run then "run" else "walk"
	end

	-- ground probe: collidable parts and terrain, never bodies, the camera's own parts or water
	local probe = RaycastParams.new()
	probe.FilterType = Enum.RaycastFilterType.Exclude
	probe.RespectCanCollide = true
	probe.IgnoreWater = true
	probe.FilterDescendantsInstances = { opts.container, workspace.CurrentCamera }
	local DOWN = Vector3.new(0, -(AnimationDriver.PROBE_UP - AnimationDriver.FIX_MIN + 0.5), 0)

	-- the visible body's vertical offset from its root (world up, whatever the root's attitude), and
	-- its lean (a stagger: about the soles, so the feet stay where they are)
	local function applyOffset(e: Entry, off: number, roll: number?, pitch: number?)
		local r, p = roll or 0, pitch or 0
		if math.abs(off - e.applied) > 0.002 or (off == 0 and e.applied ~= 0) or r ~= e.roll or p ~= e.pitch then
			e.applied, e.roll, e.pitch = off, r, p
			local shifted = CFrame.new(e.root.CFrame:VectorToObjectSpace(Vector3.new(0, off, 0))) * e.baseC0
			if r ~= 0 or p ~= 0 then
				local soles = Vector3.new(0, -e.footDrop, 0)
				shifted = CFrame.new(soles) * CFrame.Angles(p, 0, r) * CFrame.new(-soles) * shifted
			end
			local rj, ra = e.rootJoint, e.rootAttach
			if rj then
				rj.C0 = shifted
			elseif ra then
				ra.CFrame = shifted
			end
		end
	end

	-- the visual root of one body this frame (after physics: root.Position is what renders)
	local function visualRoot(e: Entry, pos: Vector3, dt: number, now: number, camPos: Vector3)
		local rj, ra = e.rootJoint, e.rootAttach
		if (rj == nil or rj.Parent == nil) and (ra == nil or ra.Parent == nil) then
			return
		end
		local anchored = e.root.Anchored
		if KinematicPose.get(e.body) then
			if not e.kin then
				e.kin = true
				e.fix, e.fixTarget = e.applied, 0
				e.settle.live = false
			end
			e.anchored = anchored
			e.fix *= math.exp(-dt * AnimationDriver.KIN_RATE)
			if math.abs(e.fix) < 0.001 then
				e.fix = 0
			end
			applyOffset(e, e.fix)
			return
		elseif e.kin then
			-- the controller let go: the smoothing starts again from the height drawn now
			e.kin = false
			e.settle.live = false
			e.fix, e.fixTarget = 0, 0
		end
		if anchored ~= e.anchored then
			-- possession or release: carry the ground correction into the smoothed height so the
			-- body does not jump when the root takes over (or gives up) the real ground
			e.anchored = anchored
			e.settle.y += e.fix
			e.fix, e.fixTarget = 0, 0
		end
		local off = 0
		if e.humanoid and not anchored then
			e.settle.live = false -- a possessed person stands on its Humanoid
		else
			off = AnimationDriver.settle(e.settle, pos.Y, dt)
		end
		if anchored then
			if now >= e.nextProbe then
				e.nextProbe = now + AnimationDriver.PROBE_EVERY
				local target = 0
				local sole = pos.Y - e.footDrop
				if
					(pos - camPos).Magnitude < AnimationDriver.PROBE_RANGE
					and math.abs(sole - Height.at(pos.X, pos.Z)) < AnimationDriver.NEAR_GROUND
				then
					local hit =
						workspace:Raycast(Vector3.new(pos.X, sole + AnimationDriver.PROBE_UP, pos.Z), DOWN, probe)
					if hit and hit.Normal.Y > 0.6 then
						local lift = hit.Position.Y + AnimationDriver.CLEARANCE - sole
						if lift >= AnimationDriver.FIX_MIN and lift <= AnimationDriver.FIX_MAX then
							target = lift
						end
					end
				end
				e.fixTarget = target
			end
		else
			e.fixTarget = 0
		end
		e.fix += (e.fixTarget - e.fix) * (1 - math.exp(-dt * 8))
		off += e.fix
		-- a patient's pose lowers the visible body (sitting on the ground, or up on the cot)
		local wantDrop = if anchored and e.med ~= nil then AnimationDriver.medPose(e.med, e.footDrop).drop else 0
		if wantDrop ~= e.drop then
			e.drop += (wantDrop - e.drop) * (1 - math.exp(-dt * AnimationDriver.POSE_RATE))
			if math.abs(wantDrop - e.drop) < 0.005 then
				e.drop = wantDrop
			end
		end
		off -= e.drop
		-- the stagger of someone with the symptoms (AI bodies: a held body is never posed)
		local wantLean = if anchored and e.med == "symptomatic" then 1 else 0
		if wantLean ~= e.lean then
			e.lean += (wantLean - e.lean) * (1 - math.exp(-dt * AnimationDriver.SWAY_RATE))
			if math.abs(wantLean - e.lean) < 0.01 then
				e.lean = wantLean
			end
		end
		if e.lean > 0 then
			local roll, pitch = AnimationDriver.sway("symptomatic", now, e.phase)
			applyOffset(e, off, roll * e.lean, pitch * e.lean)
		else
			applyOffset(e, off)
		end
	end

	local function step(dt: number)
		if dt <= 0 then
			return
		end
		local alpha = math.min(1, dt / 0.15)
		local now = os.clock()
		local camera = workspace.CurrentCamera
		local camPos = if camera then camera.CFrame.Position else Vector3.zero
		for _, e in entries do
			local pos = e.root.Position
			local d = pos - e.lastPos
			e.lastPos = pos
			-- animals measure 3D speed so a climb up a trunk animates like a run
			local inst = (if e.gait then d.Magnitude else Vector3.new(d.X, 0, d.Z).Magnitude) / dt
			local vy = d.Y / dt
			if inst > 200 then
				inst = e.speed -- a teleport or recovery, not motion
				vy = 0
			end
			local kin = KinematicPose.get(e.body)
			local toldBefore = e.speed
			if kin then
				-- the motor's own speed: what the body is seen to do never feeds the animation
				e.speed, e.vy = kin.moveSpeed, 0
				e.pace = kin.moveSpeed
			else
				e.speed += (inst - e.speed) * alpha
				e.vy += (vy - e.vy) * alpha
				e.pace = AnimationDriver.pace(e.pace, inst, dt)
			end
			visualRoot(e, pos, dt, now, camPos)
			local heroSet = e.hero
			if heroSet then
				-- what the body is doing: the controller says so for a held body; for the rest, a root
				-- standing on end is on a trunk, and anything else is on the ground at its seen speed
				local mode = if kin and kin.mode
					then kin.mode
					elseif math.abs(e.root.CFrame.LookVector.Y) > 0.6 then "trunk"
					else "ground"
				e.mode = mode
				local action = if kin then kin.action else nil
				local slowing = if kin
					then (toldBefore - e.speed) / math.max(dt, 1e-3)
					elseif e.creep then -e.creep.live.accel
					else 0
				local braking = AnimationDriver.heroBraking(e.speed, slowing)
				local want = AnimationDriver.heroClip(
					mode,
					e.speed,
					kin ~= nil and kin.stalk == true,
					action,
					e.current,
					braking
				)
				local clip = heroSet[want]
				local t = if clip then track(e, want) else nil
				if t == nil or clip == nil then
					-- the clip did not load: this body goes back to the procedural gait for good
					for _, old in e.tracks do
						old:Stop(0)
					end
					e.hero = nil
					continue
				end
				local cadence, airSeconds = if kin then kin.cadence else nil, if kin then kin.airSeconds else nil
				local rate = AnimationDriver.heroRate(want, e.speed, cadence, clip.length, airSeconds)
				if want == e.current then
					rate = AnimationDriver.heroSettle(want, t.TimePosition, clip.length, e.speed, slowing, rate)
				end
				e.current = AnimationDriver.heroTracks(
					e.tracks,
					e.current,
					want,
					t,
					clip.loop,
					rate,
					AnimationDriver.heroStart(want, action)
				)
				continue
			end
			if e.gait then
				continue -- posed in Stepped (gaitStep)
			end
			local want = choose(e)
			local set: ClipSet = clips[e.species] or {}
			if want == "hold" then
				-- squirrel puppet stopped: freeze the run clip where it is (no snap to the rest pose)
				local t = e.tracks.run
				if t and t.IsPlaying then
					t:AdjustSpeed(0)
				end
				e.current = "hold"
				continue
			end
			if want ~= e.current then
				local nextTrack = if want ~= "none" then track(e, want) else nil
				for name, t in e.tracks do
					if name ~= want and t.IsPlaying then
						t:Stop(0.2)
					end
				end
				if nextTrack and not nextTrack.IsPlaying then
					nextTrack:Play(0.2)
					local t0 = e.body:GetAttribute(PossessionState.ATTR.ClipT0)
					if type(t0) == "number" and nextTrack.Length > 0 then
						nextTrack.TimePosition = (workspace:GetServerTimeNow() - t0) % nextTrack.Length
					end
				end
				e.current = want
			end
			local cur = e.current and e.tracks[e.current]
			if cur then
				local nominal = if e.current == "run"
					then set.nominalRun
					elseif e.current == "walk" then set.nominalWalk
					else nil
				cur:AdjustSpeed(AnimationDriver.clipSpeed(e.speed, nominal))
			end
		end
	end

	-- the procedural gait writes Motor6D.Transform in Stepped (before the joints are solved)
	local clock = 0
	local function gaitStep(_t: number, dt: number)
		clock += dt
		for _, e in entries do
			local p = e.gait
			local creep = e.creep
			if creep and e.hero then
				-- the layers (heroLayers), multiplied onto what the clip gave each bone this frame
				local function layer(name: string, offset: CFrame)
					local bone = creep.bones[name]
					if bone == nil then
						return
					end
					local now = bone.Transform
					-- if the Animator did not write this bone since the last frame, `now` is our own
					-- value: start again from what the clip last gave
					local base = if creep.wrote[bone] == now then creep.base[bone] else now
					local out = base * offset
					creep.base[bone] = base
					creep.wrote[bone] = out
					bone.Transform = out
				end
				local now = workspace:GetServerTimeNow()
				local cf, camera = e.root.CFrame, workspace.CurrentCamera
				local far = camera ~= nil and (cf.Position - camera.CFrame.Position).Magnitude > Liveliness.RANGE
				local sample = AnimationDriver.liveSample(cf, e.speed, e.mode, KinematicPose.get(e.body), now, far)
				local live = if Liveliness.frame(creep.live, sample, dt) then creep.live else nil
				for name, r in AnimationDriver.heroLayers(creep.rig, now, creep.seed, live) do
					layer(name, CFrame.new(r[4] or 0, r[5] or 0, r[6] or 0) * CFrame.Angles(r[1], r[2], r[3]))
				end
			end
			if #e.legs > 0 and e.med ~= nil and e.root.Anchored and AnimationDriver.medPose(e.med, e.footDrop).flat then
				-- a sitting patient's legs lie flat: the knees and ankles are straightened after the
				-- Animator has written the chair sit (it writes them again every frame, so nothing is
				-- left to put back when the pose ends)
				for _, joint in e.legs do
					joint.Transform = CFrame.identity
				end
			end
			if p == nil or #e.joints == 0 or e.hero ~= nil then
				continue -- (a hero rig is posed by its clips)
			end
			local kin = KinematicPose.get(e.body)
			if kin then
				e.phase = (e.phase + kin.cadence * dt) % (2 * math.pi)
			else
				e.phase = Gait.advance(e.phase, e.speed, dt, p)
			end
			local pose = Gait.pose(e.phase, e.speed, clock, p, e.tailN, if kin then kin.climb else 0)
			for _, j in e.joints do
				local cf = CFrame.identity
				local leg = if j.leg then pose.legs[j.leg] else nil
				if j.kind == "Upper" and leg then
					cf = CFrame.Angles(leg.upper, 0, 0)
				elseif j.kind == "Lower" and leg then
					cf = CFrame.Angles(leg.lower, 0, 0)
				elseif j.kind == "Tail" then
					local seg = pose.tail[j.index :: number]
					if seg then
						cf = CFrame.Angles(seg.pitch, seg.yaw, 0)
					end
				elseif j.kind == "Head" then
					cf = CFrame.Angles(pose.head, 0, 0)
				elseif j.kind == "Root" then
					cf = CFrame.new(0, pose.bob, 0) * CFrame.Angles(pose.rock, 0, 0)
				end
				j.motor.Transform = cf
			end
		end
	end

	for _, child in opts.container:GetChildren() do
		add(child)
	end
	local conns = {
		opts.container.ChildAdded:Connect(add),
		opts.container.ChildRemoved:Connect(remove),
		RunService.RenderStepped:Connect(step),
		RunService.Stepped:Connect(gaitStep),
	}

	return {
		stop = function()
			for _, c in conns do
				c:Disconnect()
			end
			for model in entries do
				remove(model)
			end
		end,
		bodies = function(): number
			return count
		end,
	}
end

return AnimationDriver
