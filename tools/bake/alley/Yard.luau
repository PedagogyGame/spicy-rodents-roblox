--!strict
-- tools/bake/alley/Yard: the yard behind the bowling alley's games room (BRIEF_ADDENDUM D9, D10: "climbing up on
-- to the roof of a house, then jumping to tree branch"): a plain two-storey house and the tree beside the games
-- wing, standing where the routes of Shared/Attractions/AlleyRoof are. Built in the alley's local frame with the
-- alley bake's Kit, as one Model "Yard" (the house, "House", and the tree, "Tree_AlleyYard": the client treats
-- its "Trunk*" parts as a round trunk). It stands outside the alley's footprint, in AlleyRoof.ANNEX.
--   House  a clapboard house (24 x 24, two storeys, gables west toward the tree and east, the ridge along X),
--          on a concrete plinth over the ground falling east; slate roof with a ridge cap, white rakes, fascia
--          and gutters, a brick chimney on the south slope, a porch and a red door on the north (street) side,
--          windows with white frames, sills and bars, green shutters on the street side; the downspout drawn
--          round route 9101 (by the north-east corner), with its brackets, kick-out and splash block.
--   Tree   a proxy of parts until the route-true tree art takes an authored tree: a tapered bark trunk on route
--          9104 (bark radius = the squirrel's tapered radius, as the town's trees), the house bough on 9105 and
--          the roof crossing on 9106 (the bough's TOP is the squirrel's feet, rail + 1.25, as the town's), a
--          leader and three side limbs, and leaf clumps kept clear of every route so a squirrel stays visible.
--          Only the trunk collides; the boughs and leaves neither collide nor take queries.
-- NOT built into build/Attractions.rbxm yet: the alley's footprint, its bake spec and the expansion check know
-- nothing of the annex (tools/review/alley_roof.luau bakes it for the review pictures).
-- Interface: build(kit, root) -> Model; HOUSE_COLORS; CROWN; LEAF_CLUMPS (local {X, Y, D, diameter}); keepOut() ->
--   { {X, Y, D} }; boughRadius(id, t)
local AlleyRoof = require("../../../src/shared/Attractions/AlleyRoof")
local Curve = require("../../../src/shared/Routes/Curve")
local SquirrelMotor = require("../../../src/shared/Movement/SquirrelMotor")

local Yard = {}

local SIDING = { 205, 196, 160 } -- buttercream clapboard
local TRIM = { 241, 238, 228 }
local ROOF = { 74, 76, 84 }
local SHUTTER = { 56, 86, 66 }
local DOOR = { 148, 44, 40 }
local PLINTH = { 150, 147, 138 }
local BRICK = { 138, 72, 54 }
local GLASS = { 58, 74, 88 }
local PIPE = { 228, 228, 222 }
local BARK = { 94, 72, 54 }
local BARK_LIGHT = { 112, 88, 66 }
local LEAF = { 82, 124, 58 }
local LEAF_DARK = { 64, 104, 48 }

Yard.HOUSE_COLORS = { siding = SIDING, trim = TRIM, roof = ROOF }

local H = AlleyRoof.HOUSE
local ROOF_SLOPE = (H.ridgeY - H.eaveY) / (H.ridgeD - H.d0) -- 0.7: 35 degrees
local ROOF_T = 0.35
local LIFT = 1.25 -- Motion.C.visualBranchLift: the top of a bough is the squirrel's feet

local NOQUERY = { collide = false, query = false }
local DRESS = { collide = false }

-- Where a route's line is at t (arc length), in the local frame.
local function curveOf(id: number): Curve.Curve
	return Curve.fromArrays(AlleyRoof.route(id).points)
end

-- What the leaves keep clear of (local points): every route of the way up (a bough's at the squirrel's feet), and
-- the leap's flight off the ridge's west end, with no key held and with W (the motor's numbers).
function Yard.keepOut(): { { number } }
	local out = {}
	for _, id in { 9101, 9102, 9103, 9104, 9105, 9106 } do
		local c = curveOf(id)
		local n = math.ceil(c:getLength() / 0.75)
		local lift = if id == 9105 or id == 9106 then LIFT else 0
		for k = 0, n do
			local p = c:getPointAt(k / n)
			table.insert(out, { p.x, p.y + lift, p.z })
		end
	end
	local P = SquirrelMotor.params
	local e = AlleyRoof.route(9103).points[2]
	for _, held in { false, true } do
		local X, Y, vx, vy = e[1], e[2], -P.leapForward, P.leapUp
		for _ = 1, 40 do
			local dt = 1 / 60
			if held then
				vx += (-SquirrelMotor.V54.walk - vx) * (1 - math.exp(-dt * P.accelAir))
			else
				vx *= math.exp(-dt * P.dragAir)
			end
			vy -= P.gravity * dt
			X += vx * dt
			Y += vy * dt
			table.insert(out, { X, Y, e[3] })
		end
	end
	return out
end

-- The crown: leaf clumps {X, Y, D, diameter} scattered (a fixed seed) through a broad ellipsoid over the fork that
-- reaches over the games wing's parapet and toward the house, each at least TUNNEL from everything in keepOut() so
-- a squirrel on a route or in the leap stays in sight, and inside the annex (and the footprint beside it).
local TUNNEL = 2.4
Yard.CROWN = { x = 163, y = 31, d = 33, rx = 19, ry = 9, rd = 14, count = 26 }
Yard.LEAF_CLUMPS = (function(): { { number } }
	local keep = Yard.keepOut()
	local cr = Yard.CROWN
	local seed = 20261113
	local function rand(): number
		seed = (seed * 1103515245 + 12345) % 2147483648
		return seed / 2147483648
	end
	local clumps: { { number } } = {}
	for _ = 1, 3000 do
		if #clumps >= cr.count then
			break
		end
		local X = cr.x + (2 * rand() - 1) * cr.rx
		local Y = cr.y + (2 * rand() - 1) * cr.ry
		local D = cr.d + (2 * rand() - 1) * cr.rd
		local size = 7 + 5 * rand()
		local e = ((X - cr.x) / cr.rx) ^ 2 + ((Y - cr.y) / cr.ry) ^ 2 + ((D - cr.d) / cr.rd) ^ 2
		if e > 1 or D + size / 2 > AlleyRoof.ANNEX.d1 or X + size / 2 > H.x0 - 1 then
			continue
		end
		local ok = true
		for _, q in keep do
			local dx, dy, dd = q[1] - X, q[2] - Y, q[3] - D
			if math.sqrt(dx * dx + dy * dy + dd * dd) - size / 2 < TUNNEL then
				ok = false
				break
			end
		end
		-- spread out: overlapping, but not one inside another
		for _, c in clumps do
			if math.sqrt((c[1] - X) ^ 2 + (c[2] - Y) ^ 2 + (c[3] - D) ^ 2) < 0.6 * (c[4] + size) / 2 then
				ok = false
				break
			end
		end
		if ok then
			table.insert(
				clumps,
				{
					math.floor(X * 10 + 0.5) / 10,
					math.floor(Y * 10 + 0.5) / 10,
					math.floor(D * 10 + 0.5) / 10,
					math.floor(size * 10 + 0.5) / 10,
				}
			)
		end
	end
	return clumps
end)()

-- The bark's radius of a bough at t: thicker at the fork.
function Yard.boughRadius(id: number, t: number): number
	if id == 9105 then
		return 0.9 - 0.25 * t
	end
	return 0.85 - 0.2 * t
end

-- the roof's top surface over the north (d < ridge) or south slope
local function roofTop(d: number): number
	local dd = if d <= H.ridgeD then d - H.d0 else H.d1 - d
	return H.eaveY + ROOF_SLOPE * dd
end

-- A flat board across local X (x0..x1) whose TOP face runs along the line (ya, da) -> (yb, db).
local function board(
	kit: any,
	parent: any,
	name: string,
	x0: number,
	x1: number,
	ya: number,
	da: number,
	yb: number,
	db: number,
	thick: number,
	color: { number },
	material: string,
	opts: any?
): any
	local r = kit.roblox
	local xm = (x0 + x1) / 2
	local a = kit:cf(xm, ya, da).Position
	local b = kit:cf(xm, yb, db).Position
	local along = (b - a).Unit
	local right = kit:cf(0, 0, 0).XVector
	local up = along:Cross(right)
	if up.Y < 0 then
		right = -right
		up = -up
	end
	local p = kit:at(parent, name, 0, 0, 0, math.abs(x1 - x0), thick, (b - a).Magnitude, color, material, opts)
	p.CFrame = r.CFrame.fromMatrix((a + b) / 2 - up * (thick / 2), right, up)
	return p
end

-- A box on one face of the house, `out0`..`out1` proud of it: face "N" (D = d0), "S" (D = d1), "W" (X = x0),
-- "E" (X = x1); u runs along the face (X on N and S, D on W and E).
local function onFace(
	kit: any,
	parent: any,
	name: string,
	face: string,
	u0: number,
	u1: number,
	y0: number,
	y1: number,
	out0: number,
	out1: number,
	color: { number },
	material: string,
	opts: any?
): any
	if face == "N" then
		return kit:box(parent, name, u0, u1, y0, y1, H.d0 - out1, H.d0 - out0, color, material, opts)
	elseif face == "S" then
		return kit:box(parent, name, u0, u1, y0, y1, H.d1 + out0, H.d1 + out1, color, material, opts)
	elseif face == "W" then
		return kit:box(parent, name, H.x0 - out1, H.x0 - out0, y0, y1, u0, u1, color, material, opts)
	end
	return kit:box(parent, name, H.x1 + out0, H.x1 + out1, y0, y1, u0, u1, color, material, opts)
end

local function window(kit: any, m: any, face: string, u: number, y0: number, w: number, h: number, shutters: boolean)
	local tag = `{face}{math.floor(u)}_{math.floor(y0 + 10)}`
	onFace(
		kit,
		m,
		"WinFrame" .. tag,
		face,
		u - w / 2 - 0.25,
		u + w / 2 + 0.25,
		y0 - 0.25,
		y0 + h + 0.25,
		0,
		0.12,
		TRIM,
		"SmoothPlastic",
		DRESS
	)
	onFace(kit, m, "WinGlass" .. tag, face, u - w / 2, u + w / 2, y0, y0 + h, 0, 0.16, GLASS, "Glass", DRESS)
	onFace(kit, m, "WinBar" .. tag, face, u - 0.07, u + 0.07, y0, y0 + h, 0, 0.2, TRIM, "SmoothPlastic", DRESS)
	onFace(
		kit,
		m,
		"WinSill" .. tag,
		face,
		u - w / 2 - 0.45,
		u + w / 2 + 0.45,
		y0 - 0.45,
		y0 - 0.22,
		0,
		0.32,
		TRIM,
		"SmoothPlastic",
		DRESS
	)
	if shutters then
		for _, side in { -1, 1 } do
			local inner = u + side * (w / 2 + 0.3)
			local outer = u + side * (w / 2 + 0.3 + w * 0.45)
			onFace(
				kit,
				m,
				"Shutter" .. tag .. (if side < 0 then "L" else "R"),
				face,
				math.min(inner, outer),
				math.max(inner, outer),
				y0 - 0.15,
				y0 + h + 0.15,
				0,
				0.14,
				SHUTTER,
				"WoodPlanks",
				DRESS
			)
		end
	end
end

local function house(kit: any, yard: any): any
	local m = kit:model(yard, "House")
	local ov = H.overhang
	-- plinth over the falling ground, the clapboard body, the attic between the gables
	kit:box(m, "Plinth", H.x0 - 0.2, H.x1 + 0.2, H.floorY - 3.6, H.floorY, H.d0 - 0.2, H.d1 + 0.2, PLINTH, "Concrete")
	kit:box(m, "Body", H.x0, H.x1, H.floorY, H.eaveY, H.d0, H.d1, SIDING, "WoodPlanks")
	local half = H.ridgeD - H.d0
	local apex = H.ridgeY - ROOF_T * 1.3 - H.eaveY
	-- (a WedgePart's tall side is its +Z face, local -D: the south half as it comes, the north half turned round)
	kit:wedge(
		m,
		"AtticN",
		(H.x0 + H.x1) / 2,
		H.eaveY + apex / 2,
		H.d0 + half / 2,
		H.x1 - H.x0,
		apex,
		half,
		SIDING,
		"WoodPlanks",
		{
			rot = kit.roblox.CFrame.Angles(0, math.pi, 0),
		}
	)
	kit:wedge(
		m,
		"AtticS",
		(H.x0 + H.x1) / 2,
		H.eaveY + apex / 2,
		H.ridgeD + half / 2,
		H.x1 - H.x0,
		apex,
		half,
		SIDING,
		"WoodPlanks"
	)
	-- the roof: two slopes, the ridge cap (its top is the ridge route), the rakes on the gables, fascia, gutters
	local x0, x1 = H.x0 - ov, H.x1 + ov
	local dN, dS = H.d0 - ov, H.d1 + ov
	board(kit, m, "RoofN", x0, x1, roofTop(H.d0) - ROOF_SLOPE * ov, dN, H.ridgeY, H.ridgeD, ROOF_T, ROOF, "Slate")
	board(kit, m, "RoofS", x0, x1, H.ridgeY, H.ridgeD, roofTop(H.d1) - ROOF_SLOPE * ov, dS, ROOF_T, ROOF, "Slate")
	local ridge = AlleyRoof.route(9103).points
	kit:box(
		m,
		"RidgeCap",
		x0,
		x1,
		H.ridgeY - 0.2,
		ridge[1][2],
		H.ridgeD - 0.45,
		H.ridgeD + 0.45,
		{ 60, 62, 68 },
		"Slate"
	)
	for _, side in { { x0 - 0.25, x0, "W" }, { x1, x1 + 0.25, "E" } } do
		local a, b = side[1], side[2]
		board(
			kit,
			m,
			"Rake" .. side[3] .. "N",
			a,
			b,
			roofTop(H.d0) - ROOF_SLOPE * ov + 0.06,
			dN,
			H.ridgeY + 0.06,
			H.ridgeD,
			0.75,
			TRIM,
			"SmoothPlastic",
			DRESS
		)
		board(
			kit,
			m,
			"Rake" .. side[3] .. "S",
			a,
			b,
			H.ridgeY + 0.06,
			H.ridgeD,
			roofTop(H.d1) - ROOF_SLOPE * ov + 0.06,
			dS,
			0.75,
			TRIM,
			"SmoothPlastic",
			DRESS
		)
	end
	local eaveEdge = H.eaveY - ROOF_SLOPE * ov
	kit:box(m, "FasciaN", x0, x1, eaveEdge - 0.65, eaveEdge - 0.05, dN - 0.12, dN, TRIM, "SmoothPlastic", DRESS)
	kit:box(m, "FasciaS", x0, x1, eaveEdge - 0.65, eaveEdge - 0.05, dS, dS + 0.12, TRIM, "SmoothPlastic", DRESS)
	kit:box(m, "GutterN", x0, x1, eaveEdge - 0.55, eaveEdge - 0.05, dN - 0.62, dN - 0.12, PIPE, "SmoothPlastic", DRESS)
	kit:box(m, "GutterS", x0, x1, eaveEdge - 0.55, eaveEdge - 0.05, dS + 0.12, dS + 0.62, PIPE, "SmoothPlastic", DRESS)
	-- trim: corner boards and the band between the storeys
	for _, c in { { H.x0, H.d0 }, { H.x1, H.d0 }, { H.x0, H.d1 }, { H.x1, H.d1 } } do
		kit:box(
			m,
			"CornerBoard",
			c[1] - 0.3,
			c[1] + 0.3,
			H.floorY,
			H.eaveY - 0.1,
			c[2] - 0.3,
			c[2] + 0.3,
			TRIM,
			"SmoothPlastic"
		)
	end
	for _, f in { "N", "S" } do
		onFace(kit, m, "Band" .. f, f, H.x0, H.x1, -0.05, 0.3, 0, 0.1, TRIM, "SmoothPlastic", DRESS)
	end
	for _, f in { "W", "E" } do
		onFace(kit, m, "Band" .. f, f, H.d0, H.d1, -0.05, 0.3, 0, 0.1, TRIM, "SmoothPlastic", DRESS)
	end
	-- the chimney, through the south slope
	kit:box(m, "Chimney", 197, 199.2, 7.5, 19.4, 23.2, 25.4, BRICK, "Brick")
	kit:box(m, "ChimneyCap", 196.8, 199.4, 19.4, 19.7, 23.0, 25.6, { 120, 118, 112 }, "Concrete")
	-- windows: street side with shutters, back, and the two gables (the attic's small window too)
	local W, WH = 2.6, 3.6
	for _, u in { 189, 203 } do
		window(kit, m, "N", u, -5.9, W, WH, true)
		window(kit, m, "S", u, -5.9, W, WH, false)
	end
	window(kit, m, "S", 196, -5.9, W, WH, false)
	for _, u in { 189, 196, 203 } do
		window(kit, m, "N", u, 2.4, W, WH, true)
		window(kit, m, "S", u, 2.4, W, WH, false)
	end
	for _, f in { "W", "E" } do
		for _, u in { 13.5, 26.5 } do
			window(kit, m, f, u, -5.9, W, WH, false)
			window(kit, m, f, u, 2.4, W, WH, false)
		end
		window(kit, m, f, H.ridgeD, 10.2, 1.6, 2.2, false)
	end
	-- the front door and its porch
	onFace(kit, m, "DoorFrame", "N", 194.6, 197.8, H.floorY, -1.2, 0, 0.12, TRIM, "SmoothPlastic", DRESS)
	onFace(kit, m, "Door", "N", 195.0, 197.4, H.floorY, -1.6, 0, 0.18, DOOR, "WoodPlanks", DRESS)
	onFace(kit, m, "DoorKnob", "N", 196.9, 197.1, -4.7, -4.5, 0, 0.32, { 196, 168, 92 }, "Metal", DRESS)
	kit:box(m, "PorchDeck", 192.6, 199.8, H.floorY - 3.4, H.floorY - 0.1, H.d0 - 3.2, H.d0, PLINTH, "Concrete")
	kit:box(m, "PorchStep", 194.2, 198.2, H.floorY - 3.4, H.floorY - 1.0, H.d0 - 4.0, H.d0 - 3.2, PLINTH, "Concrete")
	for _, x in { 193.0, 199.4 } do
		kit:cyl(
			m,
			"PorchPost",
			x,
			(H.floorY - 0.1 - 0.3) / 2,
			H.d0 - 2.85,
			H.floorY * -1 - 0.2,
			0.36,
			"Y",
			TRIM,
			"SmoothPlastic",
			DRESS
		)
	end
	board(kit, m, "PorchRoof", 192.3, 200.1, 0.9, H.d0, -0.2, H.d0 - 3.4, 0.3, ROOF, "Slate", DRESS)
	-- the downspout, round route 9101: the pipe on the route's line, brackets to the wall, a kick-out and a splash
	-- block at its foot, an offset into the gutter at its head
	local spout = AlleyRoof.route(9101)
	local foot, head = spout.points[1], spout.points[#spout.points]
	local r = spout.surfaceRadius
	local top = eaveEdge - 0.5
	kit:cyl(
		m,
		"Downspout",
		foot[1],
		(foot[2] + 0.5 + top) / 2,
		foot[3],
		top - foot[2] - 0.5,
		2 * r,
		"Y",
		PIPE,
		"SmoothPlastic",
		DRESS
	)
	kit:rod(
		m,
		"DownspoutHead",
		head[1],
		top,
		head[3],
		head[1],
		eaveEdge - 0.2,
		dN - 0.37,
		2 * r,
		PIPE,
		"SmoothPlastic",
		DRESS
	)
	kit:rod(
		m,
		"DownspoutKick",
		foot[1],
		foot[2] + 0.75,
		foot[3],
		foot[1],
		foot[2] + 0.2,
		foot[3] - 1.1,
		2 * r,
		PIPE,
		"SmoothPlastic",
		DRESS
	)
	kit:box(
		m,
		"SplashBlock",
		foot[1] - 0.6,
		foot[1] + 0.6,
		foot[2] - 0.45,
		foot[2] - 0.25,
		foot[3] - 2.6,
		foot[3] - 0.9,
		PLINTH,
		"Concrete",
		DRESS
	)
	for _, y in { -6.5, 0.6, 6.4 } do
		kit:box(
			m,
			"DownspoutBracket",
			foot[1] - 0.45,
			foot[1] + 0.45,
			y - 0.1,
			y + 0.1,
			foot[3],
			H.d0,
			PIPE,
			"Metal",
			DRESS
		)
	end
	return m
end

-- a chain of cylinders through points (with balls at the joints so the bends are round)
local function limb(
	kit: any,
	m: any,
	name: string,
	pts: { { number } },
	radii: { number },
	color: { number },
	opts: any
)
	for i = 1, #pts - 1 do
		local a, b = pts[i], pts[i + 1]
		local rr = (radii[i] + radii[i + 1]) / 2
		kit:rod(m, `{name}_{i}`, a[1], a[2], a[3], b[1], b[2], b[3], 2 * rr, color, "Wood", opts)
		if i > 1 then
			kit:ball(m, `{name}_J{i}`, a[1], a[2], a[3], 2 * radii[i], color, "Wood", opts)
		end
	end
end

local function tree(kit: any, yard: any): any
	local m = kit:model(yard, "Tree_AlleyYard")
	-- the trunk: the squirrel's tapered radius r(1 - 0.48 t), at least 0.8 (Routes/Motion.visualPose)
	local trunk = AlleyRoof.route(9104)
	local tc = curveOf(9104)
	local rT = trunk.surfaceRadius
	local function tapered(t: number): number
		return math.max(0.8, rT * (1 - 0.48 * t))
	end
	local N = 6
	for i = 1, N do
		local u0, u1 = (i - 1) / N, i / N
		local a, b = tc:getPointAt(u0), tc:getPointAt(u1)
		kit:rod(
			m,
			`Trunk{i}`,
			a.x,
			a.y,
			a.z,
			b.x,
			b.y,
			b.z,
			2 * tapered((u0 + u1) / 2),
			BARK,
			"Wood",
			{ collide = true }
		)
	end
	-- the root flare (below the route's foot) and the leader above the fork
	local base = tc:getPointAt(0)
	kit:cyl(m, "TrunkFlare", base.x, base.y - 0.1, base.z, 1.2, 2 * rT + 0.9, "Y", BARK, "Wood")
	local fork = tc:getPointAt(1)
	limb(kit, m, "Leader", {
		{ fork.x, fork.y - 0.5, fork.z },
		{ fork.x - 0.6, fork.y + 7, fork.z + 0.8 },
		{ fork.x - 0.3, fork.y + 14, fork.z + 0.5 },
		{ fork.x + 0.4, fork.y + 19, fork.z - 0.4 },
	}, { 0.85, 0.7, 0.5, 0.3 }, BARK, NOQUERY)
	-- the two boughs the squirrel runs: the bough's top at the rail + 1.25
	for _, id in { 9105, 9106 } do
		local c = curveOf(id)
		local pts, radii = {}, {}
		local S = 9
		for i = 0, S do
			local u = i / S
			local p = c:getPointAt(u)
			local rr = Yard.boughRadius(id, u)
			table.insert(pts, { p.x, p.y + LIFT - rr, p.z })
			table.insert(radii, rr)
		end
		limb(kit, m, `Bough{id}`, pts, radii, BARK_LIGHT, NOQUERY)
	end
	-- three side limbs that carry the crown (south, east and west), none on a route
	limb(kit, m, "LimbS", {
		{ fork.x, fork.y + 1, fork.z },
		{ fork.x - 1, fork.y + 5, fork.z + 5 },
		{ fork.x - 2, fork.y + 9, fork.z + 10 },
	}, { 0.7, 0.5, 0.3 }, BARK, NOQUERY)
	limb(kit, m, "LimbE", {
		{ fork.x, fork.y + 3, fork.z },
		{ fork.x + 5, fork.y + 7, fork.z + 3 },
		{ fork.x + 10, fork.y + 10, fork.z + 6 },
	}, { 0.6, 0.45, 0.3 }, BARK, NOQUERY)
	limb(kit, m, "LimbW", {
		{ fork.x, fork.y + 4, fork.z },
		{ fork.x - 5, fork.y + 8, fork.z - 1 },
		{ fork.x - 9, fork.y + 12, fork.z - 4 },
	}, { 0.55, 0.4, 0.28 }, BARK, NOQUERY)
	-- the crown
	for i, c in Yard.LEAF_CLUMPS do
		kit:ball(m, `Leaves{i}`, c[1], c[2], c[3], c[4], if i % 3 == 0 then LEAF_DARK else LEAF, "LeafyGrass", NOQUERY)
	end
	return m
end

-- build(kit, root): the Model "Yard" under root (the alley's Kit: its place puts it beside the games wing).
function Yard.build(kit: any, root: any): any
	local yard = kit:model(root, "Yard")
	house(kit, yard)
	tree(kit, yard)
	return yard
end

return Yard
