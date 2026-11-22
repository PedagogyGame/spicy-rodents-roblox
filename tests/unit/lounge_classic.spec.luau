--!strict
-- THE GILDED ACORN, the 1940s lounge (f3_lounge_classic; brief v2 "Lounge one", addendum D14): the bake in memory
-- with the same code tools/bake/lounge_classic.luau runs (tools/bake/lounge_classic/Lounge): its place, its part,
-- light and shadow budgets, and a sealed shell (nothing gets in but through the door's prompt).
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local AlleyLayout = require("@shared/Attractions/AlleyLayout")
local Expansion = require("../../generated/Expansion")
local Kit = require("../../tools/bake/alley/Kit")
local Lounge = require("../../tools/bake/lounge_classic/Lounge")
local Style = require("../../tools/bake/lounge_classic/Style")
local Data = require("@shared/Data")
local LoungeArt = require("@shared/Attractions/LoungeArt")
local LoungeClassic = require("@shared/Attractions/LoungeClassic")

local Vector3 = roblox.Vector3

local function venue(): any
	for _, v in (Expansion :: any).venues do
		if v.id == "f3_lounge_classic" then
			return v
		end
	end
	error("f3_lounge_classic missing from generated/Expansion")
end

local function bake(): (any, any)
	local v = venue()
	local folder = roblox.Instance.new("Folder")
	local root = Lounge.build(Kit.new(roblox, v.place), folder, v)
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

local function lights(root: any): { any }
	local out = {}
	for _, d in root:GetDescendants() do
		if d:IsA("Light") then
			table.insert(out, d)
		end
	end
	return out
end

-- Is the world point inside any solid part (oriented boxes; balls and cylinders by their boxes)?
local function solidAt(list: { any }, w: any): boolean
	for _, p in list do
		local l = p.CFrame:Inverse() * w
		local s = p.Size
		if math.abs(l.X) < s.X / 2 and math.abs(l.Y) < s.Y / 2 and math.abs(l.Z) < s.Z / 2 then
			return true
		end
	end
	return false
end

local function solids(root: any): { any }
	local out = {}
	for _, p in parts(root) do
		if p.CanCollide and p.Transparency < 1 then
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

-- Where a person (radius r, body from 0.7 to 5.2 above the floor) can walk on the floor, flooded from just inside
-- the door: every colliding part that reaches into the body's height blocks the cells within r of its bounds.
local STEP = 0.25
local GRID = { x0 = -24, x1 = 24, d0 = -21, d1 = 27 }
local function flood(root: any, v: any, r: number): (number, number) -> boolean
	local nx = math.floor((GRID.x1 - GRID.x0) / STEP)
	local nd = math.floor((GRID.d1 - GRID.d0) / STEP)
	local blocked: { [number]: boolean } = {}
	for _, p in parts(root) do
		if p.CanCollide then
			local lo, hi = localBounds(v, p)
			if hi[2] > 0.7 and lo[2] < 5.2 then
				for i = math.max(0, math.floor((lo[1] - r - GRID.x0) / STEP)), math.min(nx, math.ceil((hi[1] + r - GRID.x0) / STEP)) do
					for j = math.max(0, math.floor((lo[3] - r - GRID.d0) / STEP)), math.min(nd, math.ceil((hi[3] + r - GRID.d0) / STEP)) do
						local x, d = GRID.x0 + i * STEP, GRID.d0 + j * STEP
						local dx = math.max(lo[1] - x, 0, x - hi[1])
						local dd = math.max(lo[3] - d, 0, d - hi[3])
						if dx * dx + dd * dd < r * r then
							blocked[i * (nd + 1) + j] = true
						end
					end
				end
			end
		end
	end
	local function key(x: number, d: number): (number, number)
		return math.floor((x - GRID.x0) / STEP + 0.5), math.floor((d - GRID.d0) / STEP + 0.5)
	end
	local reached: { [number]: boolean } = {}
	local si, sj = key(0, Style.DOOR_D + Style.WALL + 1.5)
	assert(not blocked[si * (nd + 1) + sj], "the door's inside is blocked")
	local queue = { { si, sj } }
	reached[si * (nd + 1) + sj] = true
	local head = 1
	while head <= #queue do
		local c = queue[head]
		head += 1
		for _, o in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
			local i, j = c[1] + o[1], c[2] + o[2]
			local k = i * (nd + 1) + j
			if i >= 0 and i <= nx and j >= 0 and j <= nd and not reached[k] and not blocked[k] then
				reached[k] = true
				table.insert(queue, { i, j })
			end
		end
	end
	return function(x: number, d: number): boolean
		local i, j = key(x, d)
		return reached[i * (nd + 1) + j] == true
	end
end

return function(t)
	t.test("its place: the leisure quarter, facing +Z onto Bowl Lane, the floor above the ground", function()
		local v = venue()
		t.eq(v.family, "F3")
		t.eq(v.name, "THE GILDED ACORN")
		t.eq(v.facing, "+Z")
		t.near(v.position.x, 1487, 1e-6)
		t.near(v.position.z, -362, 1e-6)
		t.near(v.floorY, 9.5, 1e-6)
		t.eq(v.footprint.w, 2 * Style.OUTER_X)
		t.eq(v.footprint.d, Style.BACK_D - Style.FRONT_D)
	end)

	t.test("the bake: one Atomic model inside its part, light and shadow budgets, inside its site", function()
		local root, v = bake()
		local list = parts(root)
		t.eq(root:GetAttribute("Parts"), #list)
		t.truthy(#list <= Lounge.PART_BUDGET, `{#list} parts, cap {Lounge.PART_BUDGET}`)
		t.truthy(Lounge.PART_BUDGET <= v.partBudget)
		t.eq(root.ModelStreamingMode, roblox.Enum.ModelStreamingMode.Atomic)
		local ls = lights(root)
		local shadowed = 0
		for _, l in ls do
			if l.Shadows then
				shadowed += 1
			end
		end
		t.eq(root:GetAttribute("Lights"), #ls)
		t.eq(root:GetAttribute("Shadows"), shadowed)
		t.truthy(#ls <= Lounge.LIGHT_BUDGET, `{#ls} lights, budget {Lounge.LIGHT_BUDGET}`)
		t.truthy(shadowed <= Lounge.SHADOW_BUDGET, `{shadowed} shadowed, budget {Lounge.SHADOW_BUDGET}`)
		-- everything inside the site, and in front only the forecourt (to Bowl Lane's planned sidewalk)
		local s = v.site
		for _, p in list do
			local c = p.CFrame.Position
			local x, y, d = AlleyLayout.toLocal(v.place, c.X, c.Y, c.Z)
			t.truthy(x >= s.x0 - 0.5 and x <= s.x1 + 0.5 and d <= s.d1 + 0.5, p:GetFullName())
			t.truthy(d >= Style.FORECOURT_D, `{p:GetFullName()} at D {d}`)
			t.truthy(y <= Style.CREST + 0.01 and y >= v.ground.min - v.floorY - 1.01, `{p:GetFullName()} at Y {y}`)
		end
	end)

	t.test("sealed: walls, roof, floor and the door's leaves are solid all the way round", function()
		local root, v = bake()
		local list = solids(root)
		local function w(x: number, y: number, d: number): any
			local wx, wy, wz = AlleyLayout.toWorld(v.place, x, y, d)
			return Vector3.new(wx, wy, wz)
		end
		local mid = Style.WALL / 2
		-- the side and back walls, every 0.5 stud along and up
		for y = 0.25, Style.CEILING, 0.5 do
			for d = Style.FRONT_D + 0.25, Style.BACK_D - 0.25, 0.5 do
				t.truthy(solidAt(list, w(-Style.OUTER_X + mid, y, d)), `west wall open at Y {y} D {d}`)
				t.truthy(solidAt(list, w(Style.OUTER_X - mid, y, d)), `east wall open at Y {y} D {d}`)
			end
			for x = -Style.OUTER_X + 0.25, Style.OUTER_X - 0.25, 0.5 do
				t.truthy(solidAt(list, w(x, y, Style.BACK_D - mid)), `back wall open at X {x} Y {y}`)
				-- the front: the wall either side of the alcove, the alcove's sides, and the door wall with its leaves
				local front = if math.abs(x) > Style.ALCOVE_X + Style.WALL
					then Style.FRONT_D + mid
					elseif math.abs(x) >= Style.ALCOVE_X then Style.DOOR_D - 2
					else Style.DOOR_D + 0.5
				local probe = if y >= Style.ALCOVE_TOP + 0.1 and math.abs(x) <= Style.ALCOVE_X + Style.WALL
					then w(x, y, Style.FRONT_D + mid)
					else w(x, y, front)
				-- the gap between the two leaves (0.04 stud) is narrower than any body
				if math.abs(x) > 0.05 then
					t.truthy(solidAt(list, probe), `front open at X {x} Y {y}`)
				end
			end
		end
		-- the ceiling and the floor, every stud
		for x = -Style.INNER_X + 0.5, Style.INNER_X - 0.5, 1 do
			for d = Style.FRONT_D + Style.WALL + 0.5, Style.INNER_BACK - 0.5, 1 do
				t.truthy(solidAt(list, w(x, Style.CEILING + 0.5, d)), `ceiling open at X {x} D {d}`)
				if math.abs(x) > Style.ALCOVE_X + Style.WALL or d > Style.DOOR_D + Style.WALL then
					t.truthy(solidAt(list, w(x, -0.1, d)), `floor open at X {x} D {d}`)
				end
			end
		end
	end)

	t.test(
		"a person walks from the door to the bar, every booth, the tables, the stage, the fire and behind the bar",
		function()
			local root, v = bake()
			local at = flood(root, v, 1.0)
			local places: { [string]: { number } } = {
				bar = { Style.STOOL_GAP / 2, Style.BAR_D0 - 1.6 },
				bartender = Style.BARTENDER,
				stage = { -18, Style.STAGE.d0 - 1.6 },
				fire = { Style.INNER_X - 4, Style.FIRE_D },
			}
			for i, b in Style.BOOTHS do
				-- the open end of each booth, between its benches
				places[`booth{i}`] = { (if b[1] < 0 then -1 else 1) * (Style.BOOTH_X0 - 1.2), b[2] }
			end
			for i, tb in Style.TABLES do
				places[`table{i}`] = { tb[1], tb[2] - 2.6 }
			end
			for name, p in places do
				t.truthy(at(p[1], p[2]), `{name} at X {p[1]} D {p[2]} is not reached from the door`)
			end
		end
	)

	-- owner D32 ("sitting down traps you and you can't actually leave"): the server stands a person who gets up at the
	-- seat's LoungeClassic.standSpot; a body (radius a stud) there is clear of every solid piece of furniture and on the
	-- floor that is walked to from the door, so getting up never leaves anyone wedged in a booth or behind a chair
	t.test("D32: every seat's stand spot is clear floor, reached from the door", function()
		local root, v = bake()
		local at = flood(root, v, 1.0)
		for _, st in LoungeClassic.SEATS do
			local x, d = LoungeClassic.standSpot(st)
			t.truthy(at(x, d), `{st.id}: its stand spot X {x} D {d} is not reached from the door`)
			t.truthy(LoungeClassic.inside(x, 0, d), `{st.id}: in the room`)
		end
	end)

	t.test("mild: hot drinks and snow cones only; no bottles, taps or cocktail glasses anywhere", function()
		local root = bake()
		for _, d in root:GetDescendants() do
			local n = string.lower(d.Name)
			for _, bad in { "bottle", "tap%f[%a]", "beer", "wine", "whisk", "cocktail", "martini", "liquor", "keg" } do
				t.truthy(string.find(n, bad) == nil, d:GetFullName())
			end
			if d:IsA("TextLabel") then
				t.truthy(d.Text == Style.SIGN or d.Text == Style.MENU, d.Text)
			end
		end
		t.eq(Style.MENU, "HOT COCOA  ·  COFFEE  ·  GREEN TEA  ·  SNOW CONES")
	end)

	t.test("no squirrel route (a bough, a pole, a wire, a pipe) runs into or through the building", function()
		local v = venue()
		local registry = Data.default():routes()
		t.truthy(#registry:all() > 1000, "the town's routes are loaded")
		local near = 0
		for _, r in registry:all() do
			local pts = r.points
			for i = 1, #pts do
				local a, b = pts[i], pts[math.min(i + 1, #pts)]
				-- along each leg, a point every half stud
				local n = math.max(1, math.ceil(math.sqrt((b.x - a.x) ^ 2 + (b.y - a.y) ^ 2 + (b.z - a.z) ^ 2) * 2))
				for k = 0, n do
					local f = k / n
					local x, y, d = AlleyLayout.toLocal(
						v.place,
						a.x + (b.x - a.x) * f,
						a.y + (b.y - a.y) * f,
						a.z + (b.z - a.z) * f
					)
					if math.abs(x) < Style.OUTER_X + 6 and d > Style.FORECOURT_D - 6 and d < Style.BACK_D + 6 then
						near += 1
					end
					local inBuilding = math.abs(x) < Style.OUTER_X + 0.5
						and d > Style.FRONT_D - 0.5
						and d < Style.BACK_D + 0.5
						and y < Style.CREST + 0.5
					t.truthy(not inBuilding, `route {r.name} at X {x} Y {y} D {d}`)
				end
			end
		end
		-- (none comes within 6 studs today: the nearest is the alley yard's downspout, 68 studs off)
		t.eq(near, 0)
	end)

	t.test("the Blender pieces: inside their triangle budget, each within the baked parts it stands in for", function()
		local root, v = bake()
		-- uploaded and approved (tools/blender/lounge_classic/publish.py): the game's id is the record's
		local record = serde.decode("json", fs.readFile("data/art/lounge_classic.json"))
		t.truthy(tonumber(LoungeArt.ASSET_ID) ~= nil, "the hero pieces are uploaded")
		t.eq(record.asset.assetId, LoungeArt.ASSET_ID)
		t.eq(record.asset.moderation, "Approved")
		local total = 0
		for _, p in LoungeArt.PIECES do
			total += p.tris
		end
		t.eq(total, LoungeArt.TOTAL_TRIS)
		t.truthy(total <= LoungeArt.BUDGET and LoungeArt.BUDGET <= 20000, `{total} triangles`)
		-- every part it hides is in the bake, under Interior
		local interior = root:FindFirstChild("Interior")
		local bounds: { [string]: { lo: { number }, hi: { number } } } = {}
		local function grow(key: string, lo: { number }, hi: { number })
			local b = bounds[key]
				or { lo = { math.huge, math.huge, math.huge }, hi = { -math.huge, -math.huge, -math.huge } }
			for k = 1, 3 do
				b.lo[k] = math.min(b.lo[k], lo[k])
				b.hi[k] = math.max(b.hi[k], hi[k])
			end
			bounds[key] = b
		end
		-- which piece group a name belongs to: a booth's, the bar's (its rail and arm roll too) or the walls'
		local function groupOf(name: string): string
			local booth = string.match(name, "^(Booth%d)")
			if booth then
				return booth
			end
			for _, prefix in { "Bar", "ArmRoll", "FootRail", "RailBracket" } do
				if string.sub(name, 1, #prefix) == prefix then
					return "Bar"
				end
			end
			return "Wall"
		end
		for _, n in LoungeArt.REPLACES do
			local part = interior:FindFirstChild(n)
			t.truthy(part ~= nil and part:IsA("BasePart"), `no baked part {n}`)
			if part then
				local lo, hi = localBounds(v, part)
				grow(groupOf(n), lo, hi)
			end
		end
		for _, p in LoungeArt.PIECES do
			local key = groupOf(p.name)
			local b = bounds[key]
			t.truthy(b ~= nil, `no baked parts for {p.name}`)
			for k = 1, 3 do
				local lo, hi = p.centre[k] - p.size[k] / 2, p.centre[k] + p.size[k] / 2
				t.truthy(
					lo >= b.lo[k] - 0.7 and hi <= b.hi[k] + 0.7,
					`{p.name} axis {k}: {lo}..{hi} outside {b.lo[k]}..{b.hi[k]}`
				)
			end
		end
	end)

	t.test("the spots and the back bar's strip shine down (a light's face, turned with its part)", function()
		local root = bake()
		local NORMALS = {
			Right = Vector3.new(1, 0, 0),
			Left = Vector3.new(-1, 0, 0),
			Top = Vector3.new(0, 1, 0),
			Bottom = Vector3.new(0, -1, 0),
			Back = Vector3.new(0, 0, 1),
			Front = Vector3.new(0, 0, -1),
		}
		local n = 0
		for _, l in root:GetDescendants() do
			if l:IsA("SpotLight") or l:IsA("SurfaceLight") then
				local dir = l.Parent.CFrame:VectorToWorldSpace(NORMALS[l.Face.Name])
				t.truthy(dir.Y < -0.99, `{l.Parent.Name}'s light points {dir}`)
				n += 1
			end
		end
		t.eq(n, 3)
	end)
end
