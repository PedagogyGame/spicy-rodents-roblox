--!strict
-- Server/Assets/TreeArt: the uploaded tree model's SurfaceAppearances move onto the baked MeshParts of
-- the same name; a failed load leaves the tree as baked; trees without ArtAsset are ignored.
local roblox = require("@lune/roblox")
local TreeArt = require("@server/Assets/TreeArt")

local Instance = roblox.Instance

local function tree(parent: any, asset: string?, names: { string }): any
	local m = Instance.new("Model")
	m.Name = "Tree"
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

local function asset(names: { string }): any
	local holder = Instance.new("Model")
	local inner = Instance.new("Model")
	inner.Parent = holder
	for _, n in names do
		local p = Instance.new("MeshPart")
		p.Name = n
		Instance.new("SurfaceAppearance").Parent = p
		p.Parent = inner
	end
	return holder
end

return function(t)
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
		t.eq(report.failed, 1)
		t.truthy(a.Bark:FindFirstChildOfClass("SurfaceAppearance"))
		t.eq(b.Bark:FindFirstChildOfClass("SurfaceAppearance"), nil)
	end)
end
