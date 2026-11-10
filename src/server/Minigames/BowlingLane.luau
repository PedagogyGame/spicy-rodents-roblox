--!strict
-- ServerScriptService.Server.Minigames.BowlingLane
-- One bowling lane's hardware (brief v2 §13a: "choose your angle and power, bowl ... the ball returns up the
-- rack"; BUILD_PLAN D28): the baked ball, ten composite pins and the sweep bar (tools/bake/alley/Lanes) are
-- ANCHORED parts this module moves; nothing here is Roblox physics. A throw is decided the moment it is
-- released by the pure models in Shared/Minigames/Bowling (BallPath for the ball's line, PinModel for the
-- pins; one RollScript table per throw), so the pin count is the same on every machine, repeats from a seed,
-- and exists in the cloud checks where there is no physics. This module is the thin applier: it owns a
-- LaneCycle (ready -> rolling -> counted -> setting -> ready) and writes the poses that gives onto the parts:
-- the ball down the lane and into the pit, pins tipping and sliding, the sweep bar, kept pins lifted and set
-- back or a fresh rack lowered, and the ball's run home through the return duct (the squirrel tunnel's curve)
-- up onto the rack. Clients play the same RollScript at their own frame rate (Client/Minigames/
-- BowlingPlayback), so the server only writes the roll at ROLL_WRITE_HZ: enough for a late joiner or a client
-- whose playback failed, without flooding replication.
-- Why the server decides: a lane is watched by up to four bowlers and the settees, a roll has no steering
-- after release so input latency is invisible, and the score must be what everyone saw.
-- Interface: new(opts) -> Lane; Lane:ready() -> bool; Lane:release(params, seat?, seed) -> (ok, why?, script?);
--   Lane:debugRoll(n, seat?) -> (ok, why?, script?) (n pins tip over: the engine smoke's stand-in);
--   Lane:step(dt) -> { event }; Lane:takeResult() -> { pins, seat, standing, flags }?; Lane:setRack(rack,
--   instant?); Lane:reset(instant?); Lane:hold(body?) (ball in the bowler's hand or back on the rack);
--   Lane:standingMask() -> { bool }; Lane:standingCount(); Lane:script() -> RollScript?; Lane:scriptTime() ->
--   t?; Lane:sweep() -> (d, low) while the pinsetter runs; Lane.state; Lane.ball; RANGES; ROLL_WRITE_HZ

local Import = require("../Import")
local AlleyLayout = Import.shared("Attractions/AlleyLayout") :: typeof(require("../../shared/Attractions/AlleyLayout"))
local Curve = Import.shared("Routes/Curve") :: typeof(require("../../shared/Routes/Curve"))
local BallPath =
	Import.shared("Minigames/Bowling/BallPath") :: typeof(require("../../shared/Minigames/Bowling/BallPath"))
local LaneCycle =
	Import.shared("Minigames/Bowling/LaneCycle") :: typeof(require("../../shared/Minigames/Bowling/LaneCycle"))
local PartPose =
	Import.shared("Minigames/Bowling/PartPose") :: typeof(require("../../shared/Minigames/Bowling/PartPose"))
local RollScript =
	Import.shared("Minigames/Bowling/RollScript") :: typeof(require("../../shared/Minigames/Bowling/RollScript"))

local BowlingLane = {}
BowlingLane.__index = BowlingLane

BowlingLane.RANGES = BallPath.RANGES
BowlingLane.ROLL_WRITE_HZ = 20 -- server writes of a throw in flight (clients draw every frame themselves)
BowlingLane.SET_TIME = LaneCycle.SET_TIME
BowlingLane.RETURN_TIME = LaneCycle.RETURN_TIME

export type Params = BallPath.Params

type Pin = {
	model: Model,
	parts: { BasePart },
	transparency: { [BasePart]: number },
	home: CFrame,
	hidden: boolean,
	last: { number }, -- the pose last written (x, y, d, tilt)
}

function BowlingLane.new(opts: { [string]: any }): any
	local model: Model = opts.model
	local place = opts.place
	local lane: number = opts.lane
	local self = setmetatable({}, BowlingLane) :: any
	self.lane = lane
	self.model = model
	self.place = place
	self.cycle = LaneCycle.new()
	self.state = "ready"
	self.writeAcc = 0
	self.ball = model:FindFirstChild("Ball") :: BasePart?
	self.sweepPart = model:FindFirstChild("Sweep") :: BasePart?
	self.sweepEdge = model:FindFirstChild("SweepEdge") :: BasePart?
	self.sweepHome = if self.sweepPart then self.sweepPart.CFrame else nil
	self.edgeHome = if self.sweepEdge then self.sweepEdge.CFrame else nil
	self.yawCF = CFrame.Angles(0, AlleyLayout.yawOf(place), 0)
	self.onRack = opts.onRack :: ((mask: { boolean }) -> ())?
	-- the whole lane arrives on a client together (a pin model without its body would pivot about nothing)
	pcall(function()
		model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	end)
	self.pins = {} :: { Pin }
	local pinsFolder = model:FindFirstChild("Pins")
	for n = 1, 10 do
		local pm = pinsFolder and pinsFolder:FindFirstChild(`Pin{n}`) :: Model?
		if pm then
			local parts = {}
			local tr = {}
			for _, d in pm:GetDescendants() do
				if d:IsA("BasePart") then
					table.insert(parts, d)
					tr[d] = d.Transparency
					-- scripted pins: never simulated, never in anything's way
					d.Anchored = true
					d.CanCollide = false
					d.CanTouch = false
				end
			end
			-- a client's playback needs the same resting pose the server uses
			local home = pm:GetPivot()
			pm:SetAttribute(PartPose.HOME, home)
			self.pins[n] = {
				model = pm,
				parts = parts,
				transparency = tr,
				home = home,
				hidden = false,
				last = { math.huge, 0, 0, 0 },
			}
		end
	end
	local ball = self.ball :: BasePart?
	if ball then
		ball.Anchored = true
		ball.CanCollide = false
		ball.CanTouch = false
		self.rackCF = ball.CFrame
		self.ballWhere = "rack"
		ball:SetAttribute(PartPose.RACK, ball.CFrame)
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
	self:_apply()
	return self
end

-- Writing poses ------------------------------------------------------------------------------------------------
local function setVisible(pin: Pin, on: boolean)
	if pin.hidden == not on then
		return
	end
	pin.hidden = not on
	for _, p in pin.parts do
		p.Transparency = if on then pin.transparency[p] else 1
	end
end

function BowlingLane._writePin(self: any, n: number, pose: { [string]: any })
	local pin = self.pins[n] :: Pin?
	if pin == nil then
		return
	end
	setVisible(pin, not pose.hidden)
	local last = pin.last
	if last[1] == pose.x and last[2] == pose.y and last[3] == pose.d and last[4] == pose.tilt then
		return
	end
	last[1], last[2], last[3], last[4] = pose.x, pose.y, pose.d, pose.tilt
	pin.model:PivotTo(PartPose.pin(self.place, pin.home, n, pose.x, pose.y, pose.d, pose.tilt, pose.yaw))
end

function BowlingLane._writeSweep(self: any, y: number, d: number)
	local sweep, edge = self.sweepPart :: BasePart?, self.sweepEdge :: BasePart?
	if sweep == nil or self.sweepHome == nil then
		return
	end
	if self.sweepY == y and self.sweepD == d then
		return
	end
	self.sweepY, self.sweepD = y, d
	local _, hy, hd = AlleyLayout.toLocal(self.place, self.sweepHome.X, self.sweepHome.Y, self.sweepHome.Z)
	local dx, dz = AlleyLayout.dirToWorld(self.place, 0, d - hd)
	local delta = Vector3.new(dx, y - hy, dz)
	sweep.CFrame = self.sweepHome + delta
	if edge and self.edgeHome then
		edge.CFrame = self.edgeHome + delta
	end
end

function BowlingLane._writeBall(self: any, b: { [string]: any })
	local ball = self.ball :: BasePart?
	if ball == nil then
		return
	end
	if b.where == "rack" then
		if self.ballWhere ~= "rack" then
			ball.CFrame = self.rackCF
		end
	elseif b.where == "return" then
		local curve = self.returnCurve
		if curve then
			local p = curve:getPointAt(b.u)
			ball.CFrame = CFrame.new(p.x, p.y, p.z) * self.yawCF * CFrame.Angles(-b.u * 40, 0, 0)
		else
			ball.CFrame = self.rackCF
		end
	else
		ball.CFrame = PartPose.ball(self.place, self.lane, b.x, b.y, b.d, b.turn)
	end
	self.ballWhere = b.where
end

function BowlingLane._apply(self: any)
	local pose = LaneCycle.pose(self.cycle)
	for n = 1, 10 do
		self:_writePin(n, pose.pins[n])
	end
	self:_writeSweep(pose.sweep.y, pose.sweep.d)
	self:_writeBall(pose.ball)
	self.state = self.cycle.phase
end

-- State ----------------------------------------------------------------------------------------------------------
function BowlingLane.ready(self: any): boolean
	return LaneCycle.ready(self.cycle)
end

function BowlingLane.standingMask(self: any): { boolean }
	return LaneCycle.mask(self.cycle)
end

function BowlingLane.standingCount(self: any): number
	return LaneCycle.standingCount(self.cycle)
end

-- The throw being played (nil between throws) and how far into it the lane is.
function BowlingLane.script(self: any): any?
	return self.cycle.script
end

function BowlingLane.scriptTime(self: any): number?
	return LaneCycle.scriptTime(self.cycle)
end

-- The sweep bar while the pinsetter runs: how far down the lane it is and whether it is down at deck level.
function BowlingLane.sweep(self: any): (number?, boolean)
	local c = self.cycle
	if c.phase ~= "setting" then
		return nil, false
	end
	local _, d, low = LaneCycle.sweepAt(c.t - LaneCycle.PAUSE)
	return d, low
end

-- Ball in hand ----------------------------------------------------------------------------------------------------
-- hold(body?): the ball in the bowler's hand (a welded copy everyone sees) or back on the rack.
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
	if body == nil or not self:ready() then
		ball.Transparency = 0
		return
	end
	local hand = body:FindFirstChild("RightHand") or body:FindFirstChild("Right Arm") or body.PrimaryPart
	if hand == nil or not hand:IsA("BasePart") then
		return
	end
	local copy = ball:Clone()
	for _, c in copy:GetChildren() do
		c:Destroy()
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

-- Throws ----------------------------------------------------------------------------------------------------------
function BowlingLane._start(self: any, script: any, seat: number?): (boolean, string?, any?)
	local ok, why = LaneCycle.release(self.cycle, script, seat)
	if not ok then
		return false, why, nil
	end
	self:hold(nil)
	self.writeAcc = 0
	self:_apply()
	return true, nil, script
end

-- release: the throw is decided here and now (clamped, a seeded release error outside the meter's sweet band,
-- the ball's path, the pinfall) and starts playing. Returns the script to send to clients.
function BowlingLane.release(self: any, params: any, seat: number?, seed: number): (boolean, string?, any?)
	if not self:ready() then
		return false, "Wait for the pinsetter and the ball", nil
	end
	if self.ball == nil then
		return false, "This lane has no ball", nil
	end
	return self:_start(RollScript.build(params, LaneCycle.mask(self.cycle), seed), seat)
end

-- debugRoll(n): the first n standing pins tip over where they stand (the engine smoke's scripted pinfall; the
-- rest of the cycle is exactly the same).
function BowlingLane.debugRoll(self: any, n: number, seat: number?): (boolean, string?, any?)
	if not self:ready() then
		return false, "the lane is not ready", nil
	end
	return self:_start(RollScript.fake(LaneCycle.mask(self.cycle), n), seat)
end

function BowlingLane.takeResult(self: any): any?
	return LaneCycle.take(self.cycle)
end

-- setRack: the pinsetter's cycle for the next ball ("full": ten fresh pins; "keep": what stood is set back,
-- deadwood swept) and the ball's run home; at once when instant.
function BowlingLane.setRack(self: any, rack: string, instant: boolean?)
	local wasBusy = not self:ready()
	local ok = LaneCycle.set(self.cycle, rack, instant)
	if not ok then
		instant = true
		LaneCycle.set(self.cycle, rack, true)
	end
	self:_apply()
	if instant then
		self:_cut(wasBusy)
	end
end

-- reset: ten pins, the ball home, nothing pending; a throw in flight is abandoned.
function BowlingLane.reset(self: any, _instant: boolean?)
	local wasBusy = not self:ready()
	LaneCycle.reset(self.cycle)
	self.heldBy = nil
	self:hold(nil)
	self:_apply()
	self:_cut(wasBusy)
end

-- The lane jumped straight to a set rack while something was still playing: clients that are playing the
-- throw back must stop and show the rack (the service tells them through onRack).
function BowlingLane._cut(self: any, wasBusy: boolean)
	local onRack = self.onRack
	if wasBusy and onRack then
		onRack(LaneCycle.mask(self.cycle))
	end
end

-- Per frame ---------------------------------------------------------------------------------------------------
function BowlingLane.step(self: any, dt: number): { string }
	local c = self.cycle
	if c.phase == "ready" then
		return {}
	end
	local events = LaneCycle.step(c, dt)
	self.writeAcc += dt
	local rolling = c.phase == "rolling"
	if #events > 0 or not rolling or self.writeAcc >= 1 / BowlingLane.ROLL_WRITE_HZ then
		self.writeAcc = 0
		self:_apply()
	end
	self.state = c.phase
	return events
end

return BowlingLane
