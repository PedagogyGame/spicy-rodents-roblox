--!strict
-- ReplicatedStorage.Shared.World.SkyKeys
-- The day cycle's look as data (worldgen_districts_art §14.3 phase table and §14.2 mapping; brief v2 §3 "sunrise and
-- sunset as their own graphic moments ... a genuinely beautiful night sky"): lighting keyframes over the game clock's
-- hour (Time/Clock, Time/DayCurve), the hour -> Lighting.ClockTime warp, and the moon's lit shape. Pure numbers and
-- hex strings, so Lune tests it; Client/World/Sky applies a state every frame.
-- Keys: deep night (Atmosphere #2a3142 / decay #1a1f2b, OutdoorAmbient #2e3550, exposure about -0.25, lamps on),
-- dawn, the sunrise moment (ColorShift_Top #ffb98a, decay #e8a070, glare 0.6, sun rays 0.2), golden morning and
-- golden afternoon (both exactly World/LightingPreset.GOLDEN, the default look), clear day (the v5.4 "daylight"
-- preset), the sunset moment (ColorShift_Top #f4b88b then #ff9f6e, sun rays 0.25-0.28), blue hour (zenith #485a8a,
-- fog #89929e, lamps fading in).
-- Warp: Roblox's sun (measured, World/Backdrop) is on the horizon at ClockTime 6 and 18. DayCurve's sunrise
-- segment (05:00-06:30) maps to ClockTime 5.45-6.45 and its sunset segment (18:30-19:45) to 17.55-18.45, so the
-- sun really crosses the horizon inside the held-longer moments; golden afternoon starts at ClockTime 16, the
-- preset's own.
-- Interface: KEYS, WARP, clockTimeAt(hour), stateAt(hour) -> State, illumination(phase01) -> fraction lit,
--   moonRows(phase01, n) -> { { top, height, darkFrom, litFrom, litTo } } (scale units across the disc, lit side
--   toward +x), weather(days) -> cloud cover
-- No side effects on require.

local LightingPreset = require("./LightingPreset")

local SkyKeys = {}

export type State = {
	brightness: number,
	exposure: number,
	top: { number },
	bottom: { number },
	outdoor: { number },
	ambient: { number },
	diffuse: number,
	specular: number,
	atmDensity: number,
	atmOffset: number,
	atmColor: { number },
	atmDecay: { number },
	atmGlare: number,
	atmHaze: number,
	ccBrightness: number,
	ccContrast: number,
	ccSaturation: number,
	ccTint: { number },
	bloomIntensity: number,
	bloomSize: number,
	bloomThreshold: number,
	raysIntensity: number,
	raysSpread: number,
	sunSize: number,
	clouds: { number },
	cloudDensity: number,
	fog: { number }, -- near fog-card colour (layer 1)
	fogFar: { number }, -- far fog-card colour (layer 3)
	lamps: number, -- street lamps, beacons and night lights, 0..1
}

local G = LightingPreset.GOLDEN
local GOLDEN = {
	brightness = G.brightness,
	exposure = G.exposure,
	top = G.colorShiftTop,
	bottom = G.colorShiftBottom,
	outdoor = G.outdoorAmbient,
	ambient = G.ambient,
	diffuse = G.diffuse,
	specular = G.specular,
	atmDensity = G.atmosphere.density,
	atmOffset = G.atmosphere.offset,
	atmColor = G.atmosphere.color,
	atmDecay = G.atmosphere.decay,
	atmGlare = G.atmosphere.glare,
	atmHaze = G.atmosphere.haze,
	ccBrightness = G.correction.brightness,
	ccContrast = G.correction.contrast,
	ccSaturation = G.correction.saturation,
	ccTint = G.correction.tint,
	bloomIntensity = G.bloom.intensity,
	bloomSize = G.bloom.size,
	bloomThreshold = G.bloom.threshold,
	raysIntensity = G.sunRays.intensity,
	raysSpread = G.sunRays.spread,
	sunSize = G.sky.sunAngularSize,
	clouds = "fff6e6",
	cloudDensity = 0.7,
	fog = "cfd6c4",
	fogFar = "c2cfda",
	lamps = 0,
}

local function with(base: { [string]: any }, over: { [string]: any }): { [string]: any }
	local t = table.clone(base)
	for k, v in over do
		t[k] = v
	end
	return t
end

local DAY = with(GOLDEN, {
	brightness = 2.9,
	exposure = 0.11,
	top = "fff5df",
	bottom = "657753",
	outdoor = "a2b1a1",
	ambient = "6f7468",
	diffuse = 0.65,
	specular = 0.32,
	atmDensity = 0.26,
	atmColor = "bfd4d9",
	atmDecay = "a7b6ad",
	atmGlare = 0.1,
	atmHaze = 1.2,
	ccContrast = 0.04,
	ccSaturation = 0,
	bloomIntensity = 0.25,
	bloomSize = 24,
	bloomThreshold = 1.6,
	raysIntensity = 0.05,
	sunSize = 13,
	clouds = "fffaf0",
	fog = "c9d6d8",
	fogFar = "bccbd8",
})

local NIGHT = with(GOLDEN, {
	brightness = 0.42,
	exposure = -0.25,
	top = "8d9cc6",
	bottom = "1d2230",
	outdoor = "2e3550",
	ambient = "262b3a",
	diffuse = 0.35,
	specular = 0.2,
	atmDensity = 0.3,
	atmOffset = 0.12,
	atmColor = "2a3142",
	atmDecay = "1a1f2b",
	atmGlare = 0,
	atmHaze = 0.6,
	ccContrast = 0.08,
	ccSaturation = -0.08,
	ccTint = "dfe6ff",
	bloomIntensity = 0.55,
	bloomSize = 30,
	bloomThreshold = 1.05,
	raysIntensity = 0,
	sunSize = 14,
	clouds = "323949",
	cloudDensity = 0.55,
	fog = "273042",
	fogFar = "2a3249",
	lamps = 1,
})

-- Keyframes at game-clock hours (DayCurve: night 20:30-05:00, sunrise 05:00-06:30, golden am to 08:30, day to
-- 16:30, golden pm to 18:30, sunset to 19:45, blue hour to 20:30).
SkyKeys.KEYS = {
	{ hour = 0, state = NIGHT },
	{
		hour = 4.4,
		state = with(NIGHT, { outdoor = "343a55", atmColor = "33394f", atmDecay = "2a2a3a", fog = "2e3548" }),
	},
	{
		hour = 5.0, -- dawn: the sun 4 degrees under the horizon
		state = with(GOLDEN, {
			brightness = 0.9,
			exposure = 0,
			top = "c99a90",
			bottom = "4a3f4a",
			outdoor = "5d5a72",
			ambient = "4a4858",
			diffuse = 0.45,
			specular = 0.25,
			atmDensity = 0.34,
			atmOffset = 0.2,
			atmColor = "a99aa6",
			atmDecay = "8a6c78",
			atmGlare = 0.25,
			atmHaze = 1.6,
			ccTint = "f6eef4",
			ccSaturation = -0.04,
			bloomIntensity = 0.45,
			bloomThreshold = 1.25,
			raysIntensity = 0.1,
			sunSize = 17,
			clouds = "c8a0a0",
			cloudDensity = 0.65,
			fog = "a79aa6",
			fogFar = "9a96ad",
			lamps = 0.7,
		}),
	},
	{
		hour = 5.83, -- the sunrise moment: the sun on the horizon (ClockTime 6)
		state = with(GOLDEN, {
			brightness = 1.6,
			exposure = 0.22,
			top = "ffb98a",
			bottom = "5e5450",
			outdoor = "8a7a78",
			ambient = "6a6060",
			atmDensity = 0.34,
			atmColor = "e3c3a5",
			atmDecay = "e8a070",
			atmGlare = 0.6,
			atmHaze = 1.9,
			ccContrast = 0.06,
			ccSaturation = 0,
			ccTint = "fff0e0",
			bloomIntensity = 0.42,
			bloomThreshold = 1.35,
			raysIntensity = 0.2,
			sunSize = 17,
			clouds = "ffd2b0",
			fog = "e6c9b0",
			fogFar = "d9c2be",
			lamps = 0.2,
		}),
	},
	{
		hour = 6.5, -- sunrise ends
		state = with(GOLDEN, {
			brightness = 2.2,
			exposure = 0.18,
			top = "ffd29e",
			outdoor = "9b9884",
			atmDensity = 0.31,
			atmColor = "d7d2bc",
			atmDecay = "d4a87c",
			atmGlare = 0.35,
			atmHaze = 1.7,
			ccTint = "fff7ec",
			bloomIntensity = 0.35,
			bloomThreshold = 1.45,
			raysIntensity = 0.14,
			sunSize = 15,
			clouds = "fff0dc",
			fog = "d8d6c2",
			fogFar = "c8cdd2",
		}),
	},
	{ hour = 7.6, state = GOLDEN },
	{ hour = 10, state = DAY },
	{ hour = 15, state = DAY },
	{ hour = 16.5, state = GOLDEN },
	{ hour = 17.6, state = GOLDEN },
	{
		hour = 18.5, -- the sunset moment begins
		state = with(GOLDEN, {
			brightness = 1.9,
			exposure = 0.24,
			top = "f4b88b",
			bottom = "56584a",
			outdoor = "958478",
			ambient = "6b6258",
			atmDensity = 0.3,
			atmColor = "e2bba0",
			atmDecay = "d08a6a",
			atmGlare = 0.5,
			atmHaze = 2.0,
			ccContrast = 0.06,
			ccSaturation = 0.02,
			ccTint = "fff0e2",
			bloomIntensity = 0.4,
			bloomThreshold = 1.35,
			raysIntensity = 0.25,
			sunSize = 17,
			clouds = "ffc9a0",
			fog = "e3b9a2",
			fogFar = "d2aeae",
			lamps = 0.15,
		}),
	},
	{
		hour = 19.08, -- the sun on the horizon (ClockTime 18): the tower's beacons against the low sun
		state = with(GOLDEN, {
			brightness = 1.2,
			exposure = 0.28,
			top = "ff9f6e",
			bottom = "4a4048",
			outdoor = "836e77",
			ambient = "5a5058",
			diffuse = 0.5,
			atmDensity = 0.31,
			atmOffset = 0.22,
			atmColor = "d79a8c",
			atmDecay = "a86478",
			atmGlare = 0.7,
			atmHaze = 2.2,
			ccContrast = 0.06,
			ccSaturation = 0.03,
			ccTint = "ffe9dc",
			bloomIntensity = 0.45,
			bloomSize = 30,
			bloomThreshold = 1.25,
			raysIntensity = 0.28,
			sunSize = 18,
			clouds = "f7a98e",
			fog = "d6a094",
			fogFar = "b88f9e",
			lamps = 0.55,
		}),
	},
	{
		hour = 19.75, -- blue hour
		state = with(GOLDEN, {
			brightness = 0.75,
			exposure = 0.15,
			top = "9aa6d0",
			bottom = "2e3346",
			outdoor = "4e5872",
			ambient = "3e4458",
			diffuse = 0.4,
			specular = 0.22,
			atmDensity = 0.3,
			atmOffset = 0.15,
			atmColor = "89929e",
			atmDecay = "485a8a",
			atmGlare = 0.15,
			atmHaze = 1.2,
			ccContrast = 0.07,
			ccSaturation = -0.04,
			ccTint = "e4e8ff",
			bloomIntensity = 0.5,
			bloomSize = 30,
			bloomThreshold = 1.15,
			raysIntensity = 0.05,
			clouds = "8a8fae",
			cloudDensity = 0.6,
			fog = "7f899c",
			fogFar = "6e7a96",
			lamps = 0.9,
		}),
	},
	{
		hour = 20.5,
		state = with(
			NIGHT,
			{ brightness = 0.5, exposure = -0.15, outdoor = "343b58", atmColor = "2c3346", fog = "2d3446" }
		),
	},
}

-- Game hour -> Lighting.ClockTime (piecewise linear, monotone; wraps through midnight).
SkyKeys.WARP = {
	{ 5.0, 5.45 },
	{ 5.83, 6.0 },
	{ 6.5, 6.45 },
	{ 8.5, 8.3 },
	{ 16.5, 16.0 },
	{ 18.5, 17.55 },
	{ 19.08, 18.0 },
	{ 19.75, 18.45 },
	{ 20.5, 18.95 },
	{ 29.0, 29.45 }, -- 05:00 the next day
}

function SkyKeys.clockTimeAt(hour: number): number
	local h = hour % 24
	if h < SkyKeys.WARP[1][1] then
		h += 24
	end
	local w = SkyKeys.WARP
	for i = 1, #w - 1 do
		local a, b = w[i], w[i + 1]
		if h <= b[1] then
			local f = (h - a[1]) / (b[1] - a[1])
			return (a[2] + (b[2] - a[2]) * f) % 24
		end
	end
	return h % 24
end

local function rgb(v: any): { number }
	if type(v) == "string" then
		return {
			tonumber(string.sub(v, 1, 2), 16) :: number,
			tonumber(string.sub(v, 3, 4), 16) :: number,
			tonumber(string.sub(v, 5, 6), 16) :: number,
		}
	end
	return v
end

local function lerp(a: any, b: any, f: number): any
	if type(a) == "number" then
		return a + (b - a) * f
	end
	local ca, cb = rgb(a), rgb(b)
	return { ca[1] + (cb[1] - ca[1]) * f, ca[2] + (cb[2] - ca[2]) * f, ca[3] + (cb[3] - ca[3]) * f }
end

-- The interpolated look at a game hour (colours as { r, g, b } in 0..255).
function SkyKeys.stateAt(hour: number): State
	local h = hour % 24
	local keys = SkyKeys.KEYS
	local a, b = keys[#keys], keys[1]
	local ha, hb = a.hour - 24, b.hour
	for i = 1, #keys do
		local k = keys[i]
		local nxt = keys[i + 1]
		if nxt == nil then
			a, b, ha, hb = k, keys[1], k.hour, keys[1].hour + 24
			break
		end
		if h >= k.hour and h < nxt.hour then
			a, b, ha, hb = k, nxt, k.hour, nxt.hour
			break
		end
	end
	local f = if hb > ha then (h - ha) / (hb - ha) else 0
	f = f * f * (3 - 2 * f) -- ease between keys
	local out = {}
	for key, va in a.state do
		out[key] = lerp(va, (b.state :: any)[key], f)
	end
	return (out :: any) :: State
end

-- Fraction of the disc lit at a phase (0 new, 0.5 full).
function SkyKeys.illumination(phase01: number): number
	return (1 - math.cos(2 * math.pi * phase01)) / 2
end

-- The moon disc as n horizontal rows in [0, 1] scale units, the lit limb toward +x (the client rotates the disc
-- so +x points at the sun on screen). Each row spans [darkFrom, litTo]; the lit part is [litFrom, litTo]: on a
-- row at height y (-1..1) with half-width s, the terminator is at x = s cos(phase angle).
function SkyKeys.moonRows(
	phase01: number,
	n: number
): { { top: number, height: number, darkFrom: number, litFrom: number, litTo: number } }
	local c = math.cos(2 * math.pi * phase01)
	local rows = {}
	for j = 1, n do
		local y = -1 + (2 * j - 1) / n
		local s = math.sqrt(math.max(0, 1 - y * y))
		table.insert(rows, {
			top = (j - 1) / n,
			height = 1 / n,
			darkFrom = (1 - s) / 2,
			litFrom = (1 + s * c) / 2,
			litTo = (1 + s) / 2,
		})
	end
	return rows
end

-- Cloud cover from the game day count: slow weather, the same on every client.
function SkyKeys.weather(days: number): number
	local w = 0.45 + 0.15 * math.sin(2 * math.pi * days / 5.3) + 0.08 * math.sin(2 * math.pi * days / 2.1 + 1)
	return math.clamp(w, 0.2, 0.72)
end

return SkyKeys
