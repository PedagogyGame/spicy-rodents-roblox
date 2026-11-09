--!strict
-- ReplicatedStorage.Shared.Routes.Curve
-- Centripetal Catmull-Rom (alpha 0.5, three.js r160 phantom ends, 200 arc divisions).
-- Interface (BUILD_PLAN routes_movement §1-§14): new(points), getPointAt(u), getSpacedPoints(n), length()
--
-- A line-for-line port of three.js r160 `CatmullRomCurve3` (curveType "centripetal", closed = false)
-- and the arc-length machinery of `Curve` (`getLengths` with 200 divisions, `getUtoTmapping` bisection,
-- `getPointAt`, `getTangent` with delta 1e-4, `getTangentAt`, `getSpacedPoints`). v5.4 builds every
-- climbing route this way (`addRoute`, reference/v5_4_game.js L302-311; routes_movement §1.1), so the
-- same maths gives the same samples, the same `t <-> arc length` mapping and the same tangents.
--
-- Unit-agnostic: points go in and come out in whatever unit the caller used (studs at runtime, HTML
-- units in the golden tests). Pure: no engine types, Lune-tested against tests/golden/curves.json and
-- all 1,332 harvested routes (spike S3, 0.01 u).

local Curve = {}
Curve.__index = Curve

export type Vec3 = { x: number, y: number, z: number }

export type Curve = typeof(setmetatable(
	{} :: {
		points: { Vec3 },
		arcLengthDivisions: number,
		_lengths: { number }?,
	},
	Curve
))

Curve.ARC_LENGTH_DIVISIONS = 200 -- three.js Curve default (routes_movement §20)

local function vec3(x: number, y: number, z: number): Vec3
	return { x = x, y = y, z = z }
end
Curve.vec3 = vec3

-- Non-uniform Catmull-Rom cubic coefficients (three.js CubicPoly.initNonuniformCatmullRom).
-- Returns c0..c3 for p(s) = c0 + c1 s + c2 s^2 + c3 s^3 on [0, 1].
local function nonuniformCoefficients(
	x0: number,
	x1: number,
	x2: number,
	x3: number,
	dt0: number,
	dt1: number,
	dt2: number
): (number, number, number, number)
	local t1 = (x1 - x0) / dt0 - (x2 - x0) / (dt0 + dt1) + (x2 - x1) / dt1
	local t2 = (x2 - x1) / dt1 - (x3 - x1) / (dt1 + dt2) + (x3 - x2) / dt2
	t1 *= dt1
	t2 *= dt1
	-- init(x1, x2, t1, t2)
	local c0 = x1
	local c1 = t1
	local c2 = -3 * x1 + 3 * x2 - 2 * t1 - t2
	local c3 = 2 * x1 - 2 * x2 + t1 + t2
	return c0, c1, c2, c3
end

local function distanceSquared(a: Vec3, b: Vec3): number
	local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
	return dx * dx + dy * dy + dz * dz
end

--[[
	new(points): an open centripetal Catmull-Rom through the control points (>= 2, all finite).
	Errors exactly where v5.4's addRoute throws (routes_movement §1.1): fewer than 2 points or a
	non-finite coordinate.
]]
function Curve.new(points: { Vec3 }): Curve
	if #points < 2 then
		error(`Curve.new: need at least 2 control points, got {#points}`)
	end
	local copy = table.create(#points)
	for i, p in points do
		local x, y, z = p.x, p.y, p.z
		if x ~= x or y ~= y or z ~= z or math.abs(x) == math.huge or math.abs(y) == math.huge or math.abs(z) == math.huge then
			error(`Curve.new: non-finite control point #{i}`)
		end
		copy[i] = vec3(x, y, z)
	end
	local self = setmetatable({
		points = copy :: { Vec3 },
		arcLengthDivisions = Curve.ARC_LENGTH_DIVISIONS,
		_lengths = nil :: { number }?,
	}, Curve)
	return self
end

-- fromArrays({{x, y, z}, ...}): the generated/ and harvest encoding of control points.
function Curve.fromArrays(arrays: { { number } }): Curve
	local pts = table.create(#arrays)
	for i, a in arrays do
		pts[i] = vec3(a[1], a[2], a[3])
	end
	return Curve.new(pts)
end

-- getPoint(t): raw (non arc-length) evaluation, t in [0, 1]. three.js CatmullRomCurve3.getPoint.
function Curve.getPoint(self: Curve, t: number): Vec3
	local points = self.points
	local l = #points
	local p = (l - 1) * t
	local intPoint = math.floor(p)
	local weight = p - intPoint

	if weight == 0 and intPoint == l - 1 then
		intPoint = l - 2
		weight = 1
	end

	-- three.js indexes points 0..l-1; Luau arrays are 1-based.
	local p0: Vec3
	local p0Extrapolated = false
	if intPoint > 0 then
		p0 = points[((intPoint - 1) % l) + 1]
	else
		-- extrapolate first point: points[0] - points[1] + points[0]
		local a, b = points[1], points[2]
		p0 = vec3(a.x - b.x + a.x, a.y - b.y + a.y, a.z - b.z + a.z)
		p0Extrapolated = true
	end
	local p1 = points[(intPoint % l) + 1]
	local p2 = points[((intPoint + 1) % l) + 1]
	local p3: Vec3
	if intPoint + 2 < l then
		p3 = points[((intPoint + 2) % l) + 1]
	else
		-- extrapolate last point: points[l-1] - points[l-2] + points[l-1]
		local a, b = points[l], points[l - 1]
		p3 = vec3(a.x - b.x + a.x, a.y - b.y + a.y, a.z - b.z + a.z)
		if p0Extrapolated then
			-- three.js r160 quirk, reproduced on purpose: both phantom ends are written into ONE shared
			-- scratch vector (`tmp`), so for a 2-point curve p0 aliases p3 (2*p_last - p_prev). The
			-- line is still straight but its raw parametrisation is cubic, which the game's
			-- getLengths/getUtoTmapping tables and the golden `getPoint`/`u2t` vectors carry. 144 of the
			-- 1,332 v5.4 routes have 2 control points (tests/golden/curves.json reproduces it).
			p0 = p3
		end
	end

	-- centripetal: pow 0.25 of the squared distances
	local dt0 = distanceSquared(p0, p1) ^ 0.25
	local dt1 = distanceSquared(p1, p2) ^ 0.25
	local dt2 = distanceSquared(p2, p3) ^ 0.25

	-- safety check for repeated points
	if dt1 < 1e-4 then
		dt1 = 1.0
	end
	if dt0 < 1e-4 then
		dt0 = dt1
	end
	if dt2 < 1e-4 then
		dt2 = dt1
	end

	local w2 = weight * weight
	local w3 = w2 * weight
	local c0, c1, c2, c3 = nonuniformCoefficients(p0.x, p1.x, p2.x, p3.x, dt0, dt1, dt2)
	local x = c0 + c1 * weight + c2 * w2 + c3 * w3
	c0, c1, c2, c3 = nonuniformCoefficients(p0.y, p1.y, p2.y, p3.y, dt0, dt1, dt2)
	local y = c0 + c1 * weight + c2 * w2 + c3 * w3
	c0, c1, c2, c3 = nonuniformCoefficients(p0.z, p1.z, p2.z, p3.z, dt0, dt1, dt2)
	local z = c0 + c1 * weight + c2 * w2 + c3 * w3
	return vec3(x, y, z)
end

-- getLengths(): cumulative chord lengths at t = i / 200, i = 0..200 (cached). three.js Curve.getLengths.
function Curve.getLengths(self: Curve): { number }
	local cached = self._lengths
	if cached then
		return cached
	end
	local divisions = self.arcLengthDivisions
	local cache = table.create(divisions + 1)
	local last = self:getPoint(0)
	local sum = 0
	cache[1] = 0
	for p = 1, divisions do
		local current = self:getPoint(p / divisions)
		local dx, dy, dz = current.x - last.x, current.y - last.y, current.z - last.z
		sum += math.sqrt(dx * dx + dy * dy + dz * dz)
		cache[p + 1] = sum
		last = current
	end
	self._lengths = cache
	return cache
end

-- getLength(): the 200-division polyline length (what addRoute stored as route.length).
function Curve.getLength(self: Curve): number
	local lengths = self:getLengths()
	return lengths[#lengths]
end

-- getUtoTmapping(u): arc-length fraction u in [0, 1] -> raw parameter t. three.js Curve.getUtoTmapping
-- (binary search over the cumulative table, then linear interpolation inside the segment).
function Curve.getUtoTmapping(self: Curve, u: number): number
	local arcLengths = self:getLengths()
	local il = #arcLengths
	local targetArcLength = u * arcLengths[il]

	-- three.js indexes 0..il-1; keep its arithmetic and shift by one when reading the table.
	local low, high = 0, il - 1
	local i = 0
	while low <= high do
		i = math.floor(low + (high - low) / 2)
		local comparison = arcLengths[i + 1] - targetArcLength
		if comparison < 0 then
			low = i + 1
		elseif comparison > 0 then
			high = i - 1
		else
			high = i
			break
		end
	end
	i = high

	if arcLengths[i + 1] == targetArcLength then
		return i / (il - 1)
	end

	local lengthBefore = arcLengths[i + 1]
	local lengthAfter = arcLengths[i + 2]
	local segmentLength = lengthAfter - lengthBefore
	local segmentFraction = (targetArcLength - lengthBefore) / segmentLength
	return (i + segmentFraction) / (il - 1)
end

-- getPointAt(u): arc-length parameterised point (the route centreline position for railT = u).
function Curve.getPointAt(self: Curve, u: number): Vec3
	return self:getPoint(self:getUtoTmapping(u))
end

-- getTangent(t): unit tangent by central difference with delta 1e-4, clamped at the ends.
function Curve.getTangent(self: Curve, t: number): Vec3
	local delta = 0.0001
	local t1 = t - delta
	local t2 = t + delta
	if t1 < 0 then
		t1 = 0
	end
	if t2 > 1 then
		t2 = 1
	end
	local pt1 = self:getPoint(t1)
	local pt2 = self:getPoint(t2)
	local x, y, z = pt2.x - pt1.x, pt2.y - pt1.y, pt2.z - pt1.z
	-- three.js Vector3.normalize: divide by (length || 1)
	local len = math.sqrt(x * x + y * y + z * z)
	if len == 0 then
		len = 1
	end
	return vec3(x / len, y / len, z / len)
end

-- getTangentAt(u): unit tangent at arc-length fraction u.
function Curve.getTangentAt(self: Curve, u: number): Vec3
	return self:getTangent(self:getUtoTmapping(u))
end

-- getSpacedPoints(divisions): divisions + 1 arc-length-spaced points (route.sampled in v5.4).
function Curve.getSpacedPoints(self: Curve, divisions: number): { Vec3 }
	local pts = table.create(divisions + 1)
	for d = 0, divisions do
		pts[d + 1] = self:getPointAt(d / divisions)
	end
	return pts
end

-- sampleSteps(length): v5.4's `steps = max(20, ceil(length * 3))` with length in HTML units
-- (routes_movement §1.1). The registry prefers the harvested sampleCount over recomputing this
-- (docs/reports/w0_check.md: ceil(3L) flips on a 1e-14 length difference at integer boundaries).
function Curve.sampleSteps(lengthInUnits: number): number
	return math.max(20, math.ceil(lengthInUnits * 3))
end

return Curve
