--!strict
-- ReplicatedStorage.Shared.Avatar.PeopleLooks
-- What each person in town wears when the rounded townspeople are loaded (Shared/Avatar/PeopleAssets,
-- Server/Assets/PeopleArt): the build, the outfit, the face, the hair and the hat, and the colours each part is
-- tinted with. The art has eight roles (the townsperson, the hospital's doctor, nurse, guard and orderly, the
-- police officer and driver, the mime); the game's other people are dressed from those outfits:
--   paramedic   the ambulance crew: the zipped jacket in the crew's orange, no hat
--   shopkeeper  a shop's worker (Pepper's Corner Store's): the short-sleeved shirt
--   attendant   an attraction's staff (the alley's, the sky lift's): the zipped jacket
--   doorman     THE GILDED ACORN's two guards: the long-sleeved uniform (the police cut, tie and badge) and the peaked
--               cap in claret, always broad
--   bartender   THE GILDED ACORN's bartender: the zipped jacket in white over black trousers, hair combed back
-- Everything is picked from the person's index, so a seeded town looks the same on every server and in Lune.
-- Interface: ROLES; POSTS; roleOf(post, index) -> role; dress(role, index, colours?) -> Dress;
--   tint(dress, key) -> Rgb (key: skin, shirt, pants, hair, cap or "#rrggbb").
-- Pure. No side effects on require.

local PartBuilder = require("./PartBuilder")
local PeopleAssets = require("./PeopleAssets")
local RolePalettes = require("./RolePalettes")

export type Rgb = PartBuilder.Rgb
export type Colours = { skin: Rgb, shirt: Rgb, pants: Rgb, hair: Rgb, cap: Rgb? }
export type Dress = {
	role: string,
	build: string, -- "slim" | "broad" (PeopleAssets.BUILDS)
	outfit: string, -- PeopleAssets.OUTFITS
	face: string, -- PeopleAssets.HEAD.faces
	expression: string, -- PeopleAssets.HEAD.expressions
	hair: string?, -- a PeopleAssets.HEADWEAR hair item
	hat: string?, -- a PeopleAssets.HEADWEAR hat item
	colours: Colours,
}
export type Role = {
	art: string, -- the art role it is dressed from (PeopleAssets.ROLES)
	outfit: string?, -- in place of the art role's outfits
	hat: string | false | nil, -- false: no hat
	hair: { string }?, -- in place of the art role's hair styles
	build: string?, -- always this build
	shirt: string?, -- fixed colours ("#rrggbb") in place of the palette's
	pants: string?,
	cap: string?,
}

local hex = PartBuilder.hex

local PeopleLooks = {}

PeopleLooks.BROAD_EVERY = 3 -- one person in three is broad (index 3, 6, 9 ...)

PeopleLooks.ROLES = table.freeze({
	paramedic = { art = "orderly", outfit = "jacket", hat = false, shirt = "#e6782a" },
	shopkeeper = { art = "townsperson", outfit = "shirt" },
	attendant = { art = "townsperson", outfit = "jacket" },
	doorman = {
		art = "guard",
		outfit = "police",
		build = "broad",
		shirt = "#5c1c22",
		pants = "#1e1c20",
		cap = "#5c1c22",
	},
	bartender = {
		art = "townsperson",
		outfit = "jacket",
		build = "slim",
		hair = { "Hair_parted", "Hair_short" },
		shirt = "#eee8dc",
		pants = "#1a181a",
	},
} :: { [string]: Role })

-- A population post -> the role its people are dressed as (hospital staff take turns, as Actors/BodyFactory
-- colours them); a post not listed is a townsperson.
PeopleLooks.POSTS = table.freeze({
	police = "officer",
	ambulance_crew = "paramedic",
	shop_worker = "shopkeeper",
	attraction_staff = "attendant",
} :: { [string]: string })
PeopleLooks.HOSPITAL = table.freeze({ "nurse", "doctor", "orderly", "nurse", "guard" })

function PeopleLooks.roleOf(post: string?, index: number): string
	if post == "hospital_staff" then
		return PeopleLooks.HOSPITAL[index % #PeopleLooks.HOSPITAL + 1]
	end
	return PeopleLooks.POSTS[post or ""] or "townsperson"
end

local function pick<T>(list: { T }, i: number): T
	return list[(math.max(1, math.floor(i)) - 1) % #list + 1]
end

-- The art role and the overrides for a role name (an art role has none).
local function resolve(role: string): (string, Role?)
	local extra = PeopleLooks.ROLES[role]
	if extra then
		return extra.art, extra
	end
	if PeopleAssets.ROLES[role] == nil then
		error(`PeopleLooks: unknown role {role}`)
	end
	return role, nil
end

-- dress(role, index, colours?): what person `index` of `role` wears. `colours` (skin, shirt, pants, and hair and cap
-- when known) are the body's own (Actors/BodyFactory's palette and cast picks); missing ones come from
-- RolePalettes.look of the art role. A role's fixed colours win over both.
function PeopleLooks.dress(role: string, index: number, colours: { [string]: Rgb }?): Dress
	local artRole, extra = resolve(role)
	local art = PeopleAssets.ROLES[artRole]
	local i = math.max(1, math.floor(index))
	local base = RolePalettes.look(artRole, i)
	local given: { [string]: Rgb } = colours or {}
	local c: Colours = {
		skin = given.skin or base.skin,
		shirt = given.shirt or base.shirt,
		pants = given.pants or base.pants,
		hair = given.hair or base.hair,
		cap = given.cap or base.cap or given.pants or base.pants,
	}
	local outfit = if extra and extra.outfit then extra.outfit else pick(art.outfits, i)
	local hat: string? = art.hat
	local hairs: { string } = if extra and extra.hair then extra.hair else art.hair
	local build = if i % PeopleLooks.BROAD_EVERY == 0 then "broad" else "slim"
	if extra then
		if extra.hat == false then
			hat = nil
		elseif type(extra.hat) == "string" then
			hat = extra.hat
		end
		build = extra.build or build
		c.shirt = if extra.shirt then hex(extra.shirt) else c.shirt
		c.pants = if extra.pants then hex(extra.pants) else c.pants
		c.cap = if extra.cap then hex(extra.cap) else c.cap
	end
	local hair: string? = pick(hairs, i * 5 + 2)
	if hat then
		-- under a hat only a style that fits under it (a role with a hat lists only those)
		local fits = {}
		for _, h in hairs do
			if PeopleAssets.HEADWEAR[h].underCap then
				table.insert(fits, h)
			end
		end
		hair = if #fits > 0 then pick(fits, i * 5 + 2) else nil
	end
	return {
		role = role,
		build = build,
		outfit = outfit,
		face = art.face,
		expression = "calm",
		hair = hair,
		hat = hat,
		colours = c,
	}
end

-- tint(dress, key): the colour a region with tint `key` takes.
function PeopleLooks.tint(dress: Dress, key: string): Rgb
	if string.sub(key, 1, 1) == "#" then
		return hex(key)
	end
	local c = (dress.colours :: any)[key]
	if c == nil then
		error(`PeopleLooks: no colour {key}`)
	end
	return c
end

return PeopleLooks
