--!strict
-- ReplicatedStorage.Shared.Avatar.PuppetSpec
-- Part-built placeholder puppets with the FINAL RigSpec names (BUILD_PLAN §4.4 W1 #10, §5.2, D22):
-- squirrel, rodent, fox, deer (doe/buck/fawn), drone and a block R15 human in a role palette.
-- Interface: spec(species, opts?) -> PartBuilder.ModelSpec; SPECIES; PALETTES; STOCK_LOOKS;
--            human(role, index) -> ModelSpec; addHumanSockets(model, lib) (engine R15 from
--            CreateHumanoidModelFromDescription); finishStockR15(model, lib).
--
-- Every RigSpec bone is a Motor6D whose Part1 is a part of the same name, joined parent to child the
-- way the skinned skeleton is, so the procedural gait (Client/Animation/Gait) and the clips address the
-- same joints on puppets and rigs. The Root bone joins RootPart (hidden, anchored, the only queryable
-- part) to Pelvis at the body centre. Animals are modelled from overlapping Ball and Cylinder parts so
-- they read as animals from the third-person camera (owner playtest 2026-11-09: "a stack of brown
-- bricks"): the spine bones are the rounded torso around a capsule Body, the neck and head are balls,
-- the eyes are one dark cylinder through the head whose ends show on both sides, the ears are thin
-- diamonds, the tail is a chain of growing balls along an S-curve (squirrel) or a brush (fox), and the
-- legs are slim cylinders (thigh balls on the hind legs) ending in a flat toe pad on the ground.
-- Regions (Body, Pattern, Eyes, FurCards, Blood) are welded or bone parts with those names; the other
-- fur parts carry a `Region` attribute so the avatar blend can shade them with their region.
-- RootPart sits at the body centre; HipHeight (attribute) is its height above the ground and the
-- bottom of every toe pad is exactly there (nothing else reaches lower). Authored facing is -Z.
-- Sizes in studs, matched to the RigSpec hitboxes (squirrel 1.25 st at the shoulder, brief v2 §15).
-- Every visual part is non-colliding, CanTouch and CanQuery false (PartBuilder); part counts stay at
-- about 40 per animal (the bones alone are 36 for a squirrel).

local PartBuilder = require("./PartBuilder")
local RigSpec = require("../Actors/RigSpec")
local RolePalettes = require("./RolePalettes")

type ModelSpec = PartBuilder.ModelSpec
type PartSpec = PartBuilder.PartSpec
type JointSpec = PartBuilder.JointSpec
type AttachmentSpec = PartBuilder.AttachmentSpec

export type Opts = { variant: string?, name: string?, index: number?, role: string? }

local hex = PartBuilder.hex

local PuppetSpec = {}

PuppetSpec.SPECIES = { "squirrel", "rodent", "fox", "deer", "drone", "human" }

-- Palettes (hex). Regular squirrels wear a fox squirrel's rust back and cream belly; the spicy rodent is
-- the same animal gone feral: mangy dark umber fur, bald patches, oversized glowing red eyes, buck teeth
-- and a little red at the muzzle (natural colours, no green, mild rating: BUILD_PLAN §5.6). The red fox
-- has black socks and a white tail tip; the white-tailed deer a white belly, throat and tail flag.
-- stylua: ignore
PuppetSpec.PALETTES = {
	squirrel = { fur = "#9a5a32", back = "#82492a", head = "#93552f", tail = "#a3643a", fringe = "#c99560",
	             belly = "#e4c9a0", muzzle = "#d8b98f", ear = "#8a4e2c", foot = "#6b3d23", eyes = "#121010" },
	rodent = { fur = "#4b372b", back = "#3b2a20", head = "#45322a", tail = "#503b2e", fringe = "#5f4838",
	           belly = "#77655a", muzzle = "#6b5446", ear = "#4f3a2e", foot = "#33261e", eyes = "#ff2a1a",
	           mange = "#8f726a", blood = "#7a1414", teeth = "#e9dfbd" },
	fox = { fur = "#c4622d", back = "#b2552a", tail = "#c0602f", fringe = "#d27a45", white = "#f2ede4",
	        shin = "#5a3020", legs = "#2c2320", ear = "#7d3b1e", nose = "#141110", eyes = "#2a1a0e" },
	deer = { fur = "#a8784c", back = "#93673f", belly = "#efe7d8", legs = "#9a6e46", hoof = "#2a221d",
	         nose = "#1b1613", eyes = "#15110e", tail = "#8b6440", flag = "#f4efe6", antler = "#d8c8a8",
	         spots = "#f3ead9" },
	buck = { fur = "#9a6c43", back = "#86603a" },
	fawn = { fur = "#b8854f", back = "#a3743f" },
} :: { [string]: { [string]: string } }

-- The species stock looks the avatar blend starts from (Server/Avatar/AvatarBlendService.STOCK).
PuppetSpec.STOCK_LOOKS = {
	squirrel = { body = "#9a5a32", pattern = "#e4c9a0", eyes = "#121010", eyesLocked = false },
	rodent = { body = "#4b372b", pattern = "#77655a", eyes = "#ff2a1a", eyesLocked = true },
	fox = { body = "#c4622d", pattern = "#f2ede4", eyes = "#2a1a0e", eyesLocked = false },
	deer = { body = "#a8784c", pattern = "#efe7d8", eyes = "#15110e", eyesLocked = false },
} :: { [string]: { body: string, pattern: string, eyes: string, eyesLocked: boolean } }

-- Builder ------------------------------------------------------------------------------------------

type Extra = {
	region: string?, -- Region attribute (the avatar blend shades the part with that region)
	material: string?,
	transparency: number?,
	reflectance: number?,
	yaw: number?,
	pitch: number?,
	roll: number?,
	overlap: number?, -- cylinders: how far past each end point the ends reach, in diameters (default 0.3)
}

type Builder = {
	parts: { PartSpec },
	joints: { JointSpec },
	attachments: { AttachmentSpec },
	ball: (name: string, d: number, pos: { number }, color: string, extra: Extra?) -> (),
	cyl: (name: string, a: { number }, b: { number }, d: number, color: string, extra: Extra?) -> (),
	block: (name: string, size: { number }, pos: { number }, color: string, extra: Extra?) -> (),
	motor: (name: string, part0: string, at: { number }?) -> (),
	weld: (name: string, part0: string) -> (),
	socket: (name: string, part: string, pos: { number }) -> (),
}

local FUR: Extra = { region = "Body" }
local CREAM: Extra = { region = "Pattern" }

-- newBuilder(k): every position and size is multiplied by k (the deer's doe/buck/fawn scale).
local function newBuilder(k: number): Builder
	local parts: { PartSpec } = {}
	local joints: { JointSpec } = {}
	local attachments: { AttachmentSpec } = {}
	local function sc(v: { number }): { number }
		return { v[1] * k, v[2] * k, v[3] * k }
	end
	local function add(name: string, shape: string, size: { number }, pos: { number }, color: string, extra: Extra?)
		local e: Extra = extra or {}
		local p: PartSpec = {
			name = name,
			size = size,
			pos = pos,
			color = hex(color),
			shape = shape,
			yaw = e.yaw,
			pitch = e.pitch,
			roll = e.roll,
			material = e.material,
			transparency = e.transparency,
			reflectance = e.reflectance,
			attributes = if e.region then { Region = e.region } else nil,
		}
		table.insert(parts, p)
	end
	local b: Builder = {
		parts = parts,
		joints = joints,
		attachments = attachments,
		ball = function(name: string, d: number, pos: { number }, color: string, extra: Extra?)
			add(name, "Ball", { d * k, d * k, d * k }, sc(pos), color, extra)
		end,
		-- a cylinder from p0 to p1 (studs); local X is the axis, so roll pi/2 turns it to +Y, pitch tilts
		-- it toward +Z and yaw swings it toward +X; the ends reach past p0 and p1 by `overlap` diameters
		cyl = function(name: string, p0: { number }, p1: { number }, d: number, color: string, extra: Extra?)
			local dx, dy, dz = p1[1] - p0[1], p1[2] - p0[2], p1[3] - p0[3]
			local len = math.sqrt(dx * dx + dy * dy + dz * dz)
			local ux, uy, uz = dx / len, dy / len, dz / len
			local e: Extra = table.clone(extra or {})
			e.roll = math.pi / 2
			e.pitch = math.acos(math.clamp(uy, -1, 1))
			e.yaw = if math.abs(ux) + math.abs(uz) > 1e-9 then math.atan2(ux, uz) else 0
			local mid = { (p0[1] + p1[1]) / 2, (p0[2] + p1[2]) / 2, (p0[3] + p1[3]) / 2 }
			local over = 2 * (e.overlap or 0.3) * d
			add(name, "Cylinder", { (len + over) * k, d * k, d * k }, sc(mid), color, e)
		end,
		block = function(name: string, size: { number }, pos: { number }, color: string, extra: Extra?)
			add(name, "Block", sc(size), sc(pos), color, extra)
		end,
		motor = function(name: string, part0: string, at: { number }?)
			table.insert(
				joints,
				{ name = name, kind = "Motor6D", part0 = part0, part1 = name, at = if at then sc(at) else nil }
			)
		end,
		weld = function(name: string, part0: string)
			table.insert(joints, { name = `{name}Weld`, kind = "Weld", part0 = part0, part1 = name })
		end,
		socket = function(name: string, part: string, pos: { number })
			table.insert(attachments, { name = name, part = part, pos = sc(pos) })
		end,
	}
	return b
end

-- The torso chain: Root joins RootPart to Pelvis at the body centre (the gait's bob and rock pivot
-- there), then Pelvis -> Hips -> Spine1 -> Spine2 -> Spine3 -> Chest, each joint at its own ball.
type Ball = { d: number, pos: { number }, color: string, extra: Extra? }
local function torso(b: Builder, chain: { [string]: Ball })
	local prev = "RootPart"
	for _, name in { "Pelvis", "Hips", "Spine1", "Spine2", "Spine3", "Chest" } do
		local s = chain[name]
		b.ball(name, s.d, s.pos, s.color, s.extra or FUR)
		if name == "Pelvis" then
			b.motor("Root", "RootPart", { 0, 0, 0 })
			-- the Root bone's Part1 is Pelvis (RigSpec: the Motor6D carries the bone name)
			b.joints[#b.joints].part1 = "Pelvis"
		else
			b.motor(name, prev)
		end
		prev = name
	end
end

-- A tail along headings in degrees from +Z (back) toward +Y (up), one ball per segment centred on it,
-- the joint at the segment's start. Returns the tip point (the TailTip socket).
local function tail(
	b: Builder,
	start: { number },
	headings: { number },
	seg: number,
	diams: { number },
	colors: { string }
): { number }
	local y, z = start[2], start[3]
	local prev = "Hips"
	for i, deg in headings do
		local a = math.rad(deg)
		local ny, nz = y + math.sin(a) * seg, z + math.cos(a) * seg
		local name = `Tail{i}`
		b.ball(name, diams[i], { 0, (y + ny) / 2, (z + nz) / 2 }, colors[i], FUR)
		b.motor(name, prev, { 0, y, z })
		prev = name
		y, z = ny, nz
	end
	return { 0, y, z }
end

-- One leg: points P1..P5 as {y, z} (shoulder or hip, elbow or knee, wrist or ankle, toe joint, toe tip
-- on the ground); slim cylinders between them (or a thigh ball for Upper), and a flat toe pad whose
-- bottom is the ground. Joints sit at the segment starts.
type Leg = {
	pts: { { number } },
	d: { number }, -- Upper, Lower, Foot diameters
	thigh: { number }?, -- { d, y, z }: a ball for Upper (hind legs)
	toe: { number }, -- pad { width, height, length }
	colors: { string }, -- Upper, Lower, Foot, Toe
}
local function leg(b: Builder, name: string, x: number, parent: string, def: Leg)
	local p = def.pts
	local function at(i: number): { number }
		return { x, p[i][1], p[i][2] }
	end
	local thigh = def.thigh
	if thigh then
		b.ball(`{name}_Upper`, thigh[1], { x, thigh[2], thigh[3] }, def.colors[1], FUR)
	else
		b.cyl(`{name}_Upper`, at(1), at(2), def.d[1], def.colors[1], FUR)
	end
	b.motor(`{name}_Upper`, parent, at(1))
	b.cyl(`{name}_Lower`, at(2), at(3), def.d[2], def.colors[2], FUR)
	b.motor(`{name}_Lower`, `{name}_Upper`, at(2))
	b.cyl(`{name}_Foot`, at(3), at(4), def.d[3], def.colors[3], FUR)
	b.motor(`{name}_Foot`, `{name}_Lower`, at(3))
	local toe = def.toe
	b.block(`{name}_Toe`, toe, { x, p[5][1] + toe[2] / 2, (p[4][2] + p[5][2]) / 2 }, def.colors[4], FUR)
	b.motor(`{name}_Toe`, `{name}_Foot`, at(4))
end

local function mirrored(b: Builder, side: string, x: number, parent: string, def: Leg)
	leg(b, `{side}L`, -x, parent, def)
	leg(b, `{side}R`, x, parent, def)
end

local function finish(
	b: Builder,
	species: string,
	name: string,
	variant: string?,
	hip: number,
	shoulder: number
): ModelSpec
	return {
		name = name,
		species = species,
		primary = "RootPart",
		parts = b.parts,
		joints = b.joints,
		attachments = b.attachments,
		attributes = { HipHeight = hip, Variant = variant or "", ShoulderHeight = shoulder },
	}
end

-- Squirrel and spicy rodent ----------------------------------------------------------------------------

local function squirrel(species: string, opts: Opts): ModelSpec
	local rodent = species == "rodent"
	local c = PuppetSpec.PALETTES[species]
	local b = newBuilder(1)
	local HIP = 0.9
	local G = -HIP
	local arch = if rodent then 0.05 else 0 -- the rodent hunches
	local mange: Extra = { region = "Body", material = "Sand" }
	b.block("RootPart", { 0.66, 0.66, 1.4 }, { 0, 0, 0 }, c.fur, { transparency = 1 })
	torso(b, {
		Pelvis = { d = 0.48, pos = { 0, 0.1 + arch, 0.5 }, color = c.back },
		Hips = { d = 0.66, pos = { 0, 0, 0.3 }, color = c.fur },
		Spine1 = {
			d = 0.6,
			pos = { if rodent then 0.05 else 0, 0.06 + arch * 1.5, 0.1 },
			color = if rodent then c.mange else c.back,
			extra = if rodent then mange else nil,
		},
		Spine2 = { d = 0.56, pos = { 0, 0.06 + arch, -0.08 }, color = c.back },
		Spine3 = { d = 0.54, pos = { 0, 0.05 + arch * 0.5, -0.26 }, color = c.back },
		Chest = { d = 0.54, pos = { 0, 0.01, -0.42 }, color = c.fur },
	})
	b.cyl("Body", { 0, 0.02, 0.3 }, { 0, 0.02, -0.42 }, 0.58, c.fur)
	b.weld("Body", "Spine2")
	b.cyl("Pattern", { 0, -0.11, 0.22 }, { 0, -0.12, -0.5 }, 0.42, c.belly)
	b.weld("Pattern", "Spine2")
	-- neck, head, muzzle, the eyes through the head, diamond ears
	b.ball("Neck", 0.36, { 0, 0.2, -0.58 }, c.fur, FUR)
	b.motor("Neck", "Chest", { 0, 0.12, -0.5 })
	local hy, hz = 0.42 - arch, -0.78
	b.ball("Head", 0.5, { 0, hy, hz }, c.head, FUR)
	b.motor("Head", "Neck", { 0, hy - 0.12, -0.66 })
	b.ball("Jaw", 0.27, { 0, hy - 0.08, hz - 0.22 }, c.muzzle, CREAM)
	b.motor("Jaw", "Head", { 0, hy - 0.1, hz - 0.12 })
	-- one dark bead through the head: its ends are the two eyes (the rodent's bigger and glowing red)
	local eyeD = if rodent then 0.15 else 0.11
	local eyeHalf = if rodent then 0.255 else 0.245
	b.cyl(
		"Eyes",
		{ -eyeHalf, hy + 0.05, hz - 0.1 },
		{ eyeHalf, hy + 0.05, hz - 0.1 },
		eyeD,
		c.eyes,
		if rodent then { material = "Neon", overlap = 0 } else { reflectance = 0.15, overlap = 0 }
	)
	b.weld("Eyes", "Head")
	for _, side in { { name = "EarL", sx = -1 }, { name = "EarR", sx = 1 } } do
		local torn = rodent and side.sx > 0
		local s = if torn then 0.13 else 0.17
		local tilt = if torn then 0.5 else 0.2
		b.block(side.name, { s, s, 0.045 }, { side.sx * 0.13, hy + 0.22, hz + 0.06 }, c.ear, {
			region = "Body",
			roll = math.pi / 4 - side.sx * tilt,
			yaw = side.sx * 0.3,
		})
		b.motor(side.name, "Head", { side.sx * 0.12, hy + 0.17, hz + 0.06 })
	end
	if rodent then
		-- a little red at the corner of the mouth and crooked buck teeth (mild: no gore)
		b.ball("Blood", 0.1, { 0.08, hy - 0.15, hz - 0.27 }, c.blood)
		b.weld("Blood", "Jaw")
		b.block("Teeth", { 0.1, 0.1, 0.03 }, { 0, hy - 0.17, hz - 0.33 }, c.teeth, { roll = 0.08 })
		b.weld("Teeth", "Jaw")
	end
	-- the S-curved bushy tail: up and back from the rump, over toward the head, the tip flicked back
	local tip = tail(
		b,
		{ 0, 0.16 + arch, 0.66 },
		if rodent then { 35, 58, 80, 100, 122, 140, 118, 85 } else { 40, 62, 85, 108, 128, 135, 112, 78 },
		0.2,
		if rodent
			then { 0.2, 0.26, 0.2, 0.34, 0.36, 0.24, 0.32, 0.26 } -- ragged and thin where the fur fell out
			else { 0.24, 0.32, 0.4, 0.46, 0.5, 0.5, 0.46, 0.38 },
		{ c.tail, c.tail, c.tail, c.tail, c.tail, c.tail, c.tail, c.fringe }
	)
	-- FurCards: the frosted outer fringe on the tail's back curve
	b.ball("FurCards", if rodent then 0.32 else 0.48, if rodent then { 0, 0.82, 0.98 } else { 0, 0.8, 1.0 }, c.fringe)
	b.weld("FurCards", "Tail4")
	-- slim legs: short front legs under the chest, hind legs with a round thigh and a long foot
	mirrored(b, "Front", 0.15, "Chest", {
		pts = { { -0.05, -0.4 }, { -0.4, -0.38 }, { -0.74, -0.44 }, { -0.85, -0.46 }, { G, -0.58 } },
		d = { 0.17, 0.12, 0.11 },
		toe = { 0.13, 0.06, 0.15 },
		colors = { c.fur, c.fur, c.foot, c.foot },
	})
	mirrored(b, "Back", 0.19, "Hips", {
		pts = { { 0, 0.32 }, { -0.3, 0.26 }, { -0.62, 0.42 }, { -0.84, 0.24 }, { G, 0.08 } },
		d = { 0.2, 0.13, 0.11 },
		thigh = { 0.46, -0.12, 0.32 },
		toe = { 0.14, 0.06, 0.22 },
		colors = { c.fur, c.fur, c.foot, c.foot },
	})
	if rodent then
		-- a bald patch on the left haunch
		for _, p in b.parts do
			if p.name == "BackL_Upper" then
				p.color = hex(c.mange)
				p.material = "Sand"
			end
		end
	end
	b.socket("HeadSocket", "Head", { 0, hy + 0.25, hz })
	b.socket("MouthSocket", "Jaw", { 0, hy - 0.12, hz - 0.34 })
	b.socket("TailTip", "Tail8", tip)
	b.socket("ChestCenter", "Chest", { 0, 0.01, -0.42 })
	return finish(b, species, opts.name or species, opts.variant, HIP, HIP + 0.35)
end

-- Red fox --------------------------------------------------------------------------------------------

local function fox(opts: Opts): ModelSpec
	local c = PuppetSpec.PALETTES.fox
	local b = newBuilder(1)
	local HIP = 2.05
	local G = -HIP
	b.block("RootPart", { 1.0, 1.1, 3.0 }, { 0, 0, 0 }, c.fur, { transparency = 1 })
	torso(b, {
		Pelvis = { d = 0.8, pos = { 0, 0.12, 1.2 }, color = c.back },
		Hips = { d = 1.0, pos = { 0, 0.05, 0.85 }, color = c.fur },
		Spine1 = { d = 0.92, pos = { 0, 0.12, 0.42 }, color = c.back },
		Spine2 = { d = 0.88, pos = { 0, 0.1, 0 }, color = c.back },
		Spine3 = { d = 0.92, pos = { 0, 0.1, -0.42 }, color = c.back },
		Chest = { d = 1.0, pos = { 0, 0.02, -0.85 }, color = c.fur },
	})
	b.cyl("Body", { 0, 0.06, 0.85 }, { 0, 0.06, -0.85 }, 0.9, c.fur)
	b.weld("Body", "Spine2")
	b.ball("Pattern", 0.76, { 0, -0.1, -1.15 }, c.white) -- white chest and throat
	b.weld("Pattern", "Chest")
	b.ball("Neck", 0.68, { 0, 0.55, -1.32 }, c.fur, FUR)
	b.motor("Neck", "Chest", { 0, 0.35, -1.15 })
	local hy, hz = 0.98, -1.62
	b.ball("Head", 0.8, { 0, hy, hz }, c.fur, FUR)
	b.motor("Head", "Neck", { 0, 0.75, -1.45 })
	b.cyl("Snout", { 0, hy - 0.08, hz - 0.23 }, { 0, hy - 0.14, hz - 0.76 }, 0.32, c.fur, FUR)
	b.weld("Snout", "Head")
	b.cyl("Jaw", { 0, hy - 0.24, hz - 0.16 }, { 0, hy - 0.24, hz - 0.6 }, 0.24, c.white, CREAM)
	b.motor("Jaw", "Head", { 0, hy - 0.2, hz - 0.13 })
	b.ball("Nose", 0.17, { 0, hy - 0.13, hz - 0.8 }, c.nose)
	b.weld("Nose", "Head")
	b.cyl(
		"Eyes",
		{ -0.315, hy + 0.08, hz - 0.26 },
		{ 0.315, hy + 0.08, hz - 0.26 },
		0.12,
		c.eyes,
		{ reflectance = 0.15, overlap = 0 }
	)
	b.weld("Eyes", "Head")
	for _, side in { { name = "EarL", sx = -1 }, { name = "EarR", sx = 1 } } do
		b.block(side.name, { 0.36, 0.36, 0.07 }, { side.sx * 0.22, hy + 0.34, hz + 0.06 }, c.ear, {
			region = "Body",
			roll = math.pi / 4 - side.sx * 0.15,
			yaw = side.sx * 0.2,
		})
		b.motor(side.name, "Head", { side.sx * 0.2, hy + 0.28, hz + 0.06 })
	end
	-- a long brush held out behind, drooping a little, the tip curving up and white
	local tip = tail(
		b,
		{ 0, 0.22, 1.45 },
		{ -15, -28, -22, -8, 8, 22 },
		0.42,
		{ 0.44, 0.6, 0.7, 0.72, 0.64, 0.5 },
		{ c.tail, c.tail, c.tail, c.tail, c.tail, c.white }
	)
	b.ball("FurCards", 0.68, { 0, -0.27, 2.5 }, c.fringe)
	b.weld("FurCards", "Tail3")
	mirrored(b, "Front", 0.28, "Chest", {
		pts = { { -0.2, -0.9 }, { -0.95, -0.85 }, { -1.72, -0.92 }, { -1.93, -0.96 }, { G, -1.14 } },
		d = { 0.34, 0.2, 0.17 },
		toe = { 0.22, 0.1, 0.26 },
		colors = { c.fur, c.legs, c.legs, c.legs },
	})
	mirrored(b, "Back", 0.3, "Hips", {
		pts = { { -0.05, 0.86 }, { -0.72, 0.78 }, { -1.42, 1.08 }, { -1.9, 0.92 }, { G, 0.76 } },
		d = { 0.34, 0.24, 0.17 },
		thigh = { 0.7, -0.32, 0.86 },
		toe = { 0.22, 0.1, 0.26 },
		colors = { c.fur, c.shin, c.legs, c.legs },
	})
	b.socket("HeadSocket", "Head", { 0, hy + 0.4, hz })
	b.socket("MouthSocket", "Jaw", { 0, hy - 0.26, hz - 0.64 })
	b.socket("TailTip", "Tail6", tip)
	b.socket("ChestCenter", "Chest", { 0, 0.02, -0.85 })
	return finish(b, "fox", opts.name or "fox", opts.variant, HIP, HIP + 0.55)
end

-- White-tailed deer (doe, buck, fawn by RigSpec.deer.scaleVariants) ------------------------------------

local function deer(opts: Opts): ModelSpec
	local contract = RigSpec.get("deer")
	local variant = opts.variant
	local k = 1
	if contract.scaleVariants and variant then
		k = contract.scaleVariants[variant] or error(`PuppetSpec: deer has no variant {variant}`)
	end
	local base = PuppetSpec.PALETTES.deer
	local tint = PuppetSpec.PALETTES[variant or ""] or {}
	local c = table.clone(base)
	for key, v in tint do
		c[key] = v
	end
	local b = newBuilder(k)
	local HIP = 3.8
	local G = -HIP
	b.block("RootPart", { 1.5, 1.8, 4.2 }, { 0, 0, 0 }, c.fur, { transparency = 1 })
	torso(b, {
		Pelvis = { d = 1.35, pos = { 0, 0.32, 1.6 }, color = c.fur },
		Hips = { d = 1.7, pos = { 0, 0.1, 1.15 }, color = c.fur },
		Spine1 = { d = 1.62, pos = { 0, 0.18, 0.55 }, color = c.back },
		Spine2 = { d = 1.55, pos = { 0, 0.12, -0.05 }, color = c.back },
		Spine3 = { d = 1.62, pos = { 0, 0.12, -0.65 }, color = c.back },
		Chest = { d = 1.72, pos = { 0, 0.02, -1.2 }, color = c.fur },
	})
	b.cyl("Body", { 0, 0.06, 1.15 }, { 0, 0.06, -1.2 }, 1.58, c.fur)
	b.weld("Body", "Spine2")
	b.cyl("Pattern", { 0, -0.4, 0.9 }, { 0, -0.42, -1.1 }, 1.0, c.belly) -- white belly
	b.weld("Pattern", "Spine2")
	-- a long neck of three balls rising forward
	local necks = {
		{ name = "Neck1", d = 1.02, pos = { 0, 0.62, -1.72 }, at = { 0, 0.3, -1.5 }, parent = "Chest" },
		{ name = "Neck2", d = 0.88, pos = { 0, 1.25, -2.0 }, at = { 0, 0.95, -1.85 }, parent = "Neck1" },
		{ name = "Neck3", d = 0.76, pos = { 0, 1.85, -2.22 }, at = { 0, 1.55, -2.1 }, parent = "Neck2" },
	}
	for _, n in necks do
		b.ball(n.name, n.d, n.pos, c.fur, FUR)
		b.motor(n.name, n.parent, n.at)
	end
	local hy, hz = 2.3, -2.45
	b.ball("Head", 0.88, { 0, hy, hz }, c.fur, FUR)
	b.motor("Head", "Neck3", { 0, 2.1, -2.32 })
	b.cyl("Snout", { 0, hy - 0.08, hz - 0.25 }, { 0, hy - 0.32, hz - 0.85 }, 0.44, c.fur, FUR)
	b.weld("Snout", "Head")
	b.cyl("Jaw", { 0, hy - 0.28, hz - 0.27 }, { 0, hy - 0.44, hz - 0.73 }, 0.3, c.belly, CREAM)
	b.motor("Jaw", "Head", { 0, hy - 0.25, hz - 0.25 })
	b.ball("Nose", 0.24, { 0, hy - 0.32, hz - 0.91 }, c.nose)
	b.weld("Nose", "Head")
	b.cyl(
		"Eyes",
		{ -0.375, hy + 0.12, hz - 0.23 },
		{ 0.375, hy + 0.12, hz - 0.23 },
		0.17,
		c.eyes,
		{ reflectance = 0.15, overlap = 0 }
	)
	b.weld("Eyes", "Head")
	for _, side in { { name = "EarL", sx = -1 }, { name = "EarR", sx = 1 } } do
		b.block(side.name, { 0.52, 0.52, 0.08 }, { side.sx * 0.42, hy + 0.4, hz + 0.1 }, c.fur, {
			region = "Body",
			roll = math.pi / 4 - side.sx * 0.55,
			yaw = side.sx * 0.25,
		})
		b.motor(side.name, "Head", { side.sx * 0.3, hy + 0.3, hz + 0.1 })
	end
	if variant == "buck" then
		for _, sx in { -1, 1 } do
			local s = if sx < 0 then "L" else "R"
			local base0 = { sx * 0.16, hy + 0.38, hz + 0.03 }
			local beam = { sx * 0.6, hy + 1.2, hz - 0.2 }
			b.cyl(`Antler{s}`, base0, beam, 0.11, c.antler)
			b.weld(`Antler{s}`, "Head")
			b.cyl(
				`Antler{s}Tine`,
				{ sx * 0.4, hy + 0.82, hz - 0.1 },
				{ sx * 0.32, hy + 1.25, hz - 0.45 },
				0.08,
				c.antler
			)
			b.weld(`Antler{s}Tine`, "Head")
		end
	elseif variant == "fawn" then
		-- a few white spots along the back
		local spots = {
			{ pos = { -0.42, 0.62, 0.7 }, on = "Spine1" },
			{ pos = { 0.45, 0.6, 0.0 }, on = "Spine2" },
			{ pos = { -0.4, 0.6, -0.7 }, on = "Spine3" },
		}
		for i, s in spots do
			b.ball(`Spot{i}`, 0.34, s.pos, c.spots)
			b.weld(`Spot{i}`, s.on)
		end
	end
	-- the short tail hangs over the white rump; Tail2 is the white flag (raised when running, Gait)
	local tip = tail(b, { 0, 0.62, 2.2 }, { -55, -80 }, 0.36, { 0.42, 0.36 }, { c.tail, c.flag })
	mirrored(b, "Front", 0.42, "Chest", {
		pts = { { -0.3, -1.25 }, { -1.65, -1.2 }, { -3.0, -1.28 }, { -3.58, -1.3 }, { G, -1.48 } },
		d = { 0.5, 0.26, 0.2 },
		toe = { 0.3, 0.22, 0.34 },
		colors = { c.fur, c.legs, c.legs, c.hoof },
	})
	mirrored(b, "Back", 0.44, "Hips", {
		pts = { { -0.05, 1.2 }, { -1.05, 1.05 }, { -2.35, 1.5 }, { -3.58, 1.36 }, { G, 1.2 } },
		d = { 0.5, 0.34, 0.22 },
		thigh = { 1.05, -0.45, 1.2 },
		toe = { 0.3, 0.22, 0.34 },
		colors = { c.fur, c.legs, c.legs, c.hoof },
	})
	b.socket("HeadSocket", "Head", { 0, hy + 0.44, hz })
	b.socket("MouthSocket", "Jaw", { 0, hy - 0.46, hz - 0.78 })
	b.socket("TailTip", "Tail2", tip)
	b.socket("ChestCenter", "Chest", { 0, 0.02, -1.2 })
	local name = opts.name or (if variant then `deer_{variant}` else "deer")
	return finish(b, "deer", name, variant, HIP * k, (HIP + 0.9) * k)
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
type R15Row = { name: string, size: { number }, pos: { number }, joint: string, parent: string, tone: string }
-- stylua: ignore
local R15: { R15Row } = {
	{ name = "LowerTorso", size = { 2, 0.4, 1 }, pos = { 0, -0.2, 0 }, joint = "Root", parent = "HumanoidRootPart", tone = "pants" },
	{ name = "UpperTorso", size = { 2, 1.6, 1 }, pos = { 0, 0.8, 0 }, joint = "Waist", parent = "LowerTorso", tone = "shirt" },
	{ name = "Head", size = { 1.2, 1.2, 1.2 }, pos = { 0, 2.2, 0 }, joint = "Neck", parent = "UpperTorso", tone = "skin" },
	{ name = "LeftUpperArm", size = { 1, 1.2, 1 }, pos = { -1.5, 1.0, 0 }, joint = "LeftShoulder", parent = "UpperTorso", tone = "shirt" },
	{ name = "LeftLowerArm", size = { 1, 1.2, 1 }, pos = { -1.5, -0.2, 0 }, joint = "LeftElbow", parent = "LeftUpperArm", tone = "skin" },
	{ name = "LeftHand", size = { 1, 0.4, 1 }, pos = { -1.5, -1.0, 0 }, joint = "LeftWrist", parent = "LeftLowerArm", tone = "skin" },
	{ name = "RightUpperArm", size = { 1, 1.2, 1 }, pos = { 1.5, 1.0, 0 }, joint = "RightShoulder", parent = "UpperTorso", tone = "shirt" },
	{ name = "RightLowerArm", size = { 1, 1.2, 1 }, pos = { 1.5, -0.2, 0 }, joint = "RightElbow", parent = "RightUpperArm", tone = "skin" },
	{ name = "RightHand", size = { 1, 0.4, 1 }, pos = { 1.5, -1.0, 0 }, joint = "RightWrist", parent = "RightLowerArm", tone = "skin" },
	{ name = "LeftUpperLeg", size = { 1, 1.2, 1 }, pos = { -0.5, -1.0, 0 }, joint = "LeftHip", parent = "LowerTorso", tone = "pants" },
	{ name = "LeftLowerLeg", size = { 1, 1.2, 1 }, pos = { -0.5, -2.2, 0 }, joint = "LeftKnee", parent = "LeftUpperLeg", tone = "pants" },
	{ name = "LeftFoot", size = { 1, 0.4, 1 }, pos = { -0.5, -3.0, 0 }, joint = "LeftAnkle", parent = "LeftLowerLeg", tone = "shoe" },
	{ name = "RightUpperLeg", size = { 1, 1.2, 1 }, pos = { 0.5, -1.0, 0 }, joint = "RightHip", parent = "LowerTorso", tone = "pants" },
	{ name = "RightLowerLeg", size = { 1, 1.2, 1 }, pos = { 0.5, -2.2, 0 }, joint = "RightKnee", parent = "RightUpperLeg", tone = "pants" },
	{ name = "RightFoot", size = { 1, 0.4, 1 }, pos = { 0.5, -3.0, 0 }, joint = "RightAnkle", parent = "RightLowerLeg", tone = "shoe" },
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
		local name, size, pos, joint, parent, tone = r.name, r.size, r.pos, r.joint, r.parent, r.tone
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
	-- R15 HipHeight is the gap from the root part's bottom (-1) to the ground (the feet's bottom, -3.2);
	-- AI bodies show no name label (ActorService.prepareBody hides it in the engine as well)
	local children = {
		{ className = "Humanoid", name = "Humanoid", props = { HipHeight = 2.2, NameDisplayDistance = 0 } },
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
		attributes = { Role = role, HipHeight = 3.2 },
	}
end

function PuppetSpec.spec(species: string, opts: Opts?): ModelSpec
	local o: Opts = opts or {}
	if species == "squirrel" or species == "rodent" then
		return squirrel(species, o)
	elseif species == "fox" then
		return fox(o)
	elseif species == "deer" then
		return deer(o)
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
		local name, joint, parentName = r.name, r.joint, r.parent
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
				if r.name == s.part then
					ref = r.pos
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
