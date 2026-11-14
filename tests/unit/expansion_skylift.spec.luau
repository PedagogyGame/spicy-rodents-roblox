--!strict
-- tools/bake/skylift built in memory (the same code that writes build/Expansion_F4.rbxm): the sky lift's hardware
-- is where Shared/Rides/SkyLift says the cabins run, and never in their way.
--   the models and their attributes (BATCH2 §2.2), streaming modes, part budgets;
--   anchors within 0.5 of their data points; tower crossarms over SkyLift.towers()' heads, across the line;
--   every part anchored and under 2,048 st; no part (corners, edge middles and centre) inside the cabins' swept
--     volume grown by 0.25 st (the sheaves by Towers.SHEAVE_MARGIN), except the haul rope (the grips clamp it);
--   the cabin template: Persistent, its pivot part at the frame origin, everything inside the outer box or the
--     hanger column, collides with nothing, four Seats whose tops and facings match SkyLift.SEAT_LOCAL, each
--     with its EyeSocket EYE_ABOVE_SEAT over the seat; the two door leaves with their travel;
--   the Skyline: Persistent, within its budget, one mast per tower, and the rope's open spans end to end;
--   the gates the server hangs its prompts on.
local roblox = require("@lune/roblox")
local AlleyLayout = require("@shared/Attractions/AlleyLayout")
local SkyLift = require("@shared/Rides/SkyLift")
local Bake = require("../../tools/bake/skylift/Bake")
local Common = require("../../tools/bake/skylift/Common")
local Towers = require("../../tools/bake/skylift/Towers")

local MARGIN = 0.25

return function(t)
	local folder, report = Bake.build(roblox)
	local Vector3, CFrame = roblox.Vector3, roblox.CFrame

	local function parts(root: any): { any }
		local out = {}
		for _, d in root:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(out, d)
			end
		end
		return out
	end

	t.test("the models are there with their attributes, streaming modes and budgets", function()
		local base = folder:FindFirstChild("f4_lift_base")
		t.truthy(base ~= nil and base:IsA("Model"))
		for _, a in { "VenueId", "Family", "Type", "FloorY", "Yaw", "PartBudget" } do
			t.truthy(base:GetAttribute(a) ~= nil, a)
		end
		t.eq(base:GetAttribute("VenueId"), "f4_lift_base")
		t.eq(base:GetAttribute("Family"), "F4")
		t.eq(base.ModelStreamingMode, roblox.Enum.ModelStreamingMode.Atomic)
		for k = 1, #SkyLift.towers() do
			local tw = folder:FindFirstChild(`f4_lift_tower_{k}`)
			t.truthy(tw ~= nil, `tower {k}`)
			t.eq(tw.ModelStreamingMode, roblox.Enum.ModelStreamingMode.Atomic)
		end
		local summit = folder:FindFirstChild("f4_lift_summit")
		t.truthy(summit ~= nil)
		t.eq(summit:GetAttribute("VenueId"), "f3_hilltop")
		-- every model holds its own stamped budget (the number on the model and the test cannot drift apart)
		local stamped = 0
		for _, m in folder:GetChildren() do
			local budget = m:GetAttribute("PartBudget")
			if m:IsA("Model") and m.Name ~= "f3_hilltop" and m.Name ~= "f3_hilltop_Skyline" then
				t.truthy(type(budget) == "number", `{m.Name} carries a PartBudget`)
			end
			if type(budget) == "number" then
				stamped += 1
				t.truthy(#parts(m) <= budget, `{m.Name}: {#parts(m)} parts over its stamped budget {budget}`)
			end
		end
		t.truthy(stamped >= 15, `{stamped} models stamped`)
		t.truthy(folder:FindFirstChild("f3_hilltop") ~= nil, "the Lookout (or its stub)")
		t.truthy(folder:FindFirstChild("xs_lift_approach") ~= nil, "the approach")
		-- lift hardware total (station, towers, Skyline, cabin template, summit): about 830 planned
		local hw = report.models.f4_lift_base + report.models.f4_lift_base_Skyline + report.models.CabinTemplate
		hw += report.models.f4_lift_summit
		for k = 1, #SkyLift.towers() do
			hw += report.models[`f4_lift_tower_{k}`]
		end
		t.truthy(hw <= 1000, `lift hardware {hw} parts`)
	end)

	t.test("anchors stand at their data points (within 0.5) with the anchor's yaw", function()
		local function check(model: any, venueId: string)
			local v = Common.venue(venueId)
			local folderA = model:FindFirstChild("Anchors")
			t.truthy(folderA ~= nil, model.Name .. " Anchors")
			local n = 0
			for _, a in v.anchors do
				if a.owner == "F4" then
					n += 1
					local p = folderA:FindFirstChild(a.id)
					t.truthy(p ~= nil, a.id)
					local x, y, z = AlleyLayout.toWorld(Common.place(v), a.at[1], a.at[2], a.at[3])
					t.truthy((p.CFrame.Position - Vector3.new(x, y, z)).Magnitude < 0.5, a.id)
					t.eq(p.Transparency, 1)
					t.eq(p.CanCollide, false)
					t.eq(p.CanQuery, false)
					local look = p.CFrame.LookVector
					local yaw = v.yaw + math.rad(a.yaw or 0)
					t.near(look.X, -math.sin(yaw), 1e-3, a.id .. " yaw")
					t.near(look.Z, -math.cos(yaw), 1e-3, a.id .. " yaw")
				end
			end
			t.truthy(n >= 3, `{venueId}: {n} F4 anchors`)
		end
		check(folder:FindFirstChild("f4_lift_base"), "f4_lift_base")
		check(folder:FindFirstChild("f4_lift_summit"), "f3_hilltop")
	end)

	t.test("each tower's crossarm sits over its head, across the line, clear over the grips", function()
		for _, tw in SkyLift.towers() do
			local m = folder:FindFirstChild(`f4_lift_tower_{tw.index}`)
			local arm = m:FindFirstChild("Crossarm")
			t.truthy(arm ~= nil)
			local p = arm.CFrame.Position
			t.truthy(math.sqrt((p.X - tw.x) ^ 2 + (p.Z - tw.z) ^ 2) < 0.5, `tower {tw.index} arm over the head`)
			t.truthy(p.Y - arm.Size.Y / 2 > tw.y + SkyLift.GRIP_ABOVE + 1, `tower {tw.index} arm over the grips`)
			-- the arm's long axis is the line's right vector
			local right = arm.CFrame.RightVector
			t.near(math.abs(right.X * math.cos(tw.yaw) - right.Z * math.sin(tw.yaw)), 1, 1e-3)
			t.near(m:GetAttribute("CableY"), tw.y, 1e-6)
			-- the footing reaches below the ground under it
			local foot = m:FindFirstChild("Footing")
			local g = Common.ground(tw.x, tw.z)
			t.truthy(foot.CFrame.Position.Y - foot.Size.Y / 2 < g - 1, `tower {tw.index} footing in the ground`)
			t.truthy(foot.CFrame.Position.Y + foot.Size.Y / 2 > g, `tower {tw.index} footing out of it`)
		end
	end)

	t.test("every part anchored and shorter than 2,048", function()
		for _, p in parts(folder) do
			t.truthy(p.Anchored, p:GetFullName())
			t.truthy(math.max(p.Size.X, p.Size.Y, p.Size.Z) < 2048, p:GetFullName())
		end
	end)

	t.test("nothing but the rope inside the cabins' swept volume (grown by 0.25)", function()
		local function clear(p: any): boolean
			local cf, s = p.CFrame, p.Size
			-- the sheaves sit as close over the rope as the grips allow (Towers.SHEAVE_MARGIN)
			local margin = if p.Name == "Sheave" then Towers.SHEAVE_MARGIN else MARGIN
			for i = -1, 1 do
				for j = -1, 1 do
					for k = -1, 1 do
						local q = (cf * CFrame.new(i * s.X / 2, j * s.Y / 2, k * s.Z / 2)).Position
						if not SkyLift.sweptClear(q.X, q.Y, q.Z, margin) then
							return false
						end
					end
				end
			end
			return true
		end
		local bad = {}
		for _, model in folder:GetChildren() do
			if model.Name ~= "CabinTemplate" then
				for _, p in parts(model) do
					local rope = string.match(p.Name, "^Rope%d") or string.match(p.Name, "^Span%d")
					if not rope and not clear(p) then
						table.insert(bad, p:GetFullName())
					end
				end
			end
		end
		t.eq(#bad, 0, table.concat(bad, ", "))
	end)

	t.test("the cabin template: frame, box, seats, eyes, doors; collides with nothing", function()
		local tpl = folder:FindFirstChild("CabinTemplate")
		t.truthy(tpl ~= nil)
		t.eq(tpl.ModelStreamingMode, roblox.Enum.ModelStreamingMode.Persistent)
		t.eq(tpl:GetAttribute("Template"), true)
		t.truthy(#parts(tpl) <= 60, `{#parts(tpl)} parts`)
		local origin = tpl.PrimaryPart
		t.truthy(origin ~= nil and origin.Name == "Origin")
		local o = origin.CFrame
		local inv = o:Inverse()
		local HW, HL = SkyLift.CABIN_WIDTH / 2, SkyLift.CABIN_LENGTH / 2
		local top = SkyLift.CABIN_HEIGHT - SkyLift.CABIN_BELOW
		for _, p in parts(tpl) do
			t.eq(p.CanCollide, false, p.Name)
			t.eq(p.CanQuery, false, p.Name)
			t.eq(p.CanTouch, false, p.Name)
			local cf, s = inv * p.CFrame, p.Size
			for i = -1, 1, 2 do
				for j = -1, 1, 2 do
					for k = -1, 1, 2 do
						local q = (cf * CFrame.new(i * s.X / 2, j * s.Y / 2, k * s.Z / 2)).Position
						local inBox = math.abs(q.X) <= HW + 1e-3
							and math.abs(q.Z) <= HL + 1e-3
							and q.Y >= -SkyLift.CABIN_BELOW - 1e-3
							and q.Y <= top + 1e-3
						local inColumn = math.abs(q.X) <= SkyLift.HANGER_HALF + 1e-3
							and math.abs(q.Z) <= SkyLift.HANGER_HALF + 1e-3
							and q.Y >= top - 0.1
							and q.Y <= SkyLift.HANG + SkyLift.GRIP_ABOVE + 1e-3
						t.truthy(inBox or inColumn, `{p.Name} corner ({q.X}, {q.Y}, {q.Z})`)
					end
				end
			end
		end
		for k = 1, SkyLift.SEATS do
			local seat = tpl:FindFirstChild("Seats"):FindFirstChild(`Seat{k}`)
			t.truthy(seat ~= nil and seat:IsA("Seat"), `Seat{k}`)
			t.eq(seat.Disabled, true)
			local L = SkyLift.SEAT_LOCAL[k]
			local cf = inv * seat.CFrame
			local topY = cf.Position.Y + seat.Size.Y / 2
			t.near(cf.Position.X, L[1], 1e-3)
			t.near(topY, L[2], 1e-3)
			t.near(cf.Position.Z, L[3], 1e-3)
			local look = cf.LookVector
			t.near(look.X, -math.sin(L[4]), 1e-3)
			t.near(look.Z, -math.cos(L[4]), 1e-3)
			local eye = seat:FindFirstChild("EyeSocket")
			t.truthy(eye ~= nil and eye:IsA("Attachment"))
			local e = inv * (seat.CFrame * eye.CFrame)
			t.near(e.Position.Y, L[2] + SkyLift.EYE_ABOVE_SEAT, 1e-3)
			t.near(e.Position.X, L[1], 1e-3)
			t.near(e.Position.Z, L[3], 1e-3)
		end
		local doors = tpl:FindFirstChild("Doors")
		t.truthy(doors:FindFirstChild("DoorFore") ~= nil and doors:FindFirstChild("DoorAft") ~= nil)
		t.eq(doors:FindFirstChild("DoorFore"):GetAttribute("SlideZ"), -1.5)
		t.eq(doors:FindFirstChild("DoorAft"):GetAttribute("SlideZ"), 1.5)
		local light = tpl:FindFirstChild("Light")
		t.truthy(light ~= nil and light:FindFirstChildOfClass("PointLight") ~= nil)
		t.truthy(tpl:FindFirstChild("NumberFront") ~= nil and tpl:FindFirstChild("NumberBack") ~= nil)
	end)

	t.test("the Skyline: Persistent, within its budget, a mast per tower, the open spans end to end", function()
		local sky = folder:FindFirstChild("f4_lift_base_Skyline")
		t.truthy(sky ~= nil)
		t.eq(sky.ModelStreamingMode, roblox.Enum.ModelStreamingMode.Persistent)
		t.truthy(#parts(sky) <= Towers.SKYLINE_BUDGET, `{#parts(sky)} parts`)
		for k = 1, #SkyLift.towers() do
			t.truthy(sky:FindFirstChild(`Mast{k}`) ~= nil, `Mast{k}`)
		end
		-- 2 strands x (mouth -> 9 towers -> lip) = 20 spans at least, plus the chords across the vertical blends
		t.eq(sky:GetAttribute("Spans"), #Common.ropeSegments().spans)
		t.truthy(sky:GetAttribute("Spans") >= 2 * (#SkyLift.towers() + 1))
		for _, p in parts(sky) do
			t.eq(p.CanCollide, false)
		end
		-- the rope in the three models adds up to the whole loop
		local total = 0
		for _, name in { "f4_lift_base", "f4_lift_base_Skyline", "f4_lift_summit" } do
			for _, p in parts(folder:FindFirstChild(name)) do
				if string.match(p.Name, "^Rope%d") or string.match(p.Name, "^Span%d") then
					total += p.Size.X
				end
			end
		end
		t.near(total, SkyLift.loop().length, 0.5)
	end)

	t.test("the gates carry what the server needs", function()
		for _, g in { { "f4_lift_base", "base" }, { "f4_lift_summit", "summit" } } do
			local m = folder:FindFirstChild(g[1])
			local gate, arm, board = nil, nil, nil
			for _, d in m:GetDescendants() do
				if d.Name == "BoardGate" then
					gate = d
				elseif d.Name == "BoardGateArm" then
					arm = d
				elseif d.Name == "NextCabinBoard" then
					board = d
				end
			end
			t.truthy(gate ~= nil and gate:GetAttribute("Gate") == "board", g[1])
			t.eq(gate:GetAttribute("Station"), g[2])
			t.truthy(arm ~= nil and arm.CanCollide == false and arm:GetAttribute("HingeX") ~= nil)
			local label = nil
			for _, d in board:GetDescendants() do
				if d.Name == "Next" and d:IsA("TextLabel") then
					label = d
				end
			end
			t.truthy(label ~= nil, g[1] .. " Next label")
			-- the gate stands on the boarding platform
			local st = (SkyLift.stations() :: any)[g[2]]
			t.near(gate.CFrame.Position.Y - gate.Size.Y / 2, st.platformY, 1e-3)
		end
	end)
	-- every collidable part of the bake, with what a point test needs
	local solids: { { inv: any, cf: any, hx: number, hy: number, hz: number, name: string } } = {}
	for _, model in folder:GetChildren() do
		if model.Name ~= "CabinTemplate" then
			for _, p in parts(model) do
				if p.CanCollide then
					table.insert(solids, {
						inv = p.CFrame:Inverse(),
						cf = p.CFrame,
						hx = p.Size.X / 2,
						hy = p.Size.Y / 2,
						hz = p.Size.Z / 2,
						name = p.Name,
					})
				end
			end
		end
	end
	local function solidAt(q: any, skip: ((string) -> boolean)?): string?
		for _, sd in solids do
			local l = sd.inv * q
			if math.abs(l.X) <= sd.hx and math.abs(l.Y) <= sd.hy and math.abs(l.Z) <= sd.hz then
				if skip == nil or not skip(sd.name) then
					return sd.name
				end
			end
		end
		return nil
	end

	t.test(
		"a full cabin gets out on four spots apart, each on the platform and clear of every wall (review)",
		function()
			-- the review found every rider of a cabin put on one spot, the base's half inside the back wall
			for _, station in SkyLift.STATIONS do
				local spots = {}
				local st = (SkyLift.stations() :: any)[station]
				for k = 1, SkyLift.SEATS do
					local x, y, z, yaw = SkyLift.alightSpot(station, k)
					t.near(y, st.platformY, 1e-9)
					-- facing away from the cabin: the alight point (beside the door) is behind
					local fx, fz = -math.sin(yaw), -math.cos(yaw)
					t.truthy((st.alight.x - x) * fx + (st.alight.z - z) * fz < 0, `{station} seat {k} faces the cabin`)
					local cf = CFrame.new(x, y, z) * CFrame.Angles(0, yaw, 0)
					-- a body 2 wide, 1 deep and 5 tall stands there touching nothing; the platform is under its feet
					for _, i in { -1, -0.5, 0, 0.5, 1 } do
						for _, j in { -0.5, 0, 0.5 } do
							for _, h in { 0.3, 1.5, 3, 4.5 } do
								local q = (cf * CFrame.new(i, h, j)).Position
								local hit = solidAt(q)
								t.truthy(hit == nil, `{station} seat {k}: the body is inside {hit} at {i}, {h}, {j}`)
							end
						end
					end
					t.truthy(solidAt(Vector3.new(x, y - 0.1, z)) ~= nil, `{station} seat {k}: nothing underfoot`)
					t.truthy(SkyLift.sweptClear(x, y + 2.5, z, 0.5), `{station} seat {k}: in the cabins' way`)
					table.insert(spots, { x, z })
				end
				for a = 1, #spots do
					for b = a + 1, #spots do
						local d = math.sqrt((spots[a][1] - spots[b][1]) ^ 2 + (spots[a][2] - spots[b][2]) ^ 2)
						t.truthy(d >= 1.2, `{station}: seats {a} and {b} get out {d} apart`)
					end
				end
			end
		end
	)

	t.test("the pit is walled: from the platforms nobody reaches the cabins' path but through the opening", function()
		-- the review walked into an open cabin and dropped through its floor into the pit. A walker 1.5 wide
		-- (a grid of 0.25 st, every cell within 0.75 of a solid closed) is flooded from the platform at three
		-- heights; with the screen's leaves shut it never reaches a cell the cabins pass through, and with them
		-- open it reaches only the cells at the board point's opening
		local cases = {
			{ station = "base", venue = "f4_lift_base", from = { 0, -13 } },
			{ station = "summit", venue = "f3_hilltop", from = { -23.5, 0 } },
		}
		for _, case in cases do
			local station = case.station
			local st = (SkyLift.stations() :: any)[station]
			local v = Common.venue(case.venue)
			local place = Common.place(v)
			local hw, hd = v.footprint.w / 2, v.footprint.d / 2
			local C = 0.25
			local nx, nd = math.floor(2 * hw / C), math.floor(2 * hd / C)
			local function flood(open: boolean): (number, number, number)
				local skip = if open
					then function(name: string): boolean
						return string.match(name, "^ScreenDoor") ~= nil
					end
					else nil
				-- each solid marks the cells it covers at any of the three heights (rasterised over its own box)
				local blocked: { [number]: boolean } = {}
				local heights = { 1, 3.5, 6.5 }
				for _, sd in solids do
					if skip and skip(sd.name) then
						continue
					end
					local x0, x1, y0, y1, d0, d1 = math.huge, -math.huge, math.huge, -math.huge, math.huge, -math.huge
					for _, c in
						{
							{ -1, -1, -1 },
							{ -1, -1, 1 },
							{ -1, 1, -1 },
							{ -1, 1, 1 },
							{ 1, -1, -1 },
							{ 1, -1, 1 },
							{ 1, 1, -1 },
							{ 1, 1, 1 },
						}
					do
						local w = (sd.cf * CFrame.new(c[1] * sd.hx, c[2] * sd.hy, c[3] * sd.hz)).Position
						local lx, ly, ld = AlleyLayout.toLocal(place, w.X, w.Y, w.Z)
						x0, x1, y0, y1 = math.min(x0, lx), math.max(x1, lx), math.min(y0, ly), math.max(y1, ly)
						d0, d1 = math.min(d0, ld), math.max(d1, ld)
					end
					local base = st.platformY - v.floorY
					if y1 < base + 1 or y0 > base + 6.5 or x1 < -hw or x0 > hw or d1 < -hd or d0 > hd then
						continue
					end
					for i = math.max(0, math.floor((x0 + hw) / C)), math.min(nx - 1, math.floor((x1 + hw) / C)) do
						for j = math.max(0, math.floor((d0 + hd) / C)), math.min(nd - 1, math.floor((d1 + hd) / C)) do
							local key = i * 4096 + j
							if not blocked[key] then
								local lx, ld = -hw + (i + 0.5) * C, -hd + (j + 0.5) * C
								for _, h in heights do
									local wx, wy, wz = AlleyLayout.toWorld(place, lx, base + h, ld)
									-- (grown by most of a cell across, so a thin pane between two cell centres still counts)
									local l = sd.inv * Vector3.new(wx, wy, wz)
									local g = 0.75 * C
									if
										math.abs(l.X) <= sd.hx + g
										and math.abs(l.Y) <= sd.hy
										and math.abs(l.Z) <= sd.hz + g
									then
										blocked[key] = true
										break
									end
								end
							end
						end
					end
				end
				-- grow the solids by a walker's half-width
				local R = 3
				local closed: { [number]: boolean } = {}
				for key in blocked do
					local i, j = key // 4096, key % 4096
					for di = -R, R do
						for dj = -R, R do
							if di * di + dj * dj <= R * R then
								closed[(i + di) * 4096 + (j + dj)] = true
							end
						end
					end
				end
				local si = math.floor((case.from[1] + hw) / C)
				local sj = math.floor((case.from[2] + hd) / C)
				t.falsy(closed[si * 4096 + sj], `{station}: the flood starts inside a wall`)
				local seen: { [number]: boolean } = { [si * 4096 + sj] = true }
				local queue = { si * 4096 + sj }
				local head = 1
				local inPath, farthest, reached = 0, 0, 0
				while head <= #queue do
					local key = queue[head]
					head += 1
					reached += 1
					local i, j = key // 4096, key % 4096
					local lx, ld = -hw + (i + 0.5) * C, -hd + (j + 0.5) * C
					local wx, wy, wz = AlleyLayout.toWorld(place, lx, st.platformY - v.floorY + 1.5, ld)
					if not SkyLift.sweptClear(wx, wy, wz) then
						inPath += 1
						farthest = math.max(farthest, math.sqrt((wx - st.board.x) ^ 2 + (wz - st.board.z) ^ 2))
					end
					for _, n in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
						local ni, nj = i + n[1], j + n[2]
						local nk = ni * 4096 + nj
						if ni >= 0 and nj >= 0 and ni < nx and nj < nd and not seen[nk] and not closed[nk] then
							seen[nk] = true
							table.insert(queue, nk)
						end
					end
				end
				return inPath, farthest, reached
			end
			local shut, _, reachedShut = flood(false)
			t.truthy(reachedShut > 2000, `{station}: the flood reached only {reachedShut} cells`)
			t.eq(shut, 0, `{station}: with the screen shut a walker still reaches {shut} cells of the cabins' path`)
			-- the leaves are all that shut it: open, a walker steps through the opening into the cabins' path, and
			-- the first path cell reached is at the board point
			local open, nearest = flood(true)
			t.truthy(open > 0, `{station}: with the leaves open the cabins' path cannot be reached`)
			t.truthy(nearest ~= nil, `{station}: no path cell`)
		end
	end)
end
