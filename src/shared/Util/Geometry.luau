--!strict
-- ReplicatedStorage.Shared.Util.Geometry
-- AABB/OBB maths and the general segment-box slab test (traffic §8.4 generalised to any AABB; the
-- vehicle-local form with its golden vectors lives in Traffic/Swept and agrees with this one).
-- Pure; boxes are plain numbers so Lune and the engine share it (BUILD_PLAN §1.4 Util).
-- Interface: segmentBoxEntry(ax,ay,az, bx,by,bz, box) -> t?; aabbOverlap(a, b); aabbContains(box, x,y,z);
--            obbContains2(obb, x, z); obbOverlap2(a, b) (separating axis, x-z plane);
--            closestOnSegment(px,pz, ax,az, bx,bz) -> (t, distSq)

export type Aabb = { minX: number, minY: number, minZ: number, maxX: number, maxY: number, maxZ: number }
-- Oriented box in the x-z plane: centre, half extents along its local x and z, yaw (radians, about +Y).
export type Obb2 = { x: number, z: number, hx: number, hz: number, yaw: number }

local Geometry = {}

local PARALLEL = 1e-10

local function slab(a: number, d: number, lo: number, hi: number, enter: number, exit: number): (number, number)
	if math.abs(d) < PARALLEL then
		if a < lo or a > hi then
			return 1, 0 -- empty
		end
		return enter, exit
	end
	local t0, t1 = (lo - a) / d, (hi - a) / d
	if t0 > t1 then
		t0, t1 = t1, t0
	end
	return math.max(enter, t0), math.min(exit, t1)
end

-- Parametric entry t in [0, 1] of segment a->b into the box, or nil. Starting inside returns 0.
function Geometry.segmentBoxEntry(
	ax: number,
	ay: number,
	az: number,
	bx: number,
	by: number,
	bz: number,
	box: Aabb
): number?
	local enter, exit = 0, 1
	enter, exit = slab(ax, bx - ax, box.minX, box.maxX, enter, exit)
	if enter > exit then
		return nil
	end
	enter, exit = slab(ay, by - ay, box.minY, box.maxY, enter, exit)
	if enter > exit then
		return nil
	end
	enter, exit = slab(az, bz - az, box.minZ, box.maxZ, enter, exit)
	if enter > exit then
		return nil
	end
	return enter
end

function Geometry.aabbOverlap(a: Aabb, b: Aabb): boolean
	return a.minX <= b.maxX
		and b.minX <= a.maxX
		and a.minY <= b.maxY
		and b.minY <= a.maxY
		and a.minZ <= b.maxZ
		and b.minZ <= a.maxZ
end

function Geometry.aabbContains(box: Aabb, x: number, y: number, z: number): boolean
	return x >= box.minX and x <= box.maxX and y >= box.minY and y <= box.maxY and z >= box.minZ and z <= box.maxZ
end

-- Local axes of an Obb2: ux = (cos yaw, -sin yaw) and uz = (sin yaw, cos yaw), matching
-- CFrame.Angles(0, yaw, 0) applied to +X and +Z.
local function axes(o: Obb2): (number, number, number, number)
	local c, s = math.cos(o.yaw), math.sin(o.yaw)
	return c, -s, s, c
end

function Geometry.obbContains2(o: Obb2, x: number, z: number): boolean
	local uxx, uxz, uzx, uzz = axes(o)
	local dx, dz = x - o.x, z - o.z
	return math.abs(dx * uxx + dz * uxz) <= o.hx and math.abs(dx * uzx + dz * uzz) <= o.hz
end

function Geometry.obbOverlap2(a: Obb2, b: Obb2): boolean
	local axx, axz, azx, azz = axes(a)
	local bxx, bxz, bzx, bzz = axes(b)
	local dx, dz = b.x - a.x, b.z - a.z
	local candidates = { { axx, axz }, { azx, azz }, { bxx, bxz }, { bzx, bzz } }
	for _, ax in candidates do
		local nx, nz = ax[1], ax[2]
		local ra = a.hx * math.abs(axx * nx + axz * nz) + a.hz * math.abs(azx * nx + azz * nz)
		local rb = b.hx * math.abs(bxx * nx + bxz * nz) + b.hz * math.abs(bzx * nx + bzz * nz)
		if math.abs(dx * nx + dz * nz) > ra + rb then
			return false
		end
	end
	return true
end

-- Closest point on segment a-b to p, as (t in [0, 1], squared distance).
function Geometry.closestOnSegment(
	px: number,
	pz: number,
	ax: number,
	az: number,
	bx: number,
	bz: number
): (number, number)
	local dx, dz = bx - ax, bz - az
	local len2 = dx * dx + dz * dz
	local t = if len2 > 0 then math.clamp(((px - ax) * dx + (pz - az) * dz) / len2, 0, 1) else 0
	local cx, cz = ax + dx * t - px, az + dz * t - pz
	return t, cx * cx + cz * cz
end

return Geometry
