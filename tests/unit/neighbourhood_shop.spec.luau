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
local ENV =
	{ CFrame = roblox.CFrame, Color3 = roblox.Color3, Enum = roblox.Enum, Instance = Instance, Vector3 = Vector3 }

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

-- Where a person (radius r, body from 0.7 to 5.2 above the floor) can walk on the shop's floor, flooded from the
-- landing in front of the door: every solid part that reaches into the body's height blocks the cells within r.
local STEP = 0.25
local GRID = { x0 = -23, x1 = 23, d0 = -21, d1 = 20 }
local function flood(root: any, v: any, r: number): (number, number) -> boolean
	local nx = math.floor((GRID.x1 - GRID.x0) / STEP)
	local nd = math.floor((GRID.d1 - GRID.d0) / STEP)
	local blocked: { [number]: boolean } = {}
	for _, p in solids(root) do
		local lo, hi = localBounds(v, p)
		if hi[2] > 0.7 and lo[2] < 5.2 then
			local i0 = math.max(0, math.floor((lo[1] - r - GRID.x0) / STEP))
			local i1 = math.min(nx, math.ceil((hi[1] + r - GRID.x0) / STEP))
			local j0 = math.max(0, math.floor((lo[3] - r - GRID.d0) / STEP))
			local j1 = math.min(nd, math.ceil((hi[3] + r - GRID.d0) / STEP))
			for i = i0, i1 do
				for j = j0, j1 do
					local x, d = GRID.x0 + i * STEP, GRID.d0 + j * STEP
					-- the cell's centre within r of the box (a round body against a square corner)
					local dx = math.max(lo[1] - x, 0, x - hi[1])
					local dd = math.max(lo[3] - d, 0, d - hi[3])
					if dx * dx + dd * dd < r * r then
						blocked[i * (nd + 1) + j] = true
					end
				end
			end
		end
	end
	local reached: { [number]: boolean } = {}
	local door = art.doorway
	local si = math.floor(((door.x0 + door.x1) / 2 - GRID.x0) / STEP + 0.5)
	local sj = math.floor((-20 - GRID.d0) / STEP + 0.5)
	local queue = { { si, sj } }
	reached[si * (nd + 1) + sj] = true
	local head = 1
	while head <= #queue do
		local c = queue[head]
		head += 1
		for _, o in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
			local i, j = c[1] + o[1], c[2] + o[2]
			local k = i * (nd + 1) + j
			-- in front of the door the walk stays on the landing (it may not wander off round the building)
			local x, d = GRID.x0 + i * STEP, GRID.d0 + j * STEP
			local onLanding = d < -18.3 and x > door.x0 - 0.9 and x < door.x1 + 0.9
			if
				i >= 0
				and i <= nx
				and j >= 0
				and j <= nd
				and not reached[k]
				and not blocked[k]
				and (onLanding or d >= -18.3)
			then
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

-- Is any reached cell within `reach` of the box (X, D bounds), on the side `side` names (or any side)?
local function reachesBox(at: (number, number) -> boolean, c: any, reach: number, side: string?): boolean
	local x0, x1 = c.centre[1] - c.size[1] / 2, c.centre[1] + c.size[1] / 2
	local d0, d1 = c.centre[3] - c.size[3] / 2, c.centre[3] + c.size[3] / 2
	local x = x0 - reach
	while x <= x1 + reach do
		local d = d0 - reach
		while d <= d1 + reach do
			local inSide = side == nil
				or (side == "front" and d < d0)
				or (side == "back" and d > d1)
				or (side == "east" and x > x1)
				or (side == "west" and x < x0)
			local outside = x < x0 or x > x1 or d < d0 or d > d1
			if inSide and outside and at(x, d) then
				return true
			end
			d += STEP
		end
		x += STEP
	end
	return false
end

local function collider(name: string): any
	for _, c in art.colliders do
		if c.name == name then
			return c
		end
	end
	error("no collider " .. name)
end

-- Does the segment from a to b (world points) pass through the part's box?
local function crosses(part: any, a: any, b: any): boolean
	local la, lb = part.CFrame:Inverse() * a, part.CFrame:Inverse() * b
	local h = part.Size / 2
	local t0, t1 = 0, 1
	for _, k in { "X", "Y", "Z" } do
		local p0, e = (la :: any)[k], (h :: any)[k]
		local dp = (lb :: any)[k] - p0
		if math.abs(dp) < 1e-9 then
			if math.abs(p0) > e then
				return false
			end
		else
			local u0, u1 = (-e - p0) / dp, (e - p0) / dp
			if u0 > u1 then
				u0, u1 = u1, u0
			end
			t0, t1 = math.max(t0, u0), math.min(t1, u1)
			if t0 > t1 then
				return false
			end
		end
	end
	return true
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
		-- 15 tables, racks, stools and shelves; his three chairs, six floor-standing pots and the open door's leaf
		t.eq(furniture, 25)
		for _, name in { "CAFE_Chair_A", "CAFE_Chair_B", "OFFICE_Chair", "PLANT_RubberEntrance_Pot", "DOOR_OpenFrame" } do
			t.truthy(collider(name).size[2] >= 1.2, name)
		end
		-- a chair's box reaches up to its back (a person walks round it, not through its back)
		t.truthy(collider("CAFE_Chair_A").size[2] > 3, "up to the chair's back")
		-- the open door's leaf stands beside the doorway, not in it
		local leaf = collider("DOOR_OpenFrame")
		local dx0 = leaf.centre[1] - leaf.size[1] / 2
		local dx1 = leaf.centre[1] + leaf.size[1] / 2
		t.truthy(dx1 <= art.doorway.x0 or dx0 >= art.doorway.x1, "the door leaf is clear of the doorway")
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

	t.test("a person reaches every room: the checkout, the cafe counter, the window table and the office", function()
		local root, _, v = bake()
		-- a possessed person's root part is 2 x 2: radius 1.1 leaves a margin; his layout's narrowest gaps
		-- (2.5 studs between the display table and a rack, the 4.2-stud bead curtain) must stay open to it
		local at = flood(root, v, 1.1)
		t.truthy(at((art.doorway.x0 + art.doorway.x1) / 2, -16), "inside the door")
		t.truthy(reachesBox(at, collider("RetailCheckout"), 1.0, "front"), "the checkout's customer side")
		t.truthy(reachesBox(at, collider("CafeCounter"), 1.0, "east"), "the cafe counter's customer side")
		t.truthy(reachesBox(at, collider("CAFE_WindowTable_Legs"), 1.5), "the cafe's window table")
		t.truthy(reachesBox(at, collider("OFFICE_DeskLegs"), 1.5), "the office desk")
		local cafe, office = collider("CafeFloor"), collider("OfficeFloor")
		t.truthy(reachesBox(at, { centre = cafe.centre, size = { 1, 0, 1 } }, 3), "the middle of the cafe")
		local inOffice = false
		local x = office.centre[1] - office.size[1] / 2
		while x < office.centre[1] + office.size[1] / 2 and not inOffice do
			local d = office.centre[3] - office.size[3] / 2
			while d < office.centre[3] + office.size[3] / 2 do
				if at(x, d) then
					inOffice = true
					break
				end
				d += STEP
			end
			x += STEP
		end
		t.truthy(inOffice, "the office behind the bead curtain")
		-- and nobody walks out through a wall: no reached cell outside his walls
		t.falsy(at(-23, 0) or at(23, 0) or at(0, 19.5), "outside the walls")
	end)

	t.test("the camera stops at his walls: opaque, colliding occluders just inside each wall and lintel", function()
		local root, kit = bake()
		local occ = root:FindFirstChild("Occluders")
		t.truthy(occ, "an Occluders model")
		local list = occ:GetChildren()
		-- Left, Back, Right, the divider's two pieces, the partition's two, the office side wall, two lintels
		t.eq(#list, 10)
		for _, p in list do
			-- what Roblox's default camera (Poppercam) and Client/Camera/CameraRig.occludes stop at
			t.truthy(p.CanCollide and p.CanQuery, p.Name)
			t.truthy(p.Transparency < 0.25, p.Name)
			t.falsy(p.CastShadow)
		end
		for _, c in art.occluders do
			-- each one sits inside his wall (the collider, or the lintel mesh), never in front of its face
			local w = kit:cf(c.centre[1], c.centre[2], c.centre[3]).Position
			local match = nil
			for _, p in list do
				if p.Name == c.name and (p.CFrame.Position - w).Magnitude < 1e-3 then
					match = p
				end
			end
			t.truthy(match, c.name)
		end
		for _, c in art.colliders do
			if c.name == "Left" or c.name == "OfficePartition" or c.name == "OfficeSide" then
				local inner = false
				for _, p in list do
					local w = kit:cf(c.centre[1], c.centre[2], c.centre[3]).Position
					if p.Name == c.name and (p.CFrame.Position - w).Magnitude < 1e-3 then
						inner = p.Size.X <= c.size[1] - 0.1 and p.Size.Z <= c.size[3] - 0.1
					end
				end
				t.truthy(inner, `{c.name} inside its wall`)
			end
		end
		-- a person in the office and the camera 12 studs behind them in the cafe: the partition is in between
		local function blockedBetween(ax: number, ad: number, bx: number, bd: number): boolean
			local a, b = kit:cf(ax, 5, ad).Position, kit:cf(bx, 5, bd).Position
			for _, p in list do
				if crosses(p, a, b) then
					return true
				end
			end
			return false
		end
		local office = collider("OfficeFloor")
		t.truthy(blockedBetween(-12, office.centre[3], -12, office.centre[3] - 12), "office -> cafe")
		-- beside the divider in the cafe, the camera in the retail room
		t.truthy(blockedBetween(-6, 5, 6, 5), "cafe -> retail")
		-- but not through the open passage between the rooms, nor through the shopfront's glass
		t.falsy(blockedBetween(-6, -7.5, 6, -7.5), "the passage stays open")
		t.falsy(blockedBetween(12, -15, 12, -27), "the windows stay clear")
	end)

	t.test("his roof's colliders cover the drawn roof: both slopes out over the gables, up to his shingles", function()
		local root, kit = bake()
		local cols = root:FindFirstChild("Colliders")
		local slopes = 0
		local half = Shop.INNER_X + Shop.WALL -- the shell's outer faces
		for _, c in art.roof.colliders do
			local p = nil
			local w = kit:cf(c.centre[1], c.centre[2], c.centre[3]).Position
			for _, q in cols:GetChildren() do
				if q.Name == c.name and (q.CFrame.Position - w).Magnitude < 1e-3 then
					p = q
				end
			end
			t.truthy(p and p.CanCollide, c.name)
			t.truthy(c.size[1] / 2 >= half, `{c.name} reaches over the gable walls`)
			if string.find(c.name, "^RoofSlope") then
				slopes += 1
				-- its top face is at his shingles' top: over the eave-side quarter of the slope, the collider's
				-- top is within a few hundredths of the drawn roof's top (Shop.topside is the deck's top)
				local d = if c.centre[3] < 0 then -12 else 12
				local up = c.up
				local top = c.centre[2] + (c.size[2] / 2 - (d - c.centre[3]) * up[3]) / up[2]
				t.truthy(top >= Shop.topside(art, d) - 1e-3, `{c.name} not below the deck's top`)
			end
		end
		t.eq(slopes, 2)
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
			-- the sign's letters glow (they read in the eave's shadow); nothing stands on his roof (the review: a
			-- board on the roof is not his design)
			t.eq(label.Parent.LightInfluence, 0)
			t.eq(shell:FindFirstChild("RoofSign"), nil)
			-- the board hangs on his window header band, under his eave: no part of his roof in front of the board
			-- comes down below its top (on the fascia it was hidden behind his gutter from the street)
			t.truthy(Shop.SIGN_Y0 >= 10.5 and Shop.SIGN_Y1 <= Shop.HEADER_TOP, "on the header band")
			for _, r in art.roofParts do
				local d = -r.at[3]
				if d < Shop.SIGN_D then
					local sx, sy, sz = r.box[1] / 2, r.box[2] / 2, r.box[3] / 2
					local right = r.right or { 1, 0, 0 }
					local up = r.up or { 0, 1, 0 }
					-- back = right x up: its Y component
					local backY = right[3] * up[1] - right[1] * up[3]
					local halfY = math.abs(right[2]) * sx + math.abs(up[2]) * sy + math.abs(backY) * sz
					t.truthy(r.at[2] - halfY > Shop.SIGN_Y1 + 0.5, `{r.name} hangs in front of the sign`)
				end
			end
			local lamps = root:FindFirstChild("Lamps")
			local lights, shadowed, fills = 0, 0, 0
			for _, p in lamps:GetChildren() do
				local l = p:FindFirstChildOfClass("PointLight")
				if l then
					lights += 1
					if l.Shadows then
						shadowed += 1
					end
					if string.find(p.Name, "Fill$") then
						fills += 1
						t.falsy(l.Shadows)
					end
				end
			end
			-- his six pendants and the desk lamp, one over the door, a fill in each of his three rooms
			t.eq(lights, #art.lamps + 1 + 3)
			t.eq(fills, 3)
			t.eq(shadowed, 3) -- only his three big retail shades cast shadows
		end
	)

	t.test(
		"the loader: his parts are visual only, untextured ones painted, glass see-through, each in its place",
		function()
			local root = bake()
			local names = {
				"CAFE_CounterTop",
				"FLOOR_Retail",
				"WALL_Left",
				"WINDOW_RemovableGlass",
				"LIGHT_Diffusers",
				"CAFE_Stool_01_Legs",
			}
			local roofNames = { "RidgeCap", "AsphaltShingleBand_-1_00" }
			local textured = { FLOOR_Retail = true }
			local asked: { number } = {}
			local report = ShopArt.install(root, {
				data = art,
				env = ENV,
				load = function(id: number): any
					table.insert(asked, id)
					return if id == art.assets.roof.id then asset(roofNames) else asset(names, textured)
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
			-- a textured mesh that arrives with no maps is painted its map's mean colour, not the white tint
			local wall, fb = shop.WALL_Left, record("WALL_Left").fallback
			t.truthy(fb and (fb[1] ~= 231 or fb[2] ~= 231), "a fallback colour from the map")
			t.eq(wall.Color, roblox.Color3.fromRGB(fb[1], fb[2], fb[3]))
			-- his lamp shades glow
			local shade = shop.LIGHT_Diffusers
			t.truthy(record("LIGHT_Diffusers").emissive)
			t.eq(shade.Material, roblox.Enum.Material.Neon)
			-- his plain boxes are Parts (the engine batches them), the shaped meshes stay MeshParts
			t.eq(counter.ClassName, "Part")
			t.near(counter.Size.Z, record("CAFE_CounterTop").box[3], 1e-4)
			t.eq(shop.CAFE_Stool_01_Legs.ClassName, "MeshPart")
			t.eq(floor.ClassName, "MeshPart")
			t.eq(glass.ClassName, "MeshPart")
			local roof = root:FindFirstChild("ArtRoof")
			local band, rb = roof["AsphaltShingleBand_-1_00"], record("AsphaltShingleBand_-1_00")
			t.eq(band.ClassName, "Part")
			t.falsy(band.CanCollide)
			-- turned with his slope: its up is his up, in the shop's frame
			local up = pivot:VectorToWorldSpace(Vector3.new(rb.up[1], rb.up[2], rb.up[3]))
			t.truthy(band.CFrame.UpVector:Dot(up) > 0.9999, "the band lies on his slope")
			t.truthy(
				(band.CFrame.Position - (pivot * CFrame.new(rb.at[1], rb.at[2], rb.at[3])).Position).Magnitude < 1e-3
			)
			t.eq(report.boxes, 3)
			t.eq(report.glowing, 1)
			-- in his file: 45 plain boxes in the shop and all 90 roof meshes
			local shopBoxes, roofBoxes = 0, 0
			for _, r in art.shop do
				if r.box then
					shopBoxes += 1
				end
			end
			for _, r in art.roofParts do
				if r.box then
					roofBoxes += 1
				end
			end
			t.eq(shopBoxes, 45)
			t.eq(roofBoxes, #art.roofParts)
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

	t.test("the boot's one call: carves and loads the shop, and says so when its bake was not run", function()
		-- a place built without the shop's bake: an empty Expansion slot, and the server says why
		local empty = Instance.new("Folder")
		local warned: { string } = {}
		local r = ShopArt.start(empty, {
			data = art,
			env = ENV,
			heartbeat = false,
			fill = function() end,
			warn = function(m: string)
				table.insert(warned, m)
			end,
		})
		t.eq(r.venues, 0)
		t.eq(#warned, 1)
		t.truthy(string.find(warned[1], "tools/bake/neighbourhood_shop.luau", 1, true), warned[1])
		-- no Workspace.Expansion at all: the same warning, nothing else
		t.truthy(ShopArt.start(nil, { data = art, heartbeat = false, warn = function() end }).missing)
		-- the baked shop: carved at once, loaded in the spawned task, no warning
		local expansion = Instance.new("Folder")
		local root = bake()
		root.Parent = expansion
		local carved, spawned, said = 0, 0, {}
		warned = {}
		local r2 = ShopArt.start(expansion, {
			data = art,
			env = ENV,
			fill = function()
				carved += 1
			end,
			load = function(): any
				return asset({ "CAFE_CounterTop" })
			end,
			spawn = function(f: () -> ())
				spawned += 1
				f()
			end,
			print = function(m: string)
				table.insert(said, m)
			end,
			warn = function(m: string)
				table.insert(warned, m)
			end,
		})
		t.eq(r2.venues, 1)
		t.eq(r2.missing, nil)
		t.eq(carved, 1)
		t.eq(spawned, 1)
		t.eq(#warned, 0)
		t.eq(root:GetAttribute("ArtLoaded"), "Shop,Roof")
		t.eq(#said, 1)
	end)
end
