--!strict
-- ReplicatedStorage.Shared.Traffic.Swept
-- Exact sweptVehicleHit/segmentBoxEntry port (traffic §8.4).
-- Interface (BUILD_PLAN §1.4, D9): hit(...), broadPhase(...)
--
-- A statement-for-statement port of v5.4's fatal-traffic maths (reference/v5_4_game.js):
--   segmentBoxEntry(a, b, halfWidth, halfLength, minY, maxY)   L15786-15807  slab test, enter or nil
--   sweptVehicleHit(p0, p1, v0, v1, yaw0, yaw1, W, L, H)         L15808-15851  relative sweep with yaw
--                                                                 sub-steps of 0.05 rad and the
--                                                                 0.18 + 0.5*rho*|turn|/steps pad
--   finishTrafficFrame per-vehicle filter                          L15878        travel < 1e-5 or
--                                                                 travel > max(12, 80 dt + 2) skips
-- The three length constants (pad 0.18, box floor -0.3, box ceiling H - 0.16) are HTML units; every
-- function takes `scale` = studs per HTML unit (default 2.5 from Config/Units) so the same code checks
-- the golden vectors in HTML units (scale 1) and the live fleet in studs. `Math.hypot` is reproduced
-- the way V8 computes it (scaled sum of squares) so the pad matches the JS to the last bit.
-- Pure, allocation-free in the number-argument forms (hitN/entryN); Lune-tested against all 10,126
-- golden cases (tests/unit/traffic_swept.spec.luau).

local Units = require("../Config/Units")

local Swept = {}

export type Vec3 = { x: number, y: number, z: number }

Swept.PAD_UNITS = 0.18 -- squirrel body allowance (L15837)
Swept.FLOOR_UNITS = -0.3 -- box floor below the vehicle base (L15844)
Swept.CEILING_UNITS = 0.16 -- box ceiling below the vehicle top (L15845)
Swept.YAW_SUBSTEP = 0.05 -- rad per sub-step (L15824)
Swept.STATIONARY_UNITS = 1e-5 -- finishTrafficFrame: travel below this never kills (L15878)
Swept.TELEPORT_UNITS = 12 -- travel above max(12, 80 dt + 2) is a wrap/teleport (L15878)

local function isFinite(x: number): boolean
	return x == x and x ~= math.huge and x ~= -math.huge
end

-- V8's Math.hypot for two arguments: scale by the largest magnitude, Kahan-summed squares.
function Swept.hypot(a: number, b: number): number
	local x, y = math.abs(a), math.abs(b)
	local m = math.max(x, y)
	if m == 0 then
		return 0
	end
	if m == math.huge then
		return math.huge
	end
	local sx, sy = x / m, y / m
	-- Kahan summation of the two squares, as V8 does
	local sum = 0
	local compensation = 0
	for _, v in { sx * sx, sy * sy } do
		local preliminary = sum + v
		compensation += (sum - preliminary) + v
		sum = preliminary
	end
	return math.sqrt(sum + compensation) * m
end

-- segmentBoxEntry with number arguments: the parametric entry t in [0, 1] of segment a->b into the
-- box x in [-hw, hw], y in [minY, maxY], z in [-hl, hl], or nil. A segment that starts inside returns 0.
function Swept.entryN(
	ax: number,
	ay: number,
	az: number,
	bx: number,
	by: number,
	bz: number,
	halfWidth: number,
	halfLength: number,
	minY: number,
	maxY: number
): number?
	local enter, exit = 0, 1
	-- axis x
	local d = bx - ax
	if math.abs(d) < 1e-10 then
		if ax < -halfWidth or ax > halfWidth then
			return nil
		end
	else
		local t0, t1 = (-halfWidth - ax) / d, (halfWidth - ax) / d
		if t0 > t1 then
			t0, t1 = t1, t0
		end
		enter = math.max(enter, t0)
		exit = math.min(exit, t1)
		if enter > exit then
			return nil
		end
	end
	-- axis y
	d = by - ay
	if math.abs(d) < 1e-10 then
		if ay < minY or ay > maxY then
			return nil
		end
	else
		local t0, t1 = (minY - ay) / d, (maxY - ay) / d
		if t0 > t1 then
			t0, t1 = t1, t0
		end
		enter = math.max(enter, t0)
		exit = math.min(exit, t1)
		if enter > exit then
			return nil
		end
	end
	-- axis z
	d = bz - az
	if math.abs(d) < 1e-10 then
		if az < -halfLength or az > halfLength then
			return nil
		end
	else
		local t0, t1 = (-halfLength - az) / d, (halfLength - az) / d
		if t0 > t1 then
			t0, t1 = t1, t0
		end
		enter = math.max(enter, t0)
		exit = math.min(exit, t1)
		if enter > exit then
			return nil
		end
	end
	return enter
end

-- segmentBoxEntry(a, b, halfWidth, halfLength, minY, maxY) with vectors (the golden signature).
function Swept.segmentBoxEntry(
	a: Vec3,
	b: Vec3,
	halfWidth: number,
	halfLength: number,
	minY: number,
	maxY: number
): number?
	return Swept.entryN(a.x, a.y, a.z, b.x, b.y, b.z, halfWidth, halfLength, minY, maxY)
end

-- sweptVehicleHit with number arguments. p = squirrel reference point (start, end), v = vehicle origin
-- (footprint centre at the base), yaw = vehicle heading (HTML: forward = (sin yaw, cos yaw)), W/L/H =
-- the logical box, scale = studs per HTML unit for the three constants.
function Swept.hitN(
	p0x: number,
	p0y: number,
	p0z: number,
	p1x: number,
	p1y: number,
	p1z: number,
	v0x: number,
	v0y: number,
	v0z: number,
	v1x: number,
	v1y: number,
	v1z: number,
	yaw0: number,
	yaw1: number,
	width: number,
	length: number,
	height: number,
	scale: number?
): boolean
	if
		not (
			isFinite(p0x)
			and isFinite(p0y)
			and isFinite(p0z)
			and isFinite(p1x)
			and isFinite(p1y)
			and isFinite(p1z)
			and isFinite(v0x)
			and isFinite(v0y)
			and isFinite(v0z)
			and isFinite(v1x)
			and isFinite(v1y)
			and isFinite(v1z)
			and isFinite(yaw0)
			and isFinite(yaw1)
			and isFinite(width)
			and isFinite(length)
			and isFinite(height)
		)
	then
		return false
	end
	local k = scale or Units.STUDS_PER_UNIT
	local turn = math.atan2(math.sin(yaw1 - yaw0), math.cos(yaw1 - yaw0))
	local steps = math.max(1, math.ceil(math.abs(turn) / Swept.YAW_SUBSTEP))
	local r0x, r0y, r0z = p0x - v0x, p0y - v0y, p0z - v0z
	local r1x, r1y, r1z = p1x - v1x, p1y - v1y, p1z - v1z
	local radius = Swept.hypot(width, length) / 2
	local minY, maxY = Swept.FLOOR_UNITS * k, height - Swept.CEILING_UNITS * k
	local padBase = Swept.PAD_UNITS * k
	for i = 0, steps - 1 do
		local t0, t1 = i / steps, (i + 1) / steps
		-- three.js Vector3.lerp: a + (b - a) * t
		local ax, ay, az = r0x + (r1x - r0x) * t0, r0y + (r1y - r0y) * t0, r0z + (r1z - r0z) * t0
		local bx, by, bz = r0x + (r1x - r0x) * t1, r0y + (r1y - r0y) * t1, r0z + (r1z - r0z) * t1
		local yaw = yaw0 + (turn * (t0 + t1)) / 2
		local c, s = math.cos(yaw), math.sin(yaw)
		local padding = padBase + ((radius * math.abs(turn)) / steps) * 0.5
		if
			Swept.entryN(
				c * ax - s * az,
				ay,
				s * ax + c * az,
				c * bx - s * bz,
				by,
				s * bx + c * bz,
				width / 2 + padding,
				length / 2 + padding,
				minY,
				maxY
			) ~= nil
		then
			return true
		end
	end
	return false
end

-- sweptVehicleHit(p0, p1, v0, v1, yaw0, yaw1, width, length, height) with vectors.
function Swept.hit(
	p0: Vec3,
	p1: Vec3,
	v0: Vec3,
	v1: Vec3,
	yaw0: number,
	yaw1: number,
	width: number,
	length: number,
	height: number,
	scale: number?
): boolean
	return Swept.hitN(
		p0.x,
		p0.y,
		p0.z,
		p1.x,
		p1.y,
		p1.z,
		v0.x,
		v0.y,
		v0.z,
		v1.x,
		v1.y,
		v1.z,
		yaw0,
		yaw1,
		width,
		length,
		height,
		scale
	)
end

-- travelFilterSkips(travel, dt, scale): finishTrafficFrame's per-vehicle filter (L15878): a vehicle
-- that did not move never kills, and a wrap or teleport longer than max(12, 80 dt + 2) u is skipped.
function Swept.travelFilterSkips(travel: number, dt: number, scale: number?): boolean
	local k = scale or Units.STUDS_PER_UNIT
	return travel < Swept.STATIONARY_UNITS * k or travel > math.max(Swept.TELEPORT_UNITS * k, (dt * 80 + 2) * k)
end

-- broadPhase(...): a conservative sphere test around the relative segment. The vehicle box, inflated
-- by the largest pad any sub-step can use, fits in a sphere of radius `boxRadius` about its centre
-- (0, (maxY + minY) / 2, 0); the relative segment fits in a sphere about its midpoint. If those two
-- spheres do not touch there can be no hit, whatever the yaw. Returns true when the pair must go to
-- the exact test. Never rejects a true hit (tests/unit/traffic_swept.spec.luau proves it on the golden).
function Swept.broadPhase(
	p0x: number,
	p0y: number,
	p0z: number,
	p1x: number,
	p1y: number,
	p1z: number,
	v0x: number,
	v0y: number,
	v0z: number,
	v1x: number,
	v1y: number,
	v1z: number,
	yaw0: number,
	yaw1: number,
	width: number,
	length: number,
	height: number,
	scale: number?
): boolean
	local k = scale or Units.STUDS_PER_UNIT
	local turn = math.atan2(math.sin(yaw1 - yaw0), math.cos(yaw1 - yaw0))
	local steps = math.max(1, math.ceil(math.abs(turn) / Swept.YAW_SUBSTEP))
	local radius = Swept.hypot(width, length) / 2
	local padding = Swept.PAD_UNITS * k + ((radius * math.abs(turn)) / steps) * 0.5
	local hw, hl = width / 2 + padding, length / 2 + padding
	local minY, maxY = Swept.FLOOR_UNITS * k, height - Swept.CEILING_UNITS * k
	local hy = (maxY - minY) / 2
	local cy = (maxY + minY) / 2
	local boxRadius = math.sqrt(hw * hw + hl * hl + hy * hy)
	local r0x, r0y, r0z = p0x - v0x, p0y - v0y, p0z - v0z
	local r1x, r1y, r1z = p1x - v1x, p1y - v1y, p1z - v1z
	local mx, my, mz = (r0x + r1x) / 2, (r0y + r1y) / 2 - cy, (r0z + r1z) / 2
	local dx, dy, dz = r1x - r0x, r1y - r0y, r1z - r0z
	local half = math.sqrt(dx * dx + dy * dy + dz * dz) / 2
	local reach = boxRadius + half + 1e-9
	return mx * mx + my * my + mz * mz <= reach * reach
end

return Swept
