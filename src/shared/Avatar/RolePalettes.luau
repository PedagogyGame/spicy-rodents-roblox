--!strict
-- ReplicatedStorage.Shared.Avatar.RolePalettes
-- Role colour palettes for the placeholder humans (W1 #10) and the stock HumanoidDescriptions they wear
-- [hospital_police_infection §5.1 staff skins and uniforms, §8.2 police; humans_actors §2.1 pants, hair].
-- Interface: ROLES; palette(role) -> Palette; look(role, index) -> Look (deterministic per index);
--            descriptionProps(look) -> {[HumanoidDescription colour property] = Rgb};
--            description(role, index, lib) -> HumanoidDescription (engine or @lune/roblox).
--
-- Stock = role uniform and silhouette (humans_actors verifier note): body part colours carry the
-- uniform (torso = shirt, legs = pants, head and arms = skin) because a stock HumanoidDescription with
-- no clothing assets can only colour body parts; no asset uploads in W1. The avatar blend later replaces
-- skin, face and hair through appearance properties (brief v2 §13a), never the uniform.

local PartBuilder = require("./PartBuilder")

export type Rgb = PartBuilder.Rgb
export type Palette = { label: string, shirts: { string }, pants: { string }, cap: string? }
export type Look = { role: string, skin: Rgb, shirt: Rgb, pants: Rgb, hair: Rgb, cap: Rgb? }

local hex = PartBuilder.hex

local RolePalettes = {}

-- Skins: the eight hospital staff skins (§5.1), a spread of tones.
RolePalettes.SKINS = { "#d1a988", "#855946", "#d6b192", "#98715a", "#d8b296", "#ad886f", "#8a624d", "#c9a184" }
-- v5.4 pants and hair (humans_actors §2.1, L4592, L4602).
RolePalettes.PANTS = { "#3d494b", "#646c61", "#55585a", "#827a6c", "#484957" }
RolePalettes.HAIR = { "#40382f", "#755a45", "#bba27e", "#666663", "#2d2928", "#937d57" }

-- stylua: ignore
RolePalettes.PALETTES = {
	townsperson = { label = "Townsperson", shirts = { "#8d6e5a", "#5f7f8f", "#9a8b5c", "#6d8a6a", "#a0645f", "#7b6f9a" }, pants = RolePalettes.PANTS },
	doctor = { label = "Doctor", shirts = { "#e9eee7" }, pants = { "#c9d1cc" } },                         -- §5.1 Dr. Ellis
	nurse = { label = "Nurse", shirts = { "#75b0af", "#83ada3" }, pants = { "#75b0af", "#83ada3" } },    -- §5.1 scrubs
	guard = { label = "Hospital guard", shirts = { "#4a6772", "#425e69" }, pants = { "#2c3d43" }, cap = "#2c3d43" },
	orderly = { label = "Orderly", shirts = { "#9dabb3", "#9da9b1" }, pants = { "#7d8a91" } },
	officer = { label = "Police officer", shirts = { "#324b70", "#3b5274", "#354f72", "#345070" }, pants = { "#202c41" }, cap = "#202c41" }, -- §8.2
	driver = { label = "Police driver", shirts = { "#324b70" }, pants = { "#202c41" }, cap = "#202c41" },
	mime = { label = "Mime", shirts = { "#f2f2ee" }, pants = { "#202020" } },
} :: { [string]: Palette }

RolePalettes.ROLES = { "townsperson", "doctor", "nurse", "guard", "orderly", "officer", "driver", "mime" }

function RolePalettes.palette(role: string): Palette
	return RolePalettes.PALETTES[role] or error(`RolePalettes: unknown role {role}`)
end

local function pick(list: { string }, i: number): Rgb
	return hex(list[((i - 1) % #list) + 1])
end

-- Deterministic per index so a seeded population looks the same on every server and in Lune.
function RolePalettes.look(role: string, index: number): Look
	local p = RolePalettes.palette(role)
	local i = math.max(1, math.floor(index))
	return {
		role = role,
		skin = pick(RolePalettes.SKINS, i * 3 + 1),
		shirt = pick(p.shirts, i),
		pants = pick(p.pants, i * 2 + 1),
		hair = pick(RolePalettes.HAIR, i * 5 + 2),
		cap = if p.cap then hex(p.cap) else nil,
	}
end

function RolePalettes.descriptionProps(look: Look): { [string]: Rgb }
	return {
		HeadColor = look.skin,
		LeftArmColor = look.skin,
		RightArmColor = look.skin,
		TorsoColor = look.shirt,
		LeftLegColor = look.pants,
		RightLegColor = look.pants,
	}
end

-- A stock HumanoidDescription (no assets) in the role's palette. `lib` = {Instance, Color3}.
function RolePalettes.description(role: string, index: number, lib: { Instance: any, Color3: any }): any
	local look = RolePalettes.look(role, index)
	local desc = lib.Instance.new("HumanoidDescription")
	desc.Name = `Stock_{role}_{index}`
	for prop, c in RolePalettes.descriptionProps(look) do
		(desc :: any)[prop] = lib.Color3.new(c.r, c.g, c.b)
	end
	return desc
end

return RolePalettes
