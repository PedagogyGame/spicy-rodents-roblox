--!strict
-- The storm drains run through on the real motor (BRIEF_ADDENDUM D8; Shared/World/SewerLayout; the enclosed-run
-- contract Shared/Routes/Enclosure): the routes as Shared/Data has them, a plain stand-in of the pipes as parts
-- (tests/lib/SewerStandIn: floors, walls, roofs, shafts, a cover over each mouth) loaded by tests/lib/BakedWorld, the
-- real SquirrelMotor driven with scripted keys, and the envelope the server's MoveValidator applies to every frame.
--   in only at a mouth, with E (facing in, standing on it); not from beside it, not from the street over a pipe
--   out at every street mouth on its feet, still running
--   each pipe beats its surface way with W held: P1 and P2 at the street pace the motor runs today; P3 only at the
--   pipe pace (Tunables sewer.speedMult), which the motor does not apply yet (N2: the rail time is scaled to it)
--   nothing through walls: the body's section along every route meets no part of the stand-in; inside, Space, Q, a
--   click and E do nothing; the server refuses a body put into a pipe from the street or out of one through the road
--   P1's crossing: W runs straight on, A or D turns into a side arm
-- And one known gap, pinned so the motor lane sees it: walking onto a grate heading in also goes down (Enclosure rule
-- 1 has no E-only mouth: the survey's hatch mouth N3).
local Data = require("@shared/Data")
local Enclosure = require("@shared/Routes/Enclosure")
local Motion = require("@shared/Routes/Motion")
local RailWorld = require("@shared/Movement/RailWorld")
local SquirrelMotor = require("@shared/Movement/SquirrelMotor")
local SewerLayout = require("@shared/World/SewerLayout")
local Tunables = require("@shared/Config/Tunables")
local BakedWorld = require("@tests/lib/BakedWorld")
local SewerStandIn = require("@tests/lib/SewerStandIn")

type State = SquirrelMotor.State
type Mouth = SewerLayout.Mouth

-- the runs: from a mouth to the mouth at the other end (P1 corner to corner across the crossing)
local RUNS = {
	{ "P1.NW", "P1.SE" },
	{ "P1.SE", "P1.NW" },
	{ "P1.NE", "P1.SW" },
	{ "P1.SW", "P1.NE" },
	{ "P2.W", "P2.E" },
	{ "P2.E", "P2.W" },
	{ "P3.S", "P3.N" },
	{ "P3.N", "P3.S" },
}

return function(t)
	local data = Data.default()
	local layout = SewerLayout.default() :: SewerLayout.Layout
	local baked = SewerStandIn.world(layout)
	local w = baked:motorWorld(data)
	local reg = w.registry
	local flat: SquirrelMotor.World = (function(): any
		local rail = RailWorld.empty()
		return {
			registry = rail.registry,
			index = rail.index,
			graph = rail.graph,
			groundAt = function(_x: number, _z: number, _y: number): number
				return 0
			end,
		}
	end)()

	local function mouth(id: string): Mouth
		return layout.mouth(id) :: Mouth
	end
	local function isSewer(routeId: number?): boolean
		return routeId ~= nil and layout.spaceOf(routeId) ~= nil
	end
	-- standing on the street at (x, z), facing (dx, dz)
	local function standing(x: number, z: number, dx: number, dz: number): State
		local s = SquirrelMotor.new(x, baked.groundAt(x, z, 50), z)
		s.yaw = math.atan2(dx, dz)
		return s
	end
	local function onMouth(m: Mouth, dx: number?, dz: number?): State
		return standing(m.x, m.z, dx or -m.out.x, dz or -m.out.z)
	end
	local function towards(a: Mouth, b: Mouth): number
		return BakedWorld.cameraYawToward(b.x - a.x, b.z - a.z)
	end
	local function press(s: State, cam: number, key: string): { SquirrelMotor.Event }
		local _, events = SquirrelMotor.step(s, BakedWorld.keys(cam, { [key] = true }), 1 / 60, w)
		return events
	end
	local function hold(cam: number, fields: { [string]: any }?): (number, State) -> SquirrelMotor.Input
		return function(): SquirrelMotor.Input
			return BakedWorld.keys(cam, fields or { fw = 1 })
		end
	end

	-- E on mouth A facing in, then W held (the view along the way to B) until the body steps out
	type Run = { trace: BakedWorld.Trace, state: State, seconds: number, railSeconds: number, emerged: boolean }
	local function runThrough(fromId: string, toId: string, keys: ((number, State) -> SquirrelMotor.Input)?): Run
		local a, b = mouth(fromId), mouth(toId)
		local s = onMouth(a)
		local cam = towards(a, b)
		local railFrames = 0
		local trace = BakedWorld.drive(w, s, 60 * 40, function(f: number, st: State): SquirrelMotor.Input
			if st.routeId ~= nil then
				railFrames += 1
			end
			if f == 1 then
				return BakedWorld.keys(cam, { grab = true })
			end
			return if keys then keys(f, st) else BakedWorld.keys(cam, { fw = 1 })
		end, {
			validator = true,
			stop = function(_st: State, f: number)
				return f > 2 and _st.routeId == nil
			end,
		})
		return {
			trace = trace,
			state = s,
			seconds = trace.seconds,
			railSeconds = railFrames / 60,
			emerged = BakedWorld.count(trace, "emerge") == 1,
		}
	end

	-- the same two mouths over the top: W held, the view turned toward each corner of the way in turn, on flat ground
	-- (the motor sets a level speed: slopes, the quay steps and the bridge's ramps do not slow it)
	local function walkOver(fromId: string, toId: string): number
		local way = layout.surfaceWalk(fromId, toId) :: SewerLayout.SurfaceWay
		local pts = way.points
		local s = SquirrelMotor.new(pts[1].x, 0, pts[1].z)
		s.yaw = math.atan2(pts[2].x - pts[1].x, pts[2].z - pts[1].z)
		local i = 2
		local trace = BakedWorld.drive(flat, s, 60 * 200, function(_f: number, st: State): SquirrelMotor.Input?
			while i < #pts and (pts[i].x - st.x) ^ 2 + (pts[i].z - st.z) ^ 2 < 1.0 do
				i += 1
			end
			return BakedWorld.keys(BakedWorld.cameraYawToward(pts[i].x - st.x, pts[i].z - st.z), { fw = 1 })
		end, {
			stop = function(st: State)
				return i == #pts and (pts[i].x - st.x) ^ 2 + (pts[i].z - st.z) ^ 2 < 1.0
			end,
		})
		return trace.seconds
	end

	t.test("in at a mouth with E, standing on it facing in; down the shaft, along, up, out on its feet", function()
		for _, run in RUNS do
			local a, b = mouth(run[1]), mouth(run[2])
			local r = runThrough(run[1], run[2])
			t.eq(BakedWorld.count(r.trace, "enter"), 1, `{run[1]}: E goes in`)
			t.truthy(r.emerged, `{run[1]} -> {run[2]}: out at the far mouth`)
			t.eq(r.trace.violations, 0, `{run[1]} -> {run[2]}: the server accepts every frame`)
			t.truthy(r.trace.maxStep < 0.8, `{run[1]}: no frame moves more than a stride ({r.trace.maxStep})`)
			for id in r.trace.routes do
				t.eq(layout.spaceOf(id), a.space, `{run[1]}: only its own pipe's routes ({id})`)
			end
			local s = r.state
			t.truthy(s.grounded and s.routeId == nil, `{run[2]}: on its feet`)
			t.truthy(math.sqrt((s.x - b.x) ^ 2 + (s.z - b.z) ^ 2) < 1.0, `{run[2]}: at the mouth ({s.x}, {s.z})`)
			t.near(s.y, b.y, 0.05, `{run[2]}: on the street`)
			t.truthy(s.vx * b.out.x + s.vz * b.out.z > 5, `{run[2]}: still running, out of the grate's rung side`)
			-- and on: W still held, it runs on along the street and nothing pulls it back in
			local on = BakedWorld.drive(w, s, 30, hold(towards(a, b)), { validator = true })
			t.eq(next(on.routes), nil, `{run[2]}: not pulled back in`)
			t.truthy(
				s.grounded and math.abs(s.y - baked.groundAt(s.x, s.z, s.y + 1)) < 0.05,
				`{run[2]}: on the street after`
			)
			t.eq(on.violations, 0)
		end
	end)

	t.test("no way in but E at a mouth: not facing out, not from beside it, not from the street over a pipe", function()
		for _, m in layout.mouths do
			local cam = BakedWorld.cameraYawToward(-m.out.x, -m.out.z)
			-- facing out of it
			local s = onMouth(m, m.out.x, m.out.z)
			press(s, cam, "grab")
			t.truthy(not isSewer(s.routeId), `{m.id}: E facing away`)
			-- beside it, facing in
			for _, off in { 2.5, 4 } do
				local sx, sz = m.x + m.out.z * off, m.z - m.out.x * off
				local b = standing(sx, sz, -m.out.x, -m.out.z)
				press(b, cam, "grab")
				t.truthy(not isSewer(b.routeId), `{m.id}: E {off} studs to the side`)
			end
			-- standing on it and facing in: E goes in, eased onto the mouth
			local e = onMouth(m)
			local ev = press(e, cam, "grab")
			t.eq(e.routeId, m.route, `{m.id}: E on the grate facing in`)
			t.near(e.railT, m.t, 1e-9)
			local entered = false
			for _, x in ev do
				entered = entered or x.kind == "enter"
			end
			t.truthy(entered)
		end
		-- the street over the pipes: the crossing, the road over each arm, the river over the culvert, the quays, the
		-- boulevard over P3, the lawn: E finds no sewer route (an open rail near enough may still be taken)
		local over = {
			{ 0, 0 },
			{ -2.26, 0 },
			{ -12, 12 },
			{ 12, -12 },
			{ 2148, 462 },
			{ 1990, 462 },
			{ 2310, 462 },
			{ 1344, 0 },
			{ 1330, -150 },
			{ 1308, -330 },
		}
		for _, q in over do
			for _, yaw in { 0, math.pi / 2, math.pi, -math.pi / 2 } do
				local s = standing(q[1], q[2], math.sin(yaw), math.cos(yaw))
				press(s, 0, "grab")
				t.truthy(not isSewer(s.routeId), `E at ({q[1]}, {q[2]}) facing {yaw}: {s.routeId}`)
			end
		end
	end)

	t.test(
		"walking across a grate does not go down; walking straight onto it heading in does (known gap N3)",
		function()
			for _, m in layout.mouths do
				-- across it, both ways, and out over its rung side from behind it: never in
				local sideX, sideZ = m.out.z, -m.out.x
				for _, dir in { { sideX, sideZ }, { -sideX, -sideZ }, { m.out.x, m.out.z } } do
					local s = standing(m.x - dir[1] * 5, m.z - dir[2] * 5, dir[1], dir[2])
					local tr = BakedWorld.drive(w, s, 60, hold(BakedWorld.cameraYawToward(dir[1], dir[2])))
					t.eq(next(tr.routes), nil, `{m.id}: walking across ({dir[1]}, {dir[2]})`)
				end
				-- straight at it heading in: Enclosure rule 1 takes it (the contract has no E-only mouth yet)
				local s = standing(m.x + m.out.x * 4, m.z + m.out.z * 4, -m.out.x, -m.out.z)
				local tr = BakedWorld.drive(w, s, 60, hold(BakedWorld.cameraYawToward(-m.out.x, -m.out.z)))
				t.truthy(
					tr.routes[m.route] == true,
					`{m.id}: walked in heading in (N3: report, then flip this when a hatch mouth lands)`
				)
			end
		end
	)

	t.test("each pipe beats its surface way with W held (P3 at the pipe pace)", function()
		local pace = Tunables.raw("sewer.speedMult")
		local street = Motion.C.railWalk
		for _, run in { { "P1.NW", "P1.SE" }, { "P1.NE", "P1.SW" }, { "P2.W", "P2.E" }, { "P3.S", "P3.N" } } do
			local r = runThrough(run[1], run[2])
			local over = walkOver(run[1], run[2])
			-- the pace the motor ran the rails at, from the route lengths and the time on them
			local a = mouth(run[1])
			local length = 0
			for id in r.trace.routes do
				length += (reg:get(id) :: any).length
			end
			local ran = length / r.railSeconds
			-- the rail time as it would be at the pipe pace (the identity once the motor applies route.speedMult)
			local atPace = r.seconds - r.railSeconds + r.railSeconds * ran / (street * pace)
			print(
				string.format(
					"      %s -> %s: pipe %.2f s (rails at %.1f st/s; %.2f s at x%.2f), over the top %.2f s",
					run[1],
					run[2],
					r.seconds,
					ran,
					atPace,
					pace,
					over
				)
			)
			t.truthy(atPace < over, `{run[1]}: the pipe at its pace beats the surface way`)
			if a.pipe ~= "P3" then
				t.truthy(r.seconds < over, `{run[1]}: the pipe beats the surface way at the street pace`)
			end
		end
	end)

	t.test(
		"nothing through walls: the body's section along every route meets nothing but the grate it slips through",
		function()
			for _, r in layout.routes do
				local route = reg:get(r.id) :: any
				local hit = {}
				for _, b in BakedWorld.clearance(baked, reg, route) do
					if b.name ~= "MouthCover" then
						table.insert(hit, `{b.path} t {b.t0}..{b.t1}`)
					end
				end
				t.eq(#hit, 0, `route {r.id}: {table.concat(hit, "; ")}`)
			end
		end
	)

	t.test("inside, away from the mouths: Space, Q, a click and E do nothing; S turns back", function()
		for _, r in layout.routes do
			local route = reg:get(r.id) :: any
			local spec = route.enclosure :: Enclosure.Spec
			local stations = 0
			for i = 0, 30 do
				local tt = 0.02 + 0.96 * i / 30
				if Enclosure.mouthAt(spec, route.length, tt) then
					continue
				end
				-- E at the crossing takes a fork (that is a way on, not out): leave the last stretch of an arm
				if spec.atEnd and (1 - tt) * route.length < Enclosure.C.linkWindow + 0.5 then
					continue
				end
				stations += 1
				for _, key in { "leap", "drop", "pounce", "grab" } do
					local q = reg:pointAt(route, tt)
					local s = SquirrelMotor.new(q.x, q.y, q.z)
					s.grounded = false
					s.routeId, s.railT, s.railDir = r.id, tt, 1
					local before = SquirrelMotor.clone(s)
					press(s, 0, key)
					t.eq(s.routeId, r.id, `{r.id} t {tt}: {key}`)
					t.near(s.railT, tt, 1e-9)
					t.eq(#SquirrelMotor.envelope(before, s, 1 / 60, w, false), 0)
				end
			end
			t.truthy(stations >= 20, `{r.id}: {stations} stations`)
			-- a turn-back half way along
			local q = reg:pointAt(route, 0.5)
			local s = SquirrelMotor.new(q.x, q.y, q.z)
			s.grounded = false
			s.routeId, s.railT, s.railDir = r.id, 0.5, 1
			local tan = reg:tangentAt(route, 0.5)
			local cam = BakedWorld.cameraYawToward(tan.x, tan.z)
			BakedWorld.drive(w, s, 20, hold(cam))
			local t1 = s.railT
			BakedWorld.drive(w, s, 20, hold(cam, { fw = -1 }))
			t.truthy(t1 > 0.5 and s.railT < t1, `{r.id}: on, then S back`)
		end
	end)

	t.test("the server: into a pipe from the street above, or out of one up through the road, is refused", function()
		for _, r in layout.routes do
			local route = reg:get(r.id) :: any
			local q = reg:pointAt(route, 0.5)
			local above = standing(q.x, q.z, 1, 0)
			local below = SquirrelMotor.new(q.x, q.y, q.z)
			below.grounded = false
			below.routeId, below.railT, below.railDir = r.id, 0.5, 1
			below.clock = above.clock + 1 / 60
			local into = {}
			for _, x in SquirrelMotor.envelope(above, below, 1 / 60, w, false) do
				into[x.code] = true
			end
			t.truthy(into.enclosure, `{r.id}: into the pipe from the street over it`)
			local out = SquirrelMotor.clone(below)
			out.routeId = nil
			out.x, out.y, out.z = above.x, above.y, above.z
			out.grounded = true
			out.clock = below.clock + 1 / 60
			local outOf = {}
			for _, x in SquirrelMotor.envelope(below, out, 1 / 60, w, false) do
				outOf[x.code] = true
			end
			t.truthy(outOf.enclosure, `{r.id}: out of the pipe up to the street`)
		end
	end)

	t.test("P1's crossing: W runs straight on; A or D turns into a side arm; both side arms are reachable", function()
		local a = mouth("P1.NW")
		local cam = towards(a, mouth("P1.SE"))
		local reached: { [string]: boolean } = {}
		for _, side in { -1, 1 } do
			local r = runThrough("P1.NW", "P1.SE", function(_f: number, st: State): SquirrelMotor.Input
				-- A or D once on the arm, 4 studs before the crossing
				local near = st.routeId == 9301 and (1 - st.railT) * (reg:get(9301) :: any).length < 4
				local fields: { [string]: any } = { fw = 1 }
				if near and st.selectedJunction == nil then
					fields.choose = side
				end
				return BakedWorld.keys(cam, fields)
			end)
			t.truthy(r.emerged, `side {side}: out`)
			t.eq(BakedWorld.count(r.trace, "forkTaken"), 1, `side {side}: the fork is taken as W passes the crossing`)
			local m = layout.nearestMouth(r.state.x, r.state.z, 2) :: Mouth
			t.truthy(m ~= nil and m.id ~= "P1.SE" and m.id ~= "P1.NW", `side {side}: out at a side arm's grate`)
			reached[m.id] = true
			t.eq(r.trace.violations, 0)
		end
		t.truthy(reached["P1.NE"] and reached["P1.SW"], "A and D lead to the two side arms")
	end)
end
