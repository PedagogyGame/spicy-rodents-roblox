--!strict
-- tests/isolated/cart_two_seats.luau: cases for tests/unit/cart_two_seats.spec.luau, run in their own Lune process
-- (tests/lib/Isolated) because they put engine globals in place (getfenv) for Shared/Vehicles/Placeholder.build.
-- Owner D30: "i would like for the golf carts to be able to seat two". The cart as Server/Actors/DeviceService builds it:
-- a hidden PassengerSeat beside the DriverSeat, mirrored across the bench, on the drawn bench, under the canopy, off the
-- steering wheel's side; no second camera eye; nothing on any other kind.
-- Interface: return function(t) (the spec shape)
local roblox = require("@lune/roblox")
local Placeholder = require("@shared/Vehicles/Placeholder")
local VehicleKinds = require("@shared/Vehicles/VehicleKinds")

do
	local dm = roblox.Instance.new("DataModel")
	-- selene: allow(deprecated)
	local env = getfenv(0) :: any
	env.Instance, env.Vector3, env.CFrame, env.Color3, env.Enum =
		roblox.Instance, roblox.Vector3, roblox.CFrame, roblox.Color3, roblox.Enum
	env.game, env.workspace = dm, dm:GetService("Workspace")
end

local function part(m: any, name: string): any
	for _, d in m:GetChildren() do
		if d:IsA("BasePart") and d.Name == name then
			return d
		end
	end
	return nil
end

return function(t)
	t.test("the golf cart: a hidden seat beside the driver's, on the bench, under the canopy, off the wheel", function()
		local m = Placeholder.build("cart", "cart")
		local driver = m:FindFirstChild("DriverSeat") :: any
		local other = m:FindFirstChild("PassengerSeat") :: any
		t.truthy(other and other:IsA("Seat"), "a Seat the server sits the passenger on")
		local a, b = driver.CFrame.Position, other.CFrame.Position
		t.near(b.X, -a.X, 1e-4, "mirrored across the middle")
		t.near(b.Y, a.Y, 1e-4, "at the driver's height")
		t.near(b.Z, a.Z, 1e-4, "side by side")
		t.truthy(math.abs(b.X - a.X) >= 1.5, `room for two ({math.abs(b.X - a.X)} studs apart)`)
		local bench = part(m, "Seat")
		t.truthy(math.abs(b.X - bench.CFrame.Position.X) <= bench.Size.X / 2, "on the drawn bench")
		local canopy = part(m, "Canopy")
		t.truthy(math.abs(b.X - canopy.CFrame.Position.X) <= canopy.Size.X / 2, "under the canopy")
		local wheel = part(m, "Steering")
		t.truthy(math.abs(b.X - wheel.CFrame.Position.X) > 1, "not behind the wheel")
		-- hidden, weightless, nothing walks into it and gets seated, nothing queries it
		t.eq(other.Transparency, 1)
		t.falsy(other.CanCollide)
		t.falsy(other.CanQuery)
		t.falsy(other.CanTouch)
		t.truthy(other.Massless)
		t.falsy(other.CastShadow)
		-- welded to the root
		local welded = false
		for _, d in other:GetChildren() do
			if d:IsA("WeldConstraint") then
				welded = true
			end
		end
		for _, d in m.PrimaryPart:GetChildren() do
			if d:IsA("WeldConstraint") and (d.Part1 == other or d.Part0 == other) then
				welded = true
			end
		end
		t.truthy(welded, "welded to the cart")
		-- its socket, and still one camera eye
		local sockets, eyes = 0, 0
		for _, d in m:GetDescendants() do
			if d:IsA("Attachment") and d.Name == "PassengerSeat" then
				sockets += 1
			elseif d:IsA("Attachment") and d.Name == "EyeSocket" then
				eyes += 1
			end
		end
		t.eq(sockets, 1)
		t.eq(eyes, 1, "the camera never takes the passenger's place")
	end)

	t.test("no other kind has a second seat", function()
		for _, id in VehicleKinds.list() do
			if id ~= "cart" then
				local m = Placeholder.build(id, id)
				t.eq(m:FindFirstChild("PassengerSeat"), nil, id)
			end
		end
	end)
end
