--!strict
-- tools/bake/skylift/Countryside built in memory: the farmland under the sky lift's line (review: the first half
-- of the ride was "flat green grass, a few cone trees, the empty Lift Road and the next tower"). It is there and
-- under the line all the way across the plain, on the ground (not floating, not buried), and out of everyone's
-- way: the trail (bar the footbridge's rails beside it), the venues, the towers' footings, the cabins.
local roblox = require("@lune/roblox")
local SkyLift = require("@shared/Rides/SkyLift")
local Approach = require("../../tools/bake/skylift/Approach")
local Common = require("../../tools/bake/skylift/Common")
local Countryside = require("../../tools/bake/skylift/Countryside")

return function(t)
	local folder = roblox.Instance.new("Folder")
	local m = Countryside.build(roblox, folder)
	local bx, bz, ux, uz, rx, rz = Countryside.frame()
	local function uv(p: any): (number, number)
		return (p.X - bx) * ux + (p.Z - bz) * uz, (p.X - bx) * rx + (p.Z - bz) * rz
	end
	local parts = {}
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(parts, d)
		end
	end

	t.test("the model: streamed by default, within its budget, every part anchored", function()
		t.eq(m.Name, "xs_lift_country")
		t.eq(m.ModelStreamingMode, roblox.Enum.ModelStreamingMode.Default)
		t.truthy(#parts <= Countryside.BUDGET, `{#parts} parts`)
		t.truthy(#parts >= 120, `{#parts} parts: the plain is still bare`)
		for _, p in parts do
			t.eq(p.Anchored, true, p.Name)
		end
	end)

	t.test("under the line all the way across the plain, on both sides, and the ride passes over it", function()
		-- something within 120 st of the centre line in every 100 st of the plain (u 100..520)
		local bins: { [number]: number } = {}
		local left, right = 0, 0
		for _, p in parts do
			local u, v = uv(p.CFrame.Position)
			if math.abs(v) < 120 then
				local k = math.floor(u / 100)
				bins[k] = (bins[k] or 0) + 1
			end
			left += if v < -10 then 1 else 0
			right += if v > 10 then 1 else 0
		end
		for k = 1, 4 do
			t.truthy((bins[k] or 0) >= 5, `only {bins[k] or 0} pieces near the line at u {k * 100}..{k * 100 + 100}`)
		end
		t.truthy(left > 40 and right > 20, `{left} left of the line, {right} right`)
		-- the brook runs under the cabins; the lane passes under tower 3
		local brookUnder, laneByTower = false, false
		local t3 = SkyLift.towers()[3]
		for _, p in parts do
			local pos = p.CFrame.Position
			local _, v = uv(pos)
			if p.Name == "Brook" and math.abs(v) < 12 then
				brookUnder = true
			end
			if p.Name == "Lane" and math.sqrt((pos.X - t3.x) ^ 2 + (pos.Z - t3.z) ^ 2) < 25 then
				laneByTower = true
			end
		end
		t.truthy(brookUnder, "the brook does not cross under the line")
		t.truthy(laneByTower, "the lane does not pass tower 3")
	end)

	t.test("on the ground: field strips, the lane and the brook neither float nor sink", function()
		for _, p in parts do
			if p.Name == "Strip" or p.Name == "Lane" or p.Name == "Brook" then
				local cf, s = p.CFrame, p.Size
				for _, f in { -0.45, 0, 0.45 } do
					local top = (cf * roblox.CFrame.new(0, s.Y / 2, f * s.Z)).Position
					local over = top.Y - Common.ground(top.X, top.Z)
					t.truthy(over > 0.02 and over < 1.2, `{p.Name} top {over} over the ground`)
				end
			end
		end
	end)

	t.test("out of the way: the trail (bar the footbridge), the venues, the towers' footings, the cabins", function()
		local hw = Approach.TRAIL_WIDTH / 2
		for _, p in parts do
			local pos = p.CFrame.Position
			local bridge = string.sub(p.Name, 1, 6) == "Bridge"
			if not bridge and p.Name ~= "Brook" then
				-- the part's footprint corners stay off the trail
				local s = p.Size
				for _, c in { { 0, 0 }, { 1, 1 }, { -1, 1 }, { 1, -1 }, { -1, -1 } } do
					local q = (p.CFrame * roblox.CFrame.new(c[1] * s.X / 2, 0, c[2] * s.Z / 2)).Position
					local d = Approach.trailDistance(q.X, q.Z)
					t.truthy(d > hw + 0.2, `{p.Name} at {math.floor(q.X)}, {math.floor(q.Z)} is {d} from the trail`)
				end
			end
			if bridge then
				-- the rails and posts stand either side of the trail, never on it
				t.truthy(Approach.trailDistance(pos.X, pos.Z) > hw, `{p.Name} on the trail`)
			end
			t.falsy(Approach.inSite(pos.X, pos.Z, 2), `{p.Name} in a venue's site`)
			for _, tw in SkyLift.towers() do
				t.truthy((tw.x - pos.X) ^ 2 + (tw.z - pos.Z) ^ 2 > 4.5 ^ 2, `{p.Name} on tower {tw.index}'s footing`)
			end
			t.truthy(SkyLift.sweptClear(pos.X, pos.Y + p.Size.Y / 2, pos.Z, 1), `{p.Name} in the cabins' way`)
		end
	end)
end
