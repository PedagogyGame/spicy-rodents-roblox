--!strict
-- StarterPlayerScripts.Client.World.BranchNookArt
-- What a tree's branch nooks look like (owner D34: "little nooks in the branches ... stash places off to the side and a
-- little place to hangout, cozy!"; where they are: Shared/World/BranchNooks). Plain parts, few of them, none solid,
-- none queried, none touched, no shadows (the motor runs the routes; these are only seen), coloured as the tree's own
-- stand-in bark (worldgen Builders/Trees' BARKS by trunk id), drawn so the feet on the route's line stand on them
-- (Routes/Motion §14: the feet are BranchNooks.C.lift over a branch's line):
--   NOOK (6 parts)    a dark floor disc in a bark bowl, three bark walls round its far side (the way the route ran in:
--                     toward the trunk), and a soft low lip across the way in, stepped over into the cup
--   STASH (2)         a knot-hole: a pale bark ring with a dark hole in it, in the wood beside the cup; acorns (up to
--                     C.acorns, one part each) are the viewer's own and added by Client/World/BranchNookView
--   HANGOUT (9)       a flat crook: three bark discs along the ledge, moss on each, two twigs and a tuft of leaves
--   SPUR (6)          four tapering bark pieces along it, a twig and a tuft of leaves past its tip
--   NODULES (1 each)  a small knot on the run path, its top C.knotTop over the feet (Client/World/BranchNookView draws
--                     them for one tree at a time, the one the camera is at)
-- Built through an injected engine table (Instance, CFrame, Vector3, Color3, Enum), so the review renders
-- (tools/review/branch_nooks.luau, @lune/roblox) draw exactly what the client draws.
-- Interface: build(engine, nooks, registry, trunk, opts?) -> (Model, Report); nodules(engine, registry, routes, trunk,
--   parent, max?) -> number (parts added); acorns(engine, place, n, parent) -> number; PARTS (per kind); C; COLORS
--   Report = { parts, nooks, stashes, hangouts, spurs }
-- No side effects on require.

local Import = require("../Import")
local BranchNooks = Import.shared("World/BranchNooks") :: typeof(require("../../shared/World/BranchNooks"))
-- (the exported types do not cross the Import cast)
type Nooks = typeof(BranchNooks.new(nil))
type Place = typeof(BranchNooks.new(nil).places[1])

local BranchNookArt = {}

BranchNookArt.PARTS = table.freeze({ nook = 6, stash = 2, hangout = 9, spur = 6, nodule = 1, acorn = 1 })

BranchNookArt.C = table.freeze({
	floorThick = 0.3,
	bowl = 3.0, -- the bowl's diameter under the floor
	bowlThick = 0.8,
	wallWide = 1.35,
	wallThick = 0.32,
	wallTilt = math.rad(14),
	wallAngle = 62, -- degrees either side of straight ahead
	lipDia = 0.5,
	lipLong = 2.0,
	lipBack = 1.2, -- studs back along the way in
	ringOver = 0.4, -- the knot-hole's ring past the hole (radius)
	hangoutDisc = 2.8,
	hangoutThick = 0.4,
	moss = 2.35,
	mossThick = 0.08,
	hangoutAt = table.freeze({ 0.42, 0.68, 0.94 }),
	spurBase = 0.55, -- radius
	spurTip = 0.28,
	tuft = 2.0,
	knot = 0.5, -- a nodule's diameter
	knotTop = 0.12, -- over the feet
	acorns = 3,
	acorn = 0.42,
})
local C = BranchNookArt.C

BranchNookArt.COLORS = table.freeze({
	barks = table.freeze({ { 0x65, 0x53, 0x42 }, { 0x5d, 0x4c, 0x3d }, { 0x6b, 0x5a, 0x48 }, { 0x59, 0x4a, 0x3e } }),
	inner = { 58, 44, 34 }, -- the cup's floor
	hole = { 24, 17, 12 },
	ring = { 128, 106, 84 },
	moss = { 104, 132, 64 },
	leaves = { 0x6a, 0x8c, 0x3e },
	knot = { 78, 62, 48 },
	nut = { 150, 98, 52 },
})
local COL = BranchNookArt.COLORS

export type Engine = { Instance: any, CFrame: any, Vector3: any, Color3: any, Enum: any }
export type Report = { parts: number, nooks: number, stashes: number, hangouts: number, spurs: number }

local function barkOf(trunk: number): { number }
	return COL.barks[(trunk % #COL.barks) + 1]
end

local function shade(c: { number }, k: number): { number }
	return {
		math.clamp(math.floor(c[1] * k), 0, 255),
		math.clamp(math.floor(c[2] * k), 0, 255),
		math.clamp(math.floor(c[3] * k), 0, 255),
	}
end

-- a part: anchored, nothing solid about it, no shadow
local function part(
	E: Engine,
	parent: any,
	name: string,
	shape: string,
	size: { number },
	cf: any,
	color: { number },
	material: string
): any
	local p = E.Instance.new("Part")
	p.Name = name
	p.Shape = E.Enum.PartType[shape]
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.Size = E.Vector3.new(size[1], size[2], size[3])
	p.CFrame = cf
	p.Color = E.Color3.fromRGB(color[1], color[2], color[3])
	p.Material = E.Enum.Material[material]
	p.Parent = parent
	return p
end

local function unit(x: number, y: number, z: number): (number, number, number)
	local l = math.sqrt(x * x + y * y + z * z)
	if l < 1e-9 then
		return 0, 1, 0
	end
	return x / l, y / l, z / l
end

local function cross(ax: number, ay: number, az: number, bx: number, by: number, bz: number): (number, number, number)
	return ay * bz - az * by, az * bx - ax * bz, ax * by - ay * bx
end

-- a frame whose X axis is (dx, dy, dz) (a cylinder lies along X), centred at (px, py, pz)
local function alongX(E: Engine, px: number, py: number, pz: number, dx: number, dy: number, dz: number): any
	local ux, uy, uz = unit(dx, dy, dz)
	local ox, oy, oz = 0, 1, 0
	if math.abs(uy) > 0.95 then
		ox, oy, oz = 1, 0, 0
	end
	local zx, zy, zz = unit(cross(ux, uy, uz, ox, oy, oz))
	local yx, yy, yz = cross(zx, zy, zz, ux, uy, uz)
	return E.CFrame.fromMatrix(
		E.Vector3.new(px, py, pz),
		E.Vector3.new(ux, uy, uz),
		E.Vector3.new(yx, yy, yz),
		E.Vector3.new(zx, zy, zz)
	)
end

-- a frame with Y up and X along (dx, 0, dz) level, centred at (px, py, pz)
local function level(E: Engine, px: number, py: number, pz: number, dx: number, dz: number): any
	return alongX(E, px, py, pz, dx, 0, dz)
end

-- a level disc (a cylinder stood up): its top at `top`
local function disc(
	E: Engine,
	parent: any,
	name: string,
	x: number,
	top: number,
	z: number,
	dia: number,
	thick: number,
	color: { number },
	material: string
): any
	return part(
		E,
		parent,
		name,
		"Cylinder",
		{ thick, dia, dia },
		alongX(E, x, top - thick / 2, z, 0, 1, 0),
		color,
		material
	)
end

local function feetAt(reg: any, route: any, t: number): (number, number, number)
	local p = reg:pointAt(route, t)
	return p.x, p.y + BranchNooks.C.lift, p.z
end

-- the level way the route runs at t (unit)
local function runAt(reg: any, route: any, t: number): (number, number)
	local tg = reg:tangentAt(route, math.clamp(t, 0.002, 0.998))
	local l = math.sqrt(tg.x * tg.x + tg.z * tg.z)
	if l < 1e-6 then
		return 0, 1
	end
	return tg.x / l, tg.z / l
end

local function buildNook(E: Engine, model: any, reg: any, p: Place, bark: { number }): number
	local r = reg:get(p.route)
	if r == nil then
		return 0
	end
	local fx, fy, fz = feetAt(reg, r, 1)
	local tx, tz = runAt(reg, r, 0.97)
	local n = `Nook{p.route}`
	disc(E, model, n .. "_bowl", fx, fy - 0.03, fz, C.bowl, C.bowlThick, bark, "Wood")
	disc(E, model, n .. "_floor", fx, fy, fz, BranchNooks.C.cupRadius * 2, C.floorThick, COL.inner, "Wood")
	-- the walls round the far side (straight ahead of the way in, and either side of it), leaning out a little
	for k, deg in { 0, C.wallAngle, -C.wallAngle } do
		local a = math.atan2(tx, tz) + math.rad(deg)
		local ox, oz = math.sin(a), math.cos(a)
		local rad = BranchNooks.C.cupRadius + C.wallThick / 2 - 0.05
		local h = BranchNooks.C.cupWall
		local cx, cy, cz = fx + ox * rad, fy + 0.1 + h / 2, fz + oz * rad
		-- X across the wall (tangential), Y up tilted out, Z out of the cup
		local cf = E.CFrame.lookAt(E.Vector3.new(cx, cy, cz), E.Vector3.new(cx - ox, cy, cz - oz))
			* E.CFrame.Angles(-C.wallTilt, 0, 0)
		part(E, model, `{n}_wall{k}`, "Block", { C.wallWide, h, C.wallThick }, cf, shade(bark, 0.92 + 0.06 * k), "Wood")
	end
	-- the soft lip across the way in (its top a little over the floor; the feet step over it)
	local lx, lz = fx - tx * C.lipBack, fz - tz * C.lipBack
	part(
		E,
		model,
		n .. "_lip",
		"Cylinder",
		{ C.lipLong, C.lipDia, C.lipDia },
		level(E, lx, fy + 0.1 - C.lipDia / 2, lz, -tz, tx),
		shade(bark, 1.12),
		"Wood"
	)
	return BranchNookArt.PARTS.nook
end

local function buildStash(E: Engine, model: any, p: Place, bark: { number }): number
	local h = p.stash
	if h == nil then
		return 0
	end
	local x, y, z, nx, nz = h[1], h[2], h[3], h[4], h[5]
	local hole = BranchNooks.C.stashHole
	local n = `Stash{p.route}`
	part(
		E,
		model,
		n .. "_ring",
		"Cylinder",
		{ 0.4, 2 * (hole + C.ringOver), 2 * (hole + C.ringOver) },
		alongX(E, x, y, z, nx, 0, nz),
		shade(COL.ring, 1),
		"Wood"
	)
	part(
		E,
		model,
		n .. "_hole",
		"Cylinder",
		{ 0.44, 2 * hole, 2 * hole },
		alongX(E, x + nx * 0.01, y, z + nz * 0.01, nx, 0, nz),
		COL.hole,
		"Wood"
	)
	local _ = bark
	return BranchNookArt.PARTS.stash
end

-- acorns(engine, place, n, parent): up to C.acorns of the viewer's nuts showing in a knot-hole
function BranchNookArt.acorns(E: Engine, p: Place, n: number, parent: any): number
	local h = p.stash
	if h == nil or n <= 0 then
		return 0
	end
	local x, y, z, nx, nz = h[1], h[2], h[3], h[4], h[5]
	local sx, sz = -nz, nx
	local shown = math.min(n, C.acorns)
	for k = 1, shown do
		local off = (k - (shown + 1) / 2) * 0.36
		local cx, cy, cz = x + nx * 0.22 + sx * off, y - 0.18 + (if k == 2 then 0.12 else 0), z + nz * 0.22 + sz * off
		part(
			E,
			parent,
			`Acorn{p.route}_{k}`,
			"Ball",
			{ C.acorn, C.acorn, C.acorn },
			E.CFrame.new(cx, cy, cz),
			COL.nut,
			"Wood"
		)
	end
	return shown
end

local function buildHangout(E: Engine, model: any, reg: any, p: Place, bark: { number }): number
	local r = reg:get(p.route)
	if r == nil then
		return 0
	end
	local n = `Hangout{p.route}`
	for k, t in C.hangoutAt do
		local x, y, z = feetAt(reg, r, t)
		disc(
			E,
			model,
			`{n}_ledge{k}`,
			x,
			y - 0.05,
			z,
			C.hangoutDisc,
			C.hangoutThick,
			shade(bark, 0.96 + 0.04 * k),
			"Wood"
		)
		disc(E, model, `{n}_moss{k}`, x, y + 0.01, z, C.moss, C.mossThick, COL.moss, "Grass")
	end
	-- two twigs off the outer edge and a tuft of leaves on one
	local ex, ey, ez = feetAt(reg, r, 1)
	local ox, oz = p.out[1], p.out[2]
	local sx, sz = -oz, ox
	for k, s in { 1, -1 } do
		local dx, dy, dz = unit(ox * 0.7 + sx * s * 0.35, 0.65, oz * 0.7 + sz * s * 0.35)
		local bx, by, bz = ex + ox * 1.1 + sx * s * 0.6, ey - 0.1, ez + oz * 1.1 + sz * s * 0.6
		local len = 2.2
		part(
			E,
			model,
			`{n}_twig{k}`,
			"Cylinder",
			{ len, 0.2, 0.2 },
			alongX(E, bx + dx * len / 2, by + dy * len / 2, bz + dz * len / 2, dx, dy, dz),
			bark,
			"Wood"
		)
		if k == 1 then
			part(
				E,
				model,
				`{n}_leaves`,
				"Ball",
				{ 1.4, 1.4, 1.4 },
				E.CFrame.new(bx + dx * len, by + dy * len, bz + dz * len),
				COL.leaves,
				"LeafyGrass"
			)
		end
	end
	return BranchNookArt.PARTS.hangout
end

local function buildSpur(E: Engine, model: any, reg: any, p: Place, bark: { number }): number
	local r = reg:get(p.route)
	if r == nil then
		return 0
	end
	local n = `Spur{p.route}`
	-- four pieces, each a cylinder whose top runs at the feet (the centre line lowered by its radius)
	local cuts = { 0, 0.25, 0.5, 0.75, 1 }
	for k = 1, 4 do
		local t0, t1 = cuts[k], cuts[k + 1]
		local rad = C.spurBase + (C.spurTip - C.spurBase) * (t0 + t1) / 2
		local ax, ay, az = feetAt(reg, r, t0)
		local bx, by, bz = feetAt(reg, r, t1)
		ay -= rad
		by -= rad
		local dx, dy, dz = bx - ax, by - ay, bz - az
		local len = math.sqrt(dx * dx + dy * dy + dz * dz) + rad * 0.6
		part(
			E,
			model,
			`{n}_{k}`,
			"Cylinder",
			{ len, 2 * rad, 2 * rad },
			alongX(E, (ax + bx) / 2, (ay + by) / 2, (az + bz) / 2, dx, dy, dz),
			bark,
			"Wood"
		)
	end
	-- past the tip: a twig up and out, a tuft of leaves on it
	local ex, ey, ez = feetAt(reg, r, 1)
	local tx, tz = runAt(reg, r, 0.98)
	local dx, dy, dz = unit(tx, 0.55, tz)
	local len = 1.8
	local bx, by, bz = ex, ey - C.spurTip, ez
	part(
		E,
		model,
		n .. "_twig",
		"Cylinder",
		{ len, 0.2, 0.2 },
		alongX(E, bx + dx * len / 2, by + dy * len / 2, bz + dz * len / 2, dx, dy, dz),
		bark,
		"Wood"
	)
	part(
		E,
		model,
		n .. "_leaves",
		"Ball",
		{ C.tuft, C.tuft, C.tuft },
		E.CFrame.new(bx + dx * (len + 0.6), by + dy * (len + 0.6), bz + dz * (len + 0.6)),
		COL.leaves,
		"LeafyGrass"
	)
	return BranchNookArt.PARTS.spur
end

-- build(engine, nooks, registry, trunk): a Model "BranchNooks_<trunk>" with every nook, stash, hangout and spur of that
-- tree (parented to nothing: the caller places it)
function BranchNookArt.build(E: Engine, nooks: Nooks, reg: any, trunk: number): (any, Report)
	local model = E.Instance.new("Model")
	model.Name = `BranchNooks_{trunk}`
	local bark = barkOf(trunk)
	local report: Report = { parts = 0, nooks = 0, stashes = 0, hangouts = 0, spurs = 0 }
	for _, p in nooks.tree(trunk) do
		if p.kind == "nook" then
			report.parts += buildNook(E, model, reg, p, bark)
			report.nooks += 1
			local s = buildStash(E, model, p, bark)
			report.parts += s
			if s > 0 then
				report.stashes += 1
			end
		elseif p.kind == "hangout" then
			report.parts += buildHangout(E, model, reg, p, bark)
			report.hangouts += 1
		elseif p.kind == "spur" then
			report.parts += buildSpur(E, model, reg, p, bark)
			report.spurs += 1
		end
	end
	return model, report
end

-- nodules(engine, registry, routes, trunk, parent, max?): a knot on the run path at each of the routes' nodules
-- (BranchNooks.nodules), at most `max` of them, nearest the routes' starts first; the parts added
function BranchNookArt.nodules(E: Engine, reg: any, routes: { any }, trunk: number, parent: any, max: number?): number
	local color = shade(barkOf(trunk), 0.85)
	local list: { { r: any, s: number } } = {}
	for _, r in routes do
		for _, s in BranchNooks.nodules(r) do
			table.insert(list, { r = r, s = s })
		end
	end
	table.sort(list, function(a, b)
		if a.s ~= b.s then
			return a.s < b.s
		end
		return a.r.id < b.r.id
	end)
	local n = 0
	for _, k in list do
		if max and n >= max then
			break
		end
		local x, y, z = feetAt(reg, k.r, k.s / k.r.length)
		n += 1
		part(
			E,
			parent,
			`Knot{k.r.id}_{n}`,
			"Ball",
			{ C.knot, C.knot * 0.8, C.knot },
			E.CFrame.new(x, y + C.knotTop - C.knot * 0.4, z),
			color,
			"Wood"
		)
	end
	return n
end

return BranchNookArt
