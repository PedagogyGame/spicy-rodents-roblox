--!strict
-- Shared/Config/Units: the single unit boundary (BUILD_PLAN §1.4, D21).
local roblox = require("@lune/roblox")
local Units = require("@shared/Config/Units")

-- Lune has no CFrame/Vector3 globals; @lune/roblox provides the same types.
local CFrame = roblox.CFrame
local Vector3 = roblox.Vector3

return function(t)
	t.test("1 unit is 2.5 studs", function()
		t.near(Units.st(1), 2.5)
		t.near(Units.st(4), 10)
	end)
	t.test("studs back to units round-trips", function()
		for _, u in { 0, 0.48, 3.15, 1332, -3.4 } do
			t.near(Units.u(Units.st(u)), u, 1e-9)
		end
	end)
	t.test("HTML yaw gets exactly one +pi", function()
		t.near(Units.robloxYaw(0), math.pi)
		t.near(Units.robloxYaw(math.pi), 2 * math.pi)
	end)
	t.test("the +pi flip turns a -Z-facing rig towards HTML +Z (yawCFrame maths)", function()
		-- Units.yawCFrame itself uses the engine globals (covered by BootSmoke); here the same
		-- expression is evaluated with Lune's CFrame to check the maths.
		local cf = CFrame.new(Vector3.new(1, 2, 3)) * CFrame.Angles(0, Units.robloxYaw(0), 0)
		t.near(cf.Position.X, 1)
		t.near(cf.Position.Z, 3)
		-- HTML yaw 0 faces +Z; after the flip the Roblox LookVector must be +Z as well.
		t.near(cf.LookVector.Z, 1, 1e-6)
	end)
end
