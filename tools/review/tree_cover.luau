--!strict
-- tools/review/tree_cover.luau: export what the tree-cover map draws (owner D34: "making the map have more trees")
-- to build/review/tree_cover.json; tools/review/tree_cover.py renders it (before/after the D34 trees).
--   the town's bake plans (WorldGen/Bake.plans, no rbxm needed) as XZ boxes by kind: roads, buildings (lot parts over
--   2 studs tall), flat lot parts; the ground (World/Height with the D32 extensions) on a 20-stud grid; every tree:
--   the route trees (the bake's Tree_ plans: harvested, hollow, D32 planted and the D34 grown) with their crowns'
--   reach (data/art/trees_v2.json and data/art/grove.json part bounds, else 12 studs), and the D34 woods
--   (generated/Woods: kind, place, scale, crown) unless --before.
-- Usage (repo root): lune run tools/review/tree_cover.luau [--before] [--out build/review/tree_cover.json]
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local Bake = require("../../src/worldgen/Bake")
local Data = require("../../src/shared/Data")
local Colliders = require("../../src/shared/World/Colliders")
local Height = require("../../src/shared/World/Height")

local out = "build/review/tree_cover.json"
local before = false
for i, a in process.args do
	if a == "--out" then
		out = process.args[i + 1]
	elseif a == "--before" then
		before = true
	end
end

local TE = require("../../generated/TerrainExtensions") :: any
Height.configure(TE)

local function r1(n: number): number
	return math.floor(n * 10 + 0.5) / 10
end

local data = Bake.data()
local plans = Bake.plans(data)
local boxes = {}
for _, p in plans do
	local kind = if p.kind == "road" then "road" elseif p.kind == "lot" then "lot" else nil
	if kind then
		for _, s in p.parts do
			if (s.transparency or 0) < 1 then
				local c, sn = math.abs(math.cos(s.yaw)), math.abs(math.sin(s.yaw))
				local hx = (c * s.sx + sn * s.sz) / 2
				local hz = (sn * s.sx + c * s.sz) / 2
				local cat = kind
				if kind == "lot" then
					cat = if s.sy > 2 and (s.canCollide or s.role == "Roof") then "building" else "flat"
				end
				table.insert(boxes, { cat, r1(s.cx - hx), r1(s.cz - hz), r1(s.cx + hx), r1(s.cz + hz) })
			end
		end
	end
end

-- the expansion (its own bakes): streets, pads and paths as paving, every venue's site, the solid boxes of
-- World/Colliders (buildings, the built venues, the bowling alley), the rides' lines and the open zones
local ex = require("../../generated/Expansion") :: any
local lines = {}
local polys = {}
for _, r in ex.strips or {} do
	local a, b = math.min(r.start, r["end"]), math.max(r.start, r["end"])
	if r.axis == "x" then
		table.insert(boxes, { "road", r1(a), r1(r.coord - r.width / 2), r1(b), r1(r.coord + r.width / 2) })
	elseif r.axis == "z" then
		table.insert(boxes, { "road", r1(r.coord - r.width / 2), r1(a), r1(r.coord + r.width / 2), r1(b) })
	end
end
for _, p in ex.pads or {} do
	table.insert(boxes, { "road", r1(p.rect.x0), r1(p.rect.z0), r1(p.rect.x1), r1(p.rect.z1) })
end
for _, p in ex.paths or {} do
	local pts = {}
	for _, q in p.points do
		table.insert(pts, { r1(q[1]), r1(q[2]) })
	end
	table.insert(lines, { "path", p.width, pts })
end
for _, r in ex.rides or {} do
	local pts = {}
	for _, q in r.points or {} do
		if type(q) == "table" and #q >= 3 then
			table.insert(pts, { r1(q[1]), r1(q[3]) })
		end
	end
	if #pts >= 2 then
		table.insert(lines, { "ride", 3, pts })
	end
end
for _, v in ex.venues or {} do
	if v.sitePoly and #v.sitePoly >= 3 then
		local pts = {}
		for _, q in v.sitePoly do
			table.insert(pts, { r1(q[1]), r1(q[2]) })
		end
		table.insert(polys, { "site", pts })
	end
end
for _, z in ex.zones or {} do
	if z.rect then
		local q = z.rect
		table.insert(polys, { "zone", { { q.x0, q.z0 }, { q.x1, q.z0 }, { q.x1, q.z1 }, { q.x0, q.z1 } } })
	end
end
for _, b in Colliders.fromData(Data.default()).boxes do
	table.insert(boxes, { "building", r1(b.cx - b.hw), r1(b.cz - b.hd), r1(b.cx + b.hw), r1(b.cz + b.hd) })
end

-- the crowns' reach of the route trees: the widest leaf part of their Blender model
local reach: { [number]: number } = {}
local function addReach(path: string, list: string)
	if not fs.isFile(path) then
		return
	end
	local doc = serde.decode("json", fs.readFile(path))
	for _, t in doc[list] or {} do
		local r = 0
		for name, part in t.parts or {} do
			if string.sub(name, 1, 6) == "Leaves" then
				r = math.max(r, part.size[1] / 2, part.size[3] / 2)
			end
		end
		if t.trunkRoute and r > 0 then
			reach[t.trunkRoute] = r
		end
	end
end
addReach("data/art/trees_v2.json", "trees")
addReach("data/art/grove.json", "climbable")

local d = Data.default()
local reg = d:routes()
local shapes = (d:module("TreeShapes") :: any).trees or {}
local grown: { [number]: string } = {}
local planted: { [number]: number } = {}
for _, tr in shapes do
	if tr.kind == "grown" then
		grown[tr.trunk] = tr.label
	elseif tr.kind == "planted" then
		planted[tr.trunk] = tr.source
	end
end
local trees = {}
for _, p in plans do
	local r = if p.category == "tree" then reg:get(p.attributes.TrunkRoute) else nil
	if r then
		local f = r.points[1]
		local top = r.points[#r.points]
		local rr = reach[r.id] or (if planted[r.id] then reach[planted[r.id]] else nil) or 12
		local kind = if grown[r.id] then "grown" else "route"
		if not (before and grown[r.id]) then
			table.insert(trees, { kind, r1(f.x), r1(f.z), r1(rr), r1(top.y - f.y), grown[r.id] or r.name })
		end
	end
end

-- the D34 woods (data/woods.json kinds: family and crown at scale 1) and the D35 climbs (the trees other bakes draw,
-- climbable now: drawn as route trees with a ring), unless --before
local woods = {}
local climbs = 0
do
	local compiled = d:module("TreeShapes") :: any
	local kinds = serde.decode("json", fs.readFile("data/woods.json")).kinds
	if compiled and compiled.woods then
		if not before then
			for _, t in compiled.woods.trees do
				local k = kinds[t.kind]
				table.insert(woods, { t.kind, k.family, r1(t.x), r1(t.z), r1(k.crown * t.scale) })
			end
		end
		-- (before D35 these trees had no route)
		for _, c in compiled.woods.climbs do
			climbs += 1
			local kind = if before then "noroute" else "climb"
			table.insert(trees, { kind, r1(c.x), r1(c.z), r1(c.reach), r1(c.climb.trunk.height), c.label })
		end
	end
end

local clamp = Height.worldClamp()
local B = {
	x0 = math.floor(clamp.minX / 20) * 20,
	x1 = math.ceil(clamp.maxX / 20) * 20,
	z0 = math.floor(clamp.minZ / 20) * 20,
	z1 = math.ceil(clamp.maxZ / 20) * 20,
	step = 20,
}
local cells = {}
local nx = math.floor((B.x1 - B.x0) / B.step) + 1
local nz = math.floor((B.z1 - B.z0) / B.step) + 1
for k = 0, nz - 1 do
	for i = 0, nx - 1 do
		local x, z = B.x0 + i * B.step, B.z0 + k * B.step
		table.insert(cells, { r1(Height.at(x, z)), if Height.insideRiverWater(x, z) then 1 else 0 })
	end
end

local doc = {
	before = before,
	bounds = B,
	clamp = { clamp.minX, clamp.maxX, clamp.minZ, clamp.maxZ },
	grid = { nx = nx, nz = nz, cells = cells },
	boxes = boxes,
	lines = lines,
	polys = polys,
	trees = trees,
	woods = woods,
}
local dir = string.match(out, "^(.*)/[^/]*$")
if dir and not fs.isDir(dir) then
	fs.writeDir(dir)
end
fs.writeFile(out, serde.encode("json", doc))
print(
	string.format(
		"tree_cover: %d boxes, %d route trees (%d climbs), %d woods trees, %d x %d ground cells -> %s",
		#boxes,
		#trees,
		climbs,
		#woods,
		nx,
		nz,
		out
	)
)
Height.configure(nil)
