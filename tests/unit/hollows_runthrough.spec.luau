--!strict
-- The hollow trees and the fallen log run through on the real motor (brief v2 §3 "Hollow trees"; BRIEF_ADDENDUM D6;
-- Shared/World/HollowLayout over the enclosed-run contract, Shared/Routes/Enclosure): the routes as Shared/Data has
-- them, the shell the server builds (Server/World/HollowShell) loaded by tests/lib/BakedWorld, the real
-- SquirrelMotor driven with scripted keys (the view following the body, as the inside camera does), and the envelope
-- the server's MoveValidator applies to every frame.
--   in at every ground hole by walking or running into it (the run-through mouth style, as the ball return's
--   grille); not by walking past it, not from the outside trunk with E
--   a single chamber: across the floor to its dead end, S back out of the hole on its feet; S held on outside does
--   not take it back in (the log too); W does
--   the shaft and the escape tree: W climbs the wall to the top knothole and runs on along its bough; E at the
--   part-way knothole goes out onto the other bough; A or D on the way up picks the hideout or the knothole
--   the spiral: W climbs the ramp past its landings and runs out of the top knothole onto the outside trunk
--   the log: in at one end, out at the other, both ways
--   nothing of the shell through the bark: every corner of every piece (but the knothole ovals on it) inside the
--   bark mesh's flats less HollowLayout.C.barkClear, measured level from the leaning axis at its own height
--   nothing through walls: the body's section along every route meets nothing of the shell but the knothole's oval
--   it slips through; inside, away from a mouth, Space, Q, a click and E do nothing
--   out of sight inside: every chamber is hidden (Enclosure.hidden) and in its cavity (HollowLayout.contains); a
--   squirrel on the outside trunk is not
local roblox = require("@lune/roblox")
local Data = require("@shared/Data")
local Enclosure = require("@shared/Routes/Enclosure")
local HollowLayout = require("@shared/World/HollowLayout")
local SquirrelMotor = require("@shared/Movement/SquirrelMotor")
local HollowShell = require("@server/World/HollowShell")
local BakedWorld = require("@tests/lib/BakedWorld")

type State = SquirrelMotor.State

return function(t)
	local data = Data.default()
	local layout = HollowLayout.default() :: HollowLayout.Layout
	local model = HollowShell.build(roblox, layout)
	local baked = BakedWorld.fromModel(model)
	local w = baked:motorWorld(data)
	local reg = w.registry

	local function follow(st: State): number
		return BakedWorld.cameraYawToward(math.sin(st.yaw), math.cos(st.yaw))
	end
	local function onRoute(id: number, tt: number, dir: number): State
		local q = reg:pointAt(reg:get(id) :: any, tt)
		local s = SquirrelMotor.new(q.x, q.y, q.z)
		s.grounded = false
		s.routeId, s.railT, s.railDir = id, tt, dir
		return s
	end
	local function press(s: State, cam: number, key: string, value: any?): { SquirrelMotor.Event }
		local _, events =
			SquirrelMotor.step(s, BakedWorld.keys(cam, { [key] = if value ~= nil then value else true }), 1 / 60, w)
		return events
	end
	local function holeOf(h: HollowLayout.Hollow): HollowLayout.Mouth
		for _, m in h.mouths do
			if m.opens == "ground" then
				return m
			end
		end
		error(`{h.id}: no ground mouth`)
	end
	-- `dist` studs out from the hole, on its line, facing it
	local function outside(m: HollowLayout.Mouth, dist: number): (State, number)
		local ol = math.sqrt(m.out[1] ^ 2 + m.out[3] ^ 2)
		local ox, oz = m.out[1] / ol, m.out[3] / ol
		local x, z = m.x + ox * dist, m.z + oz * dist
		local s = SquirrelMotor.new(x, baked.groundAt(x, z, m.y + 3), z)
		s.yaw = math.atan2(-ox, -oz)
		return s, BakedWorld.cameraYawToward(-ox, -oz)
	end
	-- from 6 studs out, W toward the hole until it is in, then W with the view following the body
	local function runIn(h: HollowLayout.Hollow, stop: (State) -> boolean, frames: number?): (BakedWorld.Trace, State)
		local s, cam = outside(holeOf(h), 6)
		local trace = BakedWorld.drive(w, s, frames or 60 * 30, function(_f: number, st: State): SquirrelMotor.Input
			return BakedWorld.keys(if st.routeId then follow(st) else cam, { fw = 1 })
		end, {
			validator = true,
			stop = function(st: State)
				return stop(st)
			end,
		})
		return trace, s
	end
	local function report(trace: BakedWorld.Trace, s: State)
		for _, e in trace.events do
			print(`      {e.frame} {e.kind} {e.routeId} {e.fromRouteId} {e.reason}`)
		end
		print(`      ended on {s.routeId} at t {s.railT} ({s.x}, {s.y}, {s.z})`)
	end

	t.test("every hollow is built: 12 trees and the log, their routes in the Registry, the shell's parts", function()
		t.eq(#layout.hollows, 13)
		local claimable = 0
		for _, h in layout.hollows do
			if h.claimable then
				claimable += 1
			end
			for _, rid in h.routes do
				local r = reg:get(rid)
				t.truthy(r and r.enclosure and r.enclosure.id == h.space, `{h.id} route {rid}`)
			end
			t.truthy(#h.parts > 0, h.id)
		end
		t.eq(claimable, 12)
		for _, v in { "spiral", "shaft", "escape" } do
			local n = 0
			for _, h in layout.hollows do
				n += if h.variant == v then 1 else 0
			end
			t.eq(n, 1, v)
		end
	end)

	t.test("nothing of the shell through the bark: every corner inside the bark's flats, lean included", function()
		local C = HollowLayout.C
		for _, h in layout.hollows do
			if h.trunk == nil then
				continue
			end
			local tr = HollowLayout.trunk(reg, h.trunk)
			local pieces = {}
			for _, pc in h.parts do
				-- (a knothole's oval lies on the bark outside by design)
				if pc.role ~= "knothole" then
					table.insert(pieces, pc)
				end
			end
			local over = HollowLayout.barkOver(tr, pieces)
			t.truthy(
				over <= 1e-9,
				`{h.id}: a corner {string.format("%.3f", over + C.barkClear)} studs past the bark's flats less {C.barkClear}`
			)
		end
	end)

	t.test("nothing through walls: the body's section along every route meets no part of the shell", function()
		for _, r in layout.routes do
			local route = reg:get(r.id) :: any
			local hit = {}
			for _, b in BakedWorld.clearance(baked, reg, route) do
				if not string.find(b.name, "^knothole") then
					table.insert(hit, `{b.path} t {string.format("%.3f", b.t0)}..{string.format("%.3f", b.t1)}`)
				end
			end
			t.eq(#hit, 0, `route {r.id} {r.name}: {table.concat(hit, "; ")}`)
		end
	end)

	t.test("a single chamber: walk in at the hole, to the back, S back out on its feet", function()
		for _, h in layout.hollows do
			if h.variant ~= "knothole" then
				continue
			end
			local rid = h.routes[1]
			local trace, s = runIn(h, function(st)
				return st.routeId == rid and st.railT > 0.995
			end, 60 * 8)
			if s.routeId ~= rid then
				report(trace, s)
			end
			t.eq(BakedWorld.count(trace, "enter"), 1, `{h.id}: in at the hole`)
			t.eq(s.routeId, rid, `{h.id}: at the back`)
			t.eq(trace.violations, 0, `{h.id}: the server accepts the way in`)
			local back = BakedWorld.drive(w, s, 60 * 8, function(_f: number, st: State): SquirrelMotor.Input
				return BakedWorld.keys(follow(st), { fw = -1 })
			end, {
				validator = true,
				stop = function(st: State)
					return st.routeId == nil
				end,
			})
			t.eq(s.routeId, nil, `{h.id}: S runs back out`)
			t.truthy(s.grounded, `{h.id}: on its feet`)
			t.eq(back.violations, 0, `{h.id}: the server accepts the way out`)
		end
	end)

	t.test("S held on after backing out leaves the body outside (the hole does not take it back); W goes in", function()
		for _, h in layout.hollows do
			if h.variant ~= "knothole" and h.variant ~= "log" then
				continue
			end
			local rid = h.routes[1]
			local deep = if h.variant == "log" then 0.5 else 0.99
			local _, s = runIn(h, function(st)
				return st.routeId == rid and st.railT >= deep
			end, 60 * 8)
			t.eq(s.routeId, rid, `{h.id}: inside`)
			-- S for 3 s, the view following the body inside and left where it was outside (as the camera does)
			local cam = follow(s)
			local held = BakedWorld.drive(w, s, 60 * 3, function(_f: number, st: State): SquirrelMotor.Input
				if st.routeId then
					cam = follow(st)
				end
				return BakedWorld.keys(cam, { fw = -1 })
			end, { validator = true })
			t.eq(BakedWorld.count(held, "emerge"), 1, `{h.id}: out once`)
			t.eq(BakedWorld.count(held, "enter"), 0, `{h.id}: not taken back in while S is held`)
			t.eq(s.routeId, nil, `{h.id}: outside`)
			t.eq(held.violations, 0, `{h.id}: the server accepts it`)
			-- in again, S until it is out, the key let go a frame, then W into the hole: it goes back in
			local _, s2 = runIn(h, function(st)
				return st.routeId == rid and st.railT >= deep
			end, 60 * 8)
			BakedWorld.drive(w, s2, 60 * 3, function(): SquirrelMotor.Input
				return BakedWorld.keys(follow(s2), { fw = -1 })
			end, {
				stop = function(st: State)
					return st.routeId == nil
				end,
			})
			t.eq(s2.routeId, nil, `{h.id}: out`)
			local m = holeOf(h)
			local inward = BakedWorld.cameraYawToward(-m.out[1], -m.out[3])
			press(s2, inward, "fw", 0)
			local back = BakedWorld.drive(w, s2, 60, function(): SquirrelMotor.Input
				return BakedWorld.keys(inward, { fw = 1 })
			end, { validator = true })
			t.eq(BakedWorld.count(back, "enter"), 1, `{h.id}: W goes back in`)
			t.eq(s2.routeId, rid, `{h.id}: on its run`)
		end
	end)

	t.test("walking past a hole, or along the bark, does not go in", function()
		for _, h in layout.hollows do
			if h.variant == "log" then
				continue
			end
			local m = holeOf(h)
			local ol = math.sqrt(m.out[1] ^ 2 + m.out[3] ^ 2)
			local ox, oz = m.out[1] / ol, m.out[3] / ol
			-- across the hole's face, 2.5 studs out, square to its line
			local sx, sz = m.x + ox * 2.5 - oz * 6, m.z + oz * 2.5 + ox * 6
			local s = SquirrelMotor.new(sx, baked.groundAt(sx, sz, m.y + 3), sz)
			local cam = BakedWorld.cameraYawToward(oz, -ox)
			local trace = BakedWorld.drive(w, s, 60 * 2, function(): SquirrelMotor.Input
				return BakedWorld.keys(cam, { fw = 1 })
			end)
			for rid in trace.routes do
				t.truthy(layout.spaceOf(rid) == nil, `{h.id}: walking past took {rid}`)
			end
		end
	end)

	t.test("the shaft and the escape tree: W climbs to the top knothole and runs on along its bough", function()
		for _, h in layout.hollows do
			if h.variant ~= "shaft" and h.variant ~= "escape" then
				continue
			end
			local shaftId = h.routes[2]
			local top = (reg:get(shaftId) :: any).enclosure.mouths[2]
			local bough = top.links[1].route
			local trace, s = runIn(h, function(st)
				return st.routeId == bough
			end)
			if s.routeId ~= bough then
				report(trace, s)
			end
			t.eq(s.routeId, bough, `{h.id}: out on bough {bough}`)
			t.truthy(trace.routes[h.routes[1]] and trace.routes[shaftId], `{h.id}: the floor and the shaft`)
			t.eq(trace.violations, 0, h.id)
			-- E at the part-way knothole: out onto its bough
			local knot = (reg:get(shaftId) :: any).enclosure.mouths[1]
			local k = onRoute(shaftId, knot.t, 1)
			press(k, 0, "grab")
			t.eq(k.routeId, knot.links[1].route, `{h.id}: E at the knothole`)
			-- E, Space, Q and a click away from both: nothing
			for _, tt in { 0.15, (knot.t + 1) / 2 } do
				if math.abs(tt - knot.t) * (reg:get(shaftId) :: any).length < 3 then
					continue
				end
				for _, key in { "grab", "leap", "drop", "pounce" } do
					local i = onRoute(shaftId, tt, 1)
					local before = SquirrelMotor.clone(i)
					press(i, 0, key)
					t.eq(i.routeId, shaftId, `{h.id} t {tt}: {key}`)
					t.eq(#SquirrelMotor.envelope(before, i, 1 / 60, w, false), 0)
				end
			end
		end
	end)

	t.test("the shaft's hideout: A or D on the way up picks it, W carries the body onto the shelf", function()
		local h = layout.hollow("H2") :: HollowLayout.Hollow
		local shaftId, hideId = h.routes[2], h.routes[3]
		local fork = ((reg:get(shaftId) :: any).enclosure.forks :: { any })[1]
		local reached = false
		for _, side in { -1, 1 } do
			local c = onRoute(shaftId, math.max(0, fork.t - 0.08), 1)
			local tr = BakedWorld.drive(w, c, 60 * 4, function(f: number, st: State): SquirrelMotor.Input
				return BakedWorld.keys(follow(st), { fw = 1, choose = if f == 1 then side else 0 })
			end, {
				validator = true,
				stop = function(st: State)
					return st.routeId ~= shaftId
				end,
			})
			t.eq(tr.violations, 0)
			reached = reached or tr.routes[hideId] == true
		end
		t.truthy(reached, "one of A or D takes the hideout")
	end)

	t.test("the spiral: W climbs the ramp past its landings and out of the top knothole onto the trunk", function()
		local h = layout.hollow("H1") :: HollowLayout.Hollow
		local rampId = h.routes[2]
		local trunk = h.trunk :: number
		local trace, s = runIn(h, function(st)
			return st.routeId == trunk
		end, 60 * 60)
		if s.routeId ~= trunk then
			report(trace, s)
		end
		t.eq(s.routeId, trunk, "out on the outside trunk")
		t.truthy(trace.routes[rampId], "up the ramp")
		t.eq(trace.violations, 0)
		t.truthy(#h.chambers == 3, "three landings")
		print(`      the spiral: in at the hole to out at the top in {string.format("%.1f", trace.seconds)} s`)
		-- S on the ramp goes down
		local d = onRoute(rampId, 0.5, 1)
		local down = BakedWorld.drive(w, d, 60, function(_f: number, st: State): SquirrelMotor.Input
			return BakedWorld.keys(follow(st), { fw = -1 })
		end, { validator = true })
		t.truthy(d.routeId == rampId and d.railT < 0.5, `S goes down: t {d.railT}`)
		t.eq(down.violations, 0)
	end)

	t.test("E on the outside trunk stays outside (but the spiral's top knothole, which is linked to it)", function()
		for _, h in layout.hollows do
			if h.trunk == nil then
				continue
			end
			for _, tt in { 0.05, 0.12, 0.2, 0.35 } do
				local o = onRoute(h.trunk :: number, tt, 1)
				local y0 = o.y - h.y
				press(o, 0, "grab")
				if h.variant == "spiral" and math.abs(y0 - 34) < 3 then
					continue
				end
				t.truthy(layout.spaceOf(o.routeId or 0) == nil, `{h.id}: E on its trunk at t {tt} took {o.routeId}`)
			end
		end
	end)

	t.test("the log: in at one end, out at the other, both ways", function()
		local h = layout.hollow("LOG") :: HollowLayout.Hollow
		local rid = h.routes[1]
		for i, m in h.mouths do
			local other = h.mouths[3 - i]
			local s, cam = outside(m, 5)
			local trace = BakedWorld.drive(w, s, 60 * 10, function(_f: number, _st: State): SquirrelMotor.Input
				return BakedWorld.keys(cam, { fw = 1 })
			end, {
				validator = true,
				stop = function(st: State)
					return st.routeId == nil
						and st.grounded
						and (st.x - other.x) ^ 2 + (st.z - other.z) ^ 2 > 4
						and (st.x - other.x) * other.out[1] + (st.z - other.z) * other.out[3] > 0
				end,
			})
			if not trace.routes[rid] then
				report(trace, s)
			end
			t.truthy(trace.routes[rid], `in at end {i}`)
			t.eq(BakedWorld.count(trace, "emerge"), 1, `out at the other end ({i})`)
			t.eq(trace.violations, 0)
		end
	end)

	t.test("out of sight inside: chambers hidden and in their cavity; the outside trunk is not", function()
		for _, h in layout.hollows do
			for _, c in h.chambers do
				local r = reg:get(c.route) :: any
				t.truthy(Enclosure.hidden(r, c.t), `{h.id} {c.id}: hidden`)
				t.eq(layout.contains(c.x, c.y + 0.8, c.z), h.space, `{h.id} {c.id}: in the cavity`)
			end
			if h.trunk then
				local tr = reg:get(h.trunk :: number) :: any
				for _, tt in { 0.02, 0.1, 0.2 } do
					-- the drawn body on the bark: the surface radius and a body's half out from the axis
					local p = reg:pointAt(tr, tt)
					for _, a in { 0, 90, 180, 270 } do
						local rr = tr.surfaceRadius + 0.6
						local x, z = p.x + rr * math.sin(math.rad(a)), p.z + rr * math.cos(math.rad(a))
						t.eq(layout.contains(x, p.y, z), nil, `{h.id}: on its bark at t {tt}, bearing {a}`)
					end
				end
			end
		end
	end)

	t.test("the server refuses a body put into a hollow through the bark, or out of one through it", function()
		local function judge(prev: State, nxt: State): string
			local codes = {}
			for _, x in SquirrelMotor.envelope(prev, nxt, 1 / 60, w, false) do
				table.insert(codes, x.code)
			end
			return table.concat(codes, ",")
		end
		for _, h in layout.hollows do
			if h.trunk == nil then
				continue
			end
			for _, rid in h.routes do
				local r = reg:get(rid) :: any
				for _, tt in { 0.5, 0.9 } do
					if Enclosure.mouthNear(r.enclosure, r.length, tt, 0.5) then
						continue
					end
					local inside = onRoute(rid, tt, 1)
					-- from the outside trunk at the same height, one frame before
					local tr = reg:get(h.trunk :: number) :: any
					local lo, hi = 0, 1
					for _ = 1, 30 do
						local mid = (lo + hi) / 2
						if reg:pointAt(tr, mid).y < inside.y then
							lo = mid
						else
							hi = mid
						end
					end
					local onBark = onRoute(h.trunk :: number, lo, 1)
					inside.clock = onBark.clock + 1 / 60
					local code = judge(onBark, inside)
					t.truthy(
						string.find(code, "enclosure", 1, true) ~= nil,
						`{h.id} {rid} t {tt}: in through the bark ({code})`
					)
					local back = SquirrelMotor.clone(onBark)
					back.clock = inside.clock + 1 / 60
					local code2 = judge(inside, back)
					t.truthy(
						string.find(code2, "enclosure", 1, true) ~= nil,
						`{h.id} {rid} t {tt}: out through it ({code2})`
					)
				end
			end
		end
	end)
end
