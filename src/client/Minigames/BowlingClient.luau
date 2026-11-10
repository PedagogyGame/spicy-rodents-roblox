--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Minigames.BowlingClient
-- The bowler's side of a lane (brief v2 §13a "choose your angle and power, bowl"). It is thin wiring: the aiming
-- state and every word on screen come from Shared/Minigames/Bowling/AimModel, the camera shots from
-- Bowling/Shots, and the throw itself is drawn by BowlingPlayback from the server's script.
-- On your turn your person steps onto the approach holding the ball (the server welds it to your hand), the
-- camera stands behind you, a dotted line shows your throw two thirds of the way down the lane (orange where a
-- hook has begun to bend it). A / D step along the foul line; the mouse (or Left / Right, or the gamepad
-- stick) turns the angle; Z / X or the mouse wheel put hook on; hold Space or the mouse button to run the
-- power meter and let go to bowl (in the green band the ball goes exactly where you aimed). Touch players get
-- buttons for all of it. The camera rides behind the ball, cuts to the pins a moment before it arrives, holds
-- on the pinfall, then comes back for your next ball or hands your own camera back. A turn clock counts down
-- on screen before an idle turn is skipped. A throw the server refuses, or that never reaches it, puts you
-- straight back to aiming with a line on screen: input is never swallowed. Typing in chat moves nothing.
-- The SERVER decides the throw (D28): this sends { offset, angle, power, spin } once per ball.
-- Interface: new(ctx) -> Bowler; Bowler:onState(msg); Bowler:onRoll(msg, script); Bowler:onRefused(msg);
--   Bowler:stop(); HELP; SEND_TIMEOUT; WATCH_LIMIT; clock (os.clock; a test swaps it)

local Import = require("../Import")
local AlleyLayout = Import.shared("Attractions/AlleyLayout") :: typeof(require("../../shared/Attractions/AlleyLayout"))
local AimModel =
	Import.shared("Minigames/Bowling/AimModel") :: typeof(require("../../shared/Minigames/Bowling/AimModel"))
local PartPose =
	Import.shared("Minigames/Bowling/PartPose") :: typeof(require("../../shared/Minigames/Bowling/PartPose"))
local Shots = Import.shared("Minigames/Bowling/Shots") :: typeof(require("../../shared/Minigames/Bowling/Shots"))
local InputMap = require("../Input/InputMap")

local BowlingClient = {}
BowlingClient.__index = BowlingClient

BowlingClient.HELP = AimModel.HELP
BowlingClient.SEND_TIMEOUT = 2.5 -- seconds to wait for the server to answer a throw before aiming again
BowlingClient.WATCH_LIMIT = 14 -- the roll camera can never be kept longer than this
BowlingClient.clock = os.clock

function BowlingClient.new(ctx: { [string]: any }): any
	local self = setmetatable({}, BowlingClient) :: any
	self.ctx = ctx
	self.lane = ctx.lane :: number
	self.place = ctx.place
	self.aim = AimModel.new()
	self.turnMine = false -- it is my frame
	self.canBowl = false -- and the lane is set
	self.controlsOff = false
	self.sentAt = 0
	self.watch = nil :: { script: any, t0: number }?
	self.slideT = -1
	self.turnLeft = nil :: number?
	self.turnLeftAt = 0
	self.mouseDx = 0
	self.held = {} :: { [string]: boolean }
	self.dots = {} :: { BasePart }
	self.dotSig = ""
	self.conns = {} :: { RBXScriptConnection }
	local UIS = game:GetService("UserInputService")
	local RunService = game:GetService("RunService")
	table.insert(
		self.conns,
		UIS.InputBegan:Connect(function(io: InputObject, processed: boolean)
			-- chat, text boxes and the Roblox menu own the keys while they are up; a click on a button is the
			-- button's, not a throw
			if InputMap.ignore(io, processed) then
				return
			end
			self:_key(io, true)
		end)
	)
	table.insert(
		self.conns,
		UIS.InputEnded:Connect(function(io: InputObject)
			self:_key(io, false)
		end)
	)
	table.insert(
		self.conns,
		UIS.InputChanged:Connect(function(io: InputObject, processed: boolean)
			if io.UserInputType == Enum.UserInputType.MouseMovement then
				self.mouseDx += io.Delta.X
			elseif io.UserInputType == Enum.UserInputType.MouseWheel and not InputMap.ignore(io, processed) then
				if self.canBowl then
					AimModel.hook(self.aim, if io.Position.Z > 0 then 1 else -1)
				end
			end
		end)
	)
	table.insert(
		self.conns,
		RunService.RenderStepped:Connect(function(dt: number)
			self:_frame(dt)
		end)
	)
	ctx.ui:touch({
		{ "left", "<" },
		{ "right", ">" },
		{ "aimL", "<<" },
		{ "aimR", ">>" },
		{ "hookL", "Hook L" },
		{ "hookR", "Hook R" },
		{ "bowl", "HOLD TO BOWL" },
	}, function(id)
		if id == "bowl" then
			self:_charge(true)
		elseif id == "hookL" or id == "hookR" then
			if self.canBowl then
				AimModel.hook(self.aim, if id == "hookL" then -1 else 1)
			end
		else
			self.held[id] = true
		end
	end, function(id)
		if id == "bowl" then
			self:_charge(false)
		else
			self.held[id] = nil
		end
	end)
	return self
end

function BowlingClient._key(self: any, io: InputObject, down: boolean)
	local name = io.KeyCode.Name
	if io.UserInputType == Enum.UserInputType.MouseButton1 then
		name = "MouseButton1"
	end
	if name == "Space" or name == "MouseButton1" or name == "ButtonR2" or name == "ButtonA" then
		self:_charge(down)
	elseif name == "A" or name == "DPadLeft" then
		self.held.left = down or nil
	elseif name == "D" or name == "DPadRight" then
		self.held.right = down or nil
	elseif name == "Left" then
		self.held.aimL = down or nil
	elseif name == "Right" then
		self.held.aimR = down or nil
	elseif down and self.canBowl and (name == "Z" or name == "ButtonL1") then
		AimModel.hook(self.aim, -1)
	elseif down and self.canBowl and (name == "X" or name == "ButtonR1") then
		AimModel.hook(self.aim, 1)
	end
end

-- The bowl button. Down starts the meter (only when it is your ball); letting go throws.
function BowlingClient._charge(self: any, down: boolean)
	if down and not self.canBowl then
		return
	end
	local params = AimModel.charge(self.aim, down)
	if params then
		if not self.canBowl then
			-- the turn moved on while the button was held: nothing is thrown
			AimModel.refused(self.aim)
			return
		end
		self.sentAt = BowlingClient.clock()
		self.slideT = 0
		self.ctx.send("release", { params.offset, params.angle, params.power, params.spin })
		self.ctx.ui:meter(nil)
	end
end

function BowlingClient._clearDots(self: any)
	for _, d in self.dots do
		d:Destroy()
	end
	table.clear(self.dots)
	self.dotSig = ""
end

function BowlingClient._drawDots(self: any)
	local aim = self.aim
	-- the line only changes when the aim does
	local sig = string.format(
		"%.4f %.5f %d %.2f",
		aim.offset,
		aim.angle,
		aim.notch,
		if aim.charging then AimModel.power(aim) else -1
	)
	if sig == self.dotSig then
		return
	end
	self.dotSig = sig
	local pts = AimModel.preview(aim)
	local cam = workspace.CurrentCamera
	for i, p in pts do
		local dot = self.dots[i]
		if dot == nil then
			dot = Instance.new("Part")
			dot.Name = "AimDot"
			dot.Anchored = true
			dot.CanCollide = false
			dot.CanQuery = false
			dot.CanTouch = false
			dot.CastShadow = false
			dot.Material = Enum.Material.Neon
			dot.Shape = Enum.PartType.Cylinder
			dot.Parent = cam
			self.dots[i] = dot
		end
		local s = if i <= 12 then 0.18 else 0.14
		dot.Size = Vector3.new(0.01, s, s)
		dot.Color = if p.hooked then Color3.fromRGB(255, 170, 60) else Color3.fromRGB(120, 230, 255)
		dot.Transparency = math.min(0.75, 0.15 + i * 0.025)
		dot.CFrame = CFrame.new(PartPose.world(self.place, self.lane, p.x, 0.012, p.d))
			* CFrame.Angles(0, 0, math.pi / 2)
	end
	for i = #pts + 1, #self.dots do
		self.dots[i]:Destroy()
		self.dots[i] = nil
	end
end

function BowlingClient._shot(self: any, shot: any)
	local eye = PartPose.world(self.place, self.lane, shot.ex, shot.ey, shot.ed)
	local look = PartPose.world(self.place, self.lane, shot.lx, shot.ly, shot.ld)
	-- a change of shot is a cut, not a swoop through the lane
	local cut = self.lastShot ~= nil and self.lastShot ~= shot.phase
	self.lastShot = shot.phase
	self.ctx.camera(CFrame.lookAt(eye, look), shot.fov, cut)
end

-- The bowler's body on the approach, facing down the line of the throw.
function BowlingClient._stand(self: any, forward: number)
	local body = self.ctx.body()
	local root = body and body.PrimaryPart
	if root then
		local aim = self.aim
		local at =
			PartPose.world(self.place, self.lane, aim.offset * (AlleyLayout.LANE_W / 2 - 0.5) - 0.35, 0, -4.4 + forward)
		local yaw = AlleyLayout.yawOf(self.place) - aim.angle
		root.CFrame = CFrame.new(at.X, root.Position.Y, at.Z) * CFrame.Angles(0, yaw, 0)
		root.AssemblyLinearVelocity = Vector3.zero
	end
end

function BowlingClient._frame(self: any, dt: number)
	local ctx = self.ctx
	local aim = self.aim
	local now = BowlingClient.clock()
	local UIS = game:GetService("UserInputService")
	local mouseDx = self.mouseDx
	self.mouseDx = 0
	-- a throw the server never answered: back to aiming, and say so
	if aim.phase == "sent" and now - self.sentAt > BowlingClient.SEND_TIMEOUT then
		AimModel.refused(aim)
		self.slideT = -1
		if ctx.toast then
			ctx.toast("Your throw did not reach the lane: aim and bowl again", 4)
		end
	end
	local aiming = self.canBowl and aim.phase ~= "watch"
	if aiming then
		local input: { [string]: any } = {
			left = self.held.left,
			right = self.held.right,
			aimL = self.held.aimL,
			aimR = self.held.aimR,
		}
		if UIS.MouseBehavior ~= Enum.MouseBehavior.Default then
			-- the cursor is locked (first person): its travel turns the angle
			input.mouseDx = mouseDx
		elseif UIS.MouseEnabled then
			local mp = UIS:GetMouseLocation()
			if self.lastMouse and (mp - self.lastMouse).Magnitude > 0.5 then
				input.mouseX01 = mp.X / math.max(1, workspace.CurrentCamera.ViewportSize.X)
			end
			self.lastMouse = mp
		end
		for _, state in UIS:GetGamepadState(Enum.UserInputType.Gamepad1) do
			if state.KeyCode == Enum.KeyCode.Thumbstick1 and math.abs(state.Position.X) > 0.2 then
				input.stickAim = state.Position.X
			end
		end
		AimModel.step(aim, input, dt)
		if aim.charging then
			ctx.ui:meter(AimModel.power(aim), AimModel.SWEET, AimModel.SWEET_TEXT)
		else
			ctx.ui:meter(nil)
		end
		ctx.ui:hook(aim.notch, AimModel.NOTCHES)
		if aim.phase == "aim" then
			self:_drawDots()
			self:_stand(0)
		end
		-- the turn clock, counted down between the server's once-a-second reports
		local left = if self.turnLeft then math.max(0, self.turnLeft - (now - self.turnLeftAt)) else nil
		ctx.ui:clock(left, AimModel.warning(left))
		ctx.ui:status(AimModel.statusText(aim, UIS.TouchEnabled and not UIS.KeyboardEnabled))
		self:_shot(Shots.aim(aim.offset, aim.angle))
	else
		if #self.dots > 0 then
			self:_clearDots()
		end
		ctx.ui:hook(nil)
		ctx.ui:clock(nil)
		self.lastMouse = nil
	end
	-- the slide to the line after letting go
	if self.slideT >= 0 then
		self.slideT += dt
		if self.slideT < 0.45 then
			self:_stand(3.2 * self.slideT / 0.45)
		else
			self.slideT = -1
		end
	end
	local watch = self.watch
	if watch then
		-- the throw: behind the ball, the cut to the pins, then back
		local t = now - watch.t0
		local shot = Shots.roll(watch.script, t)
		if shot.phase == "done" or t > BowlingClient.WATCH_LIMIT then
			self.watch = nil
		else
			self:_shot(shot)
		end
	elseif self.turnMine and not aiming then
		-- between your two balls (the pinsetter is working): look at the deck from behind the approach
		self:_shot(Shots.between())
	elseif not self.turnMine and self.controlsOff and self.slideT < 0 then
		-- your frame is over: your own camera and legs back
		self.controlsOff = false
		ctx.controls(true)
		ctx.releaseCamera()
	end
end

-- msg = the "state" payload: { view, you, ready }.
function BowlingClient.onState(self: any, msg: { [string]: any })
	local view = msg.view
	local aim = self.aim
	local turnMine = view.phase == "playing" and view.turn == msg.you
	local canBowl = turnMine and msg.ready == true
	if turnMine and not self.controlsOff then
		self.controlsOff = true
		self.ctx.controls(false)
	end
	if canBowl and (aim.phase == "watch" or not self.canBowl) and aim.phase ~= "sent" then
		-- the lane is set and it is your ball: aim (the line of your last ball is kept)
		AimModel.nextBall(aim)
	end
	if not turnMine and aim.phase == "sent" then
		AimModel.refused(aim) -- the turn moved on with a throw unanswered
	end
	self.turnMine = turnMine
	self.canBowl = canBowl
	self.turnLeft = view.turnLeft
	self.turnLeftAt = BowlingClient.clock()
	if not canBowl then
		local ui = self.ctx.ui
		if view.phase == "lobby" then
			ui:status(
				`Starting in {view.lobbyLeft or 0}... friends can walk up and press E. Space starts now; "Add a computer" for an opponent`
			)
		elseif view.phase == "playing" and view.turn then
			local s = view.seats[view.turn]
			if turnMine then
				ui:status(if self.watch then "There it goes..." else "Your turn: the pinsetter is setting up...")
			else
				ui:status(`{s and s.name or "?"} is bowling. You are next when the board shows your name. Q leaves.`)
			end
		elseif view.phase == "done" then
			ui:status(`Game over. Play again or Leave (Q). The lane resets in {view.doneLeft or 0}`)
		end
	end
end

-- A throw on this lane is being played. If it is the one you just sent, the camera goes with it.
function BowlingClient.onRoll(self: any, msg: { [string]: any }, script: any)
	local aim = self.aim
	if aim.phase == "sent" then
		AimModel.sent(aim)
		self.watch = { script = script, t0 = BowlingClient.clock() }
		self.ctx.ui:meter(nil)
		self:_clearDots()
	elseif self.turnMine and msg.seat == nil then
		-- a scripted pinfall on your turn (a developer's test roll): watch it too
		self.watch = { script = script, t0 = BowlingClient.clock() }
	end
end

-- The server refused something. If it was the throw, you are aiming again at once.
function BowlingClient.onRefused(self: any, msg: { [string]: any })
	if msg.verb == nil or msg.verb == "release" then
		AimModel.refused(self.aim)
		self.slideT = -1
	end
end

function BowlingClient.stop(self: any)
	for _, c in self.conns do
		c:Disconnect()
	end
	table.clear(self.conns)
	self:_clearDots()
	self.watch = nil
	local ui = self.ctx.ui
	ui:meter(nil)
	ui:hook(nil)
	ui:clock(nil)
end

return BowlingClient
