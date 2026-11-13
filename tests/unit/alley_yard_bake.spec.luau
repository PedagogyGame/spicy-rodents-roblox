--!strict
-- The yard behind the bowling alley's games room as baked (tools/bake/alley/Yard; BRIEF_ADDENDUM D9, D10), built
-- in memory at the alley's place and held to the routes of Shared/Attractions/AlleyRoof:
--   * it stays in the alley's footprint or the yard annex, inside its part budget;
--   * what the squirrel runs on is drawn where the motor puts it: the downspout's pipe round route 9101; the
--     bough's TOP at the rail + 1.25 along 9105 with the rail inside the bark; the ridge cap's top on 9103; the
--     gutter route riding just over the north slope, and the body drawn on it (Routes/Motion.visualPose) and on the
--     ridge stands on the slates and the cap, not in the air;
--   * the trunk follows AlleyRoof.TREE.spine, tapering, the tree's only colliding part, with a baffle and no route;
--   * the roof slopes collide (a squirrel that misses the leap lands on them), the boughs and leaves do not;
--   * the leaf clumps keep a tunnel round every route and the leap's flight, so the squirrel stays in sight, and
--     they lie in the crown's envelope (AlleyRoof.TREE.crown), in several greens;
--   * THE GUARD'S VIEW: rays from the guard's eye on the planned platform (and its lookouts) to the squirrel's body
--     along the ridge, the leap and the bough, against the yard and the games wing's parapets: most get through;
--   * the leap's flight off the ridge passes through nothing solid; the way into the downspout is clear.
local roblox = require("@lune/roblox")
local AlleyLayout = require("@shared/Attractions/AlleyLayout")
local AlleyRoof = require("@shared/Attractions/AlleyRoof")
local Curve = require("@shared/Routes/Curve")
local Data = require("@shared/Data")
local Motion = require("@shared/Routes/Motion")
local Registry = require("@shared/Routes/Registry")
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
		-- (the plan's budget was about 120 for the house and 15 for a tree proxy; a part-built tree with a crown that
		-- reads as one needs about a hundred, until the meshed tree replaces it)
		t.truthy(house <= 170, `the house is {house} parts`)
		t.truthy(tree <= 105, `the tree is {tree} parts`)
		print(`      the house {house} parts (with its path, hedge and mailbox), the tree {tree}`)
		t.truthy(yard:FindFirstChild("Tree_AlleyYard") ~= nil, "the tree's model is named for ClientWorld")
		for i = 1, 5 do
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

	t.test("the trunk: on the spine, tapering, the tree's only colliding part, a baffle round it, no route", function()
		local T = R.TREE
		local spine = Curve.fromArrays(T.spine)
		for i = 0, 48 do
			local u = i / 48
			local q = spine:getPointAt(u)
			local s = world(q.x, q.y, q.z)
			local best, bestPart = math.huge, nil :: any
			for k = 1, 5 do
				local p = byName[`Trunk{k}`]
				local _, d, within = onAxis(p, s)
				if within and d < best then
					best, bestPart = d, p
				end
			end
			t.truthy(bestPart ~= nil and best <= 0.15, `the trunk's axis is {best} off the spine at {u}`)
			local _, _, _, radius = axisOf(bestPart)
			local want = T.trunkR + (T.forkR - T.trunkR) * u
			t.truthy(math.abs(radius - want) <= 0.15, `bark {radius} against {want} at {u}`)
		end
		for _, b in boxes do
			if b.model == "Tree_AlleyYard" and string.match(b.part.Name, "^Trunk%d$") == nil then
				t.truthy(not b.part.CanCollide and not b.part.CanQuery, `{b.part.Name} is drawn only`)
			end
		end
		local baffle = byName.Baffle
		t.near(baffle.Size.Y / 2, T.baffle.r, 0.01, "the baffle's rim")
		local _, by = AlleyLayout.toLocal(place, 0, baffle.CFrame.Position.Y, 0)
		t.truthy(by >= T.baffle.y0 and by <= T.baffle.y1, "the baffle sits where AlleyRoof says")
		for _, r in R.routes() do
			t.truthy(r.kind ~= "trunk" or r.id == 9101, `route {r.id} climbs something other than the downspout`)
		end
	end)

	t.test("the bough: its top is the squirrel's feet (rail + 1.25), the rail inside the bark", function()
		for _, id in { R.BOUGH } do
			for _, s in samples(id, 80) do
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
			-- the body as the client draws it (Motion.visualPose): on the gutter route and the ridge its feet stand on
			-- the slates and on the cap, within 0.3 (a bough's 1.25 lift would float it over the roof)
			local registry = Registry.fromRecords(R.records(place, alley.id) :: any)
			local slopeTop = R.HOUSE.eaveY + (R.HOUSE.ridgeY - R.HOUSE.eaveY) / (R.HOUSE.ridgeD - R.HOUSE.d0)
			local worst = 0
			for _, id in { 9102, 9103 } do
				local route = registry:get(id) :: Registry.Route
				for i = 0, 40 do
					local u = i / 40
					local pos = registry:pointAt(route, u)
					local feet = Motion.visualPose({ registry = registry } :: any, route, u, pos)
					local _, Y, D = AlleyLayout.toLocal(place, feet.x, feet.y, feet.z)
					local under = if id == 9103 then capTop else slopeTop
					if id == 9102 then
						if D <= R.HOUSE.d0 + 0.2 or D >= R.HOUSE.ridgeD - 0.6 then
							continue
						end
						under = R.HOUSE.eaveY
							+ (R.HOUSE.ridgeY - R.HOUSE.eaveY) * (D - R.HOUSE.d0) / (R.HOUSE.ridgeD - R.HOUSE.d0)
					end
					local gap = Y - under
					worst = math.max(worst, math.abs(gap))
					t.truthy(gap >= -0.05 and gap <= 0.3, `route {id} at t {u}: the drawn feet are {gap} over the roof`)
				end
			end
			local _ = slopeTop
			print(
				`      the drawn feet on the gutter and the ridge: at most {string.format("%.2f", worst)} off the roof`
			)
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
			for _, id in { 9101, 9102, 9103, R.BOUGH } do
				for _, s in samples(id, 60) do
					table.insert(keep, s.p + V3.new(0, if id == R.BOUGH then LIFT else 0, 0))
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
		end
	)

	t.test(
		"the crown: every clump in AlleyRoof.TREE.crown, in several greens, darker under, twigs and low limbs",
		function()
			local cr = R.TREE.crown
			local tones: { [number]: number } = {}
			local low, high = math.huge, -math.huge
			for _, c in Yard.LEAF_CLUMPS do
				local e = ((c[1] - cr.x) / cr.rx) ^ 2 + ((c[2] - cr.y) / cr.ry) ^ 2 + ((c[3] - cr.d) / cr.rd) ^ 2
				t.truthy(e <= 1 + 1e-6, `a clump at ({c[1]}, {c[2]}, {c[3]}) lies outside the crown's envelope`)
				t.truthy(c[4] <= cr.maxClump, `a clump {c[4]} across`)
				tones[c[5]] = (tones[c[5]] or 0) + 1
				low, high = math.min(low, c[2]), math.max(high, c[2])
			end
			local n, kinds = #Yard.LEAF_CLUMPS, 0
			for _ in tones do
				kinds += 1
			end
			t.truthy(n >= 30, `{n} clumps`)
			t.truthy(kinds >= 3, `{kinds} greens`)
			t.truthy((tones[1] or 0) >= 4, "a darker layer underneath")
			-- the crown starts low (the scaffold limbs' clumps), well under the trunk's top + 5
			t.truthy(low < R.TREE.spine[#R.TREE.spine][2] + 3, `the lowest clump at {low}`)
			local onTwigs = 0
			for i in Yard.TWIGS do
				local _, _, c = Yard.twig(i)
				for _, l in Yard.LEAF_CLUMPS do
					if
						math.abs(l[1] - c[1]) < 0.06
						and math.abs(l[2] - c[2]) < 0.06
						and math.abs(l[3] - c[3]) < 0.06
					then
						onTwigs += 1
					end
				end
			end
			local drawn = 0
			for i in Yard.TWIGS do
				if byName[`Twig{i}_1`] then
					drawn += 1
				end
			end
			t.truthy(onTwigs >= 2 and drawn == onTwigs, `{onTwigs} twigs carry their clump, {drawn} are drawn`)
			print(
				`      {n} clumps from {low} to {high} up, greens {tones[1] or 0}/{tones[2] or 0}/{tones[3] or 0}/{tones[4] or 0}`
			)
		end
	)

	-- THE GUARD'S VIEW: what blocks a look (the yard's drawn parts, and the games wing's parapets standing in for the
	-- alley bake: its east and back walls' tops, coping at Y 15.0)
	type Shape = { cf: any, inv: any, size: any, shape: string, name: string }
	local occluders: { Shape } = {}
	for _, b in boxes do
		local p = b.part
		if p.Transparency < 0.95 then
			local shape = if p:IsA("Part") then p.Shape.Name else "Block"
			table.insert(
				occluders,
				{ cf = p.CFrame, inv = p.CFrame:Inverse(), size = p.Size, shape = shape, name = p.Name }
			)
		end
	end
	do
		local w = R.WING_ROOF
		for _, box in
			{
				{ "WingEastParapet", w.x1, w.outerX1, w.d0, w.outerD1 },
				{ "WingBackParapet", w.x0, w.outerX1, w.d1, w.outerD1 },
			}
		do
			local x0, x1, d0, d1 = box[2], box[3], box[4], box[5]
			local c = world((x0 + x1) / 2, (w.y + w.copingY) / 2, (d0 + d1) / 2)
			local cf = roblox.CFrame.new(c)
			local size = V3.new(x1 - x0, w.copingY - w.y, d1 - d0)
			table.insert(occluders, { cf = cf, inv = cf:Inverse(), size = size, shape = "Block", name = box[1] })
		end
	end
	-- the first occluder a ray from `eye` meets before `target` (nil: it gets through)
	local function blocker(eye: any, target: any): string?
		local d = target - eye
		local len = d.Magnitude - 0.35
		local dir = d.Unit
		for _, o in occluders do
			local lo = o.inv * eye
			local ld = o.inv:VectorToObjectSpace(dir)
			local s = o.size
			if o.shape == "Ball" then
				local r = s.X / 2
				local bq = lo:Dot(ld)
				local disc = bq * bq - (lo:Dot(lo) - r * r)
				if disc >= 0 then
					local tt = -bq - math.sqrt(disc)
					if tt > 0 and tt < len then
						return o.name
					end
				end
			else
				local tmin, tmax = 0, len
				local O, Dv, Hh = { lo.X, lo.Y, lo.Z }, { ld.X, ld.Y, ld.Z }, { s.X / 2, s.Y / 2, s.Z / 2 }
				local hit = true
				for i = 1, 3 do
					if math.abs(Dv[i]) < 1e-9 then
						if math.abs(O[i]) > Hh[i] then
							hit = false
							break
						end
					else
						local t1, t2 = (-Hh[i] - O[i]) / Dv[i], (Hh[i] - O[i]) / Dv[i]
						if t1 > t2 then
							t1, t2 = t2, t1
						end
						tmin, tmax = math.max(tmin, t1), math.min(tmax, t2)
						if tmin > tmax then
							hit = false
							break
						end
					end
				end
				if hit and o.shape == "Cylinder" then
					-- inside the slab along the axis: does the line come within the radius there?
					hit = false
					local r = math.min(Hh[2], Hh[3])
					for k = 0, 24 do
						local tt = tmin + (tmax - tmin) * k / 24
						local y, z = O[2] + Dv[2] * tt, O[3] + Dv[3] * tt
						if y * y + z * z <= r * r then
							hit = true
							break
						end
					end
				end
				if hit then
					return o.name
				end
			end
		end
		return nil
	end

	t.test(
		"the guard's view: from the platform the ridge, the leap and the bough are in sight (80% or more)",
		function()
			local BODY = 0.85
			local targets: { [string]: { any } } = { ridge = {}, leap = {}, bough = {}, gutter = {}, downspout = {} }
			for _, s in samples(9103, 10) do
				table.insert(targets.ridge, s.p + V3.new(0, BODY, 0))
			end
			for _, s in samples(R.BOUGH, 20) do
				table.insert(targets.bough, s.p + V3.new(0, LIFT + BODY, 0))
			end
			for _, s in samples(9102, 6) do
				table.insert(targets.gutter, s.p + V3.new(0, BODY, 0))
			end
			for _, s in samples(9101, 6) do
				-- (the body on the pipe's north side)
				table.insert(targets.downspout, s.p + V3.new(0, 0, 0.8))
			end
			for _, path in flights() do
				for i = 3, 24, 3 do
					table.insert(targets.leap, path[i] + V3.new(0, BODY, 0))
				end
			end
			local rows = {}
			for k, e in R.guardEyes() do
				local eye = world(e[1], e[2], e[3])
				local seen: { [string]: number } = {}
				local cells = {}
				for _, name in { "ridge", "leap", "bough", "gutter", "downspout" } do
					local n = 0
					local by: { [string]: number } = {}
					for _, q in targets[name] do
						local who = blocker(eye, q)
						if who == nil then
							n += 1
						else
							by[who] = (by[who] or 0) + 1
						end
					end
					seen[name] = n / #targets[name]
					local blockers = {}
					for who, c in by do
						table.insert(blockers, `{who} x{c}`)
					end
					table.sort(blockers)
					table.insert(
						cells,
						`{name} {n}/{#targets[name]}{if #blockers > 0
							then " (" .. table.concat(blockers, ", ") .. ")"
							else ""}`
					)
				end
				table.insert(rows, `({e[1]}, D {e[3]}): {table.concat(cells, "; ")}`)
				if k == 1 then
					-- the guard at the louvre
					for _, name in { "ridge", "leap", "bough" } do
						t.truthy(seen[name] >= 0.8, `from the guard's spot the {name} is {seen[name] * 100}% in sight`)
					end
				else
					t.truthy(
						seen.leap >= 0.6 and seen.bough >= 0.6,
						`from the lookout ({e[1]}, D {e[3]}) the leap and the bough`
					)
				end
			end
			print(`      what a guard sees: {table.concat(rows, " | ")}`)
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
