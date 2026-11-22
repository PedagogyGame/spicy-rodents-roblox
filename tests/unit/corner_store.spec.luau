--!strict
-- Pepper's Corner Store (f1_corner_store; brief v2 "Corner store"; addendum D2, D14): its place in the town
-- plan and the store baked in memory with the same code tools/bake/corner_store.luau runs
-- (tools/bake/corner_store/Store): the budget, the doors a person walks through, the aisles they walk.
local roblox = require("@lune/roblox")
local AlleyLayout = require("@shared/Attractions/AlleyLayout")
local Height = require("@shared/World/Height")
local Expansion = require("../../generated/Expansion")
local Kit = require("../../tools/bake/alley/Kit")
local Store = require("../../tools/bake/corner_store/Store")
local Fixtures = require("../../tools/bake/corner_store/Fixtures")
local ItemRules = require("@shared/Items/ItemRules")
local Bank = require("@shared/Economy/Bank")
local Data = require("@shared/Data")
local Species = require("@shared/Actors/Species")
local TownAI = require("@server/AI/TownAI")

local Instance = roblox.Instance
local Vector3 = roblox.Vector3

local function venue(): any
	for _, v in (Expansion :: any).venues do
		if v.id == "f1_corner_store" then
			return v
		end
	end
	error("f1_corner_store missing from generated/Expansion")
end

local function bake(): (any, any)
	local v = venue()
	local folder = Instance.new("Folder")
	local kit = Kit.new(roblox, v.place)
	local root = Store.build(kit, folder, v, function(x: number, d: number): number
		local wx, _, wz = AlleyLayout.toWorld(v.place, x, 0, d)
		return Height.at(wx, wz) - v.floorY
	end)
	return root, v
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

local function solids(root: any): { any }
	local out = {}
	for _, p in parts(root) do
		if p.CanCollide and p.Parent.Name ~= "TerrainCarve" then
			table.insert(out, p)
		end
	end
	return out
end

-- A part's bounds in the venue frame (X, Y, D), from its eight corners.
local function localBounds(v: any, p: any): ({ number }, { number })
	local lo, hi = { math.huge, math.huge, math.huge }, { -math.huge, -math.huge, -math.huge }
	local h = p.Size / 2
	for _, sx in { -1, 1 } do
		for _, sy in { -1, 1 } do
			for _, sz in { -1, 1 } do
				local w = p.CFrame * Vector3.new(sx * h.X, sy * h.Y, sz * h.Z)
				local x, y, d = AlleyLayout.toLocal(v.place, w.X, w.Y, w.Z)
				for k, c in { x, y, d } do
					lo[k] = math.min(lo[k], c)
					hi[k] = math.max(hi[k], c)
				end
			end
		end
	end
	return lo, hi
end

-- Where a body of radius r (from `feet` to 5.2 above the floor) can stand, flooded from a start cell: every
-- solid part reaching into the body's height blocks the cells within r. The grid covers the store and a margin
-- round it; outside the walls only the landings and steps are ground (the walk may not go round the building).
local STEP = 0.25
local GRID = { x0 = -27, x1 = 27, d0 = -26, d1 = 26 }
local function flood(root: any, v: any, r: number, feet: number, sx: number, sd: number): (number, number) -> boolean
	local nx = math.floor((GRID.x1 - GRID.x0) / STEP)
	local nd = math.floor((GRID.d1 - GRID.d0) / STEP)
	local blocked: { [number]: boolean } = {}
	local ground: { [number]: boolean } = {}
	local IX, ID = Store.IN_X, Store.IN_D
	for i = 0, nx do
		for j = 0, nd do
			local x, d = GRID.x0 + i * STEP, GRID.d0 + j * STEP
			if math.abs(x) < IX and math.abs(d) < ID then
				ground[i * (nd + 1) + j] = true
			end
		end
	end
	for _, p in solids(root) do
		local lo, hi = localBounds(v, p)
		local i0 = math.max(0, math.floor((lo[1] - r - GRID.x0) / STEP))
		local i1 = math.min(nx, math.ceil((hi[1] + r - GRID.x0) / STEP))
		local j0 = math.max(0, math.floor((lo[3] - r - GRID.d0) / STEP))
		local j1 = math.min(nd, math.ceil((hi[3] + r - GRID.d0) / STEP))
		local isStep = p.Parent.Name == "Entrances"
		for i = i0, i1 do
			for j = j0, j1 do
				local x, d = GRID.x0 + i * STEP, GRID.d0 + j * STEP
				local dx = math.max(lo[1] - x, 0, x - hi[1])
				local dd = math.max(lo[3] - d, 0, d - hi[3])
				if isStep and dx <= 0.05 and dd <= 0.05 then
					ground[i * (nd + 1) + j] = true
				elseif not isStep and hi[2] > feet and lo[2] < 5.2 and dx * dx + dd * dd < r * r then
					blocked[i * (nd + 1) + j] = true
				end
			end
		end
	end
	local reached: { [number]: boolean } = {}
	local si = math.floor((sx - GRID.x0) / STEP + 0.5)
	local sj = math.floor((sd - GRID.d0) / STEP + 0.5)
	local queue = { { si, sj } }
	reached[si * (nd + 1) + sj] = true
	local head = 1
	while head <= #queue do
		local c = queue[head]
		head += 1
		for _, o in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
			local i, j = c[1] + o[1], c[2] + o[2]
			local k = i * (nd + 1) + j
			if i >= 0 and i <= nx and j >= 0 and j <= nd and not reached[k] and not blocked[k] and ground[k] then
				reached[k] = true
				table.insert(queue, { i, j })
			end
		end
	end
	return function(x: number, d: number): boolean
		local i = math.floor((x - GRID.x0) / STEP + 0.5)
		local j = math.floor((d - GRID.d0) / STEP + 0.5)
		return reached[i * (nd + 1) + j] == true
	end
end

return function(t)
	t.test("its place: the east commercial strip, facing the street, the floor just above the ground", function()
		local v = venue()
		t.eq(v.type, "shop_corner")
		t.eq(v.built, "tools/bake/corner_store.luau")
		t.eq(v.name, "PEPPER'S CORNER STORE")
		t.truthy(v.floorY > v.ground.max and v.floorY - v.ground.min < 2, `floor {v.floorY}`)
		t.near(v.place.x, 957, 0.01)
		t.near(v.place.z, 84, 0.01)
	end)

	t.test("the bake: one Atomic model inside its part budget, its sign, its lights few and unshadowed", function()
		local root, v = bake()
		t.eq(root:GetAttribute("Venue"), "f1_corner_store")
		t.eq(root.ModelStreamingMode, roblox.Enum.ModelStreamingMode.Atomic)
		local n = #parts(root)
		t.eq(root:GetAttribute("Parts"), n)
		t.truthy(n <= v.partBudget, `{n} parts against a budget of {v.partBudget}`)
		local lights, sign = 0, false
		for _, d in root:GetDescendants() do
			if d:IsA("Light") then
				lights += 1
				t.eq(d.Shadows, false, d:GetFullName())
			elseif d:IsA("TextLabel") and d.Text == "PEPPER'S CORNER STORE" then
				sign = true
			end
		end
		t.truthy(lights >= 3 and lights <= 8, `{lights} lights`)
		t.truthy(sign, "the sign")
	end)

	t.test("the steps: from each door down to the ground outside, no step higher than a person steps", function()
		local root, v = bake()
		local ent = root:FindFirstChild("Entrances")
		t.truthy(ent ~= nil)
		for _, name in { "FrontStep", "SideStep", "ServiceStep" } do
			local tops = {}
			for _, p in ent:GetChildren() do
				if string.sub(p.Name, 1, #name) == name then
					local _, hi = localBounds(v, p)
					table.insert(tops, hi[2])
				end
			end
			table.sort(tops, function(a, b)
				return a > b
			end)
			t.truthy(#tops >= 1, name)
			t.near(tops[1], 0, 0.01)
			for k = 2, #tops do
				t.truthy(tops[k - 1] - tops[k] <= Store.STEP + 1e-6, `{name}: a rise of {tops[k - 1] - tops[k]}`)
			end
		end
	end)

	t.test("a person walks in by each door and reaches every corner of the floor", function()
		local root, v = bake()
		local fd, sd, svc = Store.FRONT_DOOR, Store.SIDE_DOOR, Store.SERVICE_DOOR
		-- in from the front landing (a person: radius 1.1, feet clear of a 0.7 step)
		local at = flood(root, v, 1.1, 0.7, (fd[1] + fd[2]) / 2, -Store.IN_D - 2)
		t.truthy(at(Store.IN_X + 2, (sd[1] + sd[2]) / 2), "out by the side door")
		t.truthy(at((svc[1] + svc[2]) / 2, Store.IN_D + 2), "out by the service door")
		-- the corners of the front, every aisle's length, the fridge, the freezer, both sides of the counter
		local spots = {
			{ -20, -18, "the east front corner" },
			{ 20, -18, "the west front corner" },
			{ -16, -17, "in front of the counter" },
			{ -16, -10, "behind the counter (the shopkeeper's place)" },
			{ 11, 16.5, "in front of the fridge" },
			{ -4, 16.5, "in front of the freezer" },
			{ -12, 19, "inside the service door" },
		}
		local G, H = Fixtures.GONDOLAS, Fixtures.GONDOLA_HALF
		for i, c in G do
			local east = c + H
			local west = if i < #G then G[i + 1] - H else 21.0
			for _, d in { -2, 6, 14 } do
				table.insert(spots, { (east + west) / 2, d, `the aisle west of gondola {i}` })
			end
		end
		for _, d in { -2, 6, 14 } do
			table.insert(spots, { (-21.4 + G[1] - H) / 2, d, "the east aisle" })
		end
		for _, c in spots do
			t.truthy(at(c[1], c[2]), `{c[3]} ({c[1]}, {c[2]})`)
		end
		-- nobody walks through a window or a wall
		t.eq(at(-16, -Store.IN_D - 2), false)
		t.eq(at(-Store.IN_X - 2, 0), false)
	end)

	t.test(
		"the items on sale: each on its shelf with its price, a prompt a person standing in the store can reach",
		function()
			local root, v = bake()
			local items = root:FindFirstChild("Items")
			t.truthy(items ~= nil)
			local onSale = 0
			for _, def in ItemRules.CATALOG do
				onSale += if ItemRules.onSale(def.id) then 1 else 0
			end
			t.eq(onSale, 23, "all 23: the dog treats are back now the town has dogs, the kick ball since D30")
			t.eq(root:GetAttribute("Items"), onSale)
			t.truthy(items:FindFirstChild("Item_dog_treats"), "the dog treats are on the third gondola")
			local fd = Store.FRONT_DOOR
			local at = flood(root, v, 1.1, 0.7, (fd[1] + fd[2]) / 2, -Store.IN_D - 2)
			for _, def in ItemRules.CATALOG do
				if not ItemRules.onSale(def.id) then
					continue
				end
				local m = items:FindFirstChild("Item_" .. def.id)
				t.truthy(m ~= nil, def.id)
				t.eq(m:GetAttribute("ItemId"), def.id)
				t.eq(m:GetAttribute("Price"), def.price)
				local sample = m:FindFirstChild("Sample")
				t.truthy(sample and #sample:GetChildren() >= 1, `{def.id}: a sample to hand over`)
				for _, p in sample:GetChildren() do
					t.eq(p.CanCollide, false, `{def.id}: the sample is visual`)
				end
				local tag = m:FindFirstChild("PriceTag")
				-- owner D31: prices are ten times the first list, so a tag reads as the wallet writes it ("S$6.00")
				t.eq(
					tag:FindFirstChildWhichIsA("SurfaceGui"):FindFirstChildWhichIsA("TextLabel").Text,
					Bank.amount(def.price)
				)
				local grab = m:FindFirstChild("Grab")
				local prompt = grab:FindFirstChildWhichIsA("ProximityPrompt")
				t.truthy(prompt ~= nil, `{def.id}: a prompt`)
				t.eq(prompt:GetAttribute("StoreItem"), def.id)
				t.eq(prompt.RequiresLineOfSight, false)
				t.truthy(string.find(prompt.ObjectText, Bank.amount(def.price), 1, true) ~= nil, prompt.ObjectText)
				t.truthy(not string.find(prompt.ObjectText, "_", 1, true), prompt.ObjectText)
				-- a place to stand (a body's centre 2.5 above the floor) within the prompt's reach, less a stud
				local x, y, d =
					AlleyLayout.toLocal(v.place, grab.CFrame.Position.X, grab.CFrame.Position.Y, grab.CFrame.Position.Z)
				local best = math.huge
				for gx = x - 12, x + 12, 0.25 do
					for gd = d - 12, d + 12, 0.25 do
						if at(gx, gd) then
							best = math.min(best, math.sqrt((gx - x) ^ 2 + (gd - d) ^ 2 + (2.5 - y) ^ 2))
						end
					end
				end
				t.truthy(
					best <= prompt.MaxActivationDistance - 1,
					`{def.id}: the nearest place to stand is {best} away`
				)
			end
			t.eq(#items:GetChildren(), onSale)
		end
	)

	t.test("the shopkeeper: a town shop worker on the store's floor, walking his round behind the counter", function()
		local v = venue()
		local world = TownAI.build({ data = Data.default(), seed = 3 })
		local keeper: any = nil
		for _, a in world.actors do
			if a.post == "shop_worker" then
				local x, _, d = AlleyLayout.toLocal(v.place, a.x, a.y, a.z)
				if math.abs(x) < Store.IN_X and math.abs(d) < Store.IN_D then
					keeper = a
				end
			end
		end
		t.truthy(keeper ~= nil, "a shop worker inside the store")
		local c = Fixtures.COUNTER
		local hip = Species.def("human").hipHeight
		for _ = 1, 30 * 20 do
			TownAI.stepFrame(world, 1 / 30)
			local x, y, d = AlleyLayout.toLocal(v.place, keeper.x, keeper.y, keeper.z)
			-- behind the counter, between it and the back bar, along its length; standing on the store's floor
			t.truthy(d > c.d1 + 0.5 and d < Fixtures.BACKBAR.d0 - 0.5, `depth {d}`)
			t.truthy(x > c.x0 - 1 and x < c.x1 + 1, `across {x}`)
			t.near(y, hip, 0.3)
		end
	end)

	t.test("the plan's anchors are where the bake puts the counter, the shopkeeper and each item", function()
		local v = venue()
		local byNote: { [string]: any } = {}
		local anchors: { [string]: any } = {}
		for _, a in v.anchors do
			anchors[a.id] = a
			if a.kind == "item_shelf" then
				byNote[a.note] = a
			end
		end
		local c = Fixtures.COUNTER
		t.near(anchors.checkout.at[1], (c.x0 + c.x1) / 2, 0.01)
		t.near(anchors.checkout.at[3], (c.d0 + c.d1) / 2, 0.01)
		t.near(anchors.staff.at[1], Fixtures.STAFF.x, 0.01)
		t.near(anchors.staff.at[3], Fixtures.STAFF.d, 0.01)
		for _, def in ItemRules.CATALOG do
			local a = byNote[def.id]
			local s = (Fixtures.SLOTS :: any)[def.id]
			t.truthy(a ~= nil and s ~= nil, def.id)
			t.near(a.at[1], s.x, 0.01)
			t.near(a.at[2], s.y, 0.01)
			t.near(a.at[3], s.d, 0.01)
		end
	end)
end
