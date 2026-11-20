--!strict
-- Validator round-14 review (w0-foundation 5b8fe36): failing cases. Each case is what the validator should do; each
-- fails on the round-14 code.
--   rail to rail     MEDIUM: a gap with BOTH ends on a rail refills its whole time and judges no off-rail leg (the
--                    round-13 MEDIUM's other half): a fence top to a telephone pole 77 st across, 1.5 s gaps and 0.2 s
--                    seen, 45 st/s for good with the meter full; along one fence 62 st per 1.19 s gap (52 st/s, its cap
--                    32) the same
--   grab search      MEDIUM (cost): a crafted 0.1 s launch packet in the air at the town's densest rails visits about
--                    34,500 index entries (1 to 2.5 ms; 884 and 0.1 ms before round 14); a client sends ten a second
--   0.13 s packets   MEDIUM (honest, new in round 14): the client's own send rule (SquirrelWire.SEND_EVERY after a frame
--                    capped at frameDtCap) makes packets of up to 0.13 s; an honest E+Space grab-leap in one of 0.11 to
--                    0.13 s is charged leapCost and its flight is no free one (grabSimDt 0.1); free before round 14
--   grab snap        MEDIUM (honest, before round 14 too): E+Space beside a fence top in an ordinary 0.05 s packet: the
--                    grab's snap onto the rail is no part of the short gap's horizontal test (a teleport, 0.85 of a flag)
-- About 5 s: `lune run tests/run.luau validator_r14rv`.
local SquirrelMotor = require("@shared/Movement/SquirrelMotor")
local SquirrelWire = require("@shared/Movement/SquirrelWire")
local ValidatorWorld = require("@server/Movement/ValidatorWorld")
local MoveValidator = require("@server/Movement/MoveValidator")
local MovementService = require("@server/Movement/MovementService")
local TestWorld = require("@tests/cheat/TestWorld")

type State = SquirrelMotor.State

return function(t)
	-- (flat ground at y 0, no walls: the TestWorld's own routes, the town's)
	local function flat(): (any, any)
		local tw = TestWorld.build({ boxes = {} })
		local function wall(): boolean
			return false
		end
		local function down(_ox: number, oy: number, _oz: number, _dx: number, dy: number, _dz: number): boolean
			return oy >= 0 and math.min(oy, oy + dy) <= 0
		end
		return tw, ValidatorWorld.build(tw, { wall = wall, down = down })
	end

	-- gaps between two rail places (route, t) A and B in turn, `gap` s each with `seen` s of 20 Hz packets on the rail after;
	-- through MovementService (enforcing) for `dur` s. Returns the snaps, the pace and the server's meter
	local function shuttle(
		a: { number },
		b: { number },
		gap: number,
		seen: number,
		dur: number
	): (number, number, number)
		local _, vworld = flat()
		local reg = vworld.registry
		local val = MoveValidator.new(vworld)
		local function place(e: { number }): State
			local p = reg:pointAt(reg:get(e[1]), e[2])
			local s = SquirrelMotor.new(p.x, p.y, p.z)
			s.routeId, s.railT, s.grounded = e[1], e[2], false
			return s
		end
		local pa, pb = place(a), place(b)
		local at = { x = pa.x, y = pa.y, z = pa.z }
		local snaps = 0
		local ms = MovementService.new({
			validator = val,
			enforce = true,
			poseOf = function(_a: any): (number, number, number)
				return at.x, at.y, at.z
			end,
			engine = {
				correct = function(_id: any, msg: any)
					if msg.snap then
						snaps += 1
					end
				end,
				pin = function(): boolean
					return true
				end,
				hold = function() end,
			},
		})
		ms:onHandoff({ id = "a", species = "squirrel" }, nil, "possess")
		local seq, now = 0, 100
		local function send(e: { number }, dt: number)
			local s = place(e)
			seq += 1
			now += dt
			s.clock = now - 90
			local _, ep, dec =
				SquirrelWire.decode(SquirrelWire.encode(seq, ms:epochOf("a"), SquirrelMotor.serialize(s)))
			ms:packet("a", "squirrel", { seq = seq, epoch = ep, snapshot = dec }, now)
			at.x, at.y, at.z = s.x, s.y, s.z
			ms:watch("a", s.x, s.y, s.z, now)
		end
		for _ = 1, 10 do
			send(a, 0.05)
		end
		local d = math.sqrt((pa.x - pb.x) ^ 2 + (pa.z - pb.z) ^ 2)
		local start, travelled = now, 0
		local there, here = b, a
		while now - start < dur do
			send(there, gap)
			travelled += d
			for _ = 1, math.floor(seen / 0.05 + 0.5) do
				send(there, 0.05)
			end
			there, here = here, there
		end
		local m = (val :: any)._actors.a
		return snaps, travelled / (now - start), if m then m.marks.stamina else 0 / 0
	end

	t.test("rail to rail: a gap with both ends on a rail judges its off-rail leg", function()
		-- route 11 (a cedar fence top, y 5.25) at t 0.025 and route 46 (a telephone pole, y 3.7) at t 0.06: 76.6 st across,
		-- open ground between; each gap 1.5 s (51 st/s), 0.2 s seen on the rail between (six gaps in ten seconds)
		local snaps, pace, meter = shuttle({ 11, 0.025 }, { 46, 0.06 }, 1.5, 0.2, 60)
		print(`      fence <-> pole: {string.format("%.1f", pace)} st/s for 60 s, {snaps} snaps, meter {meter}`)
		-- along ONE route: the fence top from t 0 to t 0.485 (61.8 st along it, straight), 1.19 s gaps, 0.5 s seen: 52 st/s
		-- along a route whose cap (railSprint x railTol) is 32
		local snaps2, pace2, meter2 = shuttle({ 11, 0 }, { 11, 0.485 }, 1.19, 0.5, 60)
		print(`      along the fence: {string.format("%.1f", pace2)} st/s for 60 s, {snaps2} snaps, meter {meter2}`)
		t.truthy(snaps > 0, "77 st of open ground between two rails every 1.7 s is faster than any honest leap and run")
		t.truthy(snaps2 > 0, "a fence run at 52 st/s in gaps is faster than the fence's own pace or a leap along it")
	end)

	t.test("grab search: a launch packet in the air costs a bounded number of index entries", function()
		local tw, vworld = flat()
		local index = vworld.index :: any
		local cs = index.cellSize
		-- the cell whose 7 x 7 x 7 neighbourhood holds the most samples (the densest crowns)
		local count: { [number]: number } = {}
		local key: { [number]: { number } } = {}
		for _, r in tw.registry:all() do
			for _, p in tw.registry:samples(r) do
				local ix, iy, iz = math.floor(p.x / cs), math.floor(p.y / cs), math.floor(p.z / cs)
				local k = (ix + 512) + (iy + 512) * 1024 + (iz + 512) * 1048576
				count[k] = (count[k] or 0) + 1
				key[k] = key[k] or { p.x, p.y, p.z }
			end
		end
		local cells = {}
		for k, n in count do
			table.insert(cells, { n = n, at = key[k] })
		end
		table.sort(cells, function(x, y)
			return x.n > y.n
		end)
		local best, at = -1, nil
		for i = 1, math.min(40, #cells) do
			local c = cells[i].at
			local m = 0
			index:forEachNear(c[1], c[2], c[3], 3, function(): boolean?
				m += 1
				return nil
			end)
			if m > best then
				best, at = m, c
			end
		end
		assert(at, "a dense neighbourhood")
		local hit = index:nearest(at[1], at[2], at[3], 20)
		-- prev: in the air 2 st beside a sample, falling; next: 0.1 s on, 2 st up, rising (a launch the grab search explains)
		local prev = SquirrelMotor.new(hit.x + 2, hit.y, hit.z + 2)
		prev.grounded, prev.vy, prev.clock = false, -2, 10
		local nxt = SquirrelMotor.new(hit.x + 5, hit.y + 2, hit.z + 2)
		nxt.grounded, nxt.vy, nxt.vx, nxt.clock = false, 20, 30, 10.1
		local visits = 0
		local fen, nea = index.forEachNear, index.nearest
		index.forEachNear = function(self: any, x: number, y: number, z: number, rc: number, fn: any)
			return fen(self, x, y, z, rc, function(...): boolean?
				visits += 1
				return fn(...)
			end)
		end
		index.nearest = function(self: any, x: number, y: number, z: number, md: number, ex: any, acc: any): any
			-- (nearest walks every entry of its cells: counted the same way)
			local r = math.ceil(md / cs)
			fen(self, x, y, z, r, function(): boolean?
				visits += 1
				return nil
			end)
			return nea(self, x, y, z, md, ex, acc)
		end
		local t0 = os.clock()
		local _f, _l, _p, judged = SquirrelMotor.envelope(prev, nxt, 0.1, vworld, false, nil)
		local ms = (os.clock() - t0) * 1000
		index.forEachNear, index.nearest = fen, nea
		print(
			`      densest neighbourhood {best} samples at ({math.floor(at[1])}, {math.floor(at[2])}, {math.floor(at[3])}): {visits} entries visited, {string.format(
				"%.3f",
				ms
			)} ms, railLaunch {judged.railLaunch}`
		)
		-- (one gather of the samples a 0.1 s packet can reach, then the patterns stepped over that list, is under 2,000)
		t.truthy(visits <= 2000, "the grab search's index work for one packet stays bounded")
	end)

	-- a body 4 st beside the fence top (route 11, y 5.25, x -207.5) leaps off the ground, rises past the fence's height
	-- (packets every 0.05 s), then the motor's E+Space: the frames given, one packet over them. Returns the server's meter
	-- before and after, whether the flight is a free one, and the violations
	local function grabLeap(
		frames: { number },
		at: number,
		when: (s: State) -> boolean
	): (number, number, boolean, { string })
		local tw, vworld = flat()
		local fence = tw.registry:get(11) :: any
		local a = tw.registry:pointAt(fence, 0.5)
		local s = SquirrelMotor.new(a.x + 4, tw.groundHeight, a.z)
		s.clock = 0
		local v = MoveValidator.new(vworld)
		local seq = 0
		local function feed(): any
			seq += 1
			return v:accept("a", { seq = seq, snapshot = SquirrelMotor.serialize(s) }, s.clock + 1)
		end
		feed()
		for _ = 1, 20 do
			SquirrelMotor.step(s, SquirrelMotor.idleInput(0), 0.05, tw)
			feed()
		end
		local i = SquirrelMotor.idleInput(0)
		i.fw, i.leap = 1, true
		SquirrelMotor.step(s, i, 0.05, tw)
		feed()
		for _ = 1, 40 do
			if when(s) then
				break
			end
			local j = SquirrelMotor.idleInput(0)
			j.fw = 1
			SquirrelMotor.step(s, j, 1 / 60, tw)
			feed()
		end
		local before = v._marks.a.stamina
		local leapt = false
		for k, dt in frames do
			local j = SquirrelMotor.idleInput(0)
			j.fw = 1
			if k == at then
				j.grab, j.leap = true, true
			end
			local _, ev = SquirrelMotor.step(s, j, dt, tw)
			for _, e in ev do
				leapt = leapt or (e.kind == "leap" and e.fromRouteId ~= nil)
			end
		end
		assert(leapt, "the motor's grab and rail leap")
		local r = feed()
		local list = {}
		for _, x in r.violations do
			table.insert(list, `{x.code}: {x.detail}`)
		end
		return before, v._marks.a.stamina, v._marks.a.speedRail == true, list
	end

	t.test("0.13 s packets: an honest grab-leap in a packet the client's send rule makes is free", function()
		local P = SquirrelMotor.params
		-- (the client sends once its motor clock has run SEND_EVERY: a short frame sends nothing, the next, capped at
		-- frameDtCap, sends a packet of up to SEND_EVERY + frameDtCap)
		print(
			`      longest honest packet {SquirrelWire.SEND_EVERY + P.frameDtCap} s; grabSimDt {SquirrelMotor.envelopeParams.grabSimDt}`
		)
		for _, pair in { { 0.03, 0.08 }, { 0.049, 0.08 } } do
			for _, at in { 1, 2 } do
				local before, after, free, list = grabLeap(pair, at, function(s: State): boolean
					return not s.grounded and s.y > 5.25 - 1
				end)
				print(
					`      {pair[1]} + {pair[2]} s, E+Space in frame {at}: meter {string.format("%.2f", before)} -> {string.format(
						"%.2f",
						after
					)}, free {free} [{table.concat(list, " | ")}]`
				)
				t.truthy(after >= before - 0.03, "the motor's rail leap costs nothing")
				t.truthy(free, "its flight is the rail leap's, a free one")
			end
		end
	end)

	t.test("grab snap: E+Space beside a fence top in an ordinary 0.05 s packet is no teleport", function()
		-- (near the leap's apex, 4 st beside the fence: the grab snaps the body onto it and the leap leaves from its drawn pose)
		local _, _, _, list = grabLeap({ 1 / 60, 1 / 60, 1 / 60 }, 1, function(s: State): boolean
			return not s.grounded and s.vy < 15
		end)
		print(`      [{table.concat(list, " | ")}]`)
		t.truthy(#list == 0, "the motor's own grab-leap, packets at 20 a second, no violation")
	end)
end
