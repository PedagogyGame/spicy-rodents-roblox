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
local TestWorld = require("@tests/cheat/TestWorld")

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
end
