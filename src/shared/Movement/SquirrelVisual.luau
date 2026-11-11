--!strict
-- ReplicatedStorage.Shared.Movement.SquirrelVisual
-- The drawn squirrel (v5.4 L6757-6880, the part of updatePlayer that the first port left out). The motor
-- (Movement/SquirrelMotor) owns the authoritative position; what is drawn is a second point that follows it:
--   * position: every axis eases toward the motor's visual pose at 23/s (17/s while a transfer bridge
--     runs), integrated exactly for a moving target so the distance trailed does not depend on the frame
--     time. It cuts only when the motor's own pose jumps further than the motor travels in the frame
--     (2.5 u; 1.6 u on a rail): a teleport or a recovery. Mounting a rail from the ground or the air is
--     eased like a bridge; v5.4 tests the distance trailed instead and so teleports onto every pole;
--   * ground contact: while the motor stands on the ground the drawn height is the ground under the DRAWN
--     point (so the feet touch on a slope although the drawn point trails the motor), followed exactly at
--     the slope the ground has between the drawn point and the motor and eased beyond it, which spreads a
--     kerb or a plate lip over a few frames. Where a ledge separates the drawn point from the motor, and
--     while a landing is still arriving, the height eases toward the motor instead (v5.4's rule);
--   * heading: the motor's yaw on the ground and on branches and wires; on a trunk or a pole the body faces
--     the bark with its nose up (0.83 rad near the ground, straight up once the paws grip: v5.4's 1.43
--     rad, L6797-6846, leaves a sculpted body's fore paws in the bark and its hind feet off it);
--   * lean: a roll into turns from the yaw rate (L6817-6822), never on a trunk.
-- Nothing here feeds back into the motor: animation and drawing never move the authoritative position
-- (owner rule 2026-11-09). Pure numbers (Lune-tested); the client controller builds the CFrame.
-- `frame` is the whole drawn pose for one motor state (what Controllers/Squirrel draws): the eased point
-- (on a trunk pulled in from v5.4's pad until the paws meet the bark, standing off it by the fore paws'
-- reach while the body still leans; on a wire let down from v5.4's lift until they stand on the line),
-- heading, nose-up pitch and lean.
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
	-- the drawn feet are on the ground under them (false while arriving from the air, a rail or a ledge)
	contact: boolean,
	rail: boolean,
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
	mounted: boolean?, -- this frame took a rail from the ground or the air (eased, never cut)
	travel: number?, -- studs the motor moves in this frame by its own speed (not a teleport)
}

SquirrelVisual.params = {
	rate = 23, -- L6806
	bridgeRate = 17,
	snap = st(2.5), -- L6802
	railSnap = st(1.6),
	-- ground contact: the height change followed exactly per stud of drawn travel is the slope known here
	-- (the one followed last frame, or the one measured between the drawn point and the motor over at least
	-- lagFloor studs), at most contactSlope, plus contactBase per stud for curvature but never more than
	-- stepH in one frame (so the share of a kerb taken at once does not grow with speed or frame time);
	-- the rest is a step and eases at `rate`
	contactSlope = 1.5,
	contactBase = 0.25,
	stepH = 0.04,
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
	turnDtFloor = 1e-4, -- a divide guard only: a floor near a frame time under-reads fast displays
	-- trunk pose (L6846): nose-up pitch by how far the paws are off the ground. Once the paws grip the
	-- body lies along the bark (v5.4 has 1.43 rad: on the sculpted body, whose feet point is on the bark,
	-- those 8 degrees put the fore paws 0.03 studs into the trunk and the hind feet 0.08 off it)
	trunkPitchLow = 0.83,
	trunkPitchHigh = math.pi / 2,
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
	-- (0.3 until the sculpted body: its paws stood 0.4 studs off the bark, "floating"; the feet point is
	-- the soles of a skinned hero, so it belongs on the bark the motor takes the trunk to have)
	barkGap = 0,
	-- studs from the feet point forward to the fore paws at full reach. Until the nose is up the body
	-- leans on the trunk, and its feet point stands off the bark by this much of its lean (x cos pitch),
	-- so the fore paws meet the bark instead of going into it (with the feet point on the bark they went
	-- 0.32 studs in, and the nose after them, for the fifth of a second a trunk takes to mount)
	foreReach = 0.66,
	-- how far above a wire's own line the drawn feet point rides. The motor's visual pose is
	-- Motion.C.visualWireLift (0.55 studs) above it, which is where v5.4's body rode and where a leap off
	-- the wire starts; drawn there, the sculpted body ran half a stud above the line. A wire is drawn 0.15
	-- studs thick (worldgen RouteProps), so this is its top
	wireLift = 0.08,
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
		contact = false,
		rail = false,
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
	local lx, ly, lz = v.tx or tx, v.ty or ty, v.tz or tz
	v.tx, v.ty, v.tz = tx, ty, tz
	-- A teleport is a jump of the target itself, beyond what the motor travels in the frame. v5.4 tests
	-- the distance trailed instead, which cuts a long fall into a sawtooth (the lag grows with speed) and
	-- teleports the body onto a pole it walks into; a mount from the ground or the air is eased, as a
	-- bridge is.
	local jump = math.sqrt((tx - lx) ^ 2 + (ty - ly) ^ 2 + (tz - lz) ^ 2) - (mode.travel or 0)
	local cut = not mode.bridging and not mode.mounted and (jump > P.snap or (mode.rail and jump > P.railSnap))
	if not v.live or cut then
		v.x, v.y, v.z = tx, ty, tz
		v.live = true
		v.slope = 0
		v.contact = false
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
			-- beyond the known slope only a small height is taken at once (stepH, so the share of a kerb
			-- taken in one frame does not grow with the distance covered in it)
			local allow = math.min(P.contactSlope, known) * moved
				+ math.min(P.contactBase * moved, P.stepH)
				+ P.contactEps
			local d = gy - v.y
			if not v.contact and math.abs(eased - gy) > allow then
				-- still arriving (a landing, a dismount): ease to the motor, as v5.4 does, until the eased
				-- height meets the ground under the drawn point. Following that ground at once would dive
				-- to the foot of a platform the motor has just landed on.
				v.y = eased
				v.slope = 0
			elseif math.abs(d) <= allow then
				if moved > P.slopeMinMove then
					v.slope = math.abs(d) / moved
				end
				v.y = gy
				v.contact = true
			else
				local base = v.y + (if d > 0 then allow else -allow)
				v.y = base + (gy - base) * (1 - math.exp(-dt * rate))
				v.slope = 0
				v.contact = true
			end
		else
			v.y = eased
			v.slope = 0
			v.contact = false
		end
	else
		v.y = eased
		v.slope = 0
		v.contact = false
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
		pull -= P.foreReach * math.max(math.cos(v.pitch), 0)
		tx -= nx * pull
		tz -= nz * pull
	elseif route and route.kind == "wire" then
		ty -= C.visualWireLift - P.wireLift
	end
	local rail = route ~= nil
	local snapped = SquirrelVisual.update(v, tx, ty, tz, dt, {
		ground = not rail and state.grounded,
		rail = rail,
		bridging = state.bridge ~= nil,
		-- onto a rail from the ground or the air (a bridge covers rail to rail)
		mounted = rail and not v.rail and state.bridge == nil,
		travel = math.max(state.moveSpeed, math.sqrt(state.vx * state.vx + state.vy * state.vy + state.vz * state.vz))
			* dt,
	}, groundAt or world.groundAt)
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
	v.rail = rail
	v.yaw = targetYaw + v.yawOff
	v.climb = math.clamp(v.pitch / P.trunkPitchHigh, 0, 1)
	SquirrelVisual.lean(v, state.yaw, dt, onTrunk)
	v.moveSpeed = state.moveSpeed
	v.cadence = SquirrelVisual.cadence(state.moveSpeed, rail, state.boostRemaining > 0)
	return snapped
end

return SquirrelVisual
