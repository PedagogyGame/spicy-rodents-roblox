--!strict
-- ServerScriptService.Server.Assets.TreeArt
-- Runtime PBR for the baked trees (BUILD_PLAN D12). The place holds each tree's Blender meshes as
-- MeshParts with the colour map on TextureID (WorldGen/Factory), which the Open Cloud publisher keeps;
-- a SurfaceAppearance is never saved into the place. This module loads every tree's uploaded Model
-- (the Tree model's ArtAsset attribute) and moves its SurfaceAppearances (colour, normal and roughness
-- maps) onto the baked parts of the same name. A tree whose asset does not load keeps its colour
-- texture, so nothing here can leave a tree bare.
-- Interface: trees(town) -> { Model }; apply(tree, asset) -> moved; run(town, opts?) -> { trees, upgraded,
--   failed, seconds } (yields: call it from a task)
-- No side effects on require.

local TreeArt = {}

export type Opts = {
	load: ((assetId: number) -> Instance)?, -- default InsertService:LoadAsset
	pause: number?, -- seconds between trees (default 0.05)
	near: Vector3?, -- load the trees nearest this point first
}

-- Every baked tree that came from an uploaded Model.
function TreeArt.trees(town: Instance): { Model }
	local out: { Model } = {}
	for _, d in town:GetDescendants() do
		if d:IsA("Model") and d:GetAttribute("ArtAsset") ~= nil then
			table.insert(out, d)
		end
	end
	return out
end

-- Moves the SurfaceAppearance of each MeshPart in `asset` onto the MeshPart of the same name in `tree`.
function TreeArt.apply(tree: Instance, asset: Instance): number
	local moved = 0
	for _, d in asset:GetDescendants() do
		if d:IsA("MeshPart") then
			local appearance = d:FindFirstChildOfClass("SurfaceAppearance")
			local target = tree:FindFirstChild(d.Name)
			if
				appearance
				and target
				and target:IsA("MeshPart")
				and target:FindFirstChildOfClass("SurfaceAppearance") == nil
			then
				appearance.Parent = target
				moved += 1
			end
		end
	end
	return moved
end

function TreeArt.run(town: Instance, opts: Opts?): { trees: number, upgraded: number, failed: number, seconds: number }
	local o: Opts = opts or {}
	local load = o.load
		or function(assetId: number): Instance
			return game:GetService("InsertService"):LoadAsset(assetId)
		end
	local list = TreeArt.trees(town)
	local near = o.near
	if near then
		local function distance(m: Model): number
			return (m:GetPivot().Position - near).Magnitude
		end
		table.sort(list, function(a, b)
			return distance(a) < distance(b)
		end)
	end
	local t0 = os.clock()
	local upgraded, failed = 0, 0
	for _, tree in list do
		local assetId = tonumber(tree:GetAttribute("ArtAsset"))
		local ok, asset = pcall(function(): Instance
			return load(assetId :: number)
		end)
		if ok and asset then
			if TreeArt.apply(tree, asset) > 0 then
				upgraded += 1
			end
			asset:Destroy()
		else
			failed += 1
		end
		local pause = o.pause or 0.05
		if pause > 0 then
			task.wait(pause)
		end
	end
	return { trees = #list, upgraded = upgraded, failed = failed, seconds = os.clock() - t0 }
end

return TreeArt
