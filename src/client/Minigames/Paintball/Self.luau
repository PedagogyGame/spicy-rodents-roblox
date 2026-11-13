--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Minigames.Paintball.Self
-- The player's own body, for the paintball seat (brief v2 §14; checklist PB-9): the Port SeatCore
-- asks for, on the real Instances. It is the one place of the client that reads and writes the body
-- the player walked in with, and it writes only what the contract says a seat may:
--   first person   the body's "CameraZone" attribute ("lockFirstPerson" while the seat is open, cleared
--                  when it closes): Client/Possession and Camera/CameraPolicy do the locking. It is
--                  KEPT every frame, on whatever body the player has now, so nothing that happens in a
--                  match (a body that streams in late, another script writing the zone) lets the view
--                  out to third person
--   the eye        Humanoid.CameraOffset.Y, so that the camera is EXACTLY Body.eye(crouch) above the
--                  feet (less the landing dip) whatever the body's own proportions: the stock camera
--                  sits 1.5 above the root of an R15 body, which is 4.5 over the feet only for a root
--                  3.0 up; this game's own people have theirs 3.2 up and an avatar's varies. The ball
--                  leaves from Body.eye, so only with the camera there is what is under the crosshair
--                  what is hit, and a crouched eye really under a rail. Nothing about collision.
--   the view       Camera.FieldOfView (the sprint's widening, eased here), put back on closing
--   the jump       Humanoid.JumpHeight = Body.JUMP_HEIGHT while seated, put back on closing
--   a placement    PivotTo the placed feet point and yaw (the client owns its body's physics)
--   the look       ONE camera hold through ctx.camera, at the placed eye along the placed yaw; the
--                  seat lets it go a frame later. Nothing else here touches the camera's CFrame.
--   the curtains   CanCollide on the parts named Arena.CURTAIN .. team under the arena's model, on
--                  this screen only (looked for again as the building streams in)
-- Never Humanoid.WalkSpeed (the pace is the framework's ctx.pace) and never the Humanoid's shape.
-- Interface: new(ctx, frame, tuning?) -> Self (a SeatCore.Port, plus step(dt), muzzleAt: Vector3?
--   (the marker says where its muzzle is drawn), siteModel() -> Instance?)

local Import = require("../../Import")
local ArenaModule: typeof(require(game.ReplicatedStorage.Shared.Minigames.Paintball.Arena)) =
	Import.shared("Minigames/Paintball/Arena")
local Body: typeof(require(game.ReplicatedStorage.Shared.Minigames.Paintball.Body)) =
	Import.shared("Minigames/Paintball/Body")
local Contract: typeof(require(game.ReplicatedStorage.Shared.Minigames.Paintball.Contract)) =
	Import.shared("Minigames/Paintball/Contract")
local ClientGame = require("../ClientGame")
local Tuning = require("./Tuning")

type Place = typeof(ArenaModule.T.Place)

export type Self = {
	pose: () -> (number?, number, number, number, number, number, boolean),
	push: () -> number,
	place: (x: number, y: number, z: number, yaw: number) -> (),
	look: (x: number, y: number, z: number, yaw: number) -> (),
	muzzle: () -> (number?, number, number),
	eye: (offset: number) -> (),
	fov: (extra: number) -> (),
	curtains: (team: number?) -> (),
	lock: (on: boolean) -> (),
	user: () -> number,
	step: (dt: number) -> (),
	muzzleAt: Vector3?,
}

local SelfPort = {}

local ROOT_HEIGHT = 3 -- an R15 root above the feet (Body: the eye is root + 1.5)
local MOVE_KEYS = { "W", "A", "S", "D", "Up", "Down", "Left", "Right" }

-- The arena's baked model on this screen, if it has streamed in.
function SelfPort.arenaModel(): Instance?
	local att = workspace:FindFirstChild("Attractions")
	for _, site in if att then att:GetChildren() else {} do
		if site:GetAttribute("Site") == Contract.SITE then
			return site:FindFirstChild(ArenaModule.MODEL)
		end
	end
	return nil
end

function SelfPort.new(ctx: ClientGame.Ctx, frame: () -> Place?, tuning: typeof(Tuning.T)?): Self
	local tune = tuning or Tuning
	local UIS = game:GetService("UserInputService")
	local camera = workspace.CurrentCamera
	local controls: any = nil
	local controlsTried = false
	local baseFov: number? = nil
	local fovNow, fovWant = 0, 0
	local eyeNow = 0
	local wasJump: number? = nil
	local wasJumpPower: boolean? = nil
	local solid: number? = nil
	local curtainAcc = 0
	local locked = false
	local lockedBody: Model? = nil

	local function humanoidOf(body: Model?): Humanoid?
		return if body then body:FindFirstChildOfClass("Humanoid") else nil
	end

	local function rootHeight(body: Model): number
		local hum = humanoidOf(body)
		local root = body.PrimaryPart
		if hum and root and type(hum.HipHeight) == "number" and hum.HipHeight > 0 then
			return hum.HipHeight + root.Size.Y / 2
		end
		return ROOT_HEIGHT
	end

	-- Where the stock first-person camera sits above the feet with no CameraOffset (the PlayerModule's
	-- own rule: 1.5 above the root's centre, plus the root's extra half height, for an R15 body that
	-- scales; 2 above it for one that does not).
	local function stockEye(body: Model): number
		local hum = humanoidOf(body)
		local root = (if hum then hum.RootPart else nil) or body.PrimaryPart
		local head = 1.5
		if hum and root and hum.RigType == Enum.HumanoidRigType.R15 then
			head = if hum.AutomaticScalingEnabled then 1.5 + (root.Size.Y - 2) / 2 else 2
		end
		return rootHeight(body) + head
	end

	local self = {} :: Self
	self.muzzleAt = nil

	function self.pose(): (number?, number, number, number, number, number, boolean)
		local body = ctx.body()
		local place = frame()
		local root = if body then body.PrimaryPart else nil
		if body == nil or root == nil or place == nil then
			return nil, 0, 0, 0, 0, 0, false
		end
		local p = root.Position
		local x, y, z = ArenaModule.toLocal(place, p.X, p.Y - rootHeight(body), p.Z)
		local l = camera.CFrame.LookVector
		local dx, dy, dz = ArenaModule.dirToLocal(place, l.X, l.Y, l.Z)
		local hum = humanoidOf(body)
		local air = hum ~= nil and hum.FloorMaterial == Enum.Material.Air
		return x, y, z, dx, dy, dz, air
	end

	-- How hard the player is pushing to move, 0..1: the stock controls' own vector (a stick's push is
	-- analogue there), else the Humanoid's, else the keys.
	function self.push(): number
		if not controlsTried then
			controlsTried = true
			pcall(function()
				local player = game:GetService("Players").LocalPlayer
				local scripts = player:FindFirstChild("PlayerScripts")
				local module = if scripts then scripts:FindFirstChild("PlayerModule") else nil
				if module then
					controls = (require :: any)(module):GetControls()
				end
			end)
		end
		if controls then
			local ok, v = pcall(function()
				return controls:GetMoveVector()
			end)
			if ok and typeof(v) == "Vector3" then
				return math.min(1, v.Magnitude)
			end
		end
		local hum = humanoidOf(ctx.body())
		if hum and typeof(hum.MoveDirection) == "Vector3" then
			return math.min(1, hum.MoveDirection.Magnitude)
		end
		for _, name in MOVE_KEYS do
			if UIS:IsKeyDown((Enum.KeyCode :: any)[name]) then
				return 1
			end
		end
		return 0
	end

	function self.place(x: number, y: number, z: number, yaw: number)
		local body = ctx.body()
		local place = frame()
		if body == nil or place == nil then
			return
		end
		local wx, wy, wz = ArenaModule.toWorld(place, x, y, z)
		local cf = CFrame.new(wx, wy + rootHeight(body), wz) * CFrame.Angles(0, ArenaModule.yawToWorld(place, yaw), 0)
		body:PivotTo(cf)
		local root = body.PrimaryPart
		if root then
			root.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
		end
	end

	function self.look(x: number, y: number, z: number, yaw: number)
		local place = frame()
		if place == nil then
			return
		end
		local wx, wy, wz = ArenaModule.toWorld(place, x, y, z)
		local lx, ly, lz = Body.look(yaw, 0)
		local dx, dy, dz = ArenaModule.dirToWorld(place, lx, ly, lz)
		local eye = Vector3.new(wx, wy, wz)
		ctx.camera(CFrame.lookAt(eye, eye + Vector3.new(dx, dy, dz)), camera.FieldOfView, true)
	end

	function self.muzzle(): (number?, number, number)
		local at = self.muzzleAt
		local place = frame()
		if at == nil or place == nil then
			return nil, 0, 0
		end
		return ArenaModule.toLocal(place, at.X, at.Y, at.Z)
	end

	function self.eye(offset: number)
		local body = ctx.body()
		local hum = humanoidOf(body)
		if body == nil or hum == nil then
			return
		end
		local y = Body.STAND_EYE + offset - stockEye(body)
		if math.abs(y - eyeNow) >= 1e-4 then
			eyeNow = y
			hum.CameraOffset = Vector3.new(0, y, 0)
		end
	end

	function self.fov(extra: number)
		fovWant = extra
	end

	local function applyCurtains()
		local model = SelfPort.arenaModel()
		if model == nil then
			return
		end
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				for team = 1, #Contract.TEAMS do
					if d.Name == ArenaModule.CURTAIN .. team then
						local want = solid == team
						if d.CanCollide ~= want then
							d.CanCollide = want
						end
					end
				end
			end
		end
	end

	function self.curtains(team: number?)
		solid = team
		applyCurtains()
	end

	-- First person and the match's jump on one body; `off` puts back what was found there.
	local function engage(body: Model?)
		lockedBody = body
		if body == nil then
			return
		end
		body:SetAttribute("CameraZone", "lockFirstPerson")
		local hum = humanoidOf(body)
		if hum then
			wasJump, wasJumpPower = hum.JumpHeight, hum.UseJumpPower
			hum.UseJumpPower = false
			hum.JumpHeight = Body.JUMP_HEIGHT
		end
	end

	local function disengage()
		local body = lockedBody
		lockedBody = nil
		if body ~= nil then
			body:SetAttribute("CameraZone", nil)
			local hum = humanoidOf(body)
			if hum then
				if wasJump ~= nil then
					hum.JumpHeight = wasJump
				end
				if wasJumpPower ~= nil then
					hum.UseJumpPower = wasJumpPower
				end
				hum.CameraOffset = Vector3.new(0, 0, 0)
			end
		end
		eyeNow = 0
		wasJump, wasJumpPower = nil, nil
	end

	function self.lock(on: boolean)
		locked = on
		if on then
			baseFov = camera.FieldOfView
			engage(ctx.body())
		else
			disengage()
			local fov = baseFov
			if fov ~= nil then
				camera.FieldOfView = fov
			end
			baseFov = nil
			fovNow, fovWant = 0, 0
		end
	end

	function self.user(): number
		local id = game:GetService("Players").LocalPlayer.UserId
		return if type(id) == "number" then id else 0
	end

	function self.step(dt: number)
		-- the view widens with the sprint and comes back as smoothly (the ramp itself stops dead)
		local fov = baseFov
		if fov ~= nil then
			local next = fovNow + (fovWant - fovNow) * (1 - math.exp(-tune.fovRate * dt))
			if math.abs(fovWant - next) < 0.01 then
				next = fovWant
			end
			fovNow = next
			-- (written whenever it is not what it should be: the framework puts the view back to its
			-- own default when a camera hold is let go, which is in the middle of a match here)
			if math.abs(camera.FieldOfView - (fov + fovNow)) > 1e-4 then
				camera.FieldOfView = fov + fovNow
			end
		end
		-- THE LOCK IS KEPT, not set once: the body the seat opened on may not have been there yet, may
		-- be another one now, or something else may have written its zone. First person for the whole
		-- match is the brief's (section 14), so it is looked at every frame (one attribute read).
		if locked then
			local body = ctx.body()
			if body ~= lockedBody then
				disengage()
				engage(body)
			elseif body ~= nil and body:GetAttribute("CameraZone") ~= "lockFirstPerson" then
				body:SetAttribute("CameraZone", "lockFirstPerson")
			end
		end
		-- the building streams in piece by piece: the curtains are looked for again
		curtainAcc += dt
		if curtainAcc >= 1 then
			curtainAcc = 0
			if solid ~= nil then
				applyCurtains()
			end
		end
	end

	return self
end

return SelfPort
