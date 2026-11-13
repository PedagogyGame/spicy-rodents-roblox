--!strict
-- The Neighbourhood Shop (brief addendum D12): its place in the town plan, the shell baked in memory with the
-- same code tools/bake/neighbourhood_shop.luau runs (tools/bake/neighbourhood_shop/Shop), and the loader that
-- puts the owner's uploaded interior and roof into it at boot (Server/Assets/ShopArt) on a stand-in asset.
local roblox = require("@lune/roblox")
local AlleyLayout = require("@shared/Attractions/AlleyLayout")
local Expansion = require("../../generated/Expansion")
local ShopArtData = require("../../generated/ShopArt")
local Kit = require("../../tools/bake/alley/Kit")
local Shop = require("../../tools/bake/neighbourhood_shop/Shop")
local ShopArt = require("@server/Assets/ShopArt")

local Instance = roblox.Instance
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local ENV = { CFrame = roblox.CFrame, Color3 = roblox.Color3, Enum = roblox.Enum }

local art: any = ShopArtData

local function venue(): any
	for _, v in (Expansion :: any).venues do
		if v.id == art.venue then
			return v
		end
	end
	error("f1_neighbourhood_shop missing from generated/Expansion")
end

local function bake(): (any, any, any)
	local v = venue()
	local folder = Instance.new("Folder")
	local kit = Kit.new(roblox, v.place)
	local root = Shop.build(kit, folder, v, art)
	return root, kit, v
end

local function parts(root: any): { any }
	local out = {}
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(out, d)
		end
	end
	return out
end

-- Is the world point inside the part's box (oriented)?
local function inside(p: any, w: any, margin: number): boolean
	local l = p.CFrame:Inverse() * w
	local s = p.Size
	return math.abs(l.X) < s.X / 2 + margin and math.abs(l.Y) < s.Y / 2 + margin and math.abs(l.Z) < s.Z / 2 + margin
end

local function solids(root: any): { any }
	local out = {}
	for _, p in parts(root) do
		if p.CanCollide and p.Parent.Name ~= "TerrainCarve" then
			table.insert(out, p)
		end
	end
	return out
end

-- The highest top of a solid part under a world column (x, z) below `below`, or nil.
local function groundAt(list: { any }, x: number, z: number, below: number): number?
	local best: number? = nil
	for _, p in list do
		local cf, s = p.CFrame, p.Size
		local l = cf:Inverse() * Vector3.new(x, cf.Position.Y, z)
		if math.abs(l.X) <= s.X / 2 and math.abs(l.Z) <= s.Z / 2 and cf.UpVector.Y > 0.999 then
			local top = cf.Position.Y + s.Y / 2
			if top <= below and (best == nil or top > (best :: number)) then
				best = top
			end
		end
	end
	return best
end

-- A stand-in for the uploaded Model: InsertService gives a holder Model around the asset's Model.
local function asset(names: { string }, textured: { [string]: boolean }?): any
	local holder = Instance.new("Model")
	local inner = Instance.new("Model")
	inner.Parent = holder
	for _, n in names do
		local p = Instance.new("MeshPart")
		p.Name = n
		p.CanCollide = true
		if textured and textured[n] then
			Instance.new("SurfaceAppearance").Parent = p
		end
		p.Parent = inner
	end
	return holder
end

local function record(name: string): any
	for _, list in { art.shop, art.roofParts } do
		for _, r in list do
			if r.name == name then
				return r
			end
		end
	end
	error("no record " .. name)
end

return function(t)
	t.test("its place: Main Street's north sidewalk, facing the boulevard, the floor just above the ground", function()
		local v = venue()
		t.eq(v.family, "F1")
		t.eq(v.facing, "-Z")
		t.near(v.position.x, 686, 1e-6)
		t.near(v.position.z, 70.625, 1e-6)
		t.near(v.floorY, 2.3, 1e-6)
		-- 0.3..1.5 above the highest ground under the footprint (the compiler's own rule, held here too)
		t.truthy(v.floorY - v.ground.max >= 0.3 and v.floorY - v.ground.max <= 1.5)
		-- the front door opens onto rd_021 (Main Street's north sidewalk, z 39.4..47.6)
		local door = v.entrances[1].world
		t.truthy(door[3] > 47.6 and door[3] - 47.6 < 4, `door at z {door[3]}`)
		t.eq(art.scale, 3)
	end)

	t.test("the bake: one Atomic model with its art ids and pivot, inside its part budget", function()
		local root, _, v = bake()
		local n = #parts(root)
		t.eq(root:GetAttribute("Parts"), n)
		t.truthy(n <= v.partBudget, `{n} parts, budget {v.partBudget}`)
		t.eq(root.ModelStreamingMode, roblox.Enum.ModelStreamingMode.Atomic)
		t.eq(root:GetAttribute("ArtShop"), tostring(art.assets.shop.id))
		t.eq(root:GetAttribute("ArtRoof"), tostring(art.assets.roof.id))
		local pivot = root:GetAttribute("ArtPivot")
		t.near(pivot.Position.X, 686, 1e-3)
		t.near(pivot.Position.Y, 2.3, 1e-3)
		t.near(pivot.Position.Z, 70.625, 1e-3)
		-- facing -Z: the frame's own +Z (the street side, D < 0) points to world -Z
		t.near(pivot.LookVector.Z, 1, 1e-3)
		-- everything stays inside the planned site (the roof overhangs by less than a stud)
		local s = v.site
		for _, p in parts(root) do
			local x, _, d = AlleyLayout.toLocal(v.place, p.CFrame.Position.X, p.CFrame.Position.Y, p.CFrame.Position.Z)
			t.truthy(x >= s.x0 - 1 and x <= s.x1 + 1 and d >= s.d0 - 1e-3 and d <= s.d1 + 1, p:GetFullName())
		end
	end)

	t.test("his colliders: every floor, wall, divider and counter of his metadata, invisible and solid", function()
		local root, kit = bake()
		local cols = root:FindFirstChild("Colliders")
		local metadata, mesh, furniture = 0, 0, 0
		for _, c in art.colliders do
			local want = kit:cf(c.centre[1], c.centre[2], c.centre[3]).Position
			local found = false
			for _, p in cols:GetChildren() do
				if p.Name == c.name and (p.CFrame.Position - want).Magnitude < 1e-3 then
					found = true
					t.eq(p.Transparency, 1)
					t.truthy(p.CanCollide)
					t.near(p.Size.Y, c.size[2], 1e-3)
				end
			end
			t.truthy(found, c.name)
			if c.from == "his metadata" then
				metadata += 1
			elseif c.from == "his mesh" then
				mesh += 1
			else
				furniture += 1
			end
		end
		t.eq(metadata, 12)
		t.eq(mesh, 1)
		t.eq(furniture, 15)
		-- no collider is one box over the hollow room: none spans more than one room's floor area
		for _, p in cols:GetChildren() do
			local s = p.Size
			t.truthy(not (s.X > 25 and s.Y > 2 and s.Z > 25), p.Name)
		end
	end)

	t.test("a person walks in: from the sidewalk up the steps and through the doorway, nothing in the way", function()
		local root, kit = bake()
		local list = solids(root)
		local door = art.doorway
		local x = (door.x0 + door.x1) / 2
		local last: number? = nil
		local d = -22.9
		while d <= -12 do
			for _, dx in { -1.0, 0, 1.0 } do
				local w = kit:cf(x + dx, 0, d).Position
				local g = groundAt(list, w.X, w.Z, kit:cf(0, 1, 0).Position.Y)
				t.truthy(g ~= nil, `nothing to stand on at D {d}`)
				-- the body (2 studs wide, 5 tall) is clear of every solid part
				for h = 0.7, 5.2, 0.5 do
					local p = Vector3.new(w.X, (g :: number) + h, w.Z)
					for _, part in list do
						t.falsy(inside(part, p, 0), `{part.Name} in the way at D {d}, {h} above the ground`)
					end
				end
				if dx == 0 then
					if last then
						t.truthy(
							(g :: number) - (last :: number) <= 0.7,
							`a step of {(g :: number) - (last :: number)} at D {d}`
						)
					end
					last = g
				end
			end
			d += 0.25
		end
		-- inside, the person stands on his floor (Y 0)
		t.near((last :: number) - kit:cf(0, 0, 0).Position.Y, 0, 1e-3)
		-- and the doorway is the width his metadata gives, as high as his door frame
		t.near(door.x1 - door.x0, art.entrance.width, 0.05)
		t.truthy(door.top >= 8.75, "a person (5.5 st) fits through")
	end)

	t.test(
		"the shell: walls up to his roof deck, the attic closed, the backing slab over his ceiling, the sign",
		function()
			local root = bake()
			local shell = root:FindFirstChild("Shell")
			local wall = shell:FindFirstChild("EastWall")
			local top = wall.CFrame.Position.Y + wall.Size.Y / 2 - root:GetAttribute("ArtPivot").Position.Y
			t.near(top, Shop.underside(art, Shop.INNER_D + Shop.WALL) - 0.02, 1e-3)
			local apex = shell:FindFirstChild("EastGableBack")
			t.near(
				apex.CFrame.Position.Y + apex.Size.Y / 2 - root:GetAttribute("ArtPivot").Position.Y,
				Shop.underside(art, 0) - 0.02,
				1e-3
			)
			t.truthy(shell:FindFirstChild("CeilingBacking").Size.Y >= 1, "Realistic lighting wants 1 stud of backing")
			local label =
				shell:FindFirstChild("SignBoard"):FindFirstChildOfClass("SurfaceGui"):FindFirstChildOfClass("TextLabel")
			t.eq(label.Text, "THE NEIGHBOURHOOD SHOP")
			-- the roof sign stands clear above his deck, under his ridge
			local roofSign = shell:FindFirstChild("RoofSign")
			local floorY = root:GetAttribute("ArtPivot").Position.Y
			local bottom = roofSign.CFrame.Position.Y - roofSign.Size.Y / 2 - floorY
			local signTop = roofSign.CFrame.Position.Y + roofSign.Size.Y / 2 - floorY
			t.truthy(bottom > Shop.topside(art, Shop.ROOF_SIGN_D), "above the roof")
			t.truthy(signTop < Shop.underside(art, 0), "below the ridge")
			t.eq(roofSign:FindFirstChildOfClass("SurfaceGui"):FindFirstChildOfClass("TextLabel").Text, Shop.SIGN)
			local lamps = root:FindFirstChild("Lamps")
			local lights = 0
			for _, p in lamps:GetChildren() do
				if p:FindFirstChildOfClass("PointLight") then
					lights += 1
				end
			end
			t.eq(lights, #art.lamps + 1) -- his six pendants and the desk lamp, and one over the door
		end
	)

	t.test(
		"the loader: his parts are visual only, untextured ones painted, glass see-through, each in its place",
		function()
			local root = bake()
			local names = { "CAFE_CounterTop", "FLOOR_Retail", "WINDOW_RemovableGlass", "RidgeCap" }
			local textured = { FLOOR_Retail = true }
			local asked: { number } = {}
			local report = ShopArt.install(root, {
				data = art,
				env = ENV,
				load = function(id: number): any
					table.insert(asked, id)
					return asset(names, textured)
				end,
			})
			t.eq(#asked, 2)
			t.eq(asked[1], art.assets.shop.id)
			t.eq(asked[2], art.assets.roof.id)
			t.eq(#report.loaded, 2)
			t.eq(#report.failed, 0)
			t.eq(root:GetAttribute("ArtLoaded"), "Shop,Roof")
			local shop = root:FindFirstChild("ArtShop")
			t.truthy(shop)
			local pivot = root:GetAttribute("ArtPivot")
			for _, p in shop:GetChildren() do
				t.truthy(p.Anchored)
				t.falsy(p.CanCollide)
				t.falsy(p.CanQuery)
				t.falsy(p.CanTouch)
				local r = record(p.Name)
				local want = (pivot * CFrame.new(r.at[1], r.at[2], r.at[3])).Position
				t.truthy((p.CFrame.Position - want).Magnitude < 1e-3, p.Name)
			end
			local counter, floor, glass = shop.CAFE_CounterTop, shop.FLOOR_Retail, shop.WINDOW_RemovableGlass
			local c = record("CAFE_CounterTop").colour
			t.eq(counter.Color, roblox.Color3.fromRGB(c[1], c[2], c[3]))
			t.truthy(floor:FindFirstChildOfClass("SurfaceAppearance"), "a textured part keeps its maps")
			t.eq(glass.Material, roblox.Enum.Material.Glass)
			t.near(glass.Transparency, ShopArt.GLASS_TRANSPARENCY, 1e-6)
			t.truthy(record("WINDOW_RemovableGlass").glass)
			-- a second run loads nothing again
			ShopArt.install(root, {
				data = art,
				env = ENV,
				load = function(): any
					error("loaded twice")
				end,
			})
		end
	)

	t.test("the loader: a Model that will not load leaves the walkable shell; the carve clears its inside", function()
		local root = bake()
		local report = ShopArt.install(root, {
			data = art,
			env = ENV,
			load = function(id: number): any
				if id == art.assets.roof.id then
					error("asset is not available")
				end
				return asset({ "CAFE_CounterTop" })
			end,
		})
		t.eq(#report.loaded, 1)
		t.eq(#report.failed, 1)
		t.eq(root:FindFirstChild("ArtRoof"), nil)
		t.truthy(root:FindFirstChild("Colliders"):FindFirstChild("RetailFloor"))
		local boxes = {}
		t.eq(
			ShopArt.carve(root, {
				fill = function(cf: any, size: any)
					table.insert(boxes, { cf, size })
				end,
			}),
			1
		)
		t.truthy(boxes[1][2].Y > 12, "the whole height of the room")
		-- every shop under a root is found
		local folder = Instance.new("Folder")
		root.Parent = folder
		t.eq(#ShopArt.venues(folder), 1)
	end)
end
