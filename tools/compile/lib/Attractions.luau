--!strict
-- tools/compile: data/attractions.json -> generated/Attractions.luau (brief v2 §13a; BUILD_PLAN §3.17, W3c #15).
-- Attraction buildings that are baked on their own (tools/bake/attractions.luau -> build/Attractions.rbxm ->
-- Workspace.Attractions). The file is authored in STUDS. Each building's routes (the bowling alley's
-- ball-return vents and tunnels) are turned from the building's local frame into world route records the
-- Routes Registry reads (Shared/Data appends them after the harvested chunks): world points, the curve's arc
-- length, the sample count (max(20, ceil(3L)) + 1 on the length in HTML units, as for a harvested route),
-- origin "attraction" and explicit flags. A route of kind "tunnel" carries its `enclosure` record (Shared/Routes/
-- Enclosure: the enclosed-run contract); the compiler turns each mouth's `out` from the local frame into a world unit
-- vector and checks the record (Enclosure.validate) and the set (Enclosure.validateSet: links name real routes,
-- end links stay inside their enclosure, every enclosure has a way in). Invariants: ids unique and clear of the
-- harvest, at least two points, every point inside the footprint, every enclosure valid.
-- Interface: compile(ctx) -> Module? (nil when the file is absent)
local fs = require("@lune/fs")
local Json = require("./Json")
local Schema = require("./Schema")
local AlleyLayout = require("../../../src/shared/Attractions/AlleyLayout")
local Curve = require("../../../src/shared/Routes/Curve")
local Enclosure = require("../../../src/shared/Routes/Enclosure")

local Attractions = {}

local STUDS_PER_UNIT = 2.5

local function r4(n: number): number
	return math.floor(n * 1e4 + 0.5) / 1e4
end

local function r6(n: number): number
	return math.floor(n * 1e6 + 0.5) / 1e6
end

-- the enclosure record in world terms: each mouth's `out` from the building's local frame [X, Y, D]
local function worldEnclosure(place: any, e: any): any
	local out: { [string]: any } = table.clone(e)
	if e.mouths then
		local mouths = {}
		for _, m in e.mouths do
			local wm: { [string]: any } = table.clone(m)
			if m.out then
				local x0, y0, z0 = AlleyLayout.toWorld(place, 0, 0, 0)
				local x1, y1, z1 = AlleyLayout.toWorld(place, m.out[1], m.out[2], m.out[3])
				local dx, dy, dz = x1 - x0, y1 - y0, z1 - z0
				local len = math.sqrt(dx * dx + dy * dy + dz * dz)
				wm.out = { r6(dx / len), r6(dy / len), r6(dz / len) }
			end
			table.insert(mouths, wm)
		end
		out.mouths = mouths
	end
	return out
end

function Attractions.compile(ctx: any): any?
	local rel = "data/attractions.json"
	local path = ctx.repo .. "/" .. rel
	if not fs.isFile(path) then
		return nil
	end
	local doc = Json.decodeFile(path)
	local schema = Json.decodeFile(ctx.repo .. "/tools/compile/schema/attractions.schema.json")
	local errs = Schema.validate(schema, doc)
	if #errs > 0 then
		ctx.schemaError(rel, errs)
	end
	doc["$schema"] = nil
	local routes = {}
	local seen: { [number]: boolean } = {}
	for _, a in doc.attractions do
		local place = a.place
		local fp = a.footprint
		for _, r in a.routes do
			ctx.invariant("attraction route id unique: " .. r.id, not seen[r.id])
			ctx.invariant("attraction route id clear of the harvest: " .. r.id, not ctx.routeIds[r.id])
			seen[r.id] = true
			local pts = {}
			local vecs = {}
			for _, p in r.points do
				local X, Y, D = p[1], p[2], p[3]
				ctx.invariant(
					"attraction route point inside the footprint: " .. r.id,
					X >= fp.x0 and X <= fp.x1 and D >= fp.d0 and D <= fp.d1,
					string.format("(%.2f, %.2f, %.2f)", X, Y, D)
				)
				local x, y, z = AlleyLayout.toWorld(place, X, Y, D)
				table.insert(pts, { r4(x), r4(y), r4(z) })
				table.insert(vecs, Curve.vec3(x, y, z))
			end
			local length = Curve.new(vecs):getLength()
			local rec: { [string]: any } = {
				id = r.id,
				name = r.name,
				kind = r.kind,
				speedMult = 1,
				surfaceRadius = r.surfaceRadius,
				length = r4(length),
				sampleCount = Curve.sampleSteps(length / STUDS_PER_UNIT) + 1,
				points = pts,
				origin = "attraction",
				generator = "attraction:" .. a.id,
				lotId = a.id,
			}
			if r.visualOffset ~= nil then
				rec.visualOffset = r.visualOffset
			end
			if r.enclosure ~= nil then
				rec.enclosure = worldEnclosure(place, r.enclosure)
			end
			local encErrs = Enclosure.validate(rec.enclosure, r.kind)
			ctx.invariant("attraction route enclosure valid: " .. r.id, #encErrs == 0, table.concat(encErrs, "; "))
			if r.flags then
				local f = r.flags
				rec.flags = {
					autoGrabExcluded = f.autoGrabExcluded == true,
					isPole = f.isPole == true,
					isGiant = f.isGiant == true,
					fixedSurfaceZ = f.fixedSurfaceZ == true,
					treeTravel = f.treeTravel == true,
				}
			end
			table.insert(routes, rec)
		end
	end
	local setErrs = Enclosure.validateSet(routes, ctx.routeIds)
	ctx.invariant("attraction enclosures consistent", #setErrs == 0, table.concat(setErrs, "; "))
	ctx.compare("attraction routes (data/attractions.json)", #routes, #routes)
	return {
		name = "Attractions",
		value = { attractions = doc.attractions, routes = routes },
		records = #routes,
		map = true,
		source = rel,
		header = {
			"STUDS. attractions: placement and footprint per building (local frame: Shared/Attractions/AlleyLayout).",
			"routes: world-space route records (origin attraction) that Shared/Data appends to the Routes Registry.",
		},
	}
end

return Attractions
