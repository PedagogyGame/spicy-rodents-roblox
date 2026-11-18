--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Camera.CameraRig
-- Per-mode camera rigs from Camera/CameraPolicy (BUILD_PLAN §1.4 Camera/CameraRig, §4.4 #5; brief v2
-- §14). Modes:
--   humanThird / animalThird the orbit camera below (on a touch-only device: the default follow camera)
--   humanFirst               the default Roblox camera on the Humanoid in first person through
--                            Player.CameraMode = LockFirstPerson (the V toggle flips it)
--   lockFirst                LockFirstPerson with the toggle refused (arena, lounges)
--   chaseLock                scriptable: behind the body along its facing, looking forward
--   tunnelChase              scriptable: low behind a squirrel in the bowling alley's ball-return tunnel
--   vehicleFirst             scriptable at the vehicle's EyeSocket; mouse/right-stick look within
--                            +/-110 degrees of the nose; vehicleThird follows the vehicle root. With
--                            targets.free (the sky-lift gondola: a seat's EyeSocket) the look is free: no
--                            button, all the way round, no spring back (cars keep the right button by design)
--   drone                    the follow camera on the drone root
--   overview / outbreak      a parked scriptable shot
-- The orbit camera (owner 2026-11-10: "be sure that the mouse is controlling the camera view and that
-- there is an inversion toggle for that look"): on foot the mouse IS the look. The cursor is locked to
-- the centre and moving the mouse turns the view, with no button held; the wheel zooms; the right stick
-- of a gamepad does the same; I flips up/down (CameraRig.notify says which way it now is, and the choice
-- lasts the session). The camera sits behind the smoothed focus point, comes in front of anything solid
-- between it and the body (never past it), eases back out, and fades the body when it is pulled in close.
-- The cursor is free while a menu is open (wantCursor), the Roblox menu is open, a text box has focus, or
-- Left Alt is held; while it is free, holding the right mouse button still turns the view. A script that
-- takes camera.CFrame for a while (a minigame's shot) calls hold(true) and the orbit writes nothing.
-- Interface: apply(decision, targets) where targets = { body?, vehicle?, drone? }; follow(body);
--   orbit(body, human); overview(position, lookAt); subjectOf(body); stop();
--   focusStep(px, py, pz, tx, ty, tz, dt, lx?, ly?, lz?) -> x, y, z (pure); FOCUS;
--   LOOK; lookStep(yaw, elev, dx, dy, invert) -> yaw, elev (pure); orbitOffset(yaw, elev, dist) ->
--   x, y, z (pure); ORBIT; FOV; orbitFraming(sizeX, sizeY, sizeZ, human) -> lift, minDist, maxDist, dist
--   (pure); zoomStep(dist, wheel, min, max) -> dist (pure); occludes(name, parentName,
--   transparency, canCollide) -> boolean (pure); inverted() -> boolean; setInverted(on);
--   wantCursor(key, on); hold(on); cabinLook(yaw, pitch, dx, dy, invert) -> yaw, pitch (pure); pullIn(hitDistance) -> distance (pure); fadeAt(shown, hideAt) -> 0..1
--   (pure); notify: ((text) -> ())?
-- No side effects on require (services are looked up inside the functions).

local CameraRig = {}

local BIND = "SpicyCameraRig"
local bound = false
local onUnbind: (() -> ())? = nil

local function unbind()
	if bound then
		game:GetService("RunService"):UnbindFromRenderStep(BIND)
		bound = false
	end
	local f = onUnbind
	onUnbind = nil
	if f then
		f()
	end
	local UIS = game:GetService("UserInputService")
	UIS.MouseBehavior = Enum.MouseBehavior.Default
end

local function bind(fn: (dt: number) -> ())
	unbind()
	game:GetService("RunService"):BindToRenderStep(BIND, Enum.RenderPriority.Camera.Value - 1, fn)
	bound = true
end

function CameraRig.subjectOf(body: Model): Instance?
	local humanoid = body:FindFirstChildOfClass("Humanoid")
	if humanoid then
		return humanoid
	end
	return body:FindFirstChild("Head") or body.PrimaryPart
end

local function setFirstPerson(on: boolean)
	local player = game:GetService("Players").LocalPlayer
	if on then
		player.CameraMode = Enum.CameraMode.LockFirstPerson
	else
		player.CameraMode = Enum.CameraMode.Classic
		player.CameraMinZoomDistance = 0.5
	end
end

-- A smoothed, client-only focus part for bodies without a Humanoid (squirrels, the rodent, fox,
-- deer, vehicles, the drone). Following the rig's Head or raw root made the camera bounce with the
-- gait's head nod and body bob (owner feedback 2026-11-09): the focus tracks the root quickly in X/Z
-- and slowly in Y, so running is steady while climbing still follows.
local focus: BasePart? = nil
local function focusPart(): BasePart
	local f = focus
	if f and f.Parent then
		return f
	end
	local p = Instance.new("Part")
	p.Name = "SpicyCameraFocus"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Transparency = 1
	p.Size = Vector3.new(0.2, 0.2, 0.2)
	p.Parent = workspace.CurrentCamera -- local to this client, never replicated
	focus = p
	return p
end

CameraRig.FOCUS = {
	rateXZ = 25, -- 1/s, horizontal: tight
	rateY = 7, -- 1/s, vertical: smooths terrain steps and landings
	maxLagXZ = 3, -- studs the focus may trail the body horizontally
	maxLagY = 4, -- studs it may trail vertically (a long fall, a fast climb)
	snap = 20, -- studs: beyond this the body teleported and the focus cuts with it
}

-- One frame of the focus point (px, py, pz) following the body point (tx, ty, tz). The lag limits are
-- continuous: the focus is held at the limit, never thrown onto the target, so a long fall or a leap
-- is one smooth move (the old rule snapped to the target whenever the lag passed 3 studs, which made
-- a sawtooth of the camera on every drop). Pure numbers.
-- (lx, ly, lz) is the body point of the last frame: with it the ease is integrated for a body moving at a
-- steady speed through the frame, so the distance trailed does not change with the frame time.
function CameraRig.focusStep(
	px: number,
	py: number,
	pz: number,
	tx: number,
	ty: number,
	tz: number,
	dt: number,
	lx: number?,
	ly: number?,
	lz: number?
): (number, number, number)
	local F = CameraRig.FOCUS
	local dx, dy, dz = tx - px, ty - py, tz - pz
	if dx * dx + dy * dy + dz * dz > F.snap * F.snap then
		return tx, ty, tz
	end
	if dt > 0 then
		local function follow(x: number, t0: number, t1: number, rate: number): number
			local lead = (t1 - t0) / (rate * dt)
			return t1 - (lead + (t0 - x - lead) * math.exp(-rate * dt))
		end
		px = follow(px, lx or tx, tx, F.rateXZ)
		py = follow(py, ly or ty, ty, F.rateY)
		pz = follow(pz, lz or tz, tz, F.rateXZ)
	end
	local ox, oz = tx - px, tz - pz
	local lag = math.sqrt(ox * ox + oz * oz)
	if lag > F.maxLagXZ then
		local k = F.maxLagXZ / lag
		px, pz = tx - ox * k, tz - oz * k
	end
	py = math.clamp(py, ty - F.maxLagY, ty + F.maxLagY)
	return px, py, pz
end

function CameraRig.follow(body: Model)
	unbind()
	local camera = workspace.CurrentCamera
	local humanoid = body:FindFirstChildOfClass("Humanoid")
	if humanoid then
		camera.CameraType = Enum.CameraType.Custom
		camera.CameraSubject = humanoid
		return
	end
	local root = body.PrimaryPart
	if root == nil then
		local subject = CameraRig.subjectOf(body)
		if subject then
			camera.CameraType = Enum.CameraType.Custom
			camera.CameraSubject = subject :: any
		end
		return
	end
	local rootPart = root :: BasePart
	local f = focusPart()
	local _, size = body:GetBoundingBox()
	local lift = math.max(0.6, size.Y * 0.6) -- look slightly above the body, not at its feet
	local pos = rootPart.Position + Vector3.new(0, lift, 0)
	local last = pos
	f.CFrame = CFrame.new(pos)
	camera.CameraType = Enum.CameraType.Custom
	camera.CameraSubject = f
	bind(function(dt: number)
		if rootPart.Parent == nil then
			return
		end
		local target = rootPart.Position + Vector3.new(0, lift, 0)
		pos = Vector3.new(
			CameraRig.focusStep(pos.X, pos.Y, pos.Z, target.X, target.Y, target.Z, dt, last.X, last.Y, last.Z)
		)
		last = target
		f.CFrame = CFrame.new(pos)
	end)
end

CameraRig.LOOK = {
	sens = 0.0045, -- radians per pixel of mouse travel at Roblox's default mouse sensitivity
	stick = 2.8, -- radians per second at full right-stick deflection
	elevMin = -1.2, -- the camera below the body, looking up (under a branch)
	elevMax = 1.35, -- nearly overhead
	zoom = 0.88, -- distance multiplier per wheel notch toward the body
	easeOut = 7, -- 1/s: how fast the camera backs out again after something pushed it in
	pad = 0.35, -- studs kept between the camera and what it came in front of
}

local invertLook = false
CameraRig.notify = nil :: ((text: string) -> ())?
local cursorWanted: { [string]: boolean } = {}

function CameraRig.inverted(): boolean
	return invertLook
end

function CameraRig.setInverted(on: boolean)
	invertLook = on
end

-- A menu or panel that needs the cursor says so here (and takes it back with on = false).
function CameraRig.wantCursor(key: string, on: boolean)
	(cursorWanted :: { [string]: boolean? })[key] = if on then true else nil
end

-- Another script owns camera.CFrame for a while (a minigame's scripted shot): the orbit writes nothing
-- and gives the cursor back.
local held = false
function CameraRig.hold(on: boolean)
	held = on
end

-- How far out the camera may sit when something solid was hit `hitDistance` from the focus: short of it
-- by the pad, and never past it however near it is (a wall at the body's back).
function CameraRig.pullIn(hitDistance: number): number
	return math.max(0.1, hitDistance - CameraRig.LOOK.pad, hitDistance * 0.5)
end

-- How far the body is faded out (0 drawn, 1 hidden) with the camera `shown` studs from the focus: it
-- starts at `hideAt` and is gone at 65 % of it, so a pulled-in camera never fills the view with the
-- back of a head (the default camera's own fade does not run under a scriptable camera).
function CameraRig.fadeAt(shown: number, hideAt: number): number
	return math.clamp((hideAt - shown) / (hideAt * 0.35), 0, 1)
end

-- One look input applied: dx, dy in radians (mouse right and mouse DOWN positive, as the screen has
-- them). The view turns right for dx > 0. Up/down: by default pushing the mouse up looks up (the camera
-- drops behind the body); inverted, pushing up looks down. `elev` is the camera's elevation over the
-- focus (positive: above it, looking down).
function CameraRig.lookStep(yaw: number, elev: number, dx: number, dy: number, invert: boolean): (number, number)
	local L = CameraRig.LOOK
	local nextYaw = (yaw - dx) % (2 * math.pi)
	local nextElev = math.clamp(elev + (if invert then -dy else dy), L.elevMin, L.elevMax)
	return nextYaw, nextElev
end

-- The gondola's free look from a seat (vehicleFirst with targets.free): dx, dy in radians as lookStep has them; the
-- view turns right for dx > 0 all the way round, and pushing the mouse up looks up (down when inverted), between
-- CABIN_PITCH's limits.
CameraRig.CABIN_PITCH = { min = -1.2, max = 1.0 }
function CameraRig.cabinLook(yaw: number, pitch: number, dx: number, dy: number, invert: boolean): (number, number)
	local P = CameraRig.CABIN_PITCH
	local nextYaw = (yaw - dx) % (2 * math.pi)
	local nextPitch = math.clamp(pitch - (if invert then -dy else dy), P.min, P.max)
	return nextYaw, nextPitch
end

-- Where the camera sits relative to the focus for a view heading `yaw` (Roblox: look = (-sin, 0, -cos))
-- at elevation `elev` and distance `dist`.
function CameraRig.orbitOffset(yaw: number, elev: number, dist: number): (number, number, number)
	local c = math.cos(elev)
	return math.sin(yaw) * c * dist, math.sin(elev) * dist, math.cos(yaw) * c * dist
end

-- How the orbit frames a body it meets for the first time (pure, so the offline motion preview,
-- tools/review/motion_path.luau, stands where the game's camera stands). (sizeX, sizeY, sizeZ) is the
-- body's bounding box in studs. Returns `lift`, how far above the root the camera looks; the nearest and
-- the farthest the wheel zooms; and the distance it starts at. It starts ORBIT.elev radians above the
-- focus, behind the body, and the field of view stays the engine's own (FOV).
CameraRig.ORBIT = { elev = 0.3 }
CameraRig.FOV = 70 -- degrees, vertical: the engine's default; only the tunnel rig changes it (and puts it back)
function CameraRig.orbitFraming(
	sizeX: number,
	sizeY: number,
	sizeZ: number,
	human: boolean
): (number, number, number, number)
	local biggest = math.max(sizeX, sizeY, sizeZ)
	local lift = if human then math.max(1.5, sizeY * 0.3) else math.max(0.6, sizeY * 0.6)
	local minDist = if human then 4 else math.max(2, biggest * 1.5)
	local maxDist = if human then 40 else math.max(24, biggest * 10)
	local dist = math.clamp(if human then 12.5 else biggest * 4, math.max(minDist, 8), 16)
	return lift, minDist, maxDist, dist
end

function CameraRig.zoomStep(dist: number, wheel: number, min: number, max: number): number
	return math.clamp(dist * CameraRig.LOOK.zoom ^ wheel, min, max)
end

-- Does this part hide the body from the camera? Solid things do. The invisible cylinders that give tree
-- boughs their collision do not (a camera that jumped in at every twig would be unusable in a canopy),
-- nor does anything else invisible except a tree's trunk collider, which stands where the drawn trunk is.
function CameraRig.occludes(name: string, parentName: string, transparency: number, canCollide: boolean): boolean
	if not canCollide then
		return false
	end
	if string.match(name, "^R%d") ~= nil and string.sub(parentName, 1, 5) == "Tree_" then
		return false
	end
	return transparency < 0.9 or name == "Trunk"
end

-- The orbit state survives a re-apply for the same body (a zone change, the V toggle and back).
local orbitBody: Model? = nil
local orbitYaw, orbitElev, orbitDist = 0, CameraRig.ORBIT.elev, 12
local orbiting = false -- the orbit rig is the one bound right now

function CameraRig.orbit(body: Model, human: boolean)
	local resumed = orbiting and orbitBody == body -- the orbit itself re-applied (a zone change)
	unbind()
	local root = body.PrimaryPart
	if root == nil then
		CameraRig.follow(body)
		return
	end
	local rootPart = root :: BasePart
	local UIS = game:GetService("UserInputService")
	local GuiService = game:GetService("GuiService")
	local camera = workspace.CurrentCamera
	local L = CameraRig.LOOK
	local _, size = body:GetBoundingBox()
	local lift, minDist, maxDist, startDist = CameraRig.orbitFraming(size.X, size.Y, size.Z, human)
	if orbitBody ~= body then
		orbitBody = body
		local look = rootPart.CFrame.LookVector
		orbitYaw = math.atan2(-look.X, -look.Z) -- behind the body
		orbitElev = CameraRig.ORBIT.elev
		orbitDist = startDist
	elseif not resumed then
		-- back from first person, a vehicle, the tunnel or the chase lock: keep looking the way the
		-- camera looks now, not the way it looked before the other rig took over
		local look = camera.CFrame.LookVector
		if look.X * look.X + look.Z * look.Z > 1e-4 then
			orbitYaw = math.atan2(-look.X, -look.Z)
		end
	end
	local rays = RaycastParams.new()
	rays.FilterType = Enum.RaycastFilterType.Exclude
	rays.RespectCanCollide = true
	local ignore: { Instance } = { body, camera }
	local bodies = body.Parent
	if bodies and bodies ~= workspace then
		table.insert(ignore, bodies) -- other animals and people never push the camera in
	end
	rays.FilterDescendantsInstances = ignore
	local pos = rootPart.Position + Vector3.new(0, lift, 0)
	local last = pos
	local shown = orbitDist
	camera.CameraType = Enum.CameraType.Scriptable
	local wheel = UIS.InputChanged:Connect(function(input: InputObject, processed: boolean)
		if input.UserInputType == Enum.UserInputType.MouseWheel and not processed then
			orbitDist = CameraRig.zoomStep(orbitDist, input.Position.Z, minDist, maxDist)
		end
	end)
	local keys = UIS.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if input.KeyCode == Enum.KeyCode.I and not processed and UIS:GetFocusedTextBox() == nil then
			invertLook = not invertLook
			local say = CameraRig.notify
			if say then
				say(
					if invertLook
						then "Camera look: inverted (I switches back)"
						else "Camera look: normal (I inverts up/down)"
				)
			end
		end
	end)
	-- The body fades when the camera is pulled in close. The first call always writes, which also shows
	-- a body the default camera hid for first person (it stops updating that once the camera is
	-- scriptable, so a person stayed invisible after V and back).
	local hideAt = minDist * 0.5
	local faded = -1
	local function fadeBody(a: number)
		if a == faded then
			return
		end
		faded = a
		for _, d in body:GetDescendants() do
			if d:IsA("BasePart") or d:IsA("Decal") then
				(d :: any).LocalTransparencyModifier = a
			end
		end
	end
	bind(function(dt: number)
		if rootPart.Parent == nil then
			return
		end
		if held then
			UIS.MouseBehavior = Enum.MouseBehavior.Default
			return
		end
		local typing = GuiService.MenuIsOpen or UIS:GetFocusedTextBox() ~= nil
		local free = typing or UIS:IsKeyDown(Enum.KeyCode.LeftAlt) or next(cursorWanted) ~= nil
		local look = false
		if not free then
			UIS.MouseBehavior = Enum.MouseBehavior.LockCenter
			look = true
		elseif UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) and not typing then
			-- the cursor is out for buttons (a minigame bar, the menu, Left Alt): holding the right
			-- button still turns the view, as the default camera did
			UIS.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
			look = true
		else
			UIS.MouseBehavior = Enum.MouseBehavior.Default
		end
		if look then
			local d = UIS:GetMouseDelta()
			local k = L.sens -- GetMouseDelta already carries the player's sensitivity setting
			orbitYaw, orbitElev = CameraRig.lookStep(orbitYaw, orbitElev, d.X * k, d.Y * k, invertLook)
		end
		for _, input in UIS:GetGamepadState(Enum.UserInputType.Gamepad1) do
			if input.KeyCode == Enum.KeyCode.Thumbstick2 and input.Position.Magnitude > 0.15 then
				local k = L.stick * dt
				-- stick up is +Y; the mouse's up is -Y
				orbitYaw, orbitElev =
					CameraRig.lookStep(orbitYaw, orbitElev, input.Position.X * k, -input.Position.Y * k, invertLook)
			end
		end
		local target = rootPart.Position + Vector3.new(0, lift, 0)
		pos = Vector3.new(
			CameraRig.focusStep(pos.X, pos.Y, pos.Z, target.X, target.Y, target.Z, dt, last.X, last.Y, last.Z)
		)
		last = target
		-- come in front of whatever solid thing stands between the body and the camera
		local ox, oy, oz = CameraRig.orbitOffset(orbitYaw, orbitElev, 1)
		local dir = Vector3.new(ox, oy, oz)
		local clear = orbitDist
		local from = pos
		local travelled = 0
		for _ = 1, 6 do
			local hit = workspace:Raycast(from, dir * (orbitDist - travelled + L.pad), rays)
			if hit == nil then
				break
			end
			local part = hit.Instance
			local parent = part.Parent
			local gone = travelled + (hit.Position - from).Magnitude
			if
				part:IsA("Terrain")
				or CameraRig.occludes(part.Name, if parent then parent.Name else "", part.Transparency, part.CanCollide)
			then
				clear = CameraRig.pullIn(gone)
				break
			end
			travelled = gone + 0.05
			from = pos + dir * travelled
			if travelled >= orbitDist then
				break
			end
		end
		shown = if clear < shown
			then clear
			else math.min(clear, shown + (clear - shown) * (1 - math.exp(-dt * L.easeOut)))
		fadeBody(CameraRig.fadeAt(shown, hideAt))
		camera.CFrame = CFrame.lookAt(pos + dir * shown, pos)
		camera.Focus = CFrame.new(pos)
	end)
	orbiting = true
	onUnbind = function()
		orbiting = false
		wheel:Disconnect()
		keys:Disconnect()
		fadeBody(0)
	end
end

function CameraRig.overview(position: Vector3, lookAt: Vector3)
	unbind()
	setFirstPerson(false)
	local camera = workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = CFrame.lookAt(position, lookAt)
end

function CameraRig.stop()
	unbind()
end

local function sizeOf(model: Model): number
	local _, size = model:GetBoundingBox()
	return math.max(size.X, size.Y, size.Z)
end

export type Targets = { body: Model?, vehicle: Model?, drone: Model?, free: boolean? }

function CameraRig.apply(decision: { mode: string, firstPerson: boolean }, targets: Targets)
	local Players = game:GetService("Players")
	local UIS = game:GetService("UserInputService")
	local player = Players.LocalPlayer
	local camera = workspace.CurrentCamera
	local mode = decision.mode
	if mode == "humanThird" or mode == "humanFirst" or mode == "lockFirst" then
		local body = targets.body
		if body then
			-- a touch-only device keeps the default camera (its drag and pinch); so does first person
			local orbit = mode == "humanThird" and (UIS.MouseEnabled or UIS.GamepadEnabled)
			if orbit then
				setFirstPerson(false)
				CameraRig.orbit(body, true)
			else
				CameraRig.follow(body)
				player.CameraMaxZoomDistance = 40
				setFirstPerson(mode ~= "humanThird")
			end
		end
	elseif mode == "animalThird" then
		local body = targets.body
		if body then
			setFirstPerson(false)
			if UIS.MouseEnabled or UIS.GamepadEnabled then
				CameraRig.orbit(body, false)
			else
				CameraRig.follow(body)
				local s = sizeOf(body)
				player.CameraMinZoomDistance = math.max(2, s * 1.5)
				player.CameraMaxZoomDistance = math.max(24, s * 10)
			end
		end
	elseif mode == "chaseLock" then
		local body = targets.body
		local root = body and body.PrimaryPart
		if root then
			setFirstPerson(false)
			camera.CameraType = Enum.CameraType.Scriptable
			local dist = math.max(6, sizeOf(body :: Model) * 4)
			bind(function()
				local cf = root.CFrame
				local back = cf.Position - cf.LookVector * dist + Vector3.new(0, dist * 0.45, 0)
				camera.CFrame = CFrame.lookAt(back, cf.Position + cf.LookVector * dist)
			end)
		end
	elseif mode == "tunnelChase" then
		-- the bowling alley's ball-return tunnel: low behind the squirrel along its heading, pulled in front of
		-- any wall or ceiling between (raycasts against the duct), smoothed so the climb up the riser reads
		local body = targets.body
		local root = body and body.PrimaryPart
		if root then
			setFirstPerson(false)
			camera.CameraType = Enum.CameraType.Scriptable
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = { body :: Model }
			local current = camera.CFrame
			bind(function(dt: number)
				local cf = root.CFrame
				local look = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
				look = if look.Magnitude > 0.05 then look.Unit else Vector3.zAxis
				local head = cf.Position + Vector3.new(0, 0.35, 0)
				local want = head - look * 3.2 + Vector3.new(0, 0.55, 0)
				local hit = workspace:Raycast(head, want - head, params)
				if hit then
					want = hit.Position + (head - want).Unit * 0.25
				end
				local up = workspace:Raycast(want, Vector3.new(0, 0.4, 0), params)
				if up then
					want = Vector3.new(want.X, up.Position.Y - 0.2, want.Z)
				end
				local target = CFrame.lookAt(want, head + look * 3.5)
				current = current:Lerp(target, 1 - math.exp(-dt * 10))
				camera.CFrame = current
				camera.FieldOfView = 75
			end)
			onUnbind = function()
				camera.FieldOfView = CameraRig.FOV
			end
		end
	elseif mode == "vehicleFirst" then
		local vehicle = targets.vehicle
		local eye = vehicle and vehicle:FindFirstChild("EyeSocket", true)
		if eye and eye:IsA("Attachment") then
			setFirstPerson(false)
			camera.CameraType = Enum.CameraType.Scriptable
			local yaw, pitch = 0, 0
			local free = targets.free == true
			local GuiService = game:GetService("GuiService")
			-- the eye sits where the driver's head is: hide the driver's own body on this screen
			-- (the default camera does this only for its own first person)
			local hidden: { BasePart } = {}
			local driver = targets.body
			bind(function(dt: number)
				if driver and #hidden == 0 then
					for _, d in driver:GetDescendants() do
						if d:IsA("BasePart") then
							table.insert(hidden, d)
						end
					end
				end
				for _, part in hidden do
					part.LocalTransparencyModifier = 1
				end
				if free then
					-- the gondola: the mouse is the look (as on foot), the cursor out for a menu or Left Alt
					local out = held
						or GuiService.MenuIsOpen
						or UIS:GetFocusedTextBox() ~= nil
						or UIS:IsKeyDown(Enum.KeyCode.LeftAlt)
						or next(cursorWanted) ~= nil
					if out then
						UIS.MouseBehavior = Enum.MouseBehavior.Default
					else
						UIS.MouseBehavior = Enum.MouseBehavior.LockCenter
						local d = UIS:GetMouseDelta()
						local k = CameraRig.LOOK.sens
						yaw, pitch = CameraRig.cabinLook(yaw, pitch, d.X * k, d.Y * k, invertLook)
					end
					for _, input in UIS:GetGamepadState(Enum.UserInputType.Gamepad1) do
						if input.KeyCode == Enum.KeyCode.Thumbstick2 and input.Position.Magnitude > 0.15 then
							local k = CameraRig.LOOK.stick * dt
							yaw, pitch =
								CameraRig.cabinLook(yaw, pitch, input.Position.X * k, -input.Position.Y * k, invertLook)
						end
					end
				elseif UIS:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then
					UIS.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
					local d = UIS:GetMouseDelta()
					yaw = math.clamp(yaw - d.X * 0.004, -1.9, 1.9)
					pitch = math.clamp(pitch - d.Y * 0.004, -0.9, 0.7)
				else
					UIS.MouseBehavior = Enum.MouseBehavior.Default
					yaw *= 0.92
					pitch *= 0.92
				end
				camera.CFrame = eye.WorldCFrame * CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)
			end)
			onUnbind = function()
				for _, part in hidden do
					part.LocalTransparencyModifier = 0
				end
			end
		elseif vehicle then
			CameraRig.follow(vehicle)
		end
	elseif mode == "vehicleThird" then
		local vehicle = targets.vehicle
		if vehicle then
			setFirstPerson(false)
			CameraRig.follow(vehicle)
			player.CameraMinZoomDistance = 8
			player.CameraMaxZoomDistance = 60
		end
	elseif mode == "drone" then
		local drone = targets.drone
		if drone then
			setFirstPerson(false)
			CameraRig.follow(drone)
			player.CameraMinZoomDistance = 6
			player.CameraMaxZoomDistance = 120
		end
	else
		unbind()
		setFirstPerson(false)
		camera.CameraType = Enum.CameraType.Scriptable
	end
end

return CameraRig
