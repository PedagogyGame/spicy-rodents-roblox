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
		for _, c in { { -20, -18 }, { 20, -18 }, { -20, 18 }, { 20, 18 }, { 0, 0 } } do
			t.truthy(at(c[1], c[2]), `the floor at ({c[1]}, {c[2]})`)
		end
		-- nobody walks through a window or a wall
		t.eq(at(-16, -Store.IN_D - 2), false)
		t.eq(at(-Store.IN_X - 2, 0), false)
	end)
end
