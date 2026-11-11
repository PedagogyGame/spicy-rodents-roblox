--!strict
-- ReplicatedStorage.Shared.Minigames.Bowling.LaneCycle
-- One bowling lane's cycle as a pure state machine, so the timing and the pinsetter can be tested without the
-- engine (Server/Minigames/BowlingLane only writes the poses this gives onto the parts):
--   ready    the rack is set, the ball is on its rack (or in the bowler's hand)
--   rolling  a throw is playing (RollScript): the ball runs down, the pins fall
--   counted  the throw is over and its result is waiting to be taken (once) and a rack ordered
--   setting  the pinsetter: a beat to look at the leave, the sweep bar comes down and goes through, standing
--            pins are lifted clear and set back ("keep") or a fresh ten are lowered ("full"), deadwood is pushed
--            into the pit; meanwhile the ball runs home through the return duct
-- Poses are in the lane frame: x across from the lane centre (bowler's right +), d down-lane from the foul
-- line, y up from the floor. Pure; Lune-tested (tests/unit/bowling_lanecycle.spec.luau).
-- Interface: new() -> Cycle; ready(c) -> bool; release(c, script, seat?) -> (ok, why?); step(c, dt) -> { event }
--   ("impact" | "counted" | "ready"); take(c) -> Result { pins, seat, standing, flags }? (once); set(c, "full" |
--   "keep", instant?) -> (ok, why?); reset(c); mask(c) -> { boolean }; standingCount(c); scriptTime(c) -> t?;
--   pose(c) -> Pose { ball = { where, x, y, d, turn, u }, pins[n] = { x, y, d, tilt, yaw, hidden }, sweep = { y,
--   d } }; sweepAt(tSet) -> (y, d, low); SETTLE, PAUSE, SET_TIME, RETURN_TIME, TURNAROUND

local AlleyLayout = require("../../Attractions/AlleyLayout")
local PinModel = require("./PinModel")
local RollScript = require("./RollScript")

local LaneCycle = {}

LaneCycle.SETTLE = 0.25 -- after the throw's last movement, before it is counted
LaneCycle.PAUSE = 0.9 -- a look at what is left before the sweep comes down
LaneCycle.SET_TIME = 2.6 -- the pinsetter's own cycle
LaneCycle.RETURN_DELAY = 0.2
LaneCycle.RETURN_TIME = 2.6 -- the ball's run home
LaneCycle.TURNAROUND =
	math.max(LaneCycle.PAUSE + LaneCycle.SET_TIME, LaneCycle.RETURN_DELAY + LaneCycle.RETURN_TIME + 0.2)
LaneCycle.LIFT = 2.4 -- how high the machine lifts a pin
LaneCycle.SWEEP_REST = AlleyLayout.MASK_BOTTOM + 0.4
LaneCycle.SWEEP_LOW = 0.7
LaneCycle.SWEEP_D0 = AlleyLayout.DECK_START - 0.05 -- where the bake parks it: just behind the masking unit's face
LaneCycle.SWEEP_D1 = AlleyLayout.CUSHION_D - 0.5

export type Result = { pins: number, seat: number?, standing: { boolean }, flags: RollScript.Flags }
export type PinPose = { x: number, y: number, d: number, tilt: number, yaw: number, hidden: boolean }
export type Pose = {
	ball: { where: string, x: number, y: number, d: number, turn: number, u: number },
	pins: { PinPose },
	sweep: { y: number, d: number },
}
export type Cycle = {
	phase: "ready" | "rolling" | "counted" | "setting",
	t: number, -- seconds into the throw (rolling, counted) or into the pinsetter cycle (setting)
	script: RollScript.Script?,
	seat: number?,
	rack: { boolean }, -- the pins standing for the next ball
	result: Result?,
	taken: boolean,
	impacted: boolean,
	setRack: string?, -- "full" | "keep" while setting
	left: { boolean }, -- what stood after the last throw (setting)
	final: { PinPose }?, -- where everything lay when the pinsetter started
	hasBall: boolean, -- the last throw had a ball to bring home
}

local function full(): { boolean }
	return table.create(10, true)
end

function LaneCycle.new(): Cycle
	return {
		phase = "ready",
		t = 0,
		script = nil,
		seat = nil,
		rack = full(),
		result = nil,
		taken = false,
		impacted = false,
		setRack = nil,
		left = full(),
		final = nil,
		hasBall = false,
	}
end

function LaneCycle.ready(c: Cycle): boolean
	return c.phase == "ready"
end

function LaneCycle.mask(c: Cycle): { boolean }
	return table.clone(c.rack)
end

function LaneCycle.standingCount(c: Cycle): number
	return PinModel.count(c.rack)
end

-- Seconds into the throw being played (nil when none is).
function LaneCycle.scriptTime(c: Cycle): number?
	if c.script and (c.phase == "rolling" or c.phase == "counted") then
		return c.t
	end
	return nil
end

-- release: a throw starts. The script must have been built for the rack that stands.
function LaneCycle.release(c: Cycle, script: RollScript.Script, seat: number?): (boolean, string?)
	if c.phase ~= "ready" then
		return false, "Wait for the pinsetter and the ball"
	end
	for n = 1, 10 do
		if script.mask[n] ~= c.rack[n] then
			return false, "That throw was for a different rack"
		end
	end
	c.phase = "rolling"
	c.t = 0
	c.script = script
	c.seat = seat
	c.result = nil
	c.taken = false
	c.impacted = false
	return true
end

function LaneCycle.step(c: Cycle, dt: number): { string }
	local events: { string } = {}
	if c.phase == "rolling" then
		local script = c.script :: RollScript.Script
		c.t += dt
		if not c.impacted and c.t >= script.tImpact then
			c.impacted = true
			table.insert(events, "impact")
		end
		if c.t >= script.tEnd + LaneCycle.SETTLE then
			c.phase = "counted"
			c.result = {
				pins = script.down,
				seat = c.seat,
				standing = table.clone(script.standing),
				flags = script.flags,
			}
			table.insert(events, "counted")
		end
	elseif c.phase == "counted" then
		c.t += dt
	elseif c.phase == "setting" then
		c.t += dt
		if c.t >= LaneCycle.TURNAROUND then
			c.phase = "ready"
			c.t = 0
			c.script = nil
			c.final = nil
			c.setRack = nil
			c.seat = nil
			table.insert(events, "ready")
		end
	end
	return events
end

-- take: the throw's result, exactly once.
function LaneCycle.take(c: Cycle): Result?
	if c.phase == "counted" and not c.taken then
		c.taken = true
		local r = c.result
		c.result = nil
		return r
	end
	return nil
end

local function pinAt(c: Cycle, n: number, t: number): PinPose
	local script = c.script
	if script then
		local x, y, d, tilt, yaw, hidden = RollScript.pin(script, n, t)
		return { x = x, y = y, d = d, tilt = tilt, yaw = yaw, hidden = hidden }
	end
	local sx, sd = PinModel.spot(n)
	return { x = sx, y = 0, d = sd, tilt = 0, yaw = 0, hidden = not c.rack[n] }
end

-- set: order the rack for the next ball. "keep" sets back exactly what the last throw left standing; "full" is
-- ten fresh pins. Animated unless instant. Allowed once the throw is counted (or at any time when instant).
function LaneCycle.set(c: Cycle, rack: string, instant: boolean?): (boolean, string?)
	local script = c.script
	local nextRack = if rack == "keep" and script then table.clone(script.standing) else full()
	if rack == "keep" and script == nil then
		nextRack = table.clone(c.rack)
	end
	if instant then
		c.phase = "ready"
		c.t = 0
		c.script = nil
		c.final = nil
		c.setRack = nil
		c.result = nil
		c.seat = nil
		c.rack = nextRack
		return true
	end
	if c.phase ~= "counted" and c.phase ~= "ready" then
		return false, "the lane is busy"
	end
	-- freeze the scene as it lies, then run the pinsetter over it
	local final: { PinPose } = {}
	local left: { boolean } = {}
	for n = 1, 10 do
		final[n] = pinAt(c, n, c.t)
		left[n] = if script then script.standing[n] else c.rack[n]
	end
	c.hasBall = script ~= nil and script.path ~= nil
	c.final = final
	c.left = left
	c.setRack = if rack == "keep" then "keep" else "full"
	c.rack = nextRack
	c.phase = "setting"
	c.t = 0
	c.result = nil
	c.taken = true
	return true
end

-- reset: ten pins, ball home, nothing pending; a throw in flight is abandoned.
function LaneCycle.reset(c: Cycle)
	LaneCycle.set(c, "full", true)
end

local function smooth(a: number): number
	a = math.clamp(a, 0, 1)
	return a * a * (3 - 2 * a)
end

-- The sweep bar tSet seconds into the pinsetter's own cycle (after the pause): its height, how far down the
-- lane it is, and whether it is down at deck level pushing.
function LaneCycle.sweepAt(tSet: number): (number, number, boolean)
	local rest, low = LaneCycle.SWEEP_REST, LaneCycle.SWEEP_LOW
	local d0, d1 = LaneCycle.SWEEP_D0, LaneCycle.SWEEP_D1
	if tSet <= 0 then
		return rest, d0, false
	elseif tSet < 0.5 then
		return rest + (low - rest) * smooth(tSet / 0.5), d0, false
	elseif tSet < 1.3 then
		return low, d0 + (d1 - d0) * smooth((tSet - 0.5) / 0.8), true
	elseif tSet < 1.8 then
		return low, d1 + (d0 - d1) * smooth((tSet - 1.3) / 0.5), false
	elseif tSet < 2.2 then
		return low, d0, false
	end
	return low + (rest - low) * smooth((tSet - 2.2) / (LaneCycle.SET_TIME - 2.2)), d0, false
end

-- pose: where everything is right now.
function LaneCycle.pose(c: Cycle): Pose
	local pins: { PinPose } = {}
	local ball = { where = "rack", x = 0, y = 0, d = 0, turn = 0, u = 0 }
	local sweepY, sweepD = LaneCycle.SWEEP_REST, LaneCycle.SWEEP_D0
	if c.phase == "ready" then
		for n = 1, 10 do
			pins[n] = pinAt(c, n, 0)
		end
	elseif c.phase == "rolling" or c.phase == "counted" then
		local script = c.script :: RollScript.Script
		for n = 1, 10 do
			pins[n] = pinAt(c, n, c.t)
		end
		local x, y, d, turn, where = RollScript.ball(script, c.t)
		if x ~= nil then
			ball.where, ball.x, ball.y, ball.d, ball.turn = where, x, y, d, turn
		end
	else
		local tSet = c.t - LaneCycle.PAUSE
		local low
		sweepY, sweepD, low = LaneCycle.sweepAt(tSet)
		local final = c.final :: { PinPose }
		local keep = c.setRack == "keep"
		for n = 1, 10 do
			local f = final[n]
			local sx, sd = PinModel.spot(n)
			if keep and c.left[n] then
				-- lifted clear while the bar goes under, then set back on its spot
				local up = if tSet < 1.6 then smooth((tSet - 0.3) / 0.6) else 1 - smooth((tSet - 1.6) / 0.6)
				pins[n] = { x = sx, y = LaneCycle.LIFT * up, d = sd, tilt = 0, yaw = 0, hidden = false }
			else
				-- deadwood (and, for a fresh rack, whatever still stood): the bar takes it to the pit
				local p = { x = f.x, y = f.y, d = f.d, tilt = f.tilt, yaw = f.yaw, hidden = f.hidden }
				if tSet >= 1.3 then
					p.hidden = true -- the bar has been through: nothing is left on the deck
				elseif low and sweepD + 0.3 > f.d then
					p.d = sweepD + 0.3
					if p.d > AlleyLayout.DECK_END + 0.2 then
						p.hidden = true
					end
				end
				if c.rack[n] and tSet >= 1.4 then
					-- a fresh pin lowered onto the spot
					local a = smooth((tSet - 1.4) / 0.8)
					p = { x = sx, y = LaneCycle.LIFT * (1 - a), d = sd, tilt = 0, yaw = 0, hidden = false }
				end
				pins[n] = p
			end
		end
		if c.hasBall then
			local a = (c.t - LaneCycle.RETURN_DELAY) / LaneCycle.RETURN_TIME
			if a < 1 then
				a = math.clamp(a, 0, 1)
				ball.where = "return"
				ball.u = 0.5 * (a + smooth(a))
			end
		end
	end
	return { ball = ball, pins = pins, sweep = { y = sweepY, d = sweepD } }
end

return LaneCycle
