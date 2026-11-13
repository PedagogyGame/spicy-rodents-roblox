--!strict
-- tools/bake/skylift/Approach built in memory (the xs_lift_approach model in build/Expansion_F4.rbxm): the way to
-- the sky lift and the hill trail sit on the ground and out of everyone's way.
--   every trail piece's top meets the ground within 0.3 at both ends (on its centre line, or its uphill edge where
--     it crosses the hill's face on a stone bank) and is nowhere under the ground (centre and both edges, every
--     half stud), and no piece is longer than PIECE_MAX;
--   Lift Road meets the westside street's end (rd_071) within 0.5, in plan and in height, and its sidewalks stop
--     where the westside sidewalks stop;
--   nothing stands inside either venue's footprint or the cabins' swept volume (grown by 0.25);
--   handrails along every piece steeper than RAIL_GRADE, timber steps on those steeper than STEP_GRADE;
--   five lamps with lit heads, three benches, two signposts, about twenty conifers; the bay lines lie on the
--     car park's surface; within the part budget, all anchored.
local roblox = require("@lune/roblox")
local AlleyLayout = require("@shared/Attractions/AlleyLayout")
local SkyLift = require("@shared/Rides/SkyLift")
local Approach = require("../../tools/bake/skylift/Approach")
local Bake = require("../../tools/bake/skylift/Bake")
local Common = require("../../tools/bake/skylift/Common")
local Plan = require("@worldgen/Plan")
local Roads = require("../../generated/Roads")

return function(t)
	local folder = Bake.build(roblox)
	local m = folder:FindFirstChild("xs_lift_approach")
	local CFrame, Vector3 = roblox.CFrame, roblox.Vector3

	local function parts(root: any): { any }
		local out = {}
		for _, d in root:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(out, d)
			end
		end
		return out
	end

	t.test("the approach model is there, anchored, within its budget", function()
		t.truthy(m ~= nil and m:IsA("Model"))
		local ps = parts(m)
		t.truthy(#ps <= Approach.BUDGET, `{#ps} parts`)
		for _, p in ps do
			t.truthy(p.Anchored, p:GetFullName())
			t.truthy(math.max(p.Size.X, p.Size.Y, p.Size.Z) < 2048)
		end
	end)

	t.test("trail pieces lie on the ground: ends within 0.3, never under it, none longer than PIECE_MAX", function()
		local trail = m:FindFirstChild("Trail")
		local n = 0
		local worstEnd, worstUnder = 0, -math.huge
		for _, p in trail:GetChildren() do
			if string.match(p.Name, "^Piece%d") then
				n += 1
				local cf, s = p.CFrame, p.Size
				local L = s.Z - 0.3 -- the pieces overlap their neighbours by 0.15 at each end
				-- at each end the top meets the ground (within 0.3) somewhere across it: on the centre line on a
				-- gentle slope, on the uphill edge where the trail crosses the hill's face on its bank
				for _, e in { -L / 2, L / 2 } do
					local meet = math.huge
					for _, f in { -1, -0.5, 0, 0.5, 1 } do
						local q = (cf * CFrame.new(f * s.X / 2, s.Y / 2, e)).Position
						meet = math.min(meet, q.Y - Common.ground(q.X, q.Z))
					end
					worstEnd = math.max(worstEnd, math.abs(meet))
				end
				local steps = math.ceil(L / 0.5)
				for i = 0, steps do
					local zl = -L / 2 + L * i / steps
					for _, xl in { -s.X / 2 + 0.3, 0, s.X / 2 - 0.3 } do
						local q = (cf * CFrame.new(xl, s.Y / 2, zl)).Position
						worstUnder = math.max(worstUnder, Common.ground(q.X, q.Z) - q.Y)
					end
				end
				local a = (cf * CFrame.new(0, 0, -L / 2)).Position
				local b = (cf * CFrame.new(0, 0, L / 2)).Position
				t.truthy(math.sqrt((a.X - b.X) ^ 2 + (a.Z - b.Z) ^ 2) <= Approach.PIECE_MAX + 1e-6, p.Name)
			end
		end
		t.eq(n, #Approach.trailPieces())
		t.truthy(worstEnd <= 0.3, `ends {worstEnd} from the ground`)
		t.truthy(worstUnder <= 0.02, `ground {worstUnder} over a piece's top`)
		-- the trail runs from the car park to the Lookout's terrace steps
		local path = nil
		for _, r in Common.expansion().paths do
			if r.id == "xpath_hill_trail" then
				path = r
			end
		end
		local pieces = Approach.trailPieces()
		local first, last = pieces[1], pieces[#pieces]
		t.near(first.ax, path.points[1][1], 1e-6)
		t.near(first.az, path.points[1][2], 1e-6)
		t.near(last.bx, path.points[#path.points][1], 1e-6)
		t.near(last.bz, path.points[#path.points][2], 1e-6)
	end)

	t.test("Lift Road meets the westside street's end, in plan and in height", function()
		local roads = m:FindFirstChild("LiftRoad")
		local lift = roads:FindFirstChild("xs_lift_road")
		t.truthy(lift ~= nil)
		local rd071 = nil
		for _, r in Roads do
			if r.id == "rd_071_westside_street" then
				rd071 = r
			end
		end
		local plan = Plan.road(rd071 :: any)
		-- the end segments: Lift Road's northernmost, rd_071's southernmost
		local function endTop(model: any, zEnd: number): (number, number)
			local best, bestY, bestZ = math.huge, 0, 0
			for _, p in model:GetChildren() do
				if p:IsA("BasePart") and string.sub(p.Name, 1, 3) == "Seg" then
					for _, e in { -p.Size.Z / 2, p.Size.Z / 2 } do
						local q = (p.CFrame * CFrame.new(0, p.Size.Y / 2, e)).Position
						if math.abs(q.Z - zEnd) < best then
							best, bestY, bestZ = math.abs(q.Z - zEnd), q.Y, q.Z
						end
					end
				end
			end
			return bestY, bestZ
		end
		local y1, z1 = endTop(lift, -610)
		t.truthy(math.abs(z1 - -610) < 0.5, `Lift Road ends at z {z1}`)
		local best, y0 = math.huge, 0
		for _, spec in plan.parts do
			if string.sub(spec.name, 1, 3) == "Seg" then
				local cf = CFrame.new(spec.cx, spec.cy, spec.cz)
					* CFrame.Angles(0, spec.yaw, 0)
					* CFrame.Angles(spec.pitch, 0, 0)
				for _, e in { -spec.sz / 2, spec.sz / 2 } do
					local q = (cf * CFrame.new(0, spec.sy / 2, e)).Position
					if math.abs(q.Z - -610) < best then
						best, y0 = math.abs(q.Z - -610), q.Y
					end
				end
			end
		end
		t.truthy(best < 0.5, "rd_071 starts at z -610")
		t.truthy(math.abs(y1 - y0) < 0.5, `tops {y1} and {y0} at the joint`)
		-- the sidewalks stop where the westside sidewalks stop
		for _, id in { "xs_lift_road_sidewalk_a", "xs_lift_road_sidewalk_b" } do
			local sw = roads:FindFirstChild(id)
			t.truthy(sw ~= nil, id)
			local maxZ = -math.huge
			for _, p in parts(sw) do
				maxZ = math.max(maxZ, p.CFrame.Position.Z + p.Size.Z / 2)
			end
			t.truthy(maxZ <= Approach.SIDEWALK_JOIN + 0.5, `{id} reaches z {maxZ}`)
		end
	end)

	t.test("nothing in either venue's footprint or the cabins' swept volume", function()
		local bad = {}
		local venues = { Common.venue("f4_lift_base"), Common.venue("f3_hilltop") }
		for _, p in parts(m) do
			local cf, s = p.CFrame, p.Size
			local hit = false
			for i = -1, 1 do
				for j = -1, 1 do
					for k = -1, 1 do
						local q = (cf * CFrame.new(i * s.X / 2, j * s.Y / 2, k * s.Z / 2)).Position
						if not SkyLift.sweptClear(q.X, q.Y, q.Z, 0.25) then
							hit = true
						end
						if i == 0 and k == 0 then
							for _, v in venues do
								local X, _, D = AlleyLayout.toLocal(Common.place(v), q.X, q.Y, q.Z)
								if math.abs(X) < v.footprint.w / 2 and math.abs(D) < v.footprint.d / 2 then
									hit = true
								end
							end
						end
					end
				end
			end
			if hit then
				table.insert(bad, p:GetFullName())
			end
		end
		t.eq(#bad, 0, table.concat(bad, ", "))
	end)

	t.test("handrails on the steep stretch, steps on the steepest", function()
		local trail = m:FindFirstChild("Trail")
		local rails, logs = 0, 0
		for _, p in trail:GetChildren() do
			if p.Name == "Handrail" then
				rails += 1
			elseif p.Name == "StepLog" then
				logs += 1
			end
		end
		local steep, steeper, high = 0, 0, 0
		for _, p in Approach.trailPieces() do
			if p.grade > Approach.RAIL_GRADE then
				steep += 1
			elseif p.drop > Approach.DROP_RAIL then
				high += 1
			end
			if p.grade > Approach.STEP_GRADE then
				steeper += 1
			end
		end
		t.truthy(steep >= 1, "the trail has a steep stretch")
		t.eq(rails, 2 * steep + high, "a handrail each side of every steep piece, and on the drop where it is high")
		t.truthy(steeper >= 1 and logs >= steeper * 3, `{logs} step logs on {steeper} pieces`)
	end)

	t.test("lamps, benches, signposts, conifers; bay lines on the car park's surface", function()
		local lamps = m:FindFirstChild("Lamps"):GetChildren()
		t.eq(#lamps, 5)
		for _, l in lamps do
			local head = l:FindFirstChild("Head")
			t.truthy(head ~= nil and head:GetAttribute("NightLight") == true, l.Name)
			t.truthy(head:FindFirstChildOfClass("PointLight") ~= nil, l.Name)
		end
		local trail = m:FindFirstChild("Trail")
		local benches, signs = 0, 0
		for _, c in trail:GetChildren() do
			if string.match(c.Name, "^Bench") then
				benches += 1
			elseif string.match(c.Name, "^Sign") then
				signs += 1
			end
		end
		t.eq(benches, 3)
		t.eq(signs, 2)
		t.truthy((m:GetAttribute("Trees") :: number) >= 18, "about twenty conifers")
		local park = m:FindFirstChild("CarPark")
		local pad = park:FindFirstChild("xp_lift_lot")
		t.truthy(pad ~= nil)
		local lines = 0
		for _, p in park:GetChildren() do
			if p.Name == "BayLine" then
				lines += 1
				local q = p.CFrame.Position
				-- the segment under the line's middle
				local top = nil
				for _, s in pad:GetChildren() do
					if s:IsA("BasePart") and string.sub(s.Name, 1, 3) == "Seg" then
						local l = s.CFrame:Inverse() * Vector3.new(q.X, s.CFrame.Position.Y, q.Z)
						if math.abs(l.X) <= s.Size.X / 2 and math.abs(l.Z) <= s.Size.Z / 2 then
							top = (s.CFrame * CFrame.new(l.X, s.Size.Y / 2, l.Z)).Position.Y
						end
					end
				end
				t.truthy(top ~= nil and math.abs(q.Y - top) < 0.15, `bay line at {q.Y}, surface {top}`)
			end
		end
		t.eq(lines, 14)
	end)
end
