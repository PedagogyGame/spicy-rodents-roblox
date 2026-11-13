--!strict
-- tools/bake/skylift/Approach: the way to the sky lift and up Lookout Hill on foot (BATCH2 §1.1-1.2; "a walking
-- trail for those who will not ride"). Model xs_lift_approach (streaming Default: it is a kilometre long):
--   LiftRoad: Lift Road (xs_lift_road: asphalt 37.5 wide at x -722.5, z -905..-610, meeting the westside street's
--     end) and its two sidewalks (stopped at z -622.5, where the westside sidewalks end, so nothing overlaps),
--     from the compiled strips with WorldGen/Plan.road and Builders/Road, as the town's roads are;
--   CarPark: the pad (xp_lift_lot) the same way, with white bay lines on its surface (two rows of six bays along
--     the west and east edges, the aisle down the middle to the trailhead) and a parking sign;
--   FrontWalk: the 8-wide concrete walk from the foot of the station's front steps to the car park's corner;
--   Lamps: five street lamps in the town's pattern (one row, on the verges, alternating sides; one at the
--     trailhead), each an Atomic Model whose lit head carries a PointLight (attribute NightLight = true);
--   Trail: the hill trail (xpath_hill_trail) as gravel pieces at most PIECE_MAX long laid on World/Height (each
--     piece's ends LIFT over the highest ground across them, never under the ground, rolled to the cross slope up
--     to ROLL_MAX; where leg 5 crosses the hill's 30-degree north face the trail is a terrace on a stone bank,
--     its uphill edge on the slope), round landings at the turns, handrails where the grade passes RAIL_GRADE
--     and on the bank's drop past DROP_RAIL, timber steps where the grade passes STEP_GRADE, three benches facing
--     the town and two signposts;
--   Dressing: conifers, rocks and shrubs round the crown and along the line, seeded, never on the trail, the
--     roads, either venue's site or under the cabins.
-- Interface: build(roblox, parent) -> Model; trailPieces() -> { Piece } (pure: the trail's pieces); constants

local AlleyLayout = require("../../../src/shared/Attractions/AlleyLayout")
local Common = require("./Common")
local Factory = require("../../../src/worldgen/Factory")
local Kit = require("../alley/Kit")
local Plan = require("../../../src/worldgen/Plan")
local Road = require("../../../src/worldgen/Builders/Road")
local SkyLift = require("../../../src/shared/Rides/SkyLift")

local Approach = {}

Approach.TRAIL_WIDTH = 6
Approach.LIFT = 0.2 -- a piece's top over the highest ground across its ends
Approach.THICK = 1.2
Approach.ROLL_MAX = 0.15 -- radians of cross-fall a piece follows (about 9 degrees)
Approach.BANK_DROP = 0.9 -- a piece standing more than this over the ground at an edge gets a stone bank
Approach.DROP_RAIL = 2.5 -- ... and a rail on that edge past this
Approach.PIECE_MAX = 16
Approach.PIECE_MIN = 2
Approach.RAIL_GRADE = 0.35
Approach.STEP_GRADE = 0.42
Approach.SIDEWALK_JOIN = -622.5 -- where the westside sidewalks (rd_072, rd_073) end
Approach.BUDGET = 600
Approach.TREES = 32

export type Piece = {
	ax: number,
	az: number,
	ay: number, -- centre-line top at the start (LIFT over the highest ground across it)
	bx: number,
	bz: number,
	by: number,
	roll: number, -- about the piece's axis: + raises its right side
	grade: number, -- rise over run
	leg: number,
	drop: number, -- the most the piece's top stands over the ground under it
}

local function ground(x: number, z: number): number
	return Common.ground(x, z)
end

local function record(list: { any }, id: string): any
	for _, r in list do
		if r.id == id then
			return r
		end
	end
	error("skylift approach: no " .. id)
end

-- The trail's pieces. Each leg is cut into pieces of at most PIECE_MAX. A piece is rolled to the ground's cross
-- slope up to ROLL_MAX (a path you can walk), and its ends sit LIFT over the highest ground across it (CROSS
-- offsets): on a gentle slope that is the centre line; where the trail crosses the hill's steep face it is the
-- uphill edge, and the piece stands proud of the slope on its downhill side, built up on a stone bank (`drop`:
-- the most its edge stands over the ground). A piece the ground rises over anywhere between its ends is split at
-- its worst point, down to PIECE_MIN.
-- The trail's polyline: xpath_hill_trail's points, with a bend added wherever a leg passes within TOWER_CLEAR of a
-- line tower (towers 8 and 9 stand on the data's line): the new point stands TOWER_CLEAR + 1 from the tower, on
-- the side the leg passed it. The two ends are the data's.
Approach.TOWER_CLEAR = 8.5 -- trail half-width, the footing's half-diagonal and a rail's width
local pointsCache: { { number } }? = nil
function Approach.trailPoints(): { { number } }
	if pointsCache then
		return pointsCache
	end
	local P: { { number } } = {}
	for _, q in record(Common.expansion().paths, "xpath_hill_trail").points do
		table.insert(P, { q[1], q[2] })
	end
	for _ = 1, 8 do
		local moved = false
		for _, t in SkyLift.towers() do
			local best, bi, bx, bz = math.huge, 0, 0, 0
			for i = 1, #P - 1 do
				local a, b = P[i], P[i + 1]
				local dx, dz = b[1] - a[1], b[2] - a[2]
				local f = math.clamp(((t.x - a[1]) * dx + (t.z - a[2]) * dz) / (dx * dx + dz * dz), 0, 1)
				local qx, qz = a[1] + dx * f, a[2] + dz * f
				local d = math.sqrt((qx - t.x) ^ 2 + (qz - t.z) ^ 2)
				if d < best then
					best, bi, bx, bz = d, i, qx, qz
				end
			end
			if best < Approach.TOWER_CLEAR then
				local nx, nz = bx - t.x, bz - t.z
				if best < 0.01 then
					local a, b = P[bi], P[bi + 1]
					nx, nz = -(b[2] - a[2]), b[1] - a[1]
				end
				local nl = math.sqrt(nx * nx + nz * nz)
				local r = Approach.TOWER_CLEAR + 1
				table.insert(P, bi + 1, { t.x + nx / nl * r, t.z + nz / nl * r })
				moved = true
			end
		end
		if not moved then
			break
		end
	end
	pointsCache = P
	return P
end

local CROSS = { -1, -0.9, -0.5, 0, 0.5, 0.9, 1 } -- fractions of the half-width
local trailCache: { Piece }? = nil
function Approach.trailPieces(): { Piece }
	if trailCache then
		return trailCache
	end
	local P = Approach.trailPoints()
	local hw = Approach.TRAIL_WIDTH / 2
	local out: { Piece } = {}
	local function rollAt(x: number, z: number, ux: number, uz: number): number
		-- right of travel = (-uz, ux)
		local right = ground(x - uz * hw, z + ux * hw)
		local left = ground(x + uz * hw, z - ux * hw)
		return math.clamp(math.atan2(right - left, Approach.TRAIL_WIDTH), -Approach.ROLL_MAX, Approach.ROLL_MAX)
	end
	-- the centre top over (x, z) for a piece rolled `roll`: LIFT over the highest ground across it
	local function crossTop(x: number, z: number, ux: number, uz: number, roll: number): number
		local top = -math.huge
		for _, f in CROSS do
			local o = f * hw
			top = math.max(top, ground(x - uz * o, z + ux * o) - o * math.tan(roll))
		end
		return top + Approach.LIFT
	end
	-- the worst shortfall of the top under the ground between the ends: (gap, at f); and the largest drop
	local function survey(ax, az, ay, bx, bz, by, roll): (number, number, number)
		local dx, dz = bx - ax, bz - az
		local l = math.sqrt(dx * dx + dz * dz)
		local ux, uz = dx / l, dz / l
		local n = math.max(2, math.ceil(l / 0.5))
		local gap, at, drop = -math.huge, 0.5, 0
		for i = 0, n do
			local f = i / n
			local x, z = ax + dx * f, az + dz * f
			local top = ay + (by - ay) * f
			for _, c in CROSS do
				local o = c * hw
				local g = ground(x - uz * o, z + ux * o)
				local t = top + o * math.tan(roll)
				if i > 0 and i < n and g - t > gap then
					gap, at = g - t, f
				end
				drop = math.max(drop, t - g)
			end
		end
		return gap, at, drop
	end
	local function add(ax: number, az: number, bx: number, bz: number, leg: number)
		local dx, dz = bx - ax, bz - az
		local l = math.sqrt(dx * dx + dz * dz)
		local ux, uz = dx / l, dz / l
		local roll = rollAt((ax + bx) / 2, (az + bz) / 2, ux, uz)
		local ay, by = crossTop(ax, az, ux, uz, roll), crossTop(bx, bz, ux, uz, roll)
		local gap, at, drop = survey(ax, az, ay, bx, bz, by, roll)
		if gap > -0.02 and l > Approach.PIECE_MIN * 2 then
			at = math.clamp(at, Approach.PIECE_MIN / l, 1 - Approach.PIECE_MIN / l)
			local mx, mz = ax + dx * at, az + dz * at
			add(ax, az, mx, mz, leg)
			add(mx, mz, bx, bz, leg)
			return
		end
		table.insert(out, {
			ax = ax,
			az = az,
			ay = ay,
			bx = bx,
			bz = bz,
			by = by,
			roll = roll,
			grade = math.abs(by - ay) / l,
			leg = leg,
			drop = drop,
		})
	end
	for i = 1, #P - 1 do
		local a, b = P[i], P[i + 1]
		local l = math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2)
		local n = math.ceil(l / Approach.PIECE_MAX)
		for k = 0, n - 1 do
			local f0, f1 = k / n, (k + 1) / n
			add(
				a[1] + (b[1] - a[1]) * f0,
				a[2] + (b[2] - a[2]) * f0,
				a[1] + (b[1] - a[1]) * f1,
				a[2] + (b[2] - a[2]) * f1,
				i
			)
		end
	end
	trailCache = out
	return out
end

-- distance in plan from (x, z) to the trail's centre line
function Approach.trailDistance(x: number, z: number): number
	local best = math.huge
	for _, p in Approach.trailPieces() do
		local dx, dz = p.bx - p.ax, p.bz - p.az
		local l2 = dx * dx + dz * dz
		local f = math.clamp(((x - p.ax) * dx + (z - p.az) * dz) / l2, 0, 1)
		local ex, ez = p.ax + dx * f - x, p.az + dz * f - z
		best = math.min(best, math.sqrt(ex * ex + ez * ez))
	end
	return best
end

-- inside a venue's site (grown by `grow`)?
function Approach.inSite(x: number, z: number, grow: number): boolean
	for _, id in { "f4_lift_base", "f3_hilltop" } do
		local v = Common.venue(id)
		local X, _, D = AlleyLayout.toLocal(Common.place(v), x, 0, z)
		if X >= v.site.x0 - grow and X <= v.site.x1 + grow and D >= v.site.d0 - grow and D <= v.site.d1 + grow then
			return true
		end
	end
	return false
end

local function factoryOf(roblox: any): any
	return Factory.new({
		Instance = roblox.Instance,
		Vector3 = roblox.Vector3,
		CFrame = roblox.CFrame,
		Color3 = roblox.Color3,
		Enum = roblox.Enum,
		UDim2 = roblox.UDim2,
		ColorSequence = roblox.ColorSequence,
	})
end

-- the top of a Plan.road model's surface at (x, z): the segment under the point, its tilted top there
local function surfaceAt(roblox: any, model: any, x: number, z: number): number?
	for _, p in model:GetChildren() do
		if p:IsA("BasePart") and string.sub(p.Name, 1, 3) == "Seg" then
			local l = p.CFrame:Inverse() * roblox.Vector3.new(x, p.CFrame.Position.Y, z)
			if math.abs(l.X) <= p.Size.X / 2 + 0.01 and math.abs(l.Z) <= p.Size.Z / 2 + 0.01 then
				local top = p.CFrame * roblox.CFrame.new(l.X, p.Size.Y / 2, l.Z)
				return top.Position.Y
			end
		end
	end
	return nil
end

local function lamp(kit0: Kit.Kit, parent: any, name: string, x: number, z: number, ox: number, oz: number)
	local roblox = kit0.roblox
	local m = kit0:model(parent, name)
	m.ModelStreamingMode = roblox.Enum.ModelStreamingMode.Atomic
	local g = ground(x, z)
	local METAL = { 44, 48, 50 }
	local top = g + 15
	kit0:cyl(m, "Base", x, g + 0.2, -z, 1.4, 1.4, "Y", METAL, "Metal")
	kit0:cyl(m, "Post", x, (g + 0.9 + top) / 2, -z, top - g - 0.9, 0.84, "Y", METAL, "Metal")
	kit0:cyl(m, "Finial", x, top + 0.25, -z, 0.5, 0.5, "Y", METAL, "Metal", { collide = false, query = false })
	local p0 = { x, top - 0.9, z }
	local p1 = { p0[1] + ox * 1.3, p0[2] + 1.1, p0[3] + oz * 1.3 }
	local p2 = { p1[1] + ox * 1.8, p1[2] + 0.25, p1[3] + oz * 1.8 }
	local hx, hz = x + ox * 4.2, z + oz * 4.2
	local p3 = { hx, p2[2] - 0.55, hz }
	Common.rodW(kit0, m, "Arm", p0, p1, 0.3, METAL, "Metal")
	Common.rodW(kit0, m, "ArmB", p1, p2, 0.3, METAL, "Metal")
	Common.rodW(kit0, m, "ArmC", p2, p3, 0.3, METAL, "Metal")
	local yaw = math.atan2(-ox, -oz)
	kit0:at(m, "Housing", hx + ox * 0.3, p3[2] - 0.2, -(hz + oz * 0.3), 1.2, 0.5, 2.0, { 40, 44, 46 }, "Metal", {
		collide = false,
		query = false,
		rot = roblox.CFrame.Angles(0, yaw, 0),
	})
	local head = kit0:at(
		m,
		"Head",
		hx + ox * 0.3,
		p3[2] - 0.52,
		-(hz + oz * 0.3),
		0.9,
		0.16,
		1.5,
		{ 255, 228, 170 },
		"Neon",
		{
			collide = false,
			query = false,
			shadow = false,
			rot = roblox.CFrame.Angles(0, yaw, 0),
		}
	)
	head:SetAttribute("NightLight", true)
	kit0:light(head, "PointLight", { Range = 26, Brightness = 1.6, Color = { 242, 191, 115 }, Shadows = false })
	return m
end

-- a conifer: trunk and a crown of two crossed "tents" (four wedges), so it reads as a cone from every side
local function conifer(kit0: Kit.Kit, parent: any, x: number, z: number, h: number, w: number, tint: number)
	local roblox = kit0.roblox
	local g = ground(x, z)
	local m = kit0:model(parent, "Conifer")
	m.ModelStreamingMode = roblox.Enum.ModelStreamingMode.Atomic
	local trunkH = h * 0.22
	local trunkTop = g + trunkH + 1
	kit0:cyl(
		m,
		"Trunk",
		x,
		(g - 0.8 + trunkTop) / 2,
		-z,
		trunkTop - g + 0.8,
		math.max(0.6, w * 0.12),
		"Y",
		Common.BARK,
		"Wood"
	)
	local col = if tint > 0.5 then Common.PINE else Common.PINE_DARK
	local crownH = h - trunkH
	local cy = g + trunkH + crownH / 2
	for _, turn in { 0, math.pi / 2 } do
		for _, side in { 1, -1 } do
			-- a WedgePart's tall face is its +Z face (world (sin yaw, 0, cos yaw)): set it on the tree's axis, so the
			-- wedge's centre is w / 4 back along -Z from there
			local yaw = turn + (if side > 0 then 0 else math.pi)
			local ox, oz = math.sin(yaw) * w / 4, math.cos(yaw) * w / 4
			kit0:wedge(m, "Crown", x - ox, cy, -(z - oz), w * 0.62, crownH, w / 2, col, "Grass", {
				collide = false,
				query = false,
				rot = roblox.CFrame.Angles(0, yaw, 0),
			})
		end
	end
	return m
end

function Approach.build(roblox: any, parent: any): any
	local kit0 = Common.worldKit(roblox)
	local CFrame = roblox.CFrame
	local m = kit0:model(parent, "xs_lift_approach")
	m.ModelStreamingMode = roblox.Enum.ModelStreamingMode.Default
	m:SetAttribute("Family", Common.FAMILY)
	m:SetAttribute("PartBudget", Approach.BUDGET)
	local exp = Common.expansion()
	local factory = factoryOf(roblox)

	-- Lift Road and its sidewalks, the car park: the town's road builder on the compiled strips
	local roads = kit0:folder(m, "LiftRoad")
	local strips = {}
	for _, id in { "xs_lift_road", "xs_lift_road_sidewalk_a", "xs_lift_road_sidewalk_b" } do
		local s = table.clone(record(exp.strips, id))
		if s.kind == "concrete" then
			-- stop where the westside sidewalks end, so the two never overlap
			s["end"] = math.min(s["end"], Approach.SIDEWALK_JOIN)
		end
		table.insert(strips, s)
	end
	for _, s in strips do
		Road.build(Plan.road(s, strips), factory).Parent = roads
	end
	local lot = record(exp.pads, "xp_lift_lot").rect
	local park = kit0:folder(m, "CarPark")
	local padRoad = {
		id = "xp_lift_lot",
		kind = "asphalt",
		axis = "z",
		coord = (lot.x0 + lot.x1) / 2,
		start = lot.z0,
		["end"] = lot.z1,
		width = lot.x1 - lot.x0,
	}
	local pad = Road.build(Plan.road(padRoad :: any), factory)
	pad.Parent = park
	-- bay lines: two rows of six 9-wide, 18-deep bays along the west and east edges
	local line = { collide = false, query = false, shadow = false }
	for _, row in { { lot.x0, lot.x0 + 18 }, { lot.x1 - 18, lot.x1 } } do
		for k = 0, 6 do
			local z = lot.z1 - 3 - k * 9
			local y0 = surfaceAt(roblox, pad, row[1] + 0.5, z) or ground(row[1], z)
			local y1 = surfaceAt(roblox, pad, row[2] - 0.5, z) or ground(row[2], z)
			local a, b = { row[1] + 0.3, y0 + 0.03, z }, { row[2] - 0.3, y1 + 0.03, z }
			Common.boxW(kit0, park, "BayLine", a, b, 0.35, 0.05, { 236, 236, 230 }, "SmoothPlastic", line)
		end
	end
	-- the parking sign at the car park's north-east corner
	do
		local x, z = lot.x1 - 1.5, lot.z1 - 1.5
		local g = ground(x, z)
		kit0:box(park, "SignPost", x - 0.15, x + 0.15, g - 0.5, g + 8, -z - 0.15, -z + 0.15, Common.FRAME, "Metal")
		local board = kit0:box(
			park,
			"ParkingSign",
			x - 1.6,
			x + 1.6,
			g + 5.4,
			g + 8,
			-z + 0.15,
			-z + 0.3,
			{ 30, 70, 150 },
			"SmoothPlastic",
			{
				collide = false,
			}
		)
		for _, face in { "Front", "Back" } do
			local gui = kit0:gui(board, face, 40)
			kit0:label(gui, { Text = "P\nSKY LIFT", TextColor = { 255, 255, 255 }, Font = "GothamBlack" })
		end
	end

	-- the front walk: from the foot of the station's steps to the car park's corner
	do
		local baseV = Common.venue("f4_lift_base")
		local station = parent:FindFirstChild(baseV.id)
		local footD = if station then station:GetAttribute("StepsFootD") or -15 else -15
		local front = record(exp.paths, "xpath_lift_front")
		local doorX = -5
		for _, e in baseV.entrances do
			if e.id == "front" then
				doorX = e.at[1]
			end
		end
		local sx, _, sz = AlleyLayout.toWorld(Common.place(baseV), doorX, 0, footD)
		local e = front.points[#front.points]
		local walk = {
			id = "xpath_lift_front",
			kind = "concrete",
			axis = "free",
			start = { sx, sz },
			["end"] = { e[1], e[2] },
			width = front.width,
		}
		local wm = Road.build(Plan.road(walk :: any), factory)
		wm.Name = "FrontWalk"
		wm.Parent = m
	end

	-- lamps: one row on the verges, alternating sides, about 105 apart, and one at the trailhead
	local lamps = kit0:folder(m, "Lamps")
	local road = record(exp.strips, "xs_lift_road")
	local kerb = road.width / 2
	local verge = kerb + 1.6 -- between the kerb and the sidewalk (3.15 wide)
	local zs = { { road["end"] - 40, 1 }, { road["end"] - 145, -1 }, { road["end"] - 250, 1 } }
	for i, e in zs do
		local side = e[2]
		lamp(kit0, lamps, `Lamp{i}`, road.coord + side * verge, e[1], -side, 0)
	end
	lamp(kit0, lamps, "LampTrailhead", lot.x0 + 20, lot.z0 + 2.5, 0, 1)
	lamp(kit0, lamps, "LampStation", lot.x0 - 1.5, lot.z1 - 32, 1, 0)

	-- the hill trail
	local trail = kit0:folder(m, "Trail")
	local hw = Approach.TRAIL_WIDTH / 2
	local pieces = Approach.trailPieces()
	for i, p in ipairs(pieces) do
		local a = roblox.Vector3.new(p.ax, p.ay, p.az)
		local b = roblox.Vector3.new(p.bx, p.by, p.bz)
		local len = (b - a).Magnitude
		local frame = CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, 0, p.roll)
		local part = kit0:at(
			trail,
			string.format("Piece%03d", i),
			0,
			0,
			0,
			Approach.TRAIL_WIDTH,
			Approach.THICK,
			len + 0.3,
			Common.GRAVEL,
			"Pebble"
		)
		part.CFrame = frame * CFrame.new(0, -Approach.THICK / 2, 0)
		part:SetAttribute("Grade", math.floor(p.grade * 1000 + 0.5) / 1000)
		if p.drop > Approach.BANK_DROP then
			-- the stone bank the piece is built up on, down past the lowest ground under it
			local depth = p.drop + 1.2 - Approach.THICK + hw * math.abs(math.tan(p.roll))
			local bank = kit0:at(
				trail,
				"Bank",
				0,
				0,
				0,
				Approach.TRAIL_WIDTH - 0.1,
				depth,
				len + 0.3,
				Common.ROCK,
				"Cobblestone"
			)
			bank.CFrame = frame * CFrame.new(0, -Approach.THICK - depth / 2, 0)
		end
	end
	-- landings at the turns, level with the higher of the two pieces meeting there, built down to the ground
	local path = record(exp.paths, "xpath_hill_trail")
	local turns = Approach.trailPoints()
	for i = 2, #turns - 1 do
		local q = turns[i]
		local top, low = -math.huge, math.huge
		for _, p in pieces do
			if math.abs(p.bx - q[1]) < 1e-6 and math.abs(p.bz - q[2]) < 1e-6 then
				top = math.max(top, p.by)
			elseif math.abs(p.ax - q[1]) < 1e-6 and math.abs(p.az - q[2]) < 1e-6 then
				top = math.max(top, p.ay)
			end
		end
		for k = 0, 7 do
			local ang = k * math.pi / 4
			low = math.min(low, ground(q[1] + math.cos(ang) * (hw + 0.2), q[2] + math.sin(ang) * (hw + 0.2)))
		end
		top -= 0.03
		local bottom = math.min(low, top - Approach.THICK) - 0.6
		local d = Approach.TRAIL_WIDTH + 0.4
		kit0:cyl(trail, "Landing", q[1], (top + bottom) / 2, -q[2], top - bottom, d, "Y", Common.GRAVEL, "Pebble")
	end
	-- handrails where steep, timber steps where steeper
	local railPosts: { [string]: any } = {}
	local function post(x: number, z: number, topY: number): any
		local key = string.format("%.1f,%.1f", x, z)
		if railPosts[key] then
			return railPosts[key]
		end
		local g = ground(x, z)
		kit0:box(trail, "RailPost", x - 0.15, x + 0.15, g - 0.4, topY, -z - 0.15, -z + 0.15, Common.WOOD_DARK, "Wood")
		railPosts[key] = { x, topY, z }
		return railPosts[key]
	end
	for _, p in pieces do
		local dx, dz = p.bx - p.ax, p.bz - p.az
		local l = math.sqrt(dx * dx + dz * dz)
		local ux, uz = dx / l, dz / l
		-- both sides on the steep stretch; the downhill side where the trail stands high on its bank
		local sides = {}
		if p.grade > Approach.RAIL_GRADE then
			sides = { -1, 1 }
		elseif p.drop > Approach.DROP_RAIL then
			sides = { if p.roll > 0 then -1 else 1 }
		end
		do
			for _, side in sides do
				local o = side * (hw + 0.4)
				local ax, az = p.ax - uz * o, p.az + ux * o
				local bx, bz = p.bx - uz * o, p.bz + ux * o
				local ta = post(ax, az, p.ay + o * math.tan(p.roll) + 3.0)
				local tb = post(bx, bz, p.by + o * math.tan(p.roll) + 3.0)
				Common.rodW(
					kit0,
					trail,
					"Handrail",
					{ ta[1], ta[2] - 0.15, ta[3] },
					{ tb[1], tb[2] - 0.15, tb[3] },
					0.25,
					Common.WOOD,
					"Wood",
					{
						collide = true,
						query = true,
					}
				)
				Common.rodW(
					kit0,
					trail,
					"Midrail",
					{ ta[1], ta[2] - 1.6, ta[3] },
					{ tb[1], tb[2] - 1.6, tb[3] },
					0.2,
					Common.WOOD,
					"Wood"
				)
			end
			if p.grade > Approach.STEP_GRADE then
				local n = math.floor(l / 1.8)
				for k = 1, n do
					local f = (k - 0.5) / n
					local x, z = p.ax + dx * f, p.az + dz * f
					local y = p.ay + (p.by - p.ay) * f
					local ex, ez = -uz * (hw - 0.4), ux * (hw - 0.4)
					Common.rodW(
						kit0,
						trail,
						"StepLog",
						{ x - ex, y + 0.08 - (hw - 0.4) * math.tan(p.roll), z - ez },
						{ x + ex, y + 0.08 + (hw - 0.4) * math.tan(p.roll), z + ez },
						0.45,
						Common.WOOD_DARK,
						"Wood",
						{ collide = false, query = false }
					)
				end
			end
		end
	end
	-- benches facing the town at three turns, and two signposts
	local town = { 700, -150 }
	local function bench(name: string, q: { number }, out: number)
		-- beside the turn toward the town, stepped out until it is off the trail (bench 5 long: radius 2.6)
		local tx, tz = town[1] - q[1], town[2] - q[2]
		local tl = math.sqrt(tx * tx + tz * tz)
		tx, tz = tx / tl, tz / tl
		local x, z = q[1] + tx * out, q[2] + tz * out
		while Approach.trailDistance(x, z) < hw + 3 and out < 40 do
			out += 1
			x, z = q[1] + tx * out, q[2] + tz * out
		end
		local g = ground(x, z)
		local yaw = math.atan2(-tx, -tz)
		local bk = Kit.new(roblox, { x = x, z = z, floorY = g, yaw = yaw })
		local bm = bk:model(trail, name)
		bm.ModelStreamingMode = roblox.Enum.ModelStreamingMode.Atomic
		bk:box(bm, "Seat", -2.4, 2.4, 1.3, 1.6, -0.7, 0.7, Common.WOOD, "WoodPlanks")
		bk:box(bm, "Back", -2.4, 2.4, 1.9, 3.2, -0.95, -0.75, Common.WOOD, "WoodPlanks")
		for _, sx in { -1.9, 1.9 } do
			bk:box(bm, "Leg", sx - 0.2, sx + 0.2, -0.8, 1.3, -0.95, 0.6, Common.FRAME, "Metal")
		end
	end
	bench("BenchFoot", path.points[4], 6)
	bench("BenchTurn", path.points[6], 6.5)
	bench("BenchTop", path.points[7], 6)
	local function signpost(name: string, x: number, z: number, lines: { { any } })
		local g = ground(x, z)
		local sm = kit0:model(trail, name)
		sm.ModelStreamingMode = roblox.Enum.ModelStreamingMode.Atomic
		kit0:box(sm, "Post", x - 0.2, x + 0.2, g - 0.6, g + 8.4, -z - 0.2, -z + 0.2, Common.WOOD_DARK, "Wood")
		for i, l in lines do
			local text, dx, dz = l[1] :: string, l[2] :: number, l[3] :: number
			local yaw = math.atan2(-dz, dx)
			local y = g + 7.6 - (i - 1) * 1.3
			local bx, bz = x + dx * 1.7, z + dz * 1.7
			local board = kit0:at(sm, "Board", bx, y, -bz, 3.2, 1.0, 0.18, Common.CREAM, "Wood", {
				collide = false,
				query = false,
				rot = CFrame.Angles(0, yaw, 0),
			})
			for _, face in { "Front", "Back" } do
				local gui = kit0:gui(board, face, 40)
				kit0:label(gui, {
					Text = text,
					TextColor = Common.WOOD_DARK,
					Font = "GothamBold",
					Size = { 0.9, 0.7 },
					Pos = { 0.05, 0.15 },
				})
			end
		end
	end
	do
		local p1, p2 = path.points[1], path.points[2]
		local ux, uz = p2[1] - p1[1], p2[2] - p1[2]
		local l = math.sqrt(ux * ux + uz * uz)
		ux, uz = ux / l, uz / l
		signpost("SignTrailhead", p1[1] + 5, p1[2] - 3, {
			{ "THE LOOKOUT", ux, uz },
			{ "HILL TRAIL", ux, uz },
			{ "SKY LIFT", -1, 0.3 },
		})
		local q, n = path.points[6], path.points[7]
		local vx, vz = n[1] - q[1], n[2] - q[2]
		local vl = math.sqrt(vx * vx + vz * vz)
		local px, pz = path.points[5][1] - q[1], path.points[5][2] - q[2]
		local pl = math.sqrt(px * px + pz * pz)
		signpost("SignTurn", q[1] - 5, q[2] - 4, {
			{ "THE LOOKOUT", vx / vl, vz / vl },
			{ "LIFT ROAD", px / pl, pz / pl },
		})
	end

	-- the hill's dressing: seeded, off the trail, the roads, the sites and the cabins' way
	local dress = kit0:folder(m, "Dressing")
	local seed = 20261113
	local function rnd(): number
		seed = (seed * 1103515245 + 12345) % 2147483648
		return seed / 2147483648
	end
	local crown = { -1050, -1710 }
	local towardTown = { 0.751, 0.659 } -- the Lookout's front: keep the terrace's view clear
	local function ok(x: number, z: number, h: number, clearR: number): boolean
		if Approach.trailDistance(x, z) < hw + clearR + 1.5 then
			return false
		end
		if Approach.inSite(x, z, clearR + 3) then
			return false
		end
		for _, tw in SkyLift.towers() do
			if (tw.x - x) ^ 2 + (tw.z - z) ^ 2 < (5 + clearR) ^ 2 then
				return false -- the tower's footing
			end
		end
		if x > lot.x0 - 6 and x < lot.x1 + 6 and z > lot.z0 - 6 then
			return false -- the car park and Lift Road
		end
		local g = ground(x, z)
		for _, y in { g + 1, g + h * 0.5, g + h } do
			for _, o in { { 0, 0 }, { clearR, 0 }, { -clearR, 0 }, { 0, clearR }, { 0, -clearR } } do
				if not SkyLift.sweptClear(x + o[1], y, z + o[2], 1.5) then
					return false
				end
			end
		end
		-- not in front of the terrace, high on the slope, where a crown would block the view
		local dx, dz = x - crown[1], z - crown[2]
		local d = math.sqrt(dx * dx + dz * dz)
		if d < 260 and (dx * towardTown[1] + dz * towardTown[2]) / d > 0.6 and g + h > 100 then
			return false
		end
		return true
	end
	local trees, rocks, shrubs = 0, 0, 0
	local tries = 0
	-- conifers in small stands (a lone tree on a bare dome reads as a post from the town)
	while trees < Approach.TREES and tries < 400 do
		tries += 1
		local ang = rnd() * 2 * math.pi
		local r = 100 + rnd() * 240
		local cx, cz = crown[1] + math.cos(ang) * r, crown[2] + math.sin(ang) * r
		local stand = 2 + math.floor(rnd() * 4)
		for _ = 1, stand * 3 do
			if stand <= 0 or trees >= Approach.TREES then
				break
			end
			local a2, r2 = rnd() * 2 * math.pi, 4 + rnd() * 14
			local x, z = cx + math.cos(a2) * r2, cz + math.sin(a2) * r2
			local h = 15 + rnd() * 11
			local w = h * (0.4 + rnd() * 0.1)
			if ok(x, z, h, w / 2) then
				conifer(kit0, dress, x, z, h, w, rnd())
				trees += 1
				stand -= 1
			end
		end
	end
	tries = 0
	while rocks < 14 and tries < 2000 do
		tries += 1
		local ang = rnd() * 2 * math.pi
		local r = 60 + rnd() * 300
		local x, z = crown[1] + math.cos(ang) * r, crown[2] + math.sin(ang) * r
		local s = 2 + rnd() * 4
		if ok(x, z, s, s) then
			local g = ground(x, z)
			kit0:at(dress, "Rock", x, g + s * 0.2, -z, s * (1 + rnd() * 0.6), s * 0.75, s, Common.ROCK, "Slate", {
				rot = CFrame.Angles(rnd() * 0.4 - 0.2, rnd() * math.pi, rnd() * 0.4 - 0.2),
			})
			rocks += 1
		end
	end
	tries = 0
	while shrubs < 16 and tries < 2000 do
		tries += 1
		-- shrubs keep to the trail's sides and the foot of the hill
		local pieces2 = Approach.trailPieces()
		local p = pieces2[1 + math.floor(rnd() * #pieces2)]
		local side = if rnd() < 0.5 then -1 else 1
		local dx, dz = p.bx - p.ax, p.bz - p.az
		local l = math.sqrt(dx * dx + dz * dz)
		local o = side * (hw + 3 + rnd() * 6)
		local f = rnd()
		local x, z = p.ax + dx * f - dz / l * o, p.az + dz * f + dx / l * o
		local s = 2.2 + rnd() * 2
		if ok(x, z, s, s / 2) then
			local g = ground(x, z)
			kit0:ball(dress, "Shrub", x, g + s * 0.3, -z, s, Common.SHRUB, "Grass", { collide = false, query = false })
			shrubs += 1
		end
	end
	-- along the line: a rock and a shrub at the foot of each tower, where the mower cannot reach
	for _, tw in SkyLift.towers() do
		local c, s = math.cos(tw.yaw), math.sin(tw.yaw)
		local rx, rz = tw.x + c * 4.6 + s * 2.2, tw.z - s * 4.6 + c * 2.2
		local sx, sz = tw.x - c * 4.4 - s * 3.0, tw.z + s * 4.4 - c * 3.0
		if ok(rx, rz, 2, 1.5) then
			local r = 1.6 + rnd() * 1.4
			kit0:at(dress, "Rock", rx, ground(rx, rz) + r * 0.2, -rz, r * 1.4, r * 0.7, r, Common.ROCK, "Slate", {
				rot = CFrame.Angles(rnd() * 0.3, rnd() * math.pi, rnd() * 0.3),
			})
		end
		if ok(sx, sz, 3, 1.5) then
			local r = 2.4 + rnd() * 1.2
			kit0:ball(
				dress,
				"Shrub",
				sx,
				ground(sx, sz) + r * 0.3,
				-sz,
				r,
				Common.SHRUB,
				"Grass",
				{ collide = false, query = false }
			)
		end
	end
	m:SetAttribute("Trees", trees)
	m:SetAttribute("TrailPieces", #pieces)
	return m
end

return Approach
