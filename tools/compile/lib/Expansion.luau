--!strict
-- tools/compile: data/expansion.json -> generated/Expansion.luau (batch 2 town expansion: brief v2 §3 neighbourhood
-- expansion, §13a places and attractions, §15 decision 18; docs/waves/BATCH2_SPEC.md). STUDS.
-- One record per venue (family F1 food_shops, F2 civic, F3 leisure, F4 rides_minigame_props) with its placement,
-- footprint, site, floor height, entrances and anchors in the venue's local [X, Y, D] frame (Shared/Attractions/
-- AlleyLayout.toWorld), plus the new streets, pads, paths, rides, zones and the 6 pickups + 4 SUVs.
-- The compiler checks the layout against the existing town and emits world-space copies the bakes and the server read:
--   * no venue site overlaps another site (unless `inside` it), a solid existing lot, an existing road strip, a new
--     street, sidewalk or pad, the bowling alley, a tree trunk (+2 st) or a harvested route point below its roof;
--   * new streets meet existing roads only where `joins` says so; pads and paths stay off buildings and trunks;
--   * floorY is 0.3..1.5 st above the highest ground under the footprint (lawns: the highest ground), ground {min,
--     max} matches World/Height (Backdrop's coast north of NORTH_FROM_Z);
--   * every entrance reaches the street network: "frontage" within 16 st of a road, sidewalk, pad or path; a path id
--     whose one end is at the door and the other on the network; "inside" opens into the venue's own site;
--   * anchors sit in the site (or on a pad or path); the sky-lift cable clears the ground; the parasail runs at sea;
--   * 6 pickups + 4 SUVs on their named spots; at least 18 food businesses (10 enterable), all 8 kinds; every
--     approval-map label of dec 18 is present.
-- Interface: ground(x, z); place(v); toWorld(v, X, Y, D); sitePoly(v); footPoly(v); streetStrips(s);
--   check(doc, world) -> { string } (problems); build(doc) -> value; compile(ctx) -> Module? (nil when absent)
local fs = require("@lune/fs")
local Json = require("./Json")
local Schema = require("./Schema")
local AlleyLayout = require("../../../src/shared/Attractions/AlleyLayout")
local Backdrop = require("../../../src/shared/World/Backdrop")
local Height = require("../../../src/shared/World/Height")

local Expansion = {}

export type Pt = { number }
export type Poly = { Pt }
export type Rect = { x0: number, z0: number, x1: number, z1: number }
export type World = {
	lots: { any },
	roads: { any },
	routes: { any },
	trees: { any },
	appleTrees: { any },
	attractions: { any },
}

-- Lots that are ground, not buildings: a venue may sit on them only where it says so (none does today).
Expansion.AREA_TYPES = table.freeze({
	park = true,
	lawn = true,
	plaza = true,
	district_ground = true,
	estate_parcel = true,
	cemetery = true,
	parking = true,
	path = true,
	intersection = true,
	ambient_npcs = true,
	street_furniture = true,
	overhead_lines = true,
	sewer = true,
	stream = false, -- water: solid for placement
} :: { [string]: boolean })
Expansion.FOOD_KINDS =
	table.freeze({ "diner", "pizza", "taco", "chinese", "cafe", "bakery", "ice_cream", "bar_and_grill" })
-- brief v2 §15 dec 18 (the approval map) and §3: every label must be on some venue
Expansion.APPROVAL = table.freeze({
	"steakhouse",
	"sky lift",
	"hilltop restaurant",
	"TV station (paintball)",
	"new mall (wind tunnel)",
	"lounge one (1940s)",
	"lounge two (sci-fi)",
	"corner store",
	"doctor's office",
	"museum",
	"racquetball court",
	"school with playground",
	"church",
	"6 new homes",
	"park with gazebo",
	"community garden",
	"marina rides",
})
Expansion.FRONTAGE = 16 -- studs from a door to the network for "frontage", "alley" and "forecourt"
Expansion.PATH_END = 3 -- studs from a path end to its door or to the network
Expansion.EPS = 0.05
Expansion.CABLE_CLEAR = 20 -- studs from the sky-lift cable down to the ground...
Expansion.CABLE_APRON = 30 -- ...farther than this from either station's building

local function r4(n: number): number
	return math.floor(n * 1e4 + 0.5) / 1e4
end

function Expansion.ground(x: number, z: number): number
	if z >= Backdrop.NORTH_FROM_Z then
		return Backdrop.groundAt(x, z)
	end
	return Height.at(x, z)
end

function Expansion.place(v: any): AlleyLayout.Place
	return { x = v.position.x, z = v.position.z, floorY = v.floorY, yaw = v.yaw }
end

function Expansion.toWorld(v: any, X: number, Y: number, D: number): (number, number, number)
	return AlleyLayout.toWorld(Expansion.place(v), X, Y, D)
end

local function localPoly(v: any, x0: number, x1: number, d0: number, d1: number): Poly
	local out = {}
	for _, c in { { x0, d0 }, { x1, d0 }, { x1, d1 }, { x0, d1 } } do
		local x, _, z = Expansion.toWorld(v, c[1], 0, c[2])
		table.insert(out, { x, z })
	end
	return out
end

function Expansion.sitePoly(v: any): Poly
	local s = v.site
	return localPoly(v, s.x0, s.x1, s.d0, s.d1)
end

function Expansion.footPoly(v: any, shrink: number?): Poly
	local k = shrink or 0
	local w, d = v.footprint.w / 2 - k, v.footprint.d / 2 - k
	return localPoly(v, -w, w, -d, d)
end

local function rectPoly(r: Rect): Poly
	return { { r.x0, r.z0 }, { r.x1, r.z0 }, { r.x1, r.z1 }, { r.x0, r.z1 } }
end

-- An oriented rectangle (lots with a yaw): centre, half extents along the rotated axes.
local function orientedPoly(x: number, z: number, hw: number, hd: number, yaw: number): Poly
	local c, s = math.cos(yaw), math.sin(yaw)
	local out = {}
	for _, k in { { -hw, -hd }, { hw, -hd }, { hw, hd }, { -hw, hd } } do
		local lx, lz = k[1], k[2]
		table.insert(out, { x + lx * c + lz * s, z - lx * s + lz * c })
	end
	return out
end

-- Convex polygon overlap by separating axes; touching (within eps) does not count.
local function overlaps(a: Poly, b: Poly, eps: number?): boolean
	local e = eps or Expansion.EPS
	for _, poly in { a, b } do
		for i = 1, #poly do
			local p, q = poly[i], poly[i % #poly + 1]
			local nx, nz = q[2] - p[2], p[1] - q[1]
			local len = math.sqrt(nx * nx + nz * nz)
			if len > 1e-9 then
				nx, nz = nx / len, nz / len
				local amin, amax, bmin, bmax = math.huge, -math.huge, math.huge, -math.huge
				for _, v in a do
					local t = v[1] * nx + v[2] * nz
					amin, amax = math.min(amin, t), math.max(amax, t)
				end
				for _, v in b do
					local t = v[1] * nx + v[2] * nz
					bmin, bmax = math.min(bmin, t), math.max(bmax, t)
				end
				if amax <= bmin + e or bmax <= amin + e then
					return false
				end
			end
		end
	end
	return true
end
Expansion.overlaps = overlaps

local function segDist(px: number, pz: number, ax: number, az: number, bx: number, bz: number): number
	local dx, dz = bx - ax, bz - az
	local l2 = dx * dx + dz * dz
	local t = if l2 > 0 then math.clamp(((px - ax) * dx + (pz - az) * dz) / l2, 0, 1) else 0
	local qx, qz = ax + dx * t - px, az + dz * t - pz
	return math.sqrt(qx * qx + qz * qz)
end

local function contains(poly: Poly, x: number, z: number): boolean
	local sign = 0
	for i = 1, #poly do
		local p, q = poly[i], poly[i % #poly + 1]
		local cr = (q[1] - p[1]) * (z - p[2]) - (q[2] - p[2]) * (x - p[1])
		if math.abs(cr) > 1e-9 then
			local s = if cr > 0 then 1 else -1
			if sign == 0 then
				sign = s
			elseif s ~= sign then
				return false
			end
		end
	end
	return true
end
Expansion.contains = contains

-- Distance from a point to a polygon (0 inside).
local function polyDist(poly: Poly, x: number, z: number): number
	if contains(poly, x, z) then
		return 0
	end
	local best = math.huge
	for i = 1, #poly do
		local p, q = poly[i], poly[i % #poly + 1]
		best = math.min(best, segDist(x, z, p[1], p[2], q[1], q[2]))
	end
	return best
end
Expansion.polyDist = polyDist

local function bounds(poly: Poly): Rect
	local r = { x0 = math.huge, z0 = math.huge, x1 = -math.huge, z1 = -math.huge }
	for _, p in poly do
		r.x0, r.z0 = math.min(r.x0, p[1]), math.min(r.z0, p[2])
		r.x1, r.z1 = math.max(r.x1, p[1]), math.max(r.z1, p[2])
	end
	return r
end

-- A straight road record (generated/Roads shape: axis x runs along x at z = coord) as a rectangle; nil for free roads.
local function roadRect(r: any): Rect?
	if r.axis == "x" then
		return {
			x0 = math.min(r.start, r["end"]),
			x1 = math.max(r.start, r["end"]),
			z0 = r.coord - r.width / 2,
			z1 = r.coord + r.width / 2,
		}
	elseif r.axis == "z" then
		return {
			x0 = r.coord - r.width / 2,
			x1 = r.coord + r.width / 2,
			z0 = math.min(r.start, r["end"]),
			z1 = math.max(r.start, r["end"]),
		}
	end
	return nil
end
Expansion.roadRect = roadRect

-- A new street as Road-shaped strips: the carriageway and its two sidewalks (Builders/Road can build them as is).
function Expansion.streetStrips(s: any): { any }
	local out = {
		{
			id = s.id,
			kind = s.kind,
			axis = s.axis,
			coord = s.coord,
			start = s.start,
			["end"] = s["end"],
			width = s.width,
			registered = true,
			src = "data/expansion.json " .. s.id,
		},
	}
	if s.sidewalk then
		for _, side in { -1, 1 } do
			table.insert(out, {
				id = s.id .. (if side < 0 then "_sidewalk_a" else "_sidewalk_b"),
				kind = "concrete",
				axis = s.axis,
				coord = s.coord + side * s.sidewalk.offset,
				start = s.start,
				["end"] = s["end"],
				width = s.sidewalk.width,
				registered = true,
				src = "data/expansion.json " .. s.id,
			})
		end
	end
	return out
end

local function lotPoly(lot: any): Poly?
	local fp = lot.footprint
	if fp == nil or fp.w == nil or fp.d == nil or fp.w <= 0 or fp.d <= 0 then
		return nil
	end
	local w, d = fp.w, fp.d
	if lot.facing == "+X" or lot.facing == "-X" then
		w, d = d, w
	end
	if lot.facing == nil and type(lot.yaw) == "number" then
		return orientedPoly(lot.x, lot.z, fp.w / 2, fp.d / 2, lot.yaw)
	end
	return rectPoly({ x0 = lot.x - w / 2, x1 = lot.x + w / 2, z0 = lot.z - d / 2, z1 = lot.z + d / 2 })
end
Expansion.lotPoly = lotPoly

-- The ground under a venue's footprint: the same 2-st lattice the planner sampled.
function Expansion.groundStats(v: any): (number, number)
	local lo, hi = math.huge, -math.huge
	local w, d = v.footprint.w / 2, v.footprint.d / 2
	local X = -w
	while X <= w + 1e-6 do
		local D = -d
		while D <= d + 1e-6 do
			local x, _, z = Expansion.toWorld(v, X, 0, D)
			local h = Expansion.ground(x, z)
			lo, hi = math.min(lo, h), math.max(hi, h)
			D += 2
		end
		X += 2
	end
	return lo, hi
end

-- An attraction's footprint, and the ground it keeps for something not built yet (the bowling alley's backstage).
-- A reserve's `givesWayOnArrival` names the venues whose sites may overlap it until that thing arrives (the owner's
-- default: the park and the steakhouse give up that ground only when the backstage package is here): `yields`.
local function attractionPolys(world: World): { { id: string, poly: Poly, yields: { [string]: boolean }? } }
	local out = {}
	for _, a in world.attractions do
		local p, fp = a.place, a.footprint
		local poly = {}
		for _, c in { { fp.x0, fp.d0 }, { fp.x1, fp.d0 }, { fp.x1, fp.d1 }, { fp.x0, fp.d1 } } do
			local x, _, z = AlleyLayout.toWorld(p, c[1], 0, c[2])
			table.insert(poly, { x, z })
		end
		table.insert(out, { id = a.id, poly = poly })
		-- ground an attraction keeps free for something that has not been built yet (the bowling alley's backstage)
		local rs = a.reserve
		if rs then
			local kept = {}
			for _, c in { { rs.x0, rs.d0 }, { rs.x1, rs.d0 }, { rs.x1, rs.d1 }, { rs.x0, rs.d1 } } do
				local x, _, z = AlleyLayout.toWorld(p, c[1], 0, c[2])
				table.insert(kept, { x, z })
			end
			local yields: { [string]: boolean } = {}
			for _, vid in rs.givesWayOnArrival or {} do
				yields[vid] = true
			end
			table.insert(
				out,
				{ id = a.id .. " (ground reserved for " .. rs["for"] .. ")", poly = kept, yields = yields }
			)
		end
	end
	return out
end

-- Every problem with the layout, as readable strings (empty when the layout is sound).
function Expansion.check(doc: any, world: World): { string }
	local problems: { string } = {}
	local function bad(msg: string)
		table.insert(problems, msg)
	end

	-- ids
	local seen: { [string]: boolean } = {}
	for _, list in { doc.streets, doc.pads, doc.paths, doc.venues, doc.rides, doc.zones, doc.vehicles } do
		for _, r in list do
			if seen[r.id] then
				bad("duplicate id " .. r.id)
			end
			seen[r.id] = true
		end
	end

	-- the existing town
	local lotById: { [string]: any } = {}
	local hardLots: { { id: string, poly: Poly } } = {}
	local gasStations = 0
	for _, lot in world.lots do
		lotById[lot.id] = lot
		if lot.type == "gas_station" then
			gasStations += 1
		end
		if not Expansion.AREA_TYPES[lot.type] then
			local poly = lotPoly(lot)
			if poly then
				table.insert(hardLots, { id = lot.id, poly = poly })
			end
		end
	end
	local roads: { { id: string, poly: Poly, rect: Rect } } = {}
	for _, r in world.roads do
		local rect = roadRect(r)
		if rect then
			table.insert(roads, { id = r.id, poly = rectPoly(rect), rect = rect })
		end
	end
	local trunks: { { x: number, z: number, r: number, id: string } } = {}
	for i, t in world.trees do
		table.insert(trunks, { x = t.x, z = t.z, r = t.trunkBaseRadius or 3, id = "tree " .. (t.name or tostring(i)) })
	end
	for _, t in world.appleTrees do
		table.insert(trunks, { x = t.x, z = t.z, r = 1.5, id = "apple tree " .. tostring(t.name) })
	end
	local alleys = attractionPolys(world)

	-- the new network
	local streetStrips: { { id: string, street: string, poly: Poly } } = {}
	for _, s in doc.streets do
		for _, strip in Expansion.streetStrips(s) do
			table.insert(streetStrips, { id = strip.id, street = s.id, poly = rectPoly(roadRect(strip) :: Rect) })
		end
	end
	local pads: { [string]: Poly } = {}
	for _, p in doc.pads do
		local r = p.rect
		if r.x0 >= r.x1 or r.z0 >= r.z1 then
			bad("pad rect is empty: " .. p.id)
		end
		pads[p.id] = rectPoly(r)
	end
	local paths: { [string]: any } = {}
	for _, p in doc.paths do
		paths[p.id] = p
	end
	local function onNetwork(x: number, z: number, reach: number, skipPath: string?, padsOnly: boolean?): boolean
		for _, poly in pads do
			if polyDist(poly, x, z) <= reach then
				return true
			end
		end
		if padsOnly then
			return false
		end
		for _, r in roads do
			if polyDist(r.poly, x, z) <= reach then
				return true
			end
		end
		for _, s in streetStrips do
			if polyDist(s.poly, x, z) <= reach then
				return true
			end
		end
		for id, p in paths do
			if id ~= skipPath then
				local pts = p.points
				for i = 1, #pts - 1 do
					if segDist(x, z, pts[i][1], pts[i][2], pts[i + 1][1], pts[i + 1][2]) <= reach + p.width / 2 then
						return true
					end
				end
			end
		end
		return false
	end

	-- venues
	local venueById: { [string]: any } = {}
	local siteOf: { [string]: Poly } = {}
	local footOf: { [string]: Poly } = {}
	for _, v in doc.venues do
		venueById[v.id] = v
		siteOf[v.id] = Expansion.sitePoly(v)
		footOf[v.id] = Expansion.footPoly(v)
	end
	local facingYaw = { ["+Z"] = 0, ["-Z"] = math.pi, ["+X"] = math.pi / 2, ["-X"] = -math.pi / 2 }
	for _, v in doc.venues do
		local id = v.id
		if
			v.facing ~= "yaw"
			and math.abs((v.yaw - (facingYaw :: any)[v.facing] + math.pi) % (2 * math.pi) - math.pi) > 1e-4
		then
			bad(`{id}: yaw {v.yaw} does not match facing {v.facing}`)
		end
		local s, w2, d2 = v.site, v.footprint.w / 2, v.footprint.d / 2
		if s.x0 > -w2 + 1e-6 or s.x1 < w2 - 1e-6 or s.d0 > -d2 + 1e-6 or s.d1 < d2 - 1e-6 then
			bad(id .. ": the site does not contain the footprint")
		end
		if v.status == "upgrade" then
			if lotById[v.existingLot] == nil then
				bad(id .. ": existingLot " .. tostring(v.existingLot) .. " is not a lot")
			end
			continue
		end
		-- ground and floor
		local lo, hi = Expansion.groundStats(v)
		if math.abs(lo - v.ground.min) > 0.05 or math.abs(hi - v.ground.max) > 0.05 then
			bad(string.format("%s: ground %.2f..%.2f, data says %.2f..%.2f", id, lo, hi, v.ground.min, v.ground.max))
		end
		if v.type == "park" or v.type == "community_garden" then
			if math.abs(v.floorY - hi) > 0.05 then
				bad(string.format("%s: a lawn's floorY is the highest ground %.2f (data %.2f)", id, hi, v.floorY))
			end
		elseif v.floorY < hi + 0.3 or v.floorY > hi + 1.5 then
			bad(string.format("%s: floorY %.2f must be 0.3..1.5 above the highest ground %.2f", id, v.floorY, hi))
		end
		if #v.features == 0 then
			bad(id .. ": no features")
		end
		local site = siteOf[id]
		local sb = bounds(site)
		-- other venues
		for _, o in doc.venues do
			if o.id < id and o.status ~= "upgrade" and v.inside ~= o.id and o.inside ~= id then
				if overlaps(site, siteOf[o.id]) then
					bad(id .. " overlaps venue " .. o.id)
				end
			end
		end
		for _, l in hardLots do
			if overlaps(site, l.poly) then
				bad(id .. " overlaps lot " .. l.id)
			end
		end
		for _, r in roads do
			if overlaps(site, r.poly) then
				bad(id .. " overlaps road " .. r.id)
			end
		end
		for _, st in streetStrips do
			if overlaps(site, st.poly) then
				bad(id .. " overlaps street " .. st.id)
			end
		end
		for pid, poly in pads do
			if overlaps(site, poly) then
				bad(id .. " overlaps pad " .. pid)
			end
		end
		for _, a in alleys do
			if overlaps(site, a.poly) and not (a.yields and a.yields[id]) then
				bad(id .. " overlaps the attraction " .. a.id)
			end
		end
		for _, t in trunks do
			if polyDist(site, t.x, t.z) < t.r + 2 then
				bad(string.format("%s is within 2 st of the trunk of %s (%.0f, %.0f)", id, t.id, t.x, t.z))
			end
		end
		local roof = v.floorY + v.height + 3
		for _, route in world.routes do
			for _, p in route.points do
				local x, y, z = p[1], p[2], p[3]
				if x >= sb.x0 and x <= sb.x1 and z >= sb.z0 and z <= sb.z1 and y < roof and contains(site, x, z) then
					bad(
						string.format(
							"%s covers route %s (%s) at (%.0f, %.0f, %.0f)",
							id,
							tostring(route.id),
							route.kind,
							x,
							y,
							z
						)
					)
					break
				end
			end
		end
		-- entrances
		for _, e in v.entrances do
			local x, _, z = Expansion.toWorld(v, e.at[1], 0, e.at[2])
			local tag = id .. "/" .. e.id
			if e.path == "inside" then
				if polyDist(site, x, z) > 0.5 then
					bad(tag .. ": an inside door must open into the venue's site")
				end
			elseif e.path == "frontage" then
				if not onNetwork(x, z, Expansion.FRONTAGE) then
					bad(tag .. ": no road, sidewalk, pad or path within 16 st")
				end
			elseif e.path == "alley" or e.path == "forecourt" then
				if not onNetwork(x, z, Expansion.FRONTAGE, nil, true) then
					bad(tag .. ": no " .. e.path .. " pad within 16 st")
				end
			else
				local p = paths[e.path]
				if p == nil then
					bad(tag .. ": unknown path " .. e.path)
				else
					local a, b = p.points[1], p.points[#p.points]
					local da = math.sqrt((a[1] - x) ^ 2 + (a[2] - z) ^ 2)
					local db = math.sqrt((b[1] - x) ^ 2 + (b[2] - z) ^ 2)
					local far = if da <= db then b else a
					if math.min(da, db) > Expansion.PATH_END then
						bad(tag .. ": path " .. p.id .. " does not start at the door")
					elseif not onNetwork(far[1], far[2], Expansion.PATH_END, p.id) then
						bad(tag .. ": path " .. p.id .. " does not reach a road, sidewalk, pad or path")
					end
				end
			end
		end
		-- anchors
		for _, a in v.anchors do
			local X, D = a.at[1], a.at[3]
			local inSite = X >= s.x0 - 1 and X <= s.x1 + 1 and D >= s.d0 - 1 and D <= s.d1 + 1
			if not inSite then
				local x, _, z = Expansion.toWorld(v, X, 0, D)
				if not onNetwork(x, z, 1) then
					bad(id .. "/" .. a.id .. ": anchor outside the site and off every pad and path")
				end
			end
		end
	end

	-- streets
	for _, s in doc.streets do
		local joins: { [string]: boolean } = {}
		for _, j in s.joins do
			joins[j] = true
		end
		for _, strip in Expansion.streetStrips(s) do
			local poly = rectPoly(roadRect(strip) :: Rect)
			for _, r in roads do
				if not joins[r.id] and overlaps(poly, r.poly) then
					bad(strip.id .. " crosses road " .. r.id .. " (not in joins)")
				end
			end
			for _, l in hardLots do
				if overlaps(poly, l.poly) then
					bad(strip.id .. " overlaps lot " .. l.id)
				end
			end
			for _, t in trunks do
				if polyDist(poly, t.x, t.z) < t.r + 1 then
					bad(string.format("%s runs into the trunk of %s", strip.id, t.id))
				end
			end
			for _, a in alleys do
				if overlaps(poly, a.poly) then
					bad(strip.id .. " overlaps the attraction " .. a.id)
				end
			end
		end
	end

	-- pads
	for _, p in doc.pads do
		local poly = pads[p.id]
		local keeps: { [string]: boolean } = {}
		for _, k in p.keeps or {} do
			keeps[k] = true
		end
		for _, r in roads do
			if overlaps(poly, r.poly) then
				bad(p.id .. " overlaps road " .. r.id)
			end
		end
		for _, l in hardLots do
			if overlaps(poly, l.poly) and not (keeps[l.id] and lotById[l.id].type == "detail") then
				bad(p.id .. " overlaps lot " .. l.id)
			end
		end
		for vid, foot in footOf do
			if venueById[vid].status ~= "upgrade" and overlaps(poly, foot) then
				bad(p.id .. " overlaps the building of " .. vid)
			end
		end
		for _, t in trunks do
			if polyDist(poly, t.x, t.z) < t.r then
				bad(p.id .. " paves over the trunk of " .. t.id)
			end
		end
		for _, a in alleys do
			if overlaps(poly, a.poly) then
				bad(p.id .. " overlaps the attraction " .. a.id)
			end
		end
	end

	-- paths: off every building (1 st inside the walls) and every trunk
	local inner: { [string]: Poly } = {}
	for vid, v in venueById do
		if v.status ~= "upgrade" then
			inner[vid] = Expansion.footPoly(v, 1)
		end
	end
	for _, p in doc.paths do
		local pts = p.points
		for i = 1, #pts - 1 do
			local ax, az, bx, bz = pts[i][1], pts[i][2], pts[i + 1][1], pts[i + 1][2]
			local n = math.max(1, math.ceil(math.sqrt((bx - ax) ^ 2 + (bz - az) ^ 2) / 2))
			local hit: string? = nil
			for k = 0, n do
				local x, z = ax + (bx - ax) * k / n, az + (bz - az) * k / n
				for vid, poly in inner do
					if contains(poly, x, z) then
						hit = "the building of " .. vid
					end
				end
				for _, t in trunks do
					if math.sqrt((x - t.x) ^ 2 + (z - t.z) ^ 2) < t.r then
						hit = "the trunk of " .. t.id
					end
				end
				if hit then
					break
				end
			end
			if hit then
				bad(p.id .. " runs through " .. hit)
				break
			end
		end
	end

	-- vehicles
	local counts = { pickup = 0, suv = 0 }
	for _, veh in doc.vehicles do
		counts[veh.kind] += 1
		local at = veh.at
		local ok = false
		local slash = string.find(at, "/", 1, true)
		if slash then
			local vid = string.sub(at, 1, slash - 1)
			ok = siteOf[vid] ~= nil and contains(siteOf[vid], veh.x, veh.z)
		elseif pads[at] then
			ok = contains(pads[at], veh.x, veh.z)
		else
			for _, r in roads do
				if r.id == at and contains(r.poly, veh.x, veh.z) then
					ok = true
				end
			end
		end
		if not ok then
			bad(veh.id .. ": not on its spot " .. at)
		end
		for vid, poly in footOf do
			if venueById[vid].status ~= "upgrade" and polyDist(poly, veh.x, veh.z) < 3 then
				bad(veh.id .. ": parked against the building of " .. vid)
			end
		end
		for _, st in streetStrips do
			if contains(st.poly, veh.x, veh.z) then
				bad(veh.id .. ": parked on the new street " .. st.id)
			end
		end
	end
	if counts.pickup ~= 6 or counts.suv ~= 4 then
		bad(string.format("vehicles: %d pickups and %d SUVs (brief v2 §15: 6 and 4)", counts.pickup, counts.suv))
	end

	-- rides
	local function anchorWorld(ref: string): (number?, number?, number?)
		local slash = string.find(ref, "/", 1, true)
		if not slash then
			return nil, nil, nil
		end
		local v = venueById[string.sub(ref, 1, slash - 1)]
		local aid = string.sub(ref, slash + 1)
		if v == nil then
			return nil, nil, nil
		end
		for _, a in v.anchors do
			if a.id == aid then
				return Expansion.toWorld(v, a.at[1], a.at[2], a.at[3])
			end
		end
		return nil, nil, nil
	end
	for _, ride in doc.rides do
		for _, ref in { ride.from, ride.to } do
			if anchorWorld(ref) == nil then
				bad(ride.id .. ": unknown anchor " .. ref)
			end
		end
		local pts = ride.points
		if ride.kind == "cable" then
			if #pts < 2 then
				bad(ride.id .. ": a cable needs two points")
				continue
			end
			local first, last = pts[1], pts[#pts]
			for _, pair in { { ride.from, first, "cable_out" }, { ride.to, last, "cable_in" } } do
				local ref = pair[1] :: string
				local vid = string.sub(ref, 1, (string.find(ref, "/", 1, true) :: number) - 1)
				local cx, _, cz = anchorWorld(vid .. "/" .. (pair[3] :: string))
				local p = pair[2] :: { number }
				if cx == nil or math.sqrt((p[1] - (cx :: number)) ^ 2 + (p[3] - (cz :: number)) ^ 2) > 1 then
					bad(ride.id .. ": the cable does not end at " .. vid .. "/" .. (pair[3] :: string))
				end
			end
			-- the cable clears the ground by CABLE_CLEAR outside CABLE_APRON of either station's building (a cabin
			-- hangs 10.5 below it, so its floor stays ~9 st up); inside the apron it may come down to the platforms
			local stationFeet = {}
			for _, ref in { ride.from, ride.to } do
				local v = venueById[string.sub(ref, 1, (string.find(ref, "/", 1, true) or 1) - 1)]
				if v ~= nil then
					table.insert(stationFeet, Expansion.footPoly(v))
				end
			end
			for i = 1, #pts - 1 do
				local a, b = pts[i], pts[i + 1]
				local len = math.sqrt((b[1] - a[1]) ^ 2 + (b[3] - a[3]) ^ 2)
				local n = math.max(1, math.ceil(len / 5))
				for k = 0, n do
					local t = k / n
					local x, y, z = a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t
					local apron = false
					for _, poly in stationFeet do
						apron = apron or polyDist(poly, x, z) <= Expansion.CABLE_APRON
					end
					if not apron and y < Expansion.ground(x, z) + Expansion.CABLE_CLEAR then
						bad(
							string.format(
								"%s: the cable is %.1f st above the ground at (%.0f, %.0f)",
								ride.id,
								y - Expansion.ground(x, z),
								x,
								z
							)
						)
						break
					end
				end
			end
		elseif ride.kind == "towed_spline" then
			for i = 2, #pts - 1 do
				local p = pts[i]
				if p[3] < Backdrop.shoreZ(p[1]) + 10 then
					bad(string.format("%s: point %d (%.0f, %.0f) is not at sea", ride.id, i, p[1], p[3]))
				end
			end
		end
	end
	for _, zn in doc.zones do
		local r = zn.rect
		if r.x0 >= r.x1 or r.z0 >= r.z1 then
			bad(zn.id .. ": empty rect")
		end
		if zn.kind == "jetski_water" then
			for x = r.x0, r.x1, 20 do
				if r.z0 < Backdrop.shoreZ(x) + 5 then
					bad(string.format("%s: the water zone reaches the beach at x %.0f", zn.id, x))
					break
				end
			end
		end
	end

	-- food census (invariant 4): 18 businesses, 10 enterable, all 8 kinds
	local kinds: { [string]: boolean } = {}
	local total, enterable = 0, 0
	for _, b in doc.foodBaseline do
		if lotById[b.lot] == nil then
			bad("foodBaseline: " .. b.lot .. " is not a lot")
		end
		kinds[b.food] = true
		total += 1
		if b.enterable then
			enterable += 1
		end
	end
	for _, v in doc.venues do
		if v.food and v.status == "new" then
			kinds[v.food] = true
			total += 1
			enterable += 1
		end
	end
	if total < 18 or enterable < 10 then
		bad(string.format("food: %d businesses, %d enterable (need 18 and 10)", total, enterable))
	end
	for _, k in Expansion.FOOD_KINDS do
		if not kinds[k] then
			bad("food: no " .. k)
		end
	end
	-- approval map labels and the brief's named lot types
	local labels: { [string]: number } = {}
	local types: { [string]: boolean } = {}
	for _, v in doc.venues do
		if v.approval then
			labels[v.approval] = (labels[v.approval] or 0) + 1
		end
		types[v.type] = true
	end
	for _, l in Expansion.APPROVAL do
		if labels[l] == nil then
			bad("approval map: nothing labelled " .. l)
		end
	end
	if labels["6 new homes"] ~= 6 then
		bad(string.format("approval map: %d new homes (need 6)", labels["6 new homes"] or 0))
	end
	for _, t in
		{
			"shop_barber",
			"shop_music",
			"shop_hardware",
			"shop_laundromat",
			"shop_bookshop",
			"shop_pet",
			"shop_antique",
			"shop_corner",
			"school",
			"church",
			"gazebo",
			"community_garden",
			"museum",
			"clinic",
		}
	do
		if not types[t] then
			bad("brief v2 §3/§13a: no venue of type " .. t)
		end
	end
	if gasStations < 2 then
		bad("brief v2 §3: the two v5.4 gas stations are gone")
	end
	return problems
end

-- World-space copies for the bakes and the server (entrance and anchor points, polygons, street strips).
function Expansion.build(doc: any): any
	local venues = {}
	local byFamily: { [string]: { venues: number, partBudget: number } } = {}
	for _, v in doc.venues do
		local out = table.clone(v)
		out.place = Expansion.place(v)
		local function polyOut(poly: Poly): { { number } }
			local t = {}
			for _, p in poly do
				table.insert(t, { r4(p[1]), r4(p[2]) })
			end
			return t
		end
		out.sitePoly = polyOut(Expansion.sitePoly(v))
		out.footPoly = polyOut(Expansion.footPoly(v))
		local ents = {}
		for _, e in v.entrances do
			local c = table.clone(e)
			local x, y, z = Expansion.toWorld(v, e.at[1], 0, e.at[2])
			c.world = { r4(x), r4(y), r4(z) }
			table.insert(ents, c)
		end
		out.entrances = ents
		local ancs = {}
		for _, a in v.anchors do
			local c = table.clone(a)
			local x, y, z = Expansion.toWorld(v, a.at[1], a.at[2], a.at[3])
			c.world = { r4(x), r4(y), r4(z) }
			table.insert(ancs, c)
		end
		out.anchors = ancs
		table.insert(venues, out)
		local f = byFamily[v.family] or { venues = 0, partBudget = 0 }
		f.venues += 1
		f.partBudget += v.partBudget
		byFamily[v.family] = f
	end
	local strips = {}
	for _, s in doc.streets do
		for _, strip in Expansion.streetStrips(s) do
			table.insert(strips, strip)
		end
	end
	local totalBudget = 0
	for _, f in byFamily do
		totalBudget += f.partBudget
	end
	return {
		frame = doc.frame,
		families = doc.families,
		foodBaseline = doc.foodBaseline,
		streets = doc.streets,
		strips = strips,
		pads = doc.pads,
		paths = doc.paths,
		venues = venues,
		rides = doc.rides,
		zones = doc.zones,
		vehicles = doc.vehicles,
		parkingMoves = doc.parkingMoves,
		summary = { byFamily = byFamily, partBudget = totalBudget, venues = #venues },
	}
end

function Expansion.compile(ctx: any): any?
	local rel = "data/expansion.json"
	local path = ctx.repo .. "/" .. rel
	if not fs.isFile(path) then
		return nil
	end
	local doc = Json.decodeFile(path)
	local schema = Json.decodeFile(ctx.repo .. "/tools/compile/schema/expansion.schema.json")
	local errs = Schema.validate(schema, doc)
	if #errs > 0 then
		ctx.schemaError(rel, errs)
		return nil
	end
	doc["$schema"] = nil
	local attractions = {}
	local apath = ctx.repo .. "/data/attractions.json"
	if fs.isFile(apath) then
		attractions = Json.decodeFile(apath).attractions
	end
	Height.configure(ctx.terrainExtensions)
	Backdrop.reset()
	local problems = Expansion.check(doc, {
		lots = ctx.lots,
		roads = ctx.roads,
		routes = ctx.routes,
		trees = ctx.trees,
		appleTrees = ctx.appleTrees,
		attractions = attractions,
	})
	for _, p in problems do
		ctx.invariant("expansion: " .. p, false)
	end
	ctx.invariant("expansion layout sound", #problems == 0, `{#problems} problem(s)`)
	local value = Expansion.build(doc)
	Height.configure(nil)
	Backdrop.reset()
	ctx.compare("expansion venues (data/expansion.json)", #doc.venues, #value.venues)
	return {
		name = "Expansion",
		value = value,
		records = #value.venues,
		map = true,
		source = rel,
		header = {
			"STUDS. Batch 2 town expansion (docs/waves/BATCH2_SPEC.md). venues[i].place is the AlleyLayout frame;",
			"entrances/anchors carry `world` points; strips are Road-shaped records for the new streets and sidewalks.",
		},
	}
end

return Expansion
