--!strict
-- tools/compile: data/hollows.json -> generated/HollowTrees.luau (brief v2 §3 "Hollow trees", BRIEF_ADDENDUM D6).
-- The design file (W1 compiles it as generated/Hollows, HTML units) carries per hollow an `inside` block in studs
-- about its harvested trunk; Shared/World/HollowLayout.build, the one place the geometry rules live, turns it and the
-- harvested routes into the hollows' enclosed route records and their shells; this module checks what the compiled
-- routes must hold and hands the table to the emitter. Shared/Data appends `routes` to the Registry after the storm
-- drains; everything else reads the table through HollowLayout.new / default.
-- Invariants: route ids unique, clear of the harvest and of every other compiled id (ctx.routeIds, ctx.otherIds);
-- every enclosure record valid (Enclosure.validate), the set consistent (Enclosure.validateSet, the harvested boughs
-- and trunks its mouths link to known) and its links within a transfer (Motion.enclosureErrors); every hollow's
-- trunk a harvested trunk; 12 claimable hollows and the log.
-- Interface: compile(ctx) -> Module? (nil when the file is absent)
local fs = require("@lune/fs")
local Json = require("./Json")
local Enclosure = require("../../../src/shared/Routes/Enclosure")
local Height = require("../../../src/shared/World/Height")
local HollowLayout = require("../../../src/shared/World/HollowLayout")
local Motion = require("../../../src/shared/Routes/Motion")
local Registry = require("../../../src/shared/Routes/Registry")

local HollowTrees = {}

function HollowTrees.compile(ctx: any): any?
	local rel = "data/hollows.json"
	local path = ctx.repo .. "/" .. rel
	if not fs.isFile(path) then
		return nil
	end
	-- (the schema is checked by the W1 pass, which compiles the same file as generated/Hollows)
	local doc = Json.decodeFile(path)
	doc["$schema"] = nil
	local harvest = Registry.fromRecords(ctx.routes)
	Height.configure(ctx.terrainExtensions)
	local compiled = HollowLayout.build(doc, harvest :: any, Height.at)
	Height.configure(nil)

	local seen: { [number]: boolean } = {}
	for _, r in compiled.routes do
		ctx.invariant("hollow route id unique: " .. r.id, not seen[r.id])
		ctx.invariant("hollow route id clear of the harvest: " .. r.id, not ctx.routeIds[r.id])
		ctx.invariant("hollow route id clear of the other compiled routes: " .. r.id, not (ctx.otherIds or {})[r.id])
		seen[r.id] = true
		local encErrs = Enclosure.validate(r.enclosure, r.kind)
		ctx.invariant("hollow route enclosure valid: " .. r.id, #encErrs == 0, table.concat(encErrs, "; "))
	end
	local setErrs = Enclosure.validateSet(compiled.routes, ctx.routeIds)
	ctx.invariant("hollow enclosures consistent", #setErrs == 0, table.concat(setErrs, "; "))
	if #setErrs == 0 then
		-- the links reach: checked with the harvest's routes they name loaded beside the hollows'
		local recs = table.clone(ctx.routes)
		for _, r in compiled.routes do
			table.insert(recs, r)
		end
		local linkErrs = Motion.enclosureErrors(Registry.fromRecords(recs :: any), ctx.routeIds)
		ctx.invariant("hollow enclosure links reach", #linkErrs == 0, table.concat(linkErrs, "; "))
	end
	local claimable = 0
	for _, h in compiled.hollows do
		if h.claimable then
			claimable += 1
		end
	end
	ctx.compare("claimable hollow insides (brief v2 §3)", 12, claimable)
	ctx.compare("hollows with insides, the log among them", #doc.hollows + 1, #compiled.hollows)
	return {
		name = "HollowTrees",
		value = compiled,
		records = #compiled.routes,
		map = true,
		source = rel,
		header = {
			"STUDS, world space. The hollow trees' insides and the fallen log (Shared/World/HollowLayout: its header is the",
			"interface). routes: world-space route records (origin hollow, kind tunnel) that Shared/Data appends to the",
			"Routes Registry; hollows: per hollow its routes, mouths, chambers, cavities and the shell the server builds.",
		},
	}
end

return HollowTrees
