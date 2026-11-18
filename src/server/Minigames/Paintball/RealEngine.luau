--!strict
-- ServerScriptService.Server.Minigames.Paintball.RealEngine
-- The paintball service's hands on real bodies (PaintballService.Engine; Contract decision 5): where a
-- possessed R15 body's feet are, putting it somewhere, and the collision group that lets the bodies
-- of a match pass through each other. World coordinates; the service converts.
-- A body's FEET POINT is its root part's middle less the root's own half height and the Humanoid's
-- hip height (3.0 on the town's R15 bodies: Shared/Minigames/Paintball/Body, "the eye").
-- ghost(body, true) puts every part of the body in Contract.COLLISION_GROUP, which does not collide
-- with itself and collides with everything else as the default group does, and remembers the group
-- each part was in (the attribute WAS); ghost(body, false) puts each part back. The group is
-- registered the first time it is needed. A part that joins a ghosted body later (an accessory loaded
-- after the join, a tool, a limb the avatar code rebuilds) is ghosted as it arrives, until the body is
-- un-ghosted: as first built only the parts there at the join were, and a late hat or arm still blocked
-- a corridor a stud to one side of where the puppet is drawn.
-- ping(player) is the engine's own measure of a player's round trip (Player:GetNetworkPing, documented as the
-- time for data to go to the client and back), which the client cannot shorten or lengthen with its stamps.
-- Interface: new() -> PaintballService.Engine { positionOf, teleport, ghost, ping }; WAS; ROOT_ABOVE_FEET

local Import = require("../../Import")
local Contract: typeof(require(game.ReplicatedStorage.Shared.Minigames.Paintball.Contract)) =
	Import.shared("Minigames/Paintball/Contract")

local RealEngine = {}

RealEngine.WAS = "PaintballWasGroup"
RealEngine.ROOT_ABOVE_FEET = 3

local function rootOf(body: any): any
	if typeof(body) ~= "Instance" then
		return nil
	end
	local model = body :: any
	if model.Parent == nil then
		return nil
	end
	return model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
end

local function rootHeight(body: any, root: any): number
	local humanoid = body:FindFirstChildOfClass("Humanoid")
	if humanoid ~= nil and type(humanoid.HipHeight) == "number" then
		local h = humanoid.HipHeight + root.Size.Y / 2
		if h > 0.5 then
			return h
		end
	end
	return RealEngine.ROOT_ABOVE_FEET
end

function RealEngine.new(): {
	positionOf: (body: any) -> (number?, number?, number?),
	teleport: (body: any, x: number, y: number, z: number, yaw: number) -> (),
	ghost: (body: any, on: boolean) -> (),
	ping: (player: any) -> number?,
}
	local registered = false
	local watching: { [any]: any } = setmetatable({}, { __mode = "k" }) :: any -- body -> its DescendantAdded connection
	local function register()
		if registered then
			return
		end
		registered = true
		pcall(function()
			local PhysicsService = game:GetService("PhysicsService")
			local group = Contract.COLLISION_GROUP
			if not PhysicsService:IsCollisionGroupRegistered(group) then
				PhysicsService:RegisterCollisionGroup(group)
			end
			PhysicsService:CollisionGroupSetCollidable(group, group, false)
		end)
	end
	return {
		positionOf = function(body: any): (number?, number?, number?)
			local root = rootOf(body)
			if root == nil then
				return nil, nil, nil
			end
			local p = root.Position
			return p.X, p.Y - rootHeight(body, root), p.Z
		end,
		teleport = function(body: any, x: number, y: number, z: number, yaw: number)
			local root = rootOf(body)
			if root == nil then
				return
			end
			-- the root part goes to the feet point raised by its own height, turned to the yaw; the model's
			-- pivot (wherever it is) is carried along
			local goal = CFrame.new(x, y + rootHeight(body, root), z) * CFrame.Angles(0, yaw, 0)
			body:PivotTo(goal * root.CFrame:ToObjectSpace(body:GetPivot()))
			pcall(function()
				root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
			end)
		end,
		ghost = function(body: any, on: boolean)
			if typeof(body) ~= "Instance" then
				return
			end
			if on then
				register()
			end
			local group = Contract.COLLISION_GROUP
			local function into(part: any)
				if part:GetAttribute(RealEngine.WAS) == nil then
					part:SetAttribute(RealEngine.WAS, part.CollisionGroup or "Default")
				end
				part.CollisionGroup = group
			end
			for _, child in (body :: Instance):GetDescendants() do
				if not child:IsA("BasePart") then
					continue
				end
				local part = child :: any
				if on then
					into(part)
				else
					local was = part:GetAttribute(RealEngine.WAS)
					if was ~= nil then
						part.CollisionGroup = tostring(was)
						part:SetAttribute(RealEngine.WAS, nil)
					end
				end
			end
			local conn = watching[body]
			if on and conn == nil then
				pcall(function()
					watching[body] = (body :: any).DescendantAdded:Connect(function(child: any)
						if child:IsA("BasePart") then
							into(child)
						end
					end)
				end)
			elseif not on and conn ~= nil then
				watching[body] = nil
				pcall(function()
					conn:Disconnect()
				end)
			end
		end,
		-- the engine's own measure of the player's round trip, seconds (Player:GetNetworkPing; Clock, "the
		-- round trip"); nil for anything that is not a real Player
		ping = function(player: any): number?
			local ok, v = pcall(function(): any
				return player:GetNetworkPing()
			end)
			return if ok and type(v) == "number" and v == v and v >= 0 then v else nil
		end,
	}
end

return RealEngine
