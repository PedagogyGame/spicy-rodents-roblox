--!strict
-- tests/unit/lighting_project.spec.luau
-- The look of the place is stated twice on purpose: in the three Rojo project files, so that the place
-- file itself opens already lit (Studio, and the first frames before any script has run), and in
-- Shared/World/LightingPreset.GOLDEN, which the server applies at boot and the client's sky then moves
-- through the day. Owner, 2026-11-13: "Set Lighting Technology to Future in the Rojo project file ...
-- Turn on global shadows and add Atmosphere, environment lighting and post-processing settings."
-- This holds the two to the same numbers, and the effects to the names the game looks them up by
-- (Atmosphere, Grade, Bloom, SunRays), so the game adopts the project's instances and makes no doubles.
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local LightingPreset = require("@shared/World/LightingPreset")

local PROJECTS = { "default.project.json", "ci.project.json", "build.project.json" }
local G = LightingPreset.GOLDEN

local function channels(hexColour: string): { number }
	local out = {}
	for i = 1, 5, 2 do
		table.insert(out, (tonumber(string.sub(hexColour, i, i + 1), 16) :: number) / 255)
	end
	return out
end

return function(t: any)
	local function near(got: any, want: number, what: string)
		t.truthy(type(got) == "number" and math.abs(got - want) < 1e-3, `{what}: {tostring(got)}, want {want}`)
	end
	local function colour(got: any, hexColour: string, what: string)
		t.truthy(type(got) == "table" and #got == 3, `{what}: a colour of three numbers`)
		for i, want in channels(hexColour) do
			near(got[i], want, `{what}[{i}]`)
		end
	end

	t.test("every project lights the place the realistic way, with global shadows", function()
		for _, project in PROJECTS do
			local p = serde.decode("json", fs.readFile(project)).tree.Lighting["$properties"]
			t.eq(p.Technology, "Future", `{project}: Technology`)
			t.eq(p.LightingStyle, "Realistic", `{project}: LightingStyle`)
			t.eq(p.GlobalShadows, true, `{project}: GlobalShadows`)
			near(p.ShadowSoftness, G.shadowSoftness, `{project}: ShadowSoftness`)
		end
	end)

	t.test("every project's sun, ambient and environment light are the golden preset's", function()
		for _, project in PROJECTS do
			local p = serde.decode("json", fs.readFile(project)).tree.Lighting["$properties"]
			near(p.GeographicLatitude, G.latitude, `{project}: GeographicLatitude`)
			near(p.ClockTime, G.clockTime, `{project}: ClockTime`)
			near(p.Brightness, G.brightness, `{project}: Brightness`)
			near(p.ExposureCompensation, G.exposure, `{project}: ExposureCompensation`)
			near(p.EnvironmentDiffuseScale, G.diffuse, `{project}: EnvironmentDiffuseScale`)
			near(p.EnvironmentSpecularScale, G.specular, `{project}: EnvironmentSpecularScale`)
			colour(p.ColorShift_Top, G.colorShiftTop, `{project}: ColorShift_Top`)
			colour(p.ColorShift_Bottom, G.colorShiftBottom, `{project}: ColorShift_Bottom`)
			colour(p.OutdoorAmbient, G.outdoorAmbient, `{project}: OutdoorAmbient`)
			colour(p.Ambient, G.ambient, `{project}: Ambient`)
		end
	end)

	t.test("every project carries the atmosphere and the post-processing, under the game's own names", function()
		for _, project in PROJECTS do
			local lighting = serde.decode("json", fs.readFile(project)).tree.Lighting

			local atmosphere = lighting.Atmosphere
			t.truthy(atmosphere ~= nil and atmosphere["$className"] == "Atmosphere", `{project}: Atmosphere`)
			local a = atmosphere["$properties"]
			near(a.Density, G.atmosphere.density, `{project}: Atmosphere.Density`)
			near(a.Offset, G.atmosphere.offset, `{project}: Atmosphere.Offset`)
			near(a.Glare, G.atmosphere.glare, `{project}: Atmosphere.Glare`)
			near(a.Haze, G.atmosphere.haze, `{project}: Atmosphere.Haze`)
			colour(a.Color, G.atmosphere.color, `{project}: Atmosphere.Color`)
			colour(a.Decay, G.atmosphere.decay, `{project}: Atmosphere.Decay`)

			local grade = lighting.Grade
			t.truthy(grade ~= nil and grade["$className"] == "ColorCorrectionEffect", `{project}: Grade`)
			near(grade["$properties"].Contrast, G.correction.contrast, `{project}: Grade.Contrast`)
			near(grade["$properties"].Saturation, G.correction.saturation, `{project}: Grade.Saturation`)
			near(grade["$properties"].Brightness, G.correction.brightness, `{project}: Grade.Brightness`)
			colour(grade["$properties"].TintColor, G.correction.tint, `{project}: Grade.TintColor`)

			local bloom = lighting.Bloom
			t.truthy(bloom ~= nil and bloom["$className"] == "BloomEffect", `{project}: Bloom`)
			near(bloom["$properties"].Intensity, G.bloom.intensity, `{project}: Bloom.Intensity`)
			near(bloom["$properties"].Size, G.bloom.size, `{project}: Bloom.Size`)
			near(bloom["$properties"].Threshold, G.bloom.threshold, `{project}: Bloom.Threshold`)

			local rays = lighting.SunRays
			t.truthy(rays ~= nil and rays["$className"] == "SunRaysEffect", `{project}: SunRays`)
			near(rays["$properties"].Intensity, G.sunRays.intensity, `{project}: SunRays.Intensity`)
			near(rays["$properties"].Spread, G.sunRays.spread, `{project}: SunRays.Spread`)
		end
	end)
end
