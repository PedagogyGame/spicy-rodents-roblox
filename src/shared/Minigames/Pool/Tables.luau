--!strict
-- ReplicatedStorage.Shared.Minigames.Pool.Tables
-- The two cue-sport tables as plain data, in studs: the eight-ball table (two of them stand in the games
-- room) and the bumper pool table. Everything the model collides with and everything a bake or a client
-- draws comes from here, so what is drawn is what is simulated (checklist C18, POOL-P7, BP-R1).
-- Table frame, seen from above: x across (the head-end player's right is +), z along the table (head end -,
-- foot end +); it matches AlleyLayout's (X, D) with the table's centre at the origin. The bed is the
-- rectangle between the cushion noses (halfW by halfL).
--   Eight-ball: a 10.8 x 5.4 bed (the baked footprint) with a ball of radius 0.17 (1 stud is 6.6 inches at
--   this size: a bar table). The cushions stop short of each pocket; the angled facings behind the ends are
--   the JAWS (142 degrees at a corner, 104 at a side pocket, as cut on a real table) and the tips between a
--   cushion and its facing are the POINTS a ball rattles on. Behind each mouth is the hole: a ball whose
--   centre runs over the hole's rim falls in. A corner has a shelf of cloth before the drop (a ball can hang
--   there); a side pocket has next to none.
--   Bumper pool: a 5.6 x 3.8 bed with no pockets, a cup in the bed at each end, and the regulation twelve
--   rubber posts: eight in a cross in the middle (two on each arm) whose four inner posts leave a gap just
--   one ball wide on each diagonal, and two flanking each cup. Each side's five balls start on the spots
--   round the cup at its own end and are shot to the cup at the far end; ball 1 of each five is the marked
--   one and sits in front of the cup.
-- Pure data; Lune-tested (tests/unit/pool_tables.spec.luau).
-- Interface: eightBall() -> Table; bumper() -> Table; byId(id) -> Table; rack(seed) -> { Spot } (cue ball
--   id 0 on the head spot, 1..15 racked on the foot spot with seeded hairline gaps); bumperStart(sides?) ->
--   { Spot }; BALL_R; POCKET_NAMES; inKitchen(table, z); onBed(table, x, z, margin?); freeSpot(table, x, z,
--   others, dz?) -> (x, z)

local Rng = require("../../Util/Rng")

local Tables = {}

Tables.BALL_R = 0.17

export type Seg = {
	x1: number,
	z1: number,
	x2: number,
	z2: number,
	tx: number, -- unit tangent, from end 1 to end 2
	tz: number,
	len: number,
	jaw: boolean, -- a pocket facing (deader than a cushion, and not a "rail" for the rules)
	minX: number, -- bounds grown by a ball radius, for the broad phase
	maxX: number,
	minZ: number,
	maxZ: number,
}
export type Hole = {
	x: number,
	z: number,
	r: number,
	mx: number, -- unit vector from the hole to the table (a pocket's mouth); 0, 0 for a cup
	mz: number,
	cup: boolean, -- a hole in the open bed (no liner behind it): capture depends on speed
	depth: number, -- how far a ball must fall to be down for good
}
export type Post = { x: number, z: number, r: number }
export type Spot = { id: number, x: number, z: number }
export type Table = {
	id: string, -- "eightball" | "bumper"
	halfW: number,
	halfL: number,
	ballR: number,
	segs: { Seg },
	holes: { Hole },
	posts: { Post },
	headZ: number, -- the head string and head spot (eight-ball)
	footZ: number, -- the foot spot
	-- inside this rectangle a ball cannot reach any cushion, jaw or pocket (the broad phase)
	safeX: number,
	safeZ: number,
}

-- sines and cosines of the facing angles as literals, so the table is the same bytes on every machine
local SIN38, COS38 = 0.6156614753256583, 0.788010753606722
local SIN14, COS14 = 0.24192189559966773, 0.9702957262759965

Tables.POCKET_NAMES = {
	"head left corner",
	"head right corner",
	"left side",
	"right side",
	"foot left corner",
	"foot right corner",
}

local function addSeg(list: { Seg }, r: number, x1: number, z1: number, x2: number, z2: number, jaw: boolean)
	local dx, dz = x2 - x1, z2 - z1
	local len = math.sqrt(dx * dx + dz * dz)
	table.insert(list, {
		x1 = x1,
		z1 = z1,
		x2 = x2,
		z2 = z2,
		tx = dx / len,
		tz = dz / len,
		len = len,
		jaw = jaw,
		minX = math.min(x1, x2) - r,
		maxX = math.max(x1, x2) + r,
		minZ = math.min(z1, z2) - r,
		maxZ = math.max(z1, z2) + r,
	})
end

-- Eight-ball dimensions (studs)
Tables.POOL_HALF_W = 2.7
Tables.POOL_HALF_L = 5.4
Tables.CORNER_MOUTH = 0.72 -- between the two points of a corner pocket (2.1 balls)
Tables.SIDE_MOUTH = 0.82 -- between the points of a side pocket (2.4 balls)
Tables.JAW_LEN = 0.46 -- a facing must end inside its hole's rim, or the pocket would leak (the tables spec checks)
Tables.CORNER_HOLE_R = 0.33
Tables.SIDE_HOLE_R = 0.33
-- cloth between the mouth line and the drop, on the pocket's centre line (1.3 inches at this scale). It is
-- what makes a corner play tighter when it is hammered: a ball that catches a jaw has this far to go before
-- it can fall, and a fast one is across to the other jaw and out again first.
Tables.CORNER_SHELF = 0.2
Tables.SIDE_SHELF = 0.03
Tables.POCKET_DEPTH = 0.085 -- half a radius: past this a ball is down
Tables.RACK_GAP = 0.004 -- between racked balls, before the seeded jitter
Tables.RACK_JITTER = 0.001

local eightBallTable: Table? = nil

function Tables.eightBall(): Table
	if eightBallTable then
		return eightBallTable
	end
	local R = Tables.BALL_R
	local W, L = Tables.POOL_HALF_W, Tables.POOL_HALF_L
	local a = Tables.CORNER_MOUTH * 0.7071067811865476 -- a corner point's distance from the corner
	local h = Tables.SIDE_MOUTH / 2
	local segs: { Seg } = {}
	local holes: { Hole } = {}
	-- cushion noses: two on each long side (either side of the side pocket), one at each end
	for _, sx in { -1, 1 } do
		addSeg(segs, R, sx * W, -L + a, sx * W, -h, false)
		addSeg(segs, R, sx * W, h, sx * W, L - a, false)
	end
	for _, sz in { -1, 1 } do
		addSeg(segs, R, -W + a, sz * L, W - a, sz * L, false)
	end
	local J = Tables.JAW_LEN
	-- pockets in calling order: head left, head right, left side, right side, foot left, foot right
	local function corner(sx: number, sz: number)
		-- the point on the long cushion and the point on the end cushion, each with its facing
		addSeg(segs, R, sx * W, sz * (L - a), sx * (W + J * SIN38), sz * (L - a + J * COS38), true)
		addSeg(segs, R, sx * (W - a), sz * L, sx * (W - a + J * COS38), sz * (L + J * SIN38), true)
		local out = (Tables.CORNER_SHELF + Tables.CORNER_HOLE_R) * 0.7071067811865476 - a / 2
		table.insert(holes, {
			x = sx * (W + out),
			z = sz * (L + out),
			r = Tables.CORNER_HOLE_R,
			mx = -sx * 0.7071067811865476,
			mz = -sz * 0.7071067811865476,
			cup = false,
			depth = Tables.POCKET_DEPTH,
		})
	end
	local function side(sx: number)
		addSeg(segs, R, sx * W, -h, sx * (W + J * COS14), -h + J * SIN14, true)
		addSeg(segs, R, sx * W, h, sx * (W + J * COS14), h - J * SIN14, true)
		table.insert(holes, {
			x = sx * (W + Tables.SIDE_SHELF + Tables.SIDE_HOLE_R),
			z = 0,
			r = Tables.SIDE_HOLE_R,
			mx = -sx,
			mz = 0,
			cup = false,
			depth = Tables.POCKET_DEPTH,
		})
	end
	corner(-1, -1)
	corner(1, -1)
	side(-1)
	side(1)
	corner(-1, 1)
	corner(1, 1)
	local t: Table = {
		id = "eightball",
		halfW = W,
		halfL = L,
		ballR = R,
		segs = segs,
		holes = holes,
		posts = {},
		headZ = -L / 2,
		footZ = L / 2,
		safeX = W - R,
		safeZ = L - R,
	}
	eightBallTable = t
	return t
end

-- Bumper pool dimensions (studs)
Tables.BUMPER_HALF_W = 1.9
Tables.BUMPER_HALF_L = 2.8
Tables.POST_R = 0.11
Tables.CROSS_INNER = 0.44 -- the four inner posts' distance from the centre: leaves a diagonal gap of 1.18 balls
Tables.CROSS_OUTER = 0.76
Tables.CUP_R = 0.22
Tables.CUP_Z = 2.46 -- a cup's centre, from the table's centre
Tables.CUP_DEPTH = 0.28 -- how far a ball must fall to be caught: with RIM_K it sets the speed a cup still takes
Tables.FLANK_X = 0.45 -- the two posts either side of a cup
Tables.MARKED_OFF = 0.62 -- the marked ball's spot, in front of the cup
Tables.SPOT_X = { 0.9, 1.4 } -- the four other spots, either side of the cup

local bumperTable: Table? = nil

function Tables.bumper(): Table
	if bumperTable then
		return bumperTable
	end
	local R = Tables.BALL_R
	local W, L = Tables.BUMPER_HALF_W, Tables.BUMPER_HALF_L
	local segs: { Seg } = {}
	addSeg(segs, R, -W, -L, -W, L, false)
	addSeg(segs, R, W, -L, W, L, false)
	addSeg(segs, R, -W, -L, W, -L, false)
	addSeg(segs, R, -W, L, W, L, false)
	local posts: { Post } = {}
	local pr = Tables.POST_R
	for _, d in { Tables.CROSS_INNER, Tables.CROSS_OUTER } do
		table.insert(posts, { x = d, z = 0, r = pr })
		table.insert(posts, { x = -d, z = 0, r = pr })
		table.insert(posts, { x = 0, z = d, r = pr })
		table.insert(posts, { x = 0, z = -d, r = pr })
	end
	local holes: { Hole } = {}
	for _, sz in { -1, 1 } do
		table.insert(posts, { x = -Tables.FLANK_X, z = sz * Tables.CUP_Z, r = pr })
		table.insert(posts, { x = Tables.FLANK_X, z = sz * Tables.CUP_Z, r = pr })
		-- holes[1] is the cup at the head end (-z), holes[2] the cup at the foot end
		table.insert(holes, {
			x = 0,
			z = sz * Tables.CUP_Z,
			r = Tables.CUP_R,
			mx = 0,
			mz = 0,
			cup = true,
			depth = Tables.CUP_DEPTH,
		})
	end
	local t: Table = {
		id = "bumper",
		halfW = W,
		halfL = L,
		ballR = R,
		segs = segs,
		holes = holes,
		posts = posts,
		headZ = -L / 2,
		footZ = L / 2,
		safeX = W - R,
		safeZ = L - R,
	}
	bumperTable = t
	return t
end

function Tables.byId(id: string): Table
	return if id == "bumper" then Tables.bumper() else Tables.eightBall()
end

-- The opening rack: the cue ball (id 0) on the head spot and the fifteen in a triangle with its apex on the
-- foot spot, the 8 in the middle, a solid in one back corner and a stripe in the other, the rest shuffled.
-- No rack is set perfectly: every ball sits a seeded hair off its place, so no two breaks are alike.
function Tables.rack(seed: number): { Spot }
	local t = Tables.eightBall()
	local rng = Rng.new(seed)
	local R = t.ballR
	local pitch = 2 * R + Tables.RACK_GAP
	local solids = rng.shuffle({ 1, 2, 3, 4, 5, 6, 7 })
	local stripes = rng.shuffle({ 9, 10, 11, 12, 13, 14, 15 })
	local order = table.create(15, 0)
	order[5] = 8
	local flip = rng.next() < 0.5
	order[11] = table.remove(if flip then solids else stripes) :: number
	order[15] = table.remove(if flip then stripes else solids) :: number
	local rest = rng.shuffle(table.move(stripes, 1, #stripes, #solids + 1, solids))
	local k = 0
	for slot = 1, 15 do
		if order[slot] == 0 then
			k += 1
			order[slot] = rest[k]
		end
	end
	local out: { Spot } = { { id = 0, x = 0, z = t.headZ } }
	local slot = 0
	for row = 0, 4 do
		for i = 0, row do
			slot += 1
			table.insert(out, {
				id = order[slot],
				x = (i - row / 2) * pitch + rng.range(-1, 1) * Tables.RACK_JITTER,
				z = t.footZ + row * pitch * 0.8660254037844386 + rng.range(-1, 1) * Tables.RACK_JITTER,
			})
		end
	end
	return out
end

-- Bumper pool's start: side 1 owns balls 1..5 and starts round the head-end cup, side 2 owns 6..10 at the
-- foot end; balls 1 and 6 are the marked ones. sides = { true, false } leaves side 2's balls off (practice).
function Tables.bumperStart(sides: { boolean }?): { Spot }
	local out: { Spot } = {}
	for side = 1, 2 do
		if sides == nil or sides[side] then
			local sz = if side == 1 then -1 else 1
			local base = (side - 1) * 5
			local cz = sz * Tables.CUP_Z
			table.insert(out, { id = base + 1, x = 0, z = cz - sz * Tables.MARKED_OFF })
			table.insert(out, { id = base + 2, x = -Tables.SPOT_X[1], z = cz })
			table.insert(out, { id = base + 3, x = Tables.SPOT_X[1], z = cz })
			table.insert(out, { id = base + 4, x = -Tables.SPOT_X[2], z = cz })
			table.insert(out, { id = base + 5, x = Tables.SPOT_X[2], z = cz })
		end
	end
	return out
end

function Tables.inKitchen(t: Table, z: number): boolean
	return z <= t.headZ + 1e-9
end

-- Is a ball centred here wholly on the bed (clear of every cushion by `margin`)?
function Tables.onBed(t: Table, x: number, z: number, margin: number?): boolean
	local m = t.ballR + (margin or 0)
	return math.abs(x) <= t.halfW - m and math.abs(z) <= t.halfL - m
end

local function clearAt(t: Table, x: number, z: number, others: { Spot }, skipId: number?): boolean
	local need = 2 * t.ballR + 0.004
	for _, o in others do
		if o.id ~= skipId then
			local dx, dz = o.x - x, o.z - z
			if dx * dx + dz * dz < need * need then
				return false
			end
		end
	end
	for _, p in t.posts do
		local dx, dz = p.x - x, p.z - z
		local lim = p.r + t.ballR + 0.004
		if dx * dx + dz * dz < lim * lim then
			return false
		end
	end
	for _, hole in t.holes do
		local dx, dz = hole.x - x, hole.z - z
		local lim = hole.r + 0.02
		if dx * dx + dz * dz < lim * lim then
			return false
		end
	end
	return true
end

-- Can a ball be set down here? On the bed, touching nothing, not over a hole.
function Tables.canPlace(t: Table, x: number, z: number, others: { Spot }, skipId: number?): boolean
	return Tables.onBed(t, x, z, 0.002) and clearAt(t, x, z, others, skipId)
end

-- The nearest free place to (x, z), searched along z in the direction dz (the way a ball is re-spotted along
-- the long string) and then the other way. Always finds one on a table that is not full.
function Tables.freeSpot(t: Table, x: number, z: number, others: { Spot }, dz: number?): (number, number)
	local step = (dz or 1) * 0.02
	for dir = 1, 2 do
		local s = if dir == 1 then step else -step
		local zz = z
		for _ = 1, 600 do
			if not Tables.onBed(t, x, zz, 0.002) then
				break
			end
			if clearAt(t, x, zz, others, nil) then
				return x, zz
			end
			zz += s
		end
	end
	-- the whole string is taken: walk across the table
	for i = 1, 200 do
		for _, sx in { 1, -1 } do
			local xx = x + sx * i * 0.02
			if Tables.onBed(t, xx, z, 0.002) and clearAt(t, xx, z, others, nil) then
				return xx, z
			end
		end
	end
	return x, z
end

return Tables
