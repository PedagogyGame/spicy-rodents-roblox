--!strict
-- ReplicatedStorage.Shared.Avatar.PuppetSpec
-- Part-built placeholder puppets with the FINAL RigSpec names (BUILD_PLAN §4.4 W1 #10, §5.2, D22):
-- squirrel, rodent, fox, deer (doe/buck/fawn), drone and a block R15 human in a role palette.
-- Interface: spec(species, opts?) -> PartBuilder.ModelSpec; SPECIES; human(role, index) -> ModelSpec;
--            addHumanSockets(model, lib) (engine R15 from CreateHumanoidModelFromDescription).
--
-- Every RigSpec bone is a Motor6D whose Part1 is a part of the same name (the torso chain hides inside
-- the Body region, legs, neck, head and tail are visible), joined parent to child the way the skinned
-- skeleton is, so the procedural backend and the clips address the same joints on puppets and rigs.
-- The Root bone joins RootPart to a hidden Pelvis. Regions (Body, Pattern, Eyes, FurCards, Blood) are
-- welded parts; sockets are Attachments. RootPart sits at the body centre; HipHeight (attribute) is its
-- height above the ground. Authored facing is -Z. Sizes in studs, matched to the RigSpec hitboxes
-- (squirrel 1.2 st at the shoulder, brief v2 §15 default).

local PartBuilder = require("./PartBuilder")
local RigSpec = require("../Actors/RigSpec")
local RolePalettes = require("./RolePalettes")

type ModelSpec = PartBuilder.ModelSpec
type PartSpec = PartBuilder.PartSpec
type JointSpec = PartBuilder.JointSpec
type AttachmentSpec = PartBuilder.AttachmentSpec

export type Opts = { variant: string?, name: string?, index: number?, role: string? }

type Animal = {
	bodyL: number,
	bodyH: number,
	bodyW: number,
	legL: number,
	head: number,
	necks: { string },
	neckRise: number,
	tailN: number,
	tailR: number,
	tailSpan: number,
	tailThick: number,
	fur: string,
	pattern: string,
	eyes: string,
	furCards: boolean,
	blood: boolean,
}

local hex = PartBuilder.hex

local PuppetSpec = {}

PuppetSpec.SPECIES = { "squirrel", "rodent", "fox", "deer", "drone", "human" }

-- stylua: ignore
local ANIMALS: { [string]: Animal } = {
	squirrel = { bodyL = 1.6, bodyH = 0.7, bodyW = 0.7, legL = 0.55, head = 0.6, necks = { "Neck" }, neckRise = 0.15,
	             tailN = 8, tailR = 0.75, tailSpan = 0.85 * math.pi, tailThick = 0.38,
	             fur = "#b78453", pattern = "#e6d3b3", eyes = "#1d1a17", furCards = true, blood = false },
	rodent = { bodyL = 1.6, bodyH = 0.7, bodyW = 0.7, legL = 0.55, head = 0.6, necks = { "Neck" }, neckRise = 0.15,
	           tailN = 8, tailR = 0.75, tailSpan = 0.85 * math.pi, tailThick = 0.38,
	           fur = "#83544d", pattern = "#c9a38c", eyes = "#b0242a", furCards = true, blood = true },
	fox = { bodyL = 3.0, bodyH = 1.1, bodyW = 1.0, legL = 1.5, head = 0.9, necks = { "Neck" }, neckRise = 0.6,
	        tailN = 6, tailR = 3.2, tailSpan = 0.3 * math.pi, tailThick = 0.6,
	        fur = "#b8663c", pattern = "#efe6da", eyes = "#2a1d12", furCards = true, blood = false },
	deer = { bodyL = 4.2, bodyH = 1.8, bodyW = 1.5, legL = 2.9, head = 1.1, necks = { "Neck1", "Neck2", "Neck3" }, neckRise = 2.4,
	         tailN = 2, tailR = 0.6, tailSpan = 0.35 * math.pi, tailThick = 0.35,
	         fur = "#ad845e", pattern = "#eadfcc", eyes = "#1a1512", furCards = false, blood = false },
}

local function scaleAnimal(a: Animal, k: number): Animal
	local out = table.clone(a)
	for _, key in { "bodyL", "bodyH", "bodyW", "legL", "head", "neckRise", "tailR", "tailThick" } do
		(out :: any)[key] = (a :: any)[key] * k
	end
	return out
end

local function animal(species: string, opts: Opts): ModelSpec
	local contract = RigSpec.get(species)
	local base = ANIMALS[species] or error(`PuppetSpec: no animal {species}`)
	local variant = opts.variant
	local k = 1
	if contract.scaleVariants and variant then
		k = contract.scaleVariants[variant] or error(`PuppetSpec: {species} has no variant {variant}`)
	end
	local a = scaleAnimal(base, k)
	local fur, pattern, eyes = hex(a.fur), hex(a.pattern), hex(a.eyes)
	local parts: { PartSpec } = {}
	local joints: { JointSpec } = {}
	local attachments: { AttachmentSpec } = {}
	local function part(
		name: string,
		size: { number },
		pos: { number },
		color: PartBuilder.Rgb,
		extra: { [string]: any }?
	)
		local p: any = { name = name, size = size, pos = pos, color = color }
		for key, v in extra or {} do
			p[key] = v
		end
		table.insert(parts, p)
	end
	local function motor(name: string, part0: string, at: { number }?)
		table.insert(joints, { name = name, kind = "Motor6D", part0 = part0, part1 = name, at = at })
	end
	local function weld(name: string, part0: string)
		table.insert(joints, { name = `{name}Weld`, kind = "Weld", part0 = part0, part1 = name })
	end
	local L, H, W = a.bodyL, a.bodyH, a.bodyW
	local hip = a.legL + H / 2
	local hidden = { transparency = 1 }
	local thin = math.max(0.1, W * 0.25)
	part("RootPart", { W, H, L }, { 0, 0, 0 }, fur, hidden)
	-- torso chain (hidden inside the Body region), back (+Z) to front (-Z)
	local chain = {
		{ "Pelvis", 0.45 },
		{ "Hips", 0.35 },
		{ "Spine1", 0.18 },
		{ "Spine2", 0.0 },
		{ "Spine3", -0.18 },
		{ "Chest", -0.35 },
	}
	local prev = "RootPart"
	for _, c in chain do
		local name, f = c[1] :: string, c[2] :: number
		part(name, { thin, thin, thin }, { 0, 0, L * f }, fur, hidden)
		if name == "Pelvis" then
			table.insert(joints, { name = "Root", kind = "Motor6D", part0 = "RootPart", part1 = "Pelvis" })
		else
			motor(name, prev)
		end
		prev = name
	end
	part("Body", { W, H, L }, { 0, 0, 0 }, fur)
	weld("Body", "Spine2")
	part("Pattern", { W * 0.7, H * 0.12, L * 0.7 }, { 0, -H / 2 - 0.01, -L * 0.05 }, pattern)
	weld("Pattern", "Spine2")
	-- neck chain rising forward from the chest
	local n = #a.necks
	local nx, ny, nz = 0, H * 0.3, -L * 0.45
	prev = "Chest"
	for i, name in a.necks do
		local y = ny + a.neckRise * (i - 0.5) / n
		local z = nz - a.head * 0.25 * i / n
		part(name, { W * 0.35, a.neckRise / n + W * 0.2, W * 0.35 }, { nx, y, z }, fur)
		motor(name, prev, { nx, ny + a.neckRise * (i - 1) / n, z })
		prev = name
	end
	local hy = ny + a.neckRise + a.head * 0.4
	local hz = nz - a.head * 0.55
	part("Head", { a.head * 0.85, a.head * 0.8, a.head }, { 0, hy, hz }, fur)
	motor("Head", prev, { 0, ny + a.neckRise, nz - a.head * 0.25 })
	part("Jaw", { a.head * 0.5, a.head * 0.22, a.head * 0.45 }, { 0, hy - a.head * 0.42, hz - a.head * 0.3 }, pattern)
	motor("Jaw", "Head")
	part("Eyes", { a.head * 0.7, a.head * 0.16, a.head * 0.1 }, { 0, hy + a.head * 0.12, hz - a.head * 0.5 }, eyes)
	weld("Eyes", "Head")
	for _, side in { { "EarL", -1 }, { "EarR", 1 } } do
		local name, sx = side[1] :: string, side[2] :: number
		part(
			name,
			{ a.head * 0.18, a.head * 0.4, a.head * 0.12 },
			{ sx * a.head * 0.28, hy + a.head * 0.55, hz + a.head * 0.1 },
			fur
		)
		motor(name, "Head")
	end
	if a.blood then
		part(
			"Blood",
			{ a.head * 0.52, a.head * 0.08, a.head * 0.3 },
			{ 0, hy - a.head * 0.3, hz - a.head * 0.42 },
			hex("#8e1b1b")
		)
		weld("Blood", "Jaw")
	end
	-- tail: an arc rising up and back from the hips (+Z)
	prev = "Hips"
	local tx, ty, tz = 0, H * 0.1, L / 2
	for i = 1, a.tailN do
		local ang = a.tailSpan * (i - 0.5) / a.tailN
		local px, py, pz = 0, ty + a.tailR * (1 - math.cos(ang)), tz + a.tailR * math.sin(ang)
		local seg = a.tailR * a.tailSpan / a.tailN
		local thick = a.tailThick * (1 - 0.25 * (i - 1) / math.max(1, a.tailN - 1))
		part(`Tail{i}`, { thick, thick, math.max(seg, thick) }, { px, py, pz }, fur, { pitch = -ang })
		local ja = a.tailSpan * (i - 1) / a.tailN
		motor(`Tail{i}`, prev, { tx, ty + a.tailR * (1 - math.cos(ja)), tz + a.tailR * math.sin(ja) })
		prev = `Tail{i}`
	end
	local tipAng = a.tailSpan
	local tip = { 0, ty + a.tailR * (1 - math.cos(tipAng)), tz + a.tailR * math.sin(tipAng) }
	if a.furCards then
		local mid = math.max(1, math.floor(a.tailN / 2))
		local ang = a.tailSpan * 0.6
		part("FurCards", { a.tailThick * 1.6, a.tailThick * 0.5, a.tailR * a.tailSpan * 0.6 }, {
			0,
			ty + a.tailR * (1 - math.cos(ang)),
			tz + a.tailR * math.sin(ang),
		}, fur, { pitch = -ang, transparency = 0.2 })
		weld("FurCards", `Tail{mid}`)
	end
	-- legs: Upper / Lower / Foot / Toe stacked under shoulders (Chest) and hips (Hips)
	local legW = math.max(0.12, W * 0.22)
	local fractions = { Upper = 0.42, Lower = 0.36, Foot = 0.16, Toe = 0.06 }
	for _, leg in { { "FrontL", -1, -1 }, { "FrontR", 1, -1 }, { "BackL", -1, 1 }, { "BackR", 1, 1 } } do
		local name, sx, sz = leg[1] :: string, leg[2] :: number, leg[3] :: number
		local x, z = sx * W * 0.3, sz * L * 0.36
		local y = -H / 2 + H * 0.1
		prev = if sz < 0 then "Chest" else "Hips"
		for _, seg in { "Upper", "Lower", "Foot", "Toe" } do
			local len = (a.legL + H * 0.1) * fractions[seg]
			local bone = `{name}_{seg}`
			local size = if seg == "Toe" then { legW * 1.1, len, legW * 1.6 } else { legW, len, legW }
			part(bone, size, { x, y - len / 2, if seg == "Toe" then z - legW * 0.3 else z }, fur)
			motor(bone, prev, { x, y, z })
			prev = bone
			y -= len
		end
	end
	table.insert(attachments, { name = "HeadSocket", part = "Head", pos = { 0, hy + a.head * 0.42, hz } })
	table.insert(
		attachments,
		{ name = "MouthSocket", part = "Jaw", pos = { 0, hy - a.head * 0.42, hz - a.head * 0.55 } }
	)
	table.insert(attachments, { name = "TailTip", part = `Tail{a.tailN}`, pos = tip })
	table.insert(attachments, { name = "ChestCenter", part = "Chest", pos = { 0, 0, -L * 0.35 } })
	local name = opts.name or (if variant then `{species}_{variant}` else species)
	return {
		name = name,
		species = species,
		primary = "RootPart",
		parts = parts,
		joints = joints,
		attachments = attachments,
		attributes = { HipHeight = hip, Variant = variant or "", ShoulderHeight = a.legL + H },
	}
end

local function drone(opts: Opts): ModelSpec
	local body = hex("#2e3338")
	local parts: { PartSpec } = {
		{ name = "RootPart", size = { 2.0, 0.8, 2.0 }, pos = { 0, 0, 0 }, color = body },
		{
			name = "Lens",
			size = { 0.35, 0.35, 0.35 },
			pos = { 0, -0.45, -0.7 },
			color = hex("#111417"),
			shape = "Ball",
		},
	}
	local joints: { JointSpec } = { { name = "LensWeld", kind = "Weld", part0 = "RootPart", part1 = "Lens" } }
	for i, c in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
		local name = `Rotor{i}`
		table.insert(parts, {
			name = name,
			size = { 0.08, 1.1, 1.1 },
			pos = { c[1] * 1.15, 0.45, c[2] * 1.15 },
			color = hex("#9aa3a8"),
			shape = "Cylinder",
			roll = math.pi / 2, -- axis up
			transparency = 0.3,
		})
		table.insert(joints, { name = name, kind = "Motor6D", part0 = "RootPart", part1 = name })
	end
	return {
		name = opts.name or "drone",
		species = "drone",
		primary = "RootPart",
		parts = parts,
		joints = joints,
		attachments = { { name = "Camera", part = "RootPart", pos = { 0, -0.45, -0.7 } } },
		attributes = { HipHeight = 0 },
	}
end

-- Block R15 (RigSpec.human part and Motor6D names; Roblox's own attachment names plus our sockets).
-- stylua: ignore
local R15 = {
	{ "LowerTorso", { 2, 0.4, 1 }, { 0, -0.2, 0 }, "Root", "HumanoidRootPart", "pants" },
	{ "UpperTorso", { 2, 1.6, 1 }, { 0, 0.8, 0 }, "Waist", "LowerTorso", "shirt" },
	{ "Head", { 1.2, 1.2, 1.2 }, { 0, 2.2, 0 }, "Neck", "UpperTorso", "skin" },
	{ "LeftUpperArm", { 1, 1.2, 1 }, { -1.5, 1.0, 0 }, "LeftShoulder", "UpperTorso", "shirt" },
	{ "LeftLowerArm", { 1, 1.2, 1 }, { -1.5, -0.2, 0 }, "LeftElbow", "LeftUpperArm", "skin" },
	{ "LeftHand", { 1, 0.4, 1 }, { -1.5, -1.0, 0 }, "LeftWrist", "LeftLowerArm", "skin" },
	{ "RightUpperArm", { 1, 1.2, 1 }, { 1.5, 1.0, 0 }, "RightShoulder", "UpperTorso", "shirt" },
	{ "RightLowerArm", { 1, 1.2, 1 }, { 1.5, -0.2, 0 }, "RightElbow", "RightUpperArm", "skin" },
	{ "RightHand", { 1, 0.4, 1 }, { 1.5, -1.0, 0 }, "RightWrist", "RightLowerArm", "skin" },
	{ "LeftUpperLeg", { 1, 1.2, 1 }, { -0.5, -1.0, 0 }, "LeftHip", "LowerTorso", "pants" },
	{ "LeftLowerLeg", { 1, 1.2, 1 }, { -0.5, -2.2, 0 }, "LeftKnee", "LeftUpperLeg", "pants" },
	{ "LeftFoot", { 1, 0.4, 1 }, { -0.5, -3.0, 0 }, "LeftAnkle", "LeftLowerLeg", "shoe" },
	{ "RightUpperLeg", { 1, 1.2, 1 }, { 0.5, -1.0, 0 }, "RightHip", "LowerTorso", "pants" },
	{ "RightLowerLeg", { 1, 1.2, 1 }, { 0.5, -2.2, 0 }, "RightKnee", "RightUpperLeg", "pants" },
	{ "RightFoot", { 1, 0.4, 1 }, { 0.5, -3.0, 0 }, "RightAnkle", "RightLowerLeg", "shoe" },
}

-- stylua: ignore
PuppetSpec.HUMAN_SOCKETS = {
	{ name = "RightGripAttachment", part = "RightHand", pos = { 1.5, -1.1, 0 } },
	{ name = "LeftGripAttachment", part = "LeftHand", pos = { -1.5, -1.1, 0 } },
	{ name = "HairAttachment", part = "Head", pos = { 0, 2.8, 0 } },
	{ name = "BadgeAttachment", part = "UpperTorso", pos = { -0.5, 1.2, -0.5 } },
	{ name = "MaskAttachment", part = "Head", pos = { 0, 2.2, -0.6 } },
	{ name = "ChestRigAttachment", part = "UpperTorso", pos = { 0, 0.8, -0.5 } },
	{ name = "PadAttachmentL", part = "LeftUpperArm", pos = { -1.5, 1.6, 0 } },
	{ name = "PadAttachmentR", part = "RightUpperArm", pos = { 1.5, 1.6, 0 } },
}

function PuppetSpec.human(role: string, index: number, lib: { Instance: any, Color3: any }?): ModelSpec
	local look = RolePalettes.look(role, index)
	local colors = { skin = look.skin, shirt = look.shirt, pants = look.pants, shoe = hex("#2f3431") }
	local parts: { PartSpec } = {
		{ name = "HumanoidRootPart", size = { 2, 2, 1 }, pos = { 0, 0, 0 }, color = look.shirt, transparency = 1 },
	}
	local joints: { JointSpec } = {}
	for _, r in R15 do
		local name, size, pos, joint, parent, tone = r[1], r[2], r[3], r[4], r[5], r[6]
		table.insert(
			parts,
			{ name = name :: string, size = size :: { number }, pos = pos :: { number }, color = (colors :: any)[tone] }
		)
		table.insert(
			joints,
			{ name = joint :: string, kind = "Motor6D", part0 = parent :: string, part1 = name :: string }
		)
	end
	if look.cap then
		table.insert(parts, { name = "Cap", size = { 1.3, 0.3, 1.4 }, pos = { 0, 2.95, -0.05 }, color = look.cap })
		table.insert(joints, { name = "CapWeld", kind = "Weld", part0 = "Head", part1 = "Cap" })
	end
	local children = {
		{ className = "Humanoid", name = "Humanoid", props = { HipHeight = 2.0 } },
	}
	if lib then
		table.insert(children, {
			className = "HumanoidDescription",
			name = "StockDescription",
			props = (function()
				local props = {}
				for prop, c in RolePalettes.descriptionProps(look) do
					props[prop] = lib.Color3.new(c.r, c.g, c.b)
				end
				return props
			end)(),
		})
	end
	return {
		name = `human_{role}_{index}`,
		species = "human",
		primary = "HumanoidRootPart",
		parts = parts,
		joints = joints,
		attachments = table.clone(PuppetSpec.HUMAN_SOCKETS),
		children = children,
		attributes = { Role = role, HipHeight = 3.0 },
	}
end

function PuppetSpec.spec(species: string, opts: Opts?): ModelSpec
	local o = opts or {}
	if ANIMALS[species] then
		return animal(species, o)
	elseif species == "drone" then
		return drone(o)
	elseif species == "human" then
		return PuppetSpec.human(o.role or "townsperson", o.index or 1)
	end
	error(`PuppetSpec: unknown species {species}`)
end

-- finishStockR15(model, lib): engine R15s from CreateHumanoidModelFromDescription arrive with Roblox's rig
-- attachments but, where no simulation runs (Luau Execution, a model not yet stepped), without their
-- Motor6Ds; Humanoid:BuildRigFromAttachments makes them (named Root, Waist, Neck, ... as RigSpec.human
-- expects). Then our custom sockets are added. Returns the number of sockets added.
function PuppetSpec.finishStockR15(model: any, lib: { Instance: any, CFrame: any }): number
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local lower = model:FindFirstChild("LowerTorso")
	if humanoid and not (lower and lower:FindFirstChild("Root")) then
		pcall(function()
			humanoid:BuildRigFromAttachments()
		end)
	end
	-- any joint still missing is made from the matching <Joint>RigAttachment pair (deterministic)
	local converted: { [string]: number } = {}
	for _, r in R15 do
		local name, joint, parentName = r[1] :: string, r[4] :: string, r[5] :: string
		local part1, part0 = model:FindFirstChild(name), model:FindFirstChild(parentName)
		local existing = if part1 then part1:FindFirstChild(joint) else nil
		if existing and not existing:IsA("Motor6D") then
			-- the avatar joint upgrade builds AnimationConstraints (plus ball sockets) under these names;
			-- AI and puppet bodies drive Motor6Ds (HANDOFF rule 4), so swap the joint for a Motor6D
			converted[existing.ClassName] = (converted[existing.ClassName] or 0) + 1
			existing:Destroy()
			existing = nil
		end
		if part1 and part0 and not existing then
			local a0 = part0:FindFirstChild(`{joint}RigAttachment`)
			local a1 = part1:FindFirstChild(`{joint}RigAttachment`)
			local m = lib.Instance.new("Motor6D")
			m.Name = joint
			m.Part0 = part0
			m.Part1 = part1
			m.C0 = if a0 then a0.CFrame else lib.CFrame.new()
			m.C1 = if a1 then a1.CFrame else lib.CFrame.new()
			m.Parent = part1
		end
	end
	for className, n in converted do
		model:SetAttribute(`Converted{className}`, n)
	end
	return PuppetSpec.addHumanSockets(model, lib)
end

-- Engine R15s from CreateHumanoidModelFromDescription carry Roblox's attachments but not our custom
-- sockets (Badge, Mask, ChestRig, Pads): add whichever are missing, at the block-R15 offsets.
function PuppetSpec.addHumanSockets(model: any, lib: { Instance: any, CFrame: any }): number
	local added = 0
	for _, s in PuppetSpec.HUMAN_SOCKETS do
		local host = model:FindFirstChild(s.part)
		if host and not host:FindFirstChild(s.name) then
			local ref = nil
			for _, r in R15 do
				if r[1] == s.part then
					ref = r[3] :: { number }
				end
			end
			local o = ref or { 0, 0, 0 }
			local att = lib.Instance.new("Attachment")
			att.Name = s.name
			att.CFrame = lib.CFrame.new(s.pos[1] - o[1], s.pos[2] - o[2], s.pos[3] - o[3])
			att.Parent = host
			added += 1
		end
	end
	return added
end

return PuppetSpec
