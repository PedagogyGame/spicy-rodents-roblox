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
--          round route 9101 (by the north-east corner), with its brackets, kick-out and splash block. Its setting:
--          a flagstone path from the porch west to the walk beside the games wing, a mailbox where they meet, a
--          hedge along the yard's east and south sides.
--   Tree   a proxy of parts until the route-true tree art takes an authored tree: a tapered bark trunk on
--          AlleyRoof.TREE.spine (no route climbs it: owner question Q11's default) with a root flare and a
--          sheet-metal squirrel baffle round it, a leader and limbs (three low scaffold limbs, three from the top),
--          and one long limb drawn on route 9105 (the house bough down to the trunk's top, then the roof crossing:
--          its TOP is the squirrel's feet, rail + 1.25, as the town's boughs) with a thinner tip on past its house
--          end. Leaf clumps in four greens (darker underneath) fill AlleyRoof.TREE.crown, kept clear of every
--          route and the leap so a squirrel stays in sight, and of the guard's lines of sight from the platform to
--          the ridge, the leap and the bough (AlleyRoof.guardEyes). Only the trunk collides; the rest neither
--          collides nor takes queries.
-- NOT built into build/Attractions.rbxm yet: the alley's footprint, its bake spec and the expansion check know
-- nothing of the annex (tools/review/alley_roof.luau bakes it for the review pictures).
-- Interface: build(kit, root) -> Model; HOUSE_COLORS; LEAF_TONES; CROWN (= AlleyRoof.TREE.crown); LEAF_CLUMPS
--   (local {X, Y, D, diameter, tone}); keepOut() -> { {X, Y, D} }; sightLines() -> { { a, b } } (local points);
--   TWIGS; twig(i) -> (foot, tip, clump centre, clump diameter); boughRadius(t); BOUGH_TIP; LOW_LIMBS
local AlleyRoof = require("../../../src/shared/Attractions/AlleyRoof")
local Curve = require("../../../src/shared/Routes/Curve")
local Height = require("../../../src/shared/World/Height")
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
local BARK_LIGHT = { 108, 84, 62 }
local BAFFLE = { 178, 182, 186 }
local HEDGE = { 52, 84, 42 }
-- the leaves: darkest underneath, three greens above
Yard.LEAF_TONES = { { 54, 90, 42 }, { 72, 114, 50 }, { 86, 128, 58 }, { 104, 142, 66 } }

Yard.HOUSE_COLORS = { siding = SIDING, trim = TRIM, roof = ROOF }

local H = AlleyRoof.HOUSE
local T = AlleyRoof.TREE
local ROOF_SLOPE = (H.ridgeY - H.eaveY) / (H.ridgeD - H.d0) -- 0.7: 35 degrees
local ROOF_T = 0.35
local LIFT = 1.25 -- Motion.C.visualBranchLift: the top of a bough is the squirrel's feet
local BODY = 0.85 -- half the squirrel's body: where a guard's eye looks

local NOQUERY = { collide = false, query = false }
local DRESS = { collide = false }

-- Where a route's line is at t (arc length), in the local frame.
local function curveOf(id: number): Curve.Curve
	return Curve.fromArrays(AlleyRoof.route(id).points)
end

-- The bark's radius of the limb on 9105 at t: thickest at the trunk's top, never under 0.68 (so the rail, 1.25
-- under the bark's top, stays inside the bark).
function Yard.boughRadius(t: number): number
	local f = AlleyRoof.BOUGH_FORK_T
	if t <= f then
		return 0.68 + 0.32 * t / f
	end
	return 1.0 - 0.32 * (t - f) / (1 - f)
end

-- The leap's flights off the ridge's west end (local {X, Y, D} feet), with no key held and with W held, sampled from
-- the motor's own numbers (leap off a rail, gravity, the air drag or the air steer toward v5.4's walk).
local function flights(): { { { number } } }
	local P = SquirrelMotor.params
	local e = AlleyRoof.route(9103).points[2]
	local out = {}
	for _, held in { false, true } do
		local X, Y, vx, vy = e[1], e[2], -P.leapForward, P.leapUp
		local path = {}
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
			table.insert(path, { X, Y, e[3] })
		end
		table.insert(out, path)
	end
	return out
end

-- What the leaves keep clear of (local points): every route of the way up (the bough's at the squirrel's feet), and
-- the leap's flights.
function Yard.keepOut(): { { number } }
	local out = {}
	for _, id in { 9101, 9102, 9103, 9105 } do
		local c = curveOf(id)
		local n = math.ceil(c:getLength() / 0.75)
		local lift = if id == AlleyRoof.BOUGH then LIFT else 0
		for k = 0, n do
			local p = c:getPointAt(k / n)
			table.insert(out, { p.x, p.y + lift, p.z })
		end
	end
	for _, path in flights() do
		for _, q in path do
			table.insert(out, q)
		end
	end
	return out
end

-- The guard's lines of sight: from each eye on the platform (AlleyRoof.guardEyes) to the squirrel's body along the
-- ridge, the leap and the bough (local { a, b } pairs). The leaves keep clear of them.
function Yard.sightLines(): { { { number } } }
	local targets = {}
	for _, id in { 9103, 9105 } do
		local c = curveOf(id)
		local n = math.ceil(c:getLength() / 1.5)
		local lift = (if id == AlleyRoof.BOUGH then LIFT else 0) + BODY
		for k = 0, n do
			local p = c:getPointAt(k / n)
			table.insert(targets, { p.x, p.y + lift, p.z })
		end
	end
	for _, path in flights() do
		for i = 2, #path, 2 do
			local q = path[i]
			table.insert(targets, { q[1], q[2] + BODY, q[3] })
		end
	end
	local out = {}
	for _, eye in AlleyRoof.guardEyes() do
		for _, q in targets do
			table.insert(out, { eye, q })
		end
	end
	return out
end

-- the distance from p to the segment a-b
local function segDist(p: { number }, a: { number }, b: { number }): number
	local abx, aby, abd = b[1] - a[1], b[2] - a[2], b[3] - a[3]
	local apx, apy, apd = p[1] - a[1], p[2] - a[2], p[3] - a[3]
	local l2 = abx * abx + aby * aby + abd * abd
	local s = if l2 > 0 then math.clamp((apx * abx + apy * aby + apd * abd) / l2, 0, 1) else 0
	local dx, dy, dd = apx - abx * s, apy - aby * s, apd - abd * s
	return math.sqrt(dx * dx + dy * dy + dd * dd)
end

-- The crown: leaf clumps {X, Y, D, diameter, tone} at the twigs' and limbs' tips and scattered (a fixed seed) through
-- AlleyRoof.TREE.crown, each at least TUNNEL from everything in keepOut() and SIGHT from every line in sightLines(),
-- inside the annex (and the footprint beside it).
local TUNNEL = 2.4
local SIGHT = 0.3
Yard.CROWN = T.crown
-- Twigs off the limb on 9105, each carrying a small clump over it on the side away from the guard's platform (so
-- the limb is not a bare pole): { t on 9105, side (+1 left of the way toward the roof, -1 right) }.
Yard.TWIGS = { { 0.2, -1 }, { 0.55, -1 }, { 0.68, -1 }, { 0.8, -1 } }
-- The thin tip drawn on past the bough's house end (the route stops 3 st past the leap's catch): offsets
-- {dX, dY, dD} from the drawn limb's axis at that end.
Yard.BOUGH_TIP = { { 0, 0, 0 }, { 0.75, 0.6, -2.6 }, { 1.35, 1.0, -5.0 } }
-- The three low scaffold limbs (so the crown starts low, on the side away from the platform): points and radii.
Yard.LOW_LIMBS = {
	{ pts = { { 166.2, 6.5, 32.6 }, { 168.4, 11.5, 37.0 }, { 171.0, 15.5, 41.0 } }, radii = { 0.8, 0.55, 0.35 } },
	{ pts = { { 165.9, 8.5, 32.4 }, { 162.8, 13.0, 37.0 }, { 160.0, 16.5, 41.0 } }, radii = { 0.75, 0.5, 0.32 } },
	{ pts = { { 166.4, 10.0, 31.8 }, { 171.4, 14.0, 33.6 }, { 176.0, 17.5, 35.0 } }, radii = { 0.7, 0.48, 0.3 } },
}

-- twig(i): the twig's foot, its tip and its clump's centre (local), and the clump's diameter
function Yard.twig(i: number): ({ number }, { number }, { number }, number)
	local tw = Yard.TWIGS[i]
	local u, side = tw[1], tw[2]
	local c = curveOf(AlleyRoof.BOUGH)
	local p, tg = c:getPointAt(u), c:getTangentAt(u)
	local l = math.sqrt(tg.x * tg.x + tg.z * tg.z)
	local sx, sd = -tg.z / l * side, tg.x / l * side
	local r = Yard.boughRadius(u)
	local cy = p.y + LIFT - r
	local foot = { p.x + sx * r * 0.8, cy, p.z + sd * r * 0.8 }
	local tip = { p.x + sx * 3.6, cy + 3.4, p.z + sd * 3.6 }
	return foot, tip, { p.x + sx * 4.6, cy + 5.2, p.z + sd * 4.6 }, 6
end

-- which twigs kept their clump (a twig whose clump would close a tunnel or a sight line is not drawn)
Yard.TWIG_KEPT = {} :: { [number]: boolean }
Yard.LEAF_CLUMPS = (function(): { { number } }
	local keep = Yard.keepOut()
	local sight = Yard.sightLines()
	local cr = T.crown
	local clumps: { { number } } = {}
	local function q(n: number): number
		return math.floor(n * 10 + 0.5) / 10
	end
	local function try(X: number, Y: number, D: number, size: number, index: number): boolean
		if D + size / 2 > AlleyRoof.ANNEX.d1 or X + size / 2 > H.x0 - 1 or size > cr.maxClump then
			return false
		end
		if ((X - cr.x) / cr.rx) ^ 2 + ((Y - cr.y) / cr.ry) ^ 2 + ((D - cr.d) / cr.rd) ^ 2 > 1 then
			return false
		end
		for _, k in keep do
			local dx, dy, dd = k[1] - X, k[2] - Y, k[3] - D
			if math.sqrt(dx * dx + dy * dy + dd * dd) - size / 2 < TUNNEL then
				return false
			end
		end
		local p = { X, Y, D }
		for _, s in sight do
			if segDist(p, s[1], s[2]) < size / 2 + SIGHT then
				return false
			end
		end
		-- spread out: overlapping, but not one inside another
		for _, c in clumps do
			if math.sqrt((c[1] - X) ^ 2 + (c[2] - Y) ^ 2 + (c[3] - D) ^ 2) < 0.6 * (c[4] + size) / 2 then
				return false
			end
		end
		-- the tone: the darkest under the crown's middle, else one of the three lighter greens
		local tone = if Y < cr.y - 0.35 * cr.ry then 1 else 2 + index % 3
		table.insert(clumps, { q(X), q(Y), q(D), q(size), tone })
		return true
	end
	local n = 0
	for i in Yard.TWIGS do
		local _, _, c, size = Yard.twig(i)
		n += 1
		Yard.TWIG_KEPT[i] = try(c[1], c[2], c[3], size, n)
	end
	for _, limb in Yard.LOW_LIMBS do
		local tip = limb.pts[#limb.pts]
		n += 1
		try(tip[1], tip[2] + 3, tip[3] + 0.5, 7, n)
	end
	local seed = 20261113
	local function rand(): number
		seed = (seed * 1103515245 + 12345) % 2147483648
		return seed / 2147483648
	end
	for _ = 1, 4000 do
		if #clumps >= cr.count then
			break
		end
		local X = cr.x + (2 * rand() - 1) * cr.rx
		local Y = cr.y + (2 * rand() - 1) * cr.ry
		local D = cr.d + (2 * rand() - 1) * cr.rd
		-- big clumps make the mass, small ones fill between them
		local size = if rand() < 0.35 then 4 + 2.5 * rand() else 7 + 4 * rand()
		n += 1
		try(X, Y, D, size, n)
	end
	return clumps
end)()

-- The local height of the ground at (X, D) (the terrain under the yard).
local function groundY(kit: any, X: number, D: number): number
	local p = kit:cf(X, 0, D).Position
	return Height.at(p.X, p.Z) - p.Y
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

-- A flat slab across local D (d0..d1) from xa to xb, its top `lift` over the ground at each end (it tilts with the
-- ground along X).
local function slab(
	kit: any,
	m: any,
	name: string,
	xa: number,
	xb: number,
	d0: number,
	d1: number,
	lift: number,
	thick: number,
	color: { number },
	material: string
): any
	local r = kit.roblox
	local dm = (d0 + d1) / 2
	local a = kit:cf(xa, groundY(kit, xa, dm) + lift, dm).Position
	local b = kit:cf(xb, groundY(kit, xb, dm) + lift, dm).Position
	local along = (b - a).Unit
	local across = (kit:cf(0, 0, 1).Position - kit:cf(0, 0, 0).Position).Unit
	local up = across:Cross(along)
	if up.Y < 0 then
		up = -up
	end
	local p = kit:at(m, name, 0, 0, 0, (b - a).Magnitude, thick, math.abs(d1 - d0), color, material, NOQUERY)
	p.CFrame = r.CFrame.fromMatrix((a + b) / 2 - up * (thick / 2), along, up)
	return p
end

-- The house's setting: a flagstone path from the porch step west to the walk beside the games wing, a mailbox where
-- it meets the walk, a hedge along the yard's east and south sides. Drawn only (a squirrel runs through a hedge).
local function setting(kit: any, m: any)
	local d0, d1 = 4.3, 6.5
	local xs = { 152.6, 159.6, 166.6, 173.6, 180.6, 187.6, 194.2 }
	for i = 1, #xs - 1 do
		slab(kit, m, `Path{i}`, xs[i], xs[i + 1] - 0.25, d0, d1, 0.06, 0.3, { 168, 160, 146 }, "Slate")
	end
	-- the mailbox: a post, the box, its flag
	local mx, md = 154.2, 7.6
	local g = groundY(kit, mx, md)
	kit:cyl(m, "MailboxPost", mx, g + 1.5, md, 3.6, 0.36, "Y", { 236, 232, 222 }, "Wood", DRESS)
	kit:box(m, "Mailbox", mx - 0.5, mx + 0.5, g + 3.3, g + 4.2, md - 0.85, md + 0.85, { 44, 70, 104 }, "Metal", DRESS)
	kit:box(
		m,
		"MailboxFlag",
		mx + 0.5,
		mx + 0.62,
		g + 3.7,
		g + 4.6,
		md + 0.2,
		md + 0.6,
		{ 196, 44, 40 },
		"Metal",
		DRESS
	)
	-- the hedge: east side, then south side, in pieces that follow the ground (sunk into it, 2.4 over its highest)
	local function hedge(name: string, x0: number, x1: number, e0: number, e1: number)
		local lo, hi = math.huge, -math.huge
		for _, c in { { x0, e0 }, { x1, e0 }, { x0, e1 }, { x1, e1 } } do
			local gy = groundY(kit, c[1], c[2])
			lo, hi = math.min(lo, gy), math.max(hi, gy)
		end
		kit:box(m, name, x0, x1, lo - 0.6, hi + 2.4, e0, e1, HEDGE, "LeafyGrass", NOQUERY)
	end
	for i, e in { { 10, 18.6 }, { 18.6, 27.2 }, { 27.2, 35.8 }, { 35.8, 44.0 } } do
		hedge(`HedgeE{i}`, 210.4, 212.0, e[1], e[2])
	end
	for i, x in { { 186.0, 194.2 }, { 194.2, 202.4 }, { 202.4, 210.4 } } do
		hedge(`HedgeS{i}`, x[1], x[2], 42.4, 44.0)
	end
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
	-- the trunk on the spine, tapering from trunkR at the foot to forkR at the top (it alone collides)
	local spine = Curve.fromArrays(T.spine)
	local function radiusAt(u: number): number
		return T.trunkR + (T.forkR - T.trunkR) * u
	end
	local N = 5
	for i = 1, N do
		local u0, u1 = (i - 1) / N, i / N
		local a, b = spine:getPointAt(u0), spine:getPointAt(u1)
		local r = radiusAt((u0 + u1) / 2)
		kit:rod(m, `Trunk{i}`, a.x, a.y, a.z, b.x, b.y, b.z, 2 * r, BARK, "Wood", { collide = true })
	end
	-- the root flare: a skirt and four roots into the ground
	local base = spine:getPointAt(0)
	kit:cyl(m, "TrunkFlare", base.x, base.y + 0.4, base.z, 1.6, 2 * T.trunkR + 1.4, "Y", BARK, "Wood", NOQUERY)
	for k = 1, 3 do
		local a = math.rad(20 + 120 * k)
		local ca, sa = math.cos(a), math.sin(a)
		kit:rod(
			m,
			`Root{k}`,
			base.x + ca * T.trunkR * 0.6,
			base.y + 1.0,
			base.z + sa * T.trunkR * 0.6,
			base.x + ca * (T.trunkR + 2.6),
			base.y - 0.35,
			base.z + sa * (T.trunkR + 2.6),
			1.2,
			BARK,
			"Wood",
			NOQUERY
		)
	end
	-- the squirrel baffle: a galvanised cone round the trunk (its rim, the cone's middle, the collar)
	local bf = T.baffle
	local rB = radiusAt((bf.y0 - T.spine[1][2]) / (T.spine[#T.spine][2] - T.spine[1][2]))
	local bx, bd = T.x, T.d
	kit:cyl(m, "Baffle", bx, bf.y0 + 0.08, bd, 0.16, 2 * bf.r, "Y", BAFFLE, "Metal", NOQUERY)
	kit:cyl(m, "BaffleCone", bx, (bf.y0 + bf.y1) / 2, bd, 0.5, bf.r + rB + 0.3, "Y", BAFFLE, "Metal", NOQUERY)
	kit:cyl(m, "BaffleCollar", bx, bf.y1 - 0.3, bd, 0.6, 2 * rB + 0.3, "Y", BAFFLE, "Metal", NOQUERY)
	-- the leader above the top
	local fork = spine:getPointAt(1)
	limb(kit, m, "Leader", {
		{ fork.x, fork.y - 0.5, fork.z },
		{ fork.x - 0.6, fork.y + 7, fork.z + 0.8 },
		{ fork.x - 0.3, fork.y + 14, fork.z + 0.5 },
		{ fork.x + 0.4, fork.y + 20, fork.z - 0.4 },
	}, { T.forkR - 0.1, 0.75, 0.5, 0.3 }, BARK, NOQUERY)
	-- the limb the squirrel runs (9105): its top at the rail + 1.25, thickest where it leaves the trunk
	do
		local c = curveOf(AlleyRoof.BOUGH)
		local pts, radii = {}, {}
		local S = 10
		for i = 0, S do
			local u = i / S
			local p = c:getPointAt(u)
			local rr = Yard.boughRadius(u)
			table.insert(pts, { p.x, p.y + LIFT - rr, p.z })
			table.insert(radii, rr)
		end
		limb(kit, m, "Bough9105", pts, radii, BARK_LIGHT, NOQUERY)
		-- a rounded end over the roof, and the thin tip on past the house end
		local tip = pts[#pts]
		kit:ball(m, "Bough9105_Tip", tip[1], tip[2], tip[3], 2 * radii[#radii], BARK_LIGHT, "Wood", NOQUERY)
		local h = pts[1]
		local tipPts = {}
		for _, o in Yard.BOUGH_TIP do
			table.insert(tipPts, { h[1] + o[1], h[2] + o[2], h[3] + o[3] })
		end
		limb(kit, m, "BoughTip", tipPts, { radii[1], 0.45, 0.22 }, BARK_LIGHT, NOQUERY)
	end
	-- limbs that carry the crown: three low scaffold limbs, three from the top (south, east and west)
	for i, l in Yard.LOW_LIMBS do
		limb(kit, m, `LimbLow{i}`, l.pts, l.radii, BARK, NOQUERY)
	end
	limb(kit, m, "LimbS", {
		{ fork.x, fork.y + 1, fork.z },
		{ fork.x - 1, fork.y + 5, fork.z + 5 },
		{ fork.x - 2, fork.y + 9, fork.z + 10 },
	}, { 0.75, 0.5, 0.3 }, BARK, NOQUERY)
	limb(kit, m, "LimbE", {
		{ fork.x, fork.y + 3, fork.z },
		{ fork.x + 5, fork.y + 7, fork.z + 3 },
		{ fork.x + 10, fork.y + 10, fork.z + 6 },
	}, { 0.65, 0.45, 0.3 }, BARK, NOQUERY)
	limb(kit, m, "LimbW", {
		{ fork.x, fork.y + 4, fork.z },
		{ fork.x - 5, fork.y + 8, fork.z + 1 },
		{ fork.x - 9, fork.y + 12, fork.z - 1 },
	}, { 0.6, 0.42, 0.28 }, BARK, NOQUERY)
	for i in Yard.TWIGS do
		local foot, tip = Yard.twig(i)
		if Yard.TWIG_KEPT[i] then
			limb(kit, m, `Twig{i}`, { foot, tip }, { 0.3, 0.16 }, BARK_LIGHT, NOQUERY)
		end
	end
	-- the crown
	for i, c in Yard.LEAF_CLUMPS do
		kit:ball(m, `Leaves{i}`, c[1], c[2], c[3], c[4], Yard.LEAF_TONES[c[5]], "LeafyGrass", NOQUERY)
	end
	return m
end

-- build(kit, root): the Model "Yard" under root (the alley's Kit: its place puts it beside the games wing).
function Yard.build(kit: any, root: any): any
	local yard = kit:model(root, "Yard")
	local h = house(kit, yard)
	setting(kit, h)
	tree(kit, yard)
	return yard
end

return Yard
