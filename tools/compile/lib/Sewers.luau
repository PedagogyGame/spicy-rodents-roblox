--!strict
-- tools/compile: data/sewers.json -> generated/Sewers.luau (BRIEF_ADDENDUM D8, the storm drains under the town).
-- The authored file (studs, world space) goes through Shared/World/SewerLayout.build, the one place the geometry
-- rules live (shafts, walkway lines, the junction, the carve, the anchors); this module validates it, checks what
-- the compiled routes must hold, and hands the table to the emitter. Shared/Data appends `routes` to the Registry
-- after the harvest and the attractions; everything else reads the table through SewerLayout.new / default.
-- Invariants: route ids inside the authored range, unique, clear of the harvest and of every other compiled id
-- (ctx.routeIds, ctx.otherIds); every enclosure record valid (Enclosure.validate), the set consistent
-- (Enclosure.validateSet) and its links within a transfer (Motion.enclosureErrors); every carve box on the voxel
-- grid; every route above Recovery's floor. The pipe pace (each record's speedMult) is Tunables sewer.speedMult.
-- Interface: compile(ctx) -> Module? (nil when the file is absent)
local fs = require("@lune/fs")
local Json = require("./Json")
local Schema = require("./Schema")
local Enclosure = require("../../../src/shared/Routes/Enclosure")
local Motion = require("../../../src/shared/Routes/Motion")
local Recovery = require("../../../src/shared/Movement/Recovery")
local Registry = require("../../../src/shared/Routes/Registry")
local SewerLayout = require("../../../src/shared/World/SewerLayout")
local Tunables = require("../../../src/shared/Config/Tunables")

local Sewers = {}

function Sewers.compile(ctx: any): any?
	local rel = "data/sewers.json"
	local path = ctx.repo .. "/" .. rel
	if not fs.isFile(path) then
		return nil
	end
	local doc = Json.decodeFile(path)
	local schema = Json.decodeFile(ctx.repo .. "/tools/compile/schema/sewers.schema.json")
	local errs = Schema.validate(schema, doc)
	if #errs > 0 then
		ctx.schemaError(rel, errs)
		return nil
	end
	doc["$schema"] = nil
	local compiled = SewerLayout.build(doc, { pace = Tunables.raw("sewer.speedMult") })

	local lo, hi = doc.routeIds[1], doc.routeIds[2]
	local seen: { [number]: boolean } = {}
	for _, r in compiled.routes do
		ctx.invariant("sewer route id unique: " .. r.id, not seen[r.id])
		ctx.invariant("sewer route id in its range: " .. r.id, r.id >= lo and r.id <= hi)
		ctx.invariant("sewer route id clear of the harvest: " .. r.id, not ctx.routeIds[r.id])
		ctx.invariant("sewer route id clear of the other compiled routes: " .. r.id, not (ctx.otherIds or {})[r.id])
		seen[r.id] = true
		local encErrs = Enclosure.validate(r.enclosure, r.kind)
		ctx.invariant("sewer route enclosure valid: " .. r.id, #encErrs == 0, table.concat(encErrs, "; "))
		local lowest = math.huge
		for _, p in r.points do
			lowest = math.min(lowest, p[2])
		end
		ctx.invariant(
			"sewer route above the recovery floor: " .. r.id,
			lowest > Recovery.FLOOR_Y + 2,
			string.format("lowest point %.2f", lowest)
		)
	end
	local setErrs = Enclosure.validateSet(compiled.routes, ctx.routeIds)
	ctx.invariant("sewer enclosures consistent", #setErrs == 0, table.concat(setErrs, "; "))
	if #setErrs == 0 then
		local linkErrs = Motion.enclosureErrors(Registry.fromRecords(compiled.routes :: any), ctx.routeIds)
		ctx.invariant("sewer enclosure links reach", #linkErrs == 0, table.concat(linkErrs, "; "))
	end
	local voxel = compiled.carve.voxel
	for i, b in compiled.carves do
		local onGrid = true
		for _, v in { b.x0, b.x1, b.y0, b.y1, b.z0, b.z1 } do
			if v % voxel ~= 0 then
				onGrid = false
			end
		end
		ctx.invariant("sewer carve box on the voxel grid: " .. i, onGrid)
		ctx.invariant("sewer carve box above the terrain slab's bottom: " .. i, b.y0 >= compiled.carve.slabBottom)
	end
	ctx.compare("sewer pipes (data/sewers.json)", #doc.pipes, #compiled.pipes)
	return {
		name = "Sewers",
		value = compiled,
		records = #compiled.routes,
		map = true,
		source = rel,
		header = {
			"STUDS, world space. The storm drains (Shared/World/SewerLayout: its header is the interface). routes: world-space",
			"route records (origin sewer, kind tunnel) that Shared/Data appends to the Routes Registry.",
		},
	}
end

return Sewers
