--!strict
-- tests/lib/TreeClear: what stands where a tree would grow (the D32 tree shapes: data/tree_shapes.json, Shared/World/
-- TreeShapes). The town's paving (every road strip and footpath of the compiled roads, the expansion's streets,
-- their sidewalks, pads and paths), its lots (a tree's trunk may stand only on open ground: a park, lawn, garden,
-- the district ground or an estate's grounds; never on a building, structure, prop, slab or any other plate), the
-- solid boxes of World/Colliders (every building and structure, the built venues and the bowling alley: the boxes
-- WalkWay walks round) and the other trunks and poles. Pure Lune over Shared/Data; studs.
--   TreeClear.new(data) -> Clear
--   clear:paved(x, z, margin) -> string?          the strip or path a level point lies on, or within `margin` of
--   clear:lotAt(x, z, margin) -> string?          a lot that is not open ground holding the point (grown by margin)
--   clear:openGround(x, z) -> boolean              the point lies inside an open-ground lot
--   clear:boxAt(x, y, z, margin) -> string?        a solid box holding the point (grown by margin, up to its peak)
--   clear:nearestTrunk(x, z, skip) -> (number?, number)   the nearest trunk foot (level), `skip`ped ids left out
--   TreeClear.OPEN                                 the lot types a trunk may stand in
local Colliders = require("@shared/World/Colliders")

local TreeClear = {}

TreeClear.OPEN = table.freeze({
	park = true,
	lawn = true,
	garden = true,
	district_ground = true,
	estate_parcel = true,
})

type Rect = { id: string, x0: number, x1: number, z0: number, z1: number }
type Seg = { id: string, ax: number, az: number, bx: number, bz: number, half: number }
type Lot = { id: string, type: string, x0: number, x1: number, z0: number, z1: number }

export type Clear = {
	rects: { Rect },
	segs: { Seg },
	lots: { Lot },
	open: { Lot },
	colliders: any,
	trunks: { { id: number, x: number, z: number, r: number } },
	paved: (self: Clear, x: number, z: number, margin: number) -> string?,
	lotAt: (self: Clear, x: number, z: number, margin: number) -> string?,
	openGround: (self: Clear, x: number, z: number) -> boolean,
	boxAt: (self: Clear, x: number, y: number, z: number, margin: number) -> string?,
	nearestTrunk: (self: Clear, x: number, z: number, skip: { [number]: boolean }?) -> (number?, number),
}

local function stripRect(r: any): Rect?
	if r.axis == "x" then
		return {
			id = r.id,
			x0 = math.min(r.start, r["end"]),
			x1 = math.max(r.start, r["end"]),
			z0 = r.coord - r.width / 2,
			z1 = r.coord + r.width / 2,
		}
	elseif r.axis == "z" then
		return {
			id = r.id,
			x0 = r.coord - r.width / 2,
			x1 = r.coord + r.width / 2,
			z0 = math.min(r.start, r["end"]),
			z1 = math.max(r.start, r["end"]),
		}
	end
	return nil
end

local function segDist(s: Seg, x: number, z: number): number
	local dx, dz = s.bx - s.ax, s.bz - s.az
	local l2 = dx * dx + dz * dz
	local t = if l2 > 0 then math.clamp(((x - s.ax) * dx + (z - s.az) * dz) / l2, 0, 1) else 0
	local px, pz = s.ax + dx * t - x, s.az + dz * t - z
	return math.sqrt(px * px + pz * pz)
end

local function lotRect(lot: any): Lot?
	local fp = lot.footprint
	if fp == nil or fp.w == nil or fp.d == nil or fp.w <= 0 or fp.d <= 0 then
		return nil
	end
	local w, d = fp.w, fp.d
	if lot.facing == "+X" or lot.facing == "-X" then
		w, d = d, w
	end
	if lot.facing == nil and type(lot.yaw) == "number" and math.abs(math.sin(lot.yaw)) > 0.01 then
		-- (a turned lot: its bounding square)
		local h = math.sqrt(fp.w * fp.w + fp.d * fp.d) / 2
		return { id = lot.id, type = lot.type, x0 = lot.x - h, x1 = lot.x + h, z0 = lot.z - h, z1 = lot.z + h }
	end
	return {
		id = lot.id,
		type = lot.type,
		x0 = lot.x - w / 2,
		x1 = lot.x + w / 2,
		z0 = lot.z - d / 2,
		z1 = lot.z + d / 2,
	}
end

function TreeClear.new(data: any): Clear
	local rects: { Rect } = {}
	local segs: { Seg } = {}
	for _, r in data:roads() do
		if r.axis == "free" then
			table.insert(segs, {
				id = r.id,
				ax = r.start[1],
				az = r.start[2],
				bx = r["end"][1],
				bz = r["end"][2],
				half = r.width / 2,
			})
		else
			local rect = stripRect(r)
			if rect then
				table.insert(rects, rect)
			end
		end
	end
	local ex = data:module("Expansion") :: any
	if ex and ex.strips then
		for _, s in ex.strips do
			local rect = stripRect(s)
			if rect then
				table.insert(rects, rect)
			end
		end
		for _, p in ex.pads or {} do
			table.insert(rects, { id = p.id, x0 = p.rect.x0, x1 = p.rect.x1, z0 = p.rect.z0, z1 = p.rect.z1 })
		end
		for _, p in ex.paths or {} do
			for k = 1, #p.points - 1 do
				local a, b = p.points[k], p.points[k + 1]
				table.insert(segs, { id = p.id, ax = a[1], az = a[2], bx = b[1], bz = b[2], half = p.width / 2 })
			end
		end
	end
	local lt = data:module("LotTypes") :: any
	local types = if lt and lt.types then lt.types else {}
	local lots: { Lot } = {}
	local open: { Lot } = {}
	for _, lot in data:lots() do
		local rect = lotRect(lot)
		local t = types[lot.type]
		if rect then
			if TreeClear.OPEN[lot.type] then
				table.insert(open, rect)
			elseif t == nil or t.category ~= "marker" then
				table.insert(lots, rect)
			end
		end
	end
	local trunks = {}
	for _, r in data:routes():all() do
		if r.kind == "trunk" and r.enclosure == nil then
			local f = r.points[1]
			table.insert(trunks, { id = r.id, x = f.x, z = f.z, r = r.surfaceRadius })
		end
	end
	local self = {
		rects = rects,
		segs = segs,
		lots = lots,
		open = open,
		colliders = Colliders.fromData(data),
		trunks = trunks,
	} :: any

	function self.paved(s: Clear, x: number, z: number, margin: number): string?
		for _, r in s.rects do
			if x >= r.x0 - margin and x <= r.x1 + margin and z >= r.z0 - margin and z <= r.z1 + margin then
				return r.id
			end
		end
		for _, g in s.segs do
			if segDist(g, x, z) <= g.half + margin then
				return g.id
			end
		end
		return nil
	end
	function self.lotAt(s: Clear, x: number, z: number, margin: number): string?
		for _, r in s.lots do
			if x >= r.x0 - margin and x <= r.x1 + margin and z >= r.z0 - margin and z <= r.z1 + margin then
				return r.id
			end
		end
		return nil
	end
	function self.openGround(s: Clear, x: number, z: number): boolean
		for _, r in s.open do
			if x >= r.x0 and x <= r.x1 and z >= r.z0 and z <= r.z1 then
				return true
			end
		end
		return false
	end
	function self.boxAt(s: Clear, x: number, y: number, z: number, margin: number): string?
		for _, b in Colliders.query(s.colliders, x - margin, z - margin, x + margin, z + margin) do
			if
				math.abs(x - b.cx) <= b.hw + margin
				and math.abs(z - b.cz) <= b.hd + margin
				and y >= b.y0 - 1
				and y <= b.peak + margin
			then
				return b.id
			end
		end
		return nil
	end
	function self.nearestTrunk(s: Clear, x: number, z: number, skip: { [number]: boolean }?): (number?, number)
		local best, bd = nil, math.huge
		for _, t in s.trunks do
			if not (skip and skip[t.id]) then
				local d = math.sqrt((t.x - x) ^ 2 + (t.z - z) ^ 2)
				if d < bd then
					best, bd = t.id, d
				end
			end
		end
		return best, bd
	end
	return self :: Clear
end

return TreeClear
