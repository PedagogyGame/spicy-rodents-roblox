--!strict
-- ReplicatedStorage.Shared.Minigames.AirHockey.Sim
-- The owner's air hockey simulation, AER / 01 (docs/reference/air_hockey/: HockeyPhysics.h is the whole game,
-- physics.js is the same in JavaScript), ported line for line. Engine-independent, deterministic, two
-- dimensions, SI units (metres, seconds), 240 fixed steps a second: swept-circle contacts against the two moving
-- mallets and the four rounded goal posts, analytic rails, restitution, a speed limit, light air drag, a goal
-- when the whole puck has crossed deep inside the slot, a serve after each goal toward the side that scored from
-- the side that conceded, first to seven, mallets kept to their own halves, and the computer opponent with its
-- difficulty number.
-- NOTHING HERE IS TUNED OR IMPROVED: the numbers, the order the contacts are looked at and the order of every
-- sum are his. The port is proven against his physics.js tick for tick (tools/games/air_hockey/golden.js writes
-- tests/golden/air_hockey.json; tests/unit/air_hockey_golden.spec.luau replays it to 1e-9, and in practice to
-- the last bit), and his C++ checks are tests/unit/air_hockey_sim.spec.luau. Where the two sources differ in the
-- last bit the JavaScript is followed, because it is the one that can be run here: the literal sums (.588 for
-- HalfWidth - PuckRadius and so on), a mallet's velocity as delta * (1 / dt), a unit normal as q * (1 / l), and
-- lengths by V8's Math.hypot (scaled by the larger component), not sqrt(dot).
-- Sides: 0 is Glacier (y < 0), 1 is Ember (y > 0). x runs across the table, y along it.
-- Two things are added that the simulation never reads (they are for sound and drawing): hitWhat / hitSpeed say
-- what the last contact was and how hard; and the drag of one whole step is a constant (DECAY) instead of a call
-- to exp on every machine, so that a client and the server never differ by a rounding of exp.
-- The state is one flat record of numbers (no vectors, nothing allocated in tick): it is stepped several hundred
-- times a frame when a client replays.
-- Pure. Interface: constants; new() -> State; reset(s); resetPuck(s); serve(s); setTarget(s, side, x, y);
--   ai(s, side); tick(s, dt?, human?, computer?); copy(dst, src) -> dst; clone(s) -> State; hypot(x, y);
--   fold(x, bound); FIELDS (every field, in a fixed order)

local Sim = {}

Sim.STEP = 1 / 240
Sim.HALF_WIDTH = 0.62
Sim.HALF_LENGTH = 1.17
Sim.GOAL = 0.22 -- half the goal's width
Sim.PUCK_RADIUS = 0.032
Sim.PADDLE_RADIUS = 0.064
Sim.POST_RADIUS = 0.012
Sim.GOAL_DEPTH = 1.245 -- a goal counts when the puck's far edge is this deep (its centre at 1.277)
Sim.WIN = 7
Sim.COUNTDOWN = 1.25
Sim.DRAG = 0.08
Sim.RESTITUTION = 0.95
Sim.PADDLE_RESTITUTION = 0.94
Sim.MAX_SPEED = 7.5
Sim.HUMAN_SPEED = 3.5 -- a person's mallet follows its target at this many metres a second
Sim.COMPUTER_SPEED = 2.1 -- times the difficulty
Sim.DIFFICULTY = { easy = 0.62, medium = 1, hard = 1.38 }
-- exp(-DRAG * STEP): what one step of drag multiplies the puck's velocity by (the spec checks it is exp's value)
Sim.DECAY = 0.99966672221604991

-- what the last contact was (hitWhat)
Sim.HIT_RAIL = 0
Sim.HIT_POST = 1
Sim.HIT_MALLET = 2 -- + the side: 2 Glacier's mallet, 3 Ember's

-- his literals (physics.js), kept as literals: X_RAIL = HalfWidth - PuckRadius and so on
local X_RAIL = 0.588
local X_CHANNEL = 0.188 -- Goal - PuckRadius: the side walls of the goal slot
local Y_RAIL = 1.138
local Y_GOAL = 1.277
local HALF_LENGTH = 1.17
local GOAL = 0.22
local POST_REACH = 0.044 -- PuckRadius + PostRadius
local PADDLE_REACH = 0.096 -- PuckRadius + PaddleRadius
local TARGET_X = 0.556 -- HalfWidth - PaddleRadius
local TARGET_NEAR = 0.064
local TARGET_FAR = 1.106

export type State = {
	px: number, -- the puck
	py: number,
	vx: number,
	vy: number,
	p0x: number, -- Glacier's mallet: where it is, where it is going, its velocity this step
	p0y: number,
	t0x: number,
	t0y: number,
	v0x: number,
	v0y: number,
	p1x: number, -- Ember's
	p1y: number,
	t1x: number,
	t1y: number,
	v1x: number,
	v1y: number,
	score0: number,
	score1: number,
	countdown: number,
	drag: number,
	restitution: number,
	maxSpeed: number,
	difficulty: number,
	winner: number, -- -1, or the side
	serveSide: number, -- whose half the puck is served from (the side that conceded)
	lastGoal: number, -- -1, or the side that scored last
	hitSerial: number,
	goalSerial: number,
	paused: boolean,
	hitWhat: number, -- (not read by the simulation) the last contact: HIT_RAIL, HIT_POST, HIT_MALLET + side
	hitSpeed: number, -- (not read by the simulation) how fast the puck met it along the normal, m/s
}

Sim.FIELDS = {
	"px",
	"py",
	"vx",
	"vy",
	"p0x",
	"p0y",
	"t0x",
	"t0y",
	"v0x",
	"v0y",
	"p1x",
	"p1y",
	"t1x",
	"t1y",
	"v1x",
	"v1y",
	"score0",
	"score1",
	"countdown",
	"drag",
	"restitution",
	"maxSpeed",
	"difficulty",
	"winner",
	"serveSide",
	"lastGoal",
	"hitSerial",
	"goalSerial",
	"paused",
	"hitWhat",
	"hitSpeed",
}

local sqrt = math.sqrt
local abs = math.abs
local fmod = math.fmod

-- V8's Math.hypot for two numbers: the components are scaled by the larger before they are squared. (The same
-- value as sqrt(x * x + y * y) to within a rounding; the JavaScript game rounds this way.)
local function hypot(x: number, y: number): number
	local ax, ay = abs(x), abs(y)
	local m = if ax > ay then ax else ay
	if m == 0 then
		return 0
	end
	local nx, ny = ax / m, ay / m
	-- (Kahan summation of the two squares, as V8 does it)
	local sum = nx * nx
	local summand = ny * ny
	local preliminary = sum + summand
	return sqrt(preliminary) * m
end
Sim.hypot = hypot

-- A coordinate reflected back and forth between -bound and bound (where a rail shot will be). JavaScript's %
-- keeps the sign of the dividend, which is fmod.
local function fold(x: number, bound: number): number
	local span = 4 * bound
	local v = fmod(fmod(x + bound, span) + span, span)
	return if v <= 2 * bound then v - bound else 3 * bound - v
end
Sim.fold = fold

local function clamp(v: number, a: number, b: number): number
	-- Math.max(a, Math.min(b, v))
	local m = if v < b then v else b
	return if m > a then m else a
end

function Sim.resetPuck(s: State)
	s.px, s.py = 0, if s.serveSide ~= 0 then 0.3 else -0.3
	s.vx, s.vy = 0, 0
	s.countdown = 1.25
end

function Sim.reset(s: State)
	s.score0, s.score1 = 0, 0
	s.winner = -1
	s.paused = false
	s.serveSide = 0
	s.lastGoal = -1
	s.p0x, s.p0y, s.t0x, s.t0y, s.v0x, s.v0y = 0, -0.8, 0, -0.8, 0, 0
	s.p1x, s.p1y, s.t1x, s.t1y, s.v1x, s.v1y = 0, 0.8, 0, 0.8, 0, 0
	Sim.resetPuck(s)
end

function Sim.new(): State
	local s: State = {
		px = 0,
		py = 0,
		vx = 0,
		vy = 0,
		p0x = 0,
		p0y = 0,
		t0x = 0,
		t0y = 0,
		v0x = 0,
		v0y = 0,
		p1x = 0,
		p1y = 0,
		t1x = 0,
		t1y = 0,
		v1x = 0,
		v1y = 0,
		score0 = 0,
		score1 = 0,
		countdown = 1.25,
		drag = 0.08,
		restitution = 0.95,
		maxSpeed = 7.5,
		difficulty = 1,
		winner = -1,
		serveSide = 0,
		lastGoal = -1,
		hitSerial = 0,
		goalSerial = 0,
		paused = false,
		hitWhat = -1,
		hitSpeed = 0,
	}
	Sim.reset(s)
	return s
end

function Sim.copy(dst: State, src: State): State
	local d, f = dst :: any, src :: any
	for _, k in Sim.FIELDS do
		d[k] = f[k]
	end
	return dst
end

function Sim.clone(s: State): State
	return table.clone(s)
end

-- The puck is let go: toward the side that scored, from the side that conceded.
function Sim.serve(s: State)
	if s.winner < 0 then
		s.countdown = 0
		s.vx = if s.goalSerial % 2 ~= 0 then -0.34 else 0.34
		s.vy = if s.serveSide ~= 0 then -1.25 else 1.25
	end
end

-- Where a mallet is asked to go: kept on the table and in its own half.
function Sim.setTarget(s: State, side: number, x: number, y: number)
	local tx = clamp(x, -TARGET_X, TARGET_X)
	if side ~= 0 then
		s.t1x, s.t1y = tx, clamp(y, TARGET_NEAR, TARGET_FAR)
	else
		s.t0x, s.t0y = tx, clamp(y, -TARGET_FAR, -TARGET_NEAR)
	end
end

-- The computer opponent: shadow the puck, meet a shot where it will arrive, get behind a puck in its half and
-- commit through it toward the other goal.
function Sim.ai(s: State, side: number)
	local sg = if side ~= 0 then 1 else -1
	local mx, my
	if side ~= 0 then
		mx, my = s.p1x, s.p1y
	else
		mx, my = s.p0x, s.p0y
	end
	local px, py, vx, vy = s.px, s.py, s.vx, s.vy
	local tx, ty = px * 0.65, sg * 0.85
	if vy * sg > 0.05 then
		local t = clamp((sg * 0.88 - py) / vy, 0, 1.4)
		tx, ty = fold(px + vx * t, 0.588), sg * 0.88
	end
	if py * sg > 0.08 and py * sg < 1.07 then
		-- Get behind the puck, then commit through it toward the opposing goal.
		tx, ty = px, py + sg * 0.115
		if abs(mx - px) < 0.065 and (my - py) * sg > 0.025 then
			tx, ty = px * 0.78, py - sg * 0.26
		end
	end
	if s.countdown > 0 then
		tx, ty = 0, sg * 0.8
	end
	Sim.setTarget(s, side, tx, ty)
end

-- When a point at q moving by `relative` a second first comes within r of the origin, within `horizon` seconds
-- (nil: it does not). Already inside counts at once if it is still closing.
local function circleTOI(qx: number, qy: number, rx: number, ry: number, r: number, horizon: number): number?
	local a = rx * rx + ry * ry
	local b = qx * rx + qy * ry
	local c = (qx * qx + qy * qy) - r * r
	if c <= 1e-10 then
		return if b < -1e-9 then 0 else nil
	end
	if a < 1e-12 or b >= 0 then
		return nil
	end
	local d = b * b - a * c
	if d < 0 then
		return nil
	end
	local t = (-b - sqrt(d)) / a
	return if t >= -1e-9 and t <= horizon then t else nil
end

-- One step. human: the side a person plays (its mallet follows its target at HUMAN_SPEED); computer: the other
-- side is the computer's (it picks its own target here and moves at COMPUTER_SPEED * difficulty). With
-- computer = false both mallets are people's.
function Sim.tick(s: State, dtIn: number?, humanIn: number?, computerIn: boolean?)
	local dt: number = dtIn or Sim.STEP
	local human: number = humanIn or 0
	local computer = computerIn ~= false
	if s.paused or s.winner >= 0 then
		return
	end
	if computer then
		Sim.ai(s, 1 - human)
	end
	local s0x, s0y, s1x, s1y = s.p0x, s.p0y, s.p1x, s.p1y
	local inv = 1 / dt
	-- each mallet's velocity for this step: toward its target, no faster than its speed
	do
		local limit = (if human == 0 or not computer then 3.5 else 2.1 * s.difficulty) * dt
		local dx, dy = s.t0x - s0x, s.t0y - s0y
		local n = hypot(dx, dy)
		if n > limit then
			local k = limit / n
			dx, dy = dx * k, dy * k
		end
		s.v0x, s.v0y = dx * inv, dy * inv
	end
	do
		local limit = (if human == 1 or not computer then 3.5 else 2.1 * s.difficulty) * dt
		local dx, dy = s.t1x - s1x, s.t1y - s1y
		local n = hypot(dx, dy)
		if n > limit then
			local k = limit / n
			dx, dy = dx * k, dy * k
		end
		s.v1x, s.v1y = dx * inv, dy * inv
	end
	local v0x, v0y, v1x, v1y = s.v0x, s.v0y, s.v1x, s.v1y
	if s.countdown > 0 then
		s.p0x, s.p0y = s0x + v0x * dt, s0y + v0y * dt
		s.p1x, s.p1y = s1x + v1x * dt, s1y + v1y * dt
		s.countdown -= dt
		if s.countdown <= 0 then
			Sim.serve(s)
		end
		return
	end
	local decay = if dt == Sim.STEP and s.drag == 0.08 then Sim.DECAY else math.exp(-s.drag * dt)
	local px, py = s.px, s.py
	local vx, vy = s.vx * decay, s.vy * decay
	local left, elapsed = dt, 0
	local iteration = 0
	while iteration < 16 and left > 1e-9 do
		iteration += 1
		-- the earliest contact in what is left of the step: hit time, normal, the surface's velocity, its kind
		-- (0 a rail or a post, 1 a mallet, 3 / 4 a goal for Glacier / Ember) and what it was (for sound)
		local ht, hnx, hny, hsx, hsy, hk, hw = left + 1, 0, 0, 0, 0, -1, -1
		for sg = -1, 1, 2 do
			if vx * sg > 1e-9 then
				-- a side rail
				local t = (sg * X_RAIL - px) / vx
				if t >= -1e-9 and t <= left and t < ht then
					ht, hnx, hny, hsx, hsy, hk, hw = if t > 0 then t else 0, -sg, 0, 0, 0, 0, 0
				end
				-- a side wall of the goal slot, once the puck is past the end rail
				t = (sg * X_CHANNEL - px) / vx
				if abs(py + vy * t) >= HALF_LENGTH then
					if t >= -1e-9 and t <= left and t < ht then
						ht, hnx, hny, hsx, hsy, hk, hw = if t > 0 then t else 0, -sg, 0, 0, 0, 0, 0
					end
				end
			end
			if vy * sg > 1e-9 then
				-- an end rail, beside the goal
				local t = (sg * Y_RAIL - py) / vy
				local x = px + vx * t
				if abs(x) >= GOAL then
					if t >= -1e-9 and t <= left and t < ht then
						ht, hnx, hny, hsx, hsy, hk, hw = if t > 0 then t else 0, 0, -sg, 0, 0, 0, 0
					end
				end
				-- A full-puck crossing deep inside the goal awards exactly one point.
				t = (sg * Y_GOAL - py) / vy
				if t >= -1e-9 and t <= left and t < ht then
					ht, hnx, hny, hsx, hsy, hk, hw = if t > 0 then t else 0, 0, 0, 0, 0, if sg > 0 then 3 else 4, -1
				end
			end
		end
		-- the four rounded goal posts
		for sx = -1, 1, 2 do
			for sy = -1, 1, 2 do
				local cx, cy = sx * GOAL, sy * HALF_LENGTH
				local t = circleTOI(px - cx, py - cy, vx, vy, POST_REACH, left)
				if t ~= nil and t < ht then
					local qx, qy = (px + vx * t) - cx, (py + vy * t) - cy
					local l = hypot(qx, qy)
					if l > 1e-9 then
						local k = 1 / l
						hnx, hny = qx * k, qy * k
					else
						hnx, hny = 0, 1
					end
					ht, hsx, hsy, hk, hw = if t > 0 then t else 0, 0, 0, 0, 1
				end
			end
		end
		-- the two mallets, where they are `elapsed` into the step
		do
			local cx, cy = s0x + v0x * elapsed, s0y + v0y * elapsed
			local t = circleTOI(px - cx, py - cy, vx - v0x, vy - v0y, PADDLE_REACH, left)
			if t ~= nil and t < ht then
				local qx, qy = (px + vx * t) - (cx + v0x * t), (py + vy * t) - (cy + v0y * t)
				local l = hypot(qx, qy)
				if l > 1e-9 then
					local k = 1 / l
					hnx, hny = qx * k, qy * k
				else
					hnx, hny = 0, 1
				end
				ht, hsx, hsy, hk, hw = if t > 0 then t else 0, v0x, v0y, 1, 2
			end
			cx, cy = s1x + v1x * elapsed, s1y + v1y * elapsed
			t = circleTOI(px - cx, py - cy, vx - v1x, vy - v1y, PADDLE_REACH, left)
			if t ~= nil and t < ht then
				local qx, qy = (px + vx * t) - (cx + v1x * t), (py + vy * t) - (cy + v1y * t)
				local l = hypot(qx, qy)
				if l > 1e-9 then
					local k = 1 / l
					hnx, hny = qx * k, qy * k
				else
					hnx, hny = 0, 1
				end
				ht, hsx, hsy, hk, hw = if t > 0 then t else 0, v1x, v1y, 1, 3
			end
		end
		if hk < 0 then
			px, py = px + vx * left, py + vy * left
			left = 0
			break
		end
		px, py = px + vx * ht, py + vy * ht
		elapsed += ht
		left -= ht
		if hk == 3 or hk == 4 then
			local scorer = if hk == 3 then 0 else 1
			local score
			if scorer == 0 then
				s.score0 += 1
				score = s.score0
			else
				s.score1 += 1
				score = s.score1
			end
			s.lastGoal = scorer
			s.goalSerial += 1
			s.serveSide = 1 - scorer
			if score >= 7 then
				s.winner = scorer
				vx, vy = 0, 0
			else
				-- (ResetPuck)
				px, py = 0, if s.serveSide ~= 0 then 0.3 else -0.3
				vx, vy = 0, 0
				s.countdown = 1.25
			end
			break
		end
		local vn = (vx - hsx) * hnx + (vy - hsy) * hny
		if vn < 0 then
			local k = -(1 + (if hk == 1 then 0.94 else s.restitution)) * vn
			vx, vy = vx + hnx * k, vy + hny * k
			s.hitSerial += 1
			s.hitWhat, s.hitSpeed = hw, -vn
		end
		do
			local n = hypot(vx, vy)
			if n > s.maxSpeed then
				local k = s.maxSpeed / n
				vx, vy = vx * k, vy * k
			end
		end
		px, py = px + hnx * 1e-6, py + hny * 1e-6
		-- Progress even when two contacts share exactly the same instant.
		if ht < 1e-8 then
			local e = if left < 1e-7 then left else 1e-7
			px, py = px + vx * e, py + vy * e
			left -= e
			elapsed += e
		end
	end
	s.px, s.py, s.vx, s.vy = px, py, vx, vy
	s.p0x, s.p0y = s0x + v0x * dt, s0y + v0y * dt
	s.p1x, s.p1y = s1x + v1x * dt, s1y + v1y * dt
end

return Sim
