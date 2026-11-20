--!strict
-- probe (not committed): walk / empty-meter hop / full-meter hop paces on flat open ground
local SquirrelMotor = require("@shared/Movement/SquirrelMotor")
local TestWorld = require("@tests/cheat/TestWorld")

return function(t)
	t.test("hop table", function()
		local world = TestWorld.build({ boxes = {} })
		local function run(W: number?, stamina: number, winded: boolean, sprint: boolean, DUR: number?): (number, number, boolean, number)
			local s = SquirrelMotor.new(0, world.groundHeight, -1300)
			s.stamina, s.winded = stamina, winded
			local x0, z0 = s.x, s.z
			local groundT = 0
			local windedLeaps, leaps = 0, 0
			local DUR = DUR or 30
			for _ = 1, DUR * 60 do
				local i = SquirrelMotor.idleInput(math.pi)
				i.fw = 1
				i.sprint = sprint
				if W and s.grounded then
					groundT += 1 / 60
					if groundT >= W then
						i.leap = true
						groundT = 0
						leaps += 1
						if s.winded then
							windedLeaps += 1
						end
					end
				end
				SquirrelMotor.step(s, i, 1 / 60, world)
			end
			return math.sqrt((s.z - z0) ^ 2 + (s.x - x0) ^ 2) / DUR, s.stamina, s.winded, windedLeaps / math.max(1, leaps)
		end
		local walk = run(nil, 1, false, false)
		local sprintPace = run(nil, 1, false, true)
		print(`      walk {string.format("%.1f", walk)} st/s, Shift held {string.format("%.1f", sprintPace)}`)
		local P = SquirrelMotor.params :: any
		local base = P.leapForwardWinded
		local lfw = tonumber((require("@lune/process") :: any).env.LFW)
		if lfw then
			P.leapForwardWinded = lfw
		end
		local shift = (require("@lune/process") :: any).env.SHIFT == "1"
		print(`      leapForwardWinded {P.leapForwardWinded} st/s (base {base}), Shift {shift}`)
		for _, W in { 0, 0.15, 0.3, 0.6, 0.9, 1.2, 1.5, 2.0 } do
			local full, fm = run(W, 1, false, shift, 6)
			local empty, em, ew, wf = run(W, 0, true, shift)
			print(
				`      W {W}: full {string.format("%.1f", full)} (meter {string.format("%.2f", fm)})  empty {string.format(
					"%.1f",
					empty
				)} ({string.format("%.0f", empty / walk * 100 - 100)} % over walk; meter {string.format("%.2f", em)} winded {ew}, winded leaps {string.format(
					"%.0f",
					wf * 100
				)} %)`
			)
		end
		P.leapForwardWinded = base
	end)
end
