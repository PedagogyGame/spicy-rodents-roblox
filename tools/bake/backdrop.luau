--!strict
-- tools/bake/backdrop: Lune bake of the far scenery into build/Backdrop.rbxm, mapped to Workspace.Backdrop by
-- default/ci/build project files ($path optional). BUILD_PLAN W6 #1, worldgen_districts_art §14.4, brief v2 §3
-- Backdrop and §15 ("the far distance is painted scenery", no money on art: everything here is procedural parts).
-- Layout and the shared height functions: src/shared/World/Backdrop.luau (the server writes the terrain band
-- beyond the world clamp and the near sea from the same functions at boot: WorldGen/BackdropTerrain).
--   Land      the land mesh beyond the band as WedgePart triangles: a patchwork of fields on the plains,
--             meadows and woods on the hills (two wedges per triangle)
--   Ranges    R1 forested foothills (an arc around the bay that runs into the sea as headlands), R2 mountains,
--             R3 snowy peaks: triangle strips along elliptic arcs, colours with baked aerial perspective
--   FarLand   flat tiles under the ranges and behind the foothills' coastal ends
--   FogCards  SurfaceGui cards with a vertical UIGradient (alpha) at the foot of each range (three layers,
--             lighter and bluer with distance); Client/World/Sky tints them by time of day
--   Trees     hedgerows and copses on the plains and a tree line on the foothill crest (ellipsoids)
--   Road      a distant road across the plains (Client/World/Sky runs impostor cars on it)
--   Farms     farmsteads for scale
--   Ocean     tiles from the coast to beyond the horizon, lighter with distance
--   Coast     the pier north of Sycamore Park, the marina at the Willow River mouth (breakwaters, pontoons,
--             moored boats, harbour lights), boats at sea, a lighthouse on a skerry
--   Tower     the lattice radio tower on the measured sunset azimuth: red and steel sections, the flashing
--             Beacon and steady SideLights (Client/World/Sky blinks the beacon)
-- Every part is anchored, CanTouch false, CastShadow false and at most 2048 st on every axis; scenery out of
-- reach has CanCollide and CanQuery false; every Model is ModelStreamingMode Persistent, LevelOfDetail Disabled.
-- Usage (repo root): lune run tools/bake/backdrop.luau [--out build/Backdrop.rbxm] [--report build/backdrop_report.json]
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local Height = require("../../src/shared/World/Height")
local Backdrop = require("../../src/shared/World/Backdrop")

local okExt, ext = pcall(require, "../../generated/TerrainExtensions")
if okExt then
	Height.configure(ext)
else
	error("tools/bake/backdrop: generated/TerrainExtensions missing (run lune run tools/compile/main.luau)")
end
Backdrop.reset()

local out, report = "build/Backdrop.rbxm", "build/backdrop_report.json"
do
	local i = 1
	while i <= #process.args do
		local a = process.args[i]
		if a == "--out" then
			out = process.args[i + 1]
			i += 1
		elseif a == "--report" then
			report = process.args[i + 1]
			i += 1
		else
			error("unknown argument: " .. a)
		end
		i += 1
	end
end

local Instance, Vector3, CFrame, Color3, Enum =
	roblox.Instance, roblox.Vector3, roblox.CFrame, roblox.Color3, roblox.Enum
local NumberSequence, NumberSequenceKeypoint = roblox.NumberSequence, roblox.NumberSequenceKeypoint

local MAX_AXIS = 2048
local CX, CZ = Backdrop.CENTRE.x, Backdrop.CENTRE.z
local FAR_Y, COAST_FAR_Y = 16, 5 -- far land tile tops (inland, coastal row)

---------------------------------------------------------------------------------------------- helpers
type RGB = { number }

local function hex(s: string): RGB
	return {
		tonumber(string.sub(s, 1, 2), 16) :: number,
		tonumber(string.sub(s, 3, 4), 16) :: number,
		tonumber(string.sub(s, 5, 6), 16) :: number,
	}
end

local function mix(a: RGB, b: RGB, t: number): RGB
	t = math.clamp(t, 0, 1)
	return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t }
end

local function shade(a: RGB, k: number): RGB
	return { math.clamp(a[1] * k, 0, 255), math.clamp(a[2] * k, 0, 255), math.clamp(a[3] * k, 0, 255) }
end

-- deterministic noise in [0, 1)
local function hash(a: number, b: number?, c: number?): number
	local s = math.sin(a * 12.9898 + (b or 0) * 78.233 + (c or 0) * 37.719) * 43758.5453
	return s - math.floor(s)
end

local HAZE = hex("b6c3cd") -- baked aerial perspective target (pale blue-grey, the golden-hour fog seen far off)
local function aerial(c: RGB, x: number, z: number, strength: number?): RGB
	local d = math.sqrt((x - CX) ^ 2 + (z - CZ) ^ 2)
	local t = math.clamp((d - 3000) / 14000, 0, 1) ^ 0.9 * 0.55 * (strength or 1)
	return mix(c, HAZE, t)
end

local counts: { [string]: number } = {}
local total = 0

local function model(parent: any, name: string): any
	local m = Instance.new("Model")
	m.Name = name
	m.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	m.LevelOfDetail = Enum.ModelLevelOfDetail.Disabled
	m.Parent = parent
	return m
end

type PartOpts = {
	collide: boolean?,
	query: boolean?,
	shape: string?,
	reflectance: number?,
	transparency: number?,
	shadow: boolean?,
}

local function part(
	class: string,
	parent: any,
	name: string,
	size: any,
	cf: any,
	rgb: RGB,
	material: string,
	group: string,
	o: PartOpts?
): any
	local opts: PartOpts = o or {}
	assert(
		size.X <= MAX_AXIS and size.Y <= MAX_AXIS and size.Z <= MAX_AXIS,
		`{group}/{name}: size {size} exceeds {MAX_AXIS} st`
	)
	local p = Instance.new(class)
	p.Name = name
	p.Anchored = true
	p.Locked = true
	p.CanTouch = false
	p.CastShadow = opts.shadow == true
	p.CanCollide = opts.collide == true
	p.CanQuery = opts.query == true
	if class == "Part" and opts.shape then
		p.Shape = (Enum.PartType :: any)[opts.shape]
	end
	p.Size = size
	-- CFrame, not Position: Lune drops writes to the derived Position property
	p.CFrame = cf
	p.Color = Color3.fromRGB(math.floor(rgb[1] + 0.5), math.floor(rgb[2] + 0.5), math.floor(rgb[3] + 0.5))
	p.Material = (Enum.Material :: any)[material]
	if opts.reflectance then
		p.Reflectance = opts.reflectance
	end
	if opts.transparency then
		p.Transparency = opts.transparency
	end
	p.Parent = parent
	counts[group] = (counts[group] or 0) + 1
	total += 1
	return p
end

local function block(
	parent: any,
	name: string,
	size: any,
	cf: any,
	rgb: RGB,
	material: string,
	group: string,
	o: PartOpts?
): any
	return part("Part", parent, name, size, cf, rgb, material, group, o)
end

-- A beam-like block from p0 to p1 (square section `w`).
local function strut(
	parent: any,
	name: string,
	p0: any,
	p1: any,
	w: number,
	rgb: RGB,
	material: string,
	group: string,
	o: PartOpts?
): any
	local len = (p1 - p0).Magnitude
	return block(parent, name, Vector3.new(w, w, len), CFrame.lookAt((p0 + p1) / 2, p1), rgb, material, group, o)
end

-- A vertical cylinder (Roblox cylinders run along local X).
local function pillar(
	parent: any,
	name: string,
	base: any,
	height: number,
	d: number,
	rgb: RGB,
	material: string,
	group: string,
	o: PartOpts?
): any
	local opts: PartOpts = o or {}
	opts.shape = "Cylinder"
	return part(
		"Part",
		parent,
		name,
		Vector3.new(height, d, d),
		CFrame.new(base + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		rgb,
		material,
		group,
		opts
	)
end

local function ball(
	parent: any,
	name: string,
	centre: any,
	d: number,
	rgb: RGB,
	material: string,
	group: string,
	o: PartOpts?
): any
	local opts: PartOpts = o or {}
	opts.shape = "Ball"
	return part("Part", parent, name, Vector3.new(d, d, d), CFrame.new(centre), rgb, material, group, opts)
end

-- An ellipsoid (a Part with a Sphere SpecialMesh, scaled to the part).
local function ellipsoid(parent: any, name: string, size: any, cf: any, rgb: RGB, group: string): any
	local p = block(parent, name, size, cf, rgb, "Grass", group)
	local m = Instance.new("SpecialMesh")
	m.MeshType = Enum.MeshType.Sphere
	m.Parent = p
	return p
end

-- A triangle as two WedgeParts (verified against the WedgePart geometry: corners in the triangle's plane,
-- areas summing to the triangle's). `thick` is the wedges' thickness, centred on the triangle's plane.
local function triangle(
	parent: any,
	name: string,
	a: any,
	b: any,
	c: any,
	rgb: RGB,
	material: string,
	group: string,
	thick: number
)
	local ab, ac, bc = b - a, c - a, c - b
	local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
	if abd > acd and abd > bcd then
		c, a = a, c
	elseif acd > bcd and acd > abd then
		a, b = b, a
	end
	ab, ac, bc = b - a, c - a, c - b
	local cross = ac:Cross(ab)
	if cross.Magnitude < 1e-6 then
		return -- degenerate
	end
	local right = cross.Unit
	local up = bc:Cross(right).Unit
	local back = bc.Unit
	local height = math.abs(ab:Dot(up))
	local d1, d2 = math.abs(ab:Dot(back)), math.abs(ac:Dot(back))
	if height < 0.05 then
		return
	end
	if d1 > 0.05 then
		part(
			"WedgePart",
			parent,
			name,
			Vector3.new(thick, height, d1),
			CFrame.fromMatrix((a + b) / 2, right, up, back),
			rgb,
			material,
			group
		)
	end
	if d2 > 0.05 then
		part(
			"WedgePart",
			parent,
			name,
			Vector3.new(thick, height, d2),
			CFrame.fromMatrix((a + c) / 2, -right, up, -back),
			rgb,
			material,
			group
		)
	end
end

-- Triangles whose longest edge exceeds `limit` are split into four (midpoints) until they fit.
local function triangleFit(
	parent: any,
	name: string,
	a: any,
	b: any,
	c: any,
	rgb: RGB,
	material: string,
	group: string,
	thick: number
)
	local limit = 1900
	local longest = math.max((b - a).Magnitude, (c - b).Magnitude, (a - c).Magnitude)
	if longest <= limit then
		triangle(parent, name, a, b, c, rgb, material, group, thick)
		return
	end
	local ab, bc, ca = (a + b) / 2, (b + c) / 2, (c + a) / 2
	triangleFit(parent, name, a, ab, ca, rgb, material, group, thick)
	triangleFit(parent, name, ab, b, bc, rgb, material, group, thick)
	triangleFit(parent, name, ca, bc, c, rgb, material, group, thick)
	triangleFit(parent, name, ab, bc, ca, rgb, material, group, thick)
end

-- Flat tiles (<= 2048 st) covering [x0, x1] x [z0, z1] with their top at y.
local function tiles(
	parent: any,
	name: string,
	x0: number,
	x1: number,
	z0: number,
	z1: number,
	y: number,
	thick: number,
	colour: (number, number) -> RGB,
	material: string,
	group: string,
	o: PartOpts?
)
	local nx = math.ceil((x1 - x0) / MAX_AXIS)
	local nz = math.ceil((z1 - z0) / MAX_AXIS)
	local sx, sz = (x1 - x0) / nx, (z1 - z0) / nz
	for i = 0, nx - 1 do
		for k = 0, nz - 1 do
			local cx, cz = x0 + (i + 0.5) * sx, z0 + (k + 0.5) * sz
			block(
				parent,
				name,
				Vector3.new(sx, thick, sz),
				CFrame.new(cx, y - thick / 2, cz),
				colour(cx, cz),
				material,
				group,
				o
			)
		end
	end
end

local root = Instance.new("Model")
root.Name = "Backdrop"
root.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
root.LevelOfDetail = Enum.ModelLevelOfDetail.Disabled

local mesh = Backdrop.mesh()
local clamp = Backdrop.clamp()

local function outsideOf(x: number, z: number): number
	return (Backdrop.outside(x, z))
end

---------------------------------------------------------------------------------------------- land mesh
local FIELDS =
	{ hex("8fa266"), hex("a4ad6b"), hex("7f9a5c"), hex("b5ad77"), hex("93a46d"), hex("6f8a52"), hex("9fa978") }
local GRASS, FOREST, MEADOW, SAND = hex("8a9f63"), hex("55683f"), hex("7d9160"), hex("d8c9a3")
do
	local land = model(root, "Land")
	local xs, zs, h = mesh.xs, mesh.zs, mesh.h
	local function v(i: number, k: number): any
		return Vector3.new(xs[i], h[i][k], zs[k])
	end
	for i = 1, #xs - 1 do
		for k = 1, #zs - 1 do
			if mesh.drawn(i, k) then
				local tris = if mesh.diag(i, k)
					then { { v(i, k), v(i + 1, k), v(i + 1, k + 1) }, { v(i, k), v(i + 1, k + 1), v(i, k + 1) } }
					else { { v(i, k), v(i + 1, k), v(i, k + 1) }, { v(i + 1, k), v(i + 1, k + 1), v(i, k + 1) } }
				for t, tri in tris do
					local a, b, c = tri[1], tri[2], tri[3]
					local m = (a + b + c) / 3
					local d = outsideOf(m.X, m.Z)
					local top = math.max(a.Y, b.Y, c.Y)
					local col: RGB
					local material = "Grass"
					if top < Backdrop.SEA_Y + 2.5 then
						col, material = SAND, "Sand"
					elseif d < 650 then
						col = GRASS -- the ring next to the terrain band
					elseif d < 2600 then
						local r = hash(i, k, t)
						col = if r < 0.16 then FOREST else FIELDS[1 + math.floor(hash(k, i, t + 3) * #FIELDS)]
					else
						col = if hash(i * 3, k, t) < 0.5 then FOREST else MEADOW
					end
					col = shade(col, 0.94 + 0.12 * hash(i, k * 7, t))
					triangle(land, "Tri", a, b, c, aerial(col, m.X, m.Z), material, "land", 2)
				end
			end
		end
	end
end

---------------------------------------------------------------------------------------------- ranges
type Range = {
	id: string,
	ax: number,
	az: number,
	from: number, -- degrees (sin < 0 is the south, toward -Z)
	to: number,
	step: number, -- studs along the crest between samples
	rows: { number }, -- offsets across the arc (negative toward the town); the 0 row is the crest
	taper: number, -- degrees over which the crest falls toward each end
	crest: (u: number, j: number) -> number,
	rowHeight: (r: number, crest: number, base: number, j: number) -> number,
	base: (x: number, z: number) -> number,
	endHeight: number,
	backRise: number?, -- the back row's height as a fraction of the crest above its base (hidden from the bay)
	colour: (top: number, crest: number, row: number, j: number) -> (RGB, string),
	thick: number,
	aerial: number,
}

local function ellipsePoint(r: Range, deg: number, offset: number): (number, number, number, number)
	local t = math.rad(deg)
	local px, pz = CX + r.ax * math.cos(t), CZ + r.az * math.sin(t)
	local nx, nz = math.cos(t) / r.ax, math.sin(t) / r.az
	local nl = math.sqrt(nx * nx + nz * nz)
	nx, nz = nx / nl, nz / nl
	return px + nx * offset, pz + nz * offset, nx, nz
end

-- Angles along the arc spaced `step` apart in arc length.
local function arcSamples(r: Range, offset: number, step: number): ({ number }, { number })
	local fine = 2000
	local lens = { 0 }
	local degs = { r.from }
	local px, pz = ellipsePoint(r, r.from, offset)
	for s = 1, fine do
		local deg = r.from + (r.to - r.from) * s / fine
		local x, z = ellipsePoint(r, deg, offset)
		table.insert(lens, lens[#lens] + math.sqrt((x - px) ^ 2 + (z - pz) ^ 2))
		table.insert(degs, deg)
		px, pz = x, z
	end
	local L = lens[#lens]
	local n = math.max(2, math.ceil(L / step))
	local outDeg, outU = {}, {}
	local j = 1
	for s = 0, n do
		local u = L * s / n
		while j < #lens - 1 and lens[j + 1] < u do
			j += 1
		end
		local f = if lens[j + 1] > lens[j] then (u - lens[j]) / (lens[j + 1] - lens[j]) else 0
		table.insert(outDeg, degs[j] + (degs[j + 1] - degs[j]) * f)
		table.insert(outU, u)
	end
	return outDeg, outU
end

local function onLand(x: number, z: number): number
	local xs, zs = mesh.xs, mesh.zs
	if x >= xs[1] and x <= xs[#xs] and z >= zs[1] and z <= zs[#zs] then
		return Backdrop.meshHeight(x, z)
	end
	return if z > 480 then COAST_FAR_Y else FAR_Y
end

local ROCK2, ROCK3, SNOW = hex("6f7a84"), hex("8592a0"), hex("eef2f6")
local FOREST1, FOREST2 = hex("4a5c3b"), hex("4e6049")

local RANGES: { Range } = {
	{
		id = "R1",
		ax = 7600,
		az = 4300,
		from = 155,
		to = 385,
		step = 480,
		rows = { -950, -430, 0, 750 },
		taper = 24,
		crest = function(u: number, j: number): number
			return 330
				+ 90 * math.sin(u / 1900 + 0.4)
				+ 80 * math.abs(math.sin(u / 830 + 1.1))
				+ 45 * (hash(j, 1) - 0.5)
		end,
		rowHeight = function(r: number, crest: number, base: number, j: number): number
			if r == 2 then
				return base + (crest - base) * (0.5 + 0.12 * hash(j, 2))
			end
			return base
		end,
		base = function(x: number, z: number): number
			return onLand(x, z) - 18
		end,
		endHeight = -30,
		colour = function(top: number, crest: number, row: number, j: number): (RGB, string)
			if row >= 3 then
				return shade(FOREST1, 0.9), "Grass"
			end
			if top > crest * 0.92 and hash(j, row) < 0.35 then
				return hex("6b7656"), "Grass"
			end
			return if hash(j, row, 5) < 0.75 then FOREST1 else hex("62744b"), "Grass"
		end,
		thick = 3,
		aerial = 0.9,
	},
	{
		id = "R2",
		ax = 10200,
		az = 6300,
		from = 172,
		to = 368,
		step = 640,
		rows = { -1500, -650, 0, 1100 },
		taper = 22,
		crest = function(u: number, j: number): number
			return 980
				+ 240 * math.sin(u / 2600 + 2.0)
				+ 220 * math.abs(math.sin(u / 1150 + 0.3))
				+ 90 * (hash(j, 11) - 0.5)
		end,
		rowHeight = function(r: number, crest: number, base: number, j: number): number
			if r == 2 then
				return base + (crest - base) * (0.42 + 0.14 * hash(j, 12))
			end
			return base
		end,
		base = function(_x: number, z: number): number
			return (if z > 480 then COAST_FAR_Y else FAR_Y) - 25
		end,
		endHeight = -10,
		colour = function(top: number, crest: number, row: number, j: number): (RGB, string)
			if row == 1 or (row >= 3 and top < crest * 0.5) then
				return FOREST2, "Grass"
			end
			if top > 1250 and row == 2 and hash(j, 13) < 0.5 then
				return mix(ROCK2, SNOW, 0.55), "Slate"
			end
			return mix(ROCK2, FOREST2, 0.25 * hash(j, row)), "Slate"
		end,
		thick = 4,
		aerial = 1,
	},
	{
		id = "R3",
		ax = 13200,
		az = 8800,
		from = 190,
		to = 350,
		step = 1000,
		rows = { -2100, -900, -260, 0, 900 },
		backRise = 0.4,
		taper = 14,
		crest = function(u: number, j: number): number
			return 1850
				+ 380 * math.sin(u / 3100 + 1.0)
				+ 320 * math.abs(math.sin(u / 1400))
				+ 140 * (hash(j, 21) - 0.5)
		end,
		rowHeight = function(r: number, crest: number, base: number, j: number): number
			if r == 2 then
				return base + (crest - base) * (0.5 + 0.1 * hash(j, 22))
			elseif r == 3 then
				return base + (crest - base) * (0.84 + 0.05 * hash(j, 23))
			end
			return base
		end,
		base = function(_x: number, _z: number): number
			return FAR_Y - 30
		end,
		endHeight = 0,
		colour = function(top: number, _crest: number, row: number, j: number): (RGB, string)
			if row == 3 and top > 1450 then
				return SNOW, "Snow"
			end
			if row == 2 and top > 1900 and hash(j, 24) < 0.6 then
				return mix(ROCK3, SNOW, 0.6), "Snow"
			end
			return ROCK3, "Slate"
		end,
		thick = 6,
		aerial = 1,
	},
}

local rangeCrest: { [string]: { any } } = {} -- crest points per range (tree line, fog cards)
do
	local ranges = model(root, "Ranges")
	for _, r in RANGES do
		local m = model(ranges, r.id)
		local degs, us = arcSamples(r, 0, r.step)
		local crestRow = table.find(r.rows, 0) :: number
		-- vertex grid: rows x samples
		local grid: { { any } } = {}
		local crests: { number } = {}
		for j, deg in degs do
			local dEnd = math.min(deg - r.from, r.to - deg)
			local e = Backdrop.smooth01(dEnd / r.taper)
			local cx0, cz0 = ellipsePoint(r, deg, 0)
			local crestBase = r.base(cx0, cz0)
			local crest = r.endHeight + (r.crest(us[j], j) - r.endHeight) * e
			crest = math.max(crest, crestBase + 10)
			crests[j] = crest
			grid[j] = {}
			for ri, off in r.rows do
				local x, z = ellipsePoint(r, deg, off)
				local base = r.base(x, z)
				local y
				if ri == crestRow then
					y = crest
				elseif ri == #r.rows and r.backRise then
					y = base + (crest - base) * r.backRise
				elseif ri == 1 or ri == #r.rows then
					y = base
				else
					y = r.rowHeight(ri, crest, base, j)
				end
				grid[j][ri] = Vector3.new(x, y, z)
			end
		end
		local pts = {}
		for j = 1, #degs do
			table.insert(pts, grid[j][crestRow])
		end
		rangeCrest[r.id] = pts
		for j = 1, #degs - 1 do
			for ri = 1, #r.rows - 1 do
				local a, b, c, d = grid[j][ri], grid[j + 1][ri], grid[j + 1][ri + 1], grid[j][ri + 1]
				-- split along the shorter diagonal so peaks stay sharp
				local t1, t2
				if (a - c).Magnitude <= (b - d).Magnitude then
					t1, t2 = { a, b, c }, { a, c, d }
				else
					t1, t2 = { a, b, d }, { b, c, d }
				end
				for ti, tri in { t1, t2 } do
					local top = math.max(tri[1].Y, tri[2].Y, tri[3].Y)
					local col, material = r.colour(top, math.max(crests[j], crests[j + 1]), ri, j * 2 + ti)
					local mid = (tri[1] + tri[2] + tri[3]) / 3
					col = shade(col, 0.84 + 0.26 * hash(j, ri, ti))
					triangleFit(
						m,
						"Tri",
						tri[1],
						tri[2],
						tri[3],
						aerial(col, mid.X, mid.Z, r.aerial),
						material,
						"ranges",
						r.thick
					)
				end
			end
		end
	end
end

---------------------------------------------------------------------------------------------- far land
do
	local far = model(root, "FarLand")
	local xs, zs = mesh.xs, mesh.zs
	local mx0, mx1, mz0 = xs[1], xs[#xs], zs[1]
	local function col(x: number, z: number): RGB
		return aerial(mix(hex("6f8656"), hex("5a6e47"), hash(x, z)), x, z, 0.9)
	end
	local X0, X1, Z0 = -14400, 16400, -9100
	tiles(far, "Far", X0, X1, Z0, mz0, FAR_Y, 4, col, "Grass", "farland")
	tiles(far, "Far", X0, mx0, mz0, 480, FAR_Y, 4, col, "Grass", "farland")
	tiles(far, "Far", mx1, X1, mz0, 480, FAR_Y, 4, col, "Grass", "farland")
	tiles(far, "Coast", X0, mx0, 480, Backdrop.OCEAN_FAR_Z, COAST_FAR_Y, 4, col, "Grass", "farland")
	tiles(far, "Coast", mx1, X1, 480, Backdrop.OCEAN_FAR_Z, COAST_FAR_Y, 4, col, "Grass", "farland")
end

---------------------------------------------------------------------------------------------- fog cards
type FogLayer = {
	range: string,
	offset: number,
	height: number,
	sink: number,
	colour: string,
	bottom: number,
	mid: number,
	layer: number,
	onLand: boolean,
}
local FOG: { FogLayer } = {
	-- at the foot of the foothills, in front of them
	{
		range = "R1",
		offset = -1180,
		height = 240,
		sink = 40,
		colour = "cfd6c4",
		bottom = 0.42,
		mid = 0.8,
		layer = 1,
		onLand = true,
	},
	-- behind the foothill crest, over the foot of the mountains
	{
		range = "R1",
		offset = 850,
		height = 720,
		sink = 60,
		colour = "c6d1d3",
		bottom = 0.3,
		mid = 0.72,
		layer = 2,
		onLand = false,
	},
	-- behind the mountains, over the foot of the snowy peaks
	{
		range = "R2",
		offset = 750,
		height = 1300,
		sink = 60,
		colour = "c2cfda",
		bottom = 0.22,
		mid = 0.66,
		layer = 3,
		onLand = false,
	},
}
do
	local cards = model(root, "FogCards")
	for _, f in FOG do
		local r: Range? = nil
		for _, rr in RANGES do
			if rr.id == f.range then
				r = rr
			end
		end
		assert(r, f.range)
		local rr = r :: Range
		local degs = arcSamples(rr, f.offset, 1900)
		local layerModel = model(cards, `Layer{f.layer}`)
		layerModel:SetAttribute("FogLayer", f.layer)
		for j = 1, #degs - 1 do
			local x0, z0 = ellipsePoint(rr, degs[j], f.offset)
			local x1, z1 = ellipsePoint(rr, degs[j + 1], f.offset)
			local len = math.sqrt((x1 - x0) ^ 2 + (z1 - z0) ^ 2)
			local mx, mz = (x0 + x1) / 2, (z0 + z1) / 2
			-- only where the range stands tall: none at its coastal ends, lower toward them
			local midDeg = (degs[j] + degs[j + 1]) / 2
			local e = Backdrop.smooth01((math.min(midDeg - rr.from, rr.to - midDeg) - rr.taper * 0.6) / rr.taper)
			if e < 0.25 or mz > 700 then
				continue
			end
			-- horizontal normal of the chord, toward the town
			local nx, nz = -(z1 - z0) / len, (x1 - x0) / len
			if nx * (CX - mx) + nz * (CZ - mz) < 0 then
				nx, nz = -nx, -nz
			end
			local ground = if f.onLand
				then math.min(onLand(x0, z0), onLand(mx, mz), onLand(x1, z1))
				else (if mz > 480 then COAST_FAR_Y else FAR_Y)
			local y0 = ground - f.sink
			local h = f.height * (0.45 + 0.55 * e) + f.sink
			local centre = Vector3.new(mx, y0 + h / 2, mz)
			local cf = CFrame.lookAt(centre, centre + Vector3.new(nx, 0, nz))
			local card = block(
				layerModel,
				"Card",
				Vector3.new(math.min(len, MAX_AXIS), h, 0.2),
				cf,
				hex(f.colour),
				"SmoothPlastic",
				"fogcards",
				{ transparency = 1 }
			)
			card:SetAttribute("FogLayer", f.layer)
			local gui = Instance.new("SurfaceGui")
			gui.Name = "Fog"
			gui.Face = Enum.NormalId.Front
			gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			gui.PixelsPerStud = math.clamp(160 / h, 0.05, 1)
			gui.LightInfluence = 0
			gui.AlwaysOnTop = false
			gui.Parent = card
			local frame = Instance.new("Frame")
			frame.Name = "Haze"
			frame.Size = roblox.UDim2.fromScale(1, 1)
			frame.BorderSizePixel = 0
			frame.BackgroundTransparency = 0
			frame.BackgroundColor3 = Color3.fromHex(f.colour)
			frame.Parent = gui
			local grad = Instance.new("UIGradient")
			grad.Rotation = 90 -- keypoint 0 at the top
			local sinkT = f.sink / h
			grad.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.5 * (1 - sinkT), f.mid),
				NumberSequenceKeypoint.new(1 - sinkT, f.bottom),
				NumberSequenceKeypoint.new(1, f.bottom),
			})
			card:SetAttribute("Strength", e)
			grad.Parent = frame
		end
	end
end

---------------------------------------------------------------------------------------------- trees
local TREE = { hex("4a5b3c"), hex("53653f"), hex("46573a"), hex("5a6b44") }
do
	local trees = model(root, "Trees")
	local function clump(x: number, z: number, along: number, len: number, hgt: number, depth: number, seed: number)
		local y = Backdrop.meshHeight(x, z)
		local cf = CFrame.new(x, y + hgt * 0.36, z) * CFrame.Angles(0, along, 0)
		local col = aerial(shade(TREE[1 + math.floor(hash(seed, 3) * #TREE)], 0.92 + 0.16 * hash(seed, 4)), x, z)
		ellipsoid(trees, "Clump", Vector3.new(depth, hgt, len), cf, col, "trees")
	end
	-- hedgerows along mesh grid lines on the plains
	local xs, zs = mesh.xs, mesh.zs
	local n = 0
	local function hedge(x0: number, z0: number, x1: number, z1: number, seed: number)
		local len = math.sqrt((x1 - x0) ^ 2 + (z1 - z0) ^ 2)
		local along = math.atan2(x1 - x0, z1 - z0)
		local count = math.floor(len / 95)
		for s = 0, count do
			local f = (s + 0.5) / (count + 1)
			if hash(seed, s) > 0.12 then -- gaps
				local x, z = x0 + (x1 - x0) * f, z0 + (z1 - z0) * f
				clump(x, z, along, 105 + 30 * hash(seed, s, 1), 26 + 14 * hash(seed, s, 2), 30, seed * 100 + s)
				n += 1
			end
		end
	end
	for i = 1, #xs - 1 do
		for k = 1, #zs - 1 do
			if mesh.drawn(i, k) then
				local cx, cz = (xs[i] + xs[i + 1]) / 2, (zs[k] + zs[k + 1]) / 2
				local d = outsideOf(cx, cz)
				if d > 650 and d < 1500 and cz < 1300 then
					-- along the cell's lower z edge or its lower x edge, by hash
					local hsel = hash(i, k, 9)
					if hsel < 0.38 then
						hedge(xs[i], zs[k], xs[i + 1], zs[k], i * 31 + k)
					elseif hsel < 0.66 then
						hedge(xs[i], zs[k], xs[i], zs[k + 1], i * 37 + k)
					end
				end
			end
		end
	end
	-- copses: a few round woods on the plains
	for c = 1, 14 do
		local x = -5200 + 12400 * hash(c, 41)
		local z = -3400 + 1000 * hash(c, 42)
		if (x > clamp.minX - 500 and x < clamp.maxX + 500) or (z < clamp.minZ - 700) then
			for t = 1, 5 do
				local a = hash(c, t, 43) * math.pi * 2
				local rr = 60 * hash(c, t, 44)
				clump(x + math.cos(a) * rr, z + math.sin(a) * rr, a, 70, 46 + 16 * hash(c, t), 70, c * 10 + t)
				n += 1
			end
		end
	end
	-- the tree line on the foothill crest (south part)
	local crest = rangeCrest.R1
	for j = 1, #crest - 1 do
		local a, b = crest[j], crest[j + 1]
		local seg = (b - a).Magnitude
		local per = math.floor(seg / 120)
		for s = 0, per - 1 do
			local f = (s + 0.3 + 0.4 * hash(j, s, 50)) / per
			local p = a:Lerp(b, f)
			if p.Z < CZ - 1800 and hash(j, s, 51) > 0.3 then
				local big = hash(j, s, 52)
				local hgt = 38 + 52 * big * big
				local wide = 60 + 90 * hash(j, s, 54)
				local along = math.atan2(b.X - a.X, b.Z - a.Z) + 0.6 * (hash(j, s, 55) - 0.5)
				local col = aerial(
					shade(TREE[1 + math.floor(hash(j, s, 53) * #TREE)], 0.9 + 0.15 * hash(j, s, 56)),
					p.X,
					p.Z,
					0.9
				)
				ellipsoid(
					trees,
					"Crest",
					Vector3.new(wide * 0.7, hgt, wide),
					CFrame.new(p.X, p.Y + hgt * 0.2, p.Z) * CFrame.Angles(0, along, 0),
					col,
					"trees"
				)
			end
		end
	end
end

---------------------------------------------------------------------------------------------- road
local roadPts: { any } = {}
do
	local road = model(root, "Road")
	road:SetAttribute("Width", 22)
	local function rz(x: number): number
		return clamp.minZ - 760 + 130 * math.sin(x / 1900 + 0.5) + 50 * math.sin(x / 640 + 1.7)
	end
	local x = -5900
	while x <= 7300 do
		local z = rz(x)
		table.insert(roadPts, Vector3.new(x, Backdrop.meshHeight(x, z) + 1.4, z))
		x += 150
	end
	for j = 1, #roadPts - 1 do
		local a, b = roadPts[j], roadPts[j + 1]
		local len = (b - a).Magnitude + 2
		local seg = block(
			road,
			string.format("Seg_%03d", j),
			Vector3.new(22, 1, len),
			CFrame.lookAt((a + b) / 2, b),
			hex("55595a"),
			"Asphalt",
			"road"
		)
		seg:SetAttribute("Index", j)
	end
end

---------------------------------------------------------------------------------------------- farms
do
	local farms = model(root, "Farms")
	local spots = {
		{ -1200, -2900 },
		{ 1500, -2750 },
		{ 3900, -3150 },
		{ -3600, -2800 },
		{ 5600, -1400 },
		{ -4300, 300 },
		{ 5900, 500 },
		{ -400, -3250 },
	}
	for f, s in spots do
		local x, z = s[1], s[2]
		local y = Backdrop.meshHeight(x, z)
		local yaw = hash(f, 61) * math.pi
		local base = CFrame.new(x, y, z) * CFrame.Angles(0, yaw, 0)
		local red = aerial(hex("9a4a3c"), x, z, 0.8)
		local roofCol = aerial(hex("5d5550"), x, z, 0.8)
		local cream = aerial(hex("e4dac3"), x, z, 0.8)
		-- barn with a pitched roof (two wedges)
		block(farms, "Barn", Vector3.new(34, 18, 52), base * CFrame.new(0, 7, 0), red, "WoodPlanks", "farms")
		part(
			"WedgePart",
			farms,
			"Roof",
			Vector3.new(52, 9, 18),
			base * CFrame.new(-9, 20.5, 0) * CFrame.Angles(0, math.pi / 2, 0),
			roofCol,
			"Slate",
			"farms"
		)
		part(
			"WedgePart",
			farms,
			"Roof",
			Vector3.new(52, 9, 18),
			base * CFrame.new(9, 20.5, 0) * CFrame.Angles(0, -math.pi / 2, 0),
			roofCol,
			"Slate",
			"farms"
		)
		-- farmhouse and silo
		block(farms, "House", Vector3.new(22, 14, 18), base * CFrame.new(46, 5, 18), cream, "Plaster", "farms")
		block(farms, "HouseRoof", Vector3.new(24, 4, 20), base * CFrame.new(46, 14, 18), roofCol, "Slate", "farms")
		pillar(
			farms,
			"Silo",
			(base * CFrame.new(-28, -2, -30)).Position,
			34,
			11,
			aerial(hex("b9bdb8"), x, z, 0.8),
			"Metal",
			"farms"
		)
	end
end

---------------------------------------------------------------------------------------------- ocean
do
	local ocean = model(root, "Ocean")
	local NEAR_SEA, MID_SEA, FAR_SEA = hex("2b5a66"), hex("36696f"), hex("5a8690")
	local function col(_x: number, z: number): RGB
		local d = math.max(0, z - 1490)
		if d < 6000 then
			return mix(NEAR_SEA, MID_SEA, d / 6000)
		end
		return mix(MID_SEA, FAR_SEA, (d - 6000) / 9000)
	end
	local X0, X1, Z1 = -16400, 18400, 16200
	local bx0, bx1 = clamp.minX - Backdrop.BAND, clamp.maxX + Backdrop.BAND
	local opts: PartOpts = { reflectance = 0.12 }
	tiles(ocean, "Sea", X0, X1, Backdrop.OCEAN_NEAR_Z, Z1, Backdrop.OCEAN_Y, 2, col, "SmoothPlastic", "ocean", opts)
	tiles(
		ocean,
		"Sea",
		X0,
		bx0,
		Backdrop.OCEAN_FAR_Z,
		Backdrop.OCEAN_NEAR_Z,
		Backdrop.OCEAN_Y,
		2,
		col,
		"SmoothPlastic",
		"ocean",
		opts
	)
	tiles(
		ocean,
		"Sea",
		bx1,
		X1,
		Backdrop.OCEAN_FAR_Z,
		Backdrop.OCEAN_NEAR_Z,
		Backdrop.OCEAN_Y,
		2,
		col,
		"SmoothPlastic",
		"ocean",
		opts
	)
end

---------------------------------------------------------------------------------------------- coast: pier, marina, boats, lighthouse
local WOOD, WOOD_DARK, WHITE, CREAM = hex("806147"), hex("5e4836"), hex("e9e6dc"), hex("e7dcc4")
local NEAR: PartOpts = { collide = true, query = true }

local function lampPost(parent: any, base: any, group: string)
	pillar(parent, "LampPost", base, 9, 0.5, hex("364b51"), "Metal", group)
	local head = ball(parent, "LampHead", base + Vector3.new(0, 9.6, 0), 1.4, hex("ffe0a8"), "Neon", group)
	head:SetAttribute("NightLight", true)
end

do
	local coast = model(root, "Coast")
	local SEA = Backdrop.SEA_Y

	-- pier north of Sycamore Park: deck, ramp, piles, rails, lamps and a bait hut on the T-head
	local pier = model(coast, "Pier")
	local PX, Z0, Z1, DECK = -150, 1440, 1850, SEA + 5.5
	local shoreY = Backdrop.groundAt(PX, Z0 - 30)
	part(
		"WedgePart",
		pier,
		"Ramp",
		Vector3.new(12, math.max(0.5, DECK - shoreY), 30),
		CFrame.new(PX, (DECK + shoreY) / 2, Z0 - 15),
		WOOD,
		"WoodPlanks",
		"pier",
		NEAR
	)
	local span = (Z1 - Z0) / 4
	for s = 0, 3 do
		local zc = Z0 + (s + 0.5) * span
		block(pier, "Deck", Vector3.new(12, 1, span), CFrame.new(PX, DECK - 0.5, zc), WOOD, "WoodPlanks", "pier", NEAR)
		block(
			pier,
			"Rail",
			Vector3.new(0.6, 0.6, span),
			CFrame.new(PX - 5.7, DECK + 3, zc),
			WOOD_DARK,
			"Wood",
			"pier",
			NEAR
		)
		block(
			pier,
			"Rail",
			Vector3.new(0.6, 0.6, span),
			CFrame.new(PX + 5.7, DECK + 3, zc),
			WOOD_DARK,
			"Wood",
			"pier",
			NEAR
		)
	end
	block(pier, "Head", Vector3.new(60, 1, 26), CFrame.new(PX, DECK - 0.5, Z1 + 13), WOOD, "WoodPlanks", "pier", NEAR)
	block(pier, "Rail", Vector3.new(60, 0.6, 0.6), CFrame.new(PX, DECK + 3, Z1 + 25.7), WOOD_DARK, "Wood", "pier", NEAR)
	for z = Z0 + 10, Z1 + 20, 30 do
		for _, dx in { -5.2, 5.2 } do
			pillar(
				pier,
				"Pile",
				Vector3.new(PX + dx, SEA - 12, z),
				DECK - 0.5 - (SEA - 12),
				1.6,
				WOOD_DARK,
				"Wood",
				"pier"
			)
		end
	end
	for _, dx in { -27, 27 } do
		pillar(
			pier,
			"Pile",
			Vector3.new(PX + dx, SEA - 12, Z1 + 13),
			DECK - 0.5 - (SEA - 12),
			1.6,
			WOOD_DARK,
			"Wood",
			"pier"
		)
	end
	for z = Z0 + 40, Z1, 100 do
		lampPost(pier, Vector3.new(PX + 5.5, DECK, z), "pier")
	end
	block(
		pier,
		"Hut",
		Vector3.new(14, 9, 10),
		CFrame.new(PX + 16, DECK + 4.5, Z1 + 16),
		hex("d9cba8"),
		"WoodPlanks",
		"pier",
		NEAR
	)
	block(
		pier,
		"HutRoof",
		Vector3.new(16, 1.4, 12),
		CFrame.new(PX + 16, DECK + 9.7, Z1 + 16),
		hex("4c5a60"),
		"Slate",
		"pier",
		NEAR
	)

	-- marina at the river mouth: breakwaters of tumbled rock, pontoons, moored boats, harbour lights
	local marina = model(coast, "Marina")
	local function rocks(x0: number, z0: number, x1: number, z1: number, seed: number)
		local len = math.sqrt((x1 - x0) ^ 2 + (z1 - z0) ^ 2)
		local n = math.floor(len / 21)
		for s = 0, n do
			local f = s / n
			local x, z = x0 + (x1 - x0) * f, z0 + (z1 - z0) * f
			local cf = CFrame.new(x, SEA + 1.2 + 1.5 * hash(seed, s), z)
				* CFrame.Angles(
					0.15 * (hash(seed, s, 1) - 0.5),
					math.pi * hash(seed, s, 2),
					0.15 * (hash(seed, s, 3) - 0.5)
				)
			local col = shade(hex("8f8b80"), 0.86 + 0.22 * hash(seed, s, 4))
			block(
				marina,
				"Rock",
				Vector3.new(24 + 10 * hash(seed, s, 5), 12, 18 + 8 * hash(seed, s, 6)),
				cf,
				col,
				"Slate",
				"marina",
				NEAR
			)
		end
	end
	local WX, EX, NZ = 1820, 2720, 1870
	rocks(WX, Backdrop.shoreZ(WX) - 15, WX, NZ, 1)
	rocks(WX, NZ, 2420, NZ, 2)
	rocks(EX, Backdrop.shoreZ(EX) - 15, EX, 1790, 3)
	rocks(EX, 1790, 2585, 1805, 4)
	for _, hl in { { 2420, NZ, "3fd66b" }, { 2585, 1805, "ff3b30" } } do
		pillar(
			marina,
			"LightPost",
			Vector3.new(hl[1] :: number, SEA + 6, hl[2] :: number),
			9,
			1.2,
			WHITE,
			"SmoothPlastic",
			"marina"
		)
		local l = ball(
			marina,
			"HarbourLight",
			Vector3.new(hl[1] :: number, SEA + 16, hl[2] :: number),
			2.2,
			hex(hl[3] :: string),
			"Neon",
			"marina"
		)
		l:SetAttribute("Blink", "harbour")
	end
	local PY = SEA + 1.6
	local pz = 1532
	block(
		marina,
		"Pontoon",
		Vector3.new(800, 1.2, 8),
		CFrame.new(2260, PY - 0.6, pz),
		hex("9c8f7c"),
		"WoodPlanks",
		"marina",
		NEAR
	)
	local gz0 = Backdrop.shoreZ(2000) - 25
	local gy0 = Backdrop.groundAt(2000, gz0)
	do
		local a, b = Vector3.new(2000, gy0 + 0.4, gz0), Vector3.new(2000, PY - 0.3, pz - 4)
		block(
			marina,
			"Gangway",
			Vector3.new(5, 0.6, (b - a).Magnitude),
			CFrame.lookAt((a + b) / 2, b),
			WOOD,
			"WoodPlanks",
			"marina",
			NEAR
		)
	end
	local hullCols = { WHITE, hex("2f4a66"), WHITE, hex("477b88"), WHITE, hex("8a3b33") }
	for f = 0, 8 do
		local fx = 1900 + 88 * f
		block(
			marina,
			"Finger",
			Vector3.new(4, 1, 62),
			CFrame.new(fx, PY - 0.5, pz + 35),
			hex("9c8f7c"),
			"WoodPlanks",
			"marina",
			NEAR
		)
		if f < 8 then
			local bx = fx + 44
			local hull = hullCols[1 + f % #hullCols]
			local boatCf = CFrame.new(bx, SEA + 1.2, pz + 40) * CFrame.Angles(0, (hash(f, 71) - 0.5) * 0.08, 0)
			if f % 2 == 0 then
				-- sailboat: hull, bow, cabin, mast, boom
				block(marina, "Hull", Vector3.new(8, 3, 22), boatCf, hull, "SmoothPlastic", "boats")
				part(
					"WedgePart",
					marina,
					"Bow",
					Vector3.new(8, 3, 8),
					boatCf * CFrame.new(0, 0, 15) * CFrame.Angles(0, math.pi, 0),
					hull,
					"SmoothPlastic",
					"boats"
				)
				block(
					marina,
					"Cabin",
					Vector3.new(5, 2.4, 8),
					boatCf * CFrame.new(0, 2.6, -2),
					CREAM,
					"SmoothPlastic",
					"boats"
				)
				pillar(marina, "Mast", (boatCf * CFrame.new(0, 1.5, 3)).Position, 34, 0.7, WHITE, "Metal", "boats")
				strut(
					marina,
					"Boom",
					(boatCf * CFrame.new(0, 5, 3)).Position,
					(boatCf * CFrame.new(0, 5, -9)).Position,
					0.5,
					WHITE,
					"Metal",
					"boats"
				)
			else
				-- motor boat: hull, bow, cabin, windscreen
				block(marina, "Hull", Vector3.new(7, 3, 18), boatCf, hull, "SmoothPlastic", "boats")
				part(
					"WedgePart",
					marina,
					"Bow",
					Vector3.new(7, 3, 6),
					boatCf * CFrame.new(0, 0, 12) * CFrame.Angles(0, math.pi, 0),
					hull,
					"SmoothPlastic",
					"boats"
				)
				block(
					marina,
					"Cabin",
					Vector3.new(6, 3.2, 7),
					boatCf * CFrame.new(0, 3.1, -1),
					CREAM,
					"SmoothPlastic",
					"boats"
				)
				block(
					marina,
					"Screen",
					Vector3.new(5.6, 2, 0.3),
					boatCf * CFrame.new(0, 3.4, 3),
					hex("8db9bf"),
					"Glass",
					"boats",
					{ transparency = 0.35 }
				)
			end
		end
	end
	-- harbour office on the beach
	local oy = Backdrop.groundAt(2250, 1430)
	block(marina, "Office", Vector3.new(34, 12, 20), CFrame.new(2250, oy + 5.5, 1430), CREAM, "Plaster", "marina", NEAR)
	block(
		marina,
		"OfficeRoof",
		Vector3.new(37, 1.6, 23),
		CFrame.new(2250, oy + 12.3, 1430),
		hex("4c5a60"),
		"Slate",
		"marina",
		NEAR
	)
	pillar(marina, "Flagpole", Vector3.new(2275, oy, 1452), 28, 0.5, WHITE, "Metal", "marina")
	block(
		marina,
		"Flag",
		Vector3.new(0.2, 4, 7),
		CFrame.new(2275, oy + 25.5, 1448.3),
		hex("477b88"),
		"Fabric",
		"marina"
	)

	-- boats at sea
	local boats = model(coast, "Boats")
	for b, s in { { -1400, 2900, 0.6 }, { 3700, 3500, -0.4 }, { 900, 5200, 1.9 }, { 5400, 2400, 2.6 } } do
		local cf = CFrame.new(s[1], SEA + 1.2, s[2]) * CFrame.Angles(0, s[3], 0)
		block(
			boats,
			"Hull",
			Vector3.new(8, 3, 22),
			cf,
			if b % 2 == 0 then hex("2f4a66") else WHITE,
			"SmoothPlastic",
			"boats"
		)
		pillar(boats, "Mast", (cf * CFrame.new(0, 1.5, 2)).Position, 34, 0.7, WHITE, "Metal", "boats")
		part(
			"WedgePart",
			boats,
			"Sail",
			Vector3.new(0.3, 30, 13),
			cf * CFrame.new(0, 18, -5),
			hex("f4f1e6"),
			"Fabric",
			"boats"
		)
	end
	-- a coaster at anchor offshore (its riding light shows at night)
	local ship = CFrame.new(-2600, SEA, 6400) * CFrame.Angles(0, 0.35, 0)
	block(boats, "ShipHull", Vector3.new(44, 22, 260), ship * CFrame.new(0, 6, 0), hex("5b2f2a"), "Metal", "boats")
	block(boats, "ShipDeck", Vector3.new(42, 2, 250), ship * CFrame.new(0, 17.5, 0), hex("4a4d4c"), "Metal", "boats")
	block(boats, "Bridge", Vector3.new(36, 20, 30), ship * CFrame.new(0, 28, -100), WHITE, "SmoothPlastic", "boats")
	block(boats, "Containers", Vector3.new(36, 14, 150), ship * CFrame.new(0, 25, 20), hex("477b88"), "Metal", "boats")
	local riding =
		ball(boats, "ShipLight", (ship * CFrame.new(0, 46, -100)).Position, 3, hex("fff4d6"), "Neon", "boats")
	riding:SetAttribute("NightLight", true)

	-- lighthouse on a skerry north-east of the marina
	local lh = model(coast, "Lighthouse")
	local LX, LZ = 6300, 2050
	for s = 1, 4 do
		local a = s * 1.7
		block(
			lh,
			"Skerry",
			Vector3.new(60 - 8 * s, 10 + 3 * s, 46 - 6 * s),
			CFrame.new(LX + 10 * math.cos(a), SEA + 1 + s, LZ + 10 * math.sin(a)) * CFrame.Angles(0, a, 0.06),
			shade(hex("8a877e"), 0.85 + 0.05 * s),
			"Slate",
			"lighthouse"
		)
	end
	local ly = SEA + 8
	for s = 0, 4 do
		pillar(
			lh,
			"TowerBand",
			Vector3.new(LX, ly + s * 13, LZ),
			13,
			14 - s * 1.2,
			if s % 2 == 0 then WHITE else hex("b34c45"),
			"SmoothPlastic",
			"lighthouse"
		)
	end
	local top = ly + 65
	pillar(lh, "Gallery", Vector3.new(LX, top, LZ), 1.5, 15, hex("2f3a3d"), "Metal", "lighthouse")
	local lamp = pillar(lh, "Lamp", Vector3.new(LX, top + 1.5, LZ), 6, 7, hex("fff1c9"), "Neon", "lighthouse")
	lamp:SetAttribute("Blink", "lighthouse")
	pillar(lh, "Cap", Vector3.new(LX, top + 7.5, LZ), 3, 9, hex("2f3a3d"), "Metal", "lighthouse")
end

---------------------------------------------------------------------------------------------- tower
local towerFoot = Vector3.new(0, 0, 0)
do
	local T = Backdrop.TOWER
	local tower = model(root, "Tower")
	local y0 = Backdrop.meshHeight(T.x, T.z) - 2
	towerFoot = Vector3.new(T.x, y0, T.z)
	tower:SetAttribute("SunsetAzimuth", true)
	local RED, STEEL = hex("b34c45"), hex("aeb6b1")
	local SECTIONS, H = 10, T.height
	local function legPoint(leg: number, y: number): any
		local r = 18 + (4 - 18) * (y / H)
		local a = math.rad(90 + 120 * leg)
		return Vector3.new(T.x + r * math.cos(a), y0 + y, T.z + r * math.sin(a))
	end
	for s = 0, SECTIONS - 1 do
		local ya, yb = s * H / SECTIONS, (s + 1) * H / SECTIONS
		local legCol = if s % 2 == 0 then RED else STEEL
		for leg = 0, 2 do
			local nxt = (leg + 1) % 3
			strut(tower, "Leg", legPoint(leg, ya), legPoint(leg, yb), 2.6, legCol, "Metal", "tower")
			-- zig-zag diagonal on each face, alternating direction per section
			if s % 2 == 0 then
				strut(tower, "Brace", legPoint(leg, ya), legPoint(nxt, yb), 1.1, STEEL, "Metal", "tower")
			else
				strut(tower, "Brace", legPoint(nxt, ya), legPoint(leg, yb), 1.1, STEEL, "Metal", "tower")
			end
			strut(tower, "Ring", legPoint(leg, yb), legPoint(nxt, yb), 1.1, STEEL, "Metal", "tower")
		end
	end
	block(tower, "Mast", Vector3.new(1.8, 36, 1.8), CFrame.new(T.x, y0 + H + 18, T.z), STEEL, "Metal", "tower")
	local beacon = ball(tower, "Beacon", Vector3.new(T.x, y0 + H + 40, T.z), 9, hex("ff351e"), "Neon", "tower")
	beacon:SetAttribute("Blink", "obstruction")
	local light = Instance.new("PointLight")
	light.Name = "Glow"
	light.Color = Color3.fromRGB(255, 60, 40)
	light.Range = 60
	light.Brightness = 4
	light.Shadows = false
	light.Parent = beacon
	for _, frac in { 1 / 3, 2 / 3 } do
		for leg = 0, 2 do
			local p = legPoint(leg, H * frac)
			local outward = (p - Vector3.new(T.x, p.Y, T.z)).Unit
			ball(tower, "SideLight", p + outward * 2.5, 5, hex("ff351e"), "Neon", "tower")
		end
	end
	block(
		tower,
		"Hut",
		Vector3.new(20, 10, 14),
		CFrame.new(T.x + 34, y0 + 5, T.z - 10),
		hex("9ea39d"),
		"Concrete",
		"tower"
	)
	block(
		tower,
		"HutRoof",
		Vector3.new(22, 1.4, 16),
		CFrame.new(T.x + 34, y0 + 10.7, T.z - 10),
		hex("5d6366"),
		"Metal",
		"tower"
	)
end

---------------------------------------------------------------------------------------------- write
root:SetAttribute("PartCount", total)
root:SetAttribute("SeaY", Backdrop.SEA_Y)
root:SetAttribute("TowerFoot", towerFoot)
if not fs.isDir("build") then
	fs.writeDir("build")
end
local bytes = roblox.serializeModel({ root })
fs.writeFile(out, bytes)
local groups: { string } = {}
for g in counts do
	table.insert(groups, g)
end
table.sort(groups)
local lines = {}
for _, g in groups do
	table.insert(lines, `{g} {counts[g]}`)
end
fs.writeFile(
	report,
	serde.encode("json", {
		out = out,
		bytes = #bytes,
		parts = total,
		groups = counts,
		tower = { x = towerFoot.X, y = towerFoot.Y, z = towerFoot.Z },
		roadPoints = #roadPts,
	}, true)
)
print(`backdrop: {total} parts ({table.concat(lines, ", ")}) -> {out} ({#bytes} bytes)`)
