--!strict
-- ReplicatedStorage.Shared.Avatar.PartBuilder
-- Placeholder bodies as plain data, instantiated the same way in Lune (tools/placeholders -> .rbxm) and
-- in the engine (ghost vehicles, BodyFactory fallback), BUILD_PLAN §5.2 "placeholders", W1 #10.
-- Interface: instantiate(spec, lib) -> Model; partCount(spec); names(spec) -> {parts, joints, attachments};
--            hex(s) -> {r, g, b} (0-1); cf(spec, lib) helpers.
--
-- A ModelSpec lists parts (box, ball or cylinder; position relative to the PrimaryPart, optional yaw /
-- roll in radians), joints (Motor6D or Weld, joint frame at `at` or at Part1's centre, identity rotation),
-- attachments (sockets) and extra children (Humanoid, AnimationController, HumanoidDescription). Names
-- come from the caller, which takes them from Actors/RigSpec (final bone, socket and region names), so a
-- placeholder passes RigSpec.validate exactly like the skinned rig that replaces it.
-- `lib` carries the constructors ({Instance, Vector3, CFrame, Color3, Enum}): the engine globals or
-- @lune/roblox. Rule 4 (HANDOFF): the PrimaryPart is anchored, every other part is unanchored and
-- joined to it through the joints, so BulkMoveTo moves roots only. Pure until instantiate is called.

export type Rgb = { r: number, g: number, b: number }

export type PartSpec = {
	name: string,
	size: { number },
	pos: { number }, -- relative to the PrimaryPart, studs
	yaw: number?, -- radians about +Y
	roll: number?, -- radians about +Z (wheels: pi/2 turns a cylinder's axis from X to... see shape)
	pitch: number?, -- radians about +X
	color: Rgb,
	shape: string?, -- "Block" (default) | "Ball" | "Cylinder" (axis along local X)
	material: string?, -- Enum.Material name (default SmoothPlastic)
	transparency: number?,
	reflectance: number?,
}

export type JointSpec = { name: string, kind: string?, part0: string, part1: string, at: { number }? }
export type AttachmentSpec = { name: string, part: string, pos: { number } }
export type ChildSpec = { className: string, name: string, props: { [string]: any }? }

export type ModelSpec = {
	name: string,
	species: string,
	primary: string,
	parts: { PartSpec },
	joints: { JointSpec },
	attachments: { AttachmentSpec },
	children: { ChildSpec }?,
	attributes: { [string]: any }?,
}

export type Lib = { Instance: any, Vector3: any, CFrame: any, Color3: any, Enum: any }

local PartBuilder = {}

function PartBuilder.hex(s: string): Rgb
	local h = string.gsub(s, "#", "")
	local r = tonumber(string.sub(h, 1, 2), 16) or 0
	local g = tonumber(string.sub(h, 3, 4), 16) or 0
	local b = tonumber(string.sub(h, 5, 6), 16) or 0
	return { r = r / 255, g = g / 255, b = b / 255 }
end

function PartBuilder.partCount(spec: ModelSpec): number
	return #spec.parts
end

-- Every name the spec will create, by instance kind (what RigSpec.validate looks for).
function PartBuilder.names(spec: ModelSpec): {
	parts: { [string]: boolean },
	joints: { [string]: boolean },
	attachments: { [string]: boolean },
}
	local out = { parts = {}, joints = {}, attachments = {} }
	for _, p in spec.parts do
		out.parts[p.name] = true
	end
	for _, j in spec.joints do
		if (j.kind or "Motor6D") == "Motor6D" then
			out.joints[j.name] = true
		end
	end
	for _, a in spec.attachments do
		out.attachments[a.name] = true
	end
	return out
end

local function partCFrame(p: PartSpec, lib: Lib): any
	local cf = lib.CFrame.new(p.pos[1], p.pos[2], p.pos[3])
	if p.yaw or p.pitch or p.roll then
		cf = cf * lib.CFrame.fromEulerAnglesYXZ(p.pitch or 0, p.yaw or 0, p.roll or 0)
	end
	return cf
end

-- instantiate(spec, lib, origin?) -> Model. `origin` (a CFrame) places the PrimaryPart; default identity.
function PartBuilder.instantiate(spec: ModelSpec, lib: Lib, origin: any?): any
	local Instance, Vector3, CFrame, Color3, Enum = lib.Instance, lib.Vector3, lib.CFrame, lib.Color3, lib.Enum
	local base = origin or CFrame.new()
	local model = Instance.new("Model")
	model.Name = spec.name
	model:SetAttribute("Species", spec.species)
	model:SetAttribute("Placeholder", true)
	for k, v in (spec.attributes or {}) :: { [string]: any } do
		model:SetAttribute(k, v)
	end
	local parts: { [string]: any } = {}
	local local_: { [string]: any } = {}
	for _, p in spec.parts do
		local inst = Instance.new("Part")
		inst.Name = p.name
		inst.Size = Vector3.new(p.size[1], p.size[2], p.size[3])
		local rel = partCFrame(p, lib)
		local_[p.name] = rel
		inst.CFrame = base * rel
		inst.Color = Color3.new(p.color.r, p.color.g, p.color.b)
		inst.Material = (Enum.Material :: any)[p.material or "SmoothPlastic"]
		inst.Shape = (Enum.PartType :: any)[p.shape or "Block"]
		inst.Transparency = p.transparency or 0
		inst.Reflectance = p.reflectance or 0
		inst.TopSurface = Enum.SurfaceType.Smooth
		inst.BottomSurface = Enum.SurfaceType.Smooth
		inst.CastShadow = if p.name == spec.primary then false else (p.transparency or 0) < 1
		inst.CanCollide = false
		inst.CanTouch = false
		inst.CanQuery = p.name == spec.primary
		inst.Massless = p.name ~= spec.primary
		inst.Anchored = p.name == spec.primary
		inst.Parent = model
		parts[p.name] = inst
	end
	local primary = parts[spec.primary] or error(`PartBuilder: {spec.name} has no primary part {spec.primary}`)
	model.PrimaryPart = primary
	for _, j in spec.joints do
		local p0 = parts[j.part0] or error(`PartBuilder: joint {j.name} part0 {j.part0} missing`)
		local p1 = parts[j.part1] or error(`PartBuilder: joint {j.name} part1 {j.part1} missing`)
		local c0rel, c1rel = local_[j.part0], local_[j.part1]
		local at = if j.at then CFrame.new(j.at[1], j.at[2], j.at[3]) else CFrame.new(c1rel.Position)
		local joint = Instance.new(j.kind or "Motor6D")
		joint.Name = j.name
		joint.Part0 = p0
		joint.Part1 = p1
		joint.C0 = c0rel:Inverse() * at
		joint.C1 = c1rel:Inverse() * at
		joint.Parent = p1
	end
	for _, a in spec.attachments do
		local host = parts[a.part] or error(`PartBuilder: attachment {a.name} part {a.part} missing`)
		local att = Instance.new("Attachment")
		att.Name = a.name
		att.CFrame = local_[a.part]:Inverse() * CFrame.new(a.pos[1], a.pos[2], a.pos[3])
		att.Parent = host
	end
	for _, c in (spec.children or {}) :: { ChildSpec } do
		local inst = Instance.new(c.className)
		inst.Name = c.name
		for k, v in (c.props or {}) :: { [string]: any } do
			(inst :: any)[k] = v
		end
		inst.Parent = model
	end
	return model
end

-- The engine library (globals). Only call inside the engine.
function PartBuilder.engineLib(): Lib
	return { Instance = Instance, Vector3 = Vector3, CFrame = CFrame, Color3 = Color3, Enum = Enum }
end

return PartBuilder
