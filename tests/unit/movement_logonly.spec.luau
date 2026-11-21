--!strict
-- Log-only movement validation (Flags "moveValidatorEnforce" off, the live game's setting since 2026-11-21, set in
-- Server/Main): nothing the validator says may reach the player. A validator that flags everything, or one that
-- throws, must leave the body where its client has it: no snap, no pin, and the held place every server system reads
-- (MovementService.heldPlace, strict mode too) is the newest packet's, with the newest packet counted as the clean one
-- for the duel (motorOf).
local MovementService = require("@server/Movement/MovementService")
local SquirrelMotor = require("@shared/Movement/SquirrelMotor")

local function shot(x: number, z: number, clock: number): any
	local s = SquirrelMotor.new(x, 0, z)
	s.clock = clock
	return SquirrelMotor.serialize(s)
end

local function service(validator: any): any
	return MovementService.new({ validator = validator, enforce = false })
end

return function(t)
	t.test("a validator that flags every packet: the held place is the newest packet's, nothing snapped", function()
		local last: any = nil
		local validator = {
			world = {},
			accept = function(_self: any, _id: any, packet: any, _now: number): any
				last = packet.snapshot
				return {
					ok = false,
					accepted = true,
					flagged = true,
					bucket = 9,
					violations = { { code = "teleport", severity = 1, detail = "everything" } },
				}
			end,
			last = function(): any
				return last
			end,
			clearFlag = function() end,
			forget = function() end,
			meterOf = function(): (number, boolean)
				return 1, false
			end,
		}
		local m = service(validator)
		local snapped = 0
		for i = 1, 40 do
			local r = m:packet("a", "squirrel", { seq = i, snapshot = shot(100 + i, 50, i * 0.05) }, 10 + i * 0.05)
			if r.snapped then
				snapped += 1
			end
		end
		t.eq(snapped, 0, "no snap in log-only")
		local x, _, z = m:heldPlace("a")
		t.eq(x, 140, "the newest packet's x")
		t.eq(z, 50)
		local sx = m:heldPlace("a", true)
		t.eq(sx, 140, "strict mode too")
		local _, lastAt, _, cleanAt = m:motorOf("a")
		t.eq(cleanAt, lastAt, "the newest packet counts as the clean one")
	end)

	t.test("a validator that throws on every packet: caught, counted, the packet's place taken", function()
		local validator = {
			world = {},
			accept = function(): any
				error("engine-only failure")
			end,
			last = function(): any
				return nil
			end,
			clearFlag = function() end,
			forget = function() end,
			meterOf = function(): (number, boolean)
				return 1, false
			end,
		}
		local m = service(validator)
		for i = 1, 10 do
			local r = m:packet("a", "squirrel", { seq = i, snapshot = shot(200 + i, 60, i * 0.05) }, 20 + i * 0.05)
			t.truthy(r.ok, "taken")
			t.falsy(r.snapped)
		end
		local x, _, z = m:heldPlace("a")
		t.eq(x, 210)
		t.eq(z, 60)
		t.truthy(((m:stats() :: any).judgeErrors or 0) >= 1, "the failures are counted")
	end)
end
