--!strict
-- The squirrel motor's rules on enclosed runs (Shared/Routes/Enclosure; SquirrelMotor; the envelope the server's
-- MoveValidator applies), each on a small authored world, and one hollow tree written in the tree-local frame the
-- hollow-trees survey proposes ([bearing, radius, height] about a harvested trunk) compiled into routes that the
-- real SquirrelMotor runs on the real harvest. The same rules on the bowling alley's ball return, on the real baked
-- building, are in attractions_runthrough.spec.
--
-- The small world (flat ground at y = 0, studs):
--   1  a duct (enclosure "t.duct"): in at a ground mouth at z = 0, down to y = -3, along under the ground, up to a
--      ledge mouth at z = 38, y = 2 (as the ball return comes up into its hood over the rack)
--   2  a bough crossing 4 studs above the duct at z = 20 (an open route within E's reach of it)
--   3  a climb (enclosure "t.tree", climb): a ground mouth at its foot, a knothole part-way linking bough 5, its top
--      linking bough 4; 6 is the tree's outside trunk 1.5 studs from it
--      (it says which side its wall is: `up`), a fork at t 0.15 into the dead-end pocket 12
--   7, 8  two routes of one enclosure joined by authored end links 6 studs apart; 9 an open route starting right
--      at 7's end (the old end-of-route switch would take it)
--   10 a dead end
--   11 a second passage of the same tree 3 studs from the climb through the wood (nothing authored joins them)
--   13 a level run with a "ground" hole in its side part-way
local Data = require("@shared/Data")
local Enclosure = require("@shared/Routes/Enclosure")
local Height = require("@shared/World/Height")
local Motion = require("@shared/Routes/Motion")
local Registry = require("@shared/Routes/Registry")
local SquirrelMotor = require("@shared/Movement/SquirrelMotor")
local MoveValidator = require("@server/Movement/MoveValidator")
local RouteAdapter = require("@server/AI/RouteAdapter")
local SquirrelController = require("@client/Controllers/Squirrel")
local BakedWorld = require("@tests/lib/BakedWorld")

type Rec = Registry.RouteRecord

local function length(points: { { number } }): number
	local Curve = require("@shared/Routes/Curve")
	local v = {}
	for i, p in points do
		v[i] = Curve.vec3(p[1], p[2], p[3])
	end
	return Curve.new(v):getLength()
end

local function route(id: number, kind: string, points: { { number } }, enclosure: any?): Rec
	return {
		id = id,
		name = `r{id}`,
		kind = kind,
		points = points,
		length = length(points),
		surfaceRadius = if kind == "trunk" then 1 else 0,
		visualOffset = if kind == "tunnel" then 0 else nil,
		enclosure = enclosure,
	}
end

local function smallWorld(): SquirrelMotor.World
	local recs: { Rec }
	recs = {
		route(1, "tunnel", {
			{ 0, 0, 0 },
			{ 0, -1, 4 },
			{ 0, -3, 8 },
			{ 0, -3, 14 },
			{ 0, -3, 20 },
			{ 0, -3, 26 },
			{ 0, -3, 30 },
			{ 0, -1, 34 },
			{ 0, 2, 36 },
			{ 0, 2, 38 },
		}, {
			id = "t.duct",
			mouths = { { t = 0, opens = "ground", name = "grille" }, { t = 1, opens = "ledge", name = "rack" } },
		}),
		route(2, "branch", { { -10, 1, 20 }, { 10, 1, 20 } }),
		route(3, "tunnel", { { 20, 0, 0 }, { 20, 5, 0 }, { 20, 10, 0 } }, {
			id = "t.tree",
			climb = true,
			up = { 0, 0, 1 }, -- the wall it clings to is on its -z side
			mouths = {
				{ t = 0, opens = "ground", out = { -1, 0, 0 } },
				{ t = 0.5, opens = "link", out = { 1, 0, 0 }, links = { { route = 5, t = 0, dir = 1 } } },
				-- no `out`: it leans out along bough 4 (Motion.mouthOut), never along the body's stale facing
				{ t = 1, opens = "link", links = { { route = 4, t = 0, dir = 1 } } },
			},
			forks = { { t = 0.15, route = 12, toT = 0, dir = 1, name = "pocket" } },
		}),
		route(4, "branch", { { 21, 10, 0 }, { 30, 10, 0 } }),
		route(5, "branch", { { 21.5, 5, 0 }, { 28, 5, 0 } }),
		route(6, "trunk", { { 20, 0, 1.5 }, { 20, 12, 1.5 } }),
		route(7, "tunnel", { { 40, -3, 0 }, { 40, -3, 20 } }, {
			id = "t.pair",
			mouths = { { t = 0, opens = "ground" } },
			atEnd = { route = 8, t = 0, dir = 1 },
		}),
		route(8, "tunnel", { { 40, -3, 26 }, { 40, -3, 40 } }, {
			id = "t.pair",
			atStart = { route = 7, t = 1, dir = -1 },
			mouths = { { t = 1, opens = "ground" } },
		}),
		route(9, "bridge", { { 40.2, -3, 20.2 }, { 50, -3, 20.2 } }),
		route(
			10,
			"tunnel",
			{ { 60, -3, 0 }, { 60, -3, 15 } },
			{ id = "t.dead", mouths = { { t = 0, opens = "ground" } } }
		),
		-- a second passage up the same tree, 3 studs from the climb through the wood: nothing authored joins them
		route(11, "tunnel", { { 20, 2, -3 }, { 20, 9, -3 } }, { id = "t.tree", climb = true, up = { 0, 0, 1 } }),
		-- a dead-end pocket off the climb at t 0.15, joined by the climb's fork and its own start link back; its end
		-- lies 0.8 studs from passage 11 (the old end-of-route switch would take it)
		route(12, "tunnel", { { 20, 1.5, 0 }, { 20, 1.5, -2.4 } }, {
			id = "t.tree",
			atStart = { route = 3, t = 0.15, dir = 1 },
		}),
		-- a level run with a hole in its side part-way (onto the ground beside it)
		route(13, "tunnel", { { 80, 0, 0 }, { 80, 0, 20 } }, {
			id = "t.side",
			mouths = {
				{ t = 0, opens = "ground" },
				{ t = 0.5, opens = "ground", out = { 1, 0, 0 }, depth = 0.4, name = "side hole" },
			},
		}),
	}
	-- the outside trunk stands closer to the climb's ground mouth than the walk-in reach; kept out of the walk-in
	-- here so the walk toward the mouth is not taken by it (a real hollow puts its ground hole at least 3.8 studs
	-- from the trunk's axis: Motion.C.walkInReach less Enclosure.C.reach; the SYCAMORE case below does)
	recs[6].flags =
		{ autoGrabExcluded = true, isPole = false, isGiant = false, fixedSurfaceZ = false, treeTravel = true }
	local data = BakedWorld.recordsData(recs)
	local rail = (require("@shared/Movement/RailWorld") :: any).build(data)
	return {
		registry = rail.registry,
		index = rail.index,
		graph = rail.graph,
		trampolines = {},
		groundAt = function(_x: number, _z: number, _refY: number): number
			return 0
		end,
		clamp = nil,
	}
end

-- a squirrel on the ground at (x, z) facing along (dx, dz), and the camera behind it
local function onGround(x: number, z: number, dx: number, dz: number): (SquirrelMotor.State, number)
	local s = SquirrelMotor.new(x, 0, z)
	s.yaw = math.atan2(dx, dz)
	return s, BakedWorld.cameraYawToward(dx, dz)
end

-- a squirrel already on a route at t, travelling dir
local function onRoute(w: SquirrelMotor.World, id: number, t: number, dir: number): SquirrelMotor.State
	local r = w.registry:get(id) :: Registry.Route
	local p = w.registry:pointAt(r, t)
	local s = SquirrelMotor.new(p.x, p.y, p.z)
	s.grounded = false
	s.routeId = id
	s.railT = t
	s.railDir = dir
	return s
end

local function hold(cam: number, fields: { [string]: any }?): (number, SquirrelMotor.State) -> SquirrelMotor.Input
	return function(_f: number, _s: SquirrelMotor.State): SquirrelMotor.Input
		return BakedWorld.keys(cam, fields or { fw = 1 })
	end
end

local function press(
	state: SquirrelMotor.State,
	w: SquirrelMotor.World,
	cam: number,
	key: string
): { SquirrelMotor.Event }
	local input = BakedWorld.keys(cam, { [key] = true })
	local _, events = SquirrelMotor.step(state, input, 1 / 60, w)
	return events
end

local function kinds(events: { SquirrelMotor.Event }): string
	local out = {}
	for _, e in events do
		table.insert(out, e.kind .. (if e.reason then ":" .. e.reason else ""))
	end
	return table.concat(out, ",")
end

return function(t)
	local w = smallWorld()

	t.test("in only at the mouth and only heading into it, eased on, never pulled from a distance", function()
		-- straight at the mouth from 6 studs out: in at the mouth, eased (no frame moves more than a stride)
		local s, cam = onGround(0, -6, 0, 1)
		local trace = BakedWorld.drive(w, s, 120, hold(cam), { validator = true })
		t.eq(BakedWorld.count(trace, "enter"), 1)
		t.truthy(trace.routes[1])
		t.truthy(trace.maxStep < 0.45, `largest move in one frame {trace.maxStep}`)
		t.eq(trace.violations, 0)
		local firstOn = 0
		for i, f in trace.frames do
			if f.routeId == 1 then
				firstOn = i
				break
			end
		end
		local before = trace.frames[firstOn - 1]
		local gap = math.sqrt(before.x ^ 2 + before.z ^ 2)
		t.truthy(gap <= Enclosure.C.reach + 0.35, `got in {gap} studs from the mouth`)
		-- running past the mouth, 1.5 studs to the side: not taken
		local p, camP = onGround(1.5, -6, 0, 1)
		local passing = BakedWorld.drive(w, p, 90, hold(camP))
		t.eq(BakedWorld.count(passing, "enter"), 0)
		-- running across in front of it (along the wall): not taken
		local a, camA = onGround(-4, -0.6, 1, 0)
		local across = BakedWorld.drive(w, a, 60, hold(camA))
		t.eq(BakedWorld.count(across, "enter"), 0)
		t.eq(next(across.routes), nil)
		-- walking back toward the mouth from its inside (over the duct): not taken
		local b, camB = onGround(0, 3, 0, -1)
		local back = BakedWorld.drive(w, b, 60, hold(camB))
		t.eq(BakedWorld.count(back, "enter"), 0)
		-- E standing at the mouth facing in goes in; facing away it does not
		local e, camE = onGround(0, -1, 0, 1)
		t.truthy(string.find(kinds(press(e, w, camE, "grab")), "enter", 1, true) ~= nil)
		t.eq(e.routeId, 1)
		local f, camF = onGround(0, -1, 0, -1)
		local ev = kinds(press(f, w, camF, "grab"))
		t.eq(f.routeId, nil, ev)
	end)

	t.test("inside, away from a mouth: Space, Q and a click do nothing; E finds nothing through the wall", function()
		local s = onRoute(w, 1, 0.5, 1)
		local cam = BakedWorld.cameraYawToward(0, 1)
		for _, key in { "leap", "drop", "pounce" } do
			local ev = press(s, w, cam, key)
			t.eq(s.routeId, 1, key)
			t.eq(kinds(ev), "hint:noRoom", key)
		end
		-- the bough 4 studs overhead is within E's reach (4.9 studs): not through the ceiling
		local under = onRoute(w, 1, 0, 1)
		under.railT = 0.52
		local p = w.registry:pointAt(w.registry:get(1) :: Registry.Route, 0.52)
		under.x, under.y, under.z = p.x, p.y, p.z
		local ev = press(under, w, cam, "grab")
		t.eq(under.routeId, 1)
		t.eq(kinds(ev), "hint:noTransfer")
		-- an open route at the same point would be caught in the air; the duct never is
		t.eq(Motion.airCatch(w, p.x, p.y, p.z, 0.5, nil), nil)
	end)

	t.test("from outside: E on the bough above or on the ground above does not drop into the duct", function()
		local cam = BakedWorld.cameraYawToward(1, 0)
		local onBough = onRoute(w, 2, 0.5, 1)
		local ev = press(onBough, w, cam, "grab")
		t.eq(onBough.routeId, 2, kinds(ev))
		local s = SquirrelMotor.new(0, 0, 20)
		ev = press(s, w, cam, "grab")
		t.truthy(s.routeId == nil or s.routeId == 2, kinds(ev))
		t.truthy(s.routeId ~= 1)
		local s2 = SquirrelMotor.new(0, 0, 10)
		press(s2, w, cam, "grab")
		t.eq(s2.routeId, nil, "10 studs off the bough, 3 above the duct: nothing")
	end)

	t.test("the far mouth: a ledge stops it with the head out (once); Space, a click or Q go out along it", function()
		local cam = BakedWorld.cameraYawToward(0, 1)
		local s = onRoute(w, 1, 0.8, 1)
		local trace = BakedWorld.drive(w, s, 120, hold(cam), { validator = true })
		t.eq(s.routeId, 1)
		t.near(s.railT, 1, 1e-9)
		t.eq(BakedWorld.count(trace, "lip"), 1, "one event per arrival")
		t.eq(BakedWorld.count(trace, "railEnd"), 0)
		t.eq(trace.violations, 0)
		-- Space: out along the mouth (+z), whatever the camera
		local leapCam = BakedWorld.cameraYawToward(1, 0)
		local before = SquirrelMotor.clone(s)
		press(s, w, leapCam, "leap")
		t.eq(s.routeId, nil)
		t.truthy(s.vz > 10 and math.abs(s.vx) < 1e-6, `leap along the mouth: {s.vx}, {s.vz}`)
		t.eq(#SquirrelMotor.envelope(before, s, 1 / 60, w, false), 0, "the server accepts it")
		BakedWorld.drive(w, s, 90, hold(leapCam, { fw = 0 }))
		t.truthy(s.grounded and s.z > 40, `landed beyond the mouth at z {s.z}`)
		-- a click and Q at the lip go out too
		local c = onRoute(w, 1, 1, 1)
		press(c, w, cam, "pounce")
		t.eq(c.routeId, nil)
		local q = onRoute(w, 1, 1, 1)
		press(q, w, cam, "drop")
		t.eq(q.routeId, nil)
		-- S goes back in
		local back = onRoute(w, 1, 1, 1)
		BakedWorld.drive(w, back, 30, hold(cam, { fw = -1 }))
		t.truthy(back.routeId == 1 and back.railT < 0.95)
	end)

	t.test("the near mouth: running back out steps onto the ground on its feet, still running", function()
		local cam = BakedWorld.cameraYawToward(0, -1)
		local s = onRoute(w, 1, 0.4, -1)
		local trace = BakedWorld.drive(w, s, 150, hold(cam), { validator = true })
		t.eq(BakedWorld.count(trace, "emerge"), 1)
		t.eq(BakedWorld.count(trace, "enter"), 0, "never pulled back in")
		t.eq(s.routeId, nil)
		t.truthy(s.grounded)
		t.truthy(s.z < -3, `ran on out of the mouth to z {s.z}`)
		t.eq(trace.violations, 0)
		-- the step out is continuous
		t.truthy(trace.maxStep < 0.6, `largest move {trace.maxStep}`)
	end)

	t.test("a turn-back inside works: W one way, then S, then W with the view turned round", function()
		local s = onRoute(w, 1, 0.5, 1)
		local fwd = BakedWorld.cameraYawToward(0, 1)
		BakedWorld.drive(w, s, 20, hold(fwd))
		local t1 = s.railT
		t.truthy(t1 > 0.5)
		BakedWorld.drive(w, s, 20, hold(fwd, { fw = -1 }))
		t.truthy(s.railT < t1)
		local t2 = s.railT
		BakedWorld.drive(w, s, 5, hold(fwd, { fw = 0 }))
		BakedWorld.drive(w, s, 20, hold(BakedWorld.cameraYawToward(0, -1)))
		t.truthy(s.railT < t2, "W with the view turned back runs back")
		t.eq(s.routeId, 1)
	end)

	t.test("a climb: W climbs whatever the view; a knothole's link by E; the top runs on onto its bough", function()
		-- in at the foot heading +x
		local s, cam = onGround(17, 0, 1, 0)
		local trace = BakedWorld.drive(w, s, 600, hold(cam), {
			validator = true,
			stop = function(st)
				return st.routeId == 4 and st.railT > 0.3
			end,
		})
		t.eq(BakedWorld.count(trace, "enter"), 1)
		t.truthy(trace.routes[3])
		t.eq(s.routeId, 4, "ran on onto the bough at the top")
		t.eq(trace.violations, 0)
		-- W climbs with the camera looking down the other way
		local c = onRoute(w, 3, 0.2, 1)
		BakedWorld.drive(w, c, 20, hold(BakedWorld.cameraYawToward(-1, 0)))
		t.truthy(c.railT > 0.2)
		-- at the knothole E takes its link; away from it E finds nothing (the outside trunk is 1.5 studs off)
		local k = onRoute(w, 3, 0.5, 1)
		local ev = kinds(press(k, w, cam, "grab"))
		t.eq(k.routeId, 5, ev)
		local inner = onRoute(w, 3, 0.3, 1)
		press(inner, w, cam, "grab")
		t.eq(inner.routeId, 3, "no grab through the bark")
		-- from the outside trunk: E does not get in (it may still take the side bough outside)
		for _, tt in { 0.1, 0.3, 0.5, 0.8 } do
			local out = onRoute(w, 6, tt, 1)
			press(out, w, cam, "grab")
			t.truthy(out.routeId ~= 3, `E on the outside trunk at t {tt}`)
		end
		-- back along bough 4 into the top of the climb, down it and out onto the ground
		local b = onRoute(w, 4, 0.3, -1)
		local down = BakedWorld.drive(w, b, 900, hold(BakedWorld.cameraYawToward(-1, 0)), {
			validator = true,
			stop = function(st)
				return st.routeId == nil and st.grounded
			end,
		})
		t.truthy(down.routes[3], "back into the climb from its bough")
		t.eq(BakedWorld.count(down, "emerge"), 1)
		BakedWorld.drive(w, b, 20, hold(BakedWorld.cameraYawToward(-1, 0)))
		t.truthy(b.x < 19 and b.grounded and b.routeId == nil, `out of the foot and away, at x {b.x}`)
		t.eq(down.violations, 0)
	end)

	t.test("authored end links: the junction is never guessed, both ways; a dead end says so once", function()
		local cam = BakedWorld.cameraYawToward(0, 1)
		local s = onRoute(w, 7, 0.8, 1)
		local trace = BakedWorld.drive(w, s, 120, hold(cam), {
			validator = true,
			stop = function(st)
				return st.routeId == 8 and st.railT > 0.2
			end,
		})
		t.eq(s.routeId, 8, "onto 8 by the authored link, not onto 9 right at 7's end")
		t.falsy(trace.routes[9])
		t.eq(trace.violations, 0, "the 6-stud authored link is a declared junction for the server")
		t.truthy(trace.maxStep < 0.6, `eased across: {trace.maxStep}`)
		-- S from 8 back through its start link to 7
		local back = BakedWorld.drive(w, s, 120, hold(cam, { fw = -1 }), {
			stop = function(st)
				return st.routeId == 7 and st.railT < 0.9
			end,
		})
		t.eq(s.routeId, 7)
		t.falsy(back.routes[9])
		-- a dead end: pinned, one railEnd however long W is held
		local d = onRoute(w, 10, 0.9, 1)
		local dead = BakedWorld.drive(w, d, 90, hold(cam))
		t.eq(BakedWorld.count(dead, "railEnd", "none"), 1)
		t.eq(d.routeId, 10)
	end)

	t.test("the server: honest runs pass; into or out of a duct through its wall is refused", function()
		local v = MoveValidator.new(w)
		local cam = BakedWorld.cameraYawToward(0, 1)
		-- honest: walk in, run the whole duct, leap out of the ledge mouth
		local s, c = onGround(0, -5, 0, 1)
		local clock = 0
		local seq = 0
		local function send(state: SquirrelMotor.State): any
			seq += 1
			clock += 1 / 60
			return v:accept("a", { seq = seq, snapshot = SquirrelMotor.serialize(state) }, clock)
		end
		send(s)
		local bad = 0
		for f = 1, 60 * 6 do
			local input = BakedWorld.keys(c, { fw = 1, leap = f == 60 * 5 })
			SquirrelMotor.step(s, input, 1 / 60, w)
			local verdict = send(s)
			if not verdict.ok then
				bad += 1
			end
		end
		t.eq(bad, 0, "honest run")
		-- cheats: from the ground above straight onto the duct; out of the duct up through the ground; from the bough
		-- overhead into the duct
		local function judge(prev: SquirrelMotor.State, next: SquirrelMotor.State): string
			local found = SquirrelMotor.envelope(prev, next, 1 / 60, w, false)
			local codes = {}
			for _, x in found do
				table.insert(codes, x.code)
			end
			return table.concat(codes, ",")
		end
		local above = SquirrelMotor.new(0, 0, 20)
		local inDuct = onRoute(w, 1, 0.5, 1)
		inDuct.clock = above.clock + 1 / 60
		t.truthy(string.find(judge(above, inDuct), "enclosure", 1, true) ~= nil, "in through the ground")
		local out = SquirrelMotor.clone(inDuct)
		out.routeId = nil
		out.y = 0
		out.grounded = true
		out.clock = inDuct.clock + 1 / 60
		t.truthy(string.find(judge(inDuct, out), "enclosure", 1, true) ~= nil, "out through the ground")
		local bough = onRoute(w, 2, 0.5, 1)
		local hop = onRoute(w, 1, 0.52, 1)
		hop.clock = bough.clock + 1 / 60
		t.truthy(string.find(judge(bough, hop), "enclosure", 1, true) ~= nil, "from the bough through the ceiling")
		local _ = cam
	end)

	t.test(
		"a hollow tree written in the tree-local frame compiles to routes the rules run (SYCAMORE, trunk 241)",
		function()
			local data = Data.default()
			local harvest = data:routes()
			local trunk = harvest:get(241) :: Registry.Route
			local foot = harvest:pointAt(trunk, 0)
			-- [bearing (degrees clockwise from +z seen from above), radius from the trunk's own axis, height above its foot]
			local function axisAt(height: number): (number, number, number)
				local lo, hi = 0, 1
				for _ = 1, 40 do
					local mid = (lo + hi) / 2
					if harvest:pointAt(trunk, mid).y < foot.y + height then
						lo = mid
					else
						hi = mid
					end
				end
				local p = harvest:pointAt(trunk, (lo + hi) / 2)
				return p.x, p.y, p.z
			end
			local function toWorld(b: number, r: number, h: number): { number }
				local x, y, z = axisAt(h)
				local a = math.rad(b)
				return { x + r * math.sin(a), y, z + r * math.cos(a) }
			end
			local function bearingOf(x: number, z: number, h: number): number
				local ax, _, az = axisAt(h)
				return math.deg(math.atan2(x - ax, z - az))
			end
			-- the hand-written record (as data/hollows.json would hold it): a ground hole and a floor, a shaft up the
			-- inside wall facing bough 248, a knothole onto bough 242 part-way, and the top onto bough 248
			-- where a bough comes out of the bark (2.6 studs from the axis): the link's t, the hole's bearing and height
			local function outside(b: Registry.Route): (number, Registry.Vec3)
				for i = 1, 200 do
					local tt = i / 400
					local p = harvest:pointAt(b, tt)
					local ax, _, az = axisAt(p.y - foot.y)
					if math.sqrt((p.x - ax) ^ 2 + (p.z - az) ^ 2) >= 2.6 then
						return tt, p
					end
				end
				return 0.5, harvest:pointAt(b, 0.5)
			end
			local b248 = harvest:get(248) :: Registry.Route
			local t248, out248 = outside(b248)
			local bearing248 = bearingOf(out248.x, out248.z, out248.y - foot.y)
			local top = out248.y - foot.y - 1
			local b242 = harvest:get(242) :: Registry.Route
			local t242, out242 = outside(b242)
			local bearing242 = bearingOf(out242.x, out242.z, out242.y - foot.y)
			local holeAt = toWorld(330, 4.4, 0)
			local holeH = Height.at(holeAt[1], holeAt[3]) - foot.y
			-- the knothole onto bough 242: where the shaft (straight up from height 1.4 to 33) passes the bough's height
			local knotT = (out242.y - foot.y - 1.4) / (top - 1.4)
			local a242 = math.rad(bearing242)
			-- the shaft clings to the wall on bough 248's side: its back (`up`) faces the trunk's axis
			local a248 = math.rad(bearing248)
			local shaftUp = { -math.sin(a248), 0, -math.cos(a248) }
			-- the bark's thickness from the shaft (0.9 out) to the outside: a launch through a hole starts beyond it
			local depth = trunk.surfaceRadius - 0.9 + 0.1
			-- a hideout pocket off the shaft at 15 studs, on the side away from the knothole (A/D picks it or the hole)
			local hideH = 15
			local hideT = (hideH - 1.4) / (top - 1.4)
			local hideBearing = bearing242 + 180
			local hollow = {
				{
					id = 9120,
					name = "hollow H2 ground hole and floor",
					kind = "tunnel",
					pts = {
						{ 330, 4.4, holeH },
						{ 330, 2.6, holeH + 0.2 },
						{ 330, 1.2, 0.5 },
						{ bearing248, 0.6, 0.9 },
					},
					enclosure = {
						id = "hollow.H2",
						mouths = { { t = 0, opens = "ground", name = "ground hole" } },
						atEnd = { route = 9121, t = 0, dir = 1 },
					},
				},
				{
					id = 9121,
					name = "hollow H2 shaft",
					kind = "tunnel",
					pts = {
						{ bearing248, 0.9, 1.4 },
						{ bearing248, 0.9, 12 },
						{ bearing248, 0.9, 24 },
						{ bearing248, 0.9, top },
					},
					enclosure = {
						id = "hollow.H2",
						climb = true,
						up = shaftUp,
						atStart = { route = 9120, t = 1, dir = -1 },
						forks = { { t = hideT, route = 9122, toT = 0, dir = 1, name = "hideout" } },
						mouths = {
							{
								t = knotT,
								opens = "link",
								out = { math.sin(a242), 0, math.cos(a242) },
								depth = depth,
								links = { { route = 242, t = t242, dir = 1 } },
								name = "knothole",
							},
							-- no `out`: it leans out along bough 248 (Motion.mouthOut)
							{
								t = 1,
								opens = "link",
								depth = depth,
								links = { { route = 248, t = t248, dir = 1 } },
								name = "top",
							},
						},
					},
				},
				{
					id = 9122,
					name = "hollow H2 hideout",
					kind = "tunnel",
					pts = {
						{ bearing248, 0.9, hideH },
						{ hideBearing, 0.6, hideH + 0.1 },
						{ hideBearing, 1.4, hideH + 0.2 },
					},
					enclosure = { id = "hollow.H2", atStart = { route = 9121, t = hideT, dir = 1 } },
				},
			}
			local recs: { Rec } = {}
			for _, r in harvest:all() do
				if r.origin == "attraction" then
					continue -- the town's harvested routes only (the alley's runs are far away)
				end
				local pts = {}
				for i, p in r.points do
					pts[i] = { p.x, p.y, p.z }
				end
				table.insert(recs, {
					id = r.id,
					name = r.name,
					kind = r.kind,
					points = pts,
					length = r.length,
					surfaceRadius = r.surfaceRadius,
					visualOffset = r.visualOffset,
					trunkClearance = r.trunkClearance,
					center = if r.center then { r.center.x, r.center.y, r.center.z } else nil,
					speedMult = r.speedMult,
					origin = r.origin,
					sampleCount = r.sampleCount,
					flags = r.flags,
				})
			end
			-- "compile": tree-local points to world, the knothole's t where the shaft passes bough 242, its out vector
			for _, h in hollow do
				local pts = {}
				for _, p in h.pts do
					table.insert(pts, toWorld(p[1], p[2], p[3]))
				end
				local rec = route(h.id, h.kind, pts, h.enclosure)
				rec.origin = "hollow"
				table.insert(recs, rec)
			end
			local errs = Enclosure.validateSet(
				{ recs[#recs - 2], recs[#recs - 1], recs[#recs] },
				{ [242] = true, [248] = true }
			)
			t.eq(#errs, 0, table.concat(errs, "; "))
			local hw = BakedWorld.recordsData(recs, data:forks())
			local rail = (require("@shared/Movement/RailWorld") :: any).build(hw)
			local linkErrs = Motion.enclosureErrors(rail.registry)
			t.eq(#linkErrs, 0, table.concat(linkErrs, "; "))
			local world: SquirrelMotor.World = {
				registry = rail.registry,
				index = rail.index,
				graph = rail.graph,
				trampolines = {},
				groundAt = function(x: number, z: number, _refY: number): number
					return Height.at(x, z)
				end,
				clamp = nil,
			}
			-- from 13 studs out on the hole's bearing, W only: in at the hole, across the floor, up the shaft, out on 248
			local start = toWorld(330, 13, 0)
			local s = SquirrelMotor.new(start[1], Height.at(start[1], start[3]), start[3])
			local hole = toWorld(330, 4.4, holeH)
			local cam = BakedWorld.cameraYawToward(hole[1] - start[1], hole[3] - start[3])
			local trace = BakedWorld.drive(world, s, 60 * 10, hold(cam), {
				validator = true,
				stop = function(st)
					return st.routeId == 248 and st.railT > 0.3
				end,
			})
			t.eq(BakedWorld.count(trace, "enter"), 1, "in at the ground hole")
			t.truthy(trace.routes[9120] and trace.routes[9121], "the floor and the shaft")
			if s.routeId ~= 248 then
				for _, e in trace.events do
					print(`      {e.frame} {e.kind} {e.routeId} {e.fromRouteId} {e.reason}`)
				end
				print(`      ended on {s.routeId} at t {s.railT}`)
			end
			t.eq(s.routeId, 248, "out on bough 248")
			t.truthy(trace.seconds < 7, `{trace.seconds} s`)
			t.eq(trace.violations, 0)
			-- the leaks the survey found are shut: E on the outside trunk stays outside; E on the shaft away from the
			-- knothole stays inside; E at the knothole goes out onto 242; Space on the shaft does nothing
			for _, tt in { 0.2, 0.5, 0.7 } do
				local o = onRoute(world, 241, tt, 1)
				press(o, world, cam, "grab")
				t.truthy(o.routeId ~= 9120 and o.routeId ~= 9121, `E on the outside trunk at t {tt}: {o.routeId}`)
			end
			local inside = onRoute(world, 9121, 0.2, 1)
			press(inside, world, cam, "grab")
			t.eq(inside.routeId, 9121)
			t.eq(kinds(press(inside, world, cam, "leap")), "hint:noRoom")
			local atKnot = onRoute(world, 9121, knotT, 1)
			press(atKnot, world, cam, "grab")
			t.eq(atKnot.routeId, 242, "out through the knothole")
			-- Q, Space and a click at the knothole start outside the bark (its depth) and land outside it
			local fx0, _, fz0 = axisAt(0)
			for _, key in { "drop", "leap", "pounce" } do
				local k = onRoute(world, 9121, knotT, 1)
				local before = SquirrelMotor.clone(k)
				press(k, world, cam, key)
				t.eq(k.routeId, nil, key)
				t.eq(#SquirrelMotor.envelope(before, k, 1 / 60, world, false), 0, `{key}: the server accepts it`)
				local ax, _, az = axisAt(k.y - foot.y)
				local r0 = math.sqrt((k.x - ax) ^ 2 + (k.z - az) ^ 2)
				t.truthy(r0 > trunk.surfaceRadius, `{key} starts {r0} studs from the axis, outside the bark`)
				local flight = BakedWorld.drive(world, k, 240, hold(cam, { fw = 0 }), {
					stop = function(st)
						return st.grounded or st.routeId ~= nil
					end,
				})
				local _ = flight
				if k.grounded then
					local rl = math.sqrt((k.x - fx0) ^ 2 + (k.z - fz0) ^ 2)
					t.truthy(rl > trunk.surfaceRadius, `{key} lands {rl} studs from the axis, outside the bark`)
				end
			end
			-- Space at the shaft's top (no `out` written) leaps along bough 248, whatever the view and the body's facing
			local tan248 = harvest:tangentAt(b248, t248)
			local want = math.atan2(tan248.x, tan248.z)
			for _, view in { 0, math.pi / 2, math.pi, -math.pi / 2 } do
				local s2 = onRoute(world, 9121, 1, 1)
				s2.yaw = view + 1.1
				press(s2, world, view, "leap")
				t.eq(s2.routeId, nil)
				local got = math.atan2(s2.vx, s2.vz)
				t.near(math.abs((got - want + math.pi) % (2 * math.pi) - math.pi), 0, 1e-6, `leap heading, view {view}`)
			end
			-- A/D on the way up picks the knothole or the hideout (one key each); W carries the body onto it
			local function climbWith(side: number, below: number): (number?, { [number]: boolean })
				local c = onRoute(world, 9121, math.max(0, below - 3 / (top - 1.4)), 1)
				local kx, kz = math.sin(a242), math.cos(a242)
				-- a view across the trunk, with the knothole to its right
				local camAcross = BakedWorld.cameraYawToward(kz, -kx)
				local seen = {}
				local tr = BakedWorld.drive(world, c, 300, function(f: number): SquirrelMotor.Input
					return BakedWorld.keys(camAcross, { fw = 1, choose = if f == 1 then side else 0 })
				end, {
					validator = true,
					stop = function(st)
						return st.routeId ~= 9121
					end,
				})
				for _, e in tr.events do
					seen[e.routeId or 0] = true
				end
				t.eq(tr.violations, 0)
				return c.routeId, seen
			end
			local right = climbWith(1, knotT)
			local left = climbWith(-1, hideT)
			t.eq(right, 242, "the key on the knothole's side takes the knothole")
			t.eq(left, 9122, "the other key takes the hideout")
			-- E on the shaft at the hideout takes it; E across the wood elsewhere takes nothing
			local atHide = onRoute(world, 9121, hideT, 1)
			press(atHide, world, cam, "grab")
			t.eq(atHide.routeId, 9122, "E at the hideout")
			local inPocket = onRoute(world, 9122, 0.9, 1)
			press(inPocket, world, cam, "grab")
			t.eq(inPocket.routeId, 9122, "E at the far end of the hideout reaches nothing through the wood")
			-- walking into the trunk elsewhere still climbs the outside trunk
			local far = toWorld(150, 9, 0)
			local f = SquirrelMotor.new(far[1], Height.at(far[1], far[3]), far[3])
			local fx, _, fz = axisAt(0)
			local fcam = BakedWorld.cameraYawToward(fx - far[1], fz - far[3])
			local walk = BakedWorld.drive(world, f, 120, hold(fcam), {
				stop = function(st)
					return st.routeId ~= nil
				end,
			})
			t.eq(f.routeId, 241, "the outside trunk, as before")
			t.eq(BakedWorld.count(walk, "enter"), 0)
		end
	)

	t.test(
		"a pounce at a ground mouth goes in during the flight and the attack ends; a leap over it does not",
		function()
			for _, dist in { 2, 3, 4, 6, 8 } do
				local s, cam = onGround(0, -dist, 0, 1)
				local trace = BakedWorld.drive(w, s, 90, function(f: number): SquirrelMotor.Input
					return BakedWorld.keys(cam, { pounce = f == 1 })
				end, {
					validator = true,
					stop = function(st)
						return st.routeId ~= nil
					end,
				})
				t.eq(s.routeId, 1, `a pounce from {dist} studs goes in`)
				t.eq(s.attackWindow, 0, "going in ends the attack")
				t.eq(BakedWorld.count(trace, "enter"), 1)
				t.truthy(trace.maxStep < 0.75, `eased in: {trace.maxStep}`)
				t.eq(trace.violations, 0)
			end
			-- the swept check: a flight crossing the mouth's disc within one substep is caught (faster than the reach)
			local p0 = Motion.mouthEntrySwept(w, 0, 0.5, -1.6, 0, 0.4, 1.0, 0, 50)
			t.truthy(p0 ~= nil and p0.routeId == 1, "the segment through the disc")
			t.eq(Motion.mouthEntry(w, 0, 0.5, -1.6, 0, 50), nil, "the start point alone is out of reach")
			t.eq(Motion.mouthEntrySwept(w, 0, 0.5, -1.6, 0, 0.4, 1.0, 0, -50), nil, "moving out: not in")
			-- a body pressed half its length past the mouth point (into an opening) still gets in; a body's length does not
			local pressed, camP = onGround(0, 0.7, 0, 1)
			BakedWorld.drive(w, pressed, 20, hold(camP))
			t.eq(pressed.routeId, 1, "0.7 studs past the mouth point, heading in")
			local deep, camD = onGround(0, 1.0, 0, 1)
			BakedWorld.drive(w, deep, 20, hold(camD))
			t.eq(deep.routeId, nil, "1 stud past: on the ground over the duct")
		end
	)

	t.test("launches at a mouth start outside its face; Q pushes out; a hole part-way lets E step out", function()
		-- the ledge mouth at z = 38: Q starts 0.9 studs out (Enclosure.C.clear) and moves on out
		local q = onRoute(w, 1, 1, 1)
		local before = SquirrelMotor.clone(q)
		press(q, w, BakedWorld.cameraYawToward(-1, 0), "drop")
		t.eq(q.routeId, nil)
		t.truthy(q.z > 38 + Enclosure.C.clear - 0.05, `Q starts outside the face (z {q.z})`)
		t.truthy(q.vz > 2, `and is pushed out along it ({q.vz})`)
		t.eq(#SquirrelMotor.envelope(before, q, 1 / 60, w, false), 0)
		-- the hole in run 13's side (depth 0.4): E at it steps out onto the ground beside the run, on its feet
		local side = onRoute(w, 13, 0.5 + 0.6 / 20, 1)
		local ev = kinds(press(side, w, BakedWorld.cameraYawToward(0, 1), "grab"))
		t.eq(side.routeId, nil, ev)
		t.truthy(string.find(ev, "emerge", 1, true) ~= nil, ev)
		t.truthy(side.x > 80 + 0.4 + Enclosure.C.clear - 0.05, `outside the hole (x {side.x})`)
		BakedWorld.drive(w, side, 30, hold(BakedWorld.cameraYawToward(1, 0), { fw = 0 }))
		t.truthy(side.grounded and side.x > 81, "on its feet beside the run")
		-- E away from the hole does nothing
		local away = onRoute(w, 13, 0.3, 1)
		press(away, w, BakedWorld.cameraYawToward(0, 1), "grab")
		t.eq(away.routeId, 13)
		-- and the hole is a way in: walking into it from the side, heading in
		local walker, camW = onGround(83, 10, -1, 0)
		BakedWorld.drive(w, walker, 60, hold(camW), {
			stop = function(st)
				return st.routeId ~= nil
			end,
		})
		t.eq(walker.routeId, 13, "in through the side hole")
	end)

	t.test("a vertical shaft's top launches along the bough it opens onto, never the body's stale facing", function()
		local cam = BakedWorld.cameraYawToward(0, -1)
		for _, yaw in { 0, 1.1, -2.5 } do
			for _, key in { "leap", "pounce" } do
				local s = onRoute(w, 3, 1, 1)
				s.yaw = yaw
				press(s, w, cam, key)
				t.eq(s.routeId, nil)
				t.truthy(s.vx > 5 and math.abs(s.vz) < 1e-6, `{key} with the body facing {yaw}: along bough 4 (+x)`)
			end
		end
		-- the data check: a vertical end mouth with nothing to lean out along is refused, as is a launch point
		-- inside a trunk's bark
		local bad = Registry.fromRecords({
			route(1, "tunnel", { { 0, 0, 0 }, { 0, 10, 0 } }, {
				id = "x",
				climb = true,
				up = { 1, 0, 0 },
				mouths = { { t = 0, opens = "ground", out = { -1, 0, 0 } }, { t = 1, opens = "air" } },
			}),
			route(2, "trunk", { { 5, 0, 0 }, { 5, 20, 0 } }),
			route(3, "tunnel", { { 5, 2, -0.5 }, { 5, 9, -0.5 } }, {
				id = "y",
				climb = true,
				up = { 0, 0, -1 },
				mouths = {
					{ t = 0, opens = "air", out = { 0, 0, 1 } },
					{ t = 0.6, opens = "air", out = { 0, 0, 1 }, depth = 1.0 },
				},
			}),
		})
		local errs = Motion.enclosureErrors(bad)
		local text = table.concat(errs, "; ")
		t.truthy(string.find(text, "route 1: mouth 2 has no level way out", 1, true) ~= nil, text)
		t.truthy(string.find(text, "route 3: mouth 1's launch point", 1, true) ~= nil, text)
		t.truthy(string.find(text, "route 3: mouth 2's launch point", 1, true) == nil, "deep enough: " .. text)
		-- and a ground hole within the walk-in grab of a climbable trunk's foot
		local near = Registry.fromRecords({
			route(1, "tunnel", { { 3, 0, 0 }, { 0.5, 0, 0 } }, { id = "z", mouths = { { t = 0, opens = "ground" } } }),
			route(2, "trunk", { { 0, 0, 0 }, { 0, 20, 0 } }),
		})
		local nearText = table.concat(Motion.enclosureErrors(near), "; ")
		t.truthy(string.find(nearText, "inside its walk-in grab", 1, true) ~= nil, nearText)
	end)

	t.test(
		"inside one tree only what is authored joins two passages: no E, end switch or server pass through wood",
		function()
			local cam = BakedWorld.cameraYawToward(1, 0)
			-- the climb at y 7 is 3 studs from passage 11 (within E's reach): nothing
			local s = onRoute(w, 3, 0.7, 1)
			local ev = kinds(press(s, w, cam, "grab"))
			t.eq(s.routeId, 3, ev)
			-- the pocket's dead end lies 0.8 studs from passage 11: pinned there, once, never switched across
			local p = onRoute(w, 12, 0.6, 1)
			local camP = BakedWorld.cameraYawToward(0, -1)
			local dead = BakedWorld.drive(w, p, 60, hold(camP))
			t.eq(p.routeId, 12)
			t.eq(BakedWorld.count(dead, "railEnd", "none"), 1)
			press(p, w, camP, "grab")
			t.eq(p.routeId, 12, "E at the pocket's end: nothing through the wood")
			-- and back out of the pocket by its start link onto the climb
			local back = BakedWorld.drive(w, p, 90, hold(camP, { fw = -1 }), {
				stop = function(st)
					return st.routeId ~= 12
				end,
			})
			t.eq(p.routeId, 3, "out of the pocket onto the climb")
			t.eq(back.violations, 0)
			-- the server: one frame from the climb to passage 11 is through the wood
			local a = onRoute(w, 3, 0.7, 1)
			local b = onRoute(w, 11, (7 - 2) / 7, 1)
			b.clock = a.clock + 1 / 60
			local codes = {}
			for _, x in SquirrelMotor.envelope(a, b, 1 / 60, w, false) do
				codes[x.code] = true
			end
			t.truthy(codes.enclosure, "climb to passage 11 across the wood")
			-- a late packet may hide two authored hops (bough 5, in at the knothole, down to the pocket's fork, into it);
			-- the same move in one frame may not, and nothing authored ever joins the climb to passage 11
			local function judged(from: SquirrelMotor.State, to: SquirrelMotor.State, dt: number): { [string]: boolean }
				to.clock = from.clock + dt
				local found = {}
				for _, x in SquirrelMotor.envelope(from, to, dt, w, false) do
					found[x.code] = true
				end
				return found
			end
			t.falsy(judged(onRoute(w, 5, 0.05, -1), onRoute(w, 12, 0.1, 1), 0.2).enclosure, "two hops in 0.2 s")
			t.truthy(judged(onRoute(w, 5, 0.05, -1), onRoute(w, 12, 0.1, 1), 1 / 60).enclosure, "not in one frame")
			t.truthy(judged(onRoute(w, 3, 0.7, 1), onRoute(w, 11, 5 / 7, 1), 0.2).enclosure, "nor through the wood")
			-- A/D at the pocket's fork, then W: onto the pocket; the knothole by the other key
			local function climbing(side: number): number?
				local c = onRoute(w, 3, 0.02, 1)
				BakedWorld.drive(w, c, 120, function(f: number): SquirrelMotor.Input
					return BakedWorld.keys(cam, { fw = 1, choose = if f == 1 then side else 0 })
				end, {
					stop = function(st)
						return st.routeId ~= 3
					end,
				})
				return c.routeId
			end
			t.eq(climbing(-1), 12, "A: the pocket on the left")
			t.eq(climbing(1), 5, "D: the knothole ahead on the right")
		end
	)

	t.test(
		"the section: an authored up on a climb; the default carried up a vertical stretch; the camera zone",
		function()
			local climb = w.registry:get(3) :: Registry.Route
			local sc = Motion.section(w, climb, 0.5) :: Motion.Section
			t.near(sc.up.z, 1, 1e-9, "the climb's back faces +z, its belly the wall at -z")
			t.near(sc.tangent.y, 1, 1e-9)
			t.near(math.abs(sc.side.x), 1, 1e-9)
			t.eq(sc.width, Enclosure.C.width)
			local duct = w.registry:get(1) :: Registry.Route
			local flat = Motion.section(w, duct, 0.5) :: Motion.Section
			t.truthy(flat.up.y > 0.99, "level: world up")
			t.eq(Motion.section(w, w.registry:get(2) :: Registry.Route, 0.5), nil, "an open route has none")
			-- any enclosed run gets the inside camera, whatever its origin (a hollow's routes are not "attraction")
			t.eq(SquirrelController.cameraZone(climb), "tunnel")
			t.eq(
				SquirrelController.cameraZone({
					id = 9,
					kind = "tunnel",
					length = 5,
					origin = "hollow",
					enclosure = climb.enclosure,
				}),
				"tunnel"
			)
			t.eq(SquirrelController.cameraZone(w.registry:get(2)), nil)
			t.eq(SquirrelController.cameraZone(nil), nil)
		end
	)

	t.test("the data check and the town's brains: links that reach, no AI step through a wall", function()
		t.eq(#Motion.enclosureErrors(w.registry), 0)
		local far = Registry.fromRecords({
			route(1, "tunnel", { { 0, 0, 0 }, { 0, 0, 10 } }, {
				id = "x",
				mouths = { { t = 0, opens = "ground" } },
				atEnd = { route = 2, t = 0, dir = 1 },
			}),
			route(
				2,
				"tunnel",
				{ { 0, 0, 30 }, { 0, 0, 40 } },
				{ id = "x", mouths = { { t = 1, opens = "link", links = { { route = 77, t = 0, dir = 1 } } } } }
			),
		})
		local errs = Motion.enclosureErrors(far)
		t.eq(#errs, 2, table.concat(errs, "; "))
		t.eq(#Motion.enclosureErrors(far, { [77] = true }), 1, "a route of another registry may be named")
		-- RouteAdapter (the AI's view of the routes): the bough over the duct and the outside trunk beside the climb
		-- are within a transfer of them, but no link crosses the wall; the climb's top still links its bough
		local a = RouteAdapter.new(w)
		local function linksOf(id: number): { [number]: boolean }
			local set = {}
			for _, l in (a.byId(id) :: any).links do
				set[l.to] = true
			end
			return set
		end
		t.truthy(w.graph:linked(1, 2), "the Graph sees the bough within a transfer of the duct")
		t.falsy(linksOf(2)[1])
		t.falsy(linksOf(1)[2])
		t.truthy(w.graph:linked(3, 6))
		t.falsy(linksOf(6)[3])
		t.truthy(linksOf(3)[4], "the climb's top links its bough")
		t.falsy(linksOf(3)[11], "nor the second passage through the wood")
		t.falsy(linksOf(11)[3])
	end)

	t.test("the player is told: no room inside, and what the keys do with the head out of an opening", function()
		local frame = { grab = false, leap = true }
		local noRoom = SquirrelController.feedback(frame, { { kind = "hint", reason = "noRoom" } }, true)
		t.truthy(noRoom ~= nil and string.find(noRoom, "No room", 1, true) ~= nil)
		local lip = SquirrelController.feedback({ grab = false }, { { kind = "lip", reason = "ledge" } }, true)
		t.truthy(lip ~= nil and string.find(lip, "Space", 1, true) ~= nil)
	end)
end
