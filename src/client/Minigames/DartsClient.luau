--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Minigames.DartsClient
-- The thrower's side of the dartboard (brief v2 §13a: "mouse sets the aim point, a timing meter sets power,
-- slight wobble so it is a skill rather than a click; scores 501 and cricket"). On your turn you stand at the
-- oche and the camera looks down the throw at the board; the mouse puts the aim on the board, the hand wobbles
-- it slightly (the bright dot is where the dart is pointed; the faint ring is your mouse), hold the mouse
-- button or Space to run the timing meter and let go in the green band: early drops the dart low, late throws
-- it high. The server resolves the throw from the same rules (Minigames/MinigameRules/Darts) with its own seeded
-- scatter. In the lobby the first player picks 501 or Cricket.
-- Interface: new(ctx) -> Thrower; Thrower:onState(msg); Thrower:onDart(msg); Thrower:stop(); HELP; HELP_CRICKET

local Import = require("../Import")
local AlleyLayout = Import.shared("Attractions/AlleyLayout") :: typeof(require("../../shared/Attractions/AlleyLayout"))
local Darts =
	Import.shared("Minigames/MinigameRules/Darts") :: typeof(require("../../shared/Minigames/MinigameRules/Darts"))

local DartsClient = {}
DartsClient.__index = DartsClient

DartsClient.HELP = {
	how = {
		"501: start on 501 and count down to exactly zero, finishing on a double (outer ring) or the bull.",
		"Cricket: hit 15 to 20 and the bull three times each to close them; extra hits score until everyone closes.",
		"Three darts a turn, up to four players.",
	},
	keys = {
		"Mouse  aim at the board (it wobbles a little)",
		"Hold the mouse button or Space: timing meter",
		"Let go in the green band (early = low, late = high)",
		"Q  leave the board",
	},
}

function DartsClient.new(ctx: { [string]: any }): any
	local self = setmetatable({}, DartsClient) :: any
	self.ctx = ctx
	self.place = ctx.place
	self.board = AlleyLayout.board()
	self.myTurn = false
	self.charging = false
	self.chargeT = 0
	self.aim = { x = 0, y = 0 }
	self.sentAt = -math.huge
	self.conns = {} :: { RBXScriptConnection }
	self.wobbleT = 0
	local cam = workspace.CurrentCamera
	local function marker(name: string, size: number, color: Color3, transparency: number): BasePart
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Shape = Enum.PartType.Cylinder
		p.Material = Enum.Material.Neon
		p.Color = color
		p.Transparency = 1
		p.Size = Vector3.new(0.01, size, size)
		p:SetAttribute("Shown", transparency)
		p.Parent = cam
		return p
	end
	self.dot = marker("DartAim", 0.045, Color3.fromRGB(255, 60, 60), 0)
	self.ring = marker("DartMouse", 0.09, Color3.fromRGB(255, 255, 255), 0.6)
	local UIS = game:GetService("UserInputService")
	table.insert(
		self.conns,
		UIS.InputBegan:Connect(function(io: InputObject, processed: boolean)
			if processed and io.UserInputType ~= Enum.UserInputType.Keyboard then
				return
			end
			if
				io.UserInputType == Enum.UserInputType.MouseButton1
				or io.KeyCode == Enum.KeyCode.Space
				or io.KeyCode == Enum.KeyCode.ButtonR2
			then
				self:_charge(true)
			end
		end)
	)
	table.insert(
		self.conns,
		UIS.InputEnded:Connect(function(io: InputObject)
			if
				io.UserInputType == Enum.UserInputType.MouseButton1
				or io.KeyCode == Enum.KeyCode.Space
				or io.KeyCode == Enum.KeyCode.ButtonR2
			then
				self:_charge(false)
			end
		end)
	)
	table.insert(
		self.conns,
		game:GetService("RunService").RenderStepped:Connect(function(dt: number)
			self:_frame(dt)
		end)
	)
	ctx.ui:touch({ { "bowl", "HOLD TO THROW" } }, function()
		self:_charge(true)
	end, function()
		self:_charge(false)
	end)
	return self
end

function DartsClient._charge(self: any, down: boolean)
	if down then
		if self.myTurn and os.clock() - self.sentAt > 0.6 and not self.charging then
			self.charging = true
			self.chargeT = 0
		end
	elseif self.charging then
		self.charging = false
		if self.myTurn then
			local timing = Darts.meter(self.chargeT)
			local wx, wy = Darts.wobble(self.wobbleT)
			self.sentAt = os.clock()
			self.ctx.send("throw", { self.aim.x + wx, self.aim.y + wy, timing })
			self.ctx.ui:meter(nil)
		end
	end
end

-- world point on the board face <-> board mm
function DartsClient._world(self: any, xmm: number, ymm: number): Vector3
	local b, mm = self.board, AlleyLayout.DART_MM
	return Vector3.new(AlleyLayout.toWorld(self.place, b.x - 0.075, b.y + ymm * mm, b.d + xmm * mm))
end

function DartsClient._frame(self: any, dt: number)
	local ctx = self.ctx
	self.wobbleT += dt
	local b = self.board
	if not self.myTurn then
		self.dot.Transparency = 1
		self.ring.Transparency = 1
		return
	end
	-- stand at the oche, look at the board
	local body = ctx.body()
	local root = body and body.PrimaryPart
	if root then
		local x, _, z = AlleyLayout.toWorld(self.place, b.ocheX - 0.7, 0, b.d + 0.4)
		local fx, fz = AlleyLayout.dirToWorld(self.place, 1, 0)
		root.CFrame = CFrame.lookAt(Vector3.new(x, root.Position.Y, z), Vector3.new(x + fx, root.Position.Y, z + fz))
		root.AssemblyLinearVelocity = Vector3.zero
	end
	local eye = Vector3.new(AlleyLayout.toWorld(self.place, b.ocheX - 0.2, 5.1, b.d + 0.25))
	local centre = self:_world(0, 0)
	local cam = workspace.CurrentCamera
	ctx.camera(CFrame.lookAt(eye, centre), 20)
	-- the mouse ray onto the board plane
	local UIS = game:GetService("UserInputService")
	local mp = UIS:GetMouseLocation()
	local ray = cam:ViewportPointToRay(mp.X, mp.Y)
	local nx, nz = AlleyLayout.dirToWorld(self.place, -1, 0)
	local n = Vector3.new(nx, 0, nz)
	local denom = ray.Direction:Dot(n)
	if math.abs(denom) > 1e-4 then
		local t = (centre - ray.Origin):Dot(n) / denom
		if t > 0 then
			local hit = ray.Origin + ray.Direction * t
			local _, Y, D = AlleyLayout.toLocal(self.place, hit.X, hit.Y, hit.Z)
			local mm = AlleyLayout.DART_MM
			self.aim.x = math.clamp((D - b.d) / mm, -Darts.MAX_AIM, Darts.MAX_AIM)
			self.aim.y = math.clamp((Y - b.y) / mm, -Darts.MAX_AIM, Darts.MAX_AIM)
		end
	end
	local wx, wy = Darts.wobble(self.wobbleT)
	local rot = CFrame.lookAt(Vector3.zero, n).Rotation * CFrame.Angles(0, math.pi / 2, 0)
	self.dot.CFrame = CFrame.new(self:_world(self.aim.x + wx, self.aim.y + wy)) * rot
	self.ring.CFrame = CFrame.new(self:_world(self.aim.x, self.aim.y)) * rot
	self.dot.Transparency = 0
	self.ring.Transparency = 0.6
	if self.charging then
		self.chargeT += dt
		ctx.ui:meter(
			Darts.meter(self.chargeT),
			{ Darts.SWEET - Darts.SWEET_HALF, Darts.SWEET + Darts.SWEET_HALF },
			"let go in the green"
		)
	end
	local hit = Darts.scoreAt(self.aim.x + wx, self.aim.y + wy)
	ctx.ui:status(`Your throw - aiming at {Darts.label(hit)}. Hold the mouse button, let go in the green`)
end

function DartsClient.onState(self: any, msg: { [string]: any })
	local view = msg.view
	local g = view.game
	local mine = view.phase == "playing" and view.turn == msg.you
	if mine and not self.myTurn then
		self.ctx.controls(false)
	elseif not mine and self.myTurn then
		self.ctx.controls(true)
		self.ctx.releaseCamera()
		self.charging = false
		self.ctx.ui:meter(nil)
	end
	self.myTurn = mine
	if view.phase == "lobby" then
		local mode = view.mode or "501"
		self.ctx.ui:status(`Starting in {view.lobbyLeft or 0} - game: {mode} (pick below; Space starts now)`)
		self.ctx.setButtons({
			{ "501", "501" },
			{ "cricket", "Cricket" },
			{ "addai", "+ Computer" },
			{ "start", "Start" },
			{ "leave", "Leave (Q)" },
		})
	elseif view.phase == "playing" then
		self.ctx.setButtons({ { "leave", "Leave (Q)" } })
		if not mine and view.turn then
			local s = view.seats[view.turn]
			self.ctx.ui:status(`{s and s.name or "?"} is throwing (dart {g and g.dart or 1} of 3)`)
		end
	elseif view.phase == "done" then
		self.ctx.ui:status(`Game over. Play again or leave (Q). The board resets in {view.doneLeft or 0}`)
	end
end

function DartsClient.onDart(_self: any, _msg: { [string]: any }) end

function DartsClient.stop(self: any)
	for _, c in self.conns do
		c:Disconnect()
	end
	table.clear(self.conns)
	self.dot:Destroy()
	self.ring:Destroy()
	self.ctx.ui:meter(nil)
end

return DartsClient
