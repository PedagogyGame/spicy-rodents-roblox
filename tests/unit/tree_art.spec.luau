--!strict
-- Server/Assets/TreeArt: the uploaded tree model's SurfaceAppearances move onto the baked MeshParts of
-- the same name; a failed load leaves the tree as baked; trees without ArtAsset are ignored. A trunk whose
-- new-generator Model (generated/TreeArtNext, data/art/trees_v2.json) has an id gets its baked meshes swapped
-- for that Model's, pivoted on the tree's root and visual only, its leaves in the data's green; only a tree with
-- baked meshes, and only when the leaves took DoubleSided and AlphaMode; a v2 Model that does not load or swap
-- leaves the tree with its live Model's maps.
local roblox = require("@lune/roblox")
local TreeArt = require("@server/Assets/TreeArt")
local TreeArtNow = require("../../generated/TreeArt")
local TreeArtNext = require("../../generated/TreeArtNext")

local Instance = roblox.Instance
local CFrame = roblox.CFrame
local Vector3 = roblox.Vector3
local env = { CFrame = CFrame, Enum = roblox.Enum, Color3 = roblox.Color3 }

local function tree(parent: any, asset: string?, names: { string }, trunk: number?): any
	local m = Instance.new("Model")
	m.Name = "Tree"
	m:SetAttribute("TrunkRoute", trunk or 1)
	if asset then
		m:SetAttribute("ArtAsset", asset)
	end
	for _, n in names do
		local p = Instance.new("MeshPart")
		p.Name = n
		p.Parent = m
	end
	local proxy = Instance.new("Part")
	proxy.Name = "Trunk_1"
	proxy.Parent = m
	m.Parent = parent
	return m
end

-- what LoadAsset returns: a holder with the uploaded Model in it; its pivot (the FBX origin) at `origin`, each
-- part `offset` from it
local function asset(names: { string }, origin: any?, offset: any?, bare: { [string]: boolean }?): any
	local holder = Instance.new("Model")
	local inner = Instance.new("Model")
	inner.Parent = holder
	local o = origin or Vector3.new(0, 0, 0)
	inner.WorldPivot = CFrame.new(o.X, o.Y, o.Z)
	for _, n in names do
		local p = Instance.new("MeshPart")
		p.Name = n
		p.CanCollide = true
		p.CanQuery = true
		local at = o + (offset or Vector3.new(0, 0, 0))
		p.CFrame = CFrame.new(at.X, at.Y, at.Z)
		if not (bare and bare[n]) then
			Instance.new("SurfaceAppearance").Parent = p
		end
		p.Parent = inner
	end
	return holder
end

return function(t)
	t.test("greenLeaves: every leaf spray gets its tree's leaf green at once; bark and fruit are left alone", function()
		local town = Instance.new("Folder")
		local own = tree(town, "1", { "Bark", "LeavesShade", "LeavesMid", "LeavesSun", "Apples" }, 7)
		local plain = tree(town, nil, { "Bark", "LeavesMid" }, 8)
		local next: any = { [7] = { trunkRoute = 7, assetId = "5", pivot = { 0, 0, 0 }, leaf = { 100, 141, 73 } } }
		local bark0 = own.Bark.Color
		t.eq(TreeArt.greenLeaves(town, next, env), 4, "four sprays in the town")
		for _, name in { "LeavesShade", "LeavesMid", "LeavesSun" } do
			local c = own[name].Color
			t.near(c.R * 255, 100, 0.6, name)
			t.near(c.G * 255, 141, 0.6)
			t.near(c.B * 255, 73, 0.6)
		end
		local d = plain.LeavesMid.Color
		t.near(d.R * 255, TreeArt.LEAF[1], 0.6, "a tree with no green of its own: the default")
		t.near(d.G * 255, TreeArt.LEAF[2], 0.6)
		t.truthy(d.G > d.R and d.G > d.B, "green")
		t.eq(own.Bark.Color, bark0, "the bark keeps its colour")
	end)

	t.test("the baked data's leaf sprays: every one is baked leaf green by the tree builder", function()
		local src = require("@lune/fs").readFile("src/worldgen/Builders/Trees.luau")
		t.truthy(
			string.find(src, "color = if isLeaf then { 106, 148, 77 } else m.color", 1, true) ~= nil,
			"Builders/Trees bakes a leaf spray's part colour green"
		)
	end)

	t.test("apply moves each SurfaceAppearance onto the baked part of the same name, once", function()
		local town = Instance.new("Folder")
		local a = tree(town, "101", { "Bark", "LeavesSun" })
		t.eq(TreeArt.apply(a, asset({ "Bark", "LeavesSun", "Apples" })), 2)
		t.truthy(a.Bark:FindFirstChildOfClass("SurfaceAppearance"))
		t.truthy(a.LeavesSun:FindFirstChildOfClass("SurfaceAppearance"))
		t.eq(a.Trunk_1:FindFirstChildOfClass("SurfaceAppearance"), nil)
		t.eq(TreeArt.apply(a, asset({ "Bark", "LeavesSun" })), 0)
	end)

	t.test("run loads every tree with ArtAsset; a failed load keeps the tree as baked", function()
		local town = Instance.new("Folder")
		local a = tree(town, "101", { "Bark" })
		local b = tree(town, "102", { "Bark" })
		tree(town, nil, { "Bark" })
		t.eq(#TreeArt.trees(town), 2)
		local asked: { number } = {}
		local report = TreeArt.run(town, {
			pause = 0,
			next = {},
			load = function(id: number): any
				table.insert(asked, id)
				if id == 102 then
					error("asset is not available")
				end
				return asset({ "Bark" })
			end,
		})
		table.sort(asked)
		t.eq(#asked, 2)
		t.eq(asked[1], 101)
		t.eq(report.trees, 2)
		t.eq(report.upgraded, 1)
		t.eq(report.swapped, 0)
		t.eq(report.failed, 1)
		t.truthy(a.Bark:FindFirstChildOfClass("SurfaceAppearance"))
		t.eq(b.Bark:FindFirstChildOfClass("SurfaceAppearance"), nil)
	end)

	t.test("swap puts the new Model's meshes on the tree's root, visual only, and drops the baked ones", function()
		local town = Instance.new("Folder")
		local a = tree(town, "101", { "Bark", "LeavesSun", "LeavesMid", "Apples" })
		local old = a.Bark
		-- the Model as uploaded: its pivot somewhere else, the bark 12 studs over it
		local n = TreeArt.swap(
			a,
			asset({ "Bark", "LeavesSun", "LeavesShade" }, Vector3.new(5, 7, 9), Vector3.new(0, 12, 0)),
			{
				-100,
				3,
				40,
			},
			env,
			{ 100, 141, 73 }
		)
		t.eq(n, 3)
		t.eq(old.Parent, nil)
		t.eq(a:FindFirstChild("LeavesMid"), nil)
		t.eq(a:FindFirstChild("Apples"), nil)
		t.truthy(a:FindFirstChild("Trunk_1"), "the proxies stay")
		local bark = a:FindFirstChild("Bark")
		t.truthy(bark and bark ~= old)
		t.near(bark.CFrame.Position.X, -100, 1e-4)
		t.near(bark.CFrame.Position.Y, 15, 1e-4)
		t.near(bark.CFrame.Position.Z, 40, 1e-4)
		for _, name in { "Bark", "LeavesSun", "LeavesShade" } do
			local p = a:FindFirstChild(name)
			t.truthy(p.Anchored and not p.CanCollide and not p.CanQuery and not p.CanTouch and p.CastShadow, name)
		end
		t.eq(a.LeavesSun.DoubleSided, true)
		t.eq(a.LeavesSun:FindFirstChildOfClass("SurfaceAppearance").AlphaMode, roblox.Enum.AlphaMode.Transparency)
		t.eq(a.Bark.DoubleSided, false)
		t.eq(a.LeavesSun.Color, roblox.Color3.fromRGB(100, 141, 73))
		t.eq(a.LeavesShade.Color, roblox.Color3.fromRGB(100, 141, 73))
		t.truthy(a.Bark.Color ~= roblox.Color3.fromRGB(100, 141, 73), "the bark keeps its colour")
	end)

	t.test("a Model whose leaves did not take their alpha cut is not swapped in", function()
		local town = Instance.new("Folder")
		local a = tree(town, nil, { "Bark", "LeavesSun" })
		local old = a.Bark
		-- (a leaf part with no SurfaceAppearance reads no AlphaMode back)
		local m = asset({ "Bark", "LeavesSun" }, nil, nil, { LeavesSun = true })
		t.eq(TreeArt.swap(a, m, { 0, 0, 0 }, env), 0)
		t.eq(a.Bark, old)
		t.eq(old.Parent, a)
	end)

	t.test("a tree without baked meshes is not swapped (no v2 Model laid over its primitives)", function()
		local town = Instance.new("Folder")
		local a = tree(town, nil, {})
		a:SetAttribute("Mesh", false)
		t.eq(TreeArt.swap(a, asset({ "Bark", "LeavesSun" }), { 0, 0, 0 }, env), 0)
		t.eq(a:FindFirstChild("Bark"), nil)
		t.eq(#a:GetChildren(), 1, "only the proxy")
	end)

	t.test("a Model without bark swaps nothing", function()
		local town = Instance.new("Folder")
		local a = tree(town, nil, { "Bark", "LeavesSun" })
		local old = a.Bark
		t.eq(TreeArt.swap(a, asset({ "LeavesSun" }), { 0, 0, 0 }, env), 0)
		t.eq(a.Bark, old)
	end)

	t.test("run swaps the trunks whose v2 Model has an id, and only those", function()
		local town = Instance.new("Folder")
		local a = tree(town, "101", { "Bark" }, 7)
		local b = tree(town, nil, { "Bark" }, 8) -- (no live Model, but a v2 one)
		local c = tree(town, "103", { "Bark" }, 9)
		local d = tree(town, "104", { "Bark" }, 10) -- (a v2 Model with no bark)
		local e = tree(town, "205", { "Bark", "LeavesSun" }, 11) -- (rebaked from its v2 Model already)
		local f = tree(town, "106", { "Bark" }, 12) -- (its v2 Model does not load)
		local g = tree(town, nil, {}, 13) -- (primitives: no baked meshes)
		local eBark = e.Bark
		local asked: { [number]: boolean } = {}
		local report = TreeArt.run(town, {
			pause = 0,
			env = env,
			next = {
				{ trunkRoute = 7, assetId = "201", pivot = { 1, 2, 3 } },
				{ trunkRoute = 8, assetId = "202", pivot = { 4, 5, 6 } },
				{ trunkRoute = 9, assetId = nil, pivot = { 0, 0, 0 } },
				{ trunkRoute = 10, assetId = "204", pivot = { 0, 0, 0 } },
				{ trunkRoute = 11, assetId = "205", pivot = { 0, 0, 0 } },
				{ trunkRoute = 12, assetId = "206", pivot = { 0, 0, 0 } },
				{ trunkRoute = 13, assetId = "207", pivot = { 0, 0, 0 } },
			},
			load = function(id: number): any
				asked[id] = true
				if id == 206 then
					error("asset is not available")
				end
				return asset(
					if id == 204 then { "LeavesSun" } elseif id == 205 then { "Bark", "LeavesSun" } else { "Bark" }
				)
			end,
		})
		t.truthy(asked[201] and asked[202] and asked[103] and asked[204] and asked[206])
		t.truthy(not asked[101], "a swapped tree does not load its old Model")
		t.truthy(asked[104] and asked[106], "a v2 Model that did not swap falls back to the live one")
		t.eq(report.trees, 7)
		t.eq(report.swapped, 2)
		t.eq(report.upgraded, 4) -- c, e, and the fallbacks d and f
		t.eq(report.failed, 3) -- d (no bark), f (did not load), g (no baked meshes)
		t.near(a.Bark.CFrame.Position.Z, 3, 1e-4)
		t.near(b.Bark.CFrame.Position.X, 4, 1e-4)
		t.truthy(c.Bark:FindFirstChildOfClass("SurfaceAppearance"))
		t.truthy(d.Bark:FindFirstChildOfClass("SurfaceAppearance"), "d keeps today's maps")
		t.truthy(f.Bark:FindFirstChildOfClass("SurfaceAppearance"), "f keeps today's maps")
		t.eq(#g:GetChildren(), 1, "g keeps its primitives only")
		t.eq(e.Bark, eBark, "a rebaked tree keeps its baked meshes")
		t.truthy(e.Bark:FindFirstChildOfClass("SurfaceAppearance"))
		t.eq(e.LeavesSun:FindFirstChildOfClass("SurfaceAppearance").AlphaMode, roblox.Enum.AlphaMode.Transparency)
	end)

	t.test(
		"a v2 Model that covers grown boughs (D32) hides their baked stand-ins: bark unseen, twigs and leaves gone",
		function()
			local town = Instance.new("Folder")
			local a = tree(town, "101", { "Bark", "LeavesSun" })
			local function part(name: string, grown: number?, collide: boolean): any
				local p = Instance.new("Part")
				p.Name = name
				p.CanCollide = collide
				p.Transparency = 0
				p.CastShadow = true
				if grown then
					p:SetAttribute("Grown", grown)
				end
				p.Parent = a
				return p
			end
			local bark = part("R9701_1", 9701, true)
			local twig = part("Twig9701_1", 9701, false)
			local leaf = part("GrownLeaves1", 9701, false)
			local other = part("R9702_1", 9702, true) -- a grown bough this Model does not draw
			local proxy = part("R100_1", nil, true)
			proxy.Transparency = 1
			local n = TreeArt.swap(a, asset({ "Bark", "LeavesSun" }), { 0, 0, 0 }, env, nil, { 9701 })
			t.eq(n, 2)
			t.eq(bark.Parent, a, "the bark stays as a proxy")
			t.eq(bark.Transparency, 1)
			t.eq(bark.CastShadow, false)
			t.eq(twig.Parent, nil)
			t.eq(leaf.Parent, nil)
			t.eq(other.Transparency, 0, "a bough the Model does not cover keeps its stand-in")
			t.eq(proxy.Parent, a)
			-- without covers (a Model made before the boughs grew) nothing of the stand-ins changes
			local b = tree(town, "102", { "Bark", "LeavesSun" })
			local keep = Instance.new("Part")
			keep:SetAttribute("Grown", 9703)
			keep.Parent = b
			t.eq(TreeArt.swap(b, asset({ "Bark", "LeavesSun" }), { 0, 0, 0 }, env), 2)
			t.eq(keep.Parent, b)
			t.eq(keep.Transparency, 0)
		end
	)

	t.test("the v2 data: one Model per live tree, every id digits", function()
		local live: { [number]: boolean } = {}
		for _, r in TreeArtNow :: any do
			live[r.trunkRoute] = true
		end
		local n = 0
		for _, r in TreeArtNext :: any do
			n += 1
			t.truthy(live[r.trunkRoute], `v2 tree on trunk {r.trunkRoute} is a live tree`)
			t.truthy(r.assetId == nil or string.match(r.assetId, "^%d+$") ~= nil, `trunk {r.trunkRoute} id`)
			t.eq(#r.pivot, 3)
		end
		t.eq(n, #(TreeArtNow :: any))
	end)
end
