--!strict
-- Exploratory probe for the hero rigs (tools/blender/heroes): what does an Open Cloud Model upload of a
-- skinned FBX (armature + several meshes) arrive as through InsertService:LoadAsset? Lists the tree,
-- every Bone's parent, local CFrame (position, rotation) and WorldCFrame, and every MeshPart's size,
-- skinning and SurfaceAppearance. Needs none of our modules.
--   node tools/cloud/cloud.mjs run_engine_tests tools/cloud/tasks/heroes_rig_probe.luau --version <v> --place ci
-- The asset id comes from the first line below (edited per probe).

local MODEL_ID = 113341664367996

local InsertService = game:GetService("InsertService")

local function r3(x: number): number
	return math.round(x * 1000) / 1000
end

local function cf(c: CFrame): { number }
	local out = {}
	for _, v in { c:GetComponents() } do
		table.insert(out, r3(v))
	end
	return out
end

local result: { [string]: any } = { suite = "heroes_rig_probe", ok = true, modelId = MODEL_ID }
local ok, model = pcall(function()
	return InsertService:LoadAsset(MODEL_ID)
end)
if not ok then
	result.ok = false
	result.error = tostring(model)
	return result
end
local tree = {}
local bones = {}
local parts = {}
for _, d in (model :: Instance):GetDescendants() do
	table.insert(tree, `{d:GetFullName()} [{d.ClassName}]`)
	if d:IsA("Bone") then
		local b = d :: Bone
		table.insert(bones, {
			name = b.Name,
			parent = b.Parent and b.Parent.Name,
			parentClass = b.Parent and b.Parent.ClassName,
			cframe = cf(b.CFrame),
			world = cf(b.WorldCFrame),
		})
	elseif d:IsA("MeshPart") then
		local m = d :: MeshPart
		local sa = m:FindFirstChildOfClass("SurfaceAppearance")
		table.insert(parts, {
			name = m.Name,
			size = { r3(m.Size.X), r3(m.Size.Y), r3(m.Size.Z) },
			cframe = cf(m.CFrame),
			meshId = tostring(m.MeshId),
			textureId = tostring(m.TextureID),
			skinned = (pcall(function()
				return (m :: any).HasSkinnedMesh
			end) and (m :: any).HasSkinnedMesh) or "?",
			surfaceAppearance = sa ~= nil,
			alphaMode = sa and tostring(sa.AlphaMode) or nil,
			anchored = m.Anchored,
			children = #m:GetChildren(),
		})
	elseif d:IsA("BasePart") then
		local bp = d :: BasePart
		table.insert(parts, {
			name = bp.Name,
			class = bp.ClassName,
			size = { r3(bp.Size.X), r3(bp.Size.Y), r3(bp.Size.Z) },
			cframe = cf(bp.CFrame),
			transparency = bp.Transparency,
			anchored = bp.Anchored,
		})
	elseif d:IsA("Motor6D") then
		local m = d :: Motor6D
		table.insert(parts, {
			motor = m.Name,
			part0 = m.Part0 and m.Part0.Name,
			part1 = m.Part1 and m.Part1.Name,
			c0 = cf(m.C0),
			c1 = cf(m.C1),
		})
	elseif d:IsA("Attachment") then
		table.insert(parts, { attachment = d.Name, parent = d.Parent and d.Parent.Name })
	end
end
result.count = #tree
result.tree = tree
result.bones = bones
result.parts = parts
local primary = (model :: Model):FindFirstChildWhichIsA("Model")
result.innerModel = primary and primary.Name or nil
result.innerPrimary = primary and (primary :: Model).PrimaryPart and ((primary :: Model).PrimaryPart :: BasePart).Name or nil
print(`heroes_rig_probe: {#tree} instances, {#bones} bones, {#parts} parts/attachments`)
return result
