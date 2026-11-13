--!strict
-- The ball return run through on the real building (brief v2 §13a; BRIEF_ADDENDUM D6): the bowling alley baked in
-- memory by the bake's own code (tests/lib/BakedWorld.bakeAlley), the real route data (Shared/Data: one enclosed run
-- per pair, Shared/Routes/Enclosure), the real SquirrelMotor driven with scripted keys, and the envelope the server's
-- MoveValidator applies. Local frame: X across the lanes, Y above the floor, D down the lane (AlleyLayout).
--
-- The last test is the duct builder's list: every part of the building as baked today that the animal's section
-- (Enclosure.BODY, crawling under the pits) passes through along each run. The list is exact: clearing a part makes
-- this spec fail until its line is struck out, and nothing new may get in the way.
local AlleyLayout = require("@shared/Attractions/AlleyLayout")
local Data = require("@shared/Data")
local Enclosure = require("@shared/Routes/Enclosure")
local Registry = require("@shared/Routes/Registry")
local SquirrelMotor = require("@shared/Movement/SquirrelMotor")
local MoveValidator = require("@server/Movement/MoveValidator")
local BakedWorld = require("@tests/lib/BakedWorld")

-- What stands in the animal's way along every pair's run on the building as baked today (paths under the alley's
-- Model; <p> the pair, <a>/<b> its two lanes). Each is a known failure the duct builder clears:
local KNOWN_BLOCKAGES = {
	-- the alley opening: 1.55 high for a 1.7-high body, and the ramp behind it baked backwards (Shell.luau rotates
	-- the wedge by pi, so its tall end faces the alley)
	"Tunnels.Tunnel<p>.VentFrameTop",
	"Tunnels.Tunnel<p>.VentLintel",
	"Tunnels.Tunnel<p>.VentRamp",
	-- dressing in the duct: wall ribs every 4 studs stand into a 1.6-wide body in the 1.7-wide duct; the spare pin,
	-- the joists and a lamp under the pits hang in its way
	"Tunnels.Tunnel<p>.Rib",
	"Tunnels.Tunnel<p>.SparePin",
	"Tunnels.Tunnel<p>.Joist",
	"Tunnels.Tunnel<p>.Lamp",
	-- under the pits: 1.23 of headroom, below even a crawl (1.3)
	"Tunnels.Tunnel<p>.Ceiling2",
	"Lanes.Lane<a>.PitFloor",
	"Lanes.Lane<b>.PitFloor",
	-- the kickback board between the pin decks hangs 1.2 into the duct (to Y -1.6) from D 50 to the pits
	"Masking.Kickback",
	-- the riser: its walls are narrower than the body, and no hole is cut where it rises through the floor
	"Tunnels.Tunnel<p>.RiserWall",
	"Tunnels.Tunnel<p>.Ceiling1",
	"Masking.Capping",
	"Approach.Approach<n>",
	"Lanes.Lane<a>.Gutter",
	"Lanes.Lane<b>.Gutter",
	"Lanes.Lane<a>.FoulLine",
	"Lanes.Lane<b>.FoulLine",
	-- the hood: a solid bonnet with the lift's chute, the dryer and a liner block in it, and a mouth 1.24 x 0.9
	"Returns.Return<p>.ChuteBack",
	"Returns.Return<p>.HoodBack",
	"Returns.Return<p>.Bonnet",
	"Returns.Return<p>.BonnetCapBack",
	"Returns.Return<p>.Dryer",
	"Returns.Return<p>.DryerGrille",
	"Returns.Return<p>.MouthLiner",
	"Returns.Return<p>.FaceTop",
	"Returns.Return<p>.FaceSide",
}
-- the approach floor slab the riser comes up through, per pair
local APPROACH = { 10, 8, 6 }

return function(t)
	local baked, place = BakedWorld.bakeAlley()
	local data = Data.default()
	local w = baked:motorWorld(data)
	local reg = w.registry
	local floorY = place.floorY

	local function runOf(p: number): Registry.Route
		return reg:get(9000 + 2 * p) :: Registry.Route
	end
	local function camAlong(dX: number, dD: number): number
		local dx, dz = AlleyLayout.dirToWorld(place, dX, dD)
		return BakedWorld.cameraYawToward(dx, dz)
	end
	local function local3(x: number, y: number, z: number): (number, number, number)
		return AlleyLayout.toLocal(place, x, y, z)
	end
	-- a squirrel standing on whatever the building has at (X, D) under a reference height Y, facing (dX, dD)
	local function standing(X: number, D: number, Y: number, dX: number, dD: number): SquirrelMotor.State
		local x, _, z = AlleyLayout.toWorld(place, X, 0, D)
		local s = SquirrelMotor.new(x, baked.groundAt(x, z, floorY + Y), z)
		local dx, dz = AlleyLayout.dirToWorld(place, dX, dD)
		s.yaw = math.atan2(dx, dz)
		return s
	end
	local function onRun(p: number, tt: number, dir: number): SquirrelMotor.State
		local r = runOf(p)
		local q = reg:pointAt(r, tt)
		local s = SquirrelMotor.new(q.x, q.y, q.z)
		s.grounded = false
		s.routeId = r.id
		s.railT = tt
		s.railDir = dir
		return s
	end
	local function hold(cam: number, fields: { [string]: any }?): (number, SquirrelMotor.State) -> SquirrelMotor.Input
		return function(): SquirrelMotor.Input
			return BakedWorld.keys(cam, fields or { fw = 1 })
		end
	end
	local function press(s: SquirrelMotor.State, cam: number, key: string): { SquirrelMotor.Event }
		local _, events = SquirrelMotor.step(s, BakedWorld.keys(cam, { [key] = true }), 1 / 60, w)
		return events
	end

	t.test(
		"in at the grille, heading in, eased; under the lane; out with its head at the rack (all three pairs)",
		function()
			for p = 1, 3 do
				local px = AlleyLayout.pairX(p)
				local s = standing(px, 92, AlleyLayout.ALLEY_Y + 1, 0, -1)
				local trace = BakedWorld.drive(w, s, 60 * 10, hold(camAlong(0, -1)), {
					validator = true,
					stop = function(st)
						return st.routeId == 9000 + 2 * p and st.railT >= 1
					end,
				})
				t.eq(BakedWorld.count(trace, "enter"), 1, `pair {p}: in at the grille`)
				-- where it got on: within the mouth's reach of the grille, never pulled from a distance
				local firstOn = 0
				for i, f in trace.frames do
					if f.routeId then
						firstOn = i
						break
					end
				end
				local before = trace.frames[firstOn - 1]
				local _, _, D0 = local3(before.x, before.y, before.z)
				t.truthy(D0 < 83.0 + Enclosure.C.reach + 0.35, `pair {p}: got in from D {D0}`)
				t.truthy(trace.maxStep < 0.4, `pair {p}: no frame moves more than a stride ({trace.maxStep})`)
				t.eq(trace.violations, 0, `pair {p}: the server accepts every frame`)
				t.truthy(trace.seconds < 7, `pair {p}: {trace.seconds} s from the alley to the rack`)
				local X, Y, D = local3(s.x, s.y, s.z)
				t.truthy(math.abs(X - px) < 0.01 and Y > AlleyLayout.RACK_Y - 0.1 and D < AlleyLayout.HOOD_D1 + 0.2)
				t.eq(BakedWorld.count(trace, "lip"), 1, `pair {p}: stops with its head out`)
			end
		end
	)

	t.test("not taken from the side or running along the wall; E from a distance gets nothing", function()
		local cam = camAlong(0, -1)
		for _, off in { 1.5, 2.5, 4, 5 } do
			local s = standing(off, 92, AlleyLayout.ALLEY_Y + 1, 0, -1)
			local trace = BakedWorld.drive(w, s, 60 * 3, hold(cam))
			t.eq(next(trace.routes), nil, `{off} studs to the side of the grille`)
		end
		local along = camAlong(1, 0)
		for _, dist in { 1.2, 1.8, 2.5, 3.5, 5.5 } do
			local s = standing(0.3, AlleyLayout.REAR_WALL_D + AlleyLayout.WALL_T + dist, AlleyLayout.ALLEY_Y + 1, 1, 0)
			local trace = BakedWorld.drive(w, s, 60 * 3, hold(along))
			t.eq(next(trace.routes), nil, `running along the wall {dist} studs out`)
			local X = local3(s.x, s.y, s.z)
			t.truthy(
				X > 15,
				`ran across the grille of pair 2 and past that of pair 3 (X {X}; trash cans stand along the wall west of it)`
			)
		end
		local e = standing(0, 88, AlleyLayout.ALLEY_Y + 1, 0, -1)
		press(e, cam, "grab")
		t.eq(e.routeId, nil, "E 5 studs from the grille")
		local e2 = standing(0, 84, AlleyLayout.ALLEY_Y + 1, 0, -1)
		local ev = press(e2, cam, "grab")
		t.eq(e2.routeId, 9004, "E at the grille facing in goes in")
		local _ = ev
	end)

	t.test("inside: Space, Q, a click and E do nothing, all the way along under the lane", function()
		local cam = camAlong(0, -1)
		local r = runOf(2)
		local stations = 0
		for i = 0, 40 do
			local tt = 0.03 + 0.94 * i / 40
			if Enclosure.mouthAt(r.enclosure :: Enclosure.Spec, r.length, tt) then
				continue
			end
			stations += 1
			for _, key in { "leap", "drop", "pounce", "grab" } do
				local s = onRun(2, tt, -1)
				press(s, cam, key)
				t.eq(s.routeId, 9004, `{key} at t {tt}`)
				t.near(s.railT, tt, 1e-9, `{key} at t {tt}`)
			end
		end
		t.truthy(stations >= 38)
	end)

	t.test("E on the floors above and beside it does not drop into the duct", function()
		local cam = camAlong(0, -1)
		local spots = {
			{ "lane 3's bed", AlleyLayout.laneX(3), 30, 1 },
			{ "the capping between lanes 3 and 4", 0, 30, 1 },
			{ "the approach beside the hood", 1.5, -2, 1 },
			{ "in front of the rack", 0, -7, 1 },
			{ "the back corridor", 0, 72, 1 },
			{ "the alley, 8 studs out", 0, 89.6, AlleyLayout.ALLEY_Y + 1 },
		}
		for _, spot in spots do
			local s = standing(spot[2] :: number, spot[3] :: number, spot[4] :: number, 0, -1)
			press(s, cam, "grab")
			t.eq(s.routeId, nil, spot[1] :: string)
		end
	end)

	t.test("the rack: Space jumps out toward the bowlers; a click too; Q drops onto the rack; S goes back", function()
		local camAway = camAlong(1, 0)
		local s = onRun(2, 1, -1)
		press(s, camAway, "leap")
		t.eq(s.routeId, nil)
		BakedWorld.drive(w, s, 30, hold(camAway, { fw = 0 }))
		local _, _, D = local3(s.x, s.y, s.z)
		t.truthy(D < AlleyLayout.HOOD_D1 - 5, `out toward the bowlers, whatever the view (D {D})`)
		local c = onRun(2, 1, -1)
		press(c, camAway, "pounce")
		t.eq(c.routeId, nil)
		local q = onRun(2, 1, -1)
		press(q, camAway, "drop")
		BakedWorld.drive(w, q, 60, hold(camAway, { fw = 0 }))
		local _, qY, qD = local3(q.x, q.y, q.z)
		t.truthy(q.grounded and qD < AlleyLayout.HOOD_D1 + 0.5 and qY > 0.5, `dropped onto the rack (Y {qY}, D {qD})`)
		local b = onRun(2, 1, -1)
		BakedWorld.drive(w, b, 30, hold(camAlong(0, -1), { fw = -1 }))
		t.truthy(b.routeId == 9004 and b.railT < 0.95, "S goes back down the hood")
	end)

	t.test("back out at the grille on its feet; a turn-back inside", function()
		local toAlley = camAlong(0, 1)
		local s = onRun(2, 0.4, -1)
		local trace = BakedWorld.drive(w, s, 60 * 4, hold(toAlley), { validator = true })
		t.eq(BakedWorld.count(trace, "emerge"), 1)
		t.eq(BakedWorld.count(trace, "enter"), 0, "never pulled back in")
		local _, Y, D = local3(s.x, s.y, s.z)
		t.truthy(s.grounded and s.routeId == nil, "on its feet")
		t.near(Y, AlleyLayout.ALLEY_Y, 0.05)
		t.truthy(D > 86, `ran on out into the alley (D {D})`)
		t.eq(trace.violations, 0)
		local u = onRun(2, 0.5, -1)
		BakedWorld.drive(w, u, 30, hold(camAlong(0, -1)))
		local t1 = u.railT
		BakedWorld.drive(w, u, 30, hold(camAlong(0, -1), { fw = -1 }))
		t.truthy(t1 > 0.5 and u.railT < t1, "toward the rack, then back")
	end)

	t.test(
		"the server: the honest run is accepted; into or out of the duct through the lane floor is refused",
		function()
			local v = MoveValidator.new(w)
			local s = standing(0, 92, AlleyLayout.ALLEY_Y + 1, 0, -1)
			local cam = camAlong(0, -1)
			local clock, seq, bad = 0, 0, 0
			local function send(state: SquirrelMotor.State): boolean
				seq += 1
				clock += 1 / 60
				return v:accept("sq", { seq = seq, snapshot = SquirrelMotor.serialize(state) }, clock).ok
			end
			send(s)
			for f = 1, 60 * 7 do
				SquirrelMotor.step(s, BakedWorld.keys(cam, { fw = 1, leap = f == 60 * 7 - 30 }), 1 / 60, w)
				if not send(s) then
					bad += 1
				end
			end
			t.eq(bad, 0, "the honest run, out of the hood and onto the approach")
			-- standing on lane 4's bed at D 30, the next packet claims the duct below
			local above = standing(0, 30, 1, 0, -1)
			local below = onRun(2, 0.4, -1)
			local _, _, bD = local3(below.x, below.y, below.z)
			local ax, _, az = AlleyLayout.toWorld(place, 0, 0, bD)
			above.x, above.z = ax, az
			above.y = baked.groundAt(ax, az, floorY + 1)
			below.clock = above.clock + 1 / 60
			local codes = {}
			for _, x in SquirrelMotor.envelope(above, below, 1 / 60, w, false) do
				codes[x.code] = true
			end
			t.truthy(codes.enclosure, "into the duct through the floor")
			local out = SquirrelMotor.clone(below)
			out.routeId = nil
			out.x, out.y, out.z = above.x, above.y, above.z
			out.grounded = true
			out.clock = below.clock + 1 / 60
			codes = {}
			for _, x in SquirrelMotor.envelope(below, out, 1 / 60, w, false) do
				codes[x.code] = true
			end
			t.truthy(codes.enclosure, "out of the duct up through the floor")
		end
	)

	t.test("the duct builder's list: what the building as baked today puts in the animal's way, by name", function()
		for p = 1, 3 do
			local expected: { [string]: boolean } = {}
			for _, name in KNOWN_BLOCKAGES do
				local n = string.gsub(name, "<p>", tostring(p))
				n = string.gsub(n, "<a>", tostring(2 * p - 1))
				n = string.gsub(n, "<b>", tostring(2 * p))
				n = string.gsub(n, "<n>", tostring(APPROACH[p]))
				expected[n] = true
			end
			local found: { [string]: boolean } = {}
			for _, b in BakedWorld.clearance(baked, reg, runOf(p)) do
				found[b.path] = true
			end
			local cleared, added = {}, {}
			for n in expected do
				if not found[n] then
					table.insert(cleared, n)
				end
			end
			for n in found do
				if not expected[n] then
					table.insert(added, n)
				end
			end
			table.sort(cleared)
			table.sort(added)
			t.eq(#added, 0, `pair {p}: new in the way: {table.concat(added, ", ")}`)
			t.eq(#cleared, 0, `pair {p}: cleared (strike them from KNOWN_BLOCKAGES): {table.concat(cleared, ", ")}`)
		end
	end)
end
