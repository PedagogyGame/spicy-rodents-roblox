--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Animation.Gait
-- Procedural gait for the four-legged bodies (squirrel, Spicy Rodent, fox, deer) until their skinned
-- clips land (BUILD_PLAN §5.4): leg swing and knee bend from the stride phase, a body bob, a head nod
-- and a tail sway, all scaled by speed. Squirrels bound (front pair together, back pair opposite);
-- fox and deer trot (diagonal pairs together). Speed is the body's 3D speed, so climbing a trunk or
-- running along a wire animates the same way as running on the ground.
-- Smooth by construction (owner playtest 2026-11-09, "bumpy bouncing sharply quickly up and down"):
-- the bob is a small raised-cosine (no abs(sin) cusps), one rise per bound or two per trot cycle;
-- the head cancels the body's rock instead of snapping; standing and moving blend through a smooth
-- weight, and every moving term runs on the stride phase (never t * a speed-dependent rate, which
-- jumps when the speed wobbles). Running streams the squirrel's tail back (a deer flags its tail up).
-- Pure numbers (Lune-testable); AnimationDriver turns a Pose into Motor6D.Transform values on the
-- RigSpec bone names (FrontL_Upper, ..., Tail1..n, Head, Root).
-- Interface: PROCEDURAL; params(species, hipHeight?) -> Params; advance(phase, speed, dt, params) -> phase;
--   moving(speed) -> 0..1; pose(phase, speed, t, params, tailN) -> Pose

local Gait = {}

Gait.PROCEDURAL = { squirrel = true, rodent = true, fox = true, deer = true } :: { [string]: boolean }

export type Params = {
	bound: boolean, -- squirrel bound vs trot
	stride: number, -- studs travelled per full cycle at a run
	runSpeed: number, -- studs/s at which the swing reaches full amplitude
	swing: number, -- radians, full leg swing amplitude
	bob: number, -- studs, body bob at a full run (peak; the body never dips below its rest height)
	tailLift: number, -- radians on Tail1 at a full run (+ streams it back, - raises it)
}

export type Pose = {
	legs: { [string]: { upper: number, lower: number } }, -- FrontL, FrontR, BackL, BackR
	bob: number, -- studs (Root joint, up)
	rock: number, -- radians (Root joint pitch)
	head: number, -- radians (Head pitch)
	tail: { { pitch: number, yaw: number } }, -- per tail segment from the hips out
}

local TAU = 2 * math.pi

function Gait.params(species: string, hipHeight: number?): Params
	local hip = hipHeight or 1
	if species == "squirrel" or species == "rodent" then
		return {
			bound = true,
			stride = math.max(hip * 3.2, 1.6),
			runSpeed = 16,
			swing = 0.75,
			bob = hip * 0.05,
			tailLift = 0.7,
		}
	elseif species == "fox" then
		return {
			bound = false,
			stride = math.max(hip * 2.6, 2),
			runSpeed = 18,
			swing = 0.6,
			bob = hip * 0.025,
			tailLift = -0.1,
		}
	end
	return {
		bound = false,
		stride = math.max(hip * 2.4, 3),
		runSpeed = 22,
		swing = 0.5,
		bob = hip * 0.02,
		tailLift = -1.2,
	}
end

-- The stride phase after dt seconds at `speed` (studs/s); wraps to [0, 2pi).
function Gait.advance(phase: number, speed: number, dt: number, p: Params): number
	return (phase + TAU * math.max(speed, 0) * dt / p.stride) % TAU
end

-- 0 at rest, 1 at a full run (smooth).
function Gait.effort(speed: number, p: Params): number
	local x = math.clamp(speed / p.runSpeed, 0, 1)
	return x * (2 - x)
end

-- 0 standing, 1 moving: a smoothstep over the first stud per second, so a speed that hovers near
-- zero (an AI body between network updates) never pops the legs, bob or tail between two poses.
function Gait.moving(speed: number): number
	local w = math.clamp((speed - 0.15) / 0.85, 0, 1)
	return w * w * (3 - 2 * w)
end

function Gait.pose(phase: number, speed: number, t: number, p: Params, tailN: number): Pose
	local e = Gait.effort(speed, p)
	local w = Gait.moving(speed)
	local amp = if speed > 0 then p.swing * math.max(e, 0.35 * w) else 0
	local offsets: { [string]: number }
	if p.bound then
		offsets = { FrontL = 0, FrontR = 0.25, BackL = math.pi, BackR = math.pi + 0.25 }
	else
		offsets = { FrontL = 0, BackR = 0, FrontR = math.pi, BackL = math.pi }
	end
	local legs = {}
	for name, off in offsets do
		local a = phase + off
		-- positive pitch about the bone's X swings the foot forward (-Z is forward in RigSpec)
		local upper = amp * math.sin(a)
		-- the lower leg folds while the foot swings forward (the recovery half, d(upper)/da > 0):
		-- a front leg's foot tucks back (+Z), a hind leg's hock folds the other way; (1 + cos) / 2
		-- squared is the smooth version of max(0, cos)
		local fold = (1 + math.cos(a)) / 2
		local lower = amp * 0.9 * fold * fold
		if string.sub(name, 1, 5) == "Front" then
			lower = -lower
		end
		legs[name] = { upper = upper, lower = lower }
	end
	-- body bob: a raised cosine, 0 at contact and p.bob * e at the top of each bound (one per bound
	-- cycle, two per trot cycle), plus a faint breath when standing
	local bobFreq = if p.bound then 1 else 2
	local rise = (1 - math.cos(phase * bobFreq)) / 2
	local bob = w * p.bob * e * rise + (1 - w) * p.bob * 0.08 * (1 + math.sin(t * 2.2)) / 2
	local rock = if p.bound then w * 0.05 * e * math.sin(phase) else 0
	-- the head holds its line: it cancels the rock and adds only a small, smooth nod
	local head = -rock + w * 0.03 * e * math.sin(phase * bobFreq) + (1 - w) * 0.04 * math.sin(t * 0.9)
	local tail = {}
	for i = 1, tailN do
		local lag = i * 0.7
		local reach = 0.6 + 0.4 * i / math.max(tailN, 1)
		local lift = if i == 1 then p.tailLift * e elseif i == 2 then p.tailLift * 0.35 * e else 0
		local movingPitch = lift - 0.12 * e * math.sin(phase - lag)
		local idlePitch = 0.05 * math.sin(t * 1.3 - lag)
		local movingYaw = (0.08 + 0.06 * e) * math.sin(phase - lag)
		local idleYaw = 0.22 * math.sin(t * 1.6 - lag)
		table.insert(tail, {
			pitch = w * movingPitch + (1 - w) * idlePitch,
			yaw = (w * movingYaw + (1 - w) * idleYaw) * reach,
		})
	end
	return { legs = legs, bob = bob, rock = rock, head = head, tail = tail }
end

return Gait
