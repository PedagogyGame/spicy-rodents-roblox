-- SERVER ONLY. Single-rider point-to-point cabin prototype. Not a full cable car physics model.
-- Requires 3 anchored BaseParts: cabin, stationA, stationB. Character root anchored during transit.
local RunService = game:GetService("RunService")
local SkyLiftService = {}
SkyLiftService.__index = SkyLiftService
function SkyLiftService.new(cabin, stationA, stationB, speed)
    for _, p in ipairs({cabin, stationA, stationB}) do
        assert(p and p:IsA("BasePart") and p.Anchored, "anchored BaseParts required")
    end
    assert(cabin ~= stationA and cabin ~= stationB and stationA ~= stationB, "unique parts required")
    return setmetatable({cabin = cabin, stations = {stationA.CFrame, stationB.CFrame},
        speed = speed or 11, endpoint = 1, riding = nil, conn = nil}, SkyLiftService)
end
function SkyLiftService:Board(player)
    if self.riding then return false, "occupied" end
    local character = player and player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not root or not humanoid or humanoid.Health <= 0 then return false, "no rider" end
    if (root.Position - self.cabin.Position).Magnitude > 9 then return false, "too far" end
    local from = self.stations[self.endpoint]
    local toIndex = (self.endpoint == 1) and 2 or 1
    local to = self.stations[toIndex]
    local d = (from.Position - to.Position).Magnitude
    if d < 0.1 or self.speed <= 0 then return false, "invalid lift stations" end
    local relative = self.cabin.CFrame:ToObjectSpace(character:GetPivot())
    local oldAnchored = root.Anchored
    root.Anchored = true
    local ride = {player = player, root = root, character = character,
        humanoid = humanoid, originalAnchor = oldAnchored, relative = relative,
        from = from, to = to, targetIndex = toIndex, elapsed = 0,
        duration = d / self.speed}
    self.riding = ride
    self.conn = RunService.Heartbeat:Connect(function(dt)
        if self.riding ~= ride then return end
        if not root.Parent or not character.Parent or humanoid.Health <= 0 then
            self:Cancel("rider left")
            return
        end
        ride.elapsed += dt
        local a = math.clamp(ride.elapsed / ride.duration, 0, 1)
        local cf = ride.from:Lerp(ride.to, a)
        self.cabin.CFrame = cf
        character:PivotTo(cf * ride.relative)
        if a >= 1 then
            self.endpoint = ride.targetIndex
            self:Cancel("arrived")
        end
    end)
    return true
end
function SkyLiftService:Cancel(reason)
    if self.conn then self.conn:Disconnect(); self.conn = nil end
    local ride = self.riding
    self.riding = nil
    if ride and ride.root and ride.root.Parent then
        ride.root.Anchored = ride.originalAnchor
        ride.root.AssemblyLinearVelocity = Vector3.zero
    end
end
function SkyLiftService:Destroy() self:Cancel("destroyed") end
return SkyLiftService
