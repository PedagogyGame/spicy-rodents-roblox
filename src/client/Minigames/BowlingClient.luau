--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Minigames.BowlingClient
-- The bowler's side of a lane (brief v2 §13a "choose your angle and power, bowl"): on your turn your person steps
-- onto the approach holding the ball (the server welds it to your hand), the camera stands behind you looking
-- down the lane, a dotted aim line shows where the ball starts and where the hook takes it; A/D walk along the
-- foul line, the mouse (or Left/Right) turns the angle, Z/X put hook on, and holding Space or the mouse button
-- runs the power meter: let go to bowl (a short slide to the line). The camera rides behind the ball to the
-- pins, holds on the pin action, then comes back for your next ball. Waiting players keep their own camera
-- and controls and follow the score on screen. The SERVER rolls the ball and owns the pins (D28): this only
-- sends { offset, angle, power, spin } once.
-- Interface: new(ctx) -> Bowler; Bowler:onState(msg); Bowler:onEvent(msg); Bowler:onRolled(); Bowler:stop();
--   HELP; aimDots(offset, angle, spin, power, lane, place) -> { {X, D} } (pure)

local Import = require("../Import")
local AlleyLayout =
	Import.shared("Attractions/AlleyLayout") :: typeof(require("../../shared/Attractions/AlleyLayout"))

local BowlingClient = {}
BowlingClient.__index = BowlingClient

BowlingClient.HELP = {
	how = {
		"Ten frames each, up to four bowlers. Knock all ten down with the first ball for a STRIKE, with two for a SPARE.",
		"The scoreboard over the lane keeps score for everyone.",
	},
	keys = {
		"A / D  step left / right along the line",
		"Mouse (or Left / Right)  aim the angle",
		"Z / X  hook the ball left / right",
		"Hold Space or the mouse button: power meter",
		"Let go to bowl",
		"Q  leave the lane",
	},
}

BowlingClient.MAX_ANGLE = 0.1
BowlingClient.POWER_PERIOD = 1.5

-- Aim preview dots (local X across, D down-lane): straight along the angle, curving with the hook on the
-- back end (a picture of intent, not a simulation).
function BowlingClient.aimDots(offset: number, angle: number, spin: number, power: number, lane: number): { { number } }
	local rx, _, rd = AlleyLayout.release(lane, offset)
	local out = {}
	local d = 1.5
	while d <= 46 do
		local x = rx + math.tan(angle) * (d - rd)
		if d > 18 then
			local k = (d - 18) / 38
			x += spin * k * k * (2.2 - 1.2 * power)
		end
		table.insert(out, { x, d })
		d += if d < 20 then 1.6 else 3.2
	end
	return out
end

function BowlingClient.new(ctx: { [string]: any }): any
	local self = setmetatable({}, BowlingClient) :: any
	self.ctx = ctx
	self.lane = ctx.lane :: number
	self.place = ctx.place
	self.offset = 0
	self.angle = 0
	self.spin = 0
	self.charging = false
	self.chargeT = 0
	self.myTurn = false
	self.turnMine = false
	self.controlsOff = false
	self.sent = false
	self.watchUntil = 0
	self.slideT = -1
	self.held = {} :: { [string]: boolean }
	self.dots = {} :: { BasePart }
	self.conns = {} :: { RBXScriptConnection }
	local UIS = game:GetService("UserInputService")
	local RunService = game:GetService("RunService")
	table.insert(
		self.conns,
		UIS.InputBegan:Connect(function(io: InputObject, processed: boolean)
			if processed and io.UserInputType ~= Enum.UserInputType.Keyboard then
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
		RunService.RenderStepped:Connect(function(dt: number)
			self:_frame(dt)
		end)
	)
	ctx.ui:touch({ { "left", "<" }, { "right", ">" }, { "aimL", "<<" }, { "aimR", ">>" }, { "bowl", "HOLD TO BOWL" } }, function(id)
		self.held[id] = true
		if id == "bowl" then
			self:_charge(true)
		end
	end, function(id)
		self.held[id] = nil
		if id == "bowl" then
			self:_charge(false)
		end
	end)
	return self
end

function BowlingClient._key(self: any, io: InputObject, down: boolean)
	local k = io.KeyCode
	local name = k.Name
	if io.UserInputType == Enum.UserInputType.MouseButton1 then
		name = "MouseButton1"
	end
	if name == "Space" or name == "MouseButton1" or name == "ButtonR2" or name == "ButtonA" then
		self:_charge(down)
	elseif name == "A" then
		self.held.left = down or nil
	elseif name == "D" then
		self.held.right = down or nil
	elseif name == "Left" then
		self.held.aimL = down or nil
	elseif name == "Right" then
		self.held.aimR = down or nil
	elseif down and name == "Z" then
		self.spin = math.max(-1, self.spin - 0.5)
	elseif down and name == "X" then
		self.spin = math.min(1, self.spin + 0.5)
	end
end

function BowlingClient._charge(self: any, down: boolean)
	if down then
		if self.myTurn and not self.sent and not self.charging then
			self.charging = true
			self.chargeT = 0
		end
	elseif self.charging then
		self.charging = false
		if self.myTurn and not self.sent then
			self:_bowl()
		end
	end
end

local function powerAt(t: number): number
	local p = (t / BowlingClient.POWER_PERIOD) % 2
	return if p <= 1 then p else 2 - p
end

function BowlingClient._bowl(self: any)
	local power = powerAt(self.chargeT)
	self.sent = true
	self.sawBusy = false
	self.slideT = 0
	self.lastPower = power
	self.ctx.send("release", { self.offset, self.angle, power, self.spin })
	self.ctx.ui:meter(nil)
	self.watchUntil = os.clock() + 7
end

function BowlingClient._clearDots(self: any)
	for _, d in self.dots do
		d:Destroy()
	end
	table.clear(self.dots)
end

function BowlingClient._drawDots(self: any)
	local pts = BowlingClient.aimDots(self.offset, self.angle, self.spin, if self.charging then powerAt(self.chargeT) else 0.6, self.lane)
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
		local x, y, z = AlleyLayout.toWorld(self.place, p[1], 0.012, p[2])
		local s = if i <= 12 then 0.18 else 0.13
		dot.Size = Vector3.new(0.01, s, s)
		dot.Color = if p[2] > 18 and self.spin ~= 0 then Color3.fromRGB(255, 170, 60) else Color3.fromRGB(120, 230, 255)
		dot.Transparency = 0.15 + i * 0.03
		dot.CFrame = CFrame.new(x, y, z) * CFrame.Angles(0, 0, math.pi / 2)
	end
	for i = #pts + 1, #self.dots do
		self.dots[i]:Destroy()
		self.dots[i] = nil
	end
end

function BowlingClient._ball(self: any): BasePart?
	local att = workspace:FindFirstChild("Attractions")
	local alley = att and att:FindFirstChild("BowlingAlley")
	local lanes = alley and alley:FindFirstChild("Lanes")
	local lane = lanes and lanes:FindFirstChild(`Lane{self.lane}`)
	local ball = lane and lane:FindFirstChild("Ball")
	return if ball and ball:IsA("BasePart") then ball else nil
end

function BowlingClient._frame(self: any, dt: number)
	local ctx = self.ctx
	local now = os.clock()
	local UIS = game:GetService("UserInputService")
	if self.myTurn and not self.sent then
		local half = 1
		if self.held.left then
			self.offset = math.max(-half, self.offset - dt * 0.9)
		end
		if self.held.right then
			self.offset = math.min(half, self.offset + dt * 0.9)
		end
		local mouseMoved = false
		local mp = UIS:GetMouseLocation()
		if self.lastMouse and (mp - self.lastMouse).Magnitude > 0.5 then
			mouseMoved = true
		end
		self.lastMouse = mp
		if mouseMoved and not UIS.TouchEnabled then
			local vp = workspace.CurrentCamera.ViewportSize
			self.angle = math.clamp((mp.X / vp.X - 0.5) * 2, -1, 1) * BowlingClient.MAX_ANGLE
		end
		if self.held.aimL then
			self.angle = math.max(-BowlingClient.MAX_ANGLE, self.angle - dt * 0.06)
		end
		if self.held.aimR then
			self.angle = math.min(BowlingClient.MAX_ANGLE, self.angle + dt * 0.06)
		end
		if self.charging then
			self.chargeT += dt
			ctx.ui:meter(powerAt(self.chargeT), nil, "POWER - let go to bowl")
		else
			ctx.ui:meter(nil)
		end
		self:_drawDots()
		-- the person stands on the approach, facing the pins
		local body = ctx.body()
		local root = body and body.PrimaryPart
		if root then
			local X = AlleyLayout.laneX(self.lane) + self.offset * (AlleyLayout.LANE_W / 2 - 0.5)
			local x, _, z = AlleyLayout.toWorld(self.place, X + 0.35, 0, -4.4)
			local yaw = AlleyLayout.yawOf(self.place) - self.angle
			root.CFrame = CFrame.new(x, root.Position.Y, z) * CFrame.Angles(0, yaw, 0)
			root.AssemblyLinearVelocity = Vector3.zero
		end
		local spinText = if self.spin == 0 then "straight" elseif self.spin < 0 then "hook left" else "hook right"
		ctx.ui:status(`Your turn - aim with the mouse, hold Space to bowl ({spinText})`)
		-- camera: behind and above the bowler, down the lane
		local cx, cy, cz = AlleyLayout.toWorld(self.place, AlleyLayout.laneX(self.lane) + self.offset * 0.8, 5.6, -12.5)
		local lx, ly, lz = AlleyLayout.toWorld(self.place, AlleyLayout.laneX(self.lane) + math.tan(self.angle) * 30, 0.4, 38)
		ctx.camera(CFrame.lookAt(Vector3.new(cx, cy, cz), Vector3.new(lx, ly, lz)), 50)
	else
		if #self.dots > 0 then
			self:_clearDots()
		end
	end
	-- the slide to the line after letting go
	if self.slideT >= 0 then
		self.slideT += dt
		local body = ctx.body()
		local root = body and body.PrimaryPart
		if root and self.slideT < 0.45 then
			local X = AlleyLayout.laneX(self.lane) + self.offset * (AlleyLayout.LANE_W / 2 - 0.5)
			local x, _, z = AlleyLayout.toWorld(self.place, X + 0.35, 0, -4.4 + 3.2 * math.min(1, self.slideT / 0.45))
			root.CFrame = CFrame.new(x, root.Position.Y, z) * root.CFrame.Rotation
			root.AssemblyLinearVelocity = Vector3.zero
		elseif self.slideT >= 0.45 then
			self.slideT = -1
		end
	end
	-- after the release: ride behind the ball, then hold on the pins
	if self.sent and now < self.watchUntil then
		local ball = self:_ball()
		if ball then
			local p = ball.Position
			local _, _, D = AlleyLayout.toLocal(self.place, p.X, p.Y, p.Z)
			local fx, fz = AlleyLayout.dirToWorld(self.place, 0, 1)
			local fwd = Vector3.new(fx, 0, fz)
			local laneMid = Vector3.new(AlleyLayout.toWorld(self.place, AlleyLayout.laneX(self.lane), 0.8, AlleyLayout.HEAD_D + 1.5))
			if D < 40 and D > -2 then
				ctx.camera(CFrame.lookAt(p - fwd * 7 + Vector3.new(0, 2.6, 0), p + fwd * 12), 55)
			else
				local hx, hy, hz = AlleyLayout.toWorld(self.place, AlleyLayout.laneX(self.lane), 3.2, 44)
				ctx.camera(CFrame.lookAt(Vector3.new(hx, hy, hz), laneMid), 45)
			end
		end
	elseif not self.turnMine and self.controlsOff and self.slideT < 0 then
		-- your frame is over: your own camera and legs back
		self.controlsOff = false
		ctx.controls(true)
		ctx.releaseCamera()
	elseif self.turnMine and not self.myTurn and not (self.sent and now < self.watchUntil) then
		-- between balls (the pinsetter is working): look at the pins from behind the approach
		local cx, cy, cz = AlleyLayout.toWorld(self.place, AlleyLayout.laneX(self.lane), 5.6, -12.5)
		local lx, ly, lz = AlleyLayout.toWorld(self.place, AlleyLayout.laneX(self.lane), 0.4, 50)
		ctx.camera(CFrame.lookAt(Vector3.new(cx, cy, cz), Vector3.new(lx, ly, lz)), 50)
	end
end

-- msg = the "state" payload: { view, you, ready }. turnMine: it is your frame; canBowl: and the lane is set.
function BowlingClient.onState(self: any, msg: { [string]: any })
	local view = msg.view
	local turnMine = view.phase == "playing" and view.turn == msg.you
	local canBowl = turnMine and msg.ready == true
	if turnMine and not self.controlsOff then
		self.controlsOff = true
		self.ctx.controls(false)
	end
	if msg.ready ~= true then
		self.sawBusy = true
	end
	if canBowl and self.sent and self.sawBusy then
		-- the lane is set again: the next ball of your frame
		self.sent = false
		self.charging = false
	end
	self.turnMine = turnMine
	self.myTurn = canBowl
	if not canBowl then
		if view.phase == "lobby" then
			self.ctx.ui:status(`Starting in {view.lobbyLeft or 0}... friends can walk up and press E (Space: start now)`)
		elseif view.phase == "playing" and view.turn then
			local s = view.seats[view.turn]
			if turnMine then
				self.ctx.ui:status("Your turn: the pinsetter is setting up...")
			else
				self.ctx.ui:status(`{s and s.name or "?"} is bowling`)
			end
		elseif view.phase == "done" then
			self.ctx.ui:status(`Game over. Play again or leave (Q). The lane resets in {view.doneLeft or 0}`)
		end
	end
end

-- a roll's result: hold the pin view a moment longer, then come back
function BowlingClient.onEvent(self: any, msg: { [string]: any })
	if msg.pins ~= nil and self.sent then
		self.watchUntil = math.min(self.watchUntil, os.clock() + 1.6)
	end
end

function BowlingClient.onRolled(self: any)
	if self.sent then
		self.watchUntil = os.clock() + 9
	end
end

function BowlingClient.stop(self: any)
	for _, c in self.conns do
		c:Disconnect()
	end
	table.clear(self.conns)
	self:_clearDots()
	self.ctx.ui:meter(nil)
end

return BowlingClient
