--!strict
-- Server/Assets/WoodsArt: the D34 woods at runtime, with @lune/roblox Instances. Every woods tree is a Model
-- Workspace.Woods.Tree_W<i> holding a trunk collider the wall tests take by its round section (Client/World/
-- ClientWorld.isTrunk), and either its kind's uploaded meshes (turned, scaled and stood at its place, visual only) or a
-- stand-in of plain parts until the kind has a Model; three parts a tree under a Model.
local roblox = require("@lune/roblox")
local ClientWorld = require("@client/World/ClientWorld")
local Data = require("@shared/Data")
local WoodsArt = require("@server/Assets/WoodsArt")

local env = {
	Instance = roblox.Instance,
	CFrame = roblox.CFrame,
	Vector3 = roblox.Vector3,
	Color3 = roblox.Color3,
	Enum = roblox.Enum,
}

-- a stand-in for an uploaded kind Model: the FBX origin is the Model's pivot (the ground under the foot)
local function fakeAsset(): any
	local holder = roblox.Instance.new("Model")
	local m = roblox.Instance.new("Model")
	m.Name = "Kind"
	m.Parent = holder
	for _, spec in { { "Bark", 0, 30, 0, 10, 60, 10 }, { "Leaves", 1, 50, -2, 40, 40, 40 } } do
		local p = roblox.Instance.new("MeshPart")
		p.Name = spec[1]
		p.Size = roblox.Vector3.new(spec[5], spec[6], spec[7])
		p.CFrame = roblox.CFrame.new(spec[2], spec[3], spec[4])
		local look = roblox.Instance.new("SurfaceAppearance")
		look.Parent = p
		p.Parent = m
	end
	m.WorldPivot = roblox.CFrame.new()
	return holder
end

return function(t)
	local d = Data.default()
	local trees, kinds = WoodsArt.trees(d)
	local compiled = d:module("TreeShapes") :: any

	t.test("every woods tree is listed with its kind and place", function()
		t.eq(#trees, #compiled.woods.trees)
		for _, tr in trees do
			t.truthy(kinds[tr.kind] ~= nil, tr.kind)
			t.truthy(tr.scale > 0.5 and tr.scale < 1.5)
		end
	end)

	t.test("a stand-in: the trunk collider round the foot, a crown that neither collides nor answers rays", function()
		local tr = trees[1]
		local k = kinds[tr.kind]
		local m = WoodsArt.build(tr, k, nil, env)
		t.eq(m.Name, `Tree_W{tr.index}`)
		t.eq(m:GetAttribute("TrunkRoute"), tr.trunk)
		local trunk = m:FindFirstChild("Trunk_1") :: any
		t.truthy(trunk and trunk.CanCollide and trunk.CanQuery)
		t.truthy(ClientWorld.isTrunk(trunk.Name, m.Name), "the wall test takes it as a round trunk")
		t.near(trunk.Size.Y / 2, k.climb.trunk.radius * tr.scale, 1e-3)
		t.near(trunk.CFrame.Position.X, tr.x, 1e-3)
		t.near(trunk.CFrame.Position.Z, tr.z, 1e-3)
		-- its axis (local X) stands up, from under the ground
		t.near(math.abs(trunk.CFrame.RightVector.Y), 1, 1e-6)
		t.truthy(trunk.CFrame.Position.Y - trunk.Size.X / 2 < tr.y)
		local parts = 0
		for _, p in m:GetChildren() do
			parts += 1
			if p ~= trunk then
				t.eq(p.CanCollide, false)
				t.eq(p.CanQuery, false)
			end
		end
		t.truthy(parts <= 4, `{parts} parts`)
	end)

	t.test(
		"a kind's Model: its meshes scaled and turned onto every tree of the kind, visual only, 3 parts a tree",
		function()
			-- (the compiled woods with an id on every kind)
			local w = table.clone(compiled.woods)
			local ks = {}
			for id, k in w.kinds do
				local c = table.clone(k)
				c.art = { assetId = "123", leaf = { 90, 140, 70 }, tris = 5000 }
				ks[id] = c
			end
			w.kinds = ks
			local fake = {
				module = function(_self: any, name: string): any
					if name == "TreeShapes" then
						local c = table.clone(compiled)
						c.woods = w
						return c
					end
					return d:module(name)
				end,
				woods = function(_self: any): any
					return d:woods()
				end,
			}
			local root = roblox.Instance.new("Folder")
			local loads = 0
			local report = WoodsArt.run(root, {
				data = fake,
				env = env,
				pause = false,
				load = function(_id: number): any
					loads += 1
					return fakeAsset()
				end,
			})
			t.eq(report.trees, #trees)
			t.eq(report.drawn, #trees)
			t.eq(report.standIns, 0)
			t.eq(loads, report.kinds, "each kind loaded once")
			local folder = root:FindFirstChild(WoodsArt.FOLDER) :: any
			local total = 0
			for _, m in folder:GetChildren() do
				total += #m:GetChildren()
			end
			t.eq(total, 3 * #trees)
			local tr = trees[2]
			local m = folder:FindFirstChild(`Tree_W{tr.index}`) :: any
			local bark = m:FindFirstChild("Bark") :: any
			local leaves = m:FindFirstChild("Leaves") :: any
			t.near(bark.Size.Y, 60 * tr.scale, 1e-3)
			-- the bark's centre: 30 up from the foot, scaled; the leaves' 1, 50, -2 turned by the tree's yaw
			t.near(bark.CFrame.Position.Y, tr.y + 30 * tr.scale, 1e-3)
			local base = roblox.CFrame.new(tr.x, tr.y, tr.z) * roblox.CFrame.Angles(0, tr.yaw, 0)
			local want = base * roblox.CFrame.new(1 * tr.scale, 50 * tr.scale, -2 * tr.scale)
			t.near(leaves.CFrame.Position.X, want.Position.X, 1e-3)
			t.near(leaves.CFrame.Position.Z, want.Position.Z, 1e-3)
			for _, p in { bark, leaves } do
				t.eq(p.CanCollide, false)
				t.eq(p.CanQuery, false)
				t.eq(p.CanTouch, false)
			end
			t.eq(
				(leaves:FindFirstChildOfClass("SurfaceAppearance") :: any).AlphaMode,
				roblox.Enum.AlphaMode.Transparency
			)
			t.eq(m:FindFirstChild("Trunk_1").Transparency, 1)
		end
	)
end
