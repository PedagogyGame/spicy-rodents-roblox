--!strict
-- THE GILDED ACORN, the 1940s lounge (f3_lounge_classic; brief v2 "Lounge one", addendum D14): the bake in memory
-- with the same code tools/bake/lounge_classic.luau runs (tools/bake/lounge_classic/Lounge): its place, its part,
-- light and shadow budgets, and a sealed shell (nothing gets in but through the door's prompt).
local roblox = require("@lune/roblox")
local AlleyLayout = require("@shared/Attractions/AlleyLayout")
local Expansion = require("../../generated/Expansion")
local Kit = require("../../tools/bake/alley/Kit")
local Lounge = require("../../tools/bake/lounge_classic/Lounge")
local Style = require("../../tools/bake/lounge_classic/Style")

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
end
