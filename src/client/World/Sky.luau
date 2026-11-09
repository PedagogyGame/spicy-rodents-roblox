--!strict
-- StarterPlayer.StarterPlayerScripts.Client.World.Sky
-- The day cycle on this client (brief v2 §3 Backdrop "sky with a full day cycle: sunrise and sunset as their own
-- graphic moments, clouds ... a genuinely beautiful night sky with stars, and a moon that runs through real
-- phases"; §15 decision 10; worldgen_districts_art §14.3-14.4; BUILD_PLAN §1.4 Client/World/Sky, W6).
-- Time: the server publishes the clock once (Server/Boot/DayClock: ClockEpoch, ClockBase, ClockRate attributes);
-- here Shared/Time/Clock turns workspace:GetServerTimeNow() into game time, so every client shows the same moment
-- with no per-frame traffic. 72 real seconds per in-game day; Time/DayCurve holds sunrise and sunset longer.
-- Every frame (lighting at 30 Hz):
--   * Lighting: ClockTime through SkyKeys' warp (the sun is on the horizon inside the sunrise and sunset moments),
--     Brightness, colour shifts, ambients, exposure, Atmosphere, ColorCorrection "Grade", Bloom, SunRays and the
--     Sky (5000 stars, the engine moon hidden) from World/SkyKeys; night brightness follows the moon's phase.
--   * Clouds: Terrain.Clouds (local), cover from SkyKeys.weather (slow, identical on every client), tinted by time.
--   * Moon: a custom disc (BillboardGui rows on a camera-local part) in its real phase (Time/Moon on the calendar
--     day: new, waxing, full, waning), placed where the sun stood phase*24 hours earlier (so the full moon rises
--     at sunset), lit limb turned toward the sun on screen, pale by day. The engine moon cannot show phases
--     (Lighting:GetMoonPhase() is fixed), and no Roblox-owned phase textures are known to this project.
--   * Workspace.Backdrop: the radio tower's Beacon flashes 1 s on / 1 s off (worldgen_districts_art §14.4), the
--     harbour lights and the lighthouse flash at dusk and night, NightLight parts glow at night, fog cards take
--     the hour's haze colour, impostor cars run on the distant road (headlights at night).
--   * Lighting attribute StreetLamps (0..1) for Render/TownView's lamp pool.
-- Interface: start() -> stop(); step(gameTime) (one Clock.game() reading -> Lighting); lampLevel() -> number
-- No side effects on require.

local Import = require("../Import")
local Clock = Import.shared("Time/Clock") :: typeof(require("../../shared/Time/Clock"))
local Moon = Import.shared("Time/Moon") :: typeof(require("../../shared/Time/Moon"))
local SkyKeys = Import.shared("World/SkyKeys") :: typeof(require("../../shared/World/SkyKeys"))
local Backdrop = Import.shared("World/Backdrop") :: typeof(require("../../shared/World/Backdrop"))

local Sky = {}

Sky.MOON_DEGREES = 3.0 -- apparent diameter of the custom moon
Sky.MOON_DISTANCE = 900 -- studs from the camera (inside the haze; nearer scenery still hides it)
Sky.MOON_ROWS = 40
Sky.LIGHT_HZ = 30
Sky.CARS = 10

local lamps = 0

type GameTime = { day: number, dayFrac: number, hour: number }

function Sky.lampLevel(): number
	return lamps
end

local function c3(v: { number }): Color3
	return Color3.fromRGB(math.floor(v[1] + 0.5), math.floor(v[2] + 0.5), math.floor(v[3] + 0.5))
end

local function child(parent: Instance, class: string, name: string): any
	local found = parent:FindFirstChild(name)
	if found and found.ClassName == class then
		return found
	end
	local any = parent:FindFirstChildOfClass(class :: any)
	if any then
		return any
	end
	local i = Instance.new(class :: any)
	i.Name = name
	i.Parent = parent
	return i
end

-- Applies one game-time reading to Lighting and its effects. Returns the state used.
function Sky.step(gt: GameTime): any
	local Lighting = game:GetService("Lighting")
	local s = SkyKeys.stateAt(gt.hour)
	local k = SkyKeys.illumination(Moon.phase(gt.day + gt.dayFrac))
	lamps = s.lamps
	Lighting.ClockTime = SkyKeys.clockTimeAt(gt.hour)
	-- moonlight follows the phase at night (a new moon night is darker)
	Lighting.Brightness = s.brightness * (1 + (0.45 + 0.75 * k - 1) * s.lamps)
	Lighting.ExposureCompensation = s.exposure
	Lighting.ColorShift_Top = c3(s.top)
	Lighting.ColorShift_Bottom = c3(s.bottom)
	Lighting.OutdoorAmbient = c3(s.outdoor)
	Lighting.Ambient = c3(s.ambient)
	Lighting.EnvironmentDiffuseScale = s.diffuse
	Lighting.EnvironmentSpecularScale = s.specular
	local atm = child(Lighting, "Atmosphere", "Atmosphere") :: Atmosphere
	atm.Density = s.atmDensity
	atm.Offset = s.atmOffset
	atm.Color = c3(s.atmColor)
	atm.Decay = c3(s.atmDecay)
	atm.Glare = s.atmGlare
	atm.Haze = s.atmHaze
	local cc = child(Lighting, "ColorCorrectionEffect", "Grade") :: ColorCorrectionEffect
	cc.Brightness = s.ccBrightness
	cc.Contrast = s.ccContrast
	cc.Saturation = s.ccSaturation
	cc.TintColor = c3(s.ccTint)
	local bloom = child(Lighting, "BloomEffect", "Bloom") :: BloomEffect
	bloom.Intensity = s.bloomIntensity
	bloom.Size = s.bloomSize
	bloom.Threshold = s.bloomThreshold
	local rays = child(Lighting, "SunRaysEffect", "SunRays") :: SunRaysEffect
	rays.Intensity = s.raysIntensity
	rays.Spread = s.raysSpread
	local sky = child(Lighting, "Sky", "Sky") :: Sky
	sky.CelestialBodiesShown = true
	sky.StarCount = 5000 -- the engine's maximum; stars show only once the sky is dark
	sky.SunAngularSize = s.sunSize
	sky.MoonAngularSize = 0 -- the custom moon below shows the phase
	return s
end

-- The moon disc: rows of lit and dark frames inside a rotating container.
type MoonGui = {
	part: BasePart,
	gui: BillboardGui,
	disc: Frame,
	halo: Frame,
	lit: { Frame },
	dark: { Frame },
	phase: number,
}

local function makeMoon(): MoonGui
	local part = Instance.new("Part")
	part.Name = "SkyMoon"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.new(1, 1, 1)
	local gui = Instance.new("BillboardGui")
	gui.Name = "Moon"
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.ResetOnSpawn = false
	gui.Adornee = part
	gui.Parent = part
	local halo = Instance.new("Frame")
	halo.Name = "Halo"
	halo.AnchorPoint = Vector2.new(0.5, 0.5)
	halo.Position = UDim2.fromScale(0.5, 0.5)
	halo.Size = UDim2.fromScale(1.7, 1.7)
	halo.BackgroundColor3 = Color3.fromRGB(205, 214, 236)
	halo.BackgroundTransparency = 1
	halo.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = halo
	halo.Parent = gui
	local disc = Instance.new("Frame")
	disc.Name = "Disc"
	disc.AnchorPoint = Vector2.new(0.5, 0.5)
	disc.Position = UDim2.fromScale(0.5, 0.5)
	disc.Size = UDim2.fromScale(1, 1)
	disc.BackgroundTransparency = 1
	disc.BorderSizePixel = 0
	disc.Parent = gui
	local lit, dark = {}, {}
	for j = 1, Sky.MOON_ROWS do
		for _, kind in { "Dark", "Lit" } do
			local f = Instance.new("Frame")
			f.Name = `{kind}{j}`
			f.BorderSizePixel = 0
			f.BackgroundColor3 = if kind == "Lit" then Color3.fromRGB(246, 243, 230) else Color3.fromRGB(30, 36, 52)
			f.ZIndex = if kind == "Lit" then 2 else 1
			f.Parent = disc
			if kind == "Lit" then
				lit[j] = f
			else
				dark[j] = f
			end
		end
	end
	return { part = part, gui = gui, disc = disc, halo = halo, lit = lit, dark = dark, phase = -1 }
end

local function shapeMoon(m: MoonGui, phase: number)
	if math.abs(phase - m.phase) < 0.001 then
		return
	end
	m.phase = phase
	local overlap = 0.35 / Sky.MOON_ROWS -- rows overlap a hair so no sky shows between them
	for j, r in SkyKeys.moonRows(phase, Sky.MOON_ROWS) do
		local d, l = m.dark[j], m.lit[j]
		d.Position = UDim2.fromScale(r.darkFrom, r.top)
		d.Size = UDim2.fromScale(math.max(0, r.litTo - r.darkFrom), r.height + overlap)
		l.Position = UDim2.fromScale(r.litFrom, r.top)
		l.Size = UDim2.fromScale(math.max(0, r.litTo - r.litFrom), r.height + overlap)
		l.Visible = r.litTo - r.litFrom > 1e-3
	end
end

local function placeMoon(m: MoonGui, cam: Camera, clockTime: number, phase: number, tilt: number, night: number)
	local mx, my, mz = Backdrop.sunDirection(Backdrop.moonClockTime(clockTime, phase), tilt)
	local sx, sy, sz = Backdrop.sunDirection(clockTime, tilt)
	local moonDir = Vector3.new(mx, my, mz)
	local sunDir = Vector3.new(sx, sy, sz)
	local camCf = cam.CFrame
	local D = Sky.MOON_DISTANCE
	m.part.CFrame = CFrame.new(camCf.Position + moonDir * D)
	local size = 2 * D * math.tan(math.rad(Sky.MOON_DEGREES / 2))
	m.gui.Size = UDim2.fromScale(size, size)
	-- fade in above the horizon (and the foothills' skyline); pale and earthshine-free by day
	local up = math.clamp((my - 0.03) / 0.06, 0, 1)
	local k = SkyKeys.illumination(phase)
	local litT = 1 - up * (0.42 + 0.58 * night)
	local darkT = 1 - up * 0.72 * night
	for j = 1, #m.lit do
		m.lit[j].BackgroundTransparency = litT
		m.dark[j].BackgroundTransparency = darkT
	end
	m.halo.BackgroundTransparency = 1 - up * night * 0.12 * k
	-- turn the lit limb (+x of the disc) toward the sun on screen
	local t = sunDir - moonDir * moonDir:Dot(sunDir)
	if t.Magnitude > 1e-4 then
		local a = math.atan2(t:Dot(camCf.UpVector), t:Dot(camCf.RightVector))
		m.disc.Rotation = -math.deg(a)
	end
	m.gui.Enabled = up > 0 and k > 0.004
end

-- Backdrop pieces this client animates (found once the Persistent model has replicated).
type Pieces = {
	beacons: { BasePart },
	harbour: { BasePart },
	lighthouse: { BasePart },
	night: { { part: BasePart, color: Color3 } },
	cards: { { frame: Frame, layer: number } },
	road: { Vector3 },
	roadLen: { number },
}

local function gather(root: Instance): Pieces
	local p: Pieces = { beacons = {}, harbour = {}, lighthouse = {}, night = {}, cards = {}, road = {}, roadLen = {} }
	local segs: { BasePart } = {}
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			local blink = d:GetAttribute("Blink")
			if blink == "obstruction" then
				table.insert(p.beacons, d)
			elseif blink == "harbour" then
				table.insert(p.harbour, d)
			elseif blink == "lighthouse" then
				table.insert(p.lighthouse, d)
			elseif d:GetAttribute("NightLight") == true then
				table.insert(p.night, { part = d, color = d.Color })
			elseif d.Parent and d.Parent.Name == "Road" then
				table.insert(segs, d)
			end
		elseif d:IsA("Frame") and d.Parent and d.Parent:IsA("SurfaceGui") then
			local card = d.Parent.Parent
			local layer = if card then card:GetAttribute("FogLayer") else nil
			table.insert(p.cards, { frame = d, layer = if type(layer) == "number" then layer else 1 })
		end
	end
	table.sort(segs, function(a, b)
		return ((a:GetAttribute("Index") :: number?) or 0) < ((b:GetAttribute("Index") :: number?) or 0)
	end)
	for i, s in segs do
		local half = s.CFrame.LookVector * (s.Size.Z / 2 - 1)
		if i == 1 then
			table.insert(p.road, s.Position - half)
		end
		table.insert(p.road, s.Position + half)
	end
	local acc = 0
	for i = 1, #p.road do
		if i > 1 then
			acc += (p.road[i] - p.road[i - 1]).Magnitude
		end
		p.roadLen[i] = acc
	end
	return p
end

local function roadAt(p: Pieces, s: number): (Vector3, Vector3)
	local n = #p.roadLen
	local L = p.roadLen[n]
	s = math.clamp(s, 0, L)
	local lo, hi = 1, n
	while hi - lo > 1 do
		local mid = (lo + hi) // 2
		if p.roadLen[mid] <= s then
			lo = mid
		else
			hi = mid
		end
	end
	local a, b = p.road[lo], p.road[hi]
	local seg = p.roadLen[hi] - p.roadLen[lo]
	local f = if seg > 0 then (s - p.roadLen[lo]) / seg else 0
	return a:Lerp(b, f), (b - a).Unit
end

type Car = { body: BasePart, head: BasePart, tail: BasePart, speed: number, offset: number, dir: number }

local function makeCars(folder: Instance): { Car }
	local cars: { Car } = {}
	local colours =
		{ "b34c45", "e9e6dc", "477b88", "2f3a3d", "c9b27c", "6f8a52", "dfe2de", "5b6d82", "9a4a3c", "f0ece0" }
	local function bit(name: string, size: Vector3, colour: Color3): BasePart
		local b = Instance.new("Part")
		b.Name = name
		b.Anchored = true
		b.CanCollide = false
		b.CanQuery = false
		b.CanTouch = false
		b.CastShadow = false
		b.Size = size
		b.Color = colour
		b.Material = Enum.Material.SmoothPlastic
		b.Parent = folder
		return b
	end
	for i = 1, Sky.CARS do
		local body = bit("Car", Vector3.new(7, 5, 15), Color3.fromHex(colours[1 + (i - 1) % #colours]))
		local head = bit("Head", Vector3.new(7.4, 2, 1), Color3.fromRGB(255, 243, 205))
		local tail = bit("Tail", Vector3.new(7.4, 2, 1), Color3.fromRGB(255, 40, 30))
		table.insert(cars, {
			body = body,
			head = head,
			tail = tail,
			speed = 55 + 30 * ((i * 0.618) % 1),
			offset = i * 1873.7,
			dir = if i % 2 == 0 then 1 else -1,
		})
	end
	return cars
end

function Sky.start(): () -> ()
	local Lighting = game:GetService("Lighting")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local RunService = game:GetService("RunService")
	local alive = true
	local conns: { RBXScriptConnection } = {}
	local owned: { Instance } = {}

	local clock: any
	local function rebuild()
		local rspd = ReplicatedStorage:GetAttribute("ClockRealSecondsPerDay")
		clock = Clock.fromEngine(if type(rspd) == "number" then rspd else nil)
	end
	rebuild()
	for _, name in { "ClockEpoch", "ClockBase", "ClockRate", "ClockRealSecondsPerDay" } do
		table.insert(conns, ReplicatedStorage:GetAttributeChangedSignal(name):Connect(rebuild))
	end

	local clouds: Clouds? = nil
	pcall(function()
		local terrain = workspace.Terrain
		local found = terrain:FindFirstChildOfClass("Clouds")
		if found then
			clouds = found
		else
			local c = Instance.new("Clouds")
			c.Parent = terrain
			clouds = c
			table.insert(owned, c)
		end
		if workspace.GlobalWind.Magnitude < 0.01 then
			workspace.GlobalWind = Vector3.new(6, 0, 2.5) -- clouds drift (grass decoration is off)
		end
	end)

	local moon: MoonGui? = nil
	local okMoon = pcall(function()
		local m = makeMoon()
		m.part.Parent = workspace.CurrentCamera
		moon = m
		table.insert(owned, m.part)
	end)
	if not okMoon then
		warn("Sky: the custom moon could not be made; showing the engine moon (no phases)")
	end

	local pieces: Pieces? = nil
	local cars: { Car } = {}
	task.spawn(function()
		local root = workspace:WaitForChild("Backdrop", 60)
		if not alive or root == nil then
			if root == nil then
				warn("Sky: no Workspace.Backdrop; tower lights, fog colours and road traffic are off")
			end
			return
		end
		task.wait(1) -- a Persistent model arrives whole; give its descendants a moment anyway
		local p = gather(root)
		pieces = p
		if #p.road >= 2 then
			local folder = Instance.new("Folder")
			folder.Name = "BackdropTraffic"
			folder.Parent = workspace.CurrentCamera
			table.insert(owned, folder)
			cars = makeCars(folder)
		end
	end)

	local acc = 1
	local lastLamps = -1
	local state: any = nil
	table.insert(
		conns,
		RunService.RenderStepped:Connect(function(dt: number)
			acc += dt
			local gt = clock:game()
			if acc >= 1 / Sky.LIGHT_HZ or state == nil then
				acc = 0
				local ok, res = pcall(Sky.step, gt)
				if ok then
					state = res
				end
				local s = state
				if s and clouds then
					local cl = clouds :: Clouds
					cl.Cover = SkyKeys.weather(gt.day + gt.dayFrac)
					cl.Density = s.cloudDensity
					cl.Color = c3(s.clouds)
				end
				if math.abs(lamps - lastLamps) > 0.01 then
					lastLamps = lamps
					Lighting:SetAttribute("StreetLamps", lamps)
				end
				local p = pieces
				if s and p then
					local near, far = c3(s.fog), c3(s.fogFar)
					for _, c in p.cards do
						c.frame.BackgroundColor3 = near:Lerp(far, math.clamp((c.layer - 1) / 2, 0, 1))
					end
					local on = lamps > 0.3
					for _, n in p.night do
						n.part.Material = if on then Enum.Material.Neon else Enum.Material.SmoothPlastic
						n.part.Color = if on then n.color else n.color:Lerp(Color3.new(0.55, 0.55, 0.55), 0.5)
					end
				end
			end
			local now = workspace:GetServerTimeNow()
			local cam = workspace.CurrentCamera
			local m = moon
			if m and cam then
				local phase = Moon.phase(gt.day + gt.dayFrac)
				local tilt = math.asin(math.clamp(Lighting:GetSunDirection().Z, -1, 1))
				shapeMoon(m, phase)
				placeMoon(m, cam, Lighting.ClockTime, phase, tilt, lamps)
			end
			local p = pieces
			if p then
				-- obstruction beacon: 1 s on, 1 s off (worldgen_districts_art §14.4), on the server clock for everyone
				local beaconOn = now % 2 < 1
				for _, b in p.beacons do
					b.Material = if beaconOn then Enum.Material.Neon else Enum.Material.SmoothPlastic
					b.Color = if beaconOn then Color3.fromRGB(255, 53, 30) else Color3.fromRGB(70, 22, 18)
					local glow = b:FindFirstChildOfClass("PointLight")
					if glow then
						glow.Enabled = beaconOn
					end
				end
				local dusk = lamps > 0.2
				for i, h in p.harbour do
					local on = dusk and (now + i * 1.5) % 3 < 0.5
					h.Material = if on then Enum.Material.Neon else Enum.Material.SmoothPlastic
				end
				for _, l in p.lighthouse do
					local on = dusk and now % 6 < 0.8
					l.Material = if on then Enum.Material.Neon else Enum.Material.SmoothPlastic
				end
				local L = if #p.roadLen > 0 then p.roadLen[#p.roadLen] else 0
				if L > 0 then
					local lightsOn = lamps > 0.3
					for _, c in cars do
						local s = (now * c.speed + c.offset) % L
						if c.dir < 0 then
							s = L - s
						end
						local pos, dir = roadAt(p, s)
						dir *= c.dir
						local right = dir:Cross(Vector3.yAxis).Unit
						local at = pos + right * 5 + Vector3.new(0, 2.6, 0)
						local cf = CFrame.lookAt(at, at + dir)
						c.body.CFrame = cf
						c.head.CFrame = cf * CFrame.new(0, -0.6, -7.8)
						c.tail.CFrame = cf * CFrame.new(0, -0.6, 7.8)
						c.head.Material = if lightsOn then Enum.Material.Neon else Enum.Material.SmoothPlastic
						c.tail.Material = if lightsOn then Enum.Material.Neon else Enum.Material.SmoothPlastic
					end
				end
			end
		end)
	)

	return function()
		alive = false
		for _, c in conns do
			c:Disconnect()
		end
		for _, i in owned do
			i:Destroy()
		end
		for _, c in cars do
			c.body:Destroy()
			c.head:Destroy()
			c.tail:Destroy()
		end
	end
end

return Sky
