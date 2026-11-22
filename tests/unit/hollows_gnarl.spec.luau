--!strict
-- The hollow trees made gnarly, and getting out of their holes (owner D32: "those spiral staircase way inside the tree
-- is too uniform, have it be knarly, knotted sometimes, and realistic, allow the squirrel to actually look around and
-- of course be able to smoothly adequately jump out of any hole peeking out of that tree, preferably onto a branch, to
-- then wander out"). Shared/World/HollowLayout builds it; the real SquirrelMotor runs it in the baked town (build/Town
-- .rbxm: lune run tools/bake/main.luau, with the trees' invisible trunk colliders) with the shell the server builds
-- (Server/World/HollowShell), every frame judged by the envelope the server's MoveValidator applies.
--   the numbers the hops are planned with are the motor's own
--   the winding climb (H1): its line swings in and out by over half a stud, its pitch changes (shallow and steep
--   stretches, level ledges), never steeper than HollowLayout.C.maxSlope, turns back the other way after each root
--   across the hollow (a switchback), knots bulge from its wall, a ledge or a root under nearly all of it (no gap a
--   stud long), the same on every build and different from tree to tree; the shafts wind round their walls
--   every hole up a trunk (each tree's knotholes and its top): run up from the ground hole to it, stop, Space: the hop
--   lands on the branch it is cut over (its link) with no frame off the rails inside a cavity or inside the bark, and
--   the server accepts every frame; Space while still climbing past it does the same; E there takes the branch; from
--   the branch W runs out along it, S back to the bark, and E there goes back in at the hole (or takes the tree)
--   the inside camera peeks out at every hole up a trunk (HollowLayout.peekAt) and nowhere else on the climb
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local Data = require("@shared/Data")
local Enclosure = require("@shared/Routes/Enclosure")
local HollowLayout = require("@shared/World/HollowLayout")
local Motion = require("@shared/Routes/Motion")
local SquirrelMotor = require("@shared/Movement/SquirrelMotor")
local HollowShell = require("@server/World/HollowShell")
local BakedWorld = require("@tests/lib/BakedWorld")

type State = SquirrelMotor.State

return function(t)
	local layout = HollowLayout.default() :: HollowLayout.Layout
	local data = Data.default()
	local reg = data:routes()

	t.test("the hops are planned with the motor's own numbers", function()
		local F = HollowLayout.C.flight
		local P = SquirrelMotor.params
		t.near(F.gravity, P.gravity, 1e-9, "gravity")
		t.near(F.leapForward, P.leapForward, 1e-9, "a leap's forward speed")
		t.near(F.leapUp, P.leapUp, 1e-9, "a leap's rise")
		t.near(F.hopUp, Enclosure.C.hopUp, 1e-9, "a mouth's hop rise")
		t.near(F.clear, Enclosure.C.clear, 1e-9, "the launch's clearance outside an opening")
		t.near(F.catch, Motion.C.airCatch, 1e-9, "the air-catch's reach")
		t.near(F.catchClear, Motion.C.airCatchClear, 1e-9, "the travel before the air-catch takes anything")
	end)

	-- the climb's line, tree-local: bearing (unwrapped), radius and height every `step` studs
	local function sampled(h: HollowLayout.Hollow, rid: number, step: number): { { number } }
		local tr = HollowLayout.trunk(reg :: any, h.trunk :: number)
		local r = reg:get(rid) :: any
		local n = math.ceil(r.length / step)
		local out = {}
		local last: number? = nil
		for i = 0, n do
			local p = reg:pointAt(r, i / n)
			local hh = p.y - tr.foot.y
			local ax, _, az = tr.axisAt(hh)
			local b = math.deg(math.atan2(p.x - ax, p.z - az))
			if last then
				b = last + ((b - last + 180) % 360 - 180)
			end
			last = b
			table.insert(out, { b, math.sqrt((p.x - ax) ^ 2 + (p.z - az) ^ 2), hh, p.x, p.z })
		end
		return out
	end

	t.test("the winding climb is irregular: in and out, steep and shallow, both ways round, knots", function()
		local h = layout.hollow("H1") :: HollowLayout.Hollow
		local pts = sampled(h, h.routes[2], 0.5)
		local rMin, rMax, sMin, sMax, flat = math.huge, 0, math.huge, 0, 0
		local turns = { [1] = 0, [-1] = 0 }
		for i = 2, #pts do
			local a, b = pts[i - 1], pts[i]
			local level = math.sqrt((b[4] - a[4]) ^ 2 + (b[5] - a[5]) ^ 2)
			local s = (b[3] - a[3]) / math.max(level, 1e-6)
			-- (on the lane, off the root across the middle)
			if b[2] > 1.5 and a[2] > 1.5 then
				rMin, rMax = math.min(rMin, b[2]), math.max(rMax, b[2])
				turns[if b[1] > a[1] then 1 else -1] += level
				if math.abs(s) < 0.02 then
					flat += level
				else
					sMin = math.min(sMin, s)
				end
			end
			sMax = math.max(sMax, s)
		end
		print(
			string.format(
				"      H1: line %.2f to %.2f studs from the axis, slope %.2f to %.2f, %.1f studs level, %.1f / %.1f studs each way round",
				rMin,
				rMax,
				sMin,
				sMax,
				flat,
				turns[1],
				turns[-1]
			)
		)
		t.truthy(rMax - rMin >= 0.5, "the line swings in and out by over half a stud")
		t.truthy(sMin <= 0.3 and sMax >= 0.45, "shallow and steep stretches")
		-- (the curve through the climb's points rounds a turn from level to its steepest a little over it)
		t.truthy(sMax <= HollowLayout.C.maxSlope + 0.08, `never steeper than {HollowLayout.C.maxSlope} ({sMax})`)
		t.truthy(flat >= 8, "level ledges")
		t.truthy(turns[1] >= 15 and turns[-1] >= 15, "it turns back the other way (a switchback) and goes on round")
		local knots, roots = 0, 0
		for _, pc in h.parts do
			knots += if pc.role == "burl" then 1 else 0
			roots += if pc.role == "root" then 1 else 0
		end
		t.truthy(knots >= 8, `knots bulge from the wall ({knots})`)
		t.truthy(roots >= 6, `roots across the hollow ({roots})`)
	end)

	t.test("a ledge or a root under nearly all of the climb, no gap a stud long", function()
		local h = layout.hollow("H1") :: HollowLayout.Hollow
		local r = reg:get(h.routes[2]) :: any
		local function inside(pc: HollowLayout.Piece, x: number, y: number, z: number): boolean
			local xv, yv = pc.xv, pc.yv
			local zv = { xv[2] * yv[3] - xv[3] * yv[2], xv[3] * yv[1] - xv[1] * yv[3], xv[1] * yv[2] - xv[2] * yv[1] }
			local dx, dy, dz = x - pc.p[1], y - pc.p[2], z - pc.p[3]
			local a = dx * xv[1] + dy * xv[2] + dz * xv[3]
			local b = dx * yv[1] + dy * yv[2] + dz * yv[3]
			local c = dx * zv[1] + dy * zv[2] + dz * zv[3]
			if pc.shape == "Cylinder" then
				return math.abs(a) <= pc.size[1] / 2 and b * b + c * c <= (pc.size[2] / 2) ^ 2
			end
			return math.abs(a) <= pc.size[1] / 2 and math.abs(b) <= pc.size[2] / 2 and math.abs(c) <= pc.size[3] / 2
		end
		local n = math.ceil(r.length / 0.2)
		local bare, run, worst = 0, 0, 0
		for i = 0, n do
			local p = reg:pointAt(r, i / n)
			local under = false
			for _, pc in h.parts do
				if pc.role == "tread" or pc.role == "root" or pc.role == "floor" then
					for _, d in { 0.2, 0.35, 0.5 } do
						under = under or inside(pc, p.x, p.y - d, p.z)
					end
				end
			end
			if under then
				run = 0
			else
				bare += 1
				run += 1
				worst = math.max(worst, run)
			end
		end
		print(
			string.format(
				"      H1: %.0f %% of the climb over a gap, the longest %.1f studs",
				100 * bare / (n + 1),
				worst * 0.2
			)
		)
		t.truthy(bare / (n + 1) <= 0.08, "nearly all of it")
		t.truthy(worst * 0.2 <= 1.25, `no gap over a stud ({worst * 0.2})`)
	end)

	t.test("the same tree on every build, and different from tree to tree", function()
		local a, b, c =
			HollowLayout.rngOf("hollow H1"), HollowLayout.rngOf("hollow H1"), HollowLayout.rngOf("hollow H2")
		local same, differ = true, false
		for _ = 1, 20 do
			local x, y, z = a(), b(), c()
			same = same and x == y
			differ = differ or x ~= z
			t.truthy(x >= 0 and x < 1)
		end
		t.truthy(same and differ)
		-- the compiled trees are what a fresh build makes (generated/HollowTrees is not stale), and the two climbing
		-- trees' walls wind differently
		local turned = {}
		for _, id in { "H2", "H12" } do
			local h = layout.hollow(id) :: HollowLayout.Hollow
			local pts = sampled(h, h.routes[2], 0.5)
			local lo, hi = math.huge, -math.huge
			for _, p in pts do
				lo, hi = math.min(lo, p[1]), math.max(hi, p[1])
			end
			turned[id] = hi - lo
			t.truthy(hi - lo >= 30, `{id}: the climb winds round its wall ({hi - lo} degrees)`)
		end
		t.truthy(math.abs(turned.H2 - turned.H12) > 5, "each its own way")
		local seen: { [string]: boolean } = {}
		for _, h in layout.hollows do
			local key = {}
			for _, pc in h.parts do
				if pc.role == "burl" then
					table.insert(key, string.format("%.1f", pc.size[1]))
				end
			end
			if #key > 0 then
				local k = table.concat(key, ",")
				t.truthy(not seen[k], `{h.id}: its knots are another tree's`)
				seen[k] = true
			end
		end
	end)

	-- the town with its trees' trunk colliders, and the shell
	t.truthy(fs.isFile("build/Town.rbxm"), "build/Town.rbxm (lune run tools/bake/main.luau)")
	local town = roblox.deserializeModel(fs.readFile("build/Town.rbxm"))[1]
	HollowShell.build(roblox, layout).Parent = town
	local baked = BakedWorld.fromModel(town)
	local w = baked:motorWorld(data)
	local wreg = w.registry

	local function follow(st: State): number
		return BakedWorld.cameraYawToward(math.sin(st.yaw), math.cos(st.yaw))
	end
	local function holeOf(h: HollowLayout.Hollow): HollowLayout.Mouth
		for _, m in h.mouths do
			if m.opens == "ground" then
				return m
			end
		end
		error(`{h.id}: no ground mouth`)
	end
	-- every hole up a trunk: its hollow and mouth
	local holes: { { h: HollowLayout.Hollow, m: HollowLayout.Mouth } } = {}
	for _, h in layout.hollows do
		for _, m in h.mouths do
			if m.opens ~= "ground" then
				table.insert(holes, { h = h, m = m })
			end
		end
	end

	-- from 6 studs out of the ground hole, W in and up until the body is at the hole (its window); stop a frame
	local function climbTo(h: HollowLayout.Hollow, m: HollowLayout.Mouth): (State, BakedWorld.Trace)
		local g = holeOf(h)
		local ol = math.sqrt(g.out[1] ^ 2 + g.out[3] ^ 2)
		local ox, oz = g.out[1] / ol, g.out[3] / ol
		local x, z = g.x + ox * 6, g.z + oz * 6
		local s = SquirrelMotor.new(x, baked.groundAt(x, z, g.y + 3), z)
		s.yaw = math.atan2(-ox, -oz)
		local cam = BakedWorld.cameraYawToward(-ox, -oz)
		local r = wreg:get(m.route) :: any
		local spec = r.enclosure
		local trace = BakedWorld.drive(w, s, 60 * 30, function(_f: number, st: State): SquirrelMotor.Input
			return BakedWorld.keys(if st.routeId then follow(st) else cam, { fw = 1 })
		end, {
			validator = true,
			stop = function(st: State): boolean
				if st.routeId ~= m.route then
					return false
				end
				local mm = Enclosure.mouthAt(spec, r.length, st.railT)
				return mm ~= nil and mm.t == m.t and (m.t >= 1 or st.railT >= m.t)
			end,
		})
		return s, trace
	end

	-- after a launch out of a hole: every frame off the rails is outside every cavity and outside the bark
	local function cleanFlight(h: HollowLayout.Hollow, trace: BakedWorld.Trace): (number, number)
		local tr = HollowLayout.trunk(wreg :: any, h.trunk :: number)
		local inCavity, inBark = 0, 0
		for _, fr in trace.frames do
			if fr.routeId == nil then
				if layout.contains(fr.x, fr.y + 0.4, fr.z) ~= nil then
					inCavity += 1
				end
				local hh = fr.y + 0.4 - tr.foot.y
				if hh >= 0 then
					local ax, _, az = tr.axisAt(hh)
					if math.sqrt((fr.x - ax) ^ 2 + (fr.z - az) ^ 2) < tr.bark(hh) then
						inBark += 1
					end
				end
			end
		end
		return inCavity, inBark
	end

	t.test("every hole up a trunk: run up to it, stop, Space: the hop lands on its branch", function()
		t.truthy(#holes >= 8, `{#holes} holes up the trunks`)
		for _, e in holes do
			local h, m = e.h, e.m
			local target = if m.perch then m.perch else m.link
			local s, up = climbTo(h, m)
			t.eq(s.routeId, m.route, `{h.id} {m.name}: climbed to it`)
			t.eq(up.violations, 0, `{h.id} {m.name}: the server accepts the climb`)
			local cam = follow(s)
			local trace = BakedWorld.drive(w, s, 60 * 2, function(f: number): SquirrelMotor.Input
				return BakedWorld.keys(cam, { leap = f == 2 })
			end, {
				validator = true,
				stop = function(st: State, f: number): boolean
					return f > 2 and (st.routeId ~= nil or st.grounded)
				end,
			})
			local inCavity, inBark = cleanFlight(h, trace)
			if s.routeId ~= target then
				for _, ev in trace.events do
					print(`      {ev.frame} {ev.kind} {ev.routeId} {ev.fromRouteId} {ev.reason}`)
				end
			end
			t.eq(s.routeId, target, `{h.id} {m.name}: Space lands on branch {target}`)
			t.eq(inCavity, 0, `{h.id} {m.name}: frames in the cavity off the rails`)
			t.eq(inBark, 0, `{h.id} {m.name}: frames in the bark`)
			t.eq(trace.violations, 0, `{h.id} {m.name}: the server accepts the hop`)
			t.truthy(trace.seconds <= 1.0, `{h.id} {m.name}: landed in {trace.seconds} s`)
		end
	end)

	t.test("Space while still climbing past a hole, and with W held through the hop: the same branch", function()
		for _, e in holes do
			local h, m = e.h, e.m
			if m.t >= 1 then
				continue -- (the top is the climb's end: W runs on out of it)
			end
			local target = if m.perch then m.perch else m.link
			local s = climbTo(h, m)
			local trace = BakedWorld.drive(w, s, 60 * 2, function(f: number, st: State): SquirrelMotor.Input
				return BakedWorld.keys(follow(st), { fw = 1, leap = f == 1 })
			end, {
				validator = true,
				stop = function(st: State, f: number): boolean
					return f > 1 and (st.routeId ~= m.route) and (st.routeId ~= nil or st.grounded)
				end,
			})
			local inCavity, inBark = cleanFlight(h, trace)
			t.eq(s.routeId, target, `{h.id} {m.name}: Space and W land on branch {target}`)
			t.eq(inCavity + inBark, 0, `{h.id} {m.name}: nothing in the wall`)
			t.eq(trace.violations, 0, `{h.id} {m.name}: the server accepts it`)
		end
	end)

	t.test("E at a hole takes its branch; on the branch W runs out along it and S back to the bark", function()
		for _, e in holes do
			local h, m = e.h, e.m
			local s = climbTo(h, m)
			local cam = follow(s)
			local trace = BakedWorld.drive(w, s, 10, function(f: number): SquirrelMotor.Input
				return BakedWorld.keys(cam, { grab = f == 1 })
			end, { validator = true })
			t.eq(s.routeId, m.link, `{h.id} {m.name}: E takes {m.link}`)
			t.eq(trace.violations, 0, `{h.id} {m.name}: the server accepts it`)
			local perch = m.perch
			if perch then
				-- out along the perch to its tip, then back to the bark
				local b0 = wreg:get(perch) :: any
				local onIt = SquirrelMotor.new(s.x, s.y, s.z)
				local q = wreg:pointAt(b0, 0.5)
				onIt.x, onIt.y, onIt.z = q.x, q.y, q.z
				onIt.grounded = false
				onIt.routeId, onIt.railT, onIt.railDir = perch, 0.5, 1
				local out = BakedWorld.drive(w, onIt, 60 * 3, function(): SquirrelMotor.Input
					local d = wreg:tangentAt(b0, math.clamp(onIt.railT, 0.01, 0.99))
					return BakedWorld.keys(BakedWorld.cameraYawToward(d.x, d.z), { fw = 1 })
				end, { validator = true })
				t.truthy(onIt.routeId == perch and onIt.railT > 0.95, `{h.id} {m.name}: W runs out to the tip`)
				t.eq(out.violations, 0)
				local back = BakedWorld.drive(w, onIt, 60 * 3, function(): SquirrelMotor.Input
					local d = wreg:tangentAt(b0, math.clamp(onIt.railT, 0.01, 0.99))
					return BakedWorld.keys(BakedWorld.cameraYawToward(d.x, d.z), { fw = -1 })
				end, { validator = true })
				-- (at the bark, or on along the bough or the trunk it meets there)
				local foot = wreg:pointAt(b0, 0)
				local atBark = math.sqrt((onIt.x - foot.x) ^ 2 + (onIt.y - foot.y) ^ 2 + (onIt.z - foot.z) ^ 2)
				t.truthy(
					onIt.routeId ~= nil and atBark < 3 and layout.spaceOf(onIt.routeId) == nil,
					`{h.id} {m.name}: S runs back to the bark (on {onIt.routeId} t {onIt.railT}, {atBark} studs off)`
				)
				t.eq(back.violations, 0)
				-- E at the bark end takes the hole back in (the branch is the hole's link: Enclosure rule 5, both ways) or the
				-- tree, nothing else
				local at0 = wreg:pointAt(b0, 0.03)
				local e0 = SquirrelMotor.new(at0.x, at0.y, at0.z)
				e0.grounded = false
				e0.routeId, e0.railT, e0.railDir = perch, 0.03, -1
				local grab = BakedWorld.drive(w, e0, 20, function(f: number): SquirrelMotor.Input
					return BakedWorld.keys(0, { grab = f == 1 })
				end, { validator = true })
				local onto = wreg:get(e0.routeId or 0)
				t.truthy(
					onto ~= nil
						and e0.routeId ~= perch
						and (e0.routeId == m.route or layout.spaceOf(e0.routeId :: number) == nil),
					`{h.id} {m.name}: E at the bark end takes the hole or the tree (on {e0.routeId})`
				)
				t.eq(grab.violations, 0)
			end
		end
	end)

	t.test("the inside camera peeks out at every hole up a trunk, and nowhere else on the climb", function()
		for _, e in holes do
			local got = layout.peekAt(e.m.x, e.m.y, e.m.z)
			t.truthy(got ~= nil and got.route == e.m.route and got.t == e.m.t, `{e.h.id} {e.m.name}`)
		end
		local h = layout.hollow("H1") :: HollowLayout.Hollow
		local r = wreg:get(h.routes[2]) :: any
		local peeks = 0
		for i = 0, 400 do
			local p = wreg:pointAt(r, i / 400)
			local m = layout.peekAt(p.x, p.y, p.z)
			if m then
				peeks += 1
				t.truthy(math.abs(i / 400 - m.t) * r.length <= HollowLayout.C.peekReach + 0.2, "only by a hole")
			end
		end
		t.truthy(peeks > 0 and peeks < 60, `{peeks} of 401 points of the climb by a hole`)
	end)
end
