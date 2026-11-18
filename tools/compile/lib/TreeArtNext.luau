--!strict
-- tools/compile: data/art/trees_v2.json -> generated/TreeArtNext.luau.
-- The route-true trees of the new generator (tools/blender/trees: natural branching, bending side branches, full
-- canopies of leaf sprays), one Model per tree, as Server/Assets/TreeArt needs them to swap a baked tree's meshes
-- for the new ones: per trunk route the Model's asset id (nil until the lead uploads it; tools/blender/trees/
-- publish.py), its world pivot, its triangles and its leaf sprays' part colour. STUDS, Roblox axes.
-- Invariants: one record per trunk route; every tree passed check_promises.py (no broken promise) and, if it is
-- hollow, check_hollows.py, before it has an id (one that did not is held back); its bark and leaves inside the
-- generator's budgets; an asset id is digits.
-- Interface: compile(ctx) -> Module? (nil when the file is absent)
local fs = require("@lune/fs")
local Json = require("./Json")

local TreeArtNext = {}

TreeArtNext.BARK_BUDGET = 8000 -- tools/blender/trees/treegen.py BARK_BUDGET
TreeArtNext.BARK_BUDGET_BIG = 12000 -- BARK_BUDGET_BIG: the named trees and the giants (BIG_CATEGORIES)
TreeArtNext.BIG_CATEGORIES = table.freeze({ named = true, giant = true })
TreeArtNext.LEAF_BUDGET = 6000 -- LEAF_BUDGET, the three Leaves* parts together

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
		local barkBudget = if TreeArtNext.BIG_CATEGORIES[t.category]
			then TreeArtNext.BARK_BUDGET_BIG
			else TreeArtNext.BARK_BUDGET
		ctx.invariant(what .. ": bark within budget", t.tris.bark <= barkBudget)
		ctx.invariant(what .. ": leaves within budget", t.tris.leaves <= TreeArtNext.LEAF_BUDGET)
		local id = t.assetId -- (JSON null decodes as nil)
		if id == "" then
			id = nil
		end
		-- a tree that broke a promise is held back (publish.py never uploads it): the live tree stays
		ctx.invariant(what .. ": uploaded only with every promise kept", id == nil or t.checks.promisesBroken == 0)
		ctx.invariant(
			what .. ": uploaded only with its hollow's boards inside the bark",
			id == nil or t.checks.hollow == nil or (t.checks.hollowBoardMargin or -1) >= 0
		)
		ctx.invariant(what .. ": an asset id is digits", id == nil or string.match(tostring(id), "^%d+$") ~= nil)
		total += t.tris.total
		-- the leaf sprays' part colour (what shows before or without the maps): the Leaves* parts share one green
		local leaf = nil
		for _, name in { "LeavesSun", "LeavesMid", "LeavesShade" } do
			local part = t.parts and t.parts[name]
			if part and part.color then
				ctx.invariant(
					what .. ": one leaf colour",
					leaf == nil or (leaf[1] == part.color[1] and leaf[2] == part.color[2] and leaf[3] == part.color[3])
				)
				leaf = leaf or part.color
			end
		end
		table.insert(trees, {
			trunkRoute = t.trunkRoute,
			label = t.label,
			assetId = if id then tostring(id) else nil,
			pivot = t.pivot,
			tris = t.tris.total,
			leaf = leaf,
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
			"its world pivot, triangles and leaf colour (RGB 0-255). Server/Assets/TreeArt swaps the baked tree's meshes",
			"for it when it has an id.",
		},
	}
end

return TreeArtNext
