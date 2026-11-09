--!strict
-- ServerScriptService.Server.Minigames.BowlingLane
-- One bowling lane's hardware (brief v2 §13a: "choose your angle and power, bowl, physics pins, the ball returns
-- up the rack"; BUILD_PLAN D28): the baked ball and ten composite pins (tools/bake/alley/Lanes) become physics
-- parts the SERVER owns for the whole roll (D28's first pattern: one simulator per turn, every part on the
-- server, nothing replayed; the bowler's client predicts nothing, it only shows the ball in hand and the aim
-- line). Why server authority here: a lane is watched by up to four bowlers and the settees, a roll has no
-- steering after release so 100-150 ms of input latency is invisible, pins and ball never change owner
-- mid-collision (FE-3), and the pin count is read from the same simulation everyone saw.
-- The roll: release (offset across the foul line, angle, power, hook) -> the ball rolls (a lateral hook force on
-- the back end) -> pins fall under a slightly softened gravity (VectorForce; Roblox's 196 st/s^2 is about five
-- times real at this scale) -> once the ball is in the pit and the pins rest, standing pins are counted (upright
-- within 20 degrees, still on the deck) -> the service scores it -> the pinsetter cycles (sweep bar down,
-- standing pins lifted, deadwood swept, pins set back or a fresh rack lowered) while the ball runs back through
-- the ball-return duct under the lane (the same curve as the squirrel tunnel) and up onto the rack.
-- No physics in Luau Execution: debugRoll(n) knocks n pins over by hand and the rest of the cycle is the same.
-- Interface: new(opts) -> Lane; Lane:ready() -> bool; Lane:release(params) -> (ok, why?); Lane:step(dt);
--   Lane:takeResult() -> pinsDown?; Lane:setRack(rack, instant?); Lane:reset(instant?); Lane:debugRoll(n);
--   Lane:hold(body?) (ball in the bowler's hand or back on the rack); Lane:standingMask() -> { bool };
--   Lane.state; RANGES

local Import = require("../Import")
local AlleyLayout = Import.shared("Attractions/AlleyLayout") :: typeof(require("../../shared/Attractions/AlleyLayout"))
local Curve = Import.shared("Routes/Curve") :: typeof(require("../../shared/Routes/Curve"))

local BowlingLane = {}
BowlingLane.__index = BowlingLane

BowlingLane.RANGES = {
	angle = 0.1, -- radians either side of straight
	speedMin = 16, -- studs/s at zero power
	speedMax = 34,
	hook = 9, -- studs/s^2 of lateral pull at full hook on the back end
}
BowlingLane.EFFECTIVE_GRAVITY = 85 -- studs/s^2 felt by the ball and pins (VectorForce lifts the rest)
BowlingLane.STAND_COS = math.cos(math.rad(20))
BowlingLane.MAX_ROLL = 8
BowlingLane.SETTLE_MIN = 1.2
BowlingLane.SETTLE_MAX = 4.5
BowlingLane.SET_TIME = 2.6
BowlingLane.RETURN_TIME = 3.4

export type Params = { offset: number, angle: number, power: number, spin: number }

type Pin = {
	model: Model,
	body: BasePart,
	parts: { BasePart },
	transparency: { [BasePart]: number },
	collide: { [BasePart]: boolean },
	home: CFrame,
	up: boolean, -- standing in the current rack (before this ball)
	hidden: boolean,
	force: VectorForce?,
}

type Anim = { t0: number, t1: number, fn: (a: number) -> (), done: boolean }

local function smooth(a: number): number
	a = math.clamp(a, 0, 1)
	return a * a * (3 - 2 * a)
end

function BowlingLane.new(opts: { [string]: any }): any
	local model: Model = opts.model
	local place = opts.place
	local lane: number = opts.lane
	local self = setmetatable({}, BowlingLane) :: any
	self.lane = lane
	self.model = model
	self.place = place
	self.physics = opts.physics ~= false
	self.state = "ready"
	self.clock = 0
	self.anims = {} :: { Anim }
	self.result = nil :: number?
	self.ball = model:FindFirstChild("Ball") :: BasePart
	self.sweep = model:FindFirstChild("Sweep") :: BasePart?
	self.sweepEdge = model:FindFirstChild("SweepEdge") :: BasePart?
	self.sweepHome = if self.sweep then self.sweep.CFrame else nil
	self.edgeHome = if self.sweepEdge then self.sweepEdge.CFrame else nil
	self.pins = {} :: { Pin }
	local pinsFolder = model:FindFirstChild("Pins")
	for n = 1, 10 do
		local pm = pinsFolder and pinsFolder:FindFirstChild(`Pin{n}`) :: Model?
		if pm then
			local body = (pm.PrimaryPart or pm:FindFirstChild("Body")) :: BasePart
			local parts = {}
			local tr, cc = {}, {}
			for _, d in pm:GetDescendants() do
				if d:IsA("BasePart") then
					table.insert(parts, d)
					tr[d] = d.Transparency
					cc[d] = d.CanCollide
					if d ~= body and not d:FindFirstChildOfClass("WeldConstraint") then
						-- make sure every part is welded to the body (the bake does it; a hand-built pin might not)
						local found = false
						for _, w in body:GetChildren() do
							if w:IsA("WeldConstraint") and (w.Part1 == d or w.Part0 == d) then
								found = true
							end
						end
						if not found then
							local w = Instance.new("WeldConstraint")
							w.Part0 = body
							w.Part1 = d
							w.Parent = body
						end
					end
					if not d.Massless then
						d.CustomPhysicalProperties = PhysicalProperties.new(0.9, 0.24, 0.42, 1, 1)
					end
				end
			end
			table.insert(self.pins, {
				model = pm,
				body = body,
				parts = parts,
				transparency = tr,
				collide = cc,
				home = pm:GetPivot(),
				up = true,
				hidden = false,
				force = nil,
			})
		end
	end
	if self.ball then
		self.ball.CustomPhysicalProperties = PhysicalProperties.new(1.7, 0.12, 0.15, 1, 1)
		self.rackCF = self.ball.CFrame
	end
	-- ball return path (world): pit -> down into the duct -> the tunnel route back to the hood -> the rack slot
	self.returnCurve = nil
	local tunnel = opts.tunnel :: { { number } }?
	if tunnel then
		local r = AlleyLayout.BALL_D / 2
		local pts = {}
		local function push(X: number, Y: number, D: number)
			local x, y, z = AlleyLayout.toWorld(place, X, Y, D)
			table.insert(pts, Curve.vec3(x, y, z))
		end
		local px = AlleyLayout.pairX(AlleyLayout.pairOf(lane))
		local side = AlleyLayout.sideOf(lane)
		local liftX = AlleyLayout.laneX(lane) - side * (AlleyLayout.LANE_W / 2 + AlleyLayout.GUTTER_W - 0.5)
		push(liftX, AlleyLayout.PIT_Y + r, AlleyLayout.CUSHION_D - 0.8)
		push((liftX + px) / 2, AlleyLayout.PIT_Y - 0.6, AlleyLayout.CUSHION_D - 1.2)
		push(px, AlleyLayout.DUCT_FLOOR + 0.14 + r, AlleyLayout.CUSHION_D - 2)
		for _, p in tunnel do
			local _, _, D = AlleyLayout.toLocal(place, p[1], p[2], p[3])
			if D < AlleyLayout.CUSHION_D - 3 then
				table.insert(pts, Curve.vec3(p[1], p[2] + r + (if D > AlleyLayout.SHAFT_D1 then 0.14 else 0), p[3]))
			end
		end
		local sx, sy, sd = AlleyLayout.rackSlot(lane)
		push(sx, sy + 0.1, AlleyLayout.HOOD_D1 - 0.3)
		push(sx, sy, sd)
		self.returnCurve = Curve.new(pts)
	end
	self:reset(true)
	return self
end

-- Pins --------------------------------------------------------------------------------------------------------
local function setVisible(pin: Pin, on: boolean)
	pin.hidden = not on
	for _, p in pin.parts do
		p.Transparency = if on then pin.transparency[p] else 1
		p.CanCollide = if on then pin.collide[p] else false
	end
end

local function anchorPin(pin: Pin, on: boolean)
	pin.body.Anchored = on
	for _, p in pin.parts do
		p.Anchored = on
	end
end

function BowlingLane._release(_self: any, pin: Pin)
	anchorPin(pin, false)
	local body = pin.body
	pcall(function()
		body:SetNetworkOwner(nil)
	end)
	if pin.force == nil then
		local att = Instance.new("Attachment")
		att.Name = "LiftAttachment"
		att.Parent = body
		local vf = Instance.new("VectorForce")
		vf.Name = "Lift"
		vf.Attachment0 = att
		vf.RelativeTo = Enum.ActuatorRelativeTo.World
		vf.ApplyAtCenterOfMass = true
		vf.Parent = body
		pin.force = vf
	end
	local mass = 0
	for _, p in pin.parts do
		if not p.Massless then
			mass += p:GetMass()
		end
	end
	local g = workspace.Gravity;
	(pin.force :: VectorForce).Force = Vector3.new(0, mass * math.max(0, g - BowlingLane.EFFECTIVE_GRAVITY), 0)
end

local function upright(pin: Pin): boolean
	return pin.body.CFrame.UpVector.Y >= BowlingLane.STAND_COS
end

-- Standing after the roll: upright, still on the deck (not in the pit, gutter or the next lane).
function BowlingLane.isStanding(self: any, pin: Pin): boolean
	if pin.hidden then
		return false
	end
	local p = pin.body.Position
	local X, Y, D = AlleyLayout.toLocal(self.place, p.X, p.Y, p.Z)
	local lx = AlleyLayout.laneX(self.lane)
	local onDeck = D > AlleyLayout.DECK_START - 1.5
		and D < AlleyLayout.DECK_END + 0.05
		and math.abs(X - lx) < AlleyLayout.LANE_W / 2 + 0.15
		and Y > -0.2
	return onDeck and upright(pin)
end

function BowlingLane.standingMask(self: any): { boolean }
	local out = {}
	for i, pin in self.pins do
		out[i] = pin.up
	end
	return out
end

function BowlingLane.ready(self: any): boolean
	return self.state == "ready"
end

-- Ball ---------------------------------------------------------------------------------------------------------
local function park(ball: BasePart, cf: CFrame)
	ball.Anchored = true
	ball.AssemblyLinearVelocity = Vector3.zero
	ball.AssemblyAngularVelocity = Vector3.zero
	ball.CFrame = cf
end

-- hold(body?): the ball in the bowler's hand (a welded, non-physical copy everyone sees) or back on the rack.
function BowlingLane.hold(self: any, body: Model?)
	local held = self.held :: BasePart?
	if held then
		held:Destroy()
		self.held = nil
	end
	local ball = self.ball :: BasePart?
	if ball == nil then
		return
	end
	if body == nil or self.state ~= "ready" then
		if self.state == "ready" then
			ball.Transparency = 0
		end
		return
	end
	local hand = body:FindFirstChild("RightHand") or body:FindFirstChild("Right Arm") or body.PrimaryPart
	if hand == nil or not hand:IsA("BasePart") then
		return
	end
	local copy = ball:Clone()
	for _, c in copy:GetChildren() do
		c:Destroy() -- no lift force or attachment on the copy (it would push the bowler)
	end
	copy.Name = "HeldBall"
	copy.Anchored = false
	copy.CanCollide = false
	copy.CanQuery = false
	copy.CanTouch = false
	copy.Massless = true
	copy.Transparency = 0
	local offset = if hand.Name == "RightHand" or hand.Name == "Right Arm"
		then CFrame.new(0, -0.5, -0.1)
		else CFrame.new(1.1, -0.8, -0.5)
	copy.CFrame = (hand :: BasePart).CFrame * offset
	local w = Instance.new("WeldConstraint")
	w.Part0 = hand :: BasePart
	w.Part1 = copy
	w.Parent = copy
	copy.Parent = self.model
	self.held = copy
	ball.Transparency = 1
end

-- release: the roll starts. params are clamped here (the client's numbers are only bounds-checked: no stakes).
function BowlingLane.release(self: any, p: Params): (boolean, string?)
	if self.state ~= "ready" then
		return false, "the lane is not ready"
	end
	local ball = self.ball :: BasePart?
	if ball == nil then
		return false, "no ball"
	end
	local R = BowlingLane.RANGES
	local offset = math.clamp(tonumber(p.offset) or 0, -1, 1)
	local angle = math.clamp(tonumber(p.angle) or 0, -R.angle, R.angle)
	local power = math.clamp(tonumber(p.power) or 0.5, 0, 1)
	local spin = math.clamp(tonumber(p.spin) or 0, -1, 1)
	self:hold(nil)
	local X, Y, D = AlleyLayout.release(self.lane, offset)
	local x, y, z = AlleyLayout.toWorld(self.place, X, Y, D)
	local dxW, dzW = AlleyLayout.dirToWorld(self.place, math.sin(angle), math.cos(angle))
	local dir = Vector3.new(dxW, 0, dzW).Unit
	local speed = R.speedMin + (R.speedMax - R.speedMin) * power
	ball.Transparency = 0
	ball.CanCollide = true
	ball.CFrame = CFrame.new(x, y, z)
	self.roll = {
		t = 0,
		spin = spin,
		dir = dir,
		slow = 0,
		inPit = false,
		speed = speed,
		offset = offset,
		angle = angle,
		power = power,
	}
	self.result = nil
	self.state = "rolling"
	if self.physics then
		ball.Anchored = false
		pcall(function()
			ball:SetNetworkOwner(nil)
		end)
		local r = ball.Size.X / 2
		ball.AssemblyLinearVelocity = dir * speed
		ball.AssemblyAngularVelocity = Vector3.new(0, 1, 0):Cross(dir * speed) / r
		local mass = ball:GetMass()
		if self.ballForce == nil then
			local att = Instance.new("Attachment")
			att.Parent = ball
			local vf = Instance.new("VectorForce")
			vf.Attachment0 = att
			vf.RelativeTo = Enum.ActuatorRelativeTo.World
			vf.ApplyAtCenterOfMass = true
			vf.Parent = ball
			self.ballForce = vf
		end
		self.ballMass = mass
		self.ballForce.Force = Vector3.new(0, mass * math.max(0, workspace.Gravity - BowlingLane.EFFECTIVE_GRAVITY), 0)
		for _, pin in self.pins do
			if pin.up and not pin.hidden then
				BowlingLane._release(self, pin)
			end
		end
	end
	return true
end

-- debugRoll(n): knock over the first n standing pins by hand (Luau Execution has no physics); the cycle then
-- runs exactly as after a real roll.
function BowlingLane.debugRoll(self: any, n: number): (boolean, string?)
	if self.state ~= "ready" then
		return false, "the lane is not ready"
	end
	self:hold(nil)
	local down = 0
	for _, pin in self.pins do
		if down >= n then
			break
		end
		if pin.up and not pin.hidden then
			anchorPin(pin, true)
			local p = pin.body.Position
			pin.model:PivotTo(CFrame.new(p.X, p.Y - 0.35, p.Z) * CFrame.Angles(math.pi / 2, 0, 0))
			down += 1
		end
	end
	self.roll = nil
	self.state = "counted"
	self.result = self:_count()
	return true
end

function BowlingLane._count(self: any): number
	local down = 0
	for _, pin in self.pins do
		if pin.up then
			if self:isStanding(pin) then
				pin.stillUp = true
			else
				pin.stillUp = false
				down += 1
			end
		else
			pin.stillUp = false
		end
	end
	return down
end

function BowlingLane.takeResult(self: any): number?
	if self.state == "counted" and self.result ~= nil then
		local r = self.result
		self.result = nil
		self.state = "scored"
		return r
	end
	return nil
end

-- Animations ---------------------------------------------------------------------------------------------------
function BowlingLane._anim(self: any, t0: number, t1: number, fn: (a: number) -> ())
	table.insert(self.anims, { t0 = self.clock + t0, t1 = self.clock + t1, fn = fn, done = false })
end

local function sweepAt(self: any, y: number, d: number)
	local sweep, edge = self.sweep :: BasePart?, self.sweepEdge :: BasePart?
	if sweep == nil or self.sweepHome == nil then
		return
	end
	local hx, hy, hd = AlleyLayout.toLocal(self.place, self.sweepHome.X, self.sweepHome.Y, self.sweepHome.Z)
	local _ = hx
	local dx, dz = AlleyLayout.dirToWorld(self.place, 0, d - hd)
	local delta = Vector3.new(dx, y - hy, dz)
	sweep.CFrame = self.sweepHome + delta
	if edge and self.edgeHome then
		edge.CFrame = self.edgeHome + delta
	end
end

-- setRack: the pinsetter cycle for the next ball ("full": a fresh rack of ten; "keep": standing pins back where
-- they stood, deadwood swept) and the ball's run back to the rack.
function BowlingLane.setRack(self: any, rack: string, instant: boolean?)
	local up: { boolean } = {}
	for i, pin in self.pins do
		up[i] = if rack == "full" then true else (pin.stillUp == true)
	end
	if instant then
		for i, pin in self.pins do
			anchorPin(pin, true)
			if up[i] then
				setVisible(pin, true)
				if rack == "full" or not pin.stillUp then
					pin.model:PivotTo(pin.home)
				else
					local p = pin.body.Position
					pin.model:PivotTo(pin.home.Rotation + Vector3.new(p.X, pin.home.Y, p.Z))
				end
			else
				setVisible(pin, false)
				pin.model:PivotTo(pin.home)
			end
			pin.up = up[i]
		end
		if self.ball then
			park(self.ball, self.rackCF)
			self.ball.Transparency = 0
		end
		sweepAt(self, AlleyLayout.MASK_BOTTOM + 0.4, AlleyLayout.DECK_START - 0.05)
		self.state = "ready"
		return
	end
	self.state = "setting"
	local T = BowlingLane.SET_TIME
	local low, rest = 0.7, AlleyLayout.MASK_BOTTOM + 0.4
	local d0, d1 = AlleyLayout.DECK_START - 0.6, AlleyLayout.CUSHION_D - 0.5
	-- freeze everything where it lies
	local from: { [Pin]: CFrame } = {}
	for _, pin in self.pins do
		anchorPin(pin, true)
		from[pin] = pin.model:GetPivot()
	end
	self:_anim(0, 0.5, function(a)
		sweepAt(self, rest + (low - rest) * smooth(a), d0)
	end)
	-- standing pins rise into the machine
	for i, pin in self.pins do
		if pin.stillUp and rack == "keep" then
			local start = from[pin]
			local upCF = pin.home.Rotation + Vector3.new(start.X, pin.home.Y, start.Z)
			self:_anim(0.3, 0.9, function(a)
				pin.model:PivotTo(start:Lerp(upCF + Vector3.new(0, 2.4, 0), smooth(a)))
			end)
			self:_anim(1.6, 2.2, function(a)
				pin.model:PivotTo((upCF + Vector3.new(0, 2.4, 0)):Lerp(upCF, smooth(a)))
			end)
		else
			-- deadwood (and, for a full rack, everything): swept off as the bar passes
			self:_anim(0.5, 1.3, function(a)
				if a > 0.35 and not pin.hidden then
					setVisible(pin, false)
				end
			end)
			if up[i] then
				-- a fresh pin lowered onto its spot
				self:_anim(1.4, 2.2, function(a)
					if pin.hidden then
						setVisible(pin, true)
					end
					pin.model:PivotTo(pin.home + Vector3.new(0, 2.4 * (1 - smooth(a)), 0))
				end)
			end
		end
	end
	self:_anim(0.5, 1.3, function(a)
		sweepAt(self, low, d0 + (d1 - d0) * smooth(a))
	end)
	self:_anim(1.3, 1.8, function(a)
		sweepAt(self, low, d1 + (d0 - d1) * smooth(a))
	end)
	self:_anim(2.2, T, function(a)
		sweepAt(self, low + (rest - low) * smooth(a), d0)
	end)
	-- the ball's run home
	local ball = self.ball :: BasePart?
	if ball and self.returnCurve then
		park(ball, ball.CFrame)
		local curve = self.returnCurve
		self:_anim(0.2, 0.2 + BowlingLane.RETURN_TIME, function(a)
			local p = curve:getPointAt(0.5 * (a + smooth(a)))
			ball.CFrame = CFrame.new(p.x, p.y, p.z) * ball.CFrame.Rotation * CFrame.Angles(0.35, 0, 0)
		end)
		self:_anim(0.2 + BowlingLane.RETURN_TIME, 0.4 + BowlingLane.RETURN_TIME, function(a)
			if a >= 1 then
				park(ball, self.rackCF)
			end
		end)
	elseif ball then
		park(ball, self.rackCF)
	end
	self.pendingUp = up
	self.setEnds = self.clock + math.max(T, 0.4 + BowlingLane.RETURN_TIME)
end

function BowlingLane.reset(self: any, instant: boolean?)
	for _, pin in self.pins do
		pin.stillUp = false
	end
	self.anims = {}
	self.roll = nil
	self.result = nil
	self:hold(nil)
	self:setRack("full", if instant == nil then true else instant)
end

-- Per frame ----------------------------------------------------------------------------------------------------
function BowlingLane.step(self: any, dt: number)
	self.clock += dt
	-- animations
	if #self.anims > 0 then
		local keep = {}
		for _, an in self.anims do
			if self.clock >= an.t0 then
				local a = if an.t1 > an.t0 then (self.clock - an.t0) / (an.t1 - an.t0) else 1
				an.fn(math.clamp(a, 0, 1))
				if a >= 1 then
					an.done = true
				end
			end
			if not an.done then
				table.insert(keep, an)
			end
		end
		self.anims = keep
	end
	if self.state == "setting" and self.clock >= (self.setEnds or 0) and #self.anims == 0 then
		local up = self.pendingUp or {}
		for i, pin in self.pins do
			pin.up = up[i] == true
			pin.stillUp = false
		end
		self.state = "ready"
	elseif self.state == "rolling" then
		local roll = self.roll
		local ball = self.ball :: BasePart
		roll.t += dt
		local p = ball.Position
		local X, Y, D = AlleyLayout.toLocal(self.place, p.X, p.Y, p.Z)
		local _ = X
		if self.physics and self.ballForce then
			local lift = self.ballMass * math.max(0, workspace.Gravity - BowlingLane.EFFECTIVE_GRAVITY)
			local hook = 0
			if roll.spin ~= 0 and D > 18 and D < AlleyLayout.DECK_START and Y > -0.1 then
				hook = roll.spin * BowlingLane.RANGES.hook * math.clamp((D - 18) / 20, 0, 1) * self.ballMass
			end
			local rx, rz = AlleyLayout.dirToWorld(self.place, 1, 0)
			self.ballForce.Force = Vector3.new(rx * hook, lift, rz * hook)
		end
		local speed = ball.AssemblyLinearVelocity.Magnitude
		if D > AlleyLayout.DECK_END + 0.4 or Y < -0.9 then
			roll.inPit = true
		end
		if speed < 0.5 then
			roll.slow += dt
		else
			roll.slow = 0
		end
		if roll.inPit or roll.slow > 1.2 or roll.t > BowlingLane.MAX_ROLL or not self.physics then
			self.state = "settling"
			self.settle = 0
		end
	elseif self.state == "settling" then
		self.settle += dt
		local resting = true
		for _, pin in self.pins do
			if pin.up and not pin.hidden and not pin.body.Anchored then
				if
					pin.body.AssemblyLinearVelocity.Magnitude > 0.3
					or pin.body.AssemblyAngularVelocity.Magnitude > 0.6
				then
					resting = false
				end
			end
		end
		if (self.settle > BowlingLane.SETTLE_MIN and resting) or self.settle > BowlingLane.SETTLE_MAX then
			self.result = self:_count()
			self.state = "counted"
		end
	end
end

return BowlingLane
