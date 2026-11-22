--!strict
-- The D34 branch nooks (Shared/World/BranchNooks, generated/BranchNooks + BranchNookRoutes_NN): the owner's "little
-- nooks in the branches ... a little shift from running over the nodules, but still smooth movement feel and play,
-- the points where the branches are can have stash places off to the side and a little place to hangout, cozy! improve
-- and add branching". Over the compiled data, as every rail user sees it (Shared/Data; Movement/RailWorld):
--   * every climbable tree has them, worked out from its routes alone (a nook with a stash on each, hangouts at the
--     wider forks, spurs off the long boughs); the compiled plan is what the rules give (re-planned here);
--   * every new route leaves a sample of its bough, is smooth and no steeper than the harvest's boughs, stays outside
--     the bark, over the ground, out of the buildings and clear of every other route;
--   * the real SquirrelMotor, every frame judged by the envelope the server's MoveValidator applies, for EVERY new
--     route: from its bough at the junction, E (else A/D, then E) takes it with no jump; W runs it to its end in even
--     steps without leaving it; S runs back to its start; E puts the body back on its bough. Zero violations;
--   * the stash's reach from the cup only, never from the bough or a trunk climber;
--   * the nodules: along every branch's run path, felt as a settle of the drawn body that is gone in 0.15 s and never
--     touches the motor (Shared/Movement/BranchFeel).
local fs = require("@lune/fs")
local Data = require("@shared/Data")
local BakedWorld = require("@tests/lib/BakedWorld")
local LiveRig = require("@tests/lib/LiveRig")
local ValidatorWorld = require("@server/Movement/ValidatorWorld")
local BranchFeel = require("@shared/Movement/BranchFeel")
local BranchNooks = require("@shared/World/BranchNooks")
local Curve = require("@shared/Routes/Curve")
local Height = require("@shared/World/Height")
local Motion = require("@shared/Routes/Motion")
local RailWorld = require("@shared/Movement/RailWorld")
local Registry = require("@shared/Routes/Registry")
local SquirrelMotor = require("@shared/Movement/SquirrelMotor")
local TreeClear = require("@tests/lib/TreeClear")
local Units = require("@shared/Config/Units")

local C = BranchNooks.C

return function(t)
	local d = Data.default()
	local reg = d:routes()
	local compiled = d:module("BranchNooks") :: any
	local nooks = BranchNooks.new(compiled)
	local rail = RailWorld.build(d)
	local routeRecs = d:module("BranchNookRoutes") :: any
	local byKind: { [string]: { BranchNooks.Place } } = { nook = {}, hangout = {}, spur = {} }
	for _, p in nooks.places do
		table.insert(byKind[p.kind], p)
	end

	t.test(
		"every climbable tree: a nook with a stash, hangouts at the wider forks, spurs; the plan is the rules'",
		function()
			local climbable = 0
			local have: { [number]: { nook: number, hangout: number, spur: number, stash: number } } = {}
			for _, p in nooks.places do
				local h = have[p.trunk] or { nook = 0, hangout = 0, spur = 0, stash = 0 }
				have[p.trunk] = h
				h[p.kind] += 1
				if p.stash then
					h.stash += 1
				end
			end
			for _, rec in d:forks() do
				local trunk = reg:get(rec.trunk)
				if trunk and trunk.kind == "trunk" then
					climbable += 1
					local h = have[rec.trunk]
					t.truthy(h ~= nil and h.nook >= 1 and h.stash >= 1, `{trunk.name}: a nook with a stash`)
				end
			end
			t.truthy(climbable >= 95, `{climbable} climbable trees`)
			t.eq(#compiled.trees, climbable)
			t.truthy(#byKind.hangout >= climbable / 2, `{#byKind.hangout} hangouts`)
			t.truthy(#byKind.spur >= climbable, `{#byKind.spur} spurs`)
			for _, p in byKind.nook do
				t.truthy(p.stash ~= nil, `nook {p.route}: its stash`)
			end
			t.eq(#routeRecs, #nooks.places)
			print(
				`      {climbable} trees: {#byKind.nook} nooks (each a stash), {#byKind.hangout} hangouts, {#byKind.spur} spurs; {#routeRecs} routes`
			)
			-- the compiled plan is what the rules make of the routes before it (the same everywhere: seeded per trunk), over
			-- the records as compiled (an enclosed run's record is its own module's)
			local recs: { any } = table.clone(d:module("Routes"))
			for _, name in { "Attractions", "Sewers", "HollowTrees", "TreeShapes" } do
				local m = d:module(name) :: any
				for _, r in (m and m.routes) or {} do
					table.insert(recs, r)
				end
			end
			local clear = TreeClear.new(d)
			local again = BranchNooks.plan(
				Registry.fromRecords(recs) :: any,
				d:forks(),
				Height.at,
				function(x: number, y: number, z: number): boolean
					return clear:boxAt(x, y, z, C.buildingPad) ~= nil
				end
			)
			t.eq(#again.routes, #routeRecs)
			for i, r in again.routes do
				local c = routeRecs[i]
				t.eq(r.id, c.id)
				t.eq(r.name, c.name)
				for k, p in r.points do
					for j = 1, 3 do
						t.near(p[j], c.points[k][j], 1e-6)
					end
				end
			end
		end
	)

	t.test("every new route leaves a sample of its bough; smooth, outside the bark, over the ground, clear", function()
		local clear = TreeClear.new(d)
		local hash: { [string]: { { x: number, y: number, z: number, id: number } } } = {}
		local function key(x: number, y: number, z: number): string
			return `{math.floor(x / 4)},{math.floor(y / 4)},{math.floor(z / 4)}`
		end
		for _, r in reg:all() do
			for _, s in reg:samples(r) do
				local k = key(s.x, s.y, s.z)
				hash[k] = hash[k] or {}
				table.insert(hash[k], { x = s.x, y = s.y, z = s.z, id = r.id })
			end
		end
		local function nearest(p: any, skip: { [number]: boolean }): (number, number?)
			local best, bid = math.huge, nil
			local cx, cy, cz = math.floor(p.x / 4), math.floor(p.y / 4), math.floor(p.z / 4)
			for dx = -1, 1 do
				for dy = -1, 1 do
					for dz = -1, 1 do
						for _, s in hash[`{cx + dx},{cy + dy},{cz + dz}`] or {} do
							if not skip[s.id] then
								local dd = math.sqrt((s.x - p.x) ^ 2 + (s.y - p.y) ^ 2 + (s.z - p.z) ^ 2)
								if dd < best then
									best, bid = dd, s.id
								end
							end
						end
					end
				end
			end
			return best, bid
		end
		local worstClear, worstSlope, worstKink = math.huge, 0, 0
		for _, p in nooks.places do
			local r = reg:get(p.route) :: Registry.Route
			local bough = reg:get(p.parent) :: Registry.Route
			local trunk = reg:get(p.trunk) :: Registry.Route
			t.eq(r.kind, "branch")
			t.eq(r.origin, "branchNook")
			t.truthy(r.flags.treeTravel, "tree pace")
			t.eq(r.enclosure, nil)
			-- on its bough's own sample (the junction the motor offers)
			local start = reg:pointAt(r, 0)
			local on = math.huge
			for _, s in reg:samples(bough) do
				on = math.min(on, math.sqrt((s.x - start.x) ^ 2 + (s.y - start.y) ^ 2 + (s.z - start.z) ^ 2))
			end
			t.truthy(on < 1e-3, `{r.name}: leaves its bough {on} studs off a sample`)
			local q = reg:pointAt(bough, p.parentT)
			t.truthy(
				math.sqrt((q.x - start.x) ^ 2 + (q.y - start.y) ^ 2 + (q.z - start.z) ^ 2) < 1e-3,
				`{r.name}: parentT`
			)
			t.near(r.length, reg:curve(r):getLength(), 1e-3)
			t.eq(r.sampleCount, Curve.sampleSteps(r.length / Units.STUDS_PER_UNIT) + 1)
			local samples = reg:samples(r)
			local walked = 0
			local trunkSamples = reg:samples(trunk)
			for i, s in samples do
				t.truthy(
					s.y - Height.at(s.x, s.z) >= C.overGround,
					`{r.name}: {s.y - Height.at(s.x, s.z)} over the ground`
				)
				t.eq(clear:boxAt(s.x, s.y, s.z, 1), nil, `{r.name}: in a building`)
				if i > 1 then
					local a = samples[i - 1]
					local h = math.sqrt((s.x - a.x) ^ 2 + (s.z - a.z) ^ 2)
					walked += math.sqrt(h * h + (s.y - a.y) ^ 2)
					local slope = math.deg(math.atan2(math.abs(s.y - a.y), h))
					worstSlope = math.max(worstSlope, slope)
					t.truthy(slope <= C.maxSlope + 0.5, `{r.name}: {slope} degrees`)
				end
				if i > 2 then
					local a, b = samples[i - 2], samples[i - 1]
					local u = { b.x - a.x, b.y - a.y, b.z - a.z }
					local v = { s.x - b.x, s.y - b.y, s.z - b.z }
					local lu = math.sqrt(u[1] ^ 2 + u[2] ^ 2 + u[3] ^ 2)
					local lv = math.sqrt(v[1] ^ 2 + v[2] ^ 2 + v[3] ^ 2)
					local turn =
						math.deg(math.acos(math.clamp((u[1] * v[1] + u[2] * v[2] + u[3] * v[3]) / (lu * lv), -1, 1)))
					worstKink = math.max(worstKink, turn)
					t.truthy(turn < 15, `{r.name}: a kink of {turn} degrees`)
				end
				-- outside the bark at its height
				if s.y <= trunkSamples[#trunkSamples].y + 1 then
					local best, bi = math.huge, 1
					for k, ts in trunkSamples do
						if math.abs(ts.y - s.y) < best then
							best, bi = math.abs(ts.y - s.y), k
						end
					end
					local a = trunkSamples[bi]
					local out = math.sqrt((s.x - a.x) ^ 2 + (s.z - a.z) ^ 2)
					local bark = BranchNooks.barkRadius(trunk, (bi - 1) / (#trunkSamples - 1))
					t.truthy(out >= bark + C.barkPad - 1e-6, `{r.name}: {out} from the axis, bark {bark}`)
				end
				-- every other route but its bough and trunk
				if walked >= C.clearFrom then
					local dd, id = nearest(s, { [r.id] = true, [bough.id] = true, [trunk.id] = true })
					worstClear = math.min(worstClear, dd)
					t.truthy(dd >= C.clear - 1e-6, `{r.name}: {dd} studs from route {id}`)
				end
			end
		end
		print(
			`      the closest any new route comes to another: {math.floor(worstClear * 100) / 100} studs; steepest {math.floor(
				worstSlope
			)} degrees; sharpest bend {math.floor(worstKink * 10) / 10} degrees a sample`
		)
	end)

	-- the real motor on the town's routes and ground (no walls: what is tested is the routes; rails do not test walls)
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
	local function onRail(routeId: number, tt: number, yaw: number): SquirrelMotor.State
		local r = reg:get(routeId) :: Registry.Route
		local p = reg:pointAt(r, tt)
		local s = SquirrelMotor.new(p.x, p.y, p.z)
		s.routeId, s.railT, s.railDir, s.grounded = routeId, tt, 1, false
		s.x, s.y, s.z = p.x, p.y, p.z
		s.yaw = yaw
		return s
	end
	-- the camera looking along a route at t (forward = its level tangent)
	local function along(r: Registry.Route, tt: number, dir: number): number
		local tg = reg:tangentAt(r, math.clamp(tt, 0.002, 0.998))
		return BakedWorld.cameraYawToward(tg.x * dir, tg.z * dir)
	end

	t.test(
		"the real motor on EVERY new route: in from the bough without a jump, out to its end, back, onto the bough",
		function()
			local byE, byChoice, frames, worstStep = 0, 0, 0, 0
			local bad: { string } = {}
			-- one route's run; nil when all is well, else what went wrong
			local function runOne(p: BranchNooks.Place): string?
				local r = reg:get(p.route) :: Registry.Route
				local bough = reg:get(p.parent) :: Registry.Route
				local cam = along(r, 0.05, 1)
				local face = math.atan2(-math.sin(cam), -math.cos(cam))
				local s = onRail(bough.id, p.parentT, face)
				-- in: E alone where the new route is the nearest; else A/D picks it (either way round), then E
				local inTrace = BakedWorld.drive(world, s, 1, function(): SquirrelMotor.Input
					return BakedWorld.keys(cam, { grab = true })
				end, { validator = true })
				if inTrace.violations > 0 then
					return `in: {inTrace.violations} violations`
				end
				if s.routeId == r.id then
					byE += 1
				else
					s = onRail(bough.id, p.parentT, face)
					local picked = false
					for _, side in { 1, -1 } do
						for _ = 1, 6 do
							BakedWorld.drive(world, s, 1, function(): SquirrelMotor.Input
								return BakedWorld.keys(cam, { choose = side })
							end)
							if s.selectedJunction == r.id then
								picked = true
								break
							end
						end
						if picked then
							break
						end
					end
					if not picked then
						return "A/D does not offer it on its bough"
					end
					local tr = BakedWorld.drive(world, s, 1, function(): SquirrelMotor.Input
						return BakedWorld.keys(cam, { grab = true })
					end, { validator = true })
					if tr.violations > 0 or s.routeId ~= r.id then
						return `A/D then E: on {s.routeId}, {tr.violations} violations`
					end
					byChoice += 1
				end
				-- out to its end with W, the camera along it
				local out = BakedWorld.drive(world, s, 60 * 6, function(_f: number, st: SquirrelMotor.State)
					return BakedWorld.keys(along(r, st.railT, 1), { fw = 1 })
				end, {
					validator = true,
					stop = function(st: SquirrelMotor.State): boolean
						return st.routeId ~= r.id or st.railT >= 0.999
					end,
				})
				frames += #out.frames
				worstStep = math.max(worstStep, out.maxStep)
				if out.violations > 0 then
					return `out: {out.violations} violations`
				end
				for _, f in out.frames do
					if f.routeId ~= r.id then
						return `out: left it for {f.routeId}`
					end
				end
				if s.railT < 0.999 then
					return `out: stopped at {s.railT}`
				end
				if out.maxStep >= 0.6 then
					return `out: a step of {out.maxStep} studs`
				end
				-- a few frames pressing on at the end: it stays there (its end leads nowhere)
				BakedWorld.drive(world, s, 20, function(_f: number, st: SquirrelMotor.State)
					return BakedWorld.keys(along(r, st.railT, 1), { fw = 1 })
				end)
				if s.routeId ~= r.id then
					return `its end switched onto {s.routeId}`
				end
				-- back with S to its start
				local back = BakedWorld.drive(world, s, 60 * 6, function(_f: number, st: SquirrelMotor.State)
					return BakedWorld.keys(along(r, st.railT, 1), { fw = -1 })
				end, {
					validator = true,
					stop = function(st: SquirrelMotor.State): boolean
						return st.routeId ~= r.id or st.railT <= 0.001
					end,
				})
				frames += #back.frames
				if back.violations > 0 then
					return `back: {back.violations} violations`
				end
				if s.routeId ~= r.id or s.railT > 0.001 then
					return `back: on {s.routeId} at {s.railT}`
				end
				-- E: onto the bough
				local onto = BakedWorld.drive(world, s, 1, function(): SquirrelMotor.Input
					return BakedWorld.keys(along(r, 0, -1), { grab = true })
				end, { validator = true })
				if onto.violations > 0 or s.routeId ~= bough.id then
					return `E at its start: on {s.routeId}, {onto.violations} violations`
				end
				return nil
			end
			for _, p in nooks.places do
				local why = runOne(p)
				if why then
					table.insert(bad, `{p.kind} {p.route} off {p.parent}: {why}`)
				end
			end
			print(
				`      {#nooks.places} routes run: {byE} taken with E alone, {byChoice} with A/D then E; {frames} frames judged, largest step {math.floor(
					worstStep * 1000
				) / 1000} studs`
			)
			t.eq(#bad, 0, `{#bad}: {table.concat(bad, " | ", 1, math.min(#bad, 12))}`)
		end
	)

	t.test("the live server across the baked town: in, out, back and onto the bough, and Q off one: 0 snaps", function()
		-- the real motor through a 300 ms link with jitter and loss (tests/lib/LiveRig), judged by the server with
		-- enforcement on and the live wall, floor and cover rays over build/Town.rbxm (the trunk and bough colliders), on
		-- a spread of the new routes (every kind, the whole town)
		t.truthy(fs.isFile("build/Town.rbxm"), "build/Town.rbxm (lune run tools/bake/main.luau)")
		Height.configure(d:module("TerrainExtensions"))
		local town = BakedWorld.load("build/Town.rbxm")
		local w = town:motorWorld(d)
		local wall, down, cover = BakedWorld.validatorRays(town)
		local vworld = ValidatorWorld.build(w, { wall = wall, down = down, cover = cover })
		local link = { latency = 0.3, jitter = 0.15, loss = 0.02 }
		local every = math.max(1, math.floor(#nooks.places / 30))
		local runs, drops = 0, 0
		for k = 1, #nooks.places, every do
			local p = nooks.places[k]
			local r = reg:get(p.route) :: Registry.Route
			local bough = reg:get(p.parent) :: Registry.Route
			-- in with E, W out, S back, E onto the bough
			local rig = LiveRig.new({ world = w, vworld = vworld, link = link, seed = 70 + k })
			local start = onRail(bough.id, p.parentT, 0)
			local took = false
			local tookAt = math.huge
			local wasOn = false
			rig:possess(start, function(now: number, st: SquirrelMotor.State): SquirrelMotor.Input
				local on = st.routeId == r.id
				if on and not took then
					took, tookAt = true, now
				end
				-- (E pressed and let go every other frame until the route is taken: a press the hand-off ate is pressed
				-- again)
				local cam = along(r, if on then st.railT else 0.05, 1)
				local since = now - tookAt
				local press = not wasOn
				wasOn = not wasOn
				if not took then
					return BakedWorld.keys(cam, { grab = press })
				elseif since < 1.2 then
					return BakedWorld.keys(cam, { fw = 1 })
				elseif since < 2.6 then
					return BakedWorld.keys(cam, { fw = -1 })
				end
				return BakedWorld.keys(cam, { grab = since > 2.7 and since < 2.73 })
			end)
			rig:run(4.5)
			local res = rig:result()
			for _, v in res.violations do
				print(`      VIOLATION {v}`)
			end
			t.eq(res.snaps, 0, `{r.name}: in, out, back: {LiveRig.describe("run", res)}`)
			t.truthy(took, `{r.name}: E took it`)
			t.truthy(res.visited[r.id], `{r.name}: ran it`)
			runs += 1
			-- Q off it, half way out: down to whatever is under it, and still
			local drop = LiveRig.new({ world = w, vworld = vworld, link = link, seed = 170 + k })
			drop:possess(onRail(r.id, 0.6, 0), function(now: number): SquirrelMotor.Input
				return BakedWorld.keys(math.sin(now) * 2, { drop = now > 0.4 and now < 0.5 })
			end)
			drop:run(4)
			local dr = drop:result()
			t.eq(dr.snaps, 0, `{r.name}: Q off it: {LiveRig.describe("drop", dr)}`)
			drops += 1
		end
		Height.configure(nil)
		print(`      {runs} of the new routes run in and out and {drops} dropped off under the live server: 0 snaps`)
	end)

	t.test(
		"the stash: within reach in the cup only, never from the bough it leaves or a climber on the trunk",
		function()
			for _, p in byKind.nook do
				local r = reg:get(p.route) :: Registry.Route
				local e = reg:pointAt(r, 1)
				t.eq(nooks.stashNear(e.x, e.y, e.z), p, `{r.name}: from the cup`)
				local a = reg:pointAt(r, 0)
				t.truthy(nooks.stashNear(a.x, a.y, a.z) ~= p, `{r.name}: not from its bough`)
				-- a climber on the trunk: the axis at the cup's height
				local trunk = reg:get(p.trunk) :: Registry.Route
				local best, bd = nil, math.huge
				for _, s in reg:samples(trunk) do
					if math.abs(s.y - e.y) < bd then
						best, bd = s, math.abs(s.y - e.y)
					end
				end
				local ax = best :: any
				t.eq(nooks.stashNear(ax.x, ax.y, ax.z), nil, `{r.name}: not from the trunk`)
				-- the knot-hole sits in wood near the cup
				local h = p.stash :: { number }
				local dd = math.sqrt((h[1] - e.x) ^ 2 + (h[2] - e.y - C.lift) ^ 2 + (h[3] - e.z) ^ 2)
				t.truthy(dd <= 3.5, `{r.name}: its knot-hole {dd} studs from the cup`)
				-- where it may sit: the cup's last stretch
				t.eq(nooks.seatAt(r.id, 0.95), p)
				t.eq(nooks.seatAt(r.id, 0.1), nil)
			end
		end
	)

	t.test(
		"the nodules: along every branch's run path; a quick settle of the drawn body, the motor untouched",
		function()
			local boughs, knots = 0, 0
			for _, r in reg:all() do
				if r.kind == "branch" and r.enclosure == nil then
					local n = BranchNooks.nodules(r)
					local name = r.name
					if string.sub(name, 1, 5) == "nook " or string.sub(name, 1, 8) == "hangout " then
						t.eq(#n, 0, `{name}: a cup or a ledge has no knots`)
						continue
					end
					boughs += 1
					knots += #n
					local last = -math.huge
					for _, s in n do
						t.truthy(s >= C.noduleStart and s <= r.length - C.noduleEnd, `{name}: a knot at {s}`)
						t.truthy(s - last >= C.noduleGap[1] - 1e-6, `{name}: knots {s - last} apart`)
						last = s
					end
					if r.length >= C.noduleStart + (r.trunkClearance or 0) + C.noduleGap[1] * 1.5 + C.noduleEnd then
						t.truthy(#n >= 1, `{name}: {r.length} studs and no knot`)
					end
				end
			end
			print(`      {knots} nodules on {boughs} branches`)
			-- one nodule: up and settled in BranchFeel.C.life, a few studs a second at most
			local F = BranchFeel.C
			local peak, fastest = 0, 0
			local prev = 0
			local dt = 1 / 240
			for k = 1, math.floor(0.3 / dt) do
				local age = k * dt
				local y = BranchFeel.bump(age, F.amp * F.maxScale)
				peak = math.max(peak, math.abs(y))
				fastest = math.max(fastest, math.abs(y - prev) / dt)
				prev = y
				if age >= F.life then
					t.eq(y, 0)
					t.eq(BranchFeel.rollAt(age, F.roll), 0)
				end
			end
			t.truthy(peak <= 0.16 and peak >= 0.1, `peak {peak}`)
			t.truthy(fastest <= 8 and fastest >= 2, `a few studs a second: {fastest}`)
			t.truthy(F.life <= 0.15 + 1e-9, "eased out in 0.15 s")
			-- the motor down a long bough with knots: the same steps with the feel as without (it reads, never writes), every
			-- knot felt once, nothing left once past
			local long: Registry.Route? = nil
			for _, r in reg:all() do
				if r.kind == "branch" and r.origin == "harvest" and #BranchNooks.nodules(r) >= 3 then
					if long == nil or r.length > (long :: Registry.Route).length then
						long = r
					end
				end
			end
			local r = long :: Registry.Route
			local function run(withFeel: boolean): ({ { number } }, number, number)
				local s = onRail(r.id, 0.05, 0)
				local feel = BranchFeel.new()
				local felt, most = 0, 0
				local track = {}
				local tr = BakedWorld.drive(world, s, 60 * 20, function(_f: number, st: SquirrelMotor.State)
					return BakedWorld.keys(along(r, st.railT, 1), { fw = 1 })
				end, {
					stop = function(st: SquirrelMotor.State): boolean
						if withFeel then
							local before = #feel.bumps
							local lift = BranchFeel.step(feel, reg:get(st.routeId or -1), st.railT, 1 / 60)
							if #feel.bumps > before then
								felt += #feel.bumps - before
							end
							most = math.max(most, math.abs(lift))
						end
						table.insert(track, { st.x, st.y, st.z, st.railT })
						return st.routeId ~= r.id or st.railT >= 0.999
					end,
				})
				local _ = tr
				return track, felt, most
			end
			local plain = run(false)
			local felt, nFelt, most = run(true)
			t.eq(#felt, #plain)
			for i, p in plain do
				for j = 1, 4 do
					t.eq(felt[i][j], p[j])
				end
			end
			local passed = 0
			local endS = plain[#plain][4] * r.length
			for _, n in BranchNooks.nodules(r) do
				if n > 0.05 * r.length and n < endS then
					passed += 1
				end
			end
			t.eq(nFelt, passed, `{r.name}: every knot passed is felt once`)
			t.truthy(most > 0.05 and most <= 0.16, `the lift {most}`)
			-- off the branch: what is under way eases out and nothing new starts
			local feel = BranchFeel.new()
			BranchFeel.step(feel, r, 0.1, 1 / 60)
			BranchFeel.step(feel, r, 0.1 + 6 / r.length, 1 / 60)
			local l = 1
			for _ = 1, 20 do
				l = BranchFeel.step(feel, nil, nil, 1 / 60)
			end
			t.eq(l, 0)
			local _ = Motion
		end
	)
end
