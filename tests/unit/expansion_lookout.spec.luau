--!strict
-- THE LOOKOUT (venue f3_hilltop), baked in memory by tools/bake/lookout/Lookout (the sky-lift plan's lane 3;
-- brief v2 line 250 "a hilltop restaurant (second vantage over the town)"; BATCH2_SPEC item 35 and §2.2, §2.9):
-- the model and its far-view layer, the budget, the floor and the skirt, every entrance open, the F3 anchors,
-- nothing where a cabin or its hanger ever passes (Shared/Rides/SkyLift.sweptClear, sampled over every face),
-- nothing outside the site but the terrace steps on the trail's path, the seats, the terrace and its rail, the
-- steps down to the ground, the terrain carve.
local roblox = require("@lune/roblox")
local AlleyLayout = require("@shared/Attractions/AlleyLayout")
local Height = require("@shared/World/Height")
local SkyLift = require("@shared/Rides/SkyLift")
local Kit = require("../../tools/bake/alley/Kit")
local Lookout = require("../../tools/bake/lookout/Lookout")

type Corner = { number }

return function(t)
	local mod = require("../../generated/Expansion") :: any
	local ext = require("../../generated/TerrainExtensions") :: any
	local venue: any
	for _, v in mod.venues do
		if v.id == "f3_hilltop" then
			venue = v
		end
	end
	local place = venue.place

	local folder = roblox.Instance.new("Folder")
	folder.Name = "F4"
	local kit = Kit.new(roblox, place)
	local root = Lookout.build(kit, folder, venue)
	local sky = folder:FindFirstChild("f3_hilltop_Skyline")

	local function inFolder(p: any, name: string): boolean
		local a = p.Parent
		while a and a ~= root do
			if a.Name == name then
				return true
			end
			a = a.Parent
		end
		return false
	end
	-- every built part of the venue (the carve boxes and anchor markers apart)
	local parts: { any } = {}
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") and not inFolder(d, "TerrainCarve") and not inFolder(d, "Anchors") then
			table.insert(parts, d)
		end
	end
	local function corners(p: any): { Corner }
		local out = {}
		local s = p.Size / 2
		for _, sx in { -1, 1 } do
			for _, sy in { -1, 1 } do
				for _, sz in { -1, 1 } do
					local w = p.CFrame * roblox.Vector3.new(sx * s.X, sy * s.Y, sz * s.Z)
					table.insert(out, { w.X, w.Y, w.Z })
				end
			end
		end
		return out
	end
	local function toLocal(c: Corner): (number, number, number)
		return AlleyLayout.toLocal(place, c[1], c[2], c[3])
	end
	-- is the world point inside the part's box (grown by g)?
	local function inside(p: any, x: number, y: number, z: number, g: number): boolean
		local l = p.CFrame:PointToObjectSpace(roblox.Vector3.new(x, y, z))
		local s = p.Size / 2
		return math.abs(l.X) <= s.X + g and math.abs(l.Y) <= s.Y + g and math.abs(l.Z) <= s.Z + g
	end
	local function named(name: string): { any }
		local out = {}
		for _, p in parts do
			if p.Name == name then
				table.insert(out, p)
			end
		end
		return out
	end

	t.test("the venue Model and its far-view layer: attributes, streaming, budget", function()
		t.eq(root.Name, "f3_hilltop")
		t.eq(root:GetAttribute("VenueId"), "f3_hilltop")
		t.eq(root:GetAttribute("Family"), "F3")
		t.eq(root:GetAttribute("Type"), "restaurant_hilltop")
		t.near(root:GetAttribute("FloorY"), 116, 1e-9)
		t.near(root:GetAttribute("Yaw"), 0.85, 1e-9)
		t.eq(root:GetAttribute("PartBudget"), 1000)
		t.eq(root.ModelStreamingMode.Name, "Atomic")
		t.truthy(root:FindFirstChild("Anchors") and root:FindFirstChild("TerrainCarve"))
		local n = 0
		for _, d in root:GetDescendants() do
			if d:IsA("BasePart") then
				n += 1
			end
		end
		t.truthy(n <= venue.partBudget * 1.1, `{n} parts against a budget of {venue.partBudget} (+10%)`)
		t.truthy(sky ~= nil and sky.ModelStreamingMode.Name == "Persistent", "f3_hilltop_Skyline, Persistent")
		local k, farOnly = 0, 0
		for _, d in sky:GetDescendants() do
			if d:IsA("BasePart") then
				k += 1
				t.falsy(d.CanCollide or d.CanQuery or d.CastShadow, d.Name)
				if d:GetAttribute("FarOnly") then
					farOnly += 1
					t.eq(d.Transparency, 1)
				else
					-- an inset copy: inside a real part of the venue, so it never shows up close
					local hidden = false
					for _, p in parts do
						if p.Transparency < 0.5 and p.Material.Name ~= "Glass" then
							local ok = true
							for _, c in corners(d) do
								if not inside(p, c[1], c[2], c[3], 1e-3) then
									ok = false
									break
								end
							end
							if ok then
								hidden = true
								break
							end
						end
					end
					t.truthy(hidden, `skyline part {d.Name} is not inside an opaque part of the venue`)
				end
			end
		end
		t.truthy(k >= 10 and k <= 40, `skyline parts: {k}`)
		t.truthy(farOnly >= 1, "a window band for the far view")
	end)

	t.test("every part anchored, no part over 2048 studs", function()
		for _, d in folder:GetDescendants() do
			if d:IsA("BasePart") then
				t.truthy(d.Anchored, d:GetFullName())
				t.truthy(math.max(d.Size.X, d.Size.Y, d.Size.Z) <= 2048, d:GetFullName())
			end
		end
	end)

	t.test("the floor top at floorY; the skirt down to ground.min; the floor above the ground", function()
		for _, name in { "HallFloor", "DiningFloor" } do
			local f = named(name)
			t.eq(#f, 1, name)
			t.near(f[1].CFrame.Position.Y + f[1].Size.Y / 2, venue.floorY, 0.1)
		end
		for _, name in { "SkirtFront", "SkirtBack", "SkirtWest", "SkirtEast" } do
			local f = named(name)
			t.eq(#f, 1, name)
			t.truthy(f[1].CFrame.Position.Y - f[1].Size.Y / 2 <= venue.ground.min + 1e-6, `{name} reaches the ground`)
		end
		Height.configure(ext)
		local worst = -math.huge
		for X = -50, 50, 2 do
			for D = -25, 25, 2 do
				local x, _, z = AlleyLayout.toWorld(place, X, 0, D)
				worst = math.max(worst, Height.at(x, z))
			end
		end
		Height.configure(nil)
		t.truthy(venue.floorY > worst + 0.3, `floor {venue.floorY} over ground {worst}`)
	end)

	t.test("every entrance at least 4 wide and 7 clear above its floor", function()
		for _, e in venue.entrances do
			local X, D = e.at[1], e.at[2]
			local half = 2
			for y = 0.15, 7, 0.5 do
				for u = -half, half, 0.5 do
					for v = -1, 1, 0.5 do
						local x, wy, z = AlleyLayout.toWorld(place, X + u, y, D + v)
						for _, p in parts do
							if p.CanCollide and inside(p, x, wy, z, 0) then
								error(`entrance {e.id}: {p:GetFullName()} at local ({X + u}, {y}, {D + v})`)
							end
						end
					end
				end
			end
		end
	end)

	t.test("the F3 anchors are in Anchors within 0.5 of their world points; the lift's are left to lane 2", function()
		local folderA = root:FindFirstChild("Anchors")
		local n = 0
		for _, a in venue.anchors do
			local p = folderA:FindFirstChild(a.id)
			if a.owner == "F3" then
				n += 1
				t.truthy(p ~= nil, a.id)
				local w = a.world
				local d = (p.CFrame.Position - roblox.Vector3.new(w[1], w[2], w[3])).Magnitude
				t.truthy(d <= 0.5, `{a.id} off by {d}`)
				t.falsy(p.CanCollide or p.CanQuery)
				t.eq(p.Transparency, 1)
			else
				t.eq(p, nil, `{a.id} belongs to {a.owner}`)
			end
		end
		t.eq(n, 11)
	end)

	t.test("nothing where a cabin or its hanger ever passes (every face sampled at 1 stud)", function()
		local margin = 0.25
		local checked = 0
		local all = table.clone(parts)
		for _, d in sky:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(all, d)
			end
		end
		for _, p in all do
			local s = p.Size
			local nx, ny, nz = math.ceil(s.X) + 1, math.ceil(s.Y) + 1, math.ceil(s.Z) + 1
			local function probe(a: number, b: number, c: number)
				local w = p.CFrame * roblox.Vector3.new(a * s.X / 2, b * s.Y / 2, c * s.Z / 2)
				checked += 1
				if not SkyLift.sweptClear(w.X, w.Y, w.Z, margin) then
					local X, Y, D = AlleyLayout.toLocal(place, w.X, w.Y, w.Z)
					error(string.format("%s in the cabins' way at local (%.1f, %.1f, %.1f)", p:GetFullName(), X, Y, D))
				end
			end
			for i = 0, nx - 1 do
				local a = -1 + 2 * i / math.max(nx - 1, 1)
				for j = 0, ny - 1 do
					local b = -1 + 2 * j / math.max(ny - 1, 1)
					probe(a, b, -1)
					probe(a, b, 1)
				end
				for k = 0, nz - 1 do
					local c = -1 + 2 * k / math.max(nz - 1, 1)
					probe(a, -1, c)
					probe(a, 1, c)
				end
			end
			for j = 0, ny - 1 do
				local b = -1 + 2 * j / math.max(ny - 1, 1)
				for k = 0, nz - 1 do
					local c = -1 + 2 * k / math.max(nz - 1, 1)
					probe(-1, b, c)
					probe(1, b, c)
				end
			end
			probe(0, 0, 0)
		end
		t.truthy(checked > 10000, `{checked} points`)
	end)

	t.test("nothing outside the site; the terrace steps only on the trail's path below the deck", function()
		local site = venue.site
		local S = Lookout.STEPS
		local tol = 0.05
		for _, p in parts do
			local onSteps = inFolder(p, "TerraceSteps")
			for _, c in corners(p) do
				local X, _, D = toLocal(c)
				if onSteps then
					t.truthy(X >= S.x0 - 6 and X <= S.x1 + 6, `{p.Name} X {X}`)
					t.truthy(D <= site.d0 + 1 and D >= site.d0 - S.run - 1, `{p.Name} D {D}`)
				else
					local ok = X >= site.x0 - tol and X <= site.x1 + tol and D >= site.d0 - tol and D <= site.d1 + tol
					t.truthy(ok, string.format("%s at local (%.2f, %.2f) outside the site", p:GetFullName(), X, D))
				end
			end
		end
		t.truthy(S.run > 0 and S.run < 20, `steps run {S.run}`)
	end)

	t.test("seats: four at every table, each looking at it; the window stools look at the town", function()
		local seats: { any } = {}
		for _, d in root:GetDescendants() do
			if d:IsA("Seat") then
				table.insert(seats, d)
			end
		end
		for _, a in venue.anchors do
			if a.kind == "seat" then
				local w = a.world
				local c = roblox.Vector3.new(w[1], w[2], w[3])
				local n = 0
				for _, s in seats do
					local off = s.CFrame.Position - c
					local flat = roblox.Vector3.new(off.X, 0, off.Z)
					if flat.Magnitude < 3.5 then
						n += 1
						-- the sitter faces the table centre
						t.truthy(s.CFrame.LookVector:Dot(-flat.Unit) > 0.99, `{a.id} seat faces away`)
						t.near(s.CFrame.Position.Y + s.Size.Y / 2, venue.floorY + 1.5, 0.05)
					end
				end
				t.eq(n, 4, a.id)
			end
		end
		local fx, fz = AlleyLayout.dirToWorld(place, 0, -1)
		local stools = 0
		for _, s in seats do
			if s.Parent and s.Parent.Name == "Stool" then
				stools += 1
				local lv = s.CFrame.LookVector
				t.truthy(lv.X * fx + lv.Z * fz > 0.99, "a stool faces the town")
			end
		end
		t.truthy(stools >= 12, `{stools} window stools`)
		t.truthy(#seats >= 32 + stools, `{#seats} seats`)
	end)

	t.test("the terrace: east of the cabins, its glass rail under a seated eye, the telescope at its anchor", function()
		local T = Lookout.TERRACE
		local terrace = root:FindFirstChild("Terrace")
		for _, d in terrace:GetDescendants() do
			if d:IsA("BasePart") then
				for _, c in corners(d) do
					local X = toLocal(c)
					t.truthy(X >= T.x0 - 0.3 - 1e-3, `{d.Name} at X {X}`)
				end
			end
		end
		local seatedEye = SkyLift.SEAT_HEIGHT + SkyLift.EYE_ABOVE_SEAT
		local caps, tops = 0, 0
		-- (review) from a seat at a terrace table the town lies 3 to 6.3 degrees below the horizon (the nearest
		-- houses 950 st off, about 105 st down); the town-facing run must stay under that from every seat
		local seats = {}
		for _, a in venue.anchors do
			if string.match(a.id, "^terrace_%d$") then
				table.insert(seats, { a.at[1], a.at[3] + 1.6 }) -- the chair on the building's side of the table
			end
		end
		t.eq(#seats, 4)
		for _, d in terrace:GetDescendants() do
			if
				d:IsA("BasePart")
				and (d.Name == "RailCap" or d.Name == "RailTop" or d.Name == "RailGlass" or d.Name == "RailPost")
			then
				local top = d.CFrame.Position.Y + d.Size.Y / 2 - venue.floorY
				t.truthy(top <= T.railTop + 1e-6 and top < seatedEye - 1, `{d.Name} top {top}`)
				caps += if d.Name == "RailCap" then 1 else 0
				tops += if d.Name == "RailTop" then 1 else 0
				local p = d.CFrame.Position
				local X, _, D = AlleyLayout.toLocal(place, p.X, p.Y, p.Z)
				-- (the side runs' corner posts stand at the ends, off to either side of every seat's view)
				local corner = math.abs(X - (T.x0 + 0.3)) < 0.5 or math.abs(X - (T.x1 - 0.3)) < 0.5
				if D < T.d0 + 1 and not corner then
					t.truthy(top <= T.frontTop + 1e-4, `the town-facing {d.Name} top {top}`)
					for _, seat in seats do
						local dist = math.abs(seat[2] - D)
						local below = math.deg(math.atan2(seatedEye - top, dist))
						t.truthy(below > 6.5, `{d.Name} at X {X} is {below} degrees under a seated eye`)
					end
				end
			end
		end
		t.eq(caps, 2) -- the west and east ends
		t.eq(tops, 2) -- the town-facing run either side of the steps
		for _, d in terrace:GetDescendants() do
			if d.Name == "LanternGlass" then
				local p = d.CFrame.Position
				local _, _, D = AlleyLayout.toLocal(place, p.X, p.Y, p.Z)
				t.truthy(D > T.d0 + 1, "no lantern on the town-facing run")
			end
		end
		local scope = terrace:FindFirstChild("Telescope")
		t.truthy(scope ~= nil)
		local head = scope:FindFirstChild("Head")
		local X, _, D =
			AlleyLayout.toLocal(place, head.CFrame.Position.X, head.CFrame.Position.Y, head.CFrame.Position.Z)
		t.near(X, 15, 0.1)
		t.near(D, -44, 0.1)
	end)

	t.test("the terrace steps: risers at most 0.8, every tread over the ground, the landing on it", function()
		Height.configure(ext)
		local steps = root:FindFirstChild("TerraceSteps")
		local tops = {}
		for _, d in steps:GetChildren() do
			if d:IsA("BasePart") and string.match(d.Name, "^Step%d+$") then
				local k = tonumber(string.sub(d.Name, 5)) :: number
				tops[k] = d.CFrame.Position.Y + d.Size.Y / 2
				for _, c in corners(d) do
					if c[2] > tops[k] - 0.01 then
						t.truthy(c[2] > Height.at(c[1], c[3]), `{d.Name} under the ground`)
					end
				end
			end
		end
		local prev = venue.floorY
		for k = 1, #tops do
			t.truthy(prev - tops[k] <= 0.8 + 1e-6 and prev > tops[k], `step {k}`)
			prev = tops[k]
		end
		local landing = steps:FindFirstChild("Landing")
		local top = landing.CFrame.Position.Y + landing.Size.Y / 2
		t.truthy(prev - top <= 0.8 + 1e-6, "the last riser")
		local g = Height.at(landing.CFrame.Position.X, landing.CFrame.Position.Z)
		t.truthy(top >= g - 0.05 and top <= g + 0.8, `landing {top} over ground {g}`)
		Height.configure(nil)
		t.truthy(#tops >= 6, `{#tops} steps`)
	end)

	t.test("the terrain carve covers the footprint under the floor; lights and the sign are there", function()
		local carve = root:FindFirstChild("TerrainCarve")
		local under = carve:FindFirstChild("UnderFloor")
		t.truthy(under ~= nil)
		t.truthy(under.CFrame.Position.Y + under.Size.Y / 2 <= venue.floorY)
		t.truthy(under.Size.X >= venue.footprint.w - 1e-6 and under.Size.Z >= venue.footprint.d - 1e-6)
		local lights = 0
		local sign = false
		for _, d in root:GetDescendants() do
			if d:IsA("PointLight") or d:IsA("SpotLight") or d:IsA("SurfaceLight") then
				lights += 1
			elseif d:IsA("TextLabel") and d.Text == "THE LOOKOUT" then
				sign = true
			end
		end
		t.truthy(lights >= 30, `{lights} lights`)
		t.truthy(sign, "THE LOOKOUT sign")
	end)
end
