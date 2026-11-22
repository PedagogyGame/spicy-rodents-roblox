--!strict
-- ReplicatedStorage.Shared.Minigames.Bowling.BallPath
-- Where a bowling ball goes between the bowler's hand and the pin deck (brief v2 §13a "choose your angle and
-- power, bowl"; owner D32 "there's just no way to put any angle or twist"): a small fixed-step model the SERVER
-- runs once per throw and whose samples every client plays back, so nobody depends on Roblox physics settling.
-- A throw is four numbers: offset (where along the foul line, -1 left edge .. 1 right edge), angle (radians, +
-- to the bowler's right: the line through the target arrow), power (0..1, the meter) and spin (-1 hook left ..
-- 1 hook right: how far the ball's spin axis is turned, and which way).
-- THE HOOK IS REAL BOWLING'S: the ball leaves the hand spinning (REVS, the same for every throw) about an axis
-- turned AXIS_MAX x |spin| away from its line, so its spin would roll it somewhere other than where it is going.
-- The lane rubs the difference away (sliding friction at the contact point: the ball's speed changes by one
-- part, its spin's rolling speed by 2.5 parts, the solid-ball ratio), and the friction is the lane's: on the
-- oiled front (to OIL_D) it is slick (GRIP_OIL) and the ball skids almost straight; on the dry back end
-- (GRIP_DRY) it grips, the spin takes over and the ball hooks; once nothing is left to rub away it rolls and
-- goes straight on at the angle the hook gave it. So a hook bends late and comes into the pins at an angle
-- (six to seven degrees at full hook and medium power), more at low speed (longer on the lane), less hard; a
-- straight ball (spin 0) only skids a little and rolls dead straight. Gutters: a ball whose centre passes the
-- edge of the bed is in the channel for good and scores nothing. The power meter's sweet band: inside it the
-- ball goes exactly where it was aimed, outside it (too hard, or feeble) a small seeded release error is added.
-- The spin is part of what is drawn: each sample carries the heading of the spin's rolling direction and how
-- far the ball has turned, so the ball on screen turns about its real (tilted) axis.
-- Lane frame: x across from the lane centre (bowler's right +), d down-lane from the foul line, y up.
-- Pure; Lune-tested (tests/unit/bowling_ballpath.spec.luau).
-- Interface: RANGES; clamp(params) -> Params; speedOf(power) -> studs/s; releaseX(offset) -> x;
--   wildness(power) -> 0..1; noise(rng, params) -> Params; grip(d) -> studs/s^2; trace(params) -> Path {
--   samples = flat { t, x, d, ... }, spin = flat { heading, turn, ... } (one pair per sample), entry = { t, x,
--   vx, vd, rx, rd, turn }? (at the pin deck; nil when guttered; rx, rd the spin's rolling velocity),
--   gutterT?, gutterSide?, gutterD?, rollD? (where it stopped skidding), tEnd }; at(path, t) -> (x, y, d,
--   turn, heading); HOOK_START (where the dry back end begins to bite)

local AlleyLayout = require("../../Attractions/AlleyLayout")

local BallPath = {}

BallPath.RANGES = {
	angle = 0.24, -- radians either side of straight (the far edge from the other side, through the arrows)
	speedMin = 16, -- studs/s at zero power
	speedMax = 34,
	sweet = { 0.55, 0.85 }, -- the meter's green band: no release error inside it
}
BallPath.DECEL = 0.5 -- studs/s^2 a rolling ball loses all the way down the lane
BallPath.MIN_SPEED = 6
BallPath.OIL_D = 36 -- the oil pattern ends here (two thirds of the way to the head pin, as on a house shot)
BallPath.OIL_TAPER = 6 -- the friction rises over this length, centred on OIL_D
BallPath.GRIP_OIL = 0.8 -- studs/s^2 of sliding friction on the oil
BallPath.GRIP_DRY = 11 -- and on the dry back end (and the pin deck: PinModel)
BallPath.REVS = 12 -- studs/s: the ball's spin as a rolling speed (the bowler's "revs")
BallPath.AXIS_MAX = 0.9 -- radians the spin's axis is turned from the line at full hook
BallPath.HOOK_START = BallPath.OIL_D - BallPath.OIL_TAPER / 2 -- where the back end starts to bite
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
export type Entry = { t: number, x: number, vx: number, vd: number, rx: number, rd: number, turn: number }
export type Path = {
	samples: { number },
	spin: { number },
	entry: Entry?,
	gutterT: number?,
	gutterSide: number?,
	gutterD: number?,
	rollD: number?,
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

local function smooth(a: number): number
	a = math.clamp(a, 0, 1)
	return a * a * (3 - 2 * a)
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

-- The lane's sliding friction (studs/s^2) at d: the oil, then the dry back end.
function BallPath.grip(d: number): number
	local f = smooth((d - (BallPath.OIL_D - BallPath.OIL_TAPER / 2)) / BallPath.OIL_TAPER)
	return BallPath.GRIP_OIL + (BallPath.GRIP_DRY - BallPath.GRIP_OIL) * f
end

-- One step of a ball on a surface with sliding friction `grip`: the slip (its velocity less the rolling velocity
-- its spin gives it) is rubbed away along its own direction; the velocity takes one part of the change, the
-- spin 2.5 (a solid ball). Returns the new (vx, vd, rx, rd). Shared with the pin deck (PinModel).
function BallPath.rub(vx: number, vd: number, rx: number, rd: number, grip: number, dt: number)
	local ux, ud = vx - rx, vd - rd
	local us = math.sqrt(ux * ux + ud * ud)
	if us <= 1e-9 then
		return vx, vd, rx, rd
	end
	local dv = math.min(grip * dt, us / 3.5) -- never past rolling
	local nx, nd = ux / us, ud / us
	return vx - nx * dv, vd - nd * dv, rx + 2.5 * nx * dv, rd + 2.5 * nd * dv
end

function BallPath.trace(params: Params): Path
	local p = BallPath.clamp(params)
	local dt = BallPath.STEP
	local halfBed = AlleyLayout.LANE_W / 2
	local deck = AlleyLayout.DECK_START
	local radius = AlleyLayout.BALL_D / 2
	local speed = BallPath.speedOf(p.power)
	local x, d = BallPath.releaseX(p.offset), BallPath.RELEASE_D
	local vx, vd = speed * math.sin(p.angle), speed * math.cos(p.angle)
	-- the spin: REVS of rolling speed, its direction turned toward the hook's side
	local axis = p.angle + p.spin * BallPath.AXIS_MAX
	local rx, rd = BallPath.REVS * math.sin(axis), BallPath.REVS * math.cos(axis)
	local turn = 0
	local t = 0
	local samples: { number } = { 0, round3(x), round3(d) }
	local spin: { number } = { round3(axis), 0 }
	local path: Path = {
		samples = samples,
		spin = spin,
		entry = nil,
		gutterT = nil,
		gutterSide = nil,
		gutterD = nil,
		rollD = nil,
		tEnd = 0,
	}
	local function sample(ts: number, xs: number, ds: number)
		table.insert(samples, ts)
		table.insert(samples, xs)
		table.insert(samples, ds)
		table.insert(spin, round3(math.atan2(rx, rd)))
		table.insert(spin, round3(turn))
	end
	local side = 0
	local step = 0
	while t < 14 do
		step += 1
		-- rolling resistance, on the ball and its spin alike
		local sp = math.sqrt(vx * vx + vd * vd)
		local ns = math.max(BallPath.MIN_SPEED, sp - BallPath.DECEL * dt)
		vx *= ns / sp
		vd *= ns / sp
		rx *= ns / sp
		rd *= ns / sp
		if side == 0 then
			vx, vd, rx, rd = BallPath.rub(vx, vd, rx, rd, BallPath.grip(d), dt)
			if path.rollD == nil and math.abs(vx - rx) + math.abs(vd - rd) < 1e-6 then
				path.rollD = round3(d)
			end
		else
			-- in the channel: pulled to its middle, rolling on
			vx = (side * BallPath.GUTTER_X - x) * 10
			rx, rd = vx, vd
		end
		local px, pd = x, d
		x += vx * dt
		d += vd * dt
		t += dt
		turn += math.sqrt(rx * rx + rd * rd) * dt / radius
		if side == 0 and d >= deck then
			-- onto the pin deck: the pin model takes over from exactly this line
			local f = (deck - pd) / (d - pd)
			local te = roundT(t - dt + f * dt)
			local xe = round3(px + f * (x - px))
			path.entry = {
				t = te,
				x = xe,
				vx = round3(vx),
				vd = round3(vd),
				rx = round3(rx),
				rd = round3(rd),
				turn = round3(turn),
			}
			sample(te, xe, round3(deck))
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
			sample(roundT(t), round3(x), round3(d))
		end
		if last then
			break
		end
	end
	path.tEnd = samples[#samples - 2]
	return path
end

-- The ball at time t (clamped to the path): x, y (centre), d, how far it has turned (radians) and the heading
-- its spin rolls it (radians from down-lane toward the bowler's right; it turns about the level axis square to
-- that).
function BallPath.at(path: Path, t: number): (number, number, number, number, number)
	local s = path.samples
	local w = path.spin
	local n = #s // 3
	local x, d, turn, heading
	if t <= s[1] then
		x, d, heading, turn = s[2], s[3], w[1], w[2]
	elseif t >= s[3 * n - 2] then
		x, d, heading, turn = s[3 * n - 1], s[3 * n], w[2 * n - 1], w[2 * n]
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
		heading = w[2 * i - 1] + (w[2 * i + 1] - w[2 * i - 1]) * f
		turn = w[2 * i] + (w[2 * i + 2] - w[2 * i]) * f
	end
	local y = BallPath.BALL_Y
	local gt = path.gutterT
	if gt and t > gt then
		y -= BallPath.GUTTER_DROP * smooth((t - gt) / 0.12)
	end
	return x, y, d, turn, heading
end

return BallPath
