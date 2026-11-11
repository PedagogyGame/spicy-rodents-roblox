--!strict
-- ReplicatedStorage.Shared.World.Height
-- Verbatim port of v5.4 smoothstep (L403-406), baseTerrainHeight (L407-416), RIVER (L419-435),
-- riverCenter / inRiverDistrict / insideRiverWater / riverDeckAt (L436-457) and terrainHeight
-- (L458-464) [worldgen_core §3, §16]. Golden-tested against tests/golden/terrain.json (11,060 rows,
-- tolerance 1e-9 in HTML units; tests/unit/world_height.spec.luau).
-- Interface (BUILD_PLAN §1.4): base(x, z), at(x, z) in STUDS (runtime code sees studs only, D21);
-- the `*U` functions are the verbatim HTML-unit originals the stud wrappers scale around.
-- D32 extensions (W1 #7): `configure(generated TerrainExtensions)` adds the authored patches (hill,
-- ridge, back field, long beach) OUTSIDE the verbatim rectangle, blended in over `blendU` so the
-- ground stays continuous; inside the rectangle `at` is the verbatim port, bit for bit. Until
-- configure is called (Data/WorldBoot does it once at boot), `at` is the v5.4 function everywhere.
-- Interface additions: configure(ext?), terrainU(x, z), extensionMaterial(x, z), worldClamp()
-- Building sites: `at` is `natural` (the port and the patches) with a level site cut for each building
-- in SITES; natural(x, z), SITES, SITE_MARGIN, SITE_BANK.
-- State: the configured extension table only; no side effects on require.

local Height = {}

local STUDS_PER_UNIT = 2.5 -- Config/Units.STUDS_PER_UNIT (kept local: this module has no requires)
Height.STUDS_PER_UNIT = STUDS_PER_UNIT

-- RIVER (L419-435), HTML units.
Height.RIVER = table.freeze({
	startX = 687,
	endX = 1150,
	zMin = -244,
	zMax = 443,
	centerX = 850,
	halfWidth = 52,
	bankY = 8,
	waterY = 2.4,
	bedY = -2,
	bridgeZ = 0,
	deckY = 15.8,
	bridgeStart = 790,
	bridgeEnd = 910,
	rampStart = 744,
	rampEnd = 956,
})
local RIVER = Height.RIVER

-- v5.4 modelled extent (worldgen_core §2): x -590..1150, z -565..443 HTML units.
Height.PLAYABLE_U = table.freeze({ minX = -590, maxX = 1150, minZ = -565, maxZ = 443 })

-- smoothstep (L403-406): THREE.MathUtils.clamp(t, 0, 1) then t*t*(3-2t).
local function smoothstep(t: number): number
	t = math.max(0, math.min(1, t)) -- THREE clamp = Math.max(min, Math.min(max, value))
	return t * t * (3 - 2 * t)
end

-- THREE.MathUtils.smoothstep(x, min, max) (three r160).
local function threeSmoothstep(x: number, min: number, max: number): number
	if x <= min then
		return 0
	end
	if x >= max then
		return 1
	end
	x = (x - min) / (max - min)
	return x * x * (3 - 2 * x)
end

-- baseTerrainHeight (L407-416)
function Height.baseU(x: number, z: number): number
	local dist = math.max(math.abs(x), math.abs(z))
	local blend = smoothstep((dist - 104) / 86)
	local hills = 3.5
		+ 2.5 * math.sin(x * 0.016 + z * 0.008 + 1.1)
		+ 2.1 * math.cos(z * 0.02 - x * 0.009)
		+ 1.45 * math.sin(x * 0.034 + 1.3) * math.cos(z * 0.029 - 0.8)
	return math.max(-0.02, blend * math.max(0.1, hills))
end

-- riverCenter (L436-438)
function Height.riverCenterU(z: number): number
	return RIVER.centerX + 9 * math.sin(z * 0.009)
end

-- inRiverDistrict (L439-441)
function Height.inRiverDistrictU(x: number, z: number): boolean
	return x >= RIVER.startX and x <= RIVER.endX and z >= RIVER.zMin and z <= RIVER.zMax
end

-- insideRiverWater (L442-444)
function Height.insideRiverWaterU(x: number, z: number): boolean
	return Height.inRiverDistrictU(x, z) and math.abs(x - Height.riverCenterU(z)) < RIVER.halfWidth - 1e-6
end

-- riverDeckAt (L445-457): deck height or nil off the bridge strip.
function Height.riverDeckAtU(x: number, z: number): number?
	if math.abs(z - RIVER.bridgeZ) > 7.8 or x < RIVER.rampStart or x > RIVER.rampEnd then
		return nil
	end
	if x < RIVER.bridgeStart then
		return RIVER.bankY
			+ ((RIVER.deckY - RIVER.bankY) * (x - RIVER.rampStart)) / (RIVER.bridgeStart - RIVER.rampStart)
	end
	if x > RIVER.bridgeEnd then
		return RIVER.deckY - ((RIVER.deckY - RIVER.bankY) * (x - RIVER.bridgeEnd)) / (RIVER.rampEnd - RIVER.bridgeEnd)
	end
	return RIVER.deckY
end

-- terrainHeight (L458-464)
function Height.atU(x: number, z: number): number
	local original = Height.baseU(x, z)
	if not Height.inRiverDistrictU(x, z) then
		return original
	end
	if Height.insideRiverWaterU(x, z) then
		return RIVER.bedY
	end
	local t = threeSmoothstep(x, RIVER.startX, 735)
	return original * (1 - t) + RIVER.bankY * t
end

-- D32 terrain extensions (HTML units). `ext` is generated/TerrainExtensions or nil.
local ext: any = nil

function Height.configure(e: any?)
	ext = e
	-- (the building sites below take their level from the configured ground)
	for _, s in Height.SITES do
		s.level = nil
	end
end

local function smooth01(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

local function rectMask(p: any, x: number, z: number): number
	if x < p.minX or x > p.maxX or z < p.minZ or z > p.maxZ then
		return 0
	end
	local d = math.min(x - p.minX, p.maxX - x, z - p.minZ, p.maxZ - z)
	return smooth01(d / p.edge)
end

-- Strength of one patch at (x, z) in [0, 1] and the value it contributes (height to add, or target).
local function patchAt(p: any, x: number, z: number): (number, number)
	if p.shape == "dome" then
		local d = math.sqrt((x - p.cx) ^ 2 + (z - p.cz) ^ 2)
		return smooth01(1 - d / p.radius), p.height
	elseif p.shape == "ridge" then
		local ax, az, bx, bz = p.from[1], p.from[2], p.to[1], p.to[2]
		local abx, abz = bx - ax, bz - az
		local t = math.clamp(((x - ax) * abx + (z - az) * abz) / (abx * abx + abz * abz), 0, 1)
		local d = math.sqrt((x - ax - abx * t) ^ 2 + (z - az - abz * t) ^ 2)
		return smooth01(1 - d / p.halfWidth), p.height
	elseif p.shape == "field" then
		local m = rectMask(p, x, z)
		local w = 2 * math.pi / p.wavelength
		return m, p.base + p.amplitude * math.sin(x * w) * math.cos(z * w)
	elseif p.shape == "beach" then
		local m = rectMask(p, x, z)
		local t = math.clamp((z - p.minZ) / (p.maxZ - p.minZ), 0, 1)
		return m, p.fromY + (p.toY - p.fromY) * t
	end
	return 0, 0
end

-- Distance (HTML units) outside the verbatim rectangle; 0 inside.
local function outside(x: number, z: number): number
	local r = ext.verbatimRect
	local dx = math.max(r.minX - x, 0, x - r.maxX)
	local dz = math.max(r.minZ - z, 0, z - r.maxZ)
	return math.sqrt(dx * dx + dz * dz)
end

-- The ground with the extensions (HTML units): verbatim inside the rectangle.
function Height.terrainU(x: number, z: number): number
	local h = Height.atU(x, z)
	if ext == nil then
		return h
	end
	local d = outside(x, z)
	if d <= 0 then
		return h
	end
	local w = smooth01(d / ext.blendU)
	for _, p in ext.patches do
		local m, v = patchAt(p, x, z)
		if m > 0 then
			if p.mode == "set" then
				h = h + (v - h) * m * w
			else
				h += v * m * w
			end
		end
	end
	return h
end

-- Surface material name of the strongest patch at (x, z) (studs), or nil (v5.4 grass/mud rules).
function Height.extensionMaterial(x: number, z: number): string?
	if ext == nil then
		return nil
	end
	local xu, zu = x / STUDS_PER_UNIT, z / STUDS_PER_UNIT
	local d = outside(xu, zu)
	if d <= 0 then
		return nil
	end
	local w = smooth01(d / ext.blendU)
	local best, bestM = nil, 0.5
	for _, p in ext.patches do
		local m = patchAt(p, xu, zu)
		if m * w > bestM then
			best, bestM = p.material, m * w
		end
	end
	return best
end

-- World clamp in studs (grown by D32 when configured; the v5.4 playable rectangle otherwise).
function Height.worldClamp(): { minX: number, maxX: number, minZ: number, maxZ: number }
	local r = if ext then ext.worldClampU else Height.PLAYABLE_U
	return {
		minX = r.minX * STUDS_PER_UNIT,
		maxX = r.maxX * STUDS_PER_UNIT,
		minZ = r.minZ * STUDS_PER_UNIT,
		maxZ = r.maxZ * STUDS_PER_UNIT,
	}
end

-- Stud wrappers (the runtime interface).
function Height.base(x: number, z: number): number
	return Height.baseU(x / STUDS_PER_UNIT, z / STUDS_PER_UNIT) * STUDS_PER_UNIT
end

-- The ground before any building site is cut into it (studs): the port and the D32 patches.
function Height.natural(x: number, z: number): number
	return Height.terrainU(x / STUDS_PER_UNIT, z / STUDS_PER_UNIT) * STUDS_PER_UNIT
end

-- Building sites (the interiors work, 2026-11-11). A building people walk into stands on a level site
-- cut into the slope: v5.4's hospital sat in rising ground, which in voxels came up through the floor of
-- its back rooms (as much as 5 st of grass indoors) and buried the staff exit 2 st deep. Inside a site
-- (the lot's footprint and SITE_MARGIN round it) the ground is never above the height at the lot's
-- centre, which is the building's seat; outside it the cut bank climbs back to the natural ground at
-- SITE_BANK studs per stud. A site only ever lowers the ground. The list is static because this module
-- has no requires; tests/unit/worldgen_enter.spec checks it against the lot data (every enterable lot
-- that needs one has one, with the lot's own centre and footprint).
Height.SITE_MARGIN = 6
Height.SITE_BANK = 0.8
type Site = { id: string, x: number, z: number, w: number, d: number, level: number? }
local SITES: { Site } = {
	{ id = "hospital_main", x = -890, z = 882.5, w = 235, d = 240 },
	{ id = "west_police_station", x = -1275, z = -267.5, w = 115, d = 77.5 },
}
Height.SITES = SITES

function Height.at(x: number, z: number): number
	local h = Height.natural(x, z)
	for _, s in SITES do
		local level: number = s.level or Height.natural(s.x, s.z)
		s.level = level
		if h > level then
			local dx = math.max(math.abs(x - s.x) - s.w / 2 - Height.SITE_MARGIN, 0)
			local dz = math.max(math.abs(z - s.z) - s.d / 2 - Height.SITE_MARGIN, 0)
			local cap = level + Height.SITE_BANK * math.sqrt(dx * dx + dz * dz)
			if cap < h then
				h = cap
			end
		end
	end
	return h
end

function Height.insideRiverWater(x: number, z: number): boolean
	return Height.insideRiverWaterU(x / STUDS_PER_UNIT, z / STUDS_PER_UNIT)
end

function Height.riverDeckAt(x: number, z: number): number?
	local d = Height.riverDeckAtU(x / STUDS_PER_UNIT, z / STUDS_PER_UNIT)
	return if d then d * STUDS_PER_UNIT else nil
end

-- Water surface in studs (RIVER.waterY), for TerrainBake.
Height.WATER_Y = RIVER.waterY * STUDS_PER_UNIT

return Height
