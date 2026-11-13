--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Rides.Telescope
-- The Lookout's free telescope on the terrace (BATCH2 item 35: "a free telescope (E: zooms the camera toward the
-- town; this is the 'second vantage')"; brief v2 line 250 "second vantage over the town"; the sky-lift plan's
-- lane 5, the simple zoom of question Q10). Nothing is sent: the telescope is this screen's camera only.
--   * In: the telescope's ProximityPrompt (the server's, lane 4: attribute Telescope = true on the prompt, or the
--     prompt anywhere inside the bake's Model "Telescope"; give it Door = true so E belongs to it) is triggered by
--     this player, or enter(scope) is called. The prompt is switched off on this screen while looking.
--   * The view: CameraRig.hold(true), the camera Scriptable at the front lens (between the Lens and Eyepiece
--     parts the bake gives it, or in front of its Head), looking where the telescope points, field of view FOV.
--     The mouse (no button held; the cursor is locked to the centre), a finger's drag or the right stick pans it,
--     YAW_LIMIT either side of where it points and between PITCH_MIN and PITCH_MAX; panning is slower the
--     narrower the view; the I key's inversion (CameraRig.inverted) applies. The wheel or the shoulder buttons
--     zoom between MIN_FOV and MAX_FOV.
--   * Out: E, Q or the gamepad's B; walking more than LEAVE_DIST from it; the body gone or the telescope streamed
--     out; leave(). The camera type, field of view and the cursor are given back and CameraRig.hold(false).
--   * Words: hud(TITLE, HINT) on the way in, hud(nil, nil) on the way out (the joiner wires it to Hud.set).
-- The render step runs at RenderPriority.Camera + 1, after the default camera and CameraRig.
-- Started once by the client's Main (the joiner, lane 6). No service access at require time.
-- Interface: start(opts?) -> stop; enter(scope) -> boolean; leave(); active() -> boolean; scopeOf(prompt) ->
--   Model? (pure on the tree); look(yaw, pitch, dx, dy, fov, invert) -> yaw, pitch (pure); zoom(fov, steps) -> fov
--   (pure); viewOf(scope) -> origin: Vector3, bearing, pitch; FOV, MIN_FOV, MAX_FOV, YAW_LIMIT, PITCH_MIN,
--   PITCH_MAX, SENS, STICK, LEAVE_DIST, TITLE, HINT, BIND
--   opts = { hud: ((title: string?, hint: string?) -> ())?, body: (() -> Model?)? (default: the local player's
--   Character), onChange: ((active: boolean) -> ())? }
-- Lane 8 (not built): the zoom that streams the looked-at street in (Player.ReplicationFocus on the server).

local CameraRig = require("../Camera/CameraRig")

local Telescope = {}

Telescope.FOV = 15
Telescope.MIN_FOV = 6
Telescope.MAX_FOV = 30
Telescope.ZOOM_STEP = 1.25 -- one wheel notch divides or multiplies the field of view by this
Telescope.YAW_LIMIT = math.rad(75)
Telescope.PITCH_MIN = math.rad(-35)
Telescope.PITCH_MAX = math.rad(15)
Telescope.SENS = 0.004 -- radians per pixel of mouse at a 70-degree view (scaled by fov / 70)
Telescope.STICK = 1.6 -- radians per second at full right stick at a 70-degree view (scaled by fov / 70)
Telescope.LEAVE_DIST = 8
Telescope.TITLE = "The telescope"
Telescope.HINT = "Move the mouse to look. Wheel: zoom. E or Q: step back."
Telescope.BIND = "SpicyTelescope"

export type Opts = {
	hud: ((title: string?, hint: string?) -> ())?,
	body: (() -> Model?)?,
	onChange: ((active: boolean) -> ())?,
}

type View = {
	scope: any,
	prompt: any?,
	promptWas: boolean,
	origin: Vector3,
	bearing: number,
	yaw: number, -- relative to the bearing
	pitch: number, -- absolute
	fov: number,
	frames: number, -- render steps since entering (the key that opened it is not the one that closes it)
	camType: any,
	camFov: number,
	dx: number,
	dy: number,
	stick: Vector3,
}

local opts: Opts = {}
local view: View? = nil
local alive = false
local conns: { any } = {}

-- ===== pure =====

-- Pan by a mouse or drag delta (pixels), slower the narrower the view; yaw relative to where the telescope
-- points, pitch absolute.
function Telescope.look(
	yaw: number,
	pitch: number,
	dx: number,
	dy: number,
	fov: number,
	invert: boolean
): (number, number)
	local k = Telescope.SENS * fov / 70
	local sy = if invert then -1 else 1
	return math.clamp(yaw - dx * k, -Telescope.YAW_LIMIT, Telescope.YAW_LIMIT),
		math.clamp(pitch - sy * dy * k, Telescope.PITCH_MIN, Telescope.PITCH_MAX)
end

-- Zoom by wheel notches (positive: in, a narrower view).
function Telescope.zoom(fov: number, steps: number): number
	return math.clamp(fov / Telescope.ZOOM_STEP ^ steps, Telescope.MIN_FOV, Telescope.MAX_FOV)
end

-- The telescope a prompt belongs to: the prompt (or a part it is in) carries Telescope = true, or it sits inside
-- a Model named "Telescope". nil if neither.
function Telescope.scopeOf(prompt: any): any
	local node = prompt
	local tagged: any = nil
	while node ~= nil do
		if node:GetAttribute("Telescope") == true and tagged == nil then
			tagged = node
		end
		if node:IsA("Model") and node.Name == "Telescope" then
			return node
		end
		node = node.Parent
	end
	if tagged ~= nil then
		-- tagged but not in a Telescope model: the nearest Model or part round it
		local up = if tagged:IsA("ProximityPrompt") then tagged.Parent else tagged
		return up
	end
	return nil
end

local function centre(parts: { any }): Vector3?
	if #parts == 0 then
		return nil
	end
	local sum = Vector3.new(0, 0, 0)
	for _, p in parts do
		sum += p.Position
	end
	return sum / #parts
end

-- Where the camera goes and where it looks first: in front of the lenses, along eyepiece -> lens (the bake's
-- Lens and Eyepiece parts), else in front of the Head along its look, else the scope's pivot looking along it.
function Telescope.viewOf(scope: any): (Vector3, number, number)
	local lenses, pieces = {}, {}
	local head: any = nil
	local all = scope:GetDescendants()
	if scope:IsA("BasePart") then
		table.insert(all, scope)
	end
	for _, d in all do
		if d:IsA("BasePart") then
			if d.Name == "Lens" then
				table.insert(lenses, d)
			elseif d.Name == "Eyepiece" then
				table.insert(pieces, d)
			elseif d.Name == "Head" then
				head = d
			end
		end
	end
	local origin: Vector3
	local dir: Vector3
	local l, e = centre(lenses), centre(pieces)
	if l and e and (l - e).Magnitude > 0.05 then
		dir = (l - e).Unit
		origin = l + dir * 0.4
	elseif head then
		dir = head.CFrame.LookVector
		origin = head.Position + dir * (head.Size.Z / 2 + 0.3)
	else
		local cf = if scope:IsA("BasePart") then scope.CFrame else scope:GetPivot()
		dir = cf.LookVector
		origin = cf.Position + dir * 0.5
	end
	return origin, math.atan2(-dir.X, -dir.Z), math.asin(math.clamp(dir.Y, -1, 1))
end

-- ===== the view =====

local function bodyRoot(): any
	local get = opts.body
	local body: any = if get then get() else game:GetService("Players").LocalPlayer.Character
	if body == nil or body.Parent == nil then
		return nil
	end
	return body.PrimaryPart or body:FindFirstChild("HumanoidRootPart")
end

local function frame(dt: number)
	local v = view
	if v == nil then
		return
	end
	v.frames += 1
	-- out when the body walks off or the telescope goes
	local root = bodyRoot()
	if v.scope.Parent == nil or root == nil then
		Telescope.leave()
		return
	end
	local rp = root.Position
	if Vector3.new(rp.X - v.origin.X, 0, rp.Z - v.origin.Z).Magnitude > Telescope.LEAVE_DIST then
		Telescope.leave()
		return
	end
	local invert = CameraRig.inverted()
	v.yaw, v.pitch = Telescope.look(v.yaw, v.pitch, v.dx, v.dy, v.fov, invert)
	v.dx, v.dy = 0, 0
	local st = v.stick
	if st.Magnitude > 0.15 then
		-- the stick as a pixel delta (look scales both by fov / 70): right turns right, up looks up
		local k = Telescope.STICK * dt / Telescope.SENS
		v.yaw, v.pitch = Telescope.look(v.yaw, v.pitch, st.X * k, -st.Y * k, v.fov, invert)
	end
	local UIS = game:GetService("UserInputService")
	UIS.MouseBehavior = Enum.MouseBehavior.LockCenter
	local camera = workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = v.fov
	camera.CFrame = CFrame.new(v.origin) * CFrame.Angles(0, v.bearing + v.yaw, 0) * CFrame.Angles(v.pitch, 0, 0)
end

function Telescope.active(): boolean
	return view ~= nil
end

function Telescope.enter(scope: any, prompt: any?): boolean
	if view ~= nil or not alive or scope == nil then
		return false
	end
	local origin, bearing, pitch = Telescope.viewOf(scope)
	local camera = workspace.CurrentCamera
	local v: View = {
		scope = scope,
		prompt = prompt,
		promptWas = if prompt then prompt.Enabled ~= false else true,
		origin = origin,
		bearing = bearing,
		yaw = 0,
		pitch = math.clamp(pitch, Telescope.PITCH_MIN, Telescope.PITCH_MAX),
		fov = Telescope.FOV,
		frames = 0,
		camType = camera.CameraType,
		camFov = camera.FieldOfView,
		dx = 0,
		dy = 0,
		stick = Vector3.new(0, 0, 0),
	}
	view = v
	if prompt then
		prompt.Enabled = false
	end
	CameraRig.hold(true)
	game:GetService("RunService"):BindToRenderStep(Telescope.BIND, Enum.RenderPriority.Camera.Value + 1, frame)
	local hud = opts.hud
	if hud then
		hud(Telescope.TITLE, Telescope.HINT)
	end
	local cb = opts.onChange
	if cb then
		cb(true)
	end
	return true
end

function Telescope.leave()
	local v = view
	if v == nil then
		return
	end
	view = nil
	game:GetService("RunService"):UnbindFromRenderStep(Telescope.BIND)
	local camera = workspace.CurrentCamera
	camera.CameraType = v.camType
	camera.FieldOfView = v.camFov
	game:GetService("UserInputService").MouseBehavior = Enum.MouseBehavior.Default
	CameraRig.hold(false)
	if v.prompt then
		v.prompt.Enabled = v.promptWas
	end
	local hud = opts.hud
	if hud then
		hud(nil, nil)
	end
	local cb = opts.onChange
	if cb then
		cb(false)
	end
end

local LEAVE_KEYS = { "E", "Q", "ButtonB" }

function Telescope.start(o: Opts?): () -> ()
	if alive then
		Telescope.leave()
		for _, c in conns do
			c:Disconnect()
		end
		table.clear(conns)
	end
	opts = o or {}
	alive = true
	local UIS = game:GetService("UserInputService")
	local PPS = game:GetService("ProximityPromptService")
	table.insert(
		conns,
		PPS.PromptTriggered:Connect(function(prompt: any, player: any)
			local me = game:GetService("Players").LocalPlayer
			if player ~= nil and player ~= me then
				return
			end
			local scope = Telescope.scopeOf(prompt)
			if scope then
				Telescope.enter(scope, prompt)
			end
		end)
	)
	table.insert(
		conns,
		UIS.InputBegan:Connect(function(io: any, processed: boolean)
			local v = view
			if v == nil or processed or v.frames < 1 then
				return
			end
			if table.find(LEAVE_KEYS, io.KeyCode.Name) then
				Telescope.leave()
			elseif io.KeyCode.Name == "ButtonR1" then
				v.fov = Telescope.zoom(v.fov, 1)
			elseif io.KeyCode.Name == "ButtonL1" then
				v.fov = Telescope.zoom(v.fov, -1)
			end
		end)
	)
	table.insert(
		conns,
		UIS.InputChanged:Connect(function(io: any, _processed: boolean)
			local v = view
			if v == nil then
				return
			end
			local kind = io.UserInputType
			if kind == Enum.UserInputType.MouseMovement or kind == Enum.UserInputType.Touch then
				v.dx += io.Delta.X
				v.dy += io.Delta.Y
			elseif kind == Enum.UserInputType.MouseWheel then
				v.fov = Telescope.zoom(v.fov, io.Position.Z)
			elseif kind == Enum.UserInputType.Gamepad1 and io.KeyCode.Name == "Thumbstick2" then
				v.stick = io.Position
			end
		end)
	)
	return function()
		Telescope.leave()
		alive = false
		for _, c in conns do
			c:Disconnect()
		end
		table.clear(conns)
	end
end

return Telescope
