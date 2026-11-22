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
