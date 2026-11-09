--!strict
-- ServerScriptService.Server.WorldGen.Geometry
-- Pure geometry for the greybox bake (BUILD_PLAN §4.4 #7): lot frames (model-local -> world), the
-- PartSpec rotation (Ry(yaw) * Rx(pitch) * Rz(roll), the order Factory uses), oriented-box distance,
-- and a coarse XZ spatial hash over part boxes and wire segments. Used by the builders, by
-- RouteCheck (every route sample within surfaceRadius + 0.3 u of geometry or terrain) and by
-- DoorReach (every door reachable from a sidewalk).
-- Interface: frame(cx, cy, cz, yaw) -> Frame; rotate(v, yaw, pitch, roll) -> v; toLocal(spec, p) -> p;
--   boxDistance(spec, p) -> number; aabb(spec) -> x0, x1, y0, y1, z0, z1;
--   index(cell) -> Index with add(prim), near(x, z, r) -> { prim }; segmentDistance(a, b, p) -> number
-- Pure: no Instances, no state.

local Geometry = {}

export type Vec = { number } -- { x, y, z }

-- A lot frame: model-local (mx, my, mz) -> world; the model faces -Z (Roblox LookVector), so "toward
-- the front" is -mz. yaw is the model's Roblox yaw (Plan: quarter * pi/2 + pi).
export type Frame = { cx: number, cy: number, cz: number, yaw: number, c: number, s: number }

function Geometry.frame(cx: number, cy: number, cz: number, yaw: number): Frame
	return { cx = cx, cy = cy, cz = cz, yaw = yaw, c = math.cos(yaw), s = math.sin(yaw) }
end

-- Ry(yaw): (x cos + z sin, y, -x sin + z cos)
function Geometry.point(f: Frame, mx: number, my: number, mz: number): (number, number, number)
	return f.cx + mx * f.c + mz * f.s, f.cy + my, f.cz - mx * f.s + mz * f.c
end

function Geometry.rotate(v: Vec, yaw: number, pitch: number, roll: number): Vec
	local x, y, z = v[1], v[2], v[3]
	if roll ~= 0 then -- Rz
		local c, s = math.cos(roll), math.sin(roll)
		x, y = x * c - y * s, x * s + y * c
	end
	if pitch ~= 0 then -- Rx
		local c, s = math.cos(pitch), math.sin(pitch)
		y, z = y * c - z * s, y * s + z * c
	end
	if yaw ~= 0 then -- Ry
		local c, s = math.cos(yaw), math.sin(yaw)
		x, z = x * c + z * s, -x * s + z * c
	end
	return { x, y, z }
end

function Geometry.unrotate(v: Vec, yaw: number, pitch: number, roll: number): Vec
	local x, y, z = v[1], v[2], v[3]
	if yaw ~= 0 then
		local c, s = math.cos(-yaw), math.sin(-yaw)
		x, z = x * c + z * s, -x * s + z * c
	end
	if pitch ~= 0 then
		local c, s = math.cos(-pitch), math.sin(-pitch)
		y, z = y * c - z * s, y * s + z * c
	end
	if roll ~= 0 then
		local c, s = math.cos(-roll), math.sin(-roll)
		x, y = x * c - y * s, x * s + y * c
	end
	return { x, y, z }
end

export type Box = {
	cx: number,
	cy: number,
	cz: number,
	yaw: number,
	pitch: number,
	roll: number?,
	sx: number,
	sy: number,
	sz: number,
}

function Geometry.toLocal(b: Box, p: Vec): Vec
	return Geometry.unrotate({ p[1] - b.cx, p[2] - b.cy, p[3] - b.cz }, b.yaw, b.pitch, b.roll or 0)
end

-- Euclidean distance from p to the solid box (0 inside).
function Geometry.boxDistance(b: Box, p: Vec): number
	local l = Geometry.toLocal(b, p)
	local dx = math.max(math.abs(l[1]) - b.sx / 2, 0)
	local dy = math.max(math.abs(l[2]) - b.sy / 2, 0)
	local dz = math.max(math.abs(l[3]) - b.sz / 2, 0)
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- 2-D containment of (x, z) in the box's footprint (ignores y), with a margin in studs.
function Geometry.containsXZ(b: Box, x: number, z: number, margin: number): boolean
	local l = Geometry.toLocal(b, { x, b.cy, z })
	return math.abs(l[1]) <= b.sx / 2 + margin and math.abs(l[3]) <= b.sz / 2 + margin
end

function Geometry.aabb(b: Box): (number, number, number, number, number, number)
	local ax = Geometry.rotate({ b.sx / 2, 0, 0 }, b.yaw, b.pitch, b.roll or 0)
	local ay = Geometry.rotate({ 0, b.sy / 2, 0 }, b.yaw, b.pitch, b.roll or 0)
	local az = Geometry.rotate({ 0, 0, b.sz / 2 }, b.yaw, b.pitch, b.roll or 0)
	local ex = math.abs(ax[1]) + math.abs(ay[1]) + math.abs(az[1])
	local ey = math.abs(ax[2]) + math.abs(ay[2]) + math.abs(az[2])
	local ez = math.abs(ax[3]) + math.abs(ay[3]) + math.abs(az[3])
	return b.cx - ex, b.cx + ex, b.cy - ey, b.cy + ey, b.cz - ez, b.cz + ez
end

function Geometry.segmentDistance(a: Vec, b: Vec, p: Vec): number
	local abx, aby, abz = b[1] - a[1], b[2] - a[2], b[3] - a[3]
	local apx, apy, apz = p[1] - a[1], p[2] - a[2], p[3] - a[3]
	local len2 = abx * abx + aby * aby + abz * abz
	local t = if len2 > 0 then math.clamp((apx * abx + apy * aby + apz * abz) / len2, 0, 1) else 0
	local dx, dy, dz = apx - abx * t, apy - aby * t, apz - abz * t
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- Yaw/roll that point a part's local +X axis along d (cylinders: the axis is local X).
function Geometry.axisAngles(d: Vec): (number, number)
	local len = math.sqrt(d[1] * d[1] + d[2] * d[2] + d[3] * d[3])
	if len <= 0 then
		return 0, 0
	end
	local roll = math.asin(math.clamp(d[2] / len, -1, 1))
	local yaw = math.atan2(-d[3], d[1])
	return yaw, roll
end

-- Primitive for distance queries: a box, or a segment (wires) with a radius.
export type Prim = { box: Box?, a: Vec?, b: Vec?, r: number?, owner: string }

export type Index = {
	cell: number,
	cells: { [number]: { Prim } },
	count: number,
}

local function key(i: number, j: number): number
	return (i + 32768) * 65536 + (j + 32768)
end

function Geometry.index(cell: number): Index
	return { cell = cell, cells = {}, count = 0 }
end

function Geometry.add(ix: Index, prim: Prim)
	local x0, x1, z0, z1
	if prim.box then
		local ax0, ax1, _, _, az0, az1 = Geometry.aabb(prim.box)
		x0, x1, z0, z1 = ax0, ax1, az0, az1
	else
		local a, b = prim.a :: Vec, prim.b :: Vec
		local r = prim.r or 0
		x0, x1 = math.min(a[1], b[1]) - r, math.max(a[1], b[1]) + r
		z0, z1 = math.min(a[3], b[3]) - r, math.max(a[3], b[3]) + r
	end
	local c = ix.cell
	for i = math.floor(x0 / c), math.floor(x1 / c) do
		for j = math.floor(z0 / c), math.floor(z1 / c) do
			local k = key(i, j)
			local list = ix.cells[k]
			if not list then
				list = {}
				ix.cells[k] = list
			end
			table.insert(list, prim)
		end
	end
	ix.count += 1
end

-- Smallest distance from p to any primitive whose cells overlap the square of half-size r around p.
function Geometry.nearest(ix: Index, p: Vec, r: number): (number, Prim?)
	local c = ix.cell
	local best, bestPrim = math.huge, nil
	local seen: { [Prim]: boolean } = {}
	for i = math.floor((p[1] - r) / c), math.floor((p[1] + r) / c) do
		for j = math.floor((p[3] - r) / c), math.floor((p[3] + r) / c) do
			for _, prim in ix.cells[key(i, j)] or {} do
				if not seen[prim] then
					seen[prim] = true
					local d
					if prim.box then
						d = Geometry.boxDistance(prim.box, p)
					else
						d = math.max(Geometry.segmentDistance(prim.a :: Vec, prim.b :: Vec, p) - (prim.r or 0), 0)
					end
					if d < best then
						best, bestPrim = d, prim
					end
				end
			end
		end
	end
	return best, bestPrim
end

return Geometry
