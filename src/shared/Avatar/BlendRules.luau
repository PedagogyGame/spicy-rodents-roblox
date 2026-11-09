--!strict
-- ReplicatedStorage.Shared.Avatar.BlendRules
-- 70/30 avatar composition (Addendum A3, B1; brief v2 §13a; BUILD_PLAN D13): pure colour maths with
-- the town-palette clamp (saturation <= 0.55, value 0.39-0.91), the bizarre-avatar signature pick,
-- colour sources in priority order (body colours, item-name colour words, a curated table).
-- Interface (BUILD_PLAN §1.4): traits(desc, productInfo, table?) -> Traits,
-- compose(species, stock, traits) -> Look, isBizarre(traits), plus the colour helpers.
-- Rules this module encodes:
--   * Humans (brief v2 §13a) take face, hair and skin tone through appearance properties; no tint,
--     no accent colours; the body keeps its build and clothes. Skin tone snaps to the nearest of 8.
--   * Animals (A3, B1) keep the species mesh and markings; fur takes a CAPPED 30 % tint of the
--     avatar's dominant colour, pattern zones take the shirt/pants colours, eyes take a derived eye
--     colour (the rodent's bloodshot eyes never change), plus one rigid accessory on HeadSocket.
--   * Bizarre avatars keep ONE signature feature; everything is clamped to the palette; at most one
--     neon accent survives, and nothing here ever touches silhouette, hitbox or hip height.
-- No engine types: colours are {r, g, b} in 0-1 so Lune tests run; the service converts to Color3.

export type Rgb = { r: number, g: number, b: number }
export type Hsv = { h: number, s: number, v: number }

export type AccessoryLike = {
	assetId: number,
	accessoryType: string, -- Enum.AccessoryType.Name: Hat, Hair, Face, Neck, Shoulder, Front, Back, Waist, or layered
	isLayered: boolean,
	order: number?,
}

-- The subset of HumanoidDescription the blend reads, as plain data (AvatarBlendService converts).
export type DescriptionLike = {
	HeadColor: Rgb,
	TorsoColor: Rgb,
	LeftArmColor: Rgb,
	RightArmColor: Rgb,
	LeftLegColor: Rgb,
	RightLegColor: Rgb,
	Face: number,
	Head: number, -- 0 = classic head; a non-zero head asset may be a dynamic head
	HeadIsDynamic: boolean?,
	Shirt: number,
	Pants: number,
	GraphicTShirt: number,
	HeightScale: number,
	WidthScale: number,
	HeadScale: number,
	DepthScale: number,
	BodyTypeScale: number,
	ProportionScale: number,
	accessories: { AccessoryLike },
	bundleWords: { string }?, -- names of body-part assets (for the non-human bundle heuristic)
}

export type ProductInfo = { [number]: { name: string, description: string? } }
export type ColourTable = { [number]: Rgb } -- data/blend/item_colours.json: assetId -> colour

export type Traits = {
	skinTone: Rgb,
	skinToneIndex: number,
	skinIsHuman: boolean,
	face: number,
	headIsDynamic: boolean,
	hairAccessory: number?,
	hairIsLayered: boolean, -- a WrapLayer hair: fine on an R15 human, never on an animal's HeadSocket
	headAccessory: number?,
	signatureAccessory: number?, -- always rigid (the animal HeadSocket path)
	dominant: Rgb,
	shirt: Rgb?,
	pants: Rgb?,
	eye: Rgb,
	neon: { Rgb },
	sources: { [string]: string }, -- which source gave each colour: body | name | table | none
	nameHits: number, -- item names that yielded a colour word
	nameTried: number,
	bizarre: boolean,
	bizarreReasons: { string },
	signature: string, -- none | neon_tips | oversized_accessory | patterned_fur | nonhuman_bundle
}

export type StockLook = { body: Rgb, pattern: Rgb, eyes: Rgb, eyesLocked: boolean }

export type HumanLook = {
	kind: "human",
	skinTone: Rgb,
	skinToneIndex: number,
	face: number, -- 0 keeps the stock face
	dynamicHeadExpression: string?, -- a dynamic head maps to a stock expression (D13)
	hair: number?,
	headAccessory: number?,
}

export type AnimalLook = {
	kind: "animal",
	bodyTint: Rgb,
	patternColour: Rgb,
	tailTip: Rgb,
	eyeColour: Rgb,
	accessory: number?,
	signature: string,
	accent: Rgb?, -- the one neon accent, already softened
}

export type Look = HumanLook | AnimalLook

local BlendRules = {}

-- Palette clamps (BUILD_PLAN §6.2 BlendRules row; worldgen_districts_art §15 town palette).
BlendRules.MAX_SATURATION = 0.55
BlendRules.MIN_VALUE = 0.39
BlendRules.MAX_VALUE = 0.91
BlendRules.AVATAR_WEIGHT = 0.3 -- the capped 30 % (A3 "70% stock character 30% Roblox avatar")
BlendRules.NEON_SATURATION = 0.85
BlendRules.NEON_VALUE = 0.9
-- The single surviving neon accent is softened, not flattened, so "neon-tipped ears and tail" reads.
BlendRules.ACCENT_MAX_SATURATION = 0.8
BlendRules.ACCENT_MAX_VALUE = 0.95

-- 8 skin tones (D13 "nearest of 8"), from Roblox's own skin-tone presets, darkest last.
BlendRules.SKIN_TONES = {
	{ r = 1.0, g = 0.8, b = 0.6 }, -- pastel brown
	{ r = 0.917, g = 0.722, b = 0.573 }, -- light orange
	{ r = 0.8, g = 0.557, b = 0.412 }, -- nougat
	{ r = 0.69, g = 0.459, b = 0.341 }, -- cork
	{ r = 0.486, g = 0.361, b = 0.275 }, -- brown
	{ r = 0.412, g = 0.251, b = 0.157 }, -- reddish brown
	{ r = 0.337, g = 0.259, b = 0.212 }, -- dirt brown
	{ r = 0.235, g = 0.188, b = 0.165 }, -- dark taupe
} :: { Rgb }

-- Colour words in item names, longest match first (D13 "colour words from item names").
local COLOUR_WORDS: { { word: string, c: Rgb } } = {
	{ word = "neon green", c = { r = 0.22, g = 1.0, b = 0.08 } },
	{ word = "neon pink", c = { r = 1.0, g = 0.1, b = 0.7 } },
	{ word = "neon blue", c = { r = 0.1, g = 0.6, b = 1.0 } },
	{ word = "hot pink", c = { r = 1.0, g = 0.2, b = 0.6 } },
	{ word = "sky blue", c = { r = 0.53, g = 0.81, b = 0.92 } },
	{ word = "navy", c = { r = 0.1, g = 0.12, b = 0.35 } },
	{ word = "teal", c = { r = 0.0, g = 0.5, b = 0.5 } },
	{ word = "turquoise", c = { r = 0.25, g = 0.78, b = 0.72 } },
	{ word = "cyan", c = { r = 0.2, g = 0.75, b = 0.78 } },
	{ word = "aqua", c = { r = 0.2, g = 0.75, b = 0.78 } },
	{ word = "blue", c = { r = 0.2, g = 0.33, b = 0.72 } },
	{ word = "lime", c = { r = 0.55, g = 0.85, b = 0.2 } },
	{ word = "green", c = { r = 0.22, g = 0.55, b = 0.26 } },
	{ word = "olive", c = { r = 0.5, g = 0.5, b = 0.1 } },
	{ word = "yellow", c = { r = 0.88, g = 0.8, b = 0.25 } },
	{ word = "gold", c = { r = 0.85, g = 0.65, b = 0.13 } },
	{ word = "orange", c = { r = 0.88, g = 0.5, b = 0.15 } },
	{ word = "red", c = { r = 0.72, g = 0.16, b = 0.16 } },
	{ word = "crimson", c = { r = 0.7, g = 0.05, b = 0.15 } },
	{ word = "maroon", c = { r = 0.5, g = 0.0, b = 0.1 } },
	{ word = "pink", c = { r = 1.0, g = 0.6, b = 0.75 } },
	{ word = "magenta", c = { r = 0.8, g = 0.2, b = 0.8 } },
	{ word = "purple", c = { r = 0.5, g = 0.2, b = 0.7 } },
	{ word = "violet", c = { r = 0.55, g = 0.3, b = 0.85 } },
	{ word = "lavender", c = { r = 0.7, g = 0.6, b = 0.9 } },
	{ word = "brown", c = { r = 0.45, g = 0.3, b = 0.18 } },
	{ word = "tan", c = { r = 0.82, g = 0.7, b = 0.55 } },
	{ word = "beige", c = { r = 0.9, g = 0.85, b = 0.7 } },
	{ word = "cream", c = { r = 0.98, g = 0.95, b = 0.85 } },
	{ word = "white", c = { r = 0.95, g = 0.95, b = 0.95 } },
	{ word = "black", c = { r = 0.08, g = 0.08, b = 0.1 } },
	{ word = "gray", c = { r = 0.5, g = 0.5, b = 0.52 } },
	{ word = "grey", c = { r = 0.5, g = 0.5, b = 0.52 } },
	{ word = "silver", c = { r = 0.75, g = 0.75, b = 0.78 } },
	{ word = "charcoal", c = { r = 0.2, g = 0.2, b = 0.22 } },
	{ word = "denim", c = { r = 0.25, g = 0.35, b = 0.55 } },
	{ word = "khaki", c = { r = 0.76, g = 0.69, b = 0.57 } },
}

local BIZARRE_WORDS = {
	"robot",
	"dino",
	"dragon",
	"skeleton",
	"alien",
	"zombie",
	"knight",
	"mech",
	"shark",
	"cat ",
	"dog ",
	"bear",
	"frog",
	"bunny",
	"piggy",
	"blocky giant",
	"giant",
	"huge",
	"mega",
	"massive",
	"colossal",
}

local OVERSIZED_WORDS = { "giant", "huge", "mega", "massive", "colossal", "oversized", "big " }

local HEAD_TYPES = { Hat = true, Hair = true, Face = true }

-- ---------------------------------------------------------------- colour helpers

local function clamp01(x: number): number
	return math.clamp(x, 0, 1)
end

function BlendRules.rgbToHsv(c: Rgb): Hsv
	local r, g, b = clamp01(c.r), clamp01(c.g), clamp01(c.b)
	local maxC = math.max(r, g, b)
	local minC = math.min(r, g, b)
	local delta = maxC - minC
	local h = 0
	if delta > 1e-9 then
		if maxC == r then
			h = ((g - b) / delta) % 6
		elseif maxC == g then
			h = (b - r) / delta + 2
		else
			h = (r - g) / delta + 4
		end
		h /= 6
		if h < 0 then
			h += 1
		end
	end
	local s = if maxC > 1e-9 then delta / maxC else 0
	return { h = h, s = s, v = maxC }
end

function BlendRules.hsvToRgb(c: Hsv): Rgb
	local h, s, v = (c.h % 1) * 6, clamp01(c.s), clamp01(c.v)
	local i = math.floor(h)
	local f = h - i
	local p, q, t = v * (1 - s), v * (1 - s * f), v * (1 - s * (1 - f))
	if i == 0 then
		return { r = v, g = t, b = p }
	elseif i == 1 then
		return { r = q, g = v, b = p }
	elseif i == 2 then
		return { r = p, g = v, b = t }
	elseif i == 3 then
		return { r = p, g = q, b = v }
	elseif i == 4 then
		return { r = t, g = p, b = v }
	end
	return { r = v, g = p, b = q }
end

-- Linear mix in RGB: t = 0 gives a, t = 1 gives b. The 70/30 rule is mix(stock, avatar, 0.3).
function BlendRules.mix(a: Rgb, b: Rgb, t: number): Rgb
	t = clamp01(t)
	return { r = a.r + (b.r - a.r) * t, g = a.g + (b.g - a.g) * t, b = a.b + (b.b - a.b) * t }
end

function BlendRules.distance(a: Rgb, b: Rgb): number
	local dr, dg, db = a.r - b.r, a.g - b.g, a.b - b.b
	return math.sqrt(dr * dr + dg * dg + db * db)
end

-- Town palette clamp: S <= 0.55, V in 0.39..0.91 (hue untouched).
function BlendRules.clampPalette(c: Rgb): Rgb
	local hsv = BlendRules.rgbToHsv(c)
	hsv.s = math.min(hsv.s, BlendRules.MAX_SATURATION)
	hsv.v = math.clamp(hsv.v, BlendRules.MIN_VALUE, BlendRules.MAX_VALUE)
	return BlendRules.hsvToRgb(hsv)
end

-- The softer clamp for the single surviving neon accent.
function BlendRules.clampAccent(c: Rgb): Rgb
	local hsv = BlendRules.rgbToHsv(c)
	hsv.s = math.min(hsv.s, BlendRules.ACCENT_MAX_SATURATION)
	hsv.v = math.clamp(hsv.v, BlendRules.MIN_VALUE, BlendRules.ACCENT_MAX_VALUE)
	return BlendRules.hsvToRgb(hsv)
end

function BlendRules.inPalette(c: Rgb, eps: number?): boolean
	local e = eps or 1e-6
	local hsv = BlendRules.rgbToHsv(c)
	return hsv.s <= BlendRules.MAX_SATURATION + e
		and hsv.v >= BlendRules.MIN_VALUE - e
		and hsv.v <= BlendRules.MAX_VALUE + e
end

function BlendRules.isNeon(c: Rgb): boolean
	local hsv = BlendRules.rgbToHsv(c)
	return hsv.s >= BlendRules.NEON_SATURATION and hsv.v >= BlendRules.NEON_VALUE
end

-- First colour word in an item name (case-insensitive, longest words first in the table).
function BlendRules.colourWord(name: string?): (Rgb?, string?)
	if not name then
		return nil, nil
	end
	local lower = string.lower(name)
	for _, entry in COLOUR_WORDS do
		if string.find(lower, entry.word, 1, true) then
			return entry.c, entry.word
		end
	end
	return nil, nil
end

function BlendRules.nearestSkinTone(c: Rgb): (number, Rgb, number)
	local bestI, bestD = 1, math.huge
	for i, tone in BlendRules.SKIN_TONES do
		local d = BlendRules.distance(c, tone)
		if d < bestD then
			bestI, bestD = i, d
		end
	end
	return bestI, BlendRules.SKIN_TONES[bestI], bestD
end

-- A derived eye colour: the accent hue, dark and calm (there is no eye colour in a description).
local function eyeFrom(c: Rgb): Rgb
	local hsv = BlendRules.rgbToHsv(c)
	hsv.s = math.min(hsv.s, 0.5)
	hsv.v = math.clamp(hsv.v * 0.5, 0.2, 0.45)
	return BlendRules.hsvToRgb(hsv)
end

local function hasWord(text: string, words: { string }): string?
	local lower = string.lower(text)
	for _, w in words do
		if string.find(lower, w, 1, true) then
			return w
		end
	end
	return nil
end

-- ---------------------------------------------------------------- traits

-- Colour candidates in priority order: body colours; then item names (GetProductInfo) and the
-- curated table for shirt, pants and accessories. Dominant = the most saturated candidate, body
-- colours favoured, so a classic avatar in a red shirt tints red while a skin-toned body does not.
function BlendRules.traits(desc: DescriptionLike, productInfo: ProductInfo?, table_: ColourTable?): Traits
	local info = productInfo or {}
	local curated = table_ or {}
	local sources: { [string]: string } = {}
	local nameHits, nameTried = 0, 0

	local function itemColour(assetId: number, label: string): Rgb?
		if assetId == 0 then
			sources[label] = "none"
			return nil
		end
		local entry = info[assetId]
		if entry then
			nameTried += 1
			local c = BlendRules.colourWord(entry.name)
			if c then
				nameHits += 1
				sources[label] = "name"
				return c
			end
		end
		local t = curated[assetId]
		if t then
			sources[label] = "table"
			return t
		end
		sources[label] = "none"
		return nil
	end

	-- Skin: the nearest of the 8 tones. A neutral (grey, unsaturated) head colour is a blank or
	-- classic default avatar and simply snaps to a tone; only a coloured head far from every tone
	-- (yellow blocky heads, green or blue skins) counts as non-human for the bizarre pick.
	local skinIndex, skinTone, skinDist = BlendRules.nearestSkinTone(desc.HeadColor)
	local headHsv = BlendRules.rgbToHsv(desc.HeadColor)
	local skinIsHuman = skinDist < 0.25 or headHsv.s < 0.25
	sources.skin = "body"

	local shirt = itemColour(desc.Shirt, "shirt")
	local pants = itemColour(desc.Pants, "pants")

	local hair: number? = nil
	local hairLayered = false
	local rigidHair: number? = nil
	local headAcc: number? = nil
	local oversized: number? = nil
	local accessoryColours: { Rgb } = {}
	local layeredShirt: Rgb? = nil
	for _, acc in desc.accessories do
		local c = itemColour(acc.assetId, `accessory:{acc.assetId}`)
		if c then
			table.insert(accessoryColours, c)
		end
		-- hair comes across layered or rigid (most modern hair is a WrapLayer accessory, measured in S9)
		if acc.accessoryType == "Hair" and not hair then
			hair = acc.assetId
			hairLayered = acc.isLayered
		end
		if acc.isLayered then
			-- jackets, sweaters, shirts count as shirts for the pattern colour (D13)
			if
				c and (acc.accessoryType == "Jacket" or acc.accessoryType == "Sweater" or acc.accessoryType == "Shirt")
			then
				layeredShirt = layeredShirt or c
			end
		else
			if acc.accessoryType == "Hair" and not rigidHair then
				rigidHair = acc.assetId
			elseif HEAD_TYPES[acc.accessoryType] and not headAcc then
				headAcc = acc.assetId
			end
		end
		local entry = info[acc.assetId]
		if entry and not oversized and hasWord(entry.name, OVERSIZED_WORDS) then
			oversized = acc.assetId
		end
	end
	shirt = shirt or layeredShirt

	-- Dominant: weighted saturation over the candidates.
	local candidates: { { c: Rgb, w: number, src: string } } = {
		{ c = desc.TorsoColor, w = 1.0, src = "body" },
		{ c = desc.LeftArmColor, w = 0.6, src = "body" },
		{ c = desc.LeftLegColor, w = 0.6, src = "body" },
	}
	if shirt then
		table.insert(candidates, { c = shirt, w = 1.2, src = sources.shirt })
	end
	if pants then
		table.insert(candidates, { c = pants, w = 1.0, src = sources.pants })
	end
	for _, c in accessoryColours do
		table.insert(candidates, { c = c, w = 0.8, src = "accessory" })
	end
	local dominant = desc.TorsoColor
	local bestScore = -1
	local neon: { Rgb } = {}
	for _, cand in candidates do
		local hsv = BlendRules.rgbToHsv(cand.c)
		local score = hsv.s * cand.w
		if score > bestScore then
			bestScore = score
			dominant = cand.c
			sources.dominant = cand.src
		end
		if BlendRules.isNeon(cand.c) then
			table.insert(neon, cand.c)
		end
	end
	sources.dominant = sources.dominant or "body"

	-- Bizarre detection (A3): non-human skin, neon, many accessories, extreme scales, non-human bundle.
	local reasons: { string } = {}
	if not skinIsHuman then
		table.insert(reasons, "nonhuman_skin")
	end
	if #neon > 0 then
		table.insert(reasons, "neon")
	end
	if #desc.accessories >= 6 then
		table.insert(reasons, "many_accessories")
	end
	if
		desc.HeightScale > 1.05
		or desc.HeightScale < 0.9
		or desc.WidthScale > 1.0
		or desc.WidthScale < 0.7
		or desc.HeadScale > 1.0
		or desc.HeadScale < 0.95
		or desc.BodyTypeScale >= 0.9
	then
		table.insert(reasons, "extreme_scale")
	end
	local bundleWord: string? = nil
	for _, w in (desc.bundleWords or {}) :: { string } do
		bundleWord = bundleWord or hasWord(w, BIZARRE_WORDS)
	end
	if bundleWord then
		table.insert(reasons, "nonhuman_bundle")
	end
	if oversized then
		table.insert(reasons, "oversized_accessory")
	end

	-- One signature feature (priority: neon tips, oversized accessory, non-human bundle, patterned fur).
	local signature = "none"
	if #neon > 0 then
		signature = "neon_tips"
	elseif oversized then
		signature = "oversized_accessory"
	elseif bundleWord then
		signature = "nonhuman_bundle"
	elseif not skinIsHuman then
		signature = "patterned_fur"
	end

	local accentSource = if #neon > 0 then neon[1] else (shirt or dominant)

	return {
		skinTone = skinTone,
		skinToneIndex = skinIndex,
		skinIsHuman = skinIsHuman,
		face = desc.Face,
		headIsDynamic = desc.HeadIsDynamic == true or (desc.Head ~= 0 and desc.HeadIsDynamic ~= false),
		hairAccessory = hair,
		hairIsLayered = hairLayered,
		headAccessory = headAcc,
		signatureAccessory = oversized or rigidHair or headAcc,
		dominant = dominant,
		shirt = shirt,
		pants = pants,
		eye = eyeFrom(accentSource),
		neon = neon,
		sources = sources,
		nameHits = nameHits,
		nameTried = nameTried,
		bizarre = #reasons > 0,
		bizarreReasons = reasons,
		signature = signature,
	}
end

function BlendRules.isBizarre(traits: Traits): (boolean, { string })
	return traits.bizarre, traits.bizarreReasons
end

-- ---------------------------------------------------------------- compose

local ANIMALS: { [string]: boolean } = { squirrel = true, rodent = true, fox = true, deer = true }

-- Humans: appearance properties only (brief v2 §13a). Nothing here is a tint.
local function composeHuman(traits: Traits): HumanLook
	return {
		kind = "human",
		skinTone = traits.skinTone,
		skinToneIndex = traits.skinToneIndex,
		face = if traits.headIsDynamic then 0 else traits.face,
		dynamicHeadExpression = if traits.headIsDynamic then "neutral" else nil,
		hair = traits.hairAccessory,
		headAccessory = if traits.hairAccessory then nil else traits.headAccessory,
	}
end

-- Animals: capped fur tint, pattern colours from shirt/pants, derived eyes, one rigid accessory.
local function composeAnimal(_species: string, stock: StockLook, traits: Traits): AnimalLook
	local avatarWeight = BlendRules.AVATAR_WEIGHT
	local bodyTint = BlendRules.clampPalette(BlendRules.mix(stock.body, traits.dominant, avatarWeight))
	local patternSource = traits.shirt or traits.dominant
	local tailSource = traits.pants or patternSource
	local patternColour = BlendRules.clampPalette(BlendRules.mix(stock.pattern, patternSource, 0.6))
	local tailTip = BlendRules.clampPalette(BlendRules.mix(stock.pattern, tailSource, 0.6))
	local eyeColour = if stock.eyesLocked then stock.eyes else BlendRules.clampPalette(traits.eye)
	local accent: Rgb? = nil
	if traits.signature == "neon_tips" and #traits.neon > 0 then
		-- the one neon accent: ear tips and tail tip, softened to the accent clamp
		local soft = BlendRules.clampAccent(traits.neon[1])
		accent = soft
		tailTip = soft
	elseif traits.signature == "patterned_fur" then
		-- non-human skin becomes the pattern colour, inside the palette
		patternColour = BlendRules.clampPalette(traits.skinTone)
	end
	return {
		kind = "animal",
		bodyTint = bodyTint,
		patternColour = patternColour,
		tailTip = tailTip,
		eyeColour = eyeColour,
		accessory = traits.signatureAccessory,
		signature = traits.signature,
		accent = accent,
	}
end

function BlendRules.compose(species: string, stock: StockLook, traits: Traits): Look
	if species == "human" then
		return composeHuman(traits)
	elseif ANIMALS[species] then
		return composeAnimal(species, stock, traits)
	end
	error(`BlendRules.compose: unknown species {species}`)
end

-- Count the neon accents a Look carries (the rule allows at most one).
function BlendRules.neonAccents(look: Look): number
	if look.kind ~= "human" then
		local animal = look :: AnimalLook
		local n = 0
		for _, c in { animal.bodyTint, animal.patternColour, animal.tailTip, animal.eyeColour } do
			if BlendRules.isNeon(c) then
				n += 1
			end
		end
		return n
	end
	return 0
end

return BlendRules
