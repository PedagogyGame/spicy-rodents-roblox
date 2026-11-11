--!strict
-- ServerScriptService.Server.WorldGen.Plan
-- Lots and roads to a deterministic, pure-data BuildPlan (spike S6 greybox; W1 #7 builder families).
-- The same plan is built in Lune (tools/bake) and in the engine (tests/engine/WorldBuild); BakeParity
-- hashes it. Each lot's lot type names a builder family (Builders/Building, House, Hospital,
-- PoliceStation, Sign; structures, slabs, plates, props and markers stay single greybox blocks).
-- Interface (BUILD_PLAN §1.4): plan(lot, lotType, ctx) -> BuildPlan; road(road) -> BuildPlan;
--   containment(lots) -> { [childId]: parentId }; seat(lot) -> studs; lotFrame(lot) -> frame, W, D
-- Units: studs in and out (generated/ is already in studs). Facing: a cardinal `facing` or `yaw`
-- (HTML radians) becomes the model's LookVector through Units' single +pi (D21). The footprint is
-- a world-axis box [worldgen_core §1 "already rotated into world axes"], so non-cardinal yaws keep
-- the box axis-aligned and record the exact yaw as an attribute.
-- Pure: no Instances, no state, no side effects on require.

local BridgeTower = require("./Builders/BridgeTower")
local Building = require("./Builders/Building")
local Geometry = require("./Geometry")
local Ground = require("./Builders/Ground")
local Hospital = require("./Builders/Hospital")
local House = require("./Builders/House")
local Import = require("./Import")
local Kits = require("./Kits")
local Palette = require("./Palette")
local PoliceStation = require("./Builders/PoliceStation")
local Sign = require("./Builders/Sign")
local Props = require("./Builders/Props")
local Treehouse = require("./Builders/Treehouse")
local Spec = require("./Spec")
local Height = Import.shared("World/Height") :: typeof(require("../shared/World/Height"))
local RoadSurface = Import.shared("World/RoadSurface") :: typeof(require("../shared/World/RoadSurface"))
local Buildings = Import.generated("Buildings") :: { [string]: any }
local Interiors = Import.generated("Interiors") :: { [string]: any }

local Plan = {}

local SPU = Kits.STUDS_PER_UNIT
local HALF_PI = math.pi / 2
local PLATE_THICKNESS = 0.2
local CONTAIN_TOLERANCE = 0.5 -- studs: a child may poke this far out of its parent's footprint
local ROAD_THICKNESS = RoadSurface.THICKNESS

export type PartSpec = Spec.PartSpec
export type ExtraSpec = Spec.ExtraSpec
export type BuildPlan = Spec.BuildPlan

export type Lot = {
	id: string,
	district: string,
	type: string,
	x: number,
	z: number,
	facing: string?,
	yaw: number?,
	footprint: { w: number, d: number }?,
	hasInterior: boolean?,
	seat: string?,
	params: { [string]: any }?,
	home: { [string]: any }?,
}

export type Road = {
	id: string,
	kind: string,
	axis: string,
	coord: number?,
	start: any,
	["end"]: any,
	width: number,
	registered: boolean?,
}

export type Ctx = { parentId: string? }

local CARDINAL: { [string]: number } = { ["+Z"] = 0, ["-Z"] = math.pi, ["+X"] = HALF_PI, ["-X"] = -HALF_PI }

-- HTML yaw of the lot's front, and whether it was given at all.
local function htmlYaw(lot: Lot): (number, boolean)
	if lot.facing and CARDINAL[lot.facing] ~= nil then
		return CARDINAL[lot.facing], true
	end
	if lot.yaw then
		return lot.yaw, true
	end
	return 0, false
end

-- Snap to a quarter turn: q in {0,1,2,3}. Returns the quarter index.
local function quarter(yaw: number): number
	local q = math.floor(yaw / HALF_PI + 0.5) % 4
	return q
end

function Plan.footprint(lot: Lot): (number, number)
	local fp = lot.footprint
	if fp then
		return math.max(fp.w, 0.05), math.max(fp.d, 0.05)
	end
	return 2, 2
end

-- World AABB of a lot footprint: minX, maxX, minZ, maxZ (studs).
function Plan.bounds(lot: Lot): (number, number, number, number)
	local w, d = Plan.footprint(lot)
	return lot.x - w / 2, lot.x + w / 2, lot.z - d / 2, lot.z + d / 2
end

-- Children: a solid lot whose footprint lies inside a larger *building* footprint (mall shops in the
-- galleria, hospital rooms in the hospital). W1 data declares parents explicitly (invariant 1);
-- until then the bake derives them so the greybox has no solid overlap.
function Plan.containment(lots: { Lot }): { [string]: string }
	local out: { [string]: string } = {}
	for _, a in lots do
		local ka = Kits.get(a.type)
		if Kits.isSolid(ka.category) then
			local ax0, ax1, az0, az1 = Plan.bounds(a)
			local best: Lot? = nil
			local bestArea = math.huge
			for _, b in lots do
				if b ~= a and Kits.get(b.type).category == "building" then
					local bx0, bx1, bz0, bz1 = Plan.bounds(b)
					local area = (bx1 - bx0) * (bz1 - bz0)
					local inside = ax0 >= bx0 - CONTAIN_TOLERANCE
						and ax1 <= bx1 + CONTAIN_TOLERANCE
						and az0 >= bz0 - CONTAIN_TOLERANCE
						and az1 <= bz1 + CONTAIN_TOLERANCE
					if inside and area > (ax1 - ax0) * (az1 - az0) and area < bestArea then
						best, bestArea = b, area
					end
				end
			end
			if best then
				out[a.id] = best.id
			end
		end
	end
	return out
end

-- Seat height in studs: `seat = "absolute:<y>"` (HTML units, harvested v5.4 bases) or World/Height.
function Plan.seat(lot: Lot): number
	local abs = lot.seat and string.match(lot.seat, "^absolute:(%-?[%d%.]+)$")
	if abs then
		return (tonumber(abs) :: number) * SPU
	end
	return Height.at(lot.x, lot.z)
end

local BUILDING_BY_LOT: { [string]: any } = {}
for _, b in Buildings do
	BUILDING_BY_LOT[b.lot] = b
end

local FAMILIES: { [string]: (ctx: Spec.LotCtx) -> () } = {
	Building = Building.plan,
	House = House.plan,
	Hospital = Hospital.plan,
	PoliceStation = PoliceStation.plan,
	Sign = Sign.plan,
	BridgeTower = BridgeTower.plan,
	Treehouse = Treehouse.plan,
}

-- The S6 single block (structures, slabs, plates, props, markers and interior children).
local function blockPart(
	lot: Lot,
	kit: Kits.Kit,
	seat: number,
	q: number,
	sx: number,
	sz: number,
	isChild: boolean
): PartSpec
	local solid = Kits.isSolid(kit.category) and not isChild
	local transparency = if isChild then 0.7 elseif kit.category == "marker" then 1 else 0
	local h = kit.heightU * SPU
	local cy, sy
	if kit.category == "plate" then
		sy = PLATE_THICKNESS
		cy = seat + PLATE_THICKNESS / 2
	elseif kit.category == "slab" then
		sy = math.min(0.75 * SPU, math.max(h, 0.4))
		cy = seat + h - sy / 2
	else
		sy = math.max(h, 0.4)
		cy = seat + sy / 2
	end
	local color, material = kit.color, kit.material
	local shape: string? = nil
	if kit.category == "plate" then
		local pt
		color, material, pt = Palette.plate(lot.type, (lot :: any).style)
		transparency = math.max(transparency, pt)
	elseif kit.category ~= "marker" and not isChild then
		local look = Palette.forLot(lot, kit)
		color = look.wall
		material = if kit.category == "slab" then "WoodPlanks" else "SmoothPlastic"
		if lot.type == "tree" then
			-- every tree lot (the six Quay willows) stands on a harvested trunk route: RouteProps draws
			-- the whole tree (bark and crown) there, so the lot itself is only an invisible marker
			-- (review 2026-11-09: the trunkless 45-stud balls)
			transparency = 1
			local r = math.min(sx, sz, math.max(sy, 2))
			sx, sz, sy = r, r, r
			cy = seat + r / 2
		elseif lot.type == "shrub_cluster" then
			-- crowns as a leafy ball
			color, material, shape = Palette.LEAVES[(#lot.id % #Palette.LEAVES) + 1], "LeafyGrass", "Ball"
			local r = math.min(sx, sz, math.max(sy, 2))
			sx, sz = r, r
			sy = r
			cy = seat + r / 2
		elseif lot.type == "fence_run" then
			material = "WoodPlanks"
		end
	elseif isChild then
		color = Palette.forLot(lot, kit).wall
	end
	if lot.type == "dock" and Height.insideRiverWater(lot.x, lot.z) then
		-- Quay docks: the deck top at bank level over the water (v5.4 quayDock: deck top y 8 u)
		cy = Height.RIVER.bankY * SPU - sy / 2
	end
	return {
		name = "Greybox",
		cx = lot.x,
		cy = cy,
		cz = lot.z,
		yaw = q * HALF_PI + math.pi, -- Units.robloxYaw on the snapped front
		pitch = 0,
		sx = sx,
		sy = sy,
		sz = sz,
		color = color,
		material = material,
		canCollide = solid,
		transparency = transparency,
		canQuery = if transparency >= 1 then false else nil,
		shape = shape,
		role = "Body",
	}
end

function Plan.plan(lot: Lot, lotType: string, ctx: Ctx): BuildPlan
	local kit = Kits.get(lotType)
	local w, d = Plan.footprint(lot)
	local yawH, given = htmlYaw(lot)
	local q = quarter(yawH)
	-- local size: X across the front, Z front-to-back; odd quarter turns swap the world extents
	local sx, sz = w, d
	if q % 2 == 1 then
		sx, sz = d, w
	end
	local seat = Plan.seat(lot)
	local isChild = ctx.parentId ~= nil
	local category: string = if isChild then "interior" else kit.category
	local solid = Kits.isSolid(kit.category) and not isChild
	local attributes: { [string]: string | number | boolean } = {
		LotId = lot.id,
		LotType = lotType,
		District = lot.district,
		Category = category,
		Solid = solid,
		SeatY = seat,
		FacingYaw = yawH,
		FacingGiven = given,
		LevelOfDetail = kit.lod,
		Builder = if isChild then "Block" else kit.builder,
	}
	if ctx.parentId then
		attributes.ParentLot = ctx.parentId
	end
	if not Kits.known(lotType) then
		attributes.UnknownType = true
	end
	local list = Spec.list()
	local family = if isChild then nil else FAMILIES[kit.builder]
	if not isChild and kit.category == "plate" then
		family = Ground.plan -- terrain-aware plates, the Quay banks, river and bridge
	end
	if family then
		local frame = Geometry.frame(lot.x, seat, lot.z, q * HALF_PI + math.pi)
		local home = lot.home
		local lctx: Spec.LotCtx = {
			lot = lot,
			kit = kit,
			frame = frame,
			W = sx,
			D = sz,
			seat = seat,
			params = lot.params or {},
			list = list,
			building = BUILDING_BY_LOT[lot.id],
			interior = home and home.interior and Interiors[home.interior],
			attributes = attributes,
			palette = Palette.forLot(lot, kit),
		}
		if (kit.builder == "Hospital" or kit.builder == "PoliceStation") and not lctx.building then
			Building.plan(lctx)
		else
			family(lctx)
		end
	else
		local body = list:world(blockPart(lot, kit, seat, q, sx, sz, isChild))
		if not isChild then
			Props.dress(lot, kit, body, list, seat)
		end
	end
	if not isChild and (kit.category == "building" or kit.category == "structure") then
		Plan.foundation(lot, kit, seat, list)
	end
	return {
		kind = "lot",
		id = lot.id,
		category = category,
		lod = kit.lod,
		streaming = kit.streaming,
		attributes = attributes,
		parts = list.parts,
		extras = list.extras,
	}
end

-- A stone foundation under buildings and structures on a slope (review 2026-11-09: nothing floats):
-- from the lowest terrain under the footprint up to the seat. It is solid (owner 2026-11-10: "make sure
-- squirrel cannot run through houses"): on the downhill side the foundation stands taller than a body,
-- and without collision an animal walked in under the house through it. Lots on harvested absolute seats in the air
-- (bridge towers) and the treehouse are skipped.
local FOUNDATION = { 150, 144, 132 }
function Plan.foundation(lot: Lot, kit: Kits.Kit, seat: number, list: Spec.PartList)
	if kit.builder == "Treehouse" or kit.builder == "BridgeTower" then
		return
	end
	local x0, x1, z0, z1 = Plan.bounds(lot)
	local lo = math.huge
	for i = 0, 8 do
		for j = 0, 8 do
			lo = math.min(lo, Height.at(x0 + (x1 - x0) * i / 8, z0 + (z1 - z0) * j / 8))
		end
	end
	if seat - lo > 0.25 and seat - lo < 30 then
		local bottom = lo - 0.6
		list:world({
			name = "Foundation",
			cx = (x0 + x1) / 2,
			cy = (bottom + seat - 0.02) / 2,
			cz = (z0 + z1) / 2,
			yaw = 0,
			pitch = 0,
			sx = x1 - x0 + 0.3,
			sy = seat - 0.02 - bottom,
			sz = z1 - z0 + 0.3,
			color = FOUNDATION,
			material = "Concrete",
			canCollide = true,
			transparency = 0,
			castShadow = false,
			role = "Trim",
			attrs = { Embedded = true },
		})
	end
end

-- World-axis box of a plan's first part (yaws are quarter turns for lots): x0, x1, z0, z1.
function Plan.worldBox(spec: PartSpec): (number, number, number, number)
	local q = math.floor(spec.yaw / HALF_PI + 0.5) % 2
	local wx, wz = spec.sx, spec.sz
	if q == 1 then
		wx, wz = spec.sz, spec.sx
	end
	return spec.cx - wx / 2, spec.cx + wx / 2, spec.cz - wz / 2, spec.cz + wz / 2
end

-- Slabs (canopies, porte-cocheres, docks) abut a building wall in v5.4; their inferred footprints
-- poke into it. Trim each slab back to the wall along the axis of least penetration and record
-- `AttachedTo`, so the greybox has no solid overlap and the canopy still meets the facade.
function Plan.attachSlabs(plans: { BuildPlan })
	for _, slab in plans do
		if
			slab.kind == "lot"
			and slab.attributes.Solid
			and Kits.get(slab.attributes.LotType :: string).category == "slab"
		then
			local s = slab.parts[1]
			for _, b in plans do
				if b ~= slab and b.kind == "lot" and b.category == "building" then
					local ax0, ax1, az0, az1 = Plan.worldBox(s)
					local bx0, bx1, bz0, bz1 = Plan.worldBox(b.parts[1])
					local ox = math.min(ax1, bx1) - math.max(ax0, bx0)
					local oz = math.min(az1, bz1) - math.max(az0, bz0)
					if ox > 0 and oz > 0 then
						local q = math.floor(s.yaw / HALF_PI + 0.5) % 2
						if oz <= ox then
							local nz0, nz1 = az0, az1
							if s.cz < (bz0 + bz1) / 2 then
								nz1 = bz0
							else
								nz0 = bz1
							end
							s.cz = (nz0 + nz1) / 2
							if q == 1 then
								s.sx = nz1 - nz0
							else
								s.sz = nz1 - nz0
							end
						else
							local nx0, nx1 = ax0, ax1
							if s.cx < (bx0 + bx1) / 2 then
								nx1 = bx0
							else
								nx0 = bx1
							end
							s.cx = (nx0 + nx1) / 2
							if q == 1 then
								s.sz = nx1 - nx0
							else
								s.sx = nx1 - nx0
							end
						end
						slab.attributes.AttachedTo = b.id
					end
				end
			end
		end
	end
end

-- A road is a chain of flat parts following the terrain (v5.4 draws 104 terrain-following
-- segments per grid street at the kind's vertical offset).
-- The world-axis sign (+1 / -1 along x for z roads, along z for x roads) from a sidewalk toward the
-- parallel asphalt street it borders, or nil.
local function curbSide(road: Road, others: { Road }?): number?
	if not others or (road.axis ~= "x" and road.axis ~= "z") then
		return nil
	end
	local c = road.coord :: number
	local a0, a1 =
		math.min(road.start :: number, road["end"] :: number), math.max(road.start :: number, road["end"] :: number)
	for _, o in others do
		if o.kind == "asphalt" and o.axis == road.axis then
			local oc = o.coord :: number
			local o0, o1 =
				math.min(o.start :: number, o["end"] :: number), math.max(o.start :: number, o["end"] :: number)
			local gap = math.abs(oc - c) - o.width / 2 - road.width / 2
			if gap > -0.5 and gap < 8 and o0 < a1 and o1 > a0 then
				return if oc > c then 1 else -1
			end
		end
	end
	return nil
end

function Plan.road(road: Road, others: { Road }?): BuildPlan
	local look = Kits.ROAD[road.kind] or Kits.ROAD.concrete
	-- the segments (along the terrain, rolled to its crossfall) come from Shared/World/RoadSurface, which
	-- the clients also seat the traffic ghosts on, so the cars stand on exactly these parts' tops
	local offset = look.offsetU * SPU
	local layout = RoadSurface.layout(road :: any, offset)
	local x0, z0, dx, dz, len, n = layout.x0, layout.z0, layout.dx, layout.dz, layout.len, layout.n
	local yaw = layout.yaw -- LookVector along the road
	local parts: { PartSpec } = {}
	local function yAt(t: number): number
		return (RoadSurface.groundAt(x0 + dx * t, z0 + dz * t)) + offset - ROAD_THICKNESS / 2
	end
	local surface = Palette.ROAD[road.kind] or look.color
	local material = look.material
	local yPrev = layout.y[1]
	local ux, uz = layout.ux, layout.uz
	local curb = curbSide(road, others)
	local function strip(
		name: string,
		t: number,
		across: number,
		lift: number,
		w: number,
		h: number,
		l: number,
		color: { number },
		pitch: number,
		ySurface: number?,
		roll: number?
	)
		-- a thin visual strip on the road surface at fraction t, offset `across` to the road's right
		-- (ySurface: the segment's own centre height there, so the strip rides on its tilted top; roll:
		-- the segment's, so a strip off the centre line rides on its rolled top too)
		local r = roll or 0
		table.insert(parts, {
			name = name,
			cx = x0 + dx * t - uz * across,
			cy = (ySurface or yAt(t)) + ROAD_THICKNESS / 2 + lift + across * math.tan(r),
			cz = z0 + dz * t + ux * across,
			yaw = yaw,
			pitch = pitch,
			roll = if r ~= 0 then r else nil,
			sx = w,
			sy = h,
			sz = l,
			color = color,
			material = "SmoothPlastic",
			canCollide = false,
			transparency = 0,
			canQuery = false,
			castShadow = false,
			role = "Paint",
		})
	end
	for i = 1, n do
		local yNext = layout.y[i + 1]
		local seg = len / n
		local rise = yNext - yPrev
		local slopeLen = math.sqrt(seg * seg + rise * rise)
		local tm = (i - 0.5) / n
		local pitch = layout.pitch[i]
		local roll = layout.roll[i]
		table.insert(parts, {
			name = string.format("Seg%03d", i),
			cx = x0 + dx * tm,
			cy = (yPrev + yNext) / 2,
			cz = z0 + dz * tm,
			yaw = yaw,
			pitch = pitch,
			roll = if roll ~= 0 then roll else nil,
			sx = road.width,
			sy = ROAD_THICKNESS,
			sz = math.max(slopeLen, 0.2),
			color = surface,
			material = material,
			canCollide = look.canCollide,
			transparency = 0,
		})
		if road.kind == "asphalt" and road.width >= 10 and seg > 4 then
			-- dashed centre line: two dashes per segment (v5.4 lane paint, as parts on the segment)
			for k = 1, 2 do
				local f = (k - 0.5) / 2
				local t = (i - 1 + f) / n
				strip(
					string.format("Dash%03d_%d", i, k),
					t,
					0,
					0.03,
					0.5,
					0.05,
					math.min(seg * 0.3, 8),
					Palette.ROAD.paint,
					pitch,
					yPrev + (yNext - yPrev) * f,
					roll
				)
			end
		elseif road.kind == "concrete" and curb then
			-- the curb on the sidewalk's street edge
			local side = if road.axis == "z" then -uz * curb else ux * curb
			do
				strip(
					string.format("Curb%03d_%s", i, if side < 0 then "L" else "R"),
					tm,
					side * (road.width / 2 - 0.2),
					0.12,
					0.4,
					0.3,
					math.max(slopeLen, 0.2),
					Palette.ROAD.curb,
					pitch,
					(yPrev + yNext) / 2,
					roll
				)
			end
		end
		yPrev = yNext
	end
	return {
		kind = "road",
		id = road.id,
		category = "road",
		lod = "Disabled",
		streaming = "Default",
		attributes = {
			RoadId = road.id,
			RoadKind = road.kind,
			Axis = road.axis,
			Registered = road.registered == true,
			Width = road.width,
			Length = len,
		},
		parts = parts,
	}
end

return Plan
