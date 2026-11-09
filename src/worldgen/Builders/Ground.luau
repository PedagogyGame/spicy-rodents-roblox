--!strict
-- ServerScriptService.Server.WorldGen.Builders.Ground
-- Ground plates (lawns, plazas, courts, pools, the Quay) that sit on the terrain instead of floating
-- over it (review 2026-11-09): a flat plate only where the terrain under it is level; elsewhere a
-- grass plate is left to the (grass) terrain, water lies at the lowest ground of its footprint, and
-- hard surfaces (courts, fields, intersections) are draped over the terrain in tilted tiles. Plates
-- that overlap are stacked by kind (district < grass < pads < plazas < paths) so no two top faces
-- coincide (no z-fighting).
-- The Bellwether Quay (worldgen_districts_art §3): the cobbled district ground is split along the river
-- banks (riverCenter(z) +- halfWidth, so it never covers the water), the river channel gets stone
-- embankment walls with a light coping, and the stone bridge is a real five-arch bridge (§3.3: arches
-- at x 802..898 u, inner radius 9.6 u springing at 3.5 u, cutwater piers, the deck at 15.8 u over x
-- 790..910 u with ramps from 744 and to 956 u, and the two tower bases the bridge towers stand on).
-- Interface: plan(ctx) for every plate lot (Plan dispatches by category). Pure.

local Import = require("../Import")
local Palette = require("../Palette")
local Spec = require("../Spec")
local Height = Import.shared("World/Height") :: typeof(require("../../shared/World/Height"))

local Ground = {}

local THIN = 0.2
local LEVEL_TOLERANCE = 0.6 -- studs of terrain relief under a plate that still counts as level
local TILE = 24 -- studs: drape tile size

-- Stacking above the seat by kind (studs added to the top face).
local LAYER: { [string]: number } = {
	district_ground = 0,
	lawn = 0.04,
	park = 0.04,
	cemetery = 0.04,
	estate_parcel = 0.04,
	garden = 0.06,
	community_garden = 0.06,
	sports_field = 0.06,
	playground = 0.06,
	tennis_court = 0.06,
	parking = 0.06,
	ambulance_bay = 0.08,
	intersection = 0.08,
	plaza = 0.08,
	path = 0.12,
}
local WATER = { river = true, stream = true, pond = true, estate_pool = true, backyard_pool = true }

local STONE_LIGHT = Palette.hex("#d1c7ae")
local STONE_DARK = Palette.hex("#777b70")
local STONE_MID = Palette.hex("#a39b88")

type Ctx = Spec.LotCtx

-- World-axis extents of the lot footprint (studs).
local function extents(ctx: Ctx): (number, number, number, number)
	local fp = ctx.lot.footprint
	local w = if fp then math.max(fp.w, 0.05) else 2
	local d = if fp then math.max(fp.d, 0.05) else 2
	return ctx.lot.x - w / 2, ctx.lot.x + w / 2, ctx.lot.z - d / 2, ctx.lot.z + d / 2
end

local function relief(x0: number, x1: number, z0: number, z1: number): (number, number)
	local lo, hi = math.huge, -math.huge
	local n = math.clamp(math.ceil(math.max(x1 - x0, z1 - z0) / 12), 2, 24)
	for i = 0, n do
		for j = 0, n do
			local h = Height.at(x0 + (x1 - x0) * i / n, z0 + (z1 - z0) * j / n)
			lo, hi = math.min(lo, h), math.max(hi, h)
		end
	end
	return lo, hi
end

local function world(
	ctx: Ctx,
	name: string,
	x: number,
	y: number,
	z: number,
	sx: number,
	sy: number,
	sz: number,
	o: Spec.Opts?
): Spec.PartSpec
	local opts: Spec.Opts = o or {}
	return ctx.list:world({
		name = name,
		cx = x,
		cy = y,
		cz = z,
		yaw = opts.yaw or 0,
		pitch = opts.pitch or 0,
		roll = opts.roll,
		sx = math.max(sx, 0.05),
		sy = math.max(sy, 0.05),
		sz = math.max(sz, 0.05),
		color = opts.color or { 200, 200, 200 },
		material = opts.material or "SmoothPlastic",
		canCollide = if opts.canCollide == nil then false else opts.canCollide,
		transparency = opts.transparency or 0,
		shape = opts.shape,
		castShadow = opts.castShadow,
		role = opts.role or "Body",
		canQuery = opts.canQuery,
		attrs = opts.attrs or (if opts.role == "Wall" then { Embedded = true } else nil),
	})
end

-- An invisible placeholder (keeps the lot's Model and PrimaryPart; nothing to see or hit).
local function hidden(ctx: Ctx, why: string)
	local x0, x1, z0, z1 = extents(ctx)
	world(ctx, "Greybox", (x0 + x1) / 2, ctx.seat + THIN / 2, (z0 + z1) / 2, x1 - x0, THIN, z1 - z0, {
		transparency = 1,
		canQuery = false,
		castShadow = false,
	})
	ctx.attributes.GroundStyle = why
end

-- Terrain-following tiles (tilted to the local slope, 1 stud thick so their edges overlap).
local function drape(ctx: Ctx, color: { number }, material: string, lift: number)
	local x0, x1, z0, z1 = extents(ctx)
	local nx = math.max(1, math.ceil((x1 - x0) / TILE))
	local nz = math.max(1, math.ceil((z1 - z0) / TILE))
	local dx, dz = (x1 - x0) / nx, (z1 - z0) / nz
	local thick = 1
	for i = 0, nx - 1 do
		for j = 0, nz - 1 do
			local ax, bx = x0 + i * dx, x0 + (i + 1) * dx
			local az, bz = z0 + j * dz, z0 + (j + 1) * dz
			local h00, h10 = Height.at(ax, az), Height.at(bx, az)
			local h01, h11 = Height.at(ax, bz), Height.at(bx, bz)
			local hc = (h00 + h10 + h01 + h11) / 4
			local gx = ((h10 + h11) - (h00 + h01)) / 2 / dx
			local gz = ((h01 + h11) - (h00 + h10)) / 2 / dz
			local L = math.sqrt(gx * gx + 1 + gz * gz)
			local roll = math.asin(math.clamp(gx / L, -1, 1))
			local pitch = math.asin(math.clamp(-gz / (L * math.cos(roll)), -1, 1))
			world(
				ctx,
				if i == 0 and j == 0 then "Greybox" else `Tile_{i}_{j}`,
				(ax + bx) / 2,
				hc + lift - thick / 2,
				(az + bz) / 2,
				dx * math.sqrt(1 + gx * gx) + 0.4,
				thick,
				dz * math.sqrt(1 + gz * gz) + 0.4,
				{ color = color, material = material, pitch = pitch, roll = roll, castShadow = false, attrs = { Embedded = true } }
			)
		end
	end
	ctx.attributes.GroundStyle = "draped"
end

local function flat(ctx: Ctx, y: number, color: { number }, material: string, transparency: number)
	local x0, x1, z0, z1 = extents(ctx)
	world(ctx, "Greybox", (x0 + x1) / 2, y - THIN / 2, (z0 + z1) / 2, x1 - x0, THIN, z1 - z0, {
		color = color,
		material = material,
		transparency = transparency,
		castShadow = false,
	})
end

-- ---------------------------------------------------------------------------------------- the Quay
local R = Height.RIVER
local SPU = Spec.SPU
local BANK_Y = R.bankY * SPU
local BED_Y = R.bedY * SPU
local HALF = R.halfWidth * SPU
local STRIP = 37.5 -- studs along z

local function centre(z: number): number
	return Height.riverCenterU(z / SPU) * SPU
end

-- The cobbled district ground in strips on both banks, stopping at the embankment coping.
function Ground.district(ctx: Ctx)
	local x0, x1, z0, z1 = extents(ctx)
	local plateau = 735 * SPU -- terrainHeight is flat bank level east of x 735 u (smoothstep 687..735)
	local color, material = Palette.plate("district_ground", nil)
	local n = math.ceil((z1 - z0) / STRIP)
	local dz = (z1 - z0) / n
	local first = true
	for k = 0, n - 1 do
		local a, b = z0 + k * dz, z0 + (k + 1) * dz
		-- the bank line moves with the meander: take the narrowest land edge over the strip
		local cmin, cmax = math.huge, -math.huge
		for s = 0, 4 do
			local c = centre(a + (b - a) * s / 4)
			cmin, cmax = math.min(cmin, c), math.max(cmax, c)
		end
		local west0, west1 = math.max(x0, plateau), cmin - HALF + 0.5
		local east0, east1 = cmax + HALF - 0.5, x1
		for side, span in { { west0, west1 }, { east0, east1 } } do
			if span[2] - span[1] > 1 then
				world(
					ctx,
					if first then "Greybox" else `Bank{side}_{k}`,
					(span[1] + span[2]) / 2,
					BANK_Y + 0.1 - THIN / 2, -- top 0.1 over the bank: under the asphalt approach (+0.14)
					(a + b) / 2,
					span[2] - span[1],
					THIN,
					b - a + 0.02,
					{ color = color, material = material, castShadow = false }
				)
				first = false
			end
		end
	end
	ctx.attributes.GroundStyle = "banks"
end

-- The river: the water itself is terrain water (WorldTerrain); the lot draws the embankment walls
-- (stone, bed to bank) and their light coping along both banks, following the meander.
function Ground.river(ctx: Ctx)
	local _, _, z0, z1 = extents(ctx)
	world(ctx, "Greybox", ctx.lot.x, BED_Y + THIN / 2, ctx.lot.z, 2, THIN, 2, {
		transparency = 1,
		canQuery = false,
		castShadow = false,
	})
	local n = math.ceil((z1 - z0) / STRIP)
	local dz = (z1 - z0) / n
	for k = 0, n - 1 do
		local a, b = z0 + k * dz, z0 + (k + 1) * dz
		local ca, cb = centre(a), centre(b)
		local len = math.sqrt((b - a) ^ 2 + (cb - ca) ^ 2) + 0.6
		local yaw = math.atan2(-(cb - ca), -(b - a)) -- LookVector along the bank line
		for _, side in { -1, 1 } do
			-- the wall's water face 3.5 st inside the bank line covers the 4-stud terrain voxel cliff
			local wallC = (ca + cb) / 2 + side * (HALF - 1.25)
			local h = BANK_Y - 0.1 - (BED_Y - 1) -- just under the coping and the dock decks
			world(ctx, `Wall{if side < 0 then "W" else "E"}_{k}`, wallC, (BED_Y - 1) + h / 2, (a + b) / 2, 4.5, h, len, {
				yaw = yaw,
				color = STONE_DARK,
				material = "Cobblestone",
				canCollide = true,
				role = "Wall",
			})
			world(
				ctx,
				`Coping{if side < 0 then "W" else "E"}_{k}`,
				(ca + cb) / 2 + side * (HALF - 1.6),
				BANK_Y + 0.3,
				(a + b) / 2,
				5.4,
				0.6,
				len,
				{
					yaw = yaw,
					color = STONE_LIGHT,
					material = "Limestone",
					canCollide = true,
					role = "Wall",
				}
			)
		end
	end
	ctx.attributes.GroundStyle = "river"
end

-- The five-arch stone bridge (makeRiverBridge 13754, bridgeArch 13657), in world studs.
function Ground.bridge(ctx: Ctx)
	local deck = R.deckY * SPU -- 39.5
	local zc = R.bridgeZ * SPU
	local halfD = 15.7 / 2 * SPU -- body depth 15.7 u
	local x0, x1 = R.bridgeStart * SPU, R.bridgeEnd * SPU
	local r0 = 9.6 * SPU -- arch inner radius
	local ring = 4 -- voussoir depth (studs): the crown's extrados meets the deck slab
	local spring = 3.5 * SPU
	local slabBottom = spring + r0 + ring -- 36.75
	local bed = BED_Y - 1
	-- deck slab (the road strip rd_033 lies on it)
	world(ctx, "Greybox", (x0 + x1) / 2, (slabBottom + deck) / 2, zc, x1 - x0 + 8, deck - slabBottom, 2 * halfD, {
		color = STONE_LIGHT,
		material = "Limestone",
		canCollide = true,
		role = "Floor",
	})
	-- string course under the parapets
	for _, s in { -1, 1 } do
		world(ctx, `Course{if s < 0 then "S" else "N"}`, (x0 + x1) / 2, slabBottom + 0.4, zc + s * (halfD + 0.3), x1 - x0 + 8, 0.9, 0.7, {
			color = STONE_MID,
			material = "Limestone",
			role = "Trim",
			castShadow = false,
		})
	end
	-- piers (bed to the deck slab), at x 790..910 u every 24 u; the 2nd and 5th carry the towers
	local piers = {}
	for i = 0, 5 do
		table.insert(piers, (790 + 24 * i) * SPU)
	end
	local span = 24 * SPU
	local pierW = span - 2 * r0
	for i, px in piers do
		world(ctx, `Pier{i}`, px, (bed + slabBottom) / 2, zc, pierW, slabBottom - bed, 2 * halfD, {
			color = STONE_MID,
			material = "Limestone",
			canCollide = true,
			role = "Wall",
		})
		-- cutwaters: diamond noses up- and downstream to just above the water
		local top = R.waterY * SPU + 5
		for _, s in { -1, 1 } do
			local w = pierW / math.sqrt(2)
			world(ctx, `Cutwater{i}{if s < 0 then "S" else "N"}`, px, (bed + top) / 2, zc + s * halfD, w, top - bed, w, {
				yaw = math.pi / 4,
				color = STONE_DARK,
				material = "Limestone",
				canCollide = true,
				role = "Wall",
			})
		end
		if i == 2 or i == 5 then
			-- tower base: the bridge towers' piers (z +-10.7 u, 7.2 u deep) stand on these
			for _, s in { -1, 1 } do
				local inner, outer = halfD, (10.7 + 3.6) * SPU + 1.5
				world(ctx, `TowerBase{i}{if s < 0 then "S" else "N"}`, px, (bed + deck) / 2, zc + s * (inner + outer) / 2, 8 * SPU + 2, deck - bed, outer - inner, {
					color = STONE_MID,
					material = "Limestone",
					canCollide = true,
					role = "Wall",
				})
			end
		end
	end
	-- arches: voussoir rings (every third block dark, §3.3) and the spandrel fill up to the deck slab
	local function extrados(u: number): number
		return spring + math.sqrt(math.max((r0 + ring) ^ 2 - u * u, 0))
	end
	local N = 11
	for a = 1, 5 do
		local ax = (802 + 24 * (a - 1)) * SPU
		for k = 0, N - 1 do
			local th = math.pi * (k + 0.5) / N -- 0 at the east springing, pi at the west
			local rm = r0 + ring / 2
			local len = 2 * (r0 + ring) * math.sin(math.pi / N / 2) + 0.3
			world(ctx, `Arch{a}_{k}`, ax + rm * math.cos(th), spring + rm * math.sin(th), zc, len, ring, 2 * halfD + 0.4, {
				roll = th - math.pi / 2,
				color = if k % 3 == 0 then STONE_DARK else STONE_LIGHT,
				material = "Limestone",
				canCollide = true,
				role = "Wall",
			})
		end
		-- spandrels: slices whose bottoms stay above the opening and below the ring's back
		local outer = r0
		local slices: { { number } } = {}
		while outer > 0.5 do
			local y = extrados(outer)
			local s = y - spring
			local inner = if s >= r0 then 0 else math.sqrt(math.max(r0 * r0 - s * s, 0))
			table.insert(slices, { inner, outer, y })
			outer = inner
		end
		for k, sl in slices do
			local inner, out, y = sl[1], sl[2], sl[3]
			if inner <= 0 then
				world(ctx, `Spandrel{a}_{k}`, ax, (y + slabBottom) / 2, zc, 2 * out + 0.2, slabBottom - y + 0.1, 2 * halfD, {
					color = STONE_LIGHT,
					material = "Limestone",
					canCollide = true,
					role = "Wall",
				})
			else
				for _, s in { -1, 1 } do
					world(ctx, `Spandrel{a}_{k}{if s < 0 then "W" else "E"}`, ax + s * (inner + out) / 2, (y + slabBottom) / 2, zc, out - inner + 0.2, slabBottom - y + 0.1, 2 * halfD, {
						color = STONE_LIGHT,
						material = "Limestone",
						canCollide = true,
						role = "Wall",
					})
				end
			end
		end
	end
	-- approach ramps (744..790 u and 910..956 u): solid stone wedges from the bank to the deck
	local rampLen = (R.bridgeStart - R.rampStart) * SPU
	for _, s in { -1, 1 } do
		local mid = if s < 0 then (R.rampStart * SPU + x0) / 2 else (x1 + R.rampEnd * SPU) / 2
		-- 0.3 st narrower than the piers each side: no coplanar side faces (they z-fight in Roblox)
		world(ctx, `Ramp{if s < 0 then "W" else "E"}`, mid, (BANK_Y - 0.1 + deck) / 2, zc, 2 * halfD - 0.6, deck - (BANK_Y - 0.1), rampLen, {
			yaw = if s < 0 then math.pi / 2 else -math.pi / 2,
			shape = "Wedge",
			color = STONE_MID,
			material = "Limestone",
			canCollide = true,
			role = "Wall",
		})
	end
	ctx.attributes.GroundStyle = "bridge"
	ctx.attributes.DeckY = deck
end

-- --------------------------------------------------------------------------------------- dispatch
function Ground.plan(ctx: Ctx)
	local t = ctx.lot.type
	if t == "river" then
		return Ground.river(ctx)
	elseif t == "bridge" then
		return Ground.bridge(ctx)
	elseif t == "district_ground" and Height.inRiverDistrictU(ctx.lot.x / SPU, ctx.lot.z / SPU) then
		return Ground.district(ctx)
	end
	local color, material, transparency = Palette.plate(t, (ctx.lot :: any).style)
	local x0, x1, z0, z1 = extents(ctx)
	local lo, hi = relief(x0, x1, z0, z1)
	local layer = LAYER[t] or 0.04
	if WATER[t] then
		-- water lies level at the lowest ground of its footprint (it never floats over a slope)
		flat(ctx, lo + 0.22, color, material, transparency)
		ctx.attributes.GroundStyle = "water"
	elseif hi - lo <= LEVEL_TOLERANCE then
		flat(ctx, ctx.seat + THIN + layer, color, material, transparency)
		ctx.attributes.GroundStyle = "flat"
	elseif material == "Grass" then
		-- a grass plate on a slope adds nothing over the grass terrain and would float in places
		hidden(ctx, "terrain")
	else
		drape(ctx, color, material, 0.15 + layer)
	end
end

return Ground
