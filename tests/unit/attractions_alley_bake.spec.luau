--!strict
-- The eighteen-lane bowling alley as it is baked (tools/bake/alley/Alley, the code that writes
-- build/Attractions.rbxm), built in memory at its real place and measured against the floor plan
-- (Shared/Attractions/AlleyLayout; brief addendum D4, D5):
--   * everything baked lies inside the footprint data/attractions.json declares (the expansion planner keeps the
--     neighbours out of that box), and the part count stays inside its budget;
--   * A WALK TEST: a body 2 studs wide and 5.2 tall is flood-filled over the baked parts from the foot of the
--     entrance ramp, standing on the plan's floors (AlleyLayout.floorAt). It reaches every staff post, the back of
--     every approach, the spot behind every pinsetter and every minigame station; it can walk every leg of every
--     staff route without touching a wall or a piece of furniture; and it cannot get onto a lane;
--   * there is a floor part under every post (the employees have something to stand on);
--   * the names the server relies on, the terrain carve boxes, the lights;
--   * the interim back module: everything behind the pinsetters is the model "BackModule" (plus the exit doors
--     and the tunnels' tails), nothing of it reaches in front of the masking units, and the anchor part for the
--     owner's backstage is where the plan says.
local roblox = require("@lune/roblox")
local AlleyLayout = require("@shared/Attractions/AlleyLayout")
local Data = require("@shared/Data")
local Games = require("@shared/Minigames/Games")
local Alley = require("../../tools/bake/alley/Alley")
local Kit = require("../../tools/bake/alley/Kit")

local L = AlleyLayout
local CELL, HALF = 0.5, 1.0
local STEP, HEAD = 0.75, 5.2 -- the body's box starts one step above the floor and is this tall

return function(t)
	local mod = Data.default():module("Attractions") :: any
	local alley = mod.attractions[1]
	local place: AlleyLayout.Place = alley.place
	local fp = alley.footprint
	local kit = Kit.new(roblox, place)
	local root = roblox.Instance.new("Model")
	root.Name = "BowlingAlley"
	Alley.build(kit, root, alley)

	-- every part's box in the local frame (the place has yaw 0: local X is world X, local D is world -Z)
	type Box = { part: any, top: string, X: number, Y: number, D: number, hx: number, hy: number, hd: number }
	local boxes: { Box } = {}
	for _, top in root:GetChildren() do
		local list = top:GetDescendants()
		table.insert(list, top)
		for _, p in list do
			if p:IsA("BasePart") then
				local cf, s = p.CFrame, p.Size
				local X, Y, D = L.toLocal(place, cf.Position.X, cf.Position.Y, cf.Position.Z)
				local r, u, l = cf.XVector, cf.YVector, cf.ZVector
				table.insert(boxes, {
					part = p,
					top = top.Name,
					X = X,
					Y = Y,
					D = D,
					hx = (math.abs(r.X) * s.X + math.abs(u.X) * s.Y + math.abs(l.X) * s.Z) / 2,
					hy = (math.abs(r.Y) * s.X + math.abs(u.Y) * s.Y + math.abs(l.Y) * s.Z) / 2,
					hd = (math.abs(r.Z) * s.X + math.abs(u.Z) * s.Y + math.abs(l.Z) * s.Z) / 2,
				})
			end
		end
	end

	t.test("the bake stays inside the declared footprint and its part budget", function()
		t.eq(place.yaw, 0, "the spec reads boxes in a yaw 0 frame")
		t.eq(#boxes, kit.count)
		local perTop: { [string]: number } = {}
		for _, b in boxes do
			perTop[b.top] = (perTop[b.top] or 0) + 1
			if b.top ~= "TerrainCarve" then
				local inside = b.X - b.hx >= fp.x0 - 0.01
					and b.X + b.hx <= fp.x1 + 0.01
					and b.D - b.hd >= fp.d0 - 0.01
					and b.D + b.hd <= fp.d1 + 0.01
				t.truthy(inside, `{b.top}.{b.part.Name} at X {b.X} D {b.D} is outside the footprint`)
			end
		end
		-- the budget: the building with the games' furniture (the shop rooms are still empty)
		t.truthy(#boxes > 4500 and #boxes < 6200, `{#boxes} parts`)
		t.truthy(perTop.Lanes <= L.LANES * 132, `the lanes are {perTop.Lanes} parts`)
		t.truthy(perTop.BackModule < 450, `the back module is {perTop.BackModule} parts`)
		t.eq(
			perTop.TerrainCarve,
			L.PAIRS + 2 + #L.SITE_CUTS,
			"a carve box per duct, the alley, the entrance, the site cuts"
		)
	end)

	-- THE WALK TEST ----------------------------------------------------------------------------------------------
	local gx0, gd0 = fp.x0 - 2, fp.d0 - 2
	local nx = math.floor((fp.x1 + 2 - gx0) / CELL)
	local nd = math.floor((fp.d1 + 2 - gd0) / CELL)
	local NOFLOOR = -1e9
	local floor = table.create(nx * nd, NOFLOOR)
	local blocked = table.create(nx * nd, false)
	local function idx(i: number, j: number): number
		return (j - 1) * nx + i
	end
	local function cell(X: number, D: number): (number, number)
		return math.floor((X - gx0) / CELL) + 1, math.floor((D - gd0) / CELL) + 1
	end
	for j = 1, nd do
		for i = 1, nx do
			local f = L.floorAt(gx0 + (i - 0.5) * CELL, gd0 + (j - 0.5) * CELL)
			if f then
				floor[idx(i, j)] = f
			else
				blocked[idx(i, j)] = true
			end
		end
	end
	for _, b in boxes do
		-- (the exit doors swing: Server/Attractions/AttractionService; a carve box is not there in the game)
		if b.part.CanCollide and b.top ~= "Doors" and b.top ~= "TerrainCarve" then
			local top, bottom = b.Y + b.hy, b.Y - b.hy
			-- A wall or a piece of furniture keeps the body's half width away from it. A part that is itself the
			-- floor somewhere under it (a slab, a landing, a stair tread: its top no higher than the plan's floor
			-- over its own outline) is walked ON: it only blocks where it really stands above the floor.
			local grow = HALF
			if top <= 0.05 then
				local over = NOFLOOR
				local a0, a1 = cell(b.X - b.hx + 0.01, b.D - b.hd + 0.01)
				local b0, b1 = cell(b.X + b.hx - 0.01, b.D + b.hd - 0.01)
				for j = math.max(1, a1), math.min(nd, b1) do
					for i = math.max(1, a0), math.min(nx, b0) do
						over = math.max(over, floor[idx(i, j)])
					end
				end
				if top <= over + 0.05 then
					grow = 0
				end
			end
			local i0 = math.max(1, math.floor((b.X - b.hx - grow - gx0) / CELL) + 1)
			local i1 = math.min(nx, math.ceil((b.X + b.hx + grow - gx0) / CELL))
			local j0 = math.max(1, math.floor((b.D - b.hd - grow - gd0) / CELL) + 1)
			local j1 = math.min(nd, math.ceil((b.D + b.hd + grow - gd0) / CELL))
			for j = j0, j1 do
				for i = i0, i1 do
					local k = idx(i, j)
					local f = floor[k]
					if f ~= NOFLOOR and top > f + STEP and bottom < f + HEAD then
						blocked[k] = true
					end
				end
			end
		end
	end
	local seen = table.create(nx * nd, false)
	do
		local ramp = L.RAMP
		local si, sj = cell((ramp.x0 + ramp.x1) / 2, ramp.d0 + 1.5)
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
	end
	local function reached(X: number, D: number): boolean
		local i, j = cell(X, D)
		return i >= 1 and i <= nx and j >= 1 and j <= nd and seen[idx(i, j)]
	end
	local function reachedNear(X: number, D: number, radius: number): boolean
		for dX = -radius, radius, CELL do
			for dD = -radius, radius, CELL do
				if dX * dX + dD * dD <= radius * radius and reached(X + dX, D + dD) then
					return true
				end
			end
		end
		return false
	end

	t.test("walk test: from the entrance ramp a body reaches every staff post, approach and pinsetter", function()
		t.truthy(reached(22, -72), "the landing")
		t.truthy(reached(22, -60), "through the main doors")
		for _, p in L.POSTS do
			t.truthy(reached(p.x, p.d), `post {p.id} ({p.what}) at X {p.x} D {p.d}`)
		end
		for lane = 1, L.LANES do
			local a, m = L.approachPost(lane), L.machinePost(lane)
			t.truthy(reached(a.x, a.d), `the back of lane {lane}'s approach`)
			t.truthy(reached(m.x, m.d), `behind lane {lane}'s pinsetter`)
			-- up to the foul line, and no further: people cannot get onto a lane
			t.truthy(reached(a.x, -2.5), `lane {lane}'s foul line`)
			for _, d in { 4, 20, 45 } do
				t.falsy(reached(L.laneX(lane), d), `a body got onto lane {lane} at D {d}`)
			end
		end
		-- every room of the plan can be stood in
		for _, z in L.ZONES do
			if z.id ~= "lanes" then
				t.truthy(reachedNear((z.x0 + z.x1) / 2, (z.d0 + z.d1) / 2, 6), `room {z.id}`)
			end
		end
	end)

	t.test("walk test: every leg of every staff route is clear, and every doorway lets a body through", function()
		for id, pts in L.ROUTES do
			for i = 2, #pts do
				local a, b = pts[i - 1], pts[i]
				local len = math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2)
				local steps = math.max(1, math.ceil(len / 0.25))
				for s = 0, steps do
					local X = a[1] + (b[1] - a[1]) * s / steps
					local D = a[2] + (b[2] - a[2]) * s / steps
					if not reached(X, D) then
						t.truthy(false, `route {id} leg {i - 1} is blocked at X {X} D {D}`)
						break
					end
				end
			end
		end
		for _, o in L.OPENINGS do
			if o.kind == "door" or o.kind == "arch" or o.kind == "open" then
				local mid = (o.a + o.b) / 2
				if o.axis == "x" then
					t.truthy(reached(mid, o.at - 0.3), `through {o.id}`)
				else
					t.truthy(reached(o.at + 0.3, mid), `through {o.id}`)
				end
			elseif o.kind == "counter" then
				-- the staff's gap at the far end of a serving counter
				local gap = o.b - L.COUNTER_GAP / 2
				if o.axis == "x" then
					t.truthy(reached(gap, o.at - 0.3), `through the gap of {o.id}`)
				else
					t.truthy(reached(o.at, gap), `through the gap of {o.id}`)
				end
			end
		end
	end)

	t.test("walk test: every minigame station of the alley can be walked up to", function()
		local stations = Games.stations({ bowling_alley = place })
		local lanes = 0
		for _, st in stations do
			if st.site == "bowling_alley" then
				t.truthy(reachedNear(st.x, st.d, 4.5), `station {st.id} at X {st.x} D {st.d}`)
				lanes += if st.game == "bowling" then 1 else 0
			end
		end
		t.eq(lanes, L.LANES, "a bowling station per lane")
		-- and the clear floor the plan keeps for each table really is clear of the building (the table itself is
		-- inside it, and a machine against a wall fills two corners): its open corners can be stood on
		for _, s in L.standing() do
			local corners = 0
			for _, c in
				{
					{ s.x0 + 1.2, s.d0 + 1.2 },
					{ s.x1 - 1.2, s.d0 + 1.2 },
					{ s.x0 + 1.2, s.d1 - 1.2 },
					{ s.x1 - 1.2, s.d1 - 1.2 },
				}
			do
				corners += if reachedNear(c[1], c[2], 1) then 1 else 0
			end
			local want = if s.id == "pinball" or s.id == "fortune" or s.id == "darts" then 2 else 4
			t.truthy(corners >= want, `{s.id}: {corners} of 4 corners of its floor can be stood on`)
		end
	end)

	t.test("there is a floor under every post and route point", function()
		local function floorPartUnder(X: number, D: number, y: number): boolean
			for _, b in boxes do
				if
					b.part.CanCollide
					and math.abs(X - b.X) <= b.hx
					and math.abs(D - b.D) <= b.hd
					and b.Y + b.hy <= y + 0.75
					and b.Y + b.hy >= y - 0.75
				then
					return true
				end
			end
			return false
		end
		for _, p in L.POSTS do
			t.truthy(floorPartUnder(p.x, p.d, L.floorAt(p.x, p.d) :: number), `under post {p.id}`)
		end
		for id in L.ROUTES do
			for i, p in L.route(id) do
				t.truthy(floorPartUnder(p[1], p[2], p[3]), `under route {id} point {i}`)
			end
		end
		for lane = 1, L.LANES, 17 do
			local m = L.machinePost(lane)
			t.truthy(floorPartUnder(m.x, m.d, 0), `behind lane {lane}'s pinsetter`)
		end
	end)

	t.test("what the server finds by name, the lights, and the tunnels", function()
		local lanes = root:FindFirstChild("Lanes") :: any
		local boards = root:FindFirstChild("Scoreboards") :: any
		local returns = root:FindFirstChild("Returns") :: any
		local tunnels = root:FindFirstChild("Tunnels") :: any
		local settees = root:FindFirstChild("Settees") :: any
		for lane = 1, L.LANES do
			local lm = lanes:FindFirstChild(`Lane{lane}`)
			t.truthy(lm and lm:FindFirstChild("Ball") and lm:FindFirstChild("Sweep") and lm:FindFirstChild("Pins"))
			t.eq(lm:GetAttribute("Pair"), L.pairOf(lane))
			local sb = boards:FindFirstChild(`Lane{lane}`)
			t.truthy(sb and sb:FindFirstChild("Screen") and sb.Screen:FindFirstChild("Score"), `scoreboard {lane}`)
		end
		for p = 1, L.PAIRS do
			t.truthy(returns:FindFirstChild(`Return{p}`), `ball return {p}`)
			t.truthy(settees:FindFirstChild(`Settee{p}`), `settee {p}`)
			local tun = tunnels:FindFirstChild(`Tunnel{p}`)
			t.truthy(tun ~= nil and tun:GetAttribute("Pair") == p, `tunnel {p}`)
			t.truthy(root.TerrainCarve:FindFirstChild(`Duct{p}`), `carve box for duct {p}`)
		end
		local games = root:FindFirstChild("GamesRoom") :: any
		t.truthy(games:FindFirstChild("Dartboard") and games.Dartboard:FindFirstChild("BoardFace"))
		for _, name in { "Lever", "Reel1", "Reel2", "Reel3", "CardSlot" } do
			t.truthy(games.Fortune:FindFirstChild(name), `Fortune.{name}`)
		end
		-- the exit doors: two push-bar leaves the server swings
		local doors = root:FindFirstChild("Doors") :: any
		local leaves = 0
		for _, m in doors:GetChildren() do
			if m:IsA("Model") and m:GetAttribute("Door") == "push_bar" and m.PrimaryPart then
				leaves += 1
			end
		end
		t.eq(leaves, 2)
		-- lights: plenty of them, few that cast shadows (they are the expensive ones)
		local lights, shadows = 0, 0
		for _, d in root:GetDescendants() do
			if d:IsA("PointLight") or d:IsA("SpotLight") or d:IsA("SurfaceLight") then
				lights += 1
				shadows += if d.Shadows then 1 else 0
			end
		end
		t.truthy(lights >= 80 and lights <= 160, `{lights} lights`)
		t.truthy(shadows <= L.PAIRS + 2, `{shadows} lights cast shadows`)
		-- a real ceiling over every room (the roof deck is dark slate)
		local ceilings = root:FindFirstChild("Ceilings") :: any
		t.truthy(ceilings ~= nil and #ceilings:GetChildren() >= 3)
	end)

	t.test("the interim back module is one model behind the pinsetters; the backstage's anchor is in place", function()
		local bs = L.BACKSTAGE
		local back = root:FindFirstChild("BackModule") :: any
		t.truthy(back ~= nil and back:GetAttribute("Interim") == true)
		t.eq(back:GetAttribute("ReplacedBy"), bs.anchorName)
		local machines = back:FindFirstChild("Machines") :: any
		t.eq(#machines:GetChildren(), L.LANES, "a stand-in pinsetter per lane")
		local it = bs.interim
		for _, b in boxes do
			local mine = b.top == "BackModule" or b.top == "Doors"
			if mine then
				-- the stand-in machines sit over the pits, behind the masking units; everything else is behind the
				-- pinsetters' line (the EMPLOYEES ONLY signs hang on the hall side of the machine-room wall)
				local isMachine = b.part:IsDescendantOf(machines)
				local front = if isMachine then bs.anchor.d else bs.interimFrom - 1
				t.truthy(
					b.D - b.hd >= front - 0.01,
					`{b.part.Name} reaches in front of the back module (D {b.D - b.hd})`
				)
				t.truthy(b.D + b.hd <= it.d1 + 0.01, `{b.part.Name} reaches behind the back module`)
			elseif b.top ~= "Tunnels" and b.top ~= "TerrainCarve" and b.top ~= bs.anchorName then
				t.truthy(
					b.D + b.hd <= bs.interimFrom + 0.15,
					`{b.top}.{b.part.Name} is behind the pinsetters (D {b.D + b.hd})`
				)
			end
		end
		-- three big round dark-blue trash cans and the push broom by the door (brief v2 §13a)
		local props = back:FindFirstChild("AlleyProps") :: any
		local exit = L.opening("exit_doors")
		for i = 1, 3 do
			local can = props:FindFirstChild(`TrashCan{i}`)
			t.truthy(can ~= nil, `trash can {i}`)
			local body = can.Body
			t.truthy(body.Color.B > body.Color.R * 2 and body.Color.B < 0.5, "dark blue")
			t.truthy(body.Size.Y >= 2.4, "big and round")
		end
		local broom = props:FindFirstChild("BroomHandle")
		local bX = L.toLocal(place, broom.CFrame.Position.X, broom.CFrame.Position.Y, broom.CFrame.Position.Z)
		t.truthy(math.abs(bX - exit.b) < 4, "the broom leans by the door")
		-- the anchor: a hidden part at ServiceFrontCenter, axes as the package's (+X to lane 18, +Z to the
		-- customers), carrying the scale
		local anchor = root:FindFirstChild(bs.anchorName) :: any
		t.truthy(anchor ~= nil and anchor:IsA("BasePart"))
		local aX, aY, aD =
			L.toLocal(place, anchor.CFrame.Position.X, anchor.CFrame.Position.Y, anchor.CFrame.Position.Z)
		t.near(aX, bs.anchor.x, 1e-3)
		t.near(aY, bs.anchor.y, 1e-3)
		t.near(aD, bs.anchor.d, 1e-3)
		t.near(anchor:GetAttribute("Scale"), bs.scale, 1e-6)
		t.eq(anchor.Transparency, 1)
		t.eq(anchor.CanCollide, false)
		local x18 = L.toWorld(place, L.laneX(18), 0, bs.anchor.d)
		local toLane18 = roblox.Vector3.new(x18 - anchor.CFrame.Position.X, 0, 0).Unit
		t.truthy(anchor.CFrame.XVector:Dot(toLane18) > 0.999, "+X points to lane 18")
		local cx, _, cz = L.toWorld(place, bs.anchor.x, 0, bs.anchor.d - 10)
		local toCustomers = roblox.Vector3.new(cx - anchor.CFrame.Position.X, 0, cz - anchor.CFrame.Position.Z).Unit
		t.truthy(anchor.CFrame.ZVector:Dot(toCustomers) > 0.999, "+Z points to the customer lanes")
	end)
end
