--!strict
-- Spikes S7 + S8 (a, c2) in one Luau Execution task (BUILD_PLAN §4.3). Needs none of our modules.
--   node tools/cloud/cloud.mjs run_engine_tests tools/cloud/tasks/art_probe.luau --version <v> --place ci
-- S7:  KeyframeSequenceProvider:GetKeyframeSequenceAsync on the Lune-built clip (keyframes, duration,
--      pose names, markers, one pose value) and an Animator track's Length.
-- S8a: InsertService:LoadAsset on the bpy FBX Model upload: what arrived (classes, MeshId, TextureID,
--      size, fidelity, SurfaceAppearance and its maps), raycasts through the hollow log, and
--      AssetService:CreateMeshPartAsync on the same mesh. If the place version carries
--      Workspace.S8Probe (a MeshPart written by Lune, tools/anim/s8_probe_place.luau) it is
--      inspected the same way.
-- S8c2: which appearance properties scripts can write at runtime (MeshPart.Color, TextureID,
--      CollisionFidelity, SurfaceAppearance.Color / AlphaMode / maps on a new SurfaceAppearance).
-- Headless only: whether a tint *looks* right needs the owner's Studio (OS-1b).

local ANIMATION_ID = 92005834447457 -- S7 test clip (spicy-rodents pipeline test: S7)
local MODEL_ID = 126862471025988 -- S8a hollow log FBX (spicy-rodents pipeline test: S8a)
local EXPECTED_POSES = {
	"RootPart",
	"Root",
	"Hips",
	"Spine1",
	"Chest",
	"Neck",
	"Head",
	"FrontL_Upper",
	"FrontR_Upper",
	"Tail1",
	"Tail2",
	"Tail3",
	"BackL_Upper",
	"BackR_Upper",
}
local ORIGIN = Vector3.new(1000, 500, 1000)

local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")
local InsertService = game:GetService("InsertService")
local AssetService = game:GetService("AssetService")

local result: { [string]: any } = { suite = "art_probe", placeVersion = game.PlaceVersion }
local failures: { string } = {}

local function try(label: string, fn: () -> any): (boolean, any)
	local ok, value = pcall(fn)
	if not ok then
		return false, `{label}: {value}`
	end
	return true, value
end

local function vec(v: Vector3): { number }
	return { math.round(v.X * 1000) / 1000, math.round(v.Y * 1000) / 1000, math.round(v.Z * 1000) / 1000 }
end

-- Write a property, read it back; "ok", or the error text (capability / NotScriptable messages).
local function writeProbe(inst: Instance, prop: string, value: any): string
	local ok, err = pcall(function()
		(inst :: any)[prop] = value
	end)
	if not ok then
		return `error: {err}`
	end
	local readOk, back = pcall(function()
		return (inst :: any)[prop]
	end)
	if not readOk then
		return "written, not readable"
	end
	return if back == value then "ok" else `written, reads back {tostring(back)}`
end

local function readProbe(inst: Instance, prop: string): any
	local ok, value = pcall(function()
		return (inst :: any)[prop]
	end)
	if not ok then
		return `unreadable: {value}`
	end
	if typeof(value) == "Vector3" then
		return vec(value)
	elseif typeof(value) == "EnumItem" or typeof(value) == "Color3" or typeof(value) == "Content" then
		return tostring(value)
	end
	return value
end

-- ---- S7 -----------------------------------------------------------------------------------------
do
	local s7: { [string]: any } = { animationId = ANIMATION_ID }
	local t0 = os.clock()
	local ok, seq = try("GetKeyframeSequenceAsync", function()
		return KeyframeSequenceProvider:GetKeyframeSequenceAsync(`rbxassetid://{ANIMATION_ID}`)
	end)
	s7.loadMs = math.round((os.clock() - t0) * 1000)
	if not ok then
		s7.error = seq
		table.insert(failures, "S7: " .. tostring(seq))
	else
		local keyframes = {}
		for _, c in (seq :: Instance):GetChildren() do
			if c:IsA("Keyframe") then
				table.insert(keyframes, c)
			end
		end
		table.sort(keyframes, function(a: Keyframe, b: Keyframe)
			return a.Time < b.Time
		end)
		local poseNames: { string } = {}
		local function walk(inst: Instance)
			for _, c in inst:GetChildren() do
				if c:IsA("Pose") then
					table.insert(poseNames, c.Name)
					walk(c)
				end
			end
		end
		local markers: { string } = {}
		for _, kf in keyframes do
			for _, m in kf:GetChildren() do
				if m:IsA("KeyframeMarker") then
					table.insert(markers, `{m.Name}={m.Value}@{math.round(kf.Time * 1000) / 1000}`)
				end
			end
		end
		if keyframes[1] then
			walk(keyframes[1])
		end
		s7.name = (seq :: KeyframeSequence).Name
		s7.className = (seq :: Instance).ClassName
		s7.loop = (seq :: KeyframeSequence).Loop
		s7.priority = tostring((seq :: KeyframeSequence).Priority)
		s7.keyframes = #keyframes
		s7.duration = if #keyframes > 0 then keyframes[#keyframes].Time else 0
		s7.poseNames = poseNames
		s7.markers = markers
		s7.posesMatch = table.concat(poseNames, ",") == table.concat(EXPECTED_POSES, ",")
		-- One value check: FrontL_Upper at keyframe 6 (phase pi/2) is a 0.6 rad swing about X.
		local kf6 = keyframes[6]
		local pose = kf6 and kf6:FindFirstChild("FrontL_Upper", true) :: Pose?
		if pose then
			local rx, ry, rz = pose.CFrame:ToOrientation()
			s7.frontL6 = { math.round(rx * 1e4) / 1e4, math.round(ry * 1e4) / 1e4, math.round(rz * 1e4) / 1e4 }
		end
		if not s7.posesMatch then
			table.insert(failures, "S7: pose names differ from the clip")
		end
		-- Animator path: an AnimationController on a bare model loads the same asset as a track.
		local model = Instance.new("Model")
		local root = Instance.new("Part")
		root.Name = "RootPart"
		root.Anchored = true
		root.Parent = model
		model.PrimaryPart = root
		local controller = Instance.new("AnimationController")
		controller.Parent = model
		local animator = Instance.new("Animator")
		animator.Parent = controller
		model.Parent = workspace
		local anim = Instance.new("Animation")
		anim.AnimationId = `rbxassetid://{ANIMATION_ID}`
		local trackOk, track = try("Animator:LoadAnimation", function()
			return animator:LoadAnimation(anim)
		end)
		if trackOk then
			local waited = 0
			while (track :: AnimationTrack).Length == 0 and waited < 5 do
				waited += task.wait(0.1)
			end
			s7.trackLength = (track :: AnimationTrack).Length
			s7.trackLooped = (track :: AnimationTrack).Looped
			s7.trackPriority = tostring((track :: AnimationTrack).Priority)
		else
			s7.trackError = track
		end
		model:Destroy()
	end
	result.s7 = s7
end

-- ---- S8a / S8c2 -----------------------------------------------------------------------------------
local function describeMeshPart(part: MeshPart): { [string]: any }
	local d: { [string]: any } = {
		name = part.Name,
		meshId = readProbe(part, "MeshId"),
		textureId = readProbe(part, "TextureID"),
		size = vec(part.Size),
		meshSize = readProbe(part, "MeshSize"),
		collisionFidelity = readProbe(part, "CollisionFidelity"),
		renderFidelity = readProbe(part, "RenderFidelity"),
		material = tostring(part.Material),
		color = tostring(part.Color),
		canCollide = part.CanCollide,
		anchored = part.Anchored,
		children = {},
	}
	for _, c in part:GetChildren() do
		table.insert(d.children, `{c.ClassName}:{c.Name}`)
		if c:IsA("SurfaceAppearance") then
			d.surfaceAppearance = {
				colorMap = readProbe(c, "ColorMap"),
				normalMap = readProbe(c, "NormalMap"),
				roughnessMap = readProbe(c, "RoughnessMap"),
				metalnessMap = readProbe(c, "MetalnessMap"),
				alphaMode = readProbe(c, "AlphaMode"),
				color = readProbe(c, "Color"),
			}
		end
	end
	return d
end

-- Rays through a hollow log lying along Z, centred on its pivot: the bore ray tells the collision
-- shape apart (Box and Hull block the bore, PreciseConvexDecomposition lets it through).
local function rays(part: BasePart): { [string]: any }
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { part }
	local c = part.Position
	local out: { [string]: any } = {}
	local cases = {
		boreAlongZ = { c + Vector3.new(0, 0, -10), Vector3.new(0, 0, 20) },
		downOnTop = { c + Vector3.new(0, 10, 0), Vector3.new(0, -20, 0) },
		sideAlongX = { c + Vector3.new(-10, 0, 0), Vector3.new(20, 0, 0) },
	}
	for name, case in cases do
		local ok, hit = try(name, function()
			return workspace:Raycast(case[1], case[2], params)
		end)
		if not ok then
			out[name] = hit
		elseif hit == nil then
			out[name] = "miss"
		else
			out[name] = { distance = math.round(hit.Distance * 1000) / 1000, normal = vec(hit.Normal) }
		end
	end
	return out
end

local function appearanceWrites(part: MeshPart): { [string]: any }
	local w: { [string]: any } = {
		meshPartColor = writeProbe(part, "Color", Color3.fromRGB(200, 120, 40)),
		textureId = writeProbe(part, "TextureID", "rbxassetid://89657770904034"),
		collisionFidelity = writeProbe(part, "CollisionFidelity", Enum.CollisionFidelity.Box),
		meshId = writeProbe(part, "MeshId", "rbxassetid://1"),
	}
	local existing = part:FindFirstChildOfClass("SurfaceAppearance")
	if existing then
		w.loadedSurfaceAppearanceColor = writeProbe(existing, "Color", Color3.fromRGB(255, 140, 60))
		w.loadedSurfaceAppearanceAlphaMode = writeProbe(existing, "AlphaMode", Enum.AlphaMode.TintMask)
	end
	local ok, sa = try("Instance.new SurfaceAppearance", function()
		return Instance.new("SurfaceAppearance")
	end)
	if ok then
		local s = sa :: SurfaceAppearance
		w.newSurfaceAppearanceParent = writeProbe(s, "Parent", part)
		w.newSurfaceAppearanceColor = writeProbe(s, "Color", Color3.fromRGB(255, 140, 60))
		w.newSurfaceAppearanceAlphaMode = writeProbe(s, "AlphaMode", Enum.AlphaMode.TintMask)
		w.newSurfaceAppearanceColorMap = writeProbe(s, "ColorMap", "rbxassetid://89657770904034")
		w.newSurfaceAppearanceColorMapContent = writeProbe(s, "ColorMapContent", Content.fromAssetId(89657770904034))
		s:Destroy()
	else
		w.newSurfaceAppearance = sa
	end
	return w
end

do
	local s8: { [string]: any } = { modelId = MODEL_ID }
	local t0 = os.clock()
	local ok, model = try("LoadAsset", function()
		return InsertService:LoadAsset(MODEL_ID)
	end)
	s8.loadMs = math.round((os.clock() - t0) * 1000)
	if not ok then
		s8.error = model
		table.insert(failures, "S8a: " .. tostring(model))
	else
		local tree: { string } = {}
		local meshParts: { MeshPart } = {}
		for _, d in (model :: Instance):GetDescendants() do
			table.insert(tree, `{d:GetFullName()} ({d.ClassName})`)
			if d:IsA("MeshPart") then
				table.insert(meshParts, d)
			end
		end
		s8.tree = tree
		s8.meshParts = {}
		(model :: Model):PivotTo(CFrame.new(ORIGIN));
		(model :: Instance).Parent = workspace
		for _, p in meshParts do
			p.Anchored = true
			local d = describeMeshPart(p)
			d.rays = rays(p)
			table.insert(s8.meshParts, d)
		end
		if #meshParts == 0 then
			table.insert(failures, "S8a: no MeshPart in the loaded model")
		else
			local first = meshParts[1]
			-- Runtime kit path: a fresh MeshPart from the uploaded mesh (what a runtime swap would use).
			local cOk, mp = try("CreateMeshPartAsync", function()
				return AssetService:CreateMeshPartAsync(first.MeshContent)
			end)
			if cOk then
				local m = mp :: MeshPart
				m.Anchored = true
				m.CFrame = CFrame.new(ORIGIN + Vector3.new(20, 0, 0))
				m.Parent = workspace
				local d = describeMeshPart(m)
				d.rays = rays(m)
				s8.createMeshPart = d
				local pOk, precise = try("CreateMeshPartAsync precise", function()
					return AssetService:CreateMeshPartAsync(first.MeshContent, {
						CollisionFidelity = Enum.CollisionFidelity.PreciseConvexDecomposition,
					})
				end)
				if pOk then
					local q = precise :: MeshPart
					q.Anchored = true
					q.CFrame = CFrame.new(ORIGIN + Vector3.new(40, 0, 0))
					q.Parent = workspace
					s8.createMeshPartPrecise = { collisionFidelity = tostring(q.CollisionFidelity), rays = rays(q) }
				else
					s8.createMeshPartPrecise = precise
				end
			else
				s8.createMeshPart = mp
			end
			s8.c2 = appearanceWrites(first)
		end
	end
	-- Lune-written MeshPart (present only on a probe place version).
	local probe = workspace:FindFirstChild("S8Probe")
	if probe then
		local lune: { [string]: any } = {}
		for _, d in probe:GetDescendants() do
			if d:IsA("MeshPart") then
				local desc = describeMeshPart(d)
				desc.rays = rays(d)
				lune[d.Name] = desc
			end
		end
		s8.luneWritten = lune
	end
	result.s8 = s8
end

result.failures = failures
result.ok = #failures == 0
return result
