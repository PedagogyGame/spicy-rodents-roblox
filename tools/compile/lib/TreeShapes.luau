--!strict
-- tools/compile: data/tree_shapes.json -> generated/TreeShapes.luau (BRIEF_ADDENDUM D32: the owner's "more levels,
-- bigger trees ... add a couple trees"). Shared/World/TreeShapes.build, the one place the rules live, turns the
-- authored boughs and plantings and the harvested routes and canopy forks into route records (origin "treeShape"),
-- their forks and a per-tree list; this module checks what they must hold and hands the table to the emitter.
-- Shared/Data appends `routes` to the Registry after the hollow trees and merges `forks` into the canopy forks.
-- A planted tree is a copy of a tree with art: its source's art records (generated/TreeArt, the baked meshes, and
-- generated/TreeArtNext, the uploaded v2 Model) are copied onto the copy's trunk at the copy's pivot, with the copy's
-- routes as the ones the meshes cover (`routes` / `covers`), so the bake and Server/Assets/TreeArt place the same
-- tree there.
-- Invariants: route ids unique, clear of the harvest and of every other compiled id; a reshaped tree is a harvested
-- trunk that no hollow uses (data/hollows.json: those trunks are the hollow trees' work); a planted tree's source
-- has baked art and an uploaded v2 Model.
-- Interface: compile(ctx) -> Module? (nil when the file is absent); ctx.treeArt / ctx.treeArtNext: the art modules'
-- values (lists), extended in place with the copies.
local fs = require("@lune/fs")
local Json = require("./Json")
local Height = require("../../../src/shared/World/Height")
local Registry = require("../../../src/shared/Routes/Registry")
local TreeShapes = require("../../../src/shared/World/TreeShapes")

local Lib = {}

local function hollowTrunks(repo: string): { [number]: string }
	local out: { [number]: string } = {}
	local path = repo .. "/data/hollows.json"
	if fs.isFile(path) then
		for _, h in Json.decodeFile(path).hollows do
			if h.inside and h.inside.trunk then
				out[h.inside.trunk] = h.id
			end
		end
	end
	return out
end

-- The D35 climbs: the town's trees that had no route, where their own bakes stand them. Lookout Hill's conifers
-- (Shared/Rides/LookoutHill.dressing: a trunk of diameter max(0.6, w 0.12) to 0.22 h + 1, the crown's wedges to h):
-- a trunk to three quarters of the height, up into the crown; the sky lift's hedgerow oaks and orchard apples
-- (Shared/Rides/SkyLiftCountry OAKS, ORCHARD; tools/bake/skylift/Countryside draws a trunk to at least 0.6 x the
-- shortest seeded height and a ball crown over it): a trunk to the crown. `reach`: the crown's half width (the woods
-- keep clear of it: WorldGen/WoodsPlan). Ground: World/Height with the extensions, as their bakes stand them.
local function climbs(): { any }
	local LookoutHill = require("../../../src/shared/Rides/LookoutHill")
	local SkyLiftCountry = require("../../../src/shared/Rides/SkyLiftCountry")
	local out = {}
	local function r3(v: number): number
		return math.floor(v * 1000 + 0.5) / 1000
	end
	for _, d in LookoutHill.dressing() do
		if d.kind == "conifer" then
			local h, w = d.h :: number, d.w :: number
			table.insert(out, {
				label = "LOOKOUT CONIFER",
				what = "a conifer on Lookout Hill (tools/bake/skylift/Approach)",
				x = r3(d.x),
				y = r3(Height.at(d.x, d.z)),
				z = r3(d.z),
				reach = r3(w / 2),
				climb = { trunk = { height = r3(0.75 * h), radius = 1.0 } },
			})
		end
	end
	for _, p in SkyLiftCountry.OAKS do
		local x, z = SkyLiftCountry.at(p[1], p[2])
		table.insert(out, {
			label = "HEDGEROW OAK",
			what = "a hedgerow oak under the sky lift (tools/bake/skylift/Countryside)",
			x = r3(x),
			y = r3(Height.at(x, z)),
			z = r3(z),
			reach = 8,
			climb = { trunk = { height = 10.5, radius = 1.2 } },
		})
	end
	for _, p in SkyLiftCountry.ORCHARD do
		local x, z = SkyLiftCountry.at(p[1], p[2])
		table.insert(out, {
			label = "ORCHARD APPLE",
			what = "an apple tree in the sky lift's orchard (tools/bake/skylift/Countryside)",
			x = r3(x),
			y = r3(Height.at(x, z)),
			z = r3(z),
			reach = 4.3,
			climb = { trunk = { height = 5.0, radius = 1.0 } },
		})
	end
	return out
end

-- Lib.woods(ctx): data/woods.json (kinds) and data/woods_placed.json (tools/blender/trees/place_woods.luau) and the
-- climbs, as TreeShapes.Woods; nil when data/woods.json is absent
function Lib.woods(ctx: any): any?
	local path = ctx.repo .. "/data/woods.json"
	if not fs.isFile(path) then
		return nil
	end
	local doc = Json.decodeFile(path)
	-- the uploaded Models (data/art/woods.json, tools/blender/trees/publish_woods.py): per kind its asset id (nil until
	-- the lead uploads it), its leaf sprays' part colour and its triangles
	local art: { [string]: any } = {}
	local artPath = ctx.repo .. "/data/art/woods.json"
	if fs.isFile(artPath) then
		for _, a in Json.decodeFile(artPath).kinds do
			local id = a.assetId
			if id == "" then
				id = nil
			end
			ctx.invariant(
				`woods art {a.kind}: an asset id is digits`,
				id == nil or string.match(tostring(id), "^%d+$") ~= nil
			)
			ctx.invariant(`woods art {a.kind}: uploaded only with every promise kept`, id == nil or a.checks.ok == true)
			art[a.kind] = {
				assetId = if id then tostring(id) else nil,
				leaf = a.parts.Leaves.color,
				tris = a.tris.total,
			}
		end
	end
	local kinds = {}
	for id, k in doc.kinds do
		kinds[id] = {
			label = k.label,
			family = k.family,
			species = k.species,
			height = k.height,
			crown = k.crown,
			climb = k.climb,
			art = art[id],
		}
	end
	local trees = {}
	local placed = ctx.repo .. "/data/woods_placed.json"
	if fs.isFile(placed) then
		for _, t in Json.decodeFile(placed).trees do
			ctx.invariant(`woods: a placed tree's kind {t[1]} is in data/woods.json`, kinds[t[1]] ~= nil)
			table.insert(trees, { kind = t[1], x = t[2], y = t[3], z = t[4], yaw = t[5], scale = t[6] })
		end
	end
	Height.configure(ctx.terrainExtensions)
	local cl = climbs()
	Height.configure(nil)
	return { idBase = doc.idBase, climbBase = doc.climbBase, kinds = kinds, trees = trees, climbs = cl }
end

function Lib.compile(ctx: any): any?
	local rel = "data/tree_shapes.json"
	local path = ctx.repo .. "/" .. rel
	if not fs.isFile(path) then
		return nil
	end
	local doc = Json.decodeFile(path)
	doc["$schema"] = nil
	local harvest = Registry.fromRecords(ctx.routes)
	Height.configure(ctx.terrainExtensions)
	local compiled = TreeShapes.build(doc, harvest :: any, ctx.forks, Height.at)
	Height.configure(nil)

	local seen: { [number]: boolean } = {}
	for _, r in compiled.routes do
		ctx.invariant("tree shape route id unique: " .. r.id, not seen[r.id])
		ctx.invariant("tree shape route id clear of the harvest: " .. r.id, not ctx.routeIds[r.id])
		ctx.invariant("tree shape route id clear of the other compiled routes: " .. r.id, not ctx.otherIds[r.id])
		seen[r.id] = true
	end
	local hollows = hollowTrunks(ctx.repo)
	for _, rs in doc.reshaped do
		ctx.invariant(
			`tree shapes: {rs.label} ({rs.trunk}) is no hollow tree`,
			hollows[rs.trunk] == nil,
			`hollow {hollows[rs.trunk]}`
		)
	end

	-- the planted copies take their source's art
	local artBy: { [number]: any } = {}
	for _, a in ctx.treeArt or {} do
		artBy[a.trunkRoute] = a
	end
	local nextBy: { [number]: any } = {}
	for _, a in ctx.treeArtNext or {} do
		nextBy[a.trunkRoute] = a
	end
	-- a reshaped tree's uploaded v2 Model covers the grown boughs its data/art/trees_v2.json record lists among its
	-- routes (a Model rebuilt with them: tools/blender/trees build_trees.py --shapes); the runtime swap then hides the
	-- baked stand-ins (Server/Assets/TreeArt.hideGrown)
	local v2Routes: { [number]: { [number]: boolean } } = {}
	local v2Path = ctx.repo .. "/data/art/trees_v2.json"
	if fs.isFile(v2Path) then
		for _, t in Json.decodeFile(v2Path).trees do
			local set = {}
			for _, id in t.routes or {} do
				set[id] = true
			end
			v2Routes[t.trunkRoute] = set
		end
	end
	for _, tree in compiled.trees do
		if tree.kind == "reshaped" then
			local n, set = nextBy[tree.trunk], v2Routes[tree.trunk]
			if n and n.assetId and set then
				local covers = {}
				for _, id in tree.routes do
					if set[id] then
						table.insert(covers, id)
					end
				end
				if #covers > 0 then
					n.covers = covers
				end
			end
		end
	end
	for _, tree in compiled.trees do
		if tree.kind == "planted" then
			local src = tree.source :: number
			local off = tree.offset :: { number }
			local a, n = artBy[src], nextBy[src]
			ctx.invariant(`tree shapes: planted {tree.label}'s source {src} has baked art`, a ~= nil)
			ctx.invariant(
				`tree shapes: planted {tree.label}'s source {src} has an uploaded v2 Model`,
				n ~= nil and n.assetId ~= nil
			)
			if a and n then
				local function moved(p: { number }): { number }
					return { p[1] + off[1], p[2] + off[2], p[3] + off[3] }
				end
				local copy = table.clone(a)
				copy.trunkRoute = tree.trunk
				copy.label = tree.label
				copy.pivot = moved(a.pivot)
				copy.routes = table.clone(tree.routes)
				table.insert(ctx.treeArt, copy)
				local nc = table.clone(n)
				nc.trunkRoute = tree.trunk
				nc.label = tree.label
				nc.pivot = moved(n.pivot)
				nc.covers = table.clone(tree.routes)
				table.insert(ctx.treeArtNext, nc)
			end
		end
	end
	-- the D34/D35 woods and climbs, compact (Shared/World/TreeShapes WOODS AND CLIMBS; Shared/Data expands them)
	compiled.woods = Lib.woods(ctx)
	if compiled.woods then
		local routes = TreeShapes.expandWoods(compiled.woods)
		for _, r in routes do
			ctx.invariant("woods route id unique: " .. r.id, not seen[r.id])
			ctx.invariant("woods route id clear of the harvest: " .. r.id, not ctx.routeIds[r.id])
			ctx.invariant("woods route id clear of the other compiled routes: " .. r.id, not ctx.otherIds[r.id])
			seen[r.id] = true
		end
	end
	return {
		name = "TreeShapes",
		value = compiled,
		records = #compiled.routes,
		map = true,
		source = rel,
		header = {
			"STUDS, world space. The D32 tree shapes (Shared/World/TreeShapes: its header is the interface). routes:",
			"world-space route records (origin treeShape) that Shared/Data appends to the Routes Registry; forks: the new",
			"canopy forks per trunk, merged into the harvest's by Shared/Data; trees: per reshaped or planted tree its routes.",
		},
	}
end

return Lib
