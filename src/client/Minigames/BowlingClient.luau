--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Minigames.BowlingClient
-- The bowler's side of a lane (brief v2 §13a "choose your angle and power, bowl"; owner D32). It is thin wiring:
-- the aiming state and every word on screen come from Shared/Minigames/Bowling/AimModel, the approach from
-- Bowling/Approach, the camera shots from Bowling/Shots, and the throw itself is drawn by BowlingPlayback from
-- the server's script.
-- On your turn your person waits at the back of the approach holding the ball (the server welds it to your
-- hand), the camera stands behind you, and the aim guide is on the lane: a glowing mark on the foul line where
-- the ball will leave your hand, a glowing chevron on the target arrow, and a dotted line through both down to
-- where the back end starts to bite (orange where a hook has begun to bend it). A / D step along the foul line
-- and Left / Right move the target, one board a press (held, smoothly); the mouse or the gamepad stick move the
-- target too; Z / X, the mouse wheel or
-- LB / RB put hook on; hold Space, the mouse button or R2 to run the power meter and let go: your person walks
-- four steps, swings the ball back and through, slides and lets go at the line (in the green band the ball goes
-- exactly where you aimed). Touch players get buttons for all of it. The camera rides behind the ball, cuts to
-- the pins a moment before it arrives, holds on the pinfall, then comes back for your next ball or hands your
-- own camera back. A turn clock counts down on screen before an idle turn is skipped. A throw the server
-- refuses, or that never reaches it, puts you straight back to aiming with a line on screen: input is never
-- swallowed. Typing in chat moves nothing.
-- The approach is drawn on your own body: its root's place (which everyone sees) and its joints (on your
-- screen: Motor6D C0, put back when it ends). A body without R15 joints still walks up and slides.
-- The SERVER decides the throw (D28): this sends { offset, angle, power, spin } once per ball, at the release.
-- Interface: new(ctx) -> Bowler; Bowler:onState(msg); Bowler:onRoll(msg, script); Bowler:onRefused(msg);
--   Bowler:stop(); bodyX(lane, offset) -> x (pure); HELP; SEND_TIMEOUT; WATCH_LIMIT; APPROACH (seconds from the
--   let-go to the release); clock (os.clock; a test swaps it)

local Import = require("../Import")
local AlleyLayout = Import.shared("Attractions/AlleyLayout") :: typeof(require("../../shared/Attractions/AlleyLayout"))
local AimModel =
	Import.shared("Minigames/Bowling/AimModel") :: typeof(require("../../shared/Minigames/Bowling/AimModel"))
local Approach =
	Import.shared("Minigames/Bowling/Approach") :: typeof(require("../../shared/Minigames/Bowling/Approach"))
local PartPose =
	Import.shared("Minigames/Bowling/PartPose") :: typeof(require("../../shared/Minigames/Bowling/PartPose"))
local Shots = Import.shared("Minigames/Bowling/Shots") :: typeof(require("../../shared/Minigames/Bowling/Shots"))
local InputMap = require("../Input/InputMap")

local BowlingClient = {}
BowlingClient.__index = BowlingClient

BowlingClient.HELP = AimModel.HELP
BowlingClient.SEND_TIMEOUT = 2.5 -- seconds to wait for the server to answer a throw before aiming again
BowlingClient.WATCH_LIMIT = 14 -- the roll camera can never be kept longer than this
BowlingClient.APPROACH = Approach.TIME
BowlingClient.BODY_CLEAR = AlleyLayout.HOOD_W / 2 + 1.05 -- the body's root keeps this far from its pair's ball return
-- the joints the approach turns (R15), with the pose field that turns each
BowlingClient.JOINTS = {
	{ "RightShoulder", "arm" },
	{ "LeftHip", "leadHip" },
	{ "LeftKnee", "leadKnee" },
	{ "RightHip", "trailHip" },
	{ "Waist", "waist" },
}
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
	self.approachT = -1 -- seconds into the approach (and its follow-through); -1 standing
	self.pending = nil :: { number }? -- the throw, waiting for the release at the end of the approach
	self.jointBase = {} :: { [Motor6D]: CFrame }
	self.marks = {} :: { [string]: BasePart }
	self.turnLeft = nil :: number?
	self.turnLeftAt = 0
	self.mouseDx = 0
	self.held = {} :: { [string]: number } -- step and aim keys down: since when
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
		{ "left", "Step <" },
		{ "right", "Step >" },
		{ "aimL", "Aim <" },
		{ "aimR", "Aim >" },
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
			self:_hold(id, true)
		end
	end, function(id)
		if id == "bowl" then
			self:_charge(false)
		else
			self:_hold(id, false)
		end
	end)
	return self
end

-- the step and aim keys: a press moves one board at once; held, they move smoothly after AimModel.REPEAT_AFTER
local NUDGE: { [string]: { any } } = {
	left = { "stand", -1 },
	right = { "stand", 1 },
	aimL = { "target", -1 },
	aimR = { "target", 1 },
}

function BowlingClient._hold(self: any, id: string, down: boolean)
	if not down then
		self.held[id] = nil
		return
	end
	if self.held[id] == nil then
		self.held[id] = BowlingClient.clock()
		local n = NUDGE[id]
		if n and self.canBowl then
			AimModel.nudge(self.aim, n[1], n[2])
		end
	end
end

-- is this step or aim key held long enough to move smoothly?
function BowlingClient._repeating(self: any, id: string, now: number): boolean?
	local since = self.held[id]
	return if since ~= nil and now - since >= AimModel.REPEAT_AFTER then true else nil
end

function BowlingClient._key(self: any, io: InputObject, down: boolean)
	local name = io.KeyCode.Name
	if io.UserInputType == Enum.UserInputType.MouseButton1 then
		name = "MouseButton1"
	end
	if name == "Space" or name == "MouseButton1" or name == "ButtonR2" or name == "ButtonA" then
		self:_charge(down)
	elseif name == "A" or name == "DPadLeft" then
		self:_hold("left", down)
	elseif name == "D" or name == "DPadRight" then
		self:_hold("right", down)
	elseif name == "Left" then
		self:_hold("aimL", down)
	elseif name == "Right" then
		self:_hold("aimR", down)
	elseif down and self.canBowl and (name == "Z" or name == "ButtonL1") then
		AimModel.hook(self.aim, -1)
	elseif down and self.canBowl and (name == "X" or name == "ButtonR1") then
		AimModel.hook(self.aim, 1)
	end
end

-- The bowl button. Down starts the meter (only when it is your ball); letting go starts the approach, and the
-- throw goes to the server at its release.
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
		self.pending = { params.offset, params.angle, params.power, params.spin }
		self.approachT = 0
		self.ctx.ui:meter(nil)
		self:_clearDots()
	end
end

-- The release, at the end of the approach.
function BowlingClient._release(self: any)
	local args = self.pending
	self.pending = nil
	if args == nil then
		return
	end
	if not self.canBowl or self.aim.phase ~= "sent" then
		-- the turn moved on during the approach: nothing is thrown
		AimModel.refused(self.aim)
		return
	end
	self.sentAt = BowlingClient.clock()
	self.ctx.send("release", args)
end

function BowlingClient._clearDots(self: any)
	for _, d in self.dots do
		d:Destroy()
	end
	table.clear(self.dots)
	for _, m in self.marks do
		m:Destroy()
	end
	table.clear(self.marks)
	self.dotSig = ""
end

-- One of the aim guide's glowing marks (made on this screen only, in the camera).
function BowlingClient._mark(self: any, name: string, size: Vector3, color: Color3): BasePart
	local m = self.marks[name]
	if m == nil then
		m = Instance.new("Part")
		m.Name = name
		m.Anchored = true
		m.CanCollide = false
		m.CanQuery = false
		m.CanTouch = false
		m.CastShadow = false
		m.Material = Enum.Material.Neon
		m.Size = size
		m.Color = color
		m.Transparency = 0.2
		m.Parent = workspace.CurrentCamera
		self.marks[name] = m
	end
	return m :: BasePart
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
	-- where the ball leaves the hand, and the target arrow (a chevron pointing at the pins)
	local yaw = AlleyLayout.yawOf(self.place)
	local stand = self:_mark("AimStand", Vector3.new(0.5, 0.02, 0.16), Color3.fromRGB(120, 230, 255))
	stand.CFrame = CFrame.new(PartPose.world(self.place, self.lane, AimModel.standX(aim), 0.012, -0.25))
		* CFrame.Angles(0, yaw, 0)
	local tx, td = AimModel.targetPoint(aim)
	for side = -1, 1, 2 do
		local arm = self:_mark(
			if side < 0 then "AimTargetL" else "AimTargetR",
			Vector3.new(0.07, 0.02, 0.5),
			Color3.fromRGB(255, 214, 92)
		)
		arm.CFrame = CFrame.new(PartPose.world(self.place, self.lane, tx + side * 0.1, 0.014, td - 0.18))
			* CFrame.Angles(0, yaw - side * 0.42, 0)
	end
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
		local s = if i <= 9 then 0.18 else 0.13
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
	-- to and from the pin shot is a cut (never a swoop the length of the lane); the other changes glide
	local last = self.lastShot
	local cut = last ~= nil and last ~= shot.phase and (last == "pins" or shot.phase == "pins")
	self.lastShot = shot.phase
	self.ctx.camera(CFrame.lookAt(eye, look), shot.fov, cut)
end

-- Where the body's root stands across the lane (from the lane's centre) for a stand on the line: the ball in
-- the right hand on the line, the body a little to its left, never into the pair's ball return.
function BowlingClient.bodyX(lane: number, offset: number): number
	local x = AlleyLayout.laneX(lane) + offset * (AlleyLayout.LANE_W / 2 - 0.5) - 0.35
	local px = AlleyLayout.pairX(AlleyLayout.pairOf(lane))
	local clear = BowlingClient.BODY_CLEAR
	if math.abs(x - px) < clear then
		x = px + (if AlleyLayout.sideOf(lane) < 0 then -clear else clear)
	end
	return x - AlleyLayout.laneX(lane)
end

-- The bowler's body on the approach, facing down the line of the throw, posed for the approach.
function BowlingClient._stand(self: any, pose: any)
	local body = self.ctx.body()
	local root = body and body.PrimaryPart
	if root then
		local aim = self.aim
		local at = PartPose.world(self.place, self.lane, BowlingClient.bodyX(self.lane, aim.offset), 0, pose.d)
		local yaw = AlleyLayout.yawOf(self.place) - aim.angle
		local y = self.standY or root.Position.Y
		self.standY = y
		root.CFrame = CFrame.new(at.X, y - pose.drop, at.Z) * CFrame.Angles(0, yaw, 0)
		root.AssemblyLinearVelocity = Vector3.zero
	end
	self:_pose(body, pose)
end

-- The approach's joints on this screen (C0 turned about the joint's own x; put back with pose nil).
function BowlingClient._pose(self: any, body: any, pose: any?)
	local base = self.jointBase
	for j, c0 in base do
		j.C0 = c0
	end
	table.clear(base)
	if body == nil or pose == nil then
		return
	end
	for _, jp in BowlingClient.JOINTS do
		local j = body:FindFirstChild(jp[1], true)
		local turn = pose[jp[2]]
		if j and j:IsA("Motor6D") and type(turn) == "number" and turn ~= 0 then
			base[j] = j.C0
			j.C0 = j.C0 * CFrame.Angles(turn, 0, 0)
		end
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
	if aim.phase == "sent" and self.pending == nil and now - self.sentAt > BowlingClient.SEND_TIMEOUT then
		AimModel.refused(aim)
		self:_endApproach()
		if ctx.toast then
			ctx.toast("Your throw did not reach the lane: aim and bowl again", 4)
		end
	end
	local aiming = self.canBowl and aim.phase ~= "watch"
	if aiming then
		local input: { [string]: any } = {
			left = self:_repeating("left", now),
			right = self:_repeating("right", now),
			aimL = self:_repeating("aimL", now),
			aimR = self:_repeating("aimR", now),
		}
		-- the mouse turns the aim by how far it moved (never by where it is, so a fine aim set with the arrow
		-- keys is not thrown away by a nudge): a locked cursor (first person) reports its travel, a free one
		-- is read from its position
		if UIS.MouseBehavior ~= Enum.MouseBehavior.Default then
			input.mouseDx = mouseDx
		elseif UIS.MouseEnabled then
			local mp = UIS:GetMouseLocation()
			if self.lastMouse then
				input.mouseDx = mp.X - self.lastMouse.X
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
			self:_stand(Approach.pose(0))
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
	-- the approach after letting go: four steps, the swing, the slide; the throw goes at the release
	if self.approachT >= 0 then
		self.approachT += dt
		if self.pending and self.approachT >= Approach.TIME then
			self:_release()
		end
		if self.approachT < Approach.TIME + Approach.FOLLOW and (self.pending or aim.phase ~= "aim") then
			self:_stand(Approach.pose(self.approachT))
		else
			self:_endApproach()
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
	elseif not self.turnMine and self.controlsOff and self.approachT < 0 then
		-- your frame is over: your own camera and legs back
		self.controlsOff = false
		ctx.controls(true)
		ctx.releaseCamera()
	end
end

-- Forget input from before a hand-over of the keys (the main client's rule: PossessionClient does the same
-- with input:flush() when a body changes hands). A key must be pressed again to count.
function BowlingClient._flush(self: any)
	table.clear(self.held)
	self.mouseDx = 0
	self.lastMouse = nil
	local aim = self.aim
	aim.charging = false
	aim.chargeT = 0
	self.ctx.ui:meter(nil)
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
	if turnMine and not self.turnMine then
		-- the keys have just become the lane's: one still held from the walk up, the lobby or the last frame
		-- is not a step along the foul line, and a meter left running is not this frame's throw
		self:_flush()
	end
	if canBowl and (aim.phase == "watch" or not self.canBowl) and aim.phase ~= "sent" then
		-- the lane is set and it is your ball: aim (the line of your last ball is kept)
		AimModel.nextBall(aim)
	end
	if not turnMine and aim.phase == "sent" then
		AimModel.refused(aim) -- the turn moved on with a throw unanswered
		self.pending = nil
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

-- A throw on this lane has been counted by the server and is being played. If it is the one you just sent,
-- the camera goes with it. script is nil when this client could not play it (a damaged table): the throw still
-- counted, so you stop waiting for an answer and watch the deck from the approach instead of riding the ball.
function BowlingClient.onRoll(self: any, msg: { [string]: any }, script: any?)
	local aim = self.aim
	local watch = if script ~= nil then { script = script, t0 = BowlingClient.clock() } else nil
	if aim.phase == "sent" then
		AimModel.sent(aim)
		self.watch = watch
		self.ctx.ui:meter(nil)
		self:_clearDots()
	elseif self.turnMine and msg.seat == nil then
		-- a scripted pinfall on your turn (a developer's test roll): watch it too
		self.watch = watch
	end
end

-- The server refused something. If it was the throw, you are aiming again at once.
function BowlingClient.onRefused(self: any, msg: { [string]: any })
	if msg.verb == nil or msg.verb == "release" then
		AimModel.refused(self.aim)
		self.pending = nil
		self:_endApproach()
	end
end

-- The approach is over (or cut short): the joints put back.
function BowlingClient._endApproach(self: any)
	self.approachT = -1
	self.standY = nil
	self:_pose(nil, nil)
end

function BowlingClient.stop(self: any)
	for _, c in self.conns do
		c:Disconnect()
	end
	table.clear(self.conns)
	self:_clearDots()
	self.pending = nil
	self:_endApproach()
	self.watch = nil
	local ui = self.ctx.ui
	ui:meter(nil)
	ui:hook(nil)
	ui:clock(nil)
end

return BowlingClient
