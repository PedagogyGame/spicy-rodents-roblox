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
-- The trail's pieces, its landings and benches and the dressing are laid out by Shared/Rides/LookoutHill (pure), which
-- World/WalkWay and AI/TownAI read too (the walkers' boxes and the trail as their ground); this draws them.
-- Interface: build(roblox, parent) -> Model; trailPieces() -> { Piece } (pure: the trail's pieces); constants

local AlleyLayout = require("../../../src/shared/Attractions/AlleyLayout")
local Common = require("./Common")
local Factory = require("../../../src/worldgen/Factory")
local Kit = require("../alley/Kit")
local LookoutHill = require("../../../src/shared/Rides/LookoutHill")
local Plan = require("../../../src/worldgen/Plan")
local Road = require("../../../src/worldgen/Builders/Road")

local Approach = {}

-- (the trail's numbers are Shared/Rides/LookoutHill's)
Approach.TRAIL_WIDTH = LookoutHill.TRAIL_WIDTH
Approach.LIFT = LookoutHill.LIFT -- a piece's top over the highest ground across its ends
Approach.THICK = LookoutHill.THICK
Approach.ROLL_MAX = LookoutHill.ROLL_MAX -- radians of cross-fall a piece follows (about 9 degrees)
Approach.BANK_DROP = LookoutHill.BANK_DROP -- a piece standing more than this over the ground at an edge gets a bank
Approach.DROP_RAIL = LookoutHill.DROP_RAIL -- ... and a rail on that edge past this
Approach.PIECE_MAX = LookoutHill.PIECE_MAX
Approach.PIECE_MIN = LookoutHill.PIECE_MIN
Approach.RAIL_GRADE = LookoutHill.RAIL_GRADE
Approach.STEP_GRADE = LookoutHill.STEP_GRADE
Approach.TOWER_CLEAR = LookoutHill.TOWER_CLEAR -- trail half-width, the footing's half-diagonal and a rail's width
Approach.TREES = LookoutHill.TREES
Approach.SIDEWALK_JOIN = -622.5 -- where the westside sidewalks (rd_072, rd_073) end
Approach.BUDGET = 600

export type Piece = LookoutHill.Piece

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

-- The trail's polyline, its pieces, the distance to its centre line, a venue's site (Shared/Rides/LookoutHill).
Approach.trailPoints = LookoutHill.trailPoints
Approach.trailPieces = LookoutHill.trailPieces
Approach.trailDistance = LookoutHill.trailDistance
Approach.inSite = LookoutHill.inSite

-- Lift Road's street lamps: one row on the verges, alternating sides, about 105 apart (side +1: the east verge,
-- the arm reaching west over the road). Pure.
function Approach.roadLamps(): { { x: number, z: number, side: number } }
	local road = record(Common.expansion().strips, "xs_lift_road")
	local verge = road.width / 2 + 1.6 -- between the kerb and the sidewalk (3.15 wide)
	local out = {}
	for _, e in { { road["end"] - 40, 1 }, { road["end"] - 145, -1 }, { road["end"] - 250, 1 } } do
		table.insert(out, { x = road.coord + e[2] * verge, z = e[1], side = e[2] })
	end
	return out
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
	for i, e in Approach.roadLamps() do
		lamp(kit0, lamps, `Lamp{i}`, e.x, e.z, -e.side, 0)
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
	for _, q in LookoutHill.landings() do
		local top, low = q.top, math.huge
		for k = 0, 7 do
			local ang = k * math.pi / 4
			low = math.min(low, ground(q.x + math.cos(ang) * (hw + 0.2), q.z + math.sin(ang) * (hw + 0.2)))
		end
		local bottom = math.min(low, top - Approach.THICK) - 0.6
		local d = LookoutHill.LANDING
		kit0:cyl(trail, "Landing", q.x, (top + bottom) / 2, -q.z, top - bottom, d, "Y", Common.GRAVEL, "Pebble")
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
	-- benches facing the town at three turns (LookoutHill.benches: beside the turn toward the town, off the trail),
	-- and two signposts
	local B = LookoutHill.BENCH
	for _, b in LookoutHill.benches() do
		local bk = Kit.new(roblox, { x = b.x, z = b.z, floorY = b.ground, yaw = b.yaw })
		local bm = bk:model(trail, b.name)
		bm.ModelStreamingMode = roblox.Enum.ModelStreamingMode.Atomic
		bk:box(bm, "Seat", B.x0, B.x1, 1.3, 1.6, -0.7, 0.7, Common.WOOD, "WoodPlanks")
		bk:box(bm, "Back", B.x0, B.x1, 1.9, B.top, B.d0, -0.75, Common.WOOD, "WoodPlanks")
		for _, sx in { -1.9, 1.9 } do
			bk:box(bm, "Leg", sx - 0.2, sx + 0.2, -0.8, 1.3, B.d0, 0.6, Common.FRAME, "Metal")
		end
	end
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

	-- the hill's dressing (LookoutHill.dressing: seeded, off the trail, the roads, the sites and the cabins' way)
	local dress = kit0:folder(m, "Dressing")
	local trees = 0
	for _, d in LookoutHill.dressing() do
		if d.kind == "conifer" then
			conifer(kit0, dress, d.x, d.z, d.h :: number, d.w :: number, d.tint :: number)
			trees += 1
		elseif d.kind == "rock" then
			local size, rot = d.size :: { number }, d.rot :: { number }
			kit0:at(dress, "Rock", d.x, d.y, -d.z, size[1], size[2], size[3], Common.ROCK, "Slate", {
				rot = CFrame.Angles(rot[1], rot[2], rot[3]),
			})
		else
			local size = (d.size :: { number })[1]
			kit0:ball(dress, "Shrub", d.x, d.y, -d.z, size, Common.SHRUB, "Grass", { collide = false, query = false })
		end
	end
	m:SetAttribute("Trees", trees)
	m:SetAttribute("TrailPieces", #pieces)
	return m
end

return Approach
