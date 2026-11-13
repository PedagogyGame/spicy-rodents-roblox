--!strict
-- The yard behind the bowling alley's games room as baked (tools/bake/alley/Yard; BRIEF_ADDENDUM D9, D10), built
-- in memory at the alley's place and held to the routes of Shared/Attractions/AlleyRoof:
--   * it stays in the alley's footprint or the yard annex, inside its part budget;
--   * what the squirrel runs on is drawn where the motor puts it: the downspout's pipe round route 9101; the
--     trunk's bark at the squirrel's tapered radius on 9104 (Routes/Motion.visualPose, as the town's trees); the
--     boughs' TOP at the rail + 1.25 on 9105 and 9106 with the rail inside the bark; the ridge cap's top on 9103;
--     the gutter route riding just over the north slope;
--   * the roof slopes collide (a squirrel that misses the leap lands on them), the boughs and leaves do not;
--   * the leaf clumps keep a tunnel round every route and the leap's flight, so the squirrel stays in sight;
--   * the leap's flight off the ridge passes through nothing solid; the way into the downspout is clear.
local roblox = require("@lune/roblox")
local AlleyLayout = require("@shared/Attractions/AlleyLayout")
local AlleyRoof = require("@shared/Attractions/AlleyRoof")
local Curve = require("@shared/Routes/Curve")
local Data = require("@shared/Data")
local SquirrelMotor = require("@shared/Movement/SquirrelMotor")
local Kit = require("../../tools/bake/alley/Kit")
local Yard = require("../../tools/bake/alley/Yard")

local R = AlleyRoof
local LIFT = 1.25

type Box = { part: any, model: string, X: number, Y: number, D: number, hx: number, hy: number, hd: number }

return function(t)
	local alley = (Data.default():module("Attractions") :: any).attractions[1]
	local place: AlleyLayout.Place = alley.place
	local fp = alley.footprint
	local kit = Kit.new(roblox, place)
	local root = roblox.Instance.new("Model")
	local yard = Yard.build(kit, root)
	local V3 = roblox.Vector3

	local boxes: { Box } = {}
	local byName: { [string]: any } = {}
	for _, m in yard:GetChildren() do
		for _, p in m:GetDescendants() do
			if p:IsA("BasePart") then
				local cf, s = p.CFrame, p.Size
				local X, Y, D = AlleyLayout.toLocal(place, cf.Position.X, cf.Position.Y, cf.Position.Z)
				local r, u, l = cf.XVector, cf.YVector, cf.ZVector
				table.insert(boxes, {
					part = p,
					model = m.Name,
					X = X,
					Y = Y,
					D = D,
					hx = (math.abs(r.X) * s.X + math.abs(u.X) * s.Y + math.abs(l.X) * s.Z) / 2,
					hy = (math.abs(r.Y) * s.X + math.abs(u.Y) * s.Y + math.abs(l.Y) * s.Z) / 2,
					hd = (math.abs(r.Z) * s.X + math.abs(u.Z) * s.Y + math.abs(l.Z) * s.Z) / 2,
				})
				byName[p.Name] = p
			end
		end
	end
	local function world(X: number, Y: number, D: number): any
		local x, y, z = AlleyLayout.toWorld(place, X, Y, D)
		return V3.new(x, y, z)
	end
	local function samples(id: number, n: number): { any }
		local c = Curve.fromArrays(R.route(id).points)
		local out = {}
		for i = 0, n do
			local p = c:getPointAt(i / n)
			table.insert(out, { t = i / n, p = world(p.x, p.y, p.z) })
		end
		return out
	end
	-- a cylinder part's axis (its X) and radius
	local function axisOf(p: any): (any, any, number, number)
		local cf = p.CFrame
		return cf.Position, cf.XVector, p.Size.X / 2, math.min(p.Size.Y, p.Size.Z) / 2
	end
	-- the point of a cylinder's axis nearest q, the distance to it, and whether q projects inside its length
	local function onAxis(p: any, q: any): (any, number, boolean)
		local c, ax, half = axisOf(p)
		local s = (q - c):Dot(ax)
		local a = c + ax * math.clamp(s, -half, half)
		return a, (q - a).Magnitude, math.abs(s) <= half + 1e-3
	end
	local function inside(p: any, q: any): boolean
		local l = p.CFrame:Inverse() * q
		local s = p.Size
		if p:IsA("Part") and p.Shape == roblox.Enum.PartType.Cylinder then
			return math.abs(l.X) <= s.X / 2 and l.Y * l.Y + l.Z * l.Z <= (math.min(s.Y, s.Z) / 2) ^ 2
		elseif p:IsA("Part") and p.Shape == roblox.Enum.PartType.Ball then
			return l.Magnitude <= s.X / 2
		end
		return math.abs(l.X) <= s.X / 2 and math.abs(l.Y) <= s.Y / 2 and math.abs(l.Z) <= s.Z / 2
	end

	t.test("the yard: in the footprint or the annex, inside its budget, named for the client", function()
		local house, tree = 0, 0
		local an = R.ANNEX
		for _, b in boxes do
			if b.model == "House" then
				house += 1
			else
				tree += 1
			end
			local x0, x1, d0, d1 = b.X - b.hx, b.X + b.hx, b.D - b.hd, b.D + b.hd
			local inFoot = x0 >= fp.x0 and x1 <= fp.x1 and d0 >= fp.d0 and d1 <= fp.d1
			-- the annex and the strip of the footprint beside it (the crossing reaches over the wing)
			local inAnnex = x0 >= fp.x0 and x1 <= an.x1 + 0.01 and d0 >= an.d0 - 0.01 and d1 <= an.d1 + 0.01
			t.truthy(inFoot or inAnnex, `{b.model}.{b.part.Name} at ({b.X}, {b.D}) lies outside`)
		end
		t.eq(house + tree, kit.count)
		t.truthy(house <= 170, `the house is {house} parts`)
		t.truthy(tree <= 100, `the tree is {tree} parts`)
		print(`      the house {house} parts, the tree {tree}`)
		t.truthy(yard:FindFirstChild("Tree_AlleyYard") ~= nil, "the tree's model is named for ClientWorld")
		for i = 1, 6 do
			t.truthy(byName[`Trunk{i}`] ~= nil and byName[`Trunk{i}`].CanCollide, `Trunk{i} collides`)
		end
	end)

	t.test("the downspout's pipe is drawn round route 9101, from its foot to the gutter", function()
		local pipe = byName.Downspout
		local r = R.route(9101).surfaceRadius
		local _, _, half, radius = axisOf(pipe)
		t.near(radius, r, 0.05, "the pipe's radius is the route's surface radius")
		local covered = 0
		for _, s in samples(9101, 40) do
			local _, d, within = onAxis(pipe, s.p)
			if within then
				covered += 1
				t.truthy(d <= 0.15, `the pipe's axis is {d} off the route at t {s.t}`)
			end
		end
		t.truthy(covered >= 36, `the pipe covers {covered} of 41 samples`)
		t.truthy(half > 8, "a whole pipe")
		-- the way in: nothing colliding north of the pipe at the squirrel's height
		local foot = R.route(9101).points[1]
		for d = foot[3] - 6, foot[3] - 0.6, 0.2 do
			for _, b in boxes do
				if b.part.CanCollide then
					t.truthy(not inside(b.part, world(foot[1], foot[2] + 0.8, d)), `{b.part.Name} blocks the way in`)
				end
			end
		end
	end)

	t.test("the trunk's bark is the squirrel's tapered radius round route 9104", function()
		local rT = R.route(9104).surfaceRadius
		for _, s in samples(9104, 48) do
			local best, bestPart = math.huge, nil :: any
			for i = 1, 6 do
				local p = byName[`Trunk{i}`]
				local _, d, within = onAxis(p, s.p)
				if within and d < best then
					best, bestPart = d, p
				end
			end
			t.truthy(bestPart ~= nil and best <= 0.15, `the trunk's axis is {best} off the route at t {s.t}`)
			local _, _, _, radius = axisOf(bestPart)
			local want = math.max(0.8, rT * (1 - 0.48 * s.t))
			t.truthy(math.abs(radius - want) <= 0.15, `bark {radius} vs the squirrel's {want} at t {s.t}`)
		end
	end)

	t.test("the boughs: their top is the squirrel's feet (rail + 1.25), the rail inside the bark", function()
		for _, id in { 9105, 9106 } do
			for _, s in samples(id, 60) do
				-- the bark's top straight over the rail point: the highest point of the vertical line through it that is
				-- on a bough segment's surface (inside its length, a little slack at the joints, where a ball rounds it)
				local top = -math.huge
				local inBark = false
				for _, b in boxes do
					local p = b.part
					if
						string.sub(p.Name, 1, #`Bough{id}_`) == `Bough{id}_`
						and p.Shape == roblox.Enum.PartType.Cylinder
					then
						local c, ax, half, radius = axisOf(p)
						local w = s.p - c
						local vy = ax.Y
						local qa = 1 - vy * vy
						local qb = 2 * (w.Y - w:Dot(ax) * vy)
						local qc = w:Dot(w) - w:Dot(ax) ^ 2 - radius * radius
						local disc = qb * qb - 4 * qa * qc
						if disc >= 0 and qa > 1e-9 then
							local h = (-qb + math.sqrt(disc)) / (2 * qa)
							local along = (w + V3.new(0, h, 0)):Dot(ax)
							if math.abs(along) <= half + 0.3 then
								top = math.max(top, h)
							end
						end
						local _, d = onAxis(p, s.p)
						inBark = inBark or d <= radius
					end
				end
				t.truthy(inBark, `route {id} at t {s.t} is inside the bark`)
				t.truthy(math.abs(top - LIFT) <= 0.15, `route {id} at t {s.t}: the bough's top is {top} over the rail`)
			end
		end
	end)

	t.test(
		"the roof: the ridge cap's top is the ridge route, the gutter route rides the north slope, both slopes collide",
		function()
			local cap = byName.RidgeCap
			local ridge = R.route(9103).points
			local _, capTop = AlleyLayout.toLocal(place, 0, cap.CFrame.Position.Y + cap.Size.Y / 2, 0)
			t.near(capTop, ridge[1][2], 0.02)
			local cx = AlleyLayout.toLocal(place, cap.CFrame.Position.X, 0, cap.CFrame.Position.Z)
			t.truthy(
				cx - cap.Size.X / 2 <= ridge[2][1] - 0.5 and cx + cap.Size.X / 2 >= ridge[1][1],
				"the cap runs the route's length"
			)
			local roofN = byName.RoofN
			t.truthy(roofN.CanCollide and byName.RoofS.CanCollide, "a squirrel that misses the leap lands on the roof")
			local n = roofN.CFrame.YVector
			t.truthy(n.Y > math.cos(math.rad(40)), "the slopes are under 40 degrees")
			local topC = roofN.CFrame.Position + n * (roofN.Size.Y / 2)
			for _, s in samples(9102, 40) do
				local _, _, D = AlleyLayout.toLocal(place, s.p.X, s.p.Y, s.p.Z)
				if D > R.HOUSE.d0 + 0.2 and D < R.HOUSE.ridgeD - 0.3 then
					local h = (s.p - topC):Dot(n)
					t.truthy(h >= 0 and h <= 0.45, `the gutter route is {h} over the slope at D {D}`)
				end
			end
		end
	)

	-- the leap's flight off the ridge's west end with no key (the longest and highest) and with W held: sampled from
	-- the motor's own numbers (leap off a rail, gravity, the air steer toward v5.4's walk)
	local function flights(): { { any } }
		local out = {}
		local endP = R.route(9103).points[2]
		for _, held in { false, true } do
			local x, y, z = AlleyLayout.toWorld(place, endP[1], endP[2], endP[3])
			local P = SquirrelMotor.params
			local vx, vy = -P.leapForward, P.leapUp
			local path = {}
			for _ = 1, 40 do
				local dt = 1 / 60
				if held then
					local a = 1 - math.exp(-dt * P.accelAir)
					vx += (-SquirrelMotor.V54.walk - vx) * a
				else
					vx *= math.exp(-dt * P.dragAir)
				end
				vy -= P.gravity * dt
				x += vx * dt
				y += vy * dt
				table.insert(path, V3.new(x, y, z))
			end
			table.insert(out, path)
		end
		return out
	end

	t.test(
		"the leap's flight passes through nothing solid and the crown keeps a tunnel round it and every route",
		function()
			local paths = flights()
			for _, path in paths do
				for _, q in path do
					for _, b in boxes do
						if b.part.CanCollide then
							t.truthy(not inside(b.part, q), `the flight passes through {b.part.Name}`)
						end
					end
				end
			end
			local keep: { any } = {}
			for _, id in { 9101, 9102, 9103, 9104, 9105, 9106 } do
				for _, s in samples(id, 60) do
					table.insert(keep, s.p + V3.new(0, if id == 9105 or id == 9106 then LIFT else 0, 0))
				end
			end
			for _, path in paths do
				for _, q in path do
					table.insert(keep, q)
				end
			end
			local nearest = math.huge
			for i, c in Yard.LEAF_CLUMPS do
				local leaves = byName[`Leaves{i}`]
				t.truthy(not leaves.CanCollide and not leaves.CanQuery, "leaves neither collide nor take queries")
				local centre = world(c[1], c[2], c[3])
				for _, q in keep do
					nearest = math.min(nearest, (q - centre).Magnitude - c[4] / 2)
				end
			end
			t.truthy(nearest >= 2.0, `a leaf clump comes within {nearest} of a route or the leap`)
			print(`      the nearest leaf clump is {string.format("%.1f", nearest)} st from a route or the leap`)
			for _, b in boxes do
				if
					string.sub(b.part.Name, 1, 5) == "Bough"
					or string.sub(b.part.Name, 1, 4) == "Limb"
					or string.sub(b.part.Name, 1, 4) == "Twig"
				then
					t.truthy(not b.part.CanCollide and not b.part.CanQuery, `{b.part.Name} is drawn only`)
				end
			end
		end
	)

	t.test("the house and the tree keep apart, and nothing of the yard that collides reaches the games wing", function()
		local H = R.HOUSE
		local tr = R.TREE
		local gap = H.x0 - H.overhang - (tr.x + tr.trunkR)
		t.truthy(gap > 10, `the trunk stands {gap} from the house's eaves`)
		for _, b in boxes do
			if b.part.CanCollide then
				t.truthy(b.X - b.hx >= fp.x1, `{b.part.Name} collides inside the alley's footprint`)
			end
		end
	end)
end
