--!strict
-- ReplicatedStorage.Shared.World.Town
-- Lot and district queries and the pavement model (BUILD_PLAN §1.4 World/Town, §4.4 #2).
-- * lotAt(x, z): the lot whose footprint holds the point (the smallest when footprints overlap).
-- * districtTag(x, z): that lot's district; outside every lot, "offroad" inside the terrain
--   extension's off-road rectangle (jurisdiction false, brief v2 §15), else "street".
-- * Pavement: every road strip from roads.json (axis, coord, start, end, width) is a raised ribbon
--   over terrain, v5.4 outdoorSurfaceAt (L513-528) with registerPavement's offsets (asphalt 0.055 u,
--   other paving 0.09 u) plus the four core curb blocks (0.245 u at |x| <= 129, |z -/+ 10.1| <= 0.16
--   and the transposed pair). pavementDistance is v5.4's pavementDistance: 0 on a strip, else the
--   distance to the nearest strip edge (utility poles must stay >= 0.95 u away).
-- * sidewalks(): the concrete strips as walkable lanes (Nav and the Pedestrian brain read them).
-- Interface: fromData(data) -> Town; lotAt, districtTag, pavementAt(x, z) -> number?,
--   pavementDistance(x, z), sidewalks() -> { Strip }, strips
-- Pure; studs. No side effects on require.

local Height = require("./Height")

export type Strip = {
	id: string,
	kind: string,
	axis: "x" | "z",
	coord: number, -- the fixed cross coordinate (studs)
	min: number, -- extent along the axis
	max: number,
	half: number, -- half width
	offset: number, -- height over terrain
}

export type Lot = { id: string, x: number, z: number, hw: number, hd: number, district: string, type: string }

export type Town = {
	strips: { Strip },
	lots: { Lot },
	offroad: { minX: number, maxX: number, minZ: number, maxZ: number }?,
	lotAt: (self: Town, x: number, z: number) -> Lot?,
	districtTag: (self: Town, x: number, z: number) -> string,
	pavementAt: (self: Town, x: number, z: number) -> number?,
	pavementDistance: (self: Town, x: number, z: number) -> number,
	sidewalks: (self: Town) -> { Strip },
}

local S = Height.STUDS_PER_UNIT
local Town = {}

Town.OFFSET = table.freeze({ asphalt = 0.055 * S, default = 0.09 * S })
Town.CURB_Y = 0.245 * S

local function inStrip(s: Strip, x: number, z: number): boolean
	if s.axis == "z" then
		return math.abs(x - s.coord) <= s.half and z >= s.min and z <= s.max
	end
	return math.abs(z - s.coord) <= s.half and x >= s.min and x <= s.max
end

local function stripDistance(s: Strip, x: number, z: number): number
	local along, across = if s.axis == "z" then z else x, if s.axis == "z" then x else z
	local da = math.max(0, math.abs(across - s.coord) - s.half)
	local dl = math.max(0, s.min - along, along - s.max)
	return math.sqrt(da * da + dl * dl)
end

local function curb(x: number, z: number): boolean
	local ux, uz = x / S, z / S
	for _, side in { -1, 1 } do
		if
			(math.abs(ux) <= 129 and math.abs(uz - side * 10.1) <= 0.16)
			or (math.abs(uz) <= 129 and math.abs(ux - side * 10.1) <= 0.16)
		then
			return true
		end
	end
	return false
end

local methods = {}

function methods.lotAt(self: Town, x: number, z: number): Lot?
	local best: Lot? = nil
	local bestArea = math.huge
	for _, l in self.lots do
		if math.abs(x - l.x) <= l.hw and math.abs(z - l.z) <= l.hd then
			local a = l.hw * l.hd
			if a < bestArea then
				best, bestArea = l, a
			end
		end
	end
	return best
end

function methods.districtTag(self: Town, x: number, z: number): string
	local l = self:lotAt(x, z)
	if l then
		return l.district
	end
	local o = self.offroad
	if o and x >= o.minX and x <= o.maxX and z >= o.minZ and z <= o.maxZ then
		return "offroad"
	end
	return "street"
end

-- pavementAt(x, z): the paving surface height (terrain + offset) when (x, z) is on a strip or curb.
function methods.pavementAt(self: Town, x: number, z: number): number?
	local best: number? = nil
	local terrain: number? = nil
	for _, s in self.strips do
		if inStrip(s, x, z) then
			terrain = terrain or Height.at(x, z)
			local y = (terrain :: number) + s.offset
			if best == nil or y > best then
				best = y
			end
		end
	end
	if curb(x, z) and (best == nil or Town.CURB_Y > best) then
		best = Town.CURB_Y
	end
	return best
end

function methods.pavementDistance(self: Town, x: number, z: number): number
	local d = math.huge
	for _, s in self.strips do
		local v = stripDistance(s, x, z)
		if v < d then
			d = v
			if d == 0 then
				break
			end
		end
	end
	return d
end

function methods.sidewalks(self: Town): { Strip }
	local out = {}
	for _, s in self.strips do
		if s.kind == "concrete" then
			table.insert(out, s)
		end
	end
	return out
end

-- new(strips, lots, offroad?)
function Town.new(strips: { Strip }, lots: { Lot }, offroad: any?): Town
	local t = { strips = strips, lots = lots, offroad = offroad }
	for k, f in methods do
		(t :: any)[k] = f
	end
	return (t :: any) :: Town
end

-- fromData(data): strips from roads.json (axis-aligned roads only), lots from lots/*.json, the
-- off-road rectangle from terrain_extensions.json.
function Town.fromData(data: any): Town
	local strips: { Strip } = {}
	for _, r in data:roads() do
		if (r.axis == "x" or r.axis == "z") and r.coord and r.width and r.start and r["end"] then
			table.insert(strips, {
				id = r.id,
				kind = r.kind,
				axis = r.axis,
				coord = r.coord,
				min = math.min(r.start, r["end"]),
				max = math.max(r.start, r["end"]),
				half = r.width * 0.5,
				offset = if r.kind == "asphalt" then Town.OFFSET.asphalt else Town.OFFSET.default,
			})
		end
	end
	local lots: { Lot } = {}
	for _, l in data:lots() do
		if l.footprint then
			table.insert(lots, {
				id = l.id,
				x = l.x,
				z = l.z,
				hw = l.footprint.w * 0.5,
				hd = l.footprint.d * 0.5,
				district = l.district,
				type = l.type,
			})
		end
	end
	local offroad = nil
	local ext = data:module("TerrainExtensions") :: any
	if ext then
		for _, d in ext.districts or {} do
			if d.id == "offroad" then
				offroad = { minX = d.minX * S, maxX = d.maxX * S, minZ = d.minZ * S, maxZ = d.maxZ * S }
			end
		end
	end
	return Town.new(strips, lots, offroad)
end

return Town
