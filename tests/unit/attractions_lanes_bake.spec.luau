--!strict
-- tools/bake/alley/Lanes built in memory (the same code that writes build/Attractions.rbxm): the names and
-- properties the bowling server (Server/Minigames/BowlingLane) and the client's playback rely on are there.
-- Eighteen lanes; each with its ball on the rack slot, ten pin models whose PrimaryPart "Body" stands on the pin's
-- spot, anchored, colliding with nothing and fully visible (the server hides and shows pins by Transparency
-- and the client assumes a shown pin is at 0), the sweep bar and its edge; and the LaneGuard that keeps people
-- off the lanes.
local roblox = require("@lune/roblox")
local AlleyLayout = require("@shared/Attractions/AlleyLayout")
local Kit = require("../../tools/bake/alley/Kit")
local Lanes = require("../../tools/bake/alley/Lanes")

local PLACE: AlleyLayout.Place = { x = 40, z = -90, floorY = 12, yaw = 0.6 }

return function(t)
	local kit = Kit.new(roblox, PLACE)
	local root = roblox.Instance.new("Model")
	root.Name = "BowlingAlley"
	Lanes.build(kit, root)

	t.test("eighteen lanes, each with a ball on its rack slot, a sweep bar and ten pins on their spots", function()
		t.eq(AlleyLayout.LANES, 18)
		local lanes = root:FindFirstChild("Lanes") :: any
		t.truthy(lanes ~= nil)
		for lane = 1, AlleyLayout.LANES do
			local lm = lanes:FindFirstChild(`Lane{lane}`)
			t.truthy(lm ~= nil and lm:IsA("Model"), `Lane{lane}`)
			local ball = lm:FindFirstChild("Ball")
			t.truthy(ball ~= nil and ball:IsA("BasePart"))
			local rx, ry, rd = AlleyLayout.rackSlot(lane)
			local bx, by, bz = AlleyLayout.toWorld(PLACE, rx, ry, rd)
			t.truthy(
				(ball.CFrame.Position - roblox.Vector3.new(bx, by, bz)).Magnitude < 0.01,
				"the ball is on its rack slot"
			)
			t.near(ball.Size.X, AlleyLayout.BALL_D, 1e-4)
			t.truthy(ball.Anchored)
			t.truthy(lm:FindFirstChild("Sweep") ~= nil and lm:FindFirstChild("SweepEdge") ~= nil)
			local pins = lm:FindFirstChild("Pins")
			t.eq(#pins:GetChildren(), 10)
			for n = 1, 10 do
				local pm = pins:FindFirstChild(`Pin{n}`)
				t.truthy(pm ~= nil and pm:IsA("Model"), `lane {lane} pin {n}`)
				local body = pm.PrimaryPart
				t.truthy(body ~= nil and body.Name == "Body", "the pivot is the pin's belly")
				local px, pd = AlleyLayout.pinLocal(lane, n)
				local wx, wy, wz = AlleyLayout.toWorld(PLACE, px, 0.45, pd)
				t.truthy(
					(body.CFrame.Position - roblox.Vector3.new(wx, wy, wz)).Magnitude < 0.01,
					`lane {lane} pin {n} stands on its spot`
				)
				local parts = 0
				for _, d in pm:GetDescendants() do
					if d:IsA("BasePart") then
						parts += 1
						t.truthy(d.Anchored, "pins are scripted: anchored")
						t.eq(d.CanCollide, false, "and collide with nothing")
						t.eq(d.Transparency, 0, "a shown pin is fully visible")
					end
				end
				t.truthy(parts >= 5, `a pin is {parts} parts`)
			end
		end
	end)

	t.test("people are kept off the lanes by the LaneGuard", function()
		local guard: any = nil
		for _, d in root:GetDescendants() do
			if d.Name == "LaneGuard" then
				guard = d
			end
		end
		t.truthy(guard ~= nil and guard:IsA("BasePart"))
		t.eq(guard.CollisionGroup, "LaneGuard")
		t.truthy(guard.CanCollide)
		t.eq(guard.Transparency, 1)
		-- and along the two outer side walls (lane 1's and lane 18's), too tall to jump: a person jumps 7.2
		local sides = 0
		for _, d in root:GetDescendants() do
			if d.Name == "LaneGuardSide" then
				sides += 1
				t.eq(d.CollisionGroup, "LaneGuard")
				t.truthy(d.CanCollide and not d.CanQuery and d.Transparency == 1)
				t.truthy(d.Size.Y >= 9 - 1e-3, "taller than a jump")
				t.truthy(d.Size.Z >= AlleyLayout.MACHINE_D0 - AlleyLayout.FOUL_D, "from the foul line to the masking")
			end
		end
		t.eq(sides, 2)
	end)
end
