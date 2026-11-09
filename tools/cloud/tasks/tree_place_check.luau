--!strict
-- Tree art in the saved place: every Tree model with ArtAsset carries its MeshParts with a mesh and a colour
-- texture (and no SurfaceAppearance as saved); then Server/Assets/TreeArt's move of the uploaded models'
-- SurfaceAppearances is run on a sample and counted.
--   node tools/cloud/cloud.mjs run_engine_tests tools/cloud/tasks/tree_place_check.luau --version <v> --place ci
local InsertService = game:GetService("InsertService")

local town = workspace:FindFirstChild("Town")
local result: { [string]: any } = { suite = "tree_place_check", placeVersion = game.PlaceVersion }
if town == nil then
	result.error = "Workspace.Town missing"
	return result
end

local trees: { Model } = {}
for _, d in town:GetDescendants() do
	if d:IsA("Model") and d:GetAttribute("ArtAsset") ~= nil then
		table.insert(trees, d)
	end
end
local meshParts, withMesh, withTexture, sizeOk, savedAppearances, visibleProxies = 0, 0, 0, 0, 0, 0
local sample: { any } = {}
for _, tree in trees do
	for _, p in tree:GetChildren() do
		if p:IsA("MeshPart") then
			meshParts += 1
			if p.MeshId ~= "" then
				withMesh += 1
			end
			if p.TextureID ~= "" then
				withTexture += 1
			end
			if (p.MeshSize - p.Size).Magnitude < 0.01 then
				sizeOk += 1
			end
			if p:FindFirstChildOfClass("SurfaceAppearance") then
				savedAppearances += 1
			end
			if #sample < 3 then
				table.insert(sample, {
					tree = tree.Name,
					part = p.Name,
					meshId = p.MeshId,
					textureId = p.TextureID,
					size = tostring(p.Size),
					meshSize = tostring(p.MeshSize),
					canCollide = p.CanCollide,
					material = tostring(p.Material),
				})
			end
		elseif p:IsA("BasePart") and p.Transparency < 1 then
			visibleProxies += 1
		end
	end
end
result.trees = #trees
result.meshParts = meshParts
result.withMesh = withMesh
result.withTexture = withTexture
result.sizeOk = sizeOk
result.savedAppearances = savedAppearances
result.visibleProxies = visibleProxies
result.sample = sample

-- the runtime move, on the first 6 trees (the same steps as Server/Assets/TreeArt.apply)
local moved, loaded, failed = 0, 0, 0
local t0 = os.clock()
for i = 1, math.min(6, #trees) do
	local tree = trees[i]
	local ok, asset = pcall(function()
		return InsertService:LoadAsset(tonumber(tree:GetAttribute("ArtAsset")) :: number)
	end)
	if ok and asset then
		loaded += 1
		for _, d in asset:GetDescendants() do
			if d:IsA("MeshPart") then
				local appearance = d:FindFirstChildOfClass("SurfaceAppearance")
				local target = tree:FindFirstChild(d.Name)
				if appearance and target and target:IsA("MeshPart") and (target :: MeshPart).MeshId == d.MeshId then
					appearance.Parent = target
					moved += 1
				end
			end
		end
		asset:Destroy()
	else
		failed += 1
		result.loadError = tostring(asset)
	end
end
result.runtime =
	{ loaded = loaded, failed = failed, moved = moved, seconds = math.floor((os.clock() - t0) * 100) / 100 }
result.ok = meshParts == 392
	and withMesh == meshParts
	and withTexture == meshParts
	and sizeOk == meshParts
	and savedAppearances == 0
	and visibleProxies == 0
	and failed == 0
	and moved > 0
return result
