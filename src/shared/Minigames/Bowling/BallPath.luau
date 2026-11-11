--!strict
-- ReplicatedStorage.Shared.Minigames.Bowling.BallPath
-- Where a bowling ball goes between the bowler's hand and the pin deck (brief v2 §13a "choose your angle and
-- power, bowl"): a small fixed-step model the SERVER runs once per throw and whose samples every client plays
-- back, so nobody depends on Roblox physics settling. A throw is four numbers: offset (where along the foul
-- line, -1 left edge .. 1 right edge), angle (radians, + to the bowler's right), power (0..1, the meter) and
-- spin (-1 hook left .. 1 hook right). The ball slows a little all the way down; the hook does nothing on the
-- oiled front of the lane and bends the ball on the back end (from 18 studs, more at low speed), which is how a
-- hook ball walks into the pocket at an angle; a ball whose centre passes the edge of the bed is in the gutter
-- for good and scores nothing. The power meter has a sweet band: inside it the ball goes exactly where it was
-- aimed, outside it (too hard, or feeble) a small seeded release error is added.
-- Lane frame: x across from the lane centre (bowler's right +), d down-lane from the foul line, y up.
-- Pure; Lune-tested (tests/unit/bowling_ballpath.spec.luau).
-- Interface: RANGES; clamp(params) -> Params; speedOf(power) -> studs/s; releaseX(offset) -> x;
--   wildness(power) -> 0..1; noise(rng, params) -> Params; trace(params) -> Path { samples = flat { t, x, d,
--   ... }, entry = { t, x, vx, vd }? (at the pin deck; nil when guttered), gutterT?, gutterSide?, gutterD?,
--   tEnd }; at(path, t) -> (x, y, d, rollAngle)

local AlleyLayout = require("../../Attractions/AlleyLayout")

local BallPath = {}

BallPath.RANGES = {
	angle = 0.1, -- radians either side of straight
	speedMin = 16, -- studs/s at zero power
	speedMax = 34,
	sweet = { 0.55, 0.85 }, -- the meter's green band: no release error inside it
}
BallPath.DECEL = 0.7 -- studs/s^2 lost all the way down the lane
BallPath.MIN_SPEED = 6
BallPath.HOOK = 2.5 -- studs/s^2 of sideways pull at full spin on the back end, at the reference speed
BallPath.HOOK_START = 18 -- the oil ends here
BallPath.HOOK_RAMP = 20 -- studs over which the hook comes in
BallPath.HOOK_REF_SPEED = 25
BallPath.HOOK_MAX_TURN = 0.12 -- a hooking ball is never turned further across the lane than this (about 7 degrees)
BallPath.NOISE_ANGLE = 0.012 -- radians of release error at full power (about two thirds of a stud at the pins)
BallPath.NOISE_OFFSET = 0.06
BallPath.STEP = 1 / 120
BallPath.SAMPLE_EVERY = 8 -- one stored sample every 8 steps (1/15 s); playback interpolates
BallPath.GUTTER_X = AlleyLayout.LANE_W / 2 + AlleyLayout.GUTTER_W / 2
BallPath.GUTTER_DROP = 0.26 -- how far the ball sits down in the channel
BallPath.RELEASE_D = AlleyLayout.FOUL_D - 0.6
BallPath.BALL_Y = AlleyLayout.BALL_D / 2 + 0.02
BallPath.PIT_D = AlleyLayout.DECK_END + 0.5 -- a guttered ball drops into the pit here

export type Params = { offset: number, angle: number, power: number, spin: number }
export type Entry = { t: number, x: number, vx: number, vd: number }
export type Path = {
	samples: { number },
	entry: Entry?,
	gutterT: number?,
	gutterSide: number?,
	gutterD: number?,
	tEnd: number,
}

local function finite(v: any, default: number): number
	if type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge then
		return v
	end
	return default
end

local function round3(v: number): number
	return math.floor(v * 1000 + 0.5) / 1000
end

-- times keep five places: at 30 studs a second a millisecond is already a visible 0.03 studs
local function roundT(v: number): number
	return math.floor(v * 100000 + 0.5) / 100000
end

-- Whatever arrives (a client's numbers, a computer player's) becomes a legal throw.
function BallPath.clamp(p: any): Params
	local q = if type(p) == "table" then p else {}
	local R = BallPath.RANGES
	return {
		offset = math.clamp(finite(q.offset, 0), -1, 1),
		angle = math.clamp(finite(q.angle, 0), -R.angle, R.angle),
		power = math.clamp(finite(q.power, 0.6), 0, 1),
		spin = math.clamp(finite(q.spin, 0), -1, 1),
	}
end

function BallPath.speedOf(power: number): number
	local R = BallPath.RANGES
	return R.speedMin + (R.speedMax - R.speedMin) * math.clamp(power, 0, 1)
end

-- The release point across the lane for an offset (the ball's own radius kept on the bed).
function BallPath.releaseX(offset: number): number
	local half = AlleyLayout.LANE_W / 2 - AlleyLayout.BALL_D / 2 - 0.05
	return math.clamp(offset, -1, 1) * half
end

-- How wild a release at this power is: 0 inside the sweet band, 1 at full power, 0.6 at no power at all.
function BallPath.wildness(power: number): number
	local lo, hi = BallPath.RANGES.sweet[1], BallPath.RANGES.sweet[2]
	if power > hi then
		return (power - hi) / (1 - hi)
	elseif power < lo then
		return 0.6 * (lo - power) / lo
	end
	return 0
end

-- The release error. Two numbers are always drawn so a throw uses the same amount of the stream either way.
function BallPath.noise(rng: { next: () -> number }, params: Params): Params
	local p = BallPath.clamp(params)
	local a, b = rng.next() * 2 - 1, rng.next() * 2 - 1
	local w = BallPath.wildness(p.power)
	if w <= 0 then
		return p
	end
	return BallPath.clamp({
		offset = p.offset + b * BallPath.NOISE_OFFSET * w,
		angle = p.angle + a * BallPath.NOISE_ANGLE * w,
		power = p.power,
		spin = p.spin,
	})
end

function BallPath.trace(params: Params): Path
	local p = BallPath.clamp(params)
	local dt = BallPath.STEP
	local halfBed = AlleyLayout.LANE_W / 2
	local deck = AlleyLayout.DECK_START
	local speed = BallPath.speedOf(p.power)
	local x, d = BallPath.releaseX(p.offset), BallPath.RELEASE_D
	local vx, vd = speed * math.sin(p.angle), speed * math.cos(p.angle)
	local t = 0
	local samples: { number } = { 0, round3(x), round3(d) }
	local path: Path = { samples = samples, entry = nil, gutterT = nil, gutterSide = nil, gutterD = nil, tEnd = 0 }
	local side = 0
	local step = 0
	while t < 14 do
		step += 1
		local sp = math.sqrt(vx * vx + vd * vd)
		local ns = math.max(BallPath.MIN_SPEED, sp - BallPath.DECEL * dt)
		vx *= ns / sp
		vd *= ns / sp
		if side == 0 then
			if p.spin ~= 0 and d > BallPath.HOOK_START then
				local ramp = math.clamp((d - BallPath.HOOK_START) / BallPath.HOOK_RAMP, 0, 1)
				local grip = math.clamp(BallPath.HOOK_REF_SPEED / ns, 0.85, 1.15)
				local turned = vx / vd * (if p.spin > 0 then 1 else -1)
				if turned < BallPath.HOOK_MAX_TURN then
					vx += p.spin * BallPath.HOOK * ramp * grip * dt
				end
			end
		else
			-- in the channel: pulled to its middle, rolling on
			vx = (side * BallPath.GUTTER_X - x) * 10
		end
		local px, pd = x, d
		x += vx * dt
		d += vd * dt
		t += dt
		if side == 0 and d >= deck then
			-- onto the pin deck: the pin model takes over from exactly this line
			local f = (deck - pd) / (d - pd)
			local te = roundT(t - dt + f * dt)
			local xe = round3(px + f * (x - px))
			path.entry = { t = te, x = xe, vx = round3(vx), vd = round3(vd) }
			table.insert(samples, te)
			table.insert(samples, xe)
			table.insert(samples, round3(deck))
			path.tEnd = te
			return path
		end
		if side == 0 and math.abs(x) > halfBed then
			side = if x > 0 then 1 else -1
			path.gutterT = roundT(t)
			path.gutterSide = side
			path.gutterD = round3(d)
			vd *= 0.9
		end
		local last = side ~= 0 and d >= BallPath.PIT_D
		if last or step % BallPath.SAMPLE_EVERY == 0 then
			table.insert(samples, roundT(t))
			table.insert(samples, round3(x))
			table.insert(samples, round3(d))
		end
		if last then
			break
		end
	end
	path.tEnd = samples[#samples - 2]
	return path
end

local function smooth(a: number): number
	a = math.clamp(a, 0, 1)
	return a * a * (3 - 2 * a)
end

-- The ball at time t (clamped to the path): x, y (centre), d, and how far it has turned (radians).
function BallPath.at(path: Path, t: number): (number, number, number, number)
	local s = path.samples
	local n = #s // 3
	local x, d
	if t <= s[1] then
		x, d = s[2], s[3]
	elseif t >= s[3 * n - 2] then
		x, d = s[3 * n - 1], s[3 * n]
	else
		-- samples are evenly spaced except the last one: guess the slot, then walk to it
		local span = BallPath.STEP * BallPath.SAMPLE_EVERY
		local i = math.clamp(math.floor(t / span) + 1, 1, n - 1)
		while i > 1 and s[3 * i - 2] > t do
			i -= 1
		end
		while i < n - 1 and s[3 * i + 1] <= t do
			i += 1
		end
		local t0, t1 = s[3 * i - 2], s[3 * i + 1]
		local f = if t1 > t0 then (t - t0) / (t1 - t0) else 0
		x = s[3 * i - 1] + (s[3 * i + 2] - s[3 * i - 1]) * f
		d = s[3 * i] + (s[3 * i + 3] - s[3 * i]) * f
	end
	local y = BallPath.BALL_Y
	local gt = path.gutterT
	if gt and t > gt then
		y -= BallPath.GUTTER_DROP * smooth((t - gt) / 0.12)
	end
	return x, y, d, (d - BallPath.RELEASE_D) / (AlleyLayout.BALL_D / 2)
end

return BallPath
