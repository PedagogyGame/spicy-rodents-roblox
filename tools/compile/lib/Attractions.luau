--!strict
-- tools/compile: data/attractions.json -> generated/Attractions.luau (brief v2 §13a; BUILD_PLAN §3.17, W3c #15).
-- Attraction buildings that are baked on their own (tools/bake/attractions.luau -> build/Attractions.rbxm ->
-- Workspace.Attractions). The file is authored in STUDS. Each building's routes (the bowling alley's
-- ball-return vents and tunnels) are turned from the building's local frame into world route records the
-- Routes Registry reads (Shared/Data appends them after the harvested chunks): world points, the curve's arc
-- length, the sample count (max(20, ceil(3L)) + 1 on the length in HTML units, as for a harvested route),
-- origin "attraction" and explicit flags. Invariants: ids unique and clear of the harvest, at least two
-- points, every point inside the footprint.
-- Interface: compile(ctx) -> Module? (nil when the file is absent)
local fs = require("@lune/fs")
local Json = require("./Json")
local Schema = require("./Schema")
local AlleyLayout = require("../../../src/shared/Attractions/AlleyLayout")
local Curve = require("../../../src/shared/Routes/Curve")

local Attractions = {}

local STUDS_PER_UNIT = 2.5

local function r4(n: number): number
	return math.floor(n * 1e4 + 0.5) / 1e4
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
