--!strict
-- tools/anim/KeyframeBuilder: a "spicy-clip/1" table (tools/blender/export_art.py) -> a
-- KeyframeSequence built with @lune/roblox (BUILD_PLAN D11, spike S7). Lune only.
--
-- Shape of the result (what Animator and KeyframeSequenceProvider expect):
--   KeyframeSequence (Name = clip, Loop, Priority)
--     Keyframe (Time) x N
--       Pose <rootPart> (identity)              the rig's PrimaryPart, RigSpec "RootPart"
--         Pose Root -> Pose Hips -> ...         one Pose per bone, nested like the bone tree;
--                                               Pose.CFrame = the clip's 12-number local delta
--       KeyframeMarker (Name, Value)            Commit/Recover sync markers (D11), on the
--                                               keyframe whose Time matches
-- Bone names are RigSpec's, so the same clip drives a puppet's Motor6Ds (named after the bones)
-- and a skinned rig's Bones.

local roblox = require("@lune/roblox")

local Instance = roblox.Instance
local CFrame = roblox.CFrame
local Enum = roblox.Enum

export type ClipBone = {
	name: string,
	parent: string?,
	deform: boolean?,
	head: { number }?,
	tail: { number }?,
	restRotation: { number }?,
}
export type ClipKeyframe = { time: number, frame: number?, poses: { [string]: { number } } }
export type ClipMarker = { time: number, name: string, value: string? }
export type Clip = {
	format: string,
	rig: string,
	clip: string,
	fps: number?,
	loop: boolean?,
	priority: string?,
	rootPart: string?,
	bones: { ClipBone },
	keyframes: { ClipKeyframe },
	markers: { ClipMarker }?,
}

export type Summary = {
	name: string,
	keyframes: number,
	duration: number,
	poseNames: { string },
	markers: { string },
}

local KeyframeBuilder = {}

KeyframeBuilder.FORMAT = "spicy-clip/1"
local TIME_EPS = 1e-4

local function cframeOf(v: { number }, where: string): any
	if #v ~= 12 then
		error(`{where}: expected 12 numbers (x, y, z, R00..R22), got {#v}`)
	end
	return CFrame.new(v[1], v[2], v[3], v[4], v[5], v[6], v[7], v[8], v[9], v[10], v[11], v[12])
end

-- Check the clip before building anything; returns a list of problems (empty when valid).
function KeyframeBuilder.validate(clip: Clip): { string }
	local problems: { string } = {}
	if clip.format ~= KeyframeBuilder.FORMAT then
		table.insert(problems, `format is {clip.format}, expected {KeyframeBuilder.FORMAT}`)
	end
	local known: { [string]: boolean } = {}
	for _, b in clip.bones do
		if known[b.name] then
			table.insert(problems, `duplicate bone {b.name}`)
		end
		known[b.name] = true
	end
	for _, b in clip.bones do
		if b.parent ~= nil and not known[b.parent] then
			table.insert(problems, `bone {b.name} has unknown parent {b.parent}`)
		end
	end
	if #clip.keyframes == 0 then
		table.insert(problems, "no keyframes")
	end
	local last = -math.huge
	for i, k in clip.keyframes do
		if k.time < last - TIME_EPS then
			table.insert(problems, `keyframe {i} time {k.time} goes backwards`)
		end
		last = k.time
		for name, v in k.poses do
			if not known[name] then
				table.insert(problems, `keyframe {i} poses unknown bone {name}`)
			elseif #v ~= 12 then
				table.insert(problems, `keyframe {i} bone {name}: {#v} numbers, expected 12`)
			end
		end
	end
	for _, m in clip.markers or {} do
		local hit = false
		for _, k in clip.keyframes do
			if math.abs(k.time - m.time) < TIME_EPS then
				hit = true
			end
		end
		if not hit then
			table.insert(problems, `marker {m.name} at {m.time} is not on a keyframe`)
		end
	end
	return problems
end

-- Build the KeyframeSequence. Errors (with every problem listed) on an invalid clip.
function KeyframeBuilder.build(clip: Clip): any
	local problems = KeyframeBuilder.validate(clip)
	if #problems > 0 then
		error("invalid clip:\n  " .. table.concat(problems, "\n  "))
	end
	local children: { [string]: { string } } = {}
	local roots: { string } = {}
	for _, b in clip.bones do
		if b.parent == nil then
			table.insert(roots, b.name)
		else
			local list = children[b.parent] or {}
			list[#list + 1] = b.name
			children[b.parent] = list
		end
	end

	local seq = Instance.new("KeyframeSequence")
	seq.Name = clip.clip
	seq.Loop = clip.loop == true
	seq.Priority = (Enum.AnimationPriority :: any)[clip.priority or "Core"]

	for i, k in clip.keyframes do
		local kf = Instance.new("Keyframe")
		kf.Name = `Keyframe{i}`
		kf.Time = k.time
		local rootPose = Instance.new("Pose")
		rootPose.Name = clip.rootPart or "RootPart"
		rootPose.CFrame = CFrame.identity
		rootPose.Weight = 1
		rootPose.Parent = kf
		local function addPose(name: string, parent: any)
			local pose = Instance.new("Pose")
			pose.Name = name
			local v = k.poses[name]
			pose.CFrame = if v then cframeOf(v, `keyframe {i} bone {name}`) else CFrame.identity
			pose.Weight = if v then 1 else 0
			pose.EasingStyle = Enum.PoseEasingStyle.Linear
			pose.EasingDirection = Enum.PoseEasingDirection.In
			pose.Parent = parent
			for _, child in children[name] or {} do
				addPose(child, pose)
			end
		end
		for _, r in roots do
			addPose(r, rootPose)
		end
		for _, m in clip.markers or {} do
			if math.abs(k.time - m.time) < TIME_EPS then
				local marker = Instance.new("KeyframeMarker")
				marker.Name = m.name
				marker.Value = m.value or ""
				marker.Parent = kf
			end
		end
		kf.Parent = seq
	end
	return seq
end

-- What a reader sees: keyframe count, duration (last Time), the Pose names under the first
-- keyframe in depth-first order (the root part first) and the marker names. The engine probe
-- (tools/cloud/tasks/art_probe.luau) reports the same fields for the uploaded clip.
function KeyframeBuilder.summarize(seq: any): Summary
	local keyframes = 0
	local duration = 0
	local first: any = nil
	local markers: { string } = {}
	for _, kf in seq:GetChildren() do
		if kf.ClassName == "Keyframe" then
			keyframes += 1
			if kf.Time >= duration then
				duration = kf.Time
			end
			if first == nil or kf.Time < first.Time then
				first = kf
			end
			for _, m in kf:GetChildren() do
				if m.ClassName == "KeyframeMarker" then
					table.insert(markers, m.Name)
				end
			end
		end
	end
	local poseNames: { string } = {}
	local function walk(inst: any)
		for _, c in inst:GetChildren() do
			if c.ClassName == "Pose" then
				table.insert(poseNames, c.Name)
				walk(c)
			end
		end
	end
	if first then
		walk(first)
	end
	return { name = seq.Name, keyframes = keyframes, duration = duration, poseNames = poseNames, markers = markers }
end

return KeyframeBuilder
