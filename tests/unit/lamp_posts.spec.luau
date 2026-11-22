--!strict
-- Every light post climbable (owner D35, 2026-11-22: "make all trees climbable, and even all light posts";
-- Shared/World/LampPosts, data/lamp_posts.json, generated/LampPosts), over the compiled data as every rail user sees it
-- (Shared/Data: the routes appended, the arms' forks merged; Movement/RailWorld) and the baked models (the backdrop's
-- pier lamps aside: tools/bake/LampScan.FILES says why):
--   * every post has its climb: every light post in the bakes (tools/bake/LampScan over build/*.rbxm) inside the world
--     has a climb up its axis from the ground to its top, and an arm along its arm where it has one; nothing else;
--   * the routes: a climb is a trunk at the trees' pace (treeTravel) with a pole's grab; an arm leaves a climb sample
--     with its canopy fork made by the harvest's rule, follows the drawn arm to the lamp head, and A/D on the post
--     offers it; the top of a post with an arm is out of the end-of-route switch's reach of the arm (a stop: the perch);
--   * no route over a road's car lanes (every vehicle lane the traffic drives, both ways, the widest vehicle's half
--     width either side), and none in a building;
--   * the route graph stays connected: no island of the routes without the posts is split by them, each post's climb
--     and arm are one island;
--   * the real SquirrelMotor on the baked models (BakedWorld: the town, the attractions, Bowl Lane, Lift Road), every
--     frame judged by the motor's envelope and every packet (20 a second) by the server's MoveValidator on
--     the live rays: for every post, walk into it from beside it and up to the top, down to the foot and let go (Q);
--     run past it along the sidewalk side and E onto it; up again and leap off the top; and where it has an arm, A/D
--     and W onto the arm, along it to the lamp head and off. Zero violations, zero rejected packets, even steps;
--   * nothing drawn: the bake's own route props never see the climbs (the lamps look as they did), and the cost.
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local Bake = require("@worldgen/Bake")
local Curve = require("@shared/Routes/Curve")
local Data = require("@shared/Data")
local Height = require("@shared/World/Height")
local LampPosts = require("@shared/World/LampPosts")
local Motion = require("@shared/Routes/Motion")
local RailWorld = require("@shared/Movement/RailWorld")
local Registry = require("@shared/Routes/Registry")
local SquirrelMotor = require("@shared/Movement/SquirrelMotor")
local Units = require("@shared/Config/Units")
local MoveValidator = require("@server/Movement/MoveValidator")
local ValidatorWorld = require("@server/Movement/ValidatorWorld")
local BakedWorld = require("@tests/lib/BakedWorld")
local TreeClear = require("@tests/lib/TreeClear")
local LampScan = require("../../tools/bake/LampScan")

-- the bakes a post of each source stands in (tools/bake/LampScan.FILES)
local FILE_OF: { [string]: string } = {}
for _, f in LampScan.FILES do
	FILE_OF[f.source] = f.file
end
local NEEDED = { "town", "attractions", "bowl_lane", "skylift" }

type Drive = { violations: number, rejected: number, codes: { [string]: number }, maxStep: number, events: { string } }

return function(t)
	local d = Data.default()
	local reg = d:routes()
	local compiled = d:module("LampPosts") :: any
	local doc = serde.decode("json", fs.readFile("data/lamp_posts.json"))
	local rail = RailWorld.build(d)
	local postOf: { [string]: any } = {}
	for _, p in doc.posts do
		postOf[p.id] = p
	end
	local routesOf: { [string]: any } = {}
	for _, p in compiled.posts do
		routesOf[p.id] = p
	end

	t.test("every light post in the bakes, inside the world, has its climb (and its arm where it has one)", function()
		Height.configure(d:module("TerrainExtensions"))
		local clamp = Height.worldClamp()
		Height.configure(nil)
		local found: { [string]: boolean } = {}
		local bySource: { [string]: number } = {}
		for _, f in LampScan.FILES do
			if not fs.isFile(f.file) then
				t.truthy(table.find(NEEDED, f.source) == nil, `{f.file} (bake it first)`)
				continue
			end
			for _, p in LampScan.scan(roblox.deserializeModel(fs.readFile(f.file)), f.source) do
				if p.x < clamp.minX or p.x > clamp.maxX or p.z < clamp.minZ or p.z > clamp.maxZ then
					continue
				end
				found[p.id] = true
				bySource[p.source] = (bySource[p.source] or 0) + 1
				local rec = postOf[p.id]
				t.truthy(rec ~= nil, `{p.id} ({p.path}) has no climb: run lune run tools/bake/lamp_posts.luau`)
				if not rec then
					continue
				end
				-- where it stands now (a bake that moved it needs the file written again)
				t.truthy(
					math.abs(rec.x - p.x) < 0.01 and math.abs(rec.z - p.z) < 0.01 and math.abs(rec.top - p.top) < 0.01,
					`{p.id} moved: run lune run tools/bake/lamp_posts.luau`
				)
				t.eq(rec.arm ~= nil, p.arm ~= nil, `{p.id}: arm`)
				local armed = rec.arm ~= nil and rec.arm.run ~= 0
				local r = routesOf[p.id]
				t.truthy(r ~= nil, `{p.id}: compiled (lune run tools/compile/main.luau compile)`)
				local climb = reg:get(r.climb) :: Registry.Route
				local foot, top = reg:pointAt(climb, 0), reg:pointAt(climb, 1)
				t.near(foot.x, p.x, 0.01)
				t.near(foot.z, p.z, 0.01)
				t.near(foot.y, p.ground + LampPosts.C.stand, 0.01)
				t.near(top.y, p.top + (if p.arm then LampPosts.C.finial else 0), 0.01)
				t.eq(r.arm ~= nil, armed, `{p.id}: arm route`)
			end
		end
		for _, p in doc.posts do
			t.truthy(found[p.id], `{p.id} is in data/lamp_posts.json but in no bake`)
		end
		local parts = {}
		for _, f in LampScan.FILES do
			if bySource[f.source] then
				table.insert(parts, `{f.source} {bySource[f.source]}`)
			end
		end
		print(`      {#doc.posts} posts ({table.concat(parts, ", ")}), {#compiled.forks} with an arm`)
		t.eq(#compiled.posts, #doc.posts)
		t.truthy(#doc.posts >= 160, `{#doc.posts} posts`)
	end)

	t.test(
		"a climb is a trunk at the trees' pace; an arm leaves a climb sample by the harvest's rule, A/D offers it",
		function()
			local climbs, arms = 0, 0
			for _, p in compiled.posts do
				local post = postOf[p.id]
				local climb = reg:get(p.climb) :: Registry.Route
				climbs += 1
				t.eq(climb.kind, "trunk")
				t.eq(climb.origin, "lampPost")
				t.truthy(climb.flags.treeTravel and climb.flags.isPole and not climb.flags.autoGrabExcluded, p.id)
				t.near(climb.surfaceRadius, post.radius, 1e-3)
				t.eq(climb.sampleCount, Curve.sampleSteps(climb.length / Units.STUDS_PER_UNIT) + 1)
				t.near(climb.length, reg:curve(climb):getLength(), 1e-3)
				-- straight up the axis
				for _, s in reg:samples(climb) do
					t.truthy(math.abs(s.x - post.x) < 1e-3 and math.abs(s.z - post.z) < 1e-3, `{p.id}: off its axis`)
				end
				-- the climb's pace is a tree trunk's
				t.near(Motion.routeSpeed(climb, false, false, false), Motion.C.railWalk * Motion.C.treeTravelMult, 1e-9)
				if p.arm then
					arms += 1
					local arm = reg:get(p.arm) :: Registry.Route
					t.eq(arm.kind, "branch")
					t.truthy(arm.flags.treeTravel and not arm.flags.isPole, p.id)
					local start = reg:pointAt(arm, 0)
					local samples = reg:samples(climb)
					local nearest, nd = 0, math.huge
					for i, s in samples do
						local dd = math.sqrt((s.x - start.x) ^ 2 + (s.y - start.y) ^ 2 + (s.z - start.z) ^ 2)
						if dd < nd then
							nearest, nd = i, dd
						end
					end
					t.truthy(nd < 1e-3, `{p.id}: the arm leaves the climb {nd} studs off its sample`)
					local fork = rail.graph:forkOf(arm.id)
					t.truthy(fork ~= nil, `{p.id}: a canopy fork`)
					if fork then
						t.eq(fork.trunk, climb.id)
						t.near(fork.t, (nearest - 1) / (#samples - 1), 1e-9)
						t.near(fork.height, samples[nearest].y, 1e-6)
						local ahead = reg:pointAt(arm, LampPosts.C.forkOut)
						local ox, oz = ahead.x - start.x, ahead.z - start.z
						local l = math.sqrt(ox * ox + oz * oz)
						t.near(fork.outward.x, ox / l, 1e-6)
						t.near(fork.outward.z, oz / l, 1e-6)
						-- from the foot and from the top of the post, A/D sees it
						for _, at in { 0, 1 } do
							local near = Motion.nearbyForks(rail :: any, climb, at)
							t.truthy(table.find(near, fork) ~= nil, `{p.id}: offered at t {at}`)
						end
					end
					-- along the drawn arm (the lamps' shape) to the tip over the head
					local drawn = LampPosts.armPoints(post.x, post.z, post.top, post.arm)
					local tip = reg:pointAt(arm, 1)
					local run = post.arm.run or post.arm.reach
					local want = LampPosts.cut(drawn, run)
					t.near(tip.x, want[#want][1], 1e-3)
					t.near(tip.y, want[#want][2], 1e-3)
					t.near(tip.z, want[#want][3], 1e-3)
					t.near(math.sqrt((tip.x - post.x) ^ 2 + (tip.z - post.z) ^ 2), run, 1e-3)
					t.truthy(
						math.abs(start.y - drawn[1][2]) < 0.9,
						`{p.id}: the arm leaves {start.y - drawn[1][2]} off`
					)
					-- the top is a stop: no sample of the arm's end windows (Motion.switchRoute's candidates) within the
					-- end-of-route switch's reach of the climb's top
					local top = reg:pointAt(climb, 1)
					local armSamples = reg:samples(arm)
					for i, s in armSamples do
						local at = (i - 1) / (#armSamples - 1)
						if at <= Motion.C.endWindowLow or at >= Motion.C.endWindowHigh then
							local dd = math.sqrt((s.x - top.x) ^ 2 + (s.y - top.y) ^ 2 + (s.z - top.z) ^ 2)
							t.truthy(dd > Motion.C.autoSwitchGap, `{p.id}: the arm's end {dd} studs from the top`)
						end
					end
					-- no stretch steeper than a tree's grown bough, no kink
					local pts = reg:curve(arm):getSpacedPoints(40)
					for i = 2, #pts do
						local a, c = pts[i - 1], pts[i]
						local h = math.sqrt((c.x - a.x) ^ 2 + (c.z - a.z) ^ 2)
						t.truthy(math.deg(math.atan2(math.abs(c.y - a.y), h)) <= 60, `{p.id}: arm slope`)
					end
				else
					t.eq(rail.graph:forks(climb.id)[1], nil, `{p.id}: no fork`)
				end
			end
			t.truthy(climbs == #doc.posts and arms >= 140, `{climbs} climbs, {arms} arms`)
		end
	)

	t.test("no route over a road's car lanes; no arm in a building", function()
		-- every vehicle lane the traffic drives, both ways, with its band (tools/bake/LampScan.carLanes: half the widest
		-- vehicle that drives it and a margin)
		local lines = LampScan.carLanes(d:lanes() :: any, d:roads() :: any)
		t.truthy(#lines >= 20, `{#lines} lane lines`)
		local clear = TreeClear.new(d)
		local nearest, nearestAt = math.huge, ""
		local over: { string } = {}
		local cut = 0
		for _, p in compiled.posts do
			local post = postOf[p.id]
			if post.arm and post.arm.run then
				cut += 1
			end
			for _, id in { p.climb, p.arm } do
				local r = reg:get(id) :: Registry.Route
				local worst, lane = math.huge, ""
				for _, s in reg:samples(r) do
					local g, name = LampScan.laneGap(lines, s.x, s.z)
					if g < worst then
						worst, lane = g, name
					end
					if r.kind ~= "trunk" then
						t.eq(clear:boxAt(s.x, s.y, s.z, 0.5), nil, `{r.name}: in a building`)
					end
				end
				if worst < 0 then
					table.insert(over, `{r.name} ({lane}: {string.format("%.2f", -worst)} into its band)`)
				end
				if worst < nearest then
					nearest, nearestAt = worst, r.name
				end
			end
		end
		t.eq(#over, 0, `over a car lane: {table.concat(over, "; ")}`)
		print(
			string.format(
				"      %d vehicle lane lines; the nearest lamp route keeps %.2f studs outside a band (%s); %d arm routes stop short of a lane",
				#lines,
				nearest,
				nearestAt,
				cut
			)
		)
	end)

	t.test(
		"the route graph stays connected: no island split by the posts; each post's climb and arm one island",
		function()
			-- the same data with the lamp-post module hidden
			local without = Data.new(function(name: string): any?
				if name == "LampPosts" then
					return nil
				end
				return (require :: any)("../../generated/" .. name)
			end)
			local before = RailWorld.build(without)
			t.eq(#before.registry:all() + #compiled.routes, #reg:all())
			for _, island in before.graph:islands() do
				local into = rail.graph:islandOf(island[1])
				for _, id in island do
					t.eq(rail.graph:islandOf(id), into, `island of route {island[1]} split at route {id}`)
				end
			end
			local merged = 0
			for _, p in compiled.posts do
				local i = rail.graph:islandOf(p.climb)
				t.truthy(i ~= nil, p.id)
				if p.arm then
					t.eq(rail.graph:islandOf(p.arm), i, `{p.id}: climb and arm one island`)
				end
				if #rail.graph:islands()[i :: number] > (if p.arm then 2 else 1) then
					merged += 1
				end
			end
			print(
				`      islands {before.graph:islandCount()} -> {rail.graph:islandCount()}; {merged} posts within a transfer of another route`
			)
		end
	)

	-- the real motor on the baked models, judged frame by frame and packet by packet --------------------------------
	local worlds: { [string]: any } = {}
	local function worldFor(source: string): any?
		local w = worlds[source]
		if w then
			return w
		end
		local file = FILE_OF[source]
		if not file or not fs.isFile(file) then
			return nil
		end
		local baked = BakedWorld.load(file)
		local mw = baked:motorWorld(d)
		local wall, down, cover = BakedWorld.validatorRays(baked)
		w = {
			baked = baked,
			motor = mw,
			validator = ValidatorWorld.build(mw, { wall = wall, down = down, cover = cover }),
		}
		worlds[source] = w
		return w
	end
	local function camToward(dx: number, dz: number): number
		return math.atan2(-dx, -dz)
	end
	-- drive(w, s, frames, keys): the motor at 60 Hz, the envelope each frame, the server's validator each 3rd frame
	local function drive(
		w: any,
		s: SquirrelMotor.State,
		frames: number,
		keys: (f: number, s: SquirrelMotor.State) -> SquirrelMotor.Input?
	): Drive
		local v = MoveValidator.new(w.validator)
		s.clock = 1
		v:accept("a", { seq = 0, snapshot = SquirrelMotor.serialize(s) }, 1)
		local out: Drive = { violations = 0, rejected = 0, codes = {}, maxStep = 0, events = {} }
		local seq = 0
		for f = 1, frames do
			local input = keys(f, s)
			if not input then
				break
			end
			local before = SquirrelMotor.clone(s)
			local _, events = SquirrelMotor.step(s, input, 1 / 60, w.motor)
			for _, x in SquirrelMotor.envelope(before, s, 1 / 60, w.motor, false) do
				out.violations += 1
				out.codes["env:" .. tostring(x.code)] = (out.codes["env:" .. tostring(x.code)] or 0) + 1
			end
			if s.routeId and before.routeId == s.routeId and not s.bridge then
				out.maxStep =
					math.max(out.maxStep, math.sqrt((s.x - before.x) ^ 2 + (s.y - before.y) ^ 2 + (s.z - before.z) ^ 2))
			end
			for _, e in events do
				table.insert(out.events, `{f}:{e.kind}{if e.routeId then ":" .. e.routeId else ""}`)
			end
			if f % 3 == 0 then
				seq += 1
				local res = v:accept("a", { seq = seq, snapshot = SquirrelMotor.serialize(s) }, s.clock)
				if #res.violations > 0 then
					out.rejected += 1
				end
				for _, x in res.violations do
					out.violations += 1
					out.codes[tostring(x.code)] = (out.codes[tostring(x.code)] or 0) + 1
				end
			end
		end
		return out
	end
	local function describe(r: Drive): string
		local c = {}
		for k, n in r.codes do
			table.insert(c, `{k}={n}`)
		end
		return `{r.violations} violations ({table.concat(c, " ")}), {r.rejected} packets rejected; {table.concat(
			r.events,
			" ",
			1,
			math.min(#r.events, 12)
		)}`
	end
	-- where a squirrel stands beside a post: `out` studs from its axis, on open ground near the post's own, the side
	-- away from its arm first (the sidewalk's, for a street lamp)
	local function besideOf(w: any, post: any, out: number): (number?, number, number, number)
		local away = if post.arm then math.atan2(-post.arm.ox, -post.arm.oz) else 0
		for k = 0, 15 do
			local a = away + (if k % 2 == 0 then 1 else -1) * math.ceil(k / 2) * math.pi / 8
			local dx, dz = math.sin(a), math.cos(a)
			local x, z = post.x + dx * out, post.z + dz * out
			local g = w.motor.groundAt(x, z, post.ground + 2)
			if math.abs(g - post.ground) < 1.5 and not w.motor.blocked(x, z, g) then
				-- and the way in is open (the post itself aside)
				local clear = true
				local own = string.match(post.path, "[^/]+$")
				for q = 0.25, 0.75, 0.25 do
					local qx, qz = post.x + dx * out * q + dx * 0.6, post.z + dz * out * q + dz * 0.6
					local hit = w.baked.blocker(qx, qz, w.motor.groundAt(qx, qz, g + 1), 0.6)
					if hit and hit.name ~= own then
						clear = false
					end
				end
				if clear then
					return x, g, z, a
				end
			end
		end
		return nil, 0, 0, 0
	end

	-- a straight run past a post, `RUN_BY` studs out, on open ground at the post's own height all the way: the side
	-- away from its arm (the sidewalk's) first, then the other; -> (start x, z, along x, z), or nil
	local RUN_BY = 3.5
	local function runLine(w: any, post: any): (number?, number, number, number)
		local ox, oz = 0, 1
		if post.arm then
			ox, oz = -post.arm.ox, -post.arm.oz
		end
		for _, side in { 1, -1 } do
			for _, turn in { 0, math.pi / 2 } do
				-- (an armless post: the four ways round it)
				local c, sn = math.cos(turn), math.sin(turn)
				local ax, az = (ox * c - oz * sn) * side, (ox * sn + oz * c) * side
				for _, sense in { 1, -1 } do
					local lx, lz = -az * sense, ax * sense
					local ok = true
					for k = -7, 2 do
						local x, z = post.x + ax * RUN_BY + lx * k, post.z + az * RUN_BY + lz * k
						local g = w.motor.groundAt(x, z, post.ground + 2)
						if math.abs(g - post.ground) > 1.5 or w.motor.blocked(x, z, g) then
							ok = false
							break
						end
					end
					if ok then
						return post.x + ax * RUN_BY - lx * 6, post.z + az * RUN_BY - lz * 6, lx, lz
					end
				end
				if post.arm then
					break
				end
			end
		end
		return nil, 0, 0, 0
	end

	t.test(
		"the real motor, every post: walk in and up, down and let go; E from the sidewalk; leap off the top",
		function()
			Height.configure(d:module("TerrainExtensions"))
			local total, bad, steps, worstStep, noRoom = 0, 0, 0, 0, {}
			for _, p in compiled.posts do
				local post = postOf[p.id]
				local w = worldFor(post.source)
				t.truthy(w ~= nil, `{post.source}: its bake`)
				if not w then
					continue
				end
				local climb = w.motor.registry:get(p.climb) :: Registry.Route
				local x, g, z, a = besideOf(w, post, 3.5)
				if x == nil then
					table.insert(noRoom, p.id)
					continue
				end
				total += 1
				local inward = camToward(-math.sin(a), -math.cos(a)) -- the camera looks from the squirrel at the post
				-- 1. walk into it, W up to the top (a stop), S down to the foot, Q lets go
				local s = SquirrelMotor.new(x :: number, g, z)
				s.yaw = a + math.pi
				local phase = "walk"
				local r1 = drive(w, s, 60 * 8, function(_f, st)
					local inp = SquirrelMotor.idleInput(inward)
					if phase == "walk" then
						inp.fw = 1
						if st.routeId == climb.id then
							phase = "up"
						end
					elseif phase == "up" then
						inp.fw = 1
						if st.railT >= 1 then
							phase = "perch"
							return inp
						end
					elseif phase == "perch" then
						inp.fw = 1 -- (still held: the top is a stop)
						if st.routeId ~= climb.id then
							phase = "left"
						else
							phase = "down"
						end
					elseif phase == "down" then
						inp.fw = -1
						if st.railT <= 0 then
							phase = "drop"
						end
					elseif phase == "drop" then
						inp.drop = true
						phase = "falling"
					elseif phase == "falling" then
						if st.grounded then
							return nil
						end
					end
					return inp
				end)
				t.eq(phase, "falling", `{p.id}: walk in, up, down, let go ({describe(r1)})`)
				t.truthy(s.grounded and s.routeId == nil, `{p.id}: on the ground after letting go`)
				-- 2. along the sidewalk side past it, E as it comes abreast: up the post
				local sx, sz, lx, lz = runLine(w, post)
				if sx == nil then
					table.insert(noRoom, p.id .. " (a run past it)")
					continue
				end
				local s2 = SquirrelMotor.new(sx :: number, w.motor.groundAt(sx :: number, sz, g + 2), sz)
				local along = camToward(lx, lz)
				s2.yaw = math.atan2(lx, lz)
				local pressed = false
				local r2 = drive(w, s2, 60 * 3, function(_f, st)
					local inp = SquirrelMotor.idleInput(along)
					if st.routeId == climb.id then
						return nil
					end
					inp.fw = 1
					local rel = (st.x - post.x) * lx + (st.z - post.z) * lz
					if not pressed and rel > -1 then
						inp.grab = true
						pressed = true
					end
					return inp
				end)
				t.eq(s2.routeId, climb.id, `{p.id}: E running past it ({describe(r2)})`)
				-- 3. up again and leap off the top
				local s3 = SquirrelMotor.new(x :: number, g, z)
				s3.yaw = a + math.pi
				local leapt, airborne = false, false
				local r3 = drive(w, s3, 60 * 8, function(_f, st)
					local inp = SquirrelMotor.idleInput(inward)
					if leapt then
						airborne = airborne or st.routeId == nil
						if airborne and (st.grounded or st.routeId ~= nil) then
							return nil
						end
						return inp
					end
					inp.fw = 1
					if st.routeId == climb.id and st.railT >= 1 then
						inp.fw = 0
						inp.leap = true
						leapt = true
					end
					return inp
				end)
				t.truthy(airborne and (s3.grounded or s3.routeId ~= nil), `{p.id}: off the top ({describe(r3)})`)
				for _, r in { r1, r2, r3 } do
					bad += r.violations + r.rejected
					steps += 1
					worstStep = math.max(worstStep, r.maxStep)
					t.eq(r.violations + r.rejected, 0, `{p.id}: {describe(r)}`)
				end
			end
			Height.configure(nil)
			print(
				string.format(
					"      %d posts, %d drives: %d violations; the largest step on a post %.3f studs a frame%s",
					total,
					steps,
					bad,
					worstStep,
					if #noRoom > 0 then "; no room beside " .. table.concat(noRoom, ", ") else ""
				)
			)
			t.eq(#noRoom, 0, "a place beside every post")
			t.truthy(worstStep < 0.6, `largest step {worstStep}`)
		end
	)

	t.test(
		"the real motor, every arm: A/D and W from the foot onto the arm, along it to the lamp head, and off",
		function()
			Height.configure(d:module("TerrainExtensions"))
			local n, bad = 0, 0
			for _, p in compiled.posts do
				if not p.arm then
					continue
				end
				local post = postOf[p.id]
				local w = worldFor(post.source)
				if not w then
					continue
				end
				local reg2 = w.motor.registry
				local climb = reg2:get(p.climb) :: Registry.Route
				local arm = reg2:get(p.arm) :: Registry.Route
				local fork = w.motor.graph:forkOf(arm.id) :: any
				local x, g, z, a = besideOf(w, post, 3.5)
				if x == nil then
					continue
				end
				n += 1
				-- the camera looks so that the arm heads off to the right, from where the squirrel stands
				local yaw = math.atan2(-fork.outward.z, fork.outward.x)
				local s = SquirrelMotor.new(x :: number, g, z)
				s.yaw = a + math.pi
				local inward = camToward(-math.sin(a), -math.cos(a))
				local phase = "walk"
				local r = drive(w, s, 60 * 10, function(_f, st)
					local inp = SquirrelMotor.idleInput(if phase == "walk" then inward else yaw)
					if phase == "walk" then
						inp.fw = 1
						if st.routeId == climb.id then
							phase = "pick"
						end
					elseif phase == "pick" then
						if st.pendingFork == arm.id then
							phase = "up"
						else
							inp.choose = 1
						end
					elseif phase == "up" then
						inp.fw = 1
						if st.routeId == arm.id then
							phase = "along"
						elseif st.railT >= 1 then
							phase = "missed"
							return nil
						end
					elseif phase == "along" then
						inp.fw = 1
						if st.routeId == arm.id and st.railT >= 1 then
							phase = "tip"
						end
					elseif phase == "tip" then
						inp.leap = true
						phase = "off"
					elseif phase == "off" then
						if st.routeId == nil then
							phase = "flying"
						end
					elseif phase == "flying" then
						if st.grounded or st.routeId ~= nil then
							phase = "landed"
							return nil
						end
					end
					return inp
				end)
				t.eq(phase, "landed", `{p.id}: onto the arm, to the head and off ({describe(r)})`)
				bad += r.violations + r.rejected
				t.eq(r.violations + r.rejected, 0, `{p.id}: {describe(r)}`)
				t.truthy(r.maxStep < 0.6, `{p.id}: a step of {r.maxStep} studs`)
			end
			Height.configure(nil)
			print(`      {n} arms: {bad} violations`)
			t.truthy(n >= 140, `{n} arms driven`)
		end
	)

	t.test("nothing drawn: the bake never sees the climbs; what the routes cost", function()
		local data = Bake.data()
		for _, r in data.routes or {} do
			t.truthy(r.origin ~= "lampPost", `the bake draws {r.name}`)
		end
		local samples, climbs, arms = 0, 0, 0
		for _, r in compiled.routes do
			samples += r.sampleCount
			if r.kind == "trunk" then
				climbs += 1
			else
				arms += 1
			end
		end
		local all = 0
		for _, r in reg:all() do
			all += r.sampleCount
		end
		local bytes = #fs.readFile("generated/LampPosts.luau")
		print(
			`      {climbs} climbs and {arms} arms: {samples} route samples of {all} ({string.format(
				"%.1f",
				100 * samples / all
			)} %), generated/LampPosts {bytes} bytes; 0 parts`
		)
		t.truthy(samples < 0.15 * all, "a small share of the samples")
	end)
end
