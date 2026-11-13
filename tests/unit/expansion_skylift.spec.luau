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
--   the Skyline: Persistent, at most 40 parts, one mast per tower, and the rope's open spans end to end;
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
		t.truthy(#parts(base) <= 500 * 1.1, `station {#parts(base)} parts`)
		for k = 1, #SkyLift.towers() do
			local tw = folder:FindFirstChild(`f4_lift_tower_{k}`)
			t.truthy(tw ~= nil, `tower {k}`)
			t.eq(tw.ModelStreamingMode, roblox.Enum.ModelStreamingMode.Atomic)
			t.truthy(#parts(tw) <= 40, `tower {k}: {#parts(tw)} parts`)
		end
		local summit = folder:FindFirstChild("f4_lift_summit")
		t.truthy(summit ~= nil)
		t.eq(summit:GetAttribute("VenueId"), "f3_hilltop")
		t.truthy(#parts(summit) <= 120, `summit {#parts(summit)} parts`)
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

	t.test("the Skyline: Persistent, at most 40 parts, a mast per tower, the open spans end to end", function()
		local sky = folder:FindFirstChild("f4_lift_base_Skyline")
		t.truthy(sky ~= nil)
		t.eq(sky.ModelStreamingMode, roblox.Enum.ModelStreamingMode.Persistent)
		t.truthy(#parts(sky) <= 40, `{#parts(sky)} parts`)
		for k = 1, #SkyLift.towers() do
			t.truthy(sky:FindFirstChild(`Mast{k}`) ~= nil, `Mast{k}`)
		end
		-- 2 strands x (mouth -> 9 towers -> lip) = 20 spans
		t.eq(sky:GetAttribute("Spans"), 2 * (#SkyLift.towers() + 1))
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
end
