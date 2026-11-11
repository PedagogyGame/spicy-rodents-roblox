--!strict
-- ReplicatedStorage.Shared.Minigames.Pinball.Layout
-- What a pinball table IS, as plain data, and the one place its dimensions come from (checklist C18: what is
-- drawn is what is simulated). A table definition lists its walls, posts, pop bumpers, slingshots, flippers,
-- targets, switches (rollovers, spinners), one-way gates, kick-out holes, ramps and the plunger. Three tables
-- (TableAcorn, TableSpicy, TableSpace) are written on this one format and run on one physics core (Physics).
-- compile() turns a definition into flat arrays and a grid the physics reads at speed.
--
-- Playfield frame: x across, 0 at the player's left, WIDTH at the right; y up the table, 0 at the player's end
-- (the drain), LENGTH at the back (under the backbox); h is height above the playfield (ramps only). All in
-- studs. The playfield is the size the alley's cabinets are baked at (tools/bake/alley/Rooms.luau pinball():
-- a 2.4 x 4.9 stud playfield, a real table's 20.25 x 42 inch proportion), so one stud is about 8.5 inches and
-- the ball is a real 1 1/16 inch ball: 0.125 studs across. The table slopes toward the player; gravity in the
-- frame is along -y.
-- Angles in a definition are radians; a flipper's angle is measured from pointing straight across the table
-- toward the centre (0), positive up the table, for either hand.
-- Pure; Lune-tested (tests/unit/pinball_layout.spec.luau).
-- Interface: WIDTH, LENGTH, BALL_R, FIELD_X1, XC, TILT_RAD; MATERIALS; new(id, title) -> TableDef;
--   arc(cx, cy, r, deg0, deg1, n) -> pts; mirror(pts, xc?) -> pts; wall, post, lamp, cup; addShell (rails, arch,
--   shooter lane), addBottom (the flippers, slings, inlanes and outlanes every table shares, from a few
--   numbers); index(def) -> Index (element numbers by id); compile(def) -> Compiled; check(def) -> (ok, why?);
--   cabinetPoint(x, y, h) -> (across, up, along) for the bake and the client

local Det = require("./Det")

local Layout = {}

Layout.WIDTH = 2.4
Layout.LENGTH = 4.9
Layout.BALL_R = 0.0625
Layout.FIELD_X1 = 2.215 -- the wall between the playfield and the shooter lane
Layout.XC = 1.1075 -- the centre line of the playfield proper (the flippers straddle it)
Layout.LANE_X = 2.3075 -- the middle of the shooter lane
Layout.ARCH_Y = 3.7 -- the top arch is a half circle of radius WIDTH / 2 centred here
Layout.TILT_RAD = 0.12 -- the playfield's pitch in the cabinet as baked (what the eye sees)
local TILT_SIN, TILT_COS = 0.11971220728891936, 0.9928086358538663

Layout.CELL = 0.2 -- grid cell size
Layout.GRID_PAD = Layout.BALL_R + 0.04

export type Material = { e: number, mu: number, code: number }
-- e: how much of the speed into the surface comes back out; mu: how much of the sideways speed a hard hit rubs off
Layout.MATERIALS = {
	rubber = { e = 0.72, mu = 0.10, code = 1 }, -- rings on posts, rebound rubbers
	metal = { e = 0.38, mu = 0.04, code = 2 }, -- wire guides and ball guides: dead
	wood = { e = 0.45, mu = 0.06, code = 3 }, -- the side rails and the arch
	plastic = { e = 0.5, mu = 0.06, code = 4 }, -- slingshot bodies, lane guides
} :: { [string]: Material }

export type Wall = { mat: string, pts: { number } }
export type Post = { x: number, y: number, r: number, mat: string }
export type Bumper = { id: string, x: number, y: number, r: number }
export type Sling = { id: string, x1: number, y1: number, x2: number, y2: number }
export type Flipper = {
	id: string,
	button: "left" | "right",
	mirror: boolean, -- false: the pivot is on the left and the tip points right (a left flipper)
	x: number,
	y: number,
	len: number, -- pivot to the centre of the tip
	rBase: number,
	rTip: number,
	rest: number,
	up: number,
}
export type Target = { id: string, kind: "standup" | "drop", x1: number, y1: number, x2: number, y2: number }
export type Sensor = { id: string, kind: "rollover" | "spinner", x1: number, y1: number, x2: number, y2: number }
-- a one-way gate: a ball moving the way the gate swings (to the LEFT of a -> b) passes; one coming back is stopped
export type Gate = { id: string, x1: number, y1: number, x2: number, y2: number }
export type Saucer = {
	id: string,
	x: number,
	y: number,
	r: number, -- capture radius for the ball's centre
	maxSpeed: number, -- a faster ball skips over the hole
	vx: number, -- the kick-out
	vy: number,
	holdTicks: number,
}
export type Rail = {
	id: string,
	pts: { number }, -- x, y, h triples: the ball's path; the first point is the mouth
	mouth: number, -- half the width of the mouth
	minSpeed: number, -- slower than this along the ramp and the ball is not taken
	exitSpeed: number, -- the ball drops off the end of the wire at this speed along the last piece
	drag: number, -- 1/s on the rail
}
export type Plunger = {
	x: number,
	y: number, -- where the ball's centre rests
	vMin: number, -- launch speed at no pull
	vMax: number, -- at full pull
	pullTicks: number, -- ticks of holding for a full pull
	autoPull: number, -- 0..1: the pull the machine itself uses (ball save, multiball)
	laneTop: number, -- above this y the ball has left the shooter lane
}
export type Lamp = { id: string, x: number, y: number, colour: string }
export type TableDef = {
	id: string,
	title: string,
	gravity: number, -- studs/s^2 down the table (slope and rolling already in it)
	slopeDeg: number, -- what that gravity stands for, for the record
	drainY: number, -- a ball whose centre is below this is gone
	walls: { Wall },
	posts: { Post },
	bumpers: { Bumper },
	slings: { Sling },
	flippers: { Flipper },
	targets: { Target },
	sensors: { Sensor },
	gates: { Gate },
	saucers: { Saucer },
	rails: { Rail },
	lamps: { Lamp },
	plunger: Plunger,
}
-- element numbers by id, as the physics reports them in its events
export type Index = {
	bumper: { [string]: number },
	sling: { [string]: number },
	flipper: { [string]: number },
	target: { [string]: number },
	sensor: { [string]: number },
	gate: { [string]: number },
	saucer: { [string]: number },
	rail: { [string]: number },
	lamp: { [string]: number },
}

-- segment kinds
Layout.SEG_WALL = 1
Layout.SEG_STANDUP = 2
Layout.SEG_DROP = 3
Layout.SEG_SLING = 4
Layout.SEG_GATE = 5
-- circle kinds
Layout.CIR_POST = 1
Layout.CIR_BUMPER = 2
-- sensor kinds
Layout.SEN_ROLLOVER = 1
Layout.SEN_SPINNER = 2
Layout.SEN_RAIL = 3

export type Compiled = {
	def: TableDef,
	gravity: number,
	drainY: number,
	-- segments
	nSeg: number,
	sx: { number },
	sy: { number },
	sdx: { number },
	sdy: { number },
	sInv: { number }, -- 1 / length^2
	sLen: { number },
	sKind: { number },
	sE: { number },
	sMu: { number },
	sMat: { number },
	sRef: { number }, -- index into targets / slings / gates
	-- circles
	nCir: number,
	cx: { number },
	cy: { number },
	cr: { number },
	cKind: { number },
	cE: { number },
	cMu: { number },
	cRef: { number },
	-- the grid: per cell a list of collider numbers (segment i as +i, circle i as -i)
	gridW: number,
	gridH: number,
	grid: { { number } },
	-- sensors (rollovers, spinners and ramp mouths), all checked for a crossing
	nSen: number,
	nx1: { number },
	ny1: { number },
	ndx: { number },
	ndy: { number },
	nInv: { number },
	nKind: { number },
	nRef: { number }, -- index into def.sensors, or into def.rails for a mouth
	sgrid: { { number } },
	-- flippers
	nFlip: number,
	fpx: { number },
	fpy: { number },
	flen: { number },
	frb: { number },
	frt: { number },
	frest: { number },
	fup: { number },
	fmir: { number }, -- +1 or -1
	fbtn: { number }, -- 1 left button, 2 right button
	fb: { number }, -- taper: (rBase - rTip) / len
	fa: { number }, -- sqrt(1 - fb^2)
	freach: { number }, -- pivot to the far end of the tip
	-- rails: per rail the cumulative length at each point and the points themselves
	rails: { CompiledRail },
	nDrop: number, -- how many drop targets (their indices into def.targets are in dropTargets)
	dropTargets: { number },
	spinners: { number }, -- sensor numbers that are spinners
}
export type CompiledRail = {
	n: number, -- points
	x: { number },
	y: { number },
	h: { number },
	at: { number }, -- distance along the rail at each point
	tx: { number }, -- unit direction of each piece
	ty: { number },
	slope: { number }, -- dh/ds of each piece
	total: number,
	minSpeed: number,
	exitSpeed: number,
	drag: number,
}

function Layout.new(id: string, title: string): TableDef
	return {
		id = id,
		title = title,
		gravity = 3.64,
		slopeDeg = 6.5,
		drainY = 0.12,
		walls = {},
		posts = {},
		bumpers = {},
		slings = {},
		flippers = {},
		targets = {},
		sensors = {},
		gates = {},
		saucers = {},
		rails = {},
		lamps = {},
		plunger = {
			x = Layout.LANE_X,
			y = 0.3 + Layout.BALL_R,
			vMin = 3.0,
			vMax = 9.6,
			pullTicks = 288,
			autoPull = 0.86,
			laneTop = 3.6,
		},
	}
end

-- gravity down the table for a slope in degrees: a rolling ball takes 5/7 of g sin(slope); g is 9.81 m/s^2 at
-- this table's scale (4.9 studs to 42 inches).
function Layout.gravityFor(slopeDeg: number): number
	local metre = Layout.LENGTH / (42 * 0.0254)
	return 9.81 * metre * Det.sin(Det.rad(slopeDeg)) * 5 / 7
end

-- arc(cx, cy, r, deg0, deg1, n): n + 1 points round a circle from deg0 to deg1 (0 = +x, 90 = up the table).
function Layout.arc(cx: number, cy: number, r: number, deg0: number, deg1: number, n: number): { number }
	local pts: { number } = {}
	for i = 0, n do
		local a = Det.rad(deg0 + (deg1 - deg0) * i / n)
		table.insert(pts, cx + r * Det.cos(a))
		table.insert(pts, cy + r * Det.sin(a))
	end
	return pts
end

-- mirror(pts, xc): the same points on the other side of the playfield's centre line.
function Layout.mirror(pts: { number }, xc: number?): { number }
	local c = xc or Layout.XC
	local out: { number } = table.create(#pts)
	for i = 1, #pts, 2 do
		out[i] = 2 * c - pts[i]
		out[i + 1] = pts[i + 1]
	end
	return out
end

function Layout.wall(def: TableDef, mat: string, pts: { number })
	table.insert(def.walls, { mat = mat, pts = pts })
end

function Layout.post(def: TableDef, x: number, y: number, r: number?, mat: string?)
	table.insert(def.posts, { x = x, y = y, r = r or 0.022, mat = mat or "rubber" })
end

function Layout.lamp(def: TableDef, id: string, x: number, y: number, colour: string)
	table.insert(def.lamps, { id = id, x = x, y = y, colour = colour })
end

-- cup(def, x, y, r, openDeg, spanDeg): a metal horseshoe behind a kick-out hole at x, y, open toward openDeg
-- (0 = +x, 90 = up the table), so a ball shot into it rattles dead and drops in.
function Layout.cup(def: TableDef, x: number, y: number, r: number, openDeg: number, spanDeg: number?)
	local half = (360 - (spanDeg or 150)) / 2
	Layout.wall(def, "metal", Layout.arc(x, y, r, openDeg + 180 - half, openDeg + 180 + half, 10))
end

function Layout.index(def: TableDef): Index
	local ix: Index = {
		bumper = {},
		sling = {},
		flipper = {},
		target = {},
		sensor = {},
		gate = {},
		saucer = {},
		rail = {},
		lamp = {},
	}
	for i, v in def.bumpers do
		ix.bumper[v.id] = i
	end
	for i, v in def.slings do
		ix.sling[v.id] = i
	end
	for i, v in def.flippers do
		ix.flipper[v.id] = i
	end
	for i, v in def.targets do
		ix.target[v.id] = i
	end
	for i, v in def.sensors do
		ix.sensor[v.id] = i
	end
	for i, v in def.gates do
		ix.gate[v.id] = i
	end
	for i, v in def.saucers do
		ix.saucer[v.id] = i
	end
	for i, v in def.rails do
		ix.rail[v.id] = i
	end
	for i, v in def.lamps do
		ix.lamp[v.id] = i
	end
	return ix
end

-- The outer shell every table shares: the left rail, the arch over the top, the right rail, the shooter lane
-- with the plunger at its foot and the one-way gate at its head.
function Layout.addShell(def: TableDef)
	local W, AY = Layout.WIDTH, Layout.ARCH_Y
	local pts = { 0, 0 }
	for _, v in Layout.arc(W / 2, AY, W / 2, 180, 0, 48) do
		table.insert(pts, v)
	end
	table.insert(pts, W)
	table.insert(pts, 0.2)
	Layout.wall(def, "wood", pts)
	local x1 = Layout.FIELD_X1
	-- the lane's inner wall and the plunger tip the ball rests on
	Layout.wall(def, "wood", { x1, 0, x1, 3.52 })
	Layout.wall(def, "rubber", { x1, 0.3, W, 0.3 })
	-- the gate at the head of the lane slants down toward the playfield, so a ball that only just clears it
	-- rolls off its end into the table
	table.insert(def.gates, { id = "lane_gate", x1 = x1, y1 = 3.52, x2 = W, y2 = 3.62 })
end

export type BottomSpec = {
	gap: number, -- clear space between the flipper tips at rest
	outlane: number, -- width of each outlane
	inlane: number, -- width of each inlane
	pivotY: number,
	len: number?,
	rest: number?,
	up: number?,
}

-- The bottom of the table every machine shares in shape: two flippers, a slingshot above each, an inlane that
-- feeds each flipper and an outlane outside it that does not. Sensors: inlane_l, inlane_r, outlane_l, outlane_r.
function Layout.addBottom(def: TableDef, spec: BottomSpec)
	local XC = Layout.XC
	local len = spec.len or 0.33
	local rBase, rTip = 0.045, 0.028
	local rest = spec.rest or Det.rad(-30)
	local up = spec.up or Det.rad(28)
	local px = XC - spec.gap / 2 - rTip - len * Det.cos(rest)
	local py = spec.pivotY
	table.insert(def.flippers, {
		id = "flipper_l",
		button = "left",
		mirror = false,
		x = px,
		y = py,
		len = len,
		rBase = rBase,
		rTip = rTip,
		rest = rest,
		up = up,
	})
	table.insert(def.flippers, {
		id = "flipper_r",
		button = "right",
		mirror = true,
		x = 2 * XC - px,
		y = py,
		len = len,
		rBase = rBase,
		rTip = rTip,
		rest = rest,
		up = up,
	})
	-- the inlane guide runs down to the flipper at the flipper's own resting slope, so a ball rolls off the
	-- guide and along the flipper without a step
	local slope = -Det.sin(rest) / Det.cos(rest)
	local xo = spec.outlane
	local xi = xo + spec.inlane
	local gx1, gy1 = px - 0.012, py + rBase - 0.004
	local gy0 = gy1 + (gx1 - xo) * slope
	local function guideY(x: number): number
		return gy0 - (x - xo) * slope
	end
	local chan = 0.2 -- the channel under the slingshot, measured straight up
	local bx, by = xi, guideY(xi) + chan
	local cxs = px - 0.1
	local cys = guideY(cxs) + chan
	local ax, ay = xi, by + 0.38
	local divTop = gy0 + 0.42
	local left: { { mat: string, pts: { number } } } = {
		{ mat = "metal", pts = { xo, divTop, xo, gy0, gx1, gy1 } }, -- the divider and the inlane guide
		{ mat = "plastic", pts = { ax, ay, bx, by, cxs, cys } }, -- the slingshot's back and foot
	}
	for _, w in left do
		Layout.wall(def, w.mat, w.pts)
		Layout.wall(def, w.mat, Layout.mirror(w.pts))
	end
	for _, p in { { xo, divTop }, { ax, ay }, { bx, by }, { cxs, cys } } do
		Layout.post(def, p[1], p[2], 0.022, "rubber")
		Layout.post(def, 2 * XC - p[1], p[2], 0.022, "rubber")
	end
	table.insert(def.slings, { id = "sling_l", x1 = ax, y1 = ay, x2 = cxs, y2 = cys })
	table.insert(def.slings, { id = "sling_r", x1 = 2 * XC - ax, y1 = ay, x2 = 2 * XC - cxs, y2 = cys })
	local sy = gy0 + 0.16
	table.insert(def.sensors, { id = "outlane_l", kind = "rollover", x1 = 0, y1 = sy, x2 = xo, y2 = sy })
	table.insert(def.sensors, { id = "inlane_l", kind = "rollover", x1 = xo, y1 = sy, x2 = xi, y2 = sy })
	local X1 = Layout.FIELD_X1
	table.insert(def.sensors, { id = "outlane_r", kind = "rollover", x1 = X1 - xo, y1 = sy, x2 = X1, y2 = sy })
	table.insert(def.sensors, { id = "inlane_r", kind = "rollover", x1 = X1 - xi, y1 = sy, x2 = X1 - xo, y2 = sy })
end

-- addRamp(def, rail): a ramp is a rail (the ball's path, up off the playfield) plus what stands on the playfield
-- at its foot: the two flanks of the ramp for 0.4 studs behind the mouth and the wall under it, so a ball
-- cannot roll in beside or under the ramp. Rubber posts at the two corners of the mouth. Returns the four
-- corners of that body: mouth left, back left, back right, mouth right (left and right as the ball goes up).
function Layout.addRamp(def: TableDef, rail: Rail): { number }
	table.insert(def.rails, rail)
	local x0, y0 = rail.pts[1], rail.pts[2]
	local dx, dy = rail.pts[4] - x0, rail.pts[5] - y0
	local d = math.sqrt(dx * dx + dy * dy)
	local tx, ty = dx / d, dy / d
	local m = rail.mouth
	local depth = 0.4
	local lx, ly = x0 - ty * m, y0 + tx * m
	local rx, ry = x0 + ty * m, y0 - tx * m
	Layout.wall(def, "plastic", {
		lx,
		ly,
		lx + tx * depth,
		ly + ty * depth,
		rx + tx * depth,
		ry + ty * depth,
		rx,
		ry,
	})
	Layout.post(def, lx, ly, 0.022, "rubber")
	Layout.post(def, rx, ry, 0.022, "rubber")
	return { lx, ly, lx + tx * depth, ly + ty * depth, rx + tx * depth, ry + ty * depth, rx, ry }
end

-- Where the end of a ramp's wire should drop a ball so it rolls down an inlane to a flipper.
function Layout.inlaneDrop(def: TableDef, side: "left" | "right"): (number, number)
	for _, s in def.sensors do
		if s.id == (if side == "left" then "inlane_l" else "inlane_r") then
			return (s.x1 + s.x2) / 2, s.y1 + 0.12
		end
	end
	error("the table has no inlanes yet")
end

local function cellRange(lo: number, hi: number, count: number): (number, number)
	local a = math.clamp(math.floor(lo / Layout.CELL), 0, count - 1)
	local b = math.clamp(math.floor(hi / Layout.CELL), 0, count - 1)
	return a, b
end

function Layout.compile(def: TableDef): Compiled
	local gridW = math.ceil(Layout.WIDTH / Layout.CELL)
	local gridH = math.ceil(Layout.LENGTH / Layout.CELL) + 1
	local grid: { { number } } = table.create(gridW * gridH)
	local sgrid: { { number } } = table.create(gridW * gridH)
	for i = 1, gridW * gridH do
		grid[i] = {}
		sgrid[i] = {}
	end
	local c: Compiled = {
		def = def,
		gravity = def.gravity,
		drainY = def.drainY,
		nSeg = 0,
		sx = {},
		sy = {},
		sdx = {},
		sdy = {},
		sInv = {},
		sLen = {},
		sKind = {},
		sE = {},
		sMu = {},
		sMat = {},
		sRef = {},
		nCir = 0,
		cx = {},
		cy = {},
		cr = {},
		cKind = {},
		cE = {},
		cMu = {},
		cRef = {},
		gridW = gridW,
		gridH = gridH,
		grid = grid,
		nSen = 0,
		nx1 = {},
		ny1 = {},
		ndx = {},
		ndy = {},
		nInv = {},
		nKind = {},
		nRef = {},
		sgrid = sgrid,
		nFlip = 0,
		fpx = {},
		fpy = {},
		flen = {},
		frb = {},
		frt = {},
		frest = {},
		fup = {},
		fmir = {},
		fbtn = {},
		fb = {},
		fa = {},
		freach = {},
		rails = {},
		nDrop = 0,
		dropTargets = {},
		spinners = {},
	}
	local PAD = Layout.GRID_PAD

	local function mark(into: { { number } }, x0: number, y0: number, x1: number, y1: number, value: number)
		local ix0, ix1 = cellRange(math.min(x0, x1) - PAD, math.max(x0, x1) + PAD, gridW)
		local iy0, iy1 = cellRange(math.min(y0, y1) - PAD, math.max(y0, y1) + PAD, gridH)
		for iy = iy0, iy1 do
			for ix = ix0, ix1 do
				table.insert(into[iy * gridW + ix + 1], value)
			end
		end
	end

	local function seg(x1: number, y1: number, x2: number, y2: number, kind: number, mat: Material, ref: number)
		local dx, dy = x2 - x1, y2 - y1
		local len2 = dx * dx + dy * dy
		if len2 < 1e-12 then
			return
		end
		local i = c.nSeg + 1
		c.nSeg = i
		c.sx[i], c.sy[i], c.sdx[i], c.sdy[i] = x1, y1, dx, dy
		c.sInv[i] = 1 / len2
		c.sLen[i] = math.sqrt(len2)
		c.sKind[i], c.sE[i], c.sMu[i], c.sMat[i], c.sRef[i] = kind, mat.e, mat.mu, mat.code, ref
		mark(grid, x1, y1, x2, y2, i)
	end

	local function circle(x: number, y: number, r: number, kind: number, mat: Material, ref: number)
		local i = c.nCir + 1
		c.nCir = i
		c.cx[i], c.cy[i], c.cr[i], c.cKind[i], c.cE[i], c.cMu[i], c.cRef[i] = x, y, r, kind, mat.e, mat.mu, ref
		mark(grid, x - r, y - r, x + r, y + r, -i)
	end

	local function sensor(x1: number, y1: number, x2: number, y2: number, kind: number, ref: number): number
		local dx, dy = x2 - x1, y2 - y1
		local i = c.nSen + 1
		c.nSen = i
		c.nx1[i], c.ny1[i], c.ndx[i], c.ndy[i] = x1, y1, dx, dy
		c.nInv[i] = 1 / (dx * dx + dy * dy)
		c.nKind[i], c.nRef[i] = kind, ref
		mark(sgrid, x1, y1, x2, y2, i)
		return i
	end

	local M = Layout.MATERIALS
	for _, w in def.walls do
		local mat = M[w.mat]
		assert(mat, `unknown material {w.mat}`)
		for i = 1, #w.pts - 3, 2 do
			seg(w.pts[i], w.pts[i + 1], w.pts[i + 2], w.pts[i + 3], Layout.SEG_WALL, mat, 0)
		end
	end
	for _, p in def.posts do
		local mat = M[p.mat]
		assert(mat, `unknown material {p.mat}`)
		circle(p.x, p.y, p.r, Layout.CIR_POST, mat, 0)
	end
	for i, b in def.bumpers do
		circle(b.x, b.y, b.r, Layout.CIR_BUMPER, M.rubber, i)
	end
	for i, s in def.slings do
		seg(s.x1, s.y1, s.x2, s.y2, Layout.SEG_SLING, M.rubber, i)
	end
	for i, t in def.targets do
		if t.kind == "drop" then
			c.nDrop += 1
			table.insert(c.dropTargets, i)
			seg(t.x1, t.y1, t.x2, t.y2, Layout.SEG_DROP, M.plastic, i)
		else
			seg(t.x1, t.y1, t.x2, t.y2, Layout.SEG_STANDUP, M.plastic, i)
		end
	end
	for i, g in def.gates do
		seg(g.x1, g.y1, g.x2, g.y2, Layout.SEG_GATE, M.metal, i)
	end
	for i, s in def.sensors do
		local n =
			sensor(s.x1, s.y1, s.x2, s.y2, if s.kind == "spinner" then Layout.SEN_SPINNER else Layout.SEN_ROLLOVER, i)
		if s.kind == "spinner" then
			table.insert(c.spinners, n)
		end
	end
	for i, r in def.rails do
		local n = #r.pts // 3
		assert(n >= 2, `rail {r.id} needs two points`)
		local cr: CompiledRail = {
			n = n,
			x = {},
			y = {},
			h = {},
			at = {},
			tx = {},
			ty = {},
			slope = {},
			total = 0,
			minSpeed = r.minSpeed,
			exitSpeed = r.exitSpeed,
			drag = r.drag,
		}
		local along = 0
		for k = 1, n do
			local x, y, h = r.pts[k * 3 - 2], r.pts[k * 3 - 1], r.pts[k * 3]
			if k > 1 then
				local dx, dy = x - cr.x[k - 1], y - cr.y[k - 1]
				local d = math.sqrt(dx * dx + dy * dy)
				assert(d > 1e-6, `rail {r.id} repeats a point`)
				cr.tx[k - 1], cr.ty[k - 1] = dx / d, dy / d
				cr.slope[k - 1] = (h - cr.h[k - 1]) / d
				along += d
			end
			cr.x[k], cr.y[k], cr.h[k], cr.at[k] = x, y, h, along
		end
		cr.total = along
		c.rails[i] = cr
		-- the mouth: a line across the first piece, at the first point, laid so that a ball going up the ramp
		-- crosses it to its left
		local tx, ty = cr.tx[1], cr.ty[1]
		sensor(
			cr.x[1] - ty * r.mouth,
			cr.y[1] + tx * r.mouth,
			cr.x[1] + ty * r.mouth,
			cr.y[1] - tx * r.mouth,
			Layout.SEN_RAIL,
			i
		)
	end
	for i, f in def.flippers do
		c.nFlip = i
		c.fpx[i], c.fpy[i], c.flen[i], c.frb[i], c.frt[i] = f.x, f.y, f.len, f.rBase, f.rTip
		c.frest[i], c.fup[i] = f.rest, f.up
		c.fmir[i] = if f.mirror then -1 else 1
		c.fbtn[i] = if f.button == "left" then 1 else 2
		local b = (f.rBase - f.rTip) / f.len
		c.fb[i] = b
		c.fa[i] = math.sqrt(1 - b * b)
		c.freach[i] = f.len + f.rTip
	end
	return c
end

local function inField(x: number, y: number): boolean
	return x >= -1e-9 and x <= Layout.WIDTH + 1e-9 and y >= -1e-9 and y <= Layout.LENGTH + 1e-9
end

-- check(def): a definition is whole and inside the cabinet (ids unique, numbers finite, everything on the
-- playfield). The specs run it on all three tables.
function Layout.check(def: TableDef): (boolean, string?)
	local seen: { [string]: boolean } = {}
	local function id(kind: string, name: string): string?
		if name == "" then
			return `{kind} without an id`
		end
		if seen[name] then
			return `id {name} used twice`
		end
		seen[name] = true
		return nil
	end
	local function pt(what: string, x: number, y: number): string?
		if x ~= x or y ~= y or not inField(x, y) then
			return `{what} at {x}, {y} is off the playfield`
		end
		return nil
	end
	for _, w in def.walls do
		if Layout.MATERIALS[w.mat] == nil then
			return false, `unknown material {w.mat}`
		end
		if #w.pts < 4 or #w.pts % 2 ~= 0 then
			return false, "a wall needs at least two points"
		end
		for i = 1, #w.pts, 2 do
			local why = pt("wall point", w.pts[i], w.pts[i + 1])
			if why then
				return false, why
			end
		end
	end
	for _, p in def.posts do
		local why = pt("post", p.x, p.y)
		if why then
			return false, why
		end
	end
	for _, b in def.bumpers do
		local why = id("bumper", b.id) or pt(b.id, b.x, b.y)
		if why then
			return false, why
		end
	end
	for _, s in def.slings do
		local why = id("sling", s.id) or pt(s.id, s.x1, s.y1) or pt(s.id, s.x2, s.y2)
		if why then
			return false, why
		end
	end
	for _, t in def.targets do
		local why = id("target", t.id) or pt(t.id, t.x1, t.y1) or pt(t.id, t.x2, t.y2)
		if why then
			return false, why
		end
	end
	for _, s in def.sensors do
		local why = id("sensor", s.id) or pt(s.id, s.x1, s.y1) or pt(s.id, s.x2, s.y2)
		if why then
			return false, why
		end
	end
	for _, g in def.gates do
		local why = id("gate", g.id) or pt(g.id, g.x1, g.y1) or pt(g.id, g.x2, g.y2)
		if why then
			return false, why
		end
	end
	for _, s in def.saucers do
		local why = id("saucer", s.id) or pt(s.id, s.x, s.y)
		if why then
			return false, why
		end
		if s.holdTicks < 1 or s.maxSpeed <= 0 then
			return false, `saucer {s.id} needs a hold time and a capture speed`
		end
	end
	for _, r in def.rails do
		local why = id("rail", r.id)
		if why then
			return false, why
		end
		if #r.pts < 6 or #r.pts % 3 ~= 0 then
			return false, `rail {r.id} needs x, y, h triples`
		end
		for i = 1, #r.pts, 3 do
			why = pt(r.id, r.pts[i], r.pts[i + 1])
			if why then
				return false, why
			end
		end
	end
	for _, l in def.lamps do
		local why = id("lamp", "lamp:" .. l.id) or pt(l.id, l.x, l.y)
		if why then
			return false, why
		end
	end
	for _, f in def.flippers do
		local why = id("flipper", f.id) or pt(f.id, f.x, f.y)
		if why then
			return false, why
		end
		if not (f.up > f.rest) or f.rTip > f.rBase or f.len <= 0 then
			return false, `flipper {f.id} is malformed`
		end
	end
	if #def.flippers < 2 then
		return false, "a table needs two flippers"
	end
	if not (def.gravity > 0) then
		return false, "gravity"
	end
	return true
end

-- cabinetPoint(x, y, h): a playfield point in the cabinet's own frame, measured from the middle of the
-- playfield: across (the player's right +), up, and along (toward the backbox +). The bake places the
-- playfield part at its middle with this pitch; the client draws the ball and the flippers through this.
function Layout.cabinetPoint(x: number, y: number, h: number): (number, number, number)
	local along = y - Layout.LENGTH / 2
	return x - Layout.WIDTH / 2, along * TILT_SIN + h * TILT_COS, along * TILT_COS - h * TILT_SIN
end

return Layout
