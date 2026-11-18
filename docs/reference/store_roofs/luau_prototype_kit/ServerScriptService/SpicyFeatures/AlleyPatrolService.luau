-- SERVER ONLY. Optional routine alley NPC movement; no combat, pursuit, or player changes.
-- NPC: Model with Humanoid. Waypoints: Folder of BaseParts, sequentially named 01, 02 ...
local AlleyPatrolService = {}
AlleyPatrolService.__index = AlleyPatrolService
function AlleyPatrolService.new(npc, waypointFolder, pauseSeconds)
    assert(npc and npc:IsA("Model"), "NPC Model required")
    assert(waypointFolder and waypointFolder:IsA("Folder"), "waypoint Folder required")
    local humanoid = npc:FindFirstChildOfClass("Humanoid")
    assert(humanoid, "NPC Humanoid required")
    local points = {}
    for _,item in ipairs(waypointFolder:GetChildren()) do
        if item:IsA("BasePart") then table.insert(points, item) end
    end
    table.sort(points, function(a,b) return a.Name < b.Name end)
    assert(#points >= 2, "At least two alley waypoints required")
    return setmetatable({npc = npc, humanoid = humanoid, points = points,
        pauseSeconds = pauseSeconds or 0.75, running = false}, AlleyPatrolService)
end
function AlleyPatrolService:Start()
    if self.running then return end
    self.running = true
    task.spawn(function()
        local i = 1
        while self.running and self.npc.Parent and self.humanoid.Health > 0 do
            self.humanoid:MoveTo(self.points[i].Position)
            self.humanoid.MoveToFinished:Wait()
            if not self.running then break end
            task.wait(self.pauseSeconds)
            i = (i % #self.points) + 1
        end
        self.running = false
    end)
end
function AlleyPatrolService:Stop() self.running = false end
return AlleyPatrolService
