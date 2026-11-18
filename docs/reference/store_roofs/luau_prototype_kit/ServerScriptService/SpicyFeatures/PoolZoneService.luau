-- SERVER ONLY. Non-invasive pool-zone flags; use Roblox Terrain Water for actual swimming.
-- Keeps movement controller unchanged; this does NOT implement dive animations or buoyancy.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local PoolZoneService = {}
PoolZoneService.__index = PoolZoneService
function PoolZoneService.new(zonePart)
    assert(zonePart and zonePart:IsA("BasePart"), "PoolZone requires BasePart")
    return setmetatable({zone = zonePart, timer = 0, connection = nil}, PoolZoneService)
end
function PoolZoneService:Inside(worldPosition)
    local localPosition = self.zone.CFrame:PointToObjectSpace(worldPosition)
    local half = self.zone.Size * .5
    return math.abs(localPosition.X) <= half.X and math.abs(localPosition.Y) <= half.Y
        and math.abs(localPosition.Z) <= half.Z
end
function PoolZoneService:Start()
    if self.connection then return end
    self.connection = RunService.Heartbeat:Connect(function(dt)
        self.timer += dt
        if self.timer < 0.25 then return end
        self.timer = 0
        for _,player in ipairs(Players:GetPlayers()) do
            local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
            local inside = root ~= nil and self:Inside(root.Position)
            if player:GetAttribute("SpicyInPool") ~= inside then
                player:SetAttribute("SpicyInPool", inside)
            end
        end
    end)
end
function PoolZoneService:Stop()
    if self.connection then self.connection:Disconnect(); self.connection = nil end
end
return PoolZoneService
