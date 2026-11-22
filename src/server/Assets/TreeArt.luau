--!strict
-- ServerScriptService.Server.Assets.TreeArt
-- Runtime art for the baked trees (BUILD_PLAN D12). The place holds each tree's Blender meshes as MeshParts with
-- the colour map on TextureID (WorldGen/Factory), which the Open Cloud publisher keeps; a SurfaceAppearance is
-- never saved into the place. Per tree, off the boot path:
--   * a tree whose trunk route has a v2 Model with an id (the new generator's tree, data/art/trees_v2.json ->
--     Shared/Generated/TreeArtNext) and baked meshes of its own has those swapped for the Model's: they are pivoted
--     onto the tree's root and made visual only like the baked ones (the baked proxies keep colliding), the leaf
--     sprays drawn from both sides with their alpha cut and the data's leaf green as their part colour. The engine
--     must take both leaf writes (DoubleSided, AlphaMode Transparency: S8 left them unverified for a script): they are
--     read back before anything baked goes, and a Model whose leaves did not take them is not swapped in. This is the
--     fallback: the way to ship v2 is the rebake (tools/blender/trees/harvest_meshes.py --art
--     data/art/trees_v2.json, then the bake), where Lune writes DoubleSided and Box collision fidelity, which a
--     script cannot (a swapped part keeps the importer's Default fidelity);
--     (a tree already baked from its v2 Model, ArtAsset = its id, only gets that Model's maps, as below);
--   * any other tree from an uploaded Model (the Tree model's ArtAsset attribute), and a tree whose v2 Model did not
--     load or swap, gets that Model's SurfaceAppearances (colour, normal and roughness maps) moved onto its baked
--     parts of the same name.
-- A tree whose Model does not load keeps what was baked, so nothing here can leave a tree bare.
-- Green from the first frame (owner, 2026-11-21: "make sure they eventually populate as being green on the leaves, each
-- tree"): the baked leaf sprays carried the importer's grey as their part colour, which is what shows until a spray's
-- colour map has arrived (and under its clear texels). greenLeaves gives every leaf spray in the town its tree's leaf
-- green (the v2 data's, else TreeArt.LEAF) before anything is loaded, and every spray put in later gets it too.
-- Interface: trees(town, next?) -> { Model }; apply(tree, asset) -> moved; swap(tree, asset, pivot, env?, leaf?) -> parts;
--   nextByTrunk(list?) -> { [trunkRoute]: Next }; run(town, opts?) -> { trees, upgraded, swapped, failed, seconds }
--   (yields: call it from a task)
-- No side effects on require.

local Import = require("../Import")

local TreeArt = {}

-- the MeshParts a tree Model carries (tools/blender/trees: build_trees.py LEAF_PARTS, Bark, Apples)
TreeArt.MESHES = table.freeze({ Bark = true, LeavesShade = true, LeavesMid = true, LeavesSun = true, Apples = true })

-- the leaf green of a tree with none of its own in the data (the v2 trees' run 100-125, 141-161, 73-83)
TreeArt.LEAF = table.freeze({ 106, 148, 77 })

-- covers: the D32 grown boughs (route ids, Shared/World/TreeShapes) this Model draws: the baked stand-ins for them
-- (parts marked Grown = route) are hidden under it once it is swapped in
export type Next = {
	trunkRoute: number,
	assetId: string?,
	pivot: { number },
	leaf: { number }?,
	covers: { number }?,
}
export type Env = { CFrame: any, Enum: any, Color3: any }
export type Opts = {
	load: ((assetId: number) -> Instance)?, -- default InsertService:LoadAsset
	pause: number?, -- seconds between trees (default 0.05)
	near: Vector3?, -- load the trees nearest this point first
	next: { Next }?, -- default Shared/Generated/TreeArtNext (absent: no swaps)
	env: Env?, -- default the engine's CFrame, Enum and Color3 (Lune specs pass @lune/roblox)
}

local function engineEnv(): Env
	return { CFrame = CFrame, Enum = Enum, Color3 = Color3 }
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

local function isLeaves(p: Instance): boolean
	return string.sub(p.Name, 1, 6) == "Leaves"
end

-- greenLeaves(town, next?, env?) -> sprays: every leaf spray in the town given its tree's leaf green as its part
-- colour (what shows while its colour map is on its way). Cheap: one write a spray, once.
function TreeArt.greenLeaves(town: Instance, next: { [number]: Next }?, env: Env?): number
	local e = env or engineEnv()
	local n = 0
	for _, d in town:GetDescendants() do
		if d:IsA("MeshPart") and isLeaves(d) then
			local tree = d.Parent
			local trunk = if tree then tonumber(tree:GetAttribute("TrunkRoute")) else nil
			local own = if next and trunk and next[trunk] then next[trunk].leaf else nil
			local c = own or TreeArt.LEAF
			d.Color = e.Color3.fromRGB(c[1], c[2], c[3])
			n += 1
		end
	end
	return n
end

-- A leaf spray part: alpha-cut cards seen from both sides (a script may not be allowed to set these: then they stay
-- as the importer left them, or as baked). True when both read back as written.
local function cutLeaves(p: MeshPart, e: Env): boolean
	if not isLeaves(p) then
		return true
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
	local ok, took = pcall(function(): boolean
		return (p :: any).DoubleSided == true
			and look ~= nil
			and (look :: any).AlphaMode == e.Enum.AlphaMode.Transparency
	end)
	return ok and took
end

-- Whether a tree has baked meshes to swap out (the bake's Mesh attribute, or a baked Bark): a tree built of
-- primitives keeps them, and the v2 Model is not laid over it.
local function baked(tree: Instance): boolean
	if tree:GetAttribute("Mesh") == true then
		return true
	end
	local bark = tree:FindFirstChild("Bark")
	return bark ~= nil and bark:IsA("MeshPart")
end

-- Replaces the baked tree's meshes (TreeArt.MESHES) with the v2 Model's: `asset` is what LoadAsset returned (the
-- uploaded Model inside it), `pivot` the tree's root (its FBX origin), `leaf` the leaf sprays' part colour (what
-- shows where a map has not streamed in; default the importer's). Returns the parts put in; 0, and the tree left as
-- baked, when the tree has no baked meshes, the Model has no Bark, or a leaf part did not take DoubleSided and
-- AlphaMode Transparency (read back before anything baked is removed).
function TreeArt.swap(
	tree: Instance,
	asset: Instance,
	pivot: { number },
	env: Env?,
	leaf: { number }?,
	covers: { number }?
): number
	local e = env or engineEnv()
	if not baked(tree) then
		return 0
	end
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
	for _, p in fresh do
		if not cutLeaves(p, e) then
			return 0
		end
		if isLeaves(p) then
			local c = leaf or TreeArt.LEAF
			p.Color = e.Color3.fromRGB(c[1], c[2], c[3])
		end
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
		p.Parent = tree
	end
	if covers then
		TreeArt.hideGrown(tree, covers)
	end
	return #fresh
end

-- hideGrown(tree, covers) -> parts: the baked stand-ins for the grown boughs a Model draws (parts whose Grown
-- attribute names a route in `covers`: Builders/Trees) made unseen: the bark stays as an invisible proxy (it collides
-- and answers rays, like every bough under a mesh), the twigs and leaf clusters go.
function TreeArt.hideGrown(tree: Instance, covers: { number }): number
	local set: { [number]: boolean } = {}
	for _, id in covers do
		set[id] = true
	end
	local n = 0
	for _, d in tree:GetChildren() do
		local id = tonumber(d:GetAttribute("Grown"))
		if id and set[id] and d:IsA("BasePart") then
			n += 1
			if (d :: BasePart).CanCollide then
				d.Transparency = 1
				d.CastShadow = false
			else
				d:Destroy()
			end
		end
	end
	return n
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
	-- (green at once, before the first Model is asked for)
	pcall(TreeArt.greenLeaves, town, next, o.env)
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
	-- a tree's live Model (ArtAsset), loaded and its maps moved over: "moved", "none" (loaded, nothing to move, or
	-- no live Model) or "failed" (did not load)
	local function upgrade(tree: Instance, assetId: number?): string
		if not assetId then
			return "none"
		end
		local ok, asset = pcall(function(): Instance
			return load(assetId)
		end)
		if not (ok and asset) then
			return "failed"
		end
		local moved = TreeArt.apply(tree, asset) > 0
		asset:Destroy()
		return if moved then "moved" else "none"
	end
	for _, tree in list do
		local n = next[tonumber(tree:GetAttribute("TrunkRoute")) or -1]
		local live = tonumber(tree:GetAttribute("ArtAsset"))
		if n and tostring(tree:GetAttribute("ArtAsset")) ~= n.assetId then
			-- the v2 Model swapped in; one that does not load or swap leaves the tree with today's maps
			local ok, asset = pcall(function(): Instance
				return load(tonumber(n.assetId) :: number)
			end)
			local put = 0
			if ok and asset then
				put = TreeArt.swap(tree, asset, n.pivot, o.env, n.leaf, n.covers)
				asset:Destroy()
			end
			if put > 0 then
				swapped += 1
			else
				failed += 1
				if upgrade(tree, live) == "moved" then
					upgraded += 1
				end
			end
		elseif n then
			-- rebaked from the v2 Model already (harvest_meshes.py --art): only its maps move over
			local got = upgrade(tree, live)
			if got == "moved" then
				upgraded += 1
			elseif got == "failed" then
				failed += 1
			end
			for _, p in tree:GetChildren() do
				if p:IsA("MeshPart") then
					cutLeaves(p, o.env or engineEnv())
				end
			end
		else
			local got = upgrade(tree, live)
			if got == "moved" then
				upgraded += 1
			elseif got == "failed" then
				failed += 1
			end
		end
		local pause = o.pause or 0.05
		if pause > 0 then
			task.wait(pause)
		end
	end
	return { trees = #list, upgraded = upgraded, swapped = swapped, failed = failed, seconds = os.clock() - t0 }
end

return TreeArt
