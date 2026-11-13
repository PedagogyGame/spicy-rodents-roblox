--!strict
-- tools/bake/skylift/Signs and the base station's frontage, built in memory (review: "the way there is not
-- signposted: from town nothing says there is a ride ... the station looks like a shed from the street"). The
-- fingerposts stand on the town's sidewalks and point the way to Lift Road; the pylon stands where Lift Road
-- begins; every piece stands on the ground and is clear of everything the town bake puts there (lamps, poles,
-- buildings, props: built in memory here), of the roads' carriageways and of the lift's own approach.
local roblox = require("@lune/roblox")
local Bake = require("@worldgen/Bake")
local Factory = require("@worldgen/Factory")
local SkyBake = require("../../tools/bake/skylift/Bake")
local Common = require("../../tools/bake/skylift/Common")
local Kit = require("../../tools/bake/alley/Kit")
local Signs = require("../../tools/bake/skylift/Signs")

-- the part's box, axis-aligned in `frame` (default the world)
local function aabb(p: any, frame: any?): (any, any)
	local cf, s = if frame then frame:ToObjectSpace(p.CFrame) else p.CFrame, p.Size
	local hx, hy, hz = s.X / 2, s.Y / 2, s.Z / 2
	local R = cf.Rotation
	local ex = math.abs(R.XVector.X) * hx + math.abs(R.YVector.X) * hy + math.abs(R.ZVector.X) * hz
	local ey = math.abs(R.XVector.Y) * hx + math.abs(R.YVector.Y) * hy + math.abs(R.ZVector.Y) * hz
	local ez = math.abs(R.XVector.Z) * hx + math.abs(R.YVector.Z) * hy + math.abs(R.ZVector.Z) * hz
	local c = cf.Position
	return roblox.Vector3.new(c.X - ex, c.Y - ey, c.Z - ez), roblox.Vector3.new(c.X + ex, c.Y + ey, c.Z + ez)
end

local function overlap(a0: any, a1: any, b0: any, b1: any, pad: number): boolean
	return a0.X < b1.X - pad
		and b0.X < a1.X - pad
		and a0.Y < b1.Y - pad
		and b0.Y < a1.Y - pad
		and a0.Z < b1.Z - pad
		and b0.Z < a1.Z - pad
end

local function partsOf(root: any): { any }
	local out = {}
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(out, d)
		end
	end
	return out
end

return function(t)
	local folder = SkyBake.build(roblox)
	local signs = folder:FindFirstChild("xs_lift_signs")
	local station = folder:FindFirstChild("f4_lift_base")
	local frontage = station and station:FindFirstChild("Frontage", true)
	local data = Bake.data()

	t.test("the model: streamed by default, within its stamped budget, every part anchored", function()
		t.truthy(signs ~= nil, "no xs_lift_signs in F4")
		t.eq(signs.ModelStreamingMode, roblox.Enum.ModelStreamingMode.Default)
		local parts = partsOf(signs)
		t.eq(signs:GetAttribute("PartBudget"), Signs.BUDGET)
		t.truthy(#parts <= Signs.BUDGET, `{#parts} parts`)
		for _, p in parts do
			t.eq(p.Anchored, true, p.Name)
		end
		t.truthy(frontage ~= nil, "the station has no frontage")
	end)

	t.test("the way is pointed from the town centre to Lift Road, every arm toward the lift", function()
		local base = Common.venue("f4_lift_base").position
		local fingers = 0
		local nearCentre, atWestside = false, 0
		for _, s in Signs.spots() do
			if s.kind == "finger" then
				fingers += 1
				if math.abs(s.x) < 60 and math.abs(s.z) < 60 then
					nearCentre = true
				end
				if math.abs(s.x + 697.5) < 4 then
					atWestside += 1
				end
				for _, a in s.arms :: { { any } } do
					local text, dx, dz = a[1], a[2], a[3]
					if text ~= "TOWN CENTRE" then
						-- the arm leads along the street toward the lift: west at the centre, south on the westside
						local next = if math.abs(s.x) < 60 then { -697.5, s.z } else { s.x, base.z }
						local tx, tz = next[1] - s.x, next[2] - s.z
						t.truthy(
							(tx * dx + tz * dz) / math.sqrt(tx * tx + tz * tz) > 0.95,
							`{s.name} {text} points away`
						)
					end
				end
			end
		end
		t.truthy(fingers >= 4, `{fingers} fingerposts`)
		t.truthy(nearCentre, "nothing at the town centre")
		t.truthy(atWestside >= 3, `{atWestside} on the westside street`)
		local pylon = signs:FindFirstChild("Pylon")
		t.truthy(pylon ~= nil, "no pylon")
		local board = pylon:FindFirstChild("Board")
		-- the board stands where the westside street ends and high enough to read from up the street
		t.truthy(math.abs(board.CFrame.Position.Z + 610) < 40, "the pylon is not at the street's end")
		t.truthy(board.CFrame.Position.Y - Common.ground(-757.5, -632) > 14, "the pylon's board is low")
	end)

	t.test("fingerposts on a sidewalk; the pylon, the shelter and the banners off every carriageway", function()
		local function onStrip(x: number, z: number, kind: string?): boolean
			for _, r in data.roads do
				if kind == nil or r.kind == kind then
					local along, across = if r.axis == "z" then z else x, if r.axis == "z" then x else z
					local a0, a1 = math.min(r.start, r["end"]), math.max(r.start, r["end"])
					if along >= a0 and along <= a1 and math.abs(across - r.coord) <= r.width / 2 then
						return true
					end
				end
			end
			return false
		end
		for _, s in Signs.spots() do
			if s.kind == "finger" then
				t.truthy(onStrip(s.x, s.z, "concrete"), `{s.name} is not on a sidewalk`)
			end
			t.falsy(onStrip(s.x, s.z, "asphalt"), `{s.name} stands in a road`)
		end
		-- and off Lift Road's own carriageway (x -741.25..-703.75)
		for _, p in partsOf(signs) do
			local c = p.CFrame.Position
			if c.Y - Common.ground(c.X, c.Z) < 6 and c.Z < -610 then
				t.falsy(c.X > -741.25 and c.X < -703.75, `{p.Parent.Name}.{p.Name} on Lift Road`)
			end
		end
	end)

	t.test("every post, plinth and leg stands on the ground: not floating, not lost under it", function()
		local feet = {
			Post = true,
			Base = true,
			Plinth = true,
			SeatLeg = true,
			CanopyPost = true,
			BenchLeg = true,
			RackLeg = true,
			Flagpole = true,
		}
		local n = 0
		for _, root in { signs, frontage } do
			for _, p in partsOf(root) do
				if feet[p.Name] then
					n += 1
					local a0, a1 = aabb(p)
					local c = p.CFrame.Position
					local g = Common.ground(c.X, c.Z)
					t.truthy(a0.Y <= g + 0.05, `{p.Parent.Name}.{p.Name} floats {a0.Y - g} over the ground`)
					t.truthy(a1.Y >= g + 0.1, `{p.Parent.Name}.{p.Name} is under the ground`)
				end
			end
		end
		t.truthy(n >= 20, `{n} feet`)
	end)

	t.test("clear of everything the town bake and the lift's approach put there", function()
		local f = Factory.new({
			Instance = roblox.Instance,
			Vector3 = roblox.Vector3,
			CFrame = roblox.CFrame,
			Color3 = roblox.Color3,
			Enum = roblox.Enum,
			UDim2 = roblox.UDim2,
			ColorSequence = roblox.ColorSequence,
		})
		local town = Bake.run(data, f)
		local others: { { any } } = {}
		local function collect(root: any, skipSurfaces: boolean)
			for _, p in partsOf(root) do
				-- road and sidewalk surfaces are walked on: posts stand through them
				local surface = string.sub(p.Name, 1, 3) == "Seg"
					or string.sub(p.Name, 1, 4) == "Curb"
					or string.sub(p.Name, 1, 4) == "Dash"
				local skyline = p.Transparency >= 1
				if not (skipSurfaces and surface) and not skyline and (p.CanCollide or p.Name == "Post") then
					local a0, a1 = aabb(p)
					table.insert(others, { a0, a1, `{p.Parent.Name}.{p.Name}` })
				end
			end
		end
		collect(town, true)
		for _, name in { "xs_lift_approach", "xs_lift_country" } do
			collect(folder:FindFirstChild(name), true)
		end
		local hits = 0
		for _, root in { signs, frontage } do
			for _, p in partsOf(root) do
				local a0, a1 = aabb(p)
				for _, o in others do
					if overlap(a0, a1, o[1], o[2], 0.02) then
						hits += 1
						if hits <= 12 then
							t.truthy(false, `{p.Parent.Name}.{p.Name} runs into {o[3]}`)
						end
					end
				end
			end
		end
		t.eq(hits, 0, "overlaps")
	end)

	t.test("the frontage keeps the steps, the door and the sign clear and stays in front of the station", function()
		local v = Common.venue("f4_lift_base")
		local inv = Kit.new(roblox, Common.place(v)):cf(0, 0, 0)
		local shell = station:FindFirstChild("Shell")
		local blocked = {}
		for _, p in partsOf(shell) do
			if p.Name == "Step" or p.Name == "StepCheek" or p.Name == "Sign" or p.Name == "DoorHeader" then
				local a0, a1 = aabb(p, inv)
				table.insert(blocked, { a0, a1, p.Name })
			end
		end
		for _, p in partsOf(frontage) do
			local a0, a1 = aabb(p, inv)
			for _, b in blocked do
				t.falsy(overlap(a0, a1, b[1], b[2], 0.02), `{p.Name} runs into the {b[3]}`)
			end
			-- out in front of the face (the venue's front is local -D, beyond D = -15)
			local l = inv:PointToObjectSpace(p.CFrame.Position)
			t.truthy(math.abs(l.Z) > 15 or math.abs(l.X) > 25, `{p.Name} is inside the station`)
		end
	end)
end
