--!strict
-- ReplicatedStorage.Shared.Minigames.Bowling.Approach
-- The bowler's approach as numbers (owner D32: "a nice approach animation (step, swing, release)"): when the
-- power button is let go the bowler walks four steps up the approach, pushes the ball away, swings it back and
-- through, slides on the left foot and lets go at the foul line; the throw is sent to the server at that moment
-- (Client/Minigames/BowlingClient), so the ball leaves the hand where the hand is. A follow-through is held a
-- moment after. Pure: the client turns a pose into the body's root place and its joints (R15: RightShoulder,
-- LeftHip, LeftKnee, RightHip, Waist; joint angles in radians, + swings a limb forward).
-- Lane frame: d down-lane from the foul line.
-- Pure; Lune-tested (tests/unit/bowling_feel.spec.luau).
-- Interface: TIME, FOLLOW, START_D, SLIDE_D, STEPS; pose(t) -> Pose (t seconds since the let-go; past TIME + FOLLOW
--   the bowler stands at the line, relaxed); releaseAt() -> TIME

local Approach = {}

Approach.TIME = 0.8 -- seconds from the let-go to the release
Approach.FOLLOW = 0.7 -- the follow-through held after it, easing back
Approach.START_D = -7.6 -- where the bowler waits, ball in hand (behind the ball return's hood)
Approach.SLIDE_D = -1.5 -- the root at the release: the sliding foot just short of the foul line
Approach.STEPS = 4

export type Pose = {
	d: number, -- the root's place down the lane
	drop: number, -- how far the root is lowered (studs: the bob of each step, the crouch of the slide)
	arm: number, -- the bowling arm at the shoulder (+ forward, - back)
	leadHip: number, -- the sliding (left) leg
	leadKnee: number, -- (- bends it)
	trailHip: number, -- the right leg swept back behind
	waist: number, -- + leans forward
}

local function smooth(a: number): number
	a = math.clamp(a, 0, 1)
	return a * a * (3 - 2 * a)
end

local function lerp(a: number, b: number, f: number): number
	return a + (b - a) * f
end

-- The arm through the approach, as key angles at fractions of it: push-away, down past the leg, the top of the
-- backswing, and through to the release (pendulum in between).
local ARM = { { 0, 0.15 }, { 0.22, 0.7 }, { 0.45, 0 }, { 0.72, -1.35 }, { 1, 0.75 } }

local function armAt(u: number): number
	for i = 2, #ARM do
		if u <= ARM[i][1] then
			local a, b = ARM[i - 1], ARM[i]
			return lerp(a[2], b[2], smooth((u - a[1]) / (b[1] - a[1])))
		end
	end
	return ARM[#ARM][2]
end

function Approach.releaseAt(): number
	return Approach.TIME
end

function Approach.pose(t: number): Pose
	if t <= 0 then
		return { d = Approach.START_D, drop = 0, arm = ARM[1][2], leadHip = 0, leadKnee = 0, trailHip = 0, waist = 0.05 }
	end
	if t <= Approach.TIME then
		local u = t / Approach.TIME
		-- the walk speeds up step by step (a slower first step, a long last slide)
		local g = u * u * (1.6 - 0.6 * u)
		local d = lerp(Approach.START_D, Approach.SLIDE_D, g)
		local slide = smooth((u - 0.72) / 0.28)
		local stride = math.sin(u * Approach.STEPS * math.pi)
		return {
			d = d,
			drop = 0.1 * math.abs(stride) * (1 - slide) + 0.2 * slide,
			arm = armAt(u),
			leadHip = 0.35 * stride * (1 - slide) + 0.55 * slide,
			leadKnee = -0.15 * math.abs(stride) * (1 - slide) - 0.75 * slide,
			trailHip = -0.35 * stride * (1 - slide) - 0.6 * slide,
			waist = 0.08 + 0.3 * slide,
		}
	end
	-- the follow-through: the arm up and out in front, the slide held, then easing back to standing
	local f = smooth((t - Approach.TIME) / Approach.FOLLOW)
	local hold = 1 - smooth((t - Approach.TIME - Approach.FOLLOW * 0.4) / (Approach.FOLLOW * 0.6))
	return {
		d = Approach.SLIDE_D,
		drop = 0.2 * hold,
		arm = lerp(ARM[#ARM][2], 1.6, smooth(f * 2)) * hold,
		leadHip = 0.55 * hold,
		leadKnee = -0.75 * hold,
		trailHip = -0.6 * hold,
		waist = 0.38 * hold,
	}
end

return Approach
