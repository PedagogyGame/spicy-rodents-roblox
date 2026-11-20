--!strict
-- scratch probe (not committed): movement_validator's honest circuits on several seeds, with and without the cooldown
local process = require("@lune/process")
local Units = require("@shared/Config/Units")
local SquirrelMotor = require("@shared/Movement/SquirrelMotor")
local Harness = require("@tests/cheat/Harness")
local TestWorld = require("@tests/cheat/TestWorld")

return function(t)
	local boxes: { TestWorld.Box } = {
		{ minX = Units.st(-540), maxX = Units.st(-528), minZ = Units.st(-400), maxZ = Units.st(-388), top = Units.st(5.3) },
		{ minX = Units.st(-540), maxX = Units.st(-528), minZ = Units.st(-280), maxZ = Units.st(-268), top = Units.st(5.3) },
	}
	local world = TestWorld.build({ boxes = boxes })
	world.crosses = function(x0, z0, x1, z1, y)
		return TestWorld.segmentCrossesBox(boxes, x0, z0, x1, z1, y)
	end
	t.test("seeds", function()
		local cd = SquirrelMotor.params.grabLeapCooldown
		for _, c in { cd, 0 } do
			SquirrelMotor.params.grabLeapCooldown = c
			for s in string.gmatch(process.env.SEEDS or "4", "%d+") do
				local r: any = Harness.honest({
					world = world,
					squirrels = 6,
					minutes = 10,
					seed = tonumber(s),
					jitter = 0.15,
					loss = 0.02,
				})
				print(string.format("cd %.3f seed %s: %d violations", c, s, r.violations))
			end
		end
		SquirrelMotor.params.grabLeapCooldown = cd
	end)
end
