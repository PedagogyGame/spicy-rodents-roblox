--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Map.Minimap
-- The minimap and the full map from Map/MapModel layers (BUILD_PLAN §1.4 UI row, §3.10, W1 #11).
-- Interface: layout(map, cx, cz, radius, size) -> Layout (pure); new(map, opts?) -> Minimap;
--            Minimap:mount(parent) (engine); :update(x, z) ; :setMarkers({ {kind, x, z} }) ; :toggleFull()
--
-- North-up, +X on the left (MapModel.project). The whole town is one canvas of Frames (one per lot, road,
-- water and extension area; about 400) inside a clipping frame; the minimap pans the canvas under a fixed
-- player dot, the full map (M) scales it to fit. Markers use MapModel.MARKERS colours. The panel always
-- says what it is ("MAP - press M"), per the owner-facing build rule (HANDOFF §4.0).
-- Pure maths in `layout`; Instance work only in mount/update/setMarkers; requiring has no side effects.

local Import = require("../Import")
local MapModel = Import.shared("Map/MapModel") :: typeof(require("../../shared/Map/MapModel"))

-- Exported types do not cross Import (W1 Track A note): the map is restated loosely.
type Map = any

export type Layout = { canvasW: number, canvasH: number, offsetX: number, offsetY: number, dotX: number, dotY: number }

local Minimap = {}
Minimap.__index = Minimap

-- layout(map, cx, cz, radius, size): the canvas size in pixels so `radius` studs fill `size` pixels, and
-- the canvas offset that puts (cx, cz) at the panel centre.
function Minimap.layout(map: Map, cx: number, cz: number, radius: number, size: number): Layout
	local b = map.bounds
	local scale = size / (2 * radius) -- pixels per stud
	local canvasW = (b.maxX - b.minX) * scale
	local canvasH = (b.maxZ - b.minZ) * scale
	local u, v = MapModel.project(map, cx, cz)
	return {
		canvasW = canvasW,
		canvasH = canvasH,
		offsetX = size / 2 - u * canvasW,
		offsetY = size / 2 - v * canvasH,
		dotX = size / 2,
		dotY = size / 2,
	}
end

local function color(hexStr: string): Color3
	return Color3.fromHex(hexStr)
end

export type Minimap = typeof(setmetatable(
	{} :: {
		map: Map,
		size: number,
		radius: number,
		full: boolean,
		root: Frame?,
		canvas: Frame?,
		markers: { [number]: Frame },
		x: number,
		z: number,
	},
	Minimap
))

function Minimap.new(map: Map, opts: { size: number?, radius: number? }?): Minimap
	local o: { size: number?, radius: number? } = opts or {}
	return setmetatable({
		map = map,
		size = o.size or 220,
		radius = o.radius or 400,
		full = false,
		root = nil,
		canvas = nil,
		markers = {},
		x = 0,
		z = 0,
	}, Minimap)
end

function Minimap.mount(self: Minimap, parent: Instance)
	local root = Instance.new("Frame")
	root.Name = "Minimap"
	root.Size = UDim2.fromOffset(self.size, self.size + 18)
	root.AnchorPoint = Vector2.new(1, 0)
	root.Position = UDim2.new(1, -12, 0, 12)
	root.BackgroundColor3 = color(MapModel.COLORS.ground)
	root.BorderSizePixel = 0
	root.ClipsDescendants = true
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, 0, 0, 18)
	title.BackgroundColor3 = Color3.new(0.1, 0.1, 0.1)
	title.TextColor3 = Color3.new(1, 1, 1)
	title.TextSize = 12
	title.Text = "MAP - press M for the full map"
	title.ZIndex = 5
	title.Parent = root
	local canvas = Instance.new("Frame")
	canvas.Name = "Canvas"
	canvas.BackgroundTransparency = 1
	canvas.Parent = root
	for _, r in MapModel.layers(self.map) do
		local u0, v0 = MapModel.project(self.map, r.x0, r.z0)
		local u1, v1 = MapModel.project(self.map, r.x1, r.z1)
		local f = Instance.new("Frame")
		f.Name = r.id or r.kind
		f.BorderSizePixel = 0
		f.BackgroundColor3 = color((MapModel.COLORS :: any)[r.kind] or MapModel.COLORS.road)
		f.BackgroundTransparency = if r.kind == "area" then 0.6 else 0
		f.Position = UDim2.fromScale(math.min(u0, u1), math.min(v0, v1))
		f.Size = UDim2.fromScale(math.abs(u1 - u0), math.abs(v1 - v0))
		f.Parent = canvas
	end
	local dot = Instance.new("Frame")
	dot.Name = "You"
	dot.Size = UDim2.fromOffset(8, 8)
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.BackgroundColor3 = color(MapModel.MARKERS.you.color)
	dot.ZIndex = 4
	dot.Parent = root
	root.Parent = parent
	self.root, self.canvas = root, canvas
	self:update(self.x, self.z)
end

function Minimap.update(self: Minimap, x: number, z: number)
	self.x, self.z = x, z
	local root, canvas = self.root, self.canvas
	if not root or not canvas then
		return
	end
	local size = if self.full then 600 else self.size
	local radius = if self.full
		then math.max(self.map.bounds.maxX - self.map.bounds.minX, self.map.bounds.maxZ - self.map.bounds.minZ) / 2
		else self.radius
	local cx = if self.full then (self.map.bounds.minX + self.map.bounds.maxX) / 2 else x
	local cz = if self.full then (self.map.bounds.minZ + self.map.bounds.maxZ) / 2 else z
	local l = Minimap.layout(self.map, cx, cz, radius, size)
	root.Size = UDim2.fromOffset(size, size + 18)
	canvas.Size = UDim2.fromOffset(l.canvasW, l.canvasH)
	canvas.Position = UDim2.fromOffset(l.offsetX, l.offsetY + 18)
	local dot = root:FindFirstChild("You") :: Frame?
	if dot then
		local u, v = MapModel.project(self.map, x, z)
		dot.Position = UDim2.fromOffset(l.offsetX + u * l.canvasW, l.offsetY + 18 + v * l.canvasH)
	end
end

function Minimap.setMarkers(self: Minimap, list: { { kind: string, x: number, z: number } })
	local canvas = self.canvas
	if not canvas then
		return
	end
	for i, m in list do
		local f = self.markers[i]
		if not f then
			local made = Instance.new("Frame")
			made.Size = UDim2.fromOffset(6, 6)
			made.AnchorPoint = Vector2.new(0.5, 0.5)
			made.ZIndex = 3
			made.Parent = canvas
			self.markers[i] = made
			f = made
		end
		local frame = f :: Frame
		local u, v = MapModel.project(self.map, m.x, m.z)
		frame.Position = UDim2.fromScale(u, v)
		frame.BackgroundColor3 = color(((MapModel.MARKERS :: any)[m.kind] or MapModel.MARKERS.quest).color)
		frame.Visible = true
	end
	for i = #list + 1, #self.markers do
		self.markers[i].Visible = false
	end
end

function Minimap.toggleFull(self: Minimap)
	self.full = not self.full
	self:update(self.x, self.z)
end

return Minimap
