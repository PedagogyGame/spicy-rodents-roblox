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
local Hospital = require("./Builders/Hospital")
local House = require("./Builders/House")
local Import = require("./Import")
local Kits = require("./Kits")
local PoliceStation = require("./Builders/PoliceStation")
local Sign = require("./Builders/Sign")
local Treehouse = require("./Builders/Treehouse")
local Spec = require("./Spec")
local Height = Import.shared("World/Height") :: typeof(require("../shared/World/Height"))
local Buildings = Import.generated("Buildings") :: { [string]: any }
local Interiors = Import.generated("Interiors") :: { [string]: any }

local Plan = {}

local SPU = Kits.STUDS_PER_UNIT
local HALF_PI = math.pi / 2
local PLATE_THICKNESS = 0.2
local CONTAIN_TOLERANCE = 0.5 -- studs: a child may poke this far out of its parent's footprint
local ROAD_SEGMENT = 40 -- studs: roads follow the terrain in straight segments this long or less
local ROAD_THICKNESS = 0.4

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
local function blockPart(lot: Lot, kit: Kits.Kit, seat: number, q: number, sx: number, sz: number, isChild: boolean): PartSpec
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
		color = kit.color,
		material = kit.material,
		canCollide = solid,
		transparency = transparency,
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
		}
		if (kit.builder == "Hospital" or kit.builder == "PoliceStation") and not lctx.building then
			Building.plan(lctx)
		else
			family(lctx)
		end
	else
		list:world(blockPart(lot, kit, seat, q, sx, sz, isChild))
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

local function endpoints(road: Road): (number, number, number, number)
	if road.axis == "x" then
		local z = road.coord :: number
		return road.start :: number, z, road["end"] :: number, z
	elseif road.axis == "z" then
		local x = road.coord :: number
		return x, road.start :: number, x, road["end"] :: number
	end
	local s, e = road.start :: { number }, road["end"] :: { number }
	return s[1], s[2], e[1], e[2]
end

-- A road is a chain of flat parts following the terrain (v5.4 draws 104 terrain-following
-- segments per grid street at the kind's vertical offset).
function Plan.road(road: Road): BuildPlan
	local look = Kits.ROAD[road.kind] or Kits.ROAD.concrete
	local x0, z0, x1, z1 = endpoints(road)
	local dx, dz = x1 - x0, z1 - z0
	local len = math.sqrt(dx * dx + dz * dz)
	local n = math.max(1, math.ceil(len / ROAD_SEGMENT))
	local yaw = if len > 0 then math.atan2(-dx, -dz) else 0 -- LookVector along the road
	local offset = look.offsetU * SPU
	local parts: { PartSpec } = {}
	local function yAt(t: number): number
		return Height.at(x0 + dx * t, z0 + dz * t) + offset - ROAD_THICKNESS / 2
	end
	local yPrev = yAt(0)
	for i = 1, n do
		local yNext = yAt(i / n)
		local seg = len / n
		local rise = yNext - yPrev
		local slopeLen = math.sqrt(seg * seg + rise * rise)
		local tm = (i - 0.5) / n
		table.insert(parts, {
			name = string.format("Seg%03d", i),
			cx = x0 + dx * tm,
			cy = (yPrev + yNext) / 2,
			cz = z0 + dz * tm,
			yaw = yaw,
			pitch = math.atan2(rise, seg),
			sx = road.width,
			sy = ROAD_THICKNESS,
			sz = math.max(slopeLen, 0.2),
			color = look.color,
			material = look.material,
			canCollide = look.canCollide,
			transparency = 0,
		})
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
