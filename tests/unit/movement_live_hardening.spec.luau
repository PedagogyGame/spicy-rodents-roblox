--!strict
-- The live squirrel validator against what an adversarial review found (2026-11-18): a NaN on the wire, packets
-- spaced past the envelope's gap, a client that roams while silent, the correction handshake used as a free hop, an
-- honest link whose latency drops. Each cheat must be snapped; each honest case must not be.
local Units = require("@shared/Config/Units")
local SquirrelMotor = require("@shared/Movement/SquirrelMotor")
local SquirrelWire = require("@shared/Movement/SquirrelWire")
local ValidatorWorld = require("@server/Movement/ValidatorWorld")
local MoveValidator = require("@server/Movement/MoveValidator")
local MovementService = require("@server/Movement/MovementService")
local Harness = require("@tests/cheat/Harness")
local Rng = require("@tests/cheat/Rng")
local TestWorld = require("@tests/cheat/TestWorld")
local LiveRig = require("@tests/lib/LiveRig")

type State = SquirrelMotor.State

local function finite(v: number): boolean
	return math.abs(v) < math.huge
end

return function(t)
	local world = TestWorld.build()
	local vworld = ValidatorWorld.build(world, {})

	local function openState(): State
		local g = Harness.OPEN_GROUND
		local s =
			SquirrelMotor.new(Units.st((g.minX + g.maxX) / 2), world.groundHeight, Units.st((g.minZ + g.maxZ) / 2))
		s.clock = 1
		return s
	end

	-- one squirrel on a MovementService with enforcement on; packets go through the wire's own bytes
	local function service()
		local corrections: { any } = {}
		local ms = MovementService.new({
			validator = MoveValidator.new(vworld),
			enforce = true,
			engine = {
				correct = function(_id: any, msg: any)
					table.insert(corrections, msg)
				end,
			},
		})
		ms:onHandoff({ id = "a" }, nil, "possess")
		local function send(seq: number, snap: { [string]: number | boolean }, now: number): any
			local _, e, dec = SquirrelWire.decode(SquirrelWire.encode(seq, ms:epochOf("a"), snap))
			return ms:packet("a", "squirrel", { seq = seq, epoch = e, snapshot = dec }, now)
		end
		return ms, send, corrections
	end

	-- 1. NON-FINITE NUMBERS ---------------------------------------------------------------------------------------
	t.test("SquirrelWire.sane: NaN and infinities in any field are refused, an honest snapshot passes", function()
		local s = openState()
		t.eq(SquirrelWire.sane(SquirrelMotor.serialize(s)), true)
		for _, field in { "x", "y", "z", "clock", "vx", "vy", "railT", "stamina" } do
			for _, bad in { 0 / 0, math.huge, -math.huge, 1e12 } do
				local snap = SquirrelMotor.serialize(s)
				snap[field] = bad
				local _, _, dec = SquirrelWire.decode(SquirrelWire.encode(1, 1, snap))
				t.eq(SquirrelWire.sane(dec), false, `{field} = {bad}`)
			end
		end
	end)

	for _, field in { "x", "clock", "y+clock" } do
		t.test(`a NaN in {field} is a violation and snaps; it never becomes the baseline or a snap target`, function()
			local ms, send, corrections = service()
			local s = openState()
			local now = 100
			send(1, SquirrelMotor.serialize(s), now)
			ms:watch("a", s.x, s.y, s.z, now)
			local bad = SquirrelMotor.serialize(s)
			if field ~= "clock" then
				bad[if field == "x" then "x" else "y"] = 0 / 0
			end
			if field ~= "x" then
				bad.clock = 0 / 0
			else
				bad.clock = 1.05
			end
			now += 0.05
			local v = send(2, bad, now)
			t.eq(v.ok, false, "violation")
			t.eq(v.accepted, false, "not accepted")
			t.eq(ms:stats().snaps, 1, "snapped")
			-- the server's view of the body far away for 12 s, then a packet far away: both judged against the real place
			for _ = 1, 120 do
				now += 0.1
				ms:watch("a", s.x + 500, s.y + 200, s.z, now)
			end
			t.truthy(ms:stats().snaps >= 2, `the body away was snapped ({ms:stats().snaps})`)
			for _, c in corrections do
				t.truthy(finite(c.x) and finite(c.y) and finite(c.z), "every snap target is finite")
				if c.snapshot then
					t.eq(SquirrelWire.sane(c.snapshot), true, "every restored state is finite")
				end
			end
		end)
	end

	t.test("MoveValidator.accept refuses a non-finite packet on its own (no MovementService in front)", function()
		local v = MoveValidator.new(vworld)
		local s = openState()
		local bad = SquirrelMotor.serialize(s)
		bad.x = 0 / 0
		local first = v:accept("b", { seq = 1, snapshot = bad }, 10)
		t.eq(first.accepted, false, "never a baseline")
		t.eq(v:last("b"), nil)
		v:accept("b", { seq = 2, snapshot = SquirrelMotor.serialize(s) }, 10)
		local again = v:accept("b", { seq = 3, snapshot = bad }, 10.05)
		t.eq(again.ok, false)
		t.eq(again.accepted, false)
		t.eq(again.flagged, true)
		t.eq((v:last("b") :: any).x, s.x, "the baseline is still the honest state")
	end)

	-- THE RIG: cheats from CHEAT_AT on ------------------------------------------------------------------------------
	local town = LiveRig.town()
	local CHEAT_AT = 5
	local fastest = MoveValidator.new(town.vworld):fastest("x")
	local function still(_now: number, _s: State, _e: { SquirrelMotor.Event }): SquirrelMotor.Input
		return SquirrelMotor.idleInput(0)
	end
	local function sprintEast(_now: number, _s: State, _e: { SquirrelMotor.Event }): SquirrelMotor.Input
		local inp = SquirrelMotor.idleInput(-math.pi / 2)
		inp.fw = 1
		inp.sprint = true
		return inp
	end
	local function show(name: string, r: LiveRig.Result)
		print(`      {LiveRig.describe(name, r)}; first snap at {r.firstSnap}`)
		for i, v in r.violations do
			if i <= 4 then
				print(`        {v}`)
			end
		end
	end
	local quiet: LiveRig.Link = { latency = 0.12, jitter = 0.05, loss = 0 }

	-- 2. GAPS TOO LONG TO JUDGE MOVE BY MOVE -------------------------------------------------------------------------
	t.test(
		"cheat: one packet every 0.6 s, flying 12 studs up and climbing, at 40 st/s through houses: snapped",
		function()
			local rig = LiveRig.new({
				world = town.noWalls,
				vworld = town.vworld,
				link = quiet,
				seed = 3,
				silent = function(now: number): boolean
					return now >= CHEAT_AT and (now % 0.6) >= 0.05
				end,
				cheat = function(s: State, _inp: SquirrelMotor.Input, now: number, _w: any)
					if now >= CHEAT_AT then
						s.y = town.world.groundHeight + 12 + (now - CHEAT_AT) * 2
						s.vy, s.grounded = 0, false
						s.x += 40 / 60
					end
				end,
			})
			rig:possess(town.openStart(), sprintEast)
			rig:run(25)
			local r = rig:result()
			show("sparse fly", r)
			t.truthy(r.firstSnap and r.firstSnap <= CHEAT_AT + 2, "snapped within 2 s")
			t.truthy(r.snaps >= 5, `snapped again and again ({r.snaps})`)
		end
	)

	t.test(
		"cheat: silent 2.9 s, then a hop of 0.9 x the fastest for that time, 20 studs up, every 4 s: snapped",
		function()
			local hops = 0
			local rig = LiveRig.new({
				world = town.noWalls,
				vworld = town.vworld,
				link = quiet,
				seed = 6,
				silent = function(now: number): boolean
					return (now % 4) >= 1 and (now % 4) < 3.98
				end,
				cheat = function(s: State, _inp: SquirrelMotor.Input, now: number, _w: any)
					local ph = now % 4
					if now > CHEAT_AT and ph >= 3.98 and ph < 3.98 + 1 / 60 then
						hops += 1
						s.x += fastest * 2.9 * 0.9
						s.y += 20
						s.grounded = false
						s.vx, s.vy, s.vz = 0, 0, 0
					end
				end,
			})
			rig:possess(town.openStart(), still)
			rig:run(40)
			local r = rig:result()
			show("stall hops up", r)
			t.truthy(r.snaps >= hops - 1, `each hop snapped ({r.snaps} snaps, {hops} hops)`)
		end
	)

	t.test(
		"cheat: silent 2.9 s, then a hop through a house at ground level, back and forth: snapped by the second",
		function()
			local b = town.boxes[1]
			local cz = (b.minZ + b.maxZ) / 2
			local span = (b.maxX - b.minX) + 20
			local hops = 0
			local rig = LiveRig.new({
				world = town.noWalls,
				vworld = town.vworld,
				link = quiet,
				seed = 7,
				silent = function(now: number): boolean
					return (now % 4) >= 1 and (now % 4) < 3.98
				end,
				cheat = function(s: State, _inp: SquirrelMotor.Input, now: number, _w: any)
					local ph = now % 4
					if now > CHEAT_AT and ph >= 3.98 and ph < 3.98 + 1 / 60 then
						hops += 1
						s.x += if s.x < b.minX then span else -span
						s.vx, s.vz = 0, 0
					end
				end,
			})
			rig:possess(SquirrelMotor.new(b.minX - 10, town.world.groundHeight, cz), still)
			rig:run(30)
			local r = rig:result()
			show("stall hops through a house", r)
			t.truthy(hops >= 4, `hopped ({hops})`)
			t.truthy(r.snaps >= 1 and (r.firstSnap :: number) <= 12.5, "snapped by the second hop")
			t.truthy(r.snaps >= hops - 2, `and from then on ({r.snaps} snaps, {hops} hops)`)
		end
	)

	t.test("cheat: the clock jumped 100 s ahead and the body 1,500 studs on: snapped at once", function()
		local done = false
		local rig = LiveRig.new({
			world = town.noWalls,
			vworld = town.vworld,
			link = quiet,
			seed = 5,
			cheat = function(s: State, _inp: SquirrelMotor.Input, now: number, _w: any)
				if now >= CHEAT_AT and not done then
					done = true
					s.clock += 100
					s.x += 1500
				end
			end,
		})
		rig:possess(town.openStart(), still)
		rig:run(10)
		local r = rig:result()
		show("clock jump", r)
		t.truthy(r.firstSnap and r.firstSnap <= CHEAT_AT + 0.5, "snapped")
	end)

	t.test("cheat: a client that sends one packet in 0.6 s (hiding its moves), on the ground: snapped", function()
		local rig = LiveRig.new({
			world = town.world,
			vworld = town.vworld,
			link = quiet,
			seed = 8,
			silent = function(now: number): boolean
				return now >= CHEAT_AT and (now % 0.6) >= 0.05
			end,
		})
		rig:possess(town.openStart(), sprintEast)
		rig:run(15)
		local r = rig:result()
		show("sparse sender", r)
		t.truthy(r.firstSnap and r.firstSnap <= CHEAT_AT + 4, "snapped within 4 s")
		t.truthy((r.reasons.gaps or 0) >= 1, "for its gaps")
	end)

	-- 3. THE SERVER'S OWN VIEW OF THE BODY, AT EVERY AGE --------------------------------------------------------------
	local function far(r: LiveRig.Result, s0: State): number
		return math.sqrt((r.root.x - s0.x) ^ 2 + (r.root.z - s0.z) ^ 2)
	end
	t.test(
		"cheat: silent for 4.6 s in every 10, the body 80 studs away and 30 up, then back: snapped every time",
		function()
			local home: { x: number, y: number, z: number }? = nil
			local s0 = town.openStart()
			local rig = LiveRig.new({
				world = town.noWalls,
				vworld = town.vworld,
				link = quiet,
				seed = 4,
				silent = function(now: number): boolean
					return (now % 10) >= 5 and (now % 10) < 9.6
				end,
				cheat = function(s: State, _inp: SquirrelMotor.Input, now: number, _w: any)
					local ph = now % 10
					if ph >= 5 and ph < 5.02 then
						home = { x = s.x, y = s.y, z = s.z }
					end
					local h = home
					if h and ph >= 5.75 and ph < 9.3 then
						s.x, s.y, s.z, s.grounded = h.x + 80, h.y + 30, h.z, false
						s.vx, s.vy, s.vz = 0, 0, 0
					elseif h and ph >= 9.3 and ph < 9.35 then
						s.x, s.y, s.z, s.grounded = h.x, h.y, h.z, true
						s.vx, s.vy, s.vz = 0, 0, 0
					end
				end,
			})
			rig:possess(s0, still)
			rig:run(40)
			local r = rig:result()
			show("silent roam", r)
			t.truthy(r.snaps >= 4, `each of the four trips snapped ({r.snaps})`)
			t.truthy(r.firstSnap and r.firstSnap <= 7, "the first within 2 s of leaving")
		end
	)

	t.test("cheat: stops sending and sprints through a house: snapped at the wall, not 5 s later", function()
		local b = town.boxes[1]
		local rig = LiveRig.new({
			world = town.noWalls,
			vworld = town.vworld,
			link = { latency = 0.12, jitter = 0.15, loss = 0.02 },
			seed = 13,
			silent = function(now: number): boolean
				return now >= CHEAT_AT
			end,
		})
		rig:possess(
			SquirrelMotor.new(b.minX - 15, town.world.groundHeight, (b.minZ + b.maxZ) / 2),
			function(now: number, _s: State, _e: { SquirrelMotor.Event }): SquirrelMotor.Input
				local inp = SquirrelMotor.idleInput(-math.pi / 2)
				inp.fw = if now >= CHEAT_AT then 1 else 0
				inp.sprint = true
				return inp
			end
		)
		rig:run(CHEAT_AT + 4)
		local r = rig:result()
		show("silent through a house", r)
		t.truthy(r.firstSnap and r.firstSnap <= CHEAT_AT + 1.5, "snapped at the wall")
		t.truthy((r.reasons.wall or 0) >= 1, "for the wall")
	end)

	t.test("cheat: stops sending and hangs 20 studs up: snapped for flying", function()
		local rig = LiveRig.new({
			world = town.noWalls,
			vworld = town.vworld,
			link = quiet,
			seed = 14,
			silent = function(now: number): boolean
				return now >= CHEAT_AT
			end,
			cheat = function(s: State, _inp: SquirrelMotor.Input, now: number, _w: any)
				if now >= CHEAT_AT then
					s.y = town.world.groundHeight + 20
					s.vy, s.grounded = 0, false
				end
			end,
		})
		rig:possess(town.openStart(), still)
		rig:run(CHEAT_AT + 6)
		local r = rig:result()
		show("silent hover", r)
		t.truthy(r.firstSnap and r.firstSnap <= CHEAT_AT + 3.5, "snapped")
	end)

	-- 4. THE CORRECTION HANDSHAKE IS NO FREE HOP ----------------------------------------------------------------------
	t.test(
		"cheat: provoke a snap, hold the new epoch back 1.9 s, then appear 75 studs on and 25 up: no ground gained",
		function()
			local s0 = town.openStart()
			local hops = 0
			local rig = LiveRig.new({
				world = town.noWalls,
				vworld = town.vworld,
				link = { latency = 0.1, jitter = 0.03, loss = 0 },
				seed = 9,
				silent = function(now: number): boolean
					local ph = now % 6
					return now > CHEAT_AT and ph >= 0.05 and ph < 2.0
				end,
				cheat = function(s: State, _inp: SquirrelMotor.Input, now: number, _w: any)
					local ph = now % 6
					if now > CHEAT_AT and ph < 1 / 60 then
						s.z += 30 -- (provokes a snap)
					elseif now > CHEAT_AT and ph >= 1.95 and ph < 1.95 + 1 / 60 then
						s.x += 75
						s.y += 25
						s.grounded = false
						s.vx, s.vy, s.vz = 0, 0, 0
						hops += 1
					end
				end,
			})
			rig:possess(s0, still)
			rig:run(42)
			local r = rig:result()
			show(`handshake hops ({hops})`, r)
			t.truthy(hops >= 5, "hopped")
			t.truthy(far(r, s0) < 40, `the body ends near where it began ({far(r, s0)} studs)`)
			t.truthy(r.holds >= 1, "and is held after a run of snaps")
		end
	)

	t.test(
		"cheat: provoke a snap, hold back, then a first packet 25 studs on through a house: snapped to the gate",
		function()
			local b = town.boxes[1]
			local cz = (b.minZ + b.maxZ) / 2
			local s0 = SquirrelMotor.new(b.minX - 3, town.world.groundHeight, cz)
			local width = b.maxX - b.minX
			local rig = LiveRig.new({
				world = town.noWalls,
				vworld = town.vworld,
				link = { latency = 0.1, jitter = 0.03, loss = 0 },
				seed = 10,
				silent = function(now: number): boolean
					local ph = now % 6
					return now > CHEAT_AT and ph >= 0.05 and ph < 1.0
				end,
				cheat = function(s: State, _inp: SquirrelMotor.Input, now: number, _w: any)
					local ph = now % 6
					if now > CHEAT_AT and ph < 1 / 60 then
						s.z += 30
					elseif now > CHEAT_AT and ph >= 0.95 and ph < 0.95 + 1 / 60 and s.x < b.minX then
						s.x += width + 6
					end
				end,
			})
			rig:possess(s0, still)
			rig:run(20)
			local r = rig:result()
			show("handshake through a house", r)
			t.truthy(r.root.x < b.minX, "never on the far side of the house")
		end
	)

	-- the honest side of the same: every move the server makes, on the slowest links, with lost bursts
	for _, l in
		{
			{ name = "500 ms + 300 ms jitter", link = { latency = 0.5, jitter = 0.3, loss = 0.02 } },
			{ name = "400 ms + 400 ms jitter", link = { latency = 0.4, jitter = 0.4, loss = 0.02 } },
			{
				name = "120 ms, lost bursts of 0.8 s every 5 s",
				link = { latency = 0.12, jitter = 0.1, loss = 0.02, dropEvery = 5, dropFor = 0.8 },
			},
		}
	do
		t.test(`honest: Reset, knocks, the lounge's door and a snap-free run on {l.name}: 0 snaps`, function()
			local rng = Rng.new(71)
			local rig = LiveRig.new({ world = town.world, vworld = town.vworld, link = l.link, seed = 71 })
			rig:possess(town.startAt(rng), town.driven(rng))
			for k = 1, 4 do
				rig:at(k * 6 + 0.37, function()
					local c = rig.client.state
					if c then
						rig:teleport(
							c.x + (if k % 2 == 0 then 3 else -3),
							town.world.groundHeight + 0.6,
							c.z,
							"knocked"
						)
					end
				end)
			end
			rig:run(36)
			local r = rig:result()
			show(`server moves on {l.name}`, r)
			t.eq(r.snaps, 0, "snaps")
		end)
	end

	-- 5. THE CLOCK: A LATENCY THAT DROPS IS NO TIME HACK; A SLOW TIME HACK STILL SHOWS -------------------------------
	local function honest(name: string, link: LiveRig.Link, seconds: number, seed: number, fps: any?)
		t.test(`honest: {name}: 0 snaps`, function()
			local rng = Rng.new(seed)
			local rig = LiveRig.new({ world = town.world, vworld = town.vworld, link = link, seed = seed, fps = fps })
			rig:possess(town.startAt(rng), town.driven(rng))
			rig:run(seconds)
			local r = rig:result()
			show(name, r)
			t.eq(r.snaps, 0, "snaps")
			t.truthy(r.accepted > seconds * 5, `packets judged ({r.accepted})`)
		end)
	end
	for _, c in { { a = 0.75, b = 0.15 }, { a = 0.45, b = 0.05 }, { a = 0.6, b = 0.2 }, { a = 0.8, b = 0.05 } } do
		honest(`the latency drops from {c.a} s to {c.b} s after 20 s (a congested link clearing, a handover)`, {
			jitter = 0.1,
			loss = 0.02,
			latencyAt = function(now: number): number
				return if now < 20 then c.a else c.b
			end,
		}, 40, 21)
	end
	honest("the latency rises and drops by 0.5 s every 12 s", {
		jitter = 0.1,
		loss = 0.02,
		latencyAt = function(now: number): number
			return if now % 12 < 6 then 0.6 else 0.1
		end,
	}, 60, 22)
	-- the reviewer's links: 500 to 800 ms one way, jitter that reorders packets
	local SLOW = 90
	honest("500 ms one way and 300 ms jitter", { latency = 0.5, jitter = 0.3, loss = 0.02 }, SLOW, 31)
	honest("650 ms one way and 150 ms jitter", { latency = 0.65, jitter = 0.15, loss = 0.02 }, SLOW, 32)
	honest("400 ms one way and 400 ms jitter (reordered)", { latency = 0.4, jitter = 0.4, loss = 0.02 }, SLOW, 33)
	honest(
		"the app frozen for 10 s and then 25 s (backgrounded), 200 ms",
		{ latency = 0.2, jitter = 0.1, loss = 0.02 },
		90,
		41,
		function(frame: number, _now: number): number
			if frame == 1200 then
				return 10
			elseif frame == 3000 then
				return 25
			end
			return 1 / 60
		end
	)

	for _, c in
		{
			{ name = "80 ms", link = { latency = 0.08, jitter = 0.15, loss = 0.02 }, within = 4 },
			{
				name = "500 ms and 300 ms jitter",
				link = { latency = 0.5, jitter = 0.3, loss = 0.02 },
				within = 10, -- (eight seconds to add up to the cap, and the link's own 0.8 s)
			},
		}
	do
		t.test(`cheat: a 1.12 x clock ({c.name}): snapped within {c.within} s`, function()
			local rng = Rng.new(61)
			local rig = LiveRig.new({
				world = town.world,
				vworld = town.vworld,
				link = c.link,
				seed = 61,
				clockRate = 1.12,
			})
			rig:possess(town.startAt(rng), town.driven(rng))
			rig:run(20)
			local r = rig:result()
			show(`1.12 x clock, {c.name}`, r)
			t.truthy(r.firstSnap and r.firstSnap <= c.within, `snapped within {c.within} s`)
			t.truthy((r.reasons.clock or 0) >= 1, "for its clock")
		end)
	end
end
