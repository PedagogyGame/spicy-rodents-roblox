--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Minigames.DartsClient
-- The thrower's side of the dartboard (brief v2 §13a: "mouse sets the aim point, a timing meter sets power,
-- slight wobble so it is a skill rather than a click; scores 501 and cricket"). On your turn you stand at the
-- oche and the camera looks down the throw at the board; the mouse puts the aim on the board, the hand wobbles
-- it slightly (the bright dot is where the dart is pointed; the faint disc is your mouse), hold the mouse
-- button or Space to run the timing meter and let go in the green band: early drops the dart low, late throws
-- it high. On a touch screen a finger dragged anywhere moves the aim (as far as the finger moves) and the HOLD
-- TO THROW button runs the meter. The status line says which dart it is, what is left and what the dot is on;
-- the turn clock counts down and warns before an idle turn is skipped. The shot stays on the board for a moment
-- after your last dart, so you see it land, and then your own camera and legs come back. The server resolves
-- the throw from the same rules (Minigames/MinigameRules/Darts) with its own seeded scatter. In the lobby the
-- first player picks 501 or Cricket. Typing in chat throws nothing, and a click on a button is the button's.
-- The main client's rules (MinigameClient's header): the shot goes through ctx.camera / ctx.releaseCamera
-- (CameraRig.hold); the cursor this needs is the one MinigameUI asks for while its buttons are up (and a held
-- camera frees it too); a press from before your turn is no throw (nothing is remembered between turns).
-- Interface: new(ctx) -> Thrower; Thrower:onState(msg); Thrower:stop(); HELP; LOCK; LINGER; WARN_AT

local Import = require("../Import")
local AlleyLayout = Import.shared("Attractions/AlleyLayout") :: typeof(require("../../shared/Attractions/AlleyLayout"))
local Darts =
	Import.shared("Minigames/MinigameRules/Darts") :: typeof(require("../../shared/Minigames/MinigameRules/Darts"))
local InputMap = require("../Input/InputMap")

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
		"Touch  drag to aim, hold the button to throw",
		"Q  leave the board",
	},
}
DartsClient.LOCK = 0.6 -- seconds after a throw before the next can be started (the dart is in the air)
DartsClient.LINGER = 1.3 -- seconds the shot stays on the board after your last dart of a turn
DartsClient.WARN_AT = 10 -- seconds left on the turn clock when the warning comes up
local SHOT_FOV = 20

function DartsClient.new(ctx: { [string]: any }): any
	local self = setmetatable({}, DartsClient) :: any
	self.ctx = ctx
	self.place = ctx.place
	self.board = AlleyLayout.board()
	self.myTurn = false -- the server says it is my throw
	self.shotUp = false -- my shot of the board is up and my legs are the board's (my turn, and a moment after it)
	self.lingerUntil = nil :: number? -- when the shot is handed back after my last dart
	self.charging = false
	self.chargeT = 0
	self.aim = { x = 0, y = 0 }
	self.t = 0 -- seconds of frames since the game opened (the wobble, the throw lock, the clocks)
	self.sentAt = -math.huge
	self.finger = nil :: any -- the touch that is dragging the aim (its InputObject) and where it last was
	self.fingerAt = nil :: Vector3?
	self.dart = 1
	self.left = nil :: number? -- 501: what is left on my line
	self.turnLeft = nil :: number?
	self.turnLeftAt = 0
	self.conns = {} :: { RBXScriptConnection }
	local cam = workspace.CurrentCamera
	local function marker(name: string, size: number, color: Color3): BasePart
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
		p.Parent = cam
		return p
	end
	self.dot = marker("DartAim", 0.045, Color3.fromRGB(255, 60, 60))
	self.ring = marker("DartMouse", 0.09, Color3.fromRGB(255, 255, 255))
	local UIS = game:GetService("UserInputService")
	local function throwKey(io: InputObject): boolean
		return io.UserInputType == Enum.UserInputType.MouseButton1
			or io.KeyCode == Enum.KeyCode.Space
			or io.KeyCode == Enum.KeyCode.ButtonR2
	end
	table.insert(
		self.conns,
		UIS.InputBegan:Connect(function(io: InputObject, processed: boolean)
			-- chat, text boxes and the Roblox menu own the keys while they are up; a click or a touch on a
			-- button is the button's
			if InputMap.ignore(io, processed) then
				return
			end
			if io.UserInputType == Enum.UserInputType.Touch then
				-- a finger on the screen (not on a button) drags the aim from where the aim is
				self.finger = io
				self.fingerAt = io.Position
			elseif throwKey(io) then
				self:_charge(true)
			end
		end)
	)
	table.insert(
		self.conns,
		UIS.InputChanged:Connect(function(io: InputObject)
			local was = self.fingerAt
			if io == self.finger and was ~= nil and self.myTurn then
				local now = io.Position
				local k = self:_mmPerPixel()
				self:_setAim(self.aim.x + (now.X - was.X) * k, self.aim.y - (now.Y - was.Y) * k)
				self.fingerAt = now
			end
		end)
	)
	table.insert(
		self.conns,
		UIS.InputEnded:Connect(function(io: InputObject)
			if io == self.finger then
				self.finger = nil
				self.fingerAt = nil
			elseif throwKey(io) then
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

-- The throw button. Down starts the meter (only on my turn, and not while my last dart is in the air); letting
-- go throws.
function DartsClient._charge(self: any, down: boolean)
	if down then
		if self.myTurn and self.t - self.sentAt > DartsClient.LOCK and not self.charging then
			self.charging = true
			self.chargeT = 0
		end
	elseif self.charging then
		self.charging = false
		if self.myTurn then
			local timing = Darts.meter(self.chargeT)
			local wx, wy = Darts.wobble(self.t)
			self.sentAt = self.t
			self.ctx.send("throw", { self.aim.x + wx, self.aim.y + wy, timing })
			self.ctx.ui:meter(nil)
		end
	end
end

-- Forget input from before a hand-over of the keys (the main client's rule): a meter left running is not the
-- next turn's throw, and a finger that was dragging the aim has to touch down again.
function DartsClient._flush(self: any)
	self.charging = false
	self.chargeT = 0
	self.finger = nil
	self.fingerAt = nil
	self.ctx.ui:meter(nil)
end

function DartsClient._setAim(self: any, xmm: number, ymm: number)
	self.aim.x = math.clamp(xmm, -Darts.MAX_AIM, Darts.MAX_AIM)
	self.aim.y = math.clamp(ymm, -Darts.MAX_AIM, Darts.MAX_AIM)
end

-- world point on the board face <-> board mm (lift: studs proud of the face, toward the thrower)
function DartsClient._world(self: any, xmm: number, ymm: number, lift: number?): Vector3
	local b = self.board
	local _, Y, D = AlleyLayout.boardPoint(xmm, ymm)
	return Vector3.new(AlleyLayout.toWorld(self.place, b.x - 0.075 - (lift or 0), Y, D))
end

function DartsClient._eye(self: any): Vector3
	local b = self.board
	return Vector3.new(AlleyLayout.toWorld(self.place, b.ocheX - 0.2, 5.1, b.d + 0.25))
end

-- Board millimetres to one pixel of the shot: a finger's drag moves the aim as far as it moves on the screen.
function DartsClient._mmPerPixel(self: any): number
	local reach = (self:_world(0, 0) - self:_eye()).Magnitude
	local tall = 2 * reach * math.tan(math.rad(SHOT_FOV) / 2) -- studs of board plane in the height of the screen
	return tall / math.max(1, workspace.CurrentCamera.ViewportSize.Y) / AlleyLayout.DART_MM
end

function DartsClient._hide(self: any)
	self.dot.Transparency = 1
	self.ring.Transparency = 1
end

-- My own camera and legs back.
function DartsClient._handBack(self: any)
	self.lingerUntil = nil
	if self.shotUp then
		self.shotUp = false
		self.ctx.controls(true)
		self.ctx.releaseCamera()
	end
end

function DartsClient._frame(self: any, dt: number)
	local ctx = self.ctx
	self.t += dt
	local b = self.board
	if self.lingerUntil ~= nil and self.t >= self.lingerUntil then
		self:_handBack()
	end
	if not self.shotUp then
		self:_hide()
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
	local centre = self:_world(0, 0)
	local cam = workspace.CurrentCamera
	ctx.camera(CFrame.lookAt(self:_eye(), centre), SHOT_FOV)
	if not self.myTurn then
		-- my last dart is on its way: the shot only
		self:_hide()
		return
	end
	local UIS = game:GetService("UserInputService")
	local nx, nz = AlleyLayout.dirToWorld(self.place, -1, 0)
	local n = Vector3.new(nx, 0, nz)
	local touch = UIS.TouchEnabled and not UIS.MouseEnabled
	if not touch then
		-- the mouse ray onto the board plane
		local mp = UIS:GetMouseLocation()
		local ray = cam:ViewportPointToRay(mp.X, mp.Y)
		local denom = ray.Direction:Dot(n)
		if math.abs(denom) > 1e-4 then
			local t = (centre - ray.Origin):Dot(n) / denom
			if t > 0 then
				local hit = ray.Origin + ray.Direction * t
				local _, Y, D = AlleyLayout.toLocal(self.place, hit.X, hit.Y, hit.Z)
				self:_setAim(AlleyLayout.boardFromLocal(Y, D))
			end
		end
	end
	local wx, wy = Darts.wobble(self.t)
	local rot = CFrame.lookAt(Vector3.zero, n).Rotation * CFrame.Angles(0, math.pi / 2, 0)
	-- (the dot a hair proud of the disc: two faces in one plane would flicker)
	self.dot.CFrame = CFrame.new(self:_world(self.aim.x + wx, self.aim.y + wy, 0.012)) * rot
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
	-- the turn clock, counted down between the server's once-a-second reports
	local left = if self.turnLeft then math.max(0, self.turnLeft - (self.t - self.turnLeftAt)) else nil
	local warning: string? = nil
	if left ~= nil and left <= DartsClient.WARN_AT then
		local secs = math.max(0, math.ceil(left))
		warning = `Throw within {secs} second{if secs == 1 then "" else "s"} or your turn is skipped`
	end
	ctx.ui:clock(left, warning)
	local hit = Darts.scoreAt(self.aim.x + wx, self.aim.y + wy)
	local what = `dart {self.dart} of {Darts.DARTS_PER_TURN}`
	if self.left ~= nil then
		what ..= `, {self.left} left`
	end
	local how = if touch
		then "Drag to aim, hold the button and let go in the green"
		else "Hold the mouse button or Space, let go in the green"
	ctx.ui:status(`Your throw: {what}. Aiming at {Darts.label(hit)}. {how}`)
end

-- The end of a game in a line: who won, or how it ended.
local function resultLine(view: { [string]: any }, you: number?): string
	local r = view.result
	local seats = view.seats or {}
	if r == nil then
		return "Game over."
	end
	local w = r.winner
	if #seats <= 1 then
		local mine = r.scores and r.scores[1]
		if r.mode == "cricket" then
			return if w then "All closed: game over." else "Out of rounds: game over."
		end
		return if mine == 0 then "Game shot: you checked out!" else `Out of rounds with {tostring(mine)} left.`
	elseif w == nil then
		return "Game over: a draw."
	elseif w == you then
		return "You win!"
	end
	return `{seats[w] and seats[w].name or "?"} wins.`
end

-- msg = the "state" payload: { view, you }.
function DartsClient.onState(self: any, msg: { [string]: any })
	local view = msg.view
	local g = view.game
	local ui = self.ctx.ui
	local mine = view.phase == "playing" and view.turn == msg.you
	if mine and not self.myTurn then
		-- the keys have just become the board's: nothing from before counts
		self:_flush()
		self.lingerUntil = nil
		if not self.shotUp then
			self.shotUp = true
			self.ctx.controls(false)
		end
	elseif not mine and self.myTurn then
		self:_flush()
		ui:clock(nil)
		-- my last dart may still be in the air: the shot stays on the board until it has landed
		local stay = self.sentAt + DartsClient.LINGER - self.t
		if stay > 0 then
			self.lingerUntil = self.t + stay
		else
			self:_handBack()
		end
	end
	self.myTurn = mine
	local line = g and g.seats and msg.you and g.seats[msg.you]
	self.dart = (g and g.dart) or 1
	self.left = if line and g.mode == "501" then line.score else nil
	self.turnLeft = view.turnLeft
	self.turnLeftAt = self.t
	if view.phase == "lobby" then
		local mode = view.mode or "501"
		ui:status(`Starting in {view.lobbyLeft or 0} - game: {mode} (pick below; Space starts now)`)
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
			ui:status(`{s and s.name or "?"} is throwing (dart {self.dart} of {Darts.DARTS_PER_TURN}). Q leaves.`)
		end
	elseif view.phase == "done" then
		ui:status(`{resultLine(view, msg.you)} Play again or Leave (Q). The board resets in {view.doneLeft or 0}`)
	end
end

function DartsClient.stop(self: any)
	for _, c in self.conns do
		c:Disconnect()
	end
	table.clear(self.conns)
	self.dot:Destroy()
	self.ring:Destroy()
	self.lingerUntil = nil
	self.shotUp = false -- (MinigameClient's close() gives the camera and the legs back itself)
	self.myTurn = false
	self.charging = false
	local ui = self.ctx.ui
	ui:meter(nil)
	ui:clock(nil)
end

return DartsClient
