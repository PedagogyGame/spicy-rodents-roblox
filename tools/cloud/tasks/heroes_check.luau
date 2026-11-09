--!strict
-- Hero art engine check (tools/blender/heroes): one Luau Execution task on a CI place version built from
-- ci.project.json (ReplicatedStorage.Shared.Actors.RigSpec must be in it).
--   node tools/cloud/cloud.mjs run_engine_tests tools/cloud/tasks/heroes_check.luau --version <v> --place ci
-- 1. InsertService:LoadAsset(squirrel model): the Bone tree under the Part named RootPart, every Bone's
--    rest rotation (must be identity: the clips are axis-aligned joint deltas), the region MeshParts
--    (skinned, SurfaceAppearance) and RigSpec.validate before and after adding the sockets from
--    data/art/heroes.json as Attachments under their Bones.
-- 2. KeyframeSequenceProvider:GetKeyframeSequenceAsync on two clips: keyframes, duration, loop, markers,
--    and the Pose tree (parent/child pairs) against the Bone tree and RigSpec's bone list.
-- 3. An Animator on the loaded model's AnimationController loads each clip as a track (Length, Looped).
-- The ids below are filled from data/art/heroes.json (publish.py) before the run.

local MODEL_ID = 0 -- @@MODEL_ID@@
local CLIPS = { Run = 0, Pounce = 0 } -- @@CLIPS@@
local SOCKETS = {} :: { [string]: { bone: string, offset: { number } } } -- @@SOCKETS@@

local InsertService = game:GetService("InsertService")
local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RigSpec = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Actors"):WaitForChild("RigSpec")) :: any

local result: { [string]: any } = { suite = "heroes_check", placeVersion = game.PlaceVersion, modelId = MODEL_ID }
local failures: { string } = {}

local function fail(msg: string)
	table.insert(failures, msg)
end

local ok, loaded = pcall(function()
	return InsertService:LoadAsset(MODEL_ID)
end)
if not ok then
	result.ok = false
	result.error = `LoadAsset: {loaded}`
	return result
end
local container = loaded :: Model
local model: Model = container:FindFirstChildWhichIsA("Model") or container
model.Name = "squirrel"
model.Parent = workspace

-- 1. bones -----------------------------------------------------------------------------------------
local rootPart = model:FindFirstChild("RootPart")
local boneRoot: Instance? = nil
for _, d in model:GetDescendants() do
	if d:IsA("Bone") and d.Name == "Root" then
		boneRoot = d.Parent
	end
end
result.boneParent = boneRoot and `{boneRoot.Name} [{boneRoot.ClassName}]` or "none"
local bonePairs: { [string]: boolean } = {}
local boneNames: { string } = {}
local maxRot = 0
local function walkBones(inst: Instance)
	for _, c in inst:GetChildren() do
		if c:IsA("Bone") then
			table.insert(boneNames, c.Name)
			bonePairs[`{inst.Name}>{c.Name}`] = true
			local _, _, _, r00, r01, r02, r10, r11, r12, r20, r21, r22 = c.CFrame:GetComponents()
			local dev = math.max(
				math.abs(r00 - 1),
				math.abs(r11 - 1),
				math.abs(r22 - 1),
				math.abs(r01),
				math.abs(r02),
				math.abs(r10),
				math.abs(r12),
				math.abs(r20),
				math.abs(r21)
			)
			maxRot = math.max(maxRot, dev)
			walkBones(c)
		end
	end
end
if boneRoot then
	walkBones(boneRoot)
end
result.bones = #boneNames
result.boneOrder = boneNames
result.maxRestRotationDeviation = math.round(maxRot * 1e6) / 1e6
if maxRot > 1e-3 then
	fail(`bone rest rotations are not identity (max deviation {maxRot})`)
end
local contract = RigSpec.get("squirrel")
local have: { [string]: boolean } = {}
for _, n in boneNames do
	have[n] = true
end
local missing, extra = {}, {}
for _, n in contract.bones do
	if not have[n] then
		table.insert(missing, n)
	end
	have[n] = nil
end
for n in have do
	table.insert(extra, n)
end
result.bonesMissingFromRigSpec = missing
result.bonesNotInRigSpec = extra
if #missing > 0 or #extra > 0 then
	fail(`bones differ from RigSpec.squirrel: missing {table.concat(missing, ",")} extra {table.concat(extra, ",")}`)
end

-- regions
local regions = {}
for _, d in model:GetChildren() do
	if d:IsA("MeshPart") then
		local sa = d:FindFirstChildOfClass("SurfaceAppearance")
		regions[d.Name] = {
			skinned = (d :: any).HasSkinnedMesh,
			surfaceAppearance = sa ~= nil,
			alphaMode = sa and tostring(sa.AlphaMode) or nil,
			size = {
				math.round(d.Size.X * 1000) / 1000,
				math.round(d.Size.Y * 1000) / 1000,
				math.round(d.Size.Z * 1000) / 1000,
			},
		}
	end
end
result.regions = regions
result.rootPart = rootPart
		and {
			class = rootPart.ClassName,
			size = { (rootPart :: BasePart).Size.X, (rootPart :: BasePart).Size.Y, (rootPart :: BasePart).Size.Z },
			transparency = (rootPart :: BasePart).Transparency,
		}
	or nil
model.PrimaryPart = rootPart :: BasePart?
local before = RigSpec.validate(model, "squirrel")
result.validateBefore = {
	ok = before.ok,
	missingBones = before.missingBones,
	missingSockets = before.missingSockets,
	missingRegions = before.missingRegions,
	primaryPartOk = before.primaryPartOk,
}
-- sockets from heroes.json as Attachments under their Bones
local bonesByName: { [string]: Bone } = {}
for _, d in model:GetDescendants() do
	if d:IsA("Bone") then
		bonesByName[d.Name] = d
	end
end
for name, s in SOCKETS do
	local bone = bonesByName[s.bone]
	if bone then
		local a = Instance.new("Attachment")
		a.Name = name
		a.CFrame = CFrame.new(s.offset[1], s.offset[2], s.offset[3])
		a.Parent = bone
	end
end
local after = RigSpec.validate(model, "squirrel")
result.validateAfterSockets = {
	ok = after.ok,
	missingBones = after.missingBones,
	missingSockets = after.missingSockets,
	missingRegions = after.missingRegions,
	primaryPartOk = after.primaryPartOk,
}
if not after.ok then
	fail("RigSpec.validate fails after adding the sockets")
end

-- 2 and 3. clips -------------------------------------------------------------------------------------
local controller = model:FindFirstChildOfClass("AnimationController") or Instance.new("AnimationController")
controller.Parent = model
local animator = controller:FindFirstChildOfClass("Animator") or Instance.new("Animator")
animator.Parent = controller
local clips = {}
for name, id in CLIPS do
	local info: { [string]: any } = { assetId = id }
	local t0 = os.clock()
	local okSeq, seq = pcall(function()
		return KeyframeSequenceProvider:GetKeyframeSequenceAsync(`rbxassetid://{id}`)
	end)
	info.loadMs = math.round((os.clock() - t0) * 1000)
	if not okSeq then
		info.error = tostring(seq)
		fail(`{name}: {seq}`)
	else
		local ks = seq :: KeyframeSequence
		local frames = {}
		for _, k in ks:GetChildren() do
			if k:IsA("Keyframe") then
				table.insert(frames, k)
			end
		end
		table.sort(frames, function(a: Keyframe, b: Keyframe)
			return a.Time < b.Time
		end)
		info.keyframes = #frames
		info.duration = frames[#frames] and math.round(frames[#frames].Time * 1000) / 1000 or 0
		info.loop = ks.Loop
		info.priority = tostring(ks.Priority)
		local markers = {}
		for _, k in frames do
			for _, m in k:GetChildren() do
				if m:IsA("KeyframeMarker") then
					table.insert(markers, `{m.Name}@{math.round(k.Time * 1000) / 1000}`)
				end
			end
		end
		info.markers = markers
		local poseNames: { string } = {}
		local posePairs: { [string]: boolean } = {}
		local function walk(inst: Instance)
			for _, c in inst:GetChildren() do
				if c:IsA("Pose") then
					table.insert(poseNames, c.Name)
					if inst:IsA("Pose") then
						posePairs[`{inst.Name}>{c.Name}`] = true
					end
					walk(c)
				end
			end
		end
		if frames[1] then
			walk(frames[1])
		end
		info.poseNames = poseNames
		-- every bone (and its parent link) must have a pose with the same parent, and vice versa
		local bad = {}
		for pair in bonePairs do
			if not posePairs[pair] then
				table.insert(bad, `bone {pair} has no pose`)
			end
		end
		for pair in posePairs do
			if not bonePairs[pair] then
				table.insert(bad, `pose {pair} has no bone`)
			end
		end
		info.posesMatchBones = #bad == 0
		info.mismatches = bad
		if #bad > 0 then
			fail(`{name}: {#bad} pose/bone mismatches`)
		end
		info.topPose = poseNames[1]
		if poseNames[1] ~= "RootPart" then
			fail(`{name}: top pose is {poseNames[1]}, expected RootPart`)
		end
		local okTrack, track = pcall(function()
			local a = Instance.new("Animation")
			a.AnimationId = `rbxassetid://{id}`
			return animator:LoadAnimation(a)
		end)
		if okTrack then
			local deadline = os.clock() + 5
			while (track :: AnimationTrack).Length == 0 and os.clock() < deadline do
				task.wait(0.1)
			end
			info.trackLength = math.round((track :: AnimationTrack).Length * 1000) / 1000
			info.trackLooped = (track :: AnimationTrack).Looped
		else
			info.trackError = tostring(track)
		end
	end
	clips[name] = info
end
result.clips = clips
result.failures = failures
result.ok = #failures == 0
print(`heroes_check: {#boneNames} bones, {#failures} failure(s)`)
return result
