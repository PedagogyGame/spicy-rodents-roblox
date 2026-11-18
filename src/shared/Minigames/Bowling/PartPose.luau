--!strict
-- ReplicatedStorage.Shared.Minigames.Bowling.PartPose
-- Engine glue shared by the server's lane (Server/Minigames/BowlingLane) and the client's playback
-- (Client/Minigames/BowlingPlayback): a lane-frame pose from RollScript or LaneCycle becomes the CFrame of the
-- real part. Both sides use this one piece of arithmetic so the place a pin comes to rest on a client is
-- exactly where the server put it (the client's last write and the server's must agree, or pins would pop
-- when playback hands back). Engine types appear only inside the functions: Lune can require the module (and
-- the pure helpers are tested), it just cannot call the CFrame builders.
-- Lane frame: x across from the lane centre (bowler's right +), d down-lane from the foul line, y up.
-- Interface: pin(place, home, n, x, y, d, tilt, yaw) -> CFrame (home = the pin model's pivot standing on its
--   spot); ball(place, lane, x, y, d, turn) -> CFrame; world(place, lane, x, y, d) -> Vector3; fallAxis(place,
--   yaw) -> (ax, az) (pure: the level axis a pin tips about, in world x/z); HOME, RACK (attribute names the
--   server stamps on each pin model and ball so a client knows their resting poses)

local AlleyLayout = require("../../Attractions/AlleyLayout")
local PinModel = require("./PinModel")

local PartPose = {}

PartPose.HOME = "BowlHome" -- CFrame attribute on Pins.Pin<n>: its pivot standing on its spot
PartPose.RACK = "BowlRack" -- CFrame attribute on Ball: where it rests on the rack

-- The level axis a pin tips about so that its top falls toward `yaw` (radians from down-lane toward the
-- bowler's right): up crossed with the fall direction, as world x and z.
function PartPose.fallAxis(place: AlleyLayout.Place, yaw: number): (number, number)
	local fx, fz = AlleyLayout.dirToWorld(place, math.sin(yaw), math.cos(yaw))
	-- (0, 1, 0) x (fx, 0, fz) = (fz, 0, -fx)
	return fz, -fx
end

function PartPose.world(place: AlleyLayout.Place, lane: number, x: number, y: number, d: number): Vector3
	local wx, wy, wz = AlleyLayout.toWorld(place, AlleyLayout.laneX(lane) + x, y, d)
	return Vector3.new(wx, wy, wz)
end

function PartPose.pin(
	place: AlleyLayout.Place,
	home: CFrame,
	n: number,
	x: number,
	y: number,
	d: number,
	tilt: number,
	yaw: number
): CFrame
	local sx, sd = PinModel.spot(n)
	local dx, dz = AlleyLayout.dirToWorld(place, x - sx, d - sd)
	local at = home.Position + Vector3.new(dx, y, dz)
	local rot = home.Rotation
	if tilt ~= 0 then
		local ax, az = PartPose.fallAxis(place, yaw)
		rot = CFrame.fromAxisAngle(Vector3.new(ax, 0, az), tilt) * rot
	end
	return CFrame.new(at) * rot
end

function PartPose.ball(place: AlleyLayout.Place, lane: number, x: number, y: number, d: number, turn: number): CFrame
	return CFrame.new(PartPose.world(place, lane, x, y, d))
		* CFrame.Angles(0, AlleyLayout.yawOf(place), 0)
		* CFrame.Angles(-turn, 0, 0)
end

return PartPose
