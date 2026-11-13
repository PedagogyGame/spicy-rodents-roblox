--!strict
-- tests/lib/BakedWorld: a baked model (build/Attractions.rbxm, any .rbxm, or the bowling alley baked in memory by the
-- same code as tools/bake/attractions.luau) as geometry the squirrel motor runs against headless, the clearance
-- check that holds an enclosed run's geometry to being passable, and a driver that runs the real SquirrelMotor
-- with scripted keys. The geometry the builders after the enclosed-runs contract (Shared/Routes/Enclosure) are held
-- to: the ball return's duct, hood and vent, and every hollow trunk.
--
-- Geometry. Every BasePart becomes a convex solid in its own frame: a Block its box, a WedgePart its wedge (the slope
-- rising from the -Z edge to the top at +Z, as Roblox draws it), a Cylinder a 16-sided prism along X, a Ball a
-- sphere; CornerWedges, MeshParts and unions are taken as their box (said in `shape`). Parts under a model named
-- "TerrainCarve" are not solids: they lower the terrain (as Server/Attractions/AttractionService carves it at
-- boot). Overlap tests are exact separating-axis tests between convex solids, so a 0.08-stud plank is found.
--   world.groundAt(x, z, refY)   what a ray down from refY + 1.5 meets first among colliding parts, else the
--                                terrain (World/Height lowered inside the carve boxes): Client/World/ClientWorld
--   world.blocked(x, z, y)       ClientWorld's body box (half 1.0, from STEP to BODY_TOP over the feet; its lowest
--                                BODY_RISE counts at the core only) against colliding parts; blockedCore,
--                                blockedHalf as there. As ClientWorld's wall test: a tree's bough cylinders
--                                (Tree_<id>.R<route>_<i>) are looked past and a trunk cylinder (Tree_<id>.Trunk*)
--                                is tested by its round section (ClientWorld.isBough, isTrunk, trunkClear)
--   world.raycast(origin, dir, filter?) -> (t, part)?   nearest hit along origin + dir * t, t in [0, 1]
--   world.containing(x, y, z, filter?) -> { Part }       the solids holding a point
--   world.overlapBox(cx, cy, cz, axes, half, filter?) -> { Part }   solids overlapping an oriented box
--   world:motorWorld(data) -> SquirrelMotor.World        the callbacks above plus the rail world of `data`
-- Clearance. BakedWorld.clearance(world, registry, route, opts?) sweeps the animal's section (Enclosure.BODY width,
-- headroom BODY.height, or the record's crawl height where the record declares a crawl) along a route in slices of
-- `step` studs and reports every part it passes through: { name, path, collide, visible, t0, t1, studs }, merged
-- per part, in route order. The section stands on the route line (the feet), from `lift` (0.15) up along its up
-- (the record's `up` / `upAt` where written, else Motion.section's default: world up squared to the line, carried
-- up a vertical stretch). What lies lower than `lift` above the line is walked over. A route of kind trunk or a
-- climb is swept as a square column round the line. BakedWorld.mouthClearance(world, registry, route) lists what
-- stands where each mouth's launch starts (Motion.launchPoint: the body's box there must be clear).
-- Driving. BakedWorld.drive(world, state, frames, keys, opts?) -> Trace runs SquirrelMotor.step at 1/60 s with the
-- input `keys(frame, state)` returns (nil stops), recording every frame's position, route, t and events, the
-- largest move in one frame, the routes visited, and (opts.validator) each frame's envelope violations.
-- Pure Lune (@lune/roblox for loading only). Studs.

local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local AlleyLayout = require("@shared/Attractions/AlleyLayout")
local ClientWorld = require("@client/World/ClientWorld")
local Enclosure = require("@shared/Routes/Enclosure")
local Motion = require("@shared/Routes/Motion")
local Height = require("@shared/World/Height")
local RailWorld = require("@shared/Movement/RailWorld")
local Registry = require("@shared/Routes/Registry")
local SquirrelMotor = require("@shared/Movement/SquirrelMotor")

local BakedWorld = {}

export type Part = {
	name: string,
	path: string,
	class: string,
	shape: string, -- "block" | "wedge" | "cylinder" | "ball" | "box" (taken as its box)
	collide: boolean,
	query: boolean,
	visible: boolean,
	transparency: number,
	-- frame: centre and unit axes (the part's X, Y, Z in world space), half size
	px: number,
	py: number,
	pz: number,
	ax: { number },
	ay: { number },
	az: { number },
	hx: number,
	hy: number,
	hz: number,
	-- local convex hull: vertices and face planes { nx, ny, nz, d } (n . p <= d inside); edge directions
	verts: { { number } },
	planes: { { number } },
	edges: { { number } },
	radius: number?, -- a ball's radius
	-- world bounding box
	x0: number,
	x1: number,
	y0: number,
	y1: number,
	z0: number,
	z1: number,
}

export type Carve = { x0: number, x1: number, y0: number, y1: number, z0: number, z1: number }

export type Filter = (part: Part) -> boolean

export type World = {
	parts: { Part },
	carves: { Carve },
	terrainAt: (x: number, z: number) -> number,
	groundAt: (x: number, z: number, refY: number) -> number,
	groundPart: (x: number, z: number, refY: number) -> (number, Part?),
	blocked: (x: number, z: number, y: number) -> boolean,
	blockedCore: (x: number, z: number, y: number) -> boolean,
	blockedHalf: (x: number, z: number, y: number, half: number) -> boolean,
	blocker: (x: number, z: number, y: number, half: number) -> Part?,
	raycast: (
		ox: number,
		oy: number,
		oz: number,
		dx: number,
		dy: number,
		dz: number,
		filter: Filter?
	) -> (number?, Part?),
	containing: (x: number, y: number, z: number, filter: Filter?) -> { Part },
	overlapBox: (
		cx: number,
		cy: number,
		cz: number,
		axes: { { number } },
		half: { number },
		filter: Filter?
	) -> { Part },
	motorWorld: (self: World, data: any) -> SquirrelMotor.World,
}

-- ClientWorld's body (Client/World/ClientWorld: STEP, BODY_HALF, BODY_TOP, BODY_RISE, PROBE_RADIUS)
BakedWorld.STEP = 0.75
BakedWorld.BODY_HALF = 1.0
BakedWorld.BODY_TOP = 1.7
BakedWorld.BODY_RISE = 0.25
BakedWorld.CORE = 0.35
BakedWorld.RAY_ABOVE = 1.5 -- the ground ray starts this far above the body's reference height

local CELL = 4
local EPS = 1e-6

local function dot(a: { number }, b: { number }): number
	return a[1] * b[1] + a[2] * b[2] + a[3] * b[3]
end

local function cross(a: { number }, b: { number }): { number }
	return { a[2] * b[3] - a[3] * b[2], a[3] * b[1] - a[1] * b[3], a[1] * b[2] - a[2] * b[1] }
end

local function norm(a: { number }): { number }?
	local l = math.sqrt(dot(a, a))
	if l < 1e-9 then
		return nil
	end
	return { a[1] / l, a[2] / l, a[3] / l }
end

-- the local hull of a part's shape (vertices, face planes, edge directions)
local function boxHull(hx: number, hy: number, hz: number): ({ { number } }, { { number } }, { { number } })
	local verts = {}
	for _, sx in { -1, 1 } do
		for _, sy in { -1, 1 } do
			for _, sz in { -1, 1 } do
				table.insert(verts, { sx * hx, sy * hy, sz * hz })
			end
		end
	end
	local planes = {
		{ 1, 0, 0, hx },
		{ -1, 0, 0, hx },
		{ 0, 1, 0, hy },
		{ 0, -1, 0, hy },
		{ 0, 0, 1, hz },
		{ 0, 0, -1, hz },
	}
	return verts, planes, { { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 } }
end

local function wedgeHull(hx: number, hy: number, hz: number): ({ { number } }, { { number } }, { { number } })
	-- solid where y * sz - z * sy <= 0 (the slope from the front-bottom edge to the back-top edge)
	local verts = {
		{ -hx, -hy, -hz },
		{ hx, -hy, -hz },
		{ -hx, -hy, hz },
		{ hx, -hy, hz },
		{ -hx, hy, hz },
		{ hx, hy, hz },
	}
	local n = norm({ 0, 2 * hz, -2 * hy }) :: { number }
	local planes = {
		{ 1, 0, 0, hx },
		{ -1, 0, 0, hx },
		{ 0, -1, 0, hy },
		{ 0, 0, 1, hz },
		{ n[1], n[2], n[3], 0 },
	}
	local slope = norm({ 0, 2 * hy, 2 * hz }) :: { number }
	return verts, planes, { { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 }, slope }
end

local SIDES = 16
local function cylinderHull(hx: number, r: number): ({ { number } }, { { number } }, { { number } })
	local verts = {}
	local planes = { { 1, 0, 0, hx }, { -1, 0, 0, hx } }
	local edges = { { 1, 0, 0 } }
	for i = 0, SIDES - 1 do
		local a = (i + 0.5) / SIDES * 2 * math.pi
		local y, z = r * math.cos(a), r * math.sin(a)
		table.insert(verts, { -hx, y, z })
		table.insert(verts, { hx, y, z })
		-- face between vertices i and i+1: its normal at the mid angle, distance r * cos(pi / SIDES)
		local m = (i + 1) / SIDES * 2 * math.pi
		table.insert(planes, { 0, math.cos(m), math.sin(m), r * math.cos(math.pi / SIDES) })
		table.insert(edges, { 0, -math.sin(m), math.cos(m) })
	end
	return verts, planes, edges
end

local function shapeOf(inst: any): string
	local class = inst.ClassName
	if class == "WedgePart" then
		return "wedge"
	elseif class == "Part" then
		local ok, shape = pcall(function()
			return inst.Shape
		end)
		local name = if ok and shape then tostring((shape :: any).Name) else "Block"
		if name == "Ball" then
			return "ball"
		elseif name == "Cylinder" then
			return "cylinder"
		elseif name == "Wedge" then
			return "wedge"
		elseif name == "Block" then
			return "block"
		end
		return "box"
	end
	return "box"
end

local function makePart(inst: any, path: string): Part
	local cf, s = inst.CFrame, inst.Size
	local p = cf.Position
	local rx, ry, rz = cf.XVector, cf.YVector, cf.ZVector
	local hx, hy, hz = s.X / 2, s.Y / 2, s.Z / 2
	local shape = shapeOf(inst)
	local verts, planes, edges
	local radius: number? = nil
	if shape == "wedge" then
		verts, planes, edges = wedgeHull(hx, hy, hz)
	elseif shape == "cylinder" then
		local r = math.min(hy, hz)
		verts, planes, edges = cylinderHull(hx, r)
		hy, hz = r, r
	elseif shape == "ball" then
		local r = math.min(hx, hy, hz)
		radius = r
		hx, hy, hz = r, r, r
		verts, planes, edges = boxHull(r, r, r)
	else
		verts, planes, edges = boxHull(hx, hy, hz)
	end
	local ax, ay, az = { rx.X, rx.Y, rx.Z }, { ry.X, ry.Y, ry.Z }, { rz.X, rz.Y, rz.Z }
	local ex = math.abs(ax[1]) * hx + math.abs(ay[1]) * hy + math.abs(az[1]) * hz
	local ey = math.abs(ax[2]) * hx + math.abs(ay[2]) * hy + math.abs(az[2]) * hz
	local ez = math.abs(ax[3]) * hx + math.abs(ay[3]) * hy + math.abs(az[3]) * hz
	local transparency = inst.Transparency :: number
	return {
		name = inst.Name,
		path = path,
		class = inst.ClassName,
		shape = shape,
		collide = inst.CanCollide == true,
		query = inst.CanQuery ~= false,
		visible = transparency < 1,
		transparency = transparency,
		px = p.X,
		py = p.Y,
		pz = p.Z,
		ax = ax,
		ay = ay,
		az = az,
		hx = hx,
		hy = hy,
		hz = hz,
		verts = verts,
		planes = planes,
		edges = edges,
		radius = radius,
		x0 = p.X - ex,
		x1 = p.X + ex,
		y0 = p.Y - ey,
		y1 = p.Y + ey,
		z0 = p.Z - ez,
		z1 = p.Z + ez,
	}
end

-- world point -> part-local
local function toPart(part: Part, x: number, y: number, z: number): (number, number, number)
	local dx, dy, dz = x - part.px, y - part.py, z - part.pz
	return dx * part.ax[1] + dy * part.ax[2] + dz * part.ax[3],
		dx * part.ay[1] + dy * part.ay[2] + dz * part.ay[3],
		dx * part.az[1] + dy * part.az[2] + dz * part.az[3]
end

local function toPartDir(part: Part, x: number, y: number, z: number): (number, number, number)
	return x * part.ax[1] + y * part.ax[2] + z * part.ax[3],
		x * part.ay[1] + y * part.ay[2] + z * part.ay[3],
		x * part.az[1] + y * part.az[2] + z * part.az[3]
end

local function contains(part: Part, x: number, y: number, z: number): boolean
	local lx, ly, lz = toPart(part, x, y, z)
	local r = part.radius
	if r then
		return lx * lx + ly * ly + lz * lz < r * r
	end
	for _, pl in part.planes do
		if pl[1] * lx + pl[2] * ly + pl[3] * lz > pl[4] - EPS then
			return false
		end
	end
	return true
end

-- segment origin + dir * t (t in [0, 1]) against a part: the entry t, or nil (an origin inside does not hit)
local function rayPart(part: Part, ox: number, oy: number, oz: number, dx: number, dy: number, dz: number): number?
	local lx, ly, lz = toPart(part, ox, oy, oz)
	local vx, vy, vz = toPartDir(part, dx, dy, dz)
	local r = part.radius
	if r then
		local a = vx * vx + vy * vy + vz * vz
		local b = 2 * (lx * vx + ly * vy + lz * vz)
		local c = lx * lx + ly * ly + lz * lz - r * r
		if c <= 0 or a < 1e-12 then
			return nil
		end
		local disc = b * b - 4 * a * c
		if disc < 0 then
			return nil
		end
		local t = (-b - math.sqrt(disc)) / (2 * a)
		return if t >= 0 and t <= 1 then t else nil
	end
	local tin, tout = 0, 1
	local inside = true
	for _, pl in part.planes do
		local num = pl[4] - (pl[1] * lx + pl[2] * ly + pl[3] * lz)
		local den = pl[1] * vx + pl[2] * vy + pl[3] * vz
		if num < 0 then
			inside = false
		end
		if math.abs(den) < 1e-12 then
			if num < 0 then
				return nil
			end
		else
			local t = num / den
			if den < 0 then
				tin = math.max(tin, t)
			else
				tout = math.min(tout, t)
			end
			if tin > tout then
				return nil
			end
		end
	end
	if inside then
		return nil
	end
	return tin
end

-- separating-axis overlap between a part and an oriented box (centre, unit axes, half extents)
local function overlapsBox(part: Part, c: { number }, axes: { { number } }, half: { number }): boolean
	-- the box in the part's frame
	local lc = { toPart(part, c[1], c[2], c[3]) }
	local la = {}
	for i = 1, 3 do
		la[i] = { toPartDir(part, axes[i][1], axes[i][2], axes[i][3]) }
	end
	local r = part.radius
	if r then
		-- the sphere's centre (part origin) against the box: the nearest box point
		local d2 = 0
		for i = 1, 3 do
			local s = -(lc[1] * la[i][1] + lc[2] * la[i][2] + lc[3] * la[i][3])
			local e = math.max(0, math.abs(s) - half[i])
			d2 += e * e
		end
		return d2 < r * r
	end
	local boxVerts = {}
	for _, sx in { -1, 1 } do
		for _, sy in { -1, 1 } do
			for _, sz in { -1, 1 } do
				table.insert(boxVerts, {
					lc[1] + la[1][1] * half[1] * sx + la[2][1] * half[2] * sy + la[3][1] * half[3] * sz,
					lc[2] + la[1][2] * half[1] * sx + la[2][2] * half[2] * sy + la[3][2] * half[3] * sz,
					lc[3] + la[1][3] * half[1] * sx + la[2][3] * half[2] * sy + la[3][3] * half[3] * sz,
				})
			end
		end
	end
	local function separated(axis: { number }): boolean
		local amin, amax = math.huge, -math.huge
		for _, v in part.verts do
			local p = dot(v, axis)
			amin, amax = math.min(amin, p), math.max(amax, p)
		end
		local bmin, bmax = math.huge, -math.huge
		for _, v in boxVerts do
			local p = dot(v, axis)
			bmin, bmax = math.min(bmin, p), math.max(bmax, p)
		end
		return amax <= bmin + EPS or bmax <= amin + EPS
	end
	for _, pl in part.planes do
		if separated(pl) then
			return false
		end
	end
	for i = 1, 3 do
		if separated(la[i]) then
			return false
		end
	end
	for _, e in part.edges do
		for i = 1, 3 do
			local ax = norm(cross(e, la[i]))
			if ax and separated(ax) then
				return false
			end
		end
	end
	return true
end

local function pathOf(inst: any, root: any): string
	local names = {}
	local q = inst
	while q and q ~= root do
		table.insert(names, 1, q.Name)
		q = q.Parent
	end
	return table.concat(names, ".")
end

local function underCarve(inst: any): boolean
	local q = inst.Parent
	while q do
		if q.Name == "TerrainCarve" then
			return true
		end
		q = q.Parent
	end
	return false
end

-- fromModel(root, opts?): the solids of every BasePart under root. opts.adjust(part, instance) may change a part
-- (the runtime state the server sets at boot: BakedWorld.alleyRuntime).
function BakedWorld.fromModel(root: any, opts: { adjust: ((part: Part, inst: any) -> ())? }?): World
	local parts: { Part } = {}
	local carves: { Carve } = {}
	local adjust = opts and opts.adjust
	for _, inst in root:GetDescendants() do
		if inst:IsA("BasePart") then
			local part = makePart(inst, pathOf(inst, root))
			if underCarve(inst) then
				table.insert(
					carves,
					{ x0 = part.x0, x1 = part.x1, y0 = part.y0, y1 = part.y1, z0 = part.z0, z1 = part.z1 }
				)
			else
				if adjust then
					adjust(part, inst)
				end
				table.insert(parts, part)
			end
		end
	end
	local grid: { [number]: { Part } } = {}
	local function key(i: number, j: number): number
		return i * 100003 + j
	end
	for _, p in parts do
		for i = math.floor(p.x0 / CELL), math.floor(p.x1 / CELL) do
			for j = math.floor(p.z0 / CELL), math.floor(p.z1 / CELL) do
				local k = key(i, j)
				local b = grid[k]
				if not b then
					b = {}
					grid[k] = b
				end
				table.insert(b, p)
			end
		end
	end
	local function near(x0: number, x1: number, z0: number, z1: number, fn: (p: Part) -> boolean?)
		local seen: { [Part]: boolean } = {}
		for i = math.floor(x0 / CELL), math.floor(x1 / CELL) do
			for j = math.floor(z0 / CELL), math.floor(z1 / CELL) do
				local b = grid[key(i, j)]
				if b then
					for _, p in b do
						if not seen[p] then
							seen[p] = true
							if fn(p) then
								return
							end
						end
					end
				end
			end
		end
	end

	local world = {} :: World
	world.parts = parts
	world.carves = carves

	function world.terrainAt(x: number, z: number): number
		local h = Height.at(x, z)
		for _, c in carves do
			if x >= c.x0 and x <= c.x1 and z >= c.z0 and z <= c.z1 and h > c.y0 then
				h = math.min(h, c.y0)
			end
		end
		return h
	end

	function world.raycast(ox, oy, oz, dx, dy, dz, filter)
		local best, bestPart = math.huge, nil :: Part?
		near(math.min(ox, ox + dx), math.max(ox, ox + dx), math.min(oz, oz + dz), math.max(oz, oz + dz), function(p)
			if filter and not filter(p) then
				return false
			end
			local y0, y1 = math.min(oy, oy + dy), math.max(oy, oy + dy)
			if p.y1 < y0 or p.y0 > y1 then
				return false
			end
			local t = rayPart(p, ox, oy, oz, dx, dy, dz)
			if t and t < best then
				best, bestPart = t, p
			end
			return false
		end)
		if bestPart then
			return best, bestPart
		end
		return nil, nil
	end

	local function colliding(p: Part): boolean
		return p.collide
	end

	function world.groundPart(x: number, z: number, refY: number): (number, Part?)
		local top = refY + BakedWorld.RAY_ABOVE
		local terrain = world.terrainAt(x, z)
		local depth = math.max(top - terrain, 0) + 1
		local t, part = world.raycast(x, top, z, 0, -depth, 0, colliding)
		if t and part then
			local y = top - depth * t
			if y >= terrain then
				return y, part
			end
		end
		return terrain, nil
	end

	function world.groundAt(x: number, z: number, refY: number): number
		return (world.groundPart(x, z, refY))
	end

	function world.overlapBox(cx, cy, cz, axes, half, filter)
		local out: { Part } = {}
		local ex = math.abs(axes[1][1]) * half[1] + math.abs(axes[2][1]) * half[2] + math.abs(axes[3][1]) * half[3]
		local ey = math.abs(axes[1][2]) * half[1] + math.abs(axes[2][2]) * half[2] + math.abs(axes[3][2]) * half[3]
		local ez = math.abs(axes[1][3]) * half[1] + math.abs(axes[2][3]) * half[2] + math.abs(axes[3][3]) * half[3]
		near(cx - ex, cx + ex, cz - ez, cz + ez, function(p)
			if filter and not filter(p) then
				return false
			end
			if
				p.x1 <= cx - ex
				or p.x0 >= cx + ex
				or p.y1 <= cy - ey
				or p.y0 >= cy + ey
				or p.z1 <= cz - ez
				or p.z0 >= cz + ez
			then
				return false
			end
			if overlapsBox(p, { cx, cy, cz }, axes, half) then
				table.insert(out, p)
			end
			return false
		end)
		return out
	end

	local AXES = { { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 } }
	-- ClientWorld's wall test (its `solid`): a tree's invisible bough cylinders are looked past, and a tree's trunk is
	-- tested by its round section from the probe's centre (ClientWorld.trunkClear), not by its box
	local function boxHit(x: number, z: number, ylo: number, yhi: number, half: number): Part?
		local cy = (ylo + yhi) / 2
		local hits = world.overlapBox(x, cy, z, AXES, { half, (yhi - ylo) / 2, half }, colliding)
		for _, p in hits do
			local parentName = string.match(p.path, "([^%.]+)%.[^%.]+$") or ""
			if ClientWorld.isBough(p.name, parentName) then
				continue
			end
			if ClientWorld.isTrunk(p.name, parentName) and p.shape == "cylinder" then
				-- a cylinder's axis is its local X: the distance from it is in local Y and Z; its radius is the half Y
				local _, ly, lz = toPart(p, x, cy, z)
				if ClientWorld.trunkClear(math.sqrt(ly * ly + lz * lz), p.hy) then
					continue
				end
			end
			return p
		end
		return nil
	end

	-- ClientWorld.blocked: the body box from STEP + BODY_RISE to BODY_TOP at the half-width, and from STEP at the core
	function world.blocker(x: number, z: number, y: number, half: number): Part?
		local core = boxHit(x, z, y + BakedWorld.STEP, y + BakedWorld.STEP + 2 * BakedWorld.CORE, BakedWorld.CORE)
		if core then
			return core
		end
		return boxHit(x, z, y + BakedWorld.STEP + BakedWorld.BODY_RISE, y + BakedWorld.BODY_TOP, half)
	end
	function world.blocked(x: number, z: number, y: number): boolean
		return world.blocker(x, z, y, BakedWorld.BODY_HALF) ~= nil
	end
	function world.blockedHalf(x: number, z: number, y: number, half: number): boolean
		return world.blocker(x, z, y, half) ~= nil
	end
	function world.blockedCore(x: number, z: number, y: number): boolean
		return boxHit(x, z, y + BakedWorld.STEP, y + BakedWorld.STEP + 2 * BakedWorld.CORE, BakedWorld.CORE) ~= nil
	end

	function world.containing(x: number, y: number, z: number, filter: Filter?): { Part }
		local out: { Part } = {}
		near(x, x, z, z, function(p)
			if (not filter or filter(p)) and y > p.y0 and y < p.y1 and contains(p, x, y, z) then
				table.insert(out, p)
			end
			return false
		end)
		return out
	end

	function world.motorWorld(self: World, data: any): SquirrelMotor.World
		local rail = RailWorld.build(data, function(x: number, z: number): number
			return self.groundAt(x, z, 1e4)
		end)
		return {
			registry = rail.registry,
			index = rail.index,
			graph = rail.graph,
			trampolines = rail.trampolines,
			groundAt = self.groundAt,
			blocked = self.blocked,
			blockedCore = self.blockedCore,
			blockedHalf = self.blockedHalf,
			clamp = nil,
		}
	end

	return world
end

-- load(path, name?): a .rbxm file's model (or its first descendant named `name`).
function BakedWorld.load(path: string, name: string?, opts: { adjust: ((part: Part, inst: any) -> ())? }?): World
	local roots = roblox.deserializeModel(fs.readFile(path))
	local root = roots[1]
	if name then
		local found = nil
		for _, r in roots do
			found = if r.Name == name then r else r:FindFirstChild(name, true)
			if found then
				break
			end
		end
		if not found then
			error(`BakedWorld.load: no {name} in {path}`)
		end
		root = found
	end
	return BakedWorld.fromModel(root, opts)
end

-- What the server sets at boot (Server/Minigames/BowlingLane: each lane's own ball rides anchored and colliding
-- with nothing).
function BakedWorld.alleyRuntime(part: Part, inst: any)
	if part.name == "Ball" and inst.Parent and string.match(inst.Parent.Name, "^Lane%d+$") then
		part.collide = false
	end
end

-- bakeAlley(attraction?): the bowling alley built in memory by the bake's own code (tools/bake/alley: Shell, Lanes,
-- Rooms), from data/attractions.json's first attraction unless one is given; with the server's runtime state.
-- Returns the world, the alley's place and the Model.
function BakedWorld.bakeAlley(attraction: any?): (World, AlleyLayout.Place, any)
	local serde = require("@lune/serde")
	local a = attraction or serde.decode("json", fs.readFile("data/attractions.json")).attractions[1]
	local place: AlleyLayout.Place = { x = a.place.x, z = a.place.z, floorY = a.place.floorY, yaw = a.place.yaw }
	local Kit = (require :: any)("../../tools/bake/alley/Kit")
	local Shell = (require :: any)("../../tools/bake/alley/Shell")
	local Lanes = (require :: any)("../../tools/bake/alley/Lanes")
	local Rooms = (require :: any)("../../tools/bake/alley/Rooms")
	local GameBakes = (require :: any)("../../tools/bake/GameBakes")
	local kit = Kit.new(roblox, place)
	local root = GameBakes.siteModel(roblox, "BowlingAlley", a.id, place)
	Shell.build(kit, root, a)
	Lanes.build(kit, root)
	Rooms.build(kit, root)
	return BakedWorld.fromModel(root, { adjust = BakedWorld.alleyRuntime }), place, root
end

-- Clearance ---------------------------------------------------------------------------------------------------------

export type Blockage = {
	name: string,
	path: string,
	collide: boolean,
	visible: boolean,
	t0: number,
	t1: number,
	studs: number,
}

export type ClearanceOptions = {
	step: number?, -- slice length along the route (default 0.2 studs)
	lift: number?, -- the section starts this far above the route line (default 0.15: what lies lower, the floor
	-- itself, a rail or a rib on it, is walked over)
	width: number?, -- default Enclosure.BODY.width
	height: number?, -- default Enclosure.BODY.height (a record's crawl height inside its crawl stretches)
	t0: number?, -- the stretch swept (default 0..1)
	t1: number?,
	filter: Filter?, -- which parts count (default: colliding or visible)
}

local function solidOrSeen(p: Part): boolean
	return p.collide or p.visible
end

-- clearance(world, registry, route, opts?): every part the animal's section passes through along the route.
function BakedWorld.clearance(
	world: World,
	registry: Registry.Registry,
	route: Registry.Route,
	opts: ClearanceOptions?
): { Blockage }
	local o: ClearanceOptions = opts or {}
	local step = o.step or 0.2
	local lift = o.lift or 0.15
	local width = o.width or Enclosure.BODY.width
	local filter = o.filter or solidOrSeen
	local ta, tb = o.t0 or 0, o.t1 or 1
	local spec = route.enclosure
	local column = route.kind == "trunk" or (spec ~= nil and spec.climb)
	local n = math.max(1, math.ceil((tb - ta) * route.length / step))
	local byPart: { [Part]: Blockage } = {}
	local order: { Part } = {}
	local prevUp: { number } = { 0, 1, 0 }
	for i = 0, n do
		local t = ta + (tb - ta) * i / n
		local p = registry:pointAt(route, t)
		local tan = registry:tangentAt(route, math.clamp(t, 1e-4, 1 - 1e-4))
		local T = norm({ tan.x, tan.y, tan.z }) or { 0, 0, 1 }
		local height = o.height or Enclosure.BODY.height
		if spec and not o.height then
			local h, crawl = Enclosure.headroom(spec, t)
			if crawl then
				height = math.min(height, h)
			end
		end
		local U: { number }
		if column then
			U = T
		else
			-- the body stands up from the route line: world up made square to the line (on a vertical climb, the
			-- last up it had)
			local authored = if spec then Enclosure.upAt(spec, t) else nil
			local up = if authored then { authored.x, authored.y, authored.z } else { 0, 1, 0 }
			local k = dot(up, T)
			local u = norm({ up[1] - k * T[1], up[2] - k * T[2], up[3] - k * T[3] })
			if u == nil or (authored == nil and math.abs(k) > Enclosure.C.steep) then
				local pk = dot(prevUp, T)
				u = norm({ prevUp[1] - pk * T[1], prevUp[2] - pk * T[2], prevUp[3] - pk * T[3] })
			end
			U = u or { 0, 1, 0 }
			prevUp = U
		end
		local axes, half, cx, cy, cz
		if column then
			-- a square column round the line, `width` across, one slice long
			local side = norm(cross(T, if math.abs(T[2]) < 0.9 then { 0, 1, 0 } else { 1, 0, 0 })) :: { number }
			local other = cross(T, side)
			axes = { T, side, other }
			half = { step / 2, width / 2, width / 2 }
			cx, cy, cz = p.x, p.y, p.z
		else
			local S = norm(cross(T, U)) :: { number }
			axes = { T, S, U }
			half = { step / 2, width / 2, (height - lift) / 2 }
			local m = lift + (height - lift) / 2
			cx, cy, cz = p.x + U[1] * m, p.y + U[2] * m, p.z + U[3] * m
		end
		for _, part in world.overlapBox(cx, cy, cz, axes, half, filter) do
			local b = byPart[part]
			if not b then
				b = {
					name = part.name,
					path = part.path,
					collide = part.collide,
					visible = part.visible,
					t0 = t,
					t1 = t,
					studs = 0,
				}
				byPart[part] = b
				table.insert(order, part)
			end
			b.t1 = t
			b.studs += step
		end
	end
	local out: { Blockage } = {}
	for _, part in order do
		table.insert(out, byPart[part])
	end
	return out
end

export type MouthBlockage = { mouth: string, t: number, parts: { Part } }

-- mouthClearance(world, registry, route, filter?): for each mouth of an enclosed route, the solids in the body's box
-- (Enclosure.BODY width square, BODY.height tall, standing on the launch point) where a launch out of it starts
-- (Motion.launchPoint): a mouth whose list is not empty launches the body into something.
function BakedWorld.mouthClearance(
	world: World,
	registry: Registry.Registry,
	route: Registry.Route,
	filter: Filter?
): { MouthBlockage }
	local out: { MouthBlockage } = {}
	local spec = route.enclosure
	if not spec then
		return out
	end
	local motorish = { registry = registry } :: any
	for i, m in spec.mouths do
		local p = Motion.launchPoint(motorish, route, m)
		local w, h = Enclosure.BODY.width, Enclosure.BODY.height
		local parts = world.overlapBox(
			p.x,
			p.y + 0.15 + (h - 0.15) / 2,
			p.z,
			{ { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 } },
			{ w / 2, (h - 0.15) / 2, w / 2 },
			filter or solidOrSeen
		)
		table.insert(out, { mouth = m.name or `mouth {i}`, t = m.t, parts = parts })
	end
	return out
end

-- recordsData(records, forks?): a stand-in for Shared/Data over a list of route records (studs, world space), for
-- RailWorld.build and world:motorWorld: a small authored world, or old records kept for comparison.
function BakedWorld.recordsData(records: { Registry.RouteRecord }, forks: { any }?): any
	local registry = Registry.fromRecords(records)
	return {
		routes = function(_self: any): Registry.Registry
			return registry
		end,
		forks = function(_self: any): { any }
			return forks or {}
		end,
	}
end

-- alleyRecord(place, r): a route written in the alley's local frame [X, Y, D] (as data/attractions.json writes one)
-- turned into a world record the way tools/compile/lib/Attractions does (points, length, sample count, origin).
-- An enclosure's mouth `out` vectors are turned too.
function BakedWorld.alleyRecord(place: AlleyLayout.Place, r: { [string]: any }): Registry.RouteRecord
	local Curve = require("@shared/Routes/Curve")
	local pts, vecs = {}, {}
	for _, p in r.points do
		local x, y, z = AlleyLayout.toWorld(place, p[1], p[2], p[3])
		table.insert(pts, { x, y, z })
		table.insert(vecs, Curve.vec3(x, y, z))
	end
	local length = Curve.new(vecs):getLength()
	local rec: { [string]: any } = table.clone(r)
	rec.points = pts
	rec.length = length
	rec.sampleCount = Curve.sampleSteps(length / 2.5) + 1
	rec.origin = rec.origin or "attraction"
	rec.speedMult = 1
	if r.enclosure then
		-- the compiler's own turn of `out`, `up`, `upAt` and `cavity` (tools/compile/lib/Attractions)
		local Compile = require("../../tools/compile/lib/Attractions") :: any
		rec.enclosure = Compile.worldEnclosure(place, r.enclosure)
	end
	return rec :: any
end

-- Driving -------------------------------------------------------------------------------------------------------------

export type Frame = {
	x: number,
	y: number,
	z: number,
	routeId: number?,
	railT: number,
	grounded: boolean,
	events: { SquirrelMotor.Event },
	violations: { SquirrelMotor.Violation }?,
}

export type Trace = {
	frames: { Frame },
	events: { { frame: number, kind: string, routeId: number?, fromRouteId: number?, reason: string? } },
	routes: { [number]: boolean },
	maxStep: number, -- the largest move of the body's point in one frame (studs)
	maxStepFrame: number,
	violations: number,
	seconds: number,
}

export type DriveOptions = {
	dt: number?, -- default 1/60
	validator: boolean?, -- judge each frame with SquirrelMotor.envelope (prev -> next)
	stop: ((state: SquirrelMotor.State, frame: number) -> boolean)?,
}

-- keys(frame, state) -> Input? : the scripted keys for that frame (nil ends the drive)
function BakedWorld.drive(
	world: SquirrelMotor.World,
	state: SquirrelMotor.State,
	frames: number,
	keys: (frame: number, state: SquirrelMotor.State) -> SquirrelMotor.Input?,
	opts: DriveOptions?
): Trace
	local o: DriveOptions = opts or {}
	local dt = o.dt or 1 / 60
	local trace: Trace = {
		frames = {},
		events = {},
		routes = {},
		maxStep = 0,
		maxStepFrame = 0,
		violations = 0,
		seconds = 0,
	}
	for f = 1, frames do
		local input = keys(f, state)
		if not input then
			break
		end
		local before = if o.validator then SquirrelMotor.clone(state) else nil
		local bx, by, bz = state.x, state.y, state.z
		local _, events = SquirrelMotor.step(state, input, dt, world)
		local moved = math.sqrt((state.x - bx) ^ 2 + (state.y - by) ^ 2 + (state.z - bz) ^ 2)
		if moved > trace.maxStep then
			trace.maxStep, trace.maxStepFrame = moved, f
		end
		local violations = nil
		if before then
			violations = SquirrelMotor.envelope(before, state, dt, world, false)
			trace.violations += #violations
		end
		for _, e in events do
			table.insert(
				trace.events,
				{ frame = f, kind = e.kind, routeId = e.routeId, fromRouteId = e.fromRouteId, reason = e.reason }
			)
		end
		if state.routeId then
			trace.routes[state.routeId] = true
		end
		table.insert(trace.frames, {
			x = state.x,
			y = state.y,
			z = state.z,
			routeId = state.routeId,
			railT = state.railT,
			grounded = state.grounded,
			events = events,
			violations = violations,
		})
		trace.seconds += dt
		if o.stop and o.stop(state, f) then
			break
		end
	end
	return trace
end

-- count(trace, kind, reason?): how many events of that kind (and reason) the drive produced
function BakedWorld.count(trace: Trace, kind: string, reason: string?): number
	local n = 0
	for _, e in trace.events do
		if e.kind == kind and (reason == nil or e.reason == reason) then
			n += 1
		end
	end
	return n
end

-- keys: an Input with the camera yaw and the given fields set (fw, side, sprint, leap, drop, grab, choose, pounce)
function BakedWorld.keys(cameraYaw: number, fields: { [string]: any }?): SquirrelMotor.Input
	local input = SquirrelMotor.idleInput(cameraYaw)
	for k, v in fields or {} do
		(input :: any)[k] = v
	end
	return input
end

-- cameraYawToward(dx, dz): the camera yaw whose forward (HTML convention: (-sin, -cos)) is the world direction
function BakedWorld.cameraYawToward(dx: number, dz: number): number
	return math.atan2(-dx, -dz)
end

return BakedWorld
