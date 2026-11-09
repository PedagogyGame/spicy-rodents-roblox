--!strict
-- ReplicatedStorage.Shared.Map.MapModel
-- World-to-map projection, map layers from lot and road data, labels and marker kinds (BUILD_PLAN §1.4,
-- §3.10, W1 #11). Pure: the client minimap (Client/Map/Minimap) and the Lune map render
-- (tools/placeholders -> assets/placeholders/town_map.svg) draw the same layers.
-- Interface: fromData({lots, roads, lotTypes?, extensions?, bounds?}) -> Map; project(map, x, z) -> u, v;
--            unproject(map, u, v) -> x, z; labels(map); layers(map); view(map, cx, cz, radius) -> window;
--            svg(map, {width}) -> string; MARKERS.
--
-- North is +Z and is UP on the map. A player facing +Z has +X on the LEFT (Roblox: LookVector x Up = -X),
-- so the map mirrors x (u grows toward -X) and reads like the street the player is looking at.
-- Lots are drawn as their footprint rectangles (w along the lot's local x; lots facing +X or -X are
-- rotated a quarter turn, worldgen_core §2), coloured by lot-type category; roads as their strips;
-- the river band from World/Height.RIVER; extension districts (offroad) as hatched areas.

local Height = require("../World/Height")

export type Rect = { x0: number, z0: number, x1: number, z1: number, kind: string, id: string? }
export type Label = { text: string, x: number, z: number, kind: string }
export type Map = {
	bounds: { minX: number, maxX: number, minZ: number, maxZ: number },
	lots: { Rect },
	roads: { Rect },
	water: { Rect },
	areas: { Rect },
	labels: { Label },
}

local MapModel = {}

-- §3.10 marker kinds (data/map/markers.json lands with SightingService in W2; these are the defaults).
-- stylua: ignore
MapModel.MARKERS = table.freeze({
	you = { color = "#ffffff", ttl = 0 },
	rodent_sighting = { color = "#c53227", ttl = 60 },
	squirrel = { color = "#b78453", ttl = 30 },
	police = { color = "#274a79", ttl = 0 },
	hospital = { color = "#e9eee7", ttl = 0 },
	quest = { color = "#e9a62d", ttl = 0 },
	vehicle = { color = "#9aa3a8", ttl = 0 },
})

-- stylua: ignore
MapModel.COLORS = table.freeze({
	ground = "#6f8a5a", road = "#3c3f42", water = "#4a7c95", area = "#8a7a5a",
	building = "#b9a58a", structure = "#9a8f80", plate = "#7f9a6b", slab = "#a7a29a", prop = "#6e7f5e",
	marker = "#c9b27a", lot = "#a89a84",
})

local function prettify(id: string): string
	local words = {}
	for w in string.gmatch(id, "[^_]+") do
		table.insert(words, string.upper(string.sub(w, 1, 1)) .. string.sub(w, 2))
	end
	return table.concat(words, " ")
end

function MapModel.fromData(d: { lots: { any }, roads: { any }, lotTypes: any?, extensions: any?, bounds: any? }): Map
	local types = if d.lotTypes then (d.lotTypes.types or d.lotTypes) else {}
	local lots: { Rect } = {}
	local sums: { [string]: { n: number, x: number, z: number } } = {}
	for _, l in d.lots do
		local fp = l.footprint
		if fp and l.x and l.z then
			local w, dd = fp.w, fp.d
			if l.facing == "+X" or l.facing == "-X" then
				w, dd = dd, w
			end
			local t = types[l.type]
			table.insert(lots, {
				x0 = l.x - w / 2,
				z0 = l.z - dd / 2,
				x1 = l.x + w / 2,
				z1 = l.z + dd / 2,
				kind = if t and t.category then t.category else "lot",
				id = l.id,
			})
		end
		if l.district and l.x then
			local s = sums[l.district] or { n = 0, x = 0, z = 0 }
			s.n += 1
			s.x += l.x
			s.z += l.z
			sums[l.district] = s
		end
	end
	local roads: { Rect } = {}
	for _, r in d.roads do
		local hw = r.width / 2
		if type(r.coord) ~= "number" then
			continue -- "free" paths (estate stepping stones) are yard detail, not map roads
		end
		local rect: Rect
		if r.axis == "x" then
			rect = { x0 = r.start, z0 = r.coord - hw, x1 = r["end"], z1 = r.coord + hw, kind = "road", id = r.id }
		else
			rect = { x0 = r.coord - hw, z0 = r.start, x1 = r.coord + hw, z1 = r["end"], kind = "road", id = r.id }
		end
		table.insert(roads, rect)
	end
	local st = Height.STUDS_PER_UNIT
	local river = Height.RIVER
	local water: { Rect } = {
		{
			x0 = (river.centerX - river.halfWidth) * st,
			z0 = river.zMin * st,
			x1 = (river.centerX + river.halfWidth) * st,
			z1 = river.zMax * st,
			kind = "water",
			id = "river",
		},
	}
	local areas: { Rect } = {}
	local labels: { Label } = {}
	for _, dist in (d.extensions and d.extensions.districts) or {} do
		table.insert(
			areas,
			{ x0 = dist.minX, z0 = dist.minZ, x1 = dist.maxX, z1 = dist.maxZ, kind = "area", id = dist.id }
		)
		table.insert(labels, {
			text = dist.label or prettify(dist.id),
			x = (dist.minX + dist.maxX) / 2,
			z = (dist.minZ + dist.maxZ) / 2,
			kind = "district",
		})
	end
	local names = {}
	for name in sums do
		table.insert(names, name)
	end
	table.sort(names)
	for _, name in names do
		local s = sums[name]
		table.insert(labels, { text = string.upper(prettify(name)), x = s.x / s.n, z = s.z / s.n, kind = "district" })
	end
	local b = d.bounds
	if not b then
		-- the world clamp grown to every lot and road (lots outside the v5.4 rectangle: estates, extensions)
		local c = Height.worldClamp()
		local minX, maxX, minZ, maxZ = c.minX, c.maxX, c.minZ, c.maxZ
		for _, list in { lots, roads, areas } do
			for _, r in list do
				minX, maxX = math.min(minX, r.x0, r.x1), math.max(maxX, r.x0, r.x1)
				minZ, maxZ = math.min(minZ, r.z0, r.z1), math.max(maxZ, r.z0, r.z1)
			end
		end
		b = { minX = minX, maxX = maxX, minZ = minZ, maxZ = maxZ }
	end
	return {
		bounds = { minX = b.minX, maxX = b.maxX, minZ = b.minZ, maxZ = b.maxZ },
		lots = lots,
		roads = roads,
		water = water,
		areas = areas,
		labels = labels,
	}
end

-- project(map, x, z) -> u, v in 0..1 (u to the right on screen, v down); +Z is up, +X is left.
function MapModel.project(map: Map, x: number, z: number): (number, number)
	local b = map.bounds
	return (b.maxX - x) / (b.maxX - b.minX), (b.maxZ - z) / (b.maxZ - b.minZ)
end

function MapModel.unproject(map: Map, u: number, v: number): (number, number)
	local b = map.bounds
	return b.maxX - u * (b.maxX - b.minX), b.maxZ - v * (b.maxZ - b.minZ)
end

function MapModel.labels(map: Map): { Label }
	return map.labels
end

-- Every rectangle in draw order (areas, water, roads, lots).
function MapModel.layers(map: Map): { Rect }
	local out = {}
	for _, list in { map.areas, map.water, map.roads, map.lots } do
		for _, r in list do
			table.insert(out, r)
		end
	end
	return out
end

-- view(map, cx, cz, radius): the minimap window around a player as a sub-rectangle in map space
-- (u0, v0, u1, v1), clamped to the map.
function MapModel.view(
	map: Map,
	cx: number,
	cz: number,
	radius: number
): { u0: number, v0: number, u1: number, v1: number }
	local u0, v0 = MapModel.project(map, cx + radius, cz + radius)
	local u1, v1 = MapModel.project(map, cx - radius, cz - radius)
	return { u0 = math.max(0, u0), v0 = math.max(0, v0), u1 = math.min(1, u1), v1 = math.min(1, v1) }
end

local function fmt(n: number): string
	return string.format("%.1f", n)
end

-- svg(map, {width}) -> an SVG document of the whole map (the "rendered map image", W1 #11).
function MapModel.svg(map: Map, opts: { width: number? }?): string
	local b = map.bounds
	local width = (opts and opts.width) or 1024
	local height = math.floor(width * (b.maxZ - b.minZ) / (b.maxX - b.minX) + 0.5)
	local out = {
		`<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">`,
		`<rect width="{width}" height="{height}" fill="{MapModel.COLORS.ground}"/>`,
	}
	local function rect(r: Rect)
		local ua, va = MapModel.project(map, r.x0, r.z0)
		local ub, vb = MapModel.project(map, r.x1, r.z1)
		local x, y = math.min(ua, ub) * width, math.min(va, vb) * height
		local w, h = math.abs(ub - ua) * width, math.abs(vb - va) * height
		local color = (MapModel.COLORS :: any)[r.kind] or MapModel.COLORS.road
		local extra = if r.kind == "area" then ` fill-opacity="0.35"` else ""
		table.insert(
			out,
			`<rect x="{fmt(x)}" y="{fmt(y)}" width="{fmt(math.max(w, 0.5))}" height="{fmt(math.max(h, 0.5))}" fill="{color}"{extra}/>`
		)
	end
	for _, r in MapModel.layers(map) do
		rect(r)
	end
	for _, l in map.labels do
		local u, v = MapModel.project(map, l.x, l.z)
		table.insert(
			out,
			`<text x="{fmt(u * width)}" y="{fmt(v * height)}" font-family="sans-serif" font-size="11" fill="#f4efe4" text-anchor="middle">{l.text}</text>`
		)
	end
	table.insert(out, "</svg>")
	return table.concat(out, "\n") .. "\n"
end

return MapModel
