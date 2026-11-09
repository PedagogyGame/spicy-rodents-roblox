--!strict
-- Server/Movement/MovementService (BUILD_PLAN §4.4 #6; HANDOFF rule 12) and Server/Telemetry: squirrel
-- packets through MoveValidator with corrections withheld (log-only), the generic speed check, the 1 s
-- pose history for every body, the possession handoff seam (markTeleported + reset), and Telemetry's
-- per-system ms and counts.
local Flags = require("@shared/Config/Flags")
local Log = require("@shared/Util/Log")
local MoveValidator = require("@server/Movement/MoveValidator")
local MovementService = require("@server/Movement/MovementService")
local SquirrelMotor = require("@shared/Movement/SquirrelMotor")
local Telemetry = require("@server/Telemetry")
local TestWorld = require("@tests/cheat/TestWorld")

return function(t)
	local world = TestWorld.build({ boxes = {} })

	t.test("squirrel packets: validated, pose history kept, corrections withheld while log-only", function()
		local swept = {
			marked = {},
			markTeleported = function(self, id)
				table.insert(self.marked, id)
			end,
		}
		local m = MovementService.new({ validator = MoveValidator.new(world), swept = swept })
		local s = SquirrelMotor.new(10, world.groundHeight, 10)
		local inp = SquirrelMotor.idleInput(0)
		inp.fw = 1
		for i = 0, 60 do
			if i > 0 then
				SquirrelMotor.step(s, inp, 1 / 60, world)
			end
			local v = m:packet("sq", "squirrel", { seq = i, snapshot = SquirrelMotor.serialize(s) }, i / 60)
			t.truthy(v.ok, `honest {i}`)
		end
		local x = m:pose("sq", 0.5)
		t.truthy(x ~= nil)
		-- a teleport cheat: flagged, logged, no correction sent while log-only
		Log.capture()
		local cheat = SquirrelMotor.serialize(s)
		cheat.x = (cheat.x :: number) + 400
		local verdict
		for i = 1, 5 do
			cheat.x = (cheat.x :: number) + 50
			verdict = m:packet("sq", "squirrel", { seq = 60 + i, snapshot = cheat }, 1 + i / 60)
		end
		t.truthy(m:stats().flagged >= 1)
		t.eq(verdict.correction, nil)
		Flags.set("moveValidatorEnforce", true)
		cheat.x = (cheat.x :: number) + 50
		verdict = m:packet("sq", "squirrel", { seq = 70, snapshot = cheat }, 1.2)
		t.truthy(verdict.correction ~= nil)
		Flags.reset()
		Log.setSink()
		-- the handoff seam
		m:onHandoff({ id = "sq" }, nil, "release")
		t.deepEq(swept.marked, { "sq" })
		t.eq(m:pose("sq", 1), nil)
		local fresh = m:packet("sq", "squirrel", { seq = 1, snapshot = SquirrelMotor.serialize(s) }, 2)
		t.truthy(fresh.baseline) -- the next packet is the new baseline
		t.eq(m:stats().handoffs, 1)
	end)

	t.test("generic kinds: speed cap per kind, stale packets ignored, 1 s rewind", function()
		Log.capture()
		local m = MovementService.new({})
		for i = 0, 60 do
			local v = m:packet("h", "human", { seq = i, t = i / 60, x = i * 0.2, y = 3, z = 0 }, i / 60)
			t.truthy(v.ok)
		end
		local x = m:pose("h", 0.5)
		t.near(x :: number, 6, 1e-9)
		local fast = m:packet("h", "human", { seq = 61, t = 61 / 60, x = 12 + 5, y = 3, z = 0 }, 61 / 60)
		t.falsy(fast.ok)
		t.eq(m:stats().overSpeed, 1)
		m:packet("h", "human", { seq = 10, t = 2, x = 999, y = 3, z = 0 }, 2) -- stale
		t.near(m:pose("h", 5) :: number, 17, 1e-9)
		-- a drone may go faster than a human
		m:packet("d", "drone", { seq = 1, t = 0, x = 0, y = 50, z = 0 }, 0)
		t.truthy(m:packet("d", "drone", { seq = 2, t = 1, x = 55, y = 50, z = 0 }, 1).ok)
		Log.setSink()
	end)

	t.test("Telemetry: per-system ms across frames, counts, bytes, budget check", function()
		local now = 0
		local tel = Telemetry.new(function()
			return now
		end)
		for f = 1, 4 do
			local stop = tel:scope("ai")
			now += 0.001 * f
			stop()
			tel:add("ai", 1)
			tel:count("actors.near", 10 + f)
			tel:bytes("VehiclePoses", 13)
			tel:frame()
		end
		local r = tel:report()
		t.eq(r.frames, 4)
		t.near(r.systems.ai.mean, (2 + 3 + 4 + 5) / 4, 1e-9)
		t.near(r.systems.ai.max, 5, 1e-9)
		t.eq(r.counts["actors.near"], 14)
		t.eq(r.bytes.VehiclePoses, 52)
		t.truthy(tel:over("ai", 3))
		t.falsy(tel:over("ai", 4))
		t.falsy(tel:over("nothing", 0))
	end)
end
