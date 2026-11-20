--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Controllers.KinematicPose
-- What a kinematic controller says about the body it moves, for the animation layer (owner rule
-- 2026-11-09: animation only poses the mesh, and it takes its stride from the motor, never from what the
-- body is seen to do). A controller that writes a body's pose itself (Controllers/Squirrel) publishes one
-- table per body and updates its fields every frame; Animation/AnimationDriver reads it: the stride phase
-- advances at `cadence`, the swing follows `moveSpeed`, and no height smoothing is layered on top of the
-- controller's own drawn pose.
-- Interface: set(body, pose); get(body) -> Pose?; clear(body)
-- Pure (weak-keyed by the body); no side effects on require.

export type Pose = {
	moveSpeed: number, -- studs/s, the motor's own speed
	cadence: number, -- rad/s of stride phase
	climb: number, -- 0 level .. 1 gripping a trunk or pole
	-- what the body is doing, for a rig that plays clips: "ground" | "trunk" | "rail" | "air"
	mode: string?,
	stalk: boolean?, -- creeping (Ctrl)
	winded: boolean?, -- out of fumes (the sprint meter ran out)
	-- how a body in the air left its surface: "leap" | "pounce" (nil: it fell), and the seconds the motor
	-- expects it to stay up
	action: string?,
	airSeconds: number?,
	-- the air trick (owner D17; Shared/Movement/AirTrick): the motor's move this flight (0 none, 1 roll, 2 wiggle) and
	-- the seconds of it left (0: none playing)
	trick: number?,
	trickLeft: number?,
	-- (owner D18) the twitch's aim as the motor applies it (radians; -1 in .. 1 out) and its seed (AirTrick.seedOf)
	trickAimYaw: number?,
	trickAimReach: number?,
	trickSeed: number?,
}

local KinematicPose = {}

local poses: { [any]: Pose } = setmetatable({}, { __mode = "k" }) :: any

function KinematicPose.set(body: any, pose: Pose)
	poses[body] = pose
end

function KinematicPose.get(body: any): Pose?
	return poses[body]
end

function KinematicPose.clear(body: any)
	poses[body] = nil
end

return KinematicPose
