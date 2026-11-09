--!strict
-- ServerScriptService.Server.AI.Puppets
-- Part-built puppet bodies for the S5 scale spike (BUILD_PLAN §5.2 placeholders): anchored rigs whose
-- part names follow RigSpec (R15 parts for humans, the animal part set with Motor6Ds carrying the
-- bone names), moved kinematically with workspace:BulkMoveTo. Two move modes are measured:
--   "all"  : every part anchored; BulkMoveTo gets every part with rootCFrame * offset
--   "roots": only the root is anchored, limbs are unanchored and welded (Motor6D); BulkMoveTo gets
--            the roots only, and the assembly carries the limbs (if the engine does; the spike checks)
-- Engine-only inside the functions (Instance.new, CFrame); requiring the module is side-effect free
-- so the Lune skeleton test and BootSmoke both pass.
-- Interface: build(species, variant, index, parent) -> Rig, buildVehicle(...), move(rigs, poses, mode),
-- anchorAll(rigs, anchored), partCount(rigs), checkFollow(rig)

local Units = require("../../shared/Config/Units")

export type Rig = {
	model: Model,
	root: BasePart,
	parts: { BasePart }, -- root first
	offsets: { CFrame }, -- part CFrame relative to the root (identity for the root)
	species: string,
}

export type Pose = { x: number, y: number, z: number, yaw: number }

local Puppets = {}

local function part(name: string, size: Vector3, parent: Instance, color: Color3?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if color then
		p.Color = color
	end
	p.Parent = parent
	return p
end

local function joint(name: string, p0: BasePart, p1: BasePart, offset: CFrame)
	local m = Instance.new("Motor6D")
	m.Name = name
	m.Part0 = p0
	m.Part1 = p1
	m.C0 = offset
	m.C1 = CFrame.new()
	m.Parent = p1
end

type Spec = { name: string, size: Vector3, offset: CFrame, joint: string? }

local function assemble(
	species: string,
	modelName: string,
	rootSize: Vector3,
	specs: { Spec },
	parent: Instance,
	color: Color3
): Rig
	local model = Instance.new("Model")
	model.Name = modelName
	model:SetAttribute("Species", species)
	local rootName = if species == "human" then "HumanoidRootPart" else "RootPart"
	local root = part(rootName, rootSize, model, color)
	root.Transparency = if species == "human" then 1 else 0
	model.PrimaryPart = root
	local parts: { BasePart } = { root }
	local offsets: { CFrame } = { CFrame.new() }
	for _, spec in specs do
		local p = part(spec.name, spec.size, model, color)
		table.insert(parts, p)
		table.insert(offsets, spec.offset)
		if spec.joint then
			joint(spec.joint, root, p, spec.offset)
		end
	end
	model.Parent = parent
	return { model = model, root = root, parts = parts, offsets = offsets, species = species }
end

-- R15-shaped human: 16 parts, HumanoidRootPart + Humanoid (state machine off, states disabled).
local function buildHuman(index: number, parent: Instance): Rig
	local color = Color3.fromHSV((index * 0.137) % 1, 0.35, 0.75)
	local specs: { Spec } = {
		{ name = "LowerTorso", size = Vector3.new(2, 0.4, 1), offset = CFrame.new(0, -0.2, 0), joint = "Root" },
		{ name = "UpperTorso", size = Vector3.new(2, 1.6, 1), offset = CFrame.new(0, 0.8, 0), joint = "Waist" },
		{ name = "Head", size = Vector3.new(1.2, 1.2, 1.2), offset = CFrame.new(0, 2.2, 0), joint = "Neck" },
		{
			name = "LeftUpperArm",
			size = Vector3.new(1, 1.2, 1),
			offset = CFrame.new(-1.5, 1.0, 0),
			joint = "LeftShoulder",
		},
		{
			name = "LeftLowerArm",
			size = Vector3.new(1, 1.2, 1),
			offset = CFrame.new(-1.5, -0.2, 0),
			joint = "LeftElbow",
		},
		{ name = "LeftHand", size = Vector3.new(1, 0.4, 1), offset = CFrame.new(-1.5, -1.0, 0), joint = "LeftWrist" },
		{
			name = "RightUpperArm",
			size = Vector3.new(1, 1.2, 1),
			offset = CFrame.new(1.5, 1.0, 0),
			joint = "RightShoulder",
		},
		{
			name = "RightLowerArm",
			size = Vector3.new(1, 1.2, 1),
			offset = CFrame.new(1.5, -0.2, 0),
			joint = "RightElbow",
		},
		{ name = "RightHand", size = Vector3.new(1, 0.4, 1), offset = CFrame.new(1.5, -1.0, 0), joint = "RightWrist" },
		{ name = "LeftUpperLeg", size = Vector3.new(1, 1.2, 1), offset = CFrame.new(-0.5, -1.0, 0), joint = "LeftHip" },
		{
			name = "LeftLowerLeg",
			size = Vector3.new(1, 1.2, 1),
			offset = CFrame.new(-0.5, -2.2, 0),
			joint = "LeftKnee",
		},
		{ name = "LeftFoot", size = Vector3.new(1, 0.4, 1), offset = CFrame.new(-0.5, -3.0, 0), joint = "LeftAnkle" },
		{
			name = "RightUpperLeg",
			size = Vector3.new(1, 1.2, 1),
			offset = CFrame.new(0.5, -1.0, 0),
			joint = "RightHip",
		},
		{
			name = "RightLowerLeg",
			size = Vector3.new(1, 1.2, 1),
			offset = CFrame.new(0.5, -2.2, 0),
			joint = "RightKnee",
		},
		{ name = "RightFoot", size = Vector3.new(1, 0.4, 1), offset = CFrame.new(0.5, -3.0, 0), joint = "RightAnkle" },
	}
	local rig = assemble("human", `Human_{index}`, Vector3.new(2, 2, 1), specs, parent, color)
	local humanoid = Instance.new("Humanoid")
	humanoid.EvaluateStateMachine = false
	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false
	humanoid.AutoRotate = false
	humanoid.AutoJumpEnabled = false
	for _, state in Enum.HumanoidStateType:GetEnumItems() do
		if state ~= Enum.HumanoidStateType.None and state ~= Enum.HumanoidStateType.Running then
			pcall(function()
				humanoid:SetStateEnabled(state, false)
			end)
		end
	end
	humanoid.Parent = rig.model
	return rig
end

-- A non-Humanoid rider (mime, kid cyclist, motorcyclist): 6 body parts plus 2 wheels.
local function buildRider(index: number, parent: Instance): Rig
	local color = Color3.fromHSV((index * 0.21) % 1, 0.5, 0.7)
	local specs: { Spec } = {
		{ name = "Torso", size = Vector3.new(1.6, 1.6, 0.9), offset = CFrame.new(0, 0.6, 0), joint = "Waist" },
		{ name = "Head", size = Vector3.new(1, 1, 1), offset = CFrame.new(0, 1.9, 0), joint = "Neck" },
		{ name = "LeftLeg", size = Vector3.new(0.6, 1.6, 0.6), offset = CFrame.new(-0.4, -1.0, 0), joint = "LeftHip" },
		{ name = "RightLeg", size = Vector3.new(0.6, 1.6, 0.6), offset = CFrame.new(0.4, -1.0, 0), joint = "RightHip" },
		{ name = "WheelF", size = Vector3.new(0.2, 1.4, 1.4), offset = CFrame.new(0, -1.5, -1.4), joint = "WheelF" },
		{ name = "WheelB", size = Vector3.new(0.2, 1.4, 1.4), offset = CFrame.new(0, -1.5, 1.2), joint = "WheelB" },
	}
	return assemble("human", `Rider_{index}`, Vector3.new(1, 1, 1), specs, parent, color)
end

-- Animal puppets: Body, Head, Tail1..n, four legs with the final bone names on the Motor6Ds.
local function buildAnimal(
	species: string,
	index: number,
	parent: Instance,
	scale: number,
	color: Color3,
	tailSegments: number
): Rig
	local s = scale
	local specs: { Spec } = {
		{ name = "Body", size = Vector3.new(0.9 * s, 0.7 * s, 1.6 * s), offset = CFrame.new(0, 0, 0), joint = "Hips" },
		{
			name = "Head",
			size = Vector3.new(0.6 * s, 0.6 * s, 0.7 * s),
			offset = CFrame.new(0, 0.45 * s, -1.0 * s),
			joint = "Head",
		},
		{
			name = "FrontL_Upper",
			size = Vector3.new(0.2 * s, 0.8 * s, 0.2 * s),
			offset = CFrame.new(-0.3 * s, -0.6 * s, -0.5 * s),
			joint = "FrontL_Upper",
		},
		{
			name = "FrontR_Upper",
			size = Vector3.new(0.2 * s, 0.8 * s, 0.2 * s),
			offset = CFrame.new(0.3 * s, -0.6 * s, -0.5 * s),
			joint = "FrontR_Upper",
		},
		{
			name = "BackL_Upper",
			size = Vector3.new(0.2 * s, 0.8 * s, 0.2 * s),
			offset = CFrame.new(-0.3 * s, -0.6 * s, 0.5 * s),
			joint = "BackL_Upper",
		},
		{
			name = "BackR_Upper",
			size = Vector3.new(0.2 * s, 0.8 * s, 0.2 * s),
			offset = CFrame.new(0.3 * s, -0.6 * s, 0.5 * s),
			joint = "BackR_Upper",
		},
	}
	for t = 1, tailSegments do
		table.insert(specs, {
			name = `Tail{t}`,
			size = Vector3.new(0.35 * s, 0.35 * s, 0.5 * s),
			offset = CFrame.new(0, 0.3 * s + 0.2 * s * t, 0.9 * s + 0.4 * s * t),
			joint = `Tail{t}`,
		})
	end
	return assemble(species, `{species}_{index}`, Vector3.new(0.5 * s, 0.5 * s, 0.5 * s), specs, parent, color)
end

function Puppets.build(species: string, variant: string, index: number, parent: Instance): Rig
	if species == "human" then
		if variant == "rider" then
			return buildRider(index, parent)
		end
		return buildHuman(index, parent)
	elseif species == "squirrel" then
		local color = if variant == "spicy" then Color3.fromRGB(131, 84, 77) else Color3.fromRGB(183, 132, 83)
		return buildAnimal("squirrel", index, parent, 1.0, color, 3)
	elseif species == "fox" then
		return buildAnimal("fox", index, parent, 1.6, Color3.fromRGB(184, 102, 60), 2)
	elseif species == "deer" then
		local scale = if variant == "fawn" then 3.5 * 0.55 else 3.5
		return buildAnimal("deer", index, parent, scale, Color3.fromRGB(173, 132, 94), 1)
	end
	error(`Puppets.build: unknown species {species}`)
end

-- Vehicle proxy: Body (root) plus 4 wheels, the sedan's logical box (traffic §1).
function Puppets.buildVehicle(index: number, parent: Instance, width: number, height: number, length: number): Rig
	local color = Color3.fromHSV((index * 0.31) % 1, 0.6, 0.8)
	local wx, wz = width / 2, length / 2 - Units.st(0.6)
	local wheel = Vector3.new(0.5, 1.4, 1.4)
	local specs: { Spec } = {
		{ name = "WheelFL", size = wheel, offset = CFrame.new(-wx, -height / 2 + 0.7, -wz), joint = "WheelFL" },
		{ name = "WheelFR", size = wheel, offset = CFrame.new(wx, -height / 2 + 0.7, -wz), joint = "WheelFR" },
		{ name = "WheelBL", size = wheel, offset = CFrame.new(-wx, -height / 2 + 0.7, wz), joint = "WheelBL" },
		{ name = "WheelBR", size = wheel, offset = CFrame.new(wx, -height / 2 + 0.7, wz), joint = "WheelBR" },
	}
	return assemble("car", `Vehicle_{index}`, Vector3.new(width, height, length), specs, parent, color)
end

function Puppets.partCount(rigs: { Rig }): number
	local n = 0
	for _, rig in rigs do
		n += #rig.parts
	end
	return n
end

-- Anchor or unanchor every non-root part (mode "roots" needs unanchored limbs).
function Puppets.anchorLimbs(rigs: { Rig }, anchored: boolean)
	for _, rig in rigs do
		for i = 2, #rig.parts do
			rig.parts[i].Anchored = anchored
		end
	end
end

-- Compose this frame's CFrames and move everything with ONE BulkMoveTo.
-- poses[i] is the pose of rigs[i]. Buffers are reused across frames (no per-frame tables).
export type MoveBuffers = { parts: { BasePart }, cframes: { CFrame } }

function Puppets.newBuffers(): MoveBuffers
	return { parts = {}, cframes = {} }
end

function Puppets.move(rigs: { Rig }, poses: { Pose }, mode: "all" | "roots", buffers: MoveBuffers): number
	local parts, cframes = buffers.parts, buffers.cframes
	local n = 0
	for i, rig in rigs do
		local pose = poses[i]
		local rootCf = CFrame.new(pose.x, pose.y, pose.z) * CFrame.Angles(0, Units.robloxYaw(pose.yaw), 0)
		if mode == "roots" then
			n += 1
			parts[n] = rig.root
			cframes[n] = rootCf
		else
			local offsets = rig.offsets
			for j, p in rig.parts do
				n += 1
				parts[n] = p
				cframes[n] = if j == 1 then rootCf else rootCf * offsets[j]
			end
		end
	end
	-- trim stale tail entries from a larger previous call
	for k = #parts, n + 1, -1 do
		parts[k] = nil
		cframes[k] = nil
	end
	workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	return n
end

-- After a roots-only move: did the first limb follow its root (assembly moved)?
function Puppets.checkFollow(rig: Rig): (boolean, number)
	if #rig.parts < 2 then
		return true, 0
	end
	local expected = rig.root.CFrame * rig.offsets[2]
	local err = (rig.parts[2].Position - expected.Position).Magnitude
	return err < 0.01, err
end

return Puppets
