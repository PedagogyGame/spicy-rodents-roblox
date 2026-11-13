--!strict
-- ReplicatedStorage.Shared.World.Colliders
-- Data colliders in a spatial hash (BUILD_PLAN §1.4 World/Colliders, §4.4 #2): one box per solid
-- lot (lot-type category building or structure with a height), seated at World/Height at the lot
-- centre [worldgen_core §3], footprint w along world X and d along world Z (worldgen_districts_art
-- §0 axes note). Roofs: flat at the eave, or a gable rising linearly from the eave at the long
-- walls to the peak at the ridge line (lot params eaveU/peakU/ridge; lot-type heightU otherwise).
-- These are the pure, server-and-client answers the motors and validators need (wall tests,
-- roofs to land on); the engine's own baked parts collide for physics bodies.
-- Interface: new(cell?) -> Colliders; add(c, box); fromData(data, seatAt?) -> Colliders (the solid lots and the
--   built expansion venues); addBuiltVenues(c, data) -> n;
--   query(c, minX, minZ, maxX, maxZ) -> { Box }; pointIn(c, x, z, y, pad?) -> Box?;
--   blocked(c, x0, z0, x1, z1, r, refY) -> boolean (swept circle, studs); roofAt(c, x, z, refY) -> number?
-- Pure; studs. No side effects on require.

local Height = require("./Height")

export type Box = {
	id: string,
	cx: number,
	cz: number,
	hw: number, -- half extent along X
	hd: number, -- half extent along Z
	y0: number, -- base (seat)
	eave: number, -- absolute
	peak: number, -- absolute (== eave for flat roofs)
	ridge: "x" | "z" | nil, -- ridge line axis for gables
}

export type Colliders = {
	cell: number,
	cells: { [number]: { Box } },
	boxes: { Box },
}

local Colliders = {}

local S = Height.STUDS_PER_UNIT
-- v5.4 roof rule: the body counts as on a roof when it is no more than 0.47 u below it (L6236)
Colliders.ROOF_SNAP = 0.47 * S

local function key(ix: number, iz: number): number
	return (ix + 1048576) * 2097152 + (iz + 1048576)
end

function Colliders.new(cell: number?): Colliders
	return { cell = cell or 40, cells = {}, boxes = {} }
end

function Colliders.add(c: Colliders, box: Box)
	table.insert(c.boxes, box)
	local s = c.cell
	for ix = math.floor((box.cx - box.hw) / s), math.floor((box.cx + box.hw) / s) do
		for iz = math.floor((box.cz - box.hd) / s), math.floor((box.cz + box.hd) / s) do
			local k = key(ix, iz)
			local list = c.cells[k]
			if not list then
				list = {}
				c.cells[k] = list
			end
			table.insert(list, box)
		end
	end
end

-- fromData(data, seatAt?): every solid lot as a box. `data` is Shared/Data (lots(), module()).
function Colliders.fromData(data: any, seatAt: ((x: number, z: number) -> number)?): Colliders
	local c = Colliders.new()
	local lt = data:module("LotTypes") :: any
	local types = if lt and lt.types then lt.types else {}
	local seat = seatAt or Height.at
	for _, lot in data:lots() do
		local t = types[lot.type]
		local fp = lot.footprint
		if not t or not fp or (t.category ~= "building" and t.category ~= "structure") then
			continue
		end
		local p = lot.params or {}
		local eaveU = p.eaveU or t.heightU or 0
		if eaveU <= 0 then
			continue
		end
		local peakU = if p.roof == "gable" or (p.roof == nil and t.roof == "gable") then (p.peakU or eaveU) else eaveU
		local y0 = seat(lot.x, lot.z)
		local ridge: "x" | "z" | nil = nil
		if peakU > eaveU then
			ridge = if p.ridge == "x" or p.ridge == "z" then p.ridge elseif fp.w >= fp.d then "x" else "z"
		end
		Colliders.add(c, {
			id = lot.id,
			cx = lot.x,
			cz = lot.z,
			hw = fp.w * 0.5,
			hd = fp.d * 0.5,
			y0 = y0,
			eave = y0 + eaveU * S,
			peak = y0 + peakU * S,
			ridge = ridge,
		})
	end
	Colliders.addBuiltVenues(c, data)
	return c
end

-- The expansion venues that are built (generated/Expansion: a venue with `built`, the bake that makes it, such
-- as the owner's Neighbourhood Shop): its footprint as a box from the lowest ground under it, a gable from
-- half its height up to its full height with the ridge along its longer side. Planned venues are not boxes:
-- nothing stands there yet.
function Colliders.addBuiltVenues(c: Colliders, data: any): number
	local ex = data:module("Expansion") :: any
	local n = 0
	for _, v in (if ex and ex.venues then ex.venues else {}) :: { any } do
		local poly = v.footPoly
		if v.built == nil or poly == nil or #poly < 3 then
			continue
		end
		local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
		for _, p in poly do
			minX, maxX = math.min(minX, p[1]), math.max(maxX, p[1])
			minZ, maxZ = math.min(minZ, p[2]), math.max(maxZ, p[2])
		end
		local y0 = if v.ground then v.ground.min else v.floorY
		local w, d = maxX - minX, maxZ - minZ
		Colliders.add(c, {
			id = v.id,
			cx = (minX + maxX) / 2,
			cz = (minZ + maxZ) / 2,
			hw = w / 2,
			hd = d / 2,
			y0 = y0,
			eave = v.floorY + v.height * 0.5,
			peak = v.floorY + v.height,
			ridge = if w >= d then "x" else "z",
		})
		n += 1
	end
	return n
end

function Colliders.query(c: Colliders, minX: number, minZ: number, maxX: number, maxZ: number): { Box }
	local s = c.cell
	local out, seen = {}, {}
	for ix = math.floor(minX / s), math.floor(maxX / s) do
		for iz = math.floor(minZ / s), math.floor(maxZ / s) do
			local list = c.cells[key(ix, iz)]
			if list then
				for _, b in list do
					if
						not seen[b]
						and b.cx + b.hw >= minX
						and b.cx - b.hw <= maxX
						and b.cz + b.hd >= minZ
						and b.cz - b.hd <= maxZ
					then
						seen[b] = true
						table.insert(out, b)
					end
				end
			end
		end
	end
	return out
end

-- roof height of a box at (x, z) (inside its footprint)
function Colliders.roofOf(b: Box, x: number, z: number): number
	if b.ridge == nil then
		return b.eave
	end
	local f = if b.ridge == "x" then 1 - math.abs(z - b.cz) / b.hd else 1 - math.abs(x - b.cx) / b.hw
	return b.eave + (b.peak - b.eave) * math.clamp(f, 0, 1)
end

-- pointIn(c, x, z, y, pad): the box whose footprint (+pad) holds (x, z) with y between base and roof.
function Colliders.pointIn(c: Colliders, x: number, z: number, y: number, pad: number?): Box?
	local r = pad or 0
	local list = c.cells[key(math.floor(x / c.cell), math.floor(z / c.cell))]
	if not list then
		return nil
	end
	for _, b in list do
		if math.abs(x - b.cx) < b.hw + r and math.abs(z - b.cz) < b.hd + r then
			if y >= b.y0 - 0.5 and y < Colliders.roofOf(b, x, z) - 0.05 then
				return b
			end
		end
	end
	return nil
end

-- blocked(c, x0, z0, x1, z1, r, refY): does a circle of radius r moving from (x0,z0) to (x1,z1) at
-- height refY enter any box below its roof? Sampled at r/2 steps (exact enough for motors at 60 Hz).
function Colliders.blocked(
	c: Colliders,
	x0: number,
	z0: number,
	x1: number,
	z1: number,
	r: number,
	refY: number
): boolean
	local dx, dz = x1 - x0, z1 - z0
	local len = math.sqrt(dx * dx + dz * dz)
	local n = math.max(1, math.ceil(len / math.max(0.25, r * 0.5)))
	for i = 1, n do
		local t = i / n
		if Colliders.pointIn(c, x0 + dx * t, z0 + dz * t, refY, r) then
			return true
		end
	end
	return false
end

-- roofAt(c, x, z, refY): the highest roof under (x, z) the body can stand on (refY no more than
-- ROOF_SNAP below it), else nil.
function Colliders.roofAt(c: Colliders, x: number, z: number, refY: number): number?
	local list = c.cells[key(math.floor(x / c.cell), math.floor(z / c.cell))]
	if not list then
		return nil
	end
	local best: number? = nil
	for _, b in list do
		if math.abs(x - b.cx) < b.hw and math.abs(z - b.cz) < b.hd then
			local top = Colliders.roofOf(b, x, z)
			if refY >= top - Colliders.ROOF_SNAP and (best == nil or top > best) then
				best = top
			end
		end
	end
	return best
end

return Colliders
