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
