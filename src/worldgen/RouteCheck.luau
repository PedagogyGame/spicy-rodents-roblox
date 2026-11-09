--!strict
-- ServerScriptService.Server.WorldGen.RouteCheck
-- Route-on-geometry check (BUILD_PLAN §4.4 #7 exit criteria, S-2): every harvested route sample must
-- lie within surfaceRadius + 0.3 u of baked geometry (parts and wire Beams) or of the terrain, except
-- the routes listed in data/harvest_patches.json, each of which carries a reason. Runs on BuildPlans
-- (Lune bake and engine bake give the same plans), so the same verdict holds in both runtimes.
-- Leaf clusters do not count as geometry (they neither collide nor take queries): a route must sit on
-- bark, poles, pipes, rails, roofs or wires.
-- Interface: index(plans) -> Geometry.Index; run(plans, routes, opts) -> Result
--   opts = { registry = Routes/Registry instance over the same routes, heightAt = World/Height.at,
--            slackU = 0.3, patched = { [routeId]: true } }
-- Pure.

local Geometry = require("./Geometry")
local Spec = require("./Spec")
local Yield = require("./Yield")

local RouteCheck = {}

local SKIP_ROLES = { Room = true, Anchor = true, Skyline = true, Leaves = true }

export type Failure = { id: number, name: string, kind: string, generator: string, worst: number, at: { number } }
export type Result = {
	checked: number,
	samples: number,
	failures: { Failure },
	patchedFailing: number,
	patchedPassing: { number },
}

function RouteCheck.index(plans: { Spec.BuildPlan }): Geometry.Index
	local ix = Geometry.index(16)
	for _, p in plans do
		if p.kind ~= "skyline" then
			for _, s in p.parts do
				-- invisible Limb proxies stand where a tree mesh's bark is (Builders/Trees): they count
				-- and a mesh's bounding box is not geometry
				if not SKIP_ROLES[s.role or ""] and not s.mesh and (s.transparency < 1 or s.role == "Limb") then
					Geometry.add(ix, { box = s :: any, owner = p.id })
				end
			end
			for _, e in p.extras or {} do
				if e.kind == "Beam" and e.p0 and e.p1 then
					Geometry.add(ix, { a = e.p0, b = e.p1, r = 0.1, owner = p.id })
				end
			end
		end
	end
	return ix
end

function RouteCheck.run(plans: { Spec.BuildPlan }, routes: { any }, opts: any): Result
	local ix = RouteCheck.index(plans)
	local slack = (opts.slackU or 0.3) * Spec.SPU
	local patched = opts.patched or {}
	local failures: { Failure } = {}
	local samples = 0
	local patchedFailing = 0
	local patchedPassing: { number } = {}
	for _, r in routes do
		Yield.breathe()
		local route = opts.registry:get(r.id)
		local pts = opts.registry:samples(route)
		local R = r.surfaceRadius + slack
		local worst, worstAt = 0, { 0, 0, 0 }
		for _, s in pts do
			samples += 1
			local p = { s.x, s.y, s.z }
			local d = math.max(s.y - opts.heightAt(s.x, s.z), 0)
			if d > R then
				d = math.min(d, (Geometry.nearest(ix, p, R)))
			end
			if d > R and d > worst then
				worst, worstAt = d, p
			end
		end
		local fails = worst > 0
		if patched[r.id] then
			if fails then
				patchedFailing += 1
			else
				table.insert(patchedPassing, r.id)
			end
		elseif fails then
			table.insert(failures, {
				id = r.id,
				name = r.name,
				kind = r.kind,
				generator = r.generator or "",
				worst = worst,
				at = worstAt,
			})
		end
	end
	return {
		checked = #routes,
		samples = samples,
		failures = failures,
		patchedFailing = patchedFailing,
		patchedPassing = patchedPassing,
	}
end

return RouteCheck
