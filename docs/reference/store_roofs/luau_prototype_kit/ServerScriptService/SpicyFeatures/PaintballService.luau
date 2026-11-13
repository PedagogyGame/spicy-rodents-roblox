-- SERVER ONLY. Nonlethal paintball hit/scoring core; does not damage Humanoid.
-- Requires an arena BasePart (invisible zone is fine) and equipped Tool called PaintballMarker.
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local PaintballService = {}
PaintballService.__index = PaintballService
local function finiteVector(v)
    return typeof(v) == "Vector3" and v.X == v.X and v.Y == v.Y and v.Z == v.Z
        and math.abs(v.X) < 1e7 and math.abs(v.Y) < 1e7 and math.abs(v.Z) < 1e7
end
local function findHumanoidModel(part)
    local p = part
    while p and p ~= Workspace do
        if p:IsA("Model") and p:FindFirstChildOfClass("Humanoid") then return p end
        p = p.Parent
    end
    return nil
end
function PaintballService.new(arenaPart, options)
    assert(arenaPart and arenaPart:IsA("BasePart"), "arena BasePart required")
    options = options or {}
    return setmetatable({
        arena = arenaPart, members = {}, scores = {}, lastFire = {},
        active = false, round = 0,
        toolName = options.ToolName or "PaintballMarker",
        maxRange = options.MaxRange or 160,
        cooldown = options.Cooldown or 0.35,
    }, PaintballService)
end
function PaintballService:Inside(pos)
    if not finiteVector(pos) then return false end
    local p = self.arena.CFrame:PointToObjectSpace(pos)
    local h = self.arena.Size * 0.5
    return math.abs(p.X) <= h.X and math.abs(p.Y) <= h.Y
        and math.abs(p.Z) <= h.Z
end
function PaintballService:Join(player)
    if not player or not player:IsA("Player") then return false, "invalid player" end
    local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    if not root or not self:Inside(root.Position) then return false, "outside arena" end
    self.members[player] = true
    self.scores[player] = self.scores[player] or 0
    return true
end
function PaintballService:Leave(player)
    self.members[player] = nil
    self.lastFire[player] = nil
end
function PaintballService:StartRound()
    self.round += 1
    self.active = true
    for p in pairs(self.scores) do self.scores[p] = 0 end
end
function PaintballService:StopRound() self.active = false end
function PaintballService:Fire(player, origin, direction)
    if not self.active or not self.members[player] then return false, "not participating" end
    if not finiteVector(origin) or not finiteVector(direction) or direction.Magnitude < 0.001 then
        return false, "invalid aim"
    end
    local char = player.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    local humanoid = char and char:FindFirstChildOfClass("Humanoid")
    if not root or not humanoid or humanoid.Health <= 0 then return false, "no active avatar" end
    if not self:Inside(root.Position) or (origin - root.Position).Magnitude > 9 then
        return false, "invalid shot origin"
    end
    local tool = char:FindFirstChild(self.toolName)
    if not tool or not tool:IsA("Tool") then return false, "marker not equipped" end
    local now = os.clock()
    if (now - (self.lastFire[player] or -1e6)) < self.cooldown then return false, "cooldown" end
    self.lastFire[player] = now
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {char}
    params.IgnoreWater = true
    local ray = Workspace:Raycast(origin, direction.Unit * self.maxRange, params)
    if not ray then return true, "miss" end
    if not self:Inside(ray.Position) then return true, "outside arena" end
    local targetModel = findHumanoidModel(ray.Instance)
    local target = targetModel and Players:GetPlayerFromCharacter(targetModel)
    if not target or target == player or not self.members[target] then return true, "environment" end
    local targetRoot = target.Character and target.Character:FindFirstChild("HumanoidRootPart")
    if not targetRoot or not self:Inside(targetRoot.Position) then return true, "target exited" end
    local targetHumanoid = target.Character:FindFirstChildOfClass("Humanoid")
    if not targetHumanoid or targetHumanoid.Health <= 0 then return true, "inactive target" end
    self.scores[player] = (self.scores[player] or 0) + 1
    return true, "player hit", target, self.scores[player]
end
function PaintballService:GetScore(player) return self.scores[player] or 0 end
return PaintballService
