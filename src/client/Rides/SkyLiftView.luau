--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Rides.SkyLiftView
-- The sky lift as this client sees it (brief v2 line 250 "A sky lift up a slight hill to a hilltop restaurant";
-- line 259 "the gondola must hold up at eye level"; line 278 "no controls, no score, you get on and it happens";
-- the sky-lift plan's lane 5). Nothing is sent and nothing here is replicated: every client draws the six cabins
-- from the same shared clock (Shared/Rides/SkyLift: t = workspace:GetServerTimeNow() - the SkyLiftEpoch
-- attribute on ReplicatedStorage), so the cabins agree with the server's seats without a pose stream.
--   * Cabins: Workspace.Expansion.F4.CabinTemplate (the bake's, Persistent; tools/bake/skylift/Cabin) is cloned
--     six times into a local folder Workspace.SkyLiftCabins and placed every frame from SkyLift.cabin(i, t) with
--     one workspace:BulkMoveTo. The number plates read 1..6. The doors (Doors/DoorFore, Doors/DoorAft) slide
--     along the cabin by their SlideZ attribute times SkyLift.doorFrac(i, t). At night (Lighting's StreetLamps,
--     the hysteresis of Render/TownLights) the ceiling panel (Light) glows and its PointLight is on.
--   * Riders: every body in Workspace.Bodies carrying a Ride attribute "<cabin>/<seat>" (the server's, lane 4)
--     has its root put on that seat of the local cabin in the same render step, before the camera: the cabin and
--     its riders come from the same clock on this screen, so nobody shakes against the cabin they sit in. The root
--     goes SIT_ROOT over the seat's top, facing the seat's way. (Client/Animation/AnimationDriver's visual-root
--     settle and ground probe must leave a body with a Ride attribute alone, or it hangs off its seat: joiner.)
--   * Wheels: the bullwheels (and their hubs) in f4_lift_base and f4_lift_summit and the sheaves of the
--     f4_lift_tower_<k> heads turn with the haul rope at LINE_SPEED, the right way round, while streamed in and
--     within SPIN_RANGE of the camera (their baked poses are kept; the angle comes from the clock).
--   * The camera: seatModel(cabin, seat) is a Model holding just that seat of the local cabin, with its
--     EyeSocket, so CameraRig's vehicleFirst (which looks for the first EyeSocket in the model it is given) sits
--     at the right eye; cabinModel(cabin) is the whole cabin for an outside view; eye(cabin, seat) is the eye's
--     CFrame on the clock this screen drew.
--   * Words: BOARD_LINE on boarding; hudFor(cabin, t) gives the title and hint for the ride (where it is going
--     and the seconds left).
-- The clock is smoothed: it advances by the frame time and is slewed toward the server's by at most SLEW of a
-- frame, so a cabin never jumps when the client's estimate of server time is corrected (a change of more than
-- SNAP seconds, as when the epoch first arrives, is taken at once).
-- The render step runs at RenderPriority.Camera - 2, before CameraRig's (Camera - 1).
-- Started once by the client's Main (the joiner, lane 6). No service access at require time (Lune requires it).
-- Interface: start(opts?) -> stop; frame(dt) (one render step; the bound step calls it); clock() -> t?;
--   cabinModel(cabin) -> Model?; seatModel(cabin, seat) -> Model?; eye(cabin, seat) -> CFrame?;
--   rideOf(body) -> (cabin?, seat?); parseRide(value) -> (cabin?, seat?) (pure); rootAt(cabin, seat, t) ->
--   x, y, z, yaw (pure); advance(t?, dt, target) -> t (pure); hudFor(cabin, t) -> title, hint, secs, dest (pure);
--   spinAngle(t, radius, sign) -> radians (pure); BOARD_LINE, SIT_ROOT, SLEW, SNAP, SPIN_RANGE, BIND, FOLDER
--   opts = { now: (() -> number)? (server time; default workspace:GetServerTimeNow()), bind: boolean? (false:
--   no render step, the caller calls frame) }

local Import = require("../Import")
local SkyLift = Import.shared("Rides/SkyLift") :: typeof(require("../../shared/Rides/SkyLift"))
local TownLights = require("../Render/TownLights")

local SkyLiftView = {}

SkyLiftView.BOARD_LINE = "Riding the sky lift. Move the mouse to look around. V: outside view."
SkyLiftView.SIT_ROOT = 1.35 -- an R15 root above what it sits on (Client/Animation/AnimationDriver.SIT_SEAT)
SkyLiftView.SLEW = 0.05 -- the most the smoothed clock gains or loses on the server's, per second of frames
SkyLiftView.SNAP = 1 -- seconds: a bigger disagreement is taken at once
SkyLiftView.SPIN_RANGE = 600 -- studs from the camera within which the wheels are turned
SkyLiftView.BIND = "SpicySkyLift"
SkyLiftView.FOLDER = "SkyLiftCabins"
SkyLiftView.RIDERS_PERIOD = 0.1 -- seconds between looks for bodies with a Ride attribute
SkyLiftView.LIGHTS_PERIOD = 0.5 -- seconds between looks at the lamp level
SkyLiftView.SCAN_PERIOD = 1 -- seconds between looks for the template and for streamed-in wheels
SkyLiftView.WAIT_WARN = 30 -- seconds without a CabinTemplate before the console is told

export type Opts = { now: (() -> number)?, bind: boolean? }

type PartEntry = { part: any, rel: any, leaf: number } -- leaf 0: the body; 1, 2: a door leaf
type Cabin = {
	model: any,
	parts: { PartEntry },
	slide: { number }, -- the leaves' SlideZ
	seats: { any }, -- seat k's Model (with the Seat part and its EyeSocket)
	seatParts: { any },
	light: any?,
	lamp: any?,
	lightMaterial: any,
}
type Spinner = { part: any, base: any, rate: number } -- rate: signed radians per second of the clock
type State = {
	alive: boolean,
	opts: Opts,
	t: number?,
	cabins: { Cabin },
	folder: any?,
	waited: number,
	warned: boolean,
	scanAcc: number,
	ridersAcc: number,
	lightsAcc: number,
	riders: { any },
	night: boolean?, -- nil until the day cycle has said (no StreetLamps: the baked look stands)
	wheels: { [any]: { Spinner } }, -- streamed-in model -> its spinning parts
	parts: { any },
	cframes: { any },
}

local state: State? = nil

-- ===== pure =====

-- The smoothed clock: last frame's t moved on by dt, slewed toward the server's `target` by at most SLEW * dt;
-- nil (the first frame) or a gap over SNAP takes the target.
function SkyLiftView.advance(t: number?, dt: number, target: number): number
	if t == nil then
		return target
	end
	local nextT = t + dt
	local err = target - nextT
	if math.abs(err) > SkyLiftView.SNAP then
		return target
	end
	local most = SkyLiftView.SLEW * dt
	return nextT + math.clamp(err, -most, most)
end

-- A Ride attribute: "<cabin>/<seat>" with cabin 1..CABINS and seat 1..SEATS, else nil.
function SkyLiftView.parseRide(value: any): (number?, number?)
	if type(value) ~= "string" then
		return nil, nil
	end
	local a, b = string.match(value, "^(%d+)/(%d+)$")
	local c, k = tonumber(a), tonumber(b)
	if c == nil or k == nil or c < 1 or c > SkyLift.CABINS or k < 1 or k > SkyLift.SEATS then
		return nil, nil
	end
	return c, k
end

-- Where a rider's root goes: SIT_ROOT over the top of seat k of cabin i, facing the way the seat faces.
function SkyLiftView.rootAt(i: number, k: number, t: number): (number, number, number, number)
	local x, y, z, yaw = SkyLift.seat(i, k, t)
	return x, y + SkyLiftView.SIT_ROOT, z, yaw
end

-- The wheels' angle: the rope runs at LINE_SPEED, so a wheel of `radius` turns LINE_SPEED / radius radians a
-- second, `sign` the way round (about the part's own axis, its local X).
function SkyLiftView.spinAngle(t: number, radius: number, sign: number): number
	return (sign * SkyLift.LINE_SPEED / radius * t) % (2 * math.pi)
end

-- What the screen says while riding cabin i at t: the title (where it is going), the hint (what to press and
-- the seconds to the platform), the seconds, and the station it will stop at ("summit" | "base"). The next
-- alight point a cabin reaches after boarding is always the other station's.
function SkyLiftView.hudFor(i: number, t: number): (string, string, number, string)
	local P = SkyLift.period()
	local sigma = (t - (i - 1) * P / SkyLift.CABINS) % P
	local st = SkyLift.stations()
	local toTop = (st.summit.alightSigma - sigma) % P
	local toTown = (st.base.alightSigma - sigma) % P
	local dest = if toTop <= toTown then "summit" else "base"
	local secs = math.ceil(math.min(toTop, toTown))
	local title = if dest == "summit" then "Sky lift: up to the Lookout" else "Sky lift: down to town"
	local where = if dest == "summit" then "the top" else "town"
	local hint = if secs <= 1
		then "Doors opening: step out onto the platform. V: outside view."
		else `Move the mouse to look around. V: outside view. {where} in {secs} s`
	return title, hint, secs, dest
end

-- ===== the view =====

local function now(s: State): number
	local f = s.opts.now
	local serverNow = if f then f() else workspace:GetServerTimeNow()
	local epoch = game:GetService("ReplicatedStorage"):GetAttribute(SkyLift.EPOCH_ATTRIBUTE)
	return SkyLift.clock(serverNow, if type(epoch) == "number" then epoch else 0)
end

local function template(): any
	local exp = workspace:FindFirstChild("Expansion")
	local f4 = exp and exp:FindFirstChild("F4")
	return f4 and f4:FindFirstChild("CabinTemplate")
end

-- Six clones of the template, each part's pose kept relative to the template's origin.
local function makeCabins(s: State, tpl: any)
	local origin = tpl.PrimaryPart or tpl:FindFirstChild("Origin")
	if origin == nil then
		warn("SkyLiftView: CabinTemplate has no Origin; no cabins drawn")
		return
	end
	local inv = origin.CFrame:Inverse()
	local folder = Instance.new("Folder")
	folder.Name = SkyLiftView.FOLDER
	s.folder = folder
	for i = 1, SkyLift.CABINS do
		local m = tpl:Clone()
		m.Name = `Cabin{i}`
		m:SetAttribute("Template", nil)
		m:SetAttribute("Cabin", i)
		local cab: Cabin = {
			model = m,
			parts = {},
			slide = { 0, 0 },
			seats = {},
			seatParts = {},
			light = nil,
			lamp = nil,
			lightMaterial = nil,
		}
		-- the door leaves: index 1 fore, 2 aft
		local leafOf: { [any]: number } = {}
		local doors = m:FindFirstChild("Doors")
		for li, name in { "DoorFore", "DoorAft" } do
			local leaf = doors and doors:FindFirstChild(name)
			if leaf then
				local slideZ = leaf:GetAttribute("SlideZ")
				cab.slide[li] = if type(slideZ) == "number" then slideZ else 0
				for _, d in leaf:GetDescendants() do
					leafOf[d] = li
				end
			end
		end
		-- each seat in a Model of its own, so the camera finds that seat's EyeSocket and no other
		local seats = m:FindFirstChild("Seats")
		for k = 1, SkyLift.SEATS do
			local seat = seats and seats:FindFirstChild(`Seat{k}`)
			if seat then
				local holder = Instance.new("Model")
				holder.Name = `RiderSeat{k}`
				holder:SetAttribute("Cabin", i)
				holder:SetAttribute("Seat", k)
				seat.Parent = holder
				holder.PrimaryPart = seat
				holder.Parent = m
				cab.seats[k] = holder
				cab.seatParts[k] = seat
			end
		end
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = true
				table.insert(cab.parts, { part = d, rel = inv * d.CFrame, leaf = leafOf[d] or 0 })
			end
		end
		local light = m:FindFirstChild("Light")
		if light then
			cab.light = light
			cab.lamp = light:FindFirstChildOfClass("PointLight")
			cab.lightMaterial = light.Material
		end
		for _, plate in { "NumberFront", "NumberBack" } do
			local p = m:FindFirstChild(plate)
			for _, d in if p then p:GetDescendants() else {} do
				if d.Name == "Number" and d:IsA("TextLabel") then
					d.Text = tostring(i)
				end
			end
		end
		m.Parent = folder
		s.cabins[i] = cab
	end
	folder.Parent = workspace
end

local function setNight(s: State, night: boolean)
	s.night = night
	for _, cab in s.cabins do
		if cab.lamp then
			cab.lamp.Enabled = night
		end
		if cab.light then
			cab.light.Material = if night then Enum.Material.Neon else Enum.Material.SmoothPlastic
		end
	end
end

-- Which way a wheel turns about its own axis (the part's RightVector: a cylinder's axis is its local X), as the
-- sign of (centre-to-rope x rope velocity) on that axis.
local function turnSign(part: any, rx: number, ry: number, rz: number, vx: number, vz: number): number
	-- w = r x v with v = (vx, 0, vz)
	local wx, wy, wz = ry * vz, rz * vx - rx * vz, -ry * vx
	local axis = part.CFrame.RightVector
	return if wx * axis.X + wy * axis.Y + wz * axis.Z >= 0 then 1 else -1
end

-- The loop distance of the rope nearest (x, z) in plan, from the loop's polyline.
local function nearestS(x: number, z: number): number
	local loop = SkyLift.loop()
	local best, bestS = math.huge, 0
	for j = 1, #loop.points - 1 do
		local a, b = loop.points[j], loop.points[j + 1]
		local dx, dz = b.x - a.x, b.z - a.z
		local len2 = dx * dx + dz * dz
		local u = if len2 > 0 then math.clamp(((x - a.x) * dx + (z - a.z) * dz) / len2, 0, 1) else 0
		local px, pz = a.x + dx * u, a.z + dz * u
		local d = (x - px) ^ 2 + (z - pz) ^ 2
		if d < best then
			best = d
			bestS = loop.dist[j] + (loop.dist[j + 1] - loop.dist[j]) * u
		end
	end
	return bestS
end

local function travel(yaw: number): (number, number)
	return -math.sin(yaw), -math.cos(yaw)
end

local function gatherWheels(model: any): { Spinner }
	local out: { Spinner } = {}
	local stations = SkyLift.stations()
	for _, d in model:GetDescendants() do
		if not d:IsA("BasePart") then
			continue
		end
		local name = d.Name
		local p = d.Position
		if name == "Bullwheel" or name == "BullwheelRim" or name == "Hub" then
			-- the rope goes round the nearer station's wheel: its direction where it leaves for the line
			local st = if (p.X - stations.base.wheel.x) ^ 2 + (p.Z - stations.base.wheel.z) ^ 2
					<= (p.X - stations.summit.wheel.x) ^ 2 + (p.Z - stations.summit.wheel.z) ^ 2
				then stations.base
				else stations.summit
			local x, _, z, yaw = SkyLift.at(st.boardS)
			local vx, vz = travel(yaw)
			local sign = turnSign(d, x - st.wheel.x, 0, z - st.wheel.z, vx, vz)
			table.insert(out, { part = d, base = d.CFrame, rate = sign * SkyLift.LINE_SPEED / SkyLift.STRAND })
		elseif name == "Sheave" then
			-- a sheave rides on the rope: the contact is straight below its centre
			local radius = math.max(0.1, d.Size.Y / 2)
			local _, _, _, yaw = SkyLift.at(nearestS(p.X, p.Z))
			local vx, vz = travel(yaw)
			local sign = turnSign(d, 0, -radius, 0, vx, vz)
			table.insert(out, { part = d, base = d.CFrame, rate = sign * SkyLift.LINE_SPEED / radius })
		end
	end
	return out
end

local function wheelModel(name: string): boolean
	return name == "f4_lift_base" or name == "f4_lift_summit" or string.match(name, "^f4_lift_tower_%d+$") ~= nil
end

local function scanWheels(s: State)
	local exp = workspace:FindFirstChild("Expansion")
	local f4 = exp and exp:FindFirstChild("F4")
	for m in s.wheels do
		if f4 == nil or m.Parent ~= f4 then
			s.wheels[m] = nil -- streamed out
		end
	end
	if f4 == nil then
		return
	end
	for _, m in f4:GetChildren() do
		if s.wheels[m] == nil and wheelModel(m.Name) then
			s.wheels[m] = gatherWheels(m)
		end
	end
end

local function scanRiders(s: State)
	table.clear(s.riders)
	local bodies = workspace:FindFirstChild("Bodies")
	if bodies == nil then
		return
	end
	for _, b in bodies:GetChildren() do
		if b:GetAttribute("Ride") ~= nil then
			table.insert(s.riders, b)
		end
	end
end

local function rootOf(body: any): any
	return body.PrimaryPart or body:FindFirstChild("HumanoidRootPart")
end

function SkyLiftView.frame(dt: number)
	local s = state
	if s == nil or not s.alive then
		return
	end
	-- the slow looks: the template, the wheels, the riders, the lamps
	s.scanAcc += dt
	if s.scanAcc >= SkyLiftView.SCAN_PERIOD then
		s.scanAcc = 0
		if #s.cabins == 0 then
			local tpl = template()
			if tpl then
				makeCabins(s, tpl)
				if s.night ~= nil then
					setNight(s, s.night :: boolean)
				end
			elseif not s.warned and s.waited >= SkyLiftView.WAIT_WARN then
				s.warned = true
				warn("SkyLiftView: no Workspace.Expansion.F4.CabinTemplate yet; the sky lift's cabins are not drawn")
			end
		end
		scanWheels(s)
	end
	if #s.cabins == 0 then
		s.waited += dt
	end
	s.ridersAcc += dt
	if s.ridersAcc >= SkyLiftView.RIDERS_PERIOD then
		s.ridersAcc = 0
		scanRiders(s)
	end
	s.lightsAcc += dt
	if s.lightsAcc >= SkyLiftView.LIGHTS_PERIOD then
		s.lightsAcc = 0
		local level = game:GetService("Lighting"):GetAttribute("StreetLamps")
		if type(level) == "number" then
			local night = TownLights.next(s.night == true, level)
			if night ~= s.night then
				setNight(s, night)
			end
		end
	end

	local t = SkyLiftView.advance(s.t, dt, now(s))
	s.t = t
	local parts, cframes = s.parts, s.cframes
	table.clear(parts)
	table.clear(cframes)
	local n = 0
	-- the cabins and their doors
	for i, cab in s.cabins do
		local x, y, z, yaw = SkyLift.cabin(i, t)
		local cf = CFrame.new(x, y, z) * CFrame.Angles(0, yaw, 0)
		local f = SkyLift.doorFrac(i, t)
		local fore = cf * CFrame.new(0, 0, cab.slide[1] * f)
		local aft = cf * CFrame.new(0, 0, cab.slide[2] * f)
		for _, e in cab.parts do
			n += 1
			parts[n] = e.part
			local frame = if e.leaf == 0 then cf elseif e.leaf == 1 then fore else aft
			cframes[n] = frame * e.rel
		end
	end
	-- the wheels near the camera
	local cam = workspace.CurrentCamera
	local camPos = cam and cam.CFrame.Position
	for _, list in s.wheels do
		for _, w in list do
			if camPos and (w.part.Position - camPos).Magnitude > SkyLiftView.SPIN_RANGE then
				continue
			end
			n += 1
			parts[n] = w.part
			cframes[n] = w.base * CFrame.Angles((w.rate * t) % (2 * math.pi), 0, 0)
		end
	end
	if n > 0 then
		workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	end
	-- the riders, on the same clock
	for _, body in s.riders do
		local c, k = SkyLiftView.parseRide(body:GetAttribute("Ride"))
		local root = c and k and body.Parent ~= nil and rootOf(body)
		if root and c and k then
			local x, y, z, yaw = SkyLiftView.rootAt(c, k, t)
			root.CFrame = CFrame.new(x, y, z) * CFrame.Angles(0, yaw, 0)
		end
	end
end

function SkyLiftView.start(opts: Opts?): () -> ()
	if state then
		state.alive = false
	end
	local s: State = {
		alive = true,
		opts = opts or {},
		t = nil,
		cabins = {},
		folder = nil,
		waited = 0,
		warned = false,
		scanAcc = SkyLiftView.SCAN_PERIOD,
		ridersAcc = SkyLiftView.RIDERS_PERIOD,
		lightsAcc = SkyLiftView.LIGHTS_PERIOD,
		riders = {},
		night = nil,
		wheels = {},
		parts = {},
		cframes = {},
	}
	state = s
	local bound = s.opts.bind ~= false
	if bound then
		game:GetService("RunService")
			:BindToRenderStep(SkyLiftView.BIND, Enum.RenderPriority.Camera.Value - 2, SkyLiftView.frame)
	end
	return function()
		s.alive = false
		if bound then
			game:GetService("RunService"):UnbindFromRenderStep(SkyLiftView.BIND)
		end
		if s.folder then
			s.folder:Destroy()
		end
		for _, list in s.wheels do
			for _, w in list do
				if w.part.Parent then
					w.part.CFrame = w.base
				end
			end
		end
		if state == s then
			state = nil
		end
	end
end

-- The smoothed clock of the last frame drawn (nil before the first).
function SkyLiftView.clock(): number?
	return if state then state.t else nil
end

function SkyLiftView.cabinModel(i: number): Model?
	local cab = state and state.cabins[i]
	return if cab then cab.model else nil
end

function SkyLiftView.seatModel(i: number, k: number): Model?
	local cab = state and state.cabins[i]
	return if cab then cab.seats[k] else nil
end

-- The eye of seat k of cabin i on the clock this screen last drew (EYE_ABOVE_SEAT over the seat, facing its way).
function SkyLiftView.eye(i: number, k: number): CFrame?
	local t = state and state.t
	if t == nil then
		return nil
	end
	local x, y, z, yaw = SkyLift.eye(i, k, t)
	return CFrame.new(x, y, z) * CFrame.Angles(0, yaw, 0)
end

-- The cabin and seat a body rides in (its Ride attribute), or nil.
function SkyLiftView.rideOf(body: Instance?): (number?, number?)
	if body == nil then
		return nil, nil
	end
	return SkyLiftView.parseRide(body:GetAttribute("Ride"))
end

return SkyLiftView
