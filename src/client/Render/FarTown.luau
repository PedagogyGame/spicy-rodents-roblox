--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Render.FarTown
-- The town from far off, drawn on this screen only (Shared/World/FarTown plans it; the town bake is untouched).
-- The review of the view from the Lookout, the terrace and the cabins: "the town is plain boxes", and at night
-- "a black plain". So, for every building whose lot is streamed out:
--   * its far house (Shared/World/FarTown.plan: the body turned with the lot, a gable or a flat roof's cap, window
--     bands) in a local Model under Workspace.FarTown, shown while the lot itself is streamed out (as the
--     Skyline's massing box was; that box is hidden here with LocalTransparencyModifier, so Render/TownView's
--     own switch no longer shows it);
--   * at night (Lighting's StreetLamps, Render/TownLights' hysteresis) the lit window bands glow warm (Neon);
--   * a warm dot of fixed size on screen (a BillboardGui) on every street-lamp head farther than DOT_NEAR from
--     the camera, at night only: a lamp head is a stud and a half wide, two studs a pixel at 1,500 studs;
--   * one soft crown per town tree (FarTown.crowns from Generated/TreeArt: a trunk and three balls), shown only farther than
--     CROWN_NEAR from the camera, where the real tree has streamed out.
-- Nothing collides, casts a shadow or answers a raycast. Started by the client's Main; no service access on require.
-- Interface: start() -> stop; CROWN_NEAR, DOT_NEAR, PERIOD, FOLDER

local Import = require("../Import")
local Data = Import.shared("Data") :: typeof(require("../../shared/Data"))
local Plan = Import.shared("World/FarTown") :: typeof(require("../../shared/World/FarTown"))
local TownLights = require("./TownLights")

local FarTown = {}

FarTown.CROWN_NEAR = 900 -- studs: crowns only beyond this
FarTown.DOT_NEAR = 400 -- studs: lamp dots only beyond this
FarTown.PERIOD = 0.5 -- seconds between looks at the camera and the lamp level
FarTown.FOLDER = "FarTown"
FarTown.DOT_PX = 6

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function quiet(p: BasePart)
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
end

type Lot = { model: Model, bands: { { part: BasePart, lit: boolean, litColor: Color3 } }, shown: boolean }

function FarTown.start(): () -> ()
	local alive = true
	local conns: { RBXScriptConnection } = {}
	local folder = Instance.new("Folder")
	folder.Name = FarTown.FOLDER
	folder.Parent = workspace
	local store = Instance.new("Folder") -- far houses not shown wait here, out of the world
	store.Name = "FarTownHidden"
	local dotsGui: Instance? = nil
	local hidden: { BasePart } = {}
	task.spawn(function()
		local town = workspace:WaitForChild("Town", 120)
		local skyline = town and town:WaitForChild("Skyline", 60)
		if not alive or town == nil or skyline == nil then
			warn("FarTown: no Workspace.Town.Skyline; the town from far off stays as boxes")
			return
		end
		-- the lots' data and the Skyline's boxes
		local byId: { [string]: any } = {}
		for _, lot in Data.default():lots() do
			if type(lot.id) == "string" then
				byId[lot.id] = lot
			end
		end
		local boxes: { any } = {} -- Shared/World/FarTown.Box
		local massing: { [string]: BasePart } = {}
		local heads: { BasePart } = {}
		for _, d in skyline:GetChildren() do
			if d:IsA("BasePart") then
				local lotId = d:GetAttribute("Lot")
				if type(lotId) == "string" then
					local p, s, c = d.Position, d.Size, d.Color
					table.insert(boxes, {
						lot = lotId,
						cx = p.X,
						cy = p.Y,
						cz = p.Z,
						sx = s.X,
						sy = s.Y,
						sz = s.Z,
						color = {
							math.floor(c.R * 255 + 0.5),
							math.floor(c.G * 255 + 0.5),
							math.floor(c.B * 255 + 0.5),
						},
					})
					massing[lotId] = d
				elseif string.sub(d.Name, 1, 5) == "Head_" then
					table.insert(heads, d)
				end
			end
		end
		local lotsOf: { [string]: Lot } = {}
		for _, pc in Plan.plan(boxes, byId) do
			local rec = lotsOf[pc.lot]
			if rec == nil then
				local m = Instance.new("Model")
				m.Name = pc.lot
				rec = { model = m, bands = {}, shown = false }
				lotsOf[pc.lot] = rec
			end
			local part: BasePart = if pc.shape == "Wedge" then Instance.new("WedgePart") else Instance.new("Part")
			part.Name = pc.name
			part.Size = Vector3.new(pc.sx, pc.sy, pc.sz)
			part.CFrame = CFrame.new(pc.x, pc.y, pc.z) * CFrame.Angles(0, pc.yaw, 0)
			part.Color = rgb(pc.color)
			part.Material = (Enum.Material :: any)[pc.material] or Enum.Material.SmoothPlastic
			quiet(part)
			part.Parent = rec.model
			if pc.band then
				table.insert(rec.bands, { part = part, lit = pc.lit, litColor = rgb(pc.litColor or pc.color) })
			end
		end
		for id, rec in lotsOf do
			rec.model.Parent = store
			local box = massing[id]
			if box then
				box.LocalTransparencyModifier = 1 -- the far house stands in for it
				table.insert(hidden, box)
			end
		end
		local lots = town:WaitForChild("Lots", 30)
		local function refresh(lotId: string)
			local rec = lotsOf[lotId]
			if rec then
				local show = lots ~= nil and lots:FindFirstChild(lotId) == nil
				if show ~= rec.shown then
					rec.shown = show
					rec.model.Parent = if show then folder else store
				end
			end
		end
		for id in lotsOf do
			refresh(id)
		end
		if lots then
			table.insert(
				conns,
				lots.ChildAdded:Connect(function(c: Instance)
					refresh(c.Name)
				end)
			)
			table.insert(
				conns,
				lots.ChildRemoved:Connect(function(c: Instance)
					refresh(c.Name)
				end)
			)
		end
		-- the crowns
		local crowns: { { parts: { BasePart }, at: Vector3, shown: boolean } } = {}
		local okArt, art = pcall(function()
			return Data.default():module("TreeArt")
		end)
		local crownFolder = Instance.new("Folder")
		crownFolder.Name = "Crowns"
		crownFolder.Parent = folder
		for _, c in if okArt then Plan.crowns(art :: any) else {} do
			local parts: { BasePart } = {}
			local trunk = Instance.new("Part")
			trunk.Name = "Trunk"
			trunk.Shape = Enum.PartType.Cylinder
			local th = c.trunkTop - c.trunkBase
			trunk.Size = Vector3.new(th, c.trunkD, c.trunkD)
			trunk.CFrame = CFrame.new(c.x, c.trunkBase + th / 2, c.z) * CFrame.Angles(0, 0, math.pi / 2)
			trunk.Color = rgb(Plan.BARK :: any)
			trunk.Material = Enum.Material.Wood
			table.insert(parts, trunk)
			for _, b in c.balls do
				local ball = Instance.new("Part")
				ball.Name = "Crown"
				ball.Shape = Enum.PartType.Ball
				ball.Size = Vector3.new(b[4], b[4], b[4])
				ball.CFrame = CFrame.new(b[1], b[2], b[3])
				ball.Color = rgb(b[5])
				ball.Material = Enum.Material.Grass
				table.insert(parts, ball)
			end
			for _, part in parts do
				quiet(part)
				part.Transparency = 1
				part.Parent = crownFolder
			end
			table.insert(crowns, { parts = parts, at = Vector3.new(c.x, c.y, c.z), shown = false })
		end
		-- the lamp dots
		local player = game:GetService("Players").LocalPlayer
		local gui = player and player:FindFirstChildOfClass("PlayerGui")
		local holder = Instance.new("Folder")
		holder.Name = "FarTownDots"
		holder.Parent = gui
		dotsGui = holder
		local dots: { { gui: BillboardGui, at: Vector3 } } = {}
		for _, h in heads do
			local b = Instance.new("BillboardGui")
			b.Name = "LampDot"
			b.Adornee = h
			b.Size = UDim2.fromOffset(FarTown.DOT_PX, FarTown.DOT_PX)
			b.LightInfluence = 0
			b.AlwaysOnTop = false
			b.Enabled = false
			local f = Instance.new("Frame")
			f.Size = UDim2.fromScale(1, 1)
			f.BackgroundColor3 = Color3.fromRGB(255, 214, 150)
			f.BackgroundTransparency = 0.1
			f.BorderSizePixel = 0
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(1, 0)
			corner.Parent = f
			f.Parent = b
			b.Parent = holder
			table.insert(dots, { gui = b, at = h.Position })
		end
		-- day and night, the camera's distance
		local night = false
		local acc = FarTown.PERIOD
		table.insert(
			conns,
			game:GetService("RunService").Heartbeat:Connect(function(dt: number)
				acc += dt
				if acc < FarTown.PERIOD then
					return
				end
				acc = 0
				local level = game:GetService("Lighting"):GetAttribute("StreetLamps")
				local nowNight = if type(level) == "number" then TownLights.next(night, level) else false
				if nowNight ~= night then
					night = nowNight
					for _, rec in lotsOf do
						for _, b in rec.bands do
							local glow = night and b.lit
							b.part.Material = if glow then Enum.Material.Neon else Enum.Material.SmoothPlastic
							b.part.Color = if glow then b.litColor else rgb(Plan.GLASS :: any)
						end
					end
				end
				local cam = workspace.CurrentCamera
				if cam == nil then
					return
				end
				local p = cam.CFrame.Position
				for _, c in crowns do
					local show = (c.at - p).Magnitude > FarTown.CROWN_NEAR
					if show ~= c.shown then
						c.shown = show
						for _, part in c.parts do
							part.Transparency = if show then 0 else 1
						end
					end
				end
				for _, d in dots do
					d.gui.Enabled = night and (d.at - p).Magnitude > FarTown.DOT_NEAR
				end
			end)
		)
	end)
	return function()
		alive = false
		for _, c in conns do
			c:Disconnect()
		end
		folder:Destroy()
		store:Destroy()
		if dotsGui then
			dotsGui:Destroy()
		end
		for _, box in hidden do
			box.LocalTransparencyModifier = 0
		end
	end
end

return FarTown
