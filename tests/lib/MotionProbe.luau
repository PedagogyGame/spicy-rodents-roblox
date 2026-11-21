--!strict
-- tests/lib/MotionProbe: how smoothly does a computer-run person move (owner D27: "waddles, jolts left right,
-- rocks, does not walk or run in a straight smooth line")? Walks one person with the real brain helpers and the real
-- motor (Movement/HumanAIMotor) at 60 Hz, the brain thinking at 10 Hz as the scheduler has a near body, and measures
-- the path it was given.
--   lane(speed, dodge?) -> { Sample }     a walk along a straight lane (Brains/Pedestrian), with one post to step
--                                          round when `dodge` (the step aside, studs) is given
--   corner(speed, degrees) -> { Sample }   a walk by the town's way (Brains/Common.toward) round one corner
--   measure(samples, axis?) -> Metrics     the numbers; with `axis` ("x" | "z": the lane's) the sideways ones too
--   stream(samples, hz, jitter, rng) -> { Pose }   the same walk as a client is sent it: one pose every 1 / hz
--                                          seconds, each up to `jitter` seconds late
-- Pure Lune. Studs, seconds, radians.

local Units = require("@shared/Config/Units")
local HumanAIMotor = require("@shared/Movement/HumanAIMotor")
local Common = require("@server/Actors/Brains/Common")
local Pedestrian = require("@server/Actors/Brains/Pedestrian")
local Perception = require("@server/Actors/Perception")

local MotionProbe = {}

export type Sample = { t: number, x: number, z: number, yaw: number }
export type Pose = { t: number, x: number, z: number, yaw: number }
export type Metrics = {
	seconds: number,
	crabPeak: number, -- rad: the most the body faced away from where it was going
	yawRatePeak: number, -- rad/s
	yawSnap: number, -- rad/s: the biggest change of the yaw rate from one frame to the next
	yawReversals: number, -- changes of the turn's direction per second
	speedMean: number, -- studs/s
	speedLow: number, -- studs/s: the slowest frame after the start (a stall at a point of the way)
	stepSnap: number, -- studs/s: the biggest change of velocity from one frame to the next
	sidePeak: number, -- studs/s sideways off the lane's line (with `axis`)
	sideSnap: number, -- studs/s: the biggest change of that from one frame to the next
	sideRms: number, -- studs off the line the walk ends on, RMS
	sideMax: number,
}

MotionProbe.DT = 1 / 60
MotionProbe.THINK = 0.1

local function lcg(seed: number): () -> number
	local s = seed
	return function(): number
		s = (s * 1103515245 + 12345) % 2147483648
		return s / 2147483648
	end
end

local function ctx(): Common.Ctx
	return {
		now = 0,
		rng = lcg(9),
		groundAt = function()
			return 0
		end,
		threats = Perception.newGrid(40) :: any,
		actorsById = {},
		bounds = { minX = -2000, maxX = 2000, minZ = -2000, maxZ = 2000 },
		routes = nil,
		queryBuffer = {},
	}
end

local function run(actor: Common.Actor, c: Common.Ctx, seconds: number, think: () -> ()): { Sample }
	local out: { Sample } = {}
	local dt = MotionProbe.DT
	local due = 0
	for i = 1, math.floor(seconds / dt) do
		c.now = i * dt
		if c.now >= due then
			due += MotionProbe.THINK
			think()
		end
		HumanAIMotor.step(actor :: any, dt, c :: any)
		table.insert(out, { t = c.now, x = actor.x, z = actor.z, yaw = actor.yaw })
	end
	return out
end

-- A walk along the lane z = 0 toward +X at `speed`, from standing; `dodge`: a post 30 studs on, stepped round by
-- that much.
function MotionProbe.lane(speed: number, dodge: number?): { Sample }
	local actor = Common.newActor(1, "human", "townsperson", "Pedestrian", 0, 0, 2.5)
	local lane: Pedestrian.Lane = {
		axis = "x",
		fixed = 0,
		min = -1000,
		max = 1000,
		inward = nil,
		dodges = if dodge then { { 30 + speed * 2, dodge } } else nil,
	}
	local brain: any = Pedestrian.new(actor, {
		lanes = { lane },
		coreLanes = 1,
		speedMin = speed,
		speedMax = speed,
		rng = lcg(3),
	})
	actor.x, actor.z, actor.yaw = 0, 0, math.pi / 2
	brain.goal = 900
	local c = ctx()
	return run(actor, c, (60 + speed * 4) / speed, function()
		brain:think(MotionProbe.THINK, c)
	end)
end

-- A walk by the town's way: 30 studs toward +Z, a corner of `degrees`, 30 studs on, at `speed` (as a person walking
-- back to their lane, over to a gathering or closing in on the rodent is walked).
function MotionProbe.corner(speed: number, degrees: number): { Sample }
	local actor = Common.newActor(1, "human", "townsperson", "Pedestrian", 0, 0, 2.5)
	local a = math.rad(degrees)
	local px, pz = 0, 30
	local qx, qz = px + math.sin(a) * 30, pz + math.cos(a) * 30
	local c = ctx()
	c.way = function(): ({ { number } }?, boolean?)
		return { { px, pz }, { qx, qz } }, false
	end
	c.clear = function(): boolean
		return false
	end
	local leg = Common.newLeg()
	local intent = actor.intent
	return run(actor, c, 62 / speed + 1.5, function()
		local tx, tz = Common.toward(leg, actor, c, qx, qz)
		if tx and tz and Common.dist2d(actor.x, actor.z, qx, qz) > 1 then
			intent.mode = "walk"
			intent.tx, intent.tz = tx, tz
			intent.laneAxis, intent.laneCoord = nil, nil
			intent.speed = speed
			intent.turnRate = 4
			intent.damp = 6.8
		else
			intent.mode = "stand"
			intent.heading = 0
		end
	end)
end

local function delta(a: number, b: number): number
	return (b - a + math.pi) % (2 * math.pi) - math.pi
end

function MotionProbe.measure(samples: { Sample }, axis: string?): Metrics
	local dt = MotionProbe.DT
	local m: Metrics = {
		seconds = #samples * dt,
		crabPeak = 0,
		yawRatePeak = 0,
		yawSnap = 0,
		yawReversals = 0,
		speedMean = 0,
		speedLow = math.huge,
		stepSnap = 0,
		sidePeak = 0,
		sideSnap = 0,
		sideRms = 0,
		sideMax = 0,
	}
	local last = samples[#samples]
	local line = if axis == "x" then last.z elseif axis == "z" then last.x else 0
	local pvx, pvz, pRate, pSide, turn = 0, 0, 0, 0, 0
	local moving, sum, side2 = 0, 0, 0
	for i = 2, #samples do
		local a, b = samples[i - 1], samples[i]
		local vx, vz = (b.x - a.x) / dt, (b.z - a.z) / dt
		local v = math.sqrt(vx * vx + vz * vz)
		local rate = delta(a.yaw, b.yaw) / dt
		m.yawRatePeak = math.max(m.yawRatePeak, math.abs(rate))
		if i > 2 then
			m.yawSnap = math.max(m.yawSnap, math.abs(rate - pRate))
			m.stepSnap = math.max(m.stepSnap, math.sqrt((vx - pvx) ^ 2 + (vz - pvz) ^ 2))
		end
		if math.abs(rate) > 0.02 then
			local s = if rate > 0 then 1 else -1
			if turn ~= 0 and s ~= turn then
				m.yawReversals += 1
			end
			turn = s
		end
		if v > 0.5 then
			m.crabPeak = math.max(m.crabPeak, math.abs(delta(b.yaw, math.atan2(vx, vz))))
		end
		-- (the start and the stop are eased: the stall is read between them)
		if b.t > 1 and i < #samples - 90 then
			moving += 1
			sum += v
			m.speedLow = math.min(m.speedLow, v)
		end
		if axis then
			local side = if axis == "x" then vz else vx
			m.sidePeak = math.max(m.sidePeak, math.abs(side))
			if i > 2 then
				m.sideSnap = math.max(m.sideSnap, math.abs(side - pSide))
			end
			pSide = side
			local off = (if axis == "x" then b.z else b.x) - line
			side2 += off * off
			m.sideMax = math.max(m.sideMax, math.abs(off))
		end
		pvx, pvz, pRate = vx, vz, rate
	end
	m.speedMean = if moving > 0 then sum / moving else 0
	m.yawReversals /= m.seconds
	m.sideRms = math.sqrt(side2 / math.max(1, #samples - 1))
	return m
end

-- The walk as a client is sent it: a pose every 1 / hz seconds, arriving up to `jitter` seconds late (the t of each
-- is when it arrives).
function MotionProbe.stream(samples: { Sample }, hz: number, jitter: number, rng: () -> number): { Pose }
	local out: { Pose } = {}
	local every = 1 / hz
	local due = 0
	for _, s in samples do
		if s.t >= due then
			due += every
			table.insert(out, { t = s.t + rng() * jitter, x = s.x, z = s.z, yaw = s.yaw })
		end
	end
	return out
end

MotionProbe.rng = lcg
MotionProbe.WALK = Units.st(1.2) -- studs/s: a townsperson's stroll (0.8 to 1.6 u/s)
MotionProbe.RUN = Units.st(7.6) -- studs/s: running from the rodent

return MotionProbe
