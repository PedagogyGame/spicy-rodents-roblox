--!strict
-- tools/compile: generated/BranchNooks.luau (BRIEF_ADDENDUM D34: "little nooks in the branches ... stash places off to
-- the side and a little place to hangout ... improve and add branching"). No authored file: Shared/World/BranchNooks
-- (the one place the rules live) plans every climbable tree's nooks, stashes, hangouts and spurs from the routes and
-- canopy forks compiled before it: the harvest's, and every module's `routes` and `forks` (the attractions, the storm
-- drains, the hollow trees, the tree shapes, any tree module added later), so a new tree gets them once it is compiled
-- before this step. Keep this the last step that makes routes.
-- Invariants: route ids unique and clear of every other compiled id; every new route starts on a sample of its bough;
-- every climbable tree (a trunk with canopy forks to open branches) has a nook with a stash.
-- Two modules: BranchNooks (places and trees: a record) and BranchNookRoutes (the route records, an array the emitter
-- chunks like the harvest's routes; Shared/Data appends them to the Registry).
-- Interface: compile(ctx) -> (Module, Module); ctx = { routes (every route record so far), forks (the canopy forks so far,
--   merged), ids ({ [id] = true }: every id so far), data (a Shared/Data over the modules compiled so far: the
--   buildings' boxes), terrainExtensions, invariant, compare }.
local Colliders = require("../../../src/shared/World/Colliders")
local Height = require("../../../src/shared/World/Height")
local Registry = require("../../../src/shared/Routes/Registry")
local BranchNooks = require("../../../src/shared/World/BranchNooks")

local Lib = {}

function Lib.compile(ctx: any): (any, any)
	local reg = Registry.fromRecords(ctx.routes)
	Height.configure(ctx.terrainExtensions)
	-- the buildings' boxes (World/Colliders over the compiled lots, venues and the alley: ctx.data, a Shared/Data over
	-- what is compiled so far), each grown by buildingPad, up to its peak
	local boxes = Colliders.fromData(ctx.data)
	local pad = BranchNooks.C.buildingPad
	local function blocked(x: number, y: number, z: number): boolean
		for _, b in Colliders.query(boxes, x - pad, z - pad, x + pad, z + pad) do
			if
				math.abs(x - b.cx) <= b.hw + pad
				and math.abs(z - b.cz) <= b.hd + pad
				and y >= b.y0 - 1
				and y <= b.peak + pad
			then
				return true
			end
		end
		return false
	end
	local compiled = BranchNooks.plan(reg :: any, ctx.forks, Height.at, blocked)
	Height.configure(nil)
	compiled.rejected = nil -- (the planner's tally of candidates left out: not data)

	local seen: { [number]: boolean } = {}
	for _, r in compiled.routes do
		ctx.invariant("branch nook route id unique: " .. r.id, not seen[r.id])
		ctx.invariant("branch nook route id clear of the other compiled routes: " .. r.id, not ctx.ids[r.id])
		seen[r.id] = true
	end
	local byId: { [number]: any } = {}
	for _, r in compiled.routes do
		byId[r.id] = r
	end
	for _, p in compiled.places do
		local parent = reg:get(p.parent)
		local r = byId[p.route]
		local ok = false
		if parent and r then
			for _, s in reg:samples(parent) do
				local q = r.points[1]
				if (s.x - q[1]) ^ 2 + (s.y - q[2]) ^ 2 + (s.z - q[3]) ^ 2 < 1e-8 then
					ok = true
					break
				end
			end
		end
		ctx.invariant(`branch nook {p.route} starts on a sample of its bough {p.parent}`, ok)
	end
	local climbable = 0
	local withStash: { [number]: boolean } = {}
	for _, p in compiled.places do
		if p.stash then
			withStash[p.trunk] = true
		end
	end
	for _, rec in ctx.forks do
		local trunk = reg:get(rec.trunk)
		if trunk and trunk.kind == "trunk" and trunk.enclosure == nil then
			local open = false
			for _, f in rec.forks do
				local b = reg:get(f.branch)
				if b and b.kind == "branch" and b.enclosure == nil and b.origin ~= "hollow" then
					open = true
				end
			end
			if open then
				climbable += 1
				ctx.invariant(`climbable tree {rec.trunk} has a nook with a stash`, withStash[rec.trunk] == true)
			end
		end
	end
	local source = "every compiled route and canopy fork (Shared/World/BranchNooks plans them)"
	return {
		name = "BranchNooks",
		value = { places = compiled.places, trees = compiled.trees },
		records = #compiled.places,
		map = true,
		source = source,
		header = {
			"STUDS, world space. The D34 branch nooks (Shared/World/BranchNooks: its header is the interface): places, each",
			"nook, hangout and spur and where it is (a nook's stash); trees, per climbable tree "
				.. `({climbable}) its routes. The routes`,
			"themselves are BranchNookRoutes_NN (Shared/Data appends them to the Routes Registry after the tree shapes).",
		},
	}, {
		name = "BranchNookRoutes",
		value = compiled.routes,
		records = #compiled.routes,
		chunked = true,
		source = source,
		header = {
			"STUDS, world space. The D34 branch nooks' route records (Shared/World/BranchNooks, origin branchNook): nooks,",
			"hangouts and spurs, each leaving a sample of its bough; places and trees are generated/BranchNooks.",
		},
	}
end

return Lib
