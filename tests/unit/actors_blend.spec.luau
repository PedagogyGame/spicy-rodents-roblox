--!strict
-- Shared/Avatar/BlendRules (BUILD_PLAN §6.2 BlendRules row): saturation <= 0.55 and value
-- 0.39-0.91 on every animal colour, at most one neon accent, rodent eyes unchanged, bizarre
-- detection on a sample set, humans take face/hair/skin tone only (brief v2 §13a), hitbox untouched.
local BlendRules = require("@shared/Avatar/BlendRules")
local Species = require("@shared/Actors/Species")

type Desc = BlendRules.DescriptionLike

local function rgb(r: number, g: number, b: number): BlendRules.Rgb
	return { r = r, g = g, b = b }
end

local function classic(overrides: { [string]: any }?): Desc
	local skin = rgb(0.8, 0.557, 0.412)
	local d: Desc = {
		HeadColor = skin,
		TorsoColor = skin,
		LeftArmColor = skin,
		RightArmColor = skin,
		LeftLegColor = skin,
		RightLegColor = skin,
		Face = 144075659,
		Head = 0,
		Shirt = 1001,
		Pants = 1002,
		GraphicTShirt = 0,
		HeightScale = 1,
		WidthScale = 1,
		HeadScale = 1,
		DepthScale = 1,
		BodyTypeScale = 0,
		ProportionScale = 0,
		accessories = {
			{ assetId = 2001, accessoryType = "Hair", isLayered = false },
			{ assetId = 2002, accessoryType = "Hat", isLayered = false },
		},
	}
	for k, v in overrides or {} do
		(d :: any)[k] = v
	end
	return d
end

local INFO: BlendRules.ProductInfo = {
	[1001] = { name = "Red Plaid Shirt" },
	[1002] = { name = "Blue Denim Jeans" },
	[2001] = { name = "Brown Hair" },
	[2002] = { name = "Black Fedora" },
	[3001] = { name = "Neon Green Jacket" },
	[3002] = { name = "Giant Rainbow Sombrero" },
	[4001] = { name = "Mystery Hat" },
}

-- The Lab's sample set (D13): classic, neon, giant, non-human bundle, dynamic head, layered clothing.
local SAMPLES: { { name: string, desc: Desc, bizarre: boolean } } = {
	{ name = "classic", desc = classic(), bizarre = false },
	{
		name = "neon",
		desc = classic({
			TorsoColor = rgb(0.1, 1.0, 0.2),
			accessories = { { assetId = 3001, accessoryType = "Jacket", isLayered = true } },
		}),
		bizarre = true,
	},
	{
		name = "giant",
		desc = classic({
			HeightScale = 1.05,
			WidthScale = 1.0,
			BodyTypeScale = 1.0,
			accessories = { { assetId = 3002, accessoryType = "Hat", isLayered = false } },
		}),
		bizarre = true,
	},
	{
		name = "nonhuman_bundle",
		desc = classic({
			HeadColor = rgb(0.2, 0.9, 0.3),
			TorsoColor = rgb(0.2, 0.9, 0.3),
			bundleWords = { "Dino Rex Torso", "Dino Rex Head" },
		}),
		bizarre = true,
	},
	{ name = "dynamic_head", desc = classic({ Head = 55555, HeadIsDynamic = true }), bizarre = false },
	{
		name = "layered",
		desc = classic({
			Shirt = 0,
			accessories = {
				{ assetId = 3001, accessoryType = "Jacket", isLayered = true },
				{ assetId = 2001, accessoryType = "Hair", isLayered = false },
			},
		}),
		bizarre = true, -- the neon jacket
	},
	{
		name = "blank_default",
		desc = classic({
			HeadColor = rgb(0.64, 0.64, 0.65),
			TorsoColor = rgb(0.64, 0.64, 0.65),
			Shirt = 0,
			Pants = 0,
			accessories = {},
		}),
		bizarre = false,
	},
	{
		name = "classic_yellow_head",
		desc = classic({ HeadColor = rgb(0.96, 0.8, 0.19), TorsoColor = rgb(0.07, 0.07, 0.07) }),
		bizarre = true,
	},
	{
		name = "many_accessories",
		desc = classic({
			accessories = {
				{ assetId = 2001, accessoryType = "Hair", isLayered = false },
				{ assetId = 2002, accessoryType = "Hat", isLayered = false },
				{ assetId = 4001, accessoryType = "Face", isLayered = false },
				{ assetId = 4001, accessoryType = "Back", isLayered = false },
				{ assetId = 4001, accessoryType = "Front", isLayered = false },
				{ assetId = 4001, accessoryType = "Waist", isLayered = false },
			},
		}),
		bizarre = true,
	},
}

return function(t)
	t.test("rgb <-> hsv round trips", function()
		for _, c in { rgb(0.2, 0.4, 0.9), rgb(1, 0, 0), rgb(0.5, 0.5, 0.5), rgb(0, 0, 0), rgb(0.9, 0.8, 0.1) } do
			local back = BlendRules.hsvToRgb(BlendRules.rgbToHsv(c))
			t.near(back.r, c.r, 1e-9)
			t.near(back.g, c.g, 1e-9)
			t.near(back.b, c.b, 1e-9)
		end
	end)

	t.test("70/30 mix is 0.7 stock + 0.3 avatar", function()
		local m = BlendRules.mix(rgb(1, 0, 0), rgb(0, 0, 1), BlendRules.AVATAR_WEIGHT)
		t.near(m.r, 0.7)
		t.near(m.b, 0.3)
		t.near(m.g, 0)
	end)

	t.test("clampPalette holds S <= 0.55 and V in 0.39..0.91 for 500 random colours", function()
		local seed = 17
		local function rnd(): number
			seed = (seed * 1103515245 + 12345) % 2147483648
			return seed / 2147483648
		end
		for _ = 1, 500 do
			local c = BlendRules.clampPalette(rgb(rnd(), rnd(), rnd()))
			local hsv = BlendRules.rgbToHsv(c)
			t.truthy(hsv.s <= BlendRules.MAX_SATURATION + 1e-9, `s {hsv.s}`)
			t.truthy(hsv.v >= BlendRules.MIN_VALUE - 1e-9 and hsv.v <= BlendRules.MAX_VALUE + 1e-9, `v {hsv.v}`)
		end
	end)

	t.test("colour words: longest match first, case-insensitive, none for unknown names", function()
		local c, word = BlendRules.colourWord("NEON GREEN Jacket")
		t.eq(word, "neon green")
		t.truthy(c and BlendRules.isNeon(c :: BlendRules.Rgb))
		local _, w2 = BlendRules.colourWord("Sky Blue Scarf")
		t.eq(w2, "sky blue")
		local c3 = BlendRules.colourWord("Mystery Hat")
		t.eq(c3, nil)
	end)

	t.test("traits: classic avatar takes red shirt as dominant, name hit rate recorded", function()
		local tr = BlendRules.traits(classic(), INFO)
		t.eq(tr.sources.shirt, "name")
		t.eq(tr.sources.pants, "name")
		t.eq(tr.hairAccessory, 2001)
		t.eq(tr.headAccessory, 2002)
		t.eq(tr.nameTried, 4)
		t.eq(tr.nameHits, 4)
		t.truthy(tr.skinIsHuman)
		t.eq(tr.skinToneIndex, 3) -- nougat
		t.falsy(tr.bizarre)
		local hsv = BlendRules.rgbToHsv(tr.dominant)
		t.truthy(hsv.h < 0.05 or hsv.h > 0.95, "dominant is red")
	end)

	t.test("traits: the curated table answers when the name has no colour word", function()
		local tr = BlendRules.traits(classic({ Shirt = 4001 }), INFO, { [4001] = rgb(0.1, 0.2, 0.3) })
		t.eq(tr.sources.shirt, "table")
		t.near((tr.shirt :: BlendRules.Rgb).b, 0.3)
	end)

	t.test("bizarre detection on the sample set", function()
		for _, sample in SAMPLES do
			local tr = BlendRules.traits(sample.desc, INFO)
			t.eq(tr.bizarre, sample.bizarre, `{sample.name}: {table.concat(tr.bizarreReasons, ",")}`)
		end
		local neon = BlendRules.traits(SAMPLES[2].desc, INFO)
		t.eq(neon.signature, "neon_tips")
		local giant = BlendRules.traits(SAMPLES[3].desc, INFO)
		t.eq(giant.signature, "oversized_accessory")
		t.eq(giant.signatureAccessory, 3002)
		local dino = BlendRules.traits(SAMPLES[4].desc, INFO)
		t.eq(dino.signature, "nonhuman_bundle")
		t.falsy(dino.skinIsHuman)
	end)

	t.test("animal looks stay inside the palette with at most one (softened) accent", function()
		for _, species in { "squirrel", "fox", "deer" } do
			local stock = Species.stockLook(species, 1)
			for _, sample in SAMPLES do
				local tr = BlendRules.traits(sample.desc, INFO)
				local look = BlendRules.compose(species, stock, tr) :: BlendRules.AnimalLook
				t.eq(look.kind, "animal")
				t.truthy(BlendRules.inPalette(look.bodyTint), `{species}/{sample.name} body`)
				t.truthy(BlendRules.inPalette(look.patternColour), `{species}/{sample.name} pattern`)
				t.truthy(BlendRules.inPalette(look.eyeColour), `{species}/{sample.name} eyes`)
				t.truthy(BlendRules.neonAccents(look) <= 1, `{species}/{sample.name} neon accents`)
				if look.accent then
					local hsv = BlendRules.rgbToHsv(look.accent :: BlendRules.Rgb)
					t.truthy(
						hsv.s <= BlendRules.ACCENT_MAX_SATURATION + 1e-9 and hsv.v <= BlendRules.ACCENT_MAX_VALUE + 1e-9
					)
				else
					t.truthy(BlendRules.inPalette(look.tailTip), `{species}/{sample.name} tail`)
				end
			end
		end
	end)

	t.test("the fur tint is capped: never more than 30 % of the way to the avatar colour", function()
		local stock = Species.stockLook("squirrel", 1)
		local tr = BlendRules.traits(classic({ TorsoColor = rgb(0.1, 0.1, 0.9), Shirt = 0, Pants = 0 }), INFO)
		local look = BlendRules.compose("squirrel", stock, tr) :: BlendRules.AnimalLook
		-- before the palette clamp the mix is exactly 0.7 stock + 0.3 avatar; the clamp only pulls
		-- back toward the palette, so the distance to the stock colour never exceeds the raw mix's
		local raw = BlendRules.mix(stock.body, tr.dominant, BlendRules.AVATAR_WEIGHT)
		t.truthy(
			BlendRules.distance(look.bodyTint, stock.body) <= BlendRules.distance(raw, stock.body) + 1e-9,
			"clamped tint is no further from stock than the 30 % mix"
		)
		t.truthy(BlendRules.distance(look.bodyTint, stock.body) > 0.02, "but the tint does move")
	end)

	t.test("rodent eyes never change (eyesLocked)", function()
		local rodent = Species.rodentLook()
		t.truthy(rodent.eyesLocked)
		for _, sample in SAMPLES do
			local tr = BlendRules.traits(sample.desc, INFO)
			local look = BlendRules.compose("rodent", rodent, tr) :: BlendRules.AnimalLook
			t.near(look.eyeColour.r, rodent.eyes.r, 1e-12, sample.name)
			t.near(look.eyeColour.g, rodent.eyes.g, 1e-12, sample.name)
			t.near(look.eyeColour.b, rodent.eyes.b, 1e-12, sample.name)
		end
	end)

	t.test("humans take skin tone, face and hair only; no tint, no accents (brief v2 §13a)", function()
		local tr = BlendRules.traits(classic(), INFO)
		local look = BlendRules.compose("human", Species.stockLook("human", 1), tr) :: BlendRules.HumanLook
		t.eq(look.kind, "human")
		t.eq(look.face, 144075659)
		t.eq(look.hair, 2001)
		t.eq(look.headAccessory, nil, "a hat is skipped when hair is present")
		t.eq(look.skinToneIndex, 3)
		for k in look :: any do
			t.truthy(
				k == "kind"
					or k == "skinTone"
					or k == "skinToneIndex"
					or k == "face"
					or k == "hair"
					or k == "headAccessory"
					or k == "dynamicHeadExpression",
				`unexpected human look field {k}`
			)
		end
		local dyn =
			BlendRules.compose("human", Species.stockLook("human", 1), BlendRules.traits(SAMPLES[5].desc, INFO)) :: BlendRules.HumanLook
		t.eq(dyn.face, 0, "a dynamic head keeps the stock face decal")
		t.eq(dyn.dynamicHeadExpression, "neutral")
	end)

	t.test("layered hair reaches the human look but never an animal's HeadSocket", function()
		local tr = BlendRules.traits(
			classic({
				accessories = {
					{ assetId = 5001, accessoryType = "Hair", isLayered = true },
					{ assetId = 2002, accessoryType = "Hat", isLayered = false },
				},
			}),
			INFO
		)
		t.eq(tr.hairAccessory, 5001)
		t.truthy(tr.hairIsLayered)
		t.eq(tr.signatureAccessory, 2002, "the rigid hat goes to the socket")
		local human = BlendRules.compose("human", Species.stockLook("human", 1), tr) :: BlendRules.HumanLook
		t.eq(human.hair, 5001)
		local sq = BlendRules.compose("squirrel", Species.stockLook("squirrel", 1), tr) :: BlendRules.AnimalLook
		t.eq(sq.accessory, 2002)
	end)

	t.test("hitbox untouched: no look carries size, scale or hip fields", function()
		for _, species in { "human", "squirrel", "fox", "deer" } do
			local look =
				BlendRules.compose(species, Species.stockLook(species, 1), BlendRules.traits(SAMPLES[3].desc, INFO))
			for k in look :: any do
				t.falsy(
					string.find(string.lower(k), "scale")
						or string.find(string.lower(k), "hitbox")
						or string.find(string.lower(k), "hip"),
					k
				)
			end
		end
	end)
end
