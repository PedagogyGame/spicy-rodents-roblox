--!strict
-- ReplicatedStorage.Shared.Actors.Species
-- Species definitions (body kind, motor, brains, hitbox, sockets, stock looks, reference speeds).
-- Interface (BUILD_PLAN §1.4): def(species), list(), variants(species), stockLook(species, index)
-- Pure: every length is in studs through Config/Units (the single unit boundary, D21); the HTML
-- source numbers are cited next to each value. Requiring this module has no side effects.
--
-- Sources: squirrel ground speeds 8.0 / 16.8 / 1.65 u/s and rail 7.2 / 12.2 / 1.2 u/s, x0.6 on wood
-- kinds, collision radius 0.32 u [routes_movement §8.1, §10, §5]; human walk R(0.8, 1.6), flee 7.1,
-- cyclist R(3.2, 5.2), height about 2.09 u [humans_actors §4.2, §5.2, §15]; fox roam 2.0 / hunt 8.8,
-- deer graze 1.25 / flee 11.8 (fawn 9.0), leashes 115 / 95 u [wildlife_foraging §11.8, §11.9];
-- stock furs [wildlife_foraging §2.1, §11.8, §11.9]; the spicy rodent is a squirrel actor with
-- Variant = "spicy" (rule 1).

local Units = require("../Config/Units")

export type Rgb = { r: number, g: number, b: number }

export type StockLook = {
	name: string,
	body: Rgb, -- fur or skin base
	pattern: Rgb, -- belly / tail tip / muzzle accent
	eyes: Rgb,
	eyesLocked: boolean, -- true: the blend never recolours the eyes (the rodent's bloodshot red)
}

export type Speeds = {
	walk: number, -- studs/s
	sprint: number,
	stalk: number?,
	flee: number?,
	rail: { walk: number, sprint: number, stalk: number, woodMultiplier: number }?,
}

export type SpeciesDef = {
	id: string,
	bodyKind: "humanoidR15" | "skinned" | "device",
	motor: string, -- Shared/Movement module name
	brains: { string }, -- Server/Actors/Brains module names this species may run
	variants: { string },
	hitbox: { radius: number, height: number }, -- studs; drives gameplay, never changed by the blend
	hipHeight: number, -- studs
	sockets: { string },
	speeds: Speeds,
	leash: number?, -- studs from origin (fox, deer)
	stockLooks: { StockLook },
	possessable: boolean,
}

local Species = {}

local function rgb(hex: string): Rgb
	local n = tonumber(string.sub(hex, 2), 16) :: number
	return {
		r = math.floor(n / 65536) % 256 / 255,
		g = math.floor(n / 256) % 256 / 255,
		b = n % 256 / 255,
	}
end

local function look(name: string, body: string, pattern: string, eyes: string, eyesLocked: boolean?): StockLook
	return { name = name, body = rgb(body), pattern = rgb(pattern), eyes = rgb(eyes), eyesLocked = eyesLocked == true }
end

local DEFS: { [string]: SpeciesDef } = {
	human = {
		id = "human",
		bodyKind = "humanoidR15",
		motor = "HumanAIMotor",
		brains = { "Pedestrian", "Staff", "Officer" },
		variants = { "townsperson", "shopWorker", "hospitalStaff", "ambulanceCrew", "police", "attractionStaff" },
		-- about 2.09 u tall, R15 scale [humans_actors §15]; kick reach 2.65 u is a Combat tunable
		hitbox = { radius = Units.st(0.45), height = Units.st(2.09) },
		hipHeight = Units.st(1.0),
		sockets = {
			"RightGripAttachment",
			"LeftGripAttachment",
			"BadgeAttachment",
			"HairAttachment",
			"MaskAttachment",
			"ChestRigAttachment",
			"PadAttachmentL",
			"PadAttachmentR",
		},
		speeds = { walk = Units.st(1.2), sprint = Units.st(3.2), flee = Units.st(7.1) },
		stockLooks = {
			look("townsperson", "#c69c6d", "#5a6b7d", "#2b2b2b"),
			look("police", "#c69c6d", "#1f2d4d", "#2b2b2b"),
			look("hospital", "#c69c6d", "#2f8f8a", "#2b2b2b"),
		},
		possessable = true,
	},
	squirrel = {
		id = "squirrel",
		bodyKind = "skinned",
		motor = "SquirrelMotor",
		brains = { "Squirrel", "Rodent" },
		variants = { "normal", "spicy" },
		-- 0.32 u ground collision radius [routes_movement §8.3]; about 1.2 st at the shoulder [brief §7]
		hitbox = { radius = Units.st(0.32), height = 1.7 },
		hipHeight = 0.9,
		sockets = { "HeadSocket", "MouthSocket", "TailTip", "ChestCenter" },
		speeds = {
			walk = Units.st(8.0),
			sprint = Units.st(16.8),
			stalk = Units.st(1.65),
			rail = { walk = Units.st(7.2), sprint = Units.st(12.2), stalk = Units.st(1.2), woodMultiplier = 0.6 },
		},
		stockLooks = {
			look("fur0", "#b78453", "#e8dcc4", "#29302f"),
			look("fur1", "#9a6b47", "#e8dcc4", "#29302f"),
			look("fur2", "#b19b7b", "#efe6d2", "#29302f"),
			look("fur3", "#675e4d", "#cfc3ad", "#29302f"),
			look("fur4", "#a48c68", "#e8dcc4", "#29302f"),
			look("fur5", "#8c7463", "#dccbb4", "#29302f"),
			look("fur6", "#c19c66", "#efe6d2", "#29302f"),
			-- the spicy rodent: mangy fur, bloodshot emissive eyes that the blend never touches
			look("spicy", "#83544d", "#a67860", "#ff2a1a", true),
		},
		possessable = true,
	},
	fox = {
		id = "fox",
		bodyKind = "skinned",
		motor = "QuadrupedMotor",
		brains = { "Fox" },
		variants = { "fox" },
		-- about 1.6 u tall to the ear tips, 3 u long with the tail [wildlife_foraging §11.9]
		hitbox = { radius = Units.st(0.5), height = Units.st(1.6) },
		hipHeight = Units.st(0.77),
		sockets = { "HeadSocket", "MouthSocket", "TailTip", "ChestCenter" },
		speeds = { walk = Units.st(2.0), sprint = Units.st(8.8) },
		leash = Units.st(115),
		stockLooks = { look("fox", "#b8663c", "#e4d6bc", "#302c29") },
		possessable = true,
	},
	deer = {
		id = "deer",
		bodyKind = "skinned",
		motor = "QuadrupedMotor",
		brains = { "Deer" },
		variants = { "doe", "buck", "fawn" },
		-- adult about 3.1 u to the ear tips [wildlife_foraging §11.8]; fawn = Model:ScaleTo(0.55)
		hitbox = { radius = Units.st(0.7), height = Units.st(3.1) },
		hipHeight = Units.st(1.75),
		sockets = { "HeadSocket", "MouthSocket", "TailTip", "ChestCenter" },
		speeds = { walk = Units.st(1.25), sprint = Units.st(11.8), flee = Units.st(11.8) },
		leash = Units.st(95),
		stockLooks = {
			look("doe", "#ad845e", "#dfd1b3", "#25221e"),
			look("buck", "#946f4e", "#dfd1b3", "#25221e"),
			look("fawn", "#b99a70", "#dfd1b3", "#25221e"),
		},
		possessable = true,
	},
}

local ORDER = { "human", "squirrel", "fox", "deer" }

-- Species that are actors (brief §4). Devices (drone, cars) are not species; RigSpec still names them.
function Species.list(): { string }
	return table.clone(ORDER)
end

function Species.def(id: string): SpeciesDef
	local def = DEFS[id]
	if not def then
		error(`Species.def: unknown species {id}`)
	end
	return def
end

function Species.has(id: string): boolean
	return DEFS[id] ~= nil
end

function Species.variants(id: string): { string }
	return table.clone(Species.def(id).variants)
end

-- Stock look by 1-based index, wrapping, so a seeded pick never falls off the table.
function Species.stockLook(id: string, index: number): StockLook
	local looks = Species.def(id).stockLooks
	local i = ((math.floor(index) - 1) % #looks) + 1
	return looks[i]
end

-- The spicy rodent's stock look (variant "spicy" of the squirrel species).
function Species.rodentLook(): StockLook
	local looks = DEFS.squirrel.stockLooks
	return looks[#looks]
end

-- Deer fawn scale (wildlife_foraging §11.8 "Fawn size 0.55"; RigSpec: Model:ScaleTo).
Species.FAWN_SCALE = 0.55

return Species
