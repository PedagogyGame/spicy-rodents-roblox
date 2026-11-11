--!strict
-- ServerScriptService.Server.Minigames.Dartboard
-- The dartboard's hardware (brief v2 §13a; BUILD_PLAN §3.16 darts: "server_deterministic"): a throw is resolved
-- by the rules (Minigames/MinigameRules/Darts: aim point + timing meter + seeded scatter), and this module shows it:
-- a dart flies from the thrower's hand to the landing point on the baked board (GamesRoom.Dartboard.BoardFace) and
-- sticks there, the turn's darts are pulled out when the turn passes, the idle darts hide while a game is on.
-- Board coordinates are millimetres from the bull (+x the thrower's right, +y up) as in the rules. A dart thrown
-- wild is drawn in the cabinet's edge (REACH), never in the air beyond it; its score is the rules' business.
-- Interface: new(opts) -> Board; Board:land(xmm, ymm, from?: Vector3); Board:clear(); Board:busy(); Board:idle(on);
--   Board:step(dt); Board:worldPoint(xmm, ymm) -> Vector3

local Import = require("../Import")
local AlleyLayout = Import.shared("Attractions/AlleyLayout") :: typeof(require("../../shared/Attractions/AlleyLayout"))

local Dartboard = {}
Dartboard.__index = Dartboard

Dartboard.FLIGHT = 0.32 -- seconds in the air
Dartboard.REACH = 320 -- mm from the bull, each way: as far out as a dart is drawn (the cabinet is 342 mm)

function Dartboard.new(opts: { [string]: any }): any
	local self = setmetatable({}, Dartboard) :: any
	self.place = opts.place
	self.model = opts.model :: Model?
	self.board = AlleyLayout.board()
	self.darts = {} :: { Model }
	self.flights = {} :: { { [string]: any } }
	self.clock = 0
	self.folder = Instance.new("Folder")
	self.folder.Name = "ThrownDarts"
	self.folder.Parent = self.model or workspace
	return self
end

-- The world point of a board position (mm), on the face.
function Dartboard.worldPoint(self: any, xmm: number, ymm: number): Vector3
	local b = self.board
	local _, Y, D = AlleyLayout.boardPoint(xmm, ymm)
	local x, y, z = AlleyLayout.toWorld(self.place, b.x - 0.07, Y, D)
	return Vector3.new(x, y, z)
end

-- The direction the board faces (into the room), world.
function Dartboard.normal(self: any): Vector3
	local dx, dz = AlleyLayout.dirToWorld(self.place, -1, 0)
	return Vector3.new(dx, 0, dz)
end

local function makeDart(parent: Instance, color: Color3): Model
	local m = Instance.new("Model")
	m.Name = "Dart"
	local function part(name: string, size: Vector3, offset: CFrame, col: Color3, mat: Enum.Material): BasePart
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Size = size
		p.Color = col
		p.Material = mat
		p:SetAttribute("Offset", offset)
		p.Parent = m
		return p
	end
	-- along local -Z (the point leads)
	part(
		"Barrel",
		Vector3.new(0.06, 0.06, 0.2),
		CFrame.new(0, 0, -0.08),
		Color3.fromRGB(190, 190, 196),
		Enum.Material.Metal
	)
	part(
		"Point",
		Vector3.new(0.02, 0.02, 0.12),
		CFrame.new(0, 0, -0.24),
		Color3.fromRGB(220, 220, 225),
		Enum.Material.Metal
	)
	part("Shaft", Vector3.new(0.03, 0.03, 0.18), CFrame.new(0, 0, 0.1), color, Enum.Material.SmoothPlastic)
	part("FlightA", Vector3.new(0.16, 0.005, 0.12), CFrame.new(0, 0, 0.2), color, Enum.Material.SmoothPlastic)
	part("FlightB", Vector3.new(0.005, 0.16, 0.12), CFrame.new(0, 0, 0.2), color, Enum.Material.SmoothPlastic)
	m.Parent = parent
	return m
end

local function place(m: Model, cf: CFrame)
	for _, p in m:GetChildren() do
		if p:IsA("BasePart") then
			p.CFrame = cf * (p:GetAttribute("Offset") :: CFrame)
		end
	end
end

local SEAT_COLORS = { { 220, 40, 40 }, { 40, 90, 220 }, { 40, 170, 80 }, { 240, 190, 40 } }

-- land: a dart flies from `from` (the thrower's hand; default the oche at shoulder height) to (xmm, ymm).
function Dartboard.land(self: any, xmm: number, ymm: number, seat: number?, from: Vector3?)
	local b = self.board
	local reach = Dartboard.REACH
	local target = self:worldPoint(math.clamp(xmm, -reach, reach), math.clamp(ymm, -reach, reach))
	local n = self:normal()
	local startPos = from
	if startPos == nil then
		local x, y, z = AlleyLayout.toWorld(self.place, b.ocheX + 0.4, 4.8, b.d + 0.6)
		startPos = Vector3.new(x, y, z)
	end
	local rgb = SEAT_COLORS[seat or 1] or SEAT_COLORS[1]
	local dart = makeDart(self.folder, Color3.fromRGB(rgb[1], rgb[2], rgb[3]))
	table.insert(self.darts, dart)
	-- stuck pose: point into the board, tail out along the normal (tilted a touch upward)
	local stuck = CFrame.lookAt(target + n * 0.18, target - n + Vector3.new(0, -0.12, 0))
	table.insert(self.flights, { dart = dart, from = startPos :: Vector3, to = stuck, t = 0 })
	place(dart, CFrame.lookAt(startPos :: Vector3, target))
end

function Dartboard.busy(self: any): boolean
	return #self.flights > 0
end

function Dartboard.clear(self: any)
	for _, d in self.darts do
		d:Destroy()
	end
	table.clear(self.darts)
	table.clear(self.flights)
end

function Dartboard.idle(self: any, on: boolean)
	local m = self.model
	local idle = m and m:FindFirstChild("IdleDarts")
	if idle then
		for _, p in idle:GetChildren() do
			if p:IsA("BasePart") then
				p.Transparency = if on then 0 else 1
			end
		end
	end
end

function Dartboard.step(self: any, dt: number)
	self.clock += dt
	if #self.flights == 0 then
		return
	end
	local keep = {}
	for _, f in self.flights do
		f.t += dt
		local a = math.clamp(f.t / Dartboard.FLIGHT, 0, 1)
		local to = f.to.Position
		-- a shallow arc
		local p = f.from:Lerp(to, a) + Vector3.new(0, math.sin(a * math.pi) * 0.35, 0)
		if a >= 1 then
			place(f.dart, f.to)
		else
			local ahead = f.from:Lerp(to, math.min(1, a + 0.05))
				+ Vector3.new(0, math.sin(math.min(1, a + 0.05) * math.pi) * 0.35, 0)
			place(f.dart, CFrame.lookAt(p, ahead))
			table.insert(keep, f)
		end
	end
	self.flights = keep
end

return Dartboard
