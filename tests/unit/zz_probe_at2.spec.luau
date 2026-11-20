--!strict
-- scratch probe (not committed): the re-aim's landing on flat ground
local SquirrelMotor = require("@shared/Movement/SquirrelMotor")
local Units = require("@shared/Config/Units")
local TestWorld = require("@tests/cheat/TestWorld")

return function(t)
	local world = TestWorld.build({ boxes = {} })
	-- a leap (W held, sprint `sp`), a press at frame `at` (nil: none), the aim wanted after it; the landing's distance
	local function flight(at: number?, yaw: number, reach: number, sp: boolean, fwKey: number): (number, number, number)
		local s = SquirrelMotor.new(Units.st(-560), world.groundHeight, Units.st(-545))
		for _ = 1, 30 do
			local i = SquirrelMotor.idleInput(math.pi)
			i.fw, i.sprint = fwKey, sp
			SquirrelMotor.step(s, i, 1 / 60, world)
		end
		local x0, z0 = s.x, s.z
		local f = 0
		local maxh = 0
		repeat
			f += 1
			local i = SquirrelMotor.idleInput(math.pi)
			i.fw, i.sprint = fwKey, sp
			i.leap = f == 1
			i.trick = at ~= nil and f == at
			if at and f > at then
				i.aimYaw, i.aimReach = yaw, reach
			end
			SquirrelMotor.step(s, i, 1 / 60, world)
			maxh = math.max(maxh, math.sqrt(s.vx * s.vx + s.vz * s.vz))
		until (s.grounded and f > 2) or f > 600
		return math.sqrt((s.x - x0) ^ 2 + (s.z - z0) ^ 2), f / 60, maxh
	end
	t.test("probe", function()
		for _, sp in { true, false } do
			for _, fwKey in { 1, 0 } do
				local d0, t0, h0 = flight(nil, 0, 0, sp, fwKey)
				local line = string.format("sprint %s fw %d: plain %.2f st %.2f s (h %.1f)", tostring(sp), fwKey, d0, t0, h0)
				for _, at in { 2, 6, 12, 18, 24, 26, 30, 36, 42, 46 } do
					local dO, _, hO = flight(at, 0, 1, sp, fwKey)
					local dI = flight(at, 0, -1, sp, fwKey)
					line ..= string.format("\n   press f%d: out %+.1f%% (h %.1f), in %+.1f%%", at, (dO / d0 - 1) * 100, hO, (dI / d0 - 1) * 100)
				end
				print(line)
			end
		end
	end)
end
