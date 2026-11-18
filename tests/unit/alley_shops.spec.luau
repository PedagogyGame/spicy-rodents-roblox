--!strict
-- The bowling alley's front rooms dressed (tools/bake/alley/Shops; BRIEF_ADDENDUM D5), baked in memory by the same
-- code as build/Attractions.rbxm: every fitting inside its own room's rectangle (Shared/Attractions/AlleyLayout.zone),
-- the whole within Shops.BUDGET parts, what the brief names there (a wall of balls, the cubbies by size with pairs in
-- them and the spray bench, souvenirs on shelves and a cash desk, the snack bar's grill and fridge), and no light of
-- its own (the rooms keep the house lights). The walk tests (attractions_alley_bake, alley_staff) hold the posts,
-- the routes and the employees' loops clear of all of it.
local roblox = require("@lune/roblox")
local AlleyLayout = require("@shared/Attractions/AlleyLayout")
local BakedWorld = require("../lib/BakedWorld")
local Shops = require("../../tools/bake/alley/Shops")

local L = AlleyLayout
-- (what stands on a serving counter in the room's opening, on its +X or +D wall, may reach over the counter)
local SERVING = AlleyLayout.PARTITION_T + 1.6
local ROOMS = { BallShop = "ball_shop", ShoeRental = "shoe_rental", GiftShop = "gift_shop", SnackKitchen = "snack_bar" }

return function(t)
	local _, place, root = BakedWorld.bakeAlley()

	t.test("every fitting in its own room, the whole inside the budget", function()
		local total = 0
		local counts: { [string]: { [string]: number } } = {}
		for model, room in ROOMS do
			local m = root:FindFirstChild(model)
			t.truthy(m ~= nil, model)
			local z = L.zone(room)
			counts[model] = {}
			for _, d in m:GetDescendants() do
				if d:IsA("BasePart") then
					total += 1
					counts[model][d.Name] = (counts[model][d.Name] or 0) + 1
					local p = d.CFrame.Position
					local X, Y, D = L.toLocal(place, p.X, p.Y, p.Z)
					-- the part's outline (its rotated box's extent) in the room, from the floor to the ceiling
					local cf = d.CFrame
					local s = d.Size
					local ex = (
						math.abs(cf.RightVector.X) * s.X
						+ math.abs(cf.UpVector.X) * s.Y
						+ math.abs(cf.LookVector.X) * s.Z
					) / 2
					local ez = (
						math.abs(cf.RightVector.Z) * s.X
						+ math.abs(cf.UpVector.Z) * s.Y
						+ math.abs(cf.LookVector.Z) * s.Z
					) / 2
					local in_ = X - ex >= z.x0 - 0.3
						and X + ex <= z.x1 + SERVING
						and D - ez >= z.d0 - 0.3
						and D + ez <= z.d1 + SERVING
						and Y >= 0
						and Y <= L.CEILING_Y
					t.truthy(in_, `{model}.{d.Name} at X {X} D {D} is outside {room}`)
				elseif d:IsA("Light") then
					t.truthy(false, `{model} carries a light ({d:GetFullName()})`)
				end
			end
		end
		print(`      the shops' fittings: {total} parts (budget {Shops.BUDGET})`)
		t.truthy(total <= Shops.BUDGET, `{total} parts`)
		t.eq(root:GetAttribute("ShopParts"), total)
		-- what the brief names
		t.truthy((counts.BallShop.Ball or 0) >= 30, "a wall of balls")
		t.truthy((counts.BallShop.DrillColumn or 0) == 1, "the drilling bench")
		t.truthy((counts.ShoeRental.Pair or 0) >= 20, "pairs in the cubbies")
		t.truthy((counts.ShoeRental.CubbyDivider or 0) >= 5, "the cubbies, one column a size")
		t.truthy((counts.ShoeRental.SprayCan or 0) >= 2, "the spray bench")
		t.truthy((counts.GiftShop.PlushAcorn or 0) >= 4 and (counts.GiftShop.Mug or 0) >= 4, "souvenirs on the shelves")
		t.truthy((counts.GiftShop.Desk or 0) == 1, "the cash desk")
		t.truthy((counts.SnackKitchen.Fridge or 0) == 1 and (counts.SnackKitchen.Cooker or 0) == 1, "the kitchen")
	end)

	t.test("the cubbies are labelled by size, read from the room", function()
		local strip = root:FindFirstChild("ShoeRental"):FindFirstChild("SizeStrip")
		t.truthy(strip ~= nil)
		local gui = strip:FindFirstChildOfClass("SurfaceGui")
		t.eq(gui.Face, roblox.Enum.NormalId.Right)
		local texts = {}
		for _, l in gui:GetChildren() do
			if l:IsA("TextLabel") then
				table.insert(texts, { l.Position.X.Scale, l.Text })
			end
		end
		table.sort(texts, function(a, b)
			return a[1] < b[1]
		end)
		local words = {}
		for _, x in texts do
			table.insert(words, x[2])
		end
		t.eq(table.concat(words, " "), "6-7 8 9 10 11 12-13")
	end)
end
