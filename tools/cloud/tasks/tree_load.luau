--!strict
-- Tree art check (tools/blender/trees): InsertService:LoadAsset on uploaded tree Models, timed, and a
-- description of what arrived (MeshParts, sizes, SurfaceAppearance) plus the data/art/trees.json
-- placement recipe (p.CFrame = CFrame.new(pivot + parts[name].center)) checked against the loaded parts.
-- The TREES table below is filled in by tools/blender/trees/make_load_task.py from data/art/trees.json:
--   python3 -I tools/blender/trees/make_load_task.py --ids 0,40,85 > build/art/trees/tree_load_task.luau
--   node tools/cloud/cloud.mjs run_engine_tests build/art/trees/tree_load_task.luau --version <v> --place ci

type PartSpec = { center: { number }, size: { number } }
type TreeSpec = { index: number, label: string, assetId: number, pivot: { number }, parts: { [string]: PartSpec } }

local TREES: { TreeSpec } = {} -- @@TREES@@

local InsertService = game:GetService("InsertService")

local function r3(x: number): number
	return math.round(x * 1000) / 1000
end
local function vec(v: Vector3): { number }
	return { r3(v.X), r3(v.Y), r3(v.Z) }
end

local result: { [string]: any } = { suite = "tree_load", placeVersion = game.PlaceVersion, trees = {} }
local ok = true
local holder = Instance.new("Folder")
holder.Name = "TreeLoadCheck"
holder.Parent = workspace

for _, spec in TREES do
	local entry: { [string]: any } = { index = spec.index, label = spec.label, assetId = spec.assetId }
	local t0 = os.clock()
	local good, model = pcall(function()
		return InsertService:LoadAsset(spec.assetId)
	end)
	entry.loadSeconds = r3(os.clock() - t0)
	if not good then
		entry.error = tostring(model)
		ok = false
		table.insert(result.trees, entry)
		continue
	end
	model.Parent = holder
	-- the asset container holds the uploaded Model
	local tree: Instance = model
	local kids = model:GetChildren()
	if #kids == 1 and kids[1]:IsA("Model") then
		tree = kids[1]
	end
	entry.container = model.ClassName
	entry.treeClass = tree.ClassName
	entry.treeName = tree.Name
	local parts = {}
	local meshParts = 0
	local surfaceAppearances = 0
	for _, d in tree:GetDescendants() do
		if d:IsA("MeshPart") then
			meshParts += 1
			local sa = d:FindFirstChildOfClass("SurfaceAppearance")
			if sa then
				surfaceAppearances += 1
			end
			parts[d.Name] = {
				size = vec(d.Size),
				position = vec(d.Position),
				meshSize = vec(d.MeshSize),
				meshId = tostring(d.MeshId),
				textureId = tostring(d.TextureID),
				renderFidelity = tostring(d.RenderFidelity),
				collisionFidelity = tostring(d.CollisionFidelity),
				doubleSided = (function()
					local s, v = pcall(function()
						return (d :: any).DoubleSided
					end)
					return if s then v else "unreadable"
				end)(),
				surfaceAppearance = if sa
					then {
						alphaMode = tostring(sa.AlphaMode),
						color = vec(Vector3.new(sa.Color.R, sa.Color.G, sa.Color.B)),
					}
					else false,
			}
		end
	end
	entry.meshParts = meshParts
	entry.surfaceAppearances = surfaceAppearances
	entry.parts = parts
	if tree:IsA("Model") then
		local pv = (tree :: Model):GetPivot()
		entry.modelPivot = vec(pv.Position)
		local cf, size = (tree :: Model):GetBoundingBox()
		entry.modelBoxCenter = vec(cf.Position)
		entry.modelBoxSize = vec(size)
	end
	-- placement recipe and consistency with the build's bounds
	local pivot = Vector3.new(spec.pivot[1], spec.pivot[2], spec.pivot[3])
	local maxSizeErr, maxRelErr = 0, 0
	local ref: BasePart? = nil
	local refCenter: Vector3? = nil
	local loadedPos: { [string]: Vector3 } = {}
	for name in spec.parts do
		local mp = tree:FindFirstChild(name, true)
		if mp and mp:IsA("BasePart") then
			loadedPos[name] = mp.Position -- as loaded, before the recipe moves anything
		end
	end
	for name, p in spec.parts do
		local mp = tree:FindFirstChild(name, true)
		if mp and mp:IsA("BasePart") then
			local want = Vector3.new(p.size[1], p.size[2], p.size[3])
			maxSizeErr = math.max(maxSizeErr, (mp.Size - want).Magnitude)
			local c = Vector3.new(p.center[1], p.center[2], p.center[3])
			if ref == nil then
				ref, refCenter = mp, c
			else
				-- as loaded: the offset between two parts should equal the offset of their centres
				local loadedRel = loadedPos[name] - loadedPos[(ref :: BasePart).Name]
				local wantRel = c - (refCenter :: Vector3)
				maxRelErr = math.max(maxRelErr, (loadedRel - wantRel).Magnitude)
			end
			mp.Anchored = true
			mp.CFrame = CFrame.new(pivot + c)
		else
			entry.missingPart = name
			ok = false
		end
	end
	-- as loaded, the Model pivot sits at the FBX origin = the tree root: check PivotTo(pivot) lands each part
	local maxPivotErr = 0
	if tree:IsA("Model") then
		local pv = (tree :: Model):GetPivot().Position
		for name, p in spec.parts do
			local lp = loadedPos[name]
			if lp then
				local want = Vector3.new(p.center[1], p.center[2], p.center[3])
				maxPivotErr = math.max(maxPivotErr, ((lp - pv) - want).Magnitude)
			end
		end
	end
	entry.pivotRecipeMaxErrStuds = r3(maxPivotErr)
	entry.maxSizeErrStuds = r3(maxSizeErr)
	entry.maxRelativeOffsetErrStuds = r3(maxRelErr)
	if maxSizeErr > 0.05 then
		ok = false
	end
	-- a ray straight down the trunk axis from above the canopy must hit the tree near the pivot
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { tree }
	local bark = tree:FindFirstChild("Bark", true)
	if bark and bark:IsA("BasePart") then
		local side = workspace:Raycast(pivot + Vector3.new(30, 6, 0), Vector3.new(-60, 0, 0), params)
		entry.sideRayAt6Studs = if side
			then { instance = side.Instance.Name, x = r3(side.Position.X - pivot.X) }
			else false
	end
	table.insert(result.trees, entry)
	print(
		`tree {spec.index} {spec.label}: {meshParts} MeshParts, {surfaceAppearances} SurfaceAppearances, load {entry.loadSeconds}s`
	)
end

holder:Destroy()
result.ok = ok
return result
