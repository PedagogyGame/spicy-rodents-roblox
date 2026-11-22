--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Camera.CameraRig
-- Per-mode camera rigs from Camera/CameraPolicy (BUILD_PLAN §1.4 Camera/CameraRig, §4.4 #5; brief v2
-- §14). Modes:
--   humanThird / animalThird the orbit camera below (on a touch-only device: the default follow camera)
--   humanFirst               the default Roblox camera on the Humanoid in first person through
--                            Player.CameraMode = LockFirstPerson (the V toggle flips it)
--   lockFirst                LockFirstPerson with the toggle refused (arena, lounges)
--   chaseLock                scriptable: behind the body along its facing, looking forward
--   tunnelChase              scriptable: low behind a squirrel in an enclosed run (the ball return, the drains);
--                            inside a hollow tree the hollow look (HOLLOW below: the mouse turns the view about the
--                            head, the eye kept in the cavity, the shell faded where it would block, a peek out of a
--                            hole up the trunk; its rays meet only Workspace.HollowTrees, never the tree's invisible
--                            trunk colliders)
--   vehicleFirst             scriptable at the vehicle's EyeSocket; mouse/right-stick look within
--                            +/-110 degrees of the nose; vehicleThird follows the vehicle root. With
--                            targets.free (the sky-lift gondola: a seat's EyeSocket) the look is free: no
--                            button, all the way round, no spring back (cars keep the right button by design).
--                            A leaning vehicle (the bike, the moped, the electric scooter; owner D32: "a whole flash
--                            of a glitch across the whole screen" when steering) does not throw the camera with it:
--                            the eye is taken in the vehicle's upright frame (its heading and place) and leans only
--                            RIDE.roll of the vehicle's lean, eased (rollStep, rideEye), so a tap of A or D neither
--                            whips the horizon nor swings the eye of a standing rider across the street. The parts
--                            hidden round the eye (the driver's body, CameraRig.seeOut) are chosen once on entering
--                            and never toggled after. vehicleThird fades the driver's body as the engine camera comes
--                            close to it (riderHide: a wall behind pulls the camera in), so it is never inside it.
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
--   (pure); tunnelPoint(hx, hy, hz, lx, lz, cast, keep?) -> x, y, z (pure); HOLLOW; hollowLook, hollowRecentre,
--   hollowView, peekView, viewDir (pure: the hollow look); steerYaw() -> number? (the yaw the keys steer by while the
--   hollow look is on); notify: ((text) -> ())?;
--   seeOut(eye, cframe, size, glass) -> number? (pure: a vehicle part's LocalTransparencyModifier from the eye);
--   COCKPIT; RIDE; rollOf(cframe) -> radians (pure); upright(cframe) -> CFrame (pure); rollStep(shown, actual, dt) ->
--   radians (pure); rideEye(root, eyeRel, shown) -> CFrame (pure); riderHide(radius) -> hideAt (pure); RIDER_PAD;
--   RIDER_REACH; followLift(height) -> studs (pure)
-- No side effects on require (services are looked up inside the functions).

local Import = require("../Import")
local HollowLayout = Import.shared("World/HollowLayout") :: typeof(require("../../shared/World/HollowLayout"))
-- (its Layout and Hollow types: the module is imported through a cast, so its exported types are not in scope)
type HollowLayout = typeof(HollowLayout.new(nil :: any))
type Hollow = typeof(HollowLayout.new(nil :: any).hollows[1])

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

-- How far over a followed body's root its focus is, for a body `height` studs tall. Pure
function CameraRig.followLift(height: number): number
	return math.max(0.6, height * 0.6)
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
	local lift = CameraRig.followLift(size.Y) -- look slightly above the body, not at its feet
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

-- The tunnel camera's point (pure): for a head at (hx, hy, hz) heading (lx, lz) (level, unit), 3.2 studs behind and
-- 0.55 over, pulled 0.25 in front of the first thing `cast` meets between, under a ceiling; then `keep` (inside a
-- hollow tree: HollowLayout's keepCamera) holds it where it may be. cast(ox, oy, oz, dx, dy, dz) -> the hit point
-- (x, y, z) or nil.
function CameraRig.tunnelPoint(
	hx: number,
	hy: number,
	hz: number,
	lx: number,
	lz: number,
	cast: (number, number, number, number, number, number) -> (number?, number?, number?),
	keep: ((number, number, number, number, number, number) -> (number, number, number))?
): (number, number, number)
	local wx, wy, wz = hx - lx * 3.2, hy + 0.55, hz - lz * 3.2
	local px, py, pz = cast(hx, hy, hz, wx - hx, wy - hy, wz - hz)
	if px and py and pz then
		local bx, by, bz = hx - wx, hy - wy, hz - wz
		local bl = math.sqrt(bx * bx + by * by + bz * bz)
		wx, wy, wz = px + bx / bl * 0.25, py + by / bl * 0.25, pz + bz / bl * 0.25
	end
	local _, uy = cast(wx, wy, wz, 0, 0.4, 0)
	if uy then
		wy = uy - 0.2
	end
	if keep then
		wx, wy, wz = keep(wx, wy, wz, hx, hy, hz)
	end
	return wx, wy, wz
end

-- the yaw the keys steer by while the hollow look is on (HTML convention, as BodyDriver.cameraYawHtml): the body's
-- heading, so turning the view to look round never turns the squirrel; nil otherwise
local steer: number? = nil
function CameraRig.steerYaw(): number?
	return steer
end

-- THE LOOK INSIDE A HOLLOW TREE (owner D32: "allow the squirrel to actually look around"; D33: "the view to be more
-- verticle within the tree trunk"). Inside a tall hollow the view rests pitched up it (HOLLOW.rest): the eye close
-- behind and below the squirrel's head (HOLLOW.dist along the view, drawn HOLLOW.inward towards the hollow's middle
-- line) looking up the trunk past it, so the climb above and the daylight at the holes are in the picture. The mouse
-- (and the right stick) turns the view about the head, all the way round and from looking down the hollow to straight
-- up it, the eye looking HOLLOW.over above the head, so the squirrel sits low in the picture under the hollow; held inside the cavity (HollowLayout.keepCamera); where the cavity is too narrow for that (a shaft), the eye
-- goes to the head itself and looks out of the squirrel's eyes (first person: the body is hidden on this screen). The
-- growths of the inside between the eye and the head, or round the eye, are faded on this screen (shelves, roots,
-- knots, a hole's lining: never the wall, the floor or the roof, so the view never opens onto the town through
-- them), and a hollow's dark ovals on its bark are hidden while the camera is in it (from within they would hang over
-- the holes). A view left alone while the body moves eases back to the rest (HOLLOW.idle s, at HOLLOW.recentre per
-- s), so a climb still reads. At a hole up the trunk (HollowLayout.peekAt) the eye goes to the hole and looks out of
-- it (a peek), the look still turning about the hole's way out within HOLLOW.peekYaw / peekPitch (its pitch counted
-- from the rest). Going in, the eye comes in through the ground hole (HOLLOW.entry s) rather than through the bark;
-- going out, the orbit takes over from where the eye is.
--   hollowLook(yaw, pitch, dx, dy, invert) -> yaw, pitch: one look input (radians, as lookStep has them)
--   hollowRecentre(yaw, pitch, idle, moving, dt, rest?) -> yaw, pitch (back towards 0 and the rest, HOLLOW.rest)
--   hollowAt(layout, x, y, z) -> Hollow?: the hollow whose cavity holds the head (HollowLayout's contains gives its
--   space, "hollow.H1", which hollowOfSpace turns into the Hollow; hollow() takes the id, "H1", and finds nothing)
--   hollowRest(hollow?) -> pitch: the rest in that hollow (up a tall one; nearly level in a one-chamber tree)
--   hollowView(hx, hy, hz, lx, lz, yaw, pitch, keep?, mx?, mz?) -> (eye x, y, z, look x, y, z, firstPerson): (mx, mz)
--   the hollow's middle line at the head's height
--   peekView(mouth, yaw, pitch) -> (eye x, y, z, look x, y, z)
--   viewDir(lx, lz, yaw, pitch) -> x, y, z: a level heading (x = sin, z = cos of a bearing) turned `yaw` on round the
--   bearing (to the left) and pitched up `pitch`
--   fades(name) -> boolean: whether a shell piece of that name may be faded out of the view
CameraRig.HOLLOW = {
	dist = 2.2, -- studs behind the head along the view
	over = 0.35, -- radians the eye looks over the head (the squirrel sits low in the picture)
	lookMax = 1.5, -- radians: the steepest the eye looks up
	lift = 0.25, -- studs over the head
	inward = 0.6, -- studs the eye is drawn towards the hollow's middle line (off the shelves along the wall)
	rest = 0.6, -- radians: the view's pitch at rest, up a tall hollow (34 degrees; the eye looks `over` more)
	restLow = 0.1, -- and in a hollow no taller than a chamber (a one-chamber tree, the log)
	tall = 4, -- studs: a hollow whose cavities reach this high over its floor is tall
	minHead = 0.7, -- an eye held nearer the head than this goes into the head (first person)
	pitchMin = -1.3, -- looking down the hollow
	pitchMax = 1.45, -- looking up it
	idle = 1.0, -- s without a look input before a moving body's view eases back to the rest
	recentre = 2.5, -- 1/s
	peekYaw = 1.2, -- radians either side of a hole's way out the peek may turn
	peekPitch = { -1.0, 0.8 },
	peekIn = 0.12, -- studs inside the bark's face the peeking eye sits
	peekEase = 6, -- 1/s into and out of a peek
	ease = 14, -- 1/s the eye follows its point
	entry = 0.3, -- s for the eye to come in through the ground hole
	fade = 0.8, -- a faded piece's LocalTransparencyModifier
	fadeNear = 0.7, -- studs round the eye a piece is faded within
	solid = { "^liner", "^floor", "^roof", "^log" }, -- (name patterns) the wall: never faded
}

function CameraRig.fades(name: string): boolean
	for _, pat in CameraRig.HOLLOW.solid do
		if string.find(name, pat) then
			return false
		end
	end
	return string.find(name, "^knothole") == nil and string.find(name, "^threshold") == nil
end

function CameraRig.viewDir(lx: number, lz: number, yaw: number, pitch: number): (number, number, number)
	local c, s = math.cos(-yaw), math.sin(-yaw)
	local x, z = lx * c - lz * s, lx * s + lz * c
	local cp = math.cos(pitch)
	return x * cp, math.sin(pitch), z * cp
end

function CameraRig.hollowLook(yaw: number, pitch: number, dx: number, dy: number, invert: boolean): (number, number)
	local H = CameraRig.HOLLOW
	-- (mouse right turns the view right: the bearing, clockwise from +z seen from above, goes down, +x being on the
	-- left of a view along +z)
	local y = (yaw - dx + math.pi) % (2 * math.pi) - math.pi
	return y, math.clamp(pitch - (if invert then -dy else dy), H.pitchMin, H.pitchMax)
end

function CameraRig.hollowRecentre(
	yaw: number,
	pitch: number,
	idle: number,
	moving: boolean,
	dt: number,
	rest: number?
): (number, number)
	local H = CameraRig.HOLLOW
	if idle < H.idle or not moving then
		return yaw, pitch
	end
	local k = math.exp(-H.recentre * dt)
	local r = rest or H.rest
	return yaw * k, r + (pitch - r) * k
end

-- the view's pitch at rest in a hollow: up a tall one (HOLLOW.rest), nearly level in a chamber (HOLLOW.restLow)
function CameraRig.hollowRest(h: { cavities: { any } }?): number
	local H = CameraRig.HOLLOW
	if h == nil then
		return H.rest
	end
	local lo, hi = math.huge, -math.huge
	for _, c in h.cavities do
		if c.a then
			return H.restLow
		end
		lo, hi = math.min(lo, c.bottom), math.max(hi, c.top)
	end
	return if hi - lo >= H.tall then H.rest else H.restLow
end

-- the hollow the head is in, else nil: the one lookup the hollow look turns a point into a Hollow by (its rest, its
-- middle line, its ovals, its ground hole)
function CameraRig.hollowAt(layout: HollowLayout, x: number, y: number, z: number): Hollow?
	return layout.hollowOfSpace(layout.contains(x, y, z))
end

function CameraRig.hollowView(
	hx: number,
	hy: number,
	hz: number,
	lx: number,
	lz: number,
	yaw: number,
	pitch: number,
	keep: ((number, number, number, number, number, number) -> (number, number, number))?,
	mx: number?,
	mz: number?
): (number, number, number, number, number, number, boolean)
	local H = CameraRig.HOLLOW
	local vx, vy, vz = CameraRig.viewDir(lx, lz, yaw, pitch)
	local ex, ey, ez = hx - vx * H.dist, hy + H.lift - vy * H.dist, hz - vz * H.dist
	if mx and mz then
		-- (towards the middle line, no further than it)
		local dx, dz = mx - ex, mz - ez
		local d = math.sqrt(dx * dx + dz * dz)
		if d > 1e-6 then
			local k = math.min(H.inward, d) / d
			ex, ez = ex + dx * k, ez + dz * k
		end
	end
	if keep then
		ex, ey, ez = keep(ex, ey, ez, hx, hy, hz)
	end
	if (ex - hx) ^ 2 + (ey - hy) ^ 2 + (ez - hz) ^ 2 < H.minHead ^ 2 then
		-- too narrow to stand behind: out of the squirrel's own eyes
		return hx + vx * 0.2, hy + vy * 0.2, hz + vz * 0.2, vx, vy, vz, true
	end
	-- (looking a little over the view's line from where the eye is: the squirrel low in the picture, the hollow above
	-- it in the middle, not the squirrel's back)
	local ox, oy, oz = CameraRig.viewDir(lx, lz, yaw, math.min(pitch + H.over, H.lookMax))
	return ex, ey, ez, ox, oy, oz, false
end

function CameraRig.peekView(
	mouth: { x: number, y: number, z: number, out: { number }, depth: number? },
	yaw: number,
	pitch: number
): (number, number, number, number, number, number)
	local H = CameraRig.HOLLOW
	local ol = math.max(1e-6, math.sqrt(mouth.out[1] ^ 2 + mouth.out[3] ^ 2))
	local ox, oz = mouth.out[1] / ol, mouth.out[3] / ol
	local d = math.max(0, (mouth.depth or 0) - H.peekIn)
	local vx, vy, vz = CameraRig.viewDir(
		ox,
		oz,
		math.clamp(yaw, -H.peekYaw, H.peekYaw),
		math.clamp(pitch, H.peekPitch[1], H.peekPitch[2])
	)
	return mouth.x + ox * d, mouth.y + 0.9, mouth.z + oz * d, vx, vy, vz
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

-- THE DRIVER SEES OUT (D29: "a blank grey screen when i was in the pickup truck"). A closed vehicle's drawing is
-- solid blocks: the eye at a seated driver's head is inside its Cabin (the SUV's Hull) and its SideGlass, and the
-- windscreen in front of it is Glass at Transparency 0, which the engine draws opaque: the view was the back of the
-- windscreen. In first person every part of the vehicle the eye is inside (within `near` studs of: the camera's near
-- plane) is hidden on this screen, and its glass is made see-through (`glass`); the rest (the roof, the bonnet, the
-- dash) is left as it is. Any vehicle: the drawn kinds, a greybox, a richer model under Assets.Vehicles.
CameraRig.COCKPIT = { near = 0.25, glass = 0.75 }
function CameraRig.seeOut(eye: Vector3, cframe: CFrame, size: Vector3, glass: boolean): number?
	local p = cframe:PointToObjectSpace(eye)
	local n = CameraRig.COCKPIT.near
	if math.abs(p.X) <= size.X / 2 + n and math.abs(p.Y) <= size.Y / 2 + n and math.abs(p.Z) <= size.Z / 2 + n then
		return 1
	end
	return if glass then CameraRig.COCKPIT.glass else nil
end

-- A leaning vehicle's first-person eye (owner D32). The camera leans RIDE.roll of the vehicle's lean, eased at RIDE.rate
-- per second (a one-frame wobble of the physics is smoothed out with it), and the eye's place is taken in the vehicle's
-- upright frame turned by that much lean, not by all of it: a standing rider's eyes are 3.5 studs over the box's centre,
-- and the full lean (up to 0.5 rad) swung them 1.7 studs across in half a second at every steering tap.
CameraRig.RIDE = { roll = 0.3, rate = 6 }

-- The roll of a frame about its own forward axis (positive: its right side up), with its heading taken out. Pure
function CameraRig.rollOf(cf: CFrame): number
	local look, right = cf.LookVector, cf.RightVector
	local fl = math.sqrt(look.X * look.X + look.Z * look.Z)
	if fl < 1e-6 then
		return 0
	end
	-- the upright right of that heading: (-look.Z, 0, look.X) flattened
	local ux, uz = -look.Z / fl, look.X / fl
	return math.atan2(right.Y, right.X * ux + right.Z * uz)
end

-- The frame at cf's place with only its heading (no lean, no pitch). Pure
function CameraRig.upright(cf: CFrame): CFrame
	local look = cf.LookVector
	return CFrame.new(cf.Position) * CFrame.Angles(0, math.atan2(-look.X, -look.Z), 0)
end

-- One frame of the camera's lean following RIDE.roll of the vehicle's `actual` lean. Pure
function CameraRig.rollStep(shown: number, actual: number, dt: number): number
	local R = CameraRig.RIDE
	return shown + (actual * R.roll - shown) * (1 - math.exp(-R.rate * math.max(dt, 0)))
end

-- The eye for a vehicle whose root frame is `root`, its EyeSocket `eyeRel` in that frame, leaning `shown`. Pure
function CameraRig.rideEye(root: CFrame, eyeRel: CFrame, shown: number): CFrame
	return CameraRig.upright(root) * CFrame.Angles(0, 0, shown) * eyeRel
end

-- vehicleThird: the camera distance from the focus at which the driver's body has started to fade, for a body that
-- reaches `radius` studs from the focus: it is gone (fadeAt 1) with the camera RIDER_PAD outside that reach. Pure
CameraRig.RIDER_PAD = 0.75
CameraRig.RIDER_REACH = 4.4 -- the most reach counted: the fade then starts inside 8 studs, the engine camera's least
function CameraRig.riderHide(radius: number): number
	return (radius + CameraRig.RIDER_PAD) / 0.65
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
		-- an enclosed run (the ball return, a drain, a hollow tree): low behind the squirrel along its heading, pulled
		-- in front of any wall or ceiling between (raycasts against the run's own parts), smoothed so a climb reads.
		-- Inside a hollow tree the rays meet only its shell (Workspace.HollowTrees: the tree's invisible trunk
		-- colliders fill the cavity and its bark mesh is not queryable), and the view is the hollow look (HOLLOW):
		-- the mouse and the right stick turn it about the head, the eye kept in the cavity, the shell faded where it
		-- would block, a peek out of a hole up the trunk; coming in, the eye comes through the ground hole.
		local body = targets.body
		local root = body and body.PrimaryPart
		if root then
			setFirstPerson(false)
			camera.CameraType = Enum.CameraType.Scriptable
			local GuiService = game:GetService("GuiService")
			local H = CameraRig.HOLLOW
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = { body :: Model }
			local hollows = HollowLayout.default()
			local shell = workspace:FindFirstChild("HollowTrees")
			local inShell = RaycastParams.new()
			inShell.FilterType = Enum.RaycastFilterType.Include
			inShell.FilterDescendantsInstances = if shell then { shell } else {}
			local current = camera.CFrame
			local wasIn = false
			local yaw, pitch, idle, rest = 0, H.rest, 0, H.rest
			local peekK = 0
			local entering = 0
			local lastPos = root.Position
			local faded: { [BasePart]: boolean } = {}
			local bodyHidden = false
			local function hideBody(on: boolean)
				if on == bodyHidden then
					return
				end
				bodyHidden = on
				for _, d in (body :: Model):GetDescendants() do
					if d:IsA("BasePart") or d:IsA("Decal") then
						(d :: any).LocalTransparencyModifier = if on then 1 else 0
					end
				end
			end
			-- the shell's pieces between the eye and the head, and round the eye, faded on this screen
			local function fadeBetween(eye: Vector3, head: Vector3)
				local now: { [BasePart]: boolean } = {}
				if shell then
					local near = OverlapParams.new()
					near.FilterType = Enum.RaycastFilterType.Include
					near.FilterDescendantsInstances = { shell }
					for _, p in workspace:GetPartBoundsInRadius(eye, H.fadeNear, near) do
						now[p] = true
					end
					local from, left = head, eye - head
					for _ = 1, 4 do
						local hit = workspace:Raycast(from, left, inShell)
						if hit == nil then
							break
						end
						now[hit.Instance :: BasePart] = true
						local step = left.Unit * 0.05
						left -= (hit.Position - from) + step
						from = hit.Position + step
						if left.Magnitude < 0.05 then
							break
						end
					end
				end
				for p in now do
					if not CameraRig.fades(p.Name) then
						now[p] = nil
					elseif not faded[p] then
						p.LocalTransparencyModifier = H.fade
					end
				end
				for p in faded do
					if not now[p] then
						p.LocalTransparencyModifier = 0
					end
				end
				faded = now
			end
			-- a hollow's dark ovals on its bark, hidden while the camera is in that hollow (from within they would hang
			-- in the air over its holes; the holes are lined to the bark)
			local ovalsOf: Instance? = nil
			local function hideOvals(model: Instance?)
				if model == ovalsOf then
					return
				end
				for _, m in { ovalsOf, model } do
					if m then
						for _, p in m:GetChildren() do
							if p:IsA("BasePart") and string.find(p.Name, "^knothole") then
								p.LocalTransparencyModifier = if m == model then 1 else 0
							end
						end
					end
				end
				ovalsOf = model
			end
			bind(function(dt: number)
				local cf = root.CFrame
				local look = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
				look = if look.Magnitude > 0.05 then look.Unit else Vector3.zAxis
				local head = cf.Position + Vector3.new(0, 0.35, 0)
				-- (looked up once a frame: its rest, its middle line, its ovals and its ground hole all come from it)
				local here = if hollows then CameraRig.hollowAt(hollows, head.X, head.Y, head.Z) else nil
				if here == nil or hollows == nil then
					hideBody(false)
					hideOvals(nil)
					if next(faded) then
						for p in faded do
							p.LocalTransparencyModifier = 0
						end
						faded = {}
					end
					local rays = params
					local wx, wy, wz = CameraRig.tunnelPoint(
						head.X,
						head.Y,
						head.Z,
						look.X,
						look.Z,
						function(ox: number, oy: number, oz: number, dx: number, dy: number, dz: number)
							-- (on through anything not drawn: the log's thresholds stop feet, not the view)
							local from, left = Vector3.new(ox, oy, oz), Vector3.new(dx, dy, dz)
							for _ = 1, 3 do
								local hit = workspace:Raycast(from, left, rays)
								if hit == nil then
									break
								end
								if hit.Instance.Transparency < 1 then
									return hit.Position.X, hit.Position.Y, hit.Position.Z
								end
								local step = left.Unit * 0.05
								left -= (hit.Position - from) + step
								from = hit.Position + step
								if left:Dot(Vector3.new(dx, dy, dz)) <= 0 then
									break
								end
							end
							return nil, nil, nil
						end,
						nil
					)
					current =
						current:Lerp(CFrame.lookAt(Vector3.new(wx, wy, wz), head + look * 3.5), 1 - math.exp(-dt * 10))
					wasIn = false
					camera.CFrame = current
					camera.FieldOfView = 75
					steer = nil
					return
				end
				local layout = assert(hollows, "the hollow trees are loaded")
				if not wasIn then
					-- (in at the rest: up the hollow)
					rest = CameraRig.hollowRest(here)
					yaw, pitch, idle = 0, rest, 0
				end
				-- the look: the mouse (unless the cursor is out) and the right stick
				local typing = held or GuiService.MenuIsOpen or UIS:GetFocusedTextBox() ~= nil
				local free = typing or UIS:IsKeyDown(Enum.KeyCode.LeftAlt) or next(cursorWanted) ~= nil
				local moved = false
				if not free then
					UIS.MouseBehavior = Enum.MouseBehavior.LockCenter
					local d = UIS:GetMouseDelta()
					if d.Magnitude > 0 then
						yaw, pitch = CameraRig.hollowLook(
							yaw,
							pitch,
							d.X * CameraRig.LOOK.sens,
							d.Y * CameraRig.LOOK.sens,
							invertLook
						)
						moved = true
					end
				else
					UIS.MouseBehavior = Enum.MouseBehavior.Default
				end
				for _, input in UIS:GetGamepadState(Enum.UserInputType.Gamepad1) do
					if input.KeyCode == Enum.KeyCode.Thumbstick2 and input.Position.Magnitude > 0.15 then
						local k = CameraRig.LOOK.stick * dt
						yaw, pitch =
							CameraRig.hollowLook(yaw, pitch, input.Position.X * k, -input.Position.Y * k, invertLook)
						moved = true
					end
				end
				idle = if moved then 0 else idle + dt
				local speed = (root.Position - lastPos).Magnitude / math.max(dt, 1e-3)
				lastPos = root.Position
				yaw, pitch = CameraRig.hollowRecentre(yaw, pitch, idle, speed > 0.5, dt, rest)
				-- a peek at a hole up the trunk once the body stands at it
				local feet = cf.Position
				local mouth = layout.peekAt(feet.X, feet.Y - 0.35, feet.Z)
				local wantPeek = mouth ~= nil and speed < 1
				peekK += ((if wantPeek then 1 else 0) - peekK) * (1 - math.exp(-H.peekEase * dt))
				-- (the middle line of the cavity round the head)
				local mx, mz = nil :: number?, nil :: number?
				for _, c in here.cavities do
					if c.a == nil and head.Y >= c.bottom - 0.5 and head.Y <= c.top then
						mx, mz = c.x, c.z
					end
				end
				-- (the shell's model of a hollow is named by its id: Server/World/HollowShell)
				hideOvals(if shell then shell:FindFirstChild(here.id) else nil)
				local ex, ey, ez, vx, vy, vz, first =
					CameraRig.hollowView(head.X, head.Y, head.Z, look.X, look.Z, yaw, pitch, layout.keepCamera, mx, mz)
				local eye, dir = Vector3.new(ex, ey, ez), Vector3.new(vx, vy, vz)
				if mouth and peekK > 0.01 then
					-- (the peek's pitch counted from the rest: at rest it looks level out of the hole)
					local px, py, pz, qx, qy, qz = CameraRig.peekView(mouth :: any, yaw, pitch - rest)
					eye = eye:Lerp(Vector3.new(px, py, pz), peekK)
					dir = dir:Lerp(Vector3.new(qx, qy, qz), peekK)
					first = first and peekK < 0.5
				end
				local target = CFrame.lookAt(eye, eye + (if dir.Magnitude > 1e-3 then dir.Unit else look))
				if not wasIn then
					-- coming in: from just outside the ground hole the body came through, in through it
					local g: any = nil
					for _, mm in here.mouths do
						if
							mm.opens == "ground"
							and (
								g == nil
								or (mm.x - head.X) ^ 2 + (mm.z - head.Z) ^ 2 < (g.x - head.X) ^ 2 + (g.z - head.Z) ^ 2
							)
						then
							g = mm
						end
					end
					if g then
						local o = Vector3.new(g.out[1], 0, g.out[3])
						o = if o.Magnitude > 1e-3 then o.Unit else -look
						local at = Vector3.new(g.x, g.y + 0.9, g.z) + o * 1.2
						current = CFrame.lookAt(at, at - o)
						entering = H.entry
					else
						current = target
					end
				end
				wasIn = true
				if entering > 0 then
					entering = math.max(0, entering - dt)
					current = current:Lerp(target, math.clamp(dt / math.max(entering + dt, 1e-3), 0, 1))
				else
					current = current:Lerp(target, 1 - math.exp(-dt * H.ease))
				end
				hideBody(first)
				fadeBetween(current.Position, head)
				camera.CFrame = current
				camera.FieldOfView = 75
				-- (the keys steer by the body's heading, not the look: Client/Controllers/Squirrel reads steerYaw)
				steer = math.atan2(-look.X, -look.Z)
			end)
			onUnbind = function()
				camera.FieldOfView = CameraRig.FOV
				hideBody(false)
				hideOvals(nil)
				for p in faded do
					p.LocalTransparencyModifier = 0
				end
				faded = {}
				steer = nil
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
			-- (the default camera does this only for its own first person); chosen once, never toggled
			local hidden: { Instance } = {}
			local driver = targets.body
			-- and the vehicle's own parts round the eye (CameraRig.seeOut), once it is there; not the gondola's
			local cleared: { BasePart }? = if free then {} else nil
			local car: Instance = vehicle :: any
			-- a vehicle (not the gondola): the eye in the vehicle's upright frame, leaning gently (RIDE)
			local root = (vehicle :: Model).PrimaryPart
			local eyeRel: CFrame? = nil
			local shown = 0
			bind(function(dt: number)
				if cleared == nil then
					local list: { BasePart } = {}
					local at = eye.WorldPosition
					for _, d in car:GetDescendants() do
						if d:IsA("BasePart") and d.Transparency < 1 then
							local k = CameraRig.seeOut(at, d.CFrame, d.Size, d.Material == Enum.Material.Glass)
							if k then
								d.LocalTransparencyModifier = k
								table.insert(list, d)
							end
						end
					end
					cleared = list
				end
				if driver and #hidden == 0 then
					for _, d in driver:GetDescendants() do
						if d:IsA("BasePart") or d:IsA("Decal") then
							table.insert(hidden, d)
						end
					end
				end
				for _, part in hidden do
					-- (kept at 1: something else may write it, e.g. a fade on the way in; a write only then)
					if (part :: any).LocalTransparencyModifier ~= 1 then
						(part :: any).LocalTransparencyModifier = 1
					end
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
				local at = eye.WorldCFrame
				if not free and root and root.Parent then
					local rootCf = root.CFrame
					local rel = eyeRel or rootCf:ToObjectSpace(at)
					eyeRel = rel
					shown = CameraRig.rollStep(shown, CameraRig.rollOf(rootCf), dt)
					at = CameraRig.rideEye(rootCf, rel, shown)
				end
				camera.CFrame = at * CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)
			end)
			onUnbind = function()
				for _, part in hidden do
					(part :: any).LocalTransparencyModifier = 0
				end
				local seen = cleared
				if seen then
					for _, part in seen do
						part.LocalTransparencyModifier = 0
					end
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
			-- the driver's body fades as the engine camera comes in close to it (a wall behind pulls it in), so the
			-- camera is never inside the driver; read after the engine camera has moved, in the same frame
			local driver = targets.body
			if driver then
				local parts: { Instance } = {}
				for _, d in driver:GetDescendants() do
					if d:IsA("BasePart") or d:IsA("Decal") then
						table.insert(parts, d)
					end
				end
				-- how far the driver's body reaches from the focus `follow` keeps over the vehicle (capped: faded only
				-- inside the engine camera's least distance, CameraMinZoomDistance)
				local cf, size = driver:GetBoundingBox()
				local _, vsize = vehicle:GetBoundingBox()
				local vroot = vehicle.PrimaryPart
				local focusAt = (if vroot then vroot.Position else cf.Position)
					+ Vector3.new(0, CameraRig.followLift(vsize.Y), 0)
				local reach = (cf.Position - focusAt).Magnitude + size.Magnitude / 2
				local hideAt = CameraRig.riderHide(math.min(reach, CameraRig.RIDER_REACH))
				local faded = -1
				local function fade(a: number)
					if a == faded then
						return
					end
					faded = a
					for _, d in parts do
						(d :: any).LocalTransparencyModifier = a
					end
				end
				local RunService = game:GetService("RunService")
				local name = "SpicyCameraRigRider"
				RunService:BindToRenderStep(name, Enum.RenderPriority.Camera.Value + 1, function()
					fade(CameraRig.fadeAt((camera.CFrame.Position - camera.Focus.Position).Magnitude, hideAt))
				end)
				onUnbind = function()
					RunService:UnbindFromRenderStep(name)
					fade(0)
				end
			end
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
