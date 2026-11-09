--!strict
-- ReplicatedStorage.Shared.World.Backdrop
-- The world beyond the town (brief v2 §3 Backdrop and §15; worldgen_districts_art §14.4; BUILD_PLAN W6 #1) as
-- plain numbers and pure functions, shared by:
--   tools/bake/backdrop.luau          the Persistent far scenery in build/Backdrop.rbxm (Workspace.Backdrop)
--   WorldGen/BackdropTerrain          the terrain band beyond the world clamp, the north coast and the near sea
--   Client/World/Sky                  the sun model (moon direction) and the sunset azimuth
--   tools/review/backdrop_export      the review renders
-- Layout (game compass, north = +Z): the town lies in a bay. North: a sandy coast at z ~ 1490 st and the ocean
-- to the horizon (Terrain water near the shore, a Persistent plane of 2048-st tiles beyond it). South and both
-- sides: a terrain band (BAND st beyond the world clamp, continuous with World/Height), then the land mesh
-- (plains, hedgerows, a distant road, rolling hills; WedgePart triangles from `mesh()`), then the ranges the
-- bake draws (foothills, mountains, snowy peaks, each lighter and bluer, with fog cards between them).
-- Sun (measured in the engine, CI place v32, GeographicLatitude 39): Lighting:GetSunDirection() is
-- (cos(tilt) cos a, cos(tilt) sin a, sin(tilt)) with a = (ClockTime - 6) / 24 * 2 pi and sin(tilt) = 0.267:
-- up at 6:00 toward +X, culminating toward +Z at 74.5 degrees, down at 18:00 toward (-0.964, 0, 0.267). The
-- radio tower stands on that sunset azimuth from the town centre, just beyond the band.
-- Needs World/Height configured with Generated.TerrainExtensions first (WorldTerrain, the bake and the export
-- do it); the land mesh is built lazily from it and cached (reset() drops the cache).
-- Interface: constants (SEA_Y, OCEAN_Y, OCEAN_NEAR_Z, OCEAN_FAR_Z, WATER_TO_Z, NORTH_FROM_Z, BAND,
--   MESH_INSET, CENTRE, SUN_TILT, SUNSET, TOWER); reset(); clamp(); shoreZ(x); coastProfile(t);
--   outside(x, z) -> (d, px, pz); hills(x, z); mesh() -> Mesh; meshHeight(x, z); groundAt(x, z);
--   sample(x, z) -> (h, land, t, d); materialAt(x, z, h) -> material name; terrainRects() -> { Rect };
--   sunDirection(clockTime, tilt?) -> (x, y, z); moonClockTime(clockTime, phase01) -> clockTime
-- No side effects on require.

local Height = require("./Height")

local Backdrop = {}

Backdrop.SEA_Y = 0 -- terrain water surface (studs)
Backdrop.OCEAN_Y = -0.6 -- top of the Persistent ocean plane: under the terrain water, the far sea elsewhere
Backdrop.OCEAN_NEAR_Z = 1560 -- the plane starts here inside the band's x range (the shallows are terrain)
Backdrop.OCEAN_FAR_Z = 1480 -- and here outside it (the land mesh runs under the plane at the coast)
Backdrop.WATER_TO_Z = 2520 -- terrain water reaches this far (a player on the beach streams about 1 km)
Backdrop.NORTH_FROM_Z = 1360 -- the coast rewrite starts here inside the clamp (identical to World/Height there)
Backdrop.BAND = 360 -- terrain band beyond the world clamp (studs)
Backdrop.MESH_INSET = 40 -- the land mesh starts this far beyond the clamp, under the band terrain
Backdrop.CENTRE = table.freeze({ x = 700, z = -150 }) -- middle of the v5.4 town (studs)
Backdrop.SUN_TILT = math.asin(0.267) -- measured: Z of GetSunDirection() at latitude 39
-- horizontal unit vector toward the setting sun (x, z), from the measured direction at ClockTime 18
Backdrop.SUNSET =
	table.freeze({ x = -0.964 / math.sqrt(0.964 ^ 2 + 0.267 ^ 2), z = 0.267 / math.sqrt(0.964 ^ 2 + 0.267 ^ 2) })
-- the radio tower: on the sunset azimuth from CENTRE, 3.75 km out (beyond the -X band), on a knoll
Backdrop.TOWER = table.freeze({
	x = 700 + 3750 * Backdrop.SUNSET.x,
	z = -150 + 3750 * Backdrop.SUNSET.z,
	height = 360, -- lattice top (studs above its foot); mast and beacon above
	knoll = 60, -- height of the knoll the hills function raises under it
	knollRadius = 520,
})

export type Rect = { minX: number, maxX: number, minZ: number, maxZ: number, water: boolean }
export type Mesh = {
	xs: { number }, -- node x coordinates, ascending
	zs: { number }, -- node z coordinates, ascending
	h: { { number } }, -- h[i][k] at (xs[i], zs[k])
	drawn: (i: number, k: number) -> boolean, -- whether cell (i, k) (between nodes i..i+1, k..k+1) is drawn
	diag: (i: number, k: number) -> boolean, -- true: diagonal from (i, k) to (i+1, k+1)
}

local function smooth01(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end
Backdrop.smooth01 = smooth01

type Clamp = { minX: number, maxX: number, minZ: number, maxZ: number }
local cachedClamp: Clamp? = nil
local cachedMesh: Mesh? = nil

function Backdrop.reset()
	cachedClamp = nil
	cachedMesh = nil
end

-- World clamp in studs (World/Height.worldClamp, cached).
function Backdrop.clamp(): Clamp
	local c = cachedClamp
	if c == nil then
		local w = Height.worldClamp()
		c = { minX = w.minX, maxX = w.maxX, minZ = w.minZ, maxZ = w.maxZ }
		cachedClamp = c
	end
	return c :: Clamp
end

-- Distance outside the world clamp (0 inside) and the nearest clamp point.
function Backdrop.outside(x: number, z: number): (number, number, number)
	local c = Backdrop.clamp()
	local px = math.clamp(x, c.minX, c.maxX)
	local pz = math.clamp(z, c.minZ, c.maxZ)
	local dx, dz = x - px, z - pz
	return math.sqrt(dx * dx + dz * dz), px, pz
end

-- The waterline (studs): z of the shore at x.
function Backdrop.shoreZ(x: number): number
	return 1488 + 9 * math.sin(x / 430 + 0.7) + 5 * math.sin(x / 163 + 2.1)
end

-- Beach and sea floor against the distance past the waterline (t > 0 is under water).
function Backdrop.coastProfile(t: number): number
	return math.max(Backdrop.SEA_Y - t / 22, Backdrop.SEA_Y - 13)
end

-- How strongly the coast replaces the land at (x, z), the profile there, and t.
local function coast(x: number, z: number): (number, number, number)
	local t = z - Backdrop.shoreZ(x)
	return smooth01((t + 110) / 110), Backdrop.coastProfile(t), t
end

-- Rolling land outside the clamp (studs): plains near the town, hills further out, the tower knoll.
function Backdrop.hills(x: number, z: number): number
	local d = Backdrop.outside(x, z)
	local amp = 6 + 30 * smooth01((d - 700) / 2600)
	local n = 0.55 * math.sin(x / 1270 + 0.3) * math.cos(z / 1530 - 1.1)
		+ 0.3 * math.sin((x + z) / 2100 + 2.0)
		+ 0.15 * math.sin(x / 610 - z / 830 + 0.9)
	local h = 14 + amp * n + 0.011 * math.max(0, d - 1300)
	local T = Backdrop.TOWER
	local tx, tz = x - T.x, z - T.z
	h += T.knoll * smooth01(1 - math.sqrt(tx * tx + tz * tz) / T.knollRadius)
	return math.max(h, 3)
end

-- Distances beyond the clamp edge of the mesh node rows and columns.
local OUT_SIDE = { 40, 750, 1450, 2250, 3150, 4200, 5000 }
local OUT_SOUTH = { 40, 750, 1450, 2250, 3350 }
local INNER_STEP = 650 -- node spacing along the clamp edges
local COAST_Z = { 1440, 1520, 1760 } -- side-column rows around the waterline

local function lowestEdge(x: number, z: number): number
	local c = Backdrop.clamp()
	local _, px, pz = Backdrop.outside(x, z)
	local lo = math.huge
	for u = -750, 750, 50 do
		lo = math.min(
			lo,
			Height.at(math.clamp(px + u, c.minX, c.maxX), pz),
			Height.at(px, math.clamp(pz + u, c.minZ, c.maxZ))
		)
	end
	return lo
end

local function nodeHeight(x: number, z: number): number
	local d = Backdrop.outside(x, z)
	local h = if d < 200 then lowestEdge(x, z) - 4 else Backdrop.hills(x, z)
	local m, prof = coast(x, z)
	if m > 0 then
		h += (prof - 3 - h) * m -- under the coast: 3 st below the terrain's profile
	end
	return h
end

local function spaced(a: number, b: number, step: number): { number }
	local n = math.max(1, math.floor((b - a) / step + 0.5))
	local out = {}
	for i = 0, n do
		table.insert(out, a + (b - a) * i / n)
	end
	return out
end

-- The land mesh: a rectangular node grid around the clamp. Cells inside the clamp grown by MESH_INSET (the
-- town) are not drawn; their node heights still exist so meshHeight is defined everywhere in the grid.
function Backdrop.mesh(): Mesh
	if cachedMesh then
		return cachedMesh
	end
	local c = Backdrop.clamp()
	local inset = Backdrop.MESH_INSET
	local xs: { number } = {}
	for i = #OUT_SIDE, 2, -1 do
		table.insert(xs, c.minX - OUT_SIDE[i])
	end
	for _, x in spaced(c.minX - inset, c.maxX + inset, INNER_STEP) do
		table.insert(xs, x)
	end
	for i = 2, #OUT_SIDE do
		table.insert(xs, c.maxX + OUT_SIDE[i])
	end
	local zs: { number } = {}
	for i = #OUT_SOUTH, 2, -1 do
		table.insert(zs, c.minZ - OUT_SOUTH[i])
	end
	for _, z in spaced(c.minZ - inset, COAST_Z[1], INNER_STEP) do
		table.insert(zs, z)
	end
	for i = 2, #COAST_Z do
		table.insert(zs, COAST_Z[i])
	end
	local h: { { number } } = {}
	for i, x in xs do
		h[i] = {}
		for k, z in zs do
			h[i][k] = nodeHeight(x, z)
		end
	end
	local x0, x1, z0 = c.minX - inset, c.maxX + inset, c.minZ - inset
	local m: Mesh = {
		xs = xs,
		zs = zs,
		h = h,
		drawn = function(i: number, k: number): boolean
			local cx, cz = (xs[i] + xs[i + 1]) / 2, (zs[k] + zs[k + 1]) / 2
			return not (cx > x0 and cx < x1 and cz > z0)
		end,
		diag = function(i: number, k: number): boolean
			return (i + k) % 2 == 0
		end,
	}
	cachedMesh = m
	return m
end

local function bracket(list: { number }, v: number): (number, number)
	local n = #list
	if v <= list[1] then
		return 1, 0
	elseif v >= list[n] then
		return n - 1, 1
	end
	local lo, hi = 1, n
	while hi - lo > 1 do
		local mid = (lo + hi) // 2
		if list[mid] <= v then
			lo = mid
		else
			hi = mid
		end
	end
	return lo, (v - list[lo]) / (list[lo + 1] - list[lo])
end

-- Height of the drawn triangle surface at (x, z) (clamped to the grid), exactly as the bake triangulates it.
function Backdrop.meshHeight(x: number, z: number): number
	local m = Backdrop.mesh()
	local i, u = bracket(m.xs, x)
	local k, v = bracket(m.zs, z)
	local h00, h10, h01, h11 = m.h[i][k], m.h[i + 1][k], m.h[i][k + 1], m.h[i + 1][k + 1]
	if m.diag(i, k) then
		-- triangles (00, 10, 11) and (00, 11, 01)
		if u >= v then
			return h00 + (h10 - h00) * u + (h11 - h10) * v
		end
		return h00 + (h11 - h01) * u + (h01 - h00) * v
	end
	-- triangles (00, 10, 01) and (10, 11, 01)
	if u + v <= 1 then
		return h00 + (h10 - h00) * u + (h01 - h00) * v
	end
	return h11 + (h01 - h11) * (1 - u) + (h10 - h11) * (1 - v)
end

-- The ground the server writes beyond (and along the north edge of) the clamp: h, the land before the coast
-- cut, t (distance past the waterline) and d (distance outside the clamp).
function Backdrop.sample(x: number, z: number): (number, number, number, number)
	local d, px, pz = Backdrop.outside(x, z)
	local m, prof, t = coast(x, z)
	if m >= 1 then
		return prof, prof, t, d -- open water: the profile alone (most of the north strip)
	end
	local land: number
	if d <= 0 then
		land = Height.at(x, z)
	else
		local e = Height.at(px, pz)
		if d <= Backdrop.MESH_INSET then
			land = e
		else
			local mh = Backdrop.meshHeight(x, z)
			local s = smooth01((d - Backdrop.MESH_INSET) / 260)
			land = math.max(e + (mh + 2 - e) * s, mh + 1)
		end
	end
	return land + (prof - land) * m, land, t, d
end

function Backdrop.groundAt(x: number, z: number): number
	return (Backdrop.sample(x, z))
end

-- Terrain material name for a column of height h (sand at the waterline, rock where the coast cuts a
-- headland, otherwise World/Height's own rule inside the clamp and grass beyond).
function Backdrop.materialAt(x: number, z: number, h: number): string
	local _, land, t, d = Backdrop.sample(x, z)
	if t > -160 and h < Backdrop.SEA_Y + 3.2 then
		return "Sand"
	end
	if land - h > 8 then
		return "Rock"
	end
	if d <= 0 then
		return if Height.extensionMaterial(x, z) == "Sand" then "Sand" else "Grass"
	end
	return "Grass"
end

-- The rectangles WorldGen/BackdropTerrain writes (studs; TerrainBake grows them to the 4-st grid).
function Backdrop.terrainRects(): { Rect }
	local c = Backdrop.clamp()
	local B = Backdrop.BAND
	local north = Backdrop.NORTH_FROM_Z
	return {
		{ minX = c.minX - B, maxX = c.maxX + B, minZ = north, maxZ = Backdrop.WATER_TO_Z, water = true },
		{ minX = c.minX - B, maxX = c.maxX + B, minZ = c.minZ - B, maxZ = c.minZ, water = false },
		{ minX = c.minX - B, maxX = c.minX, minZ = c.minZ, maxZ = north, water = false },
		{ minX = c.maxX, maxX = c.maxX + B, minZ = c.minZ, maxZ = north, water = false },
	}
end

-- Roblox's sun direction at a ClockTime (the measured model above); tilt defaults to SUN_TILT.
function Backdrop.sunDirection(clockTime: number, tilt: number?): (number, number, number)
	local tl = tilt or Backdrop.SUN_TILT
	local a = (clockTime - 6) / 24 * 2 * math.pi
	local c = math.cos(tl)
	return c * math.cos(a), c * math.sin(a), math.sin(tl)
end

-- The ClockTime whose sun position the moon has: it trails the sun by its phase (0 new, 0.5 full), so the
-- full moon rises at sunset and the new moon is up with the sun (worldgen_districts_art §14.4).
function Backdrop.moonClockTime(clockTime: number, phase01: number): number
	return (clockTime - phase01 * 24) % 24
end

return Backdrop
