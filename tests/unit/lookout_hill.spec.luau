--!strict
-- Lookout Hill's layout (Shared/Rides/LookoutHill) is where the sky lift's bake drew it (tools/bake/skylift/Approach,
-- built in memory), so the town's walkers meet what the players see:
--   every baked rock standing a walker's step over the ground, every bench and every handrail lies inside one of
--     the walkers' boxes (LookoutHill.obstacles, World/WalkWay's colliders);
--   the trail's top (trailTopAt, the walkers' ground on it: AI/TownAI) is the baked gravel's top, on every piece
--     (centre and both edges) and every landing; off the trail it is nil;
--   the layout is the game's whatever the process has configured: World/Height is put back as it was found.
local roblox = require("@lune/roblox")
local Height = require("@shared/World/Height")
local LookoutHill = require("@shared/Rides/LookoutHill")
local WalkWay = require("@shared/World/WalkWay")
local Bake = require("../../tools/bake/skylift/Bake")

return function(t)
	local folder = Bake.build(roblox)
	local m = folder:FindFirstChild("xs_lift_approach")
	local Vector3 = roblox.Vector3

	-- a part's plan box in world x and z (Roblox X and Z) and its top
	local function planBox(p: any): (number, number, number, number, number)
		local x0, x1, z0, z1, top = math.huge, -math.huge, math.huge, -math.huge, -math.huge
		local s = p.Size
		for _, a in { -0.5, 0.5 } do
			for _, b in { -0.5, 0.5 } do
				for _, c in { -0.5, 0.5 } do
					local w = p.CFrame * Vector3.new(s.X * a, s.Y * b, s.Z * c)
					x0, x1 = math.min(x0, w.X), math.max(x1, w.X)
					z0, z1 = math.min(z0, w.Z), math.max(z1, w.Z)
					top = math.max(top, w.Y)
				end
			end
		end
		return x0, x1, z0, z1, top
	end

	-- is the plan box inside one of the obstacles named `id` (within `tol`)?
	local function boxed(id: string, x0: number, x1: number, z0: number, z1: number, tol: number): boolean
		for _, b in LookoutHill.obstacles() do
			if b.id == id and x0 >= b.x0 - tol and x1 <= b.x1 + tol and z0 >= b.z0 - tol and z1 <= b.z1 + tol then
				return true
			end
		end
		return false
	end

	-- (a rail's box holds its line in pieces: a post or a rod is inside the union of the pieces it crosses; checked
	-- at points every half stud along its length)
	local function railed(x0: number, x1: number, z0: number, z1: number): boolean
		local n = math.max(1, math.ceil(math.max(x1 - x0, z1 - z0) / 0.5))
		for i = 0, n do
			local x, z = x0 + (x1 - x0) * i / n, z0 + (z1 - z0) * i / n
			local inside = false
			for _, b in LookoutHill.obstacles() do
				if b.id == "lookout_rail" and x >= b.x0 and x <= b.x1 and z >= b.z0 and z <= b.z1 then
					inside = true
					break
				end
			end
			if not inside then
				return false
			end
		end
		return true
	end

	t.test("the walkers' boxes hold every baked rock, bench and handrail", function()
		t.eq(LookoutHill.LOW, WalkWay.LOW, "the step a walker takes")
		local was = Height.configured()
		Height.configure(LookoutHill.terrain())
		local rocks, benches, rails, low = 0, 0, 0, 0
		local bad = {}
		for _, p in m:GetDescendants() do
			if not p:IsA("BasePart") then
				continue
			end
			local x0, x1, z0, z1, top = planBox(p)
			local parent = p.Parent and p.Parent.Name or ""
			if p.Name == "Rock" then
				local g = math.min(Height.at(x0, z0), Height.at(x1, z0), Height.at(x0, z1), Height.at(x1, z1))
				if top - g < LookoutHill.LOW then
					low += 1
				elseif boxed("lookout_rock", x0, x1, z0, z1, 0.05) then
					rocks += 1
				else
					table.insert(bad, `{p:GetFullName()} at ({x0}, {z0})`)
				end
			elseif string.sub(parent, 1, 5) == "Bench" then
				if boxed("lookout_bench", x0, x1, z0, z1, 0.05) then
					benches += 1
				else
					table.insert(bad, `{p:GetFullName()} at ({x0}, {z0})`)
				end
			elseif p.Name == "Handrail" or p.Name == "Midrail" or p.Name == "RailPost" then
				-- (the rods' line, and a post's square)
				if railed(x0, x1, z0, z1) or railed(x0, x1, z1, z0) then
					rails += 1
				else
					table.insert(bad, `{p:GetFullName()} at ({x0}, {z0})`)
				end
			end
		end
		Height.configure(was)
		print(`      {rocks} rocks boxed ({low} under a step), {benches} bench parts, {rails} rail parts`)
		t.truthy(rocks >= 10 and benches == 3 * 4 and rails > 20, `{rocks} rocks, {benches} bench parts, {rails} rails`)
		t.eq(#bad, 0, table.concat(bad, "\n"))
	end)

	t.test("the trail's top is the baked gravel's, on every piece and landing; nil off the trail", function()
		local trail = m:FindFirstChild("Trail")
		local worst, n = 0, 0
		local hw = LookoutHill.TRAIL_WIDTH / 2
		for _, p in trail:GetChildren() do
			if string.match(p.Name, "^Piece%d") then
				local cf, s = p.CFrame, p.Size
				local L = s.Z - 0.3
				for _, f in { -0.45, -0.2, 0, 0.2, 0.45 } do
					for _, o in { -(hw - 0.05), 0, hw - 0.05 } do
						local w = cf * Vector3.new(o, s.Y / 2, f * L)
						local y = LookoutHill.trailTopAt(w.X, w.Z)
						t.truthy(y ~= nil, `{p.Name} at ({w.X}, {w.Z}) off the trail`)
						-- (where two pieces or a landing meet, the higher top: never under this one)
						worst = math.max(worst, w.Y - (y :: number))
						n += 1
					end
				end
			elseif p.Name == "Landing" then
				local _, _, _, _, top = planBox(p)
				local c = p.CFrame.Position
				local y = LookoutHill.trailTopAt(c.X, c.Z)
				-- (at its centre the pieces meeting there end, a hair over it)
				local ok = y ~= nil and (y :: number) >= top - 0.01 and (y :: number) <= top + 0.05
				t.truthy(ok, `landing at {c}: {y} vs {top}`)
			end
		end
		print(`      {n} points on the pieces, the gravel at most {worst} over the walkers' ground`)
		-- (the baked piece is pitched along its grade and rolled about that line; trailTopAt rolls it level: a few
		-- hundredths at a steep piece's edge)
		t.truthy(worst < 0.1, `the gravel stands {worst} over trailTopAt`)
		t.eq(LookoutHill.trailTopAt(0, 0), nil, "the town centre")
		local p = LookoutHill.trailPieces()[10]
		local dx, dz = p.bx - p.ax, p.bz - p.az
		local l = math.sqrt(dx * dx + dz * dz)
		-- (beside a mid-trail piece, past a landing's reach)
		local mx, mz = (p.ax + p.bx) / 2, (p.az + p.bz) / 2
		t.eq(LookoutHill.trailTopAt(mx - dz / l * (hw + 4), mz + dx / l * (hw + 4)), nil, "beside the trail")
	end)

	t.test("the layout is the game's whatever World/Height has configured, and Height is put back", function()
		local was = Height.configured()
		Height.configure(nil)
		local plain = LookoutHill.benches()
		t.eq(Height.configured(), nil, "put back")
		Height.configure(LookoutHill.terrain())
		local game = LookoutHill.benches()
		Height.configure(was)
		for i, b in plain do
			t.eq(b.ground, game[i].ground, b.name)
		end
	end)
end
