--!strict
-- ReplicatedStorage.Shared.Movement.SquirrelVisual
-- The drawn squirrel (v5.4 L6757-6880, the part of updatePlayer that the first port left out). The motor
-- (Movement/SquirrelMotor) owns the authoritative position; what is drawn is a second point that follows it:
--   * position: every axis eases toward the motor's visual pose at 23/s (17/s while a transfer bridge
--     runs), integrated exactly for a moving target so the distance trailed does not depend on the frame
--     time, and snaps only on a teleport-sized gap (2.5 u; 1.6 u on a rail outside a bridge);
--   * ground contact: while the motor stands on the ground the drawn height is the ground under the DRAWN
--     point (so the feet touch on a slope although the drawn point trails the motor), followed exactly at
--     the slope the ground has between the drawn point and the motor and eased beyond it, which spreads a
--     kerb or a plate lip over a few frames. Where a ledge separates the drawn point from the motor, the
--     height eases toward the motor instead (v5.4's rule);
--   * heading: the motor's yaw on the ground and on branches and wires; on a trunk or a pole the body faces
--     the bark with its nose up (0.83 rad near the ground, 1.43 rad once the paws grip, L6797-6846);
--   * lean: a roll into turns from the yaw rate (L6817-6822), never on a trunk.
-- Nothing here feeds back into the motor: animation and drawing never move the authoritative position
-- (owner rule 2026-11-09). Pure numbers (Lune-tested); the client controller builds the CFrame.
-- `frame` is the whole drawn pose for one motor state (what Controllers/Squirrel draws): the eased point
-- (on a trunk pulled in from v5.4's pad until the paws meet the bark), heading, nose-up pitch and lean.
-- v5.4 switches heading and pitch in one frame when a trunk is mounted or left; here the pitch eases and
-- the heading change is absorbed by an offset that decays, so nothing pops and steady turning has no lag.
-- Interface: new() -> Visual; frame(v, state, world, dt, groundAt?) -> snapped;
--   update(v, tx, ty, tz, dt, mode, groundAt?) -> snapped;
--   lean(v, yaw, dt, hold?) -> radians; trunkYaw(nx, nz) -> html yaw; trunkPitch(heightAboveGround) -> radians;
--   cadence(moveSpeed, rail, boosted) -> rad/s; params

local Units = require("../Config/Units")
local Height = require("../World/Height")
local Motion = require("../Routes/Motion")
local SquirrelMotor = require("./SquirrelMotor")

local st = Units.st
local C = Motion.C

local SquirrelVisual = {}

export type Visual = {
	x: number,
	y: number,
	z: number,
	live: boolean,
	-- the target of the last frame, and the ground slope followed exactly in it (update)
	tx: number?,
	ty: number?,
	tz: number?,
	slope: number,
	lean: number,
	lastYaw: number?,
	-- the drawn orientation (frame): html yaw, nose-up pitch, and how much of a trunk grip is showing
	yaw: number?,
	yawOff: number,
	pitch: number,
	trunk: boolean,
	climb: number,
	-- for the animation layer: the motor's speed (studs/s) and the stride rate (rad/s)
	moveSpeed: number,
	cadence: number,
}

export type Mode = {
	ground: boolean, -- the motor stands on the ground (no rail)
	rail: boolean,
	bridging: boolean, -- a transfer bridge is easing between two rails
}

SquirrelVisual.params = {
	rate = 23, -- L6806
	bridgeRate = 17,
	snap = st(2.5), -- L6802
	railSnap = st(1.6),
	-- ground contact: the height change followed exactly per stud of drawn travel is the slope known here
	-- (the one followed last frame, or the one measured between the drawn point and the motor over at least
	-- lagFloor studs) plus contactBase for curvature, at most contactSlope; the rest is a step and eases at
	-- `rate`
	contactSlope = 1.5,
	contactBase = 0.25,
	contactEps = 0.002,
	lagFloor = 0.25,
	slopeMinMove = 0.02,
	-- the drawn point uses its own ground while that is within this slope (x its lag) of the motor's height
	lagSlope = 1.5,
	lagEps = 0.05,
	-- turn lean (L6817-6822)
	leanPerTurn = 0.035,
	leanMax = 0.31,
	leanRate = 12,
	turnDtFloor = 0.012,
	-- trunk pose (L6846): nose-up pitch by how far the paws are off the ground
	trunkPitchLow = 0.83,
	trunkPitchHigh = 1.43,
	gripLow = st(0.25),
	gripHigh = st(2.4),
	-- stride cadence, radians per HTML unit travelled (L6824)
	cadenceGround = 2.85,
	cadenceRail = 0.7,
	cadenceBoost = 1.14,
	-- frame: the gap left between the drawn feet point and the surface climbed (v5.4 leaves its pad of
	-- 0.2 u / 0.28 u, which reads as hovering beside a pole at this scale), and the rate at which pitch
	-- and a heading switch ease
	poleGap = 0.07,
	barkGap = 0.3,
	poseRate = 16,
}
local P = SquirrelVisual.params

function SquirrelVisual.new(): Visual
	return {
		x = 0,
		y = 0,
		z = 0,
		live = false,
		tx = nil,
		ty = nil,
		tz = nil,
		slope = 0,
		lean = 0,
		lastYaw = nil,
		yaw = nil,
		yawOff = 0,
		pitch = 0,
		trunk = false,
		climb = 0,
		moveSpeed = 0,
		cadence = 0,
	}
end

-- x after dt of easing at `rate` toward a target that moved from t0 to t1 at a steady speed during the
-- frame (the exact solution of dx/dt = rate * (target - x)). v5.4 eases toward where the target is now,
-- which makes the distance trailed depend on the frame time (0.60 u behind a sprint at 60 Hz, 0.48 u at
-- 30 Hz) and so shows every uneven frame as a lurch; this trails by speed / rate at any frame time.
local function follow(x: number, t0: number, t1: number, rate: number, dt: number): number
	if dt <= 0 then
		return x
	end
	local lead = (t1 - t0) / (rate * dt)
	return t1 - (lead + (t0 - x - lead) * math.exp(-rate * dt))
end

-- One drawn frame toward the motor's visual pose (tx, ty, tz). Returns true when the point snapped
-- (first frame, teleport, recovery), so the camera can cut with it.
function SquirrelVisual.update(
	v: Visual,
	tx: number,
	ty: number,
	tz: number,
	dt: number,
	mode: Mode,
	groundAt: ((x: number, z: number, refY: number) -> number)?
): boolean
	local dx, dy, dz = tx - v.x, ty - v.y, tz - v.z
	local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
	local lx, ly, lz = v.tx or tx, v.ty or ty, v.tz or tz
	v.tx, v.ty, v.tz = tx, ty, tz
	if
		not v.live
		or (not mode.bridging and dist > P.snap)
		or (mode.rail and not mode.bridging and dist > P.railSnap)
	then
		v.x, v.y, v.z = tx, ty, tz
		v.live = true
		v.slope = 0
		return true
	end
	local rate = if mode.bridging then P.bridgeRate else P.rate
	local nx, nz = follow(v.x, lx, tx, rate, dt), follow(v.z, lz, tz, rate, dt)
	local moved = math.sqrt((nx - v.x) ^ 2 + (nz - v.z) ^ 2)
	local eased = follow(v.y, ly, ty, rate, dt)
	if mode.ground and groundAt then
		local lag = math.sqrt((tx - nx) ^ 2 + (tz - nz) ^ 2)
		local gy = groundAt(nx, nz, math.max(ty, v.y))
		if math.abs(gy - ty) <= P.lagSlope * lag + P.lagEps then
			-- the slope the ground has here: the one just followed, or the one between the drawn point and
			-- the motor ahead of it. A height change beyond that (a kerb or a plate lip just crossed) is a
			-- step, and the excess is eased
			local known = math.max(v.slope, math.abs(ty - gy) / math.max(lag, P.lagFloor))
			local allow = math.min(P.contactSlope, P.contactBase + known) * moved + P.contactEps
			local d = gy - v.y
			if math.abs(d) <= allow then
				if moved > P.slopeMinMove then
					v.slope = math.abs(d) / moved
				end
				v.y = gy
			else
				local base = v.y + (if d > 0 then allow else -allow)
				v.y = base + (gy - base) * (1 - math.exp(-dt * rate))
				v.slope = 0
			end
		else
			v.y = eased
			v.slope = 0
		end
	else
		v.y = eased
		v.slope = 0
	end
	v.x, v.z = nx, nz
	return false
end

-- The roll into a turn after this frame (v5.4 sign: negative leans into a turn of increasing yaw).
-- `hold` eases it back to level (on a trunk).
function SquirrelVisual.lean(v: Visual, yaw: number, dt: number, hold: boolean?): number
	local last = v.lastYaw or yaw
	v.lastYaw = yaw
	local turning = math.atan2(math.sin(yaw - last), math.cos(yaw - last)) / math.max(dt, P.turnDtFloor)
	local target = if hold then 0 else math.clamp(-turning * P.leanPerTurn, -P.leanMax, P.leanMax)
	v.lean += (target - v.lean) * (1 - math.exp(-dt * P.leanRate))
	return v.lean
end

-- HTML yaw that faces the bark, given the outward surface normal ("paws and claws point IN", L6797).
function SquirrelVisual.trunkYaw(nx: number, nz: number): number
	return math.atan2(-nx, -nz)
end

-- Nose-up pitch on a trunk, radians, from the height of the paws above the ground (studs).
function SquirrelVisual.trunkPitch(heightAboveGround: number): number
	local g = math.clamp((heightAboveGround - P.gripLow) / (P.gripHigh - P.gripLow), 0, 1)
	g = g * g * (3 - 2 * g)
	return P.trunkPitchLow + (P.trunkPitchHigh - P.trunkPitchLow) * g
end

-- Stride phase rate, rad/s, from the motor's own speed (studs/s): never from what the body is seen to do.
function SquirrelVisual.cadence(moveSpeed: number, rail: boolean, boosted: boolean): number
	return Units.u(moveSpeed)
		* (if rail then P.cadenceRail else P.cadenceGround)
		* (if boosted then P.cadenceBoost else 1)
end

local function shortest(a: number): number
	return math.atan2(math.sin(a), math.cos(a))
end

-- The drawn pose for the motor's state after its step this frame: v.x, v.y, v.z (the feet point), v.yaw
-- (html), v.pitch (nose up), v.lean (v5.4 sign), v.climb, v.moveSpeed, v.cadence. `groundAt` is the drawn
-- surface (the motor world's own when omitted). Returns true when the point snapped.
function SquirrelVisual.frame(
	v: Visual,
	state: SquirrelMotor.State,
	world: SquirrelMotor.World,
	dt: number,
	groundAt: ((x: number, z: number, refY: number) -> number)?
): boolean
	local target = SquirrelMotor.visualPose(state, world)
	local tx, ty, tz = target.x, target.y, target.z
	local route = if state.routeId then world.registry:get(state.routeId) else nil
	local onTrunk = route ~= nil and route.kind == "trunk"
	local nx, nz = 0, 1
	if route and onTrunk then
		if not route.flags.fixedSurfaceZ then
			nx, nz = state.trunkNormalX, state.trunkNormalZ
		end
		local pull = if route.flags.fixedSurfaceZ or route.flags.isPole
			then C.visualTrunkFixedPad - P.poleGap
			else C.visualTrunkPad - P.barkGap
		tx -= nx * pull
		tz -= nz * pull
	end
	local rail = route ~= nil
	local snapped = SquirrelVisual.update(
		v,
		tx,
		ty,
		tz,
		dt,
		{ ground = not rail and state.grounded, rail = rail, bridging = state.bridge ~= nil },
		groundAt or world.groundAt
	)
	local targetYaw = if onTrunk then SquirrelVisual.trunkYaw(nx, nz) else state.yaw
	local targetPitch = if onTrunk then SquirrelVisual.trunkPitch(v.y - Height.at(v.x, v.z)) else 0
	local last = v.yaw
	if last == nil or snapped then
		v.yawOff = 0
		v.pitch = targetPitch
	else
		if onTrunk ~= v.trunk then
			-- mounting or leaving a trunk: keep the heading drawn last frame and let the difference decay
			v.yawOff = shortest(last - targetYaw)
		end
		local k = math.exp(-dt * P.poseRate)
		v.yawOff *= k
		v.pitch = targetPitch + (v.pitch - targetPitch) * k
	end
	v.trunk = onTrunk
	v.yaw = targetYaw + v.yawOff
	v.climb = math.clamp(v.pitch / P.trunkPitchHigh, 0, 1)
	SquirrelVisual.lean(v, state.yaw, dt, onTrunk)
	v.moveSpeed = state.moveSpeed
	v.cadence = SquirrelVisual.cadence(state.moveSpeed, rail, state.boostRemaining > 0)
	return snapped
end

return SquirrelVisual
