--!strict
-- ReplicatedStorage.Shared.World.Height
-- Verbatim port of v5.4 smoothstep (L403-406), baseTerrainHeight (L407-416), RIVER (L419-435),
-- riverCenter / inRiverDistrict / insideRiverWater / riverDeckAt (L436-457) and terrainHeight
-- (L458-464) [worldgen_core §3, §16]. Golden-tested against tests/golden/terrain.json (11,060 rows,
-- tolerance 1e-9 in HTML units; tests/unit/world_height.spec.luau).
-- Interface (BUILD_PLAN §1.4): base(x, z), at(x, z) in STUDS (runtime code sees studs only, D21);
-- the `*U` functions are the verbatim HTML-unit originals the stud wrappers scale around.
-- D32 extensions (terrain_extensions.json) are W1: outside the v5.4 rectangle this is still v5.4.
-- Pure: no state, no side effects on require.

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

-- Stud wrappers (the runtime interface).
function Height.base(x: number, z: number): number
	return Height.baseU(x / STUDS_PER_UNIT, z / STUDS_PER_UNIT) * STUDS_PER_UNIT
end

function Height.at(x: number, z: number): number
	return Height.atU(x / STUDS_PER_UNIT, z / STUDS_PER_UNIT) * STUDS_PER_UNIT
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
