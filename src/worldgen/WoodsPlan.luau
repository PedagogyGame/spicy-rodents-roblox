--!strict
-- ServerScriptService.Server.WorldGen.WoodsPlan
-- Where the D34 woods may grow (owner, 2026-11-22: "a large scattered introduction of pine trees and other nut trees,
-- making the map have more trees!"). The woods are scenery trees (Shared/Generated/Woods; Server/Assets/WoodsArt
-- puts their uploaded Models there at runtime, outside the town bake): pines, spruces, firs and nut trees in the
-- town's parks, yards and verges, groves at the edges, on Lookout Hill and on the ridge. This module holds the one
-- rule for "may a trunk stand here, and may its crown spread here", over the town as baked, so that the placement
-- tool (tools/blender/trees/place_woods.luau, which writes data/woods.json) and the spec that holds every placement
-- to it (tests/unit/woods.spec.luau) ask the same question.
-- What a woods tree keeps clear of (studs; `pad` past the thing's outline, from the trunk's centre):
--   paving       every part of every road plan (streets, sidewalks, driveways, kerbs, paint), the expansion's
--                streets, pads and paths, the Quay's cobbled ground: PAVING
--   lots         every lot that is not open ground (a park, a lawn or an estate's grounds), whole, and every part of
--                every lot plan that is not its own flat lawn (gazebos, benches, playgrounds, fences, garden
--                plots): LOT; every solid box of World/Colliders (buildings, built venues, the bowling alley) and
--                every expansion venue's site: BOX, and at least CROWN_OVER of the tree's crown from a box
--   street gear  lamps, poles, pipes and fences: GEAR; the telephone wires and the sky lift's cable: CROWN_OVER of
--                the crown, at least WIRE
--   doors        a door or a door step of any lot: DOOR
--   trees        every route tree's trunk (the climbing trees: harvested, hollow, D32 planted, D34 grown) by
--                TREE_SHARE of the two crowns' reaches added, never nearer than TREE_MIN; and one woods tree from
--                another by WOODS_SHARE of theirs, never nearer than WOODS_MIN
--   nut spots    Shared/Foraging/NutSpots: NUT
--   open zones   the kite fields and the jet-ski water (Expansion zones): ZONE
--   ground       inside the world clamp by EDGE, out of the river by RIVER, short of the beach and the sea
--                (z < BEACH_Z), on ground no steeper than SLOPE over a trunk's width either way
-- Interface:
--   WoodsPlan.build(data, plans, heightAt, extra) -> World    `data`: Bake.data() plus { expansion, colliders,
--     nutSpots, trees = { {x, z, reach} }, wires = { { {x,z}, ... } }, rides = { { {x,z}, ... } }, clamp };
--     `plans`: Bake.plans(data); heightAt: World/Height.at; insideWater: World/Height.insideRiverWater
--   WoodsPlan.check(world, x, z, crown, others?) -> string?    why a tree whose crown reaches `crown` may not stand at
--     (x, z) (nil: it may); `others` the woods trees placed so far ({ {x, z, crown} })
--   WoodsPlan.rng(seed) -> () -> number                        deterministic xorshift32 in [0, 1)
--   WoodsPlan.C                                                the numbers above
-- Pure (no engine calls); studs, world space.

local WoodsPlan = {}

WoodsPlan.C = table.freeze({
	PAVING = 6,
	LOT = 4,
	BOX = 5,
	CROWN_OVER = 0.7, -- of a crown's reach: how far it stays from a building, a wire or the cable
	GEAR = 3.5,
	WIRE = 8,
	DOOR = 14,
	TREE_SHARE = 0.75,
	TREE_MIN = 22,
	WOODS_SHARE = 0.5, -- the thinnest a grove may be (data/woods.json `share`: the town's 0.8, the edges' copses 0.5)
	WOODS_MIN = 9,
	NUT = 6,
	ZONE = 12,
	EDGE = 24,
	RIVER = 10,
	BEACH_Z = 1090,
	SLOPE = 0.45, -- rise over run across 2 x 4 studs
	OPEN = table.freeze({ park = true, lawn = true, estate_parcel = true }),
	GRASS = table.freeze({ Grass = true, LeafyGrass = true, SmoothPlastic = true, Ground = false }),
	CELL = 48,
})

-- deterministic xorshift32 in [0, 1)
function WoodsPlan.rng(seed: number): () -> number
	local s = (seed * 2654435761 + 12345) % 4294967296
	if s == 0 then
		s = 0x9e3779b9
	end
	return function(): number
		s = bit32.bxor(s, bit32.lshift(s, 13))
		s = bit32.bxor(s, bit32.rshift(s, 17))
		s = bit32.bxor(s, bit32.lshift(s, 5))
		return s / 4294967296
	end
end

-- An obstacle: an axis-aligned rect (x0..x1, z0..z1), a segment (a -> b, half width) or a disc. `pad` is the trunk's
-- clearance past its outline; `crown` true: also at least CROWN_OVER of the crown's reach.
export type Item = {
	what: string,
	shape: string, -- "rect" | "seg" | "disc"
	x0: number,
	x1: number,
	z0: number,
	z1: number,
	ax: number,
	az: number,
	bx: number,
	bz: number,
	r: number,
	pad: number,
	crown: boolean,
	tree: boolean?, -- a route tree's crown (reach r): TREE_SHARE rule
}

export type World = {
	cells: { [number]: { Item } },
	items: { Item },
	clamp: { minX: number, maxX: number, minZ: number, maxZ: number },
	heightAt: (number, number) -> number,
	insideWater: (number, number) -> boolean,
}

local function key(i: number, k: number): number
	return (i + 4096) * 8192 + (k + 4096)
end

local function bounds(it: Item): (number, number, number, number)
	if it.shape == "rect" then
		return it.x0, it.x1, it.z0, it.z1
	elseif it.shape == "seg" then
		return math.min(it.ax, it.bx) - it.r,
			math.max(it.ax, it.bx) + it.r,
			math.min(it.az, it.bz) - it.r,
			math.max(it.az, it.bz) + it.r
	end
	return it.ax - it.r, it.ax + it.r, it.az - it.r, it.az + it.r
end

-- the farthest any item reaches out for a tree (its pad, or a crown's share, or a route tree's): the grid's reach
local REACH = 70

local function insert(w: World, it: Item)
	table.insert(w.items, it)
	local x0, x1, z0, z1 = bounds(it)
	local c = WoodsPlan.C.CELL
	for i = math.floor((x0 - REACH) / c), math.floor((x1 + REACH) / c) do
		for k = math.floor((z0 - REACH) / c), math.floor((z1 + REACH) / c) do
			local kk = key(i, k)
			local list = w.cells[kk]
			if not list then
				list = {}
				w.cells[kk] = list
			end
			table.insert(list, it)
		end
	end
end

local function rect(what: string, x0: number, x1: number, z0: number, z1: number, pad: number, crown: boolean): Item
	return {
		what = what,
		shape = "rect",
		x0 = x0,
		x1 = x1,
		z0 = z0,
		z1 = z1,
		ax = 0,
		az = 0,
		bx = 0,
		bz = 0,
		r = 0,
		pad = pad,
		crown = crown,
	}
end

local function seg(
	what: string,
	ax: number,
	az: number,
	bx: number,
	bz: number,
	half: number,
	pad: number,
	crown: boolean
): Item
	return {
		what = what,
		shape = "seg",
		x0 = 0,
		x1 = 0,
		z0 = 0,
		z1 = 0,
		ax = ax,
		az = az,
		bx = bx,
		bz = bz,
		r = half,
		pad = pad,
		crown = crown,
	}
end

local function disc(what: string, x: number, z: number, r: number, pad: number, crown: boolean): Item
	return {
		what = what,
		shape = "disc",
		x0 = 0,
		x1 = 0,
		z0 = 0,
		z1 = 0,
		ax = x,
		az = z,
		bx = x,
		bz = z,
		r = r,
		pad = pad,
		crown = crown,
	}
end

-- distance from (x, z) to the item's outline (0 inside)
local function dist(it: Item, x: number, z: number): number
	if it.shape == "rect" then
		local dx = math.max(it.x0 - x, 0, x - it.x1)
		local dz = math.max(it.z0 - z, 0, z - it.z1)
		return math.sqrt(dx * dx + dz * dz)
	end
	local dx, dz = it.bx - it.ax, it.bz - it.az
	local l2 = dx * dx + dz * dz
	local t = if l2 > 0 then math.clamp(((x - it.ax) * dx + (z - it.az) * dz) / l2, 0, 1) else 0
	local px, pz = it.ax + dx * t - x, it.az + dz * t - z
	return math.max(0, math.sqrt(px * px + pz * pz) - it.r)
end
WoodsPlan.dist = dist

-- a part's level bounding rect (yaw, then pitch about its own X, then roll about its own Z)
local function footprint(s: any): (number, number, number, number)
	local cy, sy = math.cos(s.yaw or 0), math.sin(s.yaw or 0)
	local cp, sp = math.cos(s.pitch or 0), math.sin(s.pitch or 0)
	local cr, sr = math.cos(s.roll or 0), math.sin(s.roll or 0)
	-- R = Ry * Rx * Rz; rows 1 and 3 (world x and z) of the columns for local X, Y, Z
	local r11, r12, r13 = cy * cr + sy * sp * sr, -cy * sr + sy * sp * cr, sy * cp
	local r31, r32, r33 = -sy * cr + cy * sp * sr, sy * sr + cy * sp * cr, cy * cp
	local hx = (math.abs(r11) * s.sx + math.abs(r12) * s.sy + math.abs(r13) * s.sz) / 2
	local hz = (math.abs(r31) * s.sx + math.abs(r32) * s.sy + math.abs(r33) * s.sz) / 2
	return s.cx - hx, s.cx + hx, s.cz - hz, s.cz + hz
end

local function stripRect(r: any): (number?, number, number, number)
	local a, b = math.min(r.start, r["end"]), math.max(r.start, r["end"])
	if r.axis == "x" then
		return a, b, r.coord - r.width / 2, r.coord + r.width / 2
	elseif r.axis == "z" then
		return r.coord - r.width / 2, r.coord + r.width / 2, a, b
	end
	return nil, 0, 0, 0
end

export type Extra = {
	expansion: any?,
	colliders: { any }?,
	nutSpots: { any }?,
	trees: { { number } }?, -- route trees: { x, z, reach }
	wires: { { { number } } }?,
	rides: { { { number } } }?,
	clamp: { minX: number, maxX: number, minZ: number, maxZ: number },
	insideWater: (number, number) -> boolean,
}

function WoodsPlan.build(data: any, plans: { any }, heightAt: (number, number) -> number, extra: Extra): World
	local C = WoodsPlan.C
	local w: World = {
		cells = {},
		items = {},
		clamp = extra.clamp,
		heightAt = heightAt,
		insideWater = extra.insideWater,
	}
	local lotType: { [string]: string } = {}
	for _, lot in data.lots do
		lotType[lot.id] = lot.type
	end
	for _, p in plans do
		if p.kind == "road" then
			for _, s in p.parts do
				local x0, x1, z0, z1 = footprint(s)
				insert(w, rect("paving " .. p.id, x0, x1, z0, z1, C.PAVING, false))
			end
		elseif p.kind == "lot" then
			local id = p.attributes.LotId or p.id
			local t = lotType[id] or p.attributes.LotType
			local open = C.OPEN[t] == true
			for _, s in p.parts do
				local flatLawn = open and (s.sy or 0) <= 0.35 and not s.canCollide and C.GRASS[s.material] == true
				if not flatLawn then
					local x0, x1, z0, z1 = footprint(s)
					local tall = s.canCollide and (s.sy or 0) > 4
					if s.role == "Door" or s.role == "Step" then
						insert(w, rect("door " .. id, x0, x1, z0, z1, C.DOOR, false))
					else
						local pave = (s.sy or 0) <= 0.35
						insert(w, rect("lot " .. id, x0, x1, z0, z1, if pave then C.PAVING else C.LOT, tall))
					end
				end
			end
		elseif p.kind == "lamps" or (p.kind == "props" and p.category ~= "tree") then
			for _, s in p.parts do
				local x0, x1, z0, z1 = footprint(s)
				insert(w, rect(p.category .. " " .. p.id, x0, x1, z0, z1, C.GEAR, false))
			end
		end
	end
	-- the lots that are not open ground, whole (a lot's empty corners are still its own)
	for _, lot in data.lots do
		local fp = lot.footprint
		if not C.OPEN[lot.type] and fp and fp.w and fp.d and fp.w > 0 and fp.d > 0 then
			local hw, hd = fp.w / 2, fp.d / 2
			if lot.facing == "+X" or lot.facing == "-X" then
				hw, hd = hd, hw
			elseif lot.facing == nil and type(lot.yaw) == "number" and math.abs(math.sin(lot.yaw)) > 0.01 then
				local h = math.sqrt(fp.w * fp.w + fp.d * fp.d) / 2
				hw, hd = h, h
			end
			insert(w, rect("lot " .. lot.id, lot.x - hw, lot.x + hw, lot.z - hd, lot.z + hd, C.LOT, false))
		end
	end
	local ex = extra.expansion
	if ex then
		for _, r in ex.strips or {} do
			local x0, x1, z0, z1 = stripRect(r)
			if x0 then
				insert(w, rect("street " .. r.id, x0, x1, z0, z1, C.PAVING, false))
			end
		end
		for _, p in ex.pads or {} do
			insert(w, rect("pad " .. p.id, p.rect.x0, p.rect.x1, p.rect.z0, p.rect.z1, C.PAVING, false))
		end
		for _, p in ex.paths or {} do
			for k = 1, #p.points - 1 do
				local a, b = p.points[k], p.points[k + 1]
				insert(w, seg("path " .. p.id, a[1], a[2], b[1], b[2], p.width / 2, C.PAVING, false))
			end
		end
		for _, v in ex.venues or {} do
			local poly = v.sitePoly or v.footPoly
			if poly and #poly >= 3 then
				local x0, x1, z0, z1 = math.huge, -math.huge, math.huge, -math.huge
				for _, q in poly do
					x0, x1 = math.min(x0, q[1]), math.max(x1, q[1])
					z0, z1 = math.min(z0, q[2]), math.max(z1, q[2])
				end
				insert(w, rect("venue " .. v.id, x0, x1, z0, z1, C.BOX, true))
			end
		end
		for _, z in ex.zones or {} do
			if z.rect then
				insert(w, rect("zone " .. z.id, z.rect.x0, z.rect.x1, z.rect.z0, z.rect.z1, C.ZONE, false))
			end
		end
	end
	local colliders: { any } = extra.colliders or {}
	for _, b in colliders do
		insert(w, rect("box " .. b.id, b.cx - b.hw, b.cx + b.hw, b.cz - b.hd, b.cz + b.hd, C.BOX, true))
	end
	local wires: { { { number } } } = extra.wires or {}
	for _, line in wires do
		for k = 1, #line - 1 do
			local a, b = line[k], line[k + 1]
			insert(w, seg("wire", a[1], a[2], b[1], b[2], 0, C.WIRE, true))
		end
	end
	local rides: { { { number } } } = extra.rides or {}
	for _, line in rides do
		for k = 1, #line - 1 do
			local a, b = line[k], line[k + 1]
			insert(w, seg("ride cable", a[1], a[2], b[1], b[2], 6, C.WIRE, true))
		end
	end
	local spots: { any } = extra.nutSpots or {}
	for _, s in spots do
		insert(w, disc("nut spot " .. s.id, s.x, s.z, 0, C.NUT, false))
	end
	local trees: { { number } } = extra.trees or {}
	for _, t in trees do
		local it = disc("route tree", t[1], t[2], 0, C.TREE_MIN, false)
		it.tree = true
		it.r = 0
		it.pad = t[3] -- (its reach: TREE_SHARE rule below)
		insert(w, it)
	end
	return w
end

-- why a tree of crown reach `crown` may not stand at (x, z); nil: it may
function WoodsPlan.check(w: World, x: number, z: number, crown: number, others: { { number } }?): string?
	local C = WoodsPlan.C
	local cl = w.clamp
	if x < cl.minX + C.EDGE or x > cl.maxX - C.EDGE or z < cl.minZ + C.EDGE or z > cl.maxZ - C.EDGE then
		return "outside the world"
	end
	if z >= C.BEACH_Z then
		return "the beach"
	end
	for _, o in { { 0, 0 }, { C.RIVER, 0 }, { -C.RIVER, 0 }, { 0, C.RIVER }, { 0, -C.RIVER } } do
		if w.insideWater(x + o[1], z + o[2]) then
			return "the river"
		end
	end
	local h = w.heightAt
	local gx = math.abs(h(x + 4, z) - h(x - 4, z)) / 8
	local gz = math.abs(h(x, z + 4) - h(x, z - 4)) / 8
	if gx > C.SLOPE or gz > C.SLOPE then
		return "too steep"
	end
	local c = C.CELL
	local list = w.cells[key(math.floor(x / c), math.floor(z / c))]
	if list then
		for _, it in list do
			if it.tree then
				local need = math.max(C.TREE_MIN, C.TREE_SHARE * (it.pad + crown))
				local dx, dz = it.ax - x, it.az - z
				if dx * dx + dz * dz < need * need then
					return it.what
				end
			else
				local need = it.pad
				if it.crown then
					need = math.max(need, C.CROWN_OVER * crown)
				end
				if dist(it, x, z) < need then
					return it.what
				end
			end
		end
	end
	local near: { { number } } = others or {}
	for _, o in near do
		local need = math.max(C.WOODS_MIN, C.WOODS_SHARE * (o[3] + crown))
		local dx, dz = o[1] - x, o[2] - z
		if dx * dx + dz * dz < need * need then
			return "another woods tree"
		end
	end
	return nil
end

return WoodsPlan
