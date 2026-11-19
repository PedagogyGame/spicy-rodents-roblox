--!strict
-- Validator round 6 (the round-5 review's findings, fixed, and two invariants that hold whatever path a packet takes):
--   anchor     invariant A: every packet the server takes is judged from a place it holds (the last accepted, the gate,
--              the root it saw), never where the packet says; the rail a packet claims agrees with its x, y, z on every
--              packet (fieldCheck); a first packet with no place to judge it from is not taken
--   governor   invariant B: over every window of up to 3 s of accepted places, the horizontal distance and the net rise
--              stay within what an honest squirrel covers (MoveValidator.governorBounds, from the motor's constants):
--              honest play never trips it (2 to 30 packets a second, clocks x0.8 to x1.2, 300 ms + 250 ms jitter, 2 %
--              loss: the closest calls printed), the motor's own leap-and-regrab climb and a leap along the steepest
--              bough regrabbed above the body are clean, every check of the envelope switched off it still catches the
--              round-5 review's teleports, and a snap buys no new allowance
--   cover      a long line asks the cover over each wall it clears over its top (C.COVER_WALLS), not the first only
local SquirrelMotor = require("@shared/Movement/SquirrelMotor")
local SquirrelWire = require("@shared/Movement/SquirrelWire")
local MoveValidator = require("@server/Movement/MoveValidator")
local MovementService = require("@server/Movement/MovementService")
local ValidatorWorld = require("@server/Movement/ValidatorWorld")
local TestWorld = require("@tests/cheat/TestWorld")
local Harness = require("@tests/cheat/Harness")
local Driver = require("@tests/cheat/Driver")

type State = SquirrelMotor.State

local TICK = 1 / 60

local function worldWith(boxes: { TestWorld.Box }): (any, any)
	local world = TestWorld.build({ boxes = boxes })
	local function wall(ox: number, oy: number, oz: number, dx: number, _dy: number, dz: number): boolean
		return TestWorld.segmentCrossesBox(boxes, ox, oz, ox + dx, oz + dz, oy)
	end
	local function down(_ox: number, oy: number, _oz: number, _dx: number, dy: number, _dz: number): boolean
		local lo = oy + dy
		return lo <= 0 and oy >= 0
	end
	return world, ValidatorWorld.build(world, { wall = wall, down = down })
end

local function codesOf(list: { { code: string } }): string
	local out = {}
	for _, v in list do
		table.insert(out, v.code)
	end
	return table.concat(out, ",")
end

local function has(list: { { code: string } }, code: string): boolean
	for _, v in list do
		if v.code == code then
			return true
		end
	end
	return false
end

local function onRail(world: any, r: any, tt: number, clock: number): State
	local p = world.registry:pointAt(r, tt)
	local s = SquirrelMotor.new(p.x, p.y, p.z)
	s.routeId, s.railT, s.grounded, s.clock = r.id, tt, false, clock
	return s
end

local function longestWire(world: any): any
	local best: any = nil
	for _, r in world.registry:all() do
		if r.kind == "wire" and (best == nil or r.length > best.length) then
			best = r
		end
	end
	return best
end

local function tallest(world: any): any
	local best: any = nil
	for _, r in Driver.targetsAround(world, 0, 0, 3000) do
		if best == nil or r.length > best.length then
			best = r
		end
	end
	return best
end

-- the envelope, the field check and the hop switched off for `fn` (the governor and the clock check judge alone)
local function alone(fn: () -> ())
	local fc, env, hop = SquirrelMotor.fieldCheck, SquirrelMotor.envelope, MoveValidator.hop
	SquirrelMotor.fieldCheck = function(_s: any, _w: any): { any }
		return {}
	end :: any
	SquirrelMotor.envelope = function(_prev: any, next: any, _dt: number, _w: any, _b: boolean): any
		return {}, false, nil, { vy = next.vy, xz = math.huge, landed = false, longWall = false }
	end :: any
	MoveValidator.hop = function(): { any }
		return {}
	end :: any
	local ok, err = pcall(fn)
	SquirrelMotor.fieldCheck, SquirrelMotor.envelope, MoveValidator.hop = fc, env, hop
	if not ok then
		error(err, 0)
	end
end

-- a motor driven by `keys` for `secs`, its packets sent at `rate` a second to a fresh validator: the violations by code
local function drive(
	world: any,
	vworld: any,
	start: State,
	keys: (f: number) -> SquirrelMotor.Input,
	secs: number,
	rate: number
): ({ [string]: number }, number, { number })
	local v = MoveValidator.new(vworld)
	local s = SquirrelMotor.clone(start)
	local every = math.max(1, math.floor(60 / rate + 0.5))
	local seq, codes, y0 = 0, {}, s.y
	for f = 1, math.floor(secs * 60) do
		SquirrelMotor.step(s, keys(f), TICK, world)
		if f % every == 0 then
			seq += 1
			local r = v:accept("a", { seq = seq, snapshot = SquirrelMotor.serialize(s) }, s.clock)
			for _, x in r.violations do
				codes[x.code] = (codes[x.code] or 0) + 1
			end
		end
	end
	return codes, s.y - y0, v:governorPeak("a") or {}
end

local function fmt(list: { number }): string
	local out = {}
	for _, x in list do
		table.insert(out, string.format("%.1f", x))
	end
	return table.concat(out, " / ")
end

return function(t)
	-- anchor -------------------------------------------------------------------------------------------------------------
	t.test(
		"anchor: a rail claim that disagrees with x, y, z is a fault on every packet, the very first included",
		function()
			local world, vworld = worldWith({})
			local wire = longestWire(world)
			local s = onRail(world, wire, 0.05, 1)
			local ok = SquirrelMotor.fieldCheck(SquirrelMotor.serialize(s), vworld)
			t.eq(#ok, 0, "on the rail where it says")
			s.railT = 0.95
			local bad = SquirrelMotor.fieldCheck(SquirrelMotor.serialize(s), vworld)
			t.truthy(has(bad, "railPose"), `railT 0.95 at t 0.05: {codesOf(bad)}`)
			local made = SquirrelMotor.serialize(onRail(world, wire, 0.05, 1)) :: any
			made.routeId = 987654
			t.truthy(has(SquirrelMotor.fieldCheck(made, vworld), "route"), "a route the world has not")
			-- the very first packet of a validator: never a baseline
			local v = MoveValidator.new(vworld)
			local r = v:accept("a", { seq = 1, snapshot = SquirrelMotor.serialize(s) }, 0)
			t.eq(r.accepted, false, "not taken")
			t.eq(v:last("a"), nil, "no baseline")
		end
	)

	t.test("anchor: a first packet with no gate is judged from the root the server saw, never where it says", function()
		local _, vworld = worldWith({})
		local moves = {}
		local ms = MovementService.new({
			validator = MoveValidator.new(vworld),
			enforce = true,
			engine = {
				correct = function(_id: any, msg: any)
					table.insert(moves, msg)
				end,
				pin = function(_id: any, _on: boolean): boolean
					return true
				end,
				hold = function() end,
			},
		})
		-- (no poseOf: the hand-off leaves no gate)
		ms:onHandoff({ id = "a", species = "squirrel" }, nil, "possess")
		local function send(seq: number, s: State, now: number): any
			local _, e, dec = SquirrelWire.decode(SquirrelWire.encode(seq, ms:epochOf("a"), SquirrelMotor.serialize(s)))
			return ms:packet("a", "squirrel", { seq = seq, epoch = e, snapshot = dec }, now)
		end
		local far = SquirrelMotor.new(400, 0.45, 0)
		far.grounded, far.clock = true, 1
		local r0 = send(1, far, 10)
		t.eq(r0.accepted, false, "with no place known the packet is not taken")
		t.eq(#moves, 0, "and nothing is moved")
		ms:watch("a", 0, 0.45, 0, 10.05)
		far.clock = 1.05
		local r1 = send(2, far, 10.1)
		t.eq(r1.accepted, false, "400 st from the root: not taken")
		t.truthy(#moves >= 1 and math.abs(moves[#moves].x) < 1, "snapped to the root")
		local near = SquirrelMotor.new(0.5, 0.45, 0)
		near.grounded, near.clock = true, 1.2
		local r2 = send(3, near, 10.3)
		t.eq(r2.accepted, true, "beside the root: taken")
	end)

	-- governor -----------------------------------------------------------------------------------------------------------
	t.test("governor: its bounds from the motor's constants, and what a cheater can take beyond them", function()
		local _, vworld = worldWith({})
		local v = MoveValidator.new(vworld)
		local b = v:governorBounds(false)
		local W = MoveValidator.C.GOV_WINDOW
		print(
			string.format(
				"      across %.1f st/s (%.1f by a trampoline) + %.2f st; up %.1f st/s by a rail, %.1f elsewhere, %.1f by a trampoline, + %.2f st",
				b.vh,
				b.vhTramp,
				b.dh,
				b.vRail,
				b.vLedge,
				b.vTramp,
				b.dv
			)
		)
		print(
			string.format(
				"      at most, sustained over %d s: across %.1f st/s, up %.1f st/s by a rail and %.1f elsewhere; once per window %.1f st across and %.1f up",
				W,
				b.vh + b.dh / W,
				b.vRail + b.dv / W,
				b.vLedge + b.dv / W,
				b.dh,
				b.dv
			)
		)
		-- every bound at least the motor's own honest pace
		t.truthy(b.vh >= SquirrelMotor.groundCap(false) and b.vh >= SquirrelMotor.launchCapXZ(false), "across")
		t.truthy(b.vRail >= SquirrelMotor.railCap(true, false), "up a trunk")
		t.truthy(b.vLedge > 0 and b.vLedge < b.vRail, "a ledge chain under a rail's")
	end)

	t.test(
		"governor: honest circuits at 2 to 30 packets a second, clocks x0.8 to x1.2, 300 ms + 250 ms, 2 % loss",
		function()
			local world = TestWorld.build()
			local worst = table.create(6, -math.huge)
			local packets, trips = 0, 0
			local rows = {}
			for _, every in { 2, 3, 6, 15, 30 } do
				for _, rate in { 0.8, 1, 1.2 } do
					local r = Harness.honest({
						world = world,
						squirrels = 4,
						minutes = 0.5,
						seed = 31 + every,
						packetEvery = every,
						baseLatency = 0.3,
						jitter = 0.25,
						loss = 0.02,
						clockRate = rate,
					})
					packets += r.accepted
					trips += r.violationCodes.governor or 0
					for k, x in r.governorPeak do
						worst[k] = math.max(worst[k], x)
					end
					if (r.violationCodes.governor or 0) > 0 then
						table.insert(rows, `{60 / every}/s x{rate}: {r.violationCodes.governor} governor`)
					end
				end
			end
			print(
				`      {packets} packets; the governor's closest calls (st over its allowance; across 0.25/1/3 s, up 0.25/1/3 s): {fmt(
					worst
				)}`
			)
			t.eq(trips, 0, `the governor never trips on honest play: {table.concat(rows, "; ")}`)
		end
	)

	t.test("governor: the motor's own leap-and-regrab climb and a leap along the steepest bough are clean", function()
		local world, vworld = worldWith({})
		local tall = tallest(world)
		local start = onRail(world, tall, 0.05, 0)
		start.tireless = true
		local fails, rows = {}, {}
		for _, k in { 2, 3, 4 } do
			for _, rate in { 2, 3, 4, 10, 20, 30 } do
				local codes, up = drive(world, vworld, start, function(f: number): SquirrelMotor.Input
					local i = SquirrelMotor.idleInput(0)
					i.grab, i.leap = f % k == 0, f % k == 0
					return i
				end, 3, rate)
				local c = {}
				for code, n in codes do
					table.insert(c, `{code}={n}`)
				end
				if rate == 20 then
					table.insert(rows, `E+Space every {k} frames: up {string.format("%.1f", up / 3)} st/s`)
				end
				if #c > 0 then
					table.insert(fails, `every {k} frames at {rate}/s: {table.concat(c, " ")}`)
				end
			end
		end
		-- the steepest bough that is no trunk: a leap along it facing up, regrabbed above the body
		local steep, steepS = nil, 0
		for _, r in world.registry:all() do
			if r.kind ~= "trunk" and r.length > 30 then
				local a, b = world.registry:pointAt(r, 0.2), world.registry:pointAt(r, 0.6)
				local sl = math.abs(b.y - a.y) / math.max(math.sqrt((b.x - a.x) ^ 2 + (b.z - a.z) ^ 2), 1e-6)
				if sl > steepS and sl < 3 then
					steep, steepS = r, sl
				end
			end
		end
		local a, b = world.registry:pointAt(steep, 0.2), world.registry:pointAt(steep, 0.3)
		local yaw = math.atan2(-(b.x - a.x), -(b.z - a.z))
		if b.y < a.y then
			yaw += math.pi
		end
		local bough = onRail(world, steep, 0.2, 0)
		bough.tireless = true
		for _, wait in { 6, 12, 18, 24 } do
			for _, rate in { 2, 3, 4, 10, 20, 30 } do
				local codes = drive(world, vworld, bough, function(f: number): SquirrelMotor.Input
					local i = SquirrelMotor.idleInput(yaw)
					i.fw = 1
					local m = f % (wait + 6)
					i.leap, i.grab = m == 0, m == wait
					return i
				end, 3, rate)
				local c = {}
				for code, n in codes do
					table.insert(c, `{code}={n}`)
				end
				if #c > 0 then
					table.insert(fails, `bough regrab after {wait} frames at {rate}/s: {table.concat(c, " ")}`)
				end
			end
		end
		for _, row in rows do
			print(`      {row}`)
		end
		print(`      the steepest bough {steep.id}: {string.format("%.2f", steepS)} up per stud across`)
		t.eq(#fails, 0, `honest motor cases flagged: {table.concat(fails, "; ")}`)
	end)

	t.test(
		"governor: with the envelope, the field check and the hop off, it still catches the round-5 teleports",
		function()
			local world, vworld = worldWith({})
			local wire = longestWire(world)
			local rows = {}
			alone(function()
				-- the CRITICAL: a 0.6 s silence and a rail parameter 563 st along the wire
				local v = MoveValidator.new(vworld)
				local seq, clock = 0, 0
				local function send(s: State): any
					seq += 1
					return v:accept("a", { seq = seq, snapshot = SquirrelMotor.serialize(s) }, clock)
				end
				for i = 0, 20 do
					clock = i * 0.05
					send(onRail(world, wire, 0.05, clock))
				end
				clock += 0.6
				local s = onRail(world, wire, 0.05, clock)
				s.railT = 0.95
				send(s)
				clock += 0.05
				local r = send(onRail(world, wire, 0.95, clock))
				table.insert(rows, `563 st along a wire after a silence: [{codesOf(r.violations)}]`)
				t.truthy(has(r.violations, "governor"), "the far end of the wire")
				-- a climb straight up a trunk at three times its pace
				local tall = tallest(world)
				local v2 = MoveValidator.new(vworld)
				local tt, c2, n, caught = 0.02, 0, 0, false
				v2:accept("b", { seq = 1, snapshot = SquirrelMotor.serialize(onRail(world, tall, tt, 0)) }, 0)
				while tt < 0.9 do
					c2 += 0.05
					n += 1
					tt += 3 * SquirrelMotor.routeCap(tall, false) * 0.05 / tall.length
					local r2 = v2:accept(
						"b",
						{ seq = n + 1, snapshot = SquirrelMotor.serialize(onRail(world, tall, tt, c2)) },
						c2
					)
					caught = caught or has(r2.violations, "governor")
				end
				table.insert(rows, `a trunk at 3 x its pace: caught {caught}`)
				t.truthy(caught, "a trunk at three times its pace")
			end)
			for _, row in rows do
				print(`      {row}`)
			end
		end
	)

	t.test("governor: a snap keeps its history, so creeping past the bound buys nothing new", function()
		local _, vworld = worldWith({})
		local moves = {}
		local ms = MovementService.new({
			validator = MoveValidator.new(vworld),
			enforce = true,
			poseOf = function(_actor: any): (number, number, number)
				return 0, 0.45, 0
			end,
			engine = {
				correct = function(_id: any, msg: any)
					table.insert(moves, msg)
				end,
				pin = function(_id: any, _on: boolean): boolean
					return true
				end,
				hold = function() end,
			},
		})
		ms:onHandoff({ id = "a", species = "squirrel" }, nil, "possess")
		ms:watch("a", 0, 0.45, 0, 100)
		local seq, clock, now, x, seen = 0, 5, 100, 0, 0
		local b = ms.deps.validator:governorBounds(false)
		alone(function()
			-- 1.5 x the governor's pace across, every packet clean by the (switched off) envelope
			for _ = 1, 120 do
				seq += 1
				clock += 0.05
				now += 0.05
				x += 1.5 * b.vh * 0.05
				local s = SquirrelMotor.new(x, 0.45, 0)
				s.grounded, s.clock = true, clock
				local _, e, dec =
					SquirrelWire.decode(SquirrelWire.encode(seq, ms:epochOf("a"), SquirrelMotor.serialize(s)))
				ms:packet("a", "squirrel", { seq = seq, epoch = e, snapshot = dec }, now)
				if #moves > seen then
					-- (snapped: its client goes on from where it was put)
					seen = #moves
					x = moves[seen].x
				end
			end
		end)
		local st = ms:stats()
		print(`      {st.packets} packets, {st.snaps} snaps, {st.holds} holds, stale {st.stale}`)
		local furthest = 0
		for _, m in moves do
			furthest = math.max(furthest, m.x)
		end
		local allowed = b.vh * 6 + 2 * b.dh
		print(
			`      {#moves} snaps; the furthest place it was put {string.format("%.0f", furthest)} st in 6 s (an honest body {string.format(
				"%.0f",
				b.vh * 6
			)})`
		)
		t.truthy(#moves > 0, "snapped")
		t.truthy(furthest <= allowed, `no further than the governor's pace and a window's one-off: {furthest}`)
	end)

	-- cover ----------------------------------------------------------------------------------------------------------------
	t.test("cover: a long line over a garden wall and then a roofed house's wall asks the cover at both", function()
		-- walls across x = 10 (3 st high, open sky beyond) and x = 20 (8 st, a roof at 8 over x 20..30)
		local function wall(ox: number, oy: number, oz: number, dx: number, _dy: number, dz: number): boolean
			local x1 = ox + dx
			local lo, hi = math.min(ox, x1), math.max(ox, x1)
			local _ = oz + dz
			if lo <= 10 and hi >= 10 and oy < 3 then
				return true
			end
			if lo <= 20 and hi >= 20 and oy < 8 then
				return true
			end
			return false
		end
		local function down(ox: number, oy: number, _oz: number, _dx: number, dy: number, _dz: number): boolean
			local lo = oy + dy
			if lo <= 0 and oy >= 0 then
				return true
			end
			return ox > 20 and ox < 30 and 8 >= lo and 8 <= oy
		end
		local long = ValidatorWorld.crossesLong(wall, down)
		local into = long(0, 0, 27, 0, 0, 0, 10, 0)
		local garden = long(0, 0, 15, 0, 0, 0, 10, 0)
		print(`      into the house over both walls: {into}; over the garden wall only: {garden}`)
		t.eq(into, true, "the house's wall under its roof is a crossing")
		t.eq(garden, false, "a garden wall leapt under open sky is none")
	end)
end
