--!strict
-- ServerScriptService.Server.Assets.TreeArt
-- Runtime art for the baked trees (BUILD_PLAN D12). The place holds each tree's Blender meshes as MeshParts with
-- the colour map on TextureID (WorldGen/Factory), which the Open Cloud publisher keeps; a SurfaceAppearance is
-- never saved into the place. Per tree, off the boot path:
--   * a tree whose trunk route has a v2 Model with an id (the new generator's tree, data/art/trees_v2.json ->
--     Shared/Generated/TreeArtNext) has its baked meshes swapped for that Model's: they are pivoted onto the tree's
--     root and made visual only like the baked ones (the baked proxies keep colliding), the leaf sprays drawn from
--     both sides with their alpha cut (where the engine lets a script set that; the rebake path,
--     tools/blender/trees/harvest_meshes.py --art data/art/trees_v2.json, bakes it in);
--     (a tree already baked from its v2 Model, ArtAsset = its id, only gets that Model's maps, as below);
--   * any other tree from an uploaded Model (the Tree model's ArtAsset attribute) gets that Model's
--     SurfaceAppearances (colour, normal and roughness maps) moved onto its baked parts of the same name.
-- A tree whose Model does not load keeps what was baked, so nothing here can leave a tree bare.
-- Interface: trees(town, next?) -> { Model }; apply(tree, asset) -> moved; swap(tree, asset, pivot, env?) -> parts;
--   nextByTrunk(list?) -> { [trunkRoute]: Next }; run(town, opts?) -> { trees, upgraded, swapped, failed, seconds }
--   (yields: call it from a task)
-- No side effects on require.

local Import = require("../Import")

local TreeArt = {}

-- the MeshParts a tree Model carries (tools/blender/trees: build_trees.py LEAF_PARTS, Bark, Apples)
TreeArt.MESHES = table.freeze({ Bark = true, LeavesShade = true, LeavesMid = true, LeavesSun = true, Apples = true })

export type Next = { trunkRoute: number, assetId: string?, pivot: { number } }
export type Env = { CFrame: any, Enum: any }
export type Opts = {
	load: ((assetId: number) -> Instance)?, -- default InsertService:LoadAsset
	pause: number?, -- seconds between trees (default 0.05)
	near: Vector3?, -- load the trees nearest this point first
	next: { Next }?, -- default Shared/Generated/TreeArtNext (absent: no swaps)
	env: Env?, -- default the engine's CFrame and Enum (Lune specs pass @lune/roblox)
}

local function engineEnv(): Env
	return { CFrame = CFrame, Enum = Enum }
end

-- The v2 Models that have an id, by trunk route.
function TreeArt.nextByTrunk(list: { Next }?): { [number]: Next }
	local src: { Next } = list
		or (function(): { Next }
			local ok, mod = pcall(function(): any
				return (Import.shared("Data") :: any).default():module("TreeArtNext")
			end)
			return if ok and type(mod) == "table" then mod else {}
		end)()
	local out: { [number]: Next } = {}
	for _, n in src do
		if n.assetId and n.assetId ~= "" then
			out[n.trunkRoute] = n
		end
	end
	return out
end

-- Every baked tree that came from an uploaded Model or has a v2 Model to swap in.
function TreeArt.trees(town: Instance, next: { [number]: Next }?): { Model }
	local out: { Model } = {}
	for _, d in town:GetDescendants() do
		if d:IsA("Model") then
			local trunk = tonumber(d:GetAttribute("TrunkRoute"))
			if d:GetAttribute("ArtAsset") ~= nil or (next and trunk and next[trunk]) then
				table.insert(out, d)
			end
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

-- A leaf spray part: alpha-cut cards seen from both sides (a script may not be allowed to set these: then they stay
-- as the importer left them, or as baked).
local function cutLeaves(p: MeshPart, e: Env)
	if string.sub(p.Name, 1, 6) ~= "Leaves" then
		return
	end
	pcall(function()
		(p :: any).DoubleSided = true
	end)
	local look = p:FindFirstChildOfClass("SurfaceAppearance")
	if look then
		pcall(function()
			(look :: any).AlphaMode = e.Enum.AlphaMode.Transparency
		end)
	end
end

-- Replaces the baked tree's meshes (TreeArt.MESHES) with the v2 Model's: `asset` is what LoadAsset returned (the
-- uploaded Model inside it), `pivot` the tree's root (its FBX origin). Returns the parts put in; 0 (and the tree
-- left as baked) when the Model has no Bark.
function TreeArt.swap(tree: Instance, asset: Instance, pivot: { number }, env: Env?): number
	local e = env or engineEnv()
	local model = asset:FindFirstChildWhichIsA("Model") or asset
	local fresh: { MeshPart } = {}
	local bark = false
	for _, d in model:GetDescendants() do
		if d:IsA("MeshPart") and TreeArt.MESHES[d.Name] then
			table.insert(fresh, d)
			bark = bark or d.Name == "Bark"
		end
	end
	if not bark then
		return 0
	end
	-- (Model:PivotTo, done part by part: the uploaded Model's pivot is its FBX origin, the tree's root)
	local from = if model:IsA("Model")
		then (function(): any
			local ok, cf = pcall(function(): any
				return (model :: any):GetPivot()
			end)
			return if ok then cf else (model :: any).WorldPivot
		end)()
		else e.CFrame.new()
	local move = e.CFrame.new(pivot[1], pivot[2], pivot[3]) * from:Inverse()
	for _, d in tree:GetChildren() do
		if d:IsA("MeshPart") and TreeArt.MESHES[d.Name] then
			d:Destroy()
		end
	end
	for _, p in fresh do
		p.CFrame = move * p.CFrame
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = true
		cutLeaves(p, e)
		p.Parent = tree
	end
	return #fresh
end

function TreeArt.run(
	town: Instance,
	opts: Opts?
): { trees: number, upgraded: number, swapped: number, failed: number, seconds: number }
	local o: Opts = opts or {}
	local load: (assetId: number) -> Instance = o.load
		or function(assetId: number): Instance
			return game:GetService("InsertService"):LoadAsset(assetId)
		end
	local next = TreeArt.nextByTrunk(o.next)
	local list = TreeArt.trees(town, next)
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
	local upgraded, swapped, failed = 0, 0, 0
	for _, tree in list do
		local n = next[tonumber(tree:GetAttribute("TrunkRoute")) or -1]
		local assetId = tonumber(if n then n.assetId else tree:GetAttribute("ArtAsset"))
		local ok, asset = pcall(function(): Instance
			return load(assetId :: number)
		end)
		if ok and asset then
			if n and tostring(tree:GetAttribute("ArtAsset")) == n.assetId then
				-- rebaked from the v2 Model already (harvest_meshes.py --art): only its maps move over
				if TreeArt.apply(tree, asset) > 0 then
					upgraded += 1
				end
				for _, p in tree:GetChildren() do
					if p:IsA("MeshPart") then
						cutLeaves(p, o.env or engineEnv())
					end
				end
			elseif n then
				if TreeArt.swap(tree, asset, n.pivot, o.env) > 0 then
					swapped += 1
				else
					failed += 1
				end
			elseif TreeArt.apply(tree, asset) > 0 then
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
	return { trees = #list, upgraded = upgraded, swapped = swapped, failed = failed, seconds = os.clock() - t0 }
end

return TreeArt
