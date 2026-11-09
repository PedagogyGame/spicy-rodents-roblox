--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Animation.Gait
-- Procedural gait for the four-legged bodies (squirrel, Spicy Rodent, fox, deer) until their skinned
-- clips land (BUILD_PLAN §5.4): leg swing and knee bend from the stride phase, a body bob, a head nod
-- and a tail sway, all scaled by speed. Squirrels bound (front pair together, back pair opposite);
-- fox and deer trot (diagonal pairs together). Speed is the body's 3D speed, so climbing a trunk or
-- running along a wire animates the same way as running on the ground.
-- Pure numbers (Lune-testable); AnimationDriver turns a Pose into Motor6D.Transform values on the
-- RigSpec bone names (FrontL_Upper, ..., Tail1..n, Head, Root).
-- Interface: PROCEDURAL; params(species, hipHeight?) -> Params; advance(phase, speed, dt, params) -> phase;
--   pose(phase, speed, t, params, tailN) -> Pose

local Gait = {}

Gait.PROCEDURAL = { squirrel = true, rodent = true, fox = true, deer = true } :: { [string]: boolean }

export type Params = {
	bound: boolean, -- squirrel bound vs trot
	stride: number, -- studs travelled per full cycle at a run
	runSpeed: number, -- studs/s at which the swing reaches full amplitude
	swing: number, -- radians, full leg swing amplitude
	bob: number, -- studs, body bob at a full run
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
		return { bound = true, stride = math.max(hip * 3.2, 1.6), runSpeed = 16, swing = 0.75, bob = hip * 0.14 }
	elseif species == "fox" then
		return { bound = false, stride = math.max(hip * 2.6, 2), runSpeed = 18, swing = 0.6, bob = hip * 0.06 }
	end
	return { bound = false, stride = math.max(hip * 2.4, 3), runSpeed = 22, swing = 0.5, bob = hip * 0.05 }
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

function Gait.pose(phase: number, speed: number, t: number, p: Params, tailN: number): Pose
	local e = Gait.effort(speed, p)
	local moving = speed > 0.3
	local amp = if moving then p.swing * math.max(e, 0.35) else 0
	local offsets: { [string]: number }
	if p.bound then
		offsets = { FrontL = 0, FrontR = 0.25, BackL = math.pi, BackR = math.pi + 0.25 }
	else
		offsets = { FrontL = 0, BackR = 0, FrontR = math.pi, BackL = math.pi }
	end
	local legs = {}
	for name, off in offsets do
		local a = phase + off
		-- positive pitch about the bone's X swings the foot backward (-Z is forward in RigSpec)
		local upper = amp * math.sin(a)
		-- the knee folds while the foot swings forward (the recovery half of the cycle)
		local lower = amp * 0.9 * math.max(0, -math.cos(a))
		if string.sub(name, 1, 4) == "Back" then
			lower = -lower
		end
		legs[name] = { upper = upper, lower = lower }
	end
	local bobFreq = if p.bound then 1 else 2
	local bob = if moving then p.bob * e * math.abs(math.sin(phase * bobFreq)) else p.bob * 0.08 * math.sin(t * 2.2)
	local rock = if moving and p.bound then 0.12 * e * math.sin(phase) else 0
	local head = if moving then -0.6 * rock + 0.05 * e * math.sin(phase * 2) else 0.04 * math.sin(t * 0.9)
	local tail = {}
	local swayAmp = if moving then 0.1 + 0.08 * e else 0.22
	local swayRate = if moving then 6 + 4 * e else 1.6
	for i = 1, tailN do
		local lag = i * 0.7
		table.insert(tail, {
			pitch = (if moving then -0.18 * e * math.sin(phase - lag) else 0.05 * math.sin(t * 1.3 - lag)),
			yaw = swayAmp * math.sin(t * swayRate - lag) * (0.6 + 0.4 * i / math.max(tailN, 1)),
		})
	end
	return { legs = legs, bob = bob, rock = rock, head = head, tail = tail }
end

return Gait
