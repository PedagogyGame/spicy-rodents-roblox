--!strict
-- The D32 tree shapes (data/tree_shapes.json, Shared/World/TreeShapes, generated/TreeShapes): the owner's "more
-- levels, overall bigger trees, not just a single place and point where branches come out of and all split ... about
-- 11% of the other trees ... a few lower branches ... add a couple trees". Over the compiled data, as every rail user
-- sees it (Shared/Data: the routes appended, the forks merged; Movement/RailWorld):
--   * which trees: ten reshaped, none hollow (Shared/World/HollowLayout's trunks are the hollow trees' own), about
--     11 % of the rest, spread over the town; three planted;
--   * continuity and junctions: every grown bough leaves a trunk sample, its canopy fork made by the harvest's rule
--     and found where the motor looks (Motion.nearbyForks); a smooth curve, no stretch steeper than the harvest's;
--   * several heights: a reshaped tree's boughs leave the trunk at three or more levels, the lowest near the ground;
--     the "big" ones spread wider than before;
--   * the lower boughs reached from the ground: the real SquirrelMotor climbs the trunk, picks the low bough with A/D,
--     takes it holding W and runs it to its tip in even steps; and leaping from the lawn under it, E catches it;
--   * nothing in the way: no planted trunk on paving or a lot that is not open ground, no bough in a building or
--     low over a street, a sidewalk or a path, no grown bough through another route;
--   * the planted copies are their sources moved (routes, forks, art at the new pivot, its routes covered);
--   * budgets: the town under 27,000 parts; what the stand-ins for the grown boughs and the planted trees cost.
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local Bake = require("@worldgen/Bake")
local Curve = require("@shared/Routes/Curve")
local Data = require("@shared/Data")
local Height = require("@shared/World/Height")
local Motion = require("@shared/Routes/Motion")
local RailWorld = require("@shared/Movement/RailWorld")
local Registry = require("@shared/Routes/Registry")
local SquirrelMotor = require("@shared/Movement/SquirrelMotor")
local TreeClear = require("@tests/lib/TreeClear")
local TreeShapes = require("@shared/World/TreeShapes")
local Units = require("@shared/Config/Units")

local CLEAR_OF_ROUTES = 2.0 -- studs between a grown bough's centre line and any other route's, past 4 studs from its axis
local OVER_PAVING = 16 -- studs: a bough over a street, sidewalk or path is at least this high over the ground
local OVER_LAWN = 6.5 -- studs: and this high anywhere (a walker passes under)
local LOW_START = 12 -- studs above the foot: a tree's lowest bough leaves the trunk no higher

return function(t)
	local d = Data.default()
	local reg = d:routes()
	local compiled = d:module("TreeShapes") :: any
	local doc = serde.decode("json", fs.readFile("data/tree_shapes.json"))
	local rail = RailWorld.build(d)
	local hollow: { [number]: string } = {}
	for _, h in serde.decode("json", fs.readFile("data/hollows.json")).hollows do
		if h.inside and h.inside.trunk then
			hollow[h.inside.trunk] = h.id
		end
	end
	local harvestForks: { [number]: any } = {}
	for _, r in require("../../generated/Forks") :: any do
		harvestForks[r.trunk] = r
	end
	local specOf: { [number]: any } = {}
	for _, rs in doc.reshaped do
		specOf[rs.trunk] = rs
	end
	local function trees(kind: string): { any }
		local out = {}
		for _, tr in compiled.trees do
			if tr.kind == kind then
				table.insert(out, tr)
			end
		end
		return out
	end
	local function level(a: any, b: any): number
		return math.sqrt((a.x - b.x) ^ 2 + (a.z - b.z) ^ 2)
	end

	t.test("ten reshaped trees, none hollow (about 11 % of the others), spread over the town; three planted", function()
		local reshaped = trees("reshaped")
		t.eq(#reshaped, 10)
		local harvested = 0
		for _, r in require("../../generated/Forks") :: any do
			if r.trunk then
				harvested += 1
			end
		end
		local hollows = 0
		for _ in hollow do
			hollows += 1
		end
		local share = #reshaped / (harvested - hollows)
		t.truthy(share >= 0.1 and share <= 0.13, `share {share}`)
		local quadrants: { [string]: boolean } = {}
		for i, a in reshaped do
			t.eq(hollow[a.trunk], nil, `{a.label} is a hollow tree`)
			t.truthy(harvestForks[a.trunk] ~= nil, `{a.label}: a harvested tree`)
			local fa = reg:foot(reg:get(a.trunk) :: any)
			quadrants[(if fa.x < 0 then "W" else "E") .. (if fa.z < 0 then "S" else "N")] = true
			for j = i + 1, #reshaped do
				local fb = reg:foot(reg:get(reshaped[j].trunk) :: any)
				t.truthy(level(fa, fb) > 80, `{a.label} and {reshaped[j].label} are neighbours`)
			end
		end
		local nq = 0
		for _ in quadrants do
			nq += 1
		end
		t.eq(nq, 4, "all four quarters of the town")
		t.eq(#trees("planted"), 3)
		-- no hollow trunk gains a fork (the hollow trees' insides and exits are another branch's work)
		for _, r in compiled.forks do
			t.eq(hollow[r.trunk], nil, `fork on hollow trunk {r.trunk}`)
		end
	end)

	t.test(
		"every grown bough leaves a trunk sample; its canopy fork is the harvest's rule, where the motor looks",
		function()
			local n = 0
			for _, tree in trees("reshaped") do
				local trunk = reg:get(tree.trunk) :: Registry.Route
				local samples = reg:samples(trunk)
				for _, b in tree.boughs do
					n += 1
					local r = reg:get(b.route) :: Registry.Route
					t.eq(r.kind, "branch")
					t.eq(r.origin, "treeShape")
					t.truthy(r.flags.treeTravel, "tree pace")
					local start = reg:pointAt(r, 0)
					local nearest, nd = 0, math.huge
					for i, s in samples do
						local dd = math.sqrt((s.x - start.x) ^ 2 + (s.y - start.y) ^ 2 + (s.z - start.z) ^ 2)
						if dd < nd then
							nearest, nd = i, dd
						end
					end
					t.truthy(nd < 1e-3, `{r.name}: leaves the trunk {nd} studs off its sample`)
					local fork = rail.graph:forkOf(r.id)
					t.truthy(fork ~= nil, `{r.name}: a canopy fork`)
					if fork then
						t.eq(fork.trunk, tree.trunk)
						t.near(fork.t, (nearest - 1) / (#samples - 1), 1e-9)
						t.near(fork.height, samples[nearest].y, 1e-6)
						t.near(fork.origin.y, start.y, 1e-6)
						local ahead = reg:pointAt(r, TreeShapes.C.forkOut)
						local ox, oz = ahead.x - start.x, ahead.z - start.z
						local l = math.sqrt(ox * ox + oz * oz)
						t.near(fork.outward.x, ox / l, 1e-6)
						t.near(fork.outward.z, oz / l, 1e-6)
						-- standing on the trunk at the fork, A/D sees it
						local near = Motion.nearbyForks(rail :: any, trunk, fork.t)
						t.truthy(table.find(near, fork) ~= nil, `{r.name}: offered at its height`)
					end
					-- a smooth curve: its arc length is its length, no kink, nothing steeper than the harvest's boughs
					local curve = reg:curve(r)
					t.near(r.length, curve:getLength(), 1e-3)
					t.eq(r.sampleCount, Curve.sampleSteps(r.length / Units.STUDS_PER_UNIT) + 1)
					local pts = curve:getSpacedPoints(80)
					for i = 2, #pts do
						local a, c = pts[i - 1], pts[i]
						local h = math.sqrt((c.x - a.x) ^ 2 + (c.z - a.z) ^ 2)
						local slope = math.deg(math.atan2(math.abs(c.y - a.y), h))
						t.truthy(slope <= TreeShapes.C.maxSlope, `{r.name}: {slope} degrees`)
						if i > 2 then
							local p = pts[i - 2]
							local u = { a.x - p.x, a.y - p.y, a.z - p.z }
							local v = { c.x - a.x, c.y - a.y, c.z - a.z }
							local lu = math.sqrt(u[1] ^ 2 + u[2] ^ 2 + u[3] ^ 2)
							local lv = math.sqrt(v[1] ^ 2 + v[2] ^ 2 + v[3] ^ 2)
							local turn = math.deg(
								math.acos(math.clamp((u[1] * v[1] + u[2] * v[2] + u[3] * v[3]) / (lu * lv), -1, 1))
							)
							t.truthy(turn < 15, `{r.name}: a kink of {turn} degrees`)
						end
					end
				end
			end
			t.truthy(n >= 40, `{n} grown boughs`)
		end
	)

	t.test(
		"branches at several heights: three or more levels, the lowest near the ground; big trees spread wider",
		function()
			for _, tree in trees("reshaped") do
				local trunk = reg:get(tree.trunk) :: Registry.Route
				local foot = reg:foot(trunk)
				local heights: { number } = {}
				for _, f in rail.graph:forks(tree.trunk) do
					table.insert(heights, f.height - foot.y)
				end
				table.sort(heights)
				-- levels: fork heights more than 3 studs apart
				local levels, last = 0, -math.huge
				for _, h in heights do
					if h - last > 3 then
						levels += 1
						last = h
					end
				end
				t.truthy(levels >= 3, `{tree.label}: {levels} levels`)
				t.truthy(heights[1] <= LOW_START, `{tree.label}: lowest bough {heights[1]} studs up`)
				t.truthy(
					heights[#heights] - heights[1] >= 12,
					`{tree.label}: boughs over {heights[#heights] - heights[1]}`
				)
				-- the grown boughs themselves leave at different heights, never one point
				local starts: { [number]: boolean } = {}
				local tiers: { [string]: number } = {}
				for _, b in tree.boughs do
					starts[math.floor(b.at / 2)] = true
					tiers[b.tier] = (tiers[b.tier] or 0) + 1
				end
				local distinct = 0
				for _ in starts do
					distinct += 1
				end
				t.eq(distinct, #tree.boughs, `{tree.label}: two grown boughs leave at one height`)
				t.truthy((tiers.low or 0) >= 2 and (tiers.mid or 0) >= 1, `{tree.label}: low and mid boughs`)
				if specOf[tree.trunk].big then
					local function reach(ids: { number }): number
						local m = 0
						for _, id in ids do
							for _, s in reg:samples(reg:get(id) :: any) do
								m = math.max(m, level(s, foot))
							end
						end
						return m
					end
					local before = {}
					for _, f in harvestForks[tree.trunk].forks do
						table.insert(before, f.branch)
					end
					local was, now = reach(before), reach(tree.routes)
					t.truthy(now >= 1.15 * was, `{tree.label}: spread {was} -> {now}`)
				end
			end
		end
	)

	-- the real motor on the town's routes and ground (no walls: what is tested is the routes)
	local stand = Units.st(0.18)
	local world: SquirrelMotor.World = {
		registry = rail.registry,
		index = rail.index,
		graph = rail.graph,
		groundAt = function(x: number, z: number, _refY: number): number
			return Height.at(x, z) + stand
		end,
		blocked = nil,
		clamp = { minX = -1e5, maxX = 1e5, minZ = -1e5, maxZ = 1e5 },
	}
	local function lowest(tree: any): any
		local best = nil
		for _, b in tree.boughs do
			if b.tier == "low" and (best == nil or b.at < best.at) then
				best = b
			end
		end
		return best
	end

	t.test(
		"the lower boughs from the ground: climb the trunk, A/D picks the bough, W takes it and runs it evenly",
		function()
			for _, tree in trees("reshaped") do
				local low = lowest(tree)
				local trunk = reg:get(tree.trunk) :: Registry.Route
				local bough = reg:get(low.route) :: Registry.Route
				local fork = rail.graph:forkOf(bough.id) :: any
				local foot = reg:foot(trunk)
				-- the camera looks so that the bough heads off to the right
				local yaw = math.atan2(-fork.outward.z, fork.outward.x) -- right = (cos yaw, -sin yaw)
				local rx, rz = Motion.cameraRightXZ(yaw)
				t.truthy(rx * fork.outward.x + rz * fork.outward.z > 0.99, "camera right along the bough")
				local fx, fz = Motion.cameraForwardXZ(yaw)
				local s = SquirrelMotor.new(foot.x - fx * 4, world.groundAt(foot.x, foot.z, 0), foot.z - fz * 4)
				local inp = SquirrelMotor.idleInput(yaw)
				inp.fw = 1
				local onTrunk = false
				for _ = 1, 240 do
					SquirrelMotor.step(s, inp, 1 / 60, world)
					if s.routeId == trunk.id then
						onTrunk = true
						break
					end
				end
				t.truthy(onTrunk, `{tree.label}: walked onto the trunk`)
				-- A/D (right) until the low bough is the one picked
				for _ = 1, 8 do
					if s.pendingFork == bough.id then
						break
					end
					inp.choose = 1
					SquirrelMotor.step(s, inp, 1 / 60, world)
					inp.choose = 0
				end
				t.eq(s.pendingFork, bough.id, `{tree.label}: A/D picks the low bough`)
				local taken = false
				for _ = 1, 600 do
					local _, events = SquirrelMotor.step(s, inp, 1 / 60, world)
					for _, e in events do
						if e.kind == "forkTaken" then
							taken = true
						end
					end
					if taken then
						break
					end
				end
				t.truthy(taken, `{tree.label}: holding W takes it`)
				t.eq(s.routeId, bough.id)
				-- on along it to the tip: every frame a short even step on the bough
				local px, py, pz = s.x, s.y, s.z
				local most = 0
				local ended = false
				for _ = 1, 600 do
					local _, events = SquirrelMotor.step(s, inp, 1 / 60, world)
					t.eq(s.routeId, bough.id, `{tree.label}: stays on the bough`)
					most = math.max(most, math.sqrt((s.x - px) ^ 2 + (s.y - py) ^ 2 + (s.z - pz) ^ 2))
					px, py, pz = s.x, s.y, s.z
					for _, e in events do
						if e.kind == "railEnd" then
							ended = true
						end
					end
					if ended then
						break
					end
				end
				t.truthy(ended and s.railT > 0.99, `{tree.label}: ran to the tip ({s.railT})`)
				t.truthy(most < 0.6, `{tree.label}: the largest step in a frame {most} studs`)
			end
		end
	)

	t.test("the lower boughs from a leap: off the lawn in toward the trunk, E at the top catches the bough", function()
		local apex = SquirrelMotor.leapApex()
		local vx, vy, vz = SquirrelMotor.jumpVelocity(0, false, false)
		local carry = math.sqrt(vx * vx + vz * vz) * (2 * apex / vy) -- level distance to the top of a leap
		local frames = math.floor(2 * apex / vy * 60 + 0.5)
		t.truthy(apex > 6, "a leap rises")
		for _, tree in trees("reshaped") do
			local bough = reg:get(lowest(tree).route) :: Registry.Route
			local fork = rail.graph:forkOf(bough.id) :: any
			local p = reg:pointAt(bough, 0.6)
			local g = world.groundAt(p.x, p.z, p.y)
			t.truthy(p.y - g <= apex + Motion.C.airGrab - 1, `{tree.label}: {p.y - g} studs up`)
			-- a run in toward the trunk: the leap's top falls under the bough's middle
			local dx, dz = -fork.outward.x, -fork.outward.z
			local x0, z0 = p.x - dx * carry, p.z - dz * carry
			local s = SquirrelMotor.new(x0, world.groundAt(x0, z0, p.y), z0)
			s.yaw = math.atan2(dx, dz)
			local inp = SquirrelMotor.idleInput(math.atan2(-dx, -dz))
			inp.leap = true
			SquirrelMotor.step(s, inp, 1 / 60, world)
			inp.leap = false
			for _ = 2, frames do
				SquirrelMotor.step(s, inp, 1 / 60, world)
			end
			t.eq(s.routeId, nil, `{tree.label}: in the air`)
			inp.grab = true
			SquirrelMotor.step(s, inp, 1 / 60, world)
			t.eq(s.routeId, bough.id, `{tree.label}: E in the air takes the low bough`)
		end
	end)

	t.test(
		"nothing in the way: trunks off paving, boughs out of buildings and high over streets, clear of routes",
		function()
			local clear = TreeClear.new(d)
			-- (a D34 nook, hangout or spur leaves a bough from its own line: Shared/World/BranchNooks keeps it clear of the rest)
			local nookOff: { [number]: number } = {}
			for _, p in (d:module("BranchNooks") :: any).places or {} do
				nookOff[p.route] = p.parent
			end
			local others: { { x: number, y: number, z: number, id: number } } = {}
			local mine: { [number]: number } = {} -- route -> its tree's trunk
			for _, tree in compiled.trees do
				for _, id in tree.routes do
					mine[id] = tree.trunk
				end
				mine[tree.trunk] = tree.trunk
			end
			for _, r in reg:all() do
				if r.enclosure == nil then
					for _, s in reg:samples(r) do
						table.insert(others, { x = s.x, y = s.y, z = s.z, id = r.id })
					end
				end
			end
			for _, tree in trees("planted") do
				local foot = reg:foot(reg:get(tree.trunk) :: any)
				t.eq(clear:paved(foot.x, foot.z, 6), nil, `{tree.label}: on paving`)
				t.eq(clear:lotAt(foot.x, foot.z, 4), nil, `{tree.label}: in a lot`)
				local skip = {}
				for _, id in tree.routes do
					skip[id] = true
				end
				local _, gap = clear:nearestTrunk(foot.x, foot.z, skip)
				t.truthy(gap >= 40, `{tree.label}: {gap} studs from another trunk or pole`)
			end
			for _, tree in compiled.trees do
				local foot = reg:foot(reg:get(tree.trunk) :: any)
				for _, id in tree.routes do
					local r = reg:get(id) :: Registry.Route
					if r.kind ~= "trunk" then
						for _, p in reg:samples(r) do
							local g = Height.at(p.x, p.z)
							local out = level(p, foot)
							t.eq(clear:boxAt(p.x, p.y, p.z, 2), nil, `{r.name}: in a building`)
							if out > 4 then
								t.truthy(p.y - g >= OVER_LAWN, `{r.name}: {p.y - g} studs over the ground`)
								if clear:paved(p.x, p.z, 1) then
									t.truthy(p.y - g >= OVER_PAVING, `{r.name}: {p.y - g} studs over paving`)
								end
							end
							-- a grown bough passes no other route (a planted copy is its source's shape)
							if tree.kind == "reshaped" and out > 4 then
								for _, o in others do
									if o.id ~= id and o.id ~= tree.trunk and nookOff[o.id] ~= id then
										local dd = (o.x - p.x) ^ 2 + (o.y - p.y) ^ 2 + (o.z - p.z) ^ 2
										if dd < CLEAR_OF_ROUTES * CLEAR_OF_ROUTES then
											t.truthy(false, `{r.name} passes route {o.id} at {math.sqrt(dd)} studs`)
										end
									end
								end
							end
						end
					end
				end
			end
		end
	)

	t.test("the planted trees are their sources moved: routes, forks and art at the new pivot", function()
		local art: { [number]: any } = {}
		for _, a in require("../../generated/TreeArt") :: any do
			art[a.trunkRoute] = a
		end
		local nextArt: { [number]: any } = {}
		for _, a in require("../../generated/TreeArtNext") :: any do
			nextArt[a.trunkRoute] = a
		end
		for _, tree in trees("planted") do
			local src = reg:get(tree.source) :: Registry.Route
			local copy = reg:get(tree.trunk) :: Registry.Route
			local off = tree.offset
			for i, p in src.points do
				t.near(copy.points[i].x, p.x + off[1], 1e-3)
				t.near(copy.points[i].y, p.y + off[2], 1e-3)
				t.near(copy.points[i].z, p.z + off[3], 1e-3)
			end
			-- it stands on the ground as its source does
			local sf, cf = reg:foot(src), reg:foot(copy)
			t.near(cf.y - Height.at(cf.x, cf.z), sf.y - Height.at(sf.x, sf.z), 0.05)
			local srcForks = rail.graph:forks(src.id)
			local forks = rail.graph:forks(copy.id)
			t.eq(#forks, #srcForks)
			t.eq(#tree.routes, 1 + #srcForks)
			for _, f in forks do
				t.truthy(table.find(tree.routes, f.branch) ~= nil)
			end
			-- the source's meshes at the copy's pivot, covering every route of the copy
			local a, sa = art[copy.id], art[src.id]
			t.truthy(a and sa, `{tree.label}: baked art`)
			t.near(a.pivot[1], sa.pivot[1] + off[1], 1e-6)
			t.near(a.pivot[2], sa.pivot[2] + off[2], 1e-6)
			t.near(a.pivot[3], sa.pivot[3] + off[3], 1e-6)
			t.eq(#a.routes, #tree.routes)
			local n, sn = nextArt[copy.id], nextArt[src.id]
			t.truthy(n and sn and n.assetId == sn.assetId, `{tree.label}: the source's uploaded Model`)
			t.near(n.pivot[1], sn.pivot[1] + off[1], 1e-6)
			t.eq(#n.covers, #tree.routes)
		end
	end)

	t.test(
		"the ten reshaped trees' rebuilt models (grown boughs in the bark) wait in data/art/trees_v2.json",
		function()
			local v2 = serde.decode("json", fs.readFile("data/art/trees_v2.json"))
			local byTrunk: { [number]: any } = {}
			for _, rec in v2.trees do
				byTrunk[rec.trunkRoute] = rec
			end
			for _, tree in trees("reshaped") do
				local rec = byTrunk[tree.trunk]
				-- not uploaded yet: the live Model stays and the rebuilt one is "pending" (tools/blender/trees publish.py
				-- --merge); once uploaded, the record is the rebuilt Model's and lists the grown boughs among its routes
				local m = if rec.pending then rec.pending else rec
				for _, id in tree.routes do
					t.truthy(table.find(m.routes, id) ~= nil, `{tree.label}: the model is built round bough {id}`)
				end
				t.eq(m.checks.promisesBroken, 0, `{tree.label}: every promise kept`)
				t.truthy(m.tris.bark <= 8000 and m.tris.leaves <= 6000, `{tree.label}: within the tree budgets`)
			end
		end
	)

	t.test("budgets: the town under 27,000 parts; the grown boughs' stand-ins and the planted trees' cost", function()
		local plans = Bake.plans(Bake.data())
		local total, grownParts, plantedParts = 0, 0, 0
		local planted: { [string]: boolean } = {}
		for _, tree in trees("planted") do
			planted[`Tree_{tree.trunk}`] = true
		end
		for _, p in plans do
			total += #p.parts
			if p.kind == "props" and p.category == "tree" then
				for _, s in p.parts do
					if s.attrs and s.attrs.Grown then
						grownParts += 1
					end
				end
				if planted[p.id] then
					plantedParts += #p.parts
				end
			end
		end
		local grown = 0
		for _, tree in trees("reshaped") do
			grown += #tree.boughs
		end
		print(
			`      town {total} parts; {grown} grown boughs drawn in {grownParts} parts; three planted trees {plantedParts}`
		)
		t.truthy(total <= 27000, `part budget {total}`)
		t.truthy(grownParts <= 16 * grown, `stand-ins {grownParts}`)
		t.truthy(plantedParts <= 3 * 70, `planted {plantedParts}`)
		-- a planted tree draws its source's meshes: its triangles are its source's (data/art/trees_v2.json)
		local v2 = serde.decode("json", fs.readFile("data/art/trees_v2.json"))
		local tris = 0
		for _, tree in trees("planted") do
			for _, rec in v2.trees do
				if rec.trunkRoute == tree.source then
					tris += rec.tris.total
				end
			end
		end
		print(`      the planted trees add {tris} triangles (their sources' v2 Models)`)
		t.truthy(tris > 0 and tris <= 3 * 18000, `{tris}`)
	end)
end
