--!strict
-- THE WALKWAY (owner D32: "there's no room for the character to walk in between the sort of lanes there ... at least
-- there is a chance that the characters can walk past instead of having to hop over the parts before they bowl").
-- The eighteen-lane alley as it is baked (tools/bake/alley/Alley), with a person's body WALKER_R each way
-- (Shared/Attractions/AlleyLayout: Roblox's default body and its swinging arms) flood-filled over the baked parts
-- from the middle of the concourse, walking only (it steps over nothing taller than a stair's riser and never
-- jumps):
--   * it walks down every aisle between two pairs' settees, from the concourse to the approaches;
--   * it reaches every lane's station and the spot where the bowler waits with the ball (Bowling/Approach);
--   * it walks along the back of the approaches, behind the ball returns' racks, from lane 1 to lane 18;
--   * it still cannot get onto a lane; and the ball returns (the squirrels' enclosed run comes up inside each hood)
--     still stand between the two lanes of every pair.
local roblox = require("@lune/roblox")
local AlleyLayout = require("@shared/Attractions/AlleyLayout")
local Approach = require("@shared/Minigames/Bowling/Approach")
local Data = require("@shared/Data")
local Alley = require("../../tools/bake/alley/Alley")
local Kit = require("../../tools/bake/alley/Kit")

local L = AlleyLayout
local CELL = 0.25
local STEP, HEAD = 0.75, 5.2 -- the body's box starts one step above the floor and is this tall

return function(t)
	local mod = Data.default():module("Attractions") :: any
	local alley = mod.attractions[1]
	local place: AlleyLayout.Place = alley.place
	local kit = Kit.new(roblox, place)
	local root = roblox.Instance.new("Model")
	root.Name = "BowlingAlley"
	Alley.build(kit, root, alley)

	-- the hall from the concourse to the foul line, across the lane block and its two side aisles
	local X0, X1 = L.X0, L.HALL_X1
	local D0, D1 = L.CONCOURSE_D0, L.FOUL_D + 6
	local nx = math.floor((X1 - X0) / CELL)
	local nd = math.floor((D1 - D0) / CELL)
	local blocked = table.create(nx * nd, false)
	local function idx(i: number, j: number): number
		return (j - 1) * nx + i
	end
	local function cell(X: number, D: number): (number, number)
		return math.floor((X - X0) / CELL) + 1, math.floor((D - D0) / CELL) + 1
	end
	local R = L.WALKER_R
	for _, top in root:GetChildren() do
		local list = top:GetDescendants()
		table.insert(list, top)
		for _, p in list do
			-- (the exit doors swing; a carve box is not there in the game; people collide with the LaneGuard group)
			if p:IsA("BasePart") and p.CanCollide and top.Name ~= "Doors" and top.Name ~= "TerrainCarve" then
				local cf, s = p.CFrame, p.Size
				local X, Y, D = L.toLocal(place, cf.Position.X, cf.Position.Y, cf.Position.Z)
				local r, u, l = cf.XVector, cf.YVector, cf.ZVector
				local hx = (math.abs(r.X) * s.X + math.abs(u.X) * s.Y + math.abs(l.X) * s.Z) / 2
				local hy = (math.abs(r.Y) * s.X + math.abs(u.Y) * s.Y + math.abs(l.Y) * s.Z) / 2
				local hd = (math.abs(r.Z) * s.X + math.abs(u.Z) * s.Y + math.abs(l.Z) * s.Z) / 2
				local floor = L.floorAt(X, D) or 0
				-- what stands across the body's height (the floor slabs under it do not)
				if Y + hy > floor + STEP and Y - hy < floor + HEAD then
					local i0, j0 = cell(X - hx - R, D - hd - R)
					local i1, j1 = cell(X + hx + R, D + hd + R)
					for j = math.max(1, j0), math.min(nd, j1) do
						for i = math.max(1, i0), math.min(nx, i1) do
							blocked[idx(i, j)] = true
						end
					end
				end
			end
		end
	end
	-- walking only: flood from the middle of the concourse
	local seen = table.create(nx * nd, false)
	local si, sj = cell(L.post("concourse_mid").x, L.post("concourse_mid").d)
	t.falsy(blocked[idx(si, sj)], "the concourse's middle is clear")
	local queue, head = { idx(si, sj) }, 1
	seen[idx(si, sj)] = true
	while head <= #queue do
		local k = queue[head]
		head += 1
		local i = (k - 1) % nx + 1
		local j = (k - 1) // nx + 1
		for _, d in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
			local ni, nj = i + d[1], j + d[2]
			if ni >= 1 and ni <= nx and nj >= 1 and nj <= nd then
				local nk = idx(ni, nj)
				if not seen[nk] and not blocked[nk] then
					seen[nk] = true
					table.insert(queue, nk)
				end
			end
		end
	end
	local function reached(X: number, D: number): boolean
		local i, j = cell(X, D)
		return i >= 1 and i <= nx and j >= 1 and j <= nd and seen[idx(i, j)]
	end

	t.test(
		"a person walks down every aisle between the pairs' settees, from the concourse to the approaches",
		function()
			t.truthy(L.AISLE_W >= 2 * R + 1.5, `the aisles are {L.AISLE_W} wide for a body {2 * R} across`)
			for p = 1, L.PAIRS - 1 do
				local a, b = L.aisle(p)
				local mid = (a + b) / 2
				for d = L.SETTEE_D - 5, L.APPROACH_D + 1, 0.5 do -- (from the concourse, behind the settees)
					if not reached(mid, d) then
						t.truthy(false, `the aisle between pairs {p} and {p + 1} is blocked at D {d}`)
						break
					end
				end
				-- nothing of the hall's stands in it
				for d = L.SETTEE_D - 4, L.APPROACH_D, 0.5 do
					for x = a + R + 2 * CELL, b - R - 2 * CELL + 1e-9, 0.25 do -- (two cells of the grid kept at each edge)
						local i, j = cell(x, d)
						if blocked[idx(i, j)] then
							t.truthy(
								false,
								`the aisle between pairs {p} and {p + 1} has something in it at X {x} D {d}`
							)
							return
						end
					end
				end
			end
		end
	)

	t.test("a person walks up to every lane, to where the bowler waits with the ball, and along behind them", function()
		for lane = 1, L.LANES do
			local x = L.laneX(lane)
			t.truthy(reached(x, -9), `lane {lane}'s station`)
			t.truthy(reached(x, Approach.START_D), `where lane {lane}'s bowler waits`)
			t.truthy(reached(x, L.APPROACH_D + 1), `the back of lane {lane}'s approach`)
		end
		-- along the back of the approaches, behind every rack, from one end of the lane block to the other
		local d = (L.APPROACH_D + L.RACK_D1) / 2
		t.truthy(L.RACK_D1 - L.APPROACH_D >= 2 * R + 1, "room behind the racks")
		for x = L.LANE_BLOCK_X0 + R, L.LANE_BLOCK_X1 - R, 0.5 do
			if not reached(x, d) then
				t.truthy(false, `the walk behind the approaches is blocked at X {x} D {d}`)
				break
			end
		end
		-- and still nobody gets onto a lane
		for lane = 1, L.LANES do
			t.falsy(reached(L.laneX(lane), 3), `a body got onto lane {lane}`)
		end
	end)

	t.test(
		"the ball returns still stand between the two lanes of every pair, the settees still seat a pair's bowlers",
		function()
			local returns = root:FindFirstChild("Returns")
			local settees = root:FindFirstChild("Settees")
			t.truthy(returns ~= nil and settees ~= nil)
			for p = 1, L.PAIRS do
				local ret = returns:FindFirstChild(`Return{p}`)
				t.truthy(ret ~= nil and ret:FindFirstChild("HoodSide") ~= nil, `pair {p}'s ball return`)
				local s = settees:FindFirstChild(`Settee{p}`)
				t.truthy(s ~= nil, `pair {p}'s settee`)
				local bench = s:FindFirstChild("BenchSeat")
				local w = bench.Size.X
				t.truthy(w >= 7, `pair {p}'s back bench is {w} wide (room for four)`)
				t.near(w, 2 * L.SETTEE_HALF, 0.01)
			end
		end
	)
end
