--!strict
-- ReplicatedStorage.Shared.Paintball.Ballistics
-- Paintball flight and the geometric tests behind hit registration (D29; spike S18). Flight is
-- analytic, p(t) = o + v t - (0, g t^2 / 2, 0), so the client's predicted ball and the server's ball
-- agree exactly for the same muzzle state. Plain numbers only (no Vector3) so Lune runs it as is.
-- Interface: position(o, v, g, t), segmentCapsule(...) -> s?, segmentBox(...) -> (s?, nx, ny, nz),
--            aim(from, to, speed, g) -> (vx, vy, vz)

local Ballistics = {}

function Ballistics.position(
	ox: number,
	oy: number,
	oz: number,
	vx: number,
	vy: number,
	vz: number,
	g: number,
	t: number
): (number, number, number)
	return ox + vx * t, oy + vy * t - 0.5 * g * t * t, oz + vz * t
end

local function clamp01(v: number): number
	return if v < 0 then 0 elseif v > 1 then 1 else v
end

-- Closest approach between segment P0->P1 (the ball's step) and the vertical capsule axis
-- (cx, cyLow, cz)-(cx, cyHigh, cz); returns the parameter s in [0, 1] along the ball's step when the
-- distance is within r, else nil.
function Ballistics.segmentCapsule(
	p0x: number,
	p0y: number,
	p0z: number,
	p1x: number,
	p1y: number,
	p1z: number,
	cx: number,
	cyLow: number,
	cyHigh: number,
	cz: number,
	r: number
): number?
	local dx, dy, dz = p1x - p0x, p1y - p0y, p1z - p0z
	local ey = cyHigh - cyLow -- capsule axis is (0, ey, 0)
	local rx, ry, rz = p0x - cx, p0y - cyLow, p0z - cz
	local a = dx * dx + dy * dy + dz * dz
	local e = ey * ey
	local f = ey * ry
	local s, t
	if a <= 1e-12 then
		s = 0
		t = clamp01(f / e)
	else
		local c = dx * rx + dy * ry + dz * rz
		local b = dy * ey
		local denom = a * e - b * b
		s = if denom > 1e-12 then clamp01((b * f - c * e) / denom) else 0
		t = (b * s + f) / e
		if t < 0 then
			t = 0
			s = clamp01(-c / a)
		elseif t > 1 then
			t = 1
			s = clamp01((b - c) / a)
		end
	end
	local qx = p0x + dx * s - cx
	local qy = p0y + dy * s - (cyLow + ey * t)
	local qz = p0z + dz * s - cz
	if qx * qx + qy * qy + qz * qz <= r * r then
		return s
	end
	return nil
end

-- Slab test of segment P0->P1 against an axis-aligned box; returns the entry parameter and the face
-- normal, or nil. A segment starting inside reports s = 0 with a zero normal.
function Ballistics.segmentBox(
	p0x: number,
	p0y: number,
	p0z: number,
	p1x: number,
	p1y: number,
	p1z: number,
	minX: number,
	minY: number,
	minZ: number,
	maxX: number,
	maxY: number,
	maxZ: number
): (number?, number, number, number)
	local tEnter, tExit = 0, 1
	local axisHit, signHit = 0, 0
	-- unrolled per axis: this runs for every live ball against every box each frame, so no tables
	local da = p1x - p0x
	if math.abs(da) < 1e-12 then
		if p0x < minX or p0x > maxX then
			return nil, 0, 0, 0
		end
	else
		local t1, t2, sign = (minX - p0x) / da, (maxX - p0x) / da, -1
		if t1 > t2 then
			t1, t2, sign = t2, t1, 1
		end
		if t1 > tEnter then
			tEnter, axisHit, signHit = t1, 1, sign
		end
		tExit = math.min(tExit, t2)
		if tEnter > tExit then
			return nil, 0, 0, 0
		end
	end
	da = p1y - p0y
	if math.abs(da) < 1e-12 then
		if p0y < minY or p0y > maxY then
			return nil, 0, 0, 0
		end
	else
		local t1, t2, sign = (minY - p0y) / da, (maxY - p0y) / da, -1
		if t1 > t2 then
			t1, t2, sign = t2, t1, 1
		end
		if t1 > tEnter then
			tEnter, axisHit, signHit = t1, 2, sign
		end
		tExit = math.min(tExit, t2)
		if tEnter > tExit then
			return nil, 0, 0, 0
		end
	end
	da = p1z - p0z
	if math.abs(da) < 1e-12 then
		if p0z < minZ or p0z > maxZ then
			return nil, 0, 0, 0
		end
	else
		local t1, t2, sign = (minZ - p0z) / da, (maxZ - p0z) / da, -1
		if t1 > t2 then
			t1, t2, sign = t2, t1, 1
		end
		if t1 > tEnter then
			tEnter, axisHit, signHit = t1, 3, sign
		end
		tExit = math.min(tExit, t2)
		if tEnter > tExit then
			return nil, 0, 0, 0
		end
	end
	return tEnter,
		if axisHit == 1 then signHit else 0,
		if axisHit == 2 then signHit else 0,
		if axisHit == 3 then signHit else 0
end

-- Muzzle velocity that reaches (tx, ty, tz) from (fx, fy, fz) at `speed`, compensating the drop with
-- the flat-fire time of flight (good to a few cm inside the arena's 100-stud ranges).
function Ballistics.aim(
	fx: number,
	fy: number,
	fz: number,
	tx: number,
	ty: number,
	tz: number,
	speed: number,
	g: number
): (number, number, number)
	local dx, dy, dz = tx - fx, ty - fy, tz - fz
	local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
	if dist < 1e-6 then
		return 0, 0, speed
	end
	local tof = dist / speed
	dy += 0.5 * g * tof * tof
	local len = math.sqrt(dx * dx + dy * dy + dz * dz)
	return dx / len * speed, dy / len * speed, dz / len * speed
end

return Ballistics
