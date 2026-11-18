--!strict
-- tools/compile: data/art/trees_v2.json -> generated/TreeArtNext.luau.
-- The route-true trees of the new generator (tools/blender/trees: natural branching, bending side branches, full
-- canopies of leaf sprays), one Model per tree, as Server/Assets/TreeArt needs them to swap a baked tree's meshes
-- for the new ones: per trunk route the Model's asset id (nil until the lead uploads it; tools/blender/trees/
-- publish.py), its world pivot and its triangles. STUDS, Roblox axes.
-- Invariants: one record per trunk route; every tree passed check_promises.py (no broken promise) and, if it is
-- hollow, check_hollows.py; its bark and leaves inside the generator's budgets; an asset id is digits.
-- Interface: compile(ctx) -> Module? (nil when the file is absent)
local fs = require("@lune/fs")
local Json = require("./Json")

local TreeArtNext = {}

TreeArtNext.BARK_BUDGET = 12000 -- tools/blender/trees/treegen.py BARK_BUDGET
TreeArtNext.LEAF_BUDGET = 14000 -- LEAF_BUDGET, the three Leaves* parts together

function TreeArtNext.compile(ctx: any): any?
	local rel = "data/art/trees_v2.json"
	local path = ctx.repo .. "/" .. rel
	if not fs.isFile(path) then
		return nil
	end
	local doc = Json.decodeFile(path)
	local trees = {}
	local seen: { [number]: boolean } = {}
	local total = 0
	for _, t in doc.trees do
		local what = `tree art v2 {t.index} ({t.label})`
		ctx.invariant(what .. ": one model per trunk route", not seen[t.trunkRoute])
		seen[t.trunkRoute] = true
		ctx.invariant(what .. ": no broken promise", t.checks.promisesBroken == 0)
		ctx.invariant(
			what .. ": its hollow's boards stay inside the bark",
			t.checks.hollow == nil or (t.checks.hollowBoardMargin or -1) >= 0
		)
		ctx.invariant(what .. ": bark within budget", t.tris.bark <= TreeArtNext.BARK_BUDGET)
		ctx.invariant(what .. ": leaves within budget", t.tris.leaves <= TreeArtNext.LEAF_BUDGET)
		local id = t.assetId -- (JSON null decodes as nil)
		if id == "" then
			id = nil
		end
		ctx.invariant(what .. ": an asset id is digits", id == nil or string.match(tostring(id), "^%d+$") ~= nil)
		total += t.tris.total
		table.insert(trees, {
			trunkRoute = t.trunkRoute,
			label = t.label,
			assetId = if id then tostring(id) else nil,
			pivot = t.pivot,
			tris = t.tris.total,
		})
	end
	table.sort(trees, function(a, b)
		return a.trunkRoute < b.trunkRoute
	end)
	ctx.compare("tree art v2 models (data/art/trees_v2.json)", doc.count, #trees)
	ctx.compare("tree art v2 triangles (data/art/trees_v2.json totals)", doc.totals.total, total)
	return {
		name = "TreeArtNext",
		value = trees,
		records = #trees,
		source = rel,
		header = {
			"STUDS, Roblox axes. One record per tree trunk route: the new generator's Model (assetId nil until uploaded),",
			"its world pivot and triangles. Server/Assets/TreeArt swaps the baked tree's meshes for it when it has an id.",
		},
	}
end

return TreeArtNext
