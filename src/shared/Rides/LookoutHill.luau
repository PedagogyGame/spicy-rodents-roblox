--!strict
-- ReplicatedStorage.Shared.Rides.LookoutHill
-- The way up Lookout Hill on foot and what stands on the hill (BATCH2 §1.1-1.2): the hill trail's pieces, its
-- benches, and the hill's seeded dressing (conifers, rocks, shrubs). tools/bake/skylift/Approach draws them from
-- here; World/WalkWay keeps the town's walkers out of what of them a walker cannot pass (obstacles(): the rocks,
-- the benches and the handrails), and AI/TownAI gives a walker on the trail its top as the ground (trailTopAt). Both read the same
-- numbers, so the boxes and the gravel are where the bake put the parts.
--   * The trail (xpath_hill_trail): its points, with a bend wherever a leg passes within TOWER_CLEAR of a line
--     tower; each leg cut into pieces of at most PIECE_MAX, each piece rolled to the ground's cross slope up to
--     ROLL_MAX and its ends LIFT over the highest ground across it; a piece the ground rises over between its ends
--     is split at its worst point, down to PIECE_MIN. `drop` is the most a piece's top stands over the ground.
--   * The dressing: conifers in small stands, rocks and shrubs round the crown, and a rock and a shrub at the foot
--     of each tower, all drawn from one seeded generator (SEED) in that order, never on the trail, the roads,
--     either venue's site, the towers' footings or under the cabins, nor high in front of the Lookout's terrace.
-- Interface: trailPoints() -> { {x, z} }; trailPieces() -> { Piece }; trailDistance(x, z) -> studs (plan, to the
--   centre line); inSite(x, z, grow) -> boolean (in f4_lift_base's or f3_hilltop's site, grown); dressing() ->
--   { Dress } (in the bake's order); benches() -> { Bench }; obstacles() -> { Block } (plan boxes a walker cannot
--   pass: x0, x1, z0, z1, the ground y0 and the top); trailTopAt(x, z) -> number? (the gravel's top, a piece's or a
--   landing's); landings() -> { {x, z, top} }; rails() -> { {ax, az, bx, bz, top} }; terrain() -> the extensions;
--   the constants below.
-- Pure (the lift's towers and swept volume from Shared/Rides/SkyLift); studs, world x and z (a part's Roblox X
-- and Z). The hill is World/Height with the game's terrain extensions (Data's TerrainExtensions, as the
-- bake and the server's boot configure it): configured for the moment of each computation and put back as found,
-- so a process that runs on the plain ground (most specs) still gets the bake's layout. Computed once and kept. No
-- side effects on require.

local AlleyLayout = require("../Attractions/AlleyLayout")
local Data = require("../Data")
local Height = require("../World/Height")
local SkyLift = require("./SkyLift")

local LookoutHill = {}

LookoutHill.TRAIL_WIDTH = 6
LookoutHill.LIFT = 0.2 -- a piece's top over the highest ground across its ends
LookoutHill.THICK = 1.2
LookoutHill.ROLL_MAX = 0.15 -- radians of cross-fall a piece follows (about 9 degrees)
LookoutHill.PIECE_MAX = 16
LookoutHill.PIECE_MIN = 2
LookoutHill.TOWER_CLEAR = 8.5 -- trail half-width, the footing's half-diagonal and a rail's width
LookoutHill.TREES = 32
LookoutHill.ROCKS = 14
LookoutHill.SHRUBS = 16
LookoutHill.SEED = 20261113
LookoutHill.CROWN = table.freeze({ -1050, -1710 }) -- the hill's crown (plan)
LookoutHill.TOWARD_TOWN = table.freeze({ 0.751, 0.659 }) -- the Lookout's front: keep the terrace's view clear
-- the benches facing the town: at which of the data's trail points, and how far out toward the town to start
LookoutHill.BENCHES = table.freeze({
	table.freeze({ name = "BenchFoot", point = 4, out = 6 }),
	table.freeze({ name = "BenchTurn", point = 6, out = 6.5 }),
	table.freeze({ name = "BenchTop", point = 7, out = 6 }),
})
LookoutHill.TOWN = table.freeze({ 700, -150 }) -- what the benches face
-- a bench's footprint in its own frame (X across, D toward its back) and its height, as the bake builds it
LookoutHill.BENCH = table.freeze({ x0 = -2.4, x1 = 2.4, d0 = -0.95, d1 = 0.7, top = 3.2 })
-- the handrails: both sides where a piece's grade passes RAIL_GRADE, the downhill side where it stands more than
-- DROP_RAIL over the ground; RAIL_OUT past the trail's edge, their top RAIL_TOP over the trail. Timber steps where
-- the grade passes STEP_GRADE; a stone bank under a piece standing more than BANK_DROP over the ground.
LookoutHill.RAIL_GRADE = 0.35
LookoutHill.STEP_GRADE = 0.42
LookoutHill.DROP_RAIL = 2.5
LookoutHill.BANK_DROP = 0.9
LookoutHill.RAIL_OUT = 0.4
LookoutHill.RAIL_TOP = 3.0
LookoutHill.RAIL_PIECE = 3 -- studs: a handrail is boxed in pieces this long (World/WalkWay's fences: FENCE_PIECE)
LookoutHill.RAIL_HALF = 0.5 -- studs: half a box's thickness round the rail's line (posts 0.3 square, rods 0.25)
LookoutHill.LANDING = LookoutHill.TRAIL_WIDTH + 0.4 -- a round landing's diameter, at each turn
-- a walker steps over less than this (World/WalkWay.LOW; kept here so the two modules do not require each other)
LookoutHill.LOW = 1.5

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

-- one thing on the hill, in the bake's order: a conifer (h tall, w across, tint picks its green), a rock (the centre
-- y, size and CFrame.Angles turn as the bake gives the part) or a shrub (a ball `size` across, centre y)
export type Dress = {
	kind: "conifer" | "rock" | "shrub",
	x: number,
	z: number,
	y: number,
	h: number?,
	w: number?,
	tint: number?,
	size: { number }?,
	rot: { number }?,
}

export type Bench = { name: string, x: number, z: number, ground: number, yaw: number }

export type Block = { id: string, x0: number, x1: number, z0: number, z1: number, y0: number, top: number }

local function ground(x: number, z: number): number
	return Height.at(x, z)
end

local function expansion(): any
	return Data.default():module("Expansion")
end

-- the game's terrain extensions (World/Height.configure's argument at the server's boot and in the bake)
function LookoutHill.terrain(): any
	return Data.default():module("TerrainExtensions")
end

-- f() on the game's ground (the terrain extensions configured), the configuration put back as it was
local function withTerrain<T>(f: () -> T): T
	local was = Height.configured()
	local ext = LookoutHill.terrain()
	if was == ext then
		return f()
	end
	Height.configure(ext)
	local ok, result = pcall(f)
	Height.configure(was)
	if not ok then
		error(result, 0)
	end
	return result
end

local function record(list: { any }, id: string): any
	for _, r in list do
		if r.id == id then
			return r
		end
	end
	error("LookoutHill: no " .. id)
end

local pointsCache: { { number } }? = nil
-- The trail's polyline: xpath_hill_trail's points, with a bend added wherever a leg passes within TOWER_CLEAR of a
-- line tower (towers 8 and 9 stand on the data's line): the new point stands TOWER_CLEAR + 1 from the tower, on the
-- side the leg passed it. The two ends are the data's.
function LookoutHill.trailPoints(): { { number } }
	if pointsCache then
		return pointsCache
	end
	local P: { { number } } = {}
	for _, q in record(expansion().paths, "xpath_hill_trail").points do
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
			if best < LookoutHill.TOWER_CLEAR then
				local nx, nz = bx - t.x, bz - t.z
				if best < 0.01 then
					local a, b = P[bi], P[bi + 1]
					nx, nz = -(b[2] - a[2]), b[1] - a[1]
				end
				local nl = math.sqrt(nx * nx + nz * nz)
				local r = LookoutHill.TOWER_CLEAR + 1
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
local function pieces(): { Piece }
	local P = LookoutHill.trailPoints()
	local hw = LookoutHill.TRAIL_WIDTH / 2
	local out: { Piece } = {}
	local function rollAt(x: number, z: number, ux: number, uz: number): number
		-- right of travel = (-uz, ux)
		local right = ground(x - uz * hw, z + ux * hw)
		local left = ground(x + uz * hw, z - ux * hw)
		return math.clamp(
			math.atan2(right - left, LookoutHill.TRAIL_WIDTH),
			-LookoutHill.ROLL_MAX,
			LookoutHill.ROLL_MAX
		)
	end
	-- the centre top over (x, z) for a piece rolled `roll`: LIFT over the highest ground across it
	local function crossTop(x: number, z: number, ux: number, uz: number, roll: number): number
		local top = -math.huge
		for _, f in CROSS do
			local o = f * hw
			top = math.max(top, ground(x - uz * o, z + ux * o) - o * math.tan(roll))
		end
		return top + LookoutHill.LIFT
	end
	-- the worst shortfall of the top under the ground between the ends: (gap, at f); and the largest drop
	local function survey(
		ax: number,
		az: number,
		ay: number,
		bx: number,
		bz: number,
		by: number,
		roll: number
	): (number, number, number)
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
		if gap > -0.02 and l > LookoutHill.PIECE_MIN * 2 then
			at = math.clamp(at, LookoutHill.PIECE_MIN / l, 1 - LookoutHill.PIECE_MIN / l)
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
		local n = math.ceil(l / LookoutHill.PIECE_MAX)
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
	return out
end

local trailCache: { Piece }? = nil
-- The trail's pieces (see the header).
function LookoutHill.trailPieces(): { Piece }
	if trailCache == nil then
		trailCache = withTerrain(pieces)
	end
	return trailCache :: { Piece }
end

-- distance in plan from (x, z) to the trail's centre line
function LookoutHill.trailDistance(x: number, z: number): number
	local best = math.huge
	for _, p in LookoutHill.trailPieces() do
		local dx, dz = p.bx - p.ax, p.bz - p.az
		local l2 = dx * dx + dz * dz
		local f = math.clamp(((x - p.ax) * dx + (z - p.az) * dz) / l2, 0, 1)
		local ex, ez = p.ax + dx * f - x, p.az + dz * f - z
		best = math.min(best, math.sqrt(ex * ex + ez * ez))
	end
	return best
end

-- inside a venue's site (grown by `grow`)?
function LookoutHill.inSite(x: number, z: number, grow: number): boolean
	local exp = expansion()
	for _, id in { "f4_lift_base", "f3_hilltop" } do
		local v = record(exp.venues, id)
		local place = { x = v.position.x, z = v.position.z, floorY = v.floorY, yaw = v.yaw }
		local X, _, D = AlleyLayout.toLocal(place, x, 0, z)
		if X >= v.site.x0 - grow and X <= v.site.x1 + grow and D >= v.site.d0 - grow and D <= v.site.d1 + grow then
			return true
		end
	end
	return false
end

local function dress(): { Dress }
	local hw = LookoutHill.TRAIL_WIDTH / 2
	local lot = record(expansion().pads, "xp_lift_lot").rect
	local seed = LookoutHill.SEED
	local function rnd(): number
		seed = (seed * 1103515245 + 12345) % 2147483648
		return seed / 2147483648
	end
	local crown, towardTown = LookoutHill.CROWN, LookoutHill.TOWARD_TOWN
	local towers = SkyLift.towers()
	local function ok(x: number, z: number, h: number, clearR: number): boolean
		if LookoutHill.trailDistance(x, z) < hw + clearR + 1.5 then
			return false
		end
		if LookoutHill.inSite(x, z, clearR + 3) then
			return false
		end
		for _, tw in towers do
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
	local out: { Dress } = {}
	local trees, rocks, shrubs = 0, 0, 0
	local tries = 0
	-- conifers in small stands (a lone tree on a bare dome reads as a post from the town)
	while trees < LookoutHill.TREES and tries < 400 do
		tries += 1
		local ang = rnd() * 2 * math.pi
		local r = 100 + rnd() * 240
		local cx, cz = crown[1] + math.cos(ang) * r, crown[2] + math.sin(ang) * r
		local stand = 2 + math.floor(rnd() * 4)
		for _ = 1, stand * 3 do
			if stand <= 0 or trees >= LookoutHill.TREES then
				break
			end
			local a2, r2 = rnd() * 2 * math.pi, 4 + rnd() * 14
			local x, z = cx + math.cos(a2) * r2, cz + math.sin(a2) * r2
			local h = 15 + rnd() * 11
			local w = h * (0.4 + rnd() * 0.1)
			if ok(x, z, h, w / 2) then
				table.insert(out, { kind = "conifer", x = x, z = z, y = ground(x, z), h = h, w = w, tint = rnd() })
				trees += 1
				stand -= 1
			end
		end
	end
	tries = 0
	while rocks < LookoutHill.ROCKS and tries < 2000 do
		tries += 1
		local ang = rnd() * 2 * math.pi
		local r = 60 + rnd() * 300
		local x, z = crown[1] + math.cos(ang) * r, crown[2] + math.sin(ang) * r
		local s = 2 + rnd() * 4
		if ok(x, z, s, s) then
			local size = { s * (1 + rnd() * 0.6), s * 0.75, s }
			local rot = { rnd() * 0.4 - 0.2, rnd() * math.pi, rnd() * 0.4 - 0.2 }
			table.insert(out, { kind = "rock", x = x, z = z, y = ground(x, z) + s * 0.2, size = size, rot = rot })
			rocks += 1
		end
	end
	tries = 0
	local trail = LookoutHill.trailPieces()
	while shrubs < LookoutHill.SHRUBS and tries < 2000 do
		tries += 1
		-- shrubs keep to the trail's sides and the foot of the hill
		local p = trail[1 + math.floor(rnd() * #trail)]
		local side = if rnd() < 0.5 then -1 else 1
		local dx, dz = p.bx - p.ax, p.bz - p.az
		local l = math.sqrt(dx * dx + dz * dz)
		local o = side * (hw + 3 + rnd() * 6)
		local f = rnd()
		local x, z = p.ax + dx * f - dz / l * o, p.az + dz * f + dx / l * o
		local s = 2.2 + rnd() * 2
		if ok(x, z, s, s / 2) then
			table.insert(out, { kind = "shrub", x = x, z = z, y = ground(x, z) + s * 0.3, size = { s } })
			shrubs += 1
		end
	end
	-- along the line: a rock and a shrub at the foot of each tower, where the mower cannot reach
	for _, tw in towers do
		local c, s = math.cos(tw.yaw), math.sin(tw.yaw)
		local rx, rz = tw.x + c * 4.6 + s * 2.2, tw.z - s * 4.6 + c * 2.2
		local sx, sz = tw.x - c * 4.4 - s * 3.0, tw.z + s * 4.4 - c * 3.0
		if ok(rx, rz, 2, 1.5) then
			local r = 1.6 + rnd() * 1.4
			local rot = { rnd() * 0.3, rnd() * math.pi, rnd() * 0.3 }
			table.insert(out, {
				kind = "rock",
				x = rx,
				z = rz,
				y = ground(rx, rz) + r * 0.2,
				size = { r * 1.4, r * 0.7, r },
				rot = rot,
			})
		end
		if ok(sx, sz, 3, 1.5) then
			local r = 2.4 + rnd() * 1.2
			table.insert(out, { kind = "shrub", x = sx, z = sz, y = ground(sx, sz) + r * 0.3, size = { r } })
		end
	end
	return out
end

local dressCache: { Dress }? = nil
-- The hill's dressing, in the bake's order: seeded, off the trail, the roads, the sites and the cabins' way.
function LookoutHill.dressing(): { Dress }
	if dressCache == nil then
		dressCache = withTerrain(dress)
	end
	return dressCache :: { Dress }
end

-- The benches facing the town at three turns: each beside its turn toward the town, stepped out until it is off
-- the trail (a bench 5 long: radius 2.6). `yaw` turns the bench's frame (AlleyLayout's place yaw).
local function benchList(): { Bench }
	local hw = LookoutHill.TRAIL_WIDTH / 2
	local points = record(expansion().paths, "xpath_hill_trail").points
	local out: { Bench } = {}
	for _, b in LookoutHill.BENCHES do
		local q = points[b.point]
		local step = b.out
		local tx, tz = LookoutHill.TOWN[1] - q[1], LookoutHill.TOWN[2] - q[2]
		local tl = math.sqrt(tx * tx + tz * tz)
		tx, tz = tx / tl, tz / tl
		local x, z = q[1] + tx * step, q[2] + tz * step
		while LookoutHill.trailDistance(x, z) < hw + 3 and step < 40 do
			step += 1
			x, z = q[1] + tx * step, q[2] + tz * step
		end
		table.insert(out, { name = b.name, x = x, z = z, ground = ground(x, z), yaw = math.atan2(-tx, -tz) })
	end
	return out
end

function LookoutHill.benches(): { Bench }
	return withTerrain(benchList)
end

export type Landing = { x: number, z: number, top: number }
local landingCache: { Landing }? = nil
-- The round landings at the trail's turns (every point but the two ends): level with the higher of the two pieces
-- meeting there, LANDING across, built down to the ground.
function LookoutHill.landings(): { Landing }
	if landingCache then
		return landingCache
	end
	local turns = LookoutHill.trailPoints()
	local out: { Landing } = {}
	for i = 2, #turns - 1 do
		local q = turns[i]
		local top = -math.huge
		for _, p in LookoutHill.trailPieces() do
			if math.abs(p.bx - q[1]) < 1e-6 and math.abs(p.bz - q[2]) < 1e-6 then
				top = math.max(top, p.by)
			elseif math.abs(p.ax - q[1]) < 1e-6 and math.abs(p.az - q[2]) < 1e-6 then
				top = math.max(top, p.ay)
			end
		end
		table.insert(out, { x = q[1], z = q[2], top = top - 0.03 })
	end
	landingCache = out
	return out
end

-- the plan box round a part of `size` at (x, y, z) turned CFrame.Angles(rot), in world x and z; and its top
local function turnedBox(x: number, y: number, z: number, size: { number }, rot: { number }): Block
	local cx, sx = math.cos(rot[1]), math.sin(rot[1])
	local cy, sy = math.cos(rot[2]), math.sin(rot[2])
	local cz, sz = math.cos(rot[3]), math.sin(rot[3])
	-- CFrame.Angles(a, b, c) = Rx(a) Ry(b) Rz(c)
	local m = {
		{ cy * cz, -cy * sz, sy },
		{ cx * sz + sx * sy * cz, cx * cz - sx * sy * sz, -sx * cy },
		{ sx * sz - cx * sy * cz, sx * cz + cx * sy * sz, cx * cy },
	}
	local h = { size[1] / 2, size[2] / 2, size[3] / 2 }
	local e = { 0, 0, 0 }
	for i = 1, 3 do
		e[i] = math.abs(m[i][1]) * h[1] + math.abs(m[i][2]) * h[2] + math.abs(m[i][3]) * h[3]
	end
	-- (the part's Roblox X and Z are x and z)
	return {
		id = "lookout_rock",
		x0 = x - e[1],
		x1 = x + e[1],
		z0 = z - e[3],
		z1 = z + e[3],
		y0 = y - e[2],
		top = y + e[2],
	}
end

type Rect = { x0: number, x1: number, z0: number, z1: number }
local reach: Rect? = nil
-- The top of the trail's gravel over (x, z), or nil off the trail: on a piece (plan: within half the trail's width
-- of its line, between its ends) or a landing; the highest where they meet. A walker's ground on the hill (AI/TownAI):
-- the trail is walked on, never through (its steep pieces stand over the ground the town's people are given there,
-- and across the north face a piece stands on its stone bank).
function LookoutHill.trailTopAt(x: number, z: number): number?
	local hw = LookoutHill.TRAIL_WIDTH / 2
	local r = reach
	if r == nil then
		local x0, x1, z0, z1 = math.huge, -math.huge, math.huge, -math.huge
		for _, p in LookoutHill.trailPieces() do
			x0, x1 = math.min(x0, p.ax, p.bx), math.max(x1, p.ax, p.bx)
			z0, z1 = math.min(z0, p.az, p.bz), math.max(z1, p.az, p.bz)
		end
		local grow = math.max(hw, LookoutHill.LANDING / 2)
		r = { x0 = x0 - grow, x1 = x1 + grow, z0 = z0 - grow, z1 = z1 + grow }
		reach = r
	end
	local rr = r :: Rect
	if x < rr.x0 or x > rr.x1 or z < rr.z0 or z > rr.z1 then
		return nil
	end
	local top: number? = nil
	for _, p in LookoutHill.trailPieces() do
		local dx, dz = p.bx - p.ax, p.bz - p.az
		local l = math.sqrt(dx * dx + dz * dz)
		local ux, uz = dx / l, dz / l
		local ex, ez = x - p.ax, z - p.az
		local along = ex * ux + ez * uz
		-- (right of travel = (-uz, ux), as the pieces are surveyed)
		local o = ex * -uz + ez * ux
		if along >= 0 and along <= l and math.abs(o) <= hw then
			local y = p.ay + (p.by - p.ay) * along / l + o * math.tan(p.roll)
			if top == nil or y > (top :: number) then
				top = y
			end
		end
	end
	local lr2 = (LookoutHill.LANDING / 2) ^ 2
	for _, l in LookoutHill.landings() do
		if (x - l.x) ^ 2 + (z - l.z) ^ 2 <= lr2 and (top == nil or l.top > (top :: number)) then
			top = l.top
		end
	end
	return top
end

-- The handrails' lines: { ax, az, bx, bz, top } (top: the higher post's top), as the bake lays them along each
-- piece (see RAIL_GRADE).
function LookoutHill.rails(): { { number } }
	local hw = LookoutHill.TRAIL_WIDTH / 2
	local out: { { number } } = {}
	for _, p in LookoutHill.trailPieces() do
		local sides: { number } = {}
		if p.grade > LookoutHill.RAIL_GRADE then
			sides = { -1, 1 }
		elseif p.drop > LookoutHill.DROP_RAIL then
			sides = { if p.roll > 0 then -1 else 1 }
		end
		local dx, dz = p.bx - p.ax, p.bz - p.az
		local l = math.sqrt(dx * dx + dz * dz)
		local ux, uz = dx / l, dz / l
		for _, side in sides do
			local o = side * (hw + LookoutHill.RAIL_OUT)
			local lift = o * math.tan(p.roll) + LookoutHill.RAIL_TOP
			table.insert(out, {
				p.ax - uz * o,
				p.az + ux * o,
				p.bx - uz * o,
				p.bz + ux * o,
				math.max(p.ay, p.by) + lift,
			})
		end
	end
	return out
end

local function obstacleList(): { Block }
	local out: { Block } = {}
	for _, d in LookoutHill.dressing() do
		if d.kind == "rock" then
			local b = turnedBox(d.x, d.y, d.z, d.size :: { number }, d.rot :: { number })
			local g = math.min(ground(b.x0, b.z0), ground(b.x1, b.z0), ground(b.x0, b.z1), ground(b.x1, b.z1))
			if b.top - g >= LookoutHill.LOW then
				b.y0 = math.min(b.y0, g)
				table.insert(out, b)
			end
		end
	end
	local B = LookoutHill.BENCH
	for _, b in LookoutHill.benches() do
		local c, s = math.cos(b.yaw), math.sin(b.yaw)
		local x0, x1, z0, z1 = math.huge, -math.huge, math.huge, -math.huge
		for _, X in { B.x0, B.x1 } do
			for _, D in { B.d0, B.d1 } do
				-- (AlleyLayout.dirToWorld: local X across and D down-lane as world x and z)
				local lx, lz = X, -D
				local x, z = b.x + lx * c + lz * s, b.z - lx * s + lz * c
				x0, x1, z0, z1 = math.min(x0, x), math.max(x1, x), math.min(z0, z), math.max(z1, z)
			end
		end
		table.insert(out, {
			id = "lookout_bench",
			x0 = x0,
			x1 = x1,
			z0 = z0,
			z1 = z1,
			y0 = b.ground,
			top = b.ground + B.top,
		})
	end
	local half = LookoutHill.RAIL_HALF
	for _, rail in LookoutHill.rails() do
		local ax, az, bx, bz, top = rail[1], rail[2], rail[3], rail[4], rail[5]
		local len = math.sqrt((bx - ax) ^ 2 + (bz - az) ^ 2)
		local n = math.max(1, math.ceil(len / LookoutHill.RAIL_PIECE))
		for k = 0, n - 1 do
			local x0, z0 = ax + (bx - ax) * k / n, az + (bz - az) * k / n
			local x1, z1 = ax + (bx - ax) * (k + 1) / n, az + (bz - az) * (k + 1) / n
			table.insert(out, {
				id = "lookout_rail",
				x0 = math.min(x0, x1) - half,
				x1 = math.max(x0, x1) + half,
				z0 = math.min(z0, z1) - half,
				z1 = math.max(z0, z1) + half,
				y0 = math.min(ground(x0, z0), ground(x1, z1)),
				top = top,
			})
		end
	end
	return out
end

local blockCache: { Block }? = nil
-- What on the hill a walker cannot pass, as plan boxes: every rock standing LOW or more over the ground under it,
-- every bench, and the handrails in pieces RAIL_PIECE long (where they stand, the steep trail is a fenced way: the
-- town's way on foot goes round it). The trail itself is walked on: its top is the walker's ground (trailTopAt).
function LookoutHill.obstacles(): { Block }
	if blockCache == nil then
		blockCache = withTerrain(obstacleList)
	end
	return blockCache :: { Block }
end

return LookoutHill
