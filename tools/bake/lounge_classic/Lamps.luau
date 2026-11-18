--!strict
-- tools/bake/lounge_classic/Lamps: THE GILDED ACORN's light, warm and low (the brief: polish goes where people
-- pay). Inside: three brass pendants over the bar, a shaded lamp on each booth's table, six sconces on the side
-- walls' pilasters, two Art Deco chandeliers over the rug, two soft fills under the ceiling, two spots on the
-- stage, the fire, and a concealed strip lighting the back bar's mirror. Outside: a light under the canopy (the
-- two lanterns either side of the entry glow without one). 22 lights (Lounge.LIGHT_BUDGET); three cast shadows
-- (the middle pendant, the back chandelier and the piano's spot): the engine pays for every shadowed light in view.
-- Interface: build(kit, root, venue) -> (lights, shadowed). No side effects on require.

local Kit = require("../alley/Kit")
local Style = require("./Style")

local Lamps = {}

local GHOST = { collide = false, query = false, shadow = false }
local HIDDEN = { collide = false, query = false, transparency = 1, shadow = false }

function Lamps.build(kit: Kit.Kit, root: any, _venue: any): (number, number)
	local m = kit:model(root, "Lamps")
	local lights, shadowed = 0, 0
	local function light(part: any, class: string, props: { [string]: any })
		props.Color = props.Color or Style.LAMP
		kit:light(part, class, props)
		lights += 1
		if props.Shadows then
			shadowed += 1
		end
	end
	local C = Style.CEILING

	-- pendants over the bar: a rod, a brass shade, a glowing bulb
	for _, x in Style.PENDANTS do
		local d = (Style.BAR_D0 + Style.BAR_D1) / 2
		kit:cyl(m, `PendantRod{x}`, x, (C + 9.2) / 2, d, C - 9.2, 0.1, "Y", Style.BRASS, "Metal", GHOST)
		kit:cyl(m, `PendantShade{x}`, x, 8.9, d, 0.7, 1.3, "Y", Style.BRASS, "Metal", GHOST)
		local bulb = kit:ball(m, `PendantBulb{x}`, x, 8.4, d, 0.5, Style.LAMP, "Neon", GHOST)
		light(bulb, "PointLight", { Brightness = 1.2, Range = 16, Shadows = x == 0 })
	end

	-- a lamp on each booth's table, by the wall
	for i, b in Style.BOOTHS do
		local s, c = if b[1] < 0 then -1 else 1, b[2]
		local x = s * (Style.BOOTH_X1 - 1.3)
		kit:cyl(m, `BoothLampBase{i}`, x, 2.95, c, 0.2, 0.6, "Y", Style.BRASS, "Metal", GHOST)
		kit:cyl(m, `BoothLampStem{i}`, x, 3.45, c, 0.9, 0.1, "Y", Style.BRASS, "Metal", GHOST)
		local shade = kit:cyl(m, `BoothLampShade{i}`, x, 4.1, c, 0.7, 1.0, "Y", Style.IVORY, "Fabric", GHOST)
		light(shade, "PointLight", { Brightness = 0.9, Range = 12, Shadows = false })
	end

	-- sconces on the side walls' pilasters: a brass plate and a frosted shade
	for _, s in { -1, 1 } do
		for _, d in Style.SCONCES do
			local x = s * (Style.INNER_X - 0.45)
			kit:box(m, `SconcePlate{s}{d}`, x, x - s * 0.1, 6.6, 8.2, d - 0.3, d + 0.3, Style.BRASS, "Metal", GHOST)
			local shade = kit:box(
				m,
				`SconceShade{s}{d}`,
				x - s * 0.1,
				x - s * 0.6,
				7.2,
				8.0,
				d - 0.4,
				d + 0.4,
				Style.LAMP,
				"Neon",
				GHOST
			)
			light(shade, "PointLight", { Brightness = 0.8, Range = 14, Shadows = false })
		end
	end

	-- Art Deco chandeliers over the rug: a rod, two brass tiers, a frosted bowl
	for i, ch in Style.CHANDELIERS do
		local x, d = ch[1], ch[2]
		kit:cyl(m, `ChandelierRod{i}`, x, (C + 10.6) / 2, d, C - 10.6, 0.12, "Y", Style.BRASS, "Metal", GHOST)
		kit:cyl(m, `ChandelierTier{i}A`, x, 10.45, d, 0.3, 2.6, "Y", Style.GOLD, "Metal", GHOST)
		kit:cyl(m, `ChandelierTier{i}B`, x, 10.0, d, 0.3, 1.8, "Y", Style.GOLD, "Metal", GHOST)
		local bowl = kit:ball(m, `ChandelierBowl{i}`, x, 9.55, d, 1.3, Style.LAMP, "Neon", GHOST)
		light(bowl, "PointLight", { Brightness = 1.0, Range = 24, Shadows = i == 2 })
	end

	-- the stage's two spots: black cans under the ceiling, shining down on the piano and the microphone
	for i, at in { { Style.PIANO[1], Style.PIANO[2] - 1 }, { -15.6, 16 } } do
		local can = kit:cyl(m, `StageSpot{i}`, at[1], C - 0.9, at[2], 0.9, 0.7, "Y", Style.BLACK, "Metal", GHOST)
		light(can, "SpotLight", { Brightness = 1.6, Range = 16, Angle = 50, Face = "Bottom", Shadows = i == 1 })
	end

	-- two soft fills under the ceiling: the lamps light down and the engine's lighting has no bounce, so without
	-- them the ceiling, the beams and the upper walls stay black (as in the Neighbourhood Shop)
	for i, d in { -10, 12 } do
		local f = kit:at(m, `Fill{i}`, 0, Style.CROWN - 0.6, d, 0.3, 0.3, 0.3, Style.LAMP, "SmoothPlastic", HIDDEN)
		light(f, "PointLight", { Brightness = 0.55, Range = 30, Shadows = false })
	end

	-- the fire's glow
	local IX = Style.INNER_X - 0.25
	local fire = kit:box(
		m,
		"FireGlow",
		IX - 1.5,
		IX - 1.2,
		0.6,
		1.6,
		Style.FIRE_D - 0.9,
		Style.FIRE_D + 0.9,
		Style.FIRE,
		"Neon",
		GHOST
	)
	light(fire, "PointLight", { Color = Style.FIRE, Brightness = 1.2, Range = 14, Shadows = false })

	-- a concealed strip under the upper shelf, lighting the mirror and the cups
	local IB = Style.INNER_BACK - 0.25
	local strip = kit:box(m, "BackBarStrip", -8.8, 8.8, 7.9, 8.0, IB - 1.0, IB - 0.9, Style.LAMP, "Neon", GHOST)
	light(strip, "SurfaceLight", { Brightness = 1.0, Range = 6, Angle = 80, Face = "Bottom", Shadows = false })

	-- outside: under the canopy, and two brass lanterns on the black front either side of the entry
	local F = Style.FRONT_D
	local canopy =
		kit:at(m, "CanopyLight", 0, Style.ALCOVE_TOP - 0.3, F - 1.5, 0.3, 0.3, 0.3, Style.LAMP, "SmoothPlastic", HIDDEN)
	light(canopy, "PointLight", { Brightness = 1.2, Range = 14, Shadows = false })
	for _, s in { -1, 1 } do
		local x = s * (Style.ALCOVE_X + 2.6)
		kit:box(m, `LanternBack{s}`, x - 0.3, x + 0.3, 6.2, 8.4, F - 0.5, F - 0.3, Style.GOLD, "Metal", GHOST)
		-- (they glow; the canopy's light is the entry's: the lounge's budget goes inside)
		kit:box(m, `Lantern{s}`, x - 0.4, x + 0.4, 6.6, 8.0, F - 1.3, F - 0.5, Style.LAMP, "Neon", GHOST)
	end

	return lights, shadowed
end

return Lamps
