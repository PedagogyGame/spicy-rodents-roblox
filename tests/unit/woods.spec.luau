--!strict
-- The D34 woods and the D35 climbs (data/woods.json, data/woods_placed.json; Shared/World/TreeShapes WOODS AND CLIMBS;
-- WorldGen/WoodsPlan; Server/Assets/WoodsArt): the owner's "add even more of the tall tree models, even taller ...
-- a large scattered introduction of pine trees and other nut trees, making the map have more trees!" and "make all
-- trees climbable".
--   * what grows: three giants, four conifers, six nut trees (walnut, hazel, chestnut, hickory, two oaks); a large
--     increase (at least 250 woods trees), denser at the edges than in the town; every tree that had no route (the
--     Lookout Hill conifers, the sky lift's hedgerow oaks and orchard) has a trunk route now;
--   * where: every woods tree passes WorldGen/WoodsPlan.check against the town as baked (paving, lots, buildings, doors,
--     street gear, wires and the cable, the route trees' crowns, nut spots, zones, the river, the beach, slopes) and
--     stands on the ground; no two closer than the thinnest grove allows;
--   * the routes: a woods tree's routes are its kind's template turned, scaled and stood at its place (the same sample
--     counts: every fork on a trunk sample); every bough leaves a trunk sample with the harvest's fork rule, found where
--     the motor looks; smooth, no stretch steeper than TreeShapes.C.maxSlope; high enough over the ground; out of
--     buildings;
--   * the real motor climbs every new trunk from the ground to its top and runs every new bough from its fork to its
--     tip, and the server's envelope (SquirrelMotor.envelope, MoveValidator's frame judge) rejects none of its frames;
--   * the cost: route counts and samples; the woods add no part to the town bake (their parts are WoodsArt's, 3 a tree).
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local Bake = require("@worldgen/Bake")
local Curve = require("@shared/Routes/Curve")
local Height = require("@shared/World/Height")
local Motion = require("@shared/Routes/Motion")
local RailWorld = require("@shared/Movement/RailWorld")
local Registry = require("@shared/Routes/Registry")
local SquirrelMotor = require("@shared/Movement/SquirrelMotor")
local TreeClear = require("@tests/lib/TreeClear")
local TreeShapes = require("@shared/World/TreeShapes")
local Units = require("@shared/Config/Units")
local WoodsPlan = require("@worldgen/WoodsPlan")
local WoodsWorld = require("@tests/lib/WoodsWorld")

local OVER_LAWN = 6.5 -- studs: a bough past 4 studs from its trunk is this high over the ground (a walker passes)
local GIANT_OVER = 175 * 1.3 -- the town's tallest tree today (HIGHLAND ELM's model) and the owner's "even taller"

return function(t)
	local ctx = WoodsWorld.new()
	local d = ctx.data
	local reg = d:routes()
	local compiled = d:module("TreeShapes") :: any
	local woods = compiled.woods
	local doc = serde.decode("json", fs.readFile("data/woods.json"))
	local placed = serde.decode("json", fs.readFile("data/woods_placed.json"))
	local expanded = d:woods()
	local rail = RailWorld.build(d)

	t.test("what grows: three giants, four conifers, six nut trees; a large increase, denser at the edges", function()
		local fam: { [string]: number } = {}
		for _, k in doc.kinds do
			fam[k.family] = (fam[k.family] or 0) + 1
		end
		t.eq(fam.giant, 3)
		t.eq(fam.pine, 4)
		t.eq(fam.nut, 6)
		t.truthy(#woods.trees >= 250, `{#woods.trees} woods trees`)
		t.eq(#woods.trees, placed.count)
		local per: { [string]: number } = {}
		for _, tr in woods.trees do
			per[doc.kinds[tr.kind].family] = (per[doc.kinds[tr.kind].family] or 0) + 1
		end
		t.eq(per.giant, 3)
		t.truthy(per.pine >= 100 and per.nut >= 100, `pines {per.pine}, nut trees {per.nut}`)
		-- every kind stands somewhere
		local seen: { [string]: boolean } = {}
		for _, tr in woods.trees do
			seen[tr.kind] = true
		end
		for id in doc.kinds do
			t.truthy(seen[id], `{id} is planted`)
		end
		-- denser at the edges: trees per square kilostud in the edge groves against the town's
		local area: { [string]: number } = {}
		for _, g in doc.groves do
			if g.rect then
				area[g.id] = (g.rect[2] - g.rect[1]) * (g.rect[4] - g.rect[3]) / 1e6
			end
		end
		local function density(id: string): number
			return placed.groves[id] / area[id]
		end
		t.truthy(density("ridge") > 2 * density("town"), "the ridge's pines are a grove")
		-- the trees that had no route: the Lookout Hill conifers, the hedgerow oaks, the orchard
		local labels: { [string]: number } = {}
		for _, c in woods.climbs do
			labels[c.label] = (labels[c.label] or 0) + 1
		end
		t.eq(labels["LOOKOUT CONIFER"], 32)
		t.eq(labels["HEDGEROW OAK"], 5)
		t.eq(labels["ORCHARD APPLE"], 12)
		print(
			`      woods {#woods.trees} (giants {per.giant}, pines {per.pine}, nut trees {per.nut}); climbs {#woods.climbs}`
		)
	end)

	t.test("the giants' models are taller than the tallest tree today by 1.3 or more", function()
		if not fs.isFile("data/art/woods.json") then
			return
		end
		local art = serde.decode("json", fs.readFile("data/art/woods.json"))
		local n = 0
		for _, k in art.kinds do
			if k.family == "giant" then
				n += 1
				t.truthy(k.heightStuds >= GIANT_OVER, `{k.label}: {k.heightStuds} studs`)
			end
		end
		t.eq(n, 3)
	end)

	t.test("where: every woods tree clear of the town as baked (WorldGen/WoodsPlan), on the ground", function()
		local others: { { number } } = {}
		local thinnest = math.huge
		for _, g in doc.groves do
			if g.share then
				thinnest = math.min(thinnest, g.share)
			end
		end
		t.truthy(thinnest >= WoodsPlan.C.WOODS_SHARE - 1e-9, "no grove denser than the rule")
		for i, tr in woods.trees do
			local k = doc.kinds[tr.kind]
			local crown = k.crown * tr.scale
			-- (a lone giant keeps a quarter more room)
			local why = WoodsPlan.check(ctx.world, tr.x, tr.z, if k.family == "giant" then crown * 1.25 else crown, nil)
			t.eq(why, nil, `woods tree {i} ({tr.kind}) at {tr.x}, {tr.z}`)
			t.near(tr.y, Height.at(tr.x, tr.z), 0.02)
			for _, o in others do
				local need = math.max(WoodsPlan.C.WOODS_MIN, thinnest * (o[3] + crown))
				local gap = math.sqrt((o[1] - tr.x) ^ 2 + (o[2] - tr.z) ^ 2)
				t.truthy(gap >= need - 0.05, `woods tree {i} is {gap} from another`)
			end
			table.insert(others, { tr.x, tr.z, crown })
		end
	end)

	t.test(
		"the routes: the template moved; forks on trunk samples by the harvest's rule; smooth; over the ground",
		function()
			local clear = TreeClear.new(d)
			local n, boughs = 0, 0
			for _, tree in expanded.trees do
				n += 1
				local trunk = reg:get(tree.trunk) :: Registry.Route
				t.eq(trunk.kind, "trunk")
				t.truthy(trunk.flags.treeTravel)
				local foot = reg:foot(trunk)
				t.near(foot.y - Height.at(foot.x, foot.z), TreeShapes.WOODS.footLift, 0.05)
				local samples = reg:samples(trunk)
				for _, id in tree.routes do
					local r = reg:get(id) :: Registry.Route
					if r.kind == "branch" then
						boughs += 1
						local start = reg:pointAt(r, 0)
						local nd = math.huge
						local nearest = 0
						for i, s in samples do
							local dd = math.sqrt((s.x - start.x) ^ 2 + (s.y - start.y) ^ 2 + (s.z - start.z) ^ 2)
							if dd < nd then
								nearest, nd = i, dd
							end
						end
						t.truthy(nd < 2e-3, `{r.name}: leaves the trunk {nd} off its sample`)
						local fork = rail.graph:forkOf(r.id)
						t.truthy(fork ~= nil, `{r.name}: a canopy fork`)
						if fork then
							t.eq(fork.trunk, tree.trunk)
							t.near(fork.t, (nearest - 1) / (#samples - 1), 1e-6)
							local near = Motion.nearbyForks(rail :: any, trunk, fork.t)
							t.truthy(table.find(near, fork) ~= nil, `{r.name}: offered at its height`)
						end
						local pts = reg:curve(r):getSpacedPoints(40)
						for i = 2, #pts do
							local a, c = pts[i - 1], pts[i]
							local h = math.sqrt((c.x - a.x) ^ 2 + (c.z - a.z) ^ 2)
							t.truthy(
								math.deg(math.atan2(math.abs(c.y - a.y), h)) <= TreeShapes.C.maxSlope,
								`{r.name}: too steep`
							)
						end
						for _, p in reg:samples(r) do
							local out = math.sqrt((p.x - foot.x) ^ 2 + (p.z - foot.z) ^ 2)
							if out > 4 and not tree.climb then
								t.truthy(
									p.y - Height.at(p.x, p.z) >= OVER_LAWN,
									`{r.name}: {p.y - Height.at(p.x, p.z)} over the ground`
								)
							end
							t.eq(clear:boxAt(p.x, p.y, p.z, 1), nil, `{r.name}: in a building`)
						end
					end
				end
			end
			t.eq(n, #woods.trees + #woods.climbs)
			print(`      {n} trees climbable on {#expanded.routes} routes ({boughs} boughs)`)
		end
	)

	-- the real motor on the town's routes and ground (the woods' trunks as walls do not matter on a rail)
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
	local DT = 1 / 60

	-- one frame, judged by the server's envelope; returns the events
	local rejected = 0
	local frames = 0
	local function step(s: any, inp: any): { any }
		local before = SquirrelMotor.clone(s)
		local _, events = SquirrelMotor.step(s, inp, DT, world)
		frames += 1
		local v = SquirrelMotor.envelope(before, s, DT, world, false)
		if #v > 0 then
			rejected += 1
		end
		return events
	end

	t.test("the real motor climbs every new trunk and runs every new bough; the envelope rejects no frame", function()
		local trunks, runs, failed = 0, 0, {}
		for _, tree in expanded.trees do
			local trunk = reg:get(tree.trunk) :: Registry.Route
			local foot = reg:foot(trunk)
			local forks = rail.graph:forks(trunk.id)
			-- walk in from four studs off, toward the trunk (from another side if a neighbour's trunk or a slope is in
			-- the way of the first)
			local s, inp
			local on = false
			for k = 0, 3 do
				local yaw0 = 0.7 + tree.index + k * math.pi / 2
				local fx, fz = Motion.cameraForwardXZ(yaw0)
				s = SquirrelMotor.new(
					foot.x - fx * 4,
					world.groundAt(foot.x - fx * 4, foot.z - fz * 4, 0),
					foot.z - fz * 4
				)
				inp = SquirrelMotor.idleInput(yaw0)
				inp.fw = 1
				for _ = 1, 240 do
					step(s, inp)
					if s.routeId == trunk.id then
						on = true
						break
					end
				end
				if on then
					break
				end
			end
			if not on then
				table.insert(failed, `{tree.label} {tree.index}: never got on its trunk`)
				continue
			end
			-- up the trunk to its top, keeping a copy of the climb just under every fork
			local snaps: { [number]: any } = {}
			local top = false
			for _ = 1, 1800 do
				local events = step(s, inp)
				if s.routeId ~= trunk.id then
					break
				end
				for _, f in forks do
					if not snaps[f.branch] and s.railT >= f.t - 0.03 and s.railT < f.t then
						snaps[f.branch] = SquirrelMotor.clone(s)
					end
				end
				for _, e in events do
					if e.kind == "railEnd" then
						top = true
					end
				end
				if top or s.railT > 0.995 then
					top = true
					break
				end
			end
			if not top then
				table.insert(failed, `{tree.label} {tree.index}: did not climb to the top ({s.railT})`)
				continue
			end
			trunks += 1
			-- every bough from just under its fork: A/D picks it, W takes it, on to its tip
			for _, f in forks do
				local b = snaps[f.branch]
				if not b then
					table.insert(failed, `{tree.label} {tree.index}: passed fork {f.branch} unseen`)
					continue
				end
				local yaw = math.atan2(-f.outward.z, f.outward.x)
				local bi = SquirrelMotor.idleInput(yaw)
				-- (standing on the trunk while A/D cycles, then W)
				bi.fw = 0
				local picked = false
				for _ = 1, 30 do
					if b.pendingFork == f.branch then
						picked = true
						break
					end
					bi.choose = 1
					step(b, bi)
					bi.choose = 0
					if b.routeId ~= trunk.id then
						break
					end
				end
				if not picked and b.pendingFork ~= f.branch then
					table.insert(failed, `{tree.label} {tree.index}: A/D did not pick bough {f.branch}`)
					continue
				end
				bi.fw = 1
				local taken, ended = false, false
				for _ = 1, 900 do
					local events = step(b, bi)
					for _, e in events do
						if e.kind == "forkTaken" then
							taken = true
						elseif e.kind == "railEnd" and taken then
							ended = true
						end
					end
					if ended or (taken and b.routeId == f.branch and b.railT > 0.99) then
						ended = true
						break
					end
				end
				if ended and b.routeId == f.branch then
					runs += 1
				else
					table.insert(
						failed,
						`{tree.label} {tree.index}: bough {f.branch} not run (on {b.routeId} at {b.railT})`
					)
				end
			end
		end
		print(`      motor: {trunks} trunks climbed, {runs} boughs run, {frames} frames, {rejected} rejected`)
		t.eq(#failed, 0, table.concat(failed, "; ", 1, math.min(#failed, 8)))
		t.eq(rejected, 0, `{rejected} frames rejected by the envelope`)
		t.eq(trunks, #expanded.trees)
	end)

	t.test("the cost: routes are data; the town bake gains no part", function()
		local plans = Bake.plans(Bake.data())
		local total = 0
		for _, p in plans do
			total += #p.parts
		end
		t.truthy(total <= 27000, `town {total} parts`)
		local samples = 0
		for _, r in expanded.routes do
			samples += r.sampleCount
		end
		-- the compact form: a few kilobytes against a full record per route
		local bytes = #fs.readFile("generated/TreeShapes.luau")
		print(
			`      town bake {total} parts; woods {#expanded.routes} routes, {samples} samples; TreeShapes.luau {bytes} bytes`
		)
		t.truthy(bytes < 200 * 1024, "TreeShapes.luau under the 200 KB chunk size")
		t.truthy(samples < 70000, `{samples} samples`)
		local _ = Curve
	end)

	-- (tests/lib/WoodsWorld configured World/Height with the terrain extensions, as the bake does: put it back for the
	-- specs after this one, which expect the plain ground)
	t.test("leaves World/Height as the specs after it expect (the plain ground)", function()
		Height.configure(nil)
		t.truthy(true)
	end)
end
