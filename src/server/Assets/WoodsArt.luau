--!strict
-- ServerScriptService.Server.Assets.WoodsArt
-- The D34 woods at runtime (owner, 2026-11-22: "a large scattered introduction of pine trees and other nut trees,
-- making the map have more trees!"; D35: every tree climbable). Each woods tree (Shared/Data:woods(): its kind, place,
-- turn and scale; its climbing routes are data, run by the squirrel's motor like every tree's) becomes a Model
-- Workspace.Woods.Tree_W<i>, outside the town bake (the 27,000-part town budget is the bake's; the woods add 3 parts
-- a tree here):
--   * Trunk_1: an anchored cylinder round the trunk's foot, the trunk route's radius at its foot, up to its first
--     bough (or 24 studs): what the squirrel's and the people's wall tests meet (Client/World/ClientWorld takes a
--     Tree_*'s Trunk* by its round section). Invisible under a Model; the bark's colour as a stand-in without one.
--   * Bark and Leaves: the kind's uploaded Model (tools/blender/trees/grove.py, data/art/woods.json: loaded once a
--     kind with InsertService), its MeshParts cloned, scaled and turned onto the tree's foot, visual only (no
--     collision, no queries, no touch). The leaf cards are two-faced in the mesh; their alpha needs AlphaMode
--     Transparency on the SurfaceAppearance (written, then read back), else the colour map moved onto TextureID
--     (whose alpha the engine honours), else the kind is not drawn and the stand-in stays.
--   * Without a Model (no asset id yet, or it did not load): a stand-in of plain parts, the trunk and a crown
--     (one ball for a broadleaf, two stacked for a pine), so the woods and their climbs are there to see and test.
-- Every tree Model streams as a whole (ModelStreamingMode Atomic). Work is spread over frames (BATCH trees a frame).
-- Interface: start(workspace, opts?) (spawns run); run(workspace, opts?) -> Report (yields unless opts.pause is
--   false); trees(data) -> ({ Tree }, kinds); build(tree, kind, template?, env?) -> Model (one tree; pure over `env`:
--   Lune specs pass @lune/roblox); prepare(asset, leaf?, env) -> templates? (a loaded kind's Bark and Leaves)
-- No side effects on require.

local Import = require("../Import")

local WoodsArt = {}

WoodsArt.FOLDER = "Woods"
WoodsArt.BATCH = 12
WoodsArt.COLLIDER_TOP = 24 -- studs: the trunk collider's height when the first bough is higher
WoodsArt.BARK = table.freeze({ 101, 84, 66 })
WoodsArt.LEAF = table.freeze({ 96, 138, 72 })
WoodsArt.PINE = table.freeze({ 52, 92, 62 })

export type Env = { Instance: any, CFrame: any, Vector3: any, Color3: any, Enum: any }
export type Tree = {
	index: number,
	trunk: number,
	kind: string,
	x: number,
	y: number,
	z: number,
	yaw: number,
	scale: number,
	firstBough: number?, -- studs above the foot (scale 1) where the lowest bough leaves
}
export type Kind = {
	label: string,
	family: string,
	species: string,
	height: number,
	crown: number,
	climb: any,
	art: { assetId: string?, leaf: { number }?, tris: number? }?,
}
export type Report = { trees: number, drawn: number, standIns: number, kinds: number, failed: number, seconds: number }
export type Opts = {
	load: ((assetId: number) -> Instance)?,
	env: Env?,
	pause: boolean?,
	data: any?,
}

local function engineEnv(): Env
	return { Instance = Instance, CFrame = CFrame, Vector3 = Vector3, Color3 = Color3, Enum = Enum }
end

local function rgb(e: Env, c: { number }): any
	return e.Color3.fromRGB(c[1], c[2], c[3])
end

local function quiet(p: any)
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
end

-- the woods trees with their kinds, from Shared/Data (the compiled woods and their expanded trunks)
function WoodsArt.trees(data: any): ({ Tree }, { [string]: Kind })
	local compiled = data:module("TreeShapes") :: any
	if not (compiled and compiled.woods) then
		return {}, {}
	end
	local w = compiled.woods
	local expanded = data:woods()
	local out: { Tree } = {}
	for _, t in expanded.trees do
		if not t.climb then
			local p = w.trees[t.index]
			local k = w.kinds[p.kind]
			local first = nil
			for _, b in k.climb.boughs or {} do
				first = math.min(first or math.huge, b.at)
			end
			table.insert(out, {
				index = t.index,
				trunk = t.trunk,
				kind = p.kind,
				x = p.x,
				y = p.y,
				z = p.z,
				yaw = p.yaw,
				scale = p.scale,
				firstBough = first,
			})
		end
	end
	return out, w.kinds
end

-- build(tree, kind, template?, env): one tree's Model: the collider, and the kind's meshes (`template`: the loaded
-- Model's MeshParts, already made ready by prepare) or the stand-in
function WoodsArt.build(tree: Tree, kind: Kind, template: { any }?, env: Env?): any
	local e = env or engineEnv()
	local m = e.Instance.new("Model")
	m.Name = `Tree_W{tree.index}`
	m:SetAttribute("TrunkRoute", tree.trunk)
	m:SetAttribute("Kind", tree.kind)
	m:SetAttribute("Woods", true)
	pcall(function()
		m.ModelStreamingMode = e.Enum.ModelStreamingMode.Atomic
	end)
	local s = tree.scale
	local base = e.CFrame.new(tree.x, tree.y, tree.z) * e.CFrame.Angles(0, tree.yaw, 0)
	local r = kind.climb.trunk.radius * s
	local top = math.min(WoodsArt.COLLIDER_TOP, (tree.firstBough or kind.climb.trunk.height) * s)
	top = math.max(top, 6)
	local trunk = e.Instance.new("Part")
	trunk.Name = "Trunk_1"
	trunk.Shape = e.Enum.PartType.Cylinder
	trunk.Anchored = true
	trunk.CanCollide = true
	trunk.CanQuery = true
	trunk.CanTouch = false
	trunk.Material = e.Enum.Material.Wood
	trunk.Color = rgb(e, WoodsArt.BARK)
	-- (a cylinder's axis is its local X: stood up, from 2 studs under the ground)
	trunk.Size = e.Vector3.new(top + 2, 2 * r, 2 * r)
	trunk.CFrame = e.CFrame.new(tree.x, tree.y + top / 2 - 1, tree.z) * e.CFrame.Angles(0, 0, math.pi / 2)
	trunk.Parent = m
	if template then
		trunk.Transparency = 1
		trunk.CastShadow = false
		for _, src in template do
			local p = src:Clone()
			local rel = src:GetAttribute("WoodsOffset") :: any
			local off = e.CFrame.new(rel.X * s, rel.Y * s, rel.Z * s)
			p.Size = src.Size * s
			p.CFrame = base * off
			quiet(p)
			p.CastShadow = true
			p.Parent = m
		end
	else
		-- the stand-in: the trunk drawn to the route's top, and a crown
		local h = kind.climb.trunk.height * s
		local col = rgb(e, WoodsArt.BARK)
		local stem = e.Instance.new("Part")
		stem.Name = "StandInTrunk"
		stem.Shape = e.Enum.PartType.Cylinder
		stem.Size = e.Vector3.new(h, 2 * r * 0.8, 2 * r * 0.8)
		stem.CFrame = e.CFrame.new(tree.x, tree.y + h / 2, tree.z) * e.CFrame.Angles(0, 0, math.pi / 2)
		stem.Color = col
		stem.Material = e.Enum.Material.Wood
		quiet(stem)
		stem.Parent = m
		local pine = kind.family == "pine"
		local leaf =
			rgb(e, if kind.art and kind.art.leaf then kind.art.leaf elseif pine then WoodsArt.PINE else WoodsArt.LEAF)
		local crowns = if pine then { { 0.42, 0.95 }, { 0.72, 0.6 } } else { { 0.66, 1.0 } }
		for i, c in crowns do
			local d = 2 * kind.crown * s * c[2]
			local ball = e.Instance.new("Part")
			ball.Name = `StandInCrown{i}`
			ball.Shape = e.Enum.PartType.Ball
			ball.Size = e.Vector3.new(d, d, d)
			ball.CFrame = e.CFrame.new(tree.x, tree.y + kind.height * s * c[1], tree.z)
			ball.Color = leaf
			ball.Material = e.Enum.Material.LeafyGrass
			quiet(ball)
			ball.CastShadow = true
			ball.Parent = m
		end
	end
	return m
end

-- prepare(asset, leaf, env): the loaded Model's Bark and Leaves as templates (their offset from the Model's pivot, the
-- FBX origin = the ground under the foot, kept as an attribute), the leaves' alpha made to work; nil if it cannot be
local function prepare(asset: any, leaf: { number }?, e: Env): { any }?
	local model = asset:FindFirstChildWhichIsA("Model") or asset
	local pivot = if model:IsA("Model")
		then (function(): any
			local ok, cf = pcall(function(): any
				return model:GetPivot()
			end)
			return if ok then cf else e.CFrame.new()
		end)()
		else e.CFrame.new()
	local out = {}
	for _, d in model:GetDescendants() do
		if d:IsA("MeshPart") and (d.Name == "Bark" or d.Name == "Leaves") then
			local rel = pivot:ToObjectSpace(d.CFrame)
			d:SetAttribute("WoodsOffset", rel.Position)
			if d.Name == "Leaves" then
				local look = d:FindFirstChildOfClass("SurfaceAppearance")
				local took = false
				if look then
					pcall(function()
						(look :: any).AlphaMode = e.Enum.AlphaMode.Transparency
					end)
					took = (look :: any).AlphaMode == e.Enum.AlphaMode.Transparency
					if not took then
						-- the colour map on TextureID instead (its alpha is honoured), the SurfaceAppearance gone
						local ok = pcall(function()
							(d :: any).TextureID = (look :: any).ColorMap
						end)
						if ok and (d :: any).TextureID ~= "" then
							look:Destroy()
							took = true
						end
					end
				end
				if not took then
					return nil
				end
				if leaf then
					d.Color = rgb(e, leaf)
				end
			end
			table.insert(out, d)
		end
	end
	return if #out >= 2 then out else nil
end
WoodsArt.prepare = prepare

function WoodsArt.run(root: Instance, opts: Opts?): Report
	local o: Opts = opts or {}
	local e = o.env or engineEnv()
	local t0 = os.clock()
	local data = o.data or (Import.shared("Data") :: any).default()
	local load: (assetId: number) -> Instance = o.load
		or function(assetId: number): Instance
			return game:GetService("InsertService"):LoadAsset(assetId)
		end
	local trees, kinds = WoodsArt.trees(data)
	local folder = root:FindFirstChild(WoodsArt.FOLDER)
	if not folder then
		folder = e.Instance.new("Folder")
		folder.Name = WoodsArt.FOLDER
		folder.Parent = root
	end
	-- each kind's Model, once
	local templates: { [string]: { any } } = {}
	local failed, loaded = 0, 0
	for id, k in kinds do
		local a = k.art
		if a and a.assetId then
			local ok, asset = pcall(function(): Instance
				return load(tonumber(a.assetId) :: number)
			end)
			local t = if ok and asset then prepare(asset, a.leaf, e) else nil
			if t then
				templates[id] = t
				loaded += 1
			else
				failed += 1
			end
		end
	end
	local drawn, stand = 0, 0
	for i, t in trees do
		local tpl = templates[t.kind]
		local m = WoodsArt.build(t, kinds[t.kind], tpl, e)
		m.Parent = folder
		if tpl then
			drawn += 1
		else
			stand += 1
		end
		if o.pause ~= false and i % WoodsArt.BATCH == 0 then
			task.wait()
		end
	end
	return {
		trees = #trees,
		drawn = drawn,
		standIns = stand,
		kinds = loaded,
		failed = failed,
		seconds = os.clock() - t0,
	}
end

function WoodsArt.start(root: Instance, opts: Opts?)
	task.spawn(function()
		local ok, report = pcall(WoodsArt.run, root, opts)
		if ok then
			print(
				`[SpicyRodents] woods: {report.trees} trees ({report.drawn} from {report.kinds} Models, {report.standIns} stand-ins, {report.failed} Models failed), {math.floor(
					report.seconds * 10
				) / 10} s`
			)
		else
			warn(`[SpicyRodents] woods failed: {report}`)
		end
	end)
end

return WoodsArt
