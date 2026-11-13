-- SERVER ONLY. Local route lookup using RoofRouteData.luau, with explicit graph edges.
-- No changes to original v5.4 route registry or movement. Caller authorizes actual moves.
local RoofRouteData = require(script.Parent:WaitForChild("RoofRouteData"))
local RoofRouteService = {}
RoofRouteService.__index = RoofRouteService
function RoofRouteService.new(roofTransform)
    assert(typeof(roofTransform) == "CFrame", "roofTransform CFrame required")
    local self = setmetatable({transform = roofTransform, byId = {}, neighbors = {}}, RoofRouteService)
    for _,node in ipairs(RoofRouteData.Nodes) do
        assert(not self.byId[node.id], "duplicate roof node")
        self.byId[node.id] = node
        self.neighbors[node.id] = {}
    end
    for _,edge in ipairs(RoofRouteData.Edges) do
        assert(self.byId[edge.a] and self.byId[edge.b], "missing route endpoint")
        table.insert(self.neighbors[edge.a],edge.b)
        if edge.bidirectional then table.insert(self.neighbors[edge.b],edge.a) end
    end
    return self
end
function RoofRouteService:WorldPosition(id)
    local n = self.byId[id]
    if not n then return nil end
    return self.transform:PointToWorldSpace(n.position)
end
function RoofRouteService:Nearest(worldPos, radius)
    if typeof(worldPos) ~= "Vector3" then return nil end
    local best, distance = nil, radius or 7
    for id in pairs(self.byId) do
        local d = (self:WorldPosition(id) - worldPos).Magnitude
        if d < distance then best, distance = id, d end
    end
    return best, distance
end
function RoofRouteService:CanTraverse(fromId, toId)
    local arr = self.neighbors[fromId]
    if not arr then return false end
    for _,id in ipairs(arr) do if id == toId then return true end end
    return false
end
function RoofRouteService:Neighbors(id)
    return table.clone(self.neighbors[id] or {})
end
return RoofRouteService
