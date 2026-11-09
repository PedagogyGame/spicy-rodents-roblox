--!strict
-- ReplicatedStorage.Shared.World.LightingPreset
-- The first playable build's fixed daylight: the v5.4 "golden" preset mapped to Roblox lighting
-- (docs/spec/worldgen_districts_art.md §10 preset table and the porting table: ColorShift_Top #ffe0ab,
-- OutdoorAmbient #a2a180, exposure 1.12 -> +0.16 EV, Atmosphere colour #c8d1bd / decay #b9a17e,
-- EnvironmentDiffuse 0.6 / Specular 0.3, ColorCorrection contrast 0.05 / saturation -0.05), held at a
-- golden-afternoon ClockTime (§10 phase table: golden afternoon 15:30-18:00; 16:00 so the light is warm
-- and the shadows long but the town is still bright), soft shadows, a light bloom and the stock skybox. The day clock (Time/Clock, Sky.step) replaces the fixed
-- ClockTime in W2. Data is plain numbers and hex strings so Lune can test it; apply() is engine only.
-- Interface: GOLDEN (table), apply(lighting: Lighting) -> ()

local LightingPreset = {}

LightingPreset.GOLDEN = table.freeze({
	clockTime = 16,
	latitude = 39,
	brightness = 2.6,
	colorShiftTop = "ffe0ab",
	colorShiftBottom = "56664a",
	outdoorAmbient = "a2a180",
	ambient = "6b6a5a",
	exposure = 0.16,
	shadowSoftness = 0.25, -- soft-edged sun shadows (v5.4 PCF soft shadow map)
	diffuse = 0.6,
	specular = 0.3,
	atmosphere = table.freeze({
		density = 0.28,
		offset = 0.25,
		color = "c8d1bd",
		decay = "b9a17e",
		glare = 0.2,
		haze = 1.5,
	}),
	correction = table.freeze({ contrast = 0.05, saturation = -0.05, brightness = 0, tint = "ffffff" }),
	sunRays = table.freeze({ intensity = 0.06, spread = 0.6 }),
	bloom = table.freeze({ intensity = 0.3, size = 28, threshold = 1.5 }), -- v5.4 bloom on high tiers
	sky = table.freeze({ sunAngularSize = 14, moonAngularSize = 9, starCount = 0 }),
})

local function hex(s: string): Color3
	return Color3.fromHex(s)
end

local function child(parent: Instance, class: string, name: string): any
	local found = parent:FindFirstChild(name)
	if found and found.ClassName == class then
		return found
	end
	local i = Instance.new(class)
	i.Name = name
	i.Parent = parent
	return i
end

-- Applies GOLDEN to Lighting (server side; Lighting replicates). Idempotent.
function LightingPreset.apply(lighting: Lighting)
	local p = LightingPreset.GOLDEN
	lighting.ClockTime = p.clockTime
	lighting.GeographicLatitude = p.latitude
	lighting.Brightness = p.brightness
	lighting.ColorShift_Top = hex(p.colorShiftTop)
	lighting.ColorShift_Bottom = hex(p.colorShiftBottom)
	lighting.OutdoorAmbient = hex(p.outdoorAmbient)
	lighting.Ambient = hex(p.ambient)
	lighting.ExposureCompensation = p.exposure
	lighting.EnvironmentDiffuseScale = p.diffuse
	lighting.EnvironmentSpecularScale = p.specular
	lighting.GlobalShadows = true
	lighting.ShadowSoftness = p.shadowSoftness
	local atm = child(lighting, "Atmosphere", "Atmosphere") :: Atmosphere
	atm.Density = p.atmosphere.density
	atm.Offset = p.atmosphere.offset
	atm.Color = hex(p.atmosphere.color)
	atm.Decay = hex(p.atmosphere.decay)
	atm.Glare = p.atmosphere.glare
	atm.Haze = p.atmosphere.haze
	local cc = child(lighting, "ColorCorrectionEffect", "Grade") :: ColorCorrectionEffect
	cc.Contrast = p.correction.contrast
	cc.Saturation = p.correction.saturation
	cc.Brightness = p.correction.brightness
	cc.TintColor = hex(p.correction.tint)
	local rays = child(lighting, "SunRaysEffect", "SunRays") :: SunRaysEffect
	rays.Intensity = p.sunRays.intensity
	rays.Spread = p.sunRays.spread
	local bloom = child(lighting, "BloomEffect", "Bloom") :: BloomEffect
	bloom.Intensity = p.bloom.intensity
	bloom.Size = p.bloom.size
	bloom.Threshold = p.bloom.threshold
	-- the stock Roblox skybox (a new Sky carries the default cloud textures): never a void
	local sky = child(lighting, "Sky", "Sky") :: Sky
	sky.SunAngularSize = p.sky.sunAngularSize
	sky.MoonAngularSize = p.sky.moonAngularSize
	sky.StarCount = p.sky.starCount
	sky.CelestialBodiesShown = true
end

return LightingPreset
