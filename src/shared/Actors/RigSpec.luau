--!strict
-- ReplicatedStorage.Shared.Actors.RigSpec
-- Rig contracts v0 with the FINAL bone, socket and region names (BUILD_PLAN §1.4, §5.2, D22):
-- squirrel (and the spicy rodent), fox, deer, human R15, drone, car. Gameplay, placeholders and art
-- read only this contract, so puppets and skinned rigs are interchangeable.
-- Interface: RigSpec[species] (contract), RigSpec.validate(model) -> Report, RigSpec.species()
-- Pure data plus one validator that walks an Instance tree (works on @lune/roblox instances too).
-- Facing: every authored rig faces -Z (Roblox LookVector); Config/Units adds the one +pi (D21).
--
-- Naming rules (final):
--   * Bones are PascalCase; chains are numbered from the body outwards (Tail1 is at the hips).
--   * Legs are <Front|Back><L|R>_<Upper|Lower|Foot|Toe>; the R15 human keeps Roblox's names.
--   * Sockets are Attachments named *Socket (animals) or *Attachment (humans, Roblox style).
--   * Regions are the separately tinted MeshParts (one SurfaceAppearance has one Color, D22).
--   * The PrimaryPart is RootPart (animals, drone, car) or HumanoidRootPart (human); the puppet's
--     Motor6Ds carry the bone names so the procedural backend and clips address the same joints.

export type Contract = {
	id: string,
	primaryPart: string,
	bubbleHead: string?, -- the rigid part bubble chat and the face live on
	bones: { string },
	sockets: { string },
	regions: { string }, -- tintable MeshParts (animals) or skin parts (humans)
	parts: { string }?, -- rigid parts a device or R15 body must have
	clips: { string },
	budget: { tris: number, bones: number },
	hitbox: { kind: "capsule" | "box", radius: number?, height: number?, size: { number }? }, -- studs
	scaleVariants: { [string]: number }?,
}

export type Report = {
	ok: boolean,
	species: string,
	missingBones: { string },
	missingSockets: { string },
	missingRegions: { string },
	missingParts: { string },
	primaryPartOk: boolean,
	found: number,
}

local RigSpec = {}

local function legs(): { string }
	local out = {}
	for _, leg in { "FrontL", "FrontR", "BackL", "BackR" } do
		for _, seg in { "Upper", "Lower", "Foot", "Toe" } do
			table.insert(out, `{leg}_{seg}`)
		end
	end
	return out
end

local function chain(prefix: string, n: number): { string }
	local out = {}
	for i = 1, n do
		table.insert(out, `{prefix}{i}`)
	end
	return out
end

local function concat(...: { string }): { string }
	local out = {}
	for _, list in { ... } do
		for _, v in list do
			table.insert(out, v)
		end
	end
	return out
end

local ANIMAL_SOCKETS = { "HeadSocket", "MouthSocket", "TailTip", "ChestCenter" }

-- Clip names per rig (BUILD_PLAN §5.4; the brief §7's seven squirrel clips plus the shared set).
local SQUIRREL_CLIPS = {
	"Idle",
	"Walk",
	"Run",
	"Sprint",
	"Stalk",
	"Climb",
	"Leap",
	"Pounce",
	"Bite",
	"Land",
	"Forage",
	"Carry",
	"Stink",
	"Hit",
	"Die",
}
local QUADRUPED_CLIPS = { "Idle", "Walk", "Run", "Graze", "Flee", "Lunge", "Hit", "Die" }
local HUMAN_CLIPS = {
	"Idle",
	"Walk",
	"Jog",
	"Run",
	"Flee",
	"Kick",
	"Swing",
	"Flinch",
	"Injured",
	"Sit",
	"Work",
	"Crouch",
}

RigSpec.squirrel = {
	id = "squirrel",
	primaryPart = "RootPart",
	bubbleHead = "Head",
	bones = concat(
		{ "Root", "Hips", "Spine1", "Spine2", "Spine3", "Chest", "Neck", "Head", "Jaw", "EarL", "EarR" },
		chain("Tail", 8),
		legs()
	),
	sockets = ANIMAL_SOCKETS,
	regions = { "Body", "Pattern", "Eyes", "FurCards" },
	clips = SQUIRREL_CLIPS,
	budget = { tris = 13000, bones = 36 },
	hitbox = { kind = "capsule", radius = 0.8, height = 1.7 },
} :: Contract

-- The spicy rodent shares the squirrel skeleton and clips; it adds the Blood region (F-9).
RigSpec.rodent = {
	id = "rodent",
	primaryPart = "RootPart",
	bubbleHead = "Head",
	bones = RigSpec.squirrel.bones,
	sockets = ANIMAL_SOCKETS,
	regions = { "Body", "Pattern", "Eyes", "FurCards", "Blood" },
	clips = SQUIRREL_CLIPS,
	budget = { tris = 11000, bones = 36 },
	hitbox = RigSpec.squirrel.hitbox,
} :: Contract

RigSpec.fox = {
	id = "fox",
	primaryPart = "RootPart",
	bubbleHead = "Head",
	bones = concat(
		{ "Root", "Hips", "Spine1", "Spine2", "Spine3", "Chest", "Neck", "Head", "Jaw", "EarL", "EarR" },
		chain("Tail", 6),
		legs()
	),
	sockets = ANIMAL_SOCKETS,
	regions = { "Body", "Pattern", "Eyes", "FurCards" },
	clips = QUADRUPED_CLIPS,
	budget = { tris = 8000, bones = 34 },
	hitbox = { kind = "capsule", radius = 1.25, height = 4.0 },
} :: Contract

RigSpec.deer = {
	id = "deer",
	primaryPart = "RootPart",
	bubbleHead = "Head",
	bones = concat(
		{
			"Root",
			"Hips",
			"Spine1",
			"Spine2",
			"Spine3",
			"Chest",
			"Neck1",
			"Neck2",
			"Neck3",
			"Head",
			"Jaw",
			"EarL",
			"EarR",
		},
		chain("Tail", 2),
		legs()
	),
	sockets = ANIMAL_SOCKETS,
	regions = { "Body", "Pattern", "Eyes" },
	parts = {}, -- "Antlers" is optional (buck only), so it is not required here
	clips = QUADRUPED_CLIPS,
	budget = { tris = 9500, bones = 40 },
	hitbox = { kind = "capsule", radius = 1.75, height = 7.75 },
	scaleVariants = { doe = 1.0, buck = 1.18, fawn = 0.55 },
} :: Contract

-- Standard R15 (Roblox names) on one shared UV layout; skin shows through transparent texels on the
-- skin regions (D22); the face is a Decal named FaceDecal on Head.
local R15_PARTS = {
	"HumanoidRootPart",
	"Head",
	"UpperTorso",
	"LowerTorso",
	"LeftUpperArm",
	"LeftLowerArm",
	"LeftHand",
	"RightUpperArm",
	"RightLowerArm",
	"RightHand",
	"LeftUpperLeg",
	"LeftLowerLeg",
	"LeftFoot",
	"RightUpperLeg",
	"RightLowerLeg",
	"RightFoot",
}
RigSpec.human = {
	id = "human",
	primaryPart = "HumanoidRootPart",
	bubbleHead = "Head",
	-- R15 Motor6D names
	bones = {
		"Root",
		"Waist",
		"Neck",
		"LeftShoulder",
		"LeftElbow",
		"LeftWrist",
		"RightShoulder",
		"RightElbow",
		"RightWrist",
		"LeftHip",
		"LeftKnee",
		"LeftAnkle",
		"RightHip",
		"RightKnee",
		"RightAnkle",
	},
	sockets = {
		"RightGripAttachment",
		"LeftGripAttachment",
		"HairAttachment",
		"BadgeAttachment",
		"MaskAttachment",
		"ChestRigAttachment",
		"PadAttachmentL",
		"PadAttachmentR",
	},
	regions = { "Head", "LeftHand", "RightHand", "LeftLowerArm", "RightLowerArm" },
	parts = R15_PARTS,
	clips = HUMAN_CLIPS,
	budget = { tris = 10000, bones = 15 },
	hitbox = { kind = "capsule", radius = 1.1, height = 5.2 },
} :: Contract

RigSpec.drone = {
	id = "drone",
	primaryPart = "RootPart",
	bones = {},
	sockets = { "Camera" },
	regions = {},
	parts = { "RootPart", "Rotor1", "Rotor2", "Rotor3", "Rotor4" },
	clips = {},
	budget = { tris = 3000, bones = 0 },
	hitbox = { kind = "box", size = { 2.0, 0.8, 2.0 } },
} :: Contract

-- Vehicles: body plus 4 wheels; every player-enterable kind has an interior with DashSocket and
-- EyeSocket (brief v2 §14, S14). Logical box per traffic §1 (sedan 2.35 x 4.45 x 2.04 u).
RigSpec.car = {
	id = "car",
	primaryPart = "RootPart",
	bones = {},
	sockets = { "DriverSeat", "DashSocket", "EyeSocket" },
	regions = {},
	parts = { "RootPart", "Body", "WheelFL", "WheelFR", "WheelBL", "WheelBR", "LightBar", "Headlights", "TailLights" },
	clips = {},
	budget = { tris = 10000, bones = 0 },
	hitbox = { kind = "box", size = { 2.35 * 2.5, 2.04 * 2.5, 4.45 * 2.5 } },
} :: Contract

local SPECIES_ORDER = { "squirrel", "rodent", "fox", "deer", "human", "drone", "car" }

function RigSpec.species(): { string }
	return table.clone(SPECIES_ORDER)
end

function RigSpec.get(id: string): Contract
	local c = (RigSpec :: any)[id]
	if type(c) ~= "table" or c.id ~= id then
		error(`RigSpec: no contract for {id}`)
	end
	return c :: Contract
end

-- Validate a Model (or any Instance tree) against a contract. A bone is satisfied by a Motor6D or
-- Bone of that name (a puppet's joint or a skinned rig's bone); a socket by an Attachment; a region
-- or part by a BasePart. Works under Lune with @lune/roblox instances (same ClassName/IsA surface).
function RigSpec.validate(model: Instance, speciesId: string?): Report
	local id = speciesId or (model:GetAttribute("Species") :: string?) or model.Name
	local contract = RigSpec.get(id)
	local joints: { [string]: boolean } = {}
	local attachments: { [string]: boolean } = {}
	local parts: { [string]: boolean } = {}
	local found = 0
	for _, inst in model:GetDescendants() do
		found += 1
		if inst:IsA("Motor6D") or inst:IsA("Bone") then
			joints[inst.Name] = true
		elseif inst:IsA("Attachment") then
			attachments[inst.Name] = true
		elseif inst:IsA("BasePart") then
			parts[inst.Name] = true
		end
	end
	local function missing(list: { string }, present: { [string]: boolean }): { string }
		local out = {}
		for _, name in list do
			if not present[name] then
				table.insert(out, name)
			end
		end
		return out
	end
	local report: Report = {
		ok = false,
		species = id,
		missingBones = missing(contract.bones, joints),
		missingSockets = missing(contract.sockets, attachments),
		missingRegions = missing(contract.regions, parts),
		missingParts = missing(contract.parts or {}, parts),
		primaryPartOk = parts[contract.primaryPart] == true,
		found = found,
	}
	report.ok = report.primaryPartOk
		and #report.missingBones == 0
		and #report.missingSockets == 0
		and #report.missingRegions == 0
		and #report.missingParts == 0
	return report
end

return RigSpec
