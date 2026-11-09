--!strict
-- Server/Movement/MoveValidator (spike S3; BUILD_PLAN §4.3 S3 pass criteria, §6.2 MoveValidator row):
-- 10 simulated minutes of honest circuits with 150 ms jitter and 2 % loss produce 0 violations; the
-- cheat harness (speed x2, 30-st teleport, illegal 20-st leap, wall pass, non-adjacent hop) flags each
-- within 1 s at >= 95 % with 0 false positives on the honest warm-ups; <= 0.05 ms per squirrel per
-- tick. The honest run is long (6 squirrels x 10 min = 216,000 motor frames); set
-- SPICY_FAST=1 to run a 1-minute version while iterating.
local process = require("@lune/process")
local Units = require("@shared/Config/Units")
local SquirrelMotor = require("@shared/Movement/SquirrelMotor")
local MoveValidator = require("@server/Movement/MoveValidator")
local Harness = require("@tests/cheat/Harness")
local TestWorld = require("@tests/cheat/TestWorld")

local FAST = process.env.SPICY_FAST ~= nil

local function fmt(n: number): string
	return string.format("%.3f", n)
end

return function(t)
	-- the validator's world carries two house-sized wall boxes on open route-free ground in the
	-- south-west corner (the cheat scenarios start nearby, Harness.OPEN_GROUND)
	local boxes: { TestWorld.Box } = {
		{
			minX = Units.st(-540),
			maxX = Units.st(-528),
			minZ = Units.st(-400),
			maxZ = Units.st(-388),
			top = Units.st(5.3),
		},
		{
			minX = Units.st(-540),
			maxX = Units.st(-528),
			minZ = Units.st(-280),
			maxZ = Units.st(-268),
			top = Units.st(5.3),
		},
	}
	local world = TestWorld.build({ boxes = boxes })
	world.crosses = function(x0, z0, x1, z1, y)
		return TestWorld.segmentCrossesBox(boxes, x0, z0, x1, z1, y)
	end

	t.test("first packet is the baseline; stale seq is dropped; pose(t) interpolates the last second", function()
		local v = MoveValidator.new(world)
		local s = SquirrelMotor.new(10, world.groundHeight, 10)
		local verdict = v:accept("a", { seq = 1, snapshot = SquirrelMotor.serialize(s) }, 0.1)
		t.truthy(verdict.ok)
		t.truthy(verdict.baseline)
		local inp = SquirrelMotor.idleInput(math.pi)
		inp.fw = 1
		for i = 1, 30 do
			SquirrelMotor.step(s, inp, 1 / 60, world)
			local out = v:accept("a", { seq = 1 + i, snapshot = SquirrelMotor.serialize(s) }, 0.1 + i / 60)
			t.truthy(out.ok, `honest step {i}: {if #out.violations > 0 then out.violations[1].detail else ""}`)
		end
		local stale = v:accept("a", { seq = 5, snapshot = SquirrelMotor.serialize(s) }, 1)
		t.falsy(stale.accepted)
		local x, y, z = v:pose("a", s.clock - 0.25)
		t.truthy(x ~= nil and y ~= nil and z ~= nil)
		t.truthy((x :: number) <= s.x and (z :: number) < s.z, "earlier pose is behind the body")
		t.eq(v:pose("none", 0), nil)
	end)

	t.test(
		`honest circuits: {if FAST then "1 minute" else "10 minutes"}, 6 squirrels, 150 ms jitter, 2 % loss -> 0 violations`,
		function()
			local result = Harness.honest({
				world = world,
				squirrels = 6,
				minutes = if FAST then 1 else 10,
				seed = 20261109,
				jitter = 0.15,
				loss = 0.02,
			})
			local keys: { string } = {}
			for k in result.events do
				table.insert(keys, k)
			end
			table.sort(keys)
			local parts: { string } = {}
			for _, k in keys do
				table.insert(parts, `{k}={result.events[k]}`)
			end
			print(
				`      ticks {result.ticks}, packets {result.packets}, accepted {result.accepted}, reordered-dropped {result.dropped}, resyncs {result.resyncs}`
			)
			print(`      events: {table.concat(parts, " ")}`)
			print(
				`      validator {fmt(result.validatorPerPacketMs)} ms/packet, motor {fmt(result.motorSeconds)} s total`
			)
			for _, s in result.samples do
				print(`      VIOLATION {s}`)
			end
			t.eq(result.violations, 0, "honest violations")
			t.eq(result.flagged, 0, "honest flags")
			t.truthy(result.events.attach and result.events.attach > 0, "attached to routes")
			t.truthy(result.events.autoSwitch and result.events.autoSwitch > 0, "auto-switched at route ends")
			t.truthy(result.events.forkTaken and result.events.forkTaken > 0, "took forks")
			t.truthy(result.events.leap and result.events.leap > 0, "leapt")
			t.truthy(result.events.land and result.events.land > 0, "landed")
			t.truthy(result.events.transfer and result.events.transfer > 0, "E transfers")
			t.truthy(result.dropped > 0, "reordering produced stale packets (the link really jitters)")
		end
	)

	local cheats = {
		{ kind = "speed2", variant = nil, label = "speed x2 (sprinting speed hack)" },
		{ kind = "speed2_clock", variant = nil, label = "speed x2 as a time hack" },
		{ kind = "teleport30", variant = nil, label = "30-stud teleport" },
		{ kind = "leap20", variant = "snap", label = "illegal 20-stud leap onto a rail" },
		{ kind = "leap20", variant = "superjump", label = "illegal leap at twice the launch speed" },
		{ kind = "wallpass", variant = nil, label = "wall pass" },
		{ kind = "hop", variant = nil, label = "non-adjacent route hop" },
	}
	for _, c in cheats do
		t.test(`cheat harness: {c.label} flagged within 1 s, >= 95 %, 0 false positives`, function()
			local result = Harness.cheat(c.kind, {
				world = world,
				episodes = if FAST then 10 else 40,
				seed = 777 + #c.kind,
				variant = c.variant,
			})
			local codes: { string } = {}
			for k, n in result.codes do
				table.insert(codes, `{k}={n}`)
			end
			table.sort(codes)
			print(
				`      {result.kind}: {result.detected}/{result.episodes} detected, mean {fmt(result.meanTimeToFlag)} s, max {fmt(
					result.maxTimeToFlag
				)} s; codes {table.concat(codes, " ")}; honest packets {result.honestPackets}, honest violations {result.honestViolations}`
			)
			for _, n in result.notes do
				print(`      note: {n}`)
			end
			t.truthy(result.detectionRate >= 0.95, `detection {result.detectionRate}`)
			t.truthy(result.maxTimeToFlag <= 1.0, `time to flag {result.maxTimeToFlag}`)
			t.eq(result.honestViolations, 0, "false positives in honest warm-up")
		end)
	end

	t.test("perf: validator <= 0.05 ms per squirrel per tick (15 squirrels, 600 ticks)", function()
		local perf = Harness.perf(world, 15, if FAST then 200 else 600, 4242)
		print(
			`      {fmt(perf.perTickMs)} ms per squirrel per tick ({string.format("%.1f", perf.perPacketUs)} us per packet, {perf.packets} packets)`
		)
		t.truthy(perf.perTickMs <= 0.05, `{perf.perTickMs} ms`)
	end)
end
