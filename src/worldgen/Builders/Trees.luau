--!strict
-- ServerScriptService.Server.WorldGen.Builders.Trees
-- Full, leafy shade trees drawn around their harvested climbing routes (review 2026-11-09, the
-- owner's first complaint: "bare noodle branches and tiny lollipop leaves"). The routes stay exactly
-- where they are; only the visuals change:
--   * bark: round cylinders in bark colours (a little variation per tree). The trunk tapers the way
--     the squirrel's trunk offset does (Routes/Motion visualPose: r(1 - 0.48t), giants r/0.95 - 1.05 u
--     t), boughs taper from about the squirrel's bough lift (Motion: 0.5 u, apples 0.3 u, lookouts
--     0.61 u) at the trunk to 60 % at the tip, so the squirrel's feet stay on the bark; short twigs
--     splay from the bough tips into the leaves, and a root flare meets the ground.
--   * crown: many large overlapping leaf clusters (balls of 5-14 studs in 3-4 v5.4 greens per tree,
--     each cluster shaded by height and jittered), along the outer two thirds of every bough, around
--     the bough tips and over a crown dome, so from the street the canopy is one leafy mass and the
--     long living-bridge boughs are mostly hidden in foliage.
--   * a clear tunnel along every climbing route (v5.4 lifted its leaves off walkways): no cluster
--     comes within 1.6 studs of the squirrel's body on a bough (centreline + 2 studs) or within 2.2
--     studs of the trunk's climbing surface, so the squirrel stays visible.
--   * Quay willows get drooping curtains of hanging foliage; apple trees get a few apples.
-- Leaves and twigs neither collide nor take queries (rails, the camera and raycasts see only bark);
-- leaves cast shadows. Deterministic (integer xorshift seeded by the trunk route id).
-- Interface: build(list, trunk, members, opts) where members are polylines { route, line } (the trunk
--   among them) and opts = { groundAt = (x, z, maxY?) -> (y, onPart), maxLeaves? }. Returns the leaf
--   count. Pure.

local Palette = require("../Palette")
local Spec = require("../Spec")

local Trees = {}

local SPU = Spec.SPU
local ORIGIN = { cx = 0, cy = 0, cz = 0, yaw = 0, c = 1, s = 0 }

export type Member = { route: any, line: { { number } } }

-- deterministic xorshift32 in [0, 1)
local function rng(seed: number): () -> number
	local s = (seed * 2654435761 + 12345) % 4294967296
	if s == 0 then
		s = 0x9e3779b9
	end
	return function(): number
		s = bit32.bxor(s, bit32.lshift(s, 13))
		s = bit32.bxor(s, bit32.rshift(s, 17))
		s = bit32.bxor(s, bit32.lshift(s, 5))
		return s / 4294967296
	end
end

local function sub(a: { number }, b: { number }): { number }
	return { a[1] - b[1], a[2] - b[2], a[3] - b[3] }
end
local function len3(v: { number }): number
	return math.sqrt(v[1] * v[1] + v[2] * v[2] + v[3] * v[3])
end
local function unit(v: { number }): { number }
	local l = len3(v)
	if l < 1e-9 then
		return { 0, 1, 0 }
	end
	return { v[1] / l, v[2] / l, v[3] / l }
end
local function cross(a: { number }, b: { number }): { number }
	return { a[2] * b[3] - a[3] * b[2], a[3] * b[1] - a[1] * b[3], a[1] * b[2] - a[2] * b[1] }
end

local function segDist(a: { number }, b: { number }, p: { number }): number
	local abx, aby, abz = b[1] - a[1], b[2] - a[2], b[3] - a[3]
	local apx, apy, apz = p[1] - a[1], p[2] - a[2], p[3] - a[3]
	local l2 = abx * abx + aby * aby + abz * abz
	local t = if l2 > 0 then math.clamp((apx * abx + apy * aby + apz * abz) / l2, 0, 1) else 0
	local dx, dy, dz = apx - abx * t, apy - aby * t, apz - abz * t
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- Cumulative arc lengths of a polyline.
local function arcs(line: { { number } }): ({ number }, number)
	local c = { 0 }
	local total = 0
	for k = 2, #line do
		total += len3(sub(line[k], line[k - 1]))
		c[k] = total
	end
	return c, total
end

-- Point and unit tangent at arc length s.
local function at(line: { { number } }, c: { number }, s: number): ({ number }, { number })
	for k = 2, #line do
		if s <= c[k] or k == #line then
			local seg = c[k] - c[k - 1]
			local f = if seg > 0 then math.clamp((s - c[k - 1]) / seg, 0, 1) else 0
			local a, b = line[k - 1], line[k]
			return { a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f, a[3] + (b[3] - a[3]) * f }, unit(sub(b, a))
		end
	end
	return line[1], { 0, 1, 0 }
end

-- A cylinder from a to b (axis = local X), radius r, extended `ext` at both ends to close joints.
local function cylinder(list: Spec.PartList, name: string, a: { number }, b: { number }, r: number, ext: number, o: Spec.Opts)
	local d = sub(b, a)
	local l = len3(d)
	if l < 1e-4 then
		return
	end
	local roll = math.asin(math.clamp(d[2] / l, -1, 1))
	local yaw = math.atan2(-d[3], d[1])
	local opts = table.clone(o)
	opts.yaw, opts.roll, opts.shape = yaw, roll, "Cylinder"
	list:add(ORIGIN :: any, name, (a[1] + b[1]) / 2, (a[2] + b[2]) / 2, (a[3] + b[3]) / 2, l + 2 * ext, 2 * r, 2 * r, opts)
end

local function shade(c: { number }, f: number): { number }
	return {
		math.clamp(math.floor(c[1] * f + 0.5), 0, 255),
		math.clamp(math.floor(c[2] * f + 0.5), 0, 255),
		math.clamp(math.floor(c[3] * f + 0.5), 0, 255),
	}
end

local hex = Palette.hex
local GREENS = {
	default = { hex("#769377"), hex("#6a8c3e"), hex("#586f5b"), hex("#7d9a4f") },
	warm = { hex("#6a8c3e"), hex("#89ab55"), hex("#7d9a4f"), hex("#586f5b") },
	cool = { hex("#769377"), hex("#586f5b"), hex("#6a8c3e"), hex("#7d9a4f") },
	willow = { hex("#769377"), hex("#95a580"), hex("#586f5b") },
	oak = { hex("#6a8c3e"), hex("#89ab55"), hex("#a4bb66"), hex("#586f5b") },
}
local BARKS = { hex("#655342"), hex("#5d4c3d"), hex("#6b5a48"), hex("#594a3e") }

-- Bough lift above its centreline where the squirrel's feet are (Routes/Motion §14), in studs.
local function lift(route: any): number
	if route.visualOffset then
		return route.visualOffset
	end
	return if route.kind == "lookout" then 0.61 * SPU else 0.5 * SPU
end

local function trunkRadius(route: any, t: number): number
	local r = route.surfaceRadius
	if string.find(string.lower(route.name or ""), "giant trunk", 1, true) then
		return math.max(0.45 * SPU, r / 0.95 - 1.05 * SPU * t)
	end
	return math.max(0.32 * SPU, r * (1 - 0.48 * t))
end

export type Opts = { groundAt: (number, number, number?) -> (number, boolean), maxLeaves: number? }

function Trees.build(list: Spec.PartList, trunk: any, members: { Member }, opts: Opts): number
	local rand = rng(trunk.id + 7)
	local name = string.upper(trunk.name or "")
	local willow = string.find(name, "WILLOW", 1, true) ~= nil
	local apple = string.find(name, "APPLE", 1, true) ~= nil
	local foot = trunk.points[1]
	local top = trunk.points[#trunk.points]
	local H = math.max(top[2] - foot[2], 6)
	local barkColor = BARKS[(trunk.id % #BARKS) + 1]
	local greens = if willow
		then GREENS.willow
		elseif string.find(name, "TREEHOUSE", 1, true) or apple then GREENS.oak
		else ({ GREENS.default, GREENS.warm, GREENS.cool })[(trunk.id % 3) + 1]

	-- sizes scale with the tree (apples ~16 st, outer trees ~40, giants ~120)
	local scale = math.clamp(H / 44, 0.55, 1.45)
	local barkOpts: Spec.Opts = { color = barkColor, material = "Wood", role = "Limb" }

	local trunkLine: { { number } } = {}
	for _, m in members do
		if m.route == trunk then
			trunkLine = m.line
		end
	end
	if #trunkLine < 2 then
		trunkLine = { foot, top }
	end
	local tc, tl = arcs(trunkLine)

	-- 1. bark --------------------------------------------------------------------------------------
	-- trunk: pieces of at most 8 studs, each at the squirrel's tapered trunk radius
	local nT = math.max(2, math.ceil(tl / 8))
	for k = 1, nT do
		local a = at(trunkLine, tc, tl * (k - 1) / nT)
		local b = at(trunkLine, tc, tl * k / nT)
		local r = trunkRadius(trunk, (k - 0.5) / nT)
		cylinder(
			list,
			`Trunk_{k}`,
			a,
			b,
			r,
			if k == 1 then 0 else r * 0.25,
			if k == 1 then { color = barkColor, material = "Wood", role = "Limb", attrs = { Embedded = true } } else barkOpts
		)
	end
	-- root flare (skipped where the trunk stands at a kerb, road or sidewalk: no bark on the paving)
	local g, paved = opts.groundAt(foot[1], foot[3], foot[2] + 2)
	local r0 = trunkRadius(trunk, 0)
	if not paved then
		cylinder(list, "Flare", { foot[1], g - 1.2, foot[3] }, { foot[1], g + 0.9 * scale, foot[3] }, r0 * 1.16, 0, {
			color = barkColor,
			material = "Wood",
			canCollide = false,
			canQuery = false,
			castShadow = true,
			role = "Twig",
			attrs = { Embedded = true },
		})
	end
	if g < foot[2] - 0.05 then
		-- the trunk route starts above the ground: carry the bark down into it
		cylinder(list, "TrunkFoot", { foot[1], g - 1, foot[3] }, foot, r0, 0, {
			color = barkColor,
			material = "Wood",
			role = "Limb",
			attrs = { Embedded = true },
		})
	end

	-- trunk radius at a height (for bough bases and the trunk tunnel)
	local function trunkRAtY(y: number): number
		return trunkRadius(trunk, math.clamp((y - foot[2]) / H, 0, 1))
	end

	-- boughs: taper from about the squirrel's lift to 60 % of it at the tip; twigs at branch tips
	type Bough = { route: any, line: { { number } }, c: { number }, L: number }
	local boughs: { Bough } = {}
	for _, m in members do
		if m.route ~= trunk and #m.line >= 2 then
			local c, L = arcs(m.line)
			if L > 0.5 then
				table.insert(boughs, { route = m.route, line = m.line, c = c, L = L })
			end
		end
	end
	for _, b in boughs do
		local lf = lift(b.route)
		local base = math.min(lf * 0.95, trunkRAtY(b.line[1][2]) * 0.85)
		local tip = math.max(0.35, lf * 0.6)
		local n = #b.line - 1
		local piece = 0
		for k = 1, n do
			local a, e = b.line[k], b.line[k + 1]
			local sl = len3(sub(e, a))
			local parts = math.max(1, math.ceil(sl / 11))
			for j = 1, parts do
				piece += 1
				local f0, f1 = (j - 1) / parts, j / parts
				local p0 = { a[1] + (e[1] - a[1]) * f0, a[2] + (e[2] - a[2]) * f0, a[3] + (e[3] - a[3]) * f0 }
				local p1 = { a[1] + (e[1] - a[1]) * f1, a[2] + (e[2] - a[2]) * f1, a[3] + (e[3] - a[3]) * f1 }
				local u = (b.c[k] + sl * (f0 + f1) / 2) / b.L
				local r = base + (tip - base) * u
				cylinder(list, `R{b.route.id}_{piece}`, p0, p1, r, r * 0.6, barkOpts)
			end
		end
		if b.route.kind == "branch" then
			local e = b.line[#b.line]
			local _, d = at(b.line, b.c, b.L)
			local side = unit(cross(d, { 0, 1, 0 }))
			for k, s in { -1, 1 } do
				local twigLen = (4 + 3 * rand()) * scale
				local dir = unit({
					d[1] * 0.75 + side[1] * s * 0.6,
					d[2] * 0.75 + 0.35,
					d[3] * 0.75 + side[3] * s * 0.6,
				})
				cylinder(list, `Twig{b.route.id}_{k}`, e, {
					e[1] + dir[1] * twigLen,
					e[2] + dir[2] * twigLen,
					e[3] + dir[3] * twigLen,
				}, math.max(0.22, tip * 0.45), 0.1, {
					color = barkColor,
					material = "Wood",
					canCollide = false,
					canQuery = false,
					castShadow = false,
					role = "Twig",
				})
			end
		end
	end

	-- 2. leaf clusters ---------------------------------------------------------------------------
	-- tunnels: the squirrel's body over each bough, and the trunk's climbing surface
	local tunnels: { { { number } } } = {}
	for _, b in boughs do
		for k = 1, #b.line - 1 do
			local a, e = b.line[k], b.line[k + 1]
			table.insert(tunnels, { { a[1], a[2] + 2, a[3] }, { e[1], e[2] + 2, e[3] } })
		end
	end
	local function clear(p: { number }, r: number): boolean
		for _, seg in tunnels do
			if segDist(seg[1], seg[2], p) < r + 1.6 then
				return false
			end
		end
		-- the trunk: anywhere up its height, all the way round
		if p[2] <= top[2] + r then
			for k = 1, #trunkLine - 1 do
				local a, e = trunkLine[k], trunkLine[k + 1]
				local tr = trunkRAtY(math.clamp(p[2], foot[2], top[2]))
				if segDist(a, e, p) < r + tr + 2.2 then
					return false
				end
			end
		end
		return true
	end

	type Cluster = { p: { number }, r: number, pri: number }
	local cand: { Cluster } = {}
	local tips: { { number } } = {}
	local yMin, yMax = math.huge, -math.huge
	-- the crown's horizontal reach: the branch tips round the trunk top (bridges reach beyond it)
	local crownR = 8 * scale
	for _, b in boughs do
		if b.route.kind ~= "bridge" then
			local e = b.line[#b.line]
			crownR = math.max(crownR, math.sqrt((e[1] - top[1]) ^ 2 + (e[3] - top[3]) ^ 2))
		end
	end
	crownR += 6 * scale
	for _, b in boughs do
		local e = b.line[#b.line]
		if b.route.kind == "branch" or b.route.kind == "lookout" then
			table.insert(tips, e)
		end
		local t0 = if b.route.kind == "bridge" then 0.08 elseif b.route.kind == "lookout" then 0.25 else 0.3
		local t1 = if b.route.kind == "bridge" then 0.94 else 1
		local step = math.clamp(5.4 * scale, 3, 7.5)
		local s = b.L * t0
		local i = 0
		while s <= b.L * t1 + 1e-6 do
			i += 1
			local p, d = at(b.line, b.c, s)
			local u = s / b.L
			local side = cross(d, { 0, 1, 0 })
			if len3(side) < 0.2 then
				side = { 1, 0, 0 }
			end
			side = unit(side)
			local up = unit(cross(side, d))
			if up[2] < 0 then
				up = { -up[1], -up[2], -up[3] }
			end
			local function cl(r: number, ox: number, oy: number, oz: number, pri: number)
				table.insert(cand, { p = { p[1] + ox, p[2] + oy, p[3] + oz }, r = r, pri = pri })
			end
			local inCrown = math.sqrt((p[1] - top[1]) ^ 2 + (p[3] - top[3]) ^ 2) <= crownR
			if inCrown then
				for _, sg in { -1, 1 } do
					local r = scale * (3.0 + 2.6 * u) * (0.75 + 0.5 * rand())
					local off = r + 1.4 + 0.9 * rand()
					cl(r, side[1] * sg * off, r * 0.25 + rand() * 1.2, side[3] * sg * off, 2)
				end
				if u > 0.4 or b.route.kind == "bridge" then
					local r = scale * (3.6 + 3.0 * u) * (0.75 + 0.5 * rand())
					local off = r + 3.8 + 1.2 * rand()
					cl(r, up[1] * off, up[2] * off, up[3] * off, 1)
				end
				if i % 2 == 0 then
					local r = scale * (2.8 + 2.0 * u) * (0.8 + 0.4 * rand())
					cl(r, 0, -(r + 0.15), 0, 3)
				end
			elseif not willow then
				-- a living bridge out past the crown: leafy tufts alternating along it, like a vine-hung
				-- limb (the bark stays mostly hidden without a solid tube of leaves)
				local sg = if i % 2 == 0 then 1 else -1
				local r = scale * (2.3 + 1.2 * rand())
				local off = r + 1.3 + 0.6 * rand()
				cl(r, side[1] * sg * off, r * 0.2, side[3] * sg * off, 4)
				if i % 3 == 0 then
					local rb = scale * (2.2 + rand())
					cl(rb, 0, -(rb + 0.15), 0, 4)
				end
			end
			s += step
		end
	end
	-- bursts round the bough tips
	for _, e in tips do
		for k = 1, 5 do
			local a = (k / 5 + rand() * 0.15) * 2 * math.pi
			local r = scale * (4.2 + 2.6 * rand())
			local off = r + 1.8 + rand() * 1.5
			table.insert(cand, {
				p = { e[1] + math.cos(a) * off, e[2] + r * 0.35 + rand() * 2, e[3] + math.sin(a) * off },
				r = r,
				pri = 1,
			})
		end
		local r = scale * (5 + 2 * rand())
		table.insert(cand, { p = { e[1], e[2] + r + 3.9, e[3] }, r = r, pri = 0 })
	end
	-- the crown dome over the tips
	local cx, cy, cz, n = top[1] * 2, 0, top[3] * 2, 2
	for _, e in tips do
		cx += e[1]
		cz += e[3]
		cy += e[2]
		n += 1
		yMin, yMax = math.min(yMin, e[2]), math.max(yMax, e[2])
	end
	if #tips == 0 then
		yMin, yMax = top[2], top[2]
		cy = top[2]
	else
		cy = cy / #tips
	end
	cx, cz = cx / n, cz / n
	local rh = 6 * scale
	for _, e in tips do
		rh = math.max(rh, math.sqrt((e[1] - cx) ^ 2 + (e[3] - cz) ^ 2))
	end
	rh += 2 * scale
	local rv = math.max(rh * 0.5, (yMax - yMin) / 2 + 5 * scale)
	local ccy = math.max(cy, top[2]) + rv * 0.25
	local area = 2 * math.pi * rh * rv * 1.3
	local nd = math.clamp(math.floor(area / (math.pi * (5.6 * scale) ^ 2) * 1.15), 10, 80)
	local golden = math.pi * (3 - math.sqrt(5))
	for k = 0, nd - 1 do
		local y = 1 - (k + 0.5) / nd * 1.35 -- 1 .. -0.35: the top and the sides, an open underside
		local rr = math.sqrt(math.max(0, 1 - y * y))
		local a = golden * k
		local r = scale * (4.6 + 3.0 * rand())
		local f = 0.84 + 0.1 * rand()
		table.insert(cand, {
			p = { cx + math.cos(a) * rr * rh * f, ccy + y * rv * f, cz + math.sin(a) * rr * rh * f },
			r = r,
			pri = 2,
		})
	end

	-- accept: clear of the tunnels, near some bough, not redundant; tips and tops first
	table.sort(cand, function(a, b)
		if a.pri ~= b.pri then
			return a.pri < b.pri
		end
		if a.p[2] ~= b.p[2] then
			return a.p[2] > b.p[2]
		end
		return a.p[1] < b.p[1]
	end)
	local function nearBough(p: { number }, r: number): boolean
		for _, b in boughs do
			for k = 1, #b.line - 1 do
				if segDist(b.line[k], b.line[k + 1], p) < r + 9 * scale then
					return true
				end
			end
		end
		return segDist(trunkLine[#trunkLine - 1] or foot, top, p) < r + 10 * scale
	end
	local accepted: { Cluster } = {}
	local cap = opts.maxLeaves or 260
	for _, c in cand do
		if #accepted >= cap then
			break
		end
		local ok = c.p[2] - c.r > foot[2] + 4 and clear(c.p, c.r) and nearBough(c.p, c.r)
		if ok then
			for _, q in accepted do
				local d = len3(sub(c.p, q.p))
				if d < 0.5 * (c.r + q.r) then
					ok = false
					break
				end
			end
		end
		if ok then
			table.insert(accepted, c)
		end
	end
	local lo, hi = math.huge, -math.huge
	for _, c in accepted do
		lo, hi = math.min(lo, c.p[2]), math.max(hi, c.p[2])
	end
	local g1 = (trunk.id % #greens) + 1
	local pick = { greens[g1], greens[(g1 % #greens) + 1], greens[((g1 + 1) % #greens) + 1] }
	for i, c in accepted do
		local roll = rand()
		local base = if roll < 0.5 then pick[1] elseif roll < 0.85 then pick[2] else pick[3]
		local h = if hi > lo then (c.p[2] - lo) / (hi - lo) else 0.5
		local col = shade(base, 0.9 + 0.14 * h + (rand() - 0.5) * 0.06)
		local d = 2 * c.r
		list:add(ORIGIN :: any, `Leaves{i}`, c.p[1], c.p[2], c.p[3], d, d, d, {
			shape = "Ball",
			color = col,
			material = "LeafyGrass",
			canCollide = false,
			canQuery = false,
			castShadow = true,
			role = "Leaves",
		})
	end
	local leaves = #accepted

	-- 3. willow curtains and apples ----------------------------------------------------------------
	if willow then
		-- weeping curtains: strands hanging from the lower half of the crown all round, almost to the
		-- ground at the rim (QUAY WILLOW, worldgen_districts_art §3.7)
		local strands = 0
		for _, c in accepted do
			local dx, dz = c.p[1] - cx, c.p[3] - cz
			local dist = math.sqrt(dx * dx + dz * dz)
			if dist > rh * 0.25 and strands < 110 then
				local ux, uz = dx / math.max(dist, 1e-6), dz / math.max(dist, 1e-6)
				for k = 1, 3 do
					local a = (rand() - 0.5) * 1.6
					local ox = ux * math.cos(a) - uz * math.sin(a)
					local oz = ux * math.sin(a) + uz * math.cos(a)
					local x, z = c.p[1] + ox * c.r * 0.75, c.p[3] + oz * c.r * 0.75
					local y1 = c.p[2] - c.r * 0.1
					local ground = (opts.groundAt(x, z, y1))
					local rim = math.clamp(dist / rh, 0, 1)
					local y0 = math.max(ground + 2.5, y1 - (8 + 14 * rim + 4 * rand()))
					local mid = { x, (y0 + y1) / 2, z }
					if y1 - y0 > 2 and clear({ x, y0, z }, 1.2) and clear(mid, 1.2) then
						strands += 1
						local rr = 1.0 + 0.6 * rand()
						cylinder(list, `Strand{strands}`, { x, y0, z }, { x, y1, z }, rr, 0, {
							color = shade(greens[(k % #greens) + 1], 0.98 + 0.1 * rand()),
							material = "LeafyGrass",
							canCollide = false,
							canQuery = false,
							castShadow = true,
							role = "Leaves",
						})
						leaves += 1
					end
				end
			end
		end
	elseif apple then
		local n2 = 0
		for _, c in accepted do
			if n2 < 9 and rand() < 0.45 then
				n2 += 1
				local a = rand() * 2 * math.pi
				list:add(ORIGIN :: any, `Apple{n2}`, c.p[1] + math.cos(a) * c.r * 0.92, c.p[2] - c.r * 0.25, c.p[3] + math.sin(a) * c.r * 0.92, 0.9, 0.9, 0.9, {
					shape = "Ball",
					color = { 186, 52, 44 },
					material = "SmoothPlastic",
					canCollide = false,
					canQuery = false,
					castShadow = false,
					role = "Leaves",
				})
				leaves += 1
			end
		end
	end
	return leaves
end

return Trees
