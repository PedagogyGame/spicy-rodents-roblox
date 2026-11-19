--!strict
-- tests/isolated/riders_built.luau: cases for tests/unit/riders_built.spec.luau, run in their own Lune process
-- (tests/lib/Isolated) because they put engine globals in place (getfenv) for Server/AI/Puppets.build.
-- The street riders as Actors/BodyFactory builds them (Puppets.build("human", "rider", index, folder, slot)), on
-- Lune's instances (review of feat/bikes-art, finding 4): the rider is the one its town slot names (TownAI's
-- actor.ride), whatever its index; its root stands 2.2 studs above the ground (the old part-built rider's: ActorService
-- ground offsets and footDrop were set on it), the only part that takes queries.
-- Interface: return function(t) (the spec shape)
local roblox = require("@lune/roblox")
local Puppets = require("@server/AI/Puppets")
local RidePuppet = require("@shared/Vehicles/RidePuppet")

do
	local dm = roblox.Instance.new("DataModel")
	-- selene: allow(deprecated)
	local env = getfenv(0) :: any
	env.Instance, env.Vector3, env.CFrame, env.Color3, env.Enum =
		roblox.Instance, roblox.Vector3, roblox.CFrame, roblox.Color3, roblox.Enum
	env.game, env.workspace = dm, dm:GetService("Workspace")
end

-- the lowest point of any visible part, in the root's frame
local function lowest(model: any): number
	local root = model.PrimaryPart
	local low = math.huge
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 1 then
			local cf = root.CFrame:ToObjectSpace(d.CFrame)
			local s = d.Size
			local up = (math.abs(cf.XVector.Y) * s.X + math.abs(cf.YVector.Y) * s.Y + math.abs(cf.ZVector.Y) * s.Z) / 2
			low = math.min(low, cf.Position.Y - up)
		end
	end
	return low
end

return function(t)
	t.test("a street rider is the person its town slot names, whatever its body index", function()
		for slot = 1, #RidePuppet.RIDERS do
			-- an index whose own default slot (index % 8 + 1) is a different rider
			local index = slot + 3
			local rig = Puppets.build("human", "rider", index, roblox.Instance.new("Folder"), slot)
			t.eq(rig.model:GetAttribute("RiderName"), RidePuppet.RIDERS[slot].name, `slot {slot}`)
		end
	end)

	t.test(
		"as built: the rider's root stands 2.2 studs above the ground and is the only part that takes queries",
		function()
			for slot = 1, #RidePuppet.RIDERS do
				local rig = Puppets.build("human", "rider", 100 + slot, roblox.Instance.new("Folder"), slot)
				local root = rig.root
				t.eq(root.Name, "HumanoidRootPart", `slot {slot}`)
				t.truthy(root.Size.X == 1 and root.Size.Y == 1 and root.Size.Z == 1, `slot {slot}: the 1 x 1 x 1 root`)
				-- the old part-built rider's height (literal: the tyres on the ground 2.2 below the root)
				t.near(lowest(rig.model), -2.2, 0.02, `slot {slot}: the ground under the root`)
				for _, d in rig.model:GetDescendants() do
					if d:IsA("BasePart") and d ~= root then
						t.falsy(d.CanQuery or d.CanCollide or d.CanTouch, `slot {slot}: {d.Name} is never hit`)
					end
				end
			end
		end
	)
end
