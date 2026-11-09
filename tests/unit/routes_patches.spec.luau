--!strict
-- Routes/Patches (W1 #8): data/harvest_patches.json applied through Registry's transform hook. The 40
-- outer-home downspout and gutter-to-roof routes are re-seated to the eave above local ground
-- (routes_movement verifier 3), every other route is untouched, sampleCount is kept (HANDOFF rule 3),
-- and each downspout top still meets its gutter joint exactly (the transfer survives).
local Data = require("@shared/Data")
local Patches = require("@shared/Routes/Patches")
local Registry = require("@shared/Routes/Registry")

return function(t)
	local data = Data.default()
	local patches = require("../../generated/HarvestPatches") :: any
	local lots = data:lots()

	t.test("reseat 40, lock 9, keep 1; every other route exactly as harvested", function()
		local plain = data:routes()
		local reg = Registry.new({
			loaders = (plain :: any)._loaders,
			studsPerUnit = plain:studsPerUnit(),
			transform = Patches.transform(patches, lots, plain:studsPerUnit()),
		})
		local counts: { [string]: number } = {}
		local changed = 0
		local plainById = {}
		for _, r in plain:all() do
			plainById[r.id] = r
		end
		for _, r in reg:all() do
			if r.patched then
				counts[r.patched] = (counts[r.patched] or 0) + 1
			end
			local p = plainById[r.id]
			t.eq(r.sampleCount, p.sampleCount, "sampleCount kept (rule 3)")
			local moved = false
			for i, q in r.points do
				if math.abs(q.y - p.points[i].y) > 1e-9 or q.x ~= p.points[i].x or q.z ~= p.points[i].z then
					moved = true
				end
			end
			if moved then
				changed += 1
				t.eq(r.patched, "reseat", `route {r.id} moved without a reseat patch`)
			end
		end
		t.eq(counts.reseat, 40)
		t.eq(counts.harvest_lock, 9)
		t.eq(counts.keep_off_geometry, 1)
		t.truthy(changed >= 30 and changed <= 40, `{changed} routes moved (raised lots)`)
	end)

	t.test("downspout tops sit at the eave above local ground and still meet their gutter joints", function()
		local reg = data:routes()
		local before = {}
		for id = 752, 791 do
			local r = reg:get(id) :: Registry.Route
			before[id] = r.points[#r.points].y
		end
		local fresh = Registry.new({ loaders = (reg :: any)._loaders, studsPerUnit = reg:studsPerUnit() })
		Patches.attach(fresh, patches, lots)
		local drops = 0
		for id = 752, 791, 2 do
			local spout = fresh:get(id) :: Registry.Route
			local gutter = fresh:get(id + 1) :: Registry.Route
			t.eq(spout.name, "house downspout")
			t.eq(gutter.name, "gutter to roof")
			local top = spout.points[#spout.points]
			local joint = gutter.points[1]
			t.near(top.y, joint.y, 1e-9, `joint {id}`)
			t.eq(top.x, joint.x)
			t.truthy(top.y <= before[id] + 1e-9, "never raised")
			if top.y < before[id] - 0.05 then
				drops += 1
			end
			-- the curve and length follow the moved points
			t.near(fresh:samples(spout)[spout.sampleCount].y, top.y, 1e-6)
		end
		t.truthy(drops >= 15, `{drops} of 20 downspouts dropped by their lot's terrain height`)
		-- the first one by hand: outer_home_00 seat 0.836 + eave 5.2 - 0.15 = 5.886 u
		t.near((fresh:get(752) :: Registry.Route).points[3].y, 5.886 * 2.5, 1e-9)
	end)
end
