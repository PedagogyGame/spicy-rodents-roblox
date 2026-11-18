--!strict
-- tools/review/alley_plan.luau: export the bowling alley's floor plan (Shared/Attractions/AlleyLayout: rooms,
-- openings, tables and their clear floor, staff posts and routes, the backstage) and what the bake really built
-- (build/Attractions.rbxm: every part of the alley as a box in the alley's own frame) to
-- build/review_alley/plan.json; tools/review/alley_plan.py draws the labelled plan from it.
-- Usage (repo root): lune run tools/bake/attractions.luau; lune run tools/review/alley_plan.luau [--out <json>]
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local L = require("../../src/shared/Attractions/AlleyLayout")
local Games = require("../../src/shared/Minigames/Games")
local Attractions = require("../../generated/Attractions") :: any
local Expansion = require("../../generated/Expansion") :: any

local out = "build/review_alley/plan.json"
for i, a in process.args do
	if a == "--out" then
		out = process.args[i + 1]
	end
end

local record: any = nil
for _, a in Attractions.attractions do
	if a.id == "bowling_alley" then
		record = a
	end
end
assert(record, "alley_plan: no bowling_alley in generated/Attractions")
local place: L.Place = record.place

local function r2(n: number): number
	return math.floor(n * 100 + 0.5) / 100
end

-- every part of the baked alley as { model, name, x0, x1, d0, d1, y0, y1, r, g, b, transparency, material }
local boxes = {}
local counts: { [string]: number } = {}
local total = 0
local function add(c: any, model: string)
	total += 1
	counts[model] = (counts[model] or 0) + 1
	local cf, s = c.CFrame, c.Size
	local rx, uy, lz = cf.RightVector, cf.UpVector, cf.LookVector
	local hx = math.abs(rx.X) * s.X / 2 + math.abs(uy.X) * s.Y / 2 + math.abs(lz.X) * s.Z / 2
	local hy = math.abs(rx.Y) * s.X / 2 + math.abs(uy.Y) * s.Y / 2 + math.abs(lz.Y) * s.Z / 2
	local hz = math.abs(rx.Z) * s.X / 2 + math.abs(uy.Z) * s.Y / 2 + math.abs(lz.Z) * s.Z / 2
	local pos = cf.Position
	local ax, ay, ad = L.toLocal(place, pos.X - hx, pos.Y - hy, pos.Z - hz)
	local bx, by, bd = L.toLocal(place, pos.X + hx, pos.Y + hy, pos.Z + hz)
	local col = c.Color
	table.insert(boxes, {
		model,
		c.Name,
		r2(math.min(ax, bx)),
		r2(math.max(ax, bx)),
		r2(math.min(ad, bd)),
		r2(math.max(ad, bd)),
		r2(math.min(ay, by)),
		r2(math.max(ay, by)),
		math.floor(col.R * 255 + 0.5),
		math.floor(col.G * 255 + 0.5),
		math.floor(col.B * 255 + 0.5),
		r2(c.Transparency),
		c.Material.Name,
		if c:IsA("Part") then c.Shape.Name else c.ClassName,
	})
end
local function walk(inst: any, model: string)
	for _, c in inst:GetChildren() do
		if c:IsA("BasePart") then
			add(c, model)
		end
		walk(c, model)
	end
end
local file = "build/Attractions.rbxm"
assert(fs.isFile(file), "alley_plan: build/Attractions.rbxm missing (lune run tools/bake/attractions.luau)")
for _, root in roblox.deserializeModel(fs.readFile(file)) do
	for _, site in root:GetChildren() do
		if site.Name == "BowlingAlley" then
			for _, model in site:GetChildren() do
				if model:IsA("BasePart") then
					add(model, model.Name)
				end
				walk(model, model.Name)
			end
		end
	end
end

local stations = {}
for _, st in Games.stations({ bowling_alley = place }) do
	if st.site == "bowling_alley" then
		table.insert(stations, { id = st.id, game = st.game, x = st.x, d = st.d })
	end
end

local lanes = {}
for i = 1, L.LANES do
	table.insert(lanes, { n = i, x = L.laneX(i), pair = L.pairOf(i) })
end
local pairs = {}
for p = 1, L.PAIRS do
	table.insert(pairs, { n = p, x = L.pairX(p) })
end
local routes = {}
for id in L.ROUTES do
	routes[id] = L.route(id)
end
local machinePosts = {}
for i = 1, L.LANES do
	table.insert(machinePosts, L.machinePost(i))
end

-- the nine ball-return tunnels (squirrel routes) in the alley's frame
local tunnels = {}
for _, rt in record.routes do
	local pts = {}
	for _, p in rt.points do
		local X, Y, D = L.toLocal(place, p[1], p[2], p[3])
		table.insert(pts, { r2(X), r2(D), r2(Y) })
	end
	table.insert(tunnels, { id = rt.id, name = rt.name, points = pts })
end

-- the planned neighbours (data only: generated/Expansion), in world studs, for the site inset
local SITE = { x0 = 1130, x1 = 1720, z0 = -740, z1 = -220 }
local function inSite(x: number, z: number): boolean
	return x > SITE.x0 and x < SITE.x1 and z > SITE.z0 and z < SITE.z1
end
local neighbours = {}
for _, v in Expansion.venues do
	local near = false
	for _, p in v.sitePoly do
		near = near or inSite(p[1], p[2])
	end
	if near then
		table.insert(neighbours, { id = v.id, name = v.name, site = v.sitePoly, foot = v.footPoly })
	end
end
local strips = {}
for _, st in Expansion.strips do
	if st.axis == "x" and st.coord > SITE.z0 and st.coord < SITE.z1 and st["end"] > SITE.x0 then
		table.insert(strips, { id = st.id, kind = st.kind, x0 = st.start, x1 = st["end"], z = st.coord, w = st.width })
	end
end
local pads = {}
for _, pad in Expansion.pads do
	if pad.rect and inSite(pad.rect.x0, pad.rect.z0) then
		table.insert(pads, { id = pad.id, rect = pad.rect })
	end
end
local paths = {}
for _, path in Expansion.paths do
	local last = path.points[#path.points]
	if inSite(last[1], last[2]) then
		table.insert(paths, { id = path.id, w = path.width, points = path.points })
	end
end

local doc = {
	place = place,
	footprint = record.footprint,
	reserve = record.reserve,
	K = {
		X0 = L.X0,
		X1 = L.X1,
		HALL_X1 = L.HALL_X1,
		FRONT_D = L.FRONT_D,
		CONCOURSE_D0 = L.CONCOURSE_D0,
		GAME_ROOM_X0 = L.GAME_ROOM_X0,
		GAME_ROOM_D0 = L.GAME_ROOM_D0,
		GAME_ROOM_D1 = L.GAME_ROOM_D1,
		REAR_WALL_D = L.REAR_WALL_D,
		WALL_T = L.WALL_T,
		PARTITION_T = L.PARTITION_T,
		APPROACH_D = L.APPROACH_D,
		FOUL_D = L.FOUL_D,
		HEAD_D = L.HEAD_D,
		MACHINE_D0 = L.MACHINE_D0,
		MACHINE_D1 = L.MACHINE_D1,
		ALLEY_D1 = L.ALLEY_D1,
		LANE_BLOCK_X0 = L.LANE_BLOCK_X0,
		LANE_BLOCK_X1 = L.LANE_BLOCK_X1,
		LANE_W = L.LANE_W,
		PITCH = L.PITCH,
		PINBALL_D = L.PINBALL_D,
	},
	lanes = lanes,
	pairs = pairs,
	zones = L.ZONES,
	openings = L.OPENINGS,
	frontWalls = L.FRONT_WALLS_X,
	entrance = L.ENTRANCE,
	landing = L.LANDING,
	ramp = L.RAMP,
	stoop = L.STOOP,
	cuts = L.SITE_CUTS,
	posts = L.POSTS,
	machinePosts = machinePosts,
	routes = routes,
	standing = L.standing(),
	fixtures = L.GAMES_FIXTURES,
	board = L.board(),
	pool = L.POOL_TABLES,
	bumper = L.BUMPER_POOL,
	pinballs = L.PINBALLS,
	fortune = L.FORTUNE,
	airHockey = L.AIR_HOCKEY,
	airHockeySize = L.AIR_HOCKEY_SIZE,
	backstage = L.BACKSTAGE,
	stations = stations,
	tunnels = tunnels,
	site = { bounds = SITE, neighbours = neighbours, strips = strips, pads = pads, paths = paths },
	boxes = boxes,
	counts = counts,
	total = total,
}
local dir = string.match(out, "^(.*)/[^/]*$")
if dir and not fs.isDir(dir) then
	fs.writeDir(dir)
end
fs.writeFile(out, serde.encode("json", doc))
print(string.format("alley_plan: %d parts -> %s", total, out))
